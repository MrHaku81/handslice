#!/usr/bin/env python3
"""
Realtest: method 1036 (GET_HISTORY) gegen CC2 Stock 02.01.01.07.

Reihenfolge:
  1. Discovery (UDP 52700) prüft lan_status, SN
  2. MQTT connect + subscribe (api_status, register_response, api_response)
  3. 15 s passiver Idle-Check: machine_status.status muss auf 1 (Idle) stehen
  4. api_register (minimal Register-Handshake, kein PING)
  5. publish method 1036 auf api_request
  6. Antwort empfangen (ggf. mehrere Fragmente)
  7. Antwort SN-anonymisieren und ausgeben

Keine Credentials in stdout/Datei. Nur Access-Code wird nach MQTT geschickt.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import random
import socket
import sys
import threading
import time
from pathlib import Path

import paho.mqtt.client as mqtt


REPO = Path(__file__).resolve().parent.parent
ENV_FILE = REPO / ".env"


def load_env() -> dict[str, str]:
    env: dict[str, str] = {}
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    for k in ("CC2_IP", "CC2_ACCESS_CODE"):
        if k not in env:
            sys.exit(f"ERROR: {k} missing from {ENV_FILE}")
    return env


def discover(ip: str) -> dict:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(3)
    s.sendto(json.dumps({"id": 0, "method": 7000}).encode(), (ip, 52700))
    data, _ = s.recvfrom(4096)
    return json.loads(data)["result"]


def scrub(obj, sn: str, access_code: str):
    """Rekursiv: SN → <cc2-sn>, access_code → <access-code>."""
    if isinstance(obj, dict):
        return {k: scrub(v, sn, access_code) for k, v in obj.items()}
    if isinstance(obj, list):
        return [scrub(v, sn, access_code) for v in obj]
    if isinstance(obj, str):
        return obj.replace(sn, "<cc2-sn>").replace(access_code, "<access-code>")
    return obj


class Client:
    def __init__(self, ip: str, access: str, sn: str):
        self.ip, self.access, self.sn = ip, access, sn
        self.client_id = f"hsltest{random.randint(0, 0xffff):04x}"
        self.request_id = "".join(f"{random.randint(0, 15):x}" for _ in range(27))
        self.c = mqtt.Client(client_id=self.client_id, clean_session=True, protocol=mqtt.MQTTv311)
        self.c.username_pw_set("elegoo", access)
        self.c.on_connect = self._on_connect
        self.c.on_message = self._on_message
        self.ready = threading.Event()
        self.registered = threading.Event()
        self.last_status = None
        self.history_reply = None
        self.history_done = threading.Event()

    def _on_connect(self, client, userdata, flags, rc):
        if rc != 0:
            print(f"CONNACK rc={rc}", file=sys.stderr); self.ready.set(); return
        print(f"CONNACK rc=0 @ {dt.datetime.now().isoformat(timespec='seconds')}", flush=True)
        for t in (f"elegoo/{self.sn}/{self.request_id}/register_response",
                  f"elegoo/{self.sn}/api_status",
                  f"elegoo/{self.sn}/{self.client_id}/api_response"):
            client.subscribe(t, qos=0)
        self.ready.set()

    def _on_message(self, client, userdata, msg):
        try:
            payload = json.loads(msg.payload.decode())
        except Exception:
            return
        if msg.topic.endswith("/register_response"):
            print(f"REGISTER_RESPONSE {payload}", flush=True)
            self.registered.set()
            return
        if msg.topic.endswith("/api_status"):
            res = payload.get("result", {})
            ms = res.get("machine_status", {}) if isinstance(res, dict) else {}
            if "status" in ms:
                self.last_status = ms["status"]
            return
        if msg.topic.endswith("/api_response"):
            m = payload.get("method")
            if m == 1036:
                print(f"RESPONSE 1036 size={len(msg.payload)}", flush=True)
                self.history_reply = payload
                self.history_done.set()
            else:
                print(f"other api_response method={m}", flush=True)

    def connect(self):
        self.c.connect(self.ip, 1883, keepalive=60)
        self.c.loop_start()
        if not self.ready.wait(timeout=5):
            raise RuntimeError("connect timeout")

    def register(self):
        topic = f"elegoo/{self.sn}/api_register"
        payload = json.dumps({"client_id": self.client_id, "request_id": self.request_id})
        self.c.publish(topic, payload, qos=0)
        if not self.registered.wait(timeout=5):
            raise RuntimeError("register timeout")

    def request_history(self):
        topic = f"elegoo/{self.sn}/{self.client_id}/api_request"
        rid = random.randint(100000, 2_000_000_000)
        payload = json.dumps({"id": rid, "method": 1036})
        print(f"PUB method 1036 id={rid}", flush=True)
        self.c.publish(topic, payload, qos=0)
        if not self.history_done.wait(timeout=30):
            raise RuntimeError("1036 timeout")

    def disconnect(self):
        try:
            self.c.disconnect()
            self.c.loop_stop()
        except Exception:
            pass


def main():
    env = load_env()
    disc = discover(env["CC2_IP"])
    sn = disc["sn"]
    print(f"Discovery: lan_status={disc['lan_status']} token_status={disc['token_status']}", flush=True)
    if disc.get("lan_status") != 1:
        sys.exit("Drucker nicht im Nur-LAN-Modus; stoppen.")

    cli = Client(env["CC2_IP"], env["CC2_ACCESS_CODE"], sn)
    try:
        cli.connect()
        # Idle-Check: 10 s passiv auf api_status warten, letzten Status lesen
        print("Idle-Check: 10 s passiv …", flush=True)
        time.sleep(10)
        print(f"last machine_status.status = {cli.last_status}", flush=True)
        if cli.last_status is None:
            print("WARN: kein status-Delta gesehen — fahre vorsichtig fort", flush=True)
        elif cli.last_status != 1:
            sys.exit(f"Drucker nicht Idle (status={cli.last_status}); stoppen.")
        cli.register()
        cli.request_history()
    finally:
        cli.disconnect()

    reply = cli.history_reply
    if reply is None:
        sys.exit("Keine 1036-Antwort erhalten.")

    scrubbed = scrub(reply, sn, env["CC2_ACCESS_CODE"])

    # Rohantwort anonymisiert nach docs/
    out = REPO / "docs" / "cc2-history-sample.json"
    out.write_text(json.dumps(scrubbed, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"wrote {out}  ({out.stat().st_size} bytes)", flush=True)

    # Kurzfassung auf stdout: Tasks mit Zeitraffer-Status
    result = scrubbed.get("result", {})
    tasks = result.get("history_task_list", [])
    print(f"\n=== history_task_list: {len(tasks)} Tasks ===")
    for t in tasks:
        begin = t.get("begin_time")
        begin_iso = dt.datetime.fromtimestamp(begin, dt.timezone.utc).isoformat() if begin else "?"
        print(
            f"  task_id={t.get('task_id')}  begin={begin_iso}  "
            f"name={t.get('task_name')!r}  "
            f"task_status={t.get('task_status')}  "
            f"video_status={t.get('time_lapse_video_status')}  "
            f"video_url={t.get('time_lapse_video_url')!r}  "
            f"video_size={t.get('time_lapse_video_size')}"
        )

    err = result.get("error_code")
    if err:
        print(f"\nerror_code = {err}")


if __name__ == "__main__":
    main()
