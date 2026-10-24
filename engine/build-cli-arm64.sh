#!/usr/bin/env bash
# Baut handslice-cli-arm64 (eigener headless CLI gegen OrcaSlicer-libslic3r)
# fuer Android arm64-v8a (API 29) als Cross-Compile mit NDK r27d.
#
# Vorgehen:
#   1. Orca-Hauptbuild (libslic3r + libslic3r_cgal + libnest2d) mit NDK-
#      Toolchain nach engine/build/arm64. Deps werden erwartet unter
#      engine/OrcaSlicer/deps/build-arm64 (via engine/build-deps-arm64.sh).
#   2. handslice-cli unter engine/cli bauen und als arm64-Binary nach
#      engine/bin/handslice-cli-arm64 ablegen.
#
# Keine Patches an OrcaSlicer-Upstream.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCA_DIR="${PROJECT_ROOT}/engine/OrcaSlicer"
DEPS_BUILD_DIR="${ORCA_DIR}/deps/build-arm64"
DEPS_DESTDIR="${DEPS_BUILD_DIR}/OrcaSlicer_dep/usr/local"
ORCA_BUILD_DIR="${PROJECT_ROOT}/engine/build/arm64"
CLI_SRC_DIR="${PROJECT_ROOT}/engine/cli"
CLI_BUILD_DIR="${PROJECT_ROOT}/engine/build/cli-arm64"
BIN_DIR="${PROJECT_ROOT}/engine/bin"
TOOLCHAIN_FILE="${PROJECT_ROOT}/engine/cmake/android-arm64.toolchain.cmake"
JOBS="${JOBS:-$(nproc)}"

export ANDROID_NDK="${ANDROID_NDK:-$HOME/android-sdk/ndk/27.3.13750724}"
if [[ ! -d "${DEPS_DESTDIR}" ]]; then
    echo "FEHLT: ${DEPS_DESTDIR}" >&2
    echo "  → zuerst 'bash engine/build-deps-arm64.sh' laufen lassen." >&2
    exit 2
fi

# Fuer das Toolchain-File: FindBoost/BoostConfig im Deps-Prefix finden.
# Siehe engine/cmake/android-arm64.toolchain.cmake.
export HANDSLICE_DEPS_PREFIX="${DEPS_DESTDIR}"

echo "=== 1/2  Konfiguriere + baue libslic3r fuer arm64 (${ORCA_BUILD_DIR}) ==="
cmake -S "${ORCA_DIR}" -B "${ORCA_BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DCMAKE_PREFIX_PATH="${DEPS_DESTDIR}" \
    -DCMAKE_MODULE_PATH="${PROJECT_ROOT}/engine/cmake/android-shims" \
    -DSLIC3R_GUI=OFF \
    -DSLIC3R_STATIC=1 \
    -DSLIC3R_PCH=OFF \
    -DSLIC3R_BUILD_SANDBOXES=OFF \
    -DBUILD_TESTS=OFF \
    -DORCA_TOOLS=OFF
# Encoding-Check-Workaround: Orcas Build definiert ein kleines dev-utils-
# Tool `encoding-check`, das zur Build-Zeit Quelldateien auf UTF-8-BOM
# prueft. Beim Cross-Compile wird es fuer arm64 gebaut, und der Host (x86)
# versucht spaeter waehrend des libslic3r-Build-Schritts, dieses Binary
# auszufuehren – "Fehler im Format der Programmdatei".
#
# Loesung ohne Orca-Patch: build.ninja mit sed so umschreiben, dass der
# encoding-check-Aufruf im Rezept der libslic3r/libslic3r_cgal-Stamps
# durch das vorhandene Host-x86-Binary (aus engine/build/x86/) ersetzt
# wird. Das arm64-Binary selbst wird nicht mehr gebraucht; die Dependency
# bleibt bestehen, nur der Command wird umgeleitet.
HOST_EC="${PROJECT_ROOT}/engine/build/x86/src/dev-utils/encoding-check"
ARM_EC="${ORCA_BUILD_DIR}/src/dev-utils/encoding-check"
if [[ ! -x "${HOST_EC}" ]]; then
    echo "FEHLT: ${HOST_EC}" >&2
    echo "       → zuerst 'bash engine/build-headless-x86.sh' laufen, damit" >&2
    echo "         die Host-Variante existiert." >&2
    exit 2
fi
# Pfad escaped fuer sed. Wir setzen das arm64-Target-Binary auf einen
# Symlink auf die Host-Variante; so laeuft es sowohl im `--target
# encoding-check`-Fall als auch wenn ninja irgendwann relinkt.
# build.ninja patchen: Alle Vorkommen des arm64-encoding-check-Pfades durch
# den Host-x86-Pfad ersetzen. Die Linking-Rule bleibt erhalten (einfacher
# als sie zu entfernen), erzeugt aber ein nicht ausfuehrbares arm64-
# Binary – egal, weil die Encoding-Check-Rule den Host-Pfad direkt aufruft.
# ESCAPEN von sed-Delimiter-Pfad-Zeichen via Pipe-Trenner (|).
sed -i "s|${ARM_EC} libslic3r @|${HOST_EC} libslic3r @|g; s|${ARM_EC} libslic3r_cgal @|${HOST_EC} libslic3r_cgal @|g" "${ORCA_BUILD_DIR}/build.ninja"
echo "   encoding-check: build.ninja auf Host-Binary ${HOST_EC} umgebogen"

cmake --build "${ORCA_BUILD_DIR}" -j "${JOBS}" --target libslic3r libslic3r_cgal libnest2d

echo "=== 2/2  Baue handslice-cli fuer arm64 (${CLI_BUILD_DIR}) ==="
cmake -S "${CLI_SRC_DIR}" -B "${CLI_BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DORCA_SOURCE_DIR="${ORCA_DIR}" \
    -DORCA_BUILD_DIR="${ORCA_BUILD_DIR}" \
    -DORCA_DEPS_PREFIX="${DEPS_DESTDIR}" \
    -DHANDSLICE_ANDROID=1
cmake --build "${CLI_BUILD_DIR}" -j "${JOBS}" --target handslice-cli

mkdir -p "${BIN_DIR}"
install -m 0755 "${CLI_BUILD_DIR}/handslice-cli" "${BIN_DIR}/handslice-cli-arm64"
echo "--> ${BIN_DIR}/handslice-cli-arm64"
file "${BIN_DIR}/handslice-cli-arm64"
