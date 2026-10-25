#!/usr/bin/env bash
# Reproduzierbarer Stresstest fuer einen beliebigen STL-Pfad.
# Misst fuer x86 (AMR5) und arm64 (Poco X3 Pro via adb):
#   - Slice-Dauer (Wall-Clock, ms)
#   - Peak-RSS (/proc/<pid>/status VmHWM)
#   - Thermal-Status am Poco (vorher/nachher via dumpsys thermalservice)
#   - Grenztest: faellt libslic3rs Preflight an?
#
# Benutzung:
#   bash engine/test/stress-test.sh <pfad/zur/modell.stl> [--out <dir>]
#
# Keine Fremdmodelle im Repo – der Pfad kommt per Argument.
# Alle Zwischendateien werden im angegebenen OUT-Dir abgelegt (Default:
# ${TMPDIR:-/tmp}/handslice-stress). Logs + G-Code bleiben lokal und
# unter .gitignore'd Verzeichnissen (siehe local-test/).

set -euo pipefail

usage() {
    cat <<EOF >&2
Usage: $0 <modell.stl>            [--out <dir>] [--skip-arm64] [--skip-x86] [--bed A|B]
       $0 --download <name>       [--out <dir>] [--skip-arm64] [--skip-x86] [--bed A|B]
       $0 --list-downloads

--download <name>  laedt ein kuratiertes Grossmodell aus
                   engine/test/stress-models.json nach
                   local-test/stresstest-cache/<name>.stl, schreibt
                   dazu <name>.license.txt mit Herkunft/Lizenz-Beleg.
--list-downloads   listet verfuegbare Modelle.
EOF
    exit 2
}

MODEL=""
OUT_DIR=""
SKIP_X86=0
SKIP_ARM=0
BED=A
DOWNLOAD=""
LIST=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out)             OUT_DIR="$2"; shift 2 ;;
        --skip-arm64)      SKIP_ARM=1;   shift ;;
        --skip-x86)        SKIP_X86=1;   shift ;;
        --bed)             BED="$2";     shift 2 ;;
        --download)        DOWNLOAD="$2"; shift 2 ;;
        --list-downloads)  LIST=1;       shift ;;
        -h|--help)         usage ;;
        -*)                echo "unknown flag: $1" >&2; usage ;;
        *)                 MODEL="${MODEL:-$1}"; shift ;;
    esac
done

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODELS_JSON="${PROJECT_ROOT}/engine/test/stress-models.json"
CACHE_DIR="${PROJECT_ROOT}/local-test/stresstest-cache"

if [[ "${LIST}" -eq 1 ]]; then
    python3 - "${MODELS_JSON}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for name, m in d['models'].items():
    tris = m.get('triangles') or '?'
    print(f"  {name:12s}  {m['title']:30s}  {tris} Dreiecke  <- {m['download_url']}")
PY
    exit 0
fi

if [[ -n "${DOWNLOAD}" ]]; then
    mkdir -p "${CACHE_DIR}"
    entry=$(python3 -c "import json,sys;d=json.load(open('${MODELS_JSON}'));m=d['models'].get('${DOWNLOAD}');print(json.dumps(m) if m else '')")
    if [[ -z "${entry}" ]]; then
        echo "FEHLT: Modell '${DOWNLOAD}' nicht in ${MODELS_JSON}" >&2
        exit 2
    fi
    url=$(python3 -c "import json;print(json.loads(r'''${entry}''')['download_url'])")
    expected_sha=$(python3 -c "import json;print(json.loads(r'''${entry}''').get('sha256_zip') or '')")
    extract=$(python3 -c "import json;print(json.loads(r'''${entry}''').get('extract_name') or '')")
    license=$(python3 -c "import json;print(json.loads(r'''${entry}''')['license'])")
    attrib=$(python3 -c "import json;print(json.loads(r'''${entry}''')['attribution'])")
    src=$(python3 -c "import json;print(json.loads(r'''${entry}''')['source_url'])")

    tmpzip="${CACHE_DIR}/${DOWNLOAD}.download"
    echo "=== Download '${DOWNLOAD}' ==="
    echo "   URL:  ${url}"
    curl -L --fail --max-time 300 --silent --show-error "${url}" -o "${tmpzip}"

    if [[ -n "${expected_sha}" ]]; then
        actual=$(sha256sum "${tmpzip}" | awk '{print $1}')
        if [[ "${actual}" != "${expected_sha}" ]]; then
            echo "ABBRUCH: SHA256-Mismatch" >&2
            echo "   erwartet: ${expected_sha}" >&2
            echo "   erhalten: ${actual}" >&2
            rm -f "${tmpzip}"
            exit 3
        fi
        echo "   SHA256 OK: ${actual}"
    else
        echo "   SHA256: $(sha256sum "${tmpzip}" | awk '{print $1}') (nicht gelockt – bitte in stress-models.json pflegen)"
    fi

    MODEL="${CACHE_DIR}/${DOWNLOAD}.stl"
    case "${url}" in
        *.zip) unzip -o "${tmpzip}" "${extract}" -d "${CACHE_DIR}" >/dev/null
               mv "${CACHE_DIR}/${extract}" "${MODEL}"
               rm -rf "${CACHE_DIR}/__MACOSX"
               ;;
        *.stl) mv "${tmpzip}" "${MODEL}" ;;
        *)     echo "UNBEKANNTES Format: ${url##*.}; nur .stl / .zip-mit-stl unterstuetzt" >&2
               exit 2 ;;
    esac
    rm -f "${tmpzip}"
    license_file="${MODEL%.stl}.license.txt"
    cat >"${license_file}" <<EOF
