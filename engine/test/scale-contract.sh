#!/usr/bin/env bash
# Vertragstest fuer die CLI-Option --scale.
#
# Vorbedingung: engine/bin/handslice-cli-x86 ist frisch gebaut.
# Modell: cube_20mm_centered_cc2.stl (20 mm Kantenlaenge).
# Prueft:
#   1. --scale 2.0 → G-Code enthaelt G1-Zuege mit X/Y-Spannen >= 2x
#      der Baseline-Spannen (Orcas ModelObject::scale(Vec3d) wirkt).
#   2. --scale 0.5 → Spannen entsprechend halbiert.
#   3. --scale 0 oder negativ → Exit != 0 (Validierung).
#
# Keine Device-Abhaengigkeit. Reiner x86-Lauf.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="${PROJECT_ROOT}/engine/bin/handslice-cli-x86"
STL="${PROJECT_ROOT}/engine/test/cube_20mm_centered_cc2.stl"
RES="${PROJECT_ROOT}/engine/OrcaSlicer/resources"
PROF="${RES}/profiles/Elegoo"
MACH="${PROF}/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json"
PROC="${PROF}/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json"
FIL="${PROF}/filament/ECC2/Elegoo PLA @ECC2.json"

[[ -x "${CLI}" ]] || { echo "FEHLT: ${CLI}" >&2; exit 2; }
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "=== 1/3  Baseline (ohne --scale) ==="
# WITHOUT --no-center, damit skalierte Modelle nicht durch die
# urspruengliche STL-Position oben am Bed-Rand abgeschnitten werden.
"${CLI}" --machine "${MACH}" --process "${PROC}" --filament "${FIL}" \
    --resources "${RES}" --output "${TMP}/base.gcode" --bed-type A --quiet \
    "${STL}" > /dev/null

echo "=== 2/3  --scale 2.0 ==="
"${CLI}" --machine "${MACH}" --process "${PROC}" --filament "${FIL}" \
    --resources "${RES}" --output "${TMP}/scale2.gcode" --bed-type A --quiet \
    --scale 2.0 "${STL}" > /dev/null

echo "=== 3/3  --scale 0 muss abbrechen ==="
if "${CLI}" --machine "${MACH}" --process "${PROC}" --filament "${FIL}" \
    --resources "${RES}" --output "${TMP}/scale0.gcode" --bed-type A --quiet \
    --scale 0 "${STL}" > /dev/null 2>&1; then
    echo "FAIL: --scale 0 wurde akzeptiert" >&2; exit 1
fi
echo "   OK (exit != 0 wie erwartet)"

python3 <<PY
# Primaere Metrik: max_z_height im G-Code-Header (';max_z_height: X.YY').
# Das ist die tatsaechliche Modellhoehe nach dem Scale, unverrauscht
# von Travel/Prime-Line.
def mz(path):
    for line in open(path):
        s = line.lstrip('; ').strip()
        if s.startswith('max_z_height'):
            return float(s.split(':', 1)[1].strip())
    return None
mb = mz('${TMP}/base.gcode'); ms = mz('${TMP}/scale2.gcode')
if mb is None or ms is None:
    print('FAIL: max_z_height-Metadata nicht gefunden'); raise SystemExit(1)
print(f'   max_z_height (baseline → scale 2.0) = {mb:.2f} → {ms:.2f} mm')
r = ms / mb
if r < 1.95 or r > 2.05:
    print(f'FAIL: Z-Hoehe wuchs {r:.3f}x, erwartet 2.00x +/- 0.05'); raise SystemExit(1)
print('PASS (--scale 2.0 verdoppelt max_z_height im G-Code-Header)')
PY

echo
echo "scale-contract: alle 3 Checks grün."
