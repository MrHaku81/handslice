#!/usr/bin/env bash
# EXPERIMENTAL — baut handslice-cli-x86-clang mit Clang/libstdc++ statt
# GCC. Produziert eine **getrennte** Binary unter
# `engine/bin/handslice-cli-x86-clang` ohne den Default-GCC-Build zu
# ueberschreiben.
#
# Zweck: Divergenz-Stufe 2b. Isoliert den Compiler-Beitrag (Clang vs
# GCC) vom Standardbibliotheks-Beitrag. Hier verwenden wir Clang mit
# libstdc++ (= glibc's std-Lib) weiter — der NDK-Build auf arm64 nutzt
# Clang mit libc++. Wenn x86-Clang+libstdc++ immer noch deterministisch
# und = GUI-Ref bleibt, trennt das den Compiler als Ursache ab.
#
# Deps werden mit dem Default-GCC-Deps-Build geteilt (`engine/
# OrcaSlicer/deps/build-x86`): libstdc++ ABI ist zwischen GCC und
# Clang kompatibel, kein Rebuild noetig.
#
# Build-Dirs sind getrennt:
#   engine/build/x86-clang      (libslic3r)
#   engine/build/cli-x86-clang  (handslice-cli)
#
# Keine Patches an OrcaSlicer-Upstream.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCA_DIR="${PROJECT_ROOT}/engine/OrcaSlicer"
DEPS_BUILD_DIR="${ORCA_DIR}/deps/build-x86"
DEPS_DESTDIR="${DEPS_BUILD_DIR}/OrcaSlicer_dep/usr/local"
ORCA_BUILD_DIR="${PROJECT_ROOT}/engine/build/x86-clang"
CLI_SRC_DIR="${PROJECT_ROOT}/engine/cli"
CLI_BUILD_DIR="${PROJECT_ROOT}/engine/build/cli-x86-clang"
BIN_DIR="${PROJECT_ROOT}/engine/bin"
JOBS="${JOBS:-$(nproc)}"

if [[ ! -d "${DEPS_DESTDIR}" ]]; then
    echo "FEHLT: ${DEPS_DESTDIR}" >&2
    echo "  → zuerst 'bash engine/build-headless-x86.sh' laufen lassen" >&2
    echo "    (die Deps werden vom Default-GCC-Build mitgenommen)." >&2
    exit 2
fi

# NDK's clang-18 ist genau der Compiler, mit dem der arm64-Build
# laeuft. System-Clang (23.1) scheitert an Orcas Eigen-Nutzung bei
# strikterer Template-Deduktion (CwiseUnaryOp vs Matrix in
# AABBTreeLines.hpp:35), bevor libslic3r baut — kein Patch an
# OrcaSlicer erlaubt. NDK-Clang ist derselbe Compiler-Stand wie auf
# arm64, trifft also die Compiler-Variable sauber.
NDK_CLANG="$HOME/android-sdk/ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-x86_64/bin"
export CC="${NDK_CLANG}/clang"
export CXX="${NDK_CLANG}/clang++"
echo "=== 1/2  Konfiguriere + baue libslic3r (NDK clang-18, Target x86_64 Linux) → ${ORCA_BUILD_DIR} ==="
cmake -S "${ORCA_DIR}" -B "${ORCA_BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="${NDK_CLANG}/clang" \
    -DCMAKE_CXX_COMPILER="${NDK_CLANG}/clang++" \
    -DCMAKE_PREFIX_PATH="${DEPS_DESTDIR}" \
    -DSLIC3R_GUI=OFF \
    -DSLIC3R_STATIC=1 \
    -DSLIC3R_PCH=OFF \
    -DSLIC3R_BUILD_SANDBOXES=OFF \
    -DBUILD_TESTS=OFF \
    -DORCA_TOOLS=OFF
cmake --build "${ORCA_BUILD_DIR}" -j "${JOBS}" --target libslic3r libslic3r_cgal libnest2d

echo "=== 2/2  Baue handslice-cli (NDK clang-18) → ${CLI_BUILD_DIR} ==="
CLI_COMMIT="$(cd "${PROJECT_ROOT}" && git rev-parse --short=10 HEAD 2>/dev/null || echo unknown)-clang"
cmake -S "${CLI_SRC_DIR}" -B "${CLI_BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="${NDK_CLANG}/clang" \
    -DCMAKE_CXX_COMPILER="${NDK_CLANG}/clang++" \
    -DORCA_SOURCE_DIR="${ORCA_DIR}" \
    -DORCA_BUILD_DIR="${ORCA_BUILD_DIR}" \
    -DORCA_DEPS_PREFIX="${DEPS_DESTDIR}" \
    -DHANDSLICE_CLI_COMMIT="${CLI_COMMIT}"
cmake --build "${CLI_BUILD_DIR}" -j "${JOBS}" --target handslice-cli

mkdir -p "${BIN_DIR}"
install -m 0755 "${CLI_BUILD_DIR}/handslice-cli" "${BIN_DIR}/handslice-cli-x86-clang"
echo -n "${CLI_COMMIT}" > "${BIN_DIR}/handslice-cli-x86-clang.commit"
echo "--> ${BIN_DIR}/handslice-cli-x86-clang"
file "${BIN_DIR}/handslice-cli-x86-clang"
echo "HANDSLICE_CLI_COMMIT (eingebettet): ${CLI_COMMIT}"
