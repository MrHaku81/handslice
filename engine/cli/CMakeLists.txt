# handslice-cli — eigener headless CLI gegen OrcaSlicer-libslic3r.
#
# Diese CMakeLists ist eigenstaendig; sie geht davon aus, dass:
#   1. OrcaSlicer-Deps unter ${ORCA_DEPS_PREFIX}/{include,lib} liegen,
#   2. Orcas Haupt-Build unter ${ORCA_BUILD_DIR} alle libslic3r_*- und
#      deps_src/*-Statik-Bibliotheken erzeugt hat.
#
# Es wird keine Zeile im OrcaSlicer-Upstream geaendert; Pfade werden per
# -D vom umgebenden Build-Skript (engine/build-headless-x86.sh) uebergeben.

cmake_minimum_required(VERSION 3.20)
project(handslice-cli CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if (NOT DEFINED ORCA_SOURCE_DIR OR NOT DEFINED ORCA_BUILD_DIR OR NOT DEFINED ORCA_DEPS_PREFIX)
    message(FATAL_ERROR "Set -DORCA_SOURCE_DIR, -DORCA_BUILD_DIR and -DORCA_DEPS_PREFIX")
endif ()

# Konsistenz: die statischen libslic3r-Libs muessen schon da sein.
set(_libslic3r      ${ORCA_BUILD_DIR}/src/libslic3r/liblibslic3r.a)
set(_libslic3r_cgal ${ORCA_BUILD_DIR}/src/libslic3r/liblibslic3r_cgal.a)
if (NOT EXISTS ${_libslic3r})
    message(FATAL_ERROR "liblibslic3r.a nicht gefunden unter ${_libslic3r}. "
                        "Bitte zuerst 'cmake --build ${ORCA_BUILD_DIR} --target libslic3r' laufen lassen.")
endif ()

add_executable(handslice-cli
    handslice-cli.cpp
    nanosvg_impl.cpp
)

# HANDSLICE_CLI_COMMIT: Repo-HEAD-Kurz-Hash, in die Binary einkompiliert.
# Vom umgebenden Build-Skript via -DHANDSLICE_CLI_COMMIT=<hash> gesetzt;
# als Fallback hier aus git abfragen, damit lokale Builds nicht leer sind.
if (NOT DEFINED HANDSLICE_CLI_COMMIT)
    execute_process(
        COMMAND git rev-parse --short=10 HEAD
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        OUTPUT_VARIABLE HANDSLICE_CLI_COMMIT
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if (NOT HANDSLICE_CLI_COMMIT)
        set(HANDSLICE_CLI_COMMIT "unknown")
    endif ()
endif ()
message(STATUS "handslice-cli commit: ${HANDSLICE_CLI_COMMIT}")
target_compile_definitions(handslice-cli PRIVATE
    HANDSLICE_CLI_COMMIT="${HANDSLICE_CLI_COMMIT}"
)

target_include_directories(handslice-cli SYSTEM PRIVATE
    ${ORCA_SOURCE_DIR}/src
    ${ORCA_SOURCE_DIR}/deps_src
    ${ORCA_SOURCE_DIR}/deps_src/libigl
    ${ORCA_BUILD_DIR}/src
    ${ORCA_BUILD_DIR}/src/libslic3r
    ${ORCA_BUILD_DIR}/src/platform
    ${ORCA_DEPS_PREFIX}/include
    ${ORCA_DEPS_PREFIX}/include/eigen3
    ${ORCA_DEPS_PREFIX}/include/opencv4
    ${ORCA_DEPS_PREFIX}/include/OpenEXR
    ${ORCA_DEPS_PREFIX}/include/opencascade
)

# Dieselbe Reihenfolge wie Orcas eigenes OrcaSlicer-Executable (abgeleitet
# aus build.ninja), minus wxWidgets/GLFW/slic3r_gui. Statisch linken.
target_link_libraries(handslice-cli PRIVATE
    # Core libslic3r + Orca-interne Statik-Libs
    ${_libslic3r}
    ${ORCA_BUILD_DIR}/deps_src/libnest2d/liblibnest2d.a
    ${_libslic3r}
    ${ORCA_BUILD_DIR}/deps_src/libnest2d/liblibnest2d.a
    ${ORCA_BUILD_DIR}/deps_src/miniz/libminiz_static.a
    ${_libslic3r_cgal}
    ${ORCA_BUILD_DIR}/deps_src/admesh/libadmesh.a
    ${ORCA_BUILD_DIR}/deps_src/clipper/libclipper.a
    ${ORCA_BUILD_DIR}/deps_src/clipper2/libClipper2.a
    ${ORCA_BUILD_DIR}/deps_src/glu-libtess/libglu-libtess.a
    ${ORCA_BUILD_DIR}/deps_src/mcut/libmcut.a
    ${ORCA_BUILD_DIR}/deps_src/qoi/libqoi.a
    ${ORCA_BUILD_DIR}/lib/libsemver.a

    # OpenCV world + mitgebrachtes libpng (statisch). Auf Android installiert
    # Orcas OpenCV-Recipe nach `sdk/native/staticlibs/arm64-v8a/` + den 3rd-
    # Party-Mitbringseln unter `sdk/native/3rdparty/libs/arm64-v8a/`, nicht
    # unter `lib/opencv4/3rdparty/` wie auf Linux. Deshalb pfadabhaengig
    # auswaehlen.
    $<$<STREQUAL:${CMAKE_SYSTEM_NAME},Android>:${ORCA_DEPS_PREFIX}/sdk/native/staticlibs/arm64-v8a/libopencv_world.a>
    $<$<STREQUAL:${CMAKE_SYSTEM_NAME},Android>:${ORCA_DEPS_PREFIX}/sdk/native/3rdparty/libs/arm64-v8a/liblibpng.a>
    $<$<STREQUAL:${CMAKE_SYSTEM_NAME},Android>:${ORCA_DEPS_PREFIX}/sdk/native/3rdparty/libs/arm64-v8a/libcpufeatures.a>
    $<$<STREQUAL:${CMAKE_SYSTEM_NAME},Android>:${ORCA_DEPS_PREFIX}/sdk/native/3rdparty/libs/arm64-v8a/libtegra_hal.a>
    $<$<NOT:$<STREQUAL:${CMAKE_SYSTEM_NAME},Android>>:${ORCA_DEPS_PREFIX}/lib/libopencv_world.a>
    $<$<NOT:$<STREQUAL:${CMAKE_SYSTEM_NAME},Android>>:${ORCA_DEPS_PREFIX}/lib/opencv4/3rdparty/liblibpng.a>

    # OpenCascade (STEP-Import)
    ${ORCA_DEPS_PREFIX}/lib/libTKXDESTEP.a
    ${ORCA_DEPS_PREFIX}/lib/libTKSTEP.a
    ${ORCA_DEPS_PREFIX}/lib/libTKSTEP209.a
    ${ORCA_DEPS_PREFIX}/lib/libTKSTEPAttr.a
    ${ORCA_DEPS_PREFIX}/lib/libTKSTEPBase.a
    ${ORCA_DEPS_PREFIX}/lib/libTKXCAF.a
    ${ORCA_DEPS_PREFIX}/lib/libTKXSBase.a
    ${ORCA_DEPS_PREFIX}/lib/libTKVCAF.a
    ${ORCA_DEPS_PREFIX}/lib/libTKCAF.a
    ${ORCA_DEPS_PREFIX}/lib/libTKLCAF.a
    ${ORCA_DEPS_PREFIX}/lib/libTKCDF.a
    ${ORCA_DEPS_PREFIX}/lib/libTKV3d.a
    ${ORCA_DEPS_PREFIX}/lib/libTKService.a
    ${ORCA_DEPS_PREFIX}/lib/libTKMesh.a
    ${ORCA_DEPS_PREFIX}/lib/libTKBO.a
    ${ORCA_DEPS_PREFIX}/lib/libTKPrim.a
    ${ORCA_DEPS_PREFIX}/lib/libTKHLR.a
    ${ORCA_DEPS_PREFIX}/lib/libTKShHealing.a
    ${ORCA_DEPS_PREFIX}/lib/libTKTopAlgo.a
    ${ORCA_DEPS_PREFIX}/lib/libTKGeomAlgo.a
    ${ORCA_DEPS_PREFIX}/lib/libTKBRep.a
    ${ORCA_DEPS_PREFIX}/lib/libTKGeomBase.a
    ${ORCA_DEPS_PREFIX}/lib/libTKG3d.a
    ${ORCA_DEPS_PREFIX}/lib/libTKG2d.a
    ${ORCA_DEPS_PREFIX}/lib/libTKMath.a
    ${ORCA_DEPS_PREFIX}/lib/libTKernel.a

    # Draco (3mf-Mesh-Komprimierung)
    ${ORCA_DEPS_PREFIX}/lib/libdraco.a

    # Boost (statisch, gleicher Satz wie Orca)
    ${ORCA_DEPS_PREFIX}/lib/libboost_log_setup.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_log.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_filesystem.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_coroutine.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_context.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_serialization.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_locale.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_thread.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_chrono.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_atomic.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_date_time.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_exception.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_program_options.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_container.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_nowide.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_iostreams.a
    ${ORCA_DEPS_PREFIX}/lib/libboost_random.a

    # GMP/MPFR fuer CGAL
    ${ORCA_DEPS_PREFIX}/lib/libgmpxx.a
    ${ORCA_DEPS_PREFIX}/lib/libmpfr.a
    ${ORCA_DEPS_PREFIX}/lib/libgmp.a

    # libnoise (Textur-Prozedurales fuer manche Infill-Patterns)
    ${ORCA_DEPS_PREFIX}/lib/liblibnoise_static.a

    # Standalone libpng, Qhull, FREETYPE
    ${ORCA_DEPS_PREFIX}/lib/libpng.a
    ${ORCA_DEPS_PREFIX}/lib/libqhullcpp.a
    ${ORCA_DEPS_PREFIX}/lib/libqhullstatic_r.a
    ${ORCA_DEPS_PREFIX}/lib/libfreetype.a

    # OpenVDB (+ IlmBase Half + Blosc)
    ${ORCA_DEPS_PREFIX}/lib/libopenvdb.a
    ${ORCA_DEPS_PREFIX}/lib/libHalf-2_5.a
    ${ORCA_DEPS_PREFIX}/lib/libblosc.a

    # TBB
    ${ORCA_DEPS_PREFIX}/lib/libtbbmalloc.a
    ${ORCA_DEPS_PREFIX}/lib/libtbb.a

    # OpenSSL (crypto fuer Hashing in Orca-Interna)
    ${ORCA_DEPS_PREFIX}/lib/libcrypto.a

    # NLopt
    ${ORCA_DEPS_PREFIX}/lib/libnlopt.a

)

# System- und Deps-Libs, die unter Linux und Android unterschiedlich liegen.
# Auf Linux greifen wir fuer expat/jpeg/lzma/z/fontconfig auf System-Libs
# zurueck (CachyOS stellt sie als .so). Auf Android gibt es keine System-
# expat/jpeg/lzma/fontconfig, also wird gegen die statischen Varianten
# aus dem Orca-Deps-Prefix (plus dem fontconfig-Stub aus
# engine/build-deps-arm64.sh) gelinkt. libz ist auf Android eine stabile
# System-Lib (`libz.so` aus Bionic/NDK-Sysroot), lzma wird auf Android
# weggelassen – Freetype ist dort via `FT_DISABLE_*` ohne lzma gebaut
# (siehe engine/OrcaSlicer/deps/FREETYPE/FREETYPE.cmake:10). pthread/dl/m
# sind auf Android Teil von Bionic libc und werden ueber die
# Standard-Linker-Namen eingezogen.
if (CMAKE_SYSTEM_NAME STREQUAL "Android")
    target_link_libraries(handslice-cli PRIVATE
        ${ORCA_DEPS_PREFIX}/lib/libexpat.a
        ${ORCA_DEPS_PREFIX}/lib/libjpeg.a
        ${ORCA_DEPS_PREFIX}/lib/libfontconfig.a
        z
        log
        dl
        m
    )
else ()
    target_link_libraries(handslice-cli PRIVATE
        /usr/lib/libexpat.so
        /usr/lib/libjpeg.so
        /usr/lib/liblzma.so
        /usr/lib/libz.so
        fontconfig
        pthread
        dl
        m
    )
endif ()

install(TARGETS handslice-cli RUNTIME DESTINATION bin)
