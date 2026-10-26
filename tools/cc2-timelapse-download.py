#!/usr/bin/env python3
"""
Realtest: GET /download?X-Token=<access>&file_name=<url> fuer Zeitraffer-MP4.

Argument: time_lapse_video_url wie von method 1036 geliefert, z. B.
  "video/<name>.gcode<ts>.mp4"

Keine MQTT-Session noetig; nur HTTP GET gegen den Drucker.
Speichert bei Erfolg in local-test/ (git-ignoriert).
"""

from __future__ import annotations

import datetime as dt
import hashlib
import os
import socket
import ssl
import sys
import urllib.parse
import urllib.request
from pathlib import Path


REPO = Path(__file__).resolve().parent.parent


def load_env() -> dict[str, str]:
    env: dict[str, str] = {}
    for line in (REPO / ".env").read_text().splitlines():
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    return env


def main():
    if len(sys.argv) < 2:
        sys.exit("Usage: cc2-timelapse-download.py <time_lapse_video_url>")
    url_path = sys.argv[1]

    env = load_env()
    ip = env["CC2_IP"]
    access = env["CC2_ACCESS_CODE"]

    # file_name wird vom Drucker roh verglichen, deshalb nur token percent-encoden.
    # Der cc2-control-Code (history.h:321-322) macht es genau so: beide
    # percent_encode(), aber safe-Zeichen bleiben Alphanumerik + "-._~".
    query = urllib.parse.urlencode({"X-Token": access, "file_name": url_path})
    url = f"http://{ip}/download?{query}"

    # Nur die Request-URL anonymisiert loggen (Token weg).
    safe_url = url.replace(access, "<access-code>")
    print(f"GET {safe_url}", flush=True)

    out_dir = REPO / "local-test"
    out_dir.mkdir(exist_ok=True)
    # Dateiname: nur den Basename aus url_path nehmen, kein Pfadtrick zulassen.
    base = os.path.basename(url_path)
    if "/" in base or "\\" in base or base.startswith("."):
        sys.exit("Unsicherer Dateiname.")
    out_file = out_dir / base

    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            status = resp.status
            headers = {k: v for k, v in resp.getheaders()}
            print(f"HTTP {status}", flush=True)
            for k in ("Content-Type", "Content-Length", "Content-Range",
                      "Content-Disposition", "Transfer-Encoding"):
                if k in headers:
                    print(f"  {k}: {headers[k]}")
            if status != 200:
                sys.exit(f"non-200: {status}")

            h = hashlib.md5()
            total = 0
            with open(out_file, "wb") as fh:
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    fh.write(chunk)
                    h.update(chunk)
                    total += len(chunk)

        print(f"\nsaved: {out_file}  ({total} bytes, md5={h.hexdigest()})")
    except urllib.error.HTTPError as e:
        print(f"HTTPError: {e.code} {e.reason}", file=sys.stderr)
        try:
            body = e.read().decode("utf-8", errors="replace")[:400]
            print(f"body: {body}", file=sys.stderr)
        except Exception:
            pass
        sys.exit(2)
    except (socket.timeout, urllib.error.URLError, OSError) as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(3)


if __name__ == "__main__":
    main()
