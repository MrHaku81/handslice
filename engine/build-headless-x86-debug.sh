#!/usr/bin/env bash
# EXPERIMENTAL — baut handslice-cli-x86-debug: dieselbe Konfiguration
# wie Standard x86 (GCC Release, -O3) PLUS -g, damit Valgrind in den
# Fill-Pfad hineinschauen kann (file:line + origin).
#
# Produziert eine getrennte Binary unter `engine/bin/handslice-cli-x86-debug`
# ohne den Default-GCC-Build zu ueberschreiben. Standardbuild bleibt
# `engine/build-headless-x86.sh`.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCA_DIR="${PROJECT_ROOT}/engine/OrcaSlicer"
DEPS_BUILD_DIR="${ORCA_DIR}/deps/build-x86"
DEPS_DESTDIR="${DEPS_BUILD_DIR}/OrcaSlicer_dep/usr/local"
ORCA_BUILD_DIR="${PROJECT_ROOT}/engine/build/x86-debug"
CLI_SRC_DIR="${PROJECT_ROOT}/engine/cli"
CLI_BUILD_DIR="${PROJECT_ROOT}/engine/build/cli-x86-debug"
BIN_DIR="${PROJECT_ROOT}/engine/bin"
JOBS="${JOBS:-$(nproc)}"

if [[ ! -d "${DEPS_DESTDIR}" ]]; then
    echo "FEHLT: ${DEPS_DESTDIR}" >&2
    echo "  -> zuerst 'bash engine/build-headless-x86.sh' laufen lassen." >&2
    exit 2
fi

# -g in CMAKE_CXX_FLAGS_RELEASE haengt an die Release-Standards (O3,
# NDEBUG). Also keine andere Optimierung als beim Standard-Build, nur
# Debug-Symbole dran. -fno-omit-frame-pointer macht Valgrind-Backtraces
# praktikabler.
EXTRA_FLAGS="-g -fno-omit-frame-pointer"
echo "=== 1/2  Konfiguriere + baue libslic3r (debug) nach ${ORCA_BUILD_DIR} ==="
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

echo "=== 2/2  Baue handslice-cli (debug) nach ${CLI_BUILD_DIR} ==="
CLI_COMMIT="$(cd "${PROJECT_ROOT}" && git rev-parse --short=10 HEAD 2>/dev/null || echo unknown)-debug"
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
install -m 0755 "${CLI_BUILD_DIR}/handslice-cli" "${BIN_DIR}/handslice-cli-x86-debug"
echo -n "${CLI_COMMIT}" > "${BIN_DIR}/handslice-cli-x86-debug.commit"
echo "--> ${BIN_DIR}/handslice-cli-x86-debug"
file "${BIN_DIR}/handslice-cli-x86-debug"
echo "HANDSLICE_CLI_COMMIT (eingebettet): ${CLI_COMMIT}"
