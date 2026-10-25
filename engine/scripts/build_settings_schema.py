#!/usr/bin/env python3
"""Join: Schema (handslice-cli --dump-schema) + Layout (Tab.cpp) +
Deutsch-Katalog (OrcaSlicer_de.po) → ein kompaktes JSON pro Bereich
(print/filament/printer) fuer die App.

Zusaetzlich schreibt ein Report (JSON + Mensch-lesbar), was Klaus im
STOPP-Bericht sehen will:
  - Optionen je Bereich x Stufe (Basis/Fortgeschritten/Experte/Develop)
  - Reiter/Gruppen-Liste
  - Nicht zuordenbare Optionen mit Grund
  - Uebersetzungsabdeckung Deutsch in %

Aufruf (aus Projekt-Root):
    engine/bin/handslice-cli-x86 --dump-schema > out/schema-raw.json
    python3 engine/scripts/extract_tab_layout.py > out/layout.json
    python3 engine/scripts/build_de_catalog.py  > out/de.json
    python3 engine/scripts/build_settings_schema.py \
        --schema out/schema-raw.json \
        --layout out/layout.json \
        --de     out/de.json \
        --out    out/settings-schema.json \
        --report out/settings-report.md
"""
from __future__ import annotations
import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--schema", required=True, type=Path)
    ap.add_argument("--layout", required=True, type=Path)
    ap.add_argument("--de",     required=True, type=Path)
    ap.add_argument("--out",    required=True, type=Path)
    ap.add_argument("--report", required=True, type=Path)
    args = ap.parse_args()

    raw     = json.loads(args.schema.read_text())
    layout  = json.loads(args.layout.read_text())
    de      = json.loads(args.de.read_text())["de"]

    opts: dict[str, dict] = raw["options"]

    # 1. Pro Bereich: zuordenbare Keys (aus Layout) joinen mit Options-Def
    settings_schema: dict = {
        "source": {
            "orca_version": raw.get("orca_version"),
            "schema": "handslice-cli --dump-schema",
            "layout": layout.get("source"),
            "de":     "engine/OrcaSlicer/localization/i18n/de/OrcaSlicer_de.po",
        },
        "areas": {},
    }

    assigned_keys: set[str] = set()
    assignment_areas: dict[str, str] = {}  # key -> area (fuer Dedup-Check)

    for area in ("print", "filament", "printer"):
        pages_out = []
        for p in layout[area]:
            groups_out = []
            for g in p["groups"]:
                keys_out = []
                for k in g["keys"]:
                    key = k["key"]
                    od  = opts.get(key)
                    if not od:
                        # Key in Tab.cpp referenziert, aber nicht im
                        # Schema – kann an SLA/Internals liegen. Als
                        # Platzhalter mit Flag mitgeben.
                        keys_out.append({"key": key, "missing_from_schema": True,
                                          "source_line": k["line"]})
                        continue
                    label_en = od.get("label") or ""
                    tip_en   = od.get("tooltip") or ""
                    keys_out.append({
                        "key":    key,
                        "line":   k["line"],
                        "type":   od["type"],
                        "mode":   od["mode"],
                        "mode_int": od["mode_int"],
                        "label_en": label_en,
                        "label_de": de.get(label_en, "") if label_en else "",
                        "tooltip_en": tip_en,
                        "tooltip_de": de.get(tip_en, "") if tip_en else "",
                        "sidetext": od.get("sidetext", ""),
                        "default":  od.get("default", ""),
                        "min":      od.get("min"),
                        "max":      od.get("max"),
                        "enum_values": od.get("enum_values", []),
                        "enum_labels": od.get("enum_labels", []),
                        "enum_labels_de": [de.get(l, "") for l in od.get("enum_labels", [])],
                        "gui_type":   od.get("gui_type", ""),
                        "nullable":   od.get("nullable", False),
                        "readonly":   od.get("readonly", False),
                        "ratio_over": od.get("ratio_over", ""),
                    })
                    assigned_keys.add(key)
                    assignment_areas[key] = area
                groups_out.append({
                    "group": g["group"],
                    "group_label_de": de.get(g["group"], ""),
                    "group_line": g["group_line"],
                    "keys": keys_out,
                })
            pages_out.append({
                "page": p["page"],
                "page_label_de": de.get(p["page"], ""),
                "page_line": p["page_line"],
                "groups": groups_out,
            })
        settings_schema["areas"][area] = pages_out

    args.out.write_text(json.dumps(settings_schema, indent=2, ensure_ascii=False) + "\n")

    # 2. Report
    report_lines: list[str] = []
    rl = report_lines.append
    rl("# Phase 4.1 – Einstellungsbaum: Schema-Report")
    rl("")
    rl(f"- OrcaSlicer-Version (aus `--dump-schema`): `{raw.get('orca_version')}`")
    rl(f"- Options-Definitionen gesamt (print_config_def.options): **{raw['option_count']}**")
    rl(f"- Layout-Quelle: `{layout['source']['file']}` (Tag `{layout['source']['orca_tag']}`)")
    rl(f"- Uebersetzungs-Quelle: `OrcaSlicer_de.po` mit **{len(de)}** Eintraegen")
    rl("")

    rl("## Zuordnung aus Tab.cpp (mechanisch extrahiert)")
    rl("")
    rl("| Bereich | Reiter | Gruppen | Options (einzigartig) |")
    rl("|---|---|---|---|")
    for area in ("print", "filament", "printer"):
        pages = settings_schema["areas"][area]
        gc = sum(len(p["groups"]) for p in pages)
        kc = len(set(k["key"] for p in pages for g in p["groups"] for k in g["keys"]))
        rl(f"| {area} | {len(pages)} | {gc} | {kc} |")
    rl("")

    rl("### Reiter + Gruppen je Bereich")
    rl("")
    for area in ("print", "filament", "printer"):
        rl(f"**{area}**")
        for p in settings_schema["areas"][area]:
            lbl = f"{p['page']}" + (f" (de: {p['page_label_de']})" if p['page_label_de'] else "")
            rl(f"- {lbl}  _Tab.cpp:{p['page_line']}_")
            for g in p["groups"]:
                gde = f" (de: {g['group_label_de']})" if g['group_label_de'] else ""
                rl(f"  - {g['group']}{gde}  — {len(g['keys'])} keys  _:{g['group_line']}_")
        rl("")

    rl("## Verteilung nach Stufe (ConfigOptionMode)")
    rl("")
    rl("Werte aus `libslic3r/Config.hpp:199-204`: `comSimple=0, comAdvanced=1, comExpert=2, comDevelop=3`.")
    rl("")
    rl("| Bereich | Simple | Advanced | Expert | Develop | Σ |")
    rl("|---|---:|---:|---:|---:|---:|")
    for area in ("print", "filament", "printer"):
        c = Counter()
        for p in settings_schema["areas"][area]:
            for g in p["groups"]:
                for k in g["keys"]:
                    if "mode" in k:
                        c[k["mode"]] += 1
        total = sum(c.values())
        rl(f"| {area} | {c['simple']} | {c['advanced']} | {c['expert']} | {c['develop']} | {total} |")
    rl("")

    # 3. Nicht zuordenbare Optionen (im Schema, aber nicht im Layout)
    unassigned = [k for k in opts.keys() if k not in assigned_keys]
    rl("## Nicht zuordenbare Optionen (im Schema, nicht im Tab.cpp-Layout)")
    rl("")
    rl(f"Gesamt: **{len(unassigned)}** von {raw['option_count']}.")
    rl("")

    # Grund-Buckets:
    buckets: dict[str, list[str]] = defaultdict(list)
    for k in unassigned:
        od = opts[k]
        pt = od.get("printer_technology")
        label = od.get("label") or ""
        cat = od.get("category") or ""
        if pt == "SLA":
            buckets["SLA-only (nicht FFF)"].append(k)
        elif k in ("fuzzy_skin", "fuzzy_skin_point_distance", "fuzzy_skin_thickness",
                   "fuzzy_skin_first_layer"):
            buckets["Fuzzy-Skin — interaktives Werkzeug (Mal-Pfad)"].append(k)
        elif k.startswith("brim_") or k == "brim_type" or k == "brim_width":
            # Brim ist UI-Teil Support – kann sein, dass im Tab.cpp
            # vorhanden; falls hier gelandet, kennzeichnen.
            buckets["Brim (ggf. hinter Toggle in UI, nicht als Page)"].append(k)
        elif not label:
            buckets["Ohne Label (interne/legacy option)"].append(k)
        elif "custom_gcode" in k or k.endswith("_gcode"):
            buckets["G-Code-Templates (gehen separat in Drucker-Reiter)"].append(k)
        elif k.startswith("thumbnail") or k.startswith("thumbnails"):
            buckets["Thumbnails (werden ueber 3mf-Pipeline erzeugt, nicht als Nutzer-Setting)"].append(k)
        elif k in ("print_sequence", "print_order"):
            buckets["Plate-/Objekt-Setting (nicht Prozess/Filament/Drucker)"].append(k)
        else:
            buckets[f"Unbenutzt in Tab.cpp (printer_technology={pt}, category='{cat}')"].append(k)

    for bucket, keys in sorted(buckets.items(), key=lambda x: -len(x[1])):
        rl(f"### {bucket}  ({len(keys)})")
        # Beispiele, max 20
        sample = sorted(keys)[:20]
        rl("  " + ", ".join(sample) + (f", … (+{len(keys)-len(sample)})" if len(keys) > len(sample) else ""))
        rl("")

    # 4. Uebersetzungsabdeckung
    def coverage(items: list[tuple[str, str]]) -> tuple[int, int]:
        total = sum(1 for en, _ in items if en)
        covered = sum(1 for en, de_s in items if en and de_s)
        return covered, total

    rl("## Uebersetzungsabdeckung Deutsch")
    rl("")
    rl("Nur Options, die im Tab.cpp-Layout verwendet werden (= im App-UI sichtbar).")
    rl("")
    rl("| Bereich | Label (de/en) | Tooltip (de/en) | Reiter-Namen (de/en) | Gruppen-Namen (de/en) |")
    rl("|---|---|---|---|---|")
    for area in ("print", "filament", "printer"):
        labels   = []
        tooltips = []
        pages    = []
        groups   = []
        for p in settings_schema["areas"][area]:
            if p["page"]:
                pages.append((p["page"], p["page_label_de"]))
            for g in p["groups"]:
                if g["group"]:
                    groups.append((g["group"], g["group_label_de"]))
                for k in g["groups" if False else "keys"]:
                    labels.append((k.get("label_en", ""), k.get("label_de", "")))
                    tooltips.append((k.get("tooltip_en", ""), k.get("tooltip_de", "")))
        cl, tl = coverage(labels)
        ct, tt = coverage(tooltips)
        cp, tp = coverage(pages)
        cg, tg = coverage(groups)
        pct = lambda a, b: f"{a}/{b} ({(100*a/b):.0f}%)" if b else "-"
        rl(f"| {area} | {pct(cl,tl)} | {pct(ct,tt)} | {pct(cp,tp)} | {pct(cg,tg)} |")
    rl("")

    rl("## Gruppen ohne Keys (Tab.cpp fuehrt die Felder nicht per `append_single_option_line`)")
    rl("")
    rl("Betrifft die G-Code-Textfeld-Gruppen im Drucker-Reiter und analoge")
    rl("Gruppen im Filament-Reiter (Change extrusion role G-code, Post-")
    rl("processing Scripts, Notes). Dort werden Textboxen ueber einen")
    rl("eigenen Code-Pfad in Tab.cpp aufgebaut (nicht ueber den normalen")
    rl("Options-Pfad). Fuer die App-UI in Phase 4.2/4.3 brauchen wir diese")
    rl("Felder spaeter explizit – sie sind nicht verloren, sondern bewusst")
    rl("in einer anderen Zelle in Tab.cpp verdrahtet.")
    rl("")
    for area in ("print", "filament", "printer"):
        empties = []
        for p in settings_schema["areas"][area]:
            for g in p["groups"]:
                if not g["keys"]:
                    empties.append((p["page"], g["group"], g["group_line"]))
        if empties:
            rl(f"**{area}**: {len(empties)} Gruppe(n) ohne Keys")
            for page, group, ln in empties:
                rl(f"- {page} > {group}  _:{ln}_")
            rl("")

    rl("## Options-Zahl im Layout vs. Schema")
    rl("")
    rl(f"- Schema (print_config_def.options): **{raw['option_count']}**")
    rl(f"- Im Layout verwendet (einzigartige Keys ueber alle Bereiche): **{len(assigned_keys)}**")
    rl(f"- Nicht zuordenbar: **{len(unassigned)}** (Gruende: siehe Abschnitt oben)")

    args.report.write_text("\n".join(report_lines) + "\n")
    print(f"schema -> {args.out}")
    print(f"report -> {args.report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
