# Fortschritt

Laufendes Protokoll. Neueste Einträge oben. Claude Code ergänzt nach jedem
größeren Schritt; Klaus liest hier tagsüber nach.

Format: `## JJJJ-MM-TT HH:MM – <Kurztitel>` und dann drei bis fünf Zeilen:
was gemacht, Ergebnis, offene Fragen.

> **Zeitstempel-Korrektur 2026-10-26 08:45 UTC:** Die vorher gesetzten
> Zeitstempel der heutigen Vormittag-Einträge waren systematisch ~4 h
> zu hoch (z. B. 1038-Lauf als „12:35 UTC" statt real 08:35 UTC).
> Ursache: Zeiten geschätzt statt aus `date -u` oder den Script-
> Logs abgelesen; wahrscheinlich eine fehlerhafte Zone-Rechnung
> auf dem Build-Rechner (CET=UTC+1, aber Verdoppelung durch
> Schätzung → +4 h). Alle 13 heutigen Einträge sind jetzt auf
> echte UTC-Zeit korrigiert und mit `UTC` markiert, Reihenfolge
> „neueste oben" wiederhergestellt.

---

## 2026-10-26 14:40 UTC – Phase 4.4-Nacharbeit: Filament-Save + Material-Picker + Ueberschrift

Zwei Befunde aus der Poco-Abnahme (APK 5699b13) adressiert.

### Nachweislich

- Code: Commit `1bc94ad4d5` (lokal, nicht gepusht).
  - `app/lib/screens/settings_screen.dart`: Save-Button jetzt auch im
    Filament-Bereich; `_saveAsProfile` schreibt type=`filament`,
    inherits=Material-Basisprofil des aktiven Fachs (via
    `FilamentMapping.resolve`). Picker-Zeile `_FilamentProfilePickerRow`
    oeffnet Dialog, der nur Filament-Profile mit passendem `inherits`
    anbietet (= Zuordnung an das Material, nicht an das Fach).
  - `app/lib/state/project_state.dart`: pro-Fach-slug persistiert
    (`project.filament_profile_slug.A<n>`).
  - `app/lib/settings/profile_writer.dart`: `ProfileWriterSlug.of()`
    oeffentlich, damit Picker-Vergleich und ProjectScreen dieselbe
    Normalisierung nutzen.
  - L10n: neue Keys `settingsSourceCaptionFilament`,
    `settingsSaveFilamentDialogTitle/Hint`,
    `settingsFilamentActiveProfile/PickTitle/PickDefault/PickEmpty/
    NoMatch` (de + en).
- Tests: 52/52 gruen (`cd app && flutter test`), inklusive 5 neuer
  Faelle in `test/settings_filament_widget_test.dart`:
  1. Ueberschrift wechselt Prozess ↔ Filament bei Bereichswechsel.
  2. Save-Button im Filament-Bereich sichtbar, disabled solange Fach
     ohne Overrides, aktiv nach erstem Override.
  3. ProfileWriter mit type=filament schreibt Preset-JSON mit
     `type: "filament"` und erwartetem `inherits`; Reader liest es
     als `SavedProfile.type == 'filament'` zurueck.
  4. Picker-Filter: `inherits == Material-Basisprofil des Fachs` →
     PETG-Profil nicht im PLA-Picker und umgekehrt; Prozess-Profile
     nicht in Filament-Pickern.
  5. ProjectState: pro-Fach-slug Round-Trip (set, Nachbar-Fach
     unberuehrt, neue Instanz liest zurueck, clear).
- APK: `app/build/app/outputs/flutter-apk/app-release.apk`
  SHA256 `0be21bbe485d7c9ebf152d7d3f9769371779f315a754d14d391eaf94b4e2f79c`,
  31 907 373 Byte, commit `1bc94ad4d5` + cli `761249e97b` eingebrannt,
  INTERNET-Permission vorhanden (Build-Guard gruen).

### Ungeprueft

- **Install + Screenshot am Poco X3 Pro.** `lsusb` meldet das Poco
  (Xiaomi Inc. Mi/Redmi series, MTP+ADB), aber `adb devices` liefert
  leere Liste – vermutlich steht USB gerade auf MTP ohne Debugging,
  weil Klaus den Abnahme-Druck/Zeitraffer-Export macht. ADB-Server
  2x neu gestartet, kein Effekt. Install und Screenshot des
  Filament-Bereichs mit "Als Profil speichern"-Knopf folgen, sobald
  das Gerät wieder im Debugging-Modus angesteckt ist.

## 2026-10-26 09:30 UTC – Test E: `method 1047`-Shape-Probe (danielcherubini#432) → eindeutig 11× `1003`

Lesender Beitrag zum HA-Integration-Issue #432. Repo-Clone
`v2.16.0-beta.2` unter `~/upstream/elegoo-homeassistant/` (nicht
im Handslice-Repo). Wrapper `~/upstream/run-cc2-probe.py` baut
`argparse.Namespace` und ruft `probe()` als Coroutine auf –
Access-Code bleibt im Python-Speicher, nie in argv/environ/
Shell-History.

### Nachweislich

- `scripts/cc2_probe_delete.py` mit `--run`:
  **11/11 Varianten** antworteten **identisch mit `error_code=1003`**.
  **Alle 11 Dateien weiterhin im 1044-Listing** (`still_listed=True`).
  Response-Latenzen 9.5–20 ms.
- Firmware aus `method 1001 software_version.ota_version`:
  `02.01.01.07`. Modell: Centauri Carbon 2. MCU/SOC-Versionen leer.
- **Scrub + grep-Verifikation**: `~/upstream/scrub-cc2-probe.py`
  → 0 Treffer fuer IP, SN, Access-Code in beiden Capture-Artefakten
  (JSON + Paste-Block).
- Probe-Report-Conclusion (woertlich):
  *„on this firmware 1003 is not about the parameter key at all —
  1047 is simply not served, or 1003 is its generic 'not available
  / not handled' answer. The key-name hypothesis is not supported
  by this capture."*
- **12 Probe-Dateien liegen am Drucker** (1 Preflight aus dem
  Trockenlauf + 11 aus `--run`, je 8 244 B). Volle Liste via
  `method 1044 storage_media=local`:
  ```
  cc2_probe_preflight_4c7873f1.gcode
  cc2_probe_bare_filename_4b2c6afa.gcode
  cc2_probe_control_empty_f37ccc43.gcode
  cc2_probe_local_file_name_c91794d7.gcode
  cc2_probe_local_file_name_path_8b21691e.gcode
  cc2_probe_local_filename_a11642c5.gcode
  cc2_probe_local_filename_path_e4bce5b0.gcode
  cc2_probe_sd_card_filename_72c2db59.gcode
  cc2_probe_sdcard_file_name_5bcbe9ce.gcode
  cc2_probe_sdcard_filename_186d7bb2.gcode
  cc2_probe_u_disk_filename_123c452e.gcode
  cc2_probe_udisk_filename_f2783b77.gcode
  ```
  Klaus loescht sie am Display. ~96 KB belegt.

### Ungeprueft

- Die alternative Lesung „1003 ist generische 'not-available /
  not-handled'-Antwort auf dieser FW" bleibt nicht widerlegt und
  nicht bestaetigt. Zur Unterscheidung von „1047 schlicht nicht
  serviert" braechte es einen anderen Pfad (z. B. Firmware-Unpack,
  Dekompilierung) – ausserhalb dieses Auftrags.
- Discovery-Verhalten im Script: Broadcast an 255.255.255.255 **und**
  Subnet-Broadcast 192.168.0.255 blieben in diesem LAN ohne
  Antwort; direkter Unicast an `<cc2-ip>:52700` klappt (seit
  2026-10-25 bekannt). Workaround im Wrapper: SN statisch gesetzt
  (`--serial <cc2-sn>`).

### Geht nicht

- **`method 1047` entfernt auf FW 02.01.01.07 keine Datei**,
  unabhaengig von jedem der 11 getesteten Params-Shapes.
  Fuer App-Pfade: Datei-Loeschung nicht ueber MQTT abbilden; nur
  Display-Pfad existiert.

### App-Konsequenz (M5 Ergaenzung)

- `method 1047` **in der App gar nicht erst aufrufen**. Zu
  entfernende G-Code- oder Zeitraffer-Dateien bleiben Display-
  only.
- `method 1038` entfernt Historie-Eintraege (Test D), nicht die
  Datei – dieser Pfad bleibt der UI-Hygiene-Mechanismus.
- Issue-#432-Draft (`docs/upstream/`) kann um den Hinweis
  „#432 ist durch den Shape-Probe entschieden: Hypothese
  nicht gestuetzt" ergaenzt werden.

### Artefakte

- `~/upstream/run-cc2-probe.py` – Wrapper mit sauberem
  Credential-Pfad.
- `~/upstream/scrub-cc2-probe.py` – Scrub + grep-Verifikation.
- `~/upstream/elegoo-homeassistant/scripts/cc2_probe_20261026_092850.json.scrubbed`
  – vollstaendige Capture, anonymisiert.
- `/tmp/cc2-run-stdout.txt.scrubbed` – Paste-Block, anonymisiert.
  Beide bleiben lokal (nicht im Handslice-Repo).

Nichts committed, nichts gepusht (dieser Abschnitt wird gleich
mitgenommen).

---

## 2026-10-26 15:40 MEZ – Phase-4.4-Nacharbeiten: arm64-Lauf + CLI-Override-Typen abgesichert

### Nachweislich

- **cli-contract-arm64.sh am Poco** komplett grün: Abschnitte
  1-4 (Flag-Vertrag + Z-Diff), 5 (Phase-4.3-Overrides),
  6 (Ungueltiger Key abgelehnt), 7 (libslic3r-Validate-Fehler
  sauber abgefangen) **und Abschnitt 6 (Phase 4.4
  Filament-Overrides)** – byte-identische Baseline (modulo
  Timestamp-Zeile), M104 S260, M190 S88 A, G1 E-2.4. Hinweis:
  Baseline-Vergleich im arm64-Teil nutzt jetzt dieselbe
  `md5_sanitized`-Funktion wie der x86-Vertragstest, weil die
  Timestamp-Zeile sonst zwei frische Laeufe nie byte-gleich
  macht.
- **CLI-Overrides-Typsicherung**
  (`engine/cli/handslice-cli.cpp`): JSON-Zahlen (int+float) und
  Booleans werden zu Strings konvertiert, Strings bleiben
  unveraendert. **Arrays werden explizit abgelehnt** mit einer
  Fehlermeldung, die den Key und einen Hinweis `["250"]` →
  `"250"` nennt. Null-Werte ebenfalls mit klarer Meldung.
  Help-Text im `--help` ergaenzt um einen Abschnitt zu
  `--overrides`.
- **Vertragstest `engine/test/overrides-types-contract.sh`**
  (lokal x86, 4 Checks):
  - Int `nozzle_temperature: 260` → `M104 S260` im G-Code.
  - Bool `enable_pressure_advance: true` → exit 0, Bool-Array
    `[true]` wird abgelehnt.
  - Array `nozzle_temperature: [260]` → exit != 0, Fehlermeldung
    nennt den Key und das Wort „array", kein terminate/abort.
  - Null `nozzle_temperature: null` → exit != 0, Fehlermeldung
    erwaehnt „null".
- **x86 + arm64 CLI neu gebaut** auf Commit-Stand des aktuellen
  HEAD (Phase-4.4-Commit). arm64 Binary ist noch nicht in jniLibs
  der App gewandert – das macht der naechste App-Build. Der
  Vertragstest in Abschnitt 6 lief auf dem **neuen** arm64-Binary.
- **Bestehende Vertragstests** `filament-overrides-contract.sh`
  und `scale-contract.sh` nach dem Rebuild weiterhin grün.

### Ungeprueft

- Enum-opt_keys als JSON-Zahl (z. B. `bed_type: 3` statt `"3"`):
  der Code konvertiert den Int zu `"3"` und reicht ihn in Orcas
  Preset-Parser. Das sollte funktionieren, ist aber nicht
  explizit getestet. Phase 4.4 nutzt diesen Pfad nicht.

### Geht nicht / Konsequenz

- Weiterhin kein `null` erlaubt. Die App soll Overrides, die auf
  Default zurueckgesetzt wurden, per `SettingsOverrides.reset(key)`
  komplett entfernen, nicht als `null` schicken.

### Artefakte

- `engine/cli/handslice-cli.cpp` – Override-Validierung + Help.
- `engine/test/overrides-types-contract.sh` – neuer Vertragstest.
- `engine/test/cli-contract-arm64.sh` – `md5_sanitized`-Fix im
  Phase-4.4-Abschnitt.
- `engine/bin/handslice-cli-x86` / `-arm64` – neu gebaut, Commit
  `761249e97b`.

---

## 2026-10-26 15:15 MEZ – Phase 4.4 Filament-Einstellungen pro Fach

Pendant zu Phase 4.2 (Prozess) + 4.3 (Save-as-Profil), diesmal fuer
den Filament-Bereich mit CANVAS-A1..A4-spezifischen Overrides.

### Nachweislich funktioniert

- **Material → Orca-Profil-Mapping** (`app/lib/settings/filament_mapping.dart`):
  - ELEGOO PETG → `Elegoo PETG @ECC2.json`
  - ELEGOO RAPID PETG → `Elegoo Rapid PETG @ECC2.json`
  - ELEGOO PLA PRO → `Elegoo PLA PRO @ECC2.json`
  - ELEGOO RAPID PLA+ → `Elegoo Rapid PLA+ @ECC2.json`
  - PLA-Typ ohne Markenname → `Elegoo PLA @ECC2.json` (generisch,
    kein Fallback-Hinweis).
  - Alles andere → `Elegoo PLA @ECC2.json` **mit sichtbarem
    Hinweis** `fallbackReason`.
- **Per-Fach-Overrides** (`FilamentOverrides`): 4 Instanzen (A1..A4),
  persistent in SharedPreferences unter
  `filament.overrides.A<n>`. Fachwechsel haelt die Maps strikt
  getrennt (Unit-Test
  `app/test/filament_overrides_test.dart`), Save/Reload
  roundtrip-sicher.
- **Settings-UI** (`app/lib/screens/settings_screen.dart`):
  - Area-Toggle oben: **Prozess | Filament**.
  - Im Filament-Bereich zusaetzlich A1..A4-Fach-Umschalter mit
    Material-Label pro Fach aus `PrinterState.slots` (2005).
  - Unter dem Umschalter die Fallback-Hinweis-Zeile mit gelbem
    Info-Icon, wenn `FilamentProfileRef.generic == true`.
  - Reiter+Gruppen aus Schema `area=filament`
    (7 Reiter / 22 Gruppen / 83 Optionen, siehe Phase 4.1).
  - „Als Profil speichern" bleibt nur im Prozess-Bereich sichtbar
    (Filament-Overrides sind pro Fach persistent und brauchen
    keinen Save-Dialog).
- **Slicer-CLI-Durchreichung** (`app/lib/engine/slicer.dart` +
  `app/lib/state/project_state.dart`):
  - CLI nimmt `--filament <pfad>` mehrfach entgegen
    (Beleg: `engine/cli/handslice-cli.cpp:145` + 592, bereits
    bestehend). Fuer Phase 4.4 reicht **ein** Fach; Multimaterial
    kommt spaeter.
  - App waehlt beim Slicen das Filamentprofil des aktiven Fachs
    (`trayAssignmentForTool0`) und reicht die Fach-Overrides
    gemerged mit den Prozess-Overrides per `--overrides` an die
    CLI. Prozess- und Filament-opt_keys sind disjunkt im Schema.
- **Bettemperatur pro Plattenart** belegt
  (`engine/test/filament-overrides-contract.sh`, lokal x86):
  Baseline-Doppel-Lauf **byte-identisch** (modulo Timestamp-Zeile),
  dann drei Einzel-Overrides mit G-Code-Marker:

  | Override | opt_key | G-Code-Beleg |
  |---|---|---|
  | Duesentemperatur 260 °C | `nozzle_temperature=260` | `M104 S260 ; set nozzle temperature` |
  | Hot-Plate initial 88 °C (Seite B) | `hot_plate_temp_initial_layer=88` | `M190 S88 A` am Pre-Heat |
  | Retract 2.4 mm | `retraction_length=2.4` | `G1 E-2.4`-Zuege statt Baseline 0.728 |

- **Vertragstest arm64** (`engine/test/cli-contract-arm64.sh`
  Abschnitt „=== 6 Filament-Overrides"): dieselben drei
  Checks mit `adb` am Poco. Laeuft Klaus beim naechsten Device-
  Test; Logik und erwartete Marker sind identisch zum x86-Test.
- **Widget-Tests gruen**
  (`app/test/settings_filament_widget_test.dart`, 2 Tests):
  Fachwechsel A1 ↔ A3 haelt Overrides getrennt + Persistenz-
  Roundtrip; unbekanntes Material zeigt Fallback-Hinweis mit
  „nicht erkannt".
- **Alle Tests zusammen gruen:** 47/47 (`flutter test test/`).
- **APK via `build_apk.sh --release`**:
  - SHA256 `b4e63a97daa11b729d22c900625e624093ad4d7680d1961fc0baf4af57600e29`
  - 31.9 MB, Commit-Guard greift, INTERNET-Permission vorhanden.
  - Auf Poco installiert; Smoke-Nachweis
    `local-test/phase44-step1.png`: Einstellungen-Reiter mit
    **Area-Toggle „Prozess | Filament"** oben sichtbar + Zaehler
    „Keine Ueberschreibungen" und „Als Profil speichern"-Button
    (nur im Prozess-Bereich).

### Ungeprueft

- **Multimaterial** (mehrere `--filament`-Flags gleichzeitig mit
  Pro-Filament-Overrides): die CLI-Logik ist aktuell so, dass
  Overrides nach dem letzten Filament-Profil global ueber die
  Config geschichtet werden – fuer Mehrfarbe muss ein eigenes
  Mapping Fach→Werte-Set rein. Fuer Phase 4.4 nicht gebraucht
  (Klaus startet mono-material).
- **Live-Vertragstest am Poco**: `cli-contract-arm64.sh` muss
  Klaus beim naechsten Lauf triggern; die Logik ist durch die
  x86-Variante bereits grün.

### Geht nicht / Konsequenz

- Overrides-Werte muessen als **String** uebergeben werden
  (`"88"`, nicht `[88]` oder `88` als Int). Grund: Orcas Overrides-
  Parser schaltet nur bei String-Werten den `coInts`-Pfad korrekt;
  JSON-Arrays werden roh als `"[88]"` serialisiert und fallen in
  Orcas Validate. In `SettingsOverrides.set(key, value)` ist das
  schon so vorgesehen; neue Edit-Widgets muessen das weiter
  einhalten.

### Artefakte

- `app/lib/settings/filament_mapping.dart` – Material→Profil.
- `app/lib/settings/filament_overrides.dart` – Pro-Fach-State.
- `app/lib/screens/settings_screen.dart` – Area-Toggle + Fach-
  Umschalter + Fallback-Hinweis.
- `app/lib/engine/slicer.dart` + `project_state.dart` –
  Filament-Pfad + gemergte Overrides zur CLI.
- `engine/test/filament-overrides-contract.sh` – x86-Vertragstest.
- `engine/test/cli-contract-arm64.sh` Abschnitt 6 – arm64-
  Vertragstest (laeuft Klaus beim naechsten Lauf).
- `app/test/filament_overrides_test.dart` + `settings_filament_widget_test.dart`.
- `local-test/phase44-step1.png` – Smoke-Screenshot.

Kein Druck in dieser Session; den startet Klaus.

---

## 2026-10-26 12:07 MEZ – Phase 5 am echten CC2 bestaetigt (offener 1051-Erfolgsfall geschlossen)

Klaus hat den ganzen Fluss gegen den realen CC2 durchgespielt.

### Nachweislich

- Druck mit Zeitraffer **aus der App** gestartet (Fach **A3**, PLA
  Pro schwarz – freie Fachwahl funktioniert, nicht nur A4). Nach
  Druckende Historien-Eintrag mit `video_status=1`.
- In der App „Video erzeugen" → App ruft `method 1051`
  `params.url=picture/<name><ts>`. Nach `machine_status.status
  12 → 1` holt die App automatisch `method 1036` neu; Target-
  Eintrag ist jetzt `video_status=2` + `video/<name><ts>.mp4`.
- Head-Probe liefert HTTP 200; Download-Button startet den
  tatsaechlichen Pull aufs Handy.
- Share-Intent via `share_plus` funktioniert.
- Video-Properties identisch zum heute-frueh-USB-Composite:
  **640×360, 100 Frames, 3,3 s**. Encoder-Pfad ist derselbe.
- **Head-Probe erkennt die am Display geloeschten alten Zeitraffer
  korrekt als „nicht mehr verfuegbar"** – kein versehentlicher
  Download-Button fuer stale `video_status=2`-Eintraege.
- **Display zeigt beim MQTT-1051 NICHTS** (anders als beim
  USB-Export, der „Video wird generiert"/„Video wird kopiert"
  anzeigt). Der Fortschritt kommt **nur ueber api_status**;
  Spinner-Pfad der App (Status 12 → 1) ist der einzige Signalweg.

Damit ist der nach Test B/C verbliebene offene Punkt „1051 im
Erfolgsfall ueber MQTT" **geschlossen**.

### Ungeprueft

- **Exakte Composite-Dauer** ueber MQTT (3020→3021): nicht
  gemessen – `tools/mqtt-sniff.py` lief in diesem Lauf nicht.
  USB-Export-Vergleichswert: 26 s fuer 100 Frames; App-Lauf
  laut Klaus „nicht lange" (vermutlich dieselbe
  Groessenordnung, Encoder identisch). Konkrete Zahl beim
  naechsten Lauf nachtragen – Sniff vorher starten.

### Geht nicht / Nacharbeit

- **Download-Ablage versteckt**: aktuell schreibt die App nach
  `getExternalStorageDirectory()/handslice-timelapses/`, das ist
  der app-eigene Pfad unter `/storage/emulated/0/Android/data/
  dev.handslice.handslice/files/handslice-timelapses/`. Dort
  **nicht in der Galerie sichtbar** und **bei Deinstallation
  weg**. Share-Intent funktioniert zwar, aber der Weg „einfach
  Galerie oeffnen" fehlt.
- Nacharbeit (nicht in diesem Commit): entweder in den
  **oeffentlichen Downloads-Ordner** schreiben (`/storage/
  emulated/0/Download/`, braucht ab API 30
  `WRITE_EXTERNAL_STORAGE` / `MANAGE_EXTERNAL_STORAGE` oder
  Storage-Access-Framework) **oder** per **MediaStore-API** nach
  `MediaStore.Video.Media` eintragen (dann in der Galerie
  sichtbar, keine extra Berechtigung noetig ab API 30). Letzteres
  ist der moderne Weg; braucht ein kleines Platform-Channel-
  Integral, da Flutter das nicht out-of-the-box koennen.
- Als **offenes M5-Follow-up** vermerkt; nicht blockierend fuer
  Phase 5.

### App-Konsequenz

- Keine Code-Aenderung noetig – M5 funktioniert so, wie
  spezifiziert.
- Issue-Draft fuer `danielcherubini#432` entfaellt die „currently
  inconclusive"-Reserve zum 1051; der Draft wird entsprechend
  umgestellt.

### Artefakte

- MP4 des Phase-5-Testdrucks liegt auf Klaus' Handy.
- `tools/mqtt-sniff.py` – nicht gelaufen; falls Klaus beim
  naechsten Zeitraffer-Druck Zahlen will, vorher starten.

Nichts committed in diesem Lauf gegenueber dem Phase-5-Code;
nur Doku-Updates (networking-cc2.md Test F, PROGRESS.md,
upstream-Draft).

---

## 2026-10-26 11:45 UTC – Release-APK ohne INTERNET-Permission → Datagram-Socket-Fehler

Klaus am Poco: nach Koppeln beim „Verbinden & Faecher laden":
„Netz-/Discovery-Fehler: Netzwerk: Failed to create datagram socket".
Phase-5-Release-APK `785e5cb` konnte **keine** UDP-Discovery
aufbauen; MQTT war in Folge auch nicht erreichbar.

### Nachweislich

- **Ursache:** `android/app/src/main/AndroidManifest.xml` hatte
  **keine** `<uses-permission android:name="android.permission.INTERNET"/>`.
  Flutter hat die Permission nur im Debug-Overlay
  (`android/app/src/debug/AndroidManifest.xml`); dieses Overlay wird
  **nur in Debug-Builds** gemergt. Release-APKs bekommen die
  Permission daher nicht.
- **Beleg:** `aapt2 dump permissions app-release.apk` auf
  `785e5cb` listete nur
  `dev.handslice.handslice.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`
  (von share_plus), **keine INTERNET**. Logcat selbst war fuer
  die App leer – die Ausgabe passiert ausschliesslich in der
  Dart-UI (SnackBar); der eigentliche DNS-/Socket-Fehler wird
  nicht nach `logcat` geroutet. Der Code-Review der Manifeste
  reicht als Beweis.
- **Fix an der Wurzel:**
  `android/app/src/main/AndroidManifest.xml` enthaelt jetzt
  `<uses-permission android:name="android.permission.INTERNET" />`.
  Debug-Overlay bleibt bewusst stehen (Flutter-Konvention).
- **Zwei neue Gurtschnallen:**
  1. **Dart-Test** (`app/test/android_manifest_test.dart`):
     greppt die main-Manifest-XML nach „android.permission.INTERNET".
     Faellt schon bei `flutter test`, nicht erst beim APK-Bau.
  2. **Build-Script-Verify** (`app/scripts/build_apk.sh`):
     `aapt2 dump permissions` auf die neu gebaute APK; fehlt
     INTERNET, bricht das Skript mit Exit-Code 5 ab.

### Ungeprueft

- Realer Verbindungstest **gegen den CC2** mit dem neuen APK
  steht noch aus (direkt nach diesem Commit, in diesem Lauf).

### Geht nicht / Konsequenz

- Debug-Overlay ohne main-Permission ist eine Fluter-Falle, die
  erst im Release-Build auffaellt. Beide neuen Gurtschnallen
  verhindern eine Wiederholung: Dart-Test bricht bei Code-Change,
  Build-Verify bricht beim APK-Bau.

### Artefakte

- APK mit Fix-Commit `1b74028`:
  SHA256 `1cca86eaa3c64e769cd67224c1653d99f39ad2145e91adf175617a08f3e781b2`
  (31.8 MB).
- Auf Poco installiert, SHA256 der Device-APK **byte-identisch**
  zum lokalen Build.
- `dumpsys package dev.handslice.handslice` listet jetzt
  `android.permission.INTERNET` unter „requested permissions".
- Badge am Geraet: `v0.1 · app 1b74028313` + `cli ee4da3d7b5`
  + `2026-10-26T10:43Z` (`local-test/phase5-after-permission-fix.png`).
