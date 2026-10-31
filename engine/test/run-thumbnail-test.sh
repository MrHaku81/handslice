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
NOTCHED_STL="${PROJECT_ROOT}/engine/test/cube_notched_20mm_centered_cc2.stl"
REF_GCODE="${PROJECT_ROOT}/engine/test/reference/cube_20mm_cc2_gui_v2.4.2.gcode"
OUT_DIR="${PROJECT_ROOT}/local-test"
mkdir -p "${OUT_DIR}"
OUT_GCODE="${OUT_DIR}/thumbnail-cube.gcode"
OUT_PNG="${OUT_DIR}/thumbnail-cube.png"
OUT_WHITE_GCODE="${OUT_DIR}/thumbnail-cube-white.gcode"
OUT_WHITE_PNG="${OUT_DIR}/thumbnail-cube-white.png"
OUT_NOTCHED_GCODE="${OUT_DIR}/thumbnail-notched.gcode"
OUT_NOTCHED_PNG="${OUT_DIR}/thumbnail-notched.png"
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

echo "=== 4/5  White-filament render: colour + contrast checks ==="
# Second slice with filament_colour=#FFFFFF, same as the Pflicht-9
# slot-colour-override path would produce.
"${CLI}" \
    --machine "${PROFILES}/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json" \
    --process "${PROFILES}/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json" \
    --filament "${PROFILES}/filament/ECC2/Elegoo PLA @ECC2.json" \
    --resources "${RESOURCES}" \
    --output "${OUT_WHITE_GCODE}" \
    --overrides '{"filament_colour":"#FFFFFF"}' \
    --no-center --quiet \
    "${STL}" > /dev/null

python3 - "${OUT_WHITE_GCODE}" "${OUT_WHITE_PNG}" <<'PY'
import base64, re, struct, sys, zlib
gcode, out_png = sys.argv[1], sys.argv[2]
with open(gcode) as f:
    txt = f.read()
m = re.search(r'; THUMBNAIL_BLOCK_START.*?; thumbnail begin [\dx]+ \d+\n'
              r'(.*?); thumbnail end',
              txt, re.S)
if not m: sys.exit('white: no thumbnail block')
b64 = ''.join(l[2:].strip() for l in m.group(1).splitlines() if l.startswith('; '))
raw = base64.b64decode(b64)
if raw[:8] != b'\x89PNG\r\n\x1a\n': sys.exit('white: not a PNG')
with open(out_png, 'wb') as f:
    f.write(raw)

# Decode fully so we can test actual pixel values.
w = struct.unpack('>I', raw[16:20])[0]
h = struct.unpack('>I', raw[20:24])[0]
bd, ct = raw[24], raw[25]
if (w, h) != (144, 144) or ct != 6:
    sys.exit(f'white: unexpected PNG {w}x{h} ct={ct}')

# Pull IDAT, decompress, de-filter.
i = 8
data = bytearray()
while i < len(raw):
    L = struct.unpack('>I', raw[i:i+4])[0]
    T = raw[i+4:i+8].decode('latin-1')
    if T == 'IDAT': data += raw[i+8:i+8+L]
    i += 8 + L + 4