${DOWNLOAD}  —  heruntergeladen am $(date -u +'%Y-%m-%dT%H:%MZ')

Titel:       $(python3 -c "import json;print(json.loads(r'''${entry}''')['title'])")
Attribution: ${attrib}
Quelle:      ${src}
Download:    ${url}
SHA256:      $(sha256sum "${MODEL}" | awk '{print $1}')

Lizenz / Nutzungshinweis:
${license}

Dieser Sidecar wird vom stress-test.sh beim Download angelegt. Nicht
loeschen – wer das Modell lokal haelt, soll die Lizenz-Lage mit lesen
koennen. Pfad des Modells liegt im .gitignore'd local-test/-Verzeichnis.
EOF
    echo "   STL:  ${MODEL}"
    echo "   Lic:  ${license_file}"
fi

[[ -z "${MODEL}" ]] && usage
[[ ! -f "${MODEL}" ]] && { echo "FEHLT: ${MODEL}" >&2; exit 2; }

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${OUT_DIR:-${TMPDIR:-/tmp}/handslice-stress}"
mkdir -p "${OUT_DIR}"
MODEL="$(readlink -f "${MODEL}")"
BASE="$(basename "${MODEL}" .stl)"

X86_CLI="${PROJECT_ROOT}/engine/bin/handslice-cli-x86"
ARM_CLI="${PROJECT_ROOT}/engine/bin/handslice-cli-arm64"
RESOURCES="${PROJECT_ROOT}/engine/OrcaSlicer/resources"
PROF="${RESOURCES}/profiles/Elegoo"
MACHINE="${PROF}/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json"
PROCESS="${PROF}/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json"
FILAMENT="${PROF}/filament/ECC2/Elegoo PLA @ECC2.json"

# STL-Kennzahlen (ohne libslic3r, pur Python)
python3 - <<PY > "${OUT_DIR}/${BASE}-info.txt"
import struct, sys, os
p = "${MODEL}"
sz = os.path.getsize(p)
with open(p, 'rb') as f:
    f.read(80)  # header
    n = struct.unpack('<I', f.read(4))[0]
    xmin=ymin=zmin=+1e9; xmax=ymax=zmax=-1e9
    for _ in range(n):
        f.read(12)
        for _v in range(3):
            x,y,z = struct.unpack('<3f', f.read(12))
            if x<xmin: xmin=x
            if y<ymin: ymin=y
            if z<zmin: zmin=z
            if x>xmax: xmax=x
            if y>ymax: ymax=y
            if z>zmax: zmax=z
        f.read(2)
print(f'file:      {p}')
print(f'size:      {sz} byte ({sz/1024/1024:.1f} MB)')
print(f'triangles: {n}')
print(f'bbox:      X[{xmin:.2f},{xmax:.2f}] span {xmax-xmin:.2f}')
print(f'           Y[{ymin:.2f},{ymax:.2f}] span {ymax-ymin:.2f}')
print(f'           Z[{zmin:.2f},{zmax:.2f}] span {zmax-zmin:.2f}')
PY
echo "=== Modell-Kennzahlen ==="; cat "${OUT_DIR}/${BASE}-info.txt"; echo

