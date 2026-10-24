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

- [ ] Moonraker-Check am CC2 und am Neptune 4 Pro
- [ ] `MoonrakerClient` (Neptune) – Upload + Start + Status
- [ ] `ElegooClient` (CC2) – je nach Befund nachgebaut
- [ ] **Erfolg:** Vom Poco gesendeter Druck startet auf dem CC2

## Phase 3 – Komfort

- [ ] STL-Import + Auto-Orientierung
- [ ] Layer-Vorschau
- [ ] Support-Feintuning

## Phase 4 – Der harte Touch-Teil

- [ ] Color-Painting
- [ ] Mehrere Drucker, Profil-Editor

## Risiken

- Orca-ARM64-Build zäh oder unmöglich → Fallback CuraEngine (Profilübersetzung
  nötig).
- Elegoo-Protokoll ohne Moonraker → Reverse-Engineering, Aufwand unbekannt.
- APK-Größe durch gebündelte Engine → über Release-Assets, nicht im Repo.
- MIUI-Hintergrund-Killing → Foreground-Service, Akku-Ausnahme.
