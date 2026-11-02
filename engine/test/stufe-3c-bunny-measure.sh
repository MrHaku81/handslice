#!/usr/bin/env bash
# EXPERIMENTAL — Bunny-Varianz-Test mit STANDARD-arm64-Build (ohne
# PolyNode-Fix und ohne count-Instrumentierung). Prueft, ob die
# Nicht-Determinismus bei einem ANDEREN Modell reproduzierbar ist.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOURCES="${PROJECT_ROOT}/engine/OrcaSlicer/resources"
PROFILES="${RESOURCES}/profiles/Elegoo"
MODEL="${PROJECT_ROOT}/local-test/bunny_200mm.stl"
ARM64="${PROJECT_ROOT}/engine/bin/handslice-cli-arm64"
OUT_DIR="/tmp/stufe-3c-bunny"
mkdir -p "${OUT_DIR}"

if ! adb get-state 2>/dev/null | grep -q device; then
    echo "FEHLT: adb-Geraet nicht verbunden" >&2; exit 2
fi

REMOTE="/data/local/tmp/bunny-std"
adb shell "rm -rf ${REMOTE}; mkdir -p ${REMOTE}" > /dev/null
adb push "${ARM64}" "${REMOTE}/handslice-cli" > /dev/null
adb shell "chmod 0755 ${REMOTE}/handslice-cli" > /dev/null
adb push "${MODEL}" "${REMOTE}/bunny.stl" > /dev/null
adb shell "mkdir -p ${REMOTE}/resources" > /dev/null
adb push "${RESOURCES}/profiles" "${REMOTE}/resources/profiles" > /dev/null

MACHINE="${REMOTE}/resources/profiles/Elegoo/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json"
PROCESS="${REMOTE}/resources/profiles/Elegoo/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json"
FILAMENT="${REMOTE}/resources/profiles/Elegoo/filament/ECC2/Elegoo PLA @ECC2.json"

echo "=== Bunny Standard arm64 5x ==="
for i in 1 2 3 4 5; do
    adb shell "cd ${REMOTE} && ./handslice-cli \
        --machine '${MACHINE}' --process '${PROCESS}' --filament '${FILAMENT}' \
        --resources '${REMOTE}/resources' --output '${REMOTE}/bunny-${i}.gcode' \
        --quiet bunny.stl 2> stderr.txt" > "${OUT_DIR}/${i}.stats.json" 2>/dev/null
    adb pull "${REMOTE}/bunny-${i}.gcode" "${OUT_DIR}/${i}.gcode" > /dev/null 2>&1 || true
    SHA="n/a"; MM="n/a"
    if [[ -s "${OUT_DIR}/${i}.gcode" ]]; then
        SHA=$(sha256sum "${OUT_DIR}/${i}.gcode" | cut -d' ' -f1)
    fi
    if head -1 "${OUT_DIR}/${i}.stats.json" 2>/dev/null | grep -q '{'; then
        MM=$(python3 -c "import json; print(f\"{json.load(open('${OUT_DIR}/${i}.stats.json'))['total_filament_used_mm']:.2f}\")" 2>/dev/null || echo n/a)
    fi
    echo "arm64-$i:  SHA=${SHA}  mm=${MM}"
    adb shell "rm -f ${REMOTE}/bunny-${i}.gcode" > /dev/null 2>&1
done
adb shell "rm -rf ${REMOTE}" > /dev/null
