# Fortschritt

Laufendes Protokoll. Neueste Einträge oben. Claude Code ergänzt nach jedem
größeren Schritt; Klaus liest hier tagsüber nach.

Format: `## JJJJ-MM-TT HH:MM – <Kurztitel>` und dann drei bis fünf Zeilen:
was gemacht, Ergebnis, offene Fragen.

---

## 2026-10-24 23:50 – Device-Test auf Poco X3 Pro gelaufen, Byte-Gleichheit nicht erreicht

Klaus hat die ADB-Autorisierung am Poco bestaetigt; `adb devices` zeigt
`9ed86ce3 device`. `docs/blockers.md` #2 nach „Gelöst" verschoben.

### Device-Lauf

`bash engine/test/run-reference-test.sh --device` lief vollstaendig
durch:

- Push: `handslice-cli-arm64` (14 MB) in 0.097 s, `resources/profiles/`
  (12 852 Dateien, 44 MB) in 2.385 s nach `/data/local/tmp/handslice/`.
- Slice auf dem Poco: **0.9 s**, Return 0, G-Code 207 769 Byte, 100
  Layer, 8479 Zeilen EXECUTABLE_BLOCK.
- Stats (praktisch identisch zum x86-Lauf): 1177 mm Filament,
  2831 mm³, 3.54 g, 9m 21s.

**Laufzeit auf dem Snapdragon 860 (0.9 s) ist nur ca. 1.2× die
AMR5-Zeit (Ryzen 7 5800U, 0.76 s).** Deutlich besser als erwartet.
Zwei aufeinanderfolgende Slices auf dem Poco sind byte-identisch
(`a30ffec3e76452ea67843fa8a1b67eb5dd38fa92a285045a0467f163ec872c99`) –
der arm64-Build ist deterministisch.

### Byte-Divergenz zur Referenz

**EXECUTABLE_BLOCK sha256 arm64 vs. Desktop-Referenz: unterschiedlich**
(513 geaenderte Zeilen bei gleicher Zeilenzahl 8479). Nicht Fliesskomma-
Rauschen: die unterschiedlichen Zeilen sind **rotations-symmetrisch
vertauschte XY-Koordinaten** eines symmetrischen Wuerfels, plus eine
139-Zeilen-TopInfill-Partie um 90° gedrehte Linienrichtung. Topologisch
gleicher G-Code, byte-unterschiedlich. Vollstaendige Analyse in
`docs/engine-integration.md` Abschnitt „Byte-Divergenz arm64 ↔ x86".

**Vermutung:** `std::sort` ist nicht stabil; libc++ (NDK) ordnet Equal-
Key-Elemente anders als libstdc++ (Host). Beim Wuerfel sind viele
Perimeter-Nachbarschafts-Metriken exakt gleich, deshalb schlaegt das
in jeder Instance-Entscheidung durch. Alternativ TBB-paralleles
Zusammenfuehren bei 16 Host-Cores vs. 8 Device-Cores.

### Phase-C-Erfolgskriterium

Laut `docs/engine-integration.md` Schritt C war das Kriterium
„`sha256sum` identisch zum Desktop". Das ist **nicht erfuellt**.
Entscheidung ueber Lockerung (funktional vs. byte-genau) ist nicht
Teil dieses Nachtlaufs – Klaus-Rueckfrage noetig.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Binary `engine/bin/handslice-cli-arm64` laeuft auf dem Poco X3 Pro
  und erzeugt gueltigen G-Code in 0.9 s. Beweis-Befehl:
  `bash engine/test/run-reference-test.sh --device` (Exit 0, Stats-JSON
  mit `return_code: 0`, 100 Layer, Filament/Zeit/Volumen plausibel und
  identisch zum x86-Lauf auf Milligramm genau).
- arm64-Build ist deterministisch: zwei Slices desselben STL ergeben
  identische sha256 des G-Codes.
- Laufzeit arm64 : x86 ≈ 0.9 s : 0.76 s – Snapdragon 860 nur 1.2×
  langsamer als Ryzen 7 5800U.

**2. Ungeprueft**

