#!/usr/bin/env python3
"""
Test A: blockiert eine haengende Download-Anfrage den HTTP-Server?

- Baseline: 3× Head-Probe gegen den heutigen (vorhandenen) Download,
  Antwortzeit messen.
- Dann parallel:
    T1: GET auf eine geloeschte URL, ohne Timeout, bis zu 30 s offen halten
    T2: Head-Probe gegen den heutigen Download; sofort die Response-Head-
        Latenz messen.
- Vergleich mit der 74-ms-Referenz von vorhin.

Nichts schreibend am Drucker.
"""

from __future__ import annotations

import datetime as dt
import http.client
import json
import socket
import sys
import threading
import time
import urllib.parse
from pathlib import Path


REPO = Path(__file__).resolve().parent.parent


def load_env():
    env = {}
    for ln in (REPO / ".env").read_text().splitlines():
        if "=" in ln and not ln.strip().startswith("#"):
            k, v = ln.split("=", 1)
            env[k.strip()] = v.strip()
    return env


def pct(s: str) -> str:
    return urllib.parse.quote(s, safe="")


def head_probe(ip: str, access: str, file_name: str, timeout: float = 10.0) -> dict:
    """Verbindet, GET, misst Zeit bis Response-Head verfuegbar ist."""
    path = f"/download?X-Token={pct(access)}&file_name={pct(file_name)}"
    conn = http.client.HTTPConnection(ip, 80, timeout=timeout)
    t0 = time.monotonic()
    try:
        t_connect0 = t0
        conn.connect()
        t_connect1 = time.monotonic()
        conn.request("GET", path, headers={"Host": ip, "Connection": "close"})
        t_sent = time.monotonic()
        resp = conn.getresponse()
        t_head = time.monotonic()
        return {
            "connect_ms": round((t_connect1 - t_connect0) * 1000, 1),
            "send_ms": round((t_sent - t_connect1) * 1000, 1),
            "head_ms": round((t_head - t_sent) * 1000, 1),
            "total_to_head_ms": round((t_head - t0) * 1000, 1),
            "status": resp.status,
            "content_length": resp.getheader("Content-Length"),
            "transfer_encoding": resp.getheader("Transfer-Encoding"),
        }
    except TimeoutError:
        return {"timeout_ms": round((time.monotonic() - t0) * 1000, 1)}
    except Exception as e:
        return {"error": str(e), "elapsed_ms": round((time.monotonic() - t0) * 1000, 1)}
    finally:
        try: conn.close()
        except Exception: pass


def hang_request(ip: str, access: str, file_name: str, duration: float, result: dict):
    """Haengt in der Response-Head-Phase. Protokolliert, wie der Drucker reagiert."""
    path = f"/download?X-Token={pct(access)}&file_name={pct(file_name)}"
    conn = http.client.HTTPConnection(ip, 80, timeout=duration + 5)
    t0 = time.monotonic()
    try:
        conn.connect()
        result["connect_ok_at_ms"] = round((time.monotonic() - t0) * 1000, 1)
        conn.request("GET", path, headers={"Host": ip, "Connection": "close"})
        result["send_done_at_ms"] = round((time.monotonic() - t0) * 1000, 1)
        # Wir setzen den Socket auf non-blocking, damit wir messen koennen, wie lange der Drucker haengt.
        resp = conn.getresponse()
        result["response_arrived_at_ms"] = round((time.monotonic() - t0) * 1000, 1)
        result["status"] = resp.status
    except TimeoutError:
        result["timeout_ms"] = round((time.monotonic() - t0) * 1000, 1)
    except Exception as e:
        result["error"] = f"{type(e).__name__}: {e}"
        result["elapsed_ms"] = round((time.monotonic() - t0) * 1000, 1)
    finally:
        try: conn.close()
        except Exception: pass


def main():
    env = load_env()
    ip = env["CC2_IP"]; access = env["CC2_ACCESS_CODE"]

    # Zielobjekte aus der aktuellen Historie
    hist = json.load(open(REPO / "docs" / "cc2-history-sample.json"))
    tasks = hist["result"]["history_task_list"]
    status2 = sorted([t for t in tasks if t["time_lapse_video_status"] == 2],
                     key=lambda t: t["begin_time"])
    today = status2[-1]["time_lapse_video_url"]
    deleted = status2[0]["time_lapse_video_url"]  # aeltester, geloescht

    print(f"today  = {today}", flush=True)
    print(f"deleted= {deleted}", flush=True)

    # --- Baseline ---
    print("\n=== Baseline: 3× Head-Probe auf den heutigen Download ===", flush=True)
    for i in range(3):
        r = head_probe(ip, access, today, timeout=8)
        print(f"  run {i+1}: {r}", flush=True)
        time.sleep(0.5)

    # --- Haengender Request + paralleler Probe ---
    print("\n=== Parallel: haengender Request auf GELOESCHTE URL + Probe auf today ===", flush=True)
    hang_result: dict = {}
    hang_t = threading.Thread(target=hang_request, args=(ip, access, deleted, 30.0, hang_result), daemon=True)
    hang_t.start()
    # Dem haengenden Request 500 ms Vorlauf geben
    time.sleep(0.5)
    # jetzt Probe
    probe = head_probe(ip, access, today, timeout=15)
    print(f"  probe during-hang: {probe}", flush=True)
    hang_t.join(timeout=35)
    print(f"  hang result: {hang_result}", flush=True)

    # --- Nach dem haengenden Request: nochmal Probe ---
    print("\n=== Nachkontrolle: Head-Probe nach Ende des haengenden Requests ===", flush=True)
    r = head_probe(ip, access, today, timeout=8)
    print(f"  post-hang: {r}", flush=True)


if __name__ == "__main__":
    main()
