#!/usr/bin/env python3
"""
Passiver MQTT-Mitschnitt am CC2.

Verbindet sich mit user='elegoo' + Access-Code aus .env an <CC2_IP>:1883,
subscribt '#' und schreibt jede eingehende Nachricht als JSONL nach
logs/cc2-sniff-<datum>.jsonl.

Kein PUBLISH. Kein api_register, kein PING. Nur Subscribe + Receive.

Wenn der Drucker ohne Register-Handshake nichts auf api_status pusht,
wird das sichtbar, weil der Sniff dann nach einer Grace-Period
'no messages received' meldet (stdout); der Mitschnitt laeuft trotzdem
weiter.

Beenden mit SIGTERM/SIGINT → sauberer DISCONNECT.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import signal
import socket
import sys
import threading
import time
from pathlib import Path

import paho.mqtt.client as mqtt


REPO = Path(__file__).resolve().parent.parent
ENV_FILE = REPO / ".env"
LOG_DIR = REPO / "logs"


def load_env() -> dict[str, str]:
    env: dict[str, str] = {}
    if not ENV_FILE.exists():
        print(f"ERROR: {ENV_FILE} fehlt", file=sys.stderr)
        sys.exit(2)
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()
    for k in ("CC2_IP", "CC2_ACCESS_CODE"):
        if k not in env:
            print(f"ERROR: {k} nicht in {ENV_FILE}", file=sys.stderr)
            sys.exit(2)
    return env


def iso_now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds")


def payload_to_fields(payload: bytes) -> dict:
    try:
        text = payload.decode("utf-8")
    except UnicodeDecodeError:
        return {"payload_hex": payload.hex()}
    try:
        parsed = json.loads(text)
        return {"payload_text": text, "payload_json": parsed}
    except (json.JSONDecodeError, ValueError):
        return {"payload_text": text}


class Sniffer:
    def __init__(self, ip: str, access_code: str, log_path: Path):
        self.ip = ip
        self.access_code = access_code
        self.log_path = log_path
        self.log_fh = open(log_path, "a", buffering=1, encoding="utf-8")
        self.msg_count = 0
        self.first_msg_at: float | None = None
        self.last_msg_at: float | None = None
        self.stop = threading.Event()
        self.lock = threading.Lock()
        self.client = mqtt.Client(
            client_id=f"hslsniff{os.getpid() & 0xffff:04x}",
            clean_session=True,
            protocol=mqtt.MQTTv311,
        )
        self.client.username_pw_set("elegoo", access_code)
        self.client.on_connect = self._on_connect
        self.client.on_disconnect = self._on_disconnect
        self.client.on_message = self._on_message
        self.client.on_subscribe = self._on_subscribe

    def _on_connect(self, client, userdata, flags, rc):
        self._write_meta("connect", {"rc": rc, "flags": flags})
        if rc != 0:
            print(f"CONNACK rc={rc} — Verbindung abgelehnt", file=sys.stderr)
            self.stop.set()
            return
        print(f"CONNACK rc=0 (accepted) @ {iso_now_utc()}", flush=True)
        client.subscribe("#", qos=0)

    def _on_subscribe(self, client, userdata, mid, granted_qos):
        self._write_meta("subscribe", {"mid": mid, "granted_qos": list(granted_qos)})
        print(f"SUBACK # qos={list(granted_qos)}", flush=True)

    def _on_disconnect(self, client, userdata, rc):
        self._write_meta("disconnect", {"rc": rc})
        print(f"DISCONNECT rc={rc}", flush=True)

    def _on_message(self, client, userdata, msg):
        now = time.time()
        rec = {
            "ts": iso_now_utc(),
            "topic": msg.topic,
            "qos": msg.qos,
            "retain": bool(msg.retain),
            "size": len(msg.payload),
        }
        rec.update(payload_to_fields(msg.payload))
        with self.lock:
            self.log_fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
            self.msg_count += 1
            if self.first_msg_at is None:
                self.first_msg_at = now
                print(f"FIRST MSG topic={msg.topic} size={len(msg.payload)}", flush=True)
            self.last_msg_at = now

    def _write_meta(self, kind: str, data: dict):
        rec = {"ts": iso_now_utc(), "meta": kind, **data}
        with self.lock:
            self.log_fh.write(json.dumps(rec, ensure_ascii=False) + "\n")

    def run(self):
        self._write_meta("start", {"ip": self.ip, "log_path": str(self.log_path)})
        try:
            self.client.connect(self.ip, 1883, keepalive=60)
        except (OSError, socket.gaierror) as exc:
            print(f"ERROR: connect failed: {exc}", file=sys.stderr)
            self._write_meta("connect_error", {"error": str(exc)})
            self.log_fh.close()
            sys.exit(3)
        self.client.loop_start()

        try:
            while not self.stop.is_set():
                time.sleep(1)
        finally:
            self._write_meta(
                "shutdown",
                {
                    "msg_count": self.msg_count,
                    "first_msg_at": self.first_msg_at,
                    "last_msg_at": self.last_msg_at,
                },
            )
            self.client.loop_stop()
            try:
                self.client.disconnect()
            except Exception:
                pass
            self.log_fh.close()


def main():
    env = load_env()
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    date_str = dt.datetime.now().strftime("%Y-%m-%d")
    # Falls heute schon ein Lauf existiert, mit Uhrzeit-Suffix, um ihn nicht zu
    # ueberschreiben.
    base = LOG_DIR / f"cc2-sniff-{date_str}.jsonl"
    if base.exists():
        suffix = dt.datetime.now().strftime("%H%M%S")
        log_path = LOG_DIR / f"cc2-sniff-{date_str}-{suffix}.jsonl"
    else:
        log_path = base
    print(f"log → {log_path}", flush=True)

    sniffer = Sniffer(env["CC2_IP"], env["CC2_ACCESS_CODE"], log_path)

    def handle_signal(signo, frame):
        print(f"signal {signo} → shutdown", flush=True)
        sniffer.stop.set()

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    sniffer.run()
    print(
        f"done: {sniffer.msg_count} msg, "
        f"first={sniffer.first_msg_at}, last={sniffer.last_msg_at}",
        flush=True,
    )


if __name__ == "__main__":
    main()
