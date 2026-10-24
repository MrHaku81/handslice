# Wrapper-Toolchain fuer Android arm64-v8a, API 29.
#
# Grund fuer das Wrapper-File statt direkter Nutzung von
# <NDK>/build/cmake/android.toolchain.cmake: Orcas Deps-Pipeline uebergibt
# per `ExternalProject_Add` nur `CMAKE_TOOLCHAIN_FILE` an die inneren
# cmake-Aufrufe (siehe engine/OrcaSlicer/deps/CMakeLists.txt:201). Die
# Android-Varianten ANDROID_ABI / ANDROID_PLATFORM / ANDROID_STL werden
# nicht automatisch vererbt. Setzen wir sie hier als Cache-Variablen, bevor
# wir das echte NDK-Toolchain-File includen, sieht jede innere ExternalProject-
# Build dieselben Werte.
#
# Keine Zeile an OrcaSlicer-Upstream geaendert.

set(ANDROID_ABI       "arm64-v8a"  CACHE STRING "" FORCE)
set(ANDROID_PLATFORM  "android-29" CACHE STRING "" FORCE)
set(ANDROID_STL       "c++_static" CACHE STRING "" FORCE)

# NDK-Pfad standardisieren. Erlaubt Override per Umgebungsvariable
# ANDROID_NDK oder ANDROID_NDK_HOME; sonst Default aus docs/test-setup.md.
if (DEFINED ENV{ANDROID_NDK})
    set(ANDROID_NDK "$ENV{ANDROID_NDK}" CACHE PATH "" FORCE)
elseif (DEFINED ENV{ANDROID_NDK_HOME})
    set(ANDROID_NDK "$ENV{ANDROID_NDK_HOME}" CACHE PATH "" FORCE)
elseif (NOT DEFINED ANDROID_NDK)
    set(ANDROID_NDK "$ENV{HOME}/android-sdk/ndk/27.3.13750724" CACHE PATH "" FORCE)
endif ()

if (NOT EXISTS "${ANDROID_NDK}/build/cmake/android.toolchain.cmake")
    message(FATAL_ERROR
        "Android NDK nicht gefunden unter '${ANDROID_NDK}'. "
        "Entweder NDK installieren oder ANDROID_NDK als Umgebungsvariable setzen.")
endif ()

include("${ANDROID_NDK}/build/cmake/android.toolchain.cmake")

# Autotools-basierte Orca-Deps (GMP, MPFR, OpenSSL) uebergeben per
# `env CC=${CMAKE_C_COMPILER} CXX=${CMAKE_CXX_COMPILER}` an ihr `./configure`.
# Das NDK-Toolchain-File setzt CMAKE_C_COMPILER auf `clang` (ohne Triple-
# Prefix) und injiziert --target per CMAKE_C_FLAGS. Autotools kriegen die
# Flags nicht ab und das `clang++` greift auf die Host-libstdc++ zurueck –
# siehe docs/engine-integration.md Blocker-Eintrag "GMP C++ compiler".
# Fix: wir ueberschreiben die Compiler mit den prefix-gebundenen NDK-
# Wrappern (aarch64-linux-android29-clang[++]), die --target und --sysroot
# intern bereits einbaken.
set(CMAKE_C_COMPILER   "${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang"   CACHE FILEPATH "" FORCE)
set(CMAKE_CXX_COMPILER "${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang++" CACHE FILEPATH "" FORCE)

# Orcas GMP/MPFR-Recipes verwenden `--host=${TOOLCHAIN_PREFIX}` wenn
# CMAKE_CROSSCOMPILING TRUE ist. Ohne gesetzten TOOLCHAIN_PREFIX kommt
# dort `--host=` an und autotools denkt, es sei native (siehe
# dep_GMP-Blocker). Mit dem Triple ist autotools glaeucklich.
set(TOOLCHAIN_PREFIX "aarch64-linux-android" CACHE STRING "" FORCE)

