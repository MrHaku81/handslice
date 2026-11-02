#!/usr/bin/env bash
# EXPERIMENTAL — x86 Auryn-Slice unter Valgrind Memcheck mit
# --track-origins=yes. Erzeugt engine-fillpath-fokussiertes Log.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOURCES="${PROJECT_ROOT}/engine/OrcaSlicer/resources"
PROFILES="${RESOURCES}/profiles/Elegoo"
MODEL="${PROJECT_ROOT}/local-test/auryn.stl"
BIN="${PROJECT_ROOT}/engine/bin/handslice-cli-x86-debug"
OUT_DIR="/tmp/stufe-3c-valgrind"
LOG="${OUT_DIR}/memcheck.log"
GCODE="${OUT_DIR}/auryn.gcode"

if [[ ! -x "${BIN}" ]]; then
    echo "FEHLT: ${BIN}" >&2; exit 2
fi
if ! command -v valgrind > /dev/null; then
    echo "FEHLT: valgrind nicht im PATH" >&2; exit 2
fi

mkdir -p "${OUT_DIR}"

MACHINE="${PROFILES}/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json"
PROCESS="${PROFILES}/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json"
FILAMENT="${PROFILES}/filament/ECC2/Elegoo PLA @ECC2.json"

# Threads=1 um Thread-Race-Noise bei Valgrind zu reduzieren. --fair-sched=yes
# fuer vorhersehbare TBB-Thread-Reihenfolge. --num-callers=20 fuer tiefe
# Backtraces. --undef-value-errors=yes ist default an. --expensive-definedness-checks
# verringert false positives in Vektor-Code.
echo "=== Starte Valgrind Memcheck auf Auryn (threads=1) ==="
echo "Log: ${LOG}"
echo "Erwartete Laufzeit: 20-60 Minuten"
echo

exec valgrind \
    --tool=memcheck \
    --track-origins=yes \
    --num-callers=20 \
    --error-limit=no \
    --expensive-definedness-checks=yes \
    --log-file="${LOG}" \
    "${BIN}" \
    --machine "${MACHINE}" --process "${PROCESS}" --filament "${FILAMENT}" \
    --resources "${RESOURCES}" --output "${GCODE}" \
    --threads 1 --quiet "${MODEL}"
