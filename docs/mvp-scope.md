# MVP-Umfang

Ziel des MVP: **ein vorbereitetes 3mf am Handy slicen und an den CC2 senden.**
So klein wie möglich, aber ein echter End-to-End-Durchstich.

## Drin (MVP)

- **Import:** 3mf (vorab vorbereitet, ggf. vorab bemalt).
- **Drucker:** ein Profil fest – Elegoo Centauri Carbon 2, 0.4 Düse.
- **Prozess:** Auswahl aus den mitgelieferten CC2-Prozess-Presets.
- **Filament:** Slot → Filament zuordnen (Dropdown; bei 3mf vorbelegt).
- **Automatik:** Auto-Anordnen + Auto-Supports als Toggle.
- **Slicen:** on-device (Phase 1) oder remote via `server/` (Phase 0).
- **Ergebnis:** G-Code + Kennzahlen (Druckzeit, Gramm je Filament, Flush).
- **Senden:** G-Code per LAN an den CC2 + Druck starten.

## Nicht drin (bewusst später)

- STL-Import + Auto-Orientierung (Phase 3).
- Layer-für-Layer-Vorschau (Phase 3; MVP: Gesamtvorschau/Thumbnail).
- Freihändiges Color-Painting (Phase 4).
- Mehrere Drucker, Profil-Editor, Kalibrier-Tools.
- Resin.

## Akzeptanzkriterium

> „Ich lade auf dem Handy ein 4-Farb-3mf, ordne meine Slots zu, tippe Slicen,
> sehe Zeit/Gramm, tippe Senden – und der CC2 fängt an zu drucken."

## Prüfkriterium für die Engine (Phase 1)

Das Slicing-Ergebnis muss **bytegleich** sein mit dem Desktop-Orca derselben
Version, gleiches Profil, gleiche 3mf. Prüfung:

```
sha256sum desktop.gcode device.gcode
```

Abweichungen nur in Kommentarzeilen (Zeitstempel, Hostname) sind zu
dokumentieren und per Filter auszuschließen; alles andere ist ein Fehler.
