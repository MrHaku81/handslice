#!/usr/bin/env bash
# Reference-Test fuer Phase A/C: slict einen 20-mm-Wuerfel mit CC2 0.4 +
# 0.20mm Standard + Elegoo PLA und vergleicht den EXECUTABLE_BLOCK gegen
# die festgehaltene Referenz (Desktop-Orca-GUI-Export, v2.4.2).
#
# Erfolgs-Kriterium: sha256 des EXECUTABLE_BLOCK stimmt mit
#   92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d (8479 Zeilen)
# ueberein. Exit 0 = bestanden, Exit 1 = Divergenz.
#
# Modi:
#   (default)   lokal auf x86: engine/bin/handslice-cli-x86 (Phase A)
#   --device    auf dem Poco X3 Pro via adb: engine/bin/handslice-cli-arm64,
#               Profile + STL via adb push nach /data/local/tmp/handslice,
#               Slice auf dem Geraet, G-Code via adb pull zurueck (Phase C).
#
# Usage: bash engine/test/run-reference-test.sh [--device]

set -euo pipefail

MODE="local"
case "${1:-}" in
    --device) MODE="device" ;;
    "" ) MODE="local" ;;
    *)  echo "Usage: $0 [--device]" >&2; exit 2 ;;
esac

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOURCES="${PROJECT_ROOT}/engine/OrcaSlicer/resources"
PROFILES="${RESOURCES}/profiles/Elegoo"
STL="${PROJECT_ROOT}/engine/test/cube_20mm_centered_cc2.stl"
REF="${PROJECT_ROOT}/engine/test/reference/cube_20mm_cc2_gui_v2.4.2.gcode"
EXPECTED_SHA="92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d"
EXPECTED_LINES=8479

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

if [ "${MODE}" = "local" ]; then
    CLI="${PROJECT_ROOT}/engine/bin/handslice-cli-x86"
    if [ ! -x "${CLI}" ]; then
        echo "FEHLT: ${CLI}" >&2
        echo "  → zuerst 'bash engine/build-headless-x86.sh' laufen lassen." >&2
        exit 2
    fi

    echo "=== 1/3  Slice (handslice-cli-x86) ==="
    time_start=$(date +%s.%N)
    "${CLI}" \
        --machine "${PROFILES}/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json" \
        --process "${PROFILES}/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json" \
        --filament "${PROFILES}/filament/ECC2/Elegoo PLA @ECC2.json" \
        --resources "${RESOURCES}" \
        --output "${OUT_GCODE}" \
        --no-center \
        --quiet \
        "${STL}" > "${OUT_DIR}/stats.json"
    time_end=$(date +%s.%N)
    runtime_s=$(awk "BEGIN{printf \"%.1f\", ${time_end} - ${time_start}}")
    echo "   Laufzeit: ${runtime_s} s (AMR5, x86_64)"
else
    CLI_LOCAL="${PROJECT_ROOT}/engine/bin/handslice-cli-arm64"
    if [ ! -x "${CLI_LOCAL}" ]; then
        echo "FEHLT: ${CLI_LOCAL}" >&2
        echo "  → zuerst 'bash engine/build-cli-arm64.sh' laufen lassen." >&2
        exit 2
    fi
    if ! command -v adb > /dev/null; then
        echo "FEHLT: adb nicht im PATH" >&2
        exit 2
    fi
    if ! adb get-state 2>/dev/null | grep -q device; then
        echo "FEHLT: adb-Geraet nicht verbunden ('adb devices' prueft)" >&2
        exit 2
    fi

    REMOTE="/data/local/tmp/handslice"
    REMOTE_PROF="${REMOTE}/profiles"
    REMOTE_RES="${REMOTE}/resources-min"

    echo "=== 1/3  Push Binary + Profile + STL (${REMOTE}) ==="
    # Nur die fuer den Testlauf noetigen Elegoo-Profile mitnehmen plus die
    # ganze profiles/-Hierarchie der inherits-Chains. Scoped Storage ist in
    # /data/local/tmp nicht aktiv (dev-only Pfad).
    adb shell "rm -rf ${REMOTE}; mkdir -p ${REMOTE}" > /dev/null
    adb push "${CLI_LOCAL}" "${REMOTE}/handslice-cli" > /dev/null
    adb shell "chmod 0755 ${REMOTE}/handslice-cli" > /dev/null
    adb push "${STL}" "${REMOTE}/cube_20mm.stl" > /dev/null
    # Minimal-Resources-Dir: nur profiles/, in dem die inherits-Kette lebt.
    # Spart ca. 90 % der Resources-Groesse.
    REMOTE_RES_DIR="${REMOTE}/resources"
    adb shell "mkdir -p ${REMOTE_RES_DIR}" > /dev/null
    adb push "${RESOURCES}/profiles" "${REMOTE_RES_DIR}/profiles" > /dev/null

    echo "=== 2/3  Slice auf Poco X3 Pro ==="
    PROF_PATH="${REMOTE_RES_DIR}/profiles/Elegoo"
    time_start=$(date +%s.%N)
    adb shell "cd ${REMOTE} && ./handslice-cli \
        --machine '${PROF_PATH}/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json' \
        --process '${PROF_PATH}/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json' \
        --filament '${PROF_PATH}/filament/ECC2/Elegoo PLA @ECC2.json' \
        --resources '${REMOTE_RES_DIR}' \
        --output '${REMOTE}/plate_1.gcode' \
        --no-center --quiet cube_20mm.stl" > "${OUT_DIR}/stats.json"
    time_end=$(date +%s.%N)
    runtime_s=$(awk "BEGIN{printf \"%.1f\", ${time_end} - ${time_start}}")
    echo "   Laufzeit: ${runtime_s} s (Poco X3 Pro, Snapdragon 860)"

    adb pull "${REMOTE}/plate_1.gcode" "${OUT_GCODE}" > /dev/null
fi

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
