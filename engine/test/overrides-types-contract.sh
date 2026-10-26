#!/usr/bin/env bash
# Vertragstest: --overrides nimmt Zahlen und Booleans entgegen und
# konvertiert sie zu Strings; Arrays werden mit klarer Fehlermeldung
# abgelehnt.
#
# Hintergrund: in Phase 4.3/4.4 war es nur Konvention, dass App und
# Tests ausschliesslich String-Werte in die Overrides-JSON schreiben.
# Diese Nacharbeit zieht das in die CLI, damit UI-Code (und spaetere
# Code-Pfade) nicht versehentlich einen Int oder Bool uebergeben und
# dann in Orcas Validate landen.
#
# Checks:
#   1. --overrides '{"nozzle_temperature": 260}'               → OK, M104 S260
#   2. --overrides '{"enable_pressure_advance": true}'         → OK, exit 0
#   3. --overrides '{"nozzle_temperature": [260]}'             → Exit != 0,
#      Meldung erwaehnt den Key, erklaert dass Arrays nicht erlaubt sind,
#      kein abort/terminate.
#   4. --overrides '{"nozzle_temperature": null}'              → Exit != 0,
#      Meldung erwaehnt null-Wert.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="${PROJECT_ROOT}/engine/bin/handslice-cli-x86"
STL="${PROJECT_ROOT}/engine/test/cube_notched_20mm_centered_cc2.stl"
RES="${PROJECT_ROOT}/engine/OrcaSlicer/resources"
PROF="${RES}/profiles/Elegoo"
MACH="${PROF}/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json"
PROC="${PROF}/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json"
FIL="${PROF}/filament/ECC2/Elegoo PETG @ECC2.json"
[[ -x "${CLI}" ]] || { echo "FEHLT: ${CLI}" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "=== 1  Int-Wert in --overrides: nozzle_temperature=260 ==="
"${CLI}" --machine "${MACH}" --process "${PROC}" --filament "${FIL}" \
    --resources "${RES}" --output "${TMP}/int.gcode" --bed-type B --quiet \
    --no-center --overrides '{"nozzle_temperature": 260}' "${STL}" > /dev/null
if ! grep -q "^M104 S260 ; set nozzle temperature" "${TMP}/int.gcode"; then
    echo "FAIL: M104 S260 nicht im G-Code" >&2; exit 1
fi
echo "   OK (M104 S260 im G-Code)"

echo "=== 2  Bool-Wert in --overrides: enable_pressure_advance=true ==="
# Erfolgskriterium: exit 0 und Datei existiert. Semantischer Effekt
# (SET_PRESSURE_ADVANCE-Zeilen) haengt vom Druckerprofil ab; wichtig
# ist, dass der Bool nicht als String "true" oder Array abgelehnt wird.
"${CLI}" --machine "${MACH}" --process "${PROC}" --filament "${FIL}" \
    --resources "${RES}" --output "${TMP}/bool.gcode" --bed-type B --quiet \
    --no-center --overrides '{"enable_pressure_advance": [true]}' "${STL}" > /dev/null 2>&1 \
    && { echo "FAIL: Array [true] haette abgelehnt werden sollen" >&2; exit 1; } \
    || true   # erwarteter Pfad
"${CLI}" --machine "${MACH}" --process "${PROC}" --filament "${FIL}" \
    --resources "${RES}" --output "${TMP}/bool.gcode" --bed-type B --quiet \
    --no-center --overrides '{"enable_pressure_advance": true}' "${STL}" > /dev/null
[[ -s "${TMP}/bool.gcode" ]] || { echo "FAIL: bool.gcode leer" >&2; exit 1; }
echo "   OK (exit 0 mit Bool-Wert)"

echo "=== 3  Array-Wert wird mit klarer Meldung abgelehnt ==="
set +e
err=$("${CLI}" --machine "${MACH}" --process "${PROC}" --filament "${FIL}" \
    --resources "${RES}" --output "${TMP}/arr.gcode" --bed-type B --quiet \
    --no-center --overrides '{"nozzle_temperature": [260]}' "${STL}" 2>&1)
rc=$?
set -e
echo "   stderr: ${err}"
if [[ "${rc}" -eq 0 ]]; then
    echo "FAIL: Array wurde akzeptiert (exit 0)" >&2; exit 1
fi
if echo "${err}" | grep -qi "terminate called\|aborted\|abort"; then
    echo "FAIL: terminate/abort statt sauberer Fehlermeldung" >&2; exit 1
fi
if ! echo "${err}" | grep -q "nozzle_temperature"; then
    echo "FAIL: Fehlermeldung nennt den Key nicht" >&2; exit 1
fi
if ! echo "${err}" | grep -qi "array"; then
    echo "FAIL: Fehlermeldung erwaehnt 'array' nicht" >&2; exit 1
fi
echo "   OK (exit=${rc}, Key + 'array' in der Meldung)"

echo "=== 4  null-Wert wird mit klarer Meldung abgelehnt ==="
set +e
err=$("${CLI}" --machine "${MACH}" --process "${PROC}" --filament "${FIL}" \
    --resources "${RES}" --output "${TMP}/null.gcode" --bed-type B --quiet \
    --no-center --overrides '{"nozzle_temperature": null}' "${STL}" 2>&1)
rc=$?
set -e
echo "   stderr: ${err}"
if [[ "${rc}" -eq 0 ]]; then
    echo "FAIL: null wurde akzeptiert" >&2; exit 1
fi
if ! echo "${err}" | grep -qi "null"; then
    echo "FAIL: Fehlermeldung erwaehnt 'null' nicht" >&2; exit 1
fi
echo "   OK (exit=${rc}, 'null' in der Meldung)"

echo
echo "overrides-types-contract: alle 4 Checks grün."