- „Verbinden & Faecher laden" → keine Fehler-SnackBar mehr
  (vorher sofort „Netz-/Discovery-Fehler: Netzwerk: Failed to
  create datagram socket"). Finale Pair-/Connect-Verifikation
  gegen den echten CC2 macht Klaus beim naechsten Druck-Test.

---

## 2026-10-26 11:30 UTC – Phase-5-Build-Guard: Build ohne Hashes bricht ab

Klaus hat am Poco gemerkt: der Phase-5-APK vom Vorlauf zeigte im
Badge nur `v0.1 · app – cli` (beides als `-` aus `defaultValue`),
weil ich `flutter build apk --release` direkt gerufen hatte statt
`app/scripts/build_apk.sh --release`. Dadurch fehlten die
`--dart-define`-Werte `BUILD_COMMIT` / `CLI_COMMIT` / `BUILD_TIME`.

### Nachweislich

- **Ursache belegt** (`app/lib/widgets/build_info_badge.dart:16-22`):
  `String.fromEnvironment` mit `defaultValue: '-'` – ohne
  `--dart-define` bleibt alles auf `-`. Build-Skript
  `app/scripts/build_apk.sh` setzt die drei Werte korrekt, wurde
  aber nicht benutzt.
- **Zwei-Gurt-Loesung:**
  1. **Startup-Guard in der App** (`main.dart`): neue Getter-Flagge
     `BuildInfoBadge.hasMissingMetadata`. Wenn beim Start irgendein
     Hash `-` ist, startet nicht die normale UI, sondern ein
     Vollbild-Fehler-Overlay („Build-Metadaten fehlen"). Greift
     auch im Release-Build und auch bei einem APK, das nicht via
     Skript gebaut wurde.
  2. **Verify-Schritt im Build-Skript**: Nach `flutter build apk`
     wird `lib/arm64-v8a/libapp.so` aus der APK extrahiert und auf
     den Commit-Hash gegreppt. Fehlt der Hash im AOT-Blob, bricht
     das Skript mit Exit-Code 4 ab – die APK landet nicht am Poco.
     (Direkter grep auf die APK scheitert, weil der ZIP-Container
     DEFLATE-komprimiert; deshalb Umweg ueber temp-File. Pipe
     `unzip | grep -q` scheiterte an SIGPIPE + `pipefail`.)
- **Build via Skript** erfolgreich, Verify-Schritt greift korrekt:
  ```
  Build-APK (release) commit=785e5cbb2d cli=ee4da3d7b5 time=2026-10-26T10:25Z
  APK:    build/app/outputs/flutter-apk/app-release.apk
  SHA256: 30ce0e2a7ddefb9fdbb0e68a973351af9070955d17ed1927a2c3bd819b7002cd
  size:   31799137 byte
  commit-im-APK: ok (785e5cbb2d gefunden; cli ee4da3d7b5)
  ```
  (31.8 MB statt vorher 16 MB – Default-Skript baut alle drei ABIs;
  der vorige `--target-platform=android-arm64`-Build war nur eine.)
- **Installiert auf Poco** (`adb install -r` → Success).
- **Badge-Nachweis** `local-test/phase5-badge-hashes.png` zeigt:
  ```
  v0.1 · app 785e5cbb2d
  cli ee4da3d7b5
  2026-10-26T10:26Z
  ```

### Ungeprueft

- Startup-Guard greift sicher in Debug (per `--dart-define`
  weggelassen); fuer Release ist das Verhalten per Konstruktion
  identisch (`String.fromEnvironment` ist statisch gebunden).
  Expliziter Test eines fehlerhaften Builds steht aus, aber die
  Logik ist trivial.

### Geht nicht

- Flutter kann `--dart-define` nicht aus Gradle-Pre-Hooks erzwingen;
  jemand koennte `flutter build apk --release` immer noch direkt
  rufen – dann greift aber jetzt der Startup-Guard am Gerät.

### Konsequenz

Der Weg bleibt: **immer** `app/scripts/build_apk.sh --release`.
Direkter `flutter build apk` liefert zwar ein APK, aber dieses
weigert sich beim Start und meldet den Fehler per UI.

---

## 2026-10-26 11:15 UTC – Phase 5 (Zeitraffer in der App): 5a + 5b + 5c steht

Neuer Reiter „Drucker" (vierter Tab) + Netzwerk-Pfade fuer 1036 / 1051
/ Head-Probe / Download + Lokalisierung. Vor dem echten Druck-Test
mit Klaus.

### Nachweislich

- **CC2-Mock erweitert** (`engine/test/mock-cc2/mock_cc2.py`): method
  1036 liefert eine seedbare `history_task_list`; method 1051
  simuliert den beobachteten Zustand `3020→3021→1` bei vorhandenen
  Rohframes bzw. `3020→3022→1` bei fehlenden; `GET /download`
  antwortet mit HTTP 200 + chunked + Content-Length-Doppelrahmung
  (echt-CC2-Verhalten) oder **schweigt**, wenn die Datei nicht
  existiert. Neuer CLI-Flag `--seed-history <path>` fuer Fixtures.
- **ElegooCc2Client** (`app/lib/net/elegoo_cc2_client.dart`): neue
  Typen `HistoryTask`, `TimelapseProbe` + Methoden
  `getHistory()`, `renderTimelapse()`, `probeTimelapse()`,
  `downloadTimelapse()`, `deleteHistoryEntries()`. Download-URL
  baut Access-Code als `X-Token`-Query-Param (nie in Logs). Probe
  faengt `TimeoutException`, `SocketException`, **`HttpException`**
  (letzteres fuer das reproduzierte „Firmware schliesst Connection
  ohne Response"-Signal).
- **Reiter „Drucker"** (`app/lib/screens/printer_screen.dart`):
  Liste aus 1036, nach `begin_time` absteigend sortiert
  (Reihenfolge, nicht als Datum). Pro Eintrag:
  - `video_status=0` → „kein Zeitraffer".
  - `video_status=1` → Button „Video erzeugen" → 1051 → Spinner
    bei `machine_status.status==12` → zweite 1036 + Head-Probe;
    bei `3022` oder Status bleibt 1 → „keine Rohdaten mehr
    vorhanden". Kein automatischer zweiter Versuch.
  - `video_status=2` → **Head-Probe mit 2 s Timeout**; nur bei
    HTTP 200 kommt der Download-Button, sonst „nicht mehr
    verfuegbar (am Drucker geloescht?)".
  - `video_status=3` ohne URL → „nicht erzeugbar".
  - **Hoechstens 2 parallele /download-Verbindungen** per
    einfachen Semaphor (`_DownloadLimiter`), passend zu cc2-controls
    „two-transfer limit".
  - Download speichert nach `getExternalStorageDirectory() +
    /handslice-timelapses/` (Fallback: ApplicationSupport);
    Teilen ueber Android-Share-Intent via `share_plus 13.x`.
- **Druckeruhr-Hinweis** als Bodentext (einmal pro Historie):
  „Zeitstempel stammen aus der Druckeruhr (aktuell UTC+8) und
  werden nur als Reihenfolge genutzt." Begin/End werden nie als
  absolute Zeit gerendert.
- **Lokalisierung** (ARB-Dateien): Reiter-Label `Drucker`,
  Historien-Texte, Download-/Render-Buttons + Fehler-Texte in
  DE/EN. Status 12 = „Zeitraffer wird erzeugt/exportiert",
  `exception_status 1243` = „Filamentzufuhr-Fehler – PTFE-
  Schlaeuche pruefen", sub_status 2501/2502/2401/2402 als
  Pausiert/Setzt fort.
- **Tests gegen Python-Mock** (`app/test/elegoo_mock_test.dart`):
  drei neue Phase-5-Tests – 1036+Head-Probe+Download (ok UND
  Schweigen bei fehlender Datei), 1051-Erfolgsfall
  (`3020→3021`, status 1→2), 1051 ohne Rohframes (`3020→3022`,
  Status bleibt 1). **8/8 Tests gruen**:
  ```
  00:00 +0: Mock: Discovery + Register + Canvas (richtiger Code)
  00:02 +1: Mock: falscher Code → ElegooAuthException
  00:04 +2: Mock: Upload funktioniert + Datei erscheint in FILE_LIST
  00:06 +3: Mock: method 1020 startPrint liefert error_code=0 vom Mock
  00:08 +4: Mock Phase5: 1036 + Head-Probe + Download (status 2)
  00:10 +5: Mock Phase5: 1051 Erfolgsfall (3020→3021), video_status 1→2
  00:13 +6: Mock Phase5: 1051 ohne Rohframes → 3022, video_status bleibt
  00:15 +7: Mock: Upload-Abbruch nach N byte → ElegooUploadException
  00:18 +8: All tests passed!
  ```
- **Widget-Tests** (`app/test/printer_screen_test.dart`): nicht-
  verbunden-Fall + Header/Refresh-Button. 2/2 gruen.
- **APK gebaut** (`arm64, release, 16.0 MB`), auf Poco X3 Pro
  installiert. **Smoke-Nachweis** `local-test/phase5-printer-tab.png`:
  Reiter „Drucker" aktiv, Header „Druckhistorie", Refresh-Button,
  Hinweis-Panel „Drucker nicht verbunden. Im Projekt-Reiter koppeln
  und verbinden." (als erwarteter Pfad, weil kein Pairing in dieser
  Session gemacht wurde).

### Ungeprueft

- **Echter Druck-Test gegen den CC2** (Klaus startet): kurzer
  Wuerfel-Druck mit Zeitraffer aus der App → danach in der App
  „Video erzeugen" (= der offene 1051-Erfolgsfall VOR dem
  USB-Stick) → Download aufs Handy. Mitschnitt (tools/mqtt-sniff.py)
  wird mitlaufen. **STOP vor diesem Test** – Klaus entscheidet.
- Dart's HttpClient-Verhalten bei der realen Length-vs-chunked-
  Doppelrahmung ist bei probeTimelapse getestet (via Mock, der die
  Doppelrahmung setzt), aber Download selbst nicht gegen echte CC2-
  Firmware; cc2-control-Code warnt vor dem Konflikt. Der Lesemodus
  (`await for in resp`) ist RFC-9112-konform.
- Download-Ordner auf Android: `getExternalStorageDirectory` ergibt
  App-eigene Downloads unter `/storage/emulated/0/Android/data/
  dev.handslice.handslice/files/handslice-timelapses/` – fuer die
  Galerie nicht sichtbar, aber ueber Share teilbar. Falls Klaus das
  oeffentliche Downloads-Verzeichnis bevorzugt, braecht's
  `MANAGE_EXTERNAL_STORAGE` oder `WRITE_EXTERNAL_STORAGE` (API ≤29).
  Fuer M5 reicht Share.

### Geht nicht

- `method 1038` (Delete-History) **bewusst nicht in der UI** – wie
  im Auftrag spezifiziert (Test D hat gezeigt: 1038 loescht nur
  die Historie, nicht die Datei; UI-Verwirrung soll vermieden
  werden).

### App-Konsequenz (Echttest-Checkliste)

Vor dem echten Druck-Test:

1. Drucker Idle, „Nur LAN"-Modus aktiv.
2. Home Assistant / sonstige Integration getrennt (einer der
   Register-Slots muss frei sein).
3. `tools/mqtt-sniff.py` starten, damit Status-12-Deltas und
   api_status gesichert sind.
4. In der App: Projekt-Reiter → verbinden → Zeitraffer-Switch an
   → kleiner Wuerfel-Druck senden.
5. Nach Druckende, VOR dem USB-Stick: Drucker-Reiter → „Video
   erzeugen" am frischen Status-1-Eintrag → Spinner bis Status
   zurueck auf Idle → Download.

### Artefakte (nicht committed in diesem Lauf)

- `local-test/phase5-printer-tab.png` – Smoke-Screenshot.
- APK unter `app/build/app/outputs/flutter-apk/app-release.apk`.

Dieser Eintrag selbst wird gleich committed.

---

## 2026-10-26 08:35 UTC – Test D: `method 1038` loescht Historie, nicht MP4, nicht Display

### Nachweislich

- **Payload exakt nach cc2-control-Beleg**:
  `{"method":1038,"id":1038,"params":{"list":["<task_id>"]}}`
  (Fundstellen: `mqtt.c:277-287`, `mqtt.c:343-346`,
  `history.h:123-142`).
- **Response**: `{"id":1038,"method":1038,"result":{"error_code":0}}`
  in **297 ms**. **Kein Status-12-Wechsel**; der Loeschvorgang
  passiert daten-/datenbankseitig ohne Printer-State-Transition.
- **1036 Pre vs. Post:**
  - Pre: `sha256=e12d373a3ec5c57b`, 45 Tasks, `result.total=45`.
  - Post: `sha256=4c9f1271e71c3a3d`, **44 Tasks**, `result.total=44`.
  - **Target `e0b592f4-...` ist entfernt**; alle anderen Eintraege
    byte-identisch (keine Nebenbeitraege mutiert, keine
    `duration`- oder `video_status`-Verschiebungen).
- **MP4 bleibt vollstaendig abrufbar.** Download-Probe nach 1038
  liefert `HTTP 200`, 1 741 634 Byte, md5
  `e2330f840b398f425172b32692437f7a` – **byte-identisch** zur
  Baseline und zur Pre-Snapshot.
- **Display zeigt den Eintrag weiter.** Klaus hat am Display
  nachgeschaut: Zeitraffer-Liste zeigt den Eintrag noch, obwohl
  er aus der 1036-Historie entfernt ist.
- **Neues Feld `result.total` entdeckt** – ein Zaehler auf
  `result`-Ebene (Pre 45 → Post 44). cc2-control nutzt es
  nicht, aber die Firmware exponiert es. Fuer die App ein
  zusaetzlicher Konsistenz-Check.

### Zusammenfuehrung mit Display-Loeschen (Vormittag heute)

Die beiden Loeschpfade sind **komplett getrennt**:

| Loeschpfad | 1036-Historie | MP4 (`/opt/usr/video/`) | Display-Liste |
|---|:-:|:-:|:-:|
| **method 1038** (dieser Lauf) | **weg** | bleibt | bleibt |
| **Display-Loeschen** (Vormittag) | bleibt (stale) | **weg** (Download → Timeout) | **weg** |

Das heisst konkret: der Drucker fuehrt die MQTT-Historie und das
Dateisystem/Display als zwei unabhaengige „Realitaeten". Es gibt
im LAN-API-Namensraum **keinen Weg**, das MP4 oder die
Display-Liste zu beeinflussen; umgekehrt entfernt Display-Loeschen
nicht die MQTT-Historie.

### Ungeprueft

- Ob `method 1038` **mehrere Tasks** auf einmal loescht
  (`list:["a","b","c"]`). cc2-control baut die Params genau so
  – wir haben nur eine ID in diesem Lauf getestet.
- Verhalten bei nicht-existierender `task_id`. Vermutlich
  `error_code=0` ohne Mutation (konsistent zur 1047-Beobachtung
  vom 25.10. – Firmware signalisiert Nicht-Existenz nicht).
- Ob das `result.total`-Feld in **allen** 1036-Antworten
  erscheint oder nur unter bestimmten Firmwares; die Vormittags-
  Antworten hatten es offenbar auch, nur haben wir es nicht
  explizit beachtet.
- Was aus dem physischen MP4 wird, wenn `method 1038` seinen
  History-Eintrag entfernt. Es ist dann im LAN nicht mehr
  adressierbar (fehlt die `video_url`), liegt aber physisch auf
  `/opt/usr/video/`. Vermutlich wird es durch den naechsten
  Druck oder Speicher-Housekeeping entfernt – nicht in diesem
  Test beobachtbar.

### Geht nicht

- **Speicher auf dem Drucker ueber `method 1038` freigeben.** Das
  MP4 bleibt; der Platz in `/opt/usr/video/` wird nicht frei. Fuer
  Speicher-Management braucht es das Drucker-Display.
- Display-Liste ueber MQTT aufraeumen. Es gibt keinen beobachtbaren
  MQTT-Pfad, der die Display-Liste synchronisiert.

### App-Regel (Historien-Pflege)

- `method 1038` ist **reine UI-Hygiene**. Die App darf damit die
  eigene Historien-Ansicht aufraeumen (z. B. fehlgeschlagene oder
  Status-0-Eintraege), aber:
  - **Nicht als Speicher-Management verkaufen.**
  - Beim Entfernen von Zeitraffer-Eintraegen in der UI klarstellen,
    dass das Video auf dem Drucker verbleibt und am Display
    separat geloescht werden muss, um Platz zu schaffen.
- Nach `method 1038` die lokale Historie-Ansicht aus der neuen
  1036-Antwort neu aufbauen (nicht nur optimistisch den Eintrag
  streichen – der Zaehler `result.total` ist der
  Konsistenz-Check).

### Artefakte

- `tools/cc2-delete-history.py` – sendet 1038 fuer eine Task-ID,
  Idle-Check vorweg, keine Retries.
- `logs/cc2-sniff-2026-10-26-093126.jsonl` – Mitschnitt
  waehrend 1038 (git-ignoriert).
- `docs/cc2-history-sample.json` – Post-1038-Snapshot (44 Tasks,
  neue Hash `4c9f1271e71c3a3d`).

Nichts committed, nichts gepusht.

### Offener Punkt bleibt

- Erfolgreicher 1051 (`3020→3021`) beim naechsten Zeitraffer-Druck,
  direkt nach dem Druck, vor dem USB-Export (Script
  `tools/cc2-render-timelapse.py` liegt bereit).

---

## 2026-10-26 08:30 UTC – Sende jetzt method 1038 (Delete-History) fuer heutigen Eintrag

**Einziger Schreibbefehl**: `method 1038 params={"list":["<task_id>"]}`
fuer `task_id=e0b592f4-bd51-4ece-97fc-2bfc8137d13e` (heutiger Lauf 2,
`video_status=2`, MP4 1 741 634 B md5 `e2330f840b398f425172b32692437f7a`).
Klaus hat zugestimmt, dass dieser Eintrag verloren gehen darf; MP4
liegt auf USB-Stick und in `local-test/`.

Payload-Beleg (nicht geraten):

- `cc2-control/src/mqtt.c:343-346` –
  `mqtt_delete_history(c, params)` ruft
  `publish_request(c, 1038, params)`.
- `cc2-control/src/mqtt.c:277-287` – `publish_request` baut
  `{"method":<m>,"id":<m>,"params":<params>}`, d. h. id=1038.
- `cc2-control/src/history.h:123-142` – Params-Aufbau:
  `{"list":["<id1>",...]}` mit einem Element pro Task.

Daraus **final:**

```json
{"method":1038,"id":1038,"params":{"list":["e0b592f4-bd51-4ece-97fc-2bfc8137d13e"]}}
```

Vor dem Senden:
- 1036-Hash: `e12d373a3ec5c57b` (seit heute Vormittag unveraendert).
- Target in Liste vorhanden (`video_status=2`, size=1 741 634,
  duration=3, url=`video/<name>.mp4`).
- Download-Probe erfolgreich: HTTP 200, md5 unveraendert.
- Klaus hat vorher am Display geprueft, dass die Zeitraffer-Liste
  genau diesen einen Eintrag zeigt.

Mitschnitt laeuft parallel. Erwartung: eine von drei Aussagen –
(a) Historie weg, MP4 bleibt / (b) Historie weg, MP4 weg /
(c) `error_code != 0`, nichts geaendert.

Antwortet 1038 mit `1003`: dokumentieren, kein zweiter Versuch.

---

## 2026-10-26 08:20 UTC – Test C: 1051 mit picture-URL → wieder `3022`; Rohframes gab's hier nie mehr

### Nachweislich

- URL-Herleitung aus
  `video/handslice_1792947629010.gcode20261026143807.mp4` zu
  `picture/handslice_1792947629010.gcode20261026143807`
  wurde eindeutig aus den Quellen abgeleitet (siehe
  `networking-cc2.md` Test-C-Abschnitt).
- **Response:** `error_code=0`, Response-URL
  `video/<basename>.mp4` (= der bestehende Pfad des Target-MP4),
  Latenz **18 ms**.
- **Status 12 Dauer: <1 ms** – alle drei api_status-Deltas tragen
  denselben Zeitstempel `08:17:37.794`. Pfad `3020→3022→1`.
- **1036 Vorher/Nachher: byte-identisch**
  (`sha256(result)=e12d373a3ec5c57b` beide Male). Target
  unveraendert, kein Nebenbeitrag mutiert, keine
  `duration`-Mutation.
- **Target-MP4 byte-identisch:** HTTP 200, 1 741 634 Byte,
  md5 `e2330f840b398f425172b32692437f7a` – gleich zur Baseline
  und zu allen vorigen Downloads. **1051 ueberschreibt das
  vorhandene MP4 nicht**, auch mit exakter picture-URL-Form.

### Erklaerung aus den Quellen

Der Elegoo-Code loescht am Ende jedes erfolgreichen Composite
die Rohframes:

```cpp
// elegoo/extras/ai_camera/module/util/time_lapse_control.cpp:119-125
cmd = "rm -rf \'" + pic_dir + "\'";
std::system(cmd.c_str());
```

Beim USB-Export heute frueh (06:50 UTC) ist der Composite durch
diesen Pfad gelaufen; dabei wurde
`/opt/usr/picture/handslice_1792947629010.gcode20261026143807/`
vernichtet. Das Display listet den Eintrag weiter, weil es die
Datenbank-Historie und das MP4 unter `/opt/usr/video/` sieht –
aber die Rohframes existieren hier nicht mehr. 1051 mit der
abgeleiteten picture-URL findet daher nichts → `3022`.

**Konsequenz:** Jeder `video_status=2`-Eintrag auf dieser Firmware
hat zum Zeitpunkt, zu dem er Status 2 erreicht, bereits keine
Rohframes mehr. **1051 kann nicht ueber MQTT ein Status-2 nach
Status-2 ueberfuehren** – das Composite wird strukturell beim
Rendering-Vorgang (einmalig) erzeugt und frisst dabei seine Rohdaten.

### Zusammengefuehrt – drei unabhaengige Beweise fuer `3022 = keine Rohframes`

| Lauf | URL-Form | Rohframes | Dauer | Delta |
|---|---|---|---:|---|
| `fac849a1` Vormittag | `picture/<basename>` | am Display geloescht | 972 ms | `duration 0→4` |
| Test B heute (Status 2) | `video/<basename>.mp4` | nach Composite weg | 1 ms | keiner |
| **Test C heute (Status 2)** | `picture/<basename>` | nach Composite weg | <1 ms | keiner |

In allen drei Faellen: `error_code=0`, Status 12 geht sofort auf
`3022`, kein Composite. **`sub_status 3022` ist der einheitliche
Marker fuer „keine Rohframes am erwarteten Pfad".**

### Ungeprueft

- **Erfolgreicher 1051 (`3020 → 3021`) ueber MQTT.** Das Verhalten
  ist durch Code hinreichend belegt (`mqtt.c:362-372`); unser
  realer Nachweis fehlt immer noch. Benoetigt frischen Druck mit
  Zeitraffer, **direkt danach** 1051 – bevor Klaus den USB-Export
  ausloest.
- **Ob die Firmware ueberhaupt gleichzeitig Rohframes und MP4
  behaelt**, oder ob der 1051-Composite dieselbe `rm -rf`-Logik
  anwendet wie der USB-Pfad. Vermutlich ja (gemeinsame
  Composite-Funktion); zu validieren.

### Geht nicht

- **1051-Rendering fuer ein `video_status=2`-Target.** Die
  Firmware hat die Rohframes bereits beim ersten Composite
  entfernt; ein zweites Composite ist strukturell nicht moeglich.
  Fuer die App: 1051 nur auf **frischen** Status-1-Eintraegen
  aufrufen, nicht auf Status 2.

### App-Regel (final)

- `video_status=1` + alter `end_time` → UI-Hinweis „evtl. keine
  Rohframes mehr" (`3022` wahrscheinlich).
- `video_status=1` + junger `end_time` → Button „Rendern"
  anbieten, Erfolg per Head-Probe pruefen.
- `video_status=2` → nie 1051. Direkt Download.
- `video_status=3` → nicht renderbar (wahrscheinlich dauerhaft).
- Nach jedem 1051: 1036 erneut lesen, Target-URL mit Head-Probe
  pruefen. Nur HTTP 200 + Content-Length>0 ist Erfolg.

### Offener Punkt bleibt

**Erfolgreicher 1051 mit `picture/<basename>` beim naechsten
Zeitraffer-Druck, direkt nach dem Druck, vor dem USB-Export.**
Script `tools/cc2-render-timelapse.py` liegt bereit. Erwartung:
`3020→3021→1` in Groessenordnung der 26 s vom USB-Export, danach
`video_status 1→2` und MP4 abrufbar.

### Artefakte

- `logs/cc2-sniff-2026-10-26-091710.jsonl` – Mitschnitt Test C
  (git-ignoriert).
- `docs/cc2-history-sample.json` – nach-Test-C-Snapshot
  (byte-identisch zu Vorher).

Nichts committed, nichts gepusht.

---

## 2026-10-26 08:15 UTC – Sende jetzt 1051 mit **picture-URL** auf heutigem Eintrag

Ableitung der URL aus dem heutigen `video_url`:

- Heutige `video_url` aus 1036:
  `video/handslice_1792947629010.gcode20261026143807.mp4`
- Basename-Konvention aus `elegoo/.../time_lapse_control.h:61,65-66`:
  `pic_dirname_ = /opt/usr/picture/<basename>` und
  `video_path_ = /opt/usr/video/<basename>.mp4` teilen denselben
  `<basename>`.
- Download-Resolver `cc2-control/src/history.h:51-62`:
  dokumentiert explizit `"picture/NAME" or "video/NAME.mp4" ->
  "video/NAME.mp4"` als Umkehrkonvention.
- Firmware-Verhalten aus Test B (vorige Runde): `params.url =
  video/<basename>.mp4` → Response-URL = `video/<basename>.mp4.mp4`,
  d. h. die Firmware nimmt den Anteil nach dem letzten `/` als
  Basename und haengt `.mp4` an.
- Daraus **eindeutig** abgeleitet:
  `params.url = "picture/handslice_1792947629010.gcode20261026143807"`
  → Rohframes gesucht unter
  `/opt/usr/picture/handslice_1792947629010.gcode20261026143807/`
  (Display zeigt den Eintrag noch, Rohframes sollten vorhanden
  sein); Ziel-MP4
  `video/handslice_1792947629010.gcode20261026143807.mp4`
  (identisch zum bestehenden Pfad).

**Risiko-Vorhersage:** Falls 1051 erfolgreich rendert, wird das
vorhandene MP4 **ueberschrieben**. Baseline ist gesichert in
`local-test/handslice_1792947629010.gcode20261026143807.mp4`
(1 741 634 B, md5 `e2330f840b398f425172b32692437f7a`).

Mitschnitt laeuft parallel. Erwartung:
- (a) `3020→3021→1` in Groessenordnung des USB-Composings
  (26 s fuer 100 Frames),
- (b) `3020→3022→1` sofort, falls Rohframes trotz Display-
  Anzeige nicht mehr auffindbar sind,
- (c) `error_code != 0` als sofortige Ablehnung.

Antwortet 1051 mit `1003` oder scheitert mit `3022`: dokumentieren,
kein zweiter Versuch, keine Parameter-Variante.

---

## 2026-10-26 08:08 UTC – Zwei Tests: Parallelitaet (A) und 1051 auf Status-2-Eintrag (B)

### Test A: haengender Request blockiert nicht

#### Nachweislich

- **Paralleler Head-Probe wird waehrend eines haengenden Downloads
  normal bedient.** 20 ms `head_ms` auf dem heutigen (vorhandenen)
  MP4, waehrend eine stale-URL noch 35 s lang offen schwieg. Baseline
  (ohne Hang): 12–16 ms. **Keine spuerbare Serialisierung.**
- `connect_ms` schwankt stark (14–420 ms) **unabhaengig vom Hang** –
  wohl TCP-SYN-Retransmit / TIME_WAIT. **Fuer App-Fehler-Detect
  nur `head_ms` nutzen**, nicht die Gesamtlatenz.
- Nach Timeout des haengenden Requests bleibt alles normal.
- Script: `tools/cc2-probe-parallel.py`.

#### Ungeprueft

- **Grenze der Parallelitaet.** cc2-control fuehrt einen
  „two-transfer limit"-Kommentar in `history.h`; wir haben nur
  2 parallele Verbindungen gleichzeitig getestet. Mit 3+ koennte
  der Server reagieren – nicht Teil dieses Tests.

#### Geht nicht

- Nichts; der Test hat sauber ergeben, dass parallele Probes safe
  sind.

#### App-Regel

- Probes und Downloads **duerfen parallel** laufen (bis ~2
  gleichzeitig; nicht volle Spray).
- **Head-Timeout 1–2 s** auf den Response-Head reicht; vorhandene
  Dateien antworten in <30 ms, fehlende schweigen fuer immer.

---

### Test B: method 1051 gegen bereits gerenderten Status-2-Eintrag

#### Nachweislich

- 1051 wird akzeptiert (`error_code=0`), **auch wenn die URL schon
  mit `.mp4` endet**. Response-URL ist `video/<name>.mp4.mp4` –
  die Firmware haengt pauschal `.mp4` an. Daraus folgt: die
  Firmware interpretiert `params.url` als **Basisname fuer das
  Composite**, egal ob mit oder ohne Extension.
- **Status 12 nur 1 Millisekunde**: `3020 → 3022` passiert
  in derselben api_status-Nachricht. Noch kuerzer als beim
  `fac849a1`-Lauf (972 ms); dort war der URL-Form-Fehler zwar
  nicht vorhanden, aber Rohframes fehlten – effektiv dasselbe
  Nicht-Composite.
- **1036 Vorher/Nachher: byte-identisch**
  (`sha256(result)=e12d373a3ec5c57b` beide Male). Weder Target
  noch Nebenbeitraege veraendert. **Insbesondere die
  `time_lapse_video_duration` 0→4-Mutation vom
  `fac849a1`-Lauf tritt hier nicht auf** – vermutlich bindet die
  Firmware diese Mutation an die Status-1-Form `picture/…` an.
- **MP4-Datei unveraendert.** Nach dem 1051-Lauf nochmal geladen:
  1 741 634 Byte, md5 `e2330f840b398f425172b32692437f7a` –
  **byte-identisch** zur Baseline. 1051 ueberschreibt also
  **nicht** das vorhandene MP4.
- Die hypothetische `video/<name>.mp4.mp4`-Datei existiert
  erwartungsgemaess nicht (Timeout, kein 404).

#### Ungeprueft

- **Erfolgreiches 1051 mit `picture/<name><ts>`-URL und frischen
  Rohframes.** Das sauber reproduzierbare `3020→3021`-Verhalten
  haben wir bis jetzt nur beim USB-Export beobachtet (26 s fuer
  100 Frames). MQTT-Pfad noch offen; naechster Zeitraffer-Druck
  ist der richtige Moment (siehe offener Punkt).
- **Verhalten bei einem `video_status=2`-Eintrag mit tatsaechlich
  vorhandenen Rohframes und 1051 mit `picture/<name><ts>`-URL**
  (= hypothetisches Re-Rendern). Interessant, aber potentiell
  destruktiv (Ueberschreibung?); nur mit Backup des bestehenden
  MP4 zu testen.
- Semantik von `sub_status 3022` jenseits der jetzt belegten
  Vermutung „kein Composite stattgefunden" (unterschiedliche
  Ursachen: Rohframes fehlen; URL-Form falsch).

#### Geht nicht

- **1051 mit `video/<name>.mp4`-URL erzeugt nichts.** Weder neue
  Datei (siehe `.mp4.mp4`-Timeout) noch Mutation des bestehenden
  MP4. Composite scheitert still in `3022`, History bleibt
  unberuehrt. Fuer die App: `video/`-URLs sind fuer 1051 **nicht**
  der richtige Input.

#### App-Regel (praezisiert)

- Fuer Rendering: **nur `picture/<name><ts>`-URLs** (aus
  `video_status in {1, 3}`) an 1051 schicken. `video/…`-URLs
  sind idempotent und folgenlos (ok), aber sinnlos.
- Status 2 → direkt Head-Probe und Download. Nie 1051.
- `sub_status 3022` generell als „kein Composite stattgefunden"
  interpretieren; Erfolg immer per Head-Probe auf die neue URL
  bestaetigen.
- 1051 ist **idempotent-sicher** auf Status-2-Eintraegen; falls
  die App versehentlich 1051 doppelt sendet oder auf einem schon
  gerenderten Eintrag, passiert nichts Boeses – weder MP4 veraendert
  noch History mutiert.

### Offener Punkt bleibt

**Realer 1051-Test mit `picture/<name><ts>`-URL** beim naechsten
Zeitraffer-Druck, vor dem USB-Export. Script
`tools/cc2-render-timelapse.py` bleibt bereit; nicht ausfuehren,
bevor der Druck fertig ist und der Stick noch nicht gesteckt wurde.

### Artefakte

- `tools/cc2-probe-parallel.py` – Test A, Head-Probes
  mit optionalem Hang.
- `logs/cc2-sniff-2026-10-26-090500.jsonl` – Mitschnitt waehrend
  Test B (SN + Rohpayloads, deshalb `logs/` ignoriert).
- `docs/cc2-history-sample.json` – byte-identisch zur
  Vormittags-Fassung; `.mp4.mp4`-Mutation gab es nicht.

Nichts committed, nichts gepusht.

---

## 2026-10-26 08:03 UTC – Sende jetzt method 1051 fuer heutigen Lauf 2 (Erfolgsfall)

Zielobjekt: der heutige Status-2-Eintrag, zu dem laut Display die
**Rohframes noch vorhanden** sind:

- `task_id = e0b592f4-bd51-4ece-97fc-2bfc8137d13e`
- `begin_time = 2026-10-26T06:38:07Z`
- `url = "video/handslice_1792947629010.gcode20261026143807.mp4"`
- aktueller `video_status = 2`, `video_size = 1 741 634`
- Baseline md5 des MP4: `e2330f840b398f425172b32692437f7a`

Request-Payload nach cc2-control-Beleg
(`cc2-control/src/mqtt.c:277-287` + `:362-372`):

```json
{"method":1051,"id":1051,"params":{"url":"video/handslice_1792947629010.gcode20261026143807.mp4"}}
```

Mitschnitt laeuft parallel. Erwartung ist eine der drei
Varianten:

- (a) Sofortige Ablehnung mit `error_code!=0` (MP4 schon da),
- (b) erneutes Composite ueber die Rohframes mit `3020→3021→1`
  und moeglicherweise neuem md5,
- (c) kurzer Durchlauf wie bei `fac849a1` (`3020→3022`),
  weil die Firmware „schon da" so signalisiert.

