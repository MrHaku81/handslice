// Force-include fuer Android-Cross-Compile von libslic3r.
//
// Hintergrund: OrcaSlicer v2.4.2 verlaesst sich an einigen Stellen auf
// transitive STL-Includes, die unter GCC/libstdc++ (Host-x86-Build)
// klappen, unter Android NDK r27 (libc++) aber nicht. Statt Orca-Upstream
// zu patchen, injizieren wir die fehlenden Includes global ueber
// `-include ...` in engine/cmake/android-arm64.toolchain.cmake.
//
// Konkret: `libslic3r/LocalesUtils.cpp` nutzt `std::stringstream` ohne
// `<sstream>` zu includen. Weitere ggf. nachtragen, falls weitere Datei
// den gleichen Fehler zeigt.

#pragma once

#include <sstream>
