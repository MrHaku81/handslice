#!/usr/bin/env bash
# Baut die OrcaSlicer-Deps fuer Android arm64-v8a (API 29) mit dem NDK r27d
# nach engine/OrcaSlicer/deps/build-arm64. Pendant zu build-headless-x86.sh,
# aber als Cross-Compile.
#
# Vorgehen:
#   1. ExternalProjects aus Orcas deps/ mit NDK-Wrapper-Toolchain konfigurieren.
#      Build-Dir liegt INNERHALB von engine/OrcaSlicer/deps/, damit `git apply`
#      beim Patchen der Deps die Orca-.git als Repo-Root findet (siehe
#      docs/engine-integration.md, Stolperstein x86-Build).
#   2. Nur die laut Audit noetigen Deps bauen (siehe docs/engine-integration.md,
#      Abschnitt "Dep-Audit vor dem Cross-Build"). GLFW und CURL werden
#      weggelassen – libslic3r referenziert sie nicht, und auf Android
#      existieren sie ohnehin nicht.
#   3. fontconfig-Stub als leeres statisches Archiv im Deps-Prefix anlegen.
#      libslic3r/CMakeLists.txt:613 linkt hartkodiert `fontconfig` unter
#      `NOT APPLE AND NOT WIN32`. OCCT selbst setzt auf Android keinen
#      fontconfig-CSF (occt_csf.cmake:135: `CSF_androidlog`), ruft also
#      keine Symbole – Linker ist mit dem leeren Archive zufrieden.
#
# Keine Patches an OrcaSlicer-Upstream.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCA_DIR="${PROJECT_ROOT}/engine/OrcaSlicer"
DEPS_BUILD_DIR="${ORCA_DIR}/deps/build-arm64"
DEPS_DESTDIR="${DEPS_BUILD_DIR}/OrcaSlicer_dep/usr/local"
TOOLCHAIN_FILE="${PROJECT_ROOT}/engine/cmake/android-arm64.toolchain.cmake"
JOBS="${JOBS:-$(nproc)}"

# NDK-Pfad aus docs/test-setup.md; via Env ueberschreibbar.
export ANDROID_NDK="${ANDROID_NDK:-$HOME/android-sdk/ndk/27.3.13750724}"
if [[ ! -x "${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang" ]]; then
    echo "FEHLER: NDK clang nicht gefunden unter ${ANDROID_NDK}" >&2
    echo "       Bitte Pfad per ANDROID_NDK anpassen (siehe docs/test-setup.md)." >&2
    exit 1
fi

# Fuer das Toolchain-File (siehe engine/cmake/android-arm64.toolchain.cmake):
# OpenVDBs CMake benutzt das klassische FindBoost und findet die Install
# unter DEPS_DESTDIR nur, wenn BOOST_ROOT explizit gesetzt ist. Umweg ueber
# Umgebungsvariable, weil der Toolchain-File DEPS_DESTDIR nicht kennt.
export HANDSLICE_DEPS_PREFIX="${DEPS_DESTDIR}"

# Audit-Ergebnis: 19 Deps ueber Orcas CMake-Pipeline (x86-Liste minus GLFW,
# minus CURL, minus OpenSSL, plus EXPAT weil auf Android nicht System-
# vorhanden). dep_EXPAT wird von Orcas Deps-CMakeLists automatisch registriert,
# wenn find_package(EXPAT) fehlschlaegt (deps/CMakeLists.txt:330). Auf dem
# NDK ist das immer der Fall.
#
# OpenSSL wird separat gebaut (siehe Schritt 4 unten): Orcas OpenSSL.cmake:34
# haengt sein Cross-Compile an `--cross-compile-prefix=${TOOLCHAIN_PREFIX}-`,
# aber TOOLCHAIN_PREFIX wird nirgends im Orca-Baum gesetzt – OpenSSL kriegt
# dann `--cross-compile-prefix=-` als Flag, was dessen Configure-Script
# korrekt mit „./config failed" quittiert. Statt Orca zu patchen bauen wir
# OpenSSL einmal manuell mit NDK-Clang und `./Configure android-arm64`.
# Alle 19 Deps-Targets, die wir laut Audit brauchen. Von denen sind sechs
# (dep_PNG, dep_JPEG, dep_FREETYPE, dep_EXPAT, plus optional dep_OpenSSL und
# dep_CURL die wir eh nicht listen) in Orcas deps/CMakeLists.txt nur
# conditional registriert – sie entfallen beim Reconfigure, sobald die
# installierte Variante via `CMAKE_FIND_ROOT_PATH` (siehe Toolchain-File)
# gefunden wird. Darum filtern wir nach dem Configure die tatsaechlich
# noch vorhandenen Targets per `cmake --build --target help`.
DEPS_ARM64=(
    dep_Boost dep_TBB dep_Cereal dep_Eigen
    dep_PNG dep_FREETYPE dep_JPEG dep_EXPAT
    dep_NLopt dep_GMP dep_MPFR dep_CGAL
    dep_Blosc dep_OpenEXR dep_OpenVDB
    dep_OCCT dep_Qhull dep_Draco dep_libnoise
    dep_OpenCV
)

