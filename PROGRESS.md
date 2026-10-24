# Fortschritt

Laufendes Protokoll. Neueste Einträge oben. Claude Code ergänzt nach jedem
größeren Schritt; Klaus liest hier tagsüber nach.

Format: `## JJJJ-MM-TT HH:MM – <Kurztitel>` und dann drei bis fünf Zeilen:
was gemacht, Ergebnis, offene Fragen.

---

## 2026-10-24 14:35 – Schritt A: Orca-Deps gebaut, CLI-Binary blockiert

- Orcas eigenes Deps-System durchgebaut: Boost 1.84, TBB, Cereal, Eigen
  (Prusa-Fork 5.0.1), PNG, FREETYPE, JPEG, NLopt, GMP, MPFR, CGAL, Blosc,
  OpenEXR, OpenVDB, OCCT, Qhull, Draco, libnoise, OpenSSL, CURL, GLFW,
  OpenCV. Nicht gebaut (weil nur GUI): wxWidgets, GLEW, OpenCSG.
  Destdir: `engine/OrcaSlicer/deps/build-x86/OrcaSlicer_dep/usr/local`.
- Erst-Stolperstein: Orcas Deps patchen OpenCV per `git apply --directory`
  mit einem Pfad relativ zum **OrcaSlicer-Git-Root**. Baut man außerhalb
  (`engine/build/deps`), findet git das umgebende `handslice/.git` und
  wirft „unable to normalize directory". Fix: Deps-Build nach
  `engine/OrcaSlicer/deps/build-x86` legen – kein Patch nötig.
- AppImage von OrcaSlicer v2.4.2 unter `engine/reference/`, extrahiert
  nach `squashfs-root/`. 20-mm-Würfel-STL (`engine/test/cube_20mm.stl`,
  684 Byte, 12 Dreiecke, sha256 `f483867e…bdf63`) per Python erzeugt.
- Testlauf AppImage: `AppRun --slice 0 --orient 1 --arrange 1
  --load-settings "<CC2 0.4>;<0.20mm Std>" --load-filaments
  "<Elegoo PLA>" --outputdir out-appimage cube_20mm.stl` erzeugt
  `plate_1.gcode` (209 KB, 100 Layer) + `result.json` (`return_code: 0`).

### Blocker-Befund: Orca v2.4.2 CLI zieht wxWidgets + GLFW

Mit `SLIC3R_GUI=OFF` baut libslic3r sauber durch (255/258 Build-Schritte);
nur die CLI-Entry `src/OrcaSlicer.cpp` schlägt an `#include <wx/stdpaths.h>`
fehl. Die Datei hat 7 weitere ungeguardete `slic3r/GUI/*`-Includes und
`<GLFW/glfw3.h>`, insgesamt 88 Nutzungen von `Slic3r::GUI::*`, `wx*` und
`glfw*` außerhalb von `#ifdef SLIC3R_GUI` – für Thumbnail-OpenGL-Rendering
(Offscreen-FBO, GLFW-Hidden-Window) und für `PartPlateList`, die
historisch im GUI-Namespace liegt.

Das ist **struktureller Natur**, kein Build-Setup-Problem. Für Phase 1
(ARM64/Android) viel kritischer, weil wxWidgets und GLFW auf Android
nicht offiziell existieren. Volltext der Analyse: `docs/engine-integration.md`
Abschnitt „Harter Befund". Blocker + Entscheidungsfragen:
`docs/blockers.md` #1.

### Offene Frage an Klaus (siehe `docs/blockers.md` #1)

Welchen Weg weitergehen? Die fünf Kandidaten (A..E) sind dort mit Pro/
Contra aufgeführt. **Bis zur Entscheidung ist Schritt A ausgesetzt.**
Phase 0 (Server-Prototyp auf AMR5) kann jetzt schon mit dem gebündelten
AppImage laufen – der Testlauf oben beweist, dass die CC2-Profile sauber
geladen werden.

## 2026-10-24 13:40 – Schritt A: OrcaSlicer-Submodul + Pacman-Deps