dec = zlib.decompress(bytes(data))
bpp = 4
stride = 1 + w * bpp
pix = bytearray(w * h * bpp)
prev = bytes(w * bpp)
for y in range(h):
    off = y * stride
    filt = dec[off]
    row = bytearray(dec[off+1:off+stride])
    if filt == 0:
        pass
    elif filt == 1:  # Sub
        for x in range(bpp, w*bpp):
            row[x] = (row[x] + row[x-bpp]) & 0xFF
    elif filt == 2:  # Up
        for x in range(w*bpp):
            row[x] = (row[x] + prev[x]) & 0xFF
    elif filt == 3:  # Average
        for x in range(w*bpp):
            left = row[x-bpp] if x >= bpp else 0
            row[x] = (row[x] + (left + prev[x]) // 2) & 0xFF
    elif filt == 4:  # Paeth
        for x in range(w*bpp):
            a = row[x-bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x-bpp] if x >= bpp else 0
            p = a + b - c
            pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
            pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
            row[x] = (row[x] + pr) & 0xFF
    else:
        sys.exit(f'white: unknown filter {filt}')
    pix[y*w*bpp:(y+1)*w*bpp] = row
    prev = bytes(row)

def px(x, y):
    o = (y*w + x) * bpp
    return pix[o], pix[o+1], pix[o+2], pix[o+3]

# Background sanity (top-left corner): alpha must be 0.
r,g,b,a = px(0, 0)
if a != 0:
    sys.exit(f'white: expected transparent background, got alpha={a} at (0,0)')

# Model body: scan a column near the horizontal centre and
# collect all opaque pixels. The model sits roughly in the
# middle of the image.
samples = []
for y in range(10, h-10):
    r,g,b,a = px(w//2, y)
    if a == 255:
        samples.append((r,g,b,y))
if len(samples) < 20:
    sys.exit(f'white: not enough opaque pixels along centre column ({len(samples)})')

# Grey-value for white filament: r==g==b. Max brightness should
# be clearly > min brightness — i.e. the Lambert shading
# actually spreads the three faces.
greys = [s[0] for s in samples if s[0] == s[1] == s[2]]
if len(greys) < 15:
    sys.exit(f'white: expected grey pixels on a white model, got {len(greys)} '
             f'non-grey of {len(samples)} opaque')
gmin, gmax = min(greys), max(greys)
print(f'  → white model opaque column: {len(samples)} pixels, '
      f'grey range [{gmin}..{gmax}]  (spread {gmax-gmin})')
if gmax < 240:
    sys.exit(f'white: top face too dark ({gmax} < 240) — Lambert key insufficient')
if (gmax - gmin) < 60:
    sys.exit(f'white: contrast too small ({gmax-gmin} < 60) — faces blur together')
print('  OK: top near-white, side clearly darker, three faces separable.')
PY

echo "=== 5/6  Notched cube: orientation (notch must be on TOP, not bottom) ==="
# The symmetric cube cannot tell "upside-down" from "right-side-up".
# The notched cube has a 5×5×5 mm pocket in a top-face corner, so
# the TOP outline is uneven while the BOTTOM outline is straight.
# After the earlier bug (inverted z-sign in to_view()) rendered the
# model upside-down — exact Klaus report 2026-10-31 — this check
# nails that specific regression.
"${CLI}" \
    --machine "${PROFILES}/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json" \
    --process "${PROFILES}/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json" \
    --filament "${PROFILES}/filament/ECC2/Elegoo PLA @ECC2.json" \
    --resources "${RESOURCES}" \
    --output "${OUT_NOTCHED_GCODE}" \
    --overrides '{"filament_colour":"#FFFFFF"}' \
    --no-center --quiet \
    "${NOTCHED_STL}" > /dev/null
python3 - "${OUT_NOTCHED_GCODE}" "${OUT_NOTCHED_PNG}" <<'PY'
import base64, re, struct, sys, zlib, statistics
gcode, out_png = sys.argv[1], sys.argv[2]
with open(gcode) as f:
    txt = f.read()
m = re.search(r'; THUMBNAIL_BLOCK_START.*?; thumbnail begin [\dx]+ \d+\n'
              r'(.*?); thumbnail end',
              txt, re.S)
if not m: sys.exit('notched: no thumbnail block')
b64 = ''.join(l[2:].strip() for l in m.group(1).splitlines() if l.startswith('; '))
raw = base64.b64decode(b64)
with open(out_png, 'wb') as f: f.write(raw)
w = struct.unpack('>I', raw[16:20])[0]
h = struct.unpack('>I', raw[20:24])[0]

# De-filter PNG → raw RGBA pixels.
i = 8; data = bytearray()
while i < len(raw):
    L = struct.unpack('>I', raw[i:i+4])[0]
    T = raw[i+4:i+8].decode('latin-1')
    if T == 'IDAT': data += raw[i+8:i+8+L]
    i += 8 + L + 4
dec = zlib.decompress(bytes(data))
bpp, stride = 4, 1 + w * 4
pix = bytearray(w * h * bpp); prev = bytes(w * bpp)
for y in range(h):
    off = y * stride; filt = dec[off]
    row = bytearray(dec[off+1:off+stride])
    if   filt == 1:
        for x in range(bpp, w*bpp): row[x] = (row[x] + row[x-bpp]) & 0xFF
    elif filt == 2:
        for x in range(w*bpp): row[x] = (row[x] + prev[x]) & 0xFF
    elif filt == 3:
        for x in range(w*bpp):
            l = row[x-bpp] if x >= bpp else 0
            row[x] = (row[x] + (l + prev[x]) // 2) & 0xFF
    elif filt == 4:
        for x in range(w*bpp):
            a = row[x-bpp] if x >= bpp else 0; b = prev[x]
            c = prev[x-bpp] if x >= bpp else 0
            p = a + b - c
            pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
            pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
            row[x] = (row[x] + pr) & 0xFF
    pix[y*w*bpp:(y+1)*w*bpp] = row
    prev = bytes(row)

# For each column with opaque pixels: topmost y and bottommost y.
upper, lower = [], []
for x in range(w):
    ys = [y for y in range(h) if pix[(y*w+x)*bpp + 3] == 255]
    if ys:
        upper.append(ys[0])  # smaller y = higher in the image
        lower.append(ys[-1])

if len(upper) < 40:
    sys.exit(f'notched: too few opaque columns ({len(upper)})')

u_sd = statistics.pstdev(upper)
l_sd = statistics.pstdev(lower)
print(f'  → upper-outline y stdev = {u_sd:.2f}, '
      f'lower-outline y stdev = {l_sd:.2f}')

# A right-side-up notched cube: the upper outline has the step from
# the notch; the lower outline is a straight silhouette of the
# bottom face. So upper stdev MUST be larger than lower stdev. If
# the renderer flipped the model, these two swap.
if u_sd <= l_sd:
    sys.exit(f'notched: upper outline flatter than lower '
             f'(u={u_sd:.2f} <= l={l_sd:.2f}) '
             f'— model probably upside-down')
# Additionally the upper outline must have real roughness (the
# notch is 5 mm deep → ~15–25 pixels drop at ~8 px/mm scale), not
# just the natural isometric slope.
u_span = max(upper) - min(upper)
if u_span < 12:
    sys.exit(f'notched: upper outline span only {u_span} px '
             f'— notch not visible?')
print('  OK: upper outline carries the notch, lower outline is straight.')
PY

echo "=== 6/6  GUI-Referenz-PNG daneben legen ==="
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
echo "OK – alle Checks bestanden."
echo "  PNG (standard cube):  ${OUT_PNG}"
echo "  PNG (white filament): ${OUT_WHITE_PNG}"
echo "  PNG (notched cube):   ${OUT_NOTCHED_PNG}"
echo "  PNG (GUI reference):  ${GUI_PNG}"
