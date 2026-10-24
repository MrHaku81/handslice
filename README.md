# Handslice

**Ein mobil-nativer 3D-Drucker-Slicer fürs Handy.**
Android-Frontend über die offene OrcaSlicer-Engine – vom Handy aus slicen und
direkt an den Drucker schicken.

> Motto: *freeing the orca from the desktop.*

Handslice ist ein **eigenständiges Projekt**. Es bettet die Slicing-Engine von
[OrcaSlicer](https://github.com/SoftFever/OrcaSlicer) (SoftFever) ein und
übernimmt Profile und Netzwerkprotokoll aus
[ElegooSlicer](https://github.com/ELEGOO-3D/ElegooSlicer). Es ist **kein**
offizielles Produkt von SoftFever, Elegoo oder Bambu Lab.

## Grundthese

Slicen scheitert auf dem Handy **nicht an der Rechenleistung** – moderne
ARM-SoCs slicen ein Modell in Sekunden bis Minuten –, sondern an der
**fehlenden mobil-nativen Oberfläche**. Die harten Interaktionen (Anordnen,
Supports, Orientierung) macht Orca ohnehin automatisch; auf dem Handy werden
das Einzel-Taps. Übrig bleibt als echter Touch-Sonderfall nur das freihändige
Farb-Painting – und das ist bei vorab bemalten 3mf-Modellen nicht nötig.

Es ist eine **Produktlücke**, keine technische Wand.

## Zielbild (Workflow)

```
Modell laden (3mf/STL)
  → Drucker wählen (z. B. Elegoo Centauri Carbon 2)
  → Prozess-Preset wählen (0.20mm Standard …)
  → Auto-Anordnen / Auto-Supports (1 Tap)
  → Filamente/Slots zuordnen (Dropdowns, bei 3mf vorbelegt)
  → Slicen (on-device)
  → Vorschau + Kennzahlen (Zeit, Gramm, Flush)
  → an Drucker senden (LAN) + starten
```

Am Desktop bleiben bewusst: freihändiges Color-Painting und das feine
Inspizieren der Vorschau.

## Strategie: Orca zuerst, Elegoo danach

1. **Engine = OrcaSlicer-Upstream.** Keine Engine-Patches aus Hersteller-Forks,
   solange nicht ein konkreter Druck damit nachweislich besser wird.
2. **Elegoo-Teile als Schichten obendrauf:** Druckerprofile (`profiles/`) und
   das Netzwerkprotokoll des Device Assistant (`docs/elegoo-integration.md`).
   Beides liegt außerhalb der Engine und wird erst integriert, wenn der
   Orca-Build steht.

## Phasen

| Phase | Inhalt | Erfolgskriterium |
|---|---|---|
| 0 | App als dünner Client; Slicen läuft per Orca-CLI auf dem Build-Rechner (`server/`) | UI-Workflow end-to-end, G-Code kommt zurück |
| 1 | Orca-Engine headless als ARM64-Binary auf dem Gerät | **Bytegleicher G-Code** wie Desktop-Orca bei identischem Profil und 3mf |
| 1b | Elegoo-Profile aus ElegooSlicer einlesen | CC2-Profile laden ohne Fehler, G-Code identisch zu ElegooSlicer-Desktop |
| 2 | Elegoo-Netzwerkschicht: Discovery, Upload, Start, Status | CC2 startet einen vom Handy gesendeten Druck |
| 3 | STL-Import, Auto-Orient, Layer-Vorschau | – |
| 4 | Color-Painting, Mehrgeräte | – |

Details: `docs/roadmap.md`. Phase 2 kann parallel zu Phase 1 laufen – sie braucht
keinen Engine-Build, nur einen Drucker im LAN.

## Lizenz

**AGPL-3.0** – nicht optional. OrcaSlicer ist AGPL-3.0; ein Frontend, das die
Engine einbettet, ist ein abgeleitetes Werk und muss unter derselben Lizenz
stehen (inklusive Quelloffenlegung bei Netzwerknutzung). Siehe `LICENSE`.

## Struktur

```
handslice/
  README.md            dieses Dokument
  CLAUDE.md            Arbeitsregeln für Claude Code (unbeaufsichtigter Betrieb)
  PROGRESS.md          laufendes Protokoll – hier reinschauen, um den Stand zu sehen
  LICENSE              AGPL-3.0
  docs/
    architecture.md        Komponenten & Datenfluss, UI-Stack
    mvp-scope.md           was im MVP drin ist / was nicht
    engine-integration.md  Orca-Engine headless bauen & anbinden
    elegoo-integration.md  was aus ElegooSlicer übernommen wird – und was nicht
    networking-cc2.md      an den CC2 senden (Protokoll, Ports)
    roadmap.md             Phasen & Meilensteine als Checklisten
    test-setup.md          Build-Rechner, Testgerät, ADB
    blockers.md            offene Blocker (von Claude Code gepflegt)
  server/              Phase 0: kleiner Dienst, der die Orca-CLI auf dem Build-Rechner kapselt
  app/                 Frontend (Flutter/Compose – siehe architecture.md)
  engine/              Engine-Build (NDK) & Bridge
  profiles/            gebündelte Druckerprofile (CC2 …)
```

## Danksagung

OrcaSlicer (SoftFever und Team), Bambu Studio, PrusaSlicer, Slic3r – die
Linie, auf der dieses Projekt steht. ElegooSlicer für die abgestimmten
Centauri-Profile.
