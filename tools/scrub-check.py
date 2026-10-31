#!/usr/bin/env python3
"""
Scrub-Check: pruefe, ob sensible Werte aus .env irgendwo im
Projekt-Textbestand auftauchen.

Liest .env intern (die Werte verlassen das Skript nicht), ermittelt
zusaetzlich die aktuelle Druckerseriennummer per UDP-Discovery
(method 7000, Port 52700) auf dem bekannten CC2_IP, und greppt
in einem festen Zielsatz nach jedem Wert. Berichtet nur
Trefferzahlen pro Zielmenge und (anonymisierter) Zielpfad – nie
den Wert selbst, nie das Treffer-Umfeld.

Zielmenge (Default, ueber --files/--dirs ergaenzbar):
  - tools/cc2-block-a.py
  - tools/scrub-check.py   (sich selbst – 0 erwartet)
  - docs/ (rekursiv)
  - PROGRESS.md

Argumente:
  --strict   Exit != 0, sobald irgendwo > 0 Treffer stehen.
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ENV_FILE = REPO / ".env"

# Secret-Felder, nach denen immer gesucht wird. Fehlt eins in .env,
# wird es stillschweigend uebersprungen.
ENV_SECRET_KEYS = (
    "CC2_ACCESS_CODE",
    "CC2_IP",
    "CC2_SN",
    "ELEGOO_ACCOUNT_ID",
    "ELEGOO_USERNAME",
    "ELEGOO_PASSWORD",
    "ELEGOO_TOKEN",
    "ACCOUNT_ID",
    "USER_ID",
)


def load_env() -> dict[str, str]:
    env: dict[str, str] = {}
    if not ENV_FILE.exists():
        sys.exit(f"ERROR: {ENV_FILE} fehlt")
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    return env


def discover_sn(ip: str) -> str | None:
    """Hole die aktuelle Seriennummer per UDP, damit der Scrub die
    live-SN sieht, auch wenn sie nicht in .env steht. Timeout 2 s,
    fehlertolerant."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(2)
        s.sendto(json.dumps({"id": 0, "method": 7000}).encode(), (ip, 52700))
        data, _ = s.recvfrom(4096)
        sn = json.loads(data).get("result", {}).get("sn")
        return sn if isinstance(sn, str) and sn else None
    except Exception:
        return None


def default_targets() -> list[Path]:
    targets: list[Path] = []
    targets.append(REPO / "tools" / "cc2-block-a.py")
    targets.append(REPO / "tools" / "scrub-check.py")
    docs = REPO / "docs"
    if docs.is_dir():
        for p in sorted(docs.rglob("*")):
            if p.is_file() and p.suffix in {".md", ".txt", ".rst", ".json", ".yaml", ".yml"}:
                targets.append(p)
    targets.append(REPO / "PROGRESS.md")
    return [t for t in targets if t.is_file()]


def count_hits(path: Path, needle: str) -> int:
    """Byte-exakte Substring-Suche. Keine Regex, kein Case-Fold."""
    if not needle:
        return 0
    try:
        data = path.read_bytes()
    except Exception:
        return 0
    needle_b = needle.encode("utf-8")
    if not needle_b:
        return 0
    count = 0
    start = 0
    while True:
        idx = data.find(needle_b, start)
        if idx < 0:
            break
        count += 1
        start = idx + 1
    return count


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--strict", action="store_true",
                    help="Exit != 0, sobald irgendwo > 0 Treffer stehen.")
    args = ap.parse_args()

    env = load_env()
    labels: dict[str, str] = {}
    for key in ENV_SECRET_KEYS:
        val = env.get(key, "").strip()
        if len(val) >= 4:   # 1-3-Zeichen-Werte waeren zu kurz fuer eine robuste Suche
            labels[key] = val

    # live-SN fuer den Fall, dass sie nicht in .env steht
    cc2_ip = env.get("CC2_IP", "").strip()
    if cc2_ip and "CC2_SN" not in labels:
        sn = discover_sn(cc2_ip)
        if sn:
            labels["CC2_SN(live)"] = sn

    if not labels:
        print("Keine durchsuchbaren Secret-Werte in .env gefunden – nichts zu pruefen.")
        return 0

    targets = default_targets()
    print(f"Scrub-Check: {len(labels)} Secret-Felder gegen {len(targets)} Dateien.\n")
    header = f"{'Secret-Feld':<22} {'# Treffer gesamt':>18}   Dateien mit > 0 Treffern"
    print(header)
    print("-" * len(header))

    any_hit = False
    for key, val in labels.items():
        total = 0
        hit_files: list[tuple[int, Path]] = []
        for path in targets:
            n = count_hits(path, val)
            if n > 0:
                total += n
                hit_files.append((n, path))
        if total > 0:
            any_hit = True
        rel = ""
        if hit_files:
            rel = " ; ".join(f"{p.relative_to(REPO)}={n}" for n, p in hit_files)
        print(f"{key:<22} {total:>18}   {rel}")

    print()
    if any_hit:
        print("ACHTUNG: mindestens ein Secret-Feld hat Treffer. Werte NICHT ausgegeben.")
        if args.strict:
            return 2
    else:
        print("Keine Treffer. Scrub sauber.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
