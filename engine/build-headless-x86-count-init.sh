#!/usr/bin/env bash
# EXPERIMENTAL — baut handslice-cli-x86-count-<pattern|zero> mit
# -ftrivial-auto-var-init=<mode> UND -DHANDSLICE_COUNT_SPLIT_SOLID.
#
# Zweck: Stufe-3c Entscheidungstest — nach den drei committed fixes
# (PolyNode, WallToolPathsParams, Print::m_origin + layer_thickness,
# mmuseg_ts) auf arm64-Divergenz-Experiment-Branch 3965b4904c pruefen,
# ob der verbleibende arm64/x86-Pfad-Gap durch eine uninit-Stack-
# Variable getrieben wird oder eine Plattform-FP-Divergenz ist.
#
# GCC seit 12 unterstuetzt -ftrivial-auto-var-init=pattern|zero. Dieses
# Build-Skript ist das x86-Pendant zu engine/build-cli-arm64-count-init.sh.
#
# Benutzung:
#   bash engine/build-headless-x86-count-init.sh pattern
#   bash engine/build-headless-x86-count-init.sh zero
#
# Produziert handslice-cli-x86-count-<mode> unter engine/bin/,
# ohne Default-Builds zu beruehren. Standardbuild bleibt
# `engine/build-headless-x86.sh`.

set -euo pipefail

if [[ $# -ne 1 || ( "$1" != "pattern" && "$1" != "zero" ) ]]; then
    echo "Usage: $0 <pattern|zero>" >&2
    exit 2
fi
MODE="$1"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCA_DIR="${PROJECT_ROOT}/engine/OrcaSlicer"
DEPS_BUILD_DIR="${ORCA_DIR}/deps/build-x86"
DEPS_DESTDIR="${DEPS_BUILD_DIR}/OrcaSlicer_dep/usr/local"
ORCA_BUILD_DIR="${PROJECT_ROOT}/engine/build/x86-count-${MODE}"
CLI_SRC_DIR="${PROJECT_ROOT}/engine/cli"
CLI_BUILD_DIR="${PROJECT_ROOT}/engine/build/cli-x86-count-${MODE}"
BIN_DIR="${PROJECT_ROOT}/engine/bin"
JOBS="${JOBS:-$(nproc)}"

if [[ ! -d "${DEPS_DESTDIR}" ]]; then
    echo "FEHLT: ${DEPS_DESTDIR}" >&2
    echo "  -> zuerst 'bash engine/build-headless-x86.sh' laufen lassen." >&2
    exit 2
fi

EXTRA_FLAGS="-DHANDSLICE_COUNT_SPLIT_SOLID -ftrivial-auto-var-init=${MODE}"
echo "=== 1/2  Konfiguriere + baue libslic3r (count+init=${MODE}) nach ${ORCA_BUILD_DIR} ==="
cmake -S "${ORCA_DIR}" -B "${ORCA_BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="${DEPS_DESTDIR}" \
    -DCMAKE_CXX_FLAGS_INIT="${EXTRA_FLAGS}" \
    -DCMAKE_C_FLAGS_INIT="${EXTRA_FLAGS}" \
    -DSLIC3R_GUI=OFF \
    -DSLIC3R_STATIC=1 \
    -DSLIC3R_PCH=OFF \
    -DSLIC3R_BUILD_SANDBOXES=OFF \
    -DBUILD_TESTS=OFF \
    -DORCA_TOOLS=OFF
sed -i "/^  FLAGS = / s/\$/ ${EXTRA_FLAGS}/" "${ORCA_BUILD_DIR}/build.ninja"
echo "   ${EXTRA_FLAGS} injected into every FLAGS line of build.ninja"
cmake --build "${ORCA_BUILD_DIR}" -j "${JOBS}" --target libslic3r libslic3r_cgal libnest2d

echo "=== 2/2  Baue handslice-cli (count+init=${MODE}) nach ${CLI_BUILD_DIR} ==="
CLI_COMMIT="$(cd "${PROJECT_ROOT}" && git rev-parse --short=10 HEAD 2>/dev/null || echo unknown)-count-${MODE}"
cmake -S "${CLI_SRC_DIR}" -B "${CLI_BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS_INIT="${EXTRA_FLAGS}" \
    -DCMAKE_C_FLAGS_INIT="${EXTRA_FLAGS}" \
    -DORCA_SOURCE_DIR="${ORCA_DIR}" \
    -DORCA_BUILD_DIR="${ORCA_BUILD_DIR}" \
    -DORCA_DEPS_PREFIX="${DEPS_DESTDIR}" \
    -DHANDSLICE_CLI_COMMIT="${CLI_COMMIT}"
sed -i "/^  FLAGS = / s/\$/ ${EXTRA_FLAGS}/" "${CLI_BUILD_DIR}/build.ninja"
cmake --build "${CLI_BUILD_DIR}" -j "${JOBS}" --target handslice-cli

mkdir -p "${BIN_DIR}"
install -m 0755 "${CLI_BUILD_DIR}/handslice-cli" "${BIN_DIR}/handslice-cli-x86-count-${MODE}"
echo -n "${CLI_COMMIT}" > "${BIN_DIR}/handslice-cli-x86-count-${MODE}.commit"
echo "--> ${BIN_DIR}/handslice-cli-x86-count-${MODE}"
file "${BIN_DIR}/handslice-cli-x86-count-${MODE}"
echo "HANDSLICE_CLI_COMMIT (eingebettet): ${CLI_COMMIT}"
