#!/usr/bin/env bash
# Baut handslice-cli-x86 (eigener headless CLI gegen OrcaSlicer-libslic3r)
# auf x86_64 Linux reproduzierbar.
#
# Vorgehen:
#   1. OrcaSlicer-Deps-Build (ExternalProjects, ohne wxWidgets/GLEW/OpenCSG)
#      INNERHALB von engine/OrcaSlicer/deps/build-x86 ausfuehren, damit
#      git-apply --directory die OrcaSlicer-.git als Repo-Root findet.
#   2. Orca-Hauptbuild mit SLIC3R_GUI=OFF: libslic3r + alle libslic3r_*-
#      Statik-Bibliotheken. Nur Target 'libslic3r' – OrcaSlicer-Executable
#      wird nicht gebaut (koppelt wxWidgets, siehe docs/blockers.md #1).
#   3. engine/cli/handslice-cli bauen (eigener Minimal-CLI-Main, der ohne
#      wx/GLFW/slic3r_gui auskommt) und nach engine/bin/handslice-cli-x86
#      kopieren.
#
# Keine Patches an OrcaSlicer-Upstream.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCA_DIR="${PROJECT_ROOT}/engine/OrcaSlicer"
DEPS_BUILD_DIR="${ORCA_DIR}/deps/build-x86"
DEPS_DESTDIR="${DEPS_BUILD_DIR}/OrcaSlicer_dep/usr/local"
ORCA_BUILD_DIR="${PROJECT_ROOT}/engine/build/x86"
CLI_SRC_DIR="${PROJECT_ROOT}/engine/cli"
CLI_BUILD_DIR="${PROJECT_ROOT}/engine/build/cli-x86"
BIN_DIR="${PROJECT_ROOT}/engine/bin"
JOBS="${JOBS:-$(nproc)}"

# Deps-Set: alles, was fuer libslic3r gebraucht wird; wxWidgets/GLEW/
# OpenCSG bewusst ausgelassen (nur GUI-Bedarf).
DEPS_HEADLESS=(
    dep_Boost dep_TBB dep_Cereal dep_Eigen dep_PNG dep_FREETYPE dep_JPEG
    dep_NLopt dep_GMP dep_MPFR dep_CGAL
    dep_Blosc dep_OpenEXR dep_OpenVDB
    dep_OCCT dep_Qhull dep_Draco dep_libnoise
    dep_OpenSSL dep_CURL dep_GLFW dep_OpenCV
)

echo "=== 1/4  Konfiguriere Orca-Deps (${DEPS_BUILD_DIR}) ==="
cmake -S "${ORCA_DIR}/deps" -B "${DEPS_BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DDEP_WX_GTK3=ON

echo "=== 2/4  Baue Orca-Deps (${#DEPS_HEADLESS[@]} Targets, ${JOBS} Jobs) ==="
cmake --build "${DEPS_BUILD_DIR}" -j "${JOBS}" --target "${DEPS_HEADLESS[@]}"

echo "=== 3/4  Konfiguriere + baue libslic3r (${ORCA_BUILD_DIR}) ==="
cmake -S "${ORCA_DIR}" -B "${ORCA_BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="${DEPS_DESTDIR}" \
    -DSLIC3R_GUI=OFF \
    -DSLIC3R_STATIC=1 \
    -DSLIC3R_PCH=OFF \
    -DSLIC3R_BUILD_SANDBOXES=OFF \
    -DBUILD_TESTS=OFF \
    -DORCA_TOOLS=OFF
cmake --build "${ORCA_BUILD_DIR}" -j "${JOBS}" --target libslic3r libslic3r_cgal

echo "=== 4/4  Baue handslice-cli (${CLI_BUILD_DIR}) ==="
cmake -S "${CLI_SRC_DIR}" -B "${CLI_BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DORCA_SOURCE_DIR="${ORCA_DIR}" \
    -DORCA_BUILD_DIR="${ORCA_BUILD_DIR}" \
    -DORCA_DEPS_PREFIX="${DEPS_DESTDIR}"
cmake --build "${CLI_BUILD_DIR}" -j "${JOBS}" --target handslice-cli

mkdir -p "${BIN_DIR}"
install -m 0755 "${CLI_BUILD_DIR}/handslice-cli" "${BIN_DIR}/handslice-cli-x86"
echo "--> ${BIN_DIR}/handslice-cli-x86"
file "${BIN_DIR}/handslice-cli-x86"
"${BIN_DIR}/handslice-cli-x86" --help | head -20 || true
