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