run_x86() {
    local out_gcode="${OUT_DIR}/${BASE}-x86.gcode"
    local out_log="${OUT_DIR}/${BASE}-x86.log"
    local mem_log="${OUT_DIR}/${BASE}-x86-mem.log"
    local stats="${OUT_DIR}/${BASE}-x86-stats.json"
    echo "=== x86 Slice ==="
    [[ ! -x "${X86_CLI}" ]] && { echo "FEHLT: ${X86_CLI}" >&2; return 1; }
    local t0=$(date +%s%N)
    # Polling-Loop zusaetzlich zur CLI-eigenen getrusage-Zahl: fuer die
    # Verlaufsdarstellung (mem-log) hilfreich. Peak selbst kommt aus
    # dem Stats-JSON (peak_memory_kb) und ist nicht vom Poll-Intervall
    # abhaengig.
    "${X86_CLI}" --machine "${MACHINE}" --process "${PROCESS}" --filament "${FILAMENT}" \
        --resources "${RESOURCES}" --output "${out_gcode}" --bed-type "${BED}" --quiet \
        "${MODEL}" > "${stats}" 2> "${out_log}" &
    local pid=$!
    local poll_peak=0
    while kill -0 $pid 2>/dev/null; do
        local hwm=$(awk '/^VmHWM:/{print $2}' /proc/$pid/status 2>/dev/null || true)
        [[ -n "${hwm}" && "${hwm}" -gt "${poll_peak}" ]] && poll_peak=${hwm}
        echo "$(date +%s) VmHWM=${hwm:-0}" >> "${mem_log}"
        sleep 0.2
    done
    wait $pid
    local ec=$?
    local t1=$(date +%s%N)
    local ms=$(( (t1 - t0) / 1000000 ))
    # getrusage-Peak aus Stats-JSON (immer korrekt, unabhaengig vom
    # Poll-Intervall).
    local getrusage_peak=0
    if [[ -s "${stats}" ]]; then
        getrusage_peak=$(python3 -c "import json;print(json.load(open('${stats}')).get('peak_memory_kb',0))" 2>/dev/null || echo 0)
    fi
    local peak_mb=$(awk "BEGIN{printf \"%.1f\", ${getrusage_peak}/1024}")
    local poll_mb=$(awk "BEGIN{printf \"%.1f\", ${poll_peak}/1024}")
    echo "x86-exit=${ec}  dauer=${ms}ms  peak=${getrusage_peak}kB (${peak_mb} MB, getrusage) / ${poll_peak}kB (${poll_mb} MB, Poll 200 ms)" | tee -a "${OUT_DIR}/${BASE}-summary.txt"
    if [[ ${ec:-99} -ne 0 ]]; then
        echo "  stderr: $(tail -1 "${out_log}")" | tee -a "${OUT_DIR}/${BASE}-summary.txt"
    fi
    return 0
}

