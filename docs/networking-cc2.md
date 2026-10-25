# An den CC2 (und spaeter CC1) senden

Zielgerät: **Elegoo Centauri Carbon 2** (CC2) Combo, CANVAS-Vierfarbsystem.
Zweitgeraet fuer non-Multicolor-Tests: **Elegoo Neptune 4 Pro** (Klipper/
Moonraker, Phase 2 abgedeckt durch denselben Moonraker-Client wie andere
Klipper-Drucker). Dieses Dokument ist primaer der CC2-Pfad.

**Wichtig:** Der CC2 spricht **kein Moonraker**. Fruehere Vermutung
(`curl http://<ip>:7125/server/info`) ist widerlegt – siehe Nachweislauf
unten. Der CC2 nutzt ein proprietaeres MQTT-basiertes Protokoll mit
HTTP-Chunked-Upload. Der CC1 nutzt wiederum ein anderes (SDCP, Topic-
basiert ueber WebSocket). Beide werden ueber die gleiche App-
Schnittstelle angesprochen, aber ueber zwei verschiedene Client-
Implementierungen.

## CC2-Protokoll (MQTT + HTTP PUT)

Quellen (**MIT**-/**CC0**-lizenziert, Protokoll-Details reverse-engineered,
nicht offiziell von Elegoo veroeffentlicht):

- `github.com/ChestnutLabs/printer-protocol-orchard`, Datei
  `protocols/elegoo.md` – Protokoll-Taxonomie fuer alle drei Elegoo-
  Modellreihen (Neptune → Moonraker, CC1 → SDCP, CC2 → MQTT). MIT.
- `github.com/danielcherubini/elegoo-homeassistant`, Datei
  `docs/CC2_PROTOCOL.md` – detaillierte Topic-Namen, Payloads,
  Discovery-Reply-Schema. MIT.
- `github.com/lantern-eight/elegoo-printer-proxy`, README – Beschreibung
  des `PUT /upload`-Chunking fuer den G-Code-Upload. CC0-1.0.

Keine Zeile aus diesen Repos uebernommen – wir nutzen sie nur als
Protokoll-Spezifikation.

### Discovery (UDP 52700, Broadcast)

Payload (JSON, UTF-8):

```
{"id":0,"method":7000}
```

Antwort (JSON, direkt vom Drucker):

```
{
  "id": 0,
  "result": {
    "sn": "<Seriennummer>",
    "host_name": "Centauri Carbon 2",
    "machine_model": "Centauri Carbon 2",
    "protocol_version": "1.0.0",
    "lan_status": 0|1,     // 1 = LAN-only Mode am Drucker-Display aktiviert
    "token_status": 0|1    // 1 = Access-Code noetig; 0 = Default-Passwort "123456"
  }
}
```

`sn` ist der Schluessel aller nachfolgenden MQTT-Topics.

### Registrierungs-Handshake (MQTT, Port 1883)

MQTT 3.1.1, TCP only (**kein TLS**).

**Auth:**

- MQTT-Benutzername: hartkodiert `"elegoo"`.
- MQTT-Passwort: `"123456"` wenn `token_status=0`, sonst der am
  Drucker-Display angezeigte Access-Code (dieselbe Zeichenkette wird
  auch als HTTP-Header `X-Token` beim Upload erwartet).

**Handshake (nach erfolgreichem CONNACK):**

1. Client subscribt `elegoo/<sn>/<request_id>/register_response`.
2. Client publisht auf `elegoo/<sn>/api_register`:

```
{"client_id": "<beliebige-id>", "request_id": "<zufaellig-hex>"}
```

3. Drucker antwortet auf `elegoo/<sn>/<request_id>/register_response`
   mit `{"client_id": "...", "error": "ok"}`.

**Danach:**

- Client subscribt `elegoo/<sn>/api_status` (Status-Push vom Drucker)
  und `elegoo/<sn>/<client_id>/api_response` (Antworten auf eigene
  Commands).
- Client publisht Commands auf `elegoo/<sn>/<client_id>/api_request`.
- Client sendet alle 10 s ein `{"type":"PING"}` auf
  `api_request`, erwartet `{"type":"PONG"}` auf `api_response`.
  Timeout seitens Drucker: 65 s – ausbleibende PINGs → Verbindung
  wird gekappt.

### G-Code-Upload (HTTP PUT 80, chunked)

**Stock-Firmware (laut Protokoll-Quelle):** HTTP PUT auf Port 80.
**OpenCentauri-Firmware:** derselbe Pfad auf Port 8080, zusaetzliche
Headers.

```
PUT /upload HTTP/1.1
Host: <ip>
Content-Range: bytes <offset>-<endInclusive>/<total>
Content-Type: application/octet-stream
X-File-Name: <name>.gcode      // nur OpenCentauri
X-File-MD5: <md5-hex>          // nur OpenCentauri
X-Token: <access-code>         // nur OpenCentauri (= MQTT-Passwort)

<Chunk-Payload, max 1 MiB>
```

Reihenfolge: 1 MiB-Chunks sequenziell, jeweils mit um 1 MiB
hochgezaehltem `Content-Range`-Offset. Antwort:
`{"error_code": 0, "offset": <last_byte>}`.

### Druckstart (MQTT api_request, method 1020)

Topic: `elegoo/<sn>/<client_id>/api_request`

```
{
  "id": 1,
  "method": 1020,
  "params": {
    "storage_media": "local",
    "filename": "benchy.gcode",
    "config": {"printer_check": true, "slot_map": []}
  }
}
```

Fuer CANVAS-Multicolor liegt das `slot_map`-Array voll (siehe
`protocol-orchard/elegoo.md`, Abschnitt CANVAS). `method 2005` liefert
die aktuelle CANVAS-Belegung.

**Nicht moeglich:** LAN-Resume (`method 1023`) ist auf CC2 deaktiviert
(siehe Quelle). Ein Druck, der durch Netz-Unterbrechung abbricht, kann
nicht per LAN fortgesetzt werden – nur ueber das Display.

### Status-Updates (MQTT api_status, event method 6000)

Delta-Updates (nur geaenderte Felder). Beispiel-Felder (unvollstaendig):

- `machine_status.status` – Enum 0–15 (Idle, Printing, Paused,
  Error, …).
- `print_status.progress` – 0–100 %.
- `print_status.current_layer`, `print_status.total_layer`.
- `extruder.temperature`, `heater_bed.temperature`.
- `gcode_move_inf.x/y/z/e` – aktuelle Toolhead-Position.

Status wird kontinuierlich gepusht; Clients muessen Delta-Merge gegen
einen eigenen letzten State machen.

### Port-Rollen (CC2)

| Port | Protokoll | Rolle | Open bei F01TDL55…? |
|---|---|---|---|
| 80 | HTTP | G-Code-Upload (`PUT /upload`, Stock-FW) | **closed** – siehe Nachweislauf |
| 1883 | MQTT/TCP | Kommandos, Status, Registrierung | open |
| 8080 | HTTP (MJPEG) | Kamera-Stream; OpenCentauri auch API | filtered (TCP akzeptiert, HTTP schweigt) |
| 9001 | MQTT/WebSocket | Web-UI (Browser-JS-Client) | open |
| 7125 | HTTP (Moonraker) | – | closed (bestaetigt kein Moonraker) |

Firmware auf dem Testdrucker scheint Port 80 nicht als Upload-Pfad
anzubieten. Welcher Pfad stattdessen genutzt wird (z. B. MQTT-
`method ...`-basierter Upload? Oder ist 80 erst nach Access-Code-
Freischaltung offen?), ist **offen**. Protokoll-Quelle sagt Port 80
oder 8080; auf diesem CC2 ist 80 geschlossen und 8080 nur gefiltert.
Weitere Pruefung nach erfolgreichem MQTT-Handshake (mit Access-Code)
noetig.

### UDP-Discovery sieht man nicht ueber mDNS

`avahi-browse -at` liefert fuer den CC2 **keinen** Service – der
CC2 nutzt kein mDNS, nur den UDP-52700-Broadcast. Die App-seitige
Discovery schreibt also einen UDP-Broadcast auf 255.255.255.255:52700
und sammelt die Antworten.

## CC1-Protokoll (SDCP, Topic-basiert)

Zum Vollstaendigkeits-Halber dokumentiert, obwohl kein CC1 im Haus
ist. Quelle: `protocol-orchard/elegoo.md`.

- **Transport:** WebSocket auf Port 3030.
- **Discovery:** UDP-Broadcast der Zeichenkette `"M99999"` auf Port
  3000, Antwort enthaelt `MainboardID` und `MainboardIP`.
- **Frame-Format:**

```
{"Id": "<UUID>", "Topic": "sdcp/request/<MainboardID>",
 "Data": {"Cmd": 128, "RequestID": "<hex>", "MainboardID": "..."}}
```

- Topics: `sdcp/request/<MainboardID>` (Client→Geraet),
  `sdcp/response/<MainboardID>` (Antworten),
  `sdcp/status/<MainboardID>` (Statusupdates).
- **Limit:** 5 gleichzeitige WebSockets, 60 s idle-Timeout.
- **Vorsicht:** unerkannte Befehle oder unvollstaendige Start-Befehle
  koennen den Printer-Daemon crashen (Quelle).
- G-Code-Upload: `POST http://<ip>:3030/uploadFile/upload`
  (multipart), `S-File-MD5`, `Check`, `Offset`, `Uuid`, `TotalSize`.
  Max 1 MB pro Chunk, zwischen Upload-Ende und Start-Befehl
  **mindestens 1 s warten**.

Separater App-seitiger Client-Baustein – nicht derselbe wie CC2.

## Modul-Schnittstelle (App)

```
discover()            → [Printer{sn, model, ip, protocol}]
upload(gcode, name)   → ok / Fehler
start(name)           → ok / Fehler
status()              → {state, progress, temps, layer}
```

**Drei Client-Implementierungen** hinter derselben Schnittstelle, in der
Reihenfolge ihrer Prioritaet:

- `ElegooMqttClient` – CC2 und spaetere MQTT-Elegoos. UDP-Discovery
  52700, MQTT 1883 (+ 9001 optional), HTTP PUT 80/8080.
- `MoonrakerClient` – Neptune-4-Pro-Serie und alle anderen
  Klipper-Drucker (HTTP 7125 + WebSocket). Phase 2 davon unberuehrt;
  Standard-Moonraker-API.
- `SdcpClient` – CC1 und Resin-Serie. UDP-3000-Discovery, WebSocket
  3030, HTTP-Multipart-Upload.

Phase 2 ist unabhaengig vom Engine-Build und kann parallel zu Phase 1
laufen.

## Aufwand-Schaetzung fuer Phase 2 (CC2)

**Was fertig/klar ist:**

- Protokoll-Spezifikation vorhanden (siehe Quellen oben).
- IP-Discovery, Portscan, MQTT-Erreichbarkeit nachgewiesen (siehe
  Nachweislauf unten).

**Was fehlt (ca. je ein App-Tag Aufwand pro Punkt):**

- MQTT-Client in Dart (`mqtt_client` Package auf pub.dev reicht fuer
  3.1.1-TCP), Topic-Routing + PING-Loop.
- UDP-Broadcast-Discovery (`RawDatagramSocket` in dart:io, Broadcast
  auf 52700).
- HTTP-PUT-Chunker fuer Upload (1-MiB-Chunks, `Content-Range`-Header,
  MD5-Hashing waehrend des Streams).
- Status-Delta-Merge: Lokaler State wird mit jedem Push-Event
  aktualisiert; UI reagiert auf State-Transitionen.
- Access-Code-Eingabe-UI (Pairing-Dialog beim ersten Verbinden).
- Credential-Speicherung – `flutter_secure_storage` fuer den
  Access-Code pro Drucker-SN.
- Error-Pfad: PING-Timeout → Reconnect, Upload-Netz-Abbruch (resumable
  via `Content-Range`-Offset – der Server sagt uns den letzten
  bestaetigten Offset in jeder Antwort).

**Was unklar ist (Risiko):**

- Welcher Port ist der tatsaechliche Upload-Pfad auf dieser Firmware?
  Port 80 war geschlossen beim Scan. Ob er sich nach dem MQTT-
  Register-Handshake oeffnet, muss im naechsten Lauf gegen diesen
  CC2 mit Access-Code gezielt getestet werden.
- CANVAS `slot_map`: Zusammenbau fuer Multimaterial ist spezifiziert,
  aber mit vier Filamenten pro Druck in der Praxis bisher nicht
  verifiziert.

**Grob insgesamt:** 1–2 Entwicklungswochen fuer einen voll
funktionsfaehigen `ElegooMqttClient`, inklusive Pairing-UI und
sauberer Reconnect-Logik. Nicht blockierend fuer Phase 1 (Engine).

## Nachweislauf 2026-10-25: Protokoll-Pruefung CC2 (<cc2-ip>)

**Umgebung:** AMR5 (192.168.0.172) im selben /24-Subnetz wie der CC2
(<cc2-ip>). Beide Drucker eingeschaltet; Neptune 4 Pro war beim
ersten Lauf nicht im LAN sichtbar, nur der CC2.

### Erreichbarkeit und Portscan

```
$ ping -c1 -W1 <cc2-ip>
→ Keine Antwort. CC2 blockt ICMP. (nmap -Pn umgeht das, siehe unten.)

$ nmap -sT -Pn -p 22,80,443,1883,5000,7125,8080,8883,9001 <cc2-ip>
22/tcp   closed   ssh
80/tcp   closed   http            (Stock-Upload-Port laut Protokoll – ZU)
443/tcp  closed   https
1883/tcp open     mqtt            (CC2-MQTT, Core-Kanal)
5000/tcp closed   upnp
7125/tcp closed   unknown         (bestaetigt: KEIN Moonraker)
8080/tcp filtered http-proxy      (TCP connect ok, HTTP schweigt – MJPEG-Signatur)
8883/tcp closed   secure-mqtt     (kein TLS-MQTT)
9001/tcp open     tor-orport      (MQTT ueber WebSocket, Web-UI)
```

### UDP-Discovery

Direkter Unicast an UDP 52700 (statt Broadcast, weil wir die IP
schon kennen):

```
$ python3  # send {"id":0,"method":7000} to <cc2-ip>:52700
UDP 52700 (CC2-Discovery): REPLY 169 byte:
  {"id":0,"result":{"host_name":"Centauri Carbon 2","lan_status":0,
   "machine_model":"Centauri Carbon 2","protocol_version":"1.0.0",
   "sn":"<cc2-sn>","token_status":1}}
```

- `sn=<cc2-sn>` wird fuer alle folgenden MQTT-Topics gebraucht.
- `token_status=1` → **Access-Code noetig**; MQTT-Passwort ist nicht
  `123456`. Access-Code steht am Drucker-Display.
- `lan_status=0` → LAN-only-Mode am Drucker nicht aktiviert.

UDP 3000 und UDP 3030 (CC1-SDCP) antworten erwartungsgemaess nicht
(der CC2 spricht SDCP nicht; der CC1 ist nicht im Netz).

### MQTT 1883 Connect ohne Auth

Minimaler MQTT-3.1.1-CONNECT-Rohpaketversand (Client-ID
`handslicecheck`, kein Username/Passwort, Keep-Alive 60 s). Keine
SUBSCRIBE, keine PUBLISH, keine Registrierung. Danach sauberer
DISCONNECT.

```
MQTT CONNACK: session_present=0 return_code=5 (Not authorized) in 52ms
```

Erwartet – ohne `elegoo`-Username + Access-Code-Passwort wird der
Connect zurueckgewiesen. CC2 erzwingt also Auth (gut).

### MQTT 1883 Connect MIT Auth (2026-10-25 08:15)

Zugangsdaten vorbereitet: `~/handslice/.env` enthaelt `CC2_IP` und
`CC2_ACCESS_CODE` (6 Zeichen). `.env` ist in `.gitignore` und auf
`chmod 600`. Der Code wird aus der Variable in das MQTT-Password-Feld
gesetzt und niemals in Logs/stdout/Docs geschrieben.

Discovery direkt davor erneut gelaufen – `token_status=1`,
**`lan_status=0`** (Nur-LAN-Modus bewusst aus, siehe Klaus-Vorgabe).

Testablauf mit `paho-mqtt 1.6.1` (`python-paho-mqtt`-Pacman-Paket):

- `username="elegoo"`, `password=<Access-Code aus .env>`
- `client_id="hsltest<4-hex>"` (lokal zufaellig)
- `request_id=<27 hex Zeichen>` (lokal zufaellig)
- MQTT 3.1.1, Clean Session, Keep-Alive 60 s
- Geplant: CONNECT → SUBSCRIBE 3 Topics → PUBLISH `api_register` →
  einmal `api_status` lesen → PING → DISCONNECT.

**Ergebnis:**

```
CONNACK rc=5  (0=accepted, 4=badcred, 5=notauthz)
```

Verbindung wird vom CC2 abgelehnt. Nach Klaus-Vorgabe
(„Wenn die Verbindung mit `Nur LAN` aus abgelehnt wird: Befund
dokumentieren und stoppen – NICHT selbst nach Workarounds suchen")
hier gestoppt. Kein Register-Request, kein Status-Lesen, kein PING.
Sauberer `DISCONNECT`.

**Mutmassliche Ursache:**

- **lan_status=0 ist der primaere Verdacht.** `rc=5` kam identisch
  schon beim Connect ohne Auth zurueck – also bevor Credentials
  ueberhaupt gegen irgendwas abgeglichen werden konnten. Der CC2
  reserviert den LAN-MQTT-Pfad vermutlich fuer den „Nur LAN"-Modus
  und akzeptiert sonst nur die Cloud-Session.
- Alternativ, aber weniger wahrscheinlich: der Access-Code wurde
  seit der Anzeige am Display inzwischen rotiert.

**Was Klaus entscheidet:**

- „Nur LAN" am Drucker-Display einschalten und Test wiederholen
  (hier dann weiterlaufen: Register-Handshake, api_status, PONG,
  CANVAS-Slot-Belegung lesen). ODER
- Cloud-Pfad fuer Phase 2 ausarbeiten – braeuchte Elegoo-Konto-API
  (Reverse-Engineering noch nicht gemacht).

### MQTT 1883 Register mit lan_status=1 (2026-10-25 08:35)

Klaus hat „Nur LAN" am CC2-Display aktiviert. Discovery erneut
gelaufen – `token_status=1`, **`lan_status=1`**. Alles andere wie
beim vorigen Lauf.

Testablauf identisch zum vorigen Script (gleiches Client-ID- und
Request-ID-Schema, user=`elegoo`, password aus `.env`):

```
CONNACK rc=0  (accepted)
SUBACK #1  granted_qos=(0, 0, 0)

PUB elegoo/<cc2-sn>/api_register
    {"client_id": "hsltest1582", "request_id": "140e5e96129c233ba9b12a95291"}
RX  …/register_response  (40 byte)
→ {"client_id": "hsltest1582", "error": "ok"}

Warte auf ersten api_status …
RX  …/api_status  (65 byte)
→ {"id": 3, "method": 6000, "result": {"heater_bed": {"temperature": 24}}}

PUB elegoo/<cc2-sn>/hsltest1582/api_request  {"type": "PING"}
RX  …/api_response  (15 byte)
→ {"type": "PONG"}

DISCONNECT
```

**Alles wie dokumentiert.** `lan_status=1` ist tatsaechlich der
Schluessel zur Freigabe des LAN-MQTT-Pfads. Register-Response-Fehler-
Feld = `"ok"`. PING/PONG ist round-trip-fertig. Keep-Alive-Loop
koennte jetzt stabil laufen.

**api_status ist Delta-only, nicht Snapshot.**

Der erste empfangene `api_status` enthaelt genau *eine* Aenderung
(hier: `heater_bed.temperature=24` → Drucker steht idle bei
Raumtemperatur). Volle Zustandsabbildung braucht einen von zwei
Pfaden:

- **Deltas aggregieren.** Beim Verbindungsstart alle Felder auf
  „unbekannt" setzen und mit jedem eingehenden `api_status` den
  lokalen State nach-mergen. In Phase 2 sinnvoll fuer die
  Live-Fortschritts-UI (Temperaturen, Progress, Position), weil
  der Drucker ohnehin kontinuierlich pusht, sobald sich was
  bewegt.
- **Explizite Query.** `method 2005` auf `api_request` (CANVAS-
  Slot-Request) fordert die aktuelle Slot-Belegung direkt an – ein
  Request/Response-Paar auf `api_response`. Fuer das initiale
  Slot-Mapping-UI (vor dem ersten Slice) der direkte Weg.

Beide Mechanismen sind reine READ-Operationen und beeinflussen den
Drucker nicht.

**CANVAS-Slot-Belegung (A1..A4):** war nicht im ersten
Delta-`api_status` enthalten. **Nicht geprueft** in diesem Lauf,
weil Klaus-Vorgabe „einmal api_status lesen" woertlich befolgt wurde.
Pruefung A1+A2 PETG, A3+A4 PLA bleibt offen und erfordert entweder
einen zweiten Testlauf mit `method 2005` oder laengeres Delta-
Sammeln. Nicht als Blocker, sondern als Phase-2-Prototyp-Aufgabe
notiert.

### Nachweislauf 2026-10-25 09:00: method 1002 Vollstatus + method 2005 CANVAS

Direkt nach dem Register-Handshake aus 08:35 zwei Request/Response-
Paare gefahren (nur Lesen):

**method 1002 (GET_STATUS):** vollstaendige Snapshot-Antwort,
Hauptbefunde:

```
machine_status.status      = 1  (Idle)
extruder.temperature       = 28 °C,  target = 0
heater_bed.temperature     = 24 °C,  target = 0
ztemperature_sensor.temp   = 25 °C
gcode_move                 = x=52.5, y=264.0, z=4.97  (geparkt)
print_status.enable        = false, filename=""
tool_head.homed_axes       = "xyz"
external_device            = camera=true, u_disk=false
```

**Kein `plate_type` / `bed_type`-Feld im Status.** Der CC2 meldet
nicht, welche Druckbettseite montiert ist. **Nicht geraten** – im
Statusschema (`extruder`, `heater_bed`, `print_status`, `tool_head`,
`external_device`, `fans`, `gcode_move`, `led`, `machine_status`,
`ztemperature_sensor`) gibt es dafuer kein Feld. Konsequenz: der
`curr_bed_type`-Wert aus dem G-Code (vom Slicer) laesst sich nicht
gegen den tatsaechlich am Drucker montierten Belag abgleichen – die
App kann den Nutzer nur bitten, zu bestaetigen, dass der Belag passt.

**method 2005 (GET_CANVAS_STATUS):** CANVAS-Slot-Belegung
(`canvas_info.canvas_list[0].tray_list[]`):

| Slot | tray_id | filament_type | filament_name  | filament_color |
|---|---|---|---|---|
| A1 | 0 | PETG | ELEGOO PETG            | #000000 schwarz |
| A2 | 1 | PETG | ELEGOO RAPID PETG      | #FFFFFF weiss   |
| A3 | 2 | PLA  | ELEGOO PLA PRO         | #000000 schwarz |
| A4 | 3 | PLA  | ELEGOO RAPID PLA+      | #FFFFFF weiss   |

**Erwartung A1+A2 PETG, A3+A4 PLA bestaetigt.** `active_canvas_id=0`,
`active_tray_id=-1` (kein aktiver Tray – Drucker idle),
`auto_refill=false`.

### Nachweislauf 2026-10-25 09:05: Slice + Upload Kerbenwuerfel

**Slice auf dem Poco X3 Pro:**

```
Modell: engine/test/cube_notched_20mm_centered_cc2.stl (20mm, +X+Y+Z
        Kerbe, 24 Dreiecke, pre-centered)
Profile: CC2 0.4 nozzle + 0.20mm Standard + Elegoo PLA @ECC2
Binary: engine/bin/handslice-cli-arm64 (arm64-v8a, Android 29)
Laufzeit: 0.83 s (adb-shell incl. overhead; davon ~0.7 s Compute)
G-Code: handslice_kerbenwuerfel.gcode, 220 261 Byte, 100 Layer
Stats-JSON: 1172.33 mm Filament, 2819.79 mm³, 3.52 g, 9m 25s
```

Im G-Code-Header stehen:

- `curr_bed_type = High Temp Plate`
- `first_layer_bed_temperature = 60`, `hot_plate_temp = 60`,
  `hot_plate_temp_initial_layer = 60`
- `M140 S60` als erster M140 im Executable-Block
- `M190 S[bed_temperature_initial_layer_single]` im
  `machine_start_gcode` → Heizen + Warten auf 60 °C vor dem Druck
  (Platzhalter wird in der Firmware aus dem Config-Block
  substituiert)

**Abgleich mit dem Druckerstatus:** Da der CC2 kein `plate_type`-Feld
meldet (siehe oben), ist ein maschineller Abgleich nicht moeglich.
Der Slicer hat „High Temp Plate" gewaehlt, weil das der
`default_bed_type`-Default aus dem CC2-Profil ist – unabhaengig
davon, welcher Belag am Drucker tatsaechlich montiert ist.
**Nicht als Widerspruch markiert, aber als blinder Punkt
dokumentiert.**

**Upload per HTTP PUT auf Port 80 (chunked, 1 MiB max):**

Port-80-Status nach `lan_status=1`: **open** (gestern 08:15 noch
closed – „Nur LAN"-Modus schaltet also neben MQTT auch den
Upload-Port frei).

```
PUT http://<ip>/upload
Headers:
  Content-Range: bytes 0-220260/220261
  Content-Type:  application/octet-stream
  X-File-Name:   handslice_kerbenwuerfel.gcode
  X-File-MD5:    49f070da14eabe095aba554478bdbe59
  X-Token:       <Access-Code aus .env>
Body:  Chunk 0..220260 (gesamter G-Code, <1 MiB, deshalb nur ein PUT)
```

Antwort HTTP 200 in 1507 ms:

```
{"error_code": 0, "offset": 220260}
```

`offset=220260` = letztes Byte-Index. Pro Chunk antwortet der CC2 mit
dem letzten quittierten Offset – fuer Resume-Logik bei groesseren
Dateien ist das der Marker, ab dem der naechste Chunk anfaengt.

**Dateiliste-Pruefung per MQTT (method 1044 GET_FILE_LIST):** die
Datei erscheint **sofort** im Listing (`storage_media=local`):

```
file count: 21
  - handslice_kerbenwuerfel.gcode     ← NEU
  - ECC2_0.4_alle_stempel_linien_2farbig_Elegoo PETG _0.12_3h10m.gcode
  - ...
```

**File-Detail (method 1046)** liefert:

```
filename:            handslice_kerbenwuerfel.gcode
size:                220 261 byte
layer:               100
print_time:          565 s  (= 9m 25s, deckt sich mit Slicer-Stats)
total_filament_used: 3.52 g
last_print_time:     0        (noch nicht gedruckt)
color_map:
  - { t: 0, name: "PLA", color: "#F2754E" }
```

Der `color_map[0]` kommt aus dem G-Code-Header (Orca schreibt da pro
Extruder einen Eintrag) und ordnet Tool-Index `t=0` einem PLA
zu – wichtig fuer das Slot-Mapping im Druckstart (siehe naechster
Abschnitt).

### Druckstart-Befehl vorbereitet (NICHT ausgefuehrt)

Fertige `method 1020`-Payload fuer den naechsten Lauf durch Klaus
(nach Sichtkontrolle am Drucker). Nicht gesendet. CANVAS-Slot A4
(= `tray_id=3`, RAPID PLA+ weiss) wird dem einzigen Tool-Index 0
zugewiesen; `printer_check=true` **und** `bedlevel_force=true`
schalten die Bettnivellierung vor dem Druck ein (die Protokoll-
Quelle beschreibt beide als unabhaengige Flags, siehe
`CC2_PROTOCOL.md` Tabelle `config`-Optionen; `bedlevel_force` ist
der dokumentierte Weg, Leveling vor jedem Druck zu erzwingen,
`printer_check=true` ergaenzt den auto-Leveling-Check):

```
Topic:   elegoo/<cc2-sn>/<client_id>/api_request
Payload:
{
  "id": 1,
  "method": 1020,
  "params": {
    "storage_media": "local",
    "filename": "handslice_kerbenwuerfel.gcode",
    "config": {
      "delay_video": false,
      "printer_check": true,
      "print_layout": "A",
      "bedlevel_force": true,
      "slot_map": [
        {"t": 0, "canvas_id": 0, "tray_id": 3}
      ]
    }
  }
}
```

Antwort kommt auf `elegoo/<sn>/<client_id>/api_response` mit
derselben `id`. Erfolgs-Payload (laut Quelle): `{"error_code": 0}`.

**Vor dem tatsaechlichen Senden pruefen (Klaus-Checkliste):**

- Belag „High Temp Plate" ist montiert und sauber (siehe
  `curr_bed_type` im G-Code; der Drucker meldet den nicht).
- A4-Slot enthaelt tatsaechlich das vorgesehene PLA-Filament und
  nicht leer / falschen Typ.
- Z-Offset ist aktuell, falls kuerzlich Belag gewechselt.
- Nozzle ist sauber.

### Fernzugriff: VPN zuerst, Elegoo-Cloud optional

LAN ist der primaere Pfad fuer den MVP. Fuer den Alltag ausserhalb
des Heim-WLANs stehen zwei Optionen, in dieser Reihenfolge:

**Weg 1 (empfohlen fuer die meisten Benutzer): VPN ins Heimnetz.**

Tailscale (einfach einrichtbar, kostenlos fuer bis zu drei Benutzer)
oder WireGuard (voll selbst gehostet, aber mehr Setup) im Heimnetz.
Das Smartphone verbindet sich wie zu Hause: die App spricht
weiterhin dasselbe LAN-Protokoll (`MQTT 1883`, `HTTP 80`), und der
Drucker denkt, der Client sei im Heim-WLAN. **Kein eigener App-Code
noetig** – wir dokumentieren die Einrichtung in einer kurzen
Anleitung, implementieren aber nichts selbst. Vorteil: funktioniert
sofort mit der LAN-Code-Base, keine Elegoo-API-Abhaengigkeit,
Daten verlassen das Heimnetz nicht.

**Weg 2 (nach MVP, optional): Elegoo-Cloud-Modul.**

PIN-basierte Kopplung ueber Elegoo-Server. Fuer Benutzer, die kein
VPN einrichten koennen oder wollen. In der App:

- Standardmaessig **AUS** (opt-in in den Einstellungen).
- In der UI klar als „ueber Elegoo-Server" gekennzeichnet, mit
  Hinweis dass Druckauftraege dadurch die Haende von Elegoo
  passieren.
- Zugangsdaten in `flutter_secure_storage` /
  Keychain / Android-Keystore, nicht im App-State.
- Implementierung aus **ElegooSlicer** (AGPL-3.0) ableitbar – AGPL
  ist mit unserer AGPL-Lizenz kompatibel, kein Lizenzkonflikt. Das
  Reverse-Engineering ist dort schon fuer die Desktop-Version
  gemacht; der Cloud-MQTT-Broker und das Pairing-API sind dort
  sichtbar.
- **Risiko:** Elegoo kann die Cloud-API jederzeit stillegend
  umbauen. Das Modul braucht Pflege; faellt es aus, fallen nur die
  Cloud-Benutzer darueber, nicht die LAN-/VPN-Benutzer. Deshalb
  bewusst **nachgereicht**, nicht Teil des MVP.

Reihenfolge in `docs/roadmap.md` Phase 2: **LAN (MVP) → VPN
(Doku, kein Code) → Cloud-Modul (nach MVP)**.

### Zusammenfassung des Pfads (nach erfolgreichem Handshake)

Zum spaeteren Nachbau in Dart:

1. UDP-Broadcast `{"id":0,"method":7000}` auf 52700,
   Antwort parsen → `sn`, `token_status`, `lan_status`.
2. Wenn `lan_status=0`: Nutzer bitten, „Nur LAN" am Drucker-Display
   einzuschalten (sonst CONNACK rc=5).
3. MQTT-Connect auf `<ip>:1883`, user=`elegoo`, password=Access-Code
   vom Display (bzw. aus Secure-Storage).
4. Subscribe `elegoo/<sn>/<request_id>/register_response`,
   `elegoo/<sn>/api_status`,
   `elegoo/<sn>/<client_id>/api_response`.
5. Publish `{"client_id","request_id"}` auf
   `elegoo/<sn>/api_register`; auf `{"error":"ok"}` warten.
6. Alle ≤ 10 s `{"type":"PING"}` auf
   `elegoo/<sn>/<client_id>/api_request`, Keep-Alive sichern.
7. Fuer initialen Snapshot: `method 2005` fuer CANVAS,
   `method <GET_STATUS>` fuer die uebrigen Felder (Zahl aus den
   Quellen zu klaeren) – oder einfach ein paar Sekunden `api_status`-
   Deltas aufsammeln.

### CANVAS-Slot-Belegung (noch nicht am Geraet verifiziert)

Erwartung laut Klaus: Slot A1+A2 PETG, Slot A3+A4 PLA. Pruefung
erfordert `method 2005`-Request ueber den jetzt funktionierenden
MQTT-Handshake oder laengeres Delta-Sammeln auf `api_status`. In
dieser Nachtrunde explizit nicht ausgefuehrt (Klaus-Vorgabe „einmal
api_status lesen"). Format laut Protokoll-Quelle:

```
canvas_list[].tray_list[]  — pro Slot 9 Felder, u. a.
   type   ("PLA"/"PETG"/"PETG-CF"/…)
   color  (6-Hex-String)
   nozzle_temp_min / _max
   remain (optional, kann null sein)
   tag_uid (optional, kann null sein)
```

Erwartung-Nachweis-Lauf: nach aktivierter „Nur LAN"-Freischaltung
pruefen, ob die Datenstruktur die vier Slots in der dokumentierten
Reihenfolge liefert und die Materialien stimmen. Das ist der Input
fuer die App-seitige Slot-Mapping-UI im MVP.

### HTTP-Probes

```
curl -I http://<cc2-ip>/        → connect-fail (Port 80 closed)
curl -I http://<cc2-ip>:8080/   → TCP connect ok, HTTP timeout 5s
curl    http://<cc2-ip>:7125/server/info → connect-fail
```

Port 8080 akzeptiert die TCP-Session, antwortet aber auf keine
HTTP-Methode (`HEAD /`, `GET /server/info`, auch nicht `GET /?action=
stream`). Das passt zur MJPEG-Camera-Signatur, deren Endpunkt
vermutlich einen anderen Pfad verlangt – oder zur gefilterten
Variante, die den MJPEG-Stream nur freigibt, wenn das Hostgeraet
authentifiziert ist.

### Protokoll-Konsequenz

- **Moonraker definitiv aus.** `networking-cc2.md` fuehrt deshalb keinen
  Moonraker-Pfad fuer den CC2 mehr.
- **Elegoo-MQTT-Client (`ElegooMqttClient`)** ist der Pfad; UDP-52700-
  Discovery + MQTT-1883-Register + chunked HTTP-PUT-Upload. Erstmaliges
  Pairing per Access-Code vom Display.
- **Upload-Port offen** ist dieser Firmware noch unklar – Port 80
  geschlossen, Port 8080 gefiltert. Muss nach dem ersten
  authentifizierten MQTT-Handshake erneut geprueft werden; Hypothese:
  Freischaltung erst durch die Session.

**Noch nicht gemacht (bewusst):**

- Access-Code am Display abfragen und MQTT-Register-Handshake
  tatsaechlich durchfuehren. Das waere nicht mehr „nur Pruefen", sondern
  die erste echte Session. Gehoert in den naechsten Auftrag (Phase 2
  Prototyp), nicht in diese Nachtrunde.
- Neptune 4 Pro im LAN pruefen – war nicht sichtbar. Ping-Sweep
  `192.168.0.0/24` lieferte drei Hosts: Gateway, Poco, AMR5. Mit
  dem Neptune ausgeschaltet steht die Pruefung des Moonraker-Pfades
  fuer die Neptune-4-Pro-Seite ebenfalls aus.
