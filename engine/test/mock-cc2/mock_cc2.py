#!/usr/bin/env python3
"""mock_cc2 – nachahmer des Elegoo Centauri Carbon 2 fuer M3-Tests.

Nachbau der realen Austausch-Muster aus docs/networking-cc2.md:
  * UDP 52700  – Discovery {"id":0,"method":7000}
  * MQTT 1883  – Register, api_status, PING/PONG, api_request/response
                  (ueber Subprocess `mosquitto`, mit password-file)
  * HTTP 8080  – chunked PUT /upload (Port 80 ist privileged; Mock laeuft
                 auf 8080; die App-Tests setzen den Port entsprechend)

Zugangscode:
  * Kommandozeile `--access-code <wert>` ODER
  * Umgebungsvariable MOCK_ACCESS_CODE
  * Wird in das Mosquitto-Password-File geschrieben; die Dart-App gibt
    denselben Code als MQTT-Passwort an.

Fehlerinjektion fuer M3-Tests:
  * `--reject-auth`              Mosquitto startet ohne User → jeder
                                 CONNECT-Versuch bekommt CONNACK rc=5.
  * `--interrupt-upload-at N`    HTTP-Server schliesst die TCP-Verbindung,
                                 nachdem N Byte empfangen wurden
                                 (Simuliert Netz-Abbruch).

Antwort-Daten entsprechen den tatsaechlich am echten CC2 beobachteten
Payload-Structuren (siehe docs/networking-cc2.md Abschnitte
"Nachweislauf 2026-10-25 09:00: method 1002 Vollstatus" etc.) – aber
mit Platzhalter-Seriennummer, nicht mit Klaus' SN.
"""
from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
import secrets
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Optional

import paho.mqtt.client as mqtt

# Platzhalter-SN – NICHT die echte <cc2-sn> vom CC2 im Haus.
MOCK_SN = "MOCK0000000000M1"

# Fuer Realitaetstreue: dieselbe CANVAS-Belegung A1-A4 wie am echten
# Geraet (PETG/PETG/PLA/PLA).
CANVAS_FIXTURE = {
    "canvas_info": {
        "active_canvas_id": 0,
        "active_tray_id": -1,
        "auto_refill": False,
        "canvas_list": [{
            "canvas_id": 0,
            "connected": 1,
            "tray_list": [
                {"tray_id": 0, "brand": "ELEGOO", "filament_type": "PETG",
                 "filament_name": "PETG",      "filament_color": "#000000",
                 "filament_code": "0x0100",
                 "min_nozzle_temp": 230, "max_nozzle_temp": 260, "status": 1},
                {"tray_id": 1, "brand": "ELEGOO", "filament_type": "PETG",
                 "filament_name": "RAPID PETG","filament_color": "#FFFFFF",
                 "filament_code": "0x0105",
                 "min_nozzle_temp": 230, "max_nozzle_temp": 260, "status": 1},
                {"tray_id": 2, "brand": "ELEGOO", "filament_type": "PLA",
                 "filament_name": "PLA PRO",   "filament_color": "#000000",
                 "filament_code": "0x0002",
                 "min_nozzle_temp": 190, "max_nozzle_temp": 230, "status": 1},
                {"tray_id": 3, "brand": "ELEGOO", "filament_type": "PLA",
                 "filament_name": "RAPID PLA+","filament_color": "#FFFFFF",
                 "filament_code": "0x000A",
                 "min_nozzle_temp": 190, "max_nozzle_temp": 230, "status": 1},
            ],
        }],
    },
    "error_code": 0,
}

STATUS_FIXTURE_IDLE = {
    "error_code": 0,
    "machine_status": {"status": 1, "sub_status": 0, "progress": 0,
                       "exception_status": [], "sub_status_reason_code": 0},
    "heater_bed": {"target": 0, "temperature": 24},
    "extruder": {"target": 0, "temperature": 28,
                 "filament_detected": 0, "filament_detect_enable": 1},
    "print_status": {"enable": False, "state": "", "filename": "",
                     "current_layer": 0, "total_layer": 0, "progress": 0,
                     "print_duration": 0, "remaining_time_sec": 0,
                     "total_duration": 0, "bed_mesh_detect": False,
                     "filament_detect": False, "uuid": ""},
    "tool_head": {"homed_axes": "xyz"},
    "external_device": {"camera": True, "u_disk": False, "type": "0303"},
    "fans": {k: {"speed": 0.0} for k in
             ("aux_fan", "box_fan", "controller_fan", "fan", "heater_fan")},
    "gcode_move": {"x": 52.5, "y": 264.0, "z": 4.97, "speed": 1500,
                   "speed_mode": 1, "extruder": 0.0},
    "ztemperature_sensor": {"temperature": 25,
                            "measured_min_temperature": 0,
                            "measured_max_temperature": 0},
    "led": {"status": 1},
}


