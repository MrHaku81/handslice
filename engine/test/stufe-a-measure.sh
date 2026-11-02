#!/usr/bin/env bash
# EXPERIMENTAL — Mess-Lauf fuer Divergenz-Stufe A (Hypothese A,
# split_solid_surface narrow/mixed-Klassifikation). Nutzt die
# `-count`-Binaries aus `engine/bin/`, die mit HANDSLICE_COUNT_SPLIT_SOLID
# gebaut sind und auf stderr eine `HS_SPLIT_SOLID`-Zeile emittieren.
#
# Ablauf:
#   1. x86 ein Lauf lokal (handslice-cli-x86-count)
#   2. arm64 fuenf Laeufe auf dem Poco X3 Pro via adb
#   3. Pro Lauf: gcode-SHA + narrow/mixed-Counter + XOR-Hashes
#   4. Tabelle in /tmp/stufe-a/tally.tsv
#
# Keine Aenderung am Default-CLI. Keine Pushes.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOURCES="${PROJECT_ROOT}/engine/OrcaSlicer/resources"
PROFILES="${RESOURCES}/profiles/Elegoo"
MODEL="${PROJECT_ROOT}/local-test/auryn.stl"
OUT_DIR="/tmp/stufe-a"
TALLY="${OUT_DIR}/tally.tsv"

X86_CLI="${PROJECT_ROOT}/engine/bin/handslice-cli-x86-count"
ARM64_CLI="${PROJECT_ROOT}/engine/bin/handslice-cli-arm64-count"
REMOTE="/data/local/tmp/handslice-count"

if [[ ! -x "${X86_CLI}" ]]; then
    echo "FEHLT: ${X86_CLI}" >&2; exit 2
fi
if [[ ! -x "${ARM64_CLI}" ]]; then
    echo "FEHLT: ${ARM64_CLI}" >&2; exit 2
fi
if [[ ! -f "${MODEL}" ]]; then
    echo "FEHLT: ${MODEL}" >&2; exit 2
fi

mkdir -p "${OUT_DIR}"
echo -e "run\tplatform\truntime_s\tgcode_sha\tfill_surfs\tfill_paths\tfill_length_u\tcnt_hash\tlen_hash" > "${TALLY}"

MACHINE="${PROFILES}/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json"
PROCESS="${PROFILES}/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json"
FILAMENT="${PROFILES}/filament/ECC2/Elegoo PLA @ECC2.json"

run_counters_from_stderr() {
    # Parse HS_FILL_OUT: surfaces, paths, length_u, count_hash, length_hash.
    local stderr_file="$1"
    grep '^HS_FILL_OUT' "${stderr_file}" | \
        sed -E 's|^HS_FILL_OUT surfaces=([0-9]+) entries=[0-9]+ paths=([0-9]+) length_u=([0-9]+) count_hash=(0x[0-9a-f]+) length_hash=(0x[0-9a-f]+)$|\1\t\2\t\3\t\4\t\5|'
}

echo "=== x86: 1 Lauf (lokal) ==="
GCODE="${OUT_DIR}/x86-1.gcode"
STDERR="${OUT_DIR}/x86-1.stderr"
STATS="${OUT_DIR}/x86-1.stats.json"
t0=$(date +%s.%N)
"${X86_CLI}" \
    --machine "${MACHINE}" \
    --process "${PROCESS}" \
    --filament "${FILAMENT}" \
    --resources "${RESOURCES}" \
    --output "${GCODE}" \
    --quiet "${MODEL}" > "${STATS}" 2> "${STDERR}"
t1=$(date +%s.%N)
rt=$(awk "BEGIN{printf \"%.1f\", ${t1} - ${t0}}")
SHA=$(sha256sum "${GCODE}" | cut -d' ' -f1)
CNT=$(run_counters_from_stderr "${STDERR}")
echo -e "x86-1\tx86\t${rt}\t${SHA}\t${CNT}" | tee -a "${TALLY}"

if ! adb get-state 2>/dev/null | grep -q device; then
    echo "WARN: adb-Geraet nicht verbunden – ueberspringe arm64-Laeufe" >&2
    exit 0
fi

echo "=== Push binary + profiles + model nach Poco ==="
adb shell "rm -rf ${REMOTE}; mkdir -p ${REMOTE}" > /dev/null
adb push "${ARM64_CLI}" "${REMOTE}/handslice-cli" > /dev/null
adb shell "chmod 0755 ${REMOTE}/handslice-cli" > /dev/null
adb push "${MODEL}" "${REMOTE}/auryn.stl" > /dev/null
adb shell "mkdir -p ${REMOTE}/resources" > /dev/null
adb push "${RESOURCES}/profiles" "${REMOTE}/resources/profiles" > /dev/null

RMACHINE="${REMOTE}/resources/profiles/Elegoo/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json"
RPROCESS="${REMOTE}/resources/profiles/Elegoo/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json"
RFILAMENT="${REMOTE}/resources/profiles/Elegoo/filament/ECC2/Elegoo PLA @ECC2.json"

for i in 1 2 3 4 5; do
    echo "=== arm64: Lauf ${i}/5 ==="
    GCODE_REMOTE="${REMOTE}/auryn-${i}.gcode"
    STDERR_LOCAL="${OUT_DIR}/arm64-${i}.stderr"
    STATS_LOCAL="${OUT_DIR}/arm64-${i}.stats.json"
    GCODE_LOCAL="${OUT_DIR}/arm64-${i}.gcode"
    TRACE_REMOTE="${GCODE_REMOTE}.layer-fill-trace.txt"
    TRACE_LOCAL="${OUT_DIR}/arm64-${i}.layer-fill-trace.txt"
    SURF_REMOTE="${GCODE_REMOTE}.surf-fill-trace.txt"
    SURF_LOCAL="${OUT_DIR}/arm64-${i}.surf-fill-trace.txt"
    t0=$(date +%s.%N)
    adb shell "cd ${REMOTE} && ./handslice-cli \
        --machine '${RMACHINE}' --process '${RPROCESS}' --filament '${RFILAMENT}' \
        --resources '${REMOTE}/resources' --output '${GCODE_REMOTE}' \
        --quiet auryn.stl 2> stderr.txt" > "${STATS_LOCAL}"
    t1=$(date +%s.%N)
    rt=$(awk "BEGIN{printf \"%.1f\", ${t1} - ${t0}}")
    adb pull "${REMOTE}/stderr.txt" "${STDERR_LOCAL}" > /dev/null
    adb pull "${GCODE_REMOTE}" "${GCODE_LOCAL}" > /dev/null
    adb pull "${TRACE_REMOTE}" "${TRACE_LOCAL}" > /dev/null 2>&1 || true
    adb pull "${SURF_REMOTE}" "${SURF_LOCAL}" > /dev/null 2>&1 || true
    SHA=$(sha256sum "${GCODE_LOCAL}" | cut -d' ' -f1)
    CNT=$(run_counters_from_stderr "${STDERR_LOCAL}")
    echo -e "arm64-${i}\tarm64\t${rt}\t${SHA}\t${CNT}" | tee -a "${TALLY}"
done

adb shell "rm -rf ${REMOTE}" > /dev/null

echo
echo "=== Tally ==="
column -t -s $'\t' "${TALLY}"
echo
echo "Tally-Datei: ${TALLY}"
