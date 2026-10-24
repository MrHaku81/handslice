#!/usr/bin/env bash
# Reference-Test fuer Phase A: slict einen 20-mm-Wuerfel mit CC2 0.4 +
# 0.20mm Standard + Elegoo PLA und vergleicht den EXECUTABLE_BLOCK gegen
# die festgehaltene Referenz (Desktop-Orca-GUI-Export, v2.4.2).
#
# Erfolgs-Kriterium: sha256 des EXECUTABLE_BLOCK stimmt mit
#   92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d (8479 Zeilen)
# ueberein. Exit 0 = bestanden, Exit 1 = Divergenz.
#
# Voraussetzungen:
#   - engine/bin/handslice-cli-x86 ist gebaut (via engine/build-headless-x86.sh)
#   - engine/OrcaSlicer-Submodul ist auf v2.4.2 ausgecheckt (fuer Profile)
#   - engine/test/reference/cube_20mm_cc2_gui_v2.4.2.gcode ist unveraendert
#
# Usage: bash engine/test/run-reference-test.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="${PROJECT_ROOT}/engine/bin/handslice-cli-x86"
RESOURCES="${PROJECT_ROOT}/engine/OrcaSlicer/resources"
PROFILES="${RESOURCES}/profiles/Elegoo"
STL="${PROJECT_ROOT}/engine/test/cube_20mm_centered_cc2.stl"
REF="${PROJECT_ROOT}/engine/test/reference/cube_20mm_cc2_gui_v2.4.2.gcode"
EXPECTED_SHA="92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d"
EXPECTED_LINES=8479

if [ ! -x "${CLI}" ]; then
    echo "FEHLT: ${CLI}" >&2
    echo "  → zuerst 'bash engine/build-headless-x86.sh' laufen lassen." >&2
    exit 2
fi
if [ ! -d "${RESOURCES}" ]; then
    echo "FEHLT: ${RESOURCES}" >&2
    echo "  → Submodul 'engine/OrcaSlicer' nicht initialisiert." >&2
    exit 2
fi
if [ ! -f "${REF}" ]; then
    echo "FEHLT: ${REF}" >&2
    exit 2
fi

OUT_DIR="$(mktemp -d)"
trap 'rm -rf "${OUT_DIR}"' EXIT
OUT_GCODE="${OUT_DIR}/plate_1.gcode"

echo "=== 1/3  Slice (handslice-cli-x86) ==="
"${CLI}" \
    --machine "${PROFILES}/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json" \
    --process "${PROFILES}/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json" \
    --filament "${PROFILES}/filament/ECC2/Elegoo PLA @ECC2.json" \
    --resources "${RESOURCES}" \
    --output "${OUT_GCODE}" \
    --no-center \
    --quiet \
    "${STL}" > "${OUT_DIR}/stats.json"

echo "   Stats:"
sed 's/^/     /' "${OUT_DIR}/stats.json"

echo
echo "=== 2/3  EXECUTABLE_BLOCK vergleichen ==="
awk '/^; EXECUTABLE_BLOCK_START/,/^; EXECUTABLE_BLOCK_END/' "${OUT_GCODE}" > "${OUT_DIR}/our-exec.g"
our_sha=$(sha256sum "${OUT_DIR}/our-exec.g" | awk '{print $1}')
our_lines=$(wc -l < "${OUT_DIR}/our-exec.g")

printf "  erwartet: %s  (%s Zeilen)\n" "${EXPECTED_SHA}" "${EXPECTED_LINES}"
printf "  erhalten: %s  (%s Zeilen)\n" "${our_sha}"      "${our_lines}"

if [ "${our_sha}" = "${EXPECTED_SHA}" ] && [ "${our_lines}" = "${EXPECTED_LINES}" ]; then
    echo "  → IDENTISCH"
    exec_ok=1
else
    echo "  → DIVERGENZ"
    echo "  erste 40 Zeilen Diff gegen Referenz:"
    awk '/^; EXECUTABLE_BLOCK_START/,/^; EXECUTABLE_BLOCK_END/' "${REF}" > "${OUT_DIR}/ref-exec.g"
    diff "${OUT_DIR}/ref-exec.g" "${OUT_DIR}/our-exec.g" | head -40 | sed 's/^/    /'
    exec_ok=0
fi

echo
echo "=== 3/3  Gesamt-Vergleich (zur Info) ==="
bash "${PROJECT_ROOT}/engine/test/compare-gcode.sh" "${REF}" "${OUT_GCODE}" || true

[ "${exec_ok}" = "1" ] && exit 0 || exit 1