class MockCC2:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.access_code: Optional[str] = (
            None if args.reject_auth
            else (args.access_code or os.environ.get('MOCK_ACCESS_CODE')
                  or secrets.token_hex(3))
        )
        self.sn = args.sn
        # Upload-Zustand – pro Datei kumulierter Offset
        self.uploads: dict[str, bytearray] = {}
        self.mqtt_proc: Optional[subprocess.Popen] = None
        self.mqtt_cfg_dir: Optional[Path] = None
        self.mqtt_client: Optional[mqtt.Client] = None
        self.loop: Optional[asyncio.AbstractEventLoop] = None

    # ---------- MQTT (via Mosquitto als Subprocess) ----------

    def _start_mosquitto(self) -> None:
        cfg_dir = Path(tempfile.mkdtemp(prefix='mock-cc2-mqtt-'))
        self.mqtt_cfg_dir = cfg_dir
        pwfile = cfg_dir / 'passwd'
        cfgfile = cfg_dir / 'mosquitto.conf'

        if self.access_code is None:
            # --reject-auth: leeres Password-File → kein User akzeptiert
            pwfile.write_text('')
        else:
            # mosquitto_passwd -b erzeugt crypt-Hash; sauberer als
            # 'allow_anonymous true' + Code-Pruefung im Script
            pwfile.write_text(f'elegoo:{self.access_code}\n')
            subprocess.run(['mosquitto_passwd', '-U', str(pwfile)],
                           check=True)

        cfgfile.write_text(f'''
listener {self.args.mqtt_port} {self.args.bind}
allow_anonymous false
password_file {pwfile}
persistence false
log_type error
log_type warning
''')
        self.mqtt_proc = subprocess.Popen(
            ['mosquitto', '-c', str(cfgfile)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        time.sleep(0.5)  # broker startup

    def _stop_mosquitto(self) -> None:
        if self.mqtt_proc:
            self.mqtt_proc.terminate()
            try:
                self.mqtt_proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.mqtt_proc.kill()
        if self.mqtt_cfg_dir:
            for p in self.mqtt_cfg_dir.iterdir():
                p.unlink()
            self.mqtt_cfg_dir.rmdir()

    def _start_mqtt_adapter(self) -> None:
        """Interne MQTT-Logik: abonniert elegoo/<sn>/api_register,
        elegoo/<sn>/<client_id>/api_request und spielt die
        Register-Response / Query-Antworten zurueck."""
        if self.access_code is None:
            return  # --reject-auth: nichts zu adaptern
        c = mqtt.Client(client_id='mock-cc2-adapter',
                        protocol=mqtt.MQTTv311, clean_session=True)
        c.username_pw_set('elegoo', self.access_code)
        self._subscribed = threading.Event()
        c.on_connect = self._on_mqtt_connect
        c.on_subscribe = lambda *a, **kw: self._subscribed.set()
        c.on_message = self._on_mqtt_message
        c.connect(self.args.bind, self.args.mqtt_port, keepalive=60)
        c.loop_start()
        # Blockierend warten, bis der Adapter mindestens eine SUBACK hat,
        # sonst gehen fruehe Client-Requests ins Leere.
        if not self._subscribed.wait(5):
            raise RuntimeError('mock-cc2-adapter: MQTT subscribe timeout')
        self.mqtt_client = c

    def _on_mqtt_connect(self, c, u, flags, rc, props=None):
        c.subscribe(f'elegoo/{self.sn}/api_register')
        c.subscribe(f'elegoo/{self.sn}/+/api_request')

    def _on_mqtt_message(self, c, u, msg):
        try:
            payload = json.loads(msg.payload.decode('utf-8'))
        except Exception:
            return
        topic = msg.topic
        # api_register: antworte unter dem request-spezifischen Topic
        if topic.endswith('/api_register'):
            cid = payload.get('client_id', 'unknown')
            rid = payload.get('request_id', 'unknown')
            reply = {'client_id': cid, 'error': 'ok'}
            c.publish(f'elegoo/{self.sn}/{rid}/register_response',
                      json.dumps(reply), qos=0)
            return
        # api_request: method-abhaengige Antwort
        if '/api_request' not in topic:
            return
        # topic = elegoo/<sn>/<client_id>/api_request
        parts = topic.split('/')
        cid = parts[2] if len(parts) >= 3 else 'unknown'
        resp_topic = f'elegoo/{self.sn}/{cid}/api_response'
        if payload.get('type') == 'PING':
            c.publish(resp_topic, json.dumps({'type': 'PONG'}), qos=0)
            return
        method = payload.get('method')
        rid = payload.get('id')
        result: dict = {'error_code': 0}
        if method == 1002:
            result = dict(STATUS_FIXTURE_IDLE)
        elif method == 2005:
            result = dict(CANVAS_FIXTURE)
        elif method == 1044:
            # file_list – gib die aktuell hochgeladenen Dateien zurueck
            files = [{'filename': name, 'size': len(data), 'type': 'file'}
                     for name, data in self.uploads.items()]
            result = {'error_code': 0, 'file_list': files,
                      'offset': 0, 'total': len(files)}
        elif method == 1046:
            name = (payload.get('params') or {}).get('filename')
            if name in self.uploads:
                data = self.uploads[name]
                result = {'error_code': 0, 'filename': name,
                          'size': len(data), 'layer': 100,
                          'print_time': 565, 'total_filament_used': 3.52,
                          'last_print_time': 0, 'total_print_times': 0,
                          'create_time': int(time.time()),
                          'color_map': [{'t': 0, 'name': 'PLA', 'color': '#F2754E'}]}
            else:
                result = {'error_code': 1004}  # not found
        elif method == 1020:
            # Druckstart akzeptieren – aber NICHT weiter als Druck simulieren;
            # fuer M3 brauchen wir diesen Pfad nicht, nur die Response.
            result = {'error_code': 0}
        else:
            result = {'error_code': 1003}
        c.publish(resp_topic,
                  json.dumps({'id': rid, 'method': method, 'result': result}),
                  qos=0)

    # ---------- UDP (Discovery 52700) ----------

    async def _udp_loop(self) -> None:
        loop = asyncio.get_event_loop()
        transport, _ = await loop.create_datagram_endpoint(
            lambda: _DiscoveryProto(self),
            local_addr=(self.args.bind, self.args.udp_port),
        )
        # bis Shutdown offen halten
        try:
            await asyncio.Future()
        finally:
            transport.close()

    def discovery_response(self) -> bytes:
        token_status = 1 if self.access_code is not None else 1
        return json.dumps({
            'id': 0,
            'result': {
                'sn': self.sn,
                'host_name': 'Mock Centauri Carbon 2',
                'machine_model': 'Centauri Carbon 2',
                'protocol_version': '1.0.0',
                'lan_status': 1,
                'token_status': token_status,
            },
        }).encode('utf-8')

    # ---------- HTTP (chunked PUT /upload) ----------

    async def _http_loop(self) -> None:
        server = await asyncio.start_server(
            self._handle_http, self.args.bind, self.args.http_port,
        )
        async with server:
            await server.serve_forever()

    async def _handle_http(self, reader: asyncio.StreamReader,
                           writer: asyncio.StreamWriter) -> None:
        # Minimal-HTTP – nur PUT /upload mit X-Token-Auth + Content-Range.
        try:
            request_line = await reader.readline()
            method, path, _ = request_line.decode('iso-8859-1').split(' ', 2)
            headers: dict[str, str] = {}
            while True:
                h = await reader.readline()
                if h in (b'\r\n', b''):
                    break
                k, _, v = h.decode('iso-8859-1').partition(':')
                headers[k.strip().lower()] = v.strip()
            if method != 'PUT' or not path.startswith('/upload'):
                writer.write(b'HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n')
                await writer.drain()
                return
            if self.access_code is not None and \
                    headers.get('x-token') != self.access_code:
                writer.write(b'HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n')
                await writer.drain()
                return
            cl = int(headers.get('content-length', '0'))
            name = headers.get('x-file-name', 'unnamed.gcode')
            data = bytearray()
            remaining = cl
            while remaining > 0:
                chunk = await reader.read(min(remaining, 32768))
                if not chunk:
                    break
                data.extend(chunk)
                remaining -= len(chunk)
                if self.args.interrupt_upload_at and \
                        len(data) >= self.args.interrupt_upload_at:
                    # Netzabbruch simulieren
                    writer.close()
                    try:
                        await writer.wait_closed()
                    except Exception:
                        pass
                    return
            self.uploads.setdefault(name, bytearray()).extend(data)
            body = json.dumps({'error_code': 0,
                               'offset': len(self.uploads[name]) - 1}).encode('utf-8')
            writer.write(b'HTTP/1.1 200 OK\r\nContent-Length: '
                         + str(len(body)).encode('ascii')
                         + b'\r\nContent-Type: application/json\r\n\r\n' + body)
            await writer.drain()
        except Exception as e:
            print(f'[mock-http] error: {e}', file=sys.stderr)
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

    # ---------- Lifecycle ----------

    async def run(self) -> None:
        self._start_mosquitto()
        self._start_mqtt_adapter()
        print(f'[mock-cc2] SN={self.sn}', flush=True)
        print(f'[mock-cc2] MQTT  tcp://{self.args.bind}:{self.args.mqtt_port}'
              f'  user=elegoo  password='
              f'{"<REJECT>" if self.access_code is None else "<accepted, see --access-code>"}',
              flush=True)
        print(f'[mock-cc2] UDP   udp://{self.args.bind}:{self.args.udp_port}',
              flush=True)
        print(f'[mock-cc2] HTTP  http://{self.args.bind}:{self.args.http_port}/upload',
              flush=True)
        if self.args.interrupt_upload_at:
            print(f'[mock-cc2] FEHLERINJEKTION: close() nach '
                  f'{self.args.interrupt_upload_at} byte Upload', flush=True)
        try:
            await asyncio.gather(self._udp_loop(), self._http_loop())
        finally:
            if self.mqtt_client is not None:
                self.mqtt_client.loop_stop()
                self.mqtt_client.disconnect()
            self._stop_mosquitto()


class _DiscoveryProto(asyncio.DatagramProtocol):
    def __init__(self, mock: MockCC2) -> None:
        self.mock = mock
        self.transport: Optional[asyncio.DatagramTransport] = None

    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data: bytes, addr: tuple) -> None:
        try:
            msg = json.loads(data)
        except Exception:
            return
        if msg.get('method') == 7000:
            self.transport.sendto(self.mock.discovery_response(), addr)


def main() -> int:
    p = argparse.ArgumentParser(description='Mock Elegoo Centauri Carbon 2')
    p.add_argument('--bind', default='127.0.0.1')
    p.add_argument('--udp-port', type=int, default=52700)
    p.add_argument('--mqtt-port', type=int, default=1883)
    p.add_argument('--http-port', type=int, default=8080)
    p.add_argument('--sn', default=MOCK_SN)
    p.add_argument('--access-code',
                   help='Access-Code; sonst aus $MOCK_ACCESS_CODE oder '
                        'zufaellig generiert und auf stdout gedruckt')
    p.add_argument('--reject-auth', action='store_true',
                   help='MQTT lehnt jeden CONNECT ab (Simuliert falscher Code)')
    p.add_argument('--interrupt-upload-at', type=int, default=0,
                   help='HTTP schliesst Verbindung nach N byte Upload')
    args = p.parse_args()
    mock = MockCC2(args)
    # Access-Code **nur** einmalig auf stdout wenn er auto-generiert war
    # und der Test ihn braucht; einmal ausgegeben: in CI-Logs potenziell
    # sichtbar. Fuer M3-Tests besser via MOCK_ACCESS_CODE setzen.
    if (args.access_code is None and
            os.environ.get('MOCK_ACCESS_CODE') is None
            and not args.reject_auth):
        print(f'[mock-cc2] Auto-generierter Access-Code: {mock.access_code}',
              flush=True)
    try:
        asyncio.run(mock.run())
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == '__main__':
    sys.exit(main())
