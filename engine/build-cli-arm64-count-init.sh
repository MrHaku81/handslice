#!/usr/bin/env bash
# EXPERIMENTAL — baut handslice-cli-arm64-count-<pattern|zero> mit
# -ftrivial-auto-var-init=<mode> UND -DHANDSLICE_COUNT_SPLIT_SOLID.
#
# Zweck: Stufe-3c-Nachtrag — Klaus' Hypothese testen, dass die
# arm64-Divergenz an uninitialisierten Stack-Variablen haengt. Clang-
# Flag `-ftrivial-auto-var-init` initialisiert Stack-Variablen
# deterministisch (pattern = 0xAA..., zero = alles-0).
#
# Falls Varianz unter beiden Modi verschwindet und pattern vs zero
# unterschiedliche aber je stabile Ergebnisse liefert, ist "uninit
# stack var" bewiesen. Falls Varianz bleibt: Heap oder anderer Grund.
#
# Benutzung:
#   bash engine/build-cli-arm64-count-init.sh pattern
#   bash engine/build-cli-arm64-count-init.sh zero
#
# Produziert handslice-cli-arm64-count-<mode> unter engine/bin/,
# ohne Default-Builds zu beruehren. Standardbuild bleibt
# `engine/build-cli-arm64.sh`.

set -euo pipefail

if [[ $# -ne 1 || ( "$1" != "pattern" && "$1" != "zero" ) ]]; then
    echo "Usage: $0 <pattern|zero>" >&2
    exit 2
fi
MODE="$1"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCA_DIR="${PROJECT_ROOT}/engine/OrcaSlicer"
DEPS_BUILD_DIR="${ORCA_DIR}/deps/build-arm64"
DEPS_DESTDIR="${DEPS_BUILD_DIR}/OrcaSlicer_dep/usr/local"
ORCA_BUILD_DIR="${PROJECT_ROOT}/engine/build/arm64-count-${MODE}"
CLI_SRC_DIR="${PROJECT_ROOT}/engine/cli"
CLI_BUILD_DIR="${PROJECT_ROOT}/engine/build/cli-arm64-count-${MODE}"
BIN_DIR="${PROJECT_ROOT}/engine/bin"
TOOLCHAIN_FILE="${PROJECT_ROOT}/engine/cmake/android-arm64.toolchain.cmake"
JOBS="${JOBS:-$(nproc)}"

export ANDROID_NDK="${ANDROID_NDK:-$HOME/android-sdk/ndk/27.3.13750724}"
if [[ ! -d "${DEPS_DESTDIR}" ]]; then
    echo "FEHLT: ${DEPS_DESTDIR}" >&2
    echo "  -> zuerst 'bash engine/build-deps-arm64.sh' laufen lassen." >&2
    exit 2
fi
export HANDSLICE_DEPS_PREFIX="${DEPS_DESTDIR}"

EXTRA_FLAGS="-DHANDSLICE_COUNT_SPLIT_SOLID -ftrivial-auto-var-init=${MODE}"
echo "=== 1/2  Konfiguriere + baue libslic3r (count+init=${MODE}) nach ${ORCA_BUILD_DIR} ==="
cmake -S "${ORCA_DIR}" -B "${ORCA_BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DCMAKE_PREFIX_PATH="${DEPS_DESTDIR}" \
    -DCMAKE_MODULE_PATH="${PROJECT_ROOT}/engine/cmake/android-shims" \
    -DCMAKE_CXX_FLAGS_INIT="${EXTRA_FLAGS}" \
    -DCMAKE_C_FLAGS_INIT="${EXTRA_FLAGS}" \
    -DSLIC3R_GUI=OFF \
    -DSLIC3R_STATIC=1 \
    -DSLIC3R_PCH=OFF \
    -DSLIC3R_BUILD_SANDBOXES=OFF \
    -DBUILD_TESTS=OFF \
    -DORCA_TOOLS=OFF
HOST_EC="${PROJECT_ROOT}/engine/build/x86/src/dev-utils/encoding-check"
ARM_EC="${ORCA_BUILD_DIR}/src/dev-utils/encoding-check"
if [[ ! -x "${HOST_EC}" ]]; then
    echo "FEHLT: ${HOST_EC}" >&2
    exit 2
fi
sed -i "s|${ARM_EC} libslic3r @|${HOST_EC} libslic3r @|g; s|${ARM_EC} libslic3r_cgal @|${HOST_EC} libslic3r_cgal @|g" "${ORCA_BUILD_DIR}/build.ninja"
sed -i "/^  FLAGS = / s/\$/ ${EXTRA_FLAGS}/" "${ORCA_BUILD_DIR}/build.ninja"
echo "   ${EXTRA_FLAGS} injected into every FLAGS line of build.ninja"
cmake --build "${ORCA_BUILD_DIR}" -j "${JOBS}" --target libslic3r libslic3r_cgal libnest2d

echo "=== 2/2  Baue handslice-cli (count+init=${MODE}) nach ${CLI_BUILD_DIR} ==="
CLI_COMMIT="$(cd "${PROJECT_ROOT}" && git rev-parse --short=10 HEAD 2>/dev/null || echo unknown)-count-${MODE}"
cmake -S "${CLI_SRC_DIR}" -B "${CLI_BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DCMAKE_CXX_FLAGS_INIT="${EXTRA_FLAGS}" \
    -DCMAKE_C_FLAGS_INIT="${EXTRA_FLAGS}" \
    -DORCA_SOURCE_DIR="${ORCA_DIR}" \
    -DORCA_BUILD_DIR="${ORCA_BUILD_DIR}" \
    -DORCA_DEPS_PREFIX="${DEPS_DESTDIR}" \
    -DHANDSLICE_ANDROID=1 \
    -DHANDSLICE_CLI_COMMIT="${CLI_COMMIT}"
sed -i "/^  FLAGS = / s/\$/ ${EXTRA_FLAGS}/" "${CLI_BUILD_DIR}/build.ninja"
cmake --build "${CLI_BUILD_DIR}" -j "${JOBS}" --target handslice-cli

mkdir -p "${BIN_DIR}"
install -m 0755 "${CLI_BUILD_DIR}/handslice-cli" "${BIN_DIR}/handslice-cli-arm64-count-${MODE}"
STRIP="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
"${STRIP}" --strip-all "${BIN_DIR}/handslice-cli-arm64-count-${MODE}"
echo -n "${CLI_COMMIT}" > "${BIN_DIR}/handslice-cli-arm64-count-${MODE}.commit"
echo "--> ${BIN_DIR}/handslice-cli-arm64-count-${MODE}"
file "${BIN_DIR}/handslice-cli-arm64-count-${MODE}"
echo "HANDSLICE_CLI_COMMIT (eingebettet): ${CLI_COMMIT}"