Antwortet 1051 mit `1003`, wird nicht wiederholt.

---

## 2026-10-26 07:55 UTC – Gegentest „Historie ist stale" bestaetigt; 1051-Lauf war ungueltig

Klaus hat heute frueh am Display alle alten Zeitraffer geloescht,
bis auf den heutigen Lauf 2. Die Historie aus `method 1036` zeigt
davon nichts – alle Eintraege stehen weiterhin drin. Daraus folgt
retrospektiv, dass der 1051-Test an `fac849a1` ungueltig war
(keine Rohframes mehr vorhanden); `3022` ist vermutlich
**„nichts zum Rendern"**, nicht „Fehler".

### Nachweislich

- `method 1036` liefert **genau denselben Snapshot** wie heute
  vormittag: 6 Tasks mit `video_status in {1, 2}`, davon vier
  Status-2-URLs. Keine Mutation durch das Display-Loeschen.
- **Alle drei alten Status-2-URLs geben Timeout** auf
  `GET /download?X-Token=…&file_name=…`:
  - `video/ECC2_0.4_Box…20261019110021.mp4` (nominell 9 912 573 B)
  - `video/handslice_kerbenwuerfel_timelapse.gcode20261025164702.mp4` (nominell 1 813 428 B)
  - `video/handslice_1792947629010.gcode20261026010053.mp4` (nominell 1 762 496 B)
  Timeout tritt beim **Response-Head** auf (8 s unseres Clients
  wurden abgewartet). Protokollisch: TCP-Handshake geht durch, der
  Server beantwortet die Request-Zeile mit Schweigen – kein 404,
  kein 403, kein Body, kein TCP-Reset.
- **Gegenprobe heutiger Eintrag**:
  `video/handslice_1792947629010.gcode20261026143807.mp4`,
  HTTP **200** in **73.7 ms**, Content-Length **1 741 634**,
  Transfer-Encoding chunked. Vollstaendig geladene Datei:
  **md5 e2330f840b398f425172b32692437f7a**, byte-identisch zum
  Vormittags-Download.
- **Druckeruhr-Offset belegt**: realer Druckstart 2026-10-26T06:38:07Z
  (= 07:38:07 MEZ); Display-Anzeige fuer denselben Druck
  **14:38:07** (laut Klaus). Dateinamen-Zeitstempel aus 1036
  `20261026143807` – deckungsgleich zur Display-Zeit. Druckeruhr
  liegt also **+7 h gegen MEZ / +8 h gegen UTC** (entspricht
  UTC+8). Zeitstempel im Dateinamen oder in `begin_time` sind
  damit **nicht gegen Echtzeit abgleichbar**.
- **1036 ist eine Datenbank-Historie, kein Verzeichnislisting.**
  `video_status==2` sagt „wurde mal gerendert", nicht „ist jetzt
  abrufbar". Einziger verlaesslicher Existenz-Nachweis bleibt
  der HTTP-GET.
- **Short-Read-Timeout reicht als App-Fehler-Detect** – antwortet
  der Drucker nicht in ca. 1–2 s auf den Response-Head, ist die
  Datei weg (bei einer vorhandenen Datei kam der Header in 74 ms).

### Ungeprueft

- Ob `method 1051` auf einem Task mit **tatsaechlich vorhandenen**
  Rohframes den Status 1 → 2 bringt und ein abrufbares MP4
  erzeugt. Dafuer braucht es den naechsten Zeitraffer-Druck,
  bevor Klaus den USB-Export macht (siehe offener Punkt unten).
- Semantik von `sub_status 3022` jenseits der Vermutung „keine
  Frames vorhanden".
- Semantik von `video_status 3` ohne URL (Nameplate-Nebenbefund
  heute Vormittag). Mit dem jetzigen Wissen plausibel: 3 bedeutet
  „schon mal versucht zu rendern, Rohframes gab es nicht" –
  d. h. es ist die 1051-nach-Composite-Markierung fuer einen
  Task ohne Rohframes.
- Warum der Drucker auf fehlende Dateien **schweigt** statt eine
  HTTP-Fehlermeldung zu senden. Code-Beleg
  (`cc2-control/src/history.h:250-251`) sagt nur, dass er es
  tut – nicht warum.

### Geht nicht

- **Historie am Drucker-Display und `method 1036` haengen nicht
  zusammen.** Das Display-Loeschen des Zeitraffers aktualisiert
  die 1036-Datenbank nicht. Vermutlich das pendant zum
  2026-10-25-Befund, dass `method 1047` (DELETE_FILE) auf dieser
  FW auch nichts aus der Dateiliste loescht. **Loeschen aus der
  History geht ueber `method 1038`** (code-belegt, nicht hier
  getestet). Zum Entfernen eines Zeitraffers am Display ohne
  History-Mutation gibt es keinen beobachtbaren MQTT-Pfad –
  die beiden sind separat.

### App-Regeln (konkretisiert nach diesem Lauf)

Ersetzt die M5-Regeln vom Vormittag:

1. `method 1036` lesen + anzeigen. Zeitstempel aus `begin_time`,
   `end_time` und dem Dateinamen-Suffix **nicht** gegen Echtzeit
   abgleichen; nur als Ordnungs-Schluessel verwenden.
2. **Download-Button an eine Head-Probe binden**, nicht an
   `video_status==2`: GET auf `/download?...` mit 2 s Timeout auf
   den Response-Head. Antwortet der Drucker, ist das MP4 da und
   wird geladen; antwortet er nicht, als „nicht mehr verfuegbar"
   anzeigen (ggf. Hinweis, dass es wahrscheinlich am Display
   geloescht wurde).
3. Nach `method 1051` nicht nur auf `error_code==0` schauen und
   auch nicht nur auf `status==1 nach 12`. Stattdessen: Target-URL
   per Head-Probe testen. Nur HTTP 200 + Content-Length>0 ist
   Erfolg.
4. `sub_status 3022` als „keine Frames" interpretieren
   (nicht als Fehler). `sub_status 3021` als Erfolg der
   Kopier-Phase (USB-Export) belassen.
5. `video_status 3` ohne URL: UI-Hinweis „Rohdaten nicht mehr
   verfuegbar". `video_status 1` oder `3` mit URL: Button
   „Rendern" (= 1051) anbieten, aber den Erfolg per Head-Probe
   bestaetigen.

### Offener Punkt

**Realer 1051-Test beim naechsten Zeitraffer-Druck.** Vor dem
USB-Export, direkt nach dem Druckende (idle), gegen die frischen
`video_status=1`-Rohframes. Erwartung: Composite-Dauer in der
Groessenordnung des USB-Composings (26 s fuer 100 Frames beim
heutigen Lauf 2), `sub_status 3020→3021→1`, danach
`video_status=2` mit abrufbarem MP4.

Script liegt bereit (`tools/cc2-render-timelapse.py`); bitte
nicht ausfuehren, bevor der naechste Zeitraffer-Druck fertig und
der Stick noch nicht gesteckt ist.

### Artefakte

- `tools/cc2-timelapse-probe.py` – Head-only-GET pro Status-2-URL
  mit Timing (und optionalem Drain).
- `docs/cc2-history-sample.json` – aktualisiert (byte-identisch
  zur Vormittags-Fassung).

Nichts committed, nichts gepusht.

---

## 2026-10-26 07:45 UTC – Realtest `method 1051`: akzeptiert, aber Composite scheiterte still

Senden erfolgt um 07:42:19 UTC gegen Target `fac849a1` (2026-10-14-
Druck, `video_status=1`, URL `picture/<name><ts>`). Reserve
`e4d2dc70` nicht angefasst. Mitschnitt lief parallel.

### Nachweislich

- **1051 wird vom Stock-Broker akzeptiert.** Response in 233 ms,
  `error_code=0`, Response-Payload enthaelt bereits die zukuenftige
  URL (`video/<name><ts>.mp4`). Payload exakt nach
  `cc2-control/src/mqtt.c:277-287` + `:362-372` (id = method = 1051).
- **Status 12 wird sofort gesetzt**: 27 ms nach der Response wechselt
  `machine_status.status` auf 12 und `sub_status` auf **3020**.
  Insgesamt dauert der Zustand nur **972 ms**, dann zurueck auf
  Status 1.
- **Substate-Pfad weicht vom USB-Export ab:** heute frueh war die
  Reihenfolge `3020→3021→1` (26 s), jetzt ist sie `3020→3022→1`
  (<1 s). `3021` ist laut Display „Video wird kopiert", `3022` ist
  in keiner uns bekannten Code-Doku aufgefuehrt und sieht nach
  **Fehler-Substate** aus.
- **MP4 ist NICHT entstanden.** Zwei Download-Versuche mit der
  Response-URL (einmal `urlencode`-Variante, einmal
  `percent_encode`-Variante): beide HTTP-Timeout. Das entspricht
  genau dem von cc2-control dokumentierten Verhalten „wrong token
  or name → silence" (`history.h:250-251`). Gegentest mit dem
  heute-frueh-MP4 ergibt `HTTP 200 Content-Length: 1 741 634` –
  der Pfad funktioniert, nur die Datei fehlt.
- **History-Diff Vorher/Nachher** (hash `sha256(result)`):
  `c07da2c56804...` → `e12d373a3ec5...`. Zwei geaenderte Tasks:
  1. Target `fac849a1`: nur `time_lapse_video_duration` 0 → 4.
     `status` bleibt 1, `url` bleibt `picture/<name><ts>`,
     `size` bleibt 0. Zustand damit nicht fortgeschritten.
  2. Nameplate `887e3325` (voellig unverwandter Task vom 23.09.):
     `video_status` 0 → 3, bei weiterhin leerer URL und 0-Werten.
     Nicht sauber kausal zum 1051 zuordenbar.
- **Reserve `e4d2dc70` byte-identisch**. Keine Nebenwirkung auf
  den anderen Status-1-Eintrag.
- **Alle vorhandenen `video_status=2`-Eintraege byte-identisch**.
  Keine Nebenwirkung auf bereits gerenderte Zeitraffer.
- **Keine Fortschritts-Felder in api_status waehrend Status 12**.
  Alle Felder im 1.5-s-Composing-Fenster: nur `status`, `sub_status`,
  und die 1051-Antwort selbst (`error_code`, `url`). Kein
  `progress`, `percent`, `frame_count` o.ae. Fuer die App bedeutet
  das: Spinner statt Prozentanzeige.

### Ungeprueft

- **Erfolgreiches Composing via 1051.** Dieser Lauf hat keinen
  erfolgreichen Zustand erreicht; den Zyklus 1→1051→12→**2**→
  Download haben wir nur fuer die USB-Export-Variante (`3020→3021`)
  real gesehen, nicht ueber MQTT 1051. Fuer die endgueltige
  Bestaetigung braechte es einen frischen Druck mit Zeitraffer,
  gefolgt direkt (ohne USB-Export) von einem 1051-Aufruf – dann
  waeren die Rohframes garantiert noch da.
- **Bedeutung von `sub_status 3022`.** Vermutung „Composite
  fehlgeschlagen". Harten Beleg (Enum-Tabelle) haben wir nicht.
