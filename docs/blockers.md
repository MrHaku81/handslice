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

## #3 – Clang-Host-Build (Stufe 2b) scheitert an Toolchain-Mismatch  (2026-11-02, Phase C)

**Symptom:** Ein x86_64-Linux-Host-Build von `libslic3r` + `handslice-cli`
mit Clang (statt dem Default GCC 16) laesst sich mit den auf AMR5 vorhandenen
Werkzeugen nicht sauber erzeugen. Zweck des Builds: Compiler-Hypothese zur
arm64/x86-Byte-Divergenz pruefen (Klaus-Auftrag „Stufe 2b").

**Probiert:**
1. **System-Clang 23.1.4** (`/usr/bin/clang++`): bricht in
   `src/libslic3r/AABBTreeLines.hpp:35` ab. Clang-23 ist strenger als GCC
   bei der Template-Deduktion zwischen
   `Eigen::CwiseUnaryOp<...>` und `Eigen::Matrix<...>` fuer
   `distance_to_squared(point, a, b)`. Kein Patch an Orca-Upstream erlaubt
   (CLAUDE.md Pkt. 2).
2. **NDK clang-18** (`$HOME/android-sdk/ndk/27.3.13750724/.../clang++`,
   Target per Default `x86_64-unknown-linux-gnu`, zieht aber die
   System-libstdc++ von GCC 16): bricht in
   `deps_src/admesh/stlinit.cpp` (bzw. im zugehoerigen Include-Pfad
   `stl.h:222`) mit *"member access into incomplete type
   `const __normal_iterator<...>`"* ab. Ursache ist eine bekannte
   Inkompatibilitaet zwischen Clang<23 und GCC-16-libstdc++: in dem
   trailing return type von `operator-(const __normal_iterator&, const
   __normal_iterator&)` greift Clang auf `base()` zu, bevor
   `__normal_iterator` als vollstaendig gilt. GCC compiliert das; Clang 18
   nicht.

**Beobachtet:**
- System-Toolchains auf AMR5: nur **GCC 16.2.1** und **Clang 23.1.4**.
  Weder gcc-14/15 noch clang-18/19/20 sind als Pakete installiert.
- NDK clang-18 bringt eine **eigene libc++** mit
  (`.../toolchains/llvm/prebuilt/linux-x86_64/lib/libc++.a`), die den
  libstdc++-Bug umgehen wuerde. Aber: die Orca-x86-Deps
  (`deps/build-x86/`) wurden mit GCC/libstdc++ gebaut; Mischung
  libc++↔libstdc++ ergibt ABI-Mismatch an `std::string`/`std::vector` in
  Boost-/TBB-Interfaces.
- Keine Variante kommt bis an die eigentliche Divergenzfrage heran.

**Vermutung:** Es gibt genau drei saubere Wege, Stufe 2b trotzdem zu
klaeren:

a) **Clang+libc++ ueberall**: Orca-Deps-Build zusaetzlich mit NDK-clang-18
   +`-stdlib=libc++` nach `deps/build-x86-clang/` neu bauen (geschaetzt
   30–60 min), dann libslic3r + CLI dagegen linken. Beantwortet Compiler
   *und* Stdlib gemeinsam, nicht getrennt.
b) **AUR/Container**: ein zweites gcc (z. B. gcc-14) oder clang (z. B.
   clang-18) via AUR installieren bzw. in einem Toolbx-Container bauen.
   Verletzt „Keine Aenderungen an System" (CLAUDE.md Pkt. 2), es sei denn
   als Pacman-Paket genehmigt oder als Container.
c) **Compiler-Experiment fallenlassen** und direkt auf Stufe 3+4 (Grep
   nach `std::sort`/Pointer-Compare in libslic3r) ohne Clang-Vergleich
   setzen.

**Frage an Klaus:** Welchen der drei Wege darf Claude gehen? Default-Antwort
„c) ueberspringen und Stufe 3 fortsetzen" ist bereits in Arbeit, so dass
der Nachtlauf nicht leer bleibt.

---

(keine weiteren offenen Blocker)


---

## Gelöst

### #2 – adb sieht das Poco X3 Pro nach User-Wechsel nicht mehr  (2026-10-24, Phase C)

**Symptom:** `adb devices` leer, obwohl `lsusb` das Geraet
(`2717:ff48 Xiaomi Inc. Mi/Redmi series (MTP + ADB)`) als verbunden
listet. `adb kill-server && adb start-server`, `adb reconnect` sowie
`adb usb` liefern alle `no devices/emulators found`.

**Probiert:** 1. `adb kill-server; adb start-server`. 2. `adb reconnect`.
3. `adb usb`.

**Beobachtet:** USB-Verbindung ist auf OS-Ebene da (lsusb). ADB-Daemon
laeuft, listet aber keine Geraete. Keine `unauthorized`-Zeile.

**Vermutung:** ADB-RSA-Key des User `handslice` noch nicht am Geraet
autorisiert, oder USB-Debugging-Dialog war noch nicht bestaetigt.

**Loesung (2026-10-24, Klaus):** Nach erneuter Autorisierung am Poco
listet `adb devices` wieder `9ed86ce3 device`. Danach lief
`bash engine/test/run-reference-test.sh --device` sauber durch (Slice
in 0.9 s, G-Code 207 769 Byte, Return 0). Siehe PROGRESS.md
2026-10-24 23:50 fuer den vollstaendigen Nachweis + die weiterhin
offene **Byte-Divergenz** gegen die Desktop-Referenz (die ist kein
Blocker im Sinne der Drei-Versuche-Regel, sondern eine Phase-C-
Erfolgskriterium-Luecke; siehe `docs/engine-integration.md` Abschnitt
„Byte-Divergenz arm64 ↔ x86").

---

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
