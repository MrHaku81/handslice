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

MACHINE="${REMOTE_RES}/profiles/Elegoo/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json"
PROCESS="${REMOTE_RES}/profiles/Elegoo/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json"
FILAMENT="${REMOTE_RES}/profiles/Elegoo/filament/ECC2/Elegoo PLA @ECC2.json"

echo "=== 3/4  Flag-Vertrag: alle App-Flags einmal durchlaufen ==="
OUT_BASE="${REMOTE}/out_base.gcode"
OUT_Z="${REMOTE}/out_z.gcode"
adb shell "${REMOTE_CLI} --machine '${MACHINE}' --process '${PROCESS}' --filament '${FILAMENT}' --resources '${REMOTE_RES}' --output '${OUT_BASE}' --bed-type B --quiet --no-center '${REMOTE_STL}'" > "${LOCAL_TMP}/base-stats.json"
adb shell "${REMOTE_CLI} --machine '${MACHINE}' --process '${PROCESS}' --filament '${FILAMENT}' --resources '${REMOTE_RES}' --output '${OUT_Z}'    --bed-type B --z-offset -0.040 --quiet --no-center '${REMOTE_STL}'" > /dev/null

echo "=== 4/4  Z-Diff gegen Baseline ==="
adb pull "${OUT_BASE}" "${LOCAL_TMP}/base.gcode" >/dev/null
adb pull "${OUT_Z}"    "${LOCAL_TMP}/z.gcode"    >/dev/null
python3 <<PY
import re, sys, collections
def zlines(path):
    r = re.compile(r'Z([+-]?[0-9]*\\.?[0-9]+)')
    out = []
    for line in open(path):
        if line.startswith(';') or line.startswith('M'): continue
        if not (line.startswith('G0') or line.startswith('G1')): continue
        m = r.search(line)
        if m: out.append(float(m.group(1)))
    return out
base = zlines('${LOCAL_TMP}/base.gcode'); zoff = zlines('${LOCAL_TMP}/z.gcode')
if len(base) != len(zoff):
    print(f'FAIL: Zeilenzahl base={len(base)} vs z={len(zoff)}', file=sys.stderr); sys.exit(1)
deltas = [round(zi - bi, 6) for bi, zi in zip(base, zoff)]
exact = sum(1 for d in deltas if abs(d - (-0.04)) < 1e-6)
print(f'   Zeilen Delta == -0.04 exakt: {exact}/{len(deltas)}')
if exact / len(deltas) < 0.95:
    print('FAIL: zu wenig Zeilen verschoben', file=sys.stderr); sys.exit(1)
print('PASS (Z-Offset)')
PY

echo
echo "=== 5  --overrides-Vertrag (Phase 4.3) ==="
# Metrik: Orcas 'total_filament_used_mm' aus dem Stats-JSON (nur
# Extrusion mit XY-Bewegung). Nicht die rohe E-Summe im G-Code, die
# zusaetzlich die Prime-Pumpen nach Retract mitzaehlt und je nach
# Retract-Anzahl aufgeblaeht ist.

# Kombi: alle drei Overrides zusammen
OUT_OVR="${REMOTE}/out_overrides.gcode"
adb shell "${REMOTE_CLI} --machine '${MACHINE}' --process '${PROCESS}' --filament '${FILAMENT}' --resources '${REMOTE_RES}' --output '${OUT_OVR}' --bed-type B --overrides '{\"layer_height\":\"0.28\",\"wall_loops\":\"4\",\"sparse_infill_density\":\"40%\"}' --quiet --no-center '${REMOTE_STL}'" > "${LOCAL_TMP}/ovr-stats.json"
adb pull "${OUT_OVR}" "${LOCAL_TMP}/ovr.gcode" >/dev/null

# Einzeln
for pair in "L:layer_height:0.28" "W:wall_loops:4" "I:sparse_infill_density:40%"; do
    tag="${pair%%:*}"; rest="${pair#*:}"
    key="${rest%%:*}"; val="${rest#*:}"
    adb shell "${REMOTE_CLI} --machine '${MACHINE}' --process '${PROCESS}' --filament '${FILAMENT}' --resources '${REMOTE_RES}' --output '${REMOTE}/single-${tag}.gcode' --bed-type B --overrides '{\"${key}\":\"${val}\"}' --quiet --no-center '${REMOTE_STL}'" > "${LOCAL_TMP}/single-${tag}.json"
    adb pull "${REMOTE}/single-${tag}.gcode" "${LOCAL_TMP}/single-${tag}.gcode" >/dev/null
done

python3 <<PY
import json, sys
def z_count(p):
    n = 0
    for line in open(p):
        if line.startswith('G1 Z'): n += 1
    return n
def feature_lines(p, feat):
    c = 0; inside = False
    for line in open(p):
        s = line.rstrip()
        if s.startswith(';TYPE:'):
            inside = (s == f';TYPE:{feat}')
            continue
        if inside and (s.startswith('G1 ') or s.startswith('G0 ')):
            c += 1
    return c
sb = json.load(open('${LOCAL_TMP}/base-stats.json'))
so = json.load(open('${LOCAL_TMP}/ovr-stats.json'))
sL = json.load(open('${LOCAL_TMP}/single-L.json'))
sW = json.load(open('${LOCAL_TMP}/single-W.json'))
sI = json.load(open('${LOCAL_TMP}/single-I.json'))

