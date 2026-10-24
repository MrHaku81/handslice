#!/usr/bin/env bash
# Baut OrcaSlicer-Upstream auf x86_64 Linux ohne wxWidgets/GUI reproduzierbar.
#
# Vorgehen:
#   1. Deps-Build (ExternalProjects) INNERHALB von engine/OrcaSlicer/deps/
#      ausfuehren, damit git-apply --directory die OrcaSlicer-.git als
#      Repo-Root findet und BINARY_DIR_REL relativ dazu aufloesen kann.
#      Grund: unter uns liegt handslice/.git; git-apply laeuft sonst gegen
#      das umgebende Repo und wirft 'unable to normalize directory'.
#   2. Hauptbuild mit SLIC3R_GUI=OFF nach engine/build/x86. Ziel 'OrcaSlicer'
#      genuegt; libslic3r wird transitiv mitgebaut.
#   3. Binary nach engine/bin/orca-slicer-x86 kopieren (gitignored).
#
# Keine Patches an OrcaSlicer-Upstream, keine Hersteller-Fork-Diffs.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCA_DIR="${PROJECT_ROOT}/engine/OrcaSlicer"
DEPS_BUILD_DIR="${ORCA_DIR}/deps/build-x86"
DEPS_DESTDIR="${DEPS_BUILD_DIR}/OrcaSlicer_dep/usr/local"
BUILD_DIR="${PROJECT_ROOT}/engine/build/x86"
BIN_DIR="${PROJECT_ROOT}/engine/bin"
JOBS="${JOBS:-$(nproc)}"

# Diese Deps baut die GUI-freie Variante nicht: wxWidgets (keine GUI),
# GLEW/OpenCSG (nur GUI-Rendering).
DEPS_HEADLESS=(
    dep_Boost dep_TBB dep_Cereal dep_Eigen dep_PNG dep_FREETYPE dep_JPEG
    dep_NLopt dep_GMP dep_MPFR dep_CGAL
    dep_Blosc dep_OpenEXR dep_OpenVDB
    dep_OCCT dep_Qhull dep_Draco dep_libnoise
    dep_OpenSSL dep_CURL dep_GLFW dep_OpenCV
)

echo "=== 1/3  Konfiguriere Deps-Build (${DEPS_BUILD_DIR}) ==="
cmake -S "${ORCA_DIR}/deps" -B "${DEPS_BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DDEP_WX_GTK3=ON

echo "=== 2/3  Baue Deps (${#DEPS_HEADLESS[@]} Targets, ${JOBS} Jobs) ==="
cmake --build "${DEPS_BUILD_DIR}" -j "${JOBS}" --target "${DEPS_HEADLESS[@]}"

echo "=== 3/3  Konfiguriere + baue Hauptbuild ==="
cmake -S "${ORCA_DIR}" -B "${BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="${DEPS_DESTDIR}" \
    -DSLIC3R_GUI=OFF \
    -DSLIC3R_STATIC=1 \
    -DSLIC3R_PCH=OFF \
    -DSLIC3R_BUILD_SANDBOXES=OFF \
    -DBUILD_TESTS=OFF \
    -DORCA_TOOLS=OFF

cmake --build "${BUILD_DIR}" -j "${JOBS}" --target OrcaSlicer

mkdir -p "${BIN_DIR}"
install -m 0755 "${BUILD_DIR}/src/orca-slicer" "${BIN_DIR}/orca-slicer-x86"
echo "--> ${BIN_DIR}/orca-slicer-x86"
file "${BIN_DIR}/orca-slicer-x86"
"${BIN_DIR}/orca-slicer-x86" --help | head -20 || true
