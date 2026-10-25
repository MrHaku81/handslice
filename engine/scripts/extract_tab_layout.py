#!/usr/bin/env python3
"""Mechanischer Extraktor der Reiter/Gruppen/Options-Reihenfolge aus
OrcaSlicer src/slic3r/GUI/Tab.cpp.

Keine Hand-Pflege. Erzeugt JSON:

    {
      "source": {"file": "src/slic3r/GUI/Tab.cpp", "orca_tag": "v2.4.2"},
      "print":    [{"page": "...", "page_line": N,
                    "groups": [{"group": "...", "group_line": N,
                                "keys": [{"key": "layer_height", "line": N}, ...]}]}],
      "filament": [...],
      "printer":  [...]
    }

Parser verarbeitet die drei Build-Funktionen:

    TabPrint::build()      Zeilen 2311-2802
    TabFilament::build()   Zeilen 3892-4245
    TabPrinter::build()    Zeilen 4927-5302

und erkennt diese Pattern (siehe Tab.cpp selbst):

    page = add_options_page(L("Quality"), ...)
    optgroup = page->new_optgroup(L("Layer height"), ...)
    optgroup->append_single_option_line("layer_height", ...)
    optgroup->append_single_option_line(option, ...)           # Option-Objekt
    line.append_option(optgroup->get_option("overhang_1_4_speed"))
    append_option_line(optgroup, "key", ...)                   # Wrapper

Kommentarzeilen (`//`) werden ignoriert. Options-Objekt-Varianten
werden rueckwaertsaufgeloest: der letzte vorangegangene
`optgroup->get_option("<key>")`-Aufruf gilt als Key.
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
TAB_CPP      = PROJECT_ROOT / "engine/OrcaSlicer/src/slic3r/GUI/Tab.cpp"
RELATIVE     = "src/slic3r/GUI/Tab.cpp"

BUILD_FUNCS = {
    "print":    ["void TabPrint::build()"],
    "filament": ["void TabFilament::build()",
                 "void TabFilament::add_filament_overrides_page()"],
    # TabPrinter::build() ist nur Wrapper (build_fff/build_sla); fuer FFF
    # ist build_fff die eigentliche Oberflaeche + build_unregular_pages
    # erweitert um Extruder-Seiten.
    "printer":  ["void TabPrinter::build_fff()",
                 "void TabPrinter::build_unregular_pages(bool from_initial_build/* = false*/)"],
}

# Regex-Werkzeugkoffer
RE_FUNC_START  = re.compile(r"^void Tab(Print|Filament|Printer)::build\(\)\s*$")
RE_FUNC_END    = re.compile(r"^\}\s*$")
RE_PAGE        = re.compile(r"add_options_page\(\s*L\(?\s*\"([^\"]+)\"\s*\)?")
RE_OPTGROUP    = re.compile(r"new_optgroup\(\s*L\(?\s*\"([^\"]+)\"\s*\)?")
# optgroup->append_single_option_line("key", ...) ODER append_option_line(optgroup, "key"
RE_APPEND_STR  = re.compile(r"append_(?:single_option_line|option_line)\(\s*(?:optgroup\s*,\s*)?\"([a-z_0-9]+)\"")
# line.append_option(optgroup->get_option("key"))  oder  line.append_option(opt);
RE_GET_OPTION  = re.compile(r"get_option\(\s*\"([a-z_0-9]+)\"\s*\)")
RE_APPEND_OPT  = re.compile(r"append_option\(\s*([a-z_0-9]+)\s*\)")  # append_option(opt)
# Rueckwaerts: Option-Variablenname
RE_ASSIGN_GET  = re.compile(r"(?:Option\s+|auto\s+|)(\w+)\s*=\s*optgroup->get_option\(\s*\"([a-z_0-9]+)\"\s*\)")
# Kommentar?
def _is_comment(line: str) -> bool:
    s = line.lstrip()
    return s.startswith("//") or s.startswith("/*") or s.startswith("*")


def extract_section(lines: list[str], start_marker: str) -> tuple[int, int] | None:
    """Findet Zeilen [start, end) der build()-Funktion."""
    start = None
    depth = 0
    for i, line in enumerate(lines):
        if start is None:
            if line.strip() == start_marker:
                start = i
                depth = 0
            continue
        depth += line.count("{") - line.count("}")
        # Nach Oeffnung (depth>=1 nach erster {-Zeile) warten wir auf
        # depth == 0 an Zeilen-Ende.
        if depth == 0 and i > start:
            # Suche das letzte '{' in start+ – finde Funktionskoerper-End.
            return (start, i + 1)
    return None


def parse_build(lines: list[str], span: tuple[int, int]) -> list[dict]:
    """Liefert Liste von Pages mit Groups mit Keys."""
    pages: list[dict] = []
    cur_page: dict | None = None
    cur_group: dict | None = None
    # Rueckwaerts-Mapping: Variablenname → key (fuer append_option(opt))
    var_to_key: dict[str, str] = {}
    for lineno_0 in range(*span):
        raw = lines[lineno_0]
        if _is_comment(raw):
            continue
        line_no_1based = lineno_0 + 1  # 1-based fuer Beleg-Zweck

        # Variable = optgroup->get_option("key")  — merken
        for m in RE_ASSIGN_GET.finditer(raw):
            var_to_key[m.group(1)] = m.group(2)

        # Neue Page?
        mp = RE_PAGE.search(raw)
        if mp:
            cur_page = {"page": mp.group(1), "page_line": line_no_1based,
                        "groups": []}
            cur_group = None
            pages.append(cur_page)
            # Pages koennen in derselben Zeile auch new_optgroup starten –
            # weiter unten unten
        # Neue Optgroup?
        mg = RE_OPTGROUP.search(raw)
        if mg:
            if cur_page is None:
                # neue optgroup ohne page – ignorieren (nicht erwartet)
                continue
            cur_group = {"group": mg.group(1), "group_line": line_no_1based,
                         "keys": []}
            cur_page["groups"].append(cur_group)
        # append_single_option_line("key", ...)
        if cur_group is not None:
            for m in RE_APPEND_STR.finditer(raw):
                cur_group["keys"].append({"key": m.group(1),
                                          "line": line_no_1based})
            # line.append_option(optgroup->get_option("key"))
            for m in RE_GET_OPTION.finditer(raw):
                # Nur die Treffer in `append_option(...)`-Context
                # Vereinfachung: wenn `append_option` in derselben Zeile
                # steht und `get_option(...)` auch – als Multi-Line nehmen
                if "append_option" in raw or "append_single_option_line" in raw:
                    cur_group["keys"].append({"key": m.group(1),
                                              "line": line_no_1based})
            # line.append_option(opt) – var_to_key
            for m in RE_APPEND_OPT.finditer(raw):
                var = m.group(1)
                if var in var_to_key:
                    cur_group["keys"].append({"key": var_to_key[var],
                                              "line": line_no_1based})
    # Dedup pro Gruppe (manchmal taucht derselbe Key doppelt auf; Reihenfolge
    # bleibt die erste).
    for p in pages:
        for g in p["groups"]:
            seen = set()
            uniq = []
            for k in g["keys"]:
                if k["key"] in seen:
                    continue
                seen.add(k["key"])
                uniq.append(k)
            g["keys"] = uniq
    return pages


def main() -> int:
    if not TAB_CPP.exists():
        print(f"FEHLT: {TAB_CPP}", file=sys.stderr)
        return 2
    text  = TAB_CPP.read_text(encoding="utf-8")
    lines = text.splitlines()
    out: dict = {"source": {"file": RELATIVE, "orca_tag": "v2.4.2"}}
    for area, markers in BUILD_FUNCS.items():
        all_pages = []
        for marker in markers:
            span = extract_section(lines, marker)
            if not span:
                print(f"WARN: {marker} nicht gefunden", file=sys.stderr)
                continue
            all_pages.extend(parse_build(lines, span))
        out[area] = all_pages
    json.dump(out, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
