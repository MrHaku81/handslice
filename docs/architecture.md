# Architektur

## Schichten

```
┌─────────────────────────────┐
│   UI  (Flutter oder Compose)│   Scroll-Menüs, 3D-Preview, Slot-Mapping
├─────────────────────────────┤
│   App-Logik / Profilverwalt.│   lädt Orca-Profile (machine/process/filament)
├─────────────────────────────┤
│   Engine-Bridge (JNI/FFI)   │   ruft die Slicing-Engine auf
├─────────────────────────────┤
│   Slicing-Engine (C++, ARM) │   OrcaSlicer-Engine, per NDK gebaut
├─────────────────────────────┤
│   Netzwerk (LAN-Senden)     │   Elegoo-Protokoll / Moonraker
└─────────────────────────────┘
```

Die beiden Elegoo-spezifischen Teile – Profile und Netzwerk – liegen
**außerhalb der Engine**. Sie werden als Schichten draufgesetzt, die Engine
bleibt Orca-Upstream. Siehe `elegoo-integration.md`.

## Komponenten

1. **UI** – mobil-nativ, Touch-first. Gruppierte, ausklappbare Einstellungen
   (Qualität, Struktur, Speed, Supports, Multimaterial); Werte als
   Slider/Eingabe/Toggle. 3D-Viewport (Drehen/Zoomen, nach dem Slicen
   Layer-/Farbvorschau). Preset-Auswahl und Slot-Mapping als Dropdowns.
   **Vollständige Fokus-Navigation**: jedes bedienbare Element außerhalb
   des 3D-Viewports ist per Tastatur, D-Pad und Controller erreichbar
   (Tab/Shift+Tab zum Blättern, Pfeiltasten zum Fokus-Verschieben,
   Enter/Space zum Aktivieren). Keine Touch-only-Interaktionen in Menüs,
   Dialogen oder Listen. Grund: Barrierefreiheit; Nebeneffekt ist, dass
   die App auf Android TV und auf Tablets mit angeschlossener Tastatur
   komplett nutzbar bleibt.
2. **App-Logik / Profilverwaltung** – lädt die Orca-Profil-JSONs 1:1 vom
   Desktop-Format (inkl. `inherits`-Ketten) und baut daraus die Menüs
   dynamisch.
3. **Engine-Bridge** – übergibt Modell + zusammengebaute Config an die Engine,
   holt G-Code + Kennzahlen zurück. JNI (Kotlin) bzw. dart:ffi (Flutter).
   In Phase 0 ist die "Bridge" ein HTTP-Client gegen `server/`.
4. **Slicing-Engine** – siehe `engine-integration.md`.
5. **Netzwerk** – siehe `networking-cc2.md`.

## UI-Stack: Flutter (ENTSCHIEDEN, 2026-10-25)

**Entschieden:** Das Frontend wird in **Flutter (Dart)** gebaut. Android- und
iOS-Builds aus einer Codebasis; `dart:ffi` fuer die Engine-Bruecke;
plattform-spezifische Android-Teile (Foreground-Service fuer das Slicen,
Scoped-Storage-Zugriffe) als Kotlin-Platform-Channel-Code neben dem
Flutter-Modul.

**Begruendung:**

- **iOS-Option kostenlos mitgenommen.** Phase 2 der Roadmap zielt auf
  Mobil-first; iOS als zweites Target bleibt mit Flutter eine
  Rebuild-Entscheidung, mit Compose waere es ein Codebasis-Fork
  (SwiftUI). Fuer ein 1-Entwickler-Projekt der einzige realistische
  Zweit-Plattform-Pfad.
- **dart:ffi fuer die Engine-Bruecke.** Phase 0/1 ruft
  `handslice-cli-arm64` als Subprozess, Phase 1+ ruft optional
  `libslic3r.so` + eigene C-API ueber FFI. Beide Pfade sind in Dart mit
  wenigen Dutzend Zeilen umsetzbar; der JNI-Weg (Kotlin) braucht
  Wrapper-Glue, Datenmarshalling und manuelle Lifetime-Kontrolle.
- **Hot Reload** – fuer das Settings-UI, das sich dynamisch aus den
  Orca-Profil-JSONs (hunderte Felder) aufbaut, ist die Iteration pro
  Layout-Aenderung < 1 s statt Compose-Builds im zweistelligen
  Sekundenbereich. Fuer die Iterationsgeschwindigkeit bei nicht-
  trivialer Formularlogik ist das der groesste praktische Hebel.
- **Fokus-Navigation** – Flutter unterstuetzt vollstaendige
  Keyboard-/D-Pad-/Controller-Fokus-Chains (`FocusNode`,
  `FocusTraversalGroup`); kein Nachteil gegenueber Compose.

**Was in Kotlin statt in Dart lebt:**

- **Foreground-Service fuer den Slice-Lauf.** CLAUDE.md: „MIUI killt
  Hintergrundprozesse aggressiv". Ein Flutter-Isolate ist dagegen nicht
  resistent; der Slice-Prozess wird aus einem Kotlin-`Service` gestartet
  (NotificationChannel + `startForeground`), damit Android ihn nicht
  killt, waehrend der Benutzer die App in den Hintergrund schickt.
  Kommunikation ueber Platform-Channel (JSON-Status an Dart-Side fuer
  die Fortschritts-UI).
- **Scoped-Storage-Zugriffe** (STL/3mf-Import aus User-Verzeichnissen,
  G-Code-Export via SAF) brauchen die Android-System-Intents – die
  liefern wir ueber `file_picker` (Dart-Wrapper) + ggf. eigenen
  `ActivityResultContract`-Code in Kotlin, falls das Paket nicht
  reicht.
- **Spaeter:** iOS-spezifische File-Provider-Extensions in Swift.

**Ausgeschlossen (und warum):**

- **Jetpack Compose** – kein iOS-Pfad; teurer FFI/JNI; weniger
  Iterationsgeschwindigkeit bei UI-Experimenten. Die „fuehlt-sich-nativ-
  an"-Luecke von Flutter ist in Material-3-Apps vernachlaessigbar
  klein geworden; keine der projektrelevanten UIs (Scroll-Settings,
  3D-Viewport, Dialoge) sind Compose-sweet-spots.
- **React Native / Capacitor** – FFI zu C++ ist jeweils schlechter als
  dart:ffi; 3D-Viewport-Integration umstaendlicher.

**Konsequenzen fuer die Architektur-Schicht:**

- `app/lib/l10n/` wird mit ARB-Dateien (Flutter-Standard) befuellt; die
  Lokalisierungs-Regel aus `CLAUDE.md` §5 bleibt unveraendert.
- Die Engine-Bridge-Schicht in der Grafik oben ist in Phase 0 ein
  HTTP-Client gegen `server/` (Dart), ab Phase 1 ein `Process.run`-
  Aufruf auf das gebuendelte `handslice-cli-arm64`-Asset (Dart) bzw.
  spaeter FFI gegen `libslic3r.so` (dart:ffi).

Phase 1 Code-Setup kommt als eigener Auftrag; dieser Doku-Eintrag ist
die Entscheidungs-Fixierung ohne Code-Aenderung in `app/`.

## Datenfluss (MVP)

```
[3mf/STL] ──▶ App-Logik ──(Modell + Config)──▶ Engine-Bridge ──▶ Engine
                                                                    │
   UI ◀── Kennzahlen + Preview ◀── G-Code + Stats ◀──────────────────┘
                                                                    │
                                        Netzwerk ──(G-Code)──▶ Drucker (LAN)
```
