#!/usr/bin/env bash
# Vergleicht den CONFIG_BLOCK zweier G-Codes zeilenweise.
#
# OrcaSlicer schreibt den vollstaendigen DynamicPrintConfig als Kommentar-
# Block in den G-Code (`; CONFIG_BLOCK_START` … `; CONFIG_BLOCK_END`).
# Wenn die Slice-Logik divergiert, liegt die Ursache fast immer in einem
# einzelnen Config-Wert, der sich zwischen GUI-Export und CLI
# unterscheidet – etwa weil die Preset-Vererbungs-Kette unvollstaendig
# resolved wurde, oder ein Vendor-spezifischer Setzer (curr_bed_type,
# is_BBL_printer) im CLI nicht nachgebildet wird.
#
# Dieses Script findet solche Faelle automatisch, indem es die
# Zuweisungen aus dem CONFIG_BLOCK extrahiert und differenziert.
#
# Usage: compare-configblock.sh ref.gcode ours.gcode
#   exit 0 wenn kein Unterschied, sonst 1

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 ref.gcode ours.gcode" >&2
    exit 2
fi

REF="$1"
OURS="$2"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Config-Block aus beiden Dateien extrahieren und als "key = value"
# normalisieren. Es gibt zwei Formen von Config-Dumps in Orca-G-Code:
#   - "; CONFIG_BLOCK_START"-Block (am Ende der Datei, flach)
#   - "; <key>: <value>"-Zeilen (im Header, nur Teilauswahl)
# Wir vergleichen den CONFIG_BLOCK (am Ende), weil er alle Werte enthaelt.
extract_config() {
    awk '
        /^; CONFIG_BLOCK_START/ { in_block = 1; next }
        /^; CONFIG_BLOCK_END/ { in_block = 0 }
        in_block && /^; [a-z_]+ = / {
            # Schnitt "; " am Anfang
            sub(/^; /, "")
            print
        }
    ' "$1" | sort
}

extract_config "$REF"  > "$TMPDIR/ref.cfg"
extract_config "$OURS" > "$TMPDIR/our.cfg"

ln_ref=$(wc -l < "$TMPDIR/ref.cfg")
ln_our=$(wc -l < "$TMPDIR/our.cfg")

echo "=== CONFIG_BLOCK (${ln_ref} vs ${ln_our} Einträge) ==="

diff_output=$(diff -u "$TMPDIR/ref.cfg" "$TMPDIR/our.cfg" || true)

if [ -z "$diff_output" ]; then
    echo "  → IDENTISCH"
    exit 0
fi

# Keys aus beiden Dateien in assoziative Arrays einlesen und
# nach Kategorien aufteilen: nur-ref / nur-ours / beide-aber-anders.
awk -F ' = ' '
    FNR==NR { ref[$1] = $2; next }
    { our[$1] = $2 }
    END {
        for (k in ref) {
            if (!(k in our)) {
                print "ONLY_REF\t" k "\t" ref[k]
            } else if (ref[k] != our[k]) {
                print "DIFF\t" k "\t" ref[k] "\t" our[k]
            }
        }
        for (k in our)
            if (!(k in ref))
                print "ONLY_OURS\t" k "\t" our[k]
    }
' "$TMPDIR/ref.cfg" "$TMPDIR/our.cfg" | sort > "$TMPDIR/categorized"

n_diff=$(grep -c "^DIFF"      "$TMPDIR/categorized" || true)
n_only_ref=$(grep -c "^ONLY_REF"  "$TMPDIR/categorized" || true)
n_only_our=$(grep -c "^ONLY_OURS" "$TMPDIR/categorized" || true)

echo "  Werte unterschiedlich: $n_diff"
echo "  nur in ref:            $n_only_ref"
echo "  nur in ours:           $n_only_our"
echo

if [ "$n_diff" -gt 0 ]; then
    echo "--- Werte unterschiedlich (bis 60 Zeilen) ---"
    awk -F '\t' '$1=="DIFF" {printf "  %-40s  ref=%-25s  ours=%s\n", $2, $3, $4}' \
        "$TMPDIR/categorized" | head -60
fi
if [ "$n_only_ref" -gt 0 ]; then
    echo "--- Nur im Referenz-G-Code (bis 30 Zeilen) ---"
    awk -F '\t' '$1=="ONLY_REF" {printf "  %-40s  = %s\n", $2, $3}' \
        "$TMPDIR/categorized" | head -30
fi
if [ "$n_only_our" -gt 0 ]; then
    echo "--- Nur in unserem G-Code (bis 30 Zeilen) ---"
    awk -F '\t' '$1=="ONLY_OURS" {printf "  %-40s  = %s\n", $2, $3}' \
        "$TMPDIR/categorized" | head -30
fi
exit 1
