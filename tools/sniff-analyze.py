#!/usr/bin/env python3
"""Auswertung des passiven MQTT-Mitschnitts (logs/cc2-sniff-*.jsonl)."""

from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

VIDEO_KEYWORDS = re.compile(
    r"(video|time_?lapse|camera|chassis_camera|delay_video|VIDEO_COMPOSING|mp4|avi|mkv|webm|film)",
    re.IGNORECASE,
)


def walk(obj, path=""):
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield from walk(v, f"{path}.{k}" if path else k)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from walk(v, f"{path}[{i}]")
    else:
        yield path, obj


def main(path: str):
    rows = []
    for ln in open(path):
        try:
            rows.append(json.loads(ln))
        except json.JSONDecodeError:
            continue

    msgs = [r for r in rows if "topic" in r]
    print(f"total records       : {len(rows)}")
    print(f"message records     : {len(msgs)}")
    if not msgs:
        return
    print(f"time span (first→last): {msgs[0]['ts']}  →  {msgs[-1]['ts']}")
    print()

    topic_counter = Counter(m["topic"] for m in msgs)
    print("== Topics ==")
    for t, c in topic_counter.most_common():
        print(f"  {c:5d}  {t}")
    print()

    # Felder, die wir nie zuvor im Mitschnitt gesehen hatten.
    field_counter = Counter()
    for m in msgs:
        j = m.get("payload_json")
        if j is None:
            continue
        for p, _ in walk(j):
            field_counter[p] += 1
    print(f"== Alle beobachteten Felder in Payloads ({len(field_counter)}) ==")
    for p, c in field_counter.most_common():
        marker = "  ⚑" if VIDEO_KEYWORDS.search(p) else ""
        print(f"  {c:5d}  {p}{marker}")
    print()

    # Video-/Kamera-/Zeitraffer-Keyword-Hits: in Keys ODER Werten.
    hits = []
    for m in msgs:
        j = m.get("payload_json")
        if j is None:
            txt = m.get("payload_text", "")
            if VIDEO_KEYWORDS.search(txt):
                hits.append((m["ts"], m["topic"], "RAW", txt[:200]))
            continue
        matches = []
        for p, v in walk(j):
            if VIDEO_KEYWORDS.search(p):
                matches.append((p, "KEY", v))
            elif isinstance(v, str) and VIDEO_KEYWORDS.search(v):
                matches.append((p, "VAL", v))
        for p, kind, v in matches:
            hits.append((m["ts"], m["topic"], f"{p} ({kind})", repr(v)))

    print(f"== Video-/Kamera-/Zeitraffer-Keyword-Hits: {len(hits)} ==")
    for ts, topic, p, v in hits:
        short = v if len(v) < 200 else v[:200] + "…"
        print(f"  {ts}  {topic}  {p}  = {short}")
    print()

    # machine_status.status + sub_status Verlauf (Delta-Merge).
    print("== machine_status.status / sub_status / print_status.state Transitionen ==")
    last_mstatus = None
    last_sub = None
    last_state = None
    for m in msgs:
        j = m.get("payload_json")
        if j is None:
            continue
        ms = j.get("result", {}).get("machine_status", {})
        ps = j.get("result", {}).get("print_status", {})
        ms_status = ms.get("status") if isinstance(ms, dict) else None
        ms_sub = ms.get("sub_status") if isinstance(ms, dict) else None
        ps_state = ps.get("state") if isinstance(ps, dict) else None

        changed = []
        if ms_status is not None and ms_status != last_mstatus:
            changed.append(f"status {last_mstatus}→{ms_status}")
            last_mstatus = ms_status
        if ms_sub is not None and ms_sub != last_sub:
            changed.append(f"sub_status {last_sub}→{ms_sub}")
            last_sub = ms_sub
        if ps_state is not None and ps_state != last_state:
            changed.append(f"print_state {last_state!r}→{ps_state!r}")
            last_state = ps_state
        if changed:
            print(f"  {m['ts']}  " + "  ".join(changed))
    print()

    # Zustandswechsel zwischen 2 (Printing) und 1 (Idle), um die Druckläufe zu
    # trennen. Suche nach dem Übergang 1 oder None → 2 als "Start".
    print("== erkennbare Druckläufe (status→2 bis status→1) ==")
    runs = []
    cur_start = None
    last = None
    for m in msgs:
        j = m.get("payload_json")
        if j is None:
            continue
        ms = j.get("result", {}).get("machine_status", {}) if isinstance(j, dict) else {}
        s = ms.get("status") if isinstance(ms, dict) else None
        if s is None:
            continue
        if s != last:
            if s == 2 and last != 2:
                cur_start = m["ts"]
            elif s != 2 and cur_start:
                runs.append((cur_start, m["ts"], f"end-status={s}"))
                cur_start = None
            last = s
    if cur_start:
        runs.append((cur_start, "(läuft noch beim Mitschnitt-Ende)", "unterminiert"))
    for i, (st, en, note) in enumerate(runs, 1):
        print(f"  Lauf {i}: {st}  →  {en}  ({note})")
    print()

    return runs


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "logs/cc2-sniff-2026-10-26.jsonl")
