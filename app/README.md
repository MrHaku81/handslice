# app/ – Frontend (Flutter)

Mobiler Frontend-Code in **Flutter / Dart**. Entscheidung festgehalten in
`../docs/architecture.md` Abschnitt „UI-Stack: Flutter (ENTSCHIEDEN,
2026-10-25)".

## Stand

**Meilenstein 1 (2026-10-25):** leeres App-Grundgeruest mit Werkstatt-
Theme, drei Bildschirmen (Projekt, Drucken, Einstellungen) und
l10n-Setup. Keine Verdrahtung an die CLI oder den Drucker – alle Werte
sind Platzhalter, alle Buttons sind Dummies. Nachbau durch Klaus:

```
export JAVA_HOME="/usr/lib/jvm/java-21-openjdk"
export ANDROID_HOME="$HOME/android-sdk"
export PATH="$JAVA_HOME/bin:$HOME/flutter/bin:$ANDROID_HOME/platform-tools:$PATH"
cd app
flutter pub get
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n dev.handslice.handslice/.MainActivity
```

Screenshots des M1-Stands: `../docs/media/screenshots/m1_*.png`.

## Struktur

```
app/
  pubspec.yaml                 Dart-Deps + Font-Deklaration
  l10n.yaml                    l10n-Generator-Config
  assets/fonts/                IBM Plex Sans + Mono (OFL-1.1, lokal)
  lib/
    main.dart                  App-Shell + Bottom-Nav
    theme/workshop_theme.dart  Design-Tokens Variante A (zentral)
    l10n/
      app_en.arb               Quelle (Englisch)
      app_de.arb               Deutsche Uebersetzung
      app_localizations.dart   generiert (gitignored? nein – eingecheckt)
    screens/
      project_screen.dart      Projekt (Modell, Druckbett, Filamente)
      print_screen.dart        Drucken (G-Code, Switches, Status)
      settings_screen.dart     leerer Platzhalter
    widgets/
      workshop_card.dart       Flaechen-Container
      workshop_row.dart        Label/Value-Zeile
      workshop_banner.dart     Pre-Alpha-Hinweis
  android/                     Android-Projekt (minSdk 29, kotlin, Gradle)
```

## Geplante Erweiterungen (M2–M4, siehe PROGRESS.md 2026-10-25)

- **M2 Slicen in der App:** `handslice-cli-arm64` als Asset / nativeLib,
  Dateiwaehler, bed_type-Auswahl verdrahten, Z-Offset-Speicher.
- **M3 Drucker finden + hochladen:** UDP-Discovery 52700,
  MQTT-Register, Access-Code in `flutter_secure_storage`, CANVAS-
  Slot-Mapping, HTTP-PUT-Upload.
- **M4 Drucken:** `method 1020` mit slot_map/bedlevel_force/
  printer_check/delay_video; Status-Delta-Merge im Drucken-Screen.
  **Druck selbst wird nicht automatisch ausgeloest** – Klaus drueckt
  nach Sichtkontrolle am Geraet.

## Design: Werkstatt (Variante A)

Zentral in `lib/theme/workshop_theme.dart`:

| Rolle | Wert |
|---|---|
| Hintergrund | `#111317` |
| Flaeche | `#1B1F25` |
| Rahmen | `#2E343D` |
| Text | `#E8EAED` |
| Nebentext | `#9AA3AE` |
| Akzent | `#FF8A1F` (Text auf Akzent `#111317`) |
| Schrift Flaeche | IBM Plex Sans (Regular/Medium/Bold, lokal) |
| Schrift Zahlen | IBM Plex Mono (Regular/Medium, lokal) |
| Radien | 6 / 8 |
| Tipp-Target | ≥ 44 px |
| Fokus-Ring | `FocusVisible`-Widget zeichnet Akzent-Rahmen |

Keine Online-Font-Loader (`google_fonts` o.ae.) – alle TTFs liegen im
Asset-Bundle fuer Offline-Betrieb.

## Fokus-Navigation

Shell ist in `FocusTraversalGroup` mit `ReadingOrderTraversalPolicy`
eingewickelt. D-Pad/Tab-Weiterschaltung mit `KEYCODE_DPAD_*` ueber
adb getestet (Meilenstein 1): `adb shell input keyevent
KEYCODE_DPAD_RIGHT`, `KEYCODE_DPAD_CENTER` – Navigation springt
sichtbar zwischen Tabs und Button-Reihen, Fokus-Ring in Akzentfarbe.
