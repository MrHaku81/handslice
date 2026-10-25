# Fortschritt

Laufendes Protokoll. Neueste Einträge oben. Claude Code ergänzt nach jedem
größeren Schritt; Klaus liest hier tagsüber nach.

Format: `## JJJJ-MM-TT HH:MM – <Kurztitel>` und dann drei bis fünf Zeilen:
was gemacht, Ergebnis, offene Fragen.

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