- Verhalten unter Last / mehreren parallelen Slices im App-Kontext.
- Verhalten mit groesseren Modellen (>50k Dreiecke) – aktueller
  Testlauf ist nur der 12-Dreiecke-Wuerfel.
- MIUI-Hintergrund-Kill (CLAUDE.md: „MIUI killt Hintergrundprozesse
  aggressiv") – aktuell lief der CLI im Vordergrund per adb shell.
- Second-Lauf im selben adb-shell-Aufruf crasht mit
  `boost::filesystem::create_directory: No such file or directory` –
  ein Aufruf pro adb-shell-Kommando ist bisher der einzige getestete
  Pfad. Vermutlich harmlos (vermutlich braucht die 3mf-Pipeline einen
  frischen Pfad), aber nicht untersucht.

**3. Geht nicht**

- **Byte-Gleichheit arm64 ↔ Desktop-Referenz.** Phase-C-Kriterium
  nicht erfuellt. 513 von 8479 Zeilen unterschiedlich, Natur
  rotations-symmetrisch (`std::sort`-Instability oder TBB-parallele-
  Reihenfolge). Siehe `docs/engine-integration.md` Abschnitt
  „Byte-Divergenz arm64 ↔ x86" fuer die vollstaendige Analyse und
  die zwei Hypothesen zur Ursache.

---

## 2026-10-24 21:40 – Schritt B/C: Deps + handslice-cli-arm64 gebaut, Device-Test blockiert

Fortsetzung des Nachttauftrags. Alle sechs Punkte aus Klaus' Vorgabe
(Dep-Audit → Deps-Build → CLI-Build → Doku → Protokoll → Commit)
abgearbeitet; der Device-Nachweis haengt an einer offenen ADB-
Autorisierung am Telefon (siehe Rubrik 3 unten + `docs/blockers.md` #2).

### 1. Dep-Audit vor dem Cross-Build

`libslic3r.a` + `handslice-cli` brauchen 20 der 23 Orca-Deps aus dem
x86-Build. Weglassen koennen wir **GLFW** (nicht in libslic3r-Sources
referenziert) und **CURL** (ebenso). **OpenVDB/OpenEXR/Blosc** bleiben
drin, weil `SLA/Hollowing.cpp` unguarded `<openvdb/...>` includet;
Weglassen braechte einen Orca-Patch – nicht zulaessig. Ergebnis als
Tabelle in `docs/engine-integration.md` Abschnitt „Dep-Audit vor dem
Cross-Build" bevor der Build startete.

### 2. Deps fuer arm64 cross-compiled

`engine/build-deps-arm64.sh` + `engine/cmake/android-arm64.toolchain.cmake`
+ `engine/cmake/android-shims/FindOpenGL.cmake`. Baut Boost 1.84, TBB,
Cereal, Eigen, PNG, FREETYPE, JPEG, EXPAT, NLopt, GMP, MPFR, CGAL, Blosc,
OpenEXR, OpenVDB, OCCT 7.6.0, Qhull, Draco, libnoise, OpenCV 4.6.0 fuer
`arm64-v8a` / android-29 nach
`engine/OrcaSlicer/deps/build-arm64/OrcaSlicer_dep/usr/local/`.

OpenSSL baut der Build-Script manuell, weil Orcas Recipe einen leeren
`TOOLCHAIN_PREFIX` an OpenSSL durchreicht. Dazu Stubs:

- `libfontconfig.a` (leer, aber linkbar) – OCCT auf Android ruft keine
  fontconfig-Symbole, aber `src/libslic3r/CMakeLists.txt:613` linkt sie
  trotzdem hartkodiert.
- `libcurl.a` + `include/curl/curl.h` (leer) – `find_package(CURL
  REQUIRED)` in `OrcaSlicer/CMakeLists.txt:633` zufriedenstellen, ohne
  echtes libcurl zu bauen.
- `lib/cmake/glfw3/glfw3Config.cmake` – `find_package(glfw3 REQUIRED)`
  in `OrcaSlicer/CMakeLists.txt:698` zufriedenstellen; INTERFACE-Target
  ohne Libs/Includes.

94 `.a`-Dateien im Deps-Prefix, alle `file`-Check: `ELF 64-bit LSB
relocatable, ARM aarch64`. Zwoelf Cross-Compile-Stolpersteine mit
Loesung dokumentiert in `docs/engine-integration.md` Abschnitt
„Umsetzung" (von GLEW-OpenGL-Shim ueber GMP-Autotools-Compiler-Trick
bis zum NDK-libc++-sstream-Fix fuer LocalesUtils.cpp). **Keine Zeile im
OrcaSlicer-Upstream geaendert.**

### 3. libslic3r + handslice-cli-arm64

`engine/build-cli-arm64.sh` baut gegen die arm64-Deps. Umgeht die
cross-compile-fatale OrcaSlicer-encoding-check-Dependency durch einen
`sed`-Patch auf `build.ninja`, der den Encoding-Check-COMMAND auf das
bereits vorhandene Host-x86-encoding-check-Binary umbiegt.

`engine/cli/CMakeLists.txt` greift OpenCVs Android-Install-Layout auf
(`sdk/native/staticlibs/arm64-v8a/libopencv_world.a` statt
`lib/libopencv_world.a`) und waehlt pro CMAKE_SYSTEM_NAME zwischen
Linux- und Android-Pfaden fuer System-Libs (`libz`, `-llog` statt
`-lpthread`, u. a.).

Binary: `engine/bin/handslice-cli-arm64`, 14 MB nach
`llvm-strip --strip-unneeded` (vorher 865 MB mit Debug-Info).

```
$ file engine/bin/handslice-cli-arm64
ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV),
dynamically linked, interpreter /system/bin/linker64, for Android 29,
built by NDK r27d (13750724)
```

### 4. run-reference-test.sh um `--device`-Modus erweitert

Pusht Binary + Elegoo-Profile + Wuerfel per adb nach
`/data/local/tmp/handslice/`, slicet auf dem Geraet, pullt den G-Code
und vergleicht EXECUTABLE_BLOCK gegen Referenz. Nicht ausgefuehrt
(siehe Rubrik 3 unten).

### 5. Doku-Updates

- `docs/engine-integration.md`: neuer Abschnitt „Dep-Audit vor dem
  Cross-Build" (Tabelle); neuer Abschnitt „Umsetzung" unter Schritt C
  mit Script-Index, Toolchain-Hinweisen und zwoelf Stolpersteinen inkl.
  Loesung. „Device-Test" als „ausstehend" markiert.
- `docs/test-setup.md`: Toolchain-Wrapper + CMake-Shims eingetragen.
- `docs/blockers.md`: Blocker #2 (ADB).

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- `engine/bin/handslice-cli-arm64` existiert, ist ELF ARM aarch64 fuer
  Android 29. Beweis-Befehl: `file engine/bin/handslice-cli-arm64`.
- 94 arm64-static-libs unter `engine/OrcaSlicer/deps/build-arm64/
  OrcaSlicer_dep/usr/local/lib/` (Boost, TBB, OCCT 7.6, OpenCV 4.6,
  OpenVDB, CGAL, GMP, MPFR, …). Stichprobe: `file …/libTKMath.a`-
  Member → `ELF 64-bit LSB relocatable, ARM aarch64`.
- Build-Skripte reproduzierbar: `bash engine/build-deps-arm64.sh` +
  `bash engine/build-cli-arm64.sh` (von leerem `build-arm64/` ca. 50 min
  auf AMR5). Beide ohne Patches an OrcaSlicer-Upstream.
- Umgehungen fuer zwoelf Cross-Compile-Stolpersteine schriftlich
  festgehalten (`docs/engine-integration.md` Abschnitt „Umsetzung").

**2. Ungeprueft**

- **Byte-Gleichheit auf dem Poco X3 Pro.** Das Binary existiert, der
  Testlauf-Pfad in `engine/test/run-reference-test.sh --device` ist
  implementiert, aber der ADB-Rundlauf ist blockiert (siehe Rubrik 3).
- Laufzeit auf Snapdragon 860 – ohne Device-Lauf nicht gemessen.
- Reproduzierbarkeit „von null auf einem anderen Rechner": nur auf
  AMR5 getestet. Fuer andere Linux-Distributionen oder NDK-Versionen
  koennen Pfade im Toolchain-Wrapper angepasst werden muessen.
- fontconfig-Stub + CURL-Stub + glfw3-Stub-Config: belasten die Compile-
  und Link-Phase korrekt, aber zur Laufzeit ruft libslic3r keine
  Symbole aus diesen Libs; untestable, solange der G-Code nicht
  nachweislich erzeugt wird.

**3. Geht nicht**

- **ADB sieht das Poco nicht mehr**, siehe `docs/blockers.md` #2.
  `adb devices` leer, obwohl `lsusb` das Geraet listet. Vermutung:
  Nach dem Rechner-User-Wechsel braucht das Telefon einmalig eine
  neue „USB-Debugging erlauben"-Bestaetigung. Erfordert Klaus am
  Geraet.

---

## 2026-10-24 19:30 – Reproduzierbarkeit nachgewiesen, Flashforge-Rest geklärt, Android-NDK installiert

Fortsetzung unter dem frischen User `handslice` auf AMR5, kein Build-Cache
vorhanden. Alle sechs Punkte aus Klaus' Nachtlauf-Auftrag abgearbeitet.

### 1. `engine/build-headless-x86.sh` von null durchlaufen

Erst-Lauf fiel in Schritt 4/4 (CLI-Link) mit
`liblibnest2d.a missing and no known rule to make it` um. Ursache:
`libslic3r libslic3r_cgal` als `cmake --build`-Target zieht die internen
`deps_src/`-Libs (`miniz_static`, `admesh`, `clipper`, `Clipper2`,
`glu-libtess`, `mcut`, `qoi`, `libsemver`) transitiv mit, aber **nicht**
`libnest2d` – das linkt nur gegen `libslic3r`, nicht umgekehrt, und ist
daher kein ninja-Dependent. Fix im Skript: `libnest2d` explizit zu den
Build-Targets ergaenzen (`engine/build-headless-x86.sh` Zeile 58, mit
Kommentar). Nach dem Fix laeuft der Build end-to-end sauber durch, inklusive
sauber Install nach `engine/bin/handslice-cli-x86`.

Nebenbefund: `extra-cmake-modules` (vom `docs/engine-integration.md`-
Logbuch-Eintrag vom 13:40 als „fehlt" vermerkt) ist fuer den
`SLIC3R_GUI=OFF`-Build **nicht** erforderlich – der komplette Deps-
und libslic3r-Build geht ohne `ECM`-Variablen. Daher nicht als
Script-Dependency aufgenommen (nur installiert, weil heute morgen
praeventiv geholt).

### 2. Reference-Test byte-gleich reproduziert

`engine/test/run-reference-test.sh` (neu, 3 Schritte, Ein-Befehls-Call):
Slicet den Wuerfel mit CC2 0.4 + 0.20mm Standard + Elegoo PLA, zieht den
`EXECUTABLE_BLOCK` aus beiden Dateien, vergleicht sha256 + Zeilenzahl
gegen die bekannte Referenz `92951c26...8777675d` / 8479 Zeilen. **Exit 0
= bestanden.**

Lauf:

```
$ bash engine/test/run-reference-test.sh
=== 2/3  EXECUTABLE_BLOCK vergleichen ===
  erwartet: 92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d  (8479 Zeilen)
  erhalten: 92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d  (8479 Zeilen)
  → IDENTISCH
```

Stats-JSON (plausibel): 1 177 mm Filament, 2 831 mm³, 3,54 g, 9m 21s
geschaetzt. (Die kleine Differenz zur frueheren Zahl 1 201 mm liegt an
`total_filament_used_mm` vs. per-Extruder in alter Statistik.)

### 3. „Flashforge-Defaults" im CONFIG_BLOCK aufgeklaert

`compare-configblock.sh` zeigt stabil 11 / 15 / 1 (gleich wie beim ersten
Nachweis). Herkunft der 15 „nur in ref"-Keys (`flashforge_serial_number`,
`bbl_use_printhost`, `printhost_authorization_type`,
`printhost_ssl_ignore_revoke`, `printer_agent`, `pellet_modded_printer`,
`default_bed_type` empty, `default_nozzle_volume_type`,
`extruder_variant_list`, `filament_colour_type`, `filament_multi_colour`,
`filament_self_index`, `ironing_expansion`, `pellet_flow_coefficient`,
`print_compatible_printers`): **nicht** Vendor-blind-Rest, sondern
GUI-Only-Verhalten. Keiner dieser Keys steht in einem Elegoo-Profile-JSON;
die GUI ergaenzt sie beim Preset-Save ueber
`s_Preset_printer_options` + `s_PhysicalPrinter_opts` (`Preset.cpp:1375`,
`:3938`) mit ihrem `print_config_def`-Default. Unser CLI baut die Config
aus `FullPrintConfig::defaults()` + Vererbungs-Kette; da diese Keys dort
nicht per `OPT_PTR` ausgewiesen sind, fallen sie weg. Harmlos fuer den
EXECUTABLE_BLOCK (nachweislich byte-gleich). Dokumentiert in
`docs/engine-integration.md` Abschnitt „Woher die GUI-only
CONFIG_BLOCK-Keys kommen". Nicht nachbilden.

### 4. Doku-Nachtrag: Fokus-Navigation

- `docs/architecture.md` → UI-Schicht: Vollstaendige Fokus-Navigation
  (Tastatur, D-Pad, Controller) als Pflicht ausserhalb des 3D-Viewports.
- `CLAUDE.md` → Technische Konventionen: dieselbe Regel kurz, damit sie
  in jedem Session-Start sichtbar bleibt.

### 5. Android SDK/NDK vorbereitet (noch nichts damit gebaut)

- `jre-openjdk-headless` (OpenJDK 27) via Pacman installiert
  (`sudo -n pacman -S --needed --noconfirm`), weil `sdkmanager`/`android`-
  CLI eine JRE braucht.
- Googles Command-Line-Tools Linux-Zip (`16111833`) nach
  `~/android-sdk/cmdline-tools/latest/` entpackt. Hinweis: Google hat
  `sdkmanager` deprecated zugunsten einer neuen `android`-CLI; beide
  liegen im `bin/`-Dir.
- `yes | sdkmanager --licenses` einmalig akzeptiert.
- NDK `27.3.13750724` (= r27d, aktueller LTS-Patch der r27-Linie) ueber
  `sdkmanager "ndk;27.3.13750724"` installiert nach
  `~/android-sdk/ndk/27.3.13750724/` (ca. 2 GB). `aarch64-linux-android29-
  clang --version` meldet Android-Clang 18.0.4 – damit sind Bionic-Linking
  und `arm64-v8a`-Cross-Compile fuer Phase B/C bereitgestellt.
- Versionen + Pfade in `docs/test-setup.md` eingetragen (Toolchain-Tabelle
  + neuer Abschnitt „Android SDK/NDK einrichten"). `PATH`-Exports stehen
  dort als Projekt-lokale Umgebungs-Snippets – **nicht** in `~/.bashrc`
  geschrieben, Projektregel „Keine Dotfile-Aenderungen".
- Platform-SDK (API-Level, Build-Tools) **noch nicht** installiert; haengt
  an UI-Stack-Entscheid.

### 6. Protokoll + Commit

Siehe Abschlussbericht unten; lokaler Commit erstellt, nicht gepusht.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- `engine/build-headless-x86.sh` baut auf einer leeren Deps-/Build-Cache-
  Umgebung komplett durch, von Deps ueber `libslic3r` bis `handslice-cli-x86`.
  Beweis-Befehl: `rm -rf engine/build engine/OrcaSlicer/deps/build-x86 &&
  bash engine/build-headless-x86.sh` – endet mit `ELF 64-bit ... x86-64`
  und Help-Ausgabe.
- `engine/test/run-reference-test.sh` liefert Exit 0 und
  `EXECUTABLE_BLOCK sha256 = 92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d`
  bei 8479 Zeilen. Phase-A-Erfolgskriterium ist damit erneut, in einem
  einzigen Befehl, pruefbar.
- NDK r27d installiert, `aarch64-linux-android29-clang` ausfuehrbar
  (`--version` liefert Android-Clang 18.0.4).

**2. Ungeprueft**

- Reproduzierbarkeit „auf einem komplett anderen Rechner" – getestet nur
  auf AMR5 (CachyOS, GCC 16.2.1, CMake 4.4.4). Fuer andere Distributionen
  / Compiler-Versionen koennen weitere Deps noetig werden.
- Android NDK ist installiert, aber **noch nicht fuer Cross-Compile von
  Orca-Deps genutzt** (ausdruecklich Teil von Schritt B/C, nicht dieses
  Auftrags).
- Die Downloads der cmdline-tools-ZIP sind groesser als in der
  `repository2-3.xml` angekuendigt (173 MB vs. 157 MB laut `Content-Length`
  bei der Probe); Google scheint die Datei inzwischen aktualisiert zu
  haben. Zip ist gueltig (`unzip -l` listet 139 Dateien, `sdkmanager`
  laeuft), aber ein sha256-Pinning ist nicht hinterlegt.

**3. Geht nicht**

- (keine offenen Blocker; `docs/blockers.md` unveraendert bei „keine
  offenen".)

---

## 2026-10-24 17:40 – Executable-Block byte-gleich mit GUI-Export

Klaus hat den Desktop-Orca-GUI-Export unter `engine/test/out-gui/plate_1.gcode`
hinterlegt und drei Divergenzen zum CLI-Output benannt. Alle drei gefixt;
der EXECUTABLE_BLOCK ist jetzt **sha256-identisch**
(`92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d`,
8479 Zeilen auf beiden Seiten).

**Fixes im CLI:**

1. **ResourceIndex vendor-aware.** Mein alter Chain-Walker lief bei
   `inherits = fdm_filament_common` zufaellig in das Afinia-Verzeichnis
   statt in das Elegoo-Verzeichnis (40 Vendors haben eine gleichnamige
   Datei; Afinia hat `filament_flow_ratio=1`, Elegoo `0.98`). Jetzt
   speichert der Index alle Pfade pro `(type, name)`, und der Lookup
   bevorzugt den Pfad, dessen Vendor-Verzeichnis (das Segment direkt
   unter `profiles/`) mit dem Leaf uebereinstimmt. Damit kommt
   `filament_flow_ratio=0.98` sauber durch, und meine fruehere
   Behauptung „unser CLI resolvt die Chain korrekt" wird jetzt auch
   wirklich eingeloest.
2. **`curr_bed_type` nachsetzen.** CLI fiel auf Enum-Default `btPC`
   (Cool Plate) zurueck, weil wir es nicht explizit setzen. Orcas GUI
   leitet den Wert aus `default_bed_type` des Druckerprofils ab
   (int-String → `BedType`, Fallback `btPEI` = High Temp Plate).
   Im CLI nachgebildet nach dem Chain-Load.
3. **`is_BBL_printer = false` setzen.** `Print::m_isBBLPrinter` ist in
   `Print.hpp` nicht initialisiert; `GCodeProcessor::s_IsBBLPrinter`
   ist ein static mit Default `true`. Orca setzt beide aus
   `preset_bundle->is_bbl_vendor()`, fuer CC2 (Vendor „Elegoo") ist das
   `false`. Fehlte in unserem CLI – deshalb kam Bambu-Stil raus
   (`; FEATURE:`, `M624`, `M981`, `M900`) statt Klipper-Stil (`;TYPE:`,
   `SET_PRESSURE_ADVANCE`).

**Vergleichsskripte** unter `engine/test/`:

- `compare-gcode.sh` erweitert: EXECUTABLE_BLOCK-sha256 getrennt vom
  Gesamtdatei-Hash. Exit 0 wenn Executable identisch.
- `compare-configblock.sh` neu: differenziert die CONFIG_BLOCK-
  Zuweisungen in drei Kategorien („Werte unterschiedlich", „nur in ref",
  „nur in ours"). Haette den `filament_flow_ratio=1` vs `0.98` sofort
  gezeigt – kuenftige Divergenzen fallen damit automatisch auf.

**Was weiterhin unterschiedlich bleibt** (akzeptiert, dokumentiert in
`docs/engine-integration.md`):

- Thumbnail-Block (GUI schreibt PNG-base64, wir nicht).
- Reihenfolge der Bloecke (GUI: Header → Thumbnail → Executable →
  Config; wir: Header → Executable → Config).
- 11 Metadaten-Werte im CONFIG_BLOCK (`extruder_colour`, `filament_colour`,
  `wipe_tower_x/y`, `filament_ids`, `print_settings_id`, Flashforge-
  Defaults, u. ä.) – alle beeinflussen den EXECUTABLE_BLOCK nicht.
- `; model label id: 12`-Header-Zeile (bei uns da, bei GUI nicht).

Keine offenen Blocker. Phase A damit sauber abgeschlossen; naechster
Auftrag ist Schritt B/C (ARM64 Cross-Build).

## 2026-10-24 16:50 – Schritt A: eigener Minimal-CLI (Option F) steht

- Klaus hat Option F entschieden: statt Patch an `OrcaSlicer.cpp` eine
  eigene Entry unter `engine/cli/handslice-cli.cpp` (+ CMakeLists), die
  gegen die bereits gebauten `libslic3r_*`-Statik-Bibliotheken linkt und
  **keinerlei** wx-/GLFW-/`slic3r/GUI`-Code mitzieht. Keine Zeile an
  OrcaSlicer-Upstream geändert.
- Umfang: STL + 3mf laden, Profil-JSONs (machine/process/filament) mit
  `inherits`-Chain über rekursiven Resource-Scan auflösen, Modell optional
  auf Plattenmitte zentrieren (`--no-center` lässt es an Ort), Print
  erstellen+process+export_gcode, Statistik (Zeit, Volumen, Gewicht) als
  JSON auf stdout.
- Zweite CLI-Kopplungs-Fundstelle beim Linken: libslic3r referenziert
  `nsvgParseFromFile`/`nsvgDelete`, deren Implementierung in Orca-Upstream
  **in einer GUI-Datei** erzeugt wird. Lösung ohne Patch: eigene
  `engine/cli/nanosvg_impl.cpp` setzt die beiden `#define
  NANOSVG_IMPLEMENTATION`/`NANOSVGRAST_IMPLEMENTATION`. Dritte Fundstelle:
  OpenCascade-`libTKService.a` braucht `fontconfig`, in Orca nur unter
  `SLIC3R_GUI=ON` gelinkt – wir ergänzen es explizit.
- Binary: `engine/bin/handslice-cli-x86` (66 MB; `ldd` zeigt kein `libwx*`,
  `libGLFW*`, `libGL*`).
- Testlauf: Slice eines 20-mm-Würfels mit Elegoo CC2 0.4 Düse +
  0.20 mm Standard + Elegoo PLA erzeugt validen G-Code, 100 Layer,
  `return_code: 0`, Statistik (1 201 mm Filament, 2 888 mm³ Volumen,
  3.61 g) plausibel.
- Byte-Vergleich gegen AppImage CLI (mit `--arrange 0 --orient 0` auf
  vorzentriertem STL `cube_20mm_centered_cc2.stl` auf (128, 128)):
  **unterschiedlich**. Hauptursache ist aber **nicht PartPlate** – die
  AppImage CLI (nicht die GUI!) **löst die Preset-Vererbungs-Kette
  nicht auf**, deshalb bleibt bei ihr `skirt_loops=1` (Default) statt
  `0` (Elegoo-Common), und `filament_density=0` statt `1.25`. Unser
  CLI resolvt die Chain korrekt und ist semantisch näher am GUI-Resultat.
  Volltext der Analyse: `docs/engine-integration.md` Abschnitt
  „Nachweislauf (2026-10-24, Byte-Vergleich)".
- Blocker #1 nach `docs/blockers.md` → **Gelöst**.
- Option C (Upstream-PR für saubere CLI/GUI-Trennung) in
  `docs/roadmap.md` unter Phase 3 vermerkt.

### Offene Punkte

- **Byte-Gleichheit gegen Desktop-Orca-GUI-Export** (nicht gegen AppImage
  CLI) steht noch aus. Klaus prüft das manuell: STL in die GUI laden,
  gleiche Profile, slicen, G-Code exportieren, mit unserem CLI-G-Code
  diffen. Nicht blockierend für Phase 0/1.

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
- (keine)
