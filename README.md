# Handslice

**[English](README.md) | [Deutsch](README.de.md)**

> ⚠️ **Work in progress — not released yet.**
> As of October 2026 this is pre-alpha. The slicing engine runs on
> Android (arm64) and the first print has been sent from a phone to
> an Elegoo Centauri Carbon 2. There is no app you can install, no
> binaries, no releases.

**A mobile-native 3D-printer slicer, built for the phone.**
An Android frontend on top of the open OrcaSlicer engine — slice on your
phone and send straight to the printer.

## First print

A 20 mm notched test cube sliced in under a second on a Poco X3 Pro
(Snapdragon 860). The G-code went over Wi-Fi to the CC2 — chunked HTTP
`PUT` on port 80, print start over MQTT on port 1883, both using the
printer's LAN-only mode. Fifteen minutes later the part came off the
bed clean. The timelapse is produced by the printer itself, clip in
[`docs/media/erster-druck-zeitraffer.mp4`](docs/media/erster-druck-zeitraffer.mp4).

A few hours later: **first print entirely from the app.** Model opened
on the phone, sliced on the Poco in 0.9 s, paired to the CC2 via
"Connect & load slots", uploaded and started with "Print" — all from
the running app, no desktop in the loop. Smooth build-plate side,
Z-offset −0.04 mm passed from app through to the engine, the first
layer picks up the carbon pattern across its full area. Timelapse:
[`docs/media/erster-app-druck-zeitraffer.mp4`](docs/media/erster-app-druck-zeitraffer.mp4).

> Motto: *freeing the orca from the desktop.*

Handslice is an **independent project**. It embeds the slicing engine
from [OrcaSlicer](https://github.com/SoftFever/OrcaSlicer) (SoftFever),
and borrows printer profiles and the network protocol from
[ElegooSlicer](https://github.com/ELEGOO-3D/ElegooSlicer). It is
**not** an official product of SoftFever, Elegoo or Bambu Lab.

## Premise

Slicing on a phone doesn't fail on **compute** — modern ARM SoCs slice
a model in seconds to minutes. It fails on the **lack of a mobile-first
UI**. The hard interactions (arrange, supports, orientation) are
already automatic in Orca; on a phone they collapse into single taps.
The one honest touch-only edge case left is freehand color painting —
and that doesn't come up with pre-painted 3mf models.

It's a **product gap, not a technical wall.**

## Target workflow

```
Load model (3mf / STL)
  → pick a printer (e.g. Elegoo Centauri Carbon 2)
  → pick a process preset (0.20 mm Standard …)
  → auto-arrange / auto-supports (one tap)
  → map filaments to slots (dropdowns, pre-filled for 3mf)
  → slice (on device)
  → preview + stats (time, grams, flush)
  → send to printer (LAN) + start
```

Freehand color painting and detailed preview inspection stay on the
desktop by design.

## Strategy: Orca first, Elegoo second

1. **Engine = OrcaSlicer upstream.** No engine patches from
   vendor forks unless a concrete print measurably improves.
2. **Elegoo bits as layers on top:** printer profiles (`profiles/`)
   and the Device Assistant's network protocol
   (`docs/elegoo-integration.md`). Both live outside the engine and
   get wired in only once the Orca build is standing.

## Phases

| Phase | Scope | Done when |
|---|---|---|
| 0 | App as a thin client; slicing runs via Orca CLI on the build host (`server/`) | UI workflow end-to-end, G-code comes back |
| 1 | Orca engine headless as an ARM64 binary on the device | **✓ 2026-10-24:** arm64 binary slices the test cube in 0.9 s on the Poco X3 Pro, G-code functionally valid. Byte-for-byte equality with the desktop refined rather than relaxed — nondeterminism finding in `docs/engine-integration.md`. |
| 1b | Load Elegoo profiles from ElegooSlicer | CC2 profiles load without errors, G-code identical to ElegooSlicer desktop |
| 2 | Elegoo network layer: discovery, upload, start, status | **✓ End-to-end 2026-10-25:** UDP discovery + MQTT register + HTTP `PUT` upload + `method 1020` print start all work against the CC2; first print ran cleanly through. App client still missing. **Update 2026-10-31:** live status (`api_status`, `method 1036/1051`), timelapse download, and file deletion (`method 1047` with a `file_path` list) are verified on stock firmware 02.01.01.07 — see `docs/networking-cc2.md`, section "Block A device test". |
| 3 | STL import, auto-orient, layer preview | – |
| 4 | Color painting, multi-device | – |

Details: `docs/roadmap.md`. Phase 2 can run in parallel with phase 1 — it
doesn't need the engine build, just a printer on the LAN.

## License

**AGPL-3.0** — not optional. OrcaSlicer is AGPL-3.0; a frontend that
embeds the engine is a derivative work and must ship under the same
license, including source disclosure on network use. See `LICENSE`.

## Layout

```
handslice/
  README.md            this document (English)
  README.de.md         same content in German
  CLAUDE.md            working rules for Claude Code (unattended use)
  PROGRESS.md          running log — read this to see where things stand
  LICENSE              AGPL-3.0
  docs/
    architecture.md        components & data flow, UI stack
    mvp-scope.md           what is in the MVP / what isn't
    engine-integration.md  building and wiring the headless Orca engine
    elegoo-integration.md  what we take from ElegooSlicer — and what we don't
    networking-cc2.md      talking to the CC2 (protocol, ports)
    roadmap.md             phases & milestones as checklists
    test-setup.md          build host, test device, ADB
    blockers.md            open blockers (maintained by Claude Code)
  server/              phase 0: small service wrapping the Orca CLI on the build host
  app/                 frontend (Flutter / Compose — see architecture.md)
  engine/              engine build (NDK) & bridge
  profiles/            bundled printer profiles (CC2 …)
```

## Acknowledgements

OrcaSlicer (SoftFever and team), Bambu Studio, PrusaSlicer, Slic3r —
the line this project stands on. ElegooSlicer for the matched Centauri
profiles.
