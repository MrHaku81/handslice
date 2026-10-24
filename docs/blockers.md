# Blocker

Offene Probleme, die Claude Code nach der Drei-Versuche-Regel (`CLAUDE.md`)
hier ablegt. Neueste oben. Gelöste Einträge nach unten unter „Gelöst"
verschieben, nicht löschen.

Format pro Eintrag:

```
## #N – <Kurztitel>  (JJJJ-MM-TT, Phase X)
**Symptom:** was passiert
**Probiert:** 1. … 2. … 3. …
**Beobachtet:** was die Versuche gezeigt haben
**Vermutung:** wo die Ursache liegen könnte
**Frage an Klaus:** was zur Entscheidung gebraucht wird
```

---

## #2 – adb sieht das Poco X3 Pro nach User-Wechsel nicht mehr  (2026-10-24, Phase C)

**Symptom:** `adb devices` leer, obwohl `lsusb` das Geraet
(`2717:ff48 Xiaomi Inc. Mi/Redmi series (MTP + ADB)`) als verbunden
listet. `adb kill-server && adb start-server`, `adb reconnect` sowie
`adb usb` liefern alle `no devices/emulators found`.

**Probiert:** 1. `adb kill-server; adb start-server`. 2. `adb reconnect`.
3. `adb usb`.

**Beobachtet:** USB-Verbindung ist auf OS-Ebene da (lsusb). ADB-Daemon
laeuft (`* daemon started successfully`), listet aber keine Geraete.
Keine `unauthorized`-Zeile – kein Eintrag ueberhaupt.

**Vermutung:** Beim fruehen `adb` haben wir unter dem User
`handslice` noch nicht die „immer erlauben"-Bestaetigung am Poco
geklickt, oder die ADB-RSA-Keys im Home des neuen Users
(`~/.android/adbkey*`) haben noch keinen Fingerabdruck im Geraet.
Klaus muss am Telefon:
1. Entwickleroptionen → USB-Debugging kurz aus/an.
2. Beim naechsten `adb devices` am Rechner den Dialog
   „USB-Debugging von diesem Rechner erlauben?" mit „Immer erlauben"
   bestaetigen.

**Fragen an Klaus:**
- Kurz am Poco den USB-Debugging-Dialog bestaetigen, dann ist das
  arm64-Binary (14 MB, siehe `engine/bin/handslice-cli-arm64`)
  per `bash engine/test/run-reference-test.sh --device` auf
  Byte-Gleichheit pruefbar.
- Falls das Geraet weiterhin stumm bleibt: USB-Kabel wechseln
  (manche Kabel sind nur Lade-, keine Datenleitungen).

---



---

## Gelöst

### #1 – Orca v2.4.2 koppelt CLI an wxWidgets+GLFW  (2026-10-24, Phase A→B)

**Symptom:** `cmake --build … --target OrcaSlicer` mit `SLIC3R_GUI=OFF`
bricht in genau einer Datei ab: `src/OrcaSlicer.cpp:78 fatal error:
wx/stdpaths.h`. libslic3r selbst (255 von 258 Build-Schritten) baut sauber
durch.

**Probiert:**
1. `-DSLIC3R_GUI=OFF -DSLIC3R_STATIC=1 -DSLIC3R_PCH=OFF -DBUILD_TESTS=OFF
   -DORCA_TOOLS=OFF -DSLIC3R_BUILD_SANDBOXES=OFF` – libslic3r + alle
   `libslic3r_*`-Statik-Bibliotheken bauen, Linken des `OrcaSlicer`-
   Executables scheitert an `wx/stdpaths.h`.
2. Befund an Klaus übergeben (keine zweite blinde Variante durchprobiert);
   Entscheidung: Option F – eigene CLI-Entry.
3. `engine/cli/handslice-cli.cpp` + CMakeLists aufgesetzt, Build läuft
   durch, Testlauf erfolgreich.

**Beobachtet:** `OrcaSlicer.cpp` (CLI-Entry, 7 545 Zeilen) hat ab Zeile 78
neun ungeguardete Includes: `<wx/stdpaths.h>`, 7× `slic3r/GUI/*.hpp`,
`<GLFW/glfw3.h>`. Insgesamt 88 Nutzungen von `Slic3r::GUI::*`, `wx*` und
`glfw*` außerhalb der `#ifdef SLIC3R_GUI`-Guards – fast alles für
Thumbnail-OpenGL-Rendering (Offscreen-FBO + GLFW-Hidden-Window) sowie für
die zentrale Datenstruktur `PartPlateList`, die historisch im
`Slic3r::GUI`-Namespace liegt. Zwei Zweit-Fundstellen beim Linken (siehe
unten).

**Vermutung:** Keine saubere CLI/GUI-Trennung bei Orca v2.4.2. Zwei
Ursachen: (a) `PartPlateList`/`PartPlate` ist semantisch Core, lebt aber
im GUI-Namespace; (b) CLI-Thumbnail-Rendering nutzt denselben
`GLCanvas3D`-Code wie die GUI, inklusive GLFW als Window-Backend.

**Lösung (2026-10-24, Option F):** Eigener Minimal-CLI unter
`engine/cli/handslice-cli.cpp`, der gegen die statisch gebauten
`libslic3r_*`-Bibliotheken linkt und **weder wx noch GLFW noch
`slic3r/GUI/*`** mitzieht. Keine Zeile am OrcaSlicer-Upstream geändert.

**Nachweis, dass die Kopplung umgangen ist:**

- `handslice-cli-x86` (66 MB, dynamisch gegen `libpthread`/`libdl`/
  `libz`/`libexpat`/`libjpeg`/`liblzma`/`libfontconfig` gelinkt, Rest
  statisch) baut durch mit `SLIC3R_GUI=OFF`.
- Slice eines 20-mm-Würfels mit Elegoo CC2 0.4 Düse + 0.20 mm Standard +
  Elegoo PLA erzeugt validen G-Code: 100 Layer, 20 mm Höhe,
  `return_code: 0`, Statistik-JSON auf stdout.
- `ldd engine/bin/handslice-cli-x86` zeigt kein `libwx*`, kein `libGLFW*`,
  kein `libGL*`.

**Zwei Zweit-Fundstellen der GUI-Kopplung** (ebenfalls gelöst, aber
dokumentiert für den Android-Build):

1. **NanoSVG-Implementierung** wird in Orca-Upstream in
   `src/slic3r/GUI/BitmapCache.cpp` per `#define NANOSVG_IMPLEMENTATION`
   erzeugt. `libslic3r.a` referenziert aber `nsvgParseFromFile`,
   `nsvgDelete` etc. Mit `SLIC3R_GUI=OFF` fehlen diese Symbole. Lösung:
   `engine/cli/nanosvg_impl.cpp` stellt die Implementierung bereit (zwei
   `#define` + `#include`).
2. **fontconfig als System-Lib** wird von `libTKService.a` (OpenCascade)
   gebraucht. Orcas `src/libslic3r/CMakeLists.txt` linkt es nur unter
   `SLIC3R_GUI=ON`. Lösung: explizit in `engine/cli/CMakeLists.txt`.

**Offen (nicht Teil dieses Blockers):** Byte-Gleichheit gegen den
Desktop-GUI-Export (nicht gegen AppImage CLI). Siehe
`docs/engine-integration.md` Abschnitt „Nachweislauf" – AppImage CLI
lädt die Preset-Vererbungs-Kette nicht und ist dadurch ein schlechter
Byte-Vergleichs-Partner. Klaus prüft Byte-Gleichheit manuell gegen
GUI-Export, nicht blockierend für Phase 0/1.
