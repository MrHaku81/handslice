# Roadmap

Jede Phase ist ein eigener Auftrag an Claude Code mit eigenem, messbarem
Erfolgskriterium. Keine Phase gilt als erledigt, bevor Klaus die
Funktionskontrolle gemacht hat.

## Phase 0 – Proof of Concept (dünner Client)

- [ ] Headless-Orca-Build auf dem AMR5 (x86) – Schritt A aus
      `engine-integration.md`
- [ ] `server/`: kleiner HTTP-Dienst, der 3mf + Settings annimmt, Orca-CLI
      aufruft, G-Code + Kennzahlen zurückgibt
- [ ] UI-Stack entschieden (`PROGRESS.md`)
- [ ] App-Grundgerüst: 3mf laden → Preset wählen → an Server → Ergebnis anzeigen
- [ ] **Erfolg:** Vom Poco aus ein 3mf an den AMR5 geschickt, G-Code zurück,
      Kennzahlen stimmen mit Desktop-Orca überein

## Phase 1 – Engine on-device

- [ ] Deps für ARM64 cross-compiled (Schritt B)
- [ ] libslic3r + CLI für ARM64 (Schritt C)
- [ ] CLI als Asset in der App, Aufruf per Process (Schritt D)
- [ ] **Erfolg:** bytegleicher G-Code auf dem Poco vs. Desktop-Orca,
      `sha256sum` dokumentiert in `PROGRESS.md`

## Phase 1b – Elegoo-Profile

- [ ] Profile aus ElegooSlicer nach `profiles/Elegoo/` mit Herkunftsvermerk
- [ ] Liste der Fork-spezifischen Felder
- [ ] **Erfolg:** CC2-Profile laden fehlerfrei; G-Code identisch zu
      ElegooSlicer-Desktop oder Abweichungen dokumentiert

## Phase 2 – Senden (parallel zu Phase 1 möglich)

- [x] Moonraker-Check am CC2 (verneint; CC2 spricht proprietaeres MQTT).
      Neptune 4 Pro steht noch aus.
- [x] CC2-Protokoll ausgeleuchtet (UDP 52700 Discovery, MQTT 1883
      Register, chunked HTTP PUT 80 Upload, method 1020 Druckstart).
- [ ] `ElegooMqttClient` (CC2) – Pairing-UI mit Access-Code,
      Discovery, Upload, Start, Status (Delta-Merge + `method 1002`
      Vollabfrage + `method 2005` CANVAS). Reihenfolge der Reichweite:
      1. **LAN (MVP-Ziel).** Nur im Heim-WLAN. Erfordert `lan_status=1`
         am Drucker.
      2. **VPN (gratis-Erweiterung).** Fuer Fernzugriff im Alltag
         ohne eigenen App-Code: Tailscale oder WireGuard im Heimnetz
         einrichten, Nutzer verbindet sein Smartphone ins Heim-VPN,
         App spricht weiter LAN-Protokoll. In der App als
         „Fernzugriff ueber VPN" dokumentieren, nicht selbst
         implementieren.
      3. **Elegoo-Cloud als optionales Modul (nach MVP).**
         PIN-basierte Kopplung ueber Elegoo-Server. Standardmaessig
         **AUS**, in der UI klar als „ueber Elegoo-Server" markiert.
         Implementierung ableitbar aus ElegooSlicer (**AGPL** → unser
         Code bleibt AGPL-kompatibel, kein Lizenzkonflikt).
         Anmeldedaten muessen in `flutter_secure_storage` /
         Keychain / Keystore liegen, nicht im App-State.
         **Risiko:** Elegoo kann die Cloud-API jederzeit aendern;
         Reverse-Engineering-Zyklus wird dauerhaft noetig sein.
- [ ] `MoonrakerClient` (Neptune 4 Pro) – Upload + Start + Status.
      Separates Modul, Phase 2 davon unberuehrt.
- [ ] `SdcpClient` (CC1 / Resin-Serie) – spaetestens wenn das zweite
      Elegoo-Modell ins Spiel kommt; separates Modul.
- [ ] **Erfolg (LAN-MVP):** Vom Poco gesendeter Druck startet auf dem
      CC2 im Heim-WLAN, mit korrektem CANVAS-Slot-Mapping und
      aktivierter Bettnivellierung.

## Phase 3 – Komfort

- [ ] STL-Import + Auto-Orientierung
- [ ] Layer-Vorschau
- [ ] Support-Feintuning
- [ ] **Upstream-PR an OrcaSlicer** (Option C aus Blocker #1): saubere
      `SLIC3R_GUI=OFF`-CLI anbieten – `OrcaSlicer.cpp` so umbauen, dass
      wx-/GLFW-/`slic3r/GUI`-Pfade komplett im Guard liegen,
      PartPlateList aus dem `GUI`-Namespace in `libslic3r` ziehen,
      Thumbnail-Rendering per Build-Option abschaltbar. Bringt mittel-
      fristig die eigene CLI-Kopie (`engine/cli/handslice-cli.cpp`)
      weg und macht den Android-Build strukturell einfacher. Nur
      sinnvoll, nachdem Phase 0/1 steht und wir Belege haben.

## Phase 4 – Der harte Touch-Teil

- [ ] Color-Painting
- [ ] Mehrere Drucker, Profil-Editor

## Risiken

- Orca-ARM64-Build zäh oder unmöglich → Fallback CuraEngine (Profilübersetzung
  nötig).
- Elegoo-Protokoll ohne Moonraker → Reverse-Engineering, Aufwand unbekannt.
- APK-Größe durch gebündelte Engine → über Release-Assets, nicht im Repo.
- MIUI-Hintergrund-Killing → Foreground-Service, Akku-Ausnahme.