run_arm() {
    local out_gcode="${OUT_DIR}/${BASE}-arm64.gcode"
    local out_log="${OUT_DIR}/${BASE}-arm64.log"
    echo "=== arm64 Slice am Poco (adb) ==="
    [[ ! -x "${ARM_CLI}" ]] && { echo "FEHLT: ${ARM_CLI}" >&2; return 1; }
    export PATH="$HOME/android-sdk/platform-tools:$PATH"
    # Flapping-ADB (MIUI poppt den USB-Dialog nach x86-Phase gern wieder
    # auf): einmal Neustart + 10 s Wartefenster probieren.
    if ! adb get-state 2>/dev/null | grep -q device; then
        adb kill-server >/dev/null 2>&1 || true
        adb start-server >/dev/null 2>&1 || true
        for _ in 1 2 3 4 5; do
            if adb get-state 2>/dev/null | grep -q device; then break; fi
            sleep 2
        done
    fi
    if ! adb get-state 2>/dev/null | grep -q device; then
        echo "SKIP: adb-Geraet nicht verbunden" | tee -a "${OUT_DIR}/${BASE}-summary.txt"
        return 0
    fi

    local REMOTE=/data/local/tmp/handslice-stress
    adb shell "mkdir -p ${REMOTE}"
    adb push "${ARM_CLI}"   "${REMOTE}/cli"              >/dev/null
    adb shell "chmod +x ${REMOTE}/cli"
    # Resources + Modell pushen (bei grossen STLs merklich – aber einmalig)
    adb push "${RESOURCES}" "${REMOTE}/resources"        >/dev/null
    adb push "${MODEL}"     "${REMOTE}/model.stl"        >/dev/null

    local thermal_before=$(adb shell "dumpsys thermalservice" | grep -oE 'Thermal Status: [0-9]+' | head -1)

    # Mem-Polling direkt am Geraet, Peak + Dauer berechnen wir im Host
    local t0=$(date +%s%N)
    adb shell "( ${REMOTE}/cli \
        --machine '${REMOTE}/resources/profiles/Elegoo/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json' \
        --process '${REMOTE}/resources/profiles/Elegoo/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json' \
        --filament '${REMOTE}/resources/profiles/Elegoo/filament/ECC2/Elegoo PLA @ECC2.json' \
        --resources '${REMOTE}/resources' --output '${REMOTE}/out.gcode' --bed-type ${BED} --quiet \
        '${REMOTE}/model.stl' > ${REMOTE}/stats.json 2> ${REMOTE}/err.txt &
PID=\$!
while kill -0 \$PID 2>/dev/null; do
  grep -E '^Vm(HWM|RSS):' /proc/\$PID/status 2>/dev/null | tr '\n' ' '
  echo \$(date +%s)
  sleep 1
done
wait \$PID; echo exit=\$? )" > "${OUT_DIR}/${BASE}-arm64-mem.log" 2>&1
    local ec=$(grep -oE 'exit=[0-9]+' "${OUT_DIR}/${BASE}-arm64-mem.log" | tail -1 | cut -d= -f2)
    local t1=$(date +%s%N)
    local ms=$(( (t1 - t0) / 1000000 ))

    local poll_peak=$(awk '/VmHWM:/ {for(i=1;i<=NF;i++) if ($i=="VmHWM:") {v=$(i+1); if (v+0>m+0) m=v}} END {print m}' "${OUT_DIR}/${BASE}-arm64-mem.log")
    local thermal_after=$(adb shell "dumpsys thermalservice" | grep -oE 'Thermal Status: [0-9]+' | head -1)
    adb pull "${REMOTE}/out.gcode" "${out_gcode}" >/dev/null 2>&1 || true
    adb pull "${REMOTE}/stats.json" "${OUT_DIR}/${BASE}-arm64-stats.json" >/dev/null 2>&1 || true
    adb pull "${REMOTE}/err.txt"    "${out_log}" >/dev/null 2>&1 || true
    adb shell "rm -rf ${REMOTE}" >/dev/null 2>&1 || true

    local getrusage_peak=0
    if [[ -s "${OUT_DIR}/${BASE}-arm64-stats.json" ]]; then
        getrusage_peak=$(python3 -c "import json;print(json.load(open('${OUT_DIR}/${BASE}-arm64-stats.json')).get('peak_memory_kb',0))" 2>/dev/null || echo 0)
    fi
    local peak_mb=$(awk "BEGIN{printf \"%.1f\", ${getrusage_peak}/1024}")
    local poll_mb=$(awk "BEGIN{printf \"%.1f\", ${poll_peak:-0}/1024}")
    echo "arm64-exit=${ec:-?}  dauer=${ms}ms  peak=${getrusage_peak}kB (${peak_mb} MB, getrusage) / ${poll_peak:-0}kB (${poll_mb} MB, Poll 1 s)  thermal=${thermal_before:-?} / ${thermal_after:-?}" | tee -a "${OUT_DIR}/${BASE}-summary.txt"
    [[ "${ec:-99}" -ne 0 ]] && echo "  stderr: $(tail -1 "${out_log}")" | tee -a "${OUT_DIR}/${BASE}-summary.txt"
}

: > "${OUT_DIR}/${BASE}-summary.txt"
cat "${OUT_DIR}/${BASE}-info.txt" >> "${OUT_DIR}/${BASE}-summary.txt"
echo >> "${OUT_DIR}/${BASE}-summary.txt"

[[ "${SKIP_X86}" -eq 0 ]] && run_x86
[[ "${SKIP_ARM}" -eq 0 ]] && run_arm

echo
echo "Alle Zwischendateien unter ${OUT_DIR}"
echo "Zusammenfassung: ${OUT_DIR}/${BASE}-summary.txt"