# OpenCV 4.6.0 schaltet beim CMake-Configure mit `ANDROID=1` automatisch
# `BUILD_ANDROID_PROJECTS` + `BUILD_ANDROID_EXAMPLES` auf ON und zieht
# `samples/android/15-puzzle/CMakeLists.txt` rein. Das ruft
# `add_android_project()`, eine Funktion die nur verfuegbar ist, wenn
# OpenCVs AndroidSDK-Detection den SDK-Pfad gefunden hat – wir haben nur
# NDK. Dadurch failt die OpenCV-Config. OCV_OPTION respektiert eine
# vorab gesetzte Cache-Variable. Toolchain-File laeuft vor OCV_OPTION,
# also hier forcen.
set(BUILD_ANDROID_PROJECTS   OFF CACHE BOOL "" FORCE)
set(BUILD_ANDROID_EXAMPLES   OFF CACHE BOOL "" FORCE)
set(INSTALL_ANDROID_EXAMPLES OFF CACHE BOOL "" FORCE)

# OpenVDB (und einige andere Deps) verwenden das klassische `FindBoost`-
# Module statt des modernen `BoostConfig.cmake`. FindBoost schaut nach
# `BOOST_ROOT` / `BOOST_INCLUDEDIR` / `BOOST_LIBRARYDIR`, nicht an alle
# CMAKE_PREFIX_PATH-Eintraege. Beim Cross-Compile zu Android landet
# unsere Boost-Install unter dem Deps-Prefix – aber FindBoost findet sie
# dort nicht ohne Hinweis. Lesen wir die Pfade aus einer vom umgebenden
# Build-Skript exportierten Umgebungsvariable (HANDSLICE_DEPS_PREFIX).
if (DEFINED ENV{HANDSLICE_DEPS_PREFIX})
    set(_hdslice_prefix "$ENV{HANDSLICE_DEPS_PREFIX}")
    set(BOOST_ROOT       "${_hdslice_prefix}"            CACHE PATH "" FORCE)
    set(BOOST_INCLUDEDIR "${_hdslice_prefix}/include"    CACHE PATH "" FORCE)
    set(BOOST_LIBRARYDIR "${_hdslice_prefix}/lib"        CACHE PATH "" FORCE)
    # Und: Android-Toolchain setzt CMAKE_FIND_ROOT_PATH_MODE_INCLUDE/LIBRARY
    # auf ONLY (nur innerhalb von CMAKE_FIND_ROOT_PATH). Fuer unsere Deps
    # ausserhalb des NDK-Sysroots muss der Deps-Prefix in CMAKE_FIND_ROOT_PATH
    # mitgefuehrt werden, sonst findet FindBoost die Header nicht einmal mit
    # korrekten HINTS. Append statt FORCE, damit das NDK-Sysroot im Pfad
    # bleibt.
    list(APPEND CMAKE_FIND_ROOT_PATH "${_hdslice_prefix}")
    set(CMAKE_FIND_ROOT_PATH "${CMAKE_FIND_ROOT_PATH}" CACHE STRING "" FORCE)

    # OpenCV installiert sich auf Android nach `sdk/native/jni/` (nicht nach
    # `lib/cmake/opencv4/`), weil der Build-Modus Android-SDK-orientiert ist.
    # Zeigen wir OpenCV_DIR direkt dorthin, findet `find_package(OpenCV)` das
    # ABI-korrekte Config-File.
    set(OpenCV_DIR "${_hdslice_prefix}/sdk/native/jni/abi-arm64-v8a" CACHE PATH "" FORCE)
endif ()

# NDK libc++ ist strenger als GCC-libstdc++ (Host-Build) bei transitiven
# STL-Includes. Konkret fehlt in libslic3r/LocalesUtils.cpp ein `<sstream>`;
# unter GCC kommt das transitiv ueber `<iomanip>`, unter libc++ nicht.
# Statt Orca-Upstream zu patchen injizieren wir die Includes per
# -include-Header. Siehe engine/cmake/android-compat.hpp.
#
# NDK-Toolchain erbt CMAKE_CXX_FLAGS_INIT nicht sauber in alle Pfade;
# daher appenden wir direkt an CMAKE_CXX_FLAGS (nicht INIT) – sowohl im
# aktuellen Scope als auch als Cache-Variable fuer saubere Reconfigures.
set(_handslice_compat_hpp "${CMAKE_CURRENT_LIST_DIR}/android-compat.hpp")
if (EXISTS "${_handslice_compat_hpp}")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -include ${_handslice_compat_hpp}")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}" CACHE STRING "" FORCE)
endif ()
