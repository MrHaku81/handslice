#!/usr/bin/env python3
"""
Realtest: method 1051 (TIMELAPSE_RENDERING) gegen CC2 Stock 02.01.01.07.

Idle-Check, Register-Handshake, dann genau EIN publish_request(1051, {"url": ...})
nach cc2-control-Beleg. Antwort erfassen, dann DISCONNECT (das Composing
beobachtet separat der mqtt-sniff.py-Lauf).

Payload (laut mqtt.c:277-287 und :362-372):
  topic:   elegoo/<sn>/<client_id>/api_request
  payload: {"method":1051,"id":1051,"params":{"url":"<escaped>"}}
"""

from __future__ import annotations

import datetime as dt
import json
import random
import socket
import sys
import threading
import time
from pathlib import Path

import paho.mqtt.client as mqtt


REPO = Path(__file__).resolve().parent.parent


def load_env():
    env = {}
    for line in (REPO / ".env").read_text().splitlines():
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    return env


def discover(ip):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(3)
    s.sendto(json.dumps({"id": 0, "method": 7000}).encode(), (ip, 52700))
    data, _ = s.recvfrom(4096)
    return json.loads(data)["result"]


class Client:
    def __init__(self, ip, access, sn):
        self.ip, self.access, self.sn = ip, access, sn
        self.client_id = f"hslrender{random.randint(0, 0xffff):04x}"
        self.request_id = "".join(f"{random.randint(0, 15):x}" for _ in range(27))
        self.c = mqtt.Client(client_id=self.client_id, clean_session=True, protocol=mqtt.MQTTv311)
        self.c.username_pw_set("elegoo", access)
        self.c.on_connect = self._on_connect
        self.c.on_message = self._on_message
        self.ready = threading.Event()
        self.registered = threading.Event()
        self.last_status = None
        self.render_reply = None
        self.render_done = threading.Event()

    def _on_connect(self, client, userdata, flags, rc):
        if rc != 0:
            print(f"CONNACK rc={rc}", file=sys.stderr); self.ready.set(); return
        print(f"CONNACK rc=0 @ {dt.datetime.now(dt.timezone.utc).isoformat(timespec='milliseconds')}", flush=True)
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
            self.registered.set(); return
        if msg.topic.endswith("/api_status"):
            res = payload.get("result", {})
            ms = res.get("machine_status", {}) if isinstance(res, dict) else {}
            if "status" in ms:
                self.last_status = ms["status"]
            return
        if msg.topic.endswith("/api_response"):
            m = payload.get("method")
            if m == 1051:
                ts = dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds")
                print(f"RESPONSE 1051 @ {ts}: {payload}", flush=True)
                self.render_reply = payload
                self.render_done.set()
            else:
                print(f"other api_response method={m}: {payload}", flush=True)

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

    def send_1051(self, url: str):
        topic = f"elegoo/{self.sn}/{self.client_id}/api_request"
        # Zahlenschema wie cc2-control: id = method (siehe mqtt.c:284)
        payload_dict = {"method": 1051, "id": 1051, "params": {"url": url}}
        payload = json.dumps(payload_dict)
        ts = dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds")
        print(f"PUB 1051 @ {ts}: {payload_dict}", flush=True)
        self.c.publish(topic, payload, qos=0)
        if not self.render_done.wait(timeout=10):
            raise RuntimeError("1051 response timeout")

    def disconnect(self):
        try:
            self.c.disconnect()
            self.c.loop_stop()
        except Exception:
            pass


def main():
    if len(sys.argv) < 2:
        sys.exit("Usage: cc2-render-timelapse.py <time_lapse_video_url>")
    url = sys.argv[1]

    env = load_env()
    disc = discover(env["CC2_IP"])
    sn = disc["sn"]
    if disc.get("lan_status") != 1:
        sys.exit("not in LAN-only mode")

    cli = Client(env["CC2_IP"], env["CC2_ACCESS_CODE"], sn)
    try:
        cli.connect()
        print("Idle-Check: 10 s passiv …", flush=True)
        time.sleep(10)
        print(f"last machine_status.status = {cli.last_status}", flush=True)
        if cli.last_status is not None and cli.last_status != 1:
            sys.exit(f"Printer not idle (status={cli.last_status}); stop.")
        cli.register()
        cli.send_1051(url)
    finally:
        cli.disconnect()


if __name__ == "__main__":
    main()
