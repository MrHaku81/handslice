#!/usr/bin/env bash
# EXPERIMENTAL — Stufe-3c-Nachtrag: Pro init-Variante (pattern|zero)
# 5x Auryn-Slice am Poco, OHNE HS_DUMP_LAYER env (Heisenbug-Falle
# vermeiden). Per Lauf: gcode SHA, Filament, fill_paths, fill_length_u.

set -euo pipefail

if [[ $# -ne 1 || ( "$1" != "pattern" && "$1" != "zero" ) ]]; then
    echo "Usage: $0 <pattern|zero>" >&2
    exit 2
fi
MODE="$1"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOURCES="${PROJECT_ROOT}/engine/OrcaSlicer/resources"
PROFILES="${RESOURCES}/profiles/Elegoo"
MODEL="${PROJECT_ROOT}/local-test/auryn.stl"
BIN="${PROJECT_ROOT}/engine/bin/handslice-cli-arm64-count-${MODE}"
OUT_DIR="/tmp/stufe-3c-init-${MODE}"
TALLY="${OUT_DIR}/tally.tsv"
REMOTE="/data/local/tmp/handslice-count-${MODE}"

if [[ ! -x "${BIN}" ]]; then
    echo "FEHLT: ${BIN}" >&2; exit 2
fi
if ! adb get-state 2>/dev/null | grep -q device; then
    echo "FEHLT: adb-Geraet nicht verbunden" >&2; exit 2
fi

mkdir -p "${OUT_DIR}"
echo -e "run\tgcode_sha\truntime_s\tfilament_mm\tfill_paths\tfill_length_u" > "${TALLY}"

adb shell "rm -rf ${REMOTE}; mkdir -p ${REMOTE}" > /dev/null
adb push "${BIN}" "${REMOTE}/handslice-cli" > /dev/null
adb shell "chmod 0755 ${REMOTE}/handslice-cli" > /dev/null
adb push "${MODEL}" "${REMOTE}/auryn.stl" > /dev/null
adb shell "mkdir -p ${REMOTE}/resources" > /dev/null
adb push "${RESOURCES}/profiles" "${REMOTE}/resources/profiles" > /dev/null

MACHINE="${REMOTE}/resources/profiles/Elegoo/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json"
PROCESS="${REMOTE}/resources/profiles/Elegoo/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json"
FILAMENT="${REMOTE}/resources/profiles/Elegoo/filament/ECC2/Elegoo PLA @ECC2.json"

set +e   # tolerate gcode-write failures; we only need counters from stderr
for i in 1 2 3 4 5; do
    echo "=== ${MODE} arm64 Lauf ${i}/5 ==="
    STATS_LOCAL="${OUT_DIR}/${i}.stats.json"
    STDERR_LOCAL="${OUT_DIR}/${i}.stderr"
    GCODE_LOCAL="${OUT_DIR}/${i}.gcode"
    GCODE_REMOTE="${REMOTE}/auryn-${i}.gcode"
    t0=$(date +%s.%N)
    adb shell "cd ${REMOTE} && ./handslice-cli \
        --machine '${MACHINE}' --process '${PROCESS}' --filament '${FILAMENT}' \
        --resources '${REMOTE}/resources' --output '${GCODE_REMOTE}' \
        --quiet auryn.stl 2> stderr.txt" > "${STATS_LOCAL}" 2>/dev/null
    t1=$(date +%s.%N)
    rt=$(awk "BEGIN{printf \"%.1f\", ${t1} - ${t0}}")
    adb pull "${REMOTE}/stderr.txt" "${STDERR_LOCAL}" > /dev/null 2>&1 || true
    adb pull "${GCODE_REMOTE}" "${GCODE_LOCAL}" > /dev/null 2>&1 || true
    SHA="n/a"
    MM="n/a"
    if [[ -s "${GCODE_LOCAL}" ]]; then
        SHA=$(sha256sum "${GCODE_LOCAL}" | cut -d' ' -f1)
    fi
    if [[ -s "${STATS_LOCAL}" ]] && head -1 "${STATS_LOCAL}" | grep -q '{'; then
        MM=$(python3 -c "import json; print(f\"{json.load(open('${STATS_LOCAL}'))['total_filament_used_mm']:.2f}\")" 2>/dev/null || echo "n/a")
    fi
    PATHS=$(grep -oE "paths=[0-9]+" "${STDERR_LOCAL}" 2>/dev/null | head -1 | cut -d= -f2)
    LEN=$(grep -oE "length_u=[0-9]+" "${STDERR_LOCAL}" 2>/dev/null | head -1 | cut -d= -f2)
    PATHS="${PATHS:-n/a}"
    LEN="${LEN:-n/a}"
    echo -e "${i}\t${SHA}\t${rt}\t${MM}\t${PATHS}\t${LEN}" | tee -a "${TALLY}"
    adb shell "rm -f ${REMOTE}/auryn-${i}.gcode ${REMOTE}/auryn-${i}.gcode.layer-fill-trace.txt ${REMOTE}/auryn-${i}.gcode.surf-fill-trace.txt" > /dev/null 2>&1
done
set -e

adb shell "rm -rf ${REMOTE}" > /dev/null

echo
echo "=== Tally (${MODE}) ==="
column -t -s $'\t' "${TALLY}"
