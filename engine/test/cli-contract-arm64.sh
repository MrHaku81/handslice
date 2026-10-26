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
echo "=== 6  Filament-Overrides (Phase 4.4) ==="
# Belegen, dass pro-Fach-Overrides auf Filament-opt_keys im G-Code
# ankommen. PETG-Basisprofil (A1), bed-type B:
#   - nozzle_temperature=260 → "M104 S260 ; set nozzle temperature"
#   - hot_plate_temp_initial_layer=88 → "M190 S88 A" am ersten Layer
#   - retraction_length=2.4 → "G1 E-2.4" statt Baseline-0.728
# Baseline ohne Overrides muss byte-gleich zu einem zweiten Baseline-
# Lauf sein (Null-Change-Garantie, uebernommen aus Phase 4.3).
FIL_PETG="${REMOTE_RES}/profiles/Elegoo/filament/ECC2/Elegoo PETG @ECC2.json"
OUT_FBASE="${REMOTE}/fbase.gcode"
OUT_FBASE2="${REMOTE}/fbase2.gcode"
OUT_FN="${REMOTE}/fn.gcode"
OUT_FB="${REMOTE}/fb.gcode"
OUT_FR="${REMOTE}/fr.gcode"
adb shell "${REMOTE_CLI} --machine '${MACHINE}' --process '${PROCESS}' --filament '${FIL_PETG}' --resources '${REMOTE_RES}' --output '${OUT_FBASE}'  --bed-type B --quiet --no-center '${REMOTE_STL}'" > /dev/null
adb shell "${REMOTE_CLI} --machine '${MACHINE}' --process '${PROCESS}' --filament '${FIL_PETG}' --resources '${REMOTE_RES}' --output '${OUT_FBASE2}' --bed-type B --quiet --no-center '${REMOTE_STL}'" > /dev/null
adb shell "${REMOTE_CLI} --machine '${MACHINE}' --process '${PROCESS}' --filament '${FIL_PETG}' --resources '${REMOTE_RES}' --output '${OUT_FN}'     --bed-type B --overrides '{\"nozzle_temperature\":\"260\"}' --quiet --no-center '${REMOTE_STL}'" > /dev/null
adb shell "${REMOTE_CLI} --machine '${MACHINE}' --process '${PROCESS}' --filament '${FIL_PETG}' --resources '${REMOTE_RES}' --output '${OUT_FB}'     --bed-type B --overrides '{\"hot_plate_temp_initial_layer\":\"88\"}' --quiet --no-center '${REMOTE_STL}'" > /dev/null
adb shell "${REMOTE_CLI} --machine '${MACHINE}' --process '${PROCESS}' --filament '${FIL_PETG}' --resources '${REMOTE_RES}' --output '${OUT_FR}'     --bed-type B --overrides '{\"retraction_length\":\"2.4\"}' --quiet --no-center '${REMOTE_STL}'" > /dev/null
adb pull "${OUT_FBASE}"  "${LOCAL_TMP}/fbase.gcode"  >/dev/null
adb pull "${OUT_FBASE2}" "${LOCAL_TMP}/fbase2.gcode" >/dev/null
adb pull "${OUT_FN}"     "${LOCAL_TMP}/fn.gcode"     >/dev/null
adb pull "${OUT_FB}"     "${LOCAL_TMP}/fb.gcode"     >/dev/null
adb pull "${OUT_FR}"     "${LOCAL_TMP}/fr.gcode"     >/dev/null

python3 <<PY
import sys, hashlib, re
def md5(p):
    h = hashlib.md5(); h.update(open(p,'rb').read()); return h.hexdigest()
mb1 = md5('${LOCAL_TMP}/fbase.gcode')
mb2 = md5('${LOCAL_TMP}/fbase2.gcode')
if mb1 != mb2:
    print(f'FAIL: zwei Baseline-Laeufe nicht byte-identisch ({mb1} vs {mb2})', file=sys.stderr); sys.exit(1)
print(f'  Baseline byte-identisch (md5 {mb1[:10]}…)')

def grep_lines(p, pattern):
    r = re.compile(pattern)
    return [ln.rstrip() for ln in open(p) if r.search(ln)]

# 1) nozzle_temperature=260 muss als M104 S260 (set nozzle temperature) auftauchen.
nozzle_lines = grep_lines('${LOCAL_TMP}/fn.gcode', r'^M104 S\d+ ; set nozzle temperature')
if not any('S260' in l for l in nozzle_lines):
    print('FAIL: nozzle_temperature=260 nicht als M104 S260 im G-Code', file=sys.stderr)
    print('   gefundene set-Zeilen:', nozzle_lines[:3], file=sys.stderr); sys.exit(1)
print(f'  nozzle=260: {next(l for l in nozzle_lines if "S260" in l)}')

# 2) hot_plate_temp_initial_layer=88 muss als M190 S88 am ersten Layer (vor dem Druck) stehen.
mb_lines = grep_lines('${LOCAL_TMP}/fb.gcode', r'^M190 S\d+ A')
if not any('S88' in l for l in mb_lines):
    print('FAIL: hot_plate_temp_initial_layer=88 nicht als M190 S88 A im G-Code', file=sys.stderr)
    print('   gefundene M190 S* A Zeilen:', mb_lines[:3], file=sys.stderr); sys.exit(1)
print(f'  bed B initial=88: {next(l for l in mb_lines if "S88" in l)}')

# 3) retraction_length=2.4 muss sich in G1 E-2.4-Zuegen zeigen.
retract_e = set(re.findall(r'G1 E(-[0-9.]+)', open('${LOCAL_TMP}/fr.gcode').read()))
if '-2.4' not in retract_e and '-2.400' not in retract_e:
    print('FAIL: retraction_length=2.4 nicht als G1 E-2.4 im G-Code', file=sys.stderr)
    print('   gefundene retract-Werte:', sorted(retract_e)[:6], file=sys.stderr); sys.exit(1)
print(f'  retract=2.4: G1 E-2.4 in retract-Zuegen gefunden')
print('PASS (Filament-Overrides mit G-Code-Markern belegt)')
PY

echo
echo "Vertragstest bestanden. CLI-Commit auf dem Geraet: ${CLI_COMMIT}"
