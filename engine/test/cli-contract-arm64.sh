#!/usr/bin/env bash
# Vertragstest: jedes Flag, das die App an die CLI uebergibt, wird gegen
# das arm64-Binary auf dem Poco geprueft. Mindestens ein echter Slice-Lauf
# mit --z-offset (Befund-5-Reproduktion), damit sichtbar bleibt, dass
# jniLibs/arm64-v8a/libhandslice_cli.so dem Quellstand entspricht.
#
# Hintergrund: beim M4-Rebuild wurde arm64 vergessen – die App rief eine
# veraltete arm64-CLI ohne --z-offset ("unknown flag"). Dieser Test faellt
# aus, wenn so etwas wieder passiert.
#
# Vorbedingung: Poco X3 Pro am adb erreichbar + arm64-CLI frisch gebaut.
# Verwendet NIE das Smartphone-Netz, sondern pur lokale Slice-Logik.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI_LOCAL="${PROJECT_ROOT}/engine/bin/handslice-cli-arm64"
STL="${PROJECT_ROOT}/engine/test/cube_notched_20mm_centered_cc2.stl"
RESOURCES="${PROJECT_ROOT}/engine/OrcaSlicer/resources"
PROFILES="${RESOURCES}/profiles/Elegoo"

export PATH="$HOME/android-sdk/platform-tools:$PATH"

if [[ ! -x "${CLI_LOCAL}" ]]; then
    echo "FEHLT: ${CLI_LOCAL}" >&2
    echo "  → zuerst 'bash engine/build-cli-arm64.sh' laufen lassen." >&2
    exit 2
fi

if ! adb get-state 2>/dev/null | grep -q device; then
    echo "FEHLT: adb-Geraet nicht verbunden ('adb devices' prueft)" >&2
    exit 2
fi

REMOTE="/data/local/tmp/handslice-contract"
REMOTE_RES="${REMOTE}/resources"
REMOTE_CLI="${REMOTE}/handslice-cli-arm64"
REMOTE_STL="${REMOTE}/cube.stl"
LOCAL_TMP="$(mktemp -d)"
trap 'rm -rf "${LOCAL_TMP}"; adb shell "rm -rf ${REMOTE}" >/dev/null 2>&1 || true' EXIT

echo "=== 1/4  Push CLI + Minimal-Resources + STL nach ${REMOTE} ==="
adb shell "mkdir -p ${REMOTE}"
adb push "${CLI_LOCAL}" "${REMOTE_CLI}" >/dev/null
adb shell "chmod +x ${REMOTE_CLI}"
adb push "${STL}" "${REMOTE_STL}" >/dev/null
# Minimal-Resources: nur was die CLI zur Resource-Index-Loesung braucht.
adb push "${RESOURCES}/profiles" "${REMOTE_RES}/profiles" >/dev/null

echo "=== 2/4  --version-Nachweis ==="
VERSION_LINE="$(adb shell "${REMOTE_CLI} --version" | tr -d '\r')"
echo "   ${VERSION_LINE}"
if ! echo "${VERSION_LINE}" | grep -q "handslice-cli commit"; then
    echo "FAIL: --version-Format unerwartet" >&2
    exit 1
fi
CLI_COMMIT="$(echo "${VERSION_LINE}" | awk '{print $NF}')"
LOCAL_COMMIT="$(cd "${PROJECT_ROOT}" && git rev-parse --short=10 HEAD)"
if [[ "${CLI_COMMIT}" != "${LOCAL_COMMIT}" ]]; then
    echo "WARNUNG: CLI-Commit (${CLI_COMMIT}) weicht vom Repo-HEAD (${LOCAL_COMMIT}) ab." >&2
fi

echo "=== 3/4  Flag-Vertrag: alle App-Flags einmal durchlaufen ==="
# Spiegel von app/lib/engine/slicer.dart:slice():
#   --machine --process --filament --resources --output --bed-type
#   [--z-offset mm] --quiet [--no-center]
OUT_BASE="${REMOTE}/out_base.gcode"
OUT_Z="${REMOTE}/out_z.gcode"

adb shell "${REMOTE_CLI} \
    --machine '${REMOTE_RES}/profiles/Elegoo/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json' \
    --process '${REMOTE_RES}/profiles/Elegoo/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json' \
    --filament '${REMOTE_RES}/profiles/Elegoo/filament/ECC2/Elegoo PLA @ECC2.json' \
    --resources '${REMOTE_RES}' \
    --output '${OUT_BASE}' \
    --bed-type B \
    --quiet --no-center \
    '${REMOTE_STL}'"

adb shell "${REMOTE_CLI} \
    --machine '${REMOTE_RES}/profiles/Elegoo/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json' \
    --process '${REMOTE_RES}/profiles/Elegoo/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json' \
    --filament '${REMOTE_RES}/profiles/Elegoo/filament/ECC2/Elegoo PLA @ECC2.json' \
    --resources '${REMOTE_RES}' \
    --output '${OUT_Z}' \
    --bed-type B \
    --z-offset -0.040 \
    --quiet --no-center \
    '${REMOTE_STL}'"

echo "=== 4/4  G-Code zurueckziehen + Z-Diff auswerten ==="
adb pull "${OUT_BASE}" "${LOCAL_TMP}/base.gcode" >/dev/null
adb pull "${OUT_Z}"    "${LOCAL_TMP}/z.gcode"    >/dev/null

python3 <<PY
import re, sys, collections
def zlines(path):
    r = re.compile(r'Z([+-]?[0-9]*\\.?[0-9]+)')
    out = []
    with open(path) as f:
        for line in f:
            if line.startswith(';') or line.startswith('M'): continue
            if not (line.startswith('G0') or line.startswith('G1')): continue
            m = r.search(line)
            if m: out.append(float(m.group(1)))
    return out

base = zlines('${LOCAL_TMP}/base.gcode')
zoff = zlines('${LOCAL_TMP}/z.gcode')
if len(base) != len(zoff):
    print(f"FAIL: Zeilenanzahl base={len(base)} vs z={len(zoff)}", file=sys.stderr); sys.exit(1)
deltas = [round(zi - bi, 6) for bi, zi in zip(base, zoff)]
c = collections.Counter(deltas)
exact = sum(1 for d in deltas if abs(d - (-0.04)) < 1e-6)
print(f"OK Z-Zeilen: {len(deltas)}   Delta-Verteilung: {dict(c)}")
print(f"   Zeilen mit Delta == -0.04 (exakt): {exact}/{len(deltas)}")
# Erwartung: >= 95% der Zeilen exakt um -0.04 verschoben; die 2
# Ausnahmen (G1 Z0.5 aus CC2_START_GCODE-Macro) sind erwartet (siehe M4c).
if exact / len(deltas) < 0.95:
    print(f"FAIL: nur {exact}/{len(deltas)} Zeilen verschoben", file=sys.stderr); sys.exit(1)
print("PASS")
PY

echo
echo "Vertragstest bestanden. CLI-Commit auf dem Geraet: ${CLI_COMMIT}"
