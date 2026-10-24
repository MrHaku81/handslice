// NanoSVG ist in OrcaSlicer eine INTERFACE-Library; die Implementierung
// wird in genau einer Uebersetzungseinheit per #define erzeugt. In Orcas
// Upstream passiert das in src/slic3r/GUI/BitmapCache.cpp – also einer
// GUI-Datei. libslic3r.a referenziert aber trotzdem nsvgParseFromFile,
// nsvgDelete etc. und bricht ohne diese Implementierung beim Linken ab.
//
// Diese Datei stellt die Implementierung headless bereit, aequivalent zur
// Nutzung in BitmapCache.cpp. Keine Patches an OrcaSlicer-Upstream.

#define NANOSVG_IMPLEMENTATION
#include "nanosvg/nanosvg.h"

#define NANOSVGRAST_IMPLEMENTATION
#include "nanosvg/nanosvgrast.h"