zb = z_count('${LOCAL_TMP}/base.gcode')
zL = z_count('${LOCAL_TMP}/single-L.gcode')
wb = feature_lines('${LOCAL_TMP}/base.gcode', 'Outer wall') + feature_lines('${LOCAL_TMP}/base.gcode', 'Inner wall')
wW = feature_lines('${LOCAL_TMP}/single-W.gcode', 'Outer wall') + feature_lines('${LOCAL_TMP}/single-W.gcode', 'Inner wall')
ib = feature_lines('${LOCAL_TMP}/base.gcode', 'Sparse infill')
iI = feature_lines('${LOCAL_TMP}/single-I.gcode', 'Sparse infill')

print(f'  Metrik aus Stats-JSON: total_filament_used_mm (Orca-kanonisch).')
print(f'  baseline:              Z-moves={zb}  wall-lines={wb}  infill-lines={ib}  filament={sb["total_filament_used_mm"]:.1f}mm')
print(f'  nur layer_height=0.28: Z-moves={zL}            filament={sL["total_filament_used_mm"]:.1f}mm')
print(f'  nur wall_loops=4:                  wall-lines={wW}  filament={sW["total_filament_used_mm"]:.1f}mm')
print(f'  nur sparse_infill=40%:                 infill-lines={iI}  filament={sI["total_filament_used_mm"]:.1f}mm')
print(f'  alle drei zusammen:                                         filament={so["total_filament_used_mm"]:.1f}mm')

fail = []
if not (zL < zb * 0.9):
    fail.append(f'layer_height=0.28: Z-moves {zL} nicht deutlich < {zb}')
if not (wW > wb * 1.3):
    fail.append(f'wall_loops=4: wall-lines {wW} nicht >30% ueber {wb}')
if not (iI > ib * 1.5):
    fail.append(f'sparse_infill_density=40%: infill-lines {iI} nicht >50% ueber {ib}')
if not (so['total_filament_used_mm'] > sb['total_filament_used_mm'] * 1.3):
    fail.append(f'Kombi: filament {so["total_filament_used_mm"]:.1f} nicht >30% ueber {sb["total_filament_used_mm"]:.1f}')
if fail:
    for f in fail: print('FAIL:', f, file=sys.stderr)
    sys.exit(1)
print('PASS (Kombi + Einzeln)')
PY

echo
echo "=== 6  Ungueltiger Override-Key wird abgewiesen ==="
set +e
err=$(adb shell "${REMOTE_CLI} --machine '${MACHINE}' --process '${PROCESS}' --filament '${FILAMENT}' --resources '${REMOTE_RES}' --output '${REMOTE}/x.gcode' --bed-type B --overrides '{\"nonexistent_key_xy\":\"5\"}' --quiet --no-center '${REMOTE_STL}'" 2>&1)
rc=$?
set -e
echo "   $err" | tail -1
if ! echo "$err" | grep -q "unknown option 'nonexistent_key_xy'"; then
    echo "FAIL: unerwartete Fehlermeldung" >&2; exit 1
fi
if [[ "$rc" == "0" ]]; then
    echo "FAIL: Exit-Code haette != 0 sein muessen" >&2; exit 1
fi
echo "PASS (exit=$rc)"

echo
echo "=== 7  Plausibilitaetsfehler aus libslic3r sauber abgefangen ==="
# layer_height groesser als jede sinnvolle Nozzle-Groesse ist bei
# Orcas Preflight (Print::validate) ein Konfliktfall – wir setzen
# layer_height = 2.0 (max_literal: 1.0 im Schema; aber auch strukturell
# unsinnig fuer eine 0.4er Duese). Erwartet: definierter Exit-Code,
# lesbare Fehlermeldung, KEIN "terminate called" / abort.
set +e
err=$(adb shell "${REMOTE_CLI} --machine '${MACHINE}' --process '${PROCESS}' --filament '${FILAMENT}' --resources '${REMOTE_RES}' --output '${REMOTE}/x.gcode' --bed-type B --overrides '{\"layer_height\":\"2.0\"}' --quiet --no-center '${REMOTE_STL}'" 2>&1)
rc=$?
set -e
echo "   stderr tail:"; echo "$err" | tail -3 | sed 's/^/     /'
if echo "$err" | grep -qi "terminate called\|aborted\|abort"; then
    echo "FAIL: CLI hat terminate/abort statt sauberer Fehlermeldung" >&2; exit 1
fi
if ! echo "$err" | grep -qi "handslice-cli: .*\(Slic3r\|Slicing\|Konfiguration\|Flow\|invalid\|validate\|layer_height\|spacing\)"; then
    echo "FAIL: keine erkennbare Validate-Meldung im stderr" >&2; exit 1
fi
if [[ "$rc" == "0" ]]; then
    echo "FAIL: Exit-Code haette != 0 sein muessen" >&2; exit 1
fi
echo "PASS (exit=$rc)"

echo
echo "Vertragstest bestanden. CLI-Commit auf dem Geraet: ${CLI_COMMIT}"