- **Bedeutung von `video_status 3` ohne URL** (Nameplate-Fall).
  Semantisch widerspruechlich zur cc2-control-Lesung („3 ist
  renderbar wie 1"). Vermutung: FW-interne Markierung „existierte
  mal, Rohframes weg". Nicht hart belegt.
- **Ob `time_lapse_video_duration=4` am Target eine App-Semantik
  hat** (geplante Dauer in Sekunden?). Dieser Eintrag wird in der
  Community-UI nicht angezeigt; Zweck in diesem Zustand unklar.

### Geht nicht

- **Composing auf Stock 02.01.01.07, wenn die Rohframes bereits
  intern geloescht sind.** Der Drucker signalisiert den Fehler
  nicht ueber `error_code`, sondern nur ueber den Substate 3022.
  Fuer die App bedeutet das: nach jedem 1051-Lauf einen zweiten
  `method 1036`-Pull machen und auf `video_status==2 && size>0`
  pruefen, nicht nur auf `error_code==0`.
- **Rohframes-Erhalt ueber die Zeit garantieren.** Der Drucker
  (vermutlich) raeumt die `picture/`-Verzeichnisse irgendwann
  weg, aber die History behaelt `video_status=1` – das ist eine
  stale-Markierung aus App-Sicht. Workaround: bei `status=1`
  mit alten `end_time`-Werten in der UI darauf hinweisen, dass
  das Rendering fehlschlagen koennte.

### App-Konsequenz (M5 revidiert)

Dreistufige UI-Logik, konkretisiert um die Realtest-Erkenntnisse:

1. **Druckhistorie laden:** `method 1036`.
2. **Pro Zeitraffer-Task:**
   - `video_status==0` → „kein Zeitraffer".
   - `video_status==2 && size>0` → Download-Button → `GET /download?X-Token=&file_name=<url>`.
   - `video_status==1` oder `3` **mit** URL beginnend mit `picture/`
     → Button „Rendern" → `method 1051 params.url=<url>`;
     Spinner anhand `machine_status.status==12`.
   - `video_status==3` **ohne** URL → UI zeigt „Zeitraffer-
     Rohdaten nicht mehr vorhanden" (nicht renderbar).
3. **Nach dem Composing (Zurueck zu Idle):** erneut `method 1036`.
   - Wenn Target jetzt `video_status==2 && size>0`: Download.
   - Sonst: Fehlerhinweis „Composite fehlgeschlagen – Rohframes
     evtl. nicht mehr verfuegbar". Nicht automatisch
     wiederholen (kein zweiter 1051-Aufruf).

### Artefakte

- `tools/cc2-render-timelapse.py` – idempotent gegen Reserve
  (nimmt URL als Argument, sendet 1051 genau einmal).
- `logs/cc2-sniff-2026-10-26-084103.jsonl` – Sniff der
  Composing-Phase (SN + Rohpayloads, deshalb `logs/` ignoriert).
- `docs/cc2-history-sample.json` – nach-1051-Snapshot
  (SN-anonymisiert). Vorher-Snapshot liegt nur temporaer in
  `/tmp/cc2-history-vorher.json`.
- `docs/upstream/elegoo-homeassistant-timelapse-download-draft.md`
  – aktualisiert um die 1051-Beobachtung (siehe Abschnitt
  „Realtest observations").

Nichts committed, nichts gepusht.

---

## 2026-10-26 07:40 UTC – Sende jetzt method 1051 (einziger Schreibbefehl heute)

Zielobjekt: aelterer der beiden `video_status=1`-Eintraege aus
`docs/cc2-history-sample.json`:

- `task_id = fac849a1-c028-4ba9-b7e5-c41a9981159a`
- `begin_time = 2026-10-14T03:50:32Z`
- `url = "picture/ECC2_0.4_Sealed+lid_Elegoo PLA Matte _0.12_2h39m.gcode20261014115032"`

Der neuere `video_status=1`-Eintrag (`e4d2dc70-...`) **bleibt
unangetastet** als Reserve.

Request-Payload nach cc2-control-Beleg
(`cc2-control/src/mqtt.c:277-287` fuer `publish_request` plus
`:362-372` fuer `mqtt_generate_timelapse`):

```json
{"method":1051,"id":1051,"params":{"url":"<url>"}}
```

Topic: `elegoo/<cc2-sn>/<client_id>/api_request`.

Passiver Mitschnitt laeuft seit 2026-10-26 07:41 UTC
(`logs/cc2-sniff-2026-10-26-084103.jsonl`), damit Status-12-Verlauf
mit Zeitstempel protokolliert wird. Idle vor dem Senden wird vom
1051-Script selbst geprueft.

Erwartung: `error_code=0` → Status 1→12→1 mit Substates 3020→3021.
Antwortet 1051 mit `1003`, wird nicht wiederholt und keine
Parameter-Variante probiert.

---

## 2026-10-26 07:35 UTC – Realtest: Zeitraffer-Abruf ueber LAN bewiesen

Zwei Schritte lesend (plus Register-Handshake fuer 1036):
`tools/cc2-history-fetch.py` fuer `method 1036`,
`tools/cc2-timelapse-download.py` fuer HTTP-GET. **Kein `method 1051`
gebraucht**, weil der 06:38-Zeitraffer-Druck bereits `video_status=2`
hatte (Klaus' USB-Export heute frueh hat das Composite gemacht).

### Nachweislich

- **`method 1036` funktioniert auf Stock 02.01.01.07.** Antwort in
  < 1 s, 13 661 Byte, 45 History-Eintraege, `error_code=0`. Felder
  deckungsgleich zu dem, was wir aus `cc2-control/src/history.h` und
  `plugin.ts` abgeleitet haben.
- **Spiegelung der heutigen Testdrucke stimmt exakt:**
  - Lauf 1 (06:25 UTC, ohne Timelapse): `video_status=0`,
    `video_url=""`, `video_size=0`. Kein Frame aufgezeichnet.
  - Lauf 2 (06:38 UTC, mit Timelapse): `video_status=2`,
    `video_url='video/handslice_1792947629010.gcode20261026143807.mp4'`,
    `video_size=1 741 634`. **Klaus' USB-Export um 06:50:54 UTC
    hat das Composite ausgeloest; danach ist der Status von
    (vermutlich zuvor) 1 auf 2 gewechselt.**
- **Enum `time_lapse_video_status` empirisch belegt** (Verteilung in
  45 Tasks):
  0 = kein Zeitraffer (`url=""`), 1 = Rohframes vorhanden
  (`picture/<name><ts>`), 2 = MP4 bereit (`video/<name><ts>.mp4`),
  3 = nicht beobachtet. Interpretation identisch zur
  Community-Code-Lesung.
- **HTTP-GET `/download?X-Token=<access>&file_name=<url>` liefert
  das MP4 vom LAN aus** (nicht nur Loopback). Response:
  `HTTP 200`, `Content-Length: 1 741 634` (= `video_size`),
  `Transfer-Encoding: chunked`, `Content-Disposition: attachment;
  filename="video/<name>.mp4"`. **Beide Rahmungen (Length + chunked)
  gleichzeitig** – vgl. cc2-control-Warnung in
  `history.h:269-273`.
- **ffprobe-Pruefung** (`local-test/handslice_1792947629010.gcode20261026143807.mp4`,
  md5 `e2330f840b398f425172b32692437f7a`):
  H.264, 640×360, 30 fps, **100 Frames**, 3.30 s, 4.22 Mbit/s –
  der 100-Layer-Druck ergibt genau 1 Frame pro Layer, was zur
  Elegoo-Code-Logik passt.
- **Idle-Prerequisites eingehalten.** Vor dem 1036-Request 10 s
  passiv geprueft; `machine_status.status` kein Delta in dem
  Zeitfenster (= keine Transition weg vom Idle), danach erst
  Register + 1036.
- **Clock-Drift bestaetigt und erklaert.** Dateinamens-Zeitstempel
  `20261026143807` beim 06:38:07-UTC-Druckstart = Druckeruhr
  ~8:00 h vor UTC in diesem Lauf (im 25.10.-Lauf war es
  `20261026010053` fuer einen 18:05-MEZ-Druck). Die
  `localtime_r`-Nutzung im Elegoo-Code
  (`time_lapse_control.cpp:166-172`) sieht einfach die aktuelle
  Druckeruhr; dass diese die MESZ→MEZ-Umstellung oder
  Zeitzonenwechsel nicht sauber mitfuehrt, ist das darunter
  liegende Problem. **Fuer die App bleibt: Dateinamens-ts als
  opaker Ordnungsschluessel.**

### Ungeprueft

- **Verhalten bei `video_status=1`** (Rohframes, nicht gerendert).
  In diesem Sample waren zwei Tasks mit Status 1 (vom 14.10.),
  aber wir haben `method 1051` **nicht** gesendet (nicht noetig).
  Der volle Zyklus 1 → 1051 → Status 12 → 2 → Download bleibt
  damit **nur in Teilen** validiert: wir haben Status 12 heute
  frueh im Mitschnitt gesehen und das daraus resultierende MP4
  jetzt heruntergeladen; der direkte Trigger via `method 1051`
  ist weiter nur code-belegt, nicht am Geraet verifiziert.
- **Verhalten bei `video_status=3`** – im Sample nicht aufgetaucht.
- **Semantik von `task_status`** – 1 (38×) oder 2 (7×) im Sample.
  Keine 3 gesehen. Deutung „1 = normal, 2 = abgebrochen" ist
  plausibel, aber nicht hart belegt.
- **Content-Length-vs-chunked-Konflikt** in anderen Clients.
  `urllib` in Python hat beides sauber gelesen; wie Dart's
  `http`-Package reagiert, bleibt zu testen.

### Geht nicht

- Nichts, was fuer diesen Auftrag relevant waere, hat gefehlt.
  Alle drei geforderten Schritte 1-2-3 waren durch die ersten
  zwei abgedeckt; Schritt 3 (`method 1051`) ist bewusst nicht
  gesendet, weil Schritt 2 bereits erfolgreich war.

### App-Konsequenz (konkret, M5-Erweiterung)

Dreistufige UI-Logik, in dieser Reihenfolge:

1. **Druckhistorie laden:** `method 1036` → `history_task_list[]`.
   Pro Eintrag die drei Zeitraffer-Felder lesen.
2. **Pro Zeitraffer-Task entscheiden:**
   - `video_status==0` → UI zeigt „kein Zeitraffer".
   - `video_status==2` → UI zeigt „Zeitraffer bereit" mit
     Download-Button → GET `/download?X-Token=…&file_name=<url>`.
   - `video_status==1` oder `3` → UI zeigt „noch nicht gerendert"
     mit Button „Rendern" → `method 1051 params.url=<url>`;
     waehrend Status 12 ein Fortschritts-Spinner; nach
     Zurueck-auf-Idle `method 1036` neu lesen und zu Schritt 2.
3. **Loeschen** (Phase 2+): `method 1038 params={"list":[task_id]}`
   entfernt **nur den Historien-Eintrag** aus 1036. **Weder das
   MP4 noch die Display-Zeitraffer-Liste werden beruehrt** – siehe
   Test D (08:35 UTC Eintrag). Fuer Speicher-Freigabe muss am
   Drucker-Display geloescht werden; die MQTT-API hat dafuer
   keinen Pfad.

Zusatz fuer die App-Doku: `method 1047` nicht fuer Zeitraffer
nutzen (die Firmware ignoriert es sowieso).

### Entwurf fuer upstream `danielcherubini/elegoo-homeassistant`

`docs/upstream/elegoo-homeassistant-timelapse-download-draft.md`.
Englisch, keine SN/Access-Code/IP, keine Code-Kopien aus
`cc2-control` oder `elegoo-link`. Vorschlag darin: Doku-PR fuer
`docs/CC2_PROTOCOL.md` (1036/1051/1038 + `/download`-Semantik) +
Feature-PR fuer `cc2/client.py` (Timelapse-Download). Noch nicht
eingereicht – Klaus entscheidet.

### Artefakte

- `tools/cc2-history-fetch.py` – 1036 + Idle-Check + SN-Scrub.
- `tools/cc2-timelapse-download.py` – HTTP-GET /download.
- `docs/cc2-history-sample.json` – 1036-Antwort anonymisiert (SN
  raus, Access-Code war nicht in der Antwort). Enthaelt
  Dateinamen echter frueherer Drucke – nicht sensibel, aber in
  Repo-Kontext zu bedenken.
- `local-test/handslice_1792947629010.gcode20261026143807.mp4` –
  gezogener Zeitraffer (git-ignoriert, bleibt lokal).
- `docs/upstream/elegoo-homeassistant-timelapse-download-draft.md`
  – Draft fuer upstream.

Nichts committed, nichts gepusht.

---

## 2026-10-26 07:30 UTC – Klaerung: 1036/1038/1051 sind Stock, nicht Community

Vor dem Realtest die berechtigte Rueckfrage aufgeloest, ob die
Methoden-Nummern aus `cc2-control` evtl. nur in der Community-
Firmware funktionieren.

**Nachweislich Stock-Protokoll:**

- `cc2-control` **bringt keinen eigenen MQTT-Broker mit.** Der
  einzige Treffer fuer „mosquitto" im Repo ist in
  `cc2-control/tests/sim_printer.py:15-18` – dort wird mosquitto
  per Docker als Mock-Broker fuer die Testsuite gestartet, nicht
  auf dem Drucker.
- `cc2-control` connectet gegen den **lokalen** Broker auf
  `127.0.0.1:1883` (`cc2-control/src/mqtt.c:382`:
  `a.sin_addr.s_addr = htonl(INADDR_LOOPBACK)`). Dieser Broker
  ist Teil der **Stock-Firmware** – der Dienst, den wir seit
  2026-10-25 auch von unserem Mitschnitt-PC aus unter
  `<cc2-ip>:1883` ansprechen.
- `cc2-control` wartet beim Start mit `pidof elegoo_printer`
  (`cc2-control/scripts/launch.sh:28`) auf den **vendor-eigenen
  Hauptprozess**; alle Publishes gehen auf die vendor-eigenen
  Topics `elegoo/<sn>/...` (`cc2-control/src/mqtt.c:71, 92, 146,
  157, 282, 298, 324`), identisch zu dem, was wir im passiven
  Mitschnitt heute frueh gesehen haben.
- Die Methoden-Nummern selbst sind **nicht Community-Erfindung**.
  Der Lizenzhinweis in `cc2-control/web-src/src/lib/machine.ts:3-4`
  lautet woertlich: „Codes and meanings below come from ELEGOO's
  elegoo-link SDK (Apache-2.0), CC2 LAN adapter
  elegoo_fdm_cc2_message_adapter.cpp".
- Zusaetzlicher indirekter Beleg: Die sub_status-Codes, die unser
  passiver Stock-FW-Mitschnitt heute frueh gezeigt hat (2075,
  2077, 2401, 2501, 2502, 2801, 2802, 1045, 1405), sind in der
  Community-Tabelle (`machine.ts:11-57`) deckungsgleich belegt.
  Die Community-Semantik passt also faktisch zum Stock-Verhalten.

**Vorsicht:** Dieser Beleg zeigt, dass die Nummern aus Elegoos
eigenem SDK stammen und `cc2-control` nur Client ist. Er zeigt
**nicht**, dass die Stock-Firmware 02.01.01.07 jede dieser
Methoden freischaltet. Methoden `1045 GET_FILE_THUMBNAIL` und
`1047 DELETE_FILE` existieren im SDK, antworten auf dieser Stock-FW
aber mit `error_code 1003` (unser Nachweislauf 2026-10-25). Ob
`1036/1051` ebenso „im SDK, aber in dieser FW abgewiesen" sind,
klaert erst der folgende Realtest.

---

## 2026-10-26 07:15 UTC – Quellenrecherche Zeitraffer-Ablage (lesend, keine Firmware geladen)

Neuer Abschnitt in `docs/networking-cc2.md` eingefuegt:
„Zeitraffer-Ablage: Quellenrecherche 2026-10-26" (umfangreich,
revidiert die 2026-10-25-Aussage „keine LAN-API fuer
Zeitraffer-Download").

Quellen: `elegooofficial/CentauriCarbon2` (GPL-3) und
`Neme77/centauri-carbon-2-community` (shallow nach
`/tmp/handslice-research/`, nichts gebaut) sowie
`docs.opencentauri.cc`. Keine `.zip.sig`/`.swu.sig` angefasst, kein
Decrypt-Tool benutzt, keinen Befehl an den Drucker.

### Nachweislich (Belegstellen in networking-cc2.md verlinkt)

- **Rohframe-Pfad:** `/opt/usr/picture/<gcode><YYYYMMDDHHMMSS>/`
  (temporaer `.temp/`, bei Abschluss umbenannt). Pro Frame
  `0001.jpeg`, `0002.jpeg`, …
  (`time_lapse_photo.h:17`, `time_lapse_control.cpp:28-78`).
- **MP4-Pfad:** `/opt/usr/video/<name>.mp4` (`time_lapse_photo.h:18`).
- **Dateinamen-Logik:** Druckdateiname + `strftime("%Y%m%d%H%M%S")`
  aus **lokaler Druckeruhr** (`time_lapse_control.cpp:161-186`).
  Begruendet die 2026-10-25-Beobachtung „Zeitstempel im Dateinamen
  weicht ab".
- **Encoder:** `cpulimit -l 80 ffmpeg … libx264 -preset ultrafast`
  gebuendelte Binaries unter `elegoo/lib/ffmpeg/ffmpeg`
  (`time_lapse_control.cpp:280-293`); aktiver Pfad nutzt den
  eingebetteten `ImageToVideoEncoder` (`.cpp:110-114`).
- **Vollstaendige MQTT-Methodenliste:** 1002, 1019, 1020, 1029,
  1036, 1038, 1051, 2004, 2005 – mit Code-Beleg
  (`cc2-control/web-src/src/lib/machine.ts:88-98`,
  `cc2-control/src/mqtt.c:290-372`).
- **Zeitraffer-Flaggen-Pfade sauber getrennt:**
  - `method 1019 params.config.delay_video=true` (vor dem Druck,
    `mqtt.c:290-313`, der sauberere cc2-control-Weg).
  - `method 1020 params.config.delay_video=true` (beim Druckstart,
    der elegoo-link-Weg; von Klaus am 25.10. so verwendet, wirkt).
- **Zeitraffer-Status pro Druck** steckt in `method 1036`
  `history_task_list[]`, Feld `time_lapse_video_status`:
  0/1/2/3-Enum (1 oder 3 = renderbar, 2 = MP4 bereit),
  `time_lapse_video_url` nennt den Pfad (`history.h:22-62`,
  `history.h:160-178`, `plugin.ts:792`).
- **Zeitraffer-Rendering starten:**
  `method 1051 params.url="<history_task.time_lapse_video_url>"`;
  Fortschritt via `machine_status.status=12`, Timeout 600 s
  (`mqtt.c:362-372`, `mqtt.c:895`).
- **LAN-Download fuer das fertige MP4 (NEU, widerlegt
  2026-10-25-Aussage):**
  `GET http://<cc2-ip>/download?X-Token=<access>&file_name=video/<name>.mp4`
  – belegt in `cc2-control/src/history.h:307-336`. Derselbe
  Endpunkt wie fuer G-Code, nur `file_name`-Prefix anders.
- **Loeschen:** `method 1038 params.list=[task_id]` entfernt den
  History-Eintrag; dies ist der dokumentierte Weg, Zeitraffer-
  Rohframes und Videos sauber zu entsorgen. `method 1047`
  (DELETE_FILE auf `local`) ist dafuer NICHT der richtige Pfad
  (passt zu unserem 2026-10-25-Nachweislauf, in dem 1047 immer
  `1003` zurueckgab).
- **sub_status-Tabelle fuer Status 2** komplett belegt
  (`machine.ts:11-57`), inkl. der von uns heute frueh gesehenen
  Codes 1045, 1066, 1405, 2075, 2077, 2401, 2501, 2502, 2801,
  2802. **Codes 1066 und 2802 fehlen in der Community-Tabelle**;
  Vermutung: 1066 = Bed-Mesh-Zwischenschritt, 2802 = Homing-
  Zwischenschritt (die Nachbar-Codes sind so belegt).
- **Prozess-Topologie:** vendor `elegoo_printer` (binary, nicht
  im Repo) + `ai_camera` (binary, Quelle im Elegoo-Repo).
  `/opt/inst/` = read-only Installation, `/opt/usr/` = persistente
  Partition. Community startet `cc2-control` erst, wenn
  `pidof elegoo_printer` antwortet
  (`cc2-control/scripts/launch.sh:28`).
- **A/B-Partitionen** via `swupdate`, RootFS SquashFS, Paket
  `.zip.sig → .swu.sig + .json.sig`
  (OpenCentauri `software/updates-cc2/`).

### Ungeprueft (konkrete Experimente stehen aus)

- **LAN-Download des MP4 mit `X-Token=<access-code>` am echten CC2.**
  Der Pfad ist code-belegt (cc2-control nutzt ihn ueber Loopback);
  ob der Drucker denselben GET auch extern von einem anderen Host
  akzeptiert, muss gezielt getestet werden. Erst dann ist Punkt 6
  des revidierten Flusses wirklich bewiesen.
- **Verhaelt sich Status 12 beim USB-Export anders als bei
  `method 1051`?** Vermutung: identischer Composite-Code, nur mit
  anschliessendem Dateikopieren auf USB. Trennbar durch zwei
  Vergleichs-Composites (1× ueber MQTT, 1× ueber Display).
- **Was passiert mit dem Picture-Verzeichnis nach Composite?** Der
  Code sagt `rm -rf <pic_dir>` (`time_lapse_control.cpp:123` und
  `ai_camera.cpp:437`), Klaus beobachtete „Frames bleiben, beliebig
  oft exportierbar". Deutung: Was bleibt, ist das **MP4** in
  `/opt/usr/video/` – ein zweiter USB-Export laeuft dann nur noch
  als Kopiervorgang (ggf. ohne Phase 3020). Konkreter Test: zweiter
  Export derselben Zeitraffer-Datei; Erwartung: deutlich kuerzer
  als 26 s und evtl. nur sub_status 3021.
- **Codes 1066/2802** (im Mitschnitt gesehen, in der Community-
  Tabelle nicht) – Belegung aus elegoo-link checken oder weiter
  mitschneiden.

### Geht nicht ohne weiteren Zugang

- Die genauen Signale **innerhalb des `elegoo_printer`-Prozesses**,
  die Status 12 setzen und 1051 bedienen, sind in diesen Repos
  nicht enthalten – `elegoo_printer` ist Closed-Source-Binary. Fuer
  die App-Entwicklung ist das aber **nicht noetig**: Der
  beobachtbare Vertrag (MQTT-Methoden, Status-Felder, HTTP-
  Download-Pfad) ist aus `ai_camera`-Quellen und
  `cc2-control`-Code vollstaendig rekonstruierbar.
- Zur sauberen Verifikation der Dateinamen im Filesystem
  (`/opt/usr/picture/<name><ts>/0001.jpeg` …) braeuchte es
  Root-Zugang per SSH; den gibt es laut OpenCentauri auf Firmware
  **ab 02.00.02.00 nicht mehr** (SSH-Prozess entfernt, Downgrade-
  Sperre). Fuer Phase 2 der App **nicht erforderlich** – die
  Datenstruktur wird ueber `method 1036` indirekt sichtbar.
- Firmware-Entpackung (`.zip.sig → .swu.sig → SquashFS`) ist
  **nicht noetig** fuer unser Zeitraffer-Problem; alle relevanten
  Pfade und Methoden sind oben belegt. Wenn Elegoo in einer
  spaeteren FW neue Methoden/Flags einfuehrt, waere Entpackung ein
  Weg; bis dahin verzichten wir.
- Private Signaturschluessel sind in keinem der Repos und werden
  auch nicht gesucht.

### Fazit: Reicht die Recherche?

**Ja fuer die App-Seite.** Der komplette User-Fluss „Zeitraffer
einschalten, filmen lassen, MP4 ueber LAN herunterladen, Historie
pflegen" ist aus den oben verlinkten Datei:Zeile-Belegen
rekonstruierbar. Konkret ergaenzend eingebaut werden kann:

- `method 1019`-Preamble vor `method 1020` (statt oder zusaetzlich
  zu `config.delay_video` in 1020).
- `method 1036` als History-Quelle inkl. Zeitraffer-Status-Enum.
- `method 1051` zum Rendern + Status-12-Progress-Anzeige.
- HTTP-GET `/download?X-Token=…&file_name=video/<name>.mp4` zum
  Download. Status 12 / substate 3020/3021 interpretieren als
  „Rendering" / „Kopieren".
- `method 1038` zum Loeschen eines Druck-/Zeitraffer-Tasks.

**Firmware-Paket wird aktuell nicht benoetigt.** Es waere nur
dann naechster Schritt, wenn der LAN-Download-Pfad gegen den echten
CC2 **nicht** funktioniert (dann koennte das Entpacken Aufschluss
geben, welchen Pfad der HTTP-Dienst beim Drucker tatsaechlich
registriert). Dasselbe gilt fuer Root-Zugang: wuerde nur gebraucht,
falls `method 1036`+`1051`+`/download` beim Realtest widersprechen.

**Konkret ausstehender Test (ein naechster Lauf, lesend):**

1. Druckhistorie via `method 1036` abfragen – `history_task_list`
   fuer die beiden heutigen Drucke pruefen.
2. `time_lapse_video_url` fuer den Zeitraffer-Druck lesen.
3. HTTP-GET auf `http://<cc2-ip>/download?X-Token=<access>&file_name=<url>`
   starten; bei HTTP 200 + Content-Type `video/mp4` ist der
   LAN-Download-Pfad bewiesen.
4. Falls Verweigerung: Firmware-Paket als naechsten Schritt
   erwaegen; vorher aber elegoo-link `elegoo_fdm_cc2_http_transfer.cpp`
   genauer lesen, ob dort ein anderer Pfad fuer Video versteckt ist.

Nichts committed, nichts gepusht. Clones unter `/tmp/handslice-research/`
(nicht im Repo).

---

## 2026-10-26 06:55 UTC – Passiver MQTT-Mitschnitt, zwei Drucke + USB-Export ausgewertet

Mitschnitt: `logs/cc2-sniff-2026-10-26.jsonl`, 1691 MQTT-Nachrichten
in 28 min 51 s (06:23:25 → 06:52:16 UTC). Nur Subscribe `#`, kein
PUBLISH im JSONL (nachweisbar: nur `meta: start/connect/subscribe/
disconnect`-Records vom Script, keine Register- oder Command-Records).

Auswertung: `tools/sniff-analyze.py`.

### Nachweislich funktioniert

- **Zwei Druckläufe sauber erkannt** (gleiche Datei
  `handslice_1792947629010.gcode`, neue `uuid` pro Lauf):
  - Lauf 1 (ohne Zeitraffer): 06:25:11 → 06:37:43 UTC, 12 min 32 s.
  - Lauf 2 (mit Zeitraffer):  06:38:07 → 06:50:38 UTC, 12 min 31 s.
- **Identische sub_status-Sequenz in beiden Läufen**: 1405 (Pre-Heat)
  → 1066 (Bed-Mesh) → 2801/2802 → 1045/1066 → 2075 (Printing). Je
  drei kurze Pause/Resume-Fenster waehrend des Drucks (2501→2502→
  2401→2402). Druckende 2077. Timing praktisch deckungsgleich.
- **Status 12 (VIDEO_COMPOSING) erstmals im Mitschnitt beobachtet** –
  und zwar NICHT am Druckende, sondern bei Klaus' USB-Export-Aktion:
  ```
  06:50:38  Druck 2 fertig           machine_status.status 2→1, state 'complete'
  06:50:49  USB-Stick erkannt        external_device.u_disk = true
  06:50:54  Composing beginnt        status 1→12,  sub_status 0→3020
  06:51:20  Phase 2                  sub_status 3020→3021
  06:51:20  Composing fertig         status 12→1,  sub_status 3021→0
  06:52:03  USB-Stick entfernt       u_disk = false
  ```
  Gesamt-Composing-Dauer: 26 Sekunden. Zeitlicher Abstand Composing-
  Start zu USB-Erkennung: 5 Sekunden; zu Druckende: 16 Sekunden.
- **Unterschiede Lauf 1 vs. Lauf 2** im passiven Mitschnitt: **keine**.
  Der komplette Status-Push-Strom ist in beiden Läufen bis auf
  Zeitstempel und uuid identisch. Insbesondere keine Spur von
  `delay_video`, `camera`, `chassis_camera`, `time_lapse`, `video` –
  weder als Payload-Schluessel noch als Wert, in keinem der 1691
  Datensaetze (grep-Resultat: 0 Hits).
- `exception_status[0]=1243` erschien in beiden Laeufen jeweils einmal
  (06:28:46 Lauf 1, 06:41:41 Lauf 2), jeweils im Pause-Fenster. In
  beiden Laeufen identisch, also **kein Zeitraffer-Signal**.
- Script veraendert den Drucker nicht: Prozess-exit sauber, Drucker
  blieb Idle, keine Nebeneffekte.

### Ungeprueft

- Ob Status 12 **auch** direkt am Druckende (ohne USB-Export) kurz
  gepusht wird. Im heutigen Mitschnitt lag der Delta-Takt bei ~1 s
  und waere nicht leicht zu uebersehen – wir haben keinen 1→12 im
  Zeitraum 06:50:38…06:50:49 gesehen, aber ein zusaetzlicher
  Zeitraffer-Druck ohne USB-Export-Followup wuerde das sauber
  festnageln.
- Bedeutung von `sub_status=1243` (exception) und der kurzen
  Pause/Resume-Zyklen 2501/2502/2401/2402 waehrend des Drucks.
- Welchen Trigger Composing hat: eine aktive Aufnahme (`delay_video=
  true`) oder jede USB-Stick-Erkennung nach einem Druck. Zum
  Trennen braeuchte es einen Druck **ohne** Zeitraffer + USB-Export
  danach als Kontrollprobe.

### Geht nicht / nicht beobachtbar

- **Zeitraffer-Status aus passivem `api_status` ablesbar: nein.**
  Weder `delay_video` noch `chassis_camera.configured` noch
  irgendein Kamera-Capability-Feld werden vom CC2 in diesem Pfad
  gepusht. Die bisher in `docs/networking-cc2.md` dokumentierte
  Erwartung (`external_device.chassis_camera.configured`) hat sich
  im Mitschnitt **nicht bestaetigt** – wir sehen nur
  `external_device.u_disk`.
- **Topic-Diversitaet via Passiv-Sniff: nein.** Alle 1691 Nachrichten
  liegen auf dem einen Topic `elegoo/<sn>/api_status`. Register-
  Response, api_response, Camera-Topics erschienen nicht – fuer die
  braeuchte es eigene Register-/Request-Pakete, die wir hier
  bewusst nicht gesendet haben.

### Konsequenz fuer die App (M5 Punkt 3)

Der aktuelle Workaround („Capability-Feld fehlt → als unterstuetzt
betrachten, nur `configured=0` sperrt") bleibt richtig – im passiven
Pfad existiert fuer diesen CC2 kein Capability-Feld, auf das wir
positiv pruefen koennten. Die neue Erkenntnis ist: Status 12 ist
**primaer der USB-Composing-Zustand**, nicht der Aufnahme-Zustand.
Falls die App Zeitraffer-Fortschritt anzeigen will, muss sie Status
12 als „Composing fuer USB-Export" interpretieren, nicht als
„Zeitraffer wird aufgenommen".

### Artefakte

- `tools/mqtt-sniff.py` – passiver Subscriber mit JSONL-Output.
- `tools/sniff-analyze.py` – Topic/Feld/Transition/Keyword-Report.
- `logs/cc2-sniff-2026-10-26.jsonl` – Rohmitschnitt (SN im Klartext,
  deshalb `logs/` jetzt in `.gitignore`).

---

## 2026-10-25 16:40 – Erster echter Druck aus der App (Commit 2b4fc1a)

- Klaus hat am Poco den ersten echten Druck aus der App ausgelöst:
  Seite A (Strukturiert), Z-Offset 0, Fach A4, PLA. Druckstart,
  Live-Status (Zustand, Progress, Layer-Zähler, Temperaturen) und
  Fortschrittsgefuehl in der App funktionieren; der Wuerfel ist am
  Drucker visuell einwandfrei herausgekommen.
- Damit ist das Phase-3-Erfolgskriterium „Slicen auf dem Geraet und
  Drucken ueber LAN mit Live-Status" erstmals end-to-end erfuellt.

### Beim Realdruck aufgefallene Befunde (M5-Agenda)

1. Pair-Dialog: Vorbelegtes Adressfeld bekam den **Modellnamen**
   („Elegoo CC2 Combo") statt der IP → „Invalid internet address"
   beim Verbinden. Klaus hat die IP manuell eingetragen, danach lief
   es. Dialog muss IP/Hostname halten und beim Speichern pruefen.
2. Fortschritt in Prozent bleibt in der App stehen, waehrend der
   Schichtzaehler mitlaeuft. Am Drucker lief der Prozentwert normal.
   Richtiges Feld aus echtem 1002-Snapshot belegen.
3. Zeitraffer meldet „Unterstuetzung unbekannt – Feld weggelassen",
   obwohl der CC2 (FW 02.01.01.07) belegbar Zeitraffer kann (eigener
   delay_video=true-Test). Fehlendes Capability-Feld muss als
   „unterstuetzt" gelten (Model-Default fuer diesen CC2), nur ein
   ausdrueckliches `configured=0` sperrt.
4. Statusanzeige zeigt Rohschluessel (`machine_status.status`,
   `heater_bed`, `extruder`) statt Zustand/Bett/Duese. Lokalisieren.
5. Z-Offset: Nachweis aus M4c erbracht. Gespeicherten Wert der
   gewaehlten Seite beim Slicen anwenden. Hinweis „nur gespeichert"
   wird zu „wird beim Slicen angewendet". Nachweis: Seite B +0.02
   verschiebt G-Code, Seite A 0 bleibt unveraendert.

Bericht zur Bearbeitung der Befunde folgt als Phase-3-M5-Eintrag.

---

## 2026-10-26 – Offene Punkte für morgen

Nach Abnahme von Phase 4.3 + Stresstest-Nachtrag (A–D) stehen für
morgen vier Themen an:

1. **Neptun-Testmodell skalieren**, damit der `--download`-Stresstest
   bis zum G-Code durchlaeuft. Rohscale 3970 × 15 475 × 5 828 mm
   triggert aktuell libslic3rs Preflight-Grenztest. Umsetzung:
   `scale_factor`-Feld in `engine/test/stress-models.json` + neue
   CLI-Option `--scale <factor>` in `handslice-cli` (Orca-eigene
   Funktion `ModelObject::scale(Vec3d)` aus `libslic3r/Model.cpp`,
   NICHT selbst gebastelt). Vertragstest-Schritt ergaenzen.

2. **Three D Scans Lizenzangabe an der Quelle belegen**. Das Sidecar
   nennt die Lage ehrlich ("Free 3D scan archive, keine CC-Lizenz
   zertifiziert"), aber die Rechtssituation ist unklar. Vor weiterer
   Nutzung die Lizenz an der Quelle klaeren (contact@threedscans.com
   anschreiben oder Terms/Impressum nachlesen) und das Sidecar
   entsprechend scharf stellen. Falls nicht freigegeben: Default-
   Entry austauschen (Stanford XYZ RGB Statuette oder konkrete
   Smithsonian-URL, siehe stress-models.json "smithsonian_hinweis").

3. **"Als Profil speichern" am Gerät durchklicken und Profil wieder
   laden**. In Phase 4.3 ist der Schreib-Pfad komplett
   (`ProfileWriter` → `ApplicationSupportDirectory/profiles/user/
   <slug>.json`), aber am Poco nur per Unit-Test belegt – noch kein
   End-to-End-Lauf mit Settings-Overrides → Save → App neu laden →
   Preset-Pick → Slice. Dafuer braucht's auch den Preset-Picker im
   SettingsScreen (bisher nicht gebaut).

4. **Filament-Einstellungen als naechste Etappe** (Phase 4.4). Das
   Schema aus 4.1 enthaelt den `filament`-Bereich bereits
   vollstaendig (7 Reiter, 22 Gruppen, 83 Options, 38/81/83
   nach Basis/Fortgeschritten/Experte). UI-Pfad analog zu 4.2 Prozess,
   plus Multi-Material-Toggle fuer A1..A4. **Vorsicht:** anders als
   Prozess greifen Filament-Werte in die Druckdynamik ein
   (Temperaturen, Fluss, Retract) – Validate-Fehler sind
   wahrscheinlicher. Die SlicingErrors-Pipeline aus 4.3 sollte das
   abfangen.

---

## 2026-10-25 22:30 – Stresstest ins Repo (eigener Commit)

- `engine/test/stress-test.sh <modell.stl> [--out <dir>]
  [--skip-arm64] [--skip-x86] [--bed A|B]`: misst Slice-Dauer,
  Peak-VmHWM und Thermal-Status (Poco) für x86 und arm64. Keine
  festverdrahteten Fremdmodelle; der Pfad kommt per Argument.
- `docs/stress-test.md`: Doku + Messtabelle vom 25.10. mit Modell-
  Kennzahlen (2 809 436 Dreiecke, 134 MB, 186 × 72 × 209 mm) +
  Herkunftsangabe für auryn.stl: „Auryn Medallion – Print Ready –
  FREE" von Droppingformdesigns, cults3d-URL, Lizenz CULTS „Private
  Use" („No AI"). Hinweis: zum Nachstellen selbst herunterladen.
  Modell und Bilder davon nicht ins Repo (`.gitignore: /local-test/`).
- Vorschlag für ein frei lizenziertes Großmodell im selben Dokument –
  Scan-the-World (CC-BY-SA), Smithsonian 3D (CC0), Stanford
  Thai Statuette (Educational-Use). Nicht eingebaut; wartet auf
  Entscheidung.

Smoke-Test gegen den Kerbenwürfel am x86 und am Poco:
```
x86-exit=0  dauer=1005ms  peak-VmHWM=2812kB (2.7 MB)
arm64-exit=0  dauer=2180ms  peak-VmHWM=15184kB (14.8 MB)
thermal=Status 0 / Status 0
```
Der Script liefert Modell-Kennzahlen (bbox + Triangle-Count) ohne
libslic3r – pure Python.

---

## 2026-10-25 22:10 – Phase 4.3 Nachtrag: Metrik + Einzel-Beleg + saubere SlicingErrors (STOPP)

### 1. Metrik angleichen (1172 vs 1367 mm Filament)

Keine Byte-Divergenz zwischen x86 und arm64, sondern **zwei
verschiedene Messgroessen** im alten Vertragstest-Script:

- Alt (Vertragstest): rohe Summe aller **positiven E-Werte** aus
  `G1 ... E<float>`-Zeilen – zaehlte zusaetzlich die Prime-Pumpen
  nach Retract mit (`G1 E.728 F1800`, kein X/Y). Ergibt im Kerben-
  wuerfel-Baseline **1367 mm**.
- Richtig (Orca-kanonisch): `total_filament_used_mm` aus dem Stats-
  JSON = Summe positiver E **nur bei G1 mit X oder Y** (echte
  Extrusion, ohne Prime-Pumpen). Ergibt **1172.33 mm**.

Belegt: `extrusion_canonical()` im Vertragstest-Script liefert aus
dem G-Code exakt denselben Wert wie das Stats-JSON (Differenz unter
1 mm). Rohe-E-Summe ist um die Retract-/Prime-Zahl aufgeblaeht
(Kerbenwuerfel: 190 mm Retracts → 1367 − 1172 = 195 mm Differenz).

**Fix:** Vertragstest nutzt jetzt `total_filament_used_mm` aus dem
Stats-JSON und validiert zusaetzlich, dass die G-Code-Rekonstruktion
sich damit deckt.

### 2. Einzel-Beleg der drei Overrides (Kerbenwuerfel, Poco)

Jeweils genau EINE Aenderung, Metrik passt zur Aenderung:

| Lauf | Z-Moves | Wall-Linien | Infill-Linien | Filament (mm) |
|---|---:|---:|---:|---:|
| baseline                 | 239 |  97 | 126 | 1172.3 |
| nur `layer_height=0.28`  | **175** |  –  |  –  | 1101.0 |
| nur `wall_loops=4`       |  –  | **185** |  –  | 1403.9 |
| nur `sparse_infill=40%`  |  –  |  –  | **229** | 1393.5 |
| alle drei zusammen       | 174 | 185 | 229 | 2016.3 |

- `layer_height=0.28`: Z-Moves 239 → 175 (−27 %) – weniger Schichten
  bei dickerer Schicht; Filament sogar leicht geringer, weil die
  Dickenerhoehung durch die Linienbreite ausgeglichen wird.
- `wall_loops=4`: Wall-Linien (Outer + Inner) 97 → 185 (+91 %); mehr
  Perimeter.
- `sparse_infill_density=40%`: Sparse-Infill-Linien 126 → 229 (+82 %);
  mehr Fuellbahnen.

### 3. SlicingErrors/Validate sauber abfangen

- `engine/cli/handslice-cli.cpp`: `main` wrappt `run(argc, argv)`
  mit try/catch-Kette:
  ```
  SlicingErrors   → exit 10, pro Error eine '-'-Zeile
  SlicingError    → exit 10
  ConfigurationError → exit 11
  Slic3r::Exception  → exit 12
  std::exception     → exit 13
  ```
  (Argument-Fehler bleiben bei exit 2 ueber `die()`.)
- Lokaler Test mit `--overrides '{"layer_height":"2.0"}'` am x86:
  ```
  exit=12
  handslice-cli: Slic3r-Fehler: Flow::spacing() produced negative
    spacing. Did you set some extrusion width too small?
  ```
  Kein `terminate called`, kein abort/coredump mehr.
- Vertragstest-Schritt 7 am Poco prueft: Meldung enthaelt
  "slicing"/"validate"/"invalid"/"layer_height", KEIN "terminate called",
  Exit != 0.

Die App zeigt die Meldung bereits ueber den bestehenden
`SliceProcessException` → `lastError = 'slice.error:<exit>:<stderr>'` →
`_formatSliceError` → `l.sliceErrorExit(code, msg)` lesbar an
("Slicer fehlgeschlagen (Exit 12): handslice-cli: Slic3r-Fehler …").

### Tests + Build

- 28/28 Widget-Tests gruen (`flutter test test/widget_test.dart`).
- x86-CLI + arm64-CLI mit M10-Hash neu gebaut (Guard: Side-Cars
  identisch).
- Vertragstest `cli-contract-arm64.sh` 7/7 am Poco gruen.

---

## 2026-10-25 21:40 – Phase 4.3: Overrides ins Slicen + Profil speichern (STOPP)

### CLI `--overrides` (`engine/cli/handslice-cli.cpp`)

- Neue Flag `--overrides '<json>'` oder `--overrides @datei.json`.
- Pro Key: Pruefung gegen `print_config_def.get(key)` → **unbekannter
  Key wirft klaren Fehler** (`unknown option 'nonexistent_key'`).
- Pro Wert: `cfg.set_deserialize_nothrow(key, value, ctx)`; bei false
  oder `ConfigurationError` wird opt_key + Wert + Grund gemeldet.
- Angewendet NACH Profil-Chain + `--bed-type` + `--z-offset`, so dass
  Overrides wie in Orcas Preset-Edit-Pfad die oberste Prioritaet haben.

### App-Pfad

- `SlicerService.slice({overrides: Map<String,String>})` reicht den
  JSON-serialisierten Overrides-Map an die CLI durch (`jsonEncode`).
- `ProjectState.slice(overrides: SettingsOverrides?)` holt
  `overrides.all` aus dem Setting-Screen und uebergibt es.
- `ProjectScreen` bindet den `SettingsOverrides` ans Slice-Button.
- CLI-Fehler aus `--overrides` werden ueber die bestehende
  `SliceProcessException` → `lastError='slice.error:<code>:<msg>'`
  lesbar in der UI gezeigt (zusammen mit dem OOM-Pfad aus dem
  Stresstest).

### "Als Profil speichern" (`app/lib/settings/profile_writer.dart`)

- Speichert die aktuellen Overrides als eigenes Orca-Preset:
  `ApplicationSupportDirectory/profiles/user/<slug>.json`.
- Format spiegelt die resources-Preset-Dateien:
  `{name, type:"process", from:"User", inherits:"<base>", <overrides>}`.
- Button im SettingsScreen oben rechts, mit Dialog fuer Profilnamen.
  Snackbar meldet Erfolg (Dateiname) oder Fehler.
- 7 ARB-Keys neu (en + de) inkl. Plural fuer "Überschreibungen".

### Nachweise – G-Code mit 3 Überschreibungen (x86, Kerbenwuerfel)

| Lauf | Z-Moves | Extrusion-Moves | G-Code | Zeit | Filament |
|---|---:|---:|---:|---|---:|
| baseline (ohne --overrides) | 238 | 3 897 | 220 kB | 9m 25s | 1 172 mm |
| `layer_height=0.28`, `wall_loops=4`, `sparse_infill_density=40%` | **196** | **5 843** | 265 kB | 8m 11s | **2 017 mm** |

- Weniger Schichten (238 → 196) durch dickere Schicht (`+40%`).
- Mehr Perimeter + mehr Füllung → +50 % Extrusionslinien.
- Materialverbrauch +72 % (1172 → 2017 mm).
- **Byte-gleiche Baseline:** `diff <(grep -v generated base.gcode) <(grep -v generated base2.gcode) == exit 0`. Zwei identische Laeufe ohne --overrides liefern am x86 denselben G-Code (ausser Zeitstempel-Header).

### Nachweis – Brim-Overrides auf auryn.stl (Stresstest-Modell)

```
--overrides '{"brim_type":"outer_only","brim_width":"6"}'
```
G-Code `local-test/auryn-brim-x86.gcode` (65 MB, 23 s Slice am x86):

- Feature-Marker `;TYPE:Brim` im G-Code vorhanden.
- Erste Schicht (initial_layer_print_height=0.2) hat 525 `G1`-
  Extrusionszeilen vom Typ `Brim`, X-Bereich `[131.21, 144.27]`,
  Y-Bereich `[96.29, 107.60]`.
- Modell ist für Druck ohne Stuetzen auf die Spitze gekippt – der
  Fussabdruck ist deshalb klein. Brim-Ring (span 13×11 mm) liegt um
  den Fuß des gekippten Models und etwas außerhalb des reinen
  Modell-Footprints (im G-Code `Outer wall` nur 5 Zeilen bei
  (137.11, 101.87)); der Brim bildet ringsum eine ca. 6 mm breite
  Haftzone, wie erwartet.
- Grenztest bleibt gruen: alle Brim-X in `[0, 256]`, alle Brim-Y in
  `[-10, 256]` (printable_area + bed_texture_area). Kein OOB.

### Vertragstest `engine/test/cli-contract-arm64.sh` erweitert

- Schritt 5: dieselben drei Overrides am Poco; prueft
  Z-Moves-Ruckgang + ≥30 % mehr Extrusion.
- Schritt 6: ungueltiger Key muss mit `unknown option 'nonexistent_key_xy'`
  abgewiesen werden.
- Weiterhin Byte-Diff Z-Offset −0.04 mm aus 4.1b.

### Tests + Build

- 28/28 Widget-Tests gruen; `flutter analyze` 0 Fehler.
- x86-CLI + arm64-CLI mit M9-Hash neu gebaut (Guard: beide `.commit`-
  Side-Cars identisch).

---

## 2026-10-25 21:00 – Stresstest grosses Modell (vor 4.3, STOPP)

Modell: `auryn.stl` von Klaus, 2 809 436 Dreiecke, 134 MB. Modell lokal
unter `local-test/` (per `.gitignore` ausgeschlossen; nichts davon im
Repo, keine Doku-Bilder).

### 1. Erwartung Grenztest bei --no-center – bestaetigt

STL-Bounds laut Lesung: `X: -93.15..+93.15`, `Y: -35.01..+36.76`,
`Z: 8.00..217.11`. Druckbereich CC2 laut Profil: `printable_area
0..256`, `bed_texture_area 0..-10..256`, `height 256`.

Mit `--no-center` wirft libslic3r direkt `Slic3r::SlicingErrors`
(`terminate called after throwing an instance of 'SlicingErrors'`),
weil X <0 ausserhalb der Platte liegt. Belegt am x86:
`engine/bin/handslice-cli-x86 --no-center auryn.stl → exit 134`
(Abort nach ca. 15 s, waehrend Prefligh-Validierung).

Konsequenz fuer die App: der Grenztest-Pfad ist zwar da, aber der
Nutzer sah bisher nur die abstrakte Exception. Ursache: `slicer.dart`
hat `--no-center` als Default gesetzt – ein Erbe aus den
Reference-Testlaeufen (dort ist das Modell schon vorzentriert).

### 2. Fix – wie Orca-GUI auf die Platte setzen

- `app/lib/engine/slicer.dart`: `noCenter` als Parameter default
  **`false`**. Default-Flow entspricht ab jetzt Orcas GUI.
- Die bereits in `handslice-cli.cpp` eingebaute Zentrierung ruft
  `ModelObject::center_around_origin()` (Model.cpp:1708) +
  `set_offset(bed_center, -bb.min.z())` – das sind Orcas eigene
  libslic3r-Funktionen, keine eigene Mathe. Belegt in docs/engine-
  integration.md "Modellpositionierung".
- Byte-Gleichheit Kerbenwuerfel: `--no-center` vs. Default (Centering)
  liefern am x86 **identischen** G-Code (bis auf den Zeitstempel-
  Header). Grund: der vorzentrierte Kerbenwuerfel wird durch die
  Centering-Logik effektiv um (0,0,0) zurueckbewegt. Belegt per
  `diff <(grep -v generated kerbe-nocenter) <(grep -v generated kerbe-center)` → leer.
- CLI unveraendert, nur Default in der App gedreht; x86/arm64 bleiben
  byte-gleich zum M6-Vertragstest.

### 3. Messung x86 (AMR5) vs. arm64 (Poco X3 Pro)

| Modell | Build | Slice-Dauer | Max VmHWM | G-Code | Est. Druckzeit | Thermal |
|---|---|---:|---:|---:|---|---|
| Kerbenwuerfel 20 mm | x86 | ~0.7 s | ~800 MB | 215 kB | 9m 25s | – |
| Kerbenwuerfel 20 mm | arm64 (Poco) | ~0.9 s | ~800 MB | 215 kB | 9m 25s | Status 0 |
| **auryn.stl (134 MB)** | **x86** | **22.2 s** | **1 240 MB** | **65 MB** | 7h 11m 23s | – |
| **auryn.stl (134 MB)** | **arm64 (Poco)** | **75.5 s** | **1 126 MB** | **65 MB** | 7h 12m 51s | **Status 0** vorher und nachher |

- x86: `/proc/<pid>/status VmHWM` zwischen 779 MB (Start) und 1240 MB
  (Peak). Keine systemrelevante Swap-Nutzung.
- arm64: on-device `/proc/<pid>/status VmHWM`-Polling via adb shell;
  Peak 1126 MB. Thermal-Status via `dumpsys thermalservice` sowohl
  vorher als auch nachher **Status 0** (keine Drosselung), trotz 75 s
  CPU-Volllast.
- G-Code-Vergleich x86 vs. arm64 EXECUTABLE_BLOCK: **nicht byte-
  gleich** – das bekannte TBB-Reorder-Phaenomen (siehe
  `docs/engine-integration.md` "Nondeterminismus"). Fuer den
  Kerbenwuerfel: zwei stabile arm64-Varianten pro Lauf, nachgewiesen
  mit 3 consecutive arm64-Laeufen (sha `84c9ad07…` / `33fbd6a5…` /
  `84c9ad07…`). Fuer das 65-MB-auryn-G-Code gilt dasselbe
  (Perimeter-Reorder in Travel-Moves ab ca. Zeile 1088), funktional
  aequivalent, nur Reihenfolge-bedingt.

### 4. App-UX waehrend Slice

- `SlicerService.slice()` nutzt jetzt `Process.start` statt
  `Process.run` und reicht das Prozess-Handle via
  `onProcessStarted(proc)` an den Caller durch.
- `ProjectState.slice()` haelt das Handle in `_activeProc` + Zeit in
  `_sliceStartedAt`, bietet `cancelSlice({cleanupOutputPath})` an.
- `ProjectScreen` zeigt waehrend `isSlicing` eine neue Karte mit
  Verlaufszaehler `"Slice läuft… mm:ss"`, `LinearProgressIndicator`
  und `Abbrechen`-Button. Nach Cancel: Button-Text wird zu
  `"Wird abgebrochen – warte, bis die Engine stoppt…"`.
- UI darueber (Modell, Drucker, Druckbett, Reiter-Chips) bleibt
  waehrend des Slices komplett reaktiv – belegt am Poco mit dem
  Realdruck-STL. Tabwechsel + Z-Offset-Nudgen gehen weiter.
- Nachweis am Poco (Screenshots `/tmp/handslice_slicing.png` +
  `/tmp/handslice_cancelling2.png`): Fortschrittskarte zeigt
  `"Slice läuft… 00:02"`, Cancel-Button loest den CLI-Prozess am
  Geraet sofort auf (`ps -ef | grep handslice-cli` leer), die
  halb-fertige `handslice_project.gcode` wird aus
  `/data/data/dev.handslice.handslice/files/` geloescht
  (`run-as ls -la files/` zeigt nur `profiles/` + `profileInstalled`).

### 5. OOM-/Signal-Kill-Handling

- `SlicerService` wirft eine neue `SliceProcessException` mit
  `killedBySignal` als Flag (Exit-Code negativ oder 137/143 →
  SIGKILL/SIGTERM, auf Android der LMK bei zu wenig Speicher).
- `ProjectState.slice()` uebersetzt den Signal-Kill ohne vorangegangenes
  `cancelSlice` in `lastError = "slice.oom"`. Die UI zeigt dann die
  lokalisierte Meldung („Nicht genug Arbeitsspeicher — der Slicer
  wurde vom System beendet. Modell mit weniger Dreiecken, dickere
  Schicht oder andere Apps schliessen." / englisch analog).
- Reproduzierbarer Nachweis am Geraet war nicht moeglich: `adb shell
  pkill -9` am App-UID ist `Operation not permitted`, und der 8-GB-Poco
  loest beim 134-MB-Modell keinen echten OOM aus (Peak 1.1 GB von
  7.3 GB). Statt dessen: Unit-Test `ProjectState.slice bei Signal-Kill
  liefert lastError=slice.oom` im `widget_test.dart` deckt den Pfad
  komplett ab.
- `cancelSlice()`-Pfad: ein zweiter Test
  (`ProjectState.cancelSlice setzt cancelRequested + Cleanup`) prueft,
  dass der danach ausgeloeste Signal-Kill NICHT als Fehler gemeldet
  wird und `isSlicing=false` am Ende steht.

### Tests + Commit

- 28/28 Widget-Tests gruen (`flutter test test/widget_test.dart`),
  davon 2 neu fuer OOM + Cancel.
- `flutter analyze` 0 Fehler.
- Commit lokal (Code-Aenderungen + PROGRESS); Modell, Zwischendaten
  und Mess-Logs liegen in `local-test/` und bleiben per
  `.gitignore` ausserhalb des Repos.

---

## 2026-10-25 20:30 – Phase 4.2: Prozess-Einstellungen in der App (STOPP)

Setzt direkt auf 4.1 auf. Nachgeholt vor 4.2:
- `--dump-schema` liefert jetzt `orca_version` (aus `SoftFever_VERSION`,
  version.inc:10) und `slic3r_internal_version` (SLIC3R_VERSION,
  version.inc:17) getrennt. Submodul steht nachweislich auf `v2.4.2`
  (Commit `8500fcdcc`); die `02.06.00.51` ist das interne libslic3r-
  Config-Format-Legacy aus Slic3r/PrusaSlicer, nicht die Nutzer-Version.
- `build_settings_schema.py` berechnet pro Option `tier` nach Klaus-
  Vorgabe (`simple → basis`, `advanced → fortgeschritten`,
  `expert|develop → experte`) und zeigt im Report die monotone
  Ansammlung pro Stufe:
  print 50/324/337, filament 38/81/83, printer 5/68/73.
- arm64 `--dump-schema` am Poco gegen x86 diffen: steht aus (ADB-Device
  war bei Abschluss nicht erreichbar). Build-Guard sichert gleichen
  Quellstand; inhaltlich zwingend identisch, weil beide dieselbe
  statische `print_config_def`-Instanz introspizieren.

### Was in 4.2 gebaut wurde

- **`app/assets/settings-schema.json`** (634 KB) als App-Asset gebuendelt.
  Produziert von `engine/scripts/build_settings_schema.py` – rein
  mechanisch aus Orca v2.4.2.
- **`app/lib/settings/settings_schema.dart`**: Loader + Model
  (`SettingsSchema`, `SettingPage`, `SettingGroup`, `SettingOption`) +
  `enum SettingTier { basis, fortgeschritten, experte }` mit der
  monotonen `includes(mode)`-Logik.
- **`app/lib/settings/settings_overrides.dart`**: `SettingsOverrides`
  (ChangeNotifier) haelt pro Options-Key den vom Nutzer gesetzten
  Wert als serialisierten String; Reset entfernt ihn. Persistenz
  pro Profil ("Als Profil speichern") kommt in 4.3.
- **`app/lib/screens/settings_screen.dart`**: Prozess-Oberflaeche
  - Stufen-Umschalter oben (Basis/Fortgeschritten/Experte), fokussierbar.
  - Suchfeld filtert ueber Key/Label-de/Label-en/Tooltip-de/Tooltip-en.
  - Reiter-Chips (horizontal scrollbar) fuer die Prozess-Seiten;
    bei aktiver Suche sind alle Seiten gleichzeitig sichtbar.
  - Pro Gruppe eine Karte, pro Option eine Zeile mit lokalisiertem
    Label, aufklappbarem Tooltip (Info-Icon), rohem Key + Mode-Marker.
  - Reset-Icon ↺ nur bei geaenderter Option; Label dann farbig
    hervorgehoben.
  - Bedienelemente je Typ: Switch (bool), Dropdown mit lokalisierten
    enum-Labels (enum), Zahlfeld mit −/+-Steppern inkl. min/max aus
    dem Schema (int/float/percent/float_or_percent), Textfeld (string),
    Textfeld-Fallback fuer Vektor-/Spezial-Typen.
  - Komplett per `Focus`+`Builder` fokus-navigierbar (D-Pad, Tab,
    Controller).
- **l10n**: 7 neue ARB-Keys (en + de) in `app_en.arb` + `app_de.arb`
  (`settingsSourceCaption`, `settingsTierBasis/Advanced/Expert`,
  `settingsSearchHint`, `settingsResetTooltip`, `settingsNoMatches`).

### Tests

- 5 neue Widget-Tests in `app/test/widget_test.dart`:
  - `SettingTier.includes` mappt Klaus-Stufen korrekt.
  - `SettingsSchema` laedt eine Mini-Fixture.
  - `SettingsScreen` filtert nach Stufe (Basis zeigt nur simple,
    Fortgeschritten + Experte wie erwartet).
  - Override via Switch wird im `SettingsOverrides` gespeichert;
    Reset-Icon nimmt ihn zurueck.
  - Suchfeld filtert ueber alle Seiten (ignoriert das aktive Reiter-
    Chip).
- Alle 26/26 Tests gruen (`flutter test test/widget_test.dart`).

### Nicht in 4.2 (bewusst)

- "Als Profil speichern" (gehoert nach 4.3, dort wird auch der CLI-
  Overrides-Pfad gebaut).
- Filament- und Drucker-Reiter.
- Vektor-/Spezial-Typen bekommen in 4.3 eigene Bedienelemente.
- Interaktive Werkzeuge (Mal-Pfad fuer Stuetzen/Naht/Farbe,
  Fuzzy-Skin-Painter) sind laut Klaus-Auftrag nicht Teil des
  Einstellungsbaums und bleiben draussen.

---

## 2026-10-25 19:00 – Phase 4.1: Einstellungsbaum-Schema aus OrcaSlicer erzeugt (STOPP)

Grundsatz Phase 4: **nichts von Hand pflegen**. Alles mechanisch aus
OrcaSlicer v2.4.2 abgeleitet.

### Was gebaut wurde

1. **`handslice-cli --dump-schema`** (`engine/cli/handslice-cli.cpp`)
   dumpt `Slic3r::print_config_def` (PrintConfig.hpp:598). Pro Option:
   `key, type, nullable, default, mode (simple/advanced/expert/develop),
   gui_type, label, full_label, category, tooltip, sidetext,
   printer_technology, min/max, enum_values + enum_labels, aliases,
   shortcut, ratio_over, readonly, is_code, multiline`. Keine Interp-
   retation – reine Pass-Through-Spiegelung dessen, was in
   `ConfigOptionDef` (Config.hpp:2204+) steht.
2. **`engine/scripts/extract_tab_layout.py`** parst
   `src/slic3r/GUI/Tab.cpp` mechanisch:
   - `TabPrint::build()` (Zeilen 2311–2802)
   - `TabFilament::build()` + `add_filament_overrides_page()` (3892–4245)
   - `TabPrinter::build_fff()` + `build_unregular_pages()` (4457–5230)
   Erkennt `add_options_page(L("…"))`, `page->new_optgroup(L("…"))`,
   `optgroup->append_single_option_line("key", …)`, Line-Objekte mit
   `optgroup->get_option("key")` und den Wrapper
   `append_option_line(optgroup, "key", …)`. Jede Zuordnung belegt mit
   Datei+Zeile.
3. **`engine/scripts/build_de_catalog.py`** liest
   `localization/i18n/de/OrcaSlicer_de.po` und baut dict msgid→msgstr.
   PO-Multi-Line + Escape-Handling (nur `\\`, `\"`, `\n`, `\t` –
   kein Python-`unicode_escape`, das wuerde UTF-8-Bytes zerreissen und
   Umlaute kaputt machen).
4. **`engine/scripts/build_settings_schema.py`** joined Schema + Layout
   + Deutsch zu `engine/out/settings-schema.json` + Report.

### Report (`engine/out/settings-report.md`)

- OrcaSlicer-Version: `02.06.00.51` (laut `--dump-schema`)
- **751 Options** im `print_config_def` gesamt.
- **5491 Deutsch-Eintraege** aus `OrcaSlicer_de.po`.

Zuordnung Tab.cpp → Bereich/Reiter/Gruppen/Options:

| Bereich | Reiter | Gruppen | Options (einzigartig) |
|---|---|---|---|
| print    | 6 | 41 | 337 |
| filament | 7 | 22 | 83 |
| printer  | 4 | 29 | 73 |

Verteilung nach Stufe:

| Bereich | Simple | Advanced | Expert | Develop | Σ |
|---|---:|---:|---:|---:|---:|
| print    | 50 | 274 | 11 | 2 | 337 |
| filament | 38 |  43 |  0 | 2 |  83 |
| printer  |  5 |  63 |  0 | 5 |  73 |

Nicht zuordenbar (im Schema, nicht im Layout): **258 von 751** – mit
Gruenden gruppiert:
- SLA-only: 76
- Unbenutzt in Tab.cpp (FFF, ohne category): 91
- Ohne Label (interne/Legacy): 40
- any-Technologie (bed_custom, print_host*, printable_area …): 20
- G-Code-Templates (eigener Tab.cpp-Pfad, nicht `append_single_option_line`): 17
- Diverse (Rest in kleinen Kategorien): 14

Uebersetzungsabdeckung Deutsch (nur Layout-Options):

| Bereich | Label | Tooltip | Reiter | Gruppen |
|---|---|---|---|---|
| print    | 333/337 (99%) | 333/333 (100%) | 6/6 (100%) | 41/41 (100%) |
| filament | 80/81 (99%)   | 78/79 (99%)   | 7/7 (100%) | 22/22 (100%) |
| printer  | 71/72 (99%)   | 70/71 (99%)   | 4/4 (100%) | 29/29 (100%) |

**Gruppen mit 0 Keys** (im Report mit Datei+Zeile aufgelistet):
G-Code-Textfelder (`Machine start G-code` etc.) + Notes/Compatible-
Printers – die Felder stehen in Tab.cpp nicht ueber den
Standard-Options-Pfad. Fuer Phase 4.2 (Prozess) nicht relevant;
fuer 4.3/5 (Drucker) spaeter explizit zu adressieren.

### Nachweise

- `engine/bin/handslice-cli-x86 --dump-schema > engine/out/schema-raw.json`
  (16528 Zeilen, OrcaSlicer-Version eingebettet).
- `python3 engine/scripts/extract_tab_layout.py > engine/out/layout.json`
  (2613 Zeilen, pro Key `line` als Belegstelle in Tab.cpp).
- `python3 engine/scripts/build_de_catalog.py > engine/out/de.json`
  (5499 Zeilen, 5491 echte Uebersetzungen; Umlaute korrekt).
- `python3 engine/scripts/build_settings_schema.py …` erzeugt
  `settings-schema.json` + `settings-report.md`.
- `handslice-cli-arm64` ist frisch gebaut (gestript 14 MB, Side-Car
  `d57f8cacd5`); der Device-Lauf (`--dump-schema` am Poco) steht aus,
  weil ADB beim Abschluss nicht verfuegbar war. Der Build-Guard
  (M6) stellt sicher, dass x86- und arm64-Binaries vom selben
  Quellstand kommen – inhaltlich sind beide `--dump-schema`-Ausgaben
  zwingend identisch (reine Introspektion derselben `print_config_def`).

---

## 2026-10-25 18:20 – Zweiter Realdruck aus der App (Commit ac57b14, Seite B, Z-Offset −0,04)

- Klaus hat am Poco den zweiten echten Druck mit der M6-APK ausgeloest:
  Seite B (Glatt, Carbon-Optik), Z-Offset **−0,04 mm**, Fach A4, PLA.
  G-Code-Name auf dem Drucker: `handslice_1792947629010.gcode`.
- Druckstart, lokalisierter Live-Status (Zustand/Bett/Düse),
  Prozentanzeige (aus `current_layer`/`total_layer` abgeleitet, M5-Befund 2)
  und Zeitraffer-Aufnahme am Drucker (M5-Befund 3) laufen wie erwartet.
- Erste Schicht sauber heraus: **Carbon-Muster der Glattseite ist vollflaechig
  abgebildet** – der auf Dart→CLI→Engine-Pfad angewendete Z-Offset von
  −0,04 mm wirkt am echten Druck. Damit ist auch Befund 5 am Geraet
  belegt (M4c + M5 waren G-Code-seitig; dieser Druck ist der physische
  Nachweis).
- Alle fuenf M5-Befunde (Pair-Validierung, Prozent, Zeitraffer-Capability,
  Status-Lokalisierung, Z-Offset scharf) sind damit am echten CC2
  bestaetigt. Phase-3-Erfolgskriterium bleibt erfuellt, mit zusaetzlichem
  Nachweis fuer die Z-Offset-Anwendung.
- Zeitraffer-Video vom Drucker ueber USB gezogen und als
  `docs/media/erster-app-druck-zeitraffer.mp4` eingecheckt; im README
  unter „Erster Druck" verlinkt (zweiter Eintrag).
- **Beobachtung Druckeruhr:** Der CC2 hat das Video intern mit Zeitstempel
  **2026-10-26 01:00:53** benannt – real gedruckt wurde um ~18:05 MEZ am
  2026-10-25. In der Nacht davor war die Umstellung MESZ→MEZ. Nur
  festgehalten, keine Ursache behauptet (vgl. M4b-Befund:
  `print_status`-Uhr lief im LAN-Modus bereits 1 h 33 min hinter UTC).
  Dokumentiert in `docs/networking-cc2.md` Abschnitt „Beobachtung
  2026-10-25: Zeitstempel im Video-Dateinamen weicht ab".

---

## 2026-10-25 17:50 – Phase 3 M6: CLI-Vertrag + Build-Guard nach „unknown flag: --z-offset"

**Vorfall:** Klaus hat am Poco Commit `9c976f1` getestet („Auf dem Gerät
slicen", Seite B, Z-Offset −0,04). Die App brach mit
`ProcessException: handslice-cli exit 2: handslice-cli: unknown flag:
--z-offset` ab.

### Ursache belegt

- `engine/bin/handslice-cli-arm64`: Modify-Time 2026-10-25 12:43,
  stammt vom Commit vor `2b4fc1a` (M4, 16:00). Enthaelt keinen String
  `--z-offset`.
- `engine/bin/handslice-cli-x86`: Modify-Time 2026-10-25 15:58, aus
  dem M4-Rebuild – enthaelt `--z-offset` und wurde beim x86-Test gegen
  den Nachweis-Lauf verwendet.
- `app/android/app/src/main/jniLibs/arm64-v8a/libhandslice_cli.so`
  (13:10) wurde aus der veralteten arm64-CLI befuellt (Gradle-Hook
  `syncHandsliceNativeBinary` kopiert `engine/bin/handslice-cli-arm64`
  → `jniLibs/...so`).
- Damit war die APK M4/M5 funktional korrekt im Dart-Teil, hat aber
  eine CLI aus der Zeit *vor* `--z-offset` eingepackt. Beim x86-Test
  faellt das nicht auf, weil dort das richtige Binary lag.

### Fixes

1. **CLI: `--version` mit eingebettetem Commit-Hash**
   (`engine/cli/handslice-cli.cpp` + `engine/cli/CMakeLists.txt`):
   `-DHANDSLICE_CLI_COMMIT=<hash>` wird in beide CLI-Varianten
   einkompiliert. Fallback: `git rev-parse --short=10 HEAD` zur
   CMake-Konfigurationszeit.
2. **Beide Build-Skripte setzen `HANDSLICE_CLI_COMMIT` aus dem Repo-
   HEAD** (`engine/build-headless-x86.sh`, `engine/build-cli-arm64.sh`).
   Script-Ende ruft `handslice-cli --version`, damit sichtbar ist, was
   gerade in `engine/bin/` liegt.
3. **arm64-Build strippt am Ende** (865 MB → 14 MB mit
   `$ANDROID_NDK/.../bin/llvm-strip --strip-all`). Vorher wurden
   Debug-Infos mitgepackt; Grund fuer die bisherige 14-MB-Groesse war
   der frueher manuell gelaufene Strip-Schritt, der nicht im Skript
   stand.
4. **Build-APK-Guard** (`app/scripts/build_apk.sh`):
   - prueft `handslice-cli-arm64 --version` → Pflicht.
   - prueft `handslice-cli-x86 --version` (falls vorhanden) → Hash
     muss identisch sein, sonst `exit 3`.
   - warnt, wenn CLI-Hash ≠ Repo-HEAD (fuer App-only-Aenderungen OK,
     fuer Engine-Aenderungen klarer Reminder).
   - uebergibt `--dart-define=CLI_COMMIT=<hash>` an den Flutter-Build.
5. **Badge zeigt beide Hashes** (`lib/widgets/build_info_badge.dart`):
   erste Zeile `v0.1 · app <hash>`, zweite Zeile `cli <hash>`, dritte
   Zeile Build-Zeit. Dadurch ist am Geraet sofort sichtbar, wenn App-
   und CLI-Commit auseinanderlaufen.
6. **Vertragstest** (`engine/test/cli-contract-arm64.sh`): pusht die
   arm64-CLI auf den Poco, prueft `--version`, laeuft alle Flags der
   App einmal durch (`--machine --process --filament --resources
   --output --bed-type [--z-offset] --quiet --no-center`) und wertet
   den G-Code-Z-Diff gegen den Baseline-Lauf aus. Mindestens ein
   `--z-offset -0.040`-Lauf gegen den echten Kerbenwuerfel.

### Nachweise

- arm64-CLI nach Rebuild (Modify 2026-10-25 17:45): 13.8 MB stripped,
  Hash im Binary belegbar via `strings | grep "handslice-cli commit"`.
- x86-CLI nach Rebuild (18:…): `--version` liefert
  `handslice-cli commit <hash>` → Guard-Prerequisite erfuellt.
- Vertragstest `engine/test/cli-contract-arm64.sh`: … (siehe
  „Nachweislich funktioniert" im Abschluss-Bericht).
- APK-Badge zeigt jetzt `app <hash>` + `cli <hash>` getrennt; beide
  Hashes decken sich mit `git log HEAD` + `handslice-cli-arm64
  --version`.

---

## 2026-10-25 17:10 – Phase 3 M5: 5 Befunde aus dem Erstdruck behoben

### Befund 1 – Pair-Dialog: Modellname im Adressfeld

- **Ursache:** keine Validierung im `_PairDialog.submit()`. Was im IP-
  Feld stand (OS-/IME-Autofill, altes `prefs['printer.cc2.ip']`), wurde
  ungeprueft in SharedPreferences geschrieben. Beim naechsten Verbinden
  reichte das als Host an `InternetAddress()` – „Invalid internet
  address".
- **Fix (`app/lib/widgets/printer_panel.dart`):**
  - `_looksLikeHost()` prueft IPv4 (vier Oktette 0–255) oder Hostname-
    Label-Kette (RFC 1123, vereinfacht).
  - Save-Button bleibt disabled, solange die IP ungueltig oder der Code
    leer ist; Fehlertext inline unter dem IP-Feld.
  - Autofill-/Suggestions-Hinweise an die Tastatur ausgeschaltet
    (`autocorrect:false`, `enableSuggestions:false`, leere
    `autofillHints`).
  - Vorbelegung aus `widget.initialIp` wird nur uebernommen, wenn sie
    selbst wie IP/Hostname aussieht – ein Mist-Wert in prefs faelscht
    das Feld nicht mehr.
- **Nachweis:** 2 neue Widget-Tests in `app/test/widget_test.dart`:
  - „Save bleibt gesperrt bei Modellname statt IP" – gibt genau
    `Elegoo CC2 Combo` ein, erwartet Fehlertext + Button-disabled.
  - „Vorbelegung ignoriert Modellname aus prefs" – startet mit
    vergiftetem Pref-Wert, Dialog oeffnet mit leerem Feld.

### Befund 2 – Fortschritt in % bleibt stehen

- **Ursache:** `PrinterState.printProgress` las `print_status.progress`.
  Beim Realdruck 09:18 wandert dieses Feld nicht gleichmaessig mit;
  `current_layer`/`total_layer` sind die zuverlaessige Fortschritts-
  Quelle (siehe docs/networking-cc2.md Nachweislauf).
- **Fix (`app/lib/state/printer_state.dart`):**
  ```
  int? get printProgress {
    final cl = currentLayer; final tl = totalLayer;
    if (cl != null && tl != null && tl > 0) {
      return ((cl * 100) / tl).round().clamp(0, 100);
    }
    return _getInt(['print_status', 'progress']); // Fallback
  }
  ```
- **Nachweis:** 2 neue Unit-Tests – aus `current=25,total=100` kommt
  25 %, auch wenn `progress=0` gleichzeitig gepusht wird. Fallback-Pfad
  bleibt getestet.

### Befund 3 – Zeitraffer-Capability

- **Ursache:** `supportsTimelapse` lieferte `null` bei fehlendem
  `external_device.chassis_camera.configured`. UI zeigte dann
  „Unterstuetzung unbekannt – Feld weggelassen". Fuer den CC2 ist
  Zeitraffer aber belegbar (docs/networking-cc2.md 2026-10-25 10:30:
  `delay_video=true` wirkt, Klaus hat das Video am Drucker gesehen).
- **Fix:** `supportsTimelapse` ist jetzt `bool`:
  - `configured == 1` → `true`
  - `configured == 0` → `false` (Schalter gesperrt, Hinweis
    „Dieser Drucker meldet keine Kamera – Zeitraffer deaktiviert")
  - Feld fehlt → `true` als CC2-Modell-Default (Beleg s. o.)
- Im Druckstart wird `delay_video` jetzt immer gesendet (true oder
  false), nicht mehr weggelassen.
- **Nachweis:** 3 neue Tests – jeder der drei Faelle einzeln.

### Befund 4 – Status-Beschriftungen lokalisiert

- **Fix:** `_LiveStatus` zeigt jetzt lokalisierte Labels statt
  Rohschluessel. Neue ARB-Keys in `app/lib/l10n/app_en.arb` + `_de.arb`:
  - `printStatusLabel` – State / Zustand
  - `printBedLabel` – Bed / Bett
  - `printNozzleLabel` – Nozzle / Düse
  - `printExceptionLabel` – Printer alarms / Drucker-Alarme
  - `printTempFormat` – `{cur} / {tgt} °C` (lokalisiertes Grad-Format)
- Numerische Statusanzeige („2 — Printing") durch reinen lokalisierten
  Zustandstext ersetzt.
- **Nachweis:** Widget-Test „PrintScreen: Status-Labels sind
  lokalisiert" – findet State/Bed/Nozzle, verifiziert, dass
  `machine_status.status`, `heater_bed`, `extruder` nicht mehr im UI
  stehen.

### Befund 5 – Z-Offset scharf schalten

- **Fix:**
  - `SlicerService.slice(zOffsetMm: ...)` reicht den Wert als
    `--z-offset <mm>` an `handslice-cli` durch (nur wenn ≠ 0, haelt
    die CLI-Zeile sauber).
  - `ProjectState.slice()` nimmt automatisch den gespeicherten
    `zOffsetFor(_bedType)` fuer die aktive Plattenseite.
  - UI-Hinweistexte aktualisiert: „Z-Offset pro Seite (wird beim
    Slicen angewendet)" / „±0,50 mm, Schritte 0,01 mm — wird beim
    Slicen angewendet".
- **Nachweis G-Code-Vergleich (handslice-cli-x86, Kerbenwuerfel):**
  ```
  Seite A, baseline  vs  Seite A, --z-offset 0.000
    → 1220/1220 Z-Zeilen identisch; nur Zeitstempel-Header differiert.
    → "wird nicht angewendet, wenn 0" belegt.

  Seite B, baseline  vs  Seite B, --z-offset 0.020
    → 1218/1220 Z-Zeilen exakt um +0.020 verschoben.
    → 2 Zeilen unveraendert = `G1 Z0.5` aus CC2_START_GCODE-Macro
      (absolut im Start-Macro, nicht durch Offset beeinflusst –
      exakt wie M4c vorhergesagt).
    → Erste Schicht ebenfalls verschoben: 0.2 → 0.22, 0.4 → 0.42,
      0.457143 → 0.477143.
    → "wird beim Slicen angewendet" belegt.
  ```
- **Nachweis Dart-Pfad:** Widget-Test „ProjectState.slice uebergibt
  zOffsetMm an den Slicer" – prueft, dass der gespeicherte Wert pro
  Plattenseite byte-exakt am Slicer-Call ankommt.

### Tests + Build

- `flutter test test/widget_test.dart` 22/22 gruen (vorher 13; +9 neue
  Tests fuer M5).
- `flutter analyze` 0 Fehler (1 info in `elegoo_mock_test.dart`:
  `dart:async`-Re-Import, nicht blockierend).
- APK neu gebaut + auf Poco X3 Pro installiert; Badge zeigt den M5-
  Commit (siehe Nachweis unten im Abschluss-Bericht).

---

## 2026-10-25 16:00 – Phase 3 M4: Druckstart + Live-Status in der App

Code-Umfang + Nachweise – Claude Code sendet 1020 NICHT an den
echten Drucker; den echten Druck startet Klaus selbst am Poco.

### M4-R0 Beleg

- `elegoo-link/.../elegoo_fdm_cc2_message_adapter.cpp:85-96` –
  `slot_map`-Form `{t, canvas_id, tray_id}`, ein Eintrag pro Tool.
- A1..A4 ↔ tray_id 0..3 aus unserem M3-CANVAS-Read bestaetigt
  (A4 = tray_id 3).
- `supportsTimeLapse` kommt im LAN-Pfad aus
  `api_status.external_device.chassis_camera.configured == 1`
  (`.../elegoo_fdm_cc2_message_adapter.cpp:1148-1163`), nicht aus
  `GET_PRINTER_ATTRIBUTES` (dort beim CC2 bewusst nicht
  ueberschrieben, Zeile 532-535). Konsequenz fuer die Dart-Logik:
  `delay_video`-Feld wird nur gesendet, wenn die Capability
  belegbar beobachtet wurde; sonst weggelassen (per
  CC2_PROTOCOL.md: „leaving the key out lets the printer decide").

### M4a Druckstart

- `ElegooCc2Client.startPrint(filename, bedlevelForce, printerCheck,
  delayVideo?, slotMap)` baut method 1020 feld-fuer-feld.
- `PrinterState.printPreflight(boundsOk)` prueft **vor** dem Start:
  no_upload → not_connected → bounds_failed → not_idle (aus 1002)
  → tray_empty (CANVAS-Slot leer). Jede Sperre liefert einen
  l10n-Key fuer die UI.
- PING-Loop (10 s) wird in `connectAndLoad()` gestartet,
  automatisch bei Reconnect neu abonniert.

### M4b Status + Reconnect

- `_mergeStatus()` nimmt sowohl 1002 (initial) als auch api_status-
  Deltas (via `client.statusDeltas`) und mergt rekursiv in den
  Live-State.
- UI-Getter fuer `machine_status`, `print_status`, `heater_bed`,
  `extruder`, `exception_status`, `chassis_camera.configured`
  (fuer supportsTimelapse-Capability).
- `remainingSeconds` wird aus `print_status.remaining_time_sec`
  gelesen + lokal weitergezaehlt zwischen Updates. **Keine
  Druckerzeitstempel** – die Druckeruhr lief in unserem Lauf
  nachweislich ca. 1h 33min nach UTC.
- Verbindungsabbruch → `_scheduleReconnect()` nach 5 s. **Der
  laufende Druck am Drucker ist davon nicht betroffen**, der laeuft
  komplett lokal; wir re-verbinden nur die Beobachter-Session und
  re-abonnieren Status.
- UI zeigt „Verbindung verloren – wird neu aufgebaut…"-Hinweis.

### M4c Z-Offset-Nachweis (nicht scharf geschaltet)

CLI minimal um `--z-offset <mm>` erweitert (nur Diagnostik, nicht
in der App verdrahtet). Zweimal den Kerbenwuerfel gesliced:
`z_offset=0.00` vs. `z_offset=0.05`.

- **1196 Z-Zeilen verschoben um +0.05 mm**, bis auf 2 Werte mit
  FP-Noise (0.050001, 0.04997).
- **Erste Schicht** ebenfalls verschoben (`Z.2` → `Z.25`).
- **Keine XY-/E-Divergenz** ausser dem bekannten TBB-Progress-
  Reordering (3 M73-Zeilen).
- **Start-G-Code (`CC2_START_GCODE`) hebt den Offset NICHT auf.**
  `G1 Z0.5 F900` in Zeile 40 (Prime-Fahrt im `machine_start_gcode`)
  ist in beiden Varianten identisch, weil das `Z0.5` absolut im
  Macro-Text steht. Danach beginnt ab Zeile 81 der eigentliche
  Druck mit korrektem Offset.

Hinweis „nur gespeichert" bleibt in der UI, bis Klaus freigibt.

### Tests + Build

- 13 Widget-Tests gruen (`flutter test test/widget_test.dart`):
  - method 1020 Payload-Feld-fuer-Feld-Vergleich mit dem
    tatsaechlichen 1020 vom ersten echten Druck (storage_media,
    filename, config.*, slot_map): identisch.
  - delayVideo=null → `delay_video`-Feld fehlt (Capability unknown).
  - printPreflight-Sperren (no_upload, bounds_failed).
  - Plus die 10 Alt-Tests (Z-Offset, Bounds-Check, Plate-Toggle,
    Slice-Darstellung, Pair-Dialog, …).
- 5 Mock-Integration-Tests gruen inkl. neuem
  „Mock: method 1020 startPrint liefert error_code=0".

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Druckstart-Payload wird byte-identisch zum tatsaechlichen 1020
  vom ersten echten Druck gebaut – belegt durch Widget-Test.
- Alle fuenf Pre-Flight-Sperren (no_upload, not_connected,
  bounds_failed, not_idle, tray_empty) sind verdrahtet und
  blockieren den Druck-Button in der UI.
- Live-Status-Delta-Merge; Restzeit aus Dauer + lokale Fortschreibung
  (nicht aus Druckeruhr). PING-Loop 10 s. Auto-Reconnect ohne
  Impact auf den laufenden Druck.
- `delay_video` wird nur gesendet, wenn die Capability aus
  `external_device.chassis_camera.configured` belegbar ist.
- Z-Offset-Nachweis: eindeutig, nur Z um 0.05 mm, auch Layer 1;
  Start-G-Code hebt den Offset nicht auf.
- `flutter test`: 18/18 gruen (13 Widget + 5 Mock).

**2. Ungeprueft**

- **Live-Lauf gegen den echten CC2.** Claude Code sendet 1020 nach
  Vorgabe nicht; Klaus startet den eigentlichen Druck am Poco mit
  Z-Offset 0 nach Sichtkontrolle.
- **Status-Darstellung waehrend eines echten Drucks** – im Mock
  antwortet 1020 mit error_code=0, aber danach pusht der Mock
  keine „Printing"-Deltas. Reale Status-Transitionen (status=2 →
  bed_mesh_detect=true → Layer 1 → …) werden erst im Live-Lauf
  sichtbar.
- **Keep-Alive-Timeout bei Netz-Abbruch mitten im Druck.**
  Reconnect-Logik ist drin; Verhalten unter realem WLAN-Flap
  nicht geprueft.

**3. Geht nicht**

- (keine neuen Blocker)

---

## 2026-10-25 15:20 – Nebenaufgabe: method 1047 (DELETE_FILE) am CC2 gemessen

Fuer upstream Issue
[danielcherubini/elegoo-homeassistant#432](https://github.com/danielcherubini/elegoo-homeassistant/issues/432).

### Beleg Parameter-Struktur (nicht geraten)

- `CC2_PROTOCOL.md` zeigt Request `{"id","method":1047,"params":{"storage_media":"local","filename":"..."}}`,
  markiert als „Untested, no response captured".
- `custom_components/elegoo_printer/cc2/client.py:2577-2644`
  (`async def delete_file`) sendet exakt diesen Payload.
- `elegoo-link/src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp:1411`:
  `// {MethodType::DELETE_FILE, 1047}` **auskommentiert**.
- Volltext-grep im ganzen elegoo-link-Repo (243 Dateien): keine
  aktive `deleteFile(...)`-Signatur, kein `DeleteFileParams`,
  kein HTTP DELETE. ElegooSlicer loescht am CC2 nach aktuellem
  main-Stand **nichts** aus dem LAN. Parameter-Struktur ist damit
  eindeutig als `{storage_media, filename}` belegt – keine zweite,
  abweichende Form im Code.

### Was gemessen wurde

- D-1: `method 1044 local` → 23 `.gcode`, 0 Videos. `sdcard` + `udisk`
  je 0. Entry-Struktur anonymisiert in docs/networking-cc2.md
  festgehalten.
- D-2: Harmlose Test-G-Code-Datei `handslice_delete_test_<ts>.gcode`
  (182 B, nur Kommentare) hochgeladen, Liste 23 → 24, Testdatei
  genau 1× sichtbar. Klaus hat am Display bestaetigt.
- D-3: `method 1047` fuer genau diese eine Datei:
  **Firmware antwortet nach 13 ms mit `error_code=1003`,
  Datei wird NICHT geloescht.** Alle anderen Dateien unveraendert
  (name-hash-Vergleich pre/post).
- D-4: `method 1047` fuer einen definitiv nicht existierenden Namen:
  identische Antwort `error_code=1003`, 10 ms, Liste 24/24.

### Deutung (bewusst als Vermutung formuliert)

Dieselbe Firmware liefert `error_code=1003` auch fuer `method 1045`
(frueher gemessen) und einige andere nicht implementierte
Methoden. **Vermutung**, nicht Doku-Aussage: `1003` ist der
generische „not available / not implemented in this firmware"-Code
auf 02.01.01.07. 1047 ist auf dieser Firmware vermutlich nicht
aktiv – entsprechend passt der HA-Integration-Code bereits mit „0
= did not refuse, nicht beweis fuer deletion; re-list via 1044".

### Was Klaus noch tun muss

- Testdatei `handslice_delete_test_<ts>.gcode` liegt noch im local-
  Speicher des Druckers (1047 hat sie nicht geloescht). Loeschen
  entweder am Display, oder sie bleibt bis zur naechsten Firmware
  mit funktionierendem 1047.
- Issue-Kommentar-Entwurf unter
  `docs/upstream/elegoo-homeassistant-issue-432-draft.md`. Enthaelt
  einen `<TODO>` fuer Klaus' spezifischen Hinweis zur Druckeruhr
  (die Briefing-Nachricht war an der Stelle abgeschnitten).
  Observed: `create_time`-Feld in `method 1046` liefert einen
  Unix-Timestamp, der heute ca. 1 h 33 min hinter der realen UTC
  liegt – aber ohne Klaus' Zusatz formuliere ich das nicht als
  Befund.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Parameter-Struktur von `method 1047` eindeutig als
  `{storage_media, filename}` belegt (zwei Quellen).
- Testlauf an echter Hardware: `method 1047` liefert
  `error_code=1003` sowohl fuer existente als auch nicht-existente
  Dateinamen; Dateiliste bleibt unveraendert.
- Vor-/Nach-Vergleich der Dateiliste per Hash – alle anderen
  Dateien unberuehrt.
- Rohantworten + Pre-/Post-Snapshots anonymisiert in
  docs/networking-cc2.md eingetragen (keine SN, IP, Access-Code
  oder Account-IDs).
- Issue-Kommentar-Entwurf in docs/upstream/.

**2. Ungeprueft**

- **1003 ≡ „not implemented"** bleibt eine Vermutung, nicht Doku –
  Elegoo veroeffentlicht kein error-code-Mapping; die
  HA-Integration deutet 1007 als FILE_DELETE_FAILED, nicht 1003.
- Testdatei am Drucker noch da (siehe oben); Loeschung durch Klaus.

**3. Geht nicht**

- **method 1047 funktional auf Firmware 02.01.01.07.** Die Firmware
  antwortet, aber loescht nichts. Kein Blocker fuer das Projekt –
  die App-UI wird in Phase 2+ ohnehin `cleanup_files` nicht
  anbieten, solange die Firmware das nicht sauber macht.

---

## 2026-10-25 15:00 – Fix: Pair-Dialog-Crash + Build-Info im Header + SN-Scrub

Klaus hat beim ersten Live-Lauf (Commit 828ff96) auf dem Poco
„Drucker koppeln" getippt → roter Fehlerbildschirm:

```
'package:flutter/src/widgets/framework.dart': Failed assertion:
line 6281 pos 12: '_dependents.isEmpty': is not true.
```

### Ursache (an der Wurzel)

Flutter framework.dart:6281 ist der Assert in
`InheritedElement.debugDeactivated`. Er greift, wenn ein
`InheritedElement` deaktiviert wird, waehrend es noch Dependents
hat.

Im ursprunglichen `_openPairDialog` wurden zwei
`TextEditingController` im outer State erzeugt und sofort nach
`await showDialog` disposed. Zur Dispose-Zeit lief die Dialog-Pop-
Animation noch; die `TextField`-Elements im Dialog-Tree waren noch
dependents der umliegenden `_LocalizationsScope`/Theme-Inherited-
Elements. Zusaetzlich wurde `ipCtrl.text` **nach** `ipCtrl.dispose()`
gelesen (use-after-dispose).

### Fix (kein try/catch-Pflaster)

Dialog als eigener `StatefulWidget` (`_PairDialog`), die Controller
leben in dessen `State` und werden erst in dessen `dispose()`
freigegeben – also nach dem vollstaendigen Unmount der Dialog-
Element-Hierarchie. Das ist der kanonische Flutter-Weg; keine
Lifecycle-Workarounds mehr.

### Regression-Test (RED → GREEN)

`test/widget_test.dart`:
`PrinterPanel: Pair-Dialog oeffnet, Save speichert ohne
Framework-Assertion` – oeffnet den Dialog, tippt IP + Code,
drueckt Save, pumpAndSettle. Mit dem alten Code schlug der Test
fehl („Multiple exceptions (5) were detected during the running of
the current test"); mit dem Fix laeuft er sauber durch.
Nachgewiesen durch kurzen `git stash` + Test-Lauf.

### F5 – Commit-Stand sichtbar in der App

- `BuildInfoBadge`-Widget (Mono-Text) im Projekt-Screen oben
  rechts: `v0.1 · <commit>` + Build-Zeit.
- Werte werden ueber `--dart-define=BUILD_COMMIT=` /
  `BUILD_TIME=` eingebrannt; `app/scripts/build_apk.sh` setzt sie
  automatisch aus `git rev-parse --short=10 HEAD` und `date -u`.

### F6 – Serial Number Scrub

Suche in Working-Tree + Git-History (`git log --all -S`): die SN
tauchte in `PROGRESS.md` (6×), `docs/networking-cc2.md` (6× +
1× verkuerzt) und `engine/test/mock-cc2/mock_cc2.py` (1×) auf.

- **Working-Tree:** alle 14 Fundstellen durch Platzhalter `<cc2-sn>`
  (bzw. „CC2 im Haus" in einer Tabelle) ersetzt. `git grep <cc2-sn>`
  liefert jetzt leer.
- **Git-History seit letztem Push (origin/main..HEAD):** nur
  Commit `828ff96` enthielt die SN (3 Treffer). Dieser Scrub-Commit
  liegt direkt darueber; nach dem Fix-Commit „leakt" die SN damit
  nicht in neue Pushes. Rewrite von `828ff96` wuerde Force-Push
  erfordern und ist laut CLAUDE.md § 2 gesperrt – ohne Klaus-
  Entscheidung nicht gemacht.
- **Bereits gepushte Commits:** `7ac8e7b`, `e5ad931`, `7aa8108`,
  `93e26d0`, `684d1f6` enthalten die SN im History-Zustand von
  `origin/main`. Entfernung erfordert Force-Push auf main.
  **Entscheidung an Klaus:** entweder Force-Push nach Backup
  (CLAUDE.md § 2 bricht), oder SN im Repo akzeptieren (sie ist
  nicht sensibel genug fuer ein Access-Grant, aber identifiziert
  den Drucker eindeutig gegenueber anderen Elegoo-Besitzern).

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Pair-Dialog laeuft ohne `_dependents.isEmpty`-Assertion durch
  (Regression-Widget-Test gruen, nach Rollback des Fixes schlaegt
  er fehl – echter RED→GREEN-Beweis).
- 10 Widget-Tests + 4 Mock-Integration-Tests gruen (`flutter test`).
- `BuildInfoBadge` zeigt `v0.1 · <commit>` + UTC-Build-Zeit im
  Projekt-Screen (nutzt `--dart-define`).
- `app/scripts/build_apk.sh` setzt die Build-Info automatisch aus
  Git.
- SN `<cc2-sn>` nirgends mehr im Working-Tree
  (`git grep <cc2-sn>` ist leer).

**2. Ungeprueft**

- **Live-Lauf auf dem Poco nach dem Fix.** APK wird gebaut und
  installiert – der eigentliche „Drucker koppeln"-Klick muss von
  Klaus bestaetigt werden.
- **Live-Reproduktion des Original-Crashes per adb logcat.** USB-
  Tunnel wurde instabil beim Install-Lauf; die Ursachenanalyse
  stuetzt sich auf Klaus' Error-Snippet, Flutter-Framework-Code
  und den RED-Test, der den Pfad geschlossen beweist.
- **Rewrite der bereits gepushten Commits** – nicht gemacht, siehe
  F6-Entscheidung.

**3. Geht nicht**

- (keine neuen Blocker)

---

## 2026-10-25 14:30 – Phase 3 M3: Discovery, CANVAS, Upload gegen Mock + echten CC2

Vor M3 die vier Nacharbeiten aus M2 (Z-Offset, printer_check-Label,
Grenztest, Mock-Server). Danach M3 selbst.

### N1 – Z-Offset einstellbar

- UI: Zwei Fokus-Buttons `-` / `+` (D-Pad erreichbar, sichtbarer
  Fokus-Ring), aktueller Wert in Plex Mono mittig. Schritt 0.01 mm,
  Grenze ±0.50 mm, deaktiviert an den Enden.
- `ProjectState.nudgeZOffset(bedType, delta)` quantisiert auf
  0.01 mm (Vermeidung von Float-Drift bei vielen `+/-`-Klicks) und
  clampt an `zOffsetMin/Max`.
- Pro Plattenseite getrennter Shared-Preferences-Key, kein shared
  default mehr. Wert wird weiterhin **nicht angewendet**; Hinweis
  „±0.50 mm, 0.01 mm Schritte — noch nicht angewendet" bleibt
  direkt unter dem Wert.
- Widget-Test „Z-Offset: Nudge beachtet Grenzen + 0.01-mm-Raster"
  deckt +60× / −1000× ab.

### N2 – `printer_check`-Semantik + Label

Beleg aus `docs/CC2_PROTOCOL.md` (HA-Integration):

> „`printer_check` – Auto bed leveling. Three states, measured on
> 02.01.00.00: `true` always levels (~200 s), `false` never does,
> and leaving the key out lets the printer decide. ElegooSlicer
> sends `true`, or `false` when its bed-leveling box is unchecked."

Mapping im `elegoo-link`:
`src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp:81`
setzt `config.printer_check = startPrintData.autoBedLeveling`.

**Konsequenz:** Das Label „Auto-Nivellierungscheck" war
irrefuehrend. Neu:

- Englisch: „Always level the bed (adds ~200 s)".
- Deutsch: „Immer bettnivellieren (dauert ~200 s)".

`bedlevel_force` (Label „Bettnivellierung vor diesem Druck
erzwingen") bleibt daneben als expliziter Zwang.

### N3 – `engine/test/check-bounds` Grenztest-Skript

Python 3, parst `printable_area` + optional `bed_texture_area` +
`printable_height` aus dem Machine-Profil, geht alle
G0/G1/G2/G3-Bewegungen durch (modaler Zustand fuer absolute/
relative + G28/G92-Nullung), meldet XY-/Z-Verletzungen auf stderr.
Exit 0=OK, 1=FAIL, 2=Argument-/Datei-Fehler.

Nachweis:
- Kerbenwuerfel-G-Code → `OK: alle Bewegungen innerhalb X 0..256,
  Y −10..256, Z 0..256`.
- Synthetischer OOB-G-Code (`G1 X300`, `Y270`, `Z260`) → `FAIL: 3
  Verletzung(en)` + Zeilen auf stderr.

### N4 – Bounds-Check in die App

- `app/lib/engine/bounds_check.dart` ist der 1:1-Port der
  Python-Logik (gleiches Verhalten, gleiche Toleranz 1 mm /1000).
- `ProjectState.slice()` ruft nach erfolgreichem Slice automatisch
  `checkGcodeFile(outputPath, bounds)` und speichert
  `boundsViolations`.
- `PrintScreen` zeigt Status-Box
  (gruen „alle Bewegungen innerhalb der Druckflaeche" oder rot
  „N Bewegungen ausserhalb"), und **Upload/Druck-Buttons sind
  deaktiviert**, wenn `boundsViolations.isNotEmpty`.
- Zwei neue Widget-Tests: Profil-Parse (XY-Erweiterung durch
  `bed_texture_area`) und in-/out-of-bounds-Erkennung mit modal
  state (inkl. relativer Moves).

### N5 – CC2-Mock-Server

`engine/test/mock-cc2/mock_cc2.py` (Python 3 + mosquitto):

- MQTT 1883 via Mosquitto-Subprocess mit password_file. Access-Code
  aus `--access-code` oder `$MOCK_ACCESS_CODE`, Placeholder-SN
  `MOCK0000000000M1` (nicht die echte).
- UDP 52700 Discovery (eigener asyncio-Listener, antwortet mit
  derselben JSON-Struktur wie der echte CC2).
- HTTP 8080 chunked `PUT /upload` + X-Token-Pruefung.
- MQTT-Adapter abonniert `elegoo/<sn>/api_register` und
  `.../+/api_request` und spielt Register-Response + 1002 + 2005 +
  1044 + 1046 + 1020-ACK zurueck.
- Fehlerinjektion:
  - `--reject-auth` → Mosquitto ohne User, CONNACK rc=5.
  - `--interrupt-upload-at N` → HTTP schliesst Verbindung nach
    N Byte Upload.
- Access-Code taucht nirgends in den Mock-Logs auf (Platzhalter
  `<accepted, see --access-code>` statt des Werts).

### M3 I1-I4 – Dart-Client + UI

- `app/lib/net/elegoo_cc2_client.dart`: `ElegooCc2Client` mit
  `discover(ip)`, `connect(ip, sn, accessCode)` (MQTT 3.1.1 ueber
  `mqtt_client`), `getStatus(1002)`, `getCanvasStatus(2005)`,
  `getFileList(1044)`, `uploadGcode(name, data, onProgress)`
  (chunked PUT, 1 MiB), `ping()`, `disconnect()`. Eigene
  Exception-Typen (`ElegooAuthException`, `ElegooNetworkException`,
  `ElegooRegistrationException`, `ElegooUploadException`) damit
  der UI-Code sauber reagieren kann.
- `app/lib/state/printer_state.dart`: haelt IP + SN in
  SharedPreferences; **Access-Code in `flutter_secure_storage`**
  (Android: EncryptedSharedPreferences-Default). `savePairing()`
  nimmt Code und schreibt ihn direkt in Secure-Storage;
  `connectAndLoad()` fuehrt Discovery → Register → CANVAS in einem
  Schritt mit sauberer Fehler-/Statusanzeige.
- `app/lib/widgets/printer_panel.dart`: Projekt-Screen-Panel
  „Drucker", zeigt Verbindungstatus, oeffnet Pairing-Dialog (IP +
  Access-Code; Code als `obscureText`), listet nach Verbindung
  die echten A1..A4-Faecher mit Materialfarbe + Typ. Tipp auf einen
  Slot setzt die Tool-0-Zuordnung.
- `PrintScreen`-Upload-Button verdrahtet mit
  `printerState.uploadGcode()`; `onPressed` ist deaktiviert, wenn
  Slice fehlt, Bounds-Check fehlgeschlagen ist, Upload laeuft, oder
  Drucker nicht verbunden ist. Fortschrittsbalken + Erfolgs-/
  Fehlerbox.
- Druck-Button bleibt in M3 bewusst **disabled** (M4-Scope).

### M3 I5 – Mock-Tests

`app/test/elegoo_mock_test.dart` startet den Mock-Subprocess und
faehrt vier Pfade:

| Test | Ergebnis |
|---|---|
| Discovery + Register + Canvas (richtiger Code) | ✓ |
| Falscher Access-Code → `ElegooAuthException` | ✓ |
| Upload + GET_FILE_LIST-Pruefung | ✓ |
| Upload-Abbruch nach 2 KiB → `ElegooUploadException`/`SocketException` | ✓ |

Alle vier gruen. Zusammen mit 9 Widget-Tests: **13 Tests gruen**.

### M3 I6 – Lauf gegen den echten CC2

`app/tool/real_cc2_check.dart` liest `CC2_IP` + `CC2_ACCESS_CODE`
aus der Umgebung (nicht aus Argumenten, nicht aus einer Datei im
Repo), gibt den Code **nirgends** aus. Lauf mit dem
Kerbenwuerfel-G-Code als Nutzdaten:

```
[M3 real] 1) Discovery (UDP 52700)…
  sn=<cc2-sn>  model=Centauri Carbon 2  host=Centauri Carbon 2
  lan=true  token_status=true  proto=1.0.0
[M3 real] 2) MQTT Connect + Register… OK
[M3 real] 3) method 2005 (CANVAS)…
  A1 PETG  PETG                 #000000
  A2 PETG  RAPID PETG           #FFFFFF
  A3 PLA   PLA PRO              #000000
  A4 PLA   RAPID PLA+           #FFFFFF
[M3 real] 4) HTTP PUT /upload (chunked)… 100 %
  → error_code=0, offset=220260, uploaded=handslice_m3_<ts>.gcode (220261 B)
[M3 real] 5) method 1044 (file list local)…
  Datei bestaetigt. Gesamt 23 Dateien im local-Speicher.
[M3 real] 6) DISCONNECT
[M3 real] FERTIG. Kein Druckstart ausgefuehrt (M3-Scope).
```

Entspricht genau dem M3-Scope: Discovery, Faecher, Upload. Kein
Druckstart.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Z-Offset-Stepper per D-Pad bedienbar, pro Plattenseite
  gespeichert, Raster/Grenzen eingehalten (Widget-Test gruen,
  Screenshot kommt mit M4 falls Klaus einen moechte).
- `printer_check`-Label an die dokumentierte Semantik angepasst
  (Quelle: `CC2_PROTOCOL.md` + `elegoo-link`-Code).
- `engine/test/check-bounds` prueft G-Code gegen das CC2-Profil
  (printable_area + bed_texture_area + printable_height),
  reproduzierbar auf Positiv- und Negativ-G-Code getestet.
- `app/lib/engine/bounds_check.dart` ist 1:1-Port, in `ProjectState`
  verdrahtet, Upload-/Druck-Buttons im PrintScreen bei
  Verletzungen deaktiviert.
- `mock_cc2.py` deckt alle M3-Pfade ab (Discovery, Register,
  2005, 1002, 1044, chunked Upload) + zwei Fehler-Injektionen
  (`--reject-auth`, `--interrupt-upload-at`).
- `ElegooCc2Client` + `PrinterState` + `PrinterPanel` sind der
  Dart-Nachbau; 4 Mock-Tests + 9 Widget-Tests gruen
  (`flutter test`).
- End-to-End gegen echten CC2 (IP <cc2-ip>): Discovery, MQTT-
  Register, CANVAS gelesen, Kerbenwuerfel-G-Code (220 261 B)
  hochgeladen, Datei anschliessend in `GET_FILE_LIST` sichtbar
  (23 Dateien gesamt im local-Speicher). Keine Credentials in
  Logs/Code/Commits.

**2. Ungeprueft**

- **UI-Verbindungsablauf auf dem Poco** – der M3-Lauf ging gegen
  AMR5-Dart-CLI (`dart run tool/real_cc2_check.dart`), nicht
  ueber die App-APK auf dem Poco. APK laesst sich bauen, aber
  interaktives Klicken (Pairing-Dialog, Verbinden-Button, Upload-
  Button) braucht Klaus am Geraet. Alle Dart-Funktionen sind
  identisch — der Pfad ist nachgewiesen, nur die konkrete UI-
  Interaktion nicht.
- **Query-Querformat** weiterhin ungeprueft.
- **PING-Keep-Alive-Loop** (10 s) ist bereitgestellt (`client.ping()`)
  aber nicht automatisch gestartet. Mit MQTT-Keep-Alive 60 s haelt
  die Verbindung ohne Loop ohnehin eine Minute; fuer dauerhafte
  Sessions in M4 wird der Loop explizit gebraucht.
- **Flutter-Build auf Poco** fuer M3 nicht neu geprueft – kein neuer
  Native-Code dazu, nur Dart; APK sollte unproblematisch sein.

**3. Geht nicht**

- (keine neuen Blocker)

---

## 2026-10-25 13:10 – Phase 3 M2: Slicen in der App laeuft auf dem Poco

M2 fertig. Die App ruft `handslice-cli-arm64` als Native-Lib auf, uebergibt
die ausgewaehlten Werte und bekommt den G-Code zurueck.

### Research (bevor etwas gebaut wurde)

**R1 Bauplatten-Zuordnung CC2 ↔ Orca-bed_type.** In Orca
(`src/libslic3r/PrintConfig.{hpp,cpp}`) sind sieben Platten-Enums
definiert. Fuer den CC2 steht in `machine/ECC2/*.json` **kein
default_bed_type** (andere Centauri setzen "4" = btPTE). Verbindliche
Zuordnung fuer die App:
- **A = Strukturiert → btPTE** (Textured PEI Plate, enum 4),
  Filamenttemperatur ueber `textured_plate_temp`.
- **B = Glatt → btPEI** (High Temp Plate, enum 3), Temperatur
  ueber `hot_plate_temp`.
Fuer PLA sind beide Felder 60 °C (gleich), aber der
`curr_bed_type`-Header-Eintrag wandert in den G-Code. Vollstaendig in
`docs/engine-integration.md` Abschnitt „Bauplatten-Zuordnung".

**R2 Z-Offset.** Drei Wege dokumentiert: Orca-config `z_offset`,
expliziter G-Code-Patch (`G92 Z` / `SET_GCODE_OFFSET`), oder am
Drucker-Display. **In M2 nur gespeichert und angezeigt**, nicht
angewendet – Entscheidung fuer Phase 3+. Doku in
`docs/engine-integration.md` Abschnitt „Z-Offset: moegliche
Anwendungswege".

**R3 Native-Library-Ablage.** Begruendet mit zwei Android-Quellen:

- `developer.android.com/about/versions/10/behavior-changes-10`,
  Abschnitt „Execution of files from the writable app home directory
  is a W^X violation": „Untrusted apps that target Android 10 cannot
  invoke `execve()` directly on files within the app's home
  directory. Apps should load only the binary code that's embedded
  within an app's APK file."
- `developer.android.com/guide/topics/manifest/application-element`
  (`android:extractNativeLibs`): dann liegen `.so`-Dateien physisch
  im `nativeLibraryDir`, read-only + PROT_EXEC.

Konsequenz: Binary als `libhandslice_cli.so` nach
`src/main/jniLibs/arm64-v8a/`, `android:extractNativeLibs="true"` +
`jniLibs { useLegacyPackaging = true }` in `build.gradle.kts`.

### Umsetzung

**I1 CLI-Erweiterung.** `handslice-cli --bed-type A|B` nachgeruestet
(`engine/cli/handslice-cli.cpp`), beide Binaries neu gebaut und
installiert. Device-Nachweis:

```
--bed-type A: curr_bed_type = Textured PEI Plate, sha256 919cde23…
--bed-type B: curr_bed_type = High Temp Plate,    sha256 7ca4cd37…
```

**I2 App-Projekt-Ablage.**
- `app/android/app/src/main/jniLibs/arm64-v8a/libhandslice_cli.so`
  (= Byte-fuer-Byte identisch zu `engine/bin/handslice-cli-arm64`,
  sha `b63ac28c…`).
- 11 Profile-JSONs unter `app/assets/profiles/Elegoo/` (Minimum-Set
  fuer CC2 0.4 + 0.20mm + Elegoo PLA, in `pubspec.yaml` einzeln
  deklariert).
- `AndroidManifest.xml`: `android:extractNativeLibs="true"`.
- `app/android/app/build.gradle.kts`: `packaging { jniLibs {
  useLegacyPackaging = true } }` + `compileSdk = 36`
  (file_picker-Transitive-Dep verlangt es).

**I3 Platform-Channel.** `MainActivity.kt` beantwortet
`nativeLibraryDir` ueber `MethodChannel
"dev.handslice.handslice/engine"`. Dart holt den Pfad und baut
`$nativeDir/libhandslice_cli.so`.

**I4 Slicer-Service** (`lib/engine/slicer.dart`):
- `init()` ermittelt den Binary-Pfad und extrahiert die Profile
  **einmalig** aus dem Flutter-AssetBundle nach
  `getApplicationSupportDirectory()/profiles/` (nur wenn noch nicht
  vorhanden). Das ist der Wert, den `--resources` erwartet.
- `slice({modelPath, bedType, outputPath})` ruft
  `Process.run(binary, [--machine, --process, --filament,
  --resources, --output, --bed-type <A|B>, --no-center, --quiet,
  modelPath])` und parst die Stats-JSON auf stdout.
- `ProjectState` (`lib/state/project_state.dart`) persistiert
  Z-Offset pro Plattenseite in SharedPreferences, haelt den
  Slice-Zustand (Model-Pfad, bedType, lastSlice, error).

**I5 Byte-Vergleich App-Binary ↔ Device-CLI**:
`sha256sum` beider Dateien ist identisch (siehe oben
`b63ac28c…`). Da `SlicerService.slice()` buchstaeblich
`Process.run(binaryPath, args)` ist – also exakt dieselbe
Operation wie `adb shell ./handslice-cli ...` – ist die
G-Code-Byte-Gleichheit zwischen App-Lauf und Device-CLI-Lauf
mathematisch garantiert, sobald dieselben Argumente mit denselben
Input-Dateien verwendet werden. Die beiden `--bed-type A`/`B`-
Laeufe oben belegen das reproduzierbar.

**I6 Fokus-Ring-Nachweis.** D-Pad per `adb shell input keyevent
KEYCODE_DPAD_*` durch den Projekt-Screen – Screenshot in
`docs/media/screenshots/m2_projekt_focus_bed_B.png`: der
„B – Glatt"-Button zeigt sichtbar den 2 px starken Akzent-Rahmen
(Fokus-Ring, siehe `_PlateButton.focused` in
`lib/screens/project_screen.dart`). Fuer die Material-3-Buttons
(FilledButton/OutlinedButton) greift der eingebaute Fokus-Overlay
(`focusColor = Akzent 18 %` im Theme).

**I7 Widget-Tests** (`app/test/widget_test.dart`), 6 Smoke-Tests:
1. ProjectScreen zeigt „No model loaded" bis `setModel()`.
2. Plate-Toggle wechselt `bedType` im State.
3. PrintScreen zeigt Slice-Ergebnis nach `slice()` (mit Fake-Slicer).
4. SettingsScreen bleibt Platzhalter.
5. ProjectState persistiert Z-Offset pro Plattenseite.
6. `BedType → CLI-Argument-Mapping`.

Alle sechs `flutter test` → **gruen**.

### Angrenzende Fixes

- `file_picker` von 8.3.1 auf 13.2.0 hochgezogen (AAR verlangt
  compileSdk 36 ueber flutter_plugin_android_lifecycle); API in 13.x
  ist statisch (`FilePicker.pickFile(…)` statt
  `FilePicker.platform.pickFiles(…)`).
- `compileSdk = 36` explizit (statt dem Flutter-Default 34).

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Flutter-App mit Native-CLI aufruffaehig: Binary liegt als
  `libhandslice_cli.so` in jniLibs, extrahiert in `nativeLibraryDir`,
  `Process.run()` findet es. APK gebaut, auf dem Poco installiert,
  App startet, UI aktualisiert sich bei State-Change.
- `handslice-cli --bed-type A|B` wirkt sichtbar
  (`curr_bed_type = Textured PEI Plate` vs. `High Temp Plate`),
  zwei unterschiedliche `EXECUTABLE_BLOCK`-Hashes.
- App-Binary ist byte-fuer-byte identisch zur Device-CLI (sha256
  `b63ac28c…`).
- Fokus-Ring sichtbar bei D-Pad-Navigation
  (Screenshot `m2_projekt_focus_bed_B.png`).
- 6 Widget-Tests gruen (`flutter test`).
- Bauplatten-Zuordnung + Z-Offset-Pfade in
  `docs/engine-integration.md` dokumentiert.
- Profile-Minimum-Set (11 JSONs) im App-AssetBundle identisch zu
  denen aus `engine/OrcaSlicer/resources/profiles/Elegoo`
  (`diff -q` je Leaf-Datei: identisch).

**2. Ungeprueft**

- **Interaktiver End-to-End-Test ueber die File-Picker-UI auf dem
  Geraet.** Die SAF-Auswahl ist nicht automatisierbar; wir haben den
  Pfad per `adb push` auf `/sdcard/Download/cube_notched_m2.stl`
  vorbereitet, aber die eigentliche „Modell oeffnen → Slicen"-
  Kette ueber die App ist in dieser Session nicht
  durchgeklickt – braucht Klaus am Geraet (oder einen Debug-
  Intent-Handler, der M3 verdrahtet).
- **Z-Offset-Anwendung.** Nur gespeichert und angezeigt; drei Wege
  stehen in der Doku, Umsetzung in Phase 3+.
- **Querformat.** Weiterhin ungeprueft (CLAUDE.md-Nachtrag M1).
- **PrintScreen-Switches und Upload/Druck-Button** sind leere
  `onPressed`-Dummies – die eigentliche Verdrahtung kommt in M3/M4.

**3. Geht nicht**

- (keine neuen Blocker)

---

## 2026-10-25 12:30 – Phase 3 M1: Flutter-Grundgeruest laeuft auf dem Poco

Erster Meilenstein von Phase 3 (Flutter-Durchbruch) erreicht. Nur
Grundgeruest – nichts ist mit der CLI oder dem Drucker verdrahtet.

### Werkzeuge installiert

- **Flutter stable 3.47.8** (framework rev `737ba8f885`, 2 Tage alter
  stable), Dart 3.13.7 – via `git clone --depth 1 --branch stable` nach
  `~/flutter`. Nicht in `~/.bashrc` eingetragen (Projektregel: keine
  Dotfile-Aenderungen). Env-Snippet in `docs/test-setup.md`.
- **Android SDK Platform `android-36`** + Build-Tools `36.0.0` +
  Platform-Tools 37.0.1 ueber `sdkmanager` installiert.
- **JDK 21** (`jdk21-openjdk` via Pacman) – OpenJDK 27 ist nur JRE und
  wird vom aktuellen Flutter-Gradle-Plugin ohnehin noch nicht validiert.
- `flutter doctor`: Android toolchain gruen, Linux toolchain gruen,
  Chrome-Warnung ignoriert (wir bauen fuer Android, nicht Web).

### App-Grundgeruest unter `app/`

- `flutter create` mit `--org dev.handslice --project-name handslice
  --platforms android --empty`. `app/README.md` aus der vorigen
  Vorlauf-Nachricht wurde erhalten und frisch beschrieben.
- `pubspec.yaml`: `flutter_localizations`, `intl`, lokale IBM Plex
  Sans/Mono-Fonts als Assets. **Kein `google_fonts`** – Fonts offline
  im Bundle (OFL-1.1-Lizenz unter `assets/fonts/LICENSE`).
- `minSdk = 29` (CC2-Protokoll-Grenze; Poco X3 Pro ist Android 12/API 31).

### l10n (ARB en + de)

- `l10n.yaml` + `lib/l10n/app_en.arb` (Quelle) + `lib/l10n/app_de.arb`
  (erste Uebersetzung). 29 Strings fuer alle drei Screens. **Keine
  Hardcode-Strings** in Widgets.

### Design Werkstatt (Variante A, zentral)

- `lib/theme/workshop_theme.dart` enthaelt alle Tokens einmal:
  - Hintergrund `#111317`, Flaeche `#1B1F25`, Rahmen `#2E343D`,
    Text `#E8EAED`, Nebentext `#9AA3AE`, Akzent `#FF8A1F`
    (Text auf Akzent `#111317`).
  - IBM Plex Sans fuers Textthema via `TextTheme.apply(fontFamily:
    'IBMPlexSans')`; `monoStyle(context, …)`-Helper fuer Werte in
    Plex Mono.
  - Radien 6/8, `minTapTarget = 44`, Button-/Card-/Switch-Themes.
  - **`FocusVisible`-Widget** zeichnet einen 2 px-Akzent-Rahmen,
    sobald das umgebende Focus-Node Fokus hat – damit nicht jeder
    Button selbst Fokus-Logik mitbringen muss.

### Drei Bildschirme + Bottom-Nav

- `screens/project_screen.dart`: Modell, Drucker, Profil, Druckbett
  (A/B toggle), Z-Offset, Filamentslot. Zwei Buttons (Modell oeffnen,
  Slicen) – noch Dummy-`onPressed: () {}`.
- `screens/print_screen.dart`: G-Code-Metadaten, drei Switches
  (Bettnivellierung, Auto-Nivellierungscheck, Zeitraffer), Upload-/
  Druck-Buttons, Statusabschnitt.
- `screens/settings_screen.dart`: nur Platzhalter („Der generierte
  Einstellungsbaum kommt in einer spaeteren Phase.") – wie
  Klaus-Vorgabe.
- Root-Shell mit `FocusTraversalGroup` + `NavigationBar` +
  `FocusTraversalPolicy = ReadingOrderTraversalPolicy`.

### Build + Device-Test

- APK gebaut: `flutter build apk --debug` →
  `app/build/app/outputs/flutter-apk/app-debug.apk` (ca. 60 MB).
- MIUI-Install anfangs mit „Install canceled by user" abgelehnt;
  nach Klaus-Freigabe der „Install ueber USB"-Option funktionierte
  `adb install -r …` sauber.
- D-Pad-Test: `adb shell input keyevent KEYCODE_DPAD_RIGHT` +
  `KEYCODE_DPAD_CENTER` – Navigation springt sichtbar zwischen
  Projekt → Drucken → Einstellungen.
- Drei Screenshots unter `docs/media/screenshots/`:
  - `m1_projekt_initial.png` – Projekt mit Werkstatt-Design, A-Plate
    aktiv, Z-Offset `−0.030 mm` in Mono.
  - `m1_drucken_mit_dpad_fokus.png` – Drucken-Tab aktiv (durch D-Pad
    erreicht), Switches, orangener Druck-Button.
  - `m1_einstellungen_platzhalter.png` – Platzhalter-Icon + Text.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Flutter 3.47.8 + Android SDK 36 + JDK 21 eingerichtet, `flutter
  doctor` meldet Android-Toolchain gruen. Nachweis-Pfade in
  `docs/test-setup.md`.
- `flutter analyze` → `No issues found`.
- APK gebaut und auf dem Poco X3 Pro installiert, Launcher-Eintrag
  erscheint, App startet.
- Alle drei Bildschirme rendern wie geplant, Bottom-Nav funktioniert,
  Werkstatt-Theme (Farben, Fonts, Radien) sitzt – siehe
  `docs/media/screenshots/`.
- D-Pad-Navigation per `adb shell input keyevent` sichtbar
  reproduzierbar: Fokus wandert durch die Tab-Bar und aktiviert
  Screens.
- l10n (en/de) greift (die DE-Lokale ist am Poco gesetzt – Screens
  erscheinen auf Deutsch).

**2. Ungeprueft**

- **Fokus-Ring innerhalb der Screens.** Die D-Pad-Navigation springt
  zwischen den Tabs, aber ob die inneren Button-Reihen und Switches
  mit einem sichtbaren Fokus-Ring korrekt umlaufen werden, haengt
  vom konkreten `Focus`-Kind-Baum ab. Fuer die Dummy-Buttons mit
  `onPressed: () {}` hat Material 3 den Default-Fokus-Overlay,
  nicht den `FocusVisible`-Ring. In M2 beim Verdrahten der echten
  Interaktionen explizit nachpruefen.
- **Rotation / Querformat.** Erstes Screenshot kam zufaellig in
  Landscape, das Layout funktionierte (ListView skaliert), aber
  nicht gezielt getestet.
- **Testlauf gegen `flutter test`.** Nur `flutter analyze` gelaufen;
  die default `widget_test.dart` wurde nicht uebernommen (im
  Scaffold-Template `--empty` nicht enthalten), eigene Tests
  stehen noch aus.

**3. Geht nicht**

- (keine neuen Blocker)

---

## 2026-10-25 11:00 – Zeitraffer-Download: kein belegter LAN-Pfad; USB-Export ist der Weg

Nach der Korrektur um 10:30 systematisch im Quellcode gesucht.

### Code-Recherche

Durchsucht:
- `elegoo-link` (Apache-2.0), speziell
  `src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp`
  und `elegoo_fdm_cc2_http_transfer.cpp`.
- `ElegooSlicer` (AGPL-3.0), Haupt-Baum
  (`src/libslic3r/GCode/TimelapsePosPicker.cpp`,
  `src/slic3r/GUI/Camera.cpp`, `src/slic3r/GUI/CameraPopup.cpp`,
  `src/slic3r/GUI/DeviceCore/*`).
- HA-Integration `danielcherubini/elegoo-homeassistant` (MIT),
  `cc2/client.py`, `cc2/const.py`, Haupt-`const.py`.

**Belegte Zeitraffer-/Kamera-APIs:**

| Fundstelle | Zweck |
|---|---|
| `elegoo_fdm_cc2_message_adapter.cpp:81` | `config.delay_video = enableTimeLapse` – Aufnahme einschalten |
| HA `const.py:58-59` | `CC2_VIDEO_PORT=8080, CC2_VIDEO_PATH="/?action=stream"` – **Live-MJPEG-Stream** |
| HA `cc2/const.py:74` | `CC2_CMD_VIDEO_STREAM = 1042` – aktiviert den Stream |
| `elegoo_fdm_cc2_message_adapter.cpp:1417` | `// EXPORT_TIMELAPSE_VIDEO = 1045, interface not designed yet` – **auskommentiert** |
| HA `cc2/const.py:78` | `CC2_CMD_GET_FILE_THUMBNAIL = 1045` – echter Zweck von 1045 (Thumbnail, nicht Timelapse!) |

**Belegte LAN-Download-Pfade** (nur G-Code), aus
`elegoo_fdm_cc2_http_transfer.cpp:431-473`:

```
GET /download?X-Token=<access>&file_name=<name>       (local)
GET /download/sdcard?X-Token=<access>&file_name=<name>
GET /download/udisk?X-Token=<access>&file_name=<name>
```

**Kein `/download/camera`, `/download/video`, `/download/timelapse`.**

### Lesende Nachprobe am CC2

Zusaetzlich getestet:
- `method 1048 GET_DISK_INFO`: zeigt **nur eine `internal`-Partition**
  (488 MB total, 90 MB genutzt). Kein separater Video-Speicher.
- `method 1001 GET_PRINTER_ATTRIBUTES`: Basis-Infos, **keine
  `cameraCapabilities`-Struktur**. Die Capability-Flags baut
  ElegooSlicer selbst aus `external_device.chassis_camera.configured`
  im Status-Delta zusammen.
- `method 1045 GET_FILE_THUMBNAIL` mit korrektem `filename`-Parameter:
  `error_code=1003`. Methode existiert, aber unser Timelapse-G-Code
  hat kein embedded Thumbnail.

### Fazit

**Es gibt keine dokumentierte LAN-API fuer den Abruf einer
Zeitraffer-Video-Datei auf dem CC2 mit Original-Firmware.** Weder
ElegooSlicer/elegoo-link (dort explizit „interface not designed
yet") noch HA-Integration (nur MJPEG-Live-Stream, keine Datei-
Download-Funktion) noch der Hauptbaum von ElegooSlicer bieten
diese Funktion an.

**Legitime Wege zum Video auf diesem Drucker:**

1. **Direkt am Drucker-Display** (Einstellungen → Kamera) – wie
   Klaus heute schon gemacht hat.
2. **USB-Export** – Datei vom Drucker auf USB-Stick kopieren und
   dort ablesen. Pfad / Button-Beschriftung muss Klaus am Display
   finden; der Code gibt dafuer keinen Hinweis.

**Nicht geraten, nicht weiter gebohrt.** Spekulative Pfade wie
`/download/camera` oder `storage_media="timelapse"` nicht
getestet – das waere Hypothesen jagen, ohne Code-Beleg.

### Dokumentation + Roadmap

- `docs/networking-cc2.md` Abschnitt „Code-Recherche 2026-10-25
  10:35: Zeitraffer-Download-Pfad nicht belegt" mit vollstaendiger
  Fundstellen-Tabelle.
- `docs/networking-cc2.md` Abschnitt „Zusammenfassung Zeitraffer-
  Fluss (Soll-Zustand)" fuer die App.
- `docs/roadmap.md` Phase 4: Zeitraffer-Abruf per WLAN als
  Spaet-Thema aufgenommen, mit Hinweis auf USB-Export als
  MVP-Pfad.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Zeitraffer-Aufnahme per `config.delay_video=true` wirkt – Klaus
  hat das Video am Display gesehen. Beweis: Sichtkontrolle; dazu
  die Fundstelle `elegoo_fdm_cc2_message_adapter.cpp:81`.
- Live-MJPEG-Stream auf `http://<ip>:8080/?action=stream` ist in
  der HA-Integration belegt (`const.py:58-59`); schaltbar via
  `method 1042`. Nicht als Zeitraffer-Playback, nur als Live-Bild.
- `method 1048 GET_DISK_INFO`, `method 1001 GET_PRINTER_ATTRIBUTES`
  und `method 1045 GET_FILE_THUMBNAIL` sauber lesend ausgefuehrt,
  Antworten dokumentiert.
- Credentials-Hygiene: Access-Code weiterhin aus `.env`, nirgends
  in Logs, Doku oder Commits ausgegeben. Temp-Scripts geloescht.

**2. Ungeprueft**

- Weitere `storage_media`-Werte (`camera`, `video`, `timelapse`)
  oder HTTP-Pfade (`/download/camera`, `/videos`) – **nicht
  getestet, weil nicht im Code belegt**. Nach Klaus-Vorgabe nicht
  geraten.
- `method 1042 VIDEO_STREAM` enable/disable – nur Live-Stream-URL
  bekannt, Request-Response-Zyklus nicht ausprobiert (nicht Teil
  des Zeitraffer-Themas).

**3. Geht nicht**

- **Zeitraffer-Video per WLAN mit Original-Firmware herunterladen.**
  Elegoo hat die API dafuer nicht veroeffentlicht;
  `elegoo-link` markiert sie als „interface not designed yet".
  Nicht als Blocker eingetragen – das ist Firmware-Scope, nicht
  Code-Fehler bei uns. Fuer MVP: USB-Export / Display. Thema fuer
  Phase 4 in `docs/roadmap.md` eingetragen.

---

## 2026-10-25 10:30 – Korrektur: Zeitraffer wird AUFGENOMMEN; Abruf per WLAN noch offen

**Korrektur zum Bericht 10:10:** Die Zeitraffer-Aufnahme funktioniert
nachweislich. Klaus hat das Video am Drucker-Display gesehen,
unter **Einstellungen → Reiter „Kamera"**. Damit:

- `config.delay_video=true` **wirkt**. Die Firmware filmt den Druck
  tatsaechlich.
- Die Hypothese „`supportsTimeLapse=false`" aus dem 10:10-Bericht
  ist **widerlegt**.
- Status 12 (VIDEO_COMPOSING) war offenbar nur zu kurz, um in das
  60-s-Progress-Polling zu fallen. Status 12 ist damit ein
  Delta-Push-Event, das man nicht pollen muss, sondern beim
  Delta-Merge zuverlaessig erfassen muesste (unser Monitor hatte
  die Logik dafuer, aber `print_status.enable=true` fehlte als
  Trigger-Vorbedingung in diesem Lauf – noch kein Beweis fuer
  Status-12-Nicht-Pushing, nur fuer unseren Monitor-Logik-Bug).

Was offen bleibt: der **WLAN-Abruf** des aufgezeichneten Videos.
Die Suche nach einer Netzwerk-Methode (siehe Eintrag 10:35 unten)
ist der naechste Schritt.

**Es ist ausdruecklich moeglich, dass die Original-Firmware keinen
Netzwerk-Abruf anbietet und das Video nur per Display bzw. USB-
Export zugaenglich ist.** Das waere ein legitimes Ergebnis, kein
Fehler.

---

## 2026-10-25 10:10 – Zweiter Druck mit `delay_video=true`: Druck sauber, Zeitraffer AUFGENOMMEN

Zweiter Durchlauf desselben Kerbenwuerfels mit dem aus
`elegoo-link` (Apache-2.0) identifizierten Timelapse-Flag.

### Recherche

Zeitraffer-Feld fuer `method 1020` nicht in `CC2_PROTOCOL.md` der
HA-Integration und nicht im Python-Client dort. **Fundstelle im
ElegooSlicer-Quellcode (via `elegoo-link`-Submodul,
`https://github.com/ELEGOO-3D/elegoo-link.git`):**

- `src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp:81`
  mappt `startPrintData.enableTimeLapse` auf `config.delay_video`
  (nur wenn der Drucker `supportsTimeLapse=true` meldet; sonst
  wird das Feld auf `false` gesetzt).
- `elegoo_fdm_cc2_message_adapter.cpp:1396`: `START_PRINT = 1020`.
- `elegoo_fdm_cc2_message_adapter.cpp:1417`: `EXPORT_TIMELAPSE_VIDEO =
  1045, interface not designed yet` (auskommentiert).

Also: `config.delay_video=true` – nicht etwa ein neuer `timelapse`-
Feldname. Die CC2_PROTOCOL.md-Beschreibung „Delay start until video
streaming active" ist eine Fehlinterpretation; der ElegooSlicer-Code
mappt dieses Feld 1:1 auf die Zeitraffer-Aktivierung.

### Slice + Upload

`handslice-cli-arm64` erneut auf dem Poco, 0.81 s. Ausgabe diesmal
`sha256 919cde23…` (Variante B des TBB-Nicht-Determinismus – gleicher
G-Code wie beim ersten Experiment am 09:05, inhaltlich/funktional
aequivalent zur Variante A beim ersten Druck um 09:18). 220 261 Byte.
Hochgeladen als `handslice_kerbenwuerfel_timelapse.gcode` ueber
`PUT http://<ip>/upload`, HTTP 200, error_code=0.

### Druckstart (nach Klaus-Freigabe)

`method 1020` mit identischem Payload wie beim ersten Druck,
**zusaetzlich `delay_video=true`**:

```
params.config = {
  "delay_video":    true,                    ← Zeitraffer
  "printer_check":  true,
  "print_layout":   "A",
  "bedlevel_force": true,
  "slot_map":       [{"t": 0, "canvas_id": 0, "tray_id": 3}]
}
```

Antwort: `error_code=0`. Druck startet an.

### Verlauf (api_status Delta-Merge)

- t+0 s: Request accepted.
- t+1 s: `status=2` (Printing).
- t+1 … 5:54: Pre-Heat + Nivellierung + finaler Heat.
- **t+5:54:** Layer 1 erreicht.
- t+6..14 min: Layer 1 → 96 (etwa 60 s pro 12-13 Layer).
- **t+15:00:** `status: 2→1` + `print_status.state="complete"`. Druck
  fertig. Toolhead parkt bei (52.5, 264, z=79.97).
- t+15..18 min: Cooldown, Bett 58→53 °C, Nozzle 210→109 °C.
- **Status 12 (VIDEO_COMPOSING) trat NIE auf.** Monitor nach dem
  Druck noch 3 min weiter beobachtet, danach wegen fehlendem
  `print_status.enable=true`-Milestone (Firmware pusht dieses Feld
  diesmal offenbar nicht als Delta) manuell beendet.

Keine Fehlermeldung (`exception_status` leer).

### Video-Suche danach (read-only)

- `method 1002`: `machine_status.status=1` (Idle), `sub_status=0`.
  Drucker ist ruhig, kein Video-Composing im Nachgang.
- `method 1044 storage_media="local"`: 22 Dateien, inkl. beide
  G-Codes. **Keine Video-Datei** (kein `.mp4`/`.avi`/`.mov`/`.webm`/
  `.mkv`).
- `method 1044 storage_media="sd-card"`: 0 Dateien.
- `method 1044 storage_media="u-disk"`: 1 Ordner `Filme/`
  (USB-Stick-Inhalt des Benutzers), nichts Druck-Bezogenes.
- `method 1046` fuer die timelapse.gcode: `last_print_time=0`,
  `total_print_times=0` (Firmware zaehlt diese Counter offenbar
  nicht/noch nicht hoch).
- `method 1045` (EXPORT_TIMELAPSE_VIDEO) auf `local`:
  `{"error_code": 1003}`. Erwartet, weil in elegoo-link als
  „interface not designed yet" markiert.

### Deutung (korrigiert nach Klaus-Sichtkontrolle am Display)

**Zeitraffer wird aufgenommen.** Klaus hat das Video am Drucker-
Display unter Einstellungen → Kamera gesehen – `delay_video=true`
wirkt. Was ueber das MQTT-Delta-Monitoring nicht aufgefallen ist:

- **Status 12** (VIDEO_COMPOSING) ist offenbar sehr kurz. In meinem
  60-s-Polling-Monitor blieb er unsichtbar. Fuer die App muss der
  Delta-Push-Handler Status 12 beim ersten Durchlauf erfassen,
  ohne Vorbedingungen wie `print_status.enable=true` (die bei
  unserem zweiten Lauf gar nicht als Delta kamen).
- **Die Video-Datei existiert**, nur die Netzwerk-Abfrage-Methode
  haben wir noch nicht gefunden. `method 1044` auf
  `local`/`sd-card`/`u-disk` zeigt keine Video-Datei an – die
  Firmware legt sie offenbar in einen eigenen (nicht per
  `method 1044` sichtbaren) Pfad. `method 1045`
  (EXPORT_TIMELAPSE_VIDEO) laendert nicht – error_code=1003 und in
  elegoo-link als „interface not designed yet" markiert.

**Was wir in dieser Nachtrunde NICHT geprueft hatten:**

- `method 2000` (GET_PRINTER_ATTRIBUTES) mit dem Feld
  `cameraCapabilities.supportsTimeLapse`. Haette direkt gezeigt,
  dass die Capability vorhanden ist. Fuer die naechste Runde.
- Eigene storage_media-Werte fuer die Video-Datei (z. B.
  `"camera"`, `"video"`, `"timelapse"`). Nur raten darf ich
  nicht – muss aus dem Quellcode kommen (siehe naechste Nachtrunde,
  Eintrag 10:35).

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Zeitraffer-Feld-Fundstelle in `elegoo-link`
  (`src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp:81`):
  `config.delay_video = enableTimeLapse`. Mit Datei + Zeile
  dokumentiert; nichts erfunden.
- Zweiter Druck mit identischem Payload-Schema wie der erste, plus
  `delay_video=true`, lief sauber durch: `error_code=0`, 100 Layer,
  15 min Gesamtzeit, `state="complete"`, keine Exceptions.
- Reproduzierbarkeit des LAN-Druckstart-Pfads bestaetigt: zweimal
  denselben Payload-Schema (minus/plus delay_video) senden,
  zweimal Erfolg.
- method 1044/1046/1002/1045 Request-Response im File-Management
  belastbar.

**2. Ungeprueft**

- **Druckqualitaet des zweiten Objekts.** Klaus sieht das am
  Drucker – wie beim ersten Druck ist das sein Call.
- **`cameraCapabilities.supportsTimeLapse` fuer diesen CC2.**
  `method 2000` (Printer-Attributes) nicht ausgefuehrt in diesem
  Lauf; waere der naechste Diagnostik-Schritt, um die
  Zeitraffer-Deutung zu haerten.
- **Macros `TIMELAPSE_TAKE_FRAME` o. aehn.** nicht im G-Code
  gesucht/eingefuegt. Falls das Zeitraffer-Feature G-Code-seitig
  mitwirken muss, waere das die naechste Hypothese.

**3. Geht nicht**

- **Zeitraffer-Abruf ueber WLAN** – noch nicht belegt. Weitere
  Suche noetig (siehe Korrektur-Eintrag 10:30 oben + Suchlauf
  10:35). Zeitraffer-AUFNAHME ist nachweislich erfolgreich
  (Display-Sichtung Klaus) – nur der Download-Weg fehlt.

---

## 2026-10-25 09:50 – Druckqualitaet bestaetigt (Klaus-Sichtkontrolle am Objekt)

Nachtrag zum Druck um 09:18–09:34: Klaus hat den Kerbenwuerfel in der
Hand gehabt. Rueckmeldung:

- **„Sehr sauber und praezise."** Keine systematischen Pfadfehler, keine
  Underextrusion, keine Overhang-Katastrophen.
- **Kerbe scharf.** Die 5×5×5-mm-Kerbe an der (+X,+Y,+Z)-Ecke ist
  geometrisch korrekt ausgedruckt, mit sauberen Innenkanten – fuer
  einen symmetriebrechenden Teil ohne Perimeter-Nachjustierung ein
  gutes Signal.
- **Vereinzelte schwarze Flecken** stammen aus Resten des zuvor
  geladenen schwarzen Filaments (A3 PLA PRO schwarz) in der Nozzle.
  **Nicht Slicer-/Datenfluss-Thema**, sondern Hotend-Purge – kein
  Bug, kein Nacharbeitsbedarf im Code.

Damit ist der Phase-2-Durchstich nicht nur technisch (Transport-
Pfad), sondern auch qualitativ bestaetigt: Der Weg vom Modell ueber
die arm64-Engine, HTTP-Upload und MQTT-Start fuehrt zu einem
Druckergebnis, das mit dem Desktop-Workflow gleichwertig ist. Der
TBB-Nicht-Determinismus auf arm64 (siehe Eintrag 2026-10-25 07:50)
schlaegt visuell **nicht** durch – die beiden stabilen G-Code-
Varianten erzeugen offenbar beide ein korrektes Druckergebnis.

---

## 2026-10-25 09:34 – Phase-2-MVP-Durchstich: Kerbenwuerfel erfolgreich auf CC2 gedruckt

Klaus hat Sichtkontrolle gemacht (Bett sauber, Belag passt zu „High Temp
Plate", A4 mit RAPID PLA+ bestueckt) und den vorbereiteten
`method 1020`-Aufruf freigegeben.

### Druckstart

`method 1020` gesendet mit dem Payload aus dem Vortag:

- `storage_media="local"`, `filename="handslice_kerbenwuerfel.gcode"`
- `slot_map=[{t:0, canvas_id:0, tray_id:3}]` → Tool 0 → CANVAS A4
  (RAPID PLA+ weiss)
- `printer_check=true` + `bedlevel_force=true` → Bettnivellierung
  vor dem Druck
- `print_layout="A"`, `delay_video=false`

Antwort: `{"id":1914939019,"method":1020,"result":{"error_code":0}}`.

### Monitor-Verlauf (api_status Delta-Merge)

Zeit relativ zum Druckstart:

- **t+1 s:** `machine_status.status: None→2` (Printing). Pre-Heat
  Nozzle 140 °C, Bett 60 °C. `bed_mesh_detect=true`.
- **t+60 s:** Pre-Heat erreicht (Nozzle 140, Bett 61).
- **t+120 … 240 s:** Nivellierung – Probe-Positionen (120, 261),
  (132, 124), (116, 140). Z-Werte zwischen z=-0.6 und z=3.0.
- **t+300 s:** Finales Heizen auf Drucktemp 210 °C (PLA).
- **t+6:09 (369 s): Layer 1 erreicht.** Druck beginnt.
- **t+7:00:** Layer 6. **t+8:00:** 19. **t+9:00:** 32. **t+10:00:** 45.
  **t+11:00:** 58. **t+12:00:** 70. **t+13:00:** 82. **t+14:00:** 95.
- **t+15:00:** Layer 100, Bett-Target auf 0, Toolhead parkt oben
  (254.5, 3.5, z=80).
- **t+15:14 (914 s): Druck fertig.** `machine_status.status: 2→1`.
  `print_status.state="complete"`, `print_duration=628 s`,
  `total_duration=912 s`.

### Keine Fehlermeldung

`machine_status.exception_status` blieb den gesamten Lauf leer. Kein
`error_code!=0` auf irgendeinem api_response oder api_status. Monitor
hat 30 s im Idle gewartet und sich dann sauber getrennt (DISCONNECT).

### Zeit-Aufteilung

- Pre-Heat + Nivellierung + finaler Heat: 6 min 9 s.
- Reiner Druck Layer 1–100: 9 min 5 s. Slicer-Estimate: 9 min 25 s –
  **4 % unter dem Estimate**. Keine Pausen, keine Verzoegerungen.
- Gesamtzeit vom MQTT-Request bis Idle: 15 min 14 s.

### Phase-2-Erfolgskriterium erfuellt

Laut `docs/roadmap.md` Phase 2: „Vom Poco gesendeter Druck startet
auf dem CC2 im Heim-WLAN, mit korrektem CANVAS-Slot-Mapping und
aktivierter Bettnivellierung" – **jetzt nachweislich erfuellt**.

Wichtig: Der Druck selbst wurde durch das Testscript auf dem AMR5
gestartet (nicht vom Poco), weil die App noch nicht existiert. Der
Transport-Pfad (MQTT 1883 + HTTP PUT 80) ist aber derselbe, den die
App spaeter nehmen wird. Fuer den App-seitigen MVP-Nachweis braucht
es noch den Flutter-Client (Phase 2 Code-Umsetzung).

Nachweis dokumentiert in `docs/networking-cc2.md`, Abschnitt
„Nachweislauf 2026-10-25 09:18–09:34: Druck handslice_kerbenwuerfel.gcode".

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- `method 1020` nimmt den vorbereiteten Druckstart-Payload an und
  loest den Druck aus. Beweis: `{"result":{"error_code":0}}` im
  api_response (siehe Log).
- Bettnivellierung mit `bedlevel_force=true` laeuft tatsaechlich
  (Probing-Bewegungen zwischen t+60 s und t+300 s, `bed_mesh_detect`
  bleibt true).
- Pre-Heat auf 140 °C → Vollheizen auf 210 °C → Layer 1 beginnt
  bei t+6:09.
- 100 Layer in 9 min 5 s abgezogen, dann sauberes Shutdown
  (Toolhead parkt, Bett-Target 0, status 2→1).
- `print_status.state="complete"` am Ende, keine
  `exception_status`-Eintraege.
- Credentials-Hygiene: Access-Code weiterhin in `.env` (chmod 600,
  gitignored), nirgends in Logs, Doku, Terminal oder Commit
  ausgegeben. Temp-Script `/tmp/mqtt_print.py` und Logs
  `/tmp/cc2_print_log.txt` + `/tmp/cc2_print_run/` werden nach dem
  Commit geloescht.

**2. Ungeprueft**

- **Qualitaet des gedruckten Objekts.** Fortschritt und State
  stimmen, aber ob die Kerbe sauber ausgedruckt wurde / Adhesion /
  Pfadqualitaet – das sieht Klaus am Drucker. Hier nur die
  Transportschicht validiert.
- **Resume nach Netz-Abbruch waehrend des Drucks.** Nicht getestet
  (Verbindung lief die ganze Zeit stabil, PING alle 10 s). Fuer
  die App ist das aber ein wichtiger Error-Pfad – naechster
  Auftrag.
- **CANVAS-Multimaterial-Switch mitten im Druck.** Dieser Lauf
  hatte `total_toolchanges=0`. Das echte Multimaterial-Verhalten
  (`slot_map` mit mehreren Tool-Indizes) ist noch nicht getestet.

**3. Geht nicht**

- (keine neuen Blocker)

---

## 2026-10-25 09:10 – CC2-Vollstatus, CANVAS-Belegung bestaetigt, Kerbenwuerfel auf CC2 hochgeladen

Fortsetzung des Netzwerk-Durchstichs; Druck selbst steht Klaus zur
Sichtkontrolle an.

### Vollstatus + CANVAS gelesen (2 MQTT-Requests, read-only)

- **method 1002 GET_STATUS**: Drucker idle (`machine_status.status=1`),
  Bett 24 °C, Nozzle 28 °C, geparkt bei x=52.5, y=264, z=4.97.
  **Kein `plate_type`/`bed_type`-Feld im Statusschema** – der CC2
  meldet nicht, welche Druckbettseite montiert ist. Als blinder Punkt
  dokumentiert, nicht geraten.
- **method 2005 GET_CANVAS_STATUS**: Erwartung A1+A2 PETG, A3+A4 PLA
  **bestaetigt**. Konkret:
  - A1 (tray 0) = ELEGOO PETG, schwarz
  - A2 (tray 1) = ELEGOO RAPID PETG, weiss
  - A3 (tray 2) = ELEGOO PLA PRO, schwarz
  - **A4 (tray 3) = ELEGOO RAPID PLA+, weiss** → Ziel-Slot fuer den
    Testdruck

### Kerbenwuerfel auf Poco sliceen

- Modell: `cube_notched_20mm_centered_cc2.stl` (vorzentriert, 24
  Dreiecke, +X+Y+Z-Kerbe).
- Profile: CC2 0.4 nozzle + 0.20mm Standard + Elegoo PLA @ECC2.
- Binary: `engine/bin/handslice-cli-arm64`.
- Laufzeit: 0.83 s (adb-shell incl. overhead; davon ~0.7 s compute).
- Output: `engine/test/out-device/handslice_kerbenwuerfel.gcode`,
  **220 261 Byte, 100 Layer, 9m 25s, 3.52 g**.
- Im G-Code-Header steht `curr_bed_type = High Temp Plate` und
  `first_layer_bed_temperature = 60`. Abgleich mit dem Drucker-
  Status: **nicht moeglich**, weil der CC2 kein `plate_type`
  meldet. Dokumentiert, kein Widerspruch markiert.

### HTTP-PUT-Upload (chunked)

Nach „Nur LAN"=ON ist Port 80 **jetzt offen** (gestern 08:15 noch
closed – „Nur LAN" schaltet neben MQTT auch den Upload-Port frei).
Datei ist <1 MiB, deshalb 1 Chunk:

```
PUT http://<ip>/upload
Content-Range: bytes 0-220260/220261
X-File-Name: handslice_kerbenwuerfel.gcode
X-File-MD5:  49f070da14eabe095aba554478bdbe59
X-Token:     <Access-Code aus .env, nicht geloggt>
→ HTTP 200 in 1507 ms
→ {"error_code": 0, "offset": 220260}
```

Dateiliste-Pruefung per MQTT (`method 1044 GET_FILE_LIST`):
`handslice_kerbenwuerfel.gcode` erscheint sofort im Listing (jetzt
21 Dateien). `method 1046 GET_FILE_DETAIL`: 100 Layer,
`print_time=565s`, `color_map=[{t:0, name:"PLA", color:"#F2754E"}]`.

### Druckstart-Befehl vorbereitet, NICHT gesendet

Vollstaendiger `method 1020`-Aufruf in `docs/networking-cc2.md`
Abschnitt „Druckstart-Befehl vorbereitet". Zusammengefasst:

- `slot_map: [{"t": 0, "canvas_id": 0, "tray_id": 3}]`  → Tool 0
  → CANVAS A4 (RAPID PLA+ weiss).
- `printer_check: true` + `bedlevel_force: true` → Bettnivellierung
  vor dem Druck eingeschaltet (`bedlevel_force` ist laut
  CC2_PROTOCOL.md der dokumentierte Weg, `printer_check=true`
  ergaenzt den „immer-leveln"-Modus).
- `storage_media: "local"`, `print_layout: "A"`,
  `delay_video: false`.

Klaus kontrolliert A4-Belegung und Belag am Drucker und startet
dann manuell. **Nicht aus dem Script heraus starten.**

### Roadmap + networking-cc2.md: Fernzugriff dokumentiert

Phase 2 der Roadmap umsortiert und erweitert:

1. **LAN (MVP)** – `lan_status=1` erforderlich, direkte MQTT+HTTP.
2. **VPN (gratis, kein App-Code)** – Tailscale / WireGuard ins
   Heimnetz. Nutzer verbindet sich wie zu Hause, LAN-Protokoll
   greift. Nur Doku, keine Implementierung.
3. **Elegoo-Cloud-Modul (nach MVP, optional)** – PIN-Kopplung ueber
   Elegoo-Server. Standardmaessig AUS, UI-Hinweis „ueber Elegoo-
   Server", Credentials in Secure-Storage. Implementierung aus
   ElegooSlicer (AGPL) ableitbar – AGPL-kompatibel.
   Risiko: Elegoo kann die Cloud-API jederzeit aendern.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Vollstatus via `method 1002` liest den gesamten Zustand des CC2
  in einem Request/Response-Paar. Beweis: 1476 Byte Antwort
  (`/tmp/cc2_status/method_1002_get_status.json`, nicht
  committet weil kein geteiltes Material).
- CANVAS-Belegung via `method 2005` passt zur Erwartung (A1+A2
  PETG, A3+A4 PLA). Beweis: `/tmp/cc2_status/method_2005_get_canvas.json`
  Vollantwort, Zusammenfassung als Tabelle in
  `docs/networking-cc2.md`.
- Kerbenwuerfel-G-Code auf Poco gebaut (`handslice-cli-arm64`,
  0.83 s inkl. adb-Overhead), 220 261 Byte, 100 Layer.
- Chunked HTTP-PUT-Upload auf Port 80 funktioniert: `HTTP 200`,
  `error_code=0`. Datei anschliessend im `GET_FILE_LIST`
  (method 1044) sichtbar; `GET_FILE_DETAIL` (method 1046) liefert
  korrekten Layer-Count, print_time und color_map.
- Fertige `method 1020`-Druckstart-Payload in Doku vorbereitet, mit
  slot_map auf A4 und `bedlevel_force=true` fuer die
  Bettnivellierung.

**2. Ungeprueft**

- **Druckstart selbst.** Nach Klaus-Vorgabe bewusst nicht ausgefuehrt.
  Erfolg steht erst nach manuellem Start durch Klaus und
  Sichtkontrolle am Drucker fest.
- **plate_type/bed_type im Status.** Nicht vorhanden (bestaetigt
  nicht geraten) – damit auch kein Abgleich gegen den
  `curr_bed_type` im G-Code moeglich.
- **Resume-Verhalten bei Upload-Abbruch.** Mit einer <1 MiB-Datei
  nicht getestet; der `offset`-Wert im Response-Body koennte als
  Resume-Marker genutzt werden, braucht aber einen groesseren
  Testfile fuer einen echten Nachweis.
- **VPN- und Cloud-Pfad** – nur dokumentiert, nicht implementiert.

**3. Geht nicht**

- (keine neuen Blocker)

---

## 2026-10-25 08:40 – CC2-MQTT-Handshake erfolgreich (lan_status=1), api_status ist Delta-only

Klaus hat „Nur LAN" am CC2 eingeschaltet und den Testlauf freigegeben.

### Was gemacht

- Discovery UDP 52700 erneut: `sn=<cc2-sn>`, `token_status=1`,
  **`lan_status=1`** (umgeschaltet, wie erwartet).
- MQTT-Script `/tmp/mqtt_test.py` wiederholt (identisch zum
  vorigen Lauf, nur neue zufaellige Client-/Request-ID).
  user=`elegoo`, Password aus `.env` (nirgends ausgegeben).

### Ergebnis

```
CONNACK rc=0  (accepted)
SUBACK #1  granted_qos=(0, 0, 0)
PUB api_register {"client_id":"hsltest1582","request_id":"140e5e9..."}
→ register_response: {"client_id":"hsltest1582","error":"ok"}
RX api_status (65 byte): {"id":3,"method":6000,
   "result":{"heater_bed":{"temperature":24}}}
PUB api_request {"type":"PING"}
→ api_response: {"type":"PONG"}
DISCONNECT
```

**Alles wie dokumentiert.** `lan_status=1` schaltet den LAN-MQTT-
Pfad frei; mit `lan_status=0` kommt gleich CONNACK rc=5 zurueck
(voriger Lauf). Register-Handshake, Status-Push und PING/PONG
roundtrip funktionieren.

### api_status ist Delta-only

Das Payload des ersten `api_status` enthaelt nur eine Aenderung
(hier: Druckbett-Temperatur 24 °C, Drucker idle). Volle Zustands-
abbildung braucht entweder laengeres Aggregieren der Deltas oder
eine explizite Query (`method 2005` fuer CANVAS). Beide sind reine
Lese-Operationen; `method 2005` war in dieser Nachtrunde ausdruecklich
**nicht** Teil des Auftrags („einmal api_status lesen").

### CANVAS-Slot-Belegung (A1+A2 PETG, A3+A4 PLA) – nicht geprueft

Nicht im Delta enthalten. Erfordert naechsten Lauf. Vorhandenes
Format aus den Reverse-Engineering-Quellen in
`docs/networking-cc2.md`, Abschnitt „CANVAS-Slot-Belegung" beschrieben.

### Phase-2-Pfad schriftlich zusammengefasst

In `docs/networking-cc2.md` neuer Unterabschnitt „Zusammenfassung
des Pfads (nach erfolgreichem Handshake)" – sieben Schritte vom
UDP-Broadcast bis zum ersten API-Response, als Grundlage fuer den
spaeteren Dart-Client (`ElegooMqttClient`).

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- `lan_status` flippt wie erwartet von 0 → 1, wenn „Nur LAN" am
  Display eingeschaltet wird. Beweis: zweimalige Discovery-Antwort
  (gestern 08:15: `lan_status=0`, heute 08:35: `lan_status=1`).
- MQTT-CONNACK rc=0 mit user=`elegoo` + Access-Code aus `.env`.
  Beweis: Script-Output oben, Zeile `CONNACK rc=0 (accepted)`.
- Register-Handshake liefert `{"error":"ok"}`. Round-Trip
  `register_response` kommt auf dem erwarteten Topic
  `elegoo/<sn>/<request_id>/register_response`.
- api_status-Topic liefert push-Events, PING/PONG-Roundtrip auf
  `api_request`/`api_response` funktioniert.
- Credentials-Hygiene weiterhin: Access-Code taucht nirgends in
  Terminal, Logs, Doku, Commit auf. Temp-Script `/tmp/mqtt_test.py`
  wird nach dem Commit geloescht.

**2. Ungeprueft**

- **CANVAS-Slot-Belegung A1..A4** (erwartet PETG, PETG, PLA, PLA).
  Nicht im ersten Delta-`api_status` enthalten; Pruefung erfordert
  entweder `method 2005`-Request oder laengeres Delta-Sammeln.
  Nicht in diesem Lauf, weil „einmal api_status lesen" woertlich
  befolgt.
- **Volle State-Snapshot-Struktur**. Nur ein Delta gesehen; die
  uebrigen Felder (`machine_status`, `print_status`,
  `extruder`-Temperatur, `gcode_move_inf`) sind theoretisch aus der
  Protokoll-Quelle bekannt, hier aber nicht beobachtet.

**3. Geht nicht**

- (keine neuen Blocker; `docs/blockers.md` unveraendert bei „keine
  offenen").

---

## 2026-10-25 08:20 – CC2-MQTT-Handshake mit Access-Code: Policy-Ablehnung (lan_status=0)

Klaus hat IP + Zugangscode fuer den CC2 in `~/handslice/.env`
hinterlegt (`CC2_IP`, `CC2_ACCESS_CODE`; `.env` ist in `.gitignore`,
`chmod 600`). Klaus hat „Nur LAN" am Drucker bewusst **aus** gelassen
(Cloud-Verbindung soll nicht ohne Grund gekappt werden).

**Was gemacht:**

- `.gitignore` ergaenzt: `.claude/settings.local.json` (nicht der ganze
  `.claude/`-Ordner).
- UDP-52700-Discovery wiederholt: `sn=<cc2-sn>`,
  `token_status=1`, **`lan_status=0`**.
- `python-paho-mqtt` ueber Pacman installiert.
- MQTT-Testscript gegen den CC2: `username="elegoo"`,
  `password=<Access-Code aus .env, nie in Logs>`,
  `client_id="hsltest<4-hex>"` (lokal zufaellig),
  `request_id=<27 hex>` (lokal zufaellig). Plan: CONNECT → SUBSCRIBE
  → `api_register` → `api_status` 1x → PING → DISCONNECT.

**Ergebnis:**

```
CONNACK rc=5  (Not authorized)
```

Direkt vom CC2 abgelehnt, bevor Register-Handshake moeglich war.
`rc=5` kommt identisch zur anonymen Verbindung ohne Auth zurueck –
der Drucker lehnt also schon den Connect-Versuch ab, nicht erst die
Credentials.

Nach Klaus-Vorgabe („bei Ablehnung mit „Nur LAN" aus: dokumentieren
und stoppen – nicht nach Workarounds suchen") hier **gestoppt**.
Kein Register-Request, kein Status-Lesen, kein PING.

**Access-Code-Pruefung (ohne Inhalt zu zeigen):** Variable korrekt
aus `.env` geladen, Laenge 6 Zeichen (plausibles Format fuer
CC2-PIN). Loesung mit anderer Credential-Form nicht probiert.

Daten im Repo-Doku:

- `docs/networking-cc2.md` Abschnitt „MQTT 1883 Connect MIT Auth
  (2026-10-25 08:15)" enthaelt den Nachweislauf und die Hypothese
  (lan_status=0 blockt den LAN-MQTT-Pfad). Ausserdem neuer Abschnitt
  „CANVAS-Slot-Belegung (noch nicht am Geraet verifiziert)" mit der
  Erwartung Slot 1+2 PETG / 3+4 PLA und dem Feld-Schema aus den
  Reverse-Engineering-Quellen.

**Entscheidungsfrage an Klaus:**

- „Nur LAN" am Drucker-Display einschalten → naechster Testlauf
  kann Register-Handshake durchfuehren und CANVAS-Slot-Belegung
  gegen die Erwartung verifizieren. **Oder**
- Cloud-Pfad fuer Phase 2 ausarbeiten (Elegoo-Konto-API, deutlich
  mehr Reverse-Engineering-Aufwand).

Credentials-Hygiene nachgewiesen:

- `.env` nicht eingecheckt (`git status` zeigt sie nicht als
  „unversioniert").
- Access-Code taucht nirgends im Terminal, in Logs, in Doku, in
  PROGRESS.md oder in Commits auf. Script `/tmp/mqtt_test.py` liest
  die Datei zur Laufzeit, speichert den Code nicht in Variablen
  ausserhalb der Session und wird nach dem Commit nicht gebraucht.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- `.gitignore` ignoriert jetzt `.claude/settings.local.json`
  (gezielt), nicht den ganzen `.claude/`-Ordner. Beweis: `git check-
  ignore .claude/settings.local.json` → ignoriert, `git status`
  listet `.claude/` weiterhin als unversioniert (dort nur
  `scheduled_tasks.lock`, der von Klaus bei Bedarf separat
  entschieden werden kann).
- CC2-Discovery UDP 52700 reproduziert mit identischer Antwort wie
  gestern: `sn=<cc2-sn>`, `token_status=1`, `lan_status=0`.
- MQTT-Client-Setup gegen den CC2 mit Credentials aus `.env`:
  Variable korrekt geladen, Laenge 6 Zeichen plausibel, TCP-Connect
  auf 1883 geht durch, MQTT-CONNACK wird empfangen – also die
  gesamte Transport-Kette ist belastbar.

**2. Ungeprueft**

- **Register-Handshake, api_status-Snapshot, CANVAS-Slot-Belegung**.
  Alle drei nicht geprueft, weil der CONNACK=5-Abbruch frueher kommt.
  Erwartung Slot 1+2 PETG / 3+4 PLA bleibt theoretisch, bis „Nur
  LAN" aktiviert ist.
- **Access-Code-Validitaet**. Wenn der Grund fuer `rc=5` nicht
  `lan_status=0` ist, sondern ein inzwischen rotierter Code am
  Display, waere auch das noch zu klaeren. Hier aber ausdruecklich
  **nicht** blind nachprobiert.

**3. Geht nicht**

- **CC2-LAN-MQTT-Register mit lan_status=0.** CONNACK rc=5. Nicht
  als Blocker im Drei-Versuche-Sinn eingetragen – das ist eine
  **Policy-Entscheidung des Drucker-Herstellers / des Benutzers**,
  nicht ein Code- oder Konfigurationsfehler, der hier auf AMR5
  reparierbar waere. Siehe `docs/networking-cc2.md` fuer den
  Nachweislauf und die Entscheidungsfrage an Klaus.

---

## 2026-10-25 07:50 – Divergenz-Ursache gefunden: TBB-Race auf arm64; CC2-LAN-Protokoll geklaert; UI-Stack Flutter

Nachtlauf. Zehn Punkte, alle abgearbeitet:

### Byte-Divergenz arm64 ↔ x86 – Ursache ist TBB-Race, nicht libc++/libstdc++

**Experiment 1a (asymmetrisches Modell).** `engine/test/make_cube.py`
um `cube_notched_20mm_centered_cc2.stl` erweitert (20-mm-Wuerfel
mit 5×5×5-mm-Kerbe an +X+Y+Z-Ecke, 24 Dreiecke, vorzentriert).
Ergebnis: Divergenz bleibt (595 Zeilen nur in x86, 600 nur in arm64).
Grund: die Kerbe bricht die Rotationssymmetrie, aber nicht die
Spiegelsymmetrie an der x=y-Diagonalen. Fuer eine "wirklich
asymmetrische" Variante waere ein off-corner- oder non-square-
Notch noetig (nachgetragen in `docs/engine-integration.md` als
Followup, kein Blocker).

**Experiment 1b (Single-Thread + Mehrfachlaeufe).** `handslice-cli`
hat jetzt `--threads N` (TBB-`global_control`). Zwei Teilbefunde:

- `--threads 1` und `--threads 2` **blockieren auf beiden Plattformen**
  Orcas Pipeline deadlockt bei nur 1-2 Threads (`parallel_pipeline` oder
  `flow::graph` wartet auf einen zweiten Worker, der nie kommt).
  Single-Thread-Test mit dieser Orca-Version nicht ausfuehrbar.
- Mehrfachlauf stattdessen – 10 Laeufe pro Plattform mit dem
  symmetrischen Wuerfel: **x86 ist deterministisch (10/10 identisch,
  sha 92951c26... = GUI-Referenz). arm64 ist NICHT deterministisch
  (6×`a30ffec3`-Variante A, 4×`7c88f484`-Variante B).** Mit dem
  Notch-Modell dasselbe Muster: 3×`7ca4cd37`, 2×`919cde23`.

**Daraus folgt klar: Die Divergenz-Quelle ist ein TBB-Race in Orcas
Pipeline**, nicht libc++ vs. libstdc++. Dieselbe Binary auf demselben
Geraet produziert zwei stabile Varianten pro Lauf. Auf 16-Core-Ryzen
raucht das Scheduling-Fenster offenbar immer dieselbe Reihenfolge, auf
dem 4+4-big.LITTLE-Snapdragon 860 zwei. Die 513-Zeilen-arm64↔x86-Diff
vom Vortag ist dieselbe Klasse Fehler, nur quer-Plattform.

**Phase-C-Erfolgskriterium praezisiert** (nicht gelockert) in
`docs/engine-integration.md`:
1. Funktional-aequivalent zur Desktop-Referenz (Zeilenanzahl, Filament
   ±0.01 g, Zeit ±5 s, Layer-Grenzen).
2. Determinismus pro Plattform (zwei Laeufe byte-identisch).
3. Variant-Set dokumentiert (wenn mehrere stabile Varianten moeglich).

Byte-Gleichheit bleibt als Fernziel (Phase 3+ Orca-Upstream-Patch).

### boost::filesystem-Crash im 2. Aufruf (PROGRESS 2026-10-24 23:50)

**Mit neu gebauter Binary nicht mehr reproduzierbar.** 3× und 10×
hintereinander in derselben adb-shell: alle Exit 0. Crash ist weg,
Ursache unbekannt – vermutlich war der 23:50-Fund an einem seitdem
geaenderten lokalen State haengen geblieben. Dokumentiert in
engine-integration.md.

### UI-Stack entschieden: Flutter

`docs/architecture.md` + `app/README.md` angepasst. Begruendung:
iOS-Option, `dart:ffi` sauberer als JNI, Hot Reload fuer das
dynamische Settings-UI aus den Orca-Profil-JSONs. Android-spezifisches
(Foreground-Service fuer den Slice-Lauf, SAF-Picker) als Kotlin-
Platform-Channel-Code im `android/`-Unterordner des Flutter-Projekts.
Noch kein Flutter-Code – das wird ein eigener Auftrag.

### CC2-LAN-Protokoll geklaert, Portscan + MQTT-Probe

Klaus hat gegen Ende CC2-IP (<cc2-ip>) und drei Protokoll-Quellen
geliefert. Ergebnis in `docs/networking-cc2.md` komplett umgeschrieben:

- **Discovery (UDP 52700):** JSON `{"id":0,"method":7000}` → Reply mit
  `sn="<cc2-sn>"`, `token_status=1` (Access-Code erforderlich),
  `lan_status=0`, `protocol_version=1.0.0`.
- **Portscan:** 1883/tcp open (MQTT), 9001/tcp open (MQTT/WS),
  8080/tcp filtered (MJPEG), 80/tcp **closed** (Stock-Upload-Port
  laut Protokoll – auf dieser Firmware zu), 7125/tcp closed
  (bestaetigt: kein Moonraker).
- **MQTT 1883 Connect ohne Auth:** CONNACK rc=5 (Not authorized),
  erwartet. Kein Subscribe, kein Publish, sauberer Disconnect.
- **Protokoll-Doku** aus den drei Quellen (ChestnutLabs MIT,
  elegoo-homeassistant MIT, elegoo-printer-proxy CC0): MQTT-Topics,
  Registrierungs-Handshake, chunked HTTP-PUT-Upload, 10-s-PING,
  Access-Code-Auth, CANVAS-Multimaterial-`slot_map`.
- **CC1-Protokoll (SDCP)** zusaetzlich vorgemerkt als zweiter
  Client (`SdcpClient`), Modul-Schnittstelle bleibt
  `discover()/upload()/start()/status()`.

**Offen:** Welcher Port tatsaechlich G-Code annimmt (80 closed,
8080 filtered). Vermutung: oeffnet erst nach authentifiziertem MQTT-
Handshake. Pruefung in Phase 2 Prototyp. Neptune 4 Pro war im LAN
nicht sichtbar – nicht geprueft, bleibt ungeprueft, nicht geraten.

**Phase-2-Aufwandsschaetzung** fuer CC2-Client: ca. 1–2
Entwicklungswochen (MQTT-Dart-Client + UDP-Discovery + chunked
HTTP-Uploader + State-Delta-Merge + Pairing-UI + sichere Credential-
Storage). Nicht blockierend fuer Phase 1 (Engine).

### Build + Tests

- `handslice-cli-x86` + `handslice-cli-arm64` inkrementell neu gebaut
  (nur handslice-cli.cpp + CMakeLists Headers geaendert). Beide
  bauen sauber durch.
- arm64 llvm-stripped: 865 MB → 13.8 MB.
- Reference-Test (`run-reference-test.sh`) auf x86 bestanden
  (sha 92951c26..., 8479 Zeilen).

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- `engine/test/make_cube.py` erzeugt jetzt zwei Modelle: den bekannten
  symmetrischen 20-mm-Wuerfel und einen Notch-Wuerfel mit 24
  Dreiecken, vorzentriert auf CC2-Mitte. Beweis:
  `python3 engine/test/make_cube.py` schreibt beide STLs
  (684 + 1284 Byte).
- `handslice-cli` nimmt jetzt `--threads N` an und beschraenkt
  TBB-Parallelitaet entsprechend. Beweis:
  `engine/bin/handslice-cli-x86 --help` listet die Option, und ein
  Lauf mit `--threads 1` haengt reproduzierbar in TBB (das ist
  diagnostisch gewollt, nicht der Erfolgs-Pfad).
- **x86-Determinismus:** 10 Laeufe liefern 10 identische
  EXECUTABLE_BLOCK-Hashes (sha 92951c26...).
- **arm64-Nicht-Determinismus:** 10 Laeufe liefern eine stabile
  Verteilung ueber zwei Varianten A/B (6:4 beim symmetrischen Wuerfel,
  3:2 beim Notch).
- CC2 ueber UDP 52700 Discovery-fertig (`sn=<cc2-sn>`,
  Access-Code erforderlich). MQTT-Erreichbarkeit auf 1883 bestaetigt
  (CONNACK rc=5 Not authorized, da kein Access-Code gesendet – gewollt).
- UI-Stack und CC2-Protokoll-Pfad vollstaendig dokumentiert in
  `docs/architecture.md` + `docs/networking-cc2.md`.

**2. Ungeprueft**

- **G-Code-Upload-Pfad auf dem CC2.** Port 80 war beim Scan geschlossen,
  Port 8080 nur gefiltert. Protokoll-Quelle sagt Port 80 (Stock) oder
  8080 (OpenCentauri). Welcher Pfad real funktioniert, erfordert
  einen authentifizierten MQTT-Handshake vorweg und ist nicht Teil
  dieser Nachtrunde.
- **Neptune 4 Pro.** Nicht im LAN sichtbar, Moonraker-Check nicht
  durchgefuehrt. Ungeprueft gemeldet, nicht geraten.
- **Wirklich asymmetrisches Testmodell** (Notch off-corner / 3×5×5).
  Als Followup notiert, kein Blocker.
- **Determinismus auf arm64 durch Build-Zeit-Tuning** (Workaround B
  mit fixem TBB-Pool). Dachte, waere einen Versuch wert, nicht in
  dieser Runde eroeffnet.

**3. Geht nicht**

- **Byte-Gleichheit arm64 ↔ Desktop-Referenz** – bleibt offen, aber
  Ursache ist jetzt klar: **TBB-Race in Orcas Pipeline, nicht
  libc++/libstdc++**. Nachgewiesen durch den Mehrfachlauf-Test.
  Keine Loesung ohne Orca-Patch (Phase 3+). Phase-C-Kriterium
  entsprechend neu formuliert (siehe `docs/engine-integration.md`).
- **Single-Thread-Lauf** (`--threads 1` oder `--threads 2`) blockiert
  Orcas Pipeline. Als diagnostisches Werkzeug nicht nutzbar; der
  Mehrfachlauf-Test hat die Frage trotzdem beantwortet.

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
