#!/usr/bin/env python3
"""Baut aus OrcaSlicer_de.po einen JSON-Katalog: msgid (en) → msgstr (de).

Englisch ist Quelle, Deutsch Uebersetzung. Mehrzeilige PO-Strings
werden korrekt zusammengefuegt. Nicht uebersetzte Eintraege (leeres
msgstr) kommen NICHT in den Katalog – so wird die Abdeckung spaeter
richtig berechnet.
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
PO_FILE      = PROJECT_ROOT / "engine/OrcaSlicer/localization/i18n/de/OrcaSlicer_de.po"

RE_MSGID  = re.compile(r'^msgid\s+"(.*)"$')
RE_MSGSTR = re.compile(r'^msgstr\s+"(.*)"$')
RE_CONT   = re.compile(r'^"(.*)"$')


def unescape(s: str) -> str:
    # Nur die PO-ueblichen Backslash-Escapes (\\, \", \n, \t) aufloesen –
    # NICHT das volle Python-`unicode_escape`-Codec, das wuerde UTF-8-
    # Bytes als Latin-1 reinterpretieren und Umlaute zerreissen.
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            if   nxt == "n":  out.append("\n")
            elif nxt == "t":  out.append("\t")
            elif nxt == "r":  out.append("\r")
            elif nxt == '"':  out.append('"')
            elif nxt == "\\": out.append("\\")
            else:
                out.append(c); out.append(nxt)  # unbekannt → beide behalten
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def parse_po(path: Path) -> dict[str, str]:
    cat: dict[str, str] = {}
    state = None  # None | "msgid" | "msgstr"
    cur_id: list[str] = []
    cur_str: list[str] = []

    def flush() -> None:
        key = "".join(cur_id)
        val = "".join(cur_str)
        if key and val:  # leere Header-Eintraege + nicht uebersetzte raus
            cat[unescape(key)] = unescape(val)

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip()
        if not line or line.startswith("#"):
            if state == "msgstr":
                flush()
                cur_id.clear()
                cur_str.clear()
                state = None
            continue
        m = RE_MSGID.match(line)
        if m:
            if state == "msgstr":
                flush()
            cur_id = [m.group(1)]
            cur_str = []
            state = "msgid"
            continue
        m = RE_MSGSTR.match(line)
        if m:
            cur_str = [m.group(1)]
            state = "msgstr"
            continue
        m = RE_CONT.match(line)
        if m and state == "msgid":
            cur_id.append(m.group(1))
            continue
        if m and state == "msgstr":
            cur_str.append(m.group(1))
            continue
    if state == "msgstr":
        flush()
    return cat


def main() -> int:
    if not PO_FILE.exists():
        print(f"FEHLT: {PO_FILE}", file=sys.stderr)
        return 2
    cat = parse_po(PO_FILE)
    out = {
        "source": {"file": "engine/OrcaSlicer/localization/i18n/de/OrcaSlicer_de.po",
                   "entries": len(cat)},
        "de": cat,
    }
    json.dump(out, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
