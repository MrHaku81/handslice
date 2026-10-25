# app/ – Frontend (Flutter)

Mobiler Frontend-Code in **Flutter / Dart**. Entscheidung festgehalten in
`../docs/architecture.md` Abschnitt „UI-Stack: Flutter (ENTSCHIEDEN,
2026-10-25)".

**Verzeichnis ist aktuell leer** – der Flutter-Projekt-Scaffold kommt als
eigener Auftrag.

Erwarteter Umfang:

- Settings-UI, dynamisch aus den Orca-Profil-JSONs aufgebaut
  (`machine/process/filament`-Baum, inherits-Kette aufloesen wie in
  `handslice-cli`).
- 3D-Viewport (Touch) + Layer-/Farb-Preview nach dem Slicen.
- Engine-Bruecke: Phase 0 HTTP-Client gegen `../server/`, Phase 1 Aufruf
  des gebuendelten `handslice-cli-arm64`-Assets per `Process.run`,
  Phase 1+ optional FFI gegen `libslic3r.so` via `dart:ffi`.
- Netzwerk-Modul mit `MoonrakerClient` / `ElegooClient`
  (`../docs/networking-cc2.md`).
- Lokalisierung: ARB-Dateien unter `lib/l10n/`, Quellsprache Englisch,
  erste Zielsprache Deutsch (siehe `../CLAUDE.md` §5).
- Fokus-Navigation per Tastatur/D-Pad/Controller fuer alles ausser dem
  3D-Viewport (Flutter `FocusNode` + `FocusTraversalGroup`, siehe
  `../docs/architecture.md`).

Android-spezifische Teile (Foreground-Service fuer den Slice-Lauf, SAF-
File-Picker, falls `file_picker` nicht reicht) leben als Kotlin-Platform-
Channel-Code im `android/`-Unterordner des Flutter-Projekts – nicht als
eigene Compose-App.
