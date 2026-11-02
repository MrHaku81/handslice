#!/usr/bin/env bash
# EXPERIMENTAL — baut handslice-cli-arm64-count mit
# -DHANDSLICE_COUNT_SPLIT_SOLID. Produziert eine getrennte Binary unter
# `engine/bin/handslice-cli-arm64-count` ohne den Default-arm64-Build zu
# ueberschreiben. Standardbuild bleibt `engine/build-cli-arm64.sh`.
#
# Zweck: Siehe engine/build-headless-x86-count.sh. Dieselben Zaehler als
# arm64-Build fuer den Poco-Testlauf.
#
# Build-Dirs sind getrennt:
#   engine/build/arm64-count    (libslic3r)
#   engine/build/cli-arm64-count (handslice-cli)

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCA_DIR="${PROJECT_ROOT}/engine/OrcaSlicer"
DEPS_BUILD_DIR="${ORCA_DIR}/deps/build-arm64"
DEPS_DESTDIR="${DEPS_BUILD_DIR}/OrcaSlicer_dep/usr/local"
ORCA_BUILD_DIR="${PROJECT_ROOT}/engine/build/arm64-count"
CLI_SRC_DIR="${PROJECT_ROOT}/engine/cli"
CLI_BUILD_DIR="${PROJECT_ROOT}/engine/build/cli-arm64-count"
BIN_DIR="${PROJECT_ROOT}/engine/bin"
TOOLCHAIN_FILE="${PROJECT_ROOT}/engine/cmake/android-arm64.toolchain.cmake"
JOBS="${JOBS:-$(nproc)}"

export ANDROID_NDK="${ANDROID_NDK:-$HOME/android-sdk/ndk/27.3.13750724}"
if [[ ! -d "${DEPS_DESTDIR}" ]]; then
    echo "FEHLT: ${DEPS_DESTDIR}" >&2
    echo "  → zuerst 'bash engine/build-deps-arm64.sh' laufen lassen." >&2
    exit 2
fi
export HANDSLICE_DEPS_PREFIX="${DEPS_DESTDIR}"

EXTRA_FLAGS="-DHANDSLICE_COUNT_SPLIT_SOLID"
echo "=== 1/2  Konfiguriere + baue libslic3r (count) nach ${ORCA_BUILD_DIR} ==="
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
# Encoding-check-shim: same as the default arm64 build.
HOST_EC="${PROJECT_ROOT}/engine/build/x86/src/dev-utils/encoding-check"
ARM_EC="${ORCA_BUILD_DIR}/src/dev-utils/encoding-check"
if [[ ! -x "${HOST_EC}" ]]; then
    echo "FEHLT: ${HOST_EC}" >&2
    exit 2
fi
sed -i "s|${ARM_EC} libslic3r @|${HOST_EC} libslic3r @|g; s|${ARM_EC} libslic3r_cgal @|${HOST_EC} libslic3r_cgal @|g" "${ORCA_BUILD_DIR}/build.ninja"
# CMAKE_CXX_FLAGS_INIT survives at config time but gets overwritten by
# Orca's own `-Wall …` cascade. Inject directly into every ninja FLAGS
# line so HANDSLICE_COUNT_SPLIT_SOLID is actually defined at compile.
sed -i "/^  FLAGS = / s/\$/ ${EXTRA_FLAGS}/" "${ORCA_BUILD_DIR}/build.ninja"
echo "   ${EXTRA_FLAGS} injected into every FLAGS line of build.ninja"
cmake --build "${ORCA_BUILD_DIR}" -j "${JOBS}" --target libslic3r libslic3r_cgal libnest2d

echo "=== 2/2  Baue handslice-cli (count) nach ${CLI_BUILD_DIR} ==="
CLI_COMMIT="$(cd "${PROJECT_ROOT}" && git rev-parse --short=10 HEAD 2>/dev/null || echo unknown)-count"
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
install -m 0755 "${CLI_BUILD_DIR}/handslice-cli" "${BIN_DIR}/handslice-cli-arm64-count"
STRIP="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
"${STRIP}" --strip-all "${BIN_DIR}/handslice-cli-arm64-count"
echo -n "${CLI_COMMIT}" > "${BIN_DIR}/handslice-cli-arm64-count.commit"
echo "--> ${BIN_DIR}/handslice-cli-arm64-count"
file "${BIN_DIR}/handslice-cli-arm64-count"
echo "HANDSLICE_CLI_COMMIT (eingebettet): ${CLI_COMMIT}"
