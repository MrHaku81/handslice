#!/usr/bin/env bash
# EXPERIMENTAL — eigener Build von handslice-cli-arm64 mit
# `-ffp-contract=off`, um die FMA-Hypothese zur arm64/x86-Divergenz
# zu testen. Produziert eine **getrennte** Binary unter
# `engine/bin/handslice-cli-arm64-fpoff` ohne den Default-Build zu
# berueren. Standardbuild bleibt `engine/build-cli-arm64.sh`.
#
# Hintergrund: GCC auf x86 defaultet auf `-ffp-contract=fast`, Clang
# auf Android-NDK auf `-ffp-contract=on` (nur innerhalb von Statements).
# Das kann zu kleinen Rounding-Diffs zwischen a*b+c als getrennte
# Instruktionen vs. FMA fuehren. Hypothese: diese Diffs sind die Wurzel
# der arm64/x86-Byte-Divergenz.
#
# Build-Dirs sind komplett getrennt (deps_src wird nicht nochmal gebaut,
# nur libslic3r mit anderen Flags):
#   engine/build/arm64-fpoff   (libslic3r)
#   engine/build/cli-arm64-fpoff (handslice-cli)
#
# Keine Patches an OrcaSlicer-Upstream; nur ein zusaetzlicher CMake-Flag.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCA_DIR="${PROJECT_ROOT}/engine/OrcaSlicer"
DEPS_BUILD_DIR="${ORCA_DIR}/deps/build-arm64"
DEPS_DESTDIR="${DEPS_BUILD_DIR}/OrcaSlicer_dep/usr/local"
ORCA_BUILD_DIR="${PROJECT_ROOT}/engine/build/arm64-fpoff"
CLI_SRC_DIR="${PROJECT_ROOT}/engine/cli"
CLI_BUILD_DIR="${PROJECT_ROOT}/engine/build/cli-arm64-fpoff"
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

EXTRA_FLAGS="-ffp-contract=off"
echo "=== 1/2  Konfiguriere + baue libslic3r (fpoff) nach ${ORCA_BUILD_DIR} ==="
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
# Encoding-check: same workaround as the default build.
HOST_EC="${PROJECT_ROOT}/engine/build/x86/src/dev-utils/encoding-check"
ARM_EC="${ORCA_BUILD_DIR}/src/dev-utils/encoding-check"
if [[ ! -x "${HOST_EC}" ]]; then
    echo "FEHLT: ${HOST_EC}" >&2
    exit 2
fi
sed -i "s|${ARM_EC} libslic3r @|${HOST_EC} libslic3r @|g; s|${ARM_EC} libslic3r_cgal @|${HOST_EC} libslic3r_cgal @|g" "${ORCA_BUILD_DIR}/build.ninja"
# CMAKE_CXX_FLAGS_INIT is overwritten by Orca's own `set(CMAKE_CXX_FLAGS
# "${CMAKE_CXX_FLAGS} -Wall …")` cascade. We inject the flag directly
# into every `FLAGS = …` line of the generated ninja file. This is
# brittle (ninja format is cmake-internal) but it is the only way to
# guarantee the flag survives Orca's cmake machinery.
sed -i '/^  FLAGS = / s/$/ -ffp-contract=off/' "${ORCA_BUILD_DIR}/build.ninja"
echo "   -ffp-contract=off injected into every FLAGS line of build.ninja"
cmake --build "${ORCA_BUILD_DIR}" -j "${JOBS}" --target libslic3r libslic3r_cgal libnest2d

echo "=== 2/2  Baue handslice-cli (fpoff) nach ${CLI_BUILD_DIR} ==="
CLI_COMMIT="$(cd "${PROJECT_ROOT}" && git rev-parse --short=10 HEAD 2>/dev/null || echo unknown)-fpoff"
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
cmake --build "${CLI_BUILD_DIR}" -j "${JOBS}" --target handslice-cli

mkdir -p "${BIN_DIR}"
install -m 0755 "${CLI_BUILD_DIR}/handslice-cli" "${BIN_DIR}/handslice-cli-arm64-fpoff"
STRIP="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
"${STRIP}" --strip-all "${BIN_DIR}/handslice-cli-arm64-fpoff"
echo -n "${CLI_COMMIT}" > "${BIN_DIR}/handslice-cli-arm64-fpoff.commit"
echo "--> ${BIN_DIR}/handslice-cli-arm64-fpoff"
file "${BIN_DIR}/handslice-cli-arm64-fpoff"
echo "HANDSLICE_CLI_COMMIT (eingebettet): ${CLI_COMMIT}"