- OrcaSlicer-Upstream (https://github.com/SoftFever/OrcaSlicer) als Git-
  Submodul unter `engine/OrcaSlicer` angelegt und auf den neuesten stabilen
  Release-Tag **v2.4.2** (commit `8500fcdcca`) ausgecheckt. Keine inneren
  Git-Submodule bei v2.4.2. Tag in `docs/test-setup.md` eingetragen.
- Pacman-Deps-Prüfung (CachyOS/Arch): die Liste, die Orcas eigenes
  `scripts/linux.d/arch` nennt, ist GUI-fokussiert (gtk3, webkit2gtk-4.1,
  mesa, glew, libmspack, libsecret, libspnav, wayland-protocols,
  gst-plugins-good, gstreamer, eglexternalplatform). Für reinen
  Headless-Build (`SLIC3R_GUI=OFF`) brauchen wir davon fast nichts.
- Prüfliste **Pacman** für reines Slicing-Core (Stand bereits installiert):
  `base-devel`, `cmake 4.4.4`, `ninja 1.13.2`, `git 2.56.0`, `gcc 16.2.1`,
  `clang/llvm 23.1.3`, `lld 23.1.3`, `curl`, `wget`, `openssl`, `zlib`,
  `mesa`, `libglvnd`, `glu`, `glfw-x11`, `glfw-wayland`, `libxrandr`,
  `libxinerama`, `libxcursor`, `libxi`, `libx11`, `file`, `gettext`,
  `texinfo`, `dbus`, `pkgconf`, `autoconf`, `automake`, `libtool`, `m4`.
- **Fehlt:** `extra-cmake-modules` (für ECM-find-Module). Nicht installiert,
  weil Pacman root-Passwort will und Claude Code unbeaufsichtigt läuft.
  Falls der Build danach schreit, stoppen und Klaus fragen.
- Heavyweight-Slicing-Libs (Boost 1.83, TBB, Eigen 5.0.1-fork, OpenVDB 5.0
  mit alter ABI, CGAL+GMP+MPFR, cereal, EXPAT, PNG, Freetype, NLopt 1.4,
  OCCT, OpenCSG, Qhull, Draco, Blosc, OpenEXR, OpenCV, NanoSVG, libnoise,
  JPEG, GLEW, GLFW) sind in Pacman nicht in den von Orca gepinnten
  Versionen vorhanden (Arch tracked HEAD, Orca pinnt alte ABIs). Daher
  werden diese über Orcas eigenes `deps/`-Build-System gebaut, wie es
  Orca-Upstream vorsieht. Das ist der nächste Schritt.

## 2026-10-24 12:50 – Umgebungs- und Verbindungscheck

- Toolchain erfasst und in `docs/test-setup.md` eingetragen: git 2.56.0,
  CMake 4.4.4, Ninja 1.13.2, GCC 16.2.1, Clang/LLVM 23.1.3 (inkl. ld.lld),
  Python 3.14.8, adb 1.0.41 (platform-tools 37.0.0p1).
- **Nicht installiert:** Android SDK, Android NDK, aarch64-linux-gnu-gcc,
  Flutter, Kotlin. Nur festgestellt, nichts installiert.
- Testgerät Poco X3 Pro (`M2102J20SG`, `vayu`, Serie `9ed86ce3`) am ADB als
  `device` sichtbar. Android 12 (API 31), MIUI V13.0.1.0.SJUEUXM, ABI
  `arm64-v8a`, 8-GB-RAM-Variante (7,32 GiB MemTotal, 4,6 GiB verfügbar),
  144 GB frei auf `/data`.
- ADB-Rundlauf bestanden: 10 MiB urandom-Blob push → sha256 auf Gerät →
  pull → sha256 lokal, alle drei Hashes identisch
  (`90156b83…355d`). Push 44,1 MB/s, pull 37,4 MB/s.
- ARM64-Hello-World (freistehend, Clang+lld, direkte Linux-Syscalls) auf
  dem Gerät ausgeführt → `hello from arm64`, Exit 0. Beweist
  Execute-Rechte in `/data/local/tmp` und arm64-Userspace, aber **nicht**
  NDK/Bionic-Linking (NDK ist nicht installiert).
- **Ergebnis:** Umgebung grundsätzlich tragfähig. NDK-Entscheidung bleibt
  offen, hängt an UI-Stack-Entscheidung (Flutter vs. Compose).

## 2026-10-24 – Projekt angelegt

- Repo-Vorlage erstellt. Name: **Handslice** (GitHub-Name geprüft, frei).
- Entscheidungen: Orca-Upstream als Engine; Elegoo-Profile und -Protokoll
  später als Schichten; AGPL-3.0.
- Build-Rechner: AMR5 (CachyOS). Testgerät: Poco X3 Pro (Stock-MIUI).
- **Offen:** UI-Stack (Flutter vs. Compose) – siehe `docs/architecture.md`.
  Bis zur Entscheidung kein Frontend-Code.

### Offene Fragen an Klaus
- **Welchen Weg bei Blocker #1 (Orca v2.4.2 CLI = GUI)?** Fünf Kandidaten
  in `docs/blockers.md` #1 bzw. ausführlich in `docs/engine-integration.md`
  („Harter Befund"-Abschnitt). Bis zur Entscheidung ist Schritt A
  pausiert.
