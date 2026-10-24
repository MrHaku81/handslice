# An den CC2 senden

Zielgerät: Elegoo Centauri Carbon 2 Combo (CANVAS-Vierfarbsystem), privat.
Zweitgerät für Tests ohne Multicolor: Elegoo Neptune 4 Pro (Klipper/Moonraker).

## Bisher bekannt (aus der Einrichtung)

- Offene Ports am CC2: **1883** (MQTT) und **8080** (HTTP).
- Der CC2 hängt an Uhrzeit und Konto-Bindung; ohne korrekte Zeit schlagen
  Verbindungen fehl.
- ElegooSlicer-Upload funktionierte unter Windows/macOS, unter Linux gab es
  Probleme (GitHub-Issues #59, #38); Verbindungen über VLAN/Subnetz-Grenzen
  scheitern. Handy und Drucker ins selbe Netzsegment.

## Zuerst prüfen: Moonraker?

Bevor das Elegoo-Protokoll reverse-engineert wird:

```
curl http://<cc2-ip>:7125/server/info
curl http://<cc2-ip>:8080/server/info
```

Antwortet ein Moonraker, ist Phase 2 im Wesentlichen fertig – Upload über
`/server/files/upload`, Start über `/printer/print/start`, Status per
WebSocket. Dann ist der Neptune 4 Pro mit demselben Modul abgedeckt.

## Falls Elegoo-eigenes Protokoll

- Im ElegooSlicer-Quellcode den Device-Assistant-Code lesen (Discovery
  vermutlich per UDP-Broadcast oder mDNS; Upload per HTTP auf 8080; Status
  per MQTT auf 1883).
- Mitschnitt mit Wireshark auf dem Desktop beim Upload aus ElegooSlicer –
  der schnellste Weg zur Wahrheit.
- Ergebnis hier dokumentieren: Endpunkte, Payloads, Reihenfolge.

## Modul-Schnittstelle (App)

```
discover()            → [Printer]
upload(gcode, name)   → ok / Fehler
start(name)           → ok / Fehler
status()              → {state, progress, temps}
```

Zwei Implementierungen hinter derselben Schnittstelle: `MoonrakerClient`
und `ElegooClient`. Phase 2 ist unabhängig vom Engine-Build und kann parallel
zu Phase 1 laufen.
