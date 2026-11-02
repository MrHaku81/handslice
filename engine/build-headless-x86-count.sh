#!/usr/bin/env bash
# EXPERIMENTAL — baut handslice-cli-x86-count mit -DHANDSLICE_COUNT_SPLIT_SOLID.
# Produziert eine getrennte Binary unter `engine/bin/handslice-cli-x86-count`
# ohne den Default-GCC-Build zu ueberschreiben. Standardbuild bleibt
# `engine/build-headless-x86.sh`.
#
# Zweck: Hypothese A (split_solid_surface in Fill/Fill.cpp:597-630) zur
# arm64/x86-Divergenz testen. Zaehlt pro Slice:
#   - full_narrow        = Expolygone, die am `if (inner_area.empty())`
#                          als komplett schmal klassifiziert werden
#   - mixed              = Expolygone, die partiell normal/narrow werden
#   - full_narrow_hash   = XOR aus (layer_id << 20) ^ contour[0].x
#                          ueber alle full_narrow-Entscheidungen
#   - mixed_hash         = analog fuer mixed-Entscheidungen
#
# Dump auf stderr nach `print.process()`:
#   HS_SPLIT_SOLID full_narrow=N mixed=M full_narrow_hash=0x... mixed_hash=0x...
#
# Build-Dirs sind getrennt:
#   engine/build/x86-count      (libslic3r)
#   engine/build/cli-x86-count  (handslice-cli)
#
# Keine Patches an OrcaSlicer-Upstream auf einem Zweig — Fill.cpp hat einen
# `#ifdef HANDSLICE_COUNT_SPLIT_SOLID`-Block, der im Standardbuild komplett
# aus dem Translation Unit faellt.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCA_DIR="${PROJECT_ROOT}/engine/OrcaSlicer"
DEPS_BUILD_DIR="${ORCA_DIR}/deps/build-x86"
DEPS_DESTDIR="${DEPS_BUILD_DIR}/OrcaSlicer_dep/usr/local"
ORCA_BUILD_DIR="${PROJECT_ROOT}/engine/build/x86-count"
CLI_SRC_DIR="${PROJECT_ROOT}/engine/cli"
CLI_BUILD_DIR="${PROJECT_ROOT}/engine/build/cli-x86-count"
BIN_DIR="${PROJECT_ROOT}/engine/bin"
JOBS="${JOBS:-$(nproc)}"

if [[ ! -d "${DEPS_DESTDIR}" ]]; then
    echo "FEHLT: ${DEPS_DESTDIR}" >&2
    echo "  → zuerst 'bash engine/build-headless-x86.sh' laufen lassen" >&2
    echo "    (die Deps werden vom Default-GCC-Build mitgenommen)." >&2
    exit 2
fi

EXTRA_FLAGS="-DHANDSLICE_COUNT_SPLIT_SOLID"
echo "=== 1/2  Konfiguriere + baue libslic3r (count) → ${ORCA_BUILD_DIR} ==="
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
# Same ninja-level inject as the arm64-fpoff script: CMAKE_CXX_FLAGS_INIT
# gets overwritten by Orca's own cascade, so patch each `FLAGS = ...` line.
sed -i "/^  FLAGS = / s/\$/ ${EXTRA_FLAGS}/" "${ORCA_BUILD_DIR}/build.ninja"
echo "   ${EXTRA_FLAGS} injected into every FLAGS line of build.ninja"
cmake --build "${ORCA_BUILD_DIR}" -j "${JOBS}" --target libslic3r libslic3r_cgal libnest2d

echo "=== 2/2  Baue handslice-cli (count) → ${CLI_BUILD_DIR} ==="
CLI_COMMIT="$(cd "${PROJECT_ROOT}" && git rev-parse --short=10 HEAD 2>/dev/null || echo unknown)-count"
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
install -m 0755 "${CLI_BUILD_DIR}/handslice-cli" "${BIN_DIR}/handslice-cli-x86-count"
echo -n "${CLI_COMMIT}" > "${BIN_DIR}/handslice-cli-x86-count.commit"
echo "--> ${BIN_DIR}/handslice-cli-x86-count"
file "${BIN_DIR}/handslice-cli-x86-count"
echo "HANDSLICE_CLI_COMMIT (eingebettet): ${CLI_COMMIT}"
