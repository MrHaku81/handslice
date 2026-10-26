#!/usr/bin/env python3
"""
Download-Probe fuer mehrere Status-2-Eintraege aus method 1036.

Fuer jeden Eintrag einen GET /download, Timings + Response-Shape festhalten.
Nur die heutige URL wird vollstaendig heruntergeladen (ffprobe-Gegentest);
alle anderen werden nach dem Header-Read abgebrochen – wir brauchen nur
die Information, OB der Drucker antwortet und wie.
"""

from __future__ import annotations

import datetime as dt
import http.client
import json
import ssl
import sys
import time
import urllib.parse
from pathlib import Path


REPO = Path(__file__).resolve().parent.parent
TIMEOUT_HEAD = 8.0  # Header-Read: Drucker antwortet entweder zuegig oder schweigt


def load_env():
    env = {}
    for ln in (REPO / ".env").read_text().splitlines():
        if "=" in ln and not ln.strip().startswith("#"):
            k, v = ln.split("=", 1)
            env[k.strip()] = v.strip()
    return env


def pct(s: str) -> str:
    return urllib.parse.quote(s, safe="")


def probe(ip: str, access: str, file_name: str, drain: bool = False) -> dict:
    """Einzelner GET; drain=True liest den ganzen Body (fuer die Gegenprobe)."""
    path = f"/download?X-Token={pct(access)}&file_name={pct(file_name)}"
    conn = http.client.HTTPConnection(ip, 80, timeout=TIMEOUT_HEAD)
    t0 = time.monotonic()
    out: dict = {"file_name": file_name}
    try:
        conn.request("GET", path, headers={"Host": ip, "Connection": "close"})
        resp = conn.getresponse()
        t1 = time.monotonic()
        headers = {k.lower(): v for k, v in resp.getheaders()}
        out.update({
            "status": resp.status,
            "reason": resp.reason,
            "head_ms": round((t1 - t0) * 1000, 1),
            "content_length": headers.get("content-length"),
            "transfer_encoding": headers.get("transfer-encoding"),
            "content_type": headers.get("content-type"),
            "content_disposition": headers.get("content-disposition"),
        })
        if drain:
            buf = bytearray()
            while True:
                chunk = resp.read(65536)
                if not chunk:
                    break
                buf.extend(chunk)
            import hashlib
            out["body_bytes"] = len(buf)
            out["md5"] = hashlib.md5(bytes(buf)).hexdigest()
            out["body"] = bytes(buf)
        else:
            # Nur ersten Byte-Chunk, damit wir sehen, OB Body kommt
            try:
                first = resp.read(256)
                out["body_sample_len"] = len(first)
                # Keine Rohbytes in den Log, nur Metadaten
                out["body_sample_printable"] = (
                    first.decode("utf-8", errors="replace") if len(first) < 256 else "<binary/large>"
                )
            except Exception as e:
                out["body_read_error"] = str(e)
    except TimeoutError:
        out["timeout"] = round((time.monotonic() - t0) * 1000, 1)
    except http.client.RemoteDisconnected as e:
        out["remote_disconnect"] = str(e)
        out["elapsed_ms"] = round((time.monotonic() - t0) * 1000, 1)
    except OSError as e:
        out["os_error"] = str(e)
        out["elapsed_ms"] = round((time.monotonic() - t0) * 1000, 1)
    finally:
        try:
            conn.close()
        except Exception:
            pass
    return out


def main():
    env = load_env()
    ip = env["CC2_IP"]
    access = env["CC2_ACCESS_CODE"]

    hist = json.load(open(REPO / "docs" / "cc2-history-sample.json"))
    tasks = hist["result"]["history_task_list"]
    status2 = [t for t in tasks if t.get("time_lapse_video_status") == 2]
    status2.sort(key=lambda t: t["begin_time"])

    # Heutiger Eintrag = juengster
    today = status2[-1]
    older = status2[:-1]

    results = []
    print(f"=== {len(status2)} Status-2-Eintraege ===", flush=True)
    for t in older:
        url = t["time_lapse_video_url"]
        print(f"\n>>> probe (expected FAIL): {url}", flush=True)
        r = probe(ip, access, url, drain=False)
        r["expected"] = "fail"
        r["task_begin"] = dt.datetime.fromtimestamp(t["begin_time"], dt.timezone.utc).isoformat()
        r["task_video_size"] = t["time_lapse_video_size"]
        # Fuer die Doku: nur anonymisierten Pfad speichern
        r_log = {k: v for k, v in r.items() if k != "body"}
        print(json.dumps(r_log, ensure_ascii=False), flush=True)
        results.append(r)

    print(f"\n>>> gegenprobe (expected 200): {today['time_lapse_video_url']}", flush=True)
    r_today = probe(ip, access, today["time_lapse_video_url"], drain=True)
    r_today["expected"] = "ok"
    r_today["task_begin"] = dt.datetime.fromtimestamp(today["begin_time"], dt.timezone.utc).isoformat()
    r_today["task_video_size"] = today["time_lapse_video_size"]
    # body raus beim Logging
    body = r_today.pop("body", None)
    print(json.dumps(r_today, ensure_ascii=False), flush=True)

    # Zusammenfassungs-Tabelle
    print("\n=== Zusammenfassung ===")
    print(f"{'url':<80s} {'status':>7s} {'head_ms':>8s} {'content-length':>15s} {'result':>10s}")
    for r in results + [r_today]:
        url = r["file_name"]
        if len(url) > 78: url = "…" + url[-77:]
        if "timeout" in r:
            res = f"timeout({r['timeout']}ms)"
            status = "-"; head = str(r['timeout']); clen = "-"
        elif "remote_disconnect" in r:
            res = "disconnect"
            status = "-"; head = str(r.get("elapsed_ms", "-")); clen = "-"
        elif "os_error" in r:
            res = f"oserr({r['os_error'][:12]})"
            status = "-"; head = str(r.get("elapsed_ms", "-")); clen = "-"
        else:
            res = "ok" if r.get("status") == 200 else f"http{r.get('status')}"
            status = str(r.get("status", "?")); head = str(r.get("head_ms","-"))
            clen = str(r.get("content_length","-"))
        print(f"{url:<80s} {status:>7s} {head:>8s} {clen:>15s} {res:>10s}")
except_summary = None

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"fatal: {e}", file=sys.stderr)
        sys.exit(1)