echo "=== 1/3  Konfiguriere Orca-Deps (${DEPS_BUILD_DIR}) ==="
# CMAKE_MODULE_PATH mit android-shims/, damit `find_package(OpenGL REQUIRED)`
# in GLEW/GLEW.cmake:3 nicht fehlschlaegt – auf Android gibt es kein
# Desktop-OpenGL, und GLEW/GLFW/OpenCSG werden eh nicht gebaut (siehe
# Audit in docs/engine-integration.md). Die unconditionale include()-Kette
# in deps/CMakeLists.txt kommt nur zur Configure-Zeit vorbei.
cmake -S "${ORCA_DIR}/deps" -B "${DEPS_BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DCMAKE_MODULE_PATH="${PROJECT_ROOT}/engine/cmake/android-shims" \
    -DDEP_WX_GTK3=OFF

echo "=== 2/4  Baue Orca-Deps (bis zu ${#DEPS_ARM64[@]} Targets, ${JOBS} Jobs) ==="
# Smart-Filter: condition-registered Targets (dep_PNG, dep_FREETYPE,
# dep_JPEG, dep_EXPAT) verschwinden beim Reconfigure, sobald find_package
# die bereits installierten Varianten findet. Ermitteln ueber
# `ninja -t targets all` und schneiden unsere Wunschliste darauf zu.
mapfile -t available_targets < <(
    ninja -C "${DEPS_BUILD_DIR}" -t targets all 2>/dev/null \
        | awk -F ':' '/^dep_[A-Za-z0-9]+: phony$/{print $1}' | sort -u
)
if ((${#available_targets[@]} == 0)); then
    echo "WARN: Konnte Target-Liste nicht ermitteln – baue mit voller Liste." >&2
    build_targets=("${DEPS_ARM64[@]}")
else
    build_targets=()
    skipped=()
    for t in "${DEPS_ARM64[@]}"; do
        is_available=0
        for a in "${available_targets[@]}"; do
            [[ "${t}" == "${a}" ]] && { is_available=1; break; }
        done
        if ((is_available == 1)); then
            build_targets+=("${t}")
        else
            skipped+=("${t}")
        fi
    done
    if ((${#skipped[@]} > 0)); then
        echo "    Bereits installiert (via find_package aufgeloest), ueberspringen: ${skipped[*]}"
    fi
fi
cmake --build "${DEPS_BUILD_DIR}" -j "${JOBS}" --target "${build_targets[@]}"

echo "=== 3/4  Baue OpenSSL 1.1.1w fuer android-arm64 (manuell) ==="
OPENSSL_SRC="${DEPS_BUILD_DIR}/openssl-manual-src"
OPENSSL_TARBALL="${ORCA_DIR}/deps/DL_CACHE/OpenSSL/OpenSSL_1_1_1w.tar.gz"
if [[ ! -f "${OPENSSL_TARBALL}" ]]; then
    echo "FEHLT: ${OPENSSL_TARBALL}" >&2
    echo "       (Erwartet aus Orcas DL_CACHE – zuerst Deps-Konfigure laufen)" >&2
    exit 1
fi
if [[ ! -d "${OPENSSL_SRC}" ]]; then
    mkdir -p "${OPENSSL_SRC}"
    tar -C "${OPENSSL_SRC}" --strip-components=1 -xzf "${OPENSSL_TARBALL}"
fi
(
    cd "${OPENSSL_SRC}"
    # NDK-Toolchain in PATH, damit OpenSSLs eigenes `./Configure android-arm64`
    # die Prefix-losen clang/ar/ranlib findet.
    export ANDROID_NDK_ROOT="${ANDROID_NDK}"
    export PATH="${NDK_BIN:=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin}:${PATH}"
    if [[ ! -f Makefile ]]; then
        ./Configure android-arm64 \
            -D__ANDROID_API__=29 \
            no-shared no-asm no-ssl3-method no-dynamic-engine \
            --prefix="${DEPS_DESTDIR}" \
            --openssldir="${DEPS_DESTDIR}"
    fi
    # build_libs reicht fuer libcrypto.a + libssl.a; install_sw erledigt
    # Header + Pkg-Config + CMake-Config nach ${DEPS_DESTDIR}.
    make -j"${JOBS}" build_libs
    make install_sw
)

NDK_BIN="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin"

echo "=== 4a/4  Erzeuge glfw3- + CURL-Stubs im Deps-Prefix ==="
# OrcaSlicers root-CMakeLists macht `find_package(glfw3 REQUIRED)` an einer
# Stelle vor allen `SLIC3R_GUI`-Guards (CMakeLists.txt:698). GLFW wird in
# libslic3r selbst nirgends referenziert; nur `OrcaSlicer.cpp` + `slic3r/GUI`
# nutzen es fuer Thumbnail-OpenGL. Statt echtes GLFW fuer Android zu bauen
# (geht nicht offiziell), stellen wir einen minimalen `glfw3Config.cmake`
# in `${DEPS_DESTDIR}/lib/cmake/glfw3/` bereit, der nur das Imported-Target
# `glfw` als `INTERFACE` ohne Libs/Includes bereitstellt. find_package(glfw3)
# findet es, libslic3r.a hat keine GLFW-Symbole – alles clean.
GLFW_STUB_DIR="${DEPS_DESTDIR}/lib/cmake/glfw3"
mkdir -p "${GLFW_STUB_DIR}"
cat > "${GLFW_STUB_DIR}/glfw3Config.cmake" <<'EOF'
# Handslice-Stub (siehe engine/build-deps-arm64.sh + docs/engine-integration.md)
set(glfw3_VERSION 3.4)
set(glfw3_FOUND TRUE)
if (NOT TARGET glfw)
    add_library(glfw INTERFACE IMPORTED)
endif ()
EOF
cat > "${GLFW_STUB_DIR}/glfw3ConfigVersion.cmake" <<'EOF'
set(PACKAGE_VERSION "3.4")
set(PACKAGE_VERSION_EXACT TRUE)
set(PACKAGE_VERSION_COMPATIBLE TRUE)
EOF

# OrcaSlicers root-CMakeLists macht `find_package(CURL REQUIRED)` an einer
# Stelle vor allen `SLIC3R_GUI`-Guards (CMakeLists.txt:633). CURL wird in
# libslic3r selbst nirgends referenziert (grep in src/libslic3r/ ergibt
# keine Fundstelle), nur im nicht-gebauten slic3r/GUI-Baum. Statt
# richtiges libcurl fuer Android zu bauen stellen wir einen minimalen
# Header + leeres Archive bereit; find_package(CURL) ist zufrieden und
# libslic3r.a referenziert spaeter keine CURL-Symbole.
CURL_STUB_DIR="${DEPS_BUILD_DIR}/curl-stub"
mkdir -p "${CURL_STUB_DIR}" "${DEPS_DESTDIR}/include/curl"
cat > "${DEPS_DESTDIR}/include/curl/curl.h" <<'EOF'
/* CURL-Header-Stub fuer Android-Headless-libslic3r. Siehe
 * engine/build-deps-arm64.sh und docs/engine-integration.md.
 * Minimale Typ-Deklarationen, damit find_package(CURL) zufrieden ist.
 * libslic3r/* includet dies nicht; slic3r/GUI (nicht gebaut) tut es. */
#ifndef HANDSLICE_CURL_STUB_H
#define HANDSLICE_CURL_STUB_H
#define LIBCURL_VERSION_MAJOR 7
#define LIBCURL_VERSION_MINOR 85
#define LIBCURL_VERSION_PATCH 0
#define LIBCURL_VERSION "7.85.0"
#endif
EOF
cat > "${CURL_STUB_DIR}/curl_stub.c" <<'EOF'
__attribute__((visibility("default"))) int _handslice_curl_stub(void) { return 0; }
EOF
"${NDK_BIN}/aarch64-linux-android29-clang" -c -fPIC \
    -o "${CURL_STUB_DIR}/curl_stub.o" "${CURL_STUB_DIR}/curl_stub.c"
rm -f "${DEPS_DESTDIR}/lib/libcurl.a"
"${NDK_BIN}/llvm-ar" rcs "${DEPS_DESTDIR}/lib/libcurl.a" "${CURL_STUB_DIR}/curl_stub.o"

echo "=== 4b/4  Erzeuge fontconfig-Stub im Deps-Prefix ==="
# Siehe Erklaerung im Script-Kopf. Leeres Objekt in ein Archiv packen.
STUB_DIR="${DEPS_BUILD_DIR}/fontconfig-stub"
mkdir -p "${STUB_DIR}"
cat > "${STUB_DIR}/fontconfig_stub.c" <<'EOF'
/* fontconfig-Stub fuer Android-Headless-libslic3r. Siehe
 * engine/build-deps-arm64.sh und docs/engine-integration.md. OCCT auf
 * Android ruft keine fontconfig-Symbole; dieses Archive befriedigt nur
 * das -lfontconfig im libslic3r-Link. */
__attribute__((visibility("default"))) int _handslice_fontconfig_stub(void) { return 0; }
EOF
"${NDK_BIN}/aarch64-linux-android29-clang" -c -fPIC \
    -o "${STUB_DIR}/fontconfig_stub.o" "${STUB_DIR}/fontconfig_stub.c"
mkdir -p "${DEPS_DESTDIR}/lib"
rm -f "${DEPS_DESTDIR}/lib/libfontconfig.a"
"${NDK_BIN}/llvm-ar" rcs "${DEPS_DESTDIR}/lib/libfontconfig.a" "${STUB_DIR}/fontconfig_stub.o"

echo "--> Deps unter ${DEPS_DESTDIR}"
echo "    (eine Stichprobe)"
file "${DEPS_DESTDIR}/lib/libboost_filesystem.a" 2>/dev/null || true
file "${DEPS_DESTDIR}/lib/libfontconfig.a"
ls -1 "${DEPS_DESTDIR}/lib/"*.a | wc -l | xargs -I {} echo "    {} .a Dateien insgesamt"
