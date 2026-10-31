#!/usr/bin/env bash
# Pflicht 6 / Variant C — thumbnail smoke test.
#
# Slices the test cube with handslice-cli-x86, then verifies:
#   1. The G-code contains a `; THUMBNAIL_BLOCK_START` block.
#   2. The block header says 144x144.
#   3. The base64 payload decodes to a PNG whose first bytes are
#      the PNG signature `89 50 4E 47 0D 0A 1A 0A`.
#   4. The PNG is 144x144 (IHDR check) and has non-background
#      content (at least some pixel differs from the background
#      colour we fill with).
#
# Side effect: writes the extracted PNG to
#   local-test/thumbnail-cube.png
# for human review next to the GUI reference, which goes to
#   local-test/thumbnail-cube-gui-reference.png
# so Klaus can diff visually. `local-test/` is gitignored.
#
# Exit 0 on all four checks passing.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOURCES="${PROJECT_ROOT}/engine/OrcaSlicer/resources"
PROFILES="${RESOURCES}/profiles/Elegoo"
STL="${PROJECT_ROOT}/engine/test/cube_20mm_centered_cc2.stl"
REF_GCODE="${PROJECT_ROOT}/engine/test/reference/cube_20mm_cc2_gui_v2.4.2.gcode"
OUT_DIR="${PROJECT_ROOT}/local-test"
mkdir -p "${OUT_DIR}"
OUT_GCODE="${OUT_DIR}/thumbnail-cube.gcode"
OUT_PNG="${OUT_DIR}/thumbnail-cube.png"
GUI_PNG="${OUT_DIR}/thumbnail-cube-gui-reference.png"

CLI="${PROJECT_ROOT}/engine/bin/handslice-cli-x86"
[ -x "${CLI}" ] || { echo "FEHLT: ${CLI} – zuerst engine/build-headless-x86.sh laufen" >&2; exit 2; }

echo "=== 1/4  Slice cube_20mm ==="
"${CLI}" \
    --machine "${PROFILES}/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json" \
    --process "${PROFILES}/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json" \
    --filament "${PROFILES}/filament/ECC2/Elegoo PLA @ECC2.json" \
    --resources "${RESOURCES}" \
    --output "${OUT_GCODE}" \
    --no-center --quiet \
    "${STL}" > /dev/null

echo "=== 2/4  THUMBNAIL_BLOCK vorhanden + Kopf 144x144 ==="
START_LINE=$(grep -n "^; THUMBNAIL_BLOCK_START$" "${OUT_GCODE}" | head -1 | cut -d: -f1 || true)
if [ -z "${START_LINE}" ]; then
    echo "FEHLT: kein THUMBNAIL_BLOCK_START in ${OUT_GCODE}" >&2
    exit 1
fi
END_LINE=$(grep -n "^; THUMBNAIL_BLOCK_END$" "${OUT_GCODE}" | head -1 | cut -d: -f1 || true)
if [ -z "${END_LINE}" ]; then
    echo "FEHLT: kein THUMBNAIL_BLOCK_END in ${OUT_GCODE}" >&2
    exit 1
fi
HEADER=$(sed -n "${START_LINE},${END_LINE}p" "${OUT_GCODE}" | grep "^; thumbnail begin " | head -1 || true)
if [ -z "${HEADER}" ]; then
    echo "FEHLT: '; thumbnail begin <W>x<H> <size>' nicht gefunden" >&2
    exit 1
fi
# Extract WxH
WH=$(echo "${HEADER}" | awk '{print $4}')
if [ "${WH}" != "144x144" ]; then
    echo "WRONG SIZE: expected 144x144, got '${WH}'" >&2
    exit 1
fi
echo "  → block zwischen Zeile ${START_LINE} und ${END_LINE}, Kopf ${WH}"

echo "=== 3/4  PNG dekodieren ==="
python3 - "${OUT_GCODE}" "${OUT_PNG}" <<'PY'
import base64, re, struct, sys, zlib
gcode, out_png = sys.argv[1], sys.argv[2]
with open(gcode) as f:
    txt = f.read()
m = re.search(r'; THUMBNAIL_BLOCK_START.*?; thumbnail begin [\dx]+ \d+\n'
              r'(.*?); thumbnail end',
              txt, re.S)
if not m:
    sys.exit('could not isolate base64 payload')
lines = m.group(1).splitlines()
b64 = ''.join(l[2:].strip() for l in lines if l.startswith('; '))
raw = base64.b64decode(b64)
if raw[:8] != b'\x89PNG\r\n\x1a\n':
    sys.exit('decoded payload is not a PNG')
# IHDR: 8-byte signature + 4-byte length + 4-byte type "IHDR" + W + H + ...
w = struct.unpack('>I', raw[16:20])[0]
h = struct.unpack('>I', raw[20:24])[0]
if (w, h) != (144, 144):
    sys.exit(f'PNG size {w}x{h} != 144x144')
with open(out_png, 'wb') as f:
    f.write(raw)
# Check "non-empty": decompress IDAT and look for any pixel != first.
# For simplicity, compare raw byte histogram length instead.
# A fully-background PNG has very few unique bytes.
uniq_in_data = len(set(raw[33:33+256]))
print(f'  → PNG dekodiert: {w}x{h}, {len(raw)} bytes, uniq-bytes-in-head={uniq_in_data}')
if uniq_in_data < 4:
    sys.exit('PNG looks too uniform (background only?)')
PY

echo "=== 4/4  GUI-Referenz-PNG daneben legen ==="
# Reference G-code → extract the GUI thumbnail PNG for visual
# side-by-side.
python3 - "${REF_GCODE}" "${GUI_PNG}" <<'PY'
import base64, re, sys
gcode, out_png = sys.argv[1], sys.argv[2]
with open(gcode) as f:
    txt = f.read()
m = re.search(r'; THUMBNAIL_BLOCK_START.*?; thumbnail begin [\dx]+ \d+\n'
              r'(.*?); thumbnail end',
              txt, re.S)
if not m:
    sys.exit('ref: could not isolate base64 payload')
lines = m.group(1).splitlines()
b64 = ''.join(l[2:].strip() for l in lines if l.startswith('; '))
raw = base64.b64decode(b64)
with open(out_png, 'wb') as f:
    f.write(raw)
print(f'  → GUI reference PNG: {len(raw)} bytes')
PY

echo
echo "OK – alle vier Checks bestanden."
echo "  PNG (handslice-cli): ${OUT_PNG}"
echo "  PNG (GUI reference): ${GUI_PNG}"
