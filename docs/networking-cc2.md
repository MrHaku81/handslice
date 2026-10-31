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

| Port | Protokoll | Rolle | Open bei dem CC2 im Haus? |
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

### Discovery in abgeschotteten Netzen: Broadcast schweigt, Unicast klappt

In manchen Heim-LANs antwortet der CC2 **nicht** auf UDP-Broadcasts
auf 52700 – weder auf `255.255.255.255` noch auf den Subnet-Broadcast
(z. B. `192.168.0.255`). Direkter **Unicast** an die bekannte IP
desselben Druckers (`<cc2-ip>:52700`) wird dagegen beantwortet.
Reproduziert mehrfach am 2026-10-26 in dem einen Testnetz, dasselbe
Verhalten wie beim `cc2_probe_delete.py`-Lauf aus der Vorphase.

**App-Workaround (steht in `tools/cc2-history-fetch.py` und
`~/upstream/run-cc2-probe.py` schon drin):** die Serial-Nummer
einmalig per Unicast-Discovery holen bzw. aus `.env`
(`CC2_SN=`) lesen und ab dann `--serial`/direkte IP nutzen. Die
`cc2-control`-Firmware von Neme77 greift zusaetzlich auf einen
Gateway-Ping-Weg zurueck.

**Mutmassliche Ursache (nicht hart belegt fuer CC2):** Issue
[danielcherubini#431](https://github.com/danielcherubini/elegoo-homeassistant/issues/431)
beschreibt fuer den **CC1**, dass dieser vor der Discovery-Antwort
einen Gateway-Ping laufen laesst; schlaegt der fehl (Router/VLAN
blockt ICMP, Gast-/IoT-Netz-Isolation, Firewall-Regeln), antwortet
der CC1 nicht. Ob der CC2 denselben Mechanismus hat, ist **nicht
nachgewiesen** – der Code aus `elegoo-link` zeigt keinen Gateway-
Ping, und ein eigener tcpdump-/strace-Nachweis am CC2 steht aus.
Das #431-Verhalten ist hier nur **Verdacht**, keine Diagnose.

Fuer die App bedeutet das praktisch:

1. UI muss den Fall „Discovery hat niemanden gefunden" sauber
   abfangen und erlauben, die IP manuell einzutragen (ist seit M4
   drin, siehe Pair-Dialog).
2. Nach erfolgreichem Pairing wird SN + IP persistent gespeichert;
   folgende Verbindungen gehen direkt, keine Broadcast-Discovery
   mehr. Ein wiederholter Broadcast-Fehlschlag im Alltag ist damit
   kein Blocker.
3. Falls Klaus / ein spaeterer Benutzer den Broadcast-Weg zurueck
   haben will: Router auf Multicast/Broadcast-Weiterleitung,
   Gast-/IoT-Netz-Isolation deaktivieren, oder im Zweifel den CC2
   ins Haupt-WLAN hinzufuegen.

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

### Nachweislauf 2026-10-25 09:18–09:34: Druck handslice_kerbenwuerfel.gcode (erfolgreich)

Klaus hat die Sichtkontrolle am Drucker gemacht (Bett sauber, Belag passt
zu „High Temp Plate", A4 mit RAPID PLA+ bestueckt) und den vorbereiteten
`method 1020`-Aufruf freigegeben.

**Druckstart-Request** (identisch zum vorbereiteten Payload im Abschnitt
darunter):

```
PUB elegoo/<cc2-sn>/<client_id>/api_request
    {"id":1914939019,"method":1020,"params":{
      "storage_media":"local",
      "filename":"handslice_kerbenwuerfel.gcode",
      "config":{"delay_video":false,"printer_check":true,"print_layout":"A",
                "bedlevel_force":true,"slot_map":[{"t":0,"canvas_id":0,"tray_id":3}]}}}

Antwort (nach 1 s):
{"id":1914939019,"method":1020,"result":{"error_code":0}}
```

**Verlauf (api_status-Delta-Merge, Zeit relativ zum Request):**

| t      | Phase | Beobachtung |
|---|---|---|
| 0 s      | Start-Response             | `error_code=0` |
| +1 s     | machine_status.status 2    | `None → 2` (Printing). Bett-Target 60, Nozzle-Target 140 (Pre-Heat laut `machine_start_gcode`). `bed_mesh_detect=true`. |
| +60 s    | Pre-Heat erreicht          | Bett 61/60, Nozzle 140/140, Toolhead geparkt. |
| +120 s   | Nivellierung Probe 1       | Position (120, 261, z=-0.6), Nozzle schwingt auf 164. |
| +180 s   | Nivellierung Probe 2       | (132, 124, z=3.06). |
| +240 s   | Nivellierung Probe 3       | (116, 140, z=3.03). |
| +300 s   | Finales Heizen             | Nozzle 209/210 (Drucktemp PLA), zurueck geparkt. |
| **+369 s (6:09)** | **Layer 1 erreicht** | `current_layer=1`. Druck beginnt. |
| +420 s   | Layer 6                    | (130.5, 135.6, z=1.2) |
| +480 s   | Layer 19                   | (137.8, 136.3, z=3.8) |
| +540 s   | Layer 32                   | (118.2, 136.3, z=6.4) |
| +600 s   | Layer 45                   | (118.6, 117.1, z=9.0) |
| +660 s   | Layer 58                   | (120.6, 135.1, z=11.7) |
| +720 s   | Layer 70                   | (119.0, 135.6, z=14.0) |
| +780 s   | Layer 82                   | (137.1, 125.1, z=16.4) |
| +840 s   | Layer 95                   | (137.8, 131.3, z=19.0) |
| +900 s   | Layer 100 erreicht, Cooldown | Bett-Target auf 0, Position (254.5, 3.5, z=80) – Toolhead parkt oben. |
| **+914 s (15:14)** | **Druck fertig** | `machine_status.status=2 → 1` (Idle). `print_status.state="complete"`. `print_duration=628s`, `total_duration=912s`, `current_layer=100`. |

**Keine Fehlermeldung.** `machine_status.exception_status` blieb leer, kein
error_code aus den api_response-Topics. Monitor exit nach 30 s im Idle.

**Zeit-Aufteilung:**

- Pre-Heat + Nivellierung + finaler Heat: 6 min 9 s (369 s).
- Reiner Druck Layer 1–100: 9 min 5 s (545 s).
  Slicer-Estimate aus den Stats: 565 s (9m 25s). Reale Zeit war
  **4 % unter dem Estimate** – akzeptabel.
- Gesamtzeit vom Request bis Idle: 15 min 14 s.

**Beobachtung zu `total_layer`:** Im finalen Snapshot steht
`total_layer=0`, obwohl `current_layer=100` erreicht wurde. Entweder
setzt der CC2 das Feld beim Abschluss zurueck, oder es wird nur im
Verlauf gepusht und nicht im End-Delta. **Nicht problematisch**, aber
fuer die App-UI-Logik: `current_layer` ist der verlaessliche Fortschritt,
`total_layer` nur solange `state in {"printing","paused"}`.

**Beobachtung zu `print_duration` vs. `total_duration`:**

- `total_duration=912s` ≈ Request-bis-Idle (914s), also die
  Komplett-Zeit inkl. Pre-Heat + Nivellierung.
- `print_duration=628s` ≈ reine Druckzeit + ein Teil des Setups
  (nicht exakt die 545s pur Druck).

Fuer die App-UI reichen beide als „geschaetzt verbleibend" ohnehin
nicht – wichtig ist `remaining_time_sec`, das waehrend des Drucks
in jedem api_status mitwandert.

### Nachweislauf 2026-10-25 09:47–10:05: Druck mit `delay_video=true` (Zeitraffer-Versuch, kein Video)

Zweiter Druck desselben Kerbenwuerfels, diesmal mit der aus
**elegoo-link** (Apache-2.0) identifizierten Zeitraffer-Option.

**Fundstelle:** `src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp:81`:

```cpp
param["config"]["delay_video"] =
    printerAttributes_.capabilities.printCapabilities.supportsTimeLapse
        ? startPrintData.enableTimeLapse
        : false;
```

Das ist das einzige Timelapse-bezogene Feld, das ElegooSlicer bei
`method 1020` setzt. Der Name `delay_video` ist irrefuehrend – in der
CC2_PROTOCOL.md der Home-Assistant-Integration steht „Delay start until
video streaming active", aber der ElegooSlicer-Quellcode mappt
`enableTimeLapse → config.delay_video`. **Der Code gewinnt.**

Weitere Konstanten aus demselben Datei:
- `src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp:1396` –
  `START_PRINT = 1020`.
- `src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp:1417` –
  `// {MethodType::EXPORT_TIMELAPSE_VIDEO, 1045}, // Export timelapse
     video, interface not designed yet`. **Method 1045 existiert, ist
  aber in elegoo-link noch nicht implementiert.**

**Druckstart-Payload** (`handslice_kerbenwuerfel_timelapse.gcode`,
inhaltlich identisch zum ersten Druck, 220 261 Byte, EXECUTABLE_BLOCK
sha256 `919cde23…` – die arm64-Variante B, weil TBB nicht
deterministisch; funktional aequivalent zu A):

```
PUB elegoo/<sn>/<client_id>/api_request
{
  "id": 1916658895, "method": 1020,
  "params": {
    "storage_media": "local",
    "filename": "handslice_kerbenwuerfel_timelapse.gcode",
    "config": {
      "delay_video":   true,        ← Zeitraffer-Flag
      "printer_check": true,
      "print_layout":  "A",
      "bedlevel_force": true,
      "slot_map":      [{"t": 0, "canvas_id": 0, "tray_id": 3}]
    }
  }
}

Antwort: {"id":1916658895,"method":1020,"result":{"error_code":0}}
```

**Verlauf (api_status Delta-Merge):**

| t | Phase | Beobachtung |
|---|---|---|
| 0 s | Start accepted | `error_code=0` |
| +1 s | status 2 (Printing) | Pre-Heat Bett 60, Nozzle 140 |
| +60 s | Pre-Heat | Nozzle 193 (steigt), Bett 62 |
| +120 s | Nivellierung | (128, 261, z=-0.6), Nozzle 148 |
| +180 s | Nivellierung | (116, 124), Nozzle 139 |
| +240 s | Z-Lift / Transit | z=384 (vermutlich Z-Null-Kalibrierung) |
| +300 s | Finales Heizen | Nozzle 210 (Druck-Temp PLA) |
| **+5:54 (354 s)** | **Layer 1 erreicht** | current_layer=1 |
| +6:00 | Layer 1 | (136.8, 123.5, z=0.2) |
| +7:00 | Layer 9 | (126.6, 117.5, z=1.8) |
| +8:00 | Layer 22 | (130.5, 135.6, z=4.4) |
| +9:00 | Layer 35 | (118.2, 116.7, z=7.0) |
| +10:00 | Layer 48 | (137.8, 136.3, z=9.6) |
| +11:00 | Layer 61 | (118.2, 116.7, z=12.2) |
| +12:00 | Layer 73 | (137.2, 120.4, z=14.6) |
| +13:00 | Layer 85 | (118.9, 128.9, z=17.0) |
| +14:00 | Layer 96 | (125.2, 117.5, z=19.2) |
| **+15:00 (900 s)** | **Druck fertig** | `machine_status.status: 2→1`, `print_status.state='complete'`. Toolhead parkt bei (52.5, 264, z=79.97). |
| +16:00 | Cooldown | Nozzle 163, Bett 56 |
| +17:00 | Cooldown | Nozzle 132, Bett 55 |
| +18:00 | Cooldown | Nozzle 109, Bett 53 |

**Keine Fehlermeldung** (`exception_status` leer).

**Status 12 (VIDEO_COMPOSING) wurde NIE beobachtet.** Der Status ging
direkt von 2 (Printing) → 1 (Idle) und blieb dort. Auch nach weiteren
3 min Beobachtung (Cooldown) kein Wechsel auf 12.

### Video-Suche danach (read-only, nichts geloescht, nichts geladen)

**method 1002 (GET_STATUS) nach dem Druck:**

```
machine_status.status = 1 (Idle)
sub_status            = 0
print_status.state    = ""   (geleert nach Idle-Transition)
```

Drucker ist ruhig, kein verzoegertes Composing.

**method 1044 (GET_FILE_LIST) auf allen bekannten storage_media:**

| storage_media | error_code | files | Video-Datei? |
|---|---|---|---|
| `"local"`    | 0 | 22 Dateien, inkl. beide `handslice_kerbenwuerfel*.gcode` | **nein** (kein .mp4/.avi/.mov/.webm/.mkv) |
| `"sd-card"`  | 0 | 0 Dateien | – |
| `"u-disk"`   | 0 | 1 Ordner `Filme/` (USB-Stick-Inhalt des Benutzers) | **nein** |

**method 1046 (GET_FILE_DETAIL) fuer `handslice_kerbenwuerfel_timelapse.gcode`:**

```
last_print_time:    0
total_print_times:  0
```

Beide Counter stehen auf 0, obwohl der Druck nachweislich erfolgreich
durchlief (Monitor-Log, Klaus-Sichtkontrolle). Entweder zaehlt die
Firmware diese Felder nicht, oder die Zaehlerlogik triggert erst
spaeter.

**method 1045 (EXPORT_TIMELAPSE_VIDEO) auf `storage_media="local"`:**

```
{"error_code": 1003}
```

Error 1003 = kein Erfolg; in `elegoo-link` ist diese Methode als
„interface not designed yet" markiert. Das Ergebnis bestaetigt:
Export auf LAN-Pfad existiert in der Firmware nicht als Request/
Response-Interface.

### Korrektur 2026-10-25 10:30: Zeitraffer wird AUFGENOMMEN

**Klaus hat das Video am Drucker-Display gesehen**, unter
Einstellungen → Reiter „Kamera". Damit:

- `delay_video=true` **wirkt** – die Aufnahme laendert
  nachweislich.
- Hypothese „Firmware entscheidet gegen Timelapse" aus dem Bericht
  10:10 ist **widerlegt**.
- Status 12 (VIDEO_COMPOSING) wurde vermutlich nur zu kurz
  gepusht, um im 60-s-Progress-Snapshot aufzutauchen. Fuer die App
  muss der Delta-Push-Handler Status 12 ohne Vorbedingung erfassen.

**Was damit offen bleibt:** der **WLAN-Abruf** des aufgezeichneten
Videos. Code-Recherche-Ergebnis siehe naechster Abschnitt.

### Code-Recherche 2026-10-25 10:35: Zeitraffer-Download-Pfad nicht belegt

Durchsucht: **elegoo-link** (Apache-2.0, Submodul von ElegooSlicer),
**ElegooSlicer**-Hauptbaum (AGPL-3.0), **HA-Integration**
`danielcherubini/elegoo-homeassistant` (MIT).

**Belegte Zeitraffer-/Kamera-APIs:**

| Fundstelle | Zweck | Belegt? |
|---|---|---|
| `elegoo-link/src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp:81` – `config.delay_video = enableTimeLapse` | Aufnahme einschalten | ✓ wirkt |
| `elegoo-link/.../elegoo_fdm_cc2_message_adapter.cpp:1413` – `// {MethodType::VIDEO_STREAM, 1042}, // Get camera video stream` | Live-MJPEG-Stream | auskommentiert, aber Firmware antwortet (siehe HA-Integration `const.py:74`) |
| HA-Integration `elegoo_printer/const.py:58-59` – `CC2_VIDEO_PORT=8080, CC2_VIDEO_PATH="/?action=stream"` | **Live-MJPEG-URL** `http://<ip>:8080/?action=stream` | ✓ (fuer Streaming, **nicht** gespeicherter Zeitraffer) |
| `elegoo-link/.../elegoo_fdm_cc2_message_adapter.cpp:1417` – `// {MethodType::EXPORT_TIMELAPSE_VIDEO, 1045}, // interface not designed yet` | Zeitraffer-Export (geplant) | **noch nicht entworfen**, Nummer 1045 ist in Realitaet GET_FILE_THUMBNAIL (siehe HA `const.py:78`) |

**Belegte LAN-Download-Pfade** (nur fuer G-Code):

```
GET /download?X-Token=<access>&file_name=<name>       (storage_media="local")
GET /download/sdcard?X-Token=<access>&file_name=...   (storage_media="sdcard")
GET /download/udisk?X-Token=<access>&file_name=...    (storage_media="udisk")
```

(`elegoo-link/.../elegoo_fdm_cc2_http_transfer.cpp:431-473`,
`generateDownloadUrl`.) **Kein eigener Pfad `/download/camera`,
`/download/video`, `/download/timelapse`** o. aehn. im Code.

**MQTT-Methoden mit Datei-Bezug** (aus HA `cc2/const.py` und
`elegoo-link/.../elegoo_fdm_cc2_message_adapter.cpp`):

```
1044 GET_FILE_LIST       (local/sdcard/udisk – kein camera/timelapse)
1045 GET_FILE_THUMBNAIL  (fuer G-Code-Thumbnails)
1046 GET_FILE_DETAIL
1047 DELETE_FILE
1048 GET_DISK_INFO       (zeigt nur eine 'internal'-Partition, s. u.)
1042 VIDEO_STREAM        (Live-MJPEG, nicht Timelapse)
```

**Nachprobe gegen den CC2 (lesend):**

- `method 1048 GET_DISK_INFO`:
  ```
  internal: total 488 MB, used 90 MB
  ```
  **Nur eine Partition.** Kein separater Video-/Timelapse-Speicher
  im Interface. SD-Card / U-Disk werden hier nicht als eigene
  Objekte gelistet, obwohl `method 1044` sie als storage_media
  akzeptiert – die Firmware exposes sie nur ueber die File-Liste.
- `method 1001 GET_PRINTER_ATTRIBUTES`: liefert Basis-Infos
  (Firmware OTA 02.01.01.07, SOC leer, MCU-Version leer),
  **keine `cameraCapabilities`-Struktur**. Die Capability-Flags
  baut ElegooSlicer selbst aus dem Status-Delta
  (`external_device.chassis_camera.configured`, siehe
  `elegoo_fdm_cc2_message_adapter.cpp:1148-1163`), nicht aus
  Attributes.
- `method 1045 GET_FILE_THUMBNAIL` mit `filename` fuer die
  Timelapse-G-Code-Datei: `error_code=1003` (vermutlich kein
  Thumbnail embedded).

**Fazit der Suche:**

Es gibt **keine dokumentierte LAN-API fuer den Abruf einer
Zeitraffer-Video-Datei** auf dem CC2 mit Original-Firmware. Weder
in ElegooSlicer/elegoo-link (dort explizit „interface not designed
yet"), noch in der HA-Integration (dort gibt es nur das
MJPEG-Live-Stream-Toggle, kein Datei-Download), noch im
Hauptbaum von ElegooSlicer.

**Fuer Klaus auf diesem Drucker gibt es damit zwei legitime Wege
zum Zeitraffer-Video:**

1. **Direkt am Drucker-Display anschauen** (Einstellungen →
   Kamera-Reiter) – wie heute geschehen.
2. **USB-Export**: Datei vom Drucker auf USB-Stick kopieren und
   dort ablesen. (Pfad / Button-Beschriftung am Display: nicht aus
   dem Code ermittelbar – muss Klaus am Drucker finden.)

**Keine Spekulation ueber hypothetische Pfade** wie
`/download/camera` oder `storage_media="timelapse"` – das waere
Raten. Falls Elegoo in einer kuenftigen Firmware-Version einen
LAN-Export freigibt (`EXPORT_TIMELAPSE_VIDEO = 1045` im
elegoo-link-Code steht ja als Platzhalter bereit), ziehen wir nach;
bis dahin bleibt der WLAN-Abruf **nicht Teil des MVP**.

### Zusammenfassung Zeitraffer-Fluss (Soll-Zustand nach dieser Nacht)

1. UI-Checkbox „Zeitraffer aufnehmen" aktiviert.
2. App setzt `method 1020 config.delay_video=true`.
3. Drucker filmt den Druck mit (Status 12 kurz, dann wieder Idle).
4. Video liegt an einem Pfad, der ueber MQTT/HTTP nicht abfragbar
   ist. Benutzer sieht/exportiert ueber Display oder USB.

Vor-Pruefung in der App moeglich (optional, siehe Phase 2+): aus
`api_status.external_device.chassis_camera.configured == 1`
ableiten, ob der CC2 den Zeitraffer-Pfad grundsaetzlich unterstuetzt
(`elegoo-link` zieht dort seine `supportsTimeLapse`-Capability).

### Beobachtung 2026-10-25: Zeitstempel im Video-Dateinamen weicht ab

Beim zweiten Realdruck aus der App (Druckbeginn 2026-10-25 ~18:05 MEZ,
`handslice_1792947629010.gcode`) hat der CC2 das aufgenommene
Zeitraffer-Video intern mit dem Zeitstempel **2026-10-26 01:00:53**
benannt. Die reale Druckzeit lag knapp sieben Stunden davor.

In der Nacht davor stand in Deutschland die Umstellung von Sommer- auf
Winterzeit an (MESZ → MEZ, 2026-10-25 03:00 → 02:00). Nur festgehalten,
keine Ursache behauptet: ob der Drucker die Umstellung nicht mitbekommt,
ob er in einer anderen Zone lebt, ob der Zeitstempel aus einer anderen
Quelle als der Status-Uhr kommt – offen. Konsistent mit dem M4-Befund,
dass die Druckeruhr im LAN-Modus laut `print_status` ohnehin nachlief
(dort ca. 1 h 33 min hinter UTC).

Fuer die App bleibt die Konsequenz: **keine Zeitstempel aus dem
Drucker als absolute Wall-Clock behandeln** – weder in der Restzeit
(bereits durch M4b abgefedert) noch bei der Zuordnung von
Zeitraffer-Dateinamen zum Druck. Fuer die Zuordnung reicht der
G-Code-Dateiname als Stabil-Schluessel.

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

### Nachweislauf 2026-10-25: method 1047 DELETE_FILE am echten CC2

> **ÜBERHOLT durch Block A am 2026-10-31** (siehe Abschnitt "Block A
> device test – results" am Ende dieses Dokuments). Das 1003 kam
> **nicht** daher, dass 1047 auf dieser Firmware generell nichts
> loescht, sondern daher, dass sowohl Key (`filename` statt
> `file_path`) als auch Typ (String statt Liste) nicht passten. Die
> damals akzeptierte Shape ist `{"storage_media":"local","file_path":
> ["<name>"]}` – damit kam `error_code=0` und 1044 zeigt die Datei
> anschliessend als geloescht. Der Rohbefund-Teil unten bleibt der
> Nachvollziehbarkeit halber stehen; die *Deutung* in diesem
> Abschnitt ist widerlegt.

Fuer upstream Issue
[danielcherubini/elegoo-homeassistant#432](https://github.com/danielcherubini/elegoo-homeassistant/issues/432)
gemessen. Firmware OTA 02.01.01.07, MCU/SOC-Version leer (wie bisher).

**Parameter-Beleg** (nicht geraten):

- `danielcherubini/elegoo-homeassistant/docs/CC2_PROTOCOL.md`
  Abschnitt „method 1047 (DELETE_FILE)" –
  Request `{"id":<int>,"method":1047,"params":{"storage_media":"local","filename":"<name>"}}`
  dokumentiert, Response explizit **nicht** dokumentiert (markiert
  als „Untested, no response captured").
- `danielcherubini/elegoo-homeassistant/custom_components/elegoo_printer/cc2/client.py:2577-2644`
  (`async def delete_file`) – sendet exakt diese Payload, Default
  `storage_media="local"`.
- `ELEGOO-3D/elegoo-link/src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp:1411` –
  `// {MethodType::DELETE_FILE, 1047}` **auskommentiert**.
- `ELEGOO-3D/elegoo-link/src/lan/adapters/elegoo_fdm_cc/elegoo_fdm_cc_message_adapter.cpp:994` –
  CC1-Opcode fuer DELETE_FILE waere `259`, ebenfalls auskommentiert.
- Volltext-grep im gesamten elegoo-link-Repo (243 .cpp/.h-Dateien):
  **keine** aktive `deleteFile(...)`-Signatur, kein `DeleteFileParams`,
  kein HTTP `DELETE`. ElegooSlicer selbst loescht am CC2 nach aktuellem
  main-Stand **nichts** aus dem LAN.

**D-3 Lauf gegen die eine selbst hochgeladene Testdatei:**

```
PUB  elegoo/<cc2-sn>/<cid>/api_request
  {"id":<rid>,"method":1047,"params":{"storage_media":"local",
                                      "filename":"handslice_delete_test_<ts>.gcode"}}

RX   elegoo/<cc2-sn>/<cid>/api_response  (13 ms)
  {"id":<rid>,"method":1047,"result":{"error_code":1003}}
```

Vorher: 24 Dateien in `local`, Testdatei genau 1× sichtbar.
Nachher: 24 Dateien in `local`, Testdatei **weiterhin da**, alle
anderen Dateien unveraendert. Klaus hat am Display bestaetigt, dass
die Testdatei nach dem Request weiterhin sichtbar war.

**D-4 Lauf gegen einen definitiv nicht existierenden Namen:**

```
PUB  method=1047 params={"storage_media":"local",
                         "filename":"handslice_does_not_exist_<ts>.gcode"}
RX   (10 ms) {"id":<rid>,"method":1047,"result":{"error_code":1003}}
```

Liste 24/24 identisch.

**Deutung** (Vermutung, nicht Befund):

Firmware OTA 02.01.01.07 antwortet auf `method 1047` immer sofort mit
`error_code=1003`, unabhaengig davon, ob die Datei existiert, und
loescht in keinem Fall. Derselbe `error_code=1003` kam frueher
schon zurueck fuer `method 1045` (`GET_FILE_THUMBNAIL`,
anfang M3-Lauf) sowie fuer `method 1045` mit `storage_media="local"`
ohne filename. `1003` scheint demnach ein generisches „not available
/ not implemented in this firmware" zu sein – aber das ist eine
**Vermutung**, keine Doku-Aussage.

Die HA-Integration-Semantik aus `cc2/client.py:2588-2592` passt zum
Befund: „`0` means printer did not refuse, not proof of deletion;
caller re-lists via method 1044". In diesem Lauf laufen die
Zuordnungen gegen die Erwartung – der Drucker refusiert mit 1003,
und das Re-Listing bestaetigt, dass nichts geloescht wurde.

### 1044-Dateiliste-Struktur (am realen Geraet gesehen)

Pro Eintrag (anonymisiert):

```
{"color_map":[{"color":"#F2754E","name":"PLA","t":0}],
 "create_time": 1792932614,
 "filename": "<redacted>",
 "last_print_time": 0,
 "layer": 100,
 "print_time": 565,
 "size": 220261,
 "total_filament_used": 3.52,
 "total_print_times": 0,
 "type": "file"}
```

`type: "file"` beobachtet; `"folder"` haben wir frueher bei
`storage_media="udisk"` gesehen (Verzeichnis `Filme`).

Bekannte `storage_media`-Werte (aus
`elegoo_fdm_cc2_http_transfer.cpp:431-473`, nicht geraten):
`"local"`, `"sdcard"`, `"udisk"`. In diesem Lauf: `local` = 23
`.gcode`-Dateien (+ Testdatei), `sdcard` + `udisk` jeweils 0.
**Keine Videos in der 1044-Liste**, obwohl Klaus zwei Zeitraffer-
Aufnahmen am Display sieht – bestaetigt die bisherige Feststellung,
dass Zeitraffer-Dateien nicht ueber die MQTT-Dateiliste exposiert
werden (siehe Abschnitt „Code-Recherche 2026-10-25 10:35:
Zeitraffer-Download-Pfad nicht belegt").

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

## Zeitraffer-Ablage: Quellenrecherche 2026-10-26

Lesender Durchgang durch zwei offen zugaengliche Repos (geklont nach
`/tmp/handslice-research/`, nichts gebaut, nichts installiert) und die
OpenCentauri-Doku. **Alle Belege Datei:Zeile sind auf diese Clones
bezogen; die konkreten SHAs stehen unten.**

Quellen:

- `elegooofficial/CentauriCarbon2` (GPL-3). Enthaelt neben dem
  Klipper-Portieranteil (`src/`, MCU) auch die vendor-eigene
  Linux-Anwendungsschicht `elegoo/` – darin den **AI-Kamera-Daemon**
  mit vollstaendigem Timelapse-Modul.
- `Neme77/centauri-carbon-2-community` (CC-Community-Firmware auf
  Basis exakt der Original-FW 02.01.01.07; nutzt den Original-
  `elegoo_printer`-Prozess, bietet aber eigenen MQTT-Client
  `cc2-control` – darin die vollstaendige **MQTT-Methodenliste**
  samt Semantik). Keine Firmware-Images in diesem Repo; nur
  Begleitcode und Doku.
- `docs.opencentauri.cc` – nur die oeffentlich lesbaren Seiten;
  **keine** verschluesselten Firmware-Pakete, kein Online-Unpacker
  benutzt.

Nicht geladen (bewusst, laut Auftrag): die Firmware-Datei
`cc2_eeb001_02.01.01.07_20260922210235.zip.sig` (laut Builder-PR #110
im Neme77-Repo), OpenCentauri-Decrypt-Tool
(`docs.opencentauri.cc/extras/cc2_update_decrypt.html`,
„firmware research only"), keine SquashFS-Entpackung. Private
Schluessel / AES-Key sind in keinem der Repos.

### Rohframe- und Video-Ablage (Elegoo-Repo, hart belegt)

**Dateisystem-Pfade** (`elegoo/extras/ai_camera/module/camera/time_lapse_photo.h:17-18`):

```
#define TIME_LAPSE_PIC_PATH   "/opt/usr/picture/"
#define TIME_LAPSE_VIDEO_PATH "/opt/usr/video/"
```

**Lebenszyklus eines Druckauftrags** (`elegoo/extras/ai_camera/module/util/time_lapse_control.cpp`):

- `Start(file_name, w, h, fps, total_frames)` legt
  `/opt/usr/picture/<name><YYYYMMDDHHMMSS>.temp/` an
  (`.cpp:28-46`; Zeitstempel aus `addTimestampToFilename(...)`
  `.cpp:161-186`, nutzt lokale Druckeruhr via `localtime_r`).
- `Capture(index, data, len)` schreibt pro Frame `0001.jpeg`,
  `0002.jpeg`, … (vier Stellen genullt, `.cpp:76-78`).
- `Close()` benennt das `.temp/`-Verzeichnis in das endgueltige
  `/opt/usr/picture/<name><ts>/` um – **aber nur, wenn
  `frame_count >= total_frames`**; sonst Loeschung
  (`.cpp:189-203`). Praktische Konsequenz: Zeitraffer ohne
  vollstaendige Frame-Zahl geht verloren.
- `Composite(video_name, w, h, fps)` legt einen Symlink
  `/tmp/pic_link → /opt/usr/picture/<video_name>`, ruft einen
  internen `ImageToVideoEncoder` auf, schreibt das MP4 nach
  `/opt/usr/video/<video_name>.mp4` und **loescht danach**
  `/tmp/pic_link` und `/opt/usr/picture/<video_name>/`
  (`.cpp:93-128`, speziell die beiden `rm -rf`-Aufrufe in
  Zeilen 119, 123; identisch auch in
  `module/camera/ai_camera.cpp:395-440`).

**Konsequenz fuer die Beobachtung „Frames bleiben liegen, beliebig
oft exportierbar":** Code sagt eindeutig, dass das Picture-Verzeichnis
beim ersten erfolgreichen Composite entfernt wird. Das MP4 bleibt in
`/opt/usr/video/` liegen. „Beliebig oft exportierbar" passt also zum
**MP4 auf dem USB-Stick kopieren**, nicht zu einem erneuten Composing
derselben Rohframes. **Vermutung** (nicht hart belegt): der zweite
USB-Export auf dasselbe Video laeuft deutlich schneller als die 26s
beim ersten – das wuerde die Theorie bestaetigen; ein konkreter Test
steht aus.

### FFmpeg-Encoder-Kommandozeile (fallback-Variante im Code)

Alte, in `#if 0` deaktivierte Fallback-Codepfade zeigen den direkt
aufgerufenen FFmpeg-Call
(`elegoo/extras/ai_camera/module/util/time_lapse_control.cpp:280-293`):

```
cpulimit -l 80 ffmpeg \
  -framerate <fps> -pattern_type glob -i '/tmp/pic_link/*.jpeg' \
  -vf "scale=<w>:<h>,format=yuv420p" \
  -c:v libx264 -f mp4 -preset ultrafast -thread_type slice -threads 1 \
  '/opt/usr/video/<name>.mp4.temp'
```

Der aktive Pfad in `02.01.01.x` nutzt stattdessen eine eingebettete
Encoder-Klasse `ImageToVideoEncoder` (`.cpp:110-114`); FFmpeg-Binary
liegt aber im Baum unter `elegoo/lib/ffmpeg/ffmpeg` und wird gebuendelt.
`cpulimit -l 80` begrenzt die Encoder-CPU-Last beim Composing –
erklaert, warum Status 12 bei kleinen Modellen schnell durch ist.

### AI-Kamera-Daemon (`ai_camera`) und sein Socket

- Daemon-Hauptprogramm: `elegoo/extras/ai_camera/main.cpp:40` haengt
  sich an `SOCKET_FILE`. Pfad in
  `elegoo/extras/ai_camera/module/comm/server_socket.h:21`:
  `#define SOCKET_FILE "/tmp/aicamera_uds"` (Unix Domain Socket).
- Kamera-Devices
  (`elegoo/extras/ai_camera/module/camera/uvc_config_info.h:26-28`):
  `/dev/video0` MJPEG, `/dev/video1` YUYV, `/dev/video2` H264.
- Logs: `/opt/usr/logs/ai_camera.log`
  (`elegoo/extras/ai_camera/module/logs/logs.cpp:22`).
- Live-Streamer: Port **8080** MJPEG
  (bestaetigt durch Community-Doku, siehe unten).
- Zusaetzlich eingebunden: **Agora.io** RTC-Pfad fuer Remote-Monitoring
  mit **hartkodiertem AppId/License/Token** im Repo
  (`elegoo/extras/ai_camera/module/camera/ai_camera.cpp:102-104` und
  `:483-487`). Fuer uns nur ein Hinweis darauf, dass es einen WebRTC-
  Weg gibt – nicht Teil der LAN-Nutzung.
- JSON-Kommandos (`ai_camera.cpp:164-197`):
  - `method="time_lapse"` mit `params.status` ∈ {`start` mit
    `mode`∈{`begin`,`continue`}, `capture` mit `index`, `stop`} –
    wird vom `elegoo_printer`-Prozess beim Druck gesendet, nicht
    direkt ueber MQTT.
  - `method="composite_video"` mit `params.video_name` – startet
    das Composing.
  - `method="ai_detection"`, `method="video_monitor"` (fuer RTC) –
    nicht Zeitraffer-relevant.

### MQTT-Methodenliste (Community-Code, vollstaendig)

Aus `centauri-carbon-2-community/cc2-control/web-src/src/lib/machine.ts:88-98`
plus `cc2-control/src/mqtt.c`. Zahlen und Namen stammen aus elegoo-link,
Semantik aus dem Code.

| Methode | Richtung | Zweck |
|---|---|---|
| 1002 | req  | GET_STATUS (bekannt aus 2026-10-25-Lauf) |
| **1019** | req  | **PRINT.ENABLE_TIMELAPSE** – `params.config.delay_video=bool`, VOR dem Druckstart, Reply erwartet |
| 1020 | req  | PRINT_START (bekannt). Nimmt eigenstaendig `config.delay_video` entgegen – ist elegoo-link-Weg; cc2-control nutzt stattdessen 1019 davor |
| 1029 | req  | SET_LIGHT (Kammerlicht via `params.power`), Code-Beleg `mqtt.c:316-341` |
| **1036** | req  | **GET_HISTORY** – liefert `history_task_list[]` mit Zeitraffer-Status |
| **1038** | req  | **DELETE_HISTORY** – `params.list=[task_id, …]`, Loescht Historien-Eintraege (inkl. zugehoerige Zeitraffer) |
| **1051** | req  | **TIMELAPSE_RENDERING** – `params.url=<time_lapse_video_url>`, startet Composing, Antwort kommt sofort; Fortschritt via `machine_status.status=12` |
| 2004 | req  | SET_AUTO_REFILL (`params.auto_refill=bool`) |
| 2005 | req  | GET_CANVAS (bekannt) |

**Fehlercodes** (`machine.ts:68-87`): `1003 = invalid_parameters`
(am 2026-10-31 im Block A **direkt bestaetigt**: mit der richtigen
`1047`-Shape antwortet dieselbe Firmware `error_code=0`, die 1003
war also im wortsinn ein Parameter-Fehler, nicht die frueher
vermutete generische "not available"-Antwort),
`1009 = busy`, `1012 = task_not_found`.

### Zeitraffer-Status in `history_task_list` (Community-Code, hart belegt)

Jedes Element der 1036-Antwort hat ein Feld `time_lapse_video_status`
(`cc2-control/src/history.h:37`,
`cc2-control/web-src/preview/plugin.ts:389-392`):

| Wert | Bedeutung (Code-Verhalten) |
|---|---|
| -1  | Feld fehlt in der Antwort |
| 0  | kein Zeitraffer |
| **1**  | Frames vorhanden, **nicht gerendert** → 1051 startbar |
| 2  | MP4 **gerendert und abrufbar** |
| **3**  | wie 1 – Rendering abgebrochen oder neu zu starten (`history.h:167` und `plugin.ts:792` behandeln 1 und 3 identisch als „renderbar") |

Weitere Felder pro Task:
`task_id` (72-Byte-ID), `task_name` (G-Code-Name), `task_status`
(1..3 = terminal), `begin_time`, `end_time`, **`time_lapse_video_url`**
(Form: `"picture/<name>"` oder `"video/<name>.mp4"`, siehe
`history.h:51-62`), `time_lapse_video_size`,
`time_lapse_video_duration`.

### Download-Pfad fuer das fertige MP4 (NEU – revidiert fruehere Aussage)

**Der 2026-10-25 geschriebene Satz „Keine dokumentierte LAN-API fuer
den Abruf einer Zeitraffer-Video-Datei" ist widerlegt.**

Beleg: `cc2-control/src/history.h:307-336`
(`timelapse_download_start`) erzeugt dieses HTTP-Request:

```
GET /download?X-Token=<access-code>&file_name=video/<name>.mp4 HTTP/1.1
Host: 127.0.0.1
Connection: close
```

Das ist derselbe Download-Endpunkt wie fuer G-Code (siehe weiter oben
im Dokument, Abschnitt „Belegte LAN-Download-Pfade"), nur mit
anderem `file_name`-Prefix:

```
file_name=video/<name>.mp4
```

Die cc2-control-Variante geht ueber Loopback (`127.0.0.1`), weil sie
auf dem Drucker selbst laeuft. **Vom LAN aus funktioniert derselbe
Pfad gegen `http://<cc2-ip>/download` mit demselben `X-Token`-Header
oder `X-Token`-Query – zu testen ist das noch; die Analogie zum
G-Code-Download macht es plausibel, aber nicht garantiert.**

### Status 12 Trigger und Progress

- `cc2-control/src/mqtt.c:362` (Kommentar):
  „1051 acknowledges a render request; machine state 12 reports its
  progress."
- `cc2-control/src/mqtt.c:895`:
  `if(c->have_machine_status && c->machine_status==12 && now - c->timelapse_requested < 600) c->timelapse_rendering = 1;`
  Rendering-Timeout 600s.
- Trigger-Wege, hart im Code belegt:
  1. **MQTT 1051 → Composite** (cc2-control-Pfad).
  2. **Display-Export (USB)** – vermutlich loest intern denselben
     `TimeLapseComposite(video_name, …)`-Pfad aus (siehe
     `elegoo/extras/ai_camera/module/camera/ai_camera.cpp:356-446`).
     Im Mitschnitt vom Vormittag haben wir Status 12 ohne vorheriges
     1051 gesehen – passt zu einem lokal am Display ausgeloesten
     Composite. **Vermutung**, nicht hart belegt.
- `sub_status 3020/3021` sind in der Community-Mapping-Tabelle NICHT
  aufgeloest (`cc2-control/web-src/src/lib/machine.ts:11-57` listet
  Status-2-Substates vollstaendig, Status-12-Substates gar nicht).
  3020 duerfte **Composing**, 3021 **Kopieren** sein – passt zur
  Display-Beschriftung („Video wird generiert"/„Video wird kopiert")
  und zur Reihenfolge im Mitschnitt. **Vermutung mit Display-Beleg.**

### sub_status-Codes des Druck-Status (Status 2)

Hart belegt aus `cc2-control/web-src/src/lib/machine.ts:11-57`:

| Code | Bedeutung |
|---|---|
| 1045, 1096 | heating_nozzle |
| 1081, 1082, 1086 | receiving_file |
| 1405, 1906 | heating_bed |
| 2075 | printing (Haupt-Zustand) |
| 2077 | completed |
| 2401 | resuming |
| 2501 | pausing |
| 2502, 2505 | paused |
| 2503 | stopping |
| 2504 | stopped |
| 2801, 2802 | homing |
| 2901, 2902 | auto_leveling |

Fuer Fehler-Code `exception_status 1243` findet sich im Code keine
Zuordnungstabelle. Klaus' Beobachtung („Filament-Zufuhrfehler,
PTFE-Schlaeuche") ist damit die autoritative Lesung; die App soll
`1243` als **Filament-Zufuhrfehler** lokalisieren.

### Prozess- und Pfad-Topologie des CC2

Aus `centauri-carbon-2-community/cc2-control/scripts/launch.sh:4-5`
und `start-firmware.sh`:

- `/opt/inst/cc2-control/…` – installierter Programmpfad (vermutlich
  read-only auf System-Partition).
- `/opt/usr/…` – persistente Partition. Wird vor Dienststart
  abgewartet; alle Nutzerdaten (Rohframes, Videos, Logs, Presets)
  liegen hier. Groesse laut unserem `method 1048`-Lauf: 488 MB
  gesamt, 90 MB belegt.
- Vendor-Hauptprozess: `elegoo_printer` (binary, nicht im Repo).
  Macht MQTT, Status, Druckfluss. `cc2-control` wartet mit
  `pidof elegoo_printer` auf dessen Startup
  (`launch.sh:28`).
- Vendor-Camera-Prozess: `ai_camera` (binary, nicht im Repo, aber
  Quelle in `CentauriCarbon2/elegoo/extras/ai_camera/`). Haengt an
  `/tmp/aicamera_uds` und `/dev/video*`.
- Panda-Moonraker-Bruecke: Community-Code startet `cc2-control`
  mit `--panda-port 7125` (`launch.sh:45`). Das erklaert, warum
  das Community-Firmware-Image eine Moonraker-Kompatibilitaet
  **nachruestet** – auf der **Stock-Firmware ist 7125 geschlossen**
  (unser Nachweislauf 2026-10-25).

### A/B-Partitionen und Update-Paket (OpenCentauri-Doku)

- A/B-Scheme ueber `swupdate`: Update schreibt den inaktiven Slot,
  der dann Boot-Slot wird (Quelle: `docs.opencentauri.cc/software/updates-cc2/`).
- Paketformat: `.zip.sig` ist Hull/Metadaten-Wrapper mit
  `*.swu.sig` (swupdate-Paket) + `*.json.sig` (Metadaten) darin.
  RootFS: **SquashFS** (laut OpenCentauri-Doku).
- Firmware-Namensstamm fuer unseren Stand (von Builder-PR #110 im
  Neme77-Repo, laut Websuche-Hinweis): `cc2_eeb001_02.01.01.07_20260922210235.zip.sig`.
  **Nicht heruntergeladen** – gehoert nicht in diesen Auftrag.
- Die OpenCentauri-Doku listet aktuell nur bis **02.01.00.00**;
  unser 02.01.01.07 ist in der oeffentlichen Doku nicht erfasst.
- Changelog 02.00.02.00 (OpenCentauri):
  **„Fixed the occasional mismatch between timelapse video filenames
  and print file filenames during export"** – belegt, dass der
  Video-Dateiname **direkt aus dem Druckdateinamen** abgeleitet wird
  (deckungsgleich mit `addTimestampToFilename` im Elegoo-Code).

### Community-Doku zum Kamera-Dienst

`centauri-carbon-2-community/docs/CAMERA_DIAGNOSTICS.md:1-10` sagt
explizit:
- „the CC2 camera's **vendor MJPEG streamer** (`ai_camera`,
  usually port **8080**)".
- Bekannter Thread-Leak-Bug in `ai_camera` → ihr Issue #160.
- Community-Patch `/opt/usr/cc2-control/camera/manage.sh`
  (`CAMERA_UPDATE.md:14`) oder alternativ
  `/opt/usr/cc2-camera-recovery-r2/manage.sh`
  (`CAMERA_UPDATE.md:17`). Diese Pfade **existieren nur mit
  installiertem Community-Patch**, nicht auf der Stock-Firmware.

### Beobachtete Verhaltens-Fakten (Klaus, zusammengefuehrt)

- Status 12 Substates: **3020 „Video wird generiert"**,
  **3021 „Video wird kopiert"** (Display-Beschriftung).
- **A/B-Test 2026-10-26 am Display:** gleiche G-Code-Datei zweimal
  gestartet, Lauf 1 **ohne**, Lauf 2 **mit** Zeitraffer-Schalter
  am Geraet. Lauf 1 erzeugte kein Zeitraffer-Material. **Die
  G-Code-Datei traegt kein Flag** – nur die Einstellung beim
  Druckstart zaehlt. Der 2026-10-25-Befund („`delay_video=true`
  in `method 1020` erzeugte Zeitraffer") hat damit zusaetzlich die
  Entsprechung: auch der Display-Toggle erreicht denselben Pfad.
- Zeitraffer am Display waehrend eines laufenden Drucks lassen sich
  **nicht nachtraeglich** aktivieren – die Entscheidung faellt beim
  Start.
- `exception_status 1243 = Filament-Zufuhrfehler` (mechanisch:
  PTFE-Schlaeuche). Klaus hat am Display fortgesetzt;
  `sub_status 2501→2502→2401→2402` sind die Pause/Resume-Codes
  dazu. In der App als „Filamentzufuhr-Fehler" lokalisieren, nicht
  als bloße Pause.
- USB-Export ist **immer manuell**: Stick einstecken, Zeitraffer am
  Display waehlen, Exportieren. Die 5 s zwischen `u_disk=true` und
  Status 12 im Mitschnitt sind Bedienzeit. Status 12 ist der
  **Export-/Composing-Zustand**, nicht die Aufnahme. In der App
  entsprechend als „Export laeuft" interpretieren.
- `chassis_camera.configured` taucht im passiven `api_status` auf
  diesem CC2 **nicht** auf. Der Workaround „fehlendes Feld =
  unterstuetzt" bleibt richtig (Phase-2 M5 Punkt 3).
- Druckeruhr-Drift: Video-Dateiname vom 25.10. trug Zeitstempel
  2026-10-26 01:00:53 bei realem Druck ~18:05 MEZ (siehe
  Abschnitt „Beobachtung 2026-10-25: Zeitstempel im Video-Dateinamen
  weicht ab" weiter oben). Begruendet durch die
  `localtime_r`-Nutzung im Elegoo-Code (siehe
  `time_lapse_control.cpp:166-172`): die Druckeruhr geht ins
  Dateinamens-Suffix ein, und die Uhr lief im LAN-Modus ~1h33 hinter
  UTC. Konsequenz fuer die App: **Zeitstempel aus dem Drucker
  nicht als absolute Wall-Clock behandeln**; fuer die Zuordnung
  Zeitraffer→Druck ist der G-Code-Dateiname der stabile Schluessel.
- Speicher: nur eine 488-MB-Partition (`/opt/usr`), 90 MB belegt
  (unser `method 1048`-Lauf). Rohframes bleiben dort liegen, bis
  Composite oder History-Delete sie entfernt. Fuer die App ist
  Speicheranzeige/Hinweis sinnvoll. (**Korrektur 2026-10-31,
  Block A**: `method 1047` loescht auf 02.01.01.07 sehr wohl –
  mit der richtigen Shape `{"storage_media":"local","file_path":
  [<name>]}`. Die frueheren 1003-Antworten lagen am Params-
  Format, nicht an der Methode. Fuer G-Code-Dateien im local-
  Storage ist 1047 damit der korrekte Delete-Pfad; `method 1038`
  bleibt der Pfad fuer History-Eintraege / Zeitraffer-Rohframes.)
- `method 1044` listet keine Videos; `method 1048` zeigt nur
  die eine Partition – deckt sich mit dem Code (video/ wird nur
  ueber 1036 exponiert, nicht ueber 1044).

### Revidierter Zeitraffer-Fluss (Soll fuer die App)

1. **Vor dem Druck** (optional, saubere Variante nach cc2-control):
   `method 1019 params.config.delay_video=true/false`, auf Reply
   warten (max. 1,5 s laut `mqtt.c:303`).
2. **Druckstart:** `method 1020 …` wie bisher. `config.delay_video`
   kann redundant hier gesetzt werden (elegoo-link-Weg); das
   bisherige Verhalten vom 25.10. zeigt, dass beide Pfade zum
   Ziel kommen.
3. **Waehrend des Drucks:** `ai_camera` legt Frames unter
   `/opt/usr/picture/<name><YYYYMMDDHHMMSS>.temp/`. Status 12 wird
   **nicht** waehrend der Aufnahme gesetzt.
4. **Nach dem Druck:** 1036 holt die History ab; der neue Task hat
   `time_lapse_video_status=1` (Frames vorhanden) und
   `time_lapse_video_url="picture/<name><ts>"`.
5. **Rendern (= Composite = MP4-Erstellung):**
   `method 1051 params.url="picture/<name><ts>"`. Status 12 /
   substate 3020 fuer bis zu 600 s; bei kleinem Modell wie unserem
   Testwuerfel ca. 26 s. Nach Erfolg:
   `time_lapse_video_status=2`, `time_lapse_video_url="video/<name><ts>.mp4"`,
   `time_lapse_video_size` + `_duration` gesetzt.
6. **Download:** `GET http://<cc2-ip>/download?X-Token=<access>&file_name=video/<name><ts>.mp4`.
   **Noch nicht am Drucker verifiziert – naechster Prototyp-Schritt.**
7. **Loeschen:** `method 1038 params.list=[task_id]` entfernt den
   Task und zugehoerige Zeitraffer-Rohdaten.
8. **USB-Export am Display:** entspricht funktional Punkt 5 (mit
   anschliessendem Kopieren auf USB-Stick, Phase 3021). Das
   erklaert den Mitschnitt-Befund „Status 12 beim USB-Export,
   nicht beim Druckende".

Der alte Abschnitt „Zusammenfassung Zeitraffer-Fluss" (Soll-Zustand
nach 2026-10-25) weiter oben ist durch diesen revidiert.

### Clones-Metadaten

- `elegooofficial/CentauriCarbon2` – shallow-Clone 2026-10-26 08:12,
  Default-Branch, keine persoenlichen Daten im Repo.
- `Neme77/centauri-carbon-2-community` – shallow-Clone 2026-10-26 08:12,
  Default-Branch. Hinweis des Repos: „private keys, AES key, and
  original firmware are not in this repo". Hat keine Firmware-Images,
  nur Begleitcode.
- Clones liegen unter `/tmp/handslice-research/`; nicht im
  Projekt-Repo, keine Build-Caches erzeugt.

## Realtest 2026-10-26: 1036 + HTTP-Download gegen Stock 02.01.01.07 bestaetigt

Lesender Realtest, umgesetzt mit `tools/cc2-history-fetch.py` (Register
+ `method 1036` + Idle-Vorpruefung) und `tools/cc2-timelapse-download.py`
(HTTP-GET). Kein `method 1051`, kein Druckstart, kein Loeschen.
Antworten SN-anonymisiert nach `docs/cc2-history-sample.json`
abgelegt (das vollstaendige Sample liegt dort).

### method 1036 (GET_HISTORY)

- Request: `{"id":<rid>,"method":1036}` auf
  `elegoo/<cc2-sn>/<client_id>/api_request`.
- Antwort: 13 661 Byte JSON auf
  `elegoo/<cc2-sn>/<client_id>/api_response` innerhalb < 1 s.
  `result.error_code = 0`, `result.history_task_list` mit **45
  Eintraegen**. Keine Pagination noetig (bestaetigt den cc2-control-
  Kommentar „1036 returns the whole print task list").
- Eintrags-Felder (gleichbleibend, aus dem echten Sample):
  `begin_time`, `end_time` (Unix-Sekunden, lokale Druckerzeit),
  `task_id` (UUID-String), `task_name` (G-Code-Dateiname),
  `task_status`, `time_lapse_video_status`, `time_lapse_video_url`,
  `time_lapse_video_size`, `time_lapse_video_duration`.
- `task_status`: in den 45 Eintraegen nur 1 oder 2 beobachtet.
  Deutung aus cc2-control (`history.h:107`): terminale Werte 1..3.
  **1 duerfte „normal beendet" sein, 2 „abgebrochen"; nicht hart
  belegt in diesem Lauf.**

### time_lapse_video_status in freier Wildbahn

Verteilung der 45 Tasks:

| video_status | Anzahl | url-Form | Interpretation |
|---|---|---|---|
| 0 | 38 | `""` | kein Zeitraffer gefilmt |
| 1 |  2 | `picture/<name><ts>` | Rohframes vorhanden, nicht gerendert |
| 2 |  5 | `video/<name><ts>.mp4` | MP4 gerendert und abrufbar |
| 3 |  0 | – | nicht in diesem Sample vorgekommen |

Das deckt sich mit der Interpretation aus `cc2-control/src/history.h:51-62`
und `plugin.ts:792` **vollstaendig**:

- `video_status=0` ↔ `video_url=""`.
- `video_status=1` ↔ `video_url` beginnt mit `picture/`.
- `video_status=2` ↔ `video_url` beginnt mit `video/` und endet
  auf `.mp4`; `video_size` > 0.

### Spiegel der heutigen zwei Testdrucke

| begin_time (UTC) | Dateiname | task_status | video_status | video_url | video_size |
|---|---|---|---|---|---|
| 2026-10-26T06:25:11 | handslice_1792947629010.gcode | 1 | **0** | `""` | 0 |
| 2026-10-26T06:38:07 | handslice_1792947629010.gcode | 1 | **2** | `video/handslice_1792947629010.gcode20261026143807.mp4` | **1 741 634** |

Die Spiegelung ist exakt wie erwartet:

- **Lauf 1 (ohne Zeitraffer-Schalter am Geraet):** `video_status=0`,
  keine Rohframes aufgezeichnet.
- **Lauf 2 (mit Zeitraffer-Schalter):** `video_status=2`, Pfad liegt
  bereits unter `video/`, `video_size` ≠ 0. Das Composite ist beim
  USB-Export um 2026-10-26 06:50:54 UTC durchgelaufen (Mitschnitt
  Status 12, Substates 3020→3021 → 1 in 26 s), hat die Rohframes
  nach `/opt/usr/video/<name><ts>.mp4` gerendert und den
  `video_status` von 1 auf 2 hochgesetzt.
- Der Dateinamens-Zeitstempel `20261026143807` entspricht nicht
  dem Druckstart (06:38:07 UTC) sondern einer Druckeruhr-Zeit:
  **~8 h 00 min nach UTC bei 06:38:07 UTC-Druckstart**. Die
  Druckeruhr-Drift aus 2026-10-25 (dort ~1h33 hinter UTC, nach
  MESZ→MEZ-Umstellung) hat sich inzwischen offenbar auf eine
  andere Zeitzone geshiftet (vermutlich UTC+8 oder MESZ-Zuordnung
  defekt). **Nur Beobachtung, keine Ursache behauptet.**

### Weitere beobachtete Tasks (Auszug)

- `handslice_kerbenwuerfel.gcode` (2026-10-25 08:18 UTC, der
  erste Realdruck ohne Zeitraffer): `video_status=0`. Deckt sich
  mit dem Beobachtungsprotokoll vom 25.10.
- `handslice_kerbenwuerfel_timelapse.gcode` (2026-10-25 08:47
  UTC, der 25.10.-Zeitraffer-Testdruck mit `delay_video=true`):
  `video_status=2`,
  `video/handslice_kerbenwuerfel_timelapse.gcode20261025164702.mp4`
  (1 813 428 Byte). Das 25.10.-Timelapse-Testvideo liegt also
  **noch immer** als MP4 im `/opt/usr/video/` – Zeitraffer-Dateien
  bleiben nach dem Composite erhalten, bis sie explizit per
  `method 1038` geloescht werden.
- `handslice_1792947629010.gcode` (2026-10-25 17:00 UTC, zweiter
  Realdruck aus der App mit Timelapse): `video_status=2`,
  Dateinamens-Zeitstempel `20261026010053` – deckt sich **auf
  die Sekunde genau** mit dem bisher dokumentierten
  „Zeitstempel 2026-10-26 01:00:53 bei realem Druck ~18:05 MEZ".
  Belegt, dass dieser Dateinamen-Timestamp aus einer anderen
  Zeitquelle als der aktuellen Druckeruhr kommt.
- Vier aeltere Tasks (Oktober 2026) tragen den gleichen Dateinamen
  mehrfach – der Drucker vergibt pro Druckstart eine eigene
  `task_id` und einen eigenen Dateinamen-Zeitstempel; Zeitraffer
  werden pro Druckauftrag isoliert gefuehrt.

### HTTP-Download: `GET /download?X-Token=<access>&file_name=<url>`

Direkt gegen den Drucker (nicht nur Loopback!) mit genau der
`time_lapse_video_url` aus 1036 und dem Access-Code als `X-Token`-
Query-Param:

```
GET /download?X-Token=<access>&file_name=video%2Fhandslice_1792947629010.gcode20261026143807.mp4
Host: <cc2-ip>
```

Antwort (Response-Header):

```
HTTP/1.1 200 OK
Content-Length: 1741634
Content-Disposition: attachment; filename="video/handslice_1792947629010.gcode20261026143807.mp4"
Transfer-Encoding: chunked
```

- `Content-Length` passt exakt zu `time_lapse_video_size` aus 1036.
- `Content-Length` **und** `Transfer-Encoding: chunked` zusammen
  gesetzt (RFC-9112-Verstoss) – der cc2-control-Code warnt davor
  (`history.h:269-273`) und bevorzugt Chunked, wenn der Body wirklich
  chunk-framed ist. Fuer uns ist das nur ein App-seitiger
  Hinweis: HTTP-Clients sollten entweder beide Rahmungen tolerieren
  oder streng chunked lesen.
- `Content-Disposition.filename` ist unschoen (enthaelt den
  relativen Pfad `video/...`), aber nicht blockierend.

Lokal gespeichert nach `local-test/handslice_1792947629010.gcode20261026143807.mp4`
(1 741 634 Byte, md5=e2330f840b398f425172b32692437f7a).

`ffprobe`-Ergebnis:

```
format_name   = mov,mp4,m4a,3gp,3g2,mj2
codec_name    = h264
codec_type    = video
width x height= 640 x 360
r_frame_rate  = 30/1
nb_frames     = 100
duration      = 3.30 s
bit_rate      = 4 222 143 bit/s
size          = 1 741 634 byte
```

**Konsistenz-Check:** Der Druck hatte 100 Layer. Das Video hat
genau 100 Frames bei 30 fps → **1 Frame pro Layer**. Das passt zur
Elegoo-Code-Logik, dass `Capture(index, …)` mit layer-synchronem
Index aus dem Hauptprozess aufgerufen wird.

### Konsequenz fuer die App

- `method 1036` liefert die vollstaendige Druckhistorie samt
  Zeitraffer-Status; **keine Alternativlogik noetig**.
- `GET /download?X-Token=<access>&file_name=<time_lapse_video_url>`
  funktioniert gegen den Drucker direkt vom LAN aus. Derselbe
  Endpunkt wie fuer G-Code (siehe fruehere Nachweislauf-Abschnitte),
  nur anderer `file_name`-Prefix.
- `method 1051` haben wir **nicht** gebraucht und auch **nicht
  gesendet** – der Zeitraffer von Lauf 2 war bereits gerendert.
  Nur noetig fuer Tasks mit `video_status=1` (dann wuerde der
  App-Flow lauten: Zustand 1 → 1051 senden → auf Status 12 warten
  → 1036 erneut → `video_status==2` abgleichen → Download).
- Keep-Alive-Thema: der heutige Lauf hat **ohne PING** stabil
  funktioniert, aber nur <30 s dauernd. Fuer App-Sessions > 60 s
  bleibt der 10-s-PING auf `api_request` empfohlen (nach wie vor,
  siehe oberer Abschnitt).

### Was damit widerlegt / revidiert ist

- „Keine dokumentierte LAN-API fuer den Abruf einer Zeitraffer-
  Video-Datei auf dem CC2 mit Original-Firmware" (Nachweislauf
  2026-10-25) ist **widerlegt**. Der Pfad existiert, ist nicht
  dokumentiert, aber reproduzierbar und stabil.
- `method 1036/1051` stehen damit auch auf Stock 02.01.01.07
  erwiesenermaßen zur Verfuegung (nicht nur im Community-Image).
  Ihre Verhalten unterscheidet sich damals von `method 1045/1047`,
  die auf dieser FW nur `error_code 1003` lieferten – **fuer
  1047 am 2026-10-31 (Block A) widerlegt**: 1047 funktioniert
  mit der richtigen Shape (`file_path` als Liste); 1045 wurde
  nicht erneut gegen Orcas Shape (`file_name` statt `filename`)
  gegengeprueft und bleibt offen.

## Test E 2026-10-26: method 1047 Parameter-Shape-Probe (danielcherubini#432)

> **ÜBERHOLT durch Block A am 2026-10-31** (siehe "Block A device
> test – results" am Ende dieses Dokuments). Alle 11 Varianten
> von Test E hatten `filename`/`file_name` als Key und einen
> **String** als Wert; keine davon traf die akzeptierte Form
> `{"storage_media":"local","file_path":[<name>]}` (Key
> `file_path`, Wert **Liste**). Das Probe-Ergebnis ("1047 nicht
> served") war im Rahmen der getesteten Shapes korrekt, als
> Gesamt-Aussage ueber die Methode aber falsch. Rohdaten unten
> bleiben zur Nachvollziehbarkeit.

Lesender Beitrag zu Issue #432 des HA-Integration-Repos
`danielcherubini/elegoo-homeassistant`. Repo-Tag `v2.16.0-beta.2`,
Skript `scripts/cc2_probe_delete.py`. Repo liegt unter
`~/upstream/elegoo-homeassistant/` (nicht im Handslice-Repo).

Credential-Uebergabe via Wrapper `~/upstream/run-cc2-probe.py`:
Access-Code wird direkt an `probe()` als Python-Objekt uebergeben,
nie in `argv`/`environ`/Shell-History. Scrub-Skript
`~/upstream/scrub-cc2-probe.py` ersetzt IP/SN/Access-Code durch
Platzhalter; `grep`-Verifikation beider Capture-Artefakte: **0
Treffer**.

### Hypothesen-Matrix: 11 Varianten

Jede Variante lud eine eigene Probe-Datei hoch
(`cc2_probe_<slug>_<8-hex>.gcode`, 8 244 B, hand-generierter G-Code),
schickte **genau einmal** `method 1047` mit abweichendem Params-
Shape und prueft via 1044-Nachlisting, ob die Datei entfernt wurde.

### Ergebnis: **11/11 identisch `error_code=1003`, 11/11 `still_listed=True`**

| # | Params | error_code | still_listed |
|---|---|---:|:-:|
| 1 | `{"storage_media":"local","filename":<name>}` ← aktuelles delete_file-Format | 1003 | True |
| 2 | `{"storage_media":"local","file_name":<name>}` ← **die #432-Hypothese** | 1003 | True |
| 3 | `{"storage_media":"local","filename":<name>,"path":"/"}` | 1003 | True |
| 4 | `{"storage_media":"local","file_name":<name>,"path":"/"}` | 1003 | True |
| 5 | `{"filename":<name>}` | 1003 | True |
| 6 | `{}` (Control, nennt keine Datei) | 1003 | True |
| 7 | `{"storage_media":"sdcard","filename":<name>}` | 1003 | True |
| 8 | `{"storage_media":"sdcard","file_name":<name>}` | 1003 | True |
| 9 | `{"storage_media":"udisk","filename":<name>}` | 1003 | True |
| 10 | `{"storage_media":"sd-card","filename":<name>}` | 1003 | True |
| 11 | `{"storage_media":"u-disk","filename":<name>}` | 1003 | True |

Response-Latenz pro Variante: 9.5–20 ms. Firmware aus `method 1001
software_version.ota_version`: `02.01.01.07`. Modell:
Centauri Carbon 2. MCU/SOC-Versionen leer wie bisher.

### Conclusion aus dem Probe-Report

Zitat (anonymisiert, aus `scripts/cc2_probe_20261026_092850.json`):

> EVERY VARIANT ANSWERED IDENTICALLY (error_code 1003) and none of
> them removed its own file (all 11 confirming 1044 read(s) saw the
> variant's own file still listed). That is a real finding. What it
> means: on this firmware 1003 is not about the parameter key at all
> — 1047 is simply not served, or 1003 is its generic 'not
> available / not handled' answer. The key-name hypothesis is not
> supported by this capture.

**Konsequenz fuer die App** (urspruengliche Fassung, inzwischen
revidiert): `method 1047` auf dieser Firmware fuer nichts
verwenden. Zum Entfernen von Zeitraffer-/G-Code-Dateien bleibt
der Display-Pfad die einzige Option; History-Entries werden ueber
`method 1038` entfernt (siehe Test D) – ohne Datei-Loeschung.

**Revision 2026-10-31 (Block A):** 1047 ist auf fw 02.01.01.07
sehr wohl benutzbar, nur mit der Shape
`{"storage_media":"local","file_path":[<name>]}` (Key `file_path`,
Wert als Liste). Fuer G-Code-Dateien im local-Storage ist 1047
damit der richtige Delete-Pfad in der App. Zeitraffer-Videos
blieben untouched von diesem Test – fuer die bleibt der 1038+
Display-Weg vorlaeufig gueltig, bis jemand eine 1047-Shape mit
`storage_media=video` o. ae. nachtestet.

### Leftovers am Drucker nach dem Lauf

Nachpruefung via `method 1044 params.storage_media="local"`:
**12 Probe-Dateien** liegen auf dem Drucker (1 Preflight aus dem
Trockenlauf + 11 Varianten aus `--run`), je 8 244 B:

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

Klaus entfernt sie am Drucker-Display. ~96 KB belegt (von 488 MB).

### Noch offen fuer upstream

Die alternative Lesung von 1003 („generische 'not available / not
handled'-Antwort") ist durch diesen Lauf **nicht widerlegt** –
genauso wie die Key-Name-Hypothese **nicht gestuetzt** wird. Der
Capture ist eine klare Negativ-Antwort fuer die Key-Name-Hypothese
und ein guter Anlass, in #432 die Diskussion vom „welcher Key?"-
Pfad abzuhaengen.

Capture- und Report-Artefakte (anonymisiert) liegen unter:

- `~/upstream/elegoo-homeassistant/scripts/cc2_probe_20261026_092850.json.scrubbed`
- `/tmp/cc2-run-stdout.txt.scrubbed`

Diese sind das Paste-Material fuer den Issue-Kommentar auf #432.
Noch nicht gepostet – Klaus entscheidet.

### Discovery-Hinweis fuer das Script

Im Heim-LAN hat die Broadcast-Discovery (255.255.255.255 **und**
Subnet-Broadcast 192.168.0.255) nicht funktioniert; direkter
Unicast an `<printer-ip>:52700` antwortet jedoch. Workaround im
Wrapper: SN explizit setzen (`--serial`), Discovery wird vom
Script dann uebersprungen. Fuer upstream wert, als „discovery over
broadcast is unreliable; prefer unicast or an explicit serial" zu
melden.

---

## Test F 2026-10-26: 1051-Erfolgsfall belegt (App am echten CC2)

Phase-5-App-Realtest durch Klaus, 2026-10-26 12:07 MEZ (= ca. 11:07
UTC). Nach den Tests A–E war der 1051-Erfolgsfall (`3020→3021`) ueber
MQTT der einzige noch offene Punkt. Dieser Lauf schliesst ihn.

### Ablauf

1. Druck mit Zeitraffer aus der App gestartet (Fach **A3**, PLA Pro
   schwarz; freie Fachwahl funktioniert). Zeitraffer-Flag ging ueber
   den etablierten `method 1020 config.delay_video=true`-Pfad.
2. Druckende, Historie-Eintrag mit `video_status=1` + URL
   `picture/<name><ts>` erschien in der App.
3. In der App „Video erzeugen" → App schickt
   `method 1051 params.url="picture/<name><ts>"`.
4. App beobachtet `machine_status.status`-Wechsel 1 → 12 → 1 und
   holt dann `method 1036` erneut.
5. Target-Eintrag wechselt auf `video_status=2`, URL ist jetzt
   `video/<name><ts>.mp4`; Head-Probe liefert HTTP 200.
6. Download aufs Handy ueber den App-Button, Teilen via
   Android-Share funktioniert.

### Belegte Fakten

- **1051 erzeugt tatsaechlich ein MP4** – das vorher nur
  USB-Export-wege bewiesene Composite ist jetzt auch per MQTT real.
- Video-Eigenschaften: **640×360, 100 Frames, 3,3 s**. Deckt sich
  mit dem heute-frueh-USB-Composite (siehe „Realtest 2026-10-26:
  1036 + HTTP-Download") – gleiche Aufloesung, gleiche Framezahl,
  gleiche Dauer. **Der Encoder-Pfad fuer MQTT-Rendern und
  Display-/USB-Rendern ist derselbe.**
- Head-Probe erkennt die bereits am Display geloeschten alten
  Zeitraffer korrekt als „nicht mehr verfuegbar" (Timeout statt
  Download-Button) – das ist das Live-Verhalten des stale-History-
  Pfads aus Test E.

### Beobachtung: Display zeigt beim MQTT-1051 nichts an

Beim **USB-Export** (`06:50:54` UTC heute frueh) zeigte das Drucker-
Display zuerst „Video wird generiert" und kurz vor 100 % „Video
wird kopiert" (passt zu sub_status `3020 → 3021`, siehe
docs-Abschnitt „Historie ist stale" weiter unten).

Beim **MQTT-1051** zeigt das Display laut Klaus **keinen Dialog**
und keinen Fortschritt. Der Status wandert nur in den
`api_status`-Deltas. Fuer die App bedeutet das:

- **Fortschrittsanzeige geht ausschliesslich ueber MQTT**, nicht
  ueber eine Display-Interaktion. Der aktuelle Spinner-Pfad
  (`machine_status.status == 12` → zurueck auf 1) ist der einzige
  Signalweg und reicht.
- Benutzer am Drucker merkt waehrend eines App-ausgeloesten
  Composite nichts; das ist nicht schlimm, aber als Erwartungs-
  Setzung dokumentiert.

### Composite-Dauer (ungemessen in diesem Lauf)

Der passive MQTT-Mitschnitt (`tools/mqtt-sniff.py`) lief in
diesem Realtest **nicht**, also fehlt die exakte Zeitachse
`3020 → 3021`. Groessenordnungs-Vergleich:

- USB-Export heute frueh (`06:50:54 → 06:51:20` UTC) bei
  demselben 100-Frame-Video dauerte **26 s** (`3020 → 3021 → 1`).
- Klaus' User-Sicht beim App-Lauf: der App-Spinner „Erzeugt
  Video…" war „nicht lange" sichtbar; keine Minutenschleife.
- **Vermutung** (nicht gemessen): App-1051 liegt in der gleichen
  Groessenordnung wie der USB-Export (zehnersekunden), weil der
  Encoder-Pfad identisch ist.

Konkrete Messung beim naechsten App-Lauf, falls Klaus Lust hat:
`tools/mqtt-sniff.py` vorher starten, dann „Video erzeugen"
drueken. Dann steht die Zeitachse im JSONL.

### Was damit entschieden ist

- Der komplette Zeitraffer-Fluss der App (`1036` → `1051` →
  `machine_status==12` → `1036` + Head-Probe → `/download`)
  **funktioniert in jedem Schritt gegen die echte Firmware
  02.01.01.07**.
- `1051` ist **in beiden Formen** nutzbar: USB-Export durch den
  Benutzer am Display, oder MQTT-1051 durch die App. Beide
  Pfade teilen sich den `ai_camera`-Composite-Code
  (siehe `elegoo/extras/ai_camera/.../time_lapse_control.cpp`).
- Der offene Punkt „Erfolgsfall `3020→3021` ueber MQTT" aus Test
  B/C ist damit **geschlossen** – wenn Rohframes tatsaechlich
  noch vorhanden sind (frischer Druck, kein USB-Export dazwischen),
  rendert `1051` sauber durch.

---

## Historie ist stale: 1036 kennt geloeschte Zeitraffer nicht (2026-10-26)

Entscheidender Befund **nach** dem 1051-Test weiter unten, der den
1051-Test retrospektiv **ungueltig** macht:

Klaus hat heute frueh (vor dem ersten 1036-Lauf) **alle alten
Zeitraffer am Drucker-Display geloescht**, bis auf den heutigen
Lauf 2. In der Zeitraffer-Liste am Display stand danach nur noch
der Eintrag von 2026-10-26 (Druckeruhr 14:38:07, Dauer 4 s).

`method 1036` zeigt die davon nichts: alle vier Status-2-Eintraege
und beide Status-1-Eintraege sind nach wie vor in der Historie –
inklusive URLs, Groessen und IDs. **1036 spiegelt den Zustand
zum Druckzeitpunkt, nicht den aktuellen Dateisystem-Zustand.**

### Nachweis: Download-Probe auf alle Status-2-Eintraege

`tools/cc2-timelapse-probe.py` – ein GET pro URL, Header-Read mit
8 s Timeout, kein `method 1051`, kein Druckstart.

| URL (ts im Dateinamen) | video_size | head_ms | HTTP | Ergebnis |
|---|---:|---:|:-:|:-:|
| `video/ECC2_0.4_Box+w+hygromerer+TPU_PolyLite PETG _0.12_7h24m.gcode20261019110021.mp4` | 9 912 573 | 8 453 | – | **timeout** |
| `video/handslice_kerbenwuerfel_timelapse.gcode20261025164702.mp4` | 1 813 428 | 8 200 | – | **timeout** |
| `video/handslice_1792947629010.gcode20261026010053.mp4` | 1 762 496 | 8 093 | – | **timeout** |
| `video/handslice_1792947629010.gcode20261026143807.mp4` (**heute**) | 1 741 634 | **74** | **200** | **ok** |

Byte-genauer Gegentest: der heutige Download liefert dieselben
1 741 634 Byte mit md5 `e2330f840b398f425172b32692437f7a` wie beim
Vormittags-Lauf.

**Verhalten des Druckers bei nicht mehr existentem `file_name`:
komplettes Schweigen auf Protokollebene** – kein 404, kein 403,
kein leerer Body, keine TCP-Reset-Antwort. Der TCP-Handshake geht
durch, die Request-Zeile wird geschickt, und dann wartet der Client
in den Response-Headern aus. Erst der eigene Read-Timeout
terminiert die Session. Das deckt sich mit dem Kommentar in
`cc2-control/src/history.h:250-251`:
„A wrong token or name is answered with silence, hence the
receive timeout."

**Konkret fuer die App bedeutet das:**

- `Content-Length` oder HTTP-Status prueft nichts – der Drucker
  liefert sie nur fuer vorhandene Dateien. Fuer die Fehlerbehandlung
  reicht ein **Short-Read-Timeout** (~2 s auf den Response-Head);
  antwortet er in der Zeit nicht, ist die Datei weg und der
  History-Status 2 ist stale.
- `method 1036` ist eine Datenbank-Historie, kein Verzeichnislisting.
  Status 2 heißt „irgendwann mal gerendert"; Status 1 heißt
  „irgendwann mal gefilmt" – keine Garantie, dass die Datei jetzt
  noch da ist. **Einziger verlaesslicher Existenz-Nachweis bleibt
  der HTTP-GET.**

### Konsequenz fuer den 1051-Realtest (siehe naechster Abschnitt)

Der Test gegen `fac849a1` war damit nicht „gescheitert", sondern
**ungueltig**: die Rohframes zu diesem Druck existierten laut
Display zu keinem Zeitpunkt am Nachmittag mehr. Der Composite
hatte schlicht **nichts zum Rendern** – daher `3022` statt `3021`,
daher der Durchlauf in unter einer Sekunde. **`3022` steht
vermutlich fuer „keine Frames vorhanden", nicht fuer „Composite
abgebrochen".** Ohne frischen Testdruck mit erhaltenen Rohframes
laesst sich die eigentliche Zielfrage („Funktioniert 1051 als
LAN-Trigger?") **nicht beantworten** – der naechste Zeitraffer-
Druck, bevor Klaus den Stick benutzt, ist dafuer der richtige
Moment.

Die Hypothese „1051 funktioniert prinzipiell" bleibt aus den
Code-Belegen bestehen (`cc2-control/src/mqtt.c:362-372`); nur
unser Realnachweis fehlt.

### Druckeruhr: Offset 2026-10-26

Fuer den heutigen Lauf 2 belegen zwei unabhaengige Quellen den
Druckeruhr-Offset:

- Realer Druckstart (MQTT-Timestamp unseres Mitschnitts, in UTC):
  2026-10-26T06:38:07 UTC.
- Realer Druckstart in MEZ (lokale Wall-Clock): 07:38:07.
- Display des Druckers (laut Klaus) in der Zeitraffer-Liste:
  2026-10-26 **14:38:07**.
- Zeitstempel im Dateinamen aus `method 1036`: `20261026143807`.

**Daraus:**

- Druckeruhr liegt **+7 h gegen MEZ**, **+8 h gegen UTC**.
- Entspricht naemlich UTC+8 (China Standard Time) – auch wenn der
  Drucker in Deutschland steht.
- Der Stand aus `localtime_r` (siehe `time_lapse_control.cpp:166-172`)
  ist diese Druckeruhr-Zeit; sie wandert damit **in beide
  Richtungen** (gestern „1h33 hinter UTC" nach MESZ→MEZ-Umstellung,
  heute „+8h vor UTC"). Vermutlich konfiguriert das Display diese
  Zone und die Datenbank-/Dateinamen-Logik liest sie ohne weitere
  Korrektur ab.

**App-Regel:** Dateinamen-Zeitstempel aus `time_lapse_video_url`
oder begin_time/end_time aus `history_task_list` **nie** gegen
Echtzeit abgleichen oder in UI-Formate wie „heute vor 2 h"
rendern. Nur als Reihenfolge-Schluessel verwenden.

### App-Regel (Zusammenfassung dieses Befunds)

1. `method 1036` cachen und anzeigen; Zeitstempel als opake
   Ordnungs-Schluessel behandeln.
2. **Download-Button nicht an `video_status==2` haengen**, sondern
   an einen GET-Probe-Call: 2 s Timeout auf den Response-Head.
   Antwortet der Drucker, ist das Video da; sonst „nicht mehr
   verfuegbar" anzeigen und (optional) `method 1036` erneut lesen
   – auch wenn die Historie wahrscheinlich stale bleibt.
3. Nach `method 1051` den Erfolg nicht an `error_code` oder
   `status==1 nach 12` festmachen – stattdessen den GET-Probe-Call
   auf die Ziel-URL benutzen. Nur `HTTP 200 + Content-Length>0`
   gilt als Erfolg.
4. `sub_status 3022` als „keine Frames zu rendern" interpretieren
   (nicht als „Fehler" im klassischen Sinn).

---

## Test A 2026-10-26: haengender Request blockiert nicht

Fragestellung: wenn die App parallel mehrere Downloads anstoesst
und einer davon in eine stale-URL faellt (= Drucker schweigt),
blockiert das die anderen?

Setup (`tools/cc2-probe-parallel.py`): drei Baseline-Probes gegen
den heutigen Download, dann ein hangender GET auf eine **geloeschte**
Status-2-URL (ohne Timeout, bis zu 30 s), waehrenddessen parallel
ein Probe gegen den heutigen Download, dann noch ein Post-Hang-Probe.

### Ergebnisse

| Phase | connect_ms | send_ms | head_ms | total_to_head_ms | HTTP |
|---|---:|---:|---:|---:|:-:|
| Baseline run 1 | 14.1 | 0.1 | 15.9 | 30.1 | 200 |
| Baseline run 2 | 415.5 | 0.2 | 12.4 | 428.0 | 200 |
| Baseline run 3 | 369.7 | 0.1 | 12.0 | 381.8 | 200 |
| **Probe DURING hang** | 140.7 | 0.1 | **20.3** | 161.0 | **200** |
| Post-hang | 281.4 | 0.1 | 12.2 | 293.7 | 200 |

Der haengende Request belegte eine Verbindung voll (`connect_ok` nach
129 ms, `send_done` nach 129 ms, dann 35 s Schweigen bis unser
Client-Timeout greift).

### Befunde

- **Der heutige Download antwortet trotz haengender Anfrage sofort.**
  `head_ms` beim Probe waehrend des Hangs: **20 ms**, in der gleichen
  Groessenordnung wie die Baseline (12–16 ms). Der Drucker nimmt
  mehrere parallele TCP-Verbindungen an und bedient sie unabhaengig.
- `connect_ms` schwankt deutlich (14 – 420 ms), unabhaengig von
  Hang/No-Hang. Vermutung: TCP-SYN-Retransmission oder vorige
  Session noch im `TIME_WAIT`. **Nur `head_ms` taugt als Zeit-
  Indikator fuer App-Fehler-Detect**; der volle `total_to_head_ms`
  ist zu variabel.
- Nach Timeout des haengenden Requests bleibt alles normal (Baseline-
  aehnliche Latenz).

### App-Regel (parallele Probes)

- **Probes und Downloads duerfen parallel laufen.** Keine
  seriellen Warteschlangen noetig fuer Fehler-Detect.
- **Short-Head-Timeout** von 1–2 s auf den Response-Head. In 20 ms
  antwortet der Drucker, wenn er antwortet; nach 30+ s schweigt er
  immer noch.
- cc2-control begrenzt sich auf **zwei parallele Downloads**
  (`history.h` kommentiert einen „two-transfer limit") – gute
  Richtschnur, nicht uns gleichzeitig 10 Probes laufen lassen,
  aber 2–3 parallel sind empirisch unproblematisch.

---

## Test B 2026-10-26: 1051 gegen bereits gerenderten Eintrag ist folgenlos

Fragestellung: Was macht `method 1051`, wenn das MP4 bereits
existiert und die URL in `video/<name>.mp4`-Form uebergeben wird?

Setup: `method 1051 params.url="video/<name>.mp4"` gegen den
heutigen Eintrag `e0b592f4` (Baseline-MP4 1 741 634 Byte,
md5 `e2330f840b398f425172b32692437f7a`). Mitschnitt
`logs/cc2-sniff-2026-10-26-090500.jsonl`.

### Response und Status-Verlauf

```
2026-10-26T08:05:43.045Z  PUB  {"method":1051,"id":1051,
                                "params":{"url":"video/<name>.mp4"}}
2026-10-26T08:05:43.544Z  RX   api_response:
    {"id":1051,"method":1051,
     "result":{"error_code":0,
               "url":"video/<name>.mp4.mp4"}}      ← .mp4 angehaengt!
2026-10-26T08:05:43.544Z  api_status: status 1→12  sub_status 0→3020
2026-10-26T08:05:43.544Z  api_status: sub_status 3020→3022
2026-10-26T08:05:43.545Z  api_status: status 12→1  sub_status 3022→0
```

- **Antwort-Latenz:** 499 ms.
- **Status 12 Dauer: 1 ms.** Noch kuerzer als beim `fac849a1`-Lauf
  (972 ms). Composite findet nicht statt.
- **Zielpfad in der Response hat ein doppeltes `.mp4` am Ende**:
  Die Firmware behandelt `params.url` als Basisname und haengt
  `.mp4` an, auch wenn der schon mit `.mp4` endet. Daraus folgt:
  die Rohframes werden unter `/opt/usr/picture/<params.url>/`
  gesucht – fuer unsere URL `video/<name>.mp4` wuerde das
  `/opt/usr/picture/video/<name>.mp4/*.jpeg` sein. Gibt es nicht
  → `3022` sofort.
- `sub_status 3022` tritt also auch im **URL-Form-Fehler**-Fall
  auf, nicht nur bei stillschweigend geloeschten Rohframes.

### Keine Nebenwirkungen

- **1036 Vorher/Nachher: byte-identisch**
  (`sha256(result) = e12d373a3ec5c57b` beide Male). Weder der
  Target noch irgendein anderer Task veraendert sich; auch die
  `time_lapse_video_duration`-Mutation vom `fac849a1`-Lauf
  (0 → 4) tritt hier nicht auf. **Vermutung:** die
  `duration=4`-Mutation vom Vormittag war an die Status-1-Form
  `picture/…` gebunden; bei Status-2-Form `video/…` wird gar nichts
  geschrieben.
- **MP4 nach dem 1051-Lauf nochmal gezogen:**
  `HTTP 200`, 1 741 634 Byte, **md5 e2330f840b398f425172b32692437f7a**
  – byte-identisch zur Baseline. **Das vorhandene MP4 wird durch
  1051 nicht ueberschrieben, nicht veraendert.**
- **Die hypothetische Response-URL** `video/<name>.mp4.mp4`
  antwortet nicht (Timeout) – die Datei existiert erwartungsgemaess
  nicht.

### Was damit entschieden ist

- **`method 1051` ist idempotent und ungefaehrlich auf Status-2-URLs.**
  Falls die App versehentlich 1051 auf einem schon gerenderten
  Zeitraffer ausloest: keine Datenverlust, keine Nebenwirkung,
  nur ein 500-ms-Request plus 1-ms-Status-12-Flash.
- **Fuer erfolgreiches Rendern immer die Status-1-URL
  `picture/<name><ts>` verwenden**, nicht die Status-2-URL. Status 2
  bedeutet „MP4 schon da" – kein 1051 noetig und auch nicht
  wirkungsvoll.
- **`sub_status 3022` ist nicht spezifisch** fuer „Rohframes
  geloescht". Es tritt auch bei URL-Form-Fehlern auf. Fuer die App:
  3022 generell als „kein Composite stattgefunden" interpretieren;
  Erfolg bleibt an „MP4 nach dem Lauf abrufbar" gekoppelt
  (Head-Probe).

### Was weiterhin offen bleibt

- **Erfolgreicher 1051 auf frischen Rohframes.** Fuer das `3020→3021`-
  Verhalten (das wir bisher nur beim USB-Export gesehen haben)
  brauchen wir einen neuen Zeitraffer-Druck mit **noch nicht
  gelöschten** Rohframes **und** 1051 mit korrekter
  `picture/<name><ts>`-URL. Nicht Teil dieses Tests.
- Ob der 1051-Pfad bei korrekter URL `picture/<name>` eine
  vorhandene MP4 **ueberschreibt** oder abbricht, laesst sich nur
  mit frischen Rohframes auf einem Status-2-Eintrag ermitteln –
  haben wir aktuell nicht.

---

## Test C 2026-10-26: 1051 mit abgeleiteter `picture/`-URL auf Status-2-Eintrag

Fragestellung: Zeigt der heutige Lauf 2 (`video_status=2`, Display
listet den Eintrag) seine Rohframes unter `/opt/usr/picture/`, so
dass `method 1051 params.url=picture/<basename>` ein frisches
Rendering ausloest?

### URL-Herleitung (eindeutig aus den Quellen)

- `time_lapse_photo.h:17-18`: `/opt/usr/picture/` und
  `/opt/usr/video/` sind die beiden Basis-Verzeichnisse.
- `time_lapse_control.h:61,65-66`: Die Felder `pic_dirname_` und
  `video_path_` teilen denselben `<basename>` – nur Praefix und
  Extension unterscheiden sich.
- `time_lapse_control.cpp:30,38,78`: `Start(file_name,…)` baut
  `pic_dirname_ = picture_dir_ + addTimestampToFilename(file_name)`.
  Darin landen `0001.jpeg`, `0002.jpeg`, … pro Frame.
- `cc2-control/src/history.h:51-62` (Download-Resolver):
  dokumentiert explizit `"picture/NAME" or "video/NAME.mp4" ->
  "video/NAME.mp4"`.
- Test B empirisch: Response-URL ist `video/<basename>.mp4`
  mit `<basename>` = Anteil nach dem letzten `/` – d. h. die
  Firmware strippt den Praefix und haengt `.mp4` an.

Daraus abgeleitet fuer `video_url = "video/handslice_1792947629010.gcode20261026143807.mp4"`:

```
params.url = "picture/handslice_1792947629010.gcode20261026143807"
```

Vorhersage: Rohframes gesucht unter
`/opt/usr/picture/handslice_1792947629010.gcode20261026143807/`,
Ziel-MP4 `video/handslice_1792947629010.gcode20261026143807.mp4`
(= bestehender Pfad; wuerde ueberschrieben).

### Beobachteter Verlauf

```
2026-10-26T08:17:37.296Z  PUB  {"method":1051,"id":1051,
                                "params":{"url":"picture/<basename>"}}
2026-10-26T08:17:37.314Z  RX   api_response:
    {"id":1051,"method":1051,
     "result":{"error_code":0,
               "url":"video/<basename>.mp4"}}   ← genau unser existierender Pfad
2026-10-26T08:17:37.794Z  api_status: status 1→12  sub_status 0→3020
2026-10-26T08:17:37.794Z  api_status: sub_status 3020→3022
2026-10-26T08:17:37.794Z  api_status: status 12→1  sub_status 3022→0
```

- **Response-Latenz: 18 ms** (deutlich kuerzer als Test B's 500 ms).
- **Status 12 Dauer: <1 ms** – alle drei Deltas tragen denselben
  Zeitstempel. Composite findet nicht statt.
- **`sub_status 3022`** zum dritten Mal in Folge (nach Tests
  `fac849a1` und Test B).

### Keine Nebenwirkungen

- **1036 Vorher/Nachher: byte-identisch**
  (`sha256(result)=e12d373a3ec5c57b` beide Male). Target
  unveraendert (`video_status=2`, `url=video/<basename>.mp4`,
  `size=1741634`, `duration=4`).
- **Target-MP4 byte-identisch:** HTTP 200, 1 741 634 Byte,
  md5 `e2330f840b398f425172b32692437f7a` – gleich zur
  Vormittags-Baseline. **1051 hat das vorhandene MP4 nicht
  ueberschrieben**, auch nicht bei exakter URL-Form.

### Erklaerung aus den Quellen

Der entscheidende Satz im Elegoo-Code steht in
`time_lapse_control.cpp:119-125`: nach erfolgreichem Composite
loescht die Firmware das Rohframes-Verzeichnis:

```cpp
cmd = "rm -rf \'" + pic_dir + "\'";
SPDLOG_INFO("cmd {}", cmd);
std::system(cmd.c_str());
```

Dieser `rm -rf` wird aus dem `Composite()`-Pfad aufgerufen – also
genau am Ende einer Rendering-Operation (USB-Export oder 1051).
Der Rendering-Trigger beim USB-Export loescht demnach die
Rohframes des exportierten Zeitraffers.

**Konsequenz:** Fuer den heutigen Lauf 2 wurde das Composite
bereits beim 06:50-UTC-USB-Export durchlaufen; dabei
verschwand das `/opt/usr/picture/<basename>/`-Verzeichnis.
Das Display listet den Eintrag weiterhin, weil es die
Datenbank-Historie liest (und das MP4 unter `/opt/usr/video/`
noch da ist) – aber die **Rohframes gibt es nicht mehr**.
`method 1051 params.url=picture/<basename>` findet daher
keine Frames → sofortiger Uebergang `3020 → 3022`.

Konkret bedeutet das: **Jeder `video_status=2`-Eintrag auf
dieser Firmware hat keine Rohframes mehr.** Composite via
`method 1051` ist in diesem Zustand strukturell nicht
moeglich – unabhaengig von der URL-Form.

### Vollstaendige Beweiskette fuer `sub_status 3022`

Jetzt drei unabhaengige Beobachtungen desselben Verhaltens:

| Lauf | Target | URL-Form | Rohframes vorhanden? | Dauer | 1036-Diff | MP4-md5 |
|---|---|---|---|---:|---|---|
| Vormittag (`fac849a1`) | Status 1 | `picture/<basename>` | **nein** (am Display geloescht) | 972 ms | duration 0→4 | kein MP4 |
| Test B | Status 2 (heute) | `video/<basename>.mp4` | **nein** (nach Composite entfernt) | 1 ms | identisch | identisch |
| Test C | Status 2 (heute) | `picture/<basename>` | **nein** (nach Composite entfernt) | <1 ms | identisch | identisch |

In allen drei Faellen: `error_code=0`, Status 12 geht sofort auf
`3022`, kein Composite. **`sub_status 3022` ist der einheitliche
Marker fuer „keine Rohframes am erwarteten Pfad".**

### Konsequenz fuer die App (konkretisiert)

Der dreistufige UI-Flow bleibt wie in der Vormittags-Runde,
praezisiert um die Rohframes-Lebenszeit:

- `video_status=2` → Download-Flow (Head-Probe + GET).
- `video_status=1` → **Button „Rendern" nur anbieten, wenn der
  Druckauftrag jung ist**. Nach einem Composite werden die
  Rohframes vernichtet; von dieser Firmware aus gesehen hat ein
  Status-1-Eintrag genau **ein** Zeitfenster, in dem 1051
  funktioniert – naemlich **direkt nach dem Druck**, bevor
  irgendein Composite (MQTT oder Display-USB) stattgefunden hat.
- `video_status=3` → wahrscheinlich dauerhaft nicht renderbar
  (siehe Vormittags-Nebenbefund am Nameplate-Task).
- 1051 ist **gegen alle beobachteten URL-Formen idempotent-sicher**.
  Weder MP4 noch 1036 veraendern sich, wenn das Composite
  wegen fehlender Rohframes abbricht.

### Was damit abschliessend klar ist

- **`method 1051` funktioniert prinzipiell als MQTT-Trigger**
  (Response in 18 ms, Status 12 wird gesetzt) – wir koennen
  aber noch keinen Erfolgsfall (`3020→3021`) ueber MQTT
  reproduzieren, weil kein Testobjekt existiert, dessen
  Rohframes noch vorhanden sind.
- **Der einzige noch offene Realnachweis** ist ein frischer
  Zeitraffer-Druck mit anschliessendem 1051 vor dem
  USB-Export. Siehe offener Punkt in PROGRESS.md.
- **Fuer die App ist der Flow vollstaendig spezifiziert**: das
  Rendern eines `video_status=1`-Eintrags ist moeglich, muss
  aber durch eine Head-Probe auf das Ziel-MP4 validiert werden,
  nicht durch `error_code`.

---

## Test D 2026-10-26: `method 1038` loescht die Historie, aber nichts anderes

Fragestellung: Was macht `method 1038` (DELETE_HISTORY) genau –
nur Historien-Eintrag? Zusaetzlich das MP4? Nichts?

Belegte Payload-Struktur
(`cc2-control/src/mqtt.c:277-287` + `:343-346` +
`cc2-control/src/history.h:123-142`):

```json
{"method":1038,"id":1038,"params":{"list":["<task_id>",...]}}
```

Topic: `elegoo/<cc2-sn>/<client_id>/api_request`. Request-id = method =
1038, params enthaelt eine Liste von Task-IDs.

Zielobjekt: der heutige Lauf 2
(`task_id=e0b592f4-bd51-4ece-97fc-2bfc8137d13e`,
`video_status=2`, `video_size=1 741 634`,
`url=video/<basename>.mp4`). Klaus hatte explizit zugestimmt, dass
dieser Eintrag verloren gehen darf; das MP4 liegt gesichert auf
USB-Stick und in `local-test/`.

### Pre-Snapshot

- 1036 `sha256(result)[:16] = e12d373a3ec5c57b`, 45 Tasks,
  `result.total=45`.
- Target in `history_task_list[]` vorhanden.
- Download-Probe: HTTP 200, 1 741 634 Byte, md5
  `e2330f840b398f425172b32692437f7a`.
- Klaus bestaetigt am Display: Zeitraffer-Liste zeigt genau
  diesen einen Eintrag.

### Beobachteter Verlauf

```
2026-10-26T08:31:52.327Z  PUB  {"method":1038,"id":1038,
                                "params":{"list":["<task_id>"]}}
2026-10-26T08:31:52.624Z  RX   api_response:
    {"id":1038,"method":1038,"result":{"error_code":0}}
```

- Response-Latenz: **297 ms**.
- **Kein Status-12 Wechsel.** Keine api_status-Deltas im Window;
  `machine_status.status` blieb auf 1 (Idle). Das Loeschen ist
  rein daten-/datenbankseitig.
- Keine zusaetzlichen Felder in der Response – nur `error_code`.

### Post-Snapshot

- 1036 nach 1038:
  - `sha256(result)[:16] = 4c9f1271e71c3a3d` (verschieden zum
    Vorher).
  - **44 Tasks statt 45**; Target ist entfernt.
  - **Alle anderen Eintraege byte-identisch**; keine Nebenbeitraege
    mutiert, keine `duration`-Updates, keine
    `video_status`-Verschiebungen.
  - `result.total = 44` statt 45. **Neues Feld entdeckt** – 1036
    enthaelt einen expliziten Zaehler, nicht nur die Liste. Fuer
    die App ein zusaetzlicher Konsistenz-Check.
- Download-Probe auf `video/<basename>.mp4` nach 1038:
  **HTTP 200**, 1 741 634 Byte, md5 **`e2330f840b398f425172b32692437f7a`**
  – byte-identisch zum Pre-Download. Latenz 665 ms (langsamer
  als die 74 ms vorher, aber eindeutig im 200-Bereich und nicht
  im Timeout-Bereich; Varianz plausibel, siehe Test-A-Baseline-
  Varianz 14–420 ms Connect).
- **Klaus am Display geprueft:** der Eintrag ist in der
  Zeitraffer-Liste **weiterhin sichtbar**.

### Ergebnis (eindeutig)

**`method 1038` loescht ausschliesslich den MQTT-Historien-Eintrag.**
Weder die MP4-Datei unter `/opt/usr/video/` noch der
Display-Listen-Eintrag werden beruehrt.

### Vergleich mit Display-Loeschen

| Pfad | Historie (`method 1036`) | MP4 unter `/opt/usr/video/` | Display-Liste |
|---|:-:|:-:|:-:|
| **method 1038** (dieser Lauf) | **weg** | bleibt (byte-identisch) | **bleibt** |
| **Display-Loeschen** (Vormittag heute) | bleibt (stale) | **weg** (Download → Timeout) | weg |

Die beiden Loeschpfade sind **komplett getrennt**. Es existiert
im LAN-API-Namensraum **kein Weg, das MP4 oder die Display-Liste
zu beeinflussen**; umgekehrt gibt es keinen Display-Weg, der
die MQTT-Historie veraendert. Entsprechend fuehrt beides
unabhaengig zu zwei Arten „stale":

- Nach `method 1038`: 1036 ist aktuell, aber ein Zeitraffer-MP4
  liegt verwaist auf dem Drucker – im LAN nicht mehr adressierbar
  (nach 1038 fehlt `time_lapse_video_url` in der Historie), aber
  physisch auf der Partition.
- Nach Display-Loeschen: 1036 behaelt den Eintrag, `video_url`
  zeigt auf eine Datei, die der Drucker nicht mehr serviert
  (Timeout).

### App-Regeln (ergaenzend)

- `method 1038` ist **UI-Hygiene**, kein Speicher-Management.
  Die App kann damit die Historie-Ansicht aufraeumen; den
  Speicher auf dem Drucker gibt es nicht frei.
- Die App kann Benutzer darauf hinweisen, dass das Loeschen eines
  Zeitraffers **am Drucker-Display** notwendig ist, um Platz
  zu schaffen; `method 1038` entfernt nur den Historien-Eintrag.
- Das neue Feld `result.total` kann als Konsistenz-Check genutzt
  werden (`len(history_task_list) == total`), aber nicht als
  echte Pagination – wir haben keine Belege, dass 1036 paginiert.
- Nach `method 1038` sollte die App die lokale Historie-Ansicht
  aktualisieren (den geloeschten Eintrag entfernen) **ohne**
  zu versuchen, zugehoerige MP4s aus einer anderen Quelle zu
  „holen" oder zu „loeschen" – es gibt keine solche Quelle.

### Konkrete Beobachtung: `result.total`

Das Feld `total` steht in der 1036-Antwort auf oberster
`result`-Ebene (gleiche Ebene wie `history_task_list`). Vorher
45, nachher 44. Wert passt zu `len(history_task_list)`. Fuer die
Doku: wenn die App dieses Feld verwendet, muss es als
`number_in(result, "total", &total)` gelesen werden (cc2-control
verwendet es nicht aktiv, zumindest nicht in dem Code, den wir
gegrept haben; wert ist unauffaellig redundant).

---

## Realtest 2026-10-26: method 1051 (ungueltig, siehe Historie-Stale-Abschnitt oben)

**Dieser Test ist retrospektiv ungueltig** – Klaus hatte den
Ziel-Eintrag vorher am Display geloescht, dessen Rohframes
existierten damit nicht mehr. Der Abschnitt bleibt hier als
Belegstelle fuer das Verhalten in diesem (nicht intendierten)
Grenzfall erhalten; nicht als Beweis fuer das 1051-Verhalten im
Normalfall. Siehe „Historie ist stale" oben.

Zweiter Realtest, lesender Grundzug, mit genau **einem** aktiven
Befehl: `method 1051 (TIMELAPSE_RENDERING)`. Keine Druckstarts,
kein `method 1038`. Ziel: den LAN-Pfad validieren, der am Vormittag
in Teilen noch unverifiziert war („volle Zyklus 1 → 1051 → Status
12 → 2 → Download").

Ausgangslage aus `docs/cc2-history-sample.json`: zwei Tasks mit
`time_lapse_video_status=1`. Gewaehlt wurde der **aeltere**
(`task_id` beginnt mit `fac849a1`, 2026-10-14T03:50 UTC); der
zweite (`e4d2dc70`, 2026-10-14T10:02 UTC) blieb als Reserve
unberuehrt. Beide gehoeren zu Druckauftraegen desselben G-Code
(`ECC2_0.4_Sealed+lid_Elegoo PLA Matte _0.12_2h39m.gcode`,
nominell 2 h 39 min Druckzeit).

Request-Payload exakt nach `cc2-control/src/mqtt.c:277-287` + `:362-372`:

```json
{"method":1051,"id":1051,"params":{"url":"picture/<name><ts>"}}
```

Topic: `elegoo/<cc2-sn>/<client_id>/api_request`.

### Beobachtete Zeitachse (Mitschnitt + Script-Logs)

```
2026-10-26T07:42:19.888Z  PUB  method 1051 … (von unserem Script)
2026-10-26T07:42:20.121Z  RX   api_response: {"id":1051,"method":1051,
                                "result":{"error_code":0,
                                          "url":"video/<name><ts>.mp4"}}
2026-10-26T07:42:20.148Z  api_status: machine_status.status 1→12,
                                      sub_status 0→3020
2026-10-26T07:42:21.120Z  api_status: sub_status 3020→3022
2026-10-26T07:42:21.120Z  api_status: machine_status.status 12→1,
                                      sub_status 3022→0
```

- Response-Latenz (Request → `error_code=0`): **233 ms**.
- Composing-Dauer (Status 12 Start → Rueck auf 1): **972 ms**.
- Zum Vergleich: der heutige USB-Export des 100-Frame-Zeitraffers
  dauerte 26 s. Hier bei einem Nominal-„2h39m-Druck" mit vermutlich
  mehreren hundert Frames: unter einer Sekunde. **Das ist kein
  echter Composing-Vorgang.**

### Substate-Abweichung: 3022 statt 3021

- Beim USB-Export heute frueh: `3020 → 3021 → 1`
  („generieren" → „kopieren" → fertig).
- Hier bei 1051: `3020 → 3022 → 1`.

Code-Suche in `cc2-control` und `elegoo/extras/ai_camera/`: `3022`
ist weder in `machine.ts:11-57` (Status-2-Substates) noch in den
cc2-control-Headern aufgeschluesselt. **Vermutung** (nicht hart
belegt): `3022 = Composite abgebrochen / fehlgeschlagen`. Passt zur
Beobachtung, dass das MP4 danach nicht existiert (siehe unten).

### Composing-Nachpruefung: MP4 ist NICHT entstanden

Download auf den in der 1051-Antwort genannten Pfad
(`video/<name><ts>.mp4`), beide Encoding-Varianten (Leerzeichen als
`+` wie `urlencode` und als `%20` wie `cc2-control`'s
`percent_encode`): **beide HTTP-Timeout**, der Drucker schweigt.
Das ist genau das Verhalten, das cc2-control fuer „falscher Token
oder Name" dokumentiert (`cc2-control/src/history.h:250-251`:
„A wrong token or name is answered with silence, hence the receive
timeout.").

Gegenprobe mit demselben Encoder gegen das heute-frueh-MP4
(`video/handslice_1792947629010.gcode20261026143807.mp4`): sofort
`HTTP 200`, `Content-Length: 1 741 634`. Der Pfad funktioniert; nur
die konkrete Datei existiert nicht.

### History-Vorher/Nachher-Diff

Hash `sha256(result)` komplett:
- vorher: `c07da2c568049d5e...`
- nachher: `e12d373a3ec5c57b...`

Diff auf Task-Ebene (nur zwei Tasks veraendert):

1. **Target `fac849a1`** – `time_lapse_video_duration` 0 → **4**,
   alles andere unveraendert. Konkret:
   `status` bleibt 1, `url` bleibt `picture/<name><ts>`,
   `size` bleibt 0. Das MP4 ist weder in der Historie noch im
   Dateisystem reality.
2. **Nameplate-Task `887e3325`** (von 2026-09-23, 12 Tage vor dem
   Target entstanden, voellig unverwandt): `time_lapse_video_status`
   0 → **3**, mit weiterhin leerer URL und `size=0`, `duration=0`.
   **Nicht sauber kausal verknuepft zum 1051-Request** – entweder
   eine Nebenwirkung des gleichzeitig internen Housekeepings, oder
   `method 1036` triggert fuer alte Tasks eigenstaendig eine
   Zustandsneuberechnung. Dieser Task hatte im Vormittags-Snapshot
   `video_status=0` und `url=""`; jetzt `video_status=3` ohne URL,
   was semantisch widerspruechlich ist (3 bedeutet laut cc2-control
   „renderbar", also sollte eine URL da sein).
- **Reserve `e4d2dc70` ist unveraendert.** Keine Nebenwirkung auf
  den anderen Status-1-Eintrag; 1051 wirkt nur auf den
  adressierten Task.
- **Alle vorhandenen `video_status=2`-Eintraege sind unveraendert**
  (gleiche `url`, `size`, `duration`). Byte-ident. Vorhandene MP4s
  bleiben also durch 1051 unberuehrt.

### Fortschritts-Felder in api_status waehrend Status 12?

Alle Felder im Zeitraffer-Composing-Fenster
(2026-10-26T07:42:20.0 – 07:42:21.5, 4 Nachrichten):

```
result.machine_status.status     (2×, 12 und 1)
result.machine_status.sub_status (3×, 3020, 3022, 0)
result.error_code                (1×, aus 1051-Response)
result.url                       (1×, aus 1051-Response)
```

**Kein `progress`, kein `percent`, kein `frame_count`** oder sonstiges
feinkörniges Fortschritts-Feld. Fuer die App bedeutet das: der
Spinner kann nur „Status 12 → Composing" anzeigen; kein Prozent-
Fortschritt verfuegbar.

### Interpretation

Die Composing-Logik des Druckers (`time_lapse_control.cpp:93-128`)
prueft vor dem Encoder-Aufruf:

```cpp
if (!CommonTools::directoryExists(pic_dir)) {
    SPDLOG_ERROR("no such pid_dir: {}", pic_dir);
    return false;
}
```

Das MQTT-Protokoll meldet den Fehler aber **nicht** als
`error_code != 0` zurueck (dort steht sauber `0`), sondern nur
ueber den Substate-Wechsel `3020 → 3022`. **Vermutung:** die
Rohframes zu diesem Druck vom 14.10. existieren auf dem Drucker
nicht mehr (interne Loeschung durch Speicher-Housekeeping –
`/opt/usr` hat nur 488 MB gesamt). Der History-Eintrag mit
`video_status=1` bleibt stehen, obwohl die Rohframes weg sind;
das Status-Feld in der Historie wird nicht automatisch korrigiert.

Alternative Hypothese: die Rohframes sind da, aber unvollstaendig
oder beschaedigt – der Encoder bricht ab. Fuer die Unterscheidung
braechte es Zugriff auf `/opt/usr/picture/`; haben wir nicht.

### Konsequenz fuer die App

- Nach `method 1051` **nicht nur auf `error_code=0` verlassen** –
  der sagt nur „Request wurde angenommen". Erst ein zweiter
  `method 1036`-Lauf nach `machine_status.status` zurueck auf 1
  ist der verlaessliche Erfolgstest. Wenn der Zielsatz
  (`video_status==2`, `url` beginnt mit `video/`, `size>0`)
  nicht erreicht wurde, war das Composing erfolglos.
- `sub_status 3022` als Fehler-Marker im Spinner behandeln
  (Hypothese, nicht hart belegt, aber durch diesen Lauf
  nahegelegt). `3021` als „Kopieren" belassen (= Erfolg beim
  USB-Export).
- Fuer die UI-Darstellung reicht Status 12 als Trigger fuer einen
  unspezifischen „Zeitraffer wird erzeugt" / „Export laeuft"-
  Spinner. Keine Prozent-Anzeige moeglich – der Drucker pusht
  nichts dergleichen.
- Beim Auftreten von `video_status=1` in der History-Ansicht
  die App warnen, dass das Rendering **auf dieser Firmware auch
  stillschweigend scheitern kann**, insbesondere fuer aeltere
  Druckauftraege.
- `video_status=3` ohne URL (wie beim Nameplate-Task) als
  „nicht renderbar" interpretieren – semantisch unterscheidet
  sich das vom Community-Code (dort 3 == 1), aber die Realitaet
  auf Stock 02.01.01.07 sagt: ohne URL kein Rendering moeglich.

### Nachweis-Byte-Checks

- Reserve `e4d2dc70`: byte-identisch zur Vormittags-Antwort.
- Alle `video_status=2`-Eintraege: byte-identisch, insbesondere
  das heute-frueh-MP4 `handslice_1792947629010.gcode20261026143807.mp4`
  (`size=1 741 634`, md5 `e2330f840b398f425172b32692437f7a`).
- Lokal gespeichert blieb nur das heute-frueh-MP4 unter
  `local-test/`; **kein neues MP4 heruntergeladen**, weil keines
  existierte.

## Abnahmedruck 2026-10-26: MQTT-Zeitachse (Sniff-Mitschnitt)

Mitschnitt: `logs/cc2-sniff-2026-10-26-152237.jsonl` (Start 14:22
UTC, Ende 16:43 UTC). Drucker SN **`<cc2-sn>`**, Fach A4
(ELEGOO Rapid PLA+). Nur `subscribe` auf `elegoo/#`, kein PUBLISH.

### Zeitachse (alle Zeiten UTC)

| Zeit | Ereignis | method / Nachweis |
|------|----------|-------------------|
| 15:46:27.012 | Dateiliste geholt | `method 1044 storage_media=local` → `handslice_1793029586062.gcode` (221 140 B, Vorhersage 565 s / 9 m 25 s, Material PLA #F2754E) |
| 15:46:32.435 | **startPrint-Request** | `method 1020 params={filename, bedlevel_force:true, printer_check:true, slo…}` |
| 15:46:33.154 | startPrint-Response | `error_code=0` |
| 15:46:33.660 | `machine_status.status` 1 → **2** (Druck beginnt) | 6000-Report |
| 15:46:33.828 | Hot-End-Target 140 °C, Bett-Target **60 °C** | `extruder.target` / `heater_bed.target` |
| 15:47:13.630 | `sub_status` 1405 → 1066 (prepare) | 6000-Report |
| 15:47:35.631 | Hot-End-Target **200 °C** (Nivellierungs-Temp) | 6000 |
| 15:47:58.454 | Hot-End-Target **180 °C** | 6000 |
| 15:50:49.578 | Hot-End-Target **220 °C** (Druck-Setpoint) | 6000; entspricht Default des Rapid-PLA+-Presets (vererbt aus `fdm_filament_pla.json`), **kein Override** |
| 15:51:20.381 | `sub_status` → 2075 (aktives Drucken) | 6000 |
| 16:01:53.991 | `sub_status` → 2077 (Finishing) | 6000 |
| 16:01:54.013 | `machine_status.status` 2 → **1** (Druckende) | 6000 |

**Druck-Netto-Dauer:** 16:01:54 − 15:46:33 = **15 m 21 s**.
Vorhersage CLI: **9 m 25 s**. Delta +5 m 56 s deckt die
Bettnivellierung (`bedlevel_force=true` ≈ +200 s) und die Heiz-/
Preparation-Phase (~2 min Pre-Heat Hot-End + Bett 60 °C) ab.

### Beobachtungen nach dem Druck

Von 16:01:54 bis Log-Ende 16:43:33 (41 Minuten):

- **Keine `method 1051`** (Zeitraffer-Composite-Request).
- **Kein `machine_status.status 12`** und **keine 3020→3021**-
  Übergänge (Composing).
- **Kein zweites `method 1036`** nach dem Druck (die eine 1036 im
  Log stammt von 14:23 UTC — anderer Client-ID, vor der Abnahme).
- **Keine Download-Aktivität** sichtbar (HTTP geht ausserhalb MQTT;
  im Sniff waere allenfalls ein 1036-Call mit `time_lapse_video_url`
  erkennbar gewesen, aber auch der fehlt).

Interpretation: Klaus hat waehrend des Abnahmedrucks **kein
Zeitraffer-Composite ausgeloest**. Entweder war `printTimelapse=false`
beim Slicen, oder der Composite wurde nach Druckende nicht angetippt.
Fuer die Phase-4.4-Nacharbeit (Filament-Overrides, Material-Picker,
Save-Flow) ist das nicht blockierend; der Composite-Pfad ist aber
im Abnahme-Mitschnitt nicht erneut belegt.

### Was war der Override?

Der im G-Code sichtbare Düsen-Setpoint **220 °C** entspricht dem
Default des Rapid-PLA+-Presets (vererbt aus `fdm_filament_pla.json`,
Zeile `nozzle_temperature=['220']`). **Kein wirksamer Override auf
die Düsentemperatur** war im Mitschnitt zu beobachten – weder in den
`6000`-Reports noch indirekt in Status-/Phase-Uebergaengen. Falls
Klaus einen Override setzen *wollte* und keine Abweichung sieht, war
der Override identisch zum Preset-Default (oder wurde vor dem
Abnahme-Druck zurueckgenommen).

---

## Print control commands – sources (Orca ElegooLink, Elegoo method.h, elegoo-homeassistant)

**Scope.** This section documents the exact MQTT request/response shape
each printer-control command uses, with the source each shape comes
from. Written in English on purpose — this is the material we will
link to from the upstream issue trackers (OrcaSlicer #13934, PR
\#14024, danielcherubini#432).

**Sources audited** (read-only, no device commands sent):

- `engine/OrcaSlicer` submodule at tag `v2.4.2` (commit `8500fcdcca`):
  - `src/slic3r/Utils/ElegooLink.{cpp,hpp}` – native C++ host glue.
  - `resources/web/elegoolink/lan_service_web/index.html` – bundled
    Vue/MQTT client UI (minified, single file, ~3.5 MB).
- `elegooofficial/CentauriCarbon2` (GPL):
  `elegoo/common/method.h` – enum values only, no implementation.
- `danielcherubini/elegoo-homeassistant` v2.16.0-beta.2 (lesender
  Clone unter `~/upstream/elegoo-homeassistant/`, nicht im Repo):
  `custom_components/elegoo_printer/cc2/{client.py,const.py}`.

**Caveat.** PR \#14024 was already merged into v2.4.2 – the full
ElegooLink/CC2 code path is present. Orca `main` was **not** pulled
in this pass; a later ElegooLink refactor could change the enum
layout or add new methods, but the method IDs 1007/1021–23/1029/
1031/1042/1044–48/1054 covered here are all unambiguously present
in v2.4.2 and match `method.h`.

### Transport

Orca's embedded web UI connects to the printer with MQTT over
**WebSocket on port 9001**:

- `resources/web/elegoolink/lan_service_web/index.html` @1119975:
  `` `ws://${Ni.ip}:9001` `` – mqtt.js `.connect(url, options)` where
  `options = {clientId, clean: true, reconnectPeriod: 1000, username,
  password}`.
- Default LAN credentials: `username: "elegoo"`, `password:
  <access_code>` (same `access_code` the panel displays and that
  Orca passes to the Vue UI via query string).

Daniel's Python client uses **MQTT over plain TCP on port 1883**
(`~/upstream/.../cc2/const.py:23  CC2_MQTT_PORT = 1883`). Our
previous MQTT-sniff captures confirm the printer's broker **listens
on both** – no change needed to our native MQTT client. Port 9001
is only relevant if we later ship a WebView-based control panel.

### Registration + request topic layout

Both Orca and Daniel use the same topic layout (brief said
`_register`; actual string in both sources is `api_register`):

```
elegoo/<sn>/api_register                                 (publish)
elegoo/<sn>/<request_id>/register_response               (subscribe)
elegoo/<sn>/<client_id>/api_request                      (publish)
elegoo/<sn>/<client_id>/api_response                     (subscribe)
elegoo/<sn>/api_status                                   (subscribe)
```

- Orca UI @1118284..1118690: topic-template functions `lbe`, `OX`,
  `cbe`, `ube`, `dbe` emit exactly those strings.
- Orca UI @1122139: `register` payload is `{...registerParams,
  client_id: this.clientId}` published to `api_register`; the UI
  then awaits a reply on `register_response` keyed by the same
  `request_id`.
- Daniel @client.py:1216, :1311 publishes to the identical topics.

The native C++ side (`src/slic3r/Utils/ElegooLink.cpp:343..369`)
only prepares the WebView: it HTTP-GETs `/system/info` to fetch
the SN, then opens the local file `.../lan_service_web/index.html`
with query string `?access_code=…&ip=…&sn=…&id=elegoo_123456`. All
MQTT traffic is driven from the JS inside the WebView; the C++
host never speaks MQTT itself.

### Per-method request/response shapes

All UI calls build an object `{method: Pt.<Name>, params: {...}}`
and dispatch it through `N0.request()` (@1118690 and following).
`Pt` is the full method enum, declared at
`resources/web/elegoolink/lan_service_web/index.html` @738000..738400.

Table columns:

- **ID** – numeric method id (what hits the wire).
- **Enum name** – from Orca's `Pt.*` (matches `method.h` names).
- **Params (Orca UI)** – exact JS object literal published to
  `api_request`.
- **Response fields read (Orca UI)** – fields the UI reads back
  from `api_response`.
- **Source** – file:line in the Orca v2.4.2 submodule.

| ID   | Enum name          | Params (Orca UI)                                        | Response fields read                                                                 | Orca source (`resources/web/elegoolink/lan_service_web/index.html` @offset) |
|------|--------------------|---------------------------------------------------------|---------------------------------------------------------------------------------------|-----|
| 1007 | UrgentStop         | *(none)*                                                | `error_code`                                                                          | @2521985 |
| 1020 | StartPrint         | `{storage_media, filename, ...}` (full print config)    | `error_code`                                                                          | @2510067 |
| 1021 | PausePrint         | *(none)*                                                | `error_code`                                                                          | @2510582 (UI uses 60 s timeout) |
| 1022 | CancelPrint        | *(none)*                                                | `error_code`                                                                          | @2511241 (UI uses 60 s timeout) |
| 1023 | ResumePrint        | *(none)*                                                | `error_code`                                                                          | @2510915 (UI uses 60 s timeout) |
| 1028 | TemperatureControl | passthrough object (`params: Ie`)                       | `error_code`                                                                          | @2523515 |
| 1029 | LightSwitch        | `{power: 1\|0}` **only** – no `brightness`              | `error_code`                                                                          | @2517873 |
| 1030 | FanControl         | `{fan?, box_fan?, aux_fan?}` – only set fans provided   | `error_code`                                                                          | @2518247 |
| 1031 | PrintSpeedControl  | `{mode: <int>}`                                         | `error_code`                                                                          | @2518790 |
| 1042 | GetLivingVideoUrl  | *(none)*                                                | `error_code`, `url`                                                                   | @2516866 |
| 1044 | GetFileList        | `{storage_media, dir?, offset, limit}`                  | `error_code`, `offset`, `total`, `file_list[]`                                        | @2512171 |
| 1045 | GetFileThumbnail   | `{storage_media, file_name}` *(underscore)*             | `error_code`, `thumbnail`                                                             | @2511727 |
| 1046 | GetFileDetail      | `{storage_media, filename, dir?}` *(no underscore)*     | `error_code`, `filename`, `print_time`, `layer`, `size`, `create_time`, `total_filament_used`, … | @2514037 |
| 1047 | DeleteFile         | `{storage_media, file_path}` *(NOT `filename`)*         | `error_code`                                                                          | @2514470 |
| 1048 | GetCapacity        | declared only – no call site in UI                      | –                                                                                     | enum @738200; dispatcher @1127576 |
| 1054 | StartVideoStream   | declared only – no call site in UI                      | –                                                                                     | enum @738324 |

Error code 1003 (`InvalidParameter`) is emitted when `params` is
rejected – confirmed by the UI's own error enum at @583400 and by
Klaus's Test E capture (2026-10-26 09:30 UTC, PROGRESS.md).

### Points of agreement / disagreement vs method.h and elegoo-homeassistant

| ID   | `method.h` name          | Orca `Pt.*` name     | Daniel's shape                                             | Verdict |
|------|--------------------------|----------------------|------------------------------------------------------------|---------|
| 1007 | EMERGENCY_STOP           | UrgentStop           | —                                                          | names differ, semantics identical |
| 1021 | PAUSE_PRINT              | PausePrint           | no params                                                  | **agree** |
| 1022 | CANCEL_PRINT             | CancelPrint          | no params                                                  | **agree** |
| 1023 | RESUME_PRINT             | ResumePrint          | no params; Daniel says reply arrives after ~122 s and does not wait | Orca UI uses 60 s timeout but ignores a late reply; semantics compatible |
| 1029 | CTRL_LED                 | LightSwitch          | `{brightness: 0\|255, power: 0\|1}`                        | **mismatch** – Orca sends `power` only; Daniel's comment says some firmwares expect `brightness`. Not reconciled. |
| 1031 | CTRL_PRINT_SPEED         | PrintSpeedControl    | `{mode: int}`                                              | **agree** |
| 1042 | GET_MONITOR_VIDENO_URL *(sic)* | GetLivingVideoUrl | `{enable: 0\|1}` sent as toggle                        | **mismatch** – method.h and Orca treat 1042 as a URL getter with no params; Daniel sends `{enable}`. The response Daniel reads is `error_code` only (no `url` field used), so his toggle may happen to work only as a side effect, or the firmware ignores unknown params. |
| 1044 | GET_FILE_LIST            | GetFileList          | `{storage_media: "local", path: "/"}`                      | **naming mismatch** – Daniel uses `path`, Orca uses `dir`+`offset`+`limit`. The CC2's capture Klaus already recorded confirms **Daniel's `path`-shaped 1044 does return `file_list`**, so the firmware accepts both or ignores unknown keys. |
| 1045 | GET_FILE_THUMBNAIL       | GetFileThumbnail     | *(not inspected)*                                          | Orca uses `file_name` (underscore); verify Daniel's shape before mixing. |
| 1046 | GET_FILE_INFO            | GetFileDetail        | *(not inspected)*                                          | names differ in both repos; semantics appear identical. |
| 1047 | DEL_FILE                 | DeleteFile           | `{storage_media, filename}`                                | **mismatch – this is the Test-E answer.** Orca sends `file_path`, Daniel sends `filename`. method.h is silent on the param name. All 11 shape variants Klaus's `cc2_probe_delete.py` tried on 2026-10-26 included `filename`, `file_name`, `file_path` **inside a wrapper `params`** that different clients spell differently (`local_file_name`, `sd_card_filename`, …) – but **not** a plain `{storage_media, file_path}`. Likely the printer accepted neither Daniel's shape nor Klaus's probe shapes; Orca's `file_path` is the one shape not yet tested. |
| 1048 | GET_DISK_VALUME *(sic)*  | GetCapacity          | `{}` (empty)                                               | agree on no params; Orca UI never invokes it, so this is the only confirmation we have. |
| 1054 | CTRL_LIVE_STREAM         | StartVideoStream     | *(not used – aliased to 1042 in Daniel's const)*           | **unverified** – method.h says 1054 is the switch; Orca declared it but never calls it; Daniel calls 1042 instead. The real switch has never been exercised in a captured session. |

### Methods we must verify on the real printer before building App features

In priority order (first two are blocking the control-panel UI,
last three are nice-to-have before shipping):

1. **1047 DeleteFile with `{storage_media, file_path}`** (Orca's
   shape). Target: delete one of the 12 probe files Klaus has
   queued and watch for `error_code == 0` + disappearance from
   the next 1044 listing. If it still returns 1003, the correct
   shape is neither Orca's nor Daniel's.
2. **1054 StartVideoStream `{enable: 0|1}` vs 1042 as toggle.**
   Current hypotheses: (a) 1054 is the real on/off switch and
   returns `error_code` only, (b) 1042 is a getter and the stream
   is implicitly started by requesting the URL, (c) a different
   method entirely. Decide by sending 1054 with
   `{enable: 1}` first and watching the HLS/RTSP URL that 1042
   returns before/after.
3. **1029 LightSwitch – `{power}` alone sufficient?** Orca says
   yes; Daniel's comment implies some firmwares want
   `brightness`. Test on fw 02.01.01.07 (= the firmware we have).
4. **1031 PrintSpeedControl – valid `mode` values.** Neither
   source documents the integer range; Orca's UI binds it to a
   dropdown whose option list is not in this file. Try 0/1/2/3
   and record which trigger `error_code != 0`.
5. **1023 ResumePrint reply timing.** Daniel documents a ~122 s
   wait; Orca uses a 60 s timeout. Measure once at the real
   printer so we size our client's timeout correctly (and do not
   mistakenly resend).

Everything else in the table above is **either confirmed by Orca's
own code and Elegoo's enum or already matches what we've captured
on the wire**, and can be implemented without further probing.


---

## Block A device test – results (CC2 fw 02.01.01.07, 2026-10-31)

Hands-on verification of the five open points from the previous
section. Klaus physically next to the printer, idle, no job queued.
MQTT traffic captured in `logs/cc2-sniff-2026-10-31.jsonl` (gitignored).
No credential ever written to disk or stdout.

### Idle check (step 0)

- UDP 52700 discovery: `lan_status=1`, `token_status=1`.
- MQTT CONNACK rc=0, subscriptions ok.
- `api_status` push rate during idle: `method=6000` deltas carrying
  only `result.extruder.temperature`. The firmware **does not push
  `machine_status.status`** between state changes, so an idle
  reading requires either a wait for an actual transition or an
  active 1002/1003 query. Idle confirmed visually at the panel.

### 1047 DeleteFile – only the array form works (step 2)

Upload of a 112-byte comment-only file first (`PUT
http://<cc2-ip>:80/upload`, headers per
`src/slic3r/Utils/ElegooLink.cpp:909..919`): HTTP 200,
`{"error_code":0,"offset":111}`. 1044 verified name
`cc2_probe_delete_test.gcode` in the listing (`total 27→28`).

Then two 1047 attempts with that exact filename:

| Attempt | `params`                                                                   | Response (full) |
|---|---|---|
| **Orca-UI shape (string)** | `{"storage_media":"local","file_path":"cc2_probe_delete_test.gcode"}`       | `{"id":…,"method":1047,"result":{"error_code":1003}}` – file **still present** |
| **Array shape**            | `{"storage_media":"local","file_path":["cc2_probe_delete_test.gcode"]}`      | `{"id":…,"method":1047,"result":{"error_code":0}}`    – 1044 then shows file **gone**, total back to 27 |

**Verdict.** On fw 02.01.01.07 the accepted shape for method 1047
on `storage_media=local` is a **list of filenames** under
`file_path`:

```json
{"storage_media":"local","file_path":["<name>"]}
```

- The Orca Vue bundle's `Mte(Ie, Be)` builder (minified
  `index.html` @2514419) sets `file_path: Ie` from a parameter
  that the enclosing composable has already turned into a
  one-element array via `Ve = []; Ve.push(De); n.deletePrintFile(Ve, ze)`
  (@2618738). The static analysis correctly recorded the
  single-string shape visible at Mte itself; the array wrap at
  the upper caller is what reaches the wire. **The static
  recommendation ("Orca sends `file_path` as a plain string") was
  wrong — the wire form is a list.**
- `danielcherubini/elegoo-homeassistant` v2.16.0-beta.2 uses
  `{"storage_media":…,"filename":<string>}` (`cc2/client.py:2634–2636`).
  Not retested today, but the 11×1003 Klaus already captured on
  2026-10-26 (`cc2_probe_delete_20261026_092850.json.scrubbed`)
  rejected every string-valued key tried, including `filename`.
  Both the key name (`file_path` ≠ `filename`) and the value
  type (list ≠ string) diverge from Daniel's; **either divergence
  alone is enough to cause 1003.**

### 1042/1054 camera – stream is always-on, 1054 rejects `{enable}` (step 3)

| Phase | Call | `error_code` | HTTP `:8080/?action=stream` |
|---|---|---:|---|
| Baseline (nothing done)        | –                      | –    | `HTTP/1.1 200 OK`, `multipart/x-mixed-replace; boundary=frame`, JPEG SOI `\xff\xd8` in body prefix |
| after `1054 {"enable":0}`      | 1054                   | 1003 | **unchanged** – still 200, multipart, JPEG SOI |
| after `1054 {"enable":1}`      | 1054                   | 1003 | **unchanged** – still 200, multipart, JPEG SOI |

- `method 1042` with no params: `error_code=0`, response carries
  only `url` (`http://<cc2-ip>:8080/?action=stream`). No `enable`
  / `active` / `state` field. Pure URL getter, matches
  `method.h`'s name `GET_MONITOR_VIDENO_URL` and the Orca enum
  `Pt.GetLivingVideoUrl`.
- `method 1054` with `{"enable": 0|1}` is **rejected** with
  `error_code=1003`. Daniel's shape (`{"enable": int(enable)}` on
  his `CC2_CMD_SET_VIDEO_STREAM = 1042` alias, `cc2/client.py:2362`)
  does not work on 1054 either. Whether 1054 accepts a different
  shape (`{"state":…}`, `{"on":…}`, …) was not re-probed per
  Klaus's rules.
- The MJPEG server on port 8080 ran continuously throughout the
  test, unaffected by any MQTT call. Klaus (device-side
  observation, same session): the CC2 has **no camera indicator
  LED** at the printer – a camera state is visible only during a
  print with active timelapse. There is thus no non-protocol way
  to tell whether `1054` ever did anything from the outside.

**App consequence.** For the camera panel, call `method 1042` to
discover the URL and open an MJPEG decoder on it. **Do not call
`method 1054` with `{enable}` on this firmware** – it only returns
1003 and the stream server is already running.

### 1029 LightSwitch – minimal `{"power"}` is sufficient (step 4)

| Call | `error_code` | Hardware |
|---|---:|---|
| `1029 {"power":1}` | 0 | **chamber LED turned on**, confirmed visually by Klaus at the panel |
| `1029 {"power":0}` | 0 | chamber LED turned off, confirmed visually – baseline restored |

- Orca's minimal shape (no `brightness` key) is accepted on fw
  02.01.01.07. Daniel's extra `brightness: 0|255` key
  (`cc2/client.py:2431–2434`) is therefore unnecessary for this
  firmware, though it is harmless when the printer ignores extra
  keys (as seen in the 1003 shape probes, missing or wrong keys
  trigger 1003 only when a *required* one is bad).

### Verification backlog cleared vs. still open

| Topic                                   | Status after Block A |
|---|---|
| 1047 delete – which param shape?        | **Decided**: `{"storage_media":…,"file_path":[<names>]}` |
| 1054 vs 1042 camera toggle              | **1054 rejects `{enable}`**; `1042` is the URL getter; stream is always-on. Toggle, if any, uses a different (unknown) shape. |
| 1029 light – `{power}` alone enough?    | **Yes** on fw 02.01.01.07. |
| 1023 ResumePrint reply latency          | Not covered (would require a running print; Block A was idle-only). |
| 1031 PrintSpeedControl `mode` range     | Not covered (same reason). |

Both remaining items are *print-time* behaviours and cannot be
tested on an idle machine; they belong to a later block with a
running job.


---

## M6 device test – print control (CC2 fw 02.01.01.07, 2026-10-31)

App commit `0c36fb3250` installed on the Poco X3 Pro. Klaus
physically next to the printer; passive MQTT capture in
`logs/cc2-sniff-2026-10-31-133328.jsonl` (gitignored).

### Verified end-to-end

| Flow        | Observation (device-side)                                                                                       | MQTT timeline (sub_status) |
|---|---|---|
| Light on/off | Chamber LED toggles immediately on each `1029 {power:0\|1}` call                                                | – (fw does not broadcast light state) |
| Preparing   | During **auto-levelling** the Pause button was greyed and Cancel enabled — correct. During the pre-print heating ramp the Pause button was **active** — **WRONG, see 1066 fix below.** | 1045 → 1066 → 2801 → 2802 → 2901 → 2902 → 2075 |
| Pause       | Printer parks the head, app shows "Paused" and the button flips to "Resume"                                     | **2501 → 2502** within 3.9 s |
| Resume      | Head returns to work position, print continues; app follows via api_status                                      | **2401 → 2402** within **18.4 s** (temperatures were held — matches Daniel's note that a full cold-start re-heat can take ~2 min; we therefore keep the fire-and-forget semantics in the client) |
| Cancel      | Confirm dialog in the app, printer transitions to "Cancelling…" then "Idle"                                     | **2503 → 2504** within 8.7 s |

### sub_status 1066 analysis (2026-10-31)

The Pause-active-during-heating bug led to a cross-log check of
`sub_status 1066`, which `danielcherubini/elegoo-homeassistant`'s
`cc2/const.py` does **not** name. Scanning all three CC2 captures
(`cc2-sniff-2026-10-26.jsonl`, `cc2-sniff-2026-10-26-152237.jsonl`,
`cc2-sniff-2026-10-31-133328.jsonl`):

| Capture                     | Hits of 1066 | current_layer at hit  | Hotend / target at hit | Neighbouring sub_status                 |
|---|---:|---|---|---|
| 2026-10-26 (morning tests)  | 12           | **always 0**          | 141/140 → 211/210      | 1045, 2075, 2801 (neighbours only)      |
| 2026-10-26 (print 15:46)    | 10           | **always 0**          | 143/140 → 201/200 → 180/180 → 140/140 | 2901, 2801, 1045, 2075 |
| 2026-10-31 (print 13:33)    | 5            | not pushed yet        | 220 (near-target)      | 1045, 2075                              |

Across 27 appearances **1066 never carried a non-zero
`current_layer`**, and the hotend was always within ±1 °C of
target. The surrounding codes are Preparing-codes (1045, 2801,
2802, 2901, 2902) and `2075 CC2_SUBSTATUS_PRINTING`. Conclusion:
**1066 is a pre-print hotend-stabilisation state.** Added to the
`PrintPhase.preparing` set alongside the eight codes already there.

### Backlog items narrowed

- 1023 ResumePrint reply latency: measured **18.4 s** on
  temperatures-held pause (new ground truth to complement Daniel's
  cold-pause ~122 s report). Fire-and-forget semantics in the
  client remain correct — Orca's 60 s timeout would miss the long
  case anyway.
- Still open: cold-pause case (re-heat required), filament-pause
  recovery flow (sub_status 2505 + exception_status 1243 on the
  wire), 1096/1906 which the firmware did not emit in these three
  captures.

### UI fixes shipped with the same commit

- **Progress bar always full.** `print_status.progress` is not
  pushed by this firmware in deltas; `total_layer` arrived once
  with value 0 in the initial 1002 snapshot and was never
  overwritten. The old fallback field combined with `.clamp(0,100)`
  pinned the bar at 100 %. Fix: drop the `progress` fallback,
  derive a `double? printProgressFraction` purely from
  `current_layer / total_layer` and only when `total_layer > 0`.
  UI hides the bar otherwise.
- **Preflight raw-code message.** `printPreflightNotIdle(code)`
  showed `status=2` to the user. Replaced the `int` placeholder
  with a `String` label and added CC2 status names (per
  `cc2/const.py` CC2_STATUS_*). "status 2" now reads "printing".

---

## M7 – Printer-error table + reconnect behaviour (2026-10-31)

### Source for the exception_status table

Full code → text table (77 entries) extracted from the Orca
ElegooLink web UI at
`engine/OrcaSlicer/resources/web/elegoolink/lan_service_web/
index.html`:

- **Code → key** mapping (81 code→key assignments; 77 distinct
  codes). Pattern `<code>:"exceptionCode.<name>"` emitted at
  offset @590106 and following. Extraction via regex, dedup by
  first-wins.
- **Key → English text**: object `Zve = { … }` starting at
  @512127, preamble `locale:"en"`. 75 top-level keys; 76/77 of
  the mapping targets have a text (the lone miss is 1300
  `PrintFileUnavailable`, which we backfill from the key name).
- **Chinese** text in sibling object `L3e` @528357 — not used,
  we go English → German instead.

`danielcherubini/elegoo-homeassistant/custom_components/elegoo_printer/
cc2/const.py` does **not** carry an exception-code enum, so the
Orca bundle is the only full source. method.h names 1243 (and a
handful of others) but has no text.

The 77 codes are mirrored verbatim as English text in
`app/lib/net/cc2_exception_codes.dart` constant `cc2ExceptionEn`,
alongside a hand-translated `cc2ExceptionDe`. Duplicate codes with
identical English text share the same German text (e.g. 1203 =
1241 both land on the "feed-from-CANVAS failed" message).

### Display rules (print screen)

- Any non-zero `machine_status.exception_status[]` entry triggers
  a red error banner inside the live-status card.
- Code **1243** keeps its dedicated text
  "Filament feed error – check PTFE tubes" / "Filamentzufuhr-
  Fehler – PTFE-Schläuche prüfen" from `printStatusException1243`
  (Klaus-defined wording, carried over from M6).
- All other codes read from `cc2ExceptionLookup(code, locale)`.
- Unknown codes fall back to `l.exceptionCodeUnknown(code)`
  ("Printer error 2345" / "Druckerfehler 2345") — the raw list
  is never rendered.

### Reconnect behaviour

Loss of connection is detected via two signals:

1. **MQTT ping failure**: existing 10 s ping loop
   (`_startPing`); first PUBLISH error reaches the reconnect path.
2. **Status watchdog**: a 10 s periodic check verifies that the
   last `api_status` delta is no older than 30 s **while a print
   is active**. In Idle the firmware is quiet and we don't force
   a reconnect from the watchdog.

On reconnect:

- Delay follows a short progressive sequence
  **2 s → 5 s → 10 s → 20 s → 30 s**, then capped at 30 s.
- Each attempt runs the full `connectAndLoad()` path again: UDP
  discovery → MQTT CONNECT → `api_register` + `register_response`
  → subscribe → fresh 1002 full-status fetch.
- Watchdog grace timer is reset on successful connect; so are
  the attempt counter and the "due at" timestamp.
- **No command is retried** after a reconnect — no re-pause,
  re-cancel, re-light, re-start. The firmware ran the originally-
  issued command locally; the app has no reason to repeat it,
  and a replay could cause duplicate print starts if a reconnect
  happens milliseconds after a 1020 that the printer actually
  received.

### UI during reconnect

- The reconnect info-box in the print screen shows
  `l.reconnectBannerLost` ("Connection lost — reconnecting…")
  while the attempt is in flight, and
  `l.reconnectBannerRetrying(sec)` ("Reconnecting in Ns…") while
  the backoff is counting down.
- All control buttons (Pause/Resume/Cancel + the Light switch)
  are gated on `connection == connected`, so they grey out for
  the whole reconnect window without further plumbing.

### Lifecycle hook

`_RootShellState` observes `AppLifecycleState.resumed` via
`WidgetsBindingObserver` and calls `printerState.checkAliveOnResume()`.
That method:

- Does nothing if the state machine is already in the
  `disconnected` baseline.
- Otherwise checks `_client.isConnected` **and** that the last
  `api_status` delta is within the watchdog grace window.
- If either fails, resets the backoff attempt counter to 0 (so a
  user who just unlocked the phone doesn't wait 30 s) and
  schedules an immediate reconnect.

---

## M7 device test – reconnect behaviour (CC2 fw 02.01.01.07, 2026-10-31)

App commit `0c469228e5` installed on the Poco X3 Pro.

### Verified by Klaus on the device

| Scenario                                               | Observation |
|---|---|
| Phone Wi-Fi off                                        | "Connection lost" banner appears almost immediately; backoff countdown ticks as designed. |
| Phone Wi-Fi back on                                    | Auto-reconnect after ~30 s (the full remaining backoff was sat out). Broadcast-discovery was **not** the obstacle. |
| App in background, screen off, 2–3 min                 | On resume: reconnected in ~2 s (lifecycle hook via `WidgetsBindingObserver.didChangeAppLifecycleState`). |
| Error banner trigger                                   | Not reproducible on the device during this test — stays "unverified at device". The table itself remains verified against the Orca source. |

### Follow-up fixes (new commit after the device test)

- **OS-level network-up signal triggers an immediate reconnect.**
  Previously the backoff ran to completion even when Android had
  already notified that Wi-Fi was back. Added
  `package:connectivity_plus` and plumbed its stream into
  `PrinterState` as a `Stream<bool>` (true = any network
  available). While `reconnecting`, a `true` emission cancels the
  pending backoff timer and triggers an immediate
  `connectAndLoad()`. The attempt counter is **not** reset – if
  the immediate attempt fails, the normal 2 → 5 → 10 → 20 → 30 s
  progression continues from where it was.
- **Preparing-phase label shortened.** `printPhasePreparing` is
  now just "Preparing" / "Vorbereitung". `sub_status 1066` turned
  out to be a pre-print hotend-stabilisation phase (not heating,
  not levelling), so the earlier parenthetical
  "(heating/levelling)" was misleading.
- **Full reconnect flow test.** New `reconnect_flow_test.dart`
  exercises the complete reconnect sequence against a
  `_FakeCc2Client` that extends `ElegooCc2Client` and counts
  calls:
  1. First `connectAndLoad()` → `discover`+`connect`+`getCanvas`+
     `getStatus` each called once.
  2. `fake.dropConnection()` + `triggerReconnectForTest()` →
     `state.reconnecting == true`, banner countdown active.
  3. Wait for the 2-s backoff → verify counts moved to 2 each
     (second `connect` represents a fresh `api_register` +
     subscribe + full-status fetch, same path the real client
     runs).
  4. Hard-asserted invariants: `pauseCalls == 0`,
     `resumeCalls == 0`, `cancelCalls == 0`, `setLightCalls == 0`
     — the reconnect must **not** replay any user command.
  Separate cases cover the connectivity-up-signal shortcut and
  the "spurious up-signal while connected" idle path.

---

## M8 – File management + live camera (CC2 fw 02.01.01.07, 2026-10-31)

### Live read-only verification of 1045 + 1046 (step 2 of the brief)

Klaus at the printer, idle. Sniff in
`logs/cc2-sniff-2026-10-31-*.jsonl`. Only two methods issued.

**1046 GetFileDetail** (Orca-shape: `{storage_media, filename}` –
`filename` without underscore):

```json
{
  "id": …,
  "method": 1046,
  "result": {
    "color_map": [{"color": "#F2754E", "name": "PLA", "t": 0}],
    "create_time": 1793449708,
    "error_code": 0,
    "filename": "handslice_1793449708341.gcode",
    "last_print_time": 0,
    "layer": 100,
    "print_time": 565,
    "size": 221143,
    "total_filament_used": 3.52,
    "total_print_times": 0
  }
}
```

**1045 GetFileThumbnail** (Orca-shape: `{storage_media, file_name}` –
`file_name` **with** underscore):

- For the small test cube (`handslice_1793449708341.gcode`, 221 kB,
  100 layers) the firmware returned `error_code = 1015
  ThumbnailNotExist`. No preview was embedded during that slice.
- For a larger file with a bundled thumbnail
  (`Elegoo-Bauplattenhalter-1.gcode`, 12 MB): `error_code = 0`,
  `thumbnail` field carried a 2 684-byte base64 PNG.

The 1045 vs. 1046 key-naming asymmetry (`file_name` vs `filename`)
is as documented in the M7 per-method table and matches the
captured UI payloads.

### App – `app/lib/net/elegoo_cc2_client.dart`

- `RemoteFile.fromJson(..)` now carries the full 1044 payload
  shape (`layer`, `print_time`, `create_time`, `last_print_time`,
  `total_filament_used`, `color_map[]`). `ColorMapEntry` wraps the
  per-slot tuple.
- `getFileThumbnail(filename)` → `ThumbnailResult{errorCode,
  base64Png?}`. `ok` requires `error_code == 0` AND non-empty
  base64 — covers the fw 02.01.01.07 "ThumbnailNotExist" case
  (1015).
- `getFileDetail(filename)` → `RemoteFileDetail{errorCode, file}`.
- `deleteFile(List<String> filenames)` → `method 1047` with
  `file_path` as a **list** (Block-A ground truth 2026-10-31).
- `probeFile`/`downloadFile` are thin aliases for the existing
  `probeTimelapse`/`downloadTimelapse` on the shared `/download`
  endpoint.
- `getLivingVideoUrl()` → `LivingVideoResult{errorCode, url}`.
  No `1054` call (Block A proved it rejects `{enable}` on this
  firmware and the MJPEG server runs permanently anyway).

### App – `app/lib/state/printer_state.dart`

- New `runningFilename` getter reads
  `print_status.filename` from the aggregated live state.
- `startPrintFile(filename, …)` runs the same preflight +
  `startPrint` path as the upload-driven flow, minus the
  bounds-check (that is only known at upload time). Reuses the
  current tray assignment and respects `supportsTimelapse`.
- `deleteFile(filename)` guards:
  - not connected → `delete.not_connected`;
  - `runningFilename == filename` → `delete.running_file`
    (the UI greys the delete button in that row as well);
  - firmware rejection → `delete.error_code.<n>` surfaces to the
    user via `lastError`.

### UI – "Drucker" tab now a 3-way SegmentedButton

Sections: **Files · History · Camera**. Switching sections is
what gates the camera stream — only `camera` section + app
`AppLifecycleState.resumed` enables the MJPEG viewer.
`WidgetsBindingObserver` on the screen keeps `_appResumed` in
sync; backgrounding the app stops the viewer within one frame.

### UI – `widgets/printer_files_panel.dart`

- One card per file: thumbnail (lazy via 1045, falls back to a
  neutral icon when 1015), filename, size, layers, print time,
  per-slot color chips, "currently printing" badge when the row
  matches `runningFilename`.
- Actions: **Print** (opens a settings dialog mirroring the
  upload-driven print flow + visual-check hint), **Download**
  (shared `_DownloadLimiter(maxConcurrent: 2)` from the history
  panel, head-probe first, saves to
  `getExternalStorageDirectory()/handslice-downloads/`),
  **Delete** (confirmation dialog, then `deleteFile`, then
  automatic 1044 re-list).
- Running-print file row: Delete button disabled with a
  localised tooltip; Print button also hidden/disabled.

### UI – `widgets/printer_camera_panel.dart` + `widgets/mjpeg_viewer.dart`

- `getLivingVideoUrl` on section entry; errors surface as
  explicit text ("Could not get the stream URL", "method 1042
  failed: …"), never a black box.
- `MjpegViewer` is a lean own implementation (~230 LoC): parses
  `multipart/x-mixed-replace; boundary=frame`, extracts JPEG
  frames by `Content-Length`, renders via
  `Image.memory(..., gaplessPlayback: true)`. No external
  package → F-Droid-friendly, AGPL-3.0 compatible.
- Lifecycle: viewer `active` prop is driven by
  `visible && appResumed`. On transition to `false` the HTTP
  connection is force-closed; on return `true` a fresh request
  is started.
- Error states (connect fail, no first-frame within 10 s, server
  closed stream, HTTP ≠ 200 / wrong Content-Type) each produce a
  distinct localised message.

### Scope kept narrow

Per Klaus's rule, the only methods issued to the real printer
during this work were the two live reads above (1045/1046). All
mutating operations — print start, download, delete, light,
camera stream open — are triggered **by Klaus in the app**, not
by any script in this repo. `tools/cc2-block-a.py` carries the
new `thumbnail` and `detail` subcommands for repeatable
verification.

---

## M8 device test – follow-ups (CC2 fw 02.01.01.07, 2026-10-31)

Klaus tested App `55ae65f` on the Poco X3 Pro. Working: file
listing (with thumbnails/colours/slots), live camera. Not
working: the "Download" button saved files but **the user could
not find them in the Android file manager**.

### Root cause (ADB, read-only)

```
$ adb shell ls /storage/emulated/0/Android/data/dev.handslice.handslice/files/handslice-downloads/
handslice_1793449708341.gcode   # 221 143 bytes
```

That path is Android's *app-private external storage*. Since
Android 11 it is **not visible** from user-facing file managers
without ADB. The file ended up there because
`PrinterFilesPanel._downloadDir()` used
`getExternalStorageDirectory()` directly, without a MediaStore
mirror.

### Fix: MediaStore mirror on save

- New Kotlin bridge in `MainActivity.kt`:
  - `saveGcodeToDownloads(srcPath, displayName, mime)` – inserts a
    row into `MediaStore.Downloads.EXTERNAL_CONTENT_URI` with
    `RELATIVE_PATH = Download/Handslice`, streams the bytes in,
    flips `IS_PENDING` to 0. Returns the `content://` URI.
  - `openUri(uri, mime)` – fires `ACTION_VIEW` with
    `FLAG_GRANT_READ_URI_PERMISSION`; returns `true` if a handler
    was found. No READ_EXTERNAL_STORAGE needed.
  - Existing `saveVideoToGallery(..)` keeps the Movies/Handslice
    path for the timelapse flow (unchanged).
- Dart side (`PrinterFilesPanel`):
  - After the local write to the app-private dir, the panel
    invokes `saveGcodeToDownloads`. On success it stores the
    returned URI in `_downloadUris[filename]`.
  - UI shows a new confirmation line
    ("Saved to Download/Handslice (visible in Files app)")
    plus two outlined buttons: **Open** (platform intent to the
    MediaStore URI) and **Share** (`share_plus` on the
    app-private file).
  - MediaStore mirror only runs on Android; the fallback
    "Saved to {path}" message stays available for other
    platforms.
- `minSdk` already 29 (handslice project constraint), so the
  MediaStore.Downloads path has no compatibility caveat.

### Small UX fixes shipped with the same commit

- Header text was still "Druckhistorie" / "Printer history" on
  the Files and Camera sections. Now it switches with the
  selected segment: **"Dateien am Drucker"** / "Printer files",
  **"Druckhistorie"** / "Printer history",
  **"Live-Kamera"** / "Live camera".
- The History-only Refresh icon no longer appears on the other
  two sections.
- The per-file **Download** label used to wrap on narrow phones.
  Replaced with an icon-only `IconButton` + tooltip, matching
  the Delete button.
- Camera panel: tapping the preview opens a fullscreen view
  (`MaterialPageRoute(fullscreenDialog: true)`, Scaffold with
  black background). Fullscreen has its own `WidgetsBindingObserver`,
  and the inline panel pauses its own stream while the fullscreen
  overlay is open — so there is never more than one HTTP
  connection to the MJPEG server.

### Tests

- Updated `printer_screen_test.dart` "Section-abhaengiger
  Header": the default (Files) section no longer shows the
  Refresh icon; tapping "Historie" brings back the old
  Druckhistorie header + Refresh. 108/108 overall.

---

## M8 follow-ups 2 – print dialog, cancel semantics, cancel-during-levelling (2026-10-31)

### Firmware behaviour verified by Klaus (passing)

- File list with thumbnails, colours, size, layers, print time.
- Camera live + fullscreen.
- Download → Download/Handslice, Open/Share.
- Delete via `method 1047` with confirmation dialog; file is gone
  on both printer display and app list.
- Print existing file → start OK, printer actually pulled from
  slot A4. Running-print-protection ("cannot delete") held.

### Firmware behaviour to document (not a bug on our side)

**Cancel during auto-levelling delays the stop until the levelling
pass finishes.** Klaus hit Cancel while the printer was in
`sub_status 2901`/`2902` (Homing/Levelling); the printer completed
the levelling cycle and only then transitioned to Cancelling /
Idle. The app's 1022 request was accepted, but the matching
`api_response` only came after the levelling finished – well past
the earlier 10 s client-side timeout. The firmware does not
interrupt an in-flight motion-planning operation mid-stride on
this firmware (`02.01.01.07`).

### Fixes in this commit

**Cancel/Pause now follow the Resume pattern.** Both 1021 and
1022 are issued with a short client-side wait (5 s) that only
distinguishes two outcomes:

| Return                | Semantics                                                     |
|---|---|
| `error_code == 0`     | printer accepted – UI stays quiet, status watcher takes over  |
| `error_code != 0`     | **real refusal** – `lastError = control.<verb>.error_code.N`  |
| `TimeoutException`    | **no refusal**; the printer may answer later (levelling case). UI relies on `sub_status 2501/2502` for pause and `2503/2504` for cancel. `lastError` stays `null`, return value is `true`. |

Resume (1023) is unchanged (fire-and-forget).

**control.* keys now get localised text in the UI.** The new
helper `mapControlErrorToText(l, key)` in
`app/lib/net/control_error_label.dart` turns
`control.cancel.error_code.42` into "Cancel rejected by the
printer (error_code=42)" and `control.light.timeout` into "Chamber
light: no reply from the printer in time". The old `lastError`
pass-through through `l.printControlFailedPause(detail)` left the
raw key visible when there was no better text; that path now
runs through the helper first. The pure function covers all
three verbs (`pause`, `cancel`, `light`) × both kinds
(`error_code.N`, `timeout`).

**Guard test** (`test/control_error_label_test.dart`) iterates
every verb × kind combination for `en` and `de` and asserts:

1. `mapControlErrorToText(l, key)` is non-null and non-empty;
2. the returned text does not contain the substring `control.`
   (would be the sign of a raw-key leak).

### Smaller UI fixes

- **Start dialog for existing files**: now shows a Radio-style
  slot picker (A1..A4) exactly like the upload flow, and
  persists the selection via
  `PrinterState.setTrayAssignmentForTool0` so the next print
  dialog opens with the same choice.
- **Two bed-levelling switches merged into one** in both the
  upload-driven dialog (`PrintScreen`) and the existing-file
  dialog (`PrinterFilesPanel`). The new label is "Level the bed
  before this print" / "Bett vor dem Druck nivellieren". On the
  wire we send `bedlevel_force` and `printer_check` with the
  same boolean; the previous two-switch UI implied a difference
  that neither Orca nor the firmware actually surfaced to the
  user.
- **Colour chip relabelled from "PLA · A1" to "PLA · Filament 1"**
  / "PLA · Filament 1" (and localised). The `color_map[].t` is a
  file-local filament index, **not** a printer slot. The physical
  slot assignment happens later via
  `trayAssignmentForTool0` at print start; conflating the two in
  the file list caused Klaus's "wait, is Filament 1 really going
  to feed from slot A1?" moment.

---

## M8 follow-ups 3 – bedlevel_force vs printer_check: Orca 1:1 (2026-10-31)

### Belege im Orca-ElegooLink-Bundle

Datei
`engine/OrcaSlicer/resources/web/elegoolink/lan_service_web/index.html`,
drei Fundstellen:

- **@2599216 (multicolor-Druckstart):**
  `config: { delay_video, printer_check: d.value.bedLeveling,
  print_layout, bedlevel_force: !1, slot_map }`.
- **@2599552 (monochrom-Druckstart):**
  `config: { delay_video, printer_check: d.value.bedLeveling,
  print_layout }`. `bedlevel_force` fehlt hier ganz.
- **@2621481 (Retry-Pfad):**
  `ze.error_code === Th.BedMeshDataMissing && (y.value.config.
  bedlevel_force = !0, N(y.value))`.

### Interpretation

- **`printer_check`** ist der sichtbare User-Switch
  ("Bed Leveling") in Orcas Vue-UI. Bindet 1:1 an die Checkbox.
- **`bedlevel_force`** ist **kein** User-Toggle: initial immer
  `false`, nur beim Retry nach `error_code=1026
  BedMeshDataMissing` auf `true` umgestellt – derselbe Request
  wird dann noch einmal gesendet.

### Umsetzung in Handslice (nach Klaus-Freigabe "A — Orca 1:1")

- UI zeigt EINEN Switch mit neuem Label
  "Bett vor dem Druck nivellieren (ca. 200 s)" / "Level bed
  before printing (~200 s)" in beiden Start-Dialogen
  (`PrintScreen._PrintScreenState` und
  `PrinterFilesPanel._PrintSettingsDialog`).
- `PrinterState.startPrint` / `startPrintFile` haben jetzt genau
  einen Nutzer-Parameter `levelBed`, der an `printer_check`
  gebunden wird. `bedlevel_force` kommt beim Client-Call fest
  mit `false`.
- `_startPrintCore` prüft die Antwort:
  `errorCode == 1026 BedMeshDataMissing` → **genau ein Retry**
  mit `bedlevel_force=true`, gleicher restlicher Config, kein
  weiterer Loop. Vor dem Retry wird
  `lastHint = 'startprint.retry_forced_level'` gesetzt; die UI
  rendert daraus "Drucker hat keine Mesh-Daten – Nivellierung
  wird erzwungen" (im Upload-Flow als Infobox, im Datei-Flow
  als SnackBar).
- Die vorherige "beide Felder auf denselben Wert"-Vereinfachung
  wurde zurückgenommen; sie hätte beim angelassenen Switch
  immer `bedlevel_force=true` gesendet, obwohl Orca das nur im
  Retry tut.

### Tests

`files_and_camera_test.dart` neu `M8 1026-Retry (BedMeshDataMissing)`:
Fake-Client gibt beim ersten `startPrint` 1026 zurück, danach 0.
Asserts:

- genau zwei `startPrint`-Calls,
- erster Call `bedlevel_force=false, printer_check=true`,
- zweiter Call `bedlevel_force=true, printer_check=true`,
- `PrinterState.lastHint == 'startprint.retry_forced_level'`
  nach dem Lauf.

---

## M9 (Vorstufe) – slot colour as slice override + auto slot preselect (2026-10-31)

Vorstufe zu Pflicht 8 (Multicolor). Hier noch Mono-Druck:
Fach-Farbe wandert in den G-Code, und der Druck-Dialog waehlt
ein passendes Fach vor.

### Slice-Override: `filament_colour` aus dem Fach

- `project_state.slice(…, Map<String,String> slotOverrides)`
  nimmt eine zusaetzliche Override-Map. `slotOverrides`-Keys
  werden mit `putIfAbsent` nach den anderen Overrides gemergt:
  User-Overrides gewinnen, Fach-Werte fuellen nur den
  Profil-Default auf.
- `project_screen._slice()` baut die Map aus dem aktuellen
  `CanvasSlot` ueber den neuen Pure-Function-Helper
  `slotOverridesFor(slot)` in `settings/slot_matcher.dart`.
  Format: `{"filament_colour": "#RRGGBB"}`. Ein-elementiger
  Hex-String, den der CLI-`coStrings`-Deserialisierer als
  1-Vektor liest.
- Material/Filament-Profil wandert weiterhin ueber den
  Filament-Pfad (`filament_mapping.dart`), nicht als Override –
  so bleiben Rapid-PLA+ / PETG / … konsistent zum ECC2-Preset.

Verifikation `method 1046` nach dem Druckstart: `color_map[0].color`
muss die neu gesetzte Fach-Farbe tragen. (`1044` nutzt denselben
Header-Parser, ergibt denselben Wert.)

### Auto-Fach-Vorauswahl im Start-Dialog

Pure-Function `findSlotForFile(colorMap, slots)` in
`settings/slot_matcher.dart`:

- Material-Vergleich: case-insensitive + getrimmt.
- Farb-Toleranz: euklidische Summe der RGB-Komponenten ≤ 52²
  (Default `kDefaultColorToleranceSquared`). Faengt
  Spool-Jitter und Hex-Rounding, blockt aber klar verschiedene
  Farben.
- Rueckgabe `SlotMatchResult`:
  - `unique(trayId)` → Dialog waehlt das Fach vor.
  - `ambiguous` → letzte Nutzer-Wahl bleibt, kurzer Hinweis
    "Mehrere Faecher passen zu dieser Datei – letzte Wahl bleibt
    stehen." / "Several slots match this file — keeping your
    last choice."
  - `none` → letzte Nutzer-Wahl bleibt, Hinweis
    "Kein Fach passt zu Material/Farbe der Datei – letzte Wahl
    bleibt stehen." / "No slot matches the file's material/colour
    — keeping your last choice."

Umgesetzt in `_PrintSettingsDialog.initState()`: Dialog bekommt
jetzt zusaetzlich zur `filename` die `colorMap` der Datei; der
Match laeuft einmal und setzt das Fach bzw. haengt den Hinweis
ans Picker-Panel.

### Tests

`test/slot_matcher_test.dart`:
- `slotOverridesFor`: Hex-Normalisierung (mit/ohne `#`), leere
  Map bei ungueltiger Farbe.
- `findSlotForFile`: eindeutig / mehrdeutig / kein Treffer /
  Toleranz / case + trim / leere Eingaben / ungueltige Hex-Werte.
Vollsuite 126/126 gruen (+12 ggue M8-NB3).
