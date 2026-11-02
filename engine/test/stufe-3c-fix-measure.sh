#!/usr/bin/env bash
# EXPERIMENTAL — Fix-Test fuer PolyNode-Ctor-Init.
# Auryn: x86 1x lokal (count-fix), arm64 5x am Poco (count-fix).
# Dann Referenztest cube mit beiden Binaries.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOURCES="${PROJECT_ROOT}/engine/OrcaSlicer/resources"
PROFILES="${RESOURCES}/profiles/Elegoo"
AURYN="${PROJECT_ROOT}/local-test/auryn.stl"
CUBE="${PROJECT_ROOT}/engine/test/cube_20mm_centered_cc2.stl"
X86="${PROJECT_ROOT}/engine/bin/handslice-cli-x86-count-fix"
ARM64="${PROJECT_ROOT}/engine/bin/handslice-cli-arm64-count-fix"
OUT_DIR="/tmp/stufe-3c-fix"
mkdir -p "${OUT_DIR}"

MACHINE="${PROFILES}/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json"
PROCESS="${PROFILES}/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json"
FILAMENT="${PROFILES}/filament/ECC2/Elegoo PLA @ECC2.json"

# 1. x86 Auryn (1x)
echo "=== x86 Auryn 1x ==="
"${X86}" \
    --machine "${MACHINE}" --process "${PROCESS}" --filament "${FILAMENT}" \
    --resources "${RESOURCES}" --output "${OUT_DIR}/x86-auryn.gcode" \
    --quiet "${AURYN}" > "${OUT_DIR}/x86-auryn.stats.json" 2> "${OUT_DIR}/x86-auryn.stderr"
X86_SHA=$(sha256sum "${OUT_DIR}/x86-auryn.gcode" | cut -d' ' -f1)
X86_MM=$(python3 -c "import json; print(f\"{json.load(open('${OUT_DIR}/x86-auryn.stats.json'))['total_filament_used_mm']:.2f}\")")
X86_PATHS=$(grep -oE "paths=[0-9]+" "${OUT_DIR}/x86-auryn.stderr" | head -1 | cut -d= -f2)
X86_LEN=$(grep -oE "length_u=[0-9]+" "${OUT_DIR}/x86-auryn.stderr" | head -1 | cut -d= -f2)
echo "x86:      SHA=${X86_SHA}  mm=${X86_MM}  paths=${X86_PATHS}  length_u=${X86_LEN}"

# 2. arm64 Auryn 5x
if ! adb get-state 2>/dev/null | grep -q device; then
    echo "FEHLT: adb-Geraet nicht verbunden" >&2; exit 2
fi
REMOTE="/data/local/tmp/handslice-count-fix"
adb shell "rm -rf ${REMOTE}; mkdir -p ${REMOTE}" > /dev/null
adb push "${ARM64}" "${REMOTE}/handslice-cli" > /dev/null
adb shell "chmod 0755 ${REMOTE}/handslice-cli" > /dev/null
adb push "${AURYN}" "${REMOTE}/auryn.stl" > /dev/null
adb shell "mkdir -p ${REMOTE}/resources" > /dev/null
adb push "${RESOURCES}/profiles" "${REMOTE}/resources/profiles" > /dev/null

RMACHINE="${REMOTE}/resources/profiles/Elegoo/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json"
RPROCESS="${REMOTE}/resources/profiles/Elegoo/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json"
RFILAMENT="${REMOTE}/resources/profiles/Elegoo/filament/ECC2/Elegoo PLA @ECC2.json"

echo ""
echo "=== arm64 Auryn 5x ==="
for i in 1 2 3 4 5; do
    adb shell "cd ${REMOTE} && ./handslice-cli \
        --machine '${RMACHINE}' --process '${RPROCESS}' --filament '${RFILAMENT}' \
        --resources '${REMOTE}/resources' --output '${REMOTE}/auryn-${i}.gcode' \
        --quiet auryn.stl 2> stderr.txt" > "${OUT_DIR}/arm64-${i}.stats.json" 2>/dev/null
    adb pull "${REMOTE}/stderr.txt" "${OUT_DIR}/arm64-${i}.stderr" > /dev/null 2>&1 || true
    adb pull "${REMOTE}/auryn-${i}.gcode" "${OUT_DIR}/arm64-${i}.gcode" > /dev/null 2>&1 || true
    SHA="n/a"; MM="n/a"
    if [[ -s "${OUT_DIR}/arm64-${i}.gcode" ]]; then
        SHA=$(sha256sum "${OUT_DIR}/arm64-${i}.gcode" | cut -d' ' -f1)
    fi
    if head -1 "${OUT_DIR}/arm64-${i}.stats.json" 2>/dev/null | grep -q '{'; then
        MM=$(python3 -c "import json; print(f\"{json.load(open('${OUT_DIR}/arm64-${i}.stats.json'))['total_filament_used_mm']:.2f}\")" 2>/dev/null || echo n/a)
    fi
    PATHS=$(grep -oE "paths=[0-9]+" "${OUT_DIR}/arm64-${i}.stderr" 2>/dev/null | head -1 | cut -d= -f2)
    LEN=$(grep -oE "length_u=[0-9]+" "${OUT_DIR}/arm64-${i}.stderr" 2>/dev/null | head -1 | cut -d= -f2)
    PATHS="${PATHS:-n/a}"; LEN="${LEN:-n/a}"
    echo "arm64-$i:  SHA=${SHA}  mm=${MM}  paths=${PATHS}  length_u=${LEN}"
    adb shell "rm -f ${REMOTE}/auryn-${i}.gcode ${REMOTE}/auryn-${i}.gcode.layer-fill-trace.txt ${REMOTE}/auryn-${i}.gcode.surf-fill-trace.txt" > /dev/null 2>&1
done
adb shell "rm -rf ${REMOTE}" > /dev/null

echo ""
echo "=== Ref-Test Wuerfel mit fixed x86 Binary ==="
"${X86}" \
    --machine "${MACHINE}" --process "${PROCESS}" --filament "${FILAMENT}" \
    --resources "${RESOURCES}" --output "${OUT_DIR}/x86-cube.gcode" \
    --no-center --quiet "${CUBE}" > "${OUT_DIR}/x86-cube.stats.json" 2>/dev/null
# Extract EXECUTABLE_BLOCK the same way run-reference-test.sh does
awk '/^; EXECUTABLE_BLOCK_START/,/^; EXECUTABLE_BLOCK_END/' "${OUT_DIR}/x86-cube.gcode" > "${OUT_DIR}/x86-cube.exec.gcode"
CUBE_SHA=$(sha256sum "${OUT_DIR}/x86-cube.exec.gcode" | cut -d' ' -f1)
CUBE_LINES=$(wc -l < "${OUT_DIR}/x86-cube.exec.gcode")
echo "EXECUTABLE_BLOCK: ${CUBE_SHA}  (${CUBE_LINES} lines)"
echo "Reference:        92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d  (8479 lines)"
if [[ "${CUBE_SHA}" == "92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d" ]]; then
    echo "  -> IDENTISCH (fix changes nothing in cube slice)"
else
    echo "  -> UNTERSCHIEDLICH (fix changes cube slice)"
fi
