#!/usr/bin/env python3
"""
Block A Geraetetest (nach PROGRESS.md 2026-10-31).

Nur die vier erlaubten Methoden fuer die Pflichtliste:
  - 1002 GetBasicInfo / 1003 GetMachineStatus (passiv ueber api_status)
  - 1044 GetFileList
  - 1047 DeleteFile (file_path)
  - 1042 GetLivingVideoUrl / 1054 StartVideoStream
  - 1029 LightSwitch

Jeder Subcommand haelt NACH dem Schritt an und schreibt kein zusaetzliches
State ausserhalb der Logs. Credentials werden ausschliesslich aus .env
gelesen und nie ausgegeben (scrub() ersetzt SN + Access-Code).

Subcommands:
  status                             Schritt 0: Idle-Pruefung
  list                               Schritt 1: 1044 Dateiliste
  upload <name>                      Vorstufe Schritt 2: Mini-Datei per PUT /upload hochladen
  delete <filename>                  Schritt 2: 1047 mit file_path=string
                                         (--as-array fuer file_path=[string])
  camera-get                         Schritt 3a: 1042 URL + Zustand
  camera-set <0|1>                   Schritt 3b: 1054 enable
  light-set <0|1>                    Schritt 4:  1029 power
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import http.client
import json
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


def scrub(obj, sn: str, access_code: str, ip: str):
    if isinstance(obj, dict):
        return {k: scrub(v, sn, access_code, ip) for k, v in obj.items()}
    if isinstance(obj, list):
        return [scrub(v, sn, access_code, ip) for v in obj]
    if isinstance(obj, str):
        return (
            obj.replace(sn, "<cc2-sn>")
               .replace(access_code, "<access-code>")
               .replace(ip, "<cc2-ip>")
        )
    return obj


class Client:
    def __init__(self, ip: str, access: str, sn: str, methods_to_wait: set[int]):
        self.ip, self.access, self.sn = ip, access, sn
        self.client_id = f"hsltest{random.randint(0, 0xffff):04x}"
        self.request_id = "".join(f"{random.randint(0, 15):x}" for _ in range(27))
        self.c = mqtt.Client(client_id=self.client_id, clean_session=True, protocol=mqtt.MQTTv311)
        self.c.username_pw_set("elegoo", access)
        self.c.on_connect = self._on_connect
        self.c.on_message = self._on_message
        self.ready = threading.Event()
        self.registered = threading.Event()
        self.last_status: int | None = None
        self.status_samples: list[int] = []
        self.replies: dict[int, dict] = {}
        self.reply_events: dict[int, threading.Event] = {
            m: threading.Event() for m in methods_to_wait
        }

    def _on_connect(self, client, userdata, flags, rc):
        if rc != 0:
            print(f"CONNACK rc={rc}", file=sys.stderr)
            self.ready.set()
            return
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
            self.registered.set()
            return
        if msg.topic.endswith("/api_status"):
            res = payload.get("result", {})
            ms = res.get("machine_status", {}) if isinstance(res, dict) else {}
            if "status" in ms:
                self.last_status = ms["status"]
                self.status_samples.append(ms["status"])
            return
        if msg.topic.endswith("/api_response"):
            m = payload.get("method")
            if m in self.reply_events:
                self.replies[m] = payload
                self.reply_events[m].set()

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

    def publish_method(self, method: int, params: dict | None = None, rid: int | None = None) -> int:
        topic = f"elegoo/{self.sn}/{self.client_id}/api_request"
        rid = rid if rid is not None else random.randint(100000, 2_000_000_000)
        obj: dict = {"id": rid, "method": method}
        if params is not None:
            obj["params"] = params
        self.c.publish(topic, json.dumps(obj), qos=0)
        return rid

    def wait_reply(self, method: int, timeout: float = 10.0) -> dict | None:
        if not self.reply_events[method].wait(timeout=timeout):
            return None
        return self.replies.get(method)

    def disconnect(self):
        try:
            self.c.disconnect()
            self.c.loop_stop()
        except Exception:
            pass


def session(methods: set[int], env: dict[str, str], require_idle: bool = True) -> tuple[Client, str]:
    disc = discover(env["CC2_IP"])
    sn = disc["sn"]
    if disc.get("lan_status") != 1:
        sys.exit("Drucker nicht im Nur-LAN-Modus; stoppen.")
    cli = Client(env["CC2_IP"], env["CC2_ACCESS_CODE"], sn, methods)
    cli.connect()
    # Idle-Beobachtung: 4 s passiv — die CC2-Firmware pusht machine_status
    # nur bei Zustandswechseln, deshalb ist "kein Push" keine Anomalie.
    # Nur ein beobachteter status != 1 bricht ab.
    time.sleep(4)
    if cli.last_status is not None and cli.last_status != 1 and require_idle:
        cli.disconnect()
        sys.exit(f"Drucker nicht Idle (status={cli.last_status}); stoppen.")
    cli.register()
    return cli, sn


def dump(label: str, payload: dict, sn: str, env: dict[str, str]) -> None:
    scrubbed = scrub(payload, sn, env["CC2_ACCESS_CODE"], env["CC2_IP"])
    print(f"\n=== {label} ===")
    print(json.dumps(scrubbed, ensure_ascii=False, indent=2))


# ---------------------------- Subcommands ---------------------------- #

def cmd_status(args):
    env = load_env()
    disc = discover(env["CC2_IP"])
    sn = disc["sn"]
    print(f"Discovery: lan_status={disc['lan_status']} token_status={disc['token_status']}")
    if disc.get("lan_status") != 1:
        sys.exit("lan_status != 1; stoppen.")
    cli = Client(env["CC2_IP"], env["CC2_ACCESS_CODE"], sn, set())
    try:
        cli.connect()
        print("Passive status read: 12 s …")
        time.sleep(12)
        print(f"status samples seen: {cli.status_samples}")
        print(f"last machine_status.status: {cli.last_status}")
        if cli.last_status is None:
            print("Printer sent no api_status in 12 s.")
            sys.exit(2)
        if cli.last_status == 1:
            print("Idle (status=1). OK to continue.")
        else:
            print(f"NOT idle (status={cli.last_status}). ABORT Block A.")
            sys.exit(3)
    finally:
        cli.disconnect()


def cmd_list(args):
    env = load_env()
    cli, sn = session({1044}, env)
    try:
        rid = cli.publish_method(1044, {"storage_media": "local", "offset": 0, "limit": 200})
        print(f"PUB 1044 id={rid} params={{storage_media:local, offset:0, limit:200}}")
        reply = cli.wait_reply(1044, timeout=15)
        if reply is None:
            sys.exit("1044 timeout.")
        dump("RAW 1044 (anonymized)", reply, sn, env)
        res = reply.get("result", {}) if isinstance(reply, dict) else {}
        files = res.get("file_list", []) if isinstance(res, dict) else []
        probes = [f for f in files
                  if isinstance(f, dict)
                  and isinstance(f.get("filename"), str)
                  and f["filename"].startswith("cc2_probe_")]
        print(f"\n=== probe files (cc2_probe_*) : {len(probes)} ===")
        for f in probes:
            print(f"  {f.get('filename')!r}  size={f.get('size')}  "
                  f"create_time={f.get('create_time')}")
    finally:
        cli.disconnect()


def cmd_upload(args):
    """Mini-File PUT /upload. Nach Elegoo CC2 HTTP-Transfer-Protokoll:
       1 Chunk, Content-Range: bytes 0-(N-1)/N, X-File-Name, X-File-MD5,
       X-Token=access_code. Antwort JSON mit error_code=0.
    """
    env = load_env()
    body = (
        b"; delete test\n"
        b"; cc2_probe_delete_test\n"
        b"; exists only to verify method 1047 param shape\n"
        b"; NOT meant to be printed\n"
    )
    size = len(body)
    md5 = hashlib.md5(body).hexdigest()  # lowercase hex, as per Orca
    name = args.name
    headers = {
        "Content-Type": "application/octet-stream",
        "Content-Length": str(size),
        "Content-Range": f"bytes 0-{size - 1}/{size}",
        "X-File-Name": name,
        "X-File-MD5": md5,
        "X-Token": env["CC2_ACCESS_CODE"],
        "Accept": "application/json",
        "User-Agent": "handslice-block-a",
    }
    print(f"PUT http://<cc2-ip>:80/upload  size={size}B  md5={md5}  name={name!r}")
    # Nur die nicht-sensiblen Header anzeigen
    for k, v in headers.items():
        if k == "X-Token":
            continue
        print(f"  {k}: {v}")

    conn = http.client.HTTPConnection(env["CC2_IP"], 80, timeout=15)
    try:
        conn.request("PUT", "/upload", body=body, headers=headers)
        resp = conn.getresponse()
        resp_body = resp.read().decode("utf-8", errors="replace")
    finally:
        conn.close()

    print(f"\n<- HTTP {resp.status} {resp.reason}")
    try:
        parsed = json.loads(resp_body)
    except json.JSONDecodeError:
        print(f"<- raw body: {resp_body!r}")
        sys.exit("Response not JSON.")
    scrubbed = scrub(parsed, "", env["CC2_ACCESS_CODE"], env["CC2_IP"])
    print(json.dumps(scrubbed, ensure_ascii=False, indent=2))
    if resp.status != 200 or scrubbed.get("error_code") not in (0, None):
        sys.exit(f"Upload refused: HTTP={resp.status} error_code={scrubbed.get('error_code')}")


def cmd_delete(args):
    env = load_env()
    cli, sn = session({1044, 1047}, env)
    try:
        file_path = args.filename
        if args.as_array:
            fp_param = [file_path]
            label = f"1047 file_path=[{file_path!r}]"
        else:
            fp_param = file_path
            label = f"1047 file_path={file_path!r}"
        print(f"PUB {label}")
        rid = cli.publish_method(
            1047, {"storage_media": "local", "file_path": fp_param}
        )
        print(f"  id={rid}")
        reply = cli.wait_reply(1047, timeout=15)
        if reply is None:
            sys.exit("1047 timeout.")
        dump("RAW 1047 (anonymized)", reply, sn, env)
        # danach frisch 1044
        cli.reply_events[1044].clear()
        cli.replies.pop(1044, None)
        rid2 = cli.publish_method(1044, {"storage_media": "local", "offset": 0, "limit": 200})
        print(f"\nPUB 1044 id={rid2} (verify)")
        reply2 = cli.wait_reply(1044, timeout=15)
        if reply2 is None:
            sys.exit("1044 verify timeout.")
        res = reply2.get("result", {}) if isinstance(reply2, dict) else {}
        files = res.get("file_list", []) if isinstance(res, dict) else []
        names = [f.get("filename") for f in files if isinstance(f, dict)]
        still = file_path in names
        print(f"=== verify: file still present? {still} ===")
    finally:
        cli.disconnect()


def cmd_camera_get(args):
    env = load_env()
    cli, sn = session({1042}, env)
    try:
        rid = cli.publish_method(1042)
        print(f"PUB 1042 id={rid} (no params)")
        reply = cli.wait_reply(1042, timeout=15)
        if reply is None:
            sys.exit("1042 timeout.")
        dump("RAW 1042 (anonymized)", reply, sn, env)
    finally:
        cli.disconnect()


def cmd_camera_set(args):
    env = load_env()
    cli, sn = session({1054}, env)
    try:
        rid = cli.publish_method(1054, {"enable": int(args.enable)})
        print(f"PUB 1054 enable={int(args.enable)} id={rid}")
        reply = cli.wait_reply(1054, timeout=15)
        if reply is None:
            sys.exit("1054 timeout.")
        dump("RAW 1054 (anonymized)", reply, sn, env)
    finally:
        cli.disconnect()


def cmd_light_set(args):
    env = load_env()
    cli, sn = session({1029}, env)
    try:
        rid = cli.publish_method(1029, {"power": int(args.power)})
        print(f"PUB 1029 power={int(args.power)} id={rid}")
        reply = cli.wait_reply(1029, timeout=15)
        if reply is None:
            sys.exit("1029 timeout.")
        dump("RAW 1029 (anonymized)", reply, sn, env)
    finally:
        cli.disconnect()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status").set_defaults(func=cmd_status)
    sub.add_parser("list").set_defaults(func=cmd_list)
    up = sub.add_parser("upload")
    up.add_argument("name", help="Target filename on the printer")
    up.set_defaults(func=cmd_upload)
    d = sub.add_parser("delete")
    d.add_argument("filename")
    d.add_argument("--as-array", action="store_true",
                   help="Send file_path as [filename] instead of string")
    d.set_defaults(func=cmd_delete)
    sub.add_parser("camera-get").set_defaults(func=cmd_camera_get)
    cs = sub.add_parser("camera-set")
    cs.add_argument("enable", type=int, choices=(0, 1))
    cs.set_defaults(func=cmd_camera_set)
    ls = sub.add_parser("light-set")
    ls.add_argument("power", type=int, choices=(0, 1))
    ls.set_defaults(func=cmd_light_set)
    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
