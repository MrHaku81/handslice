# server/ – Phase-0-Dienst

Kleiner HTTP-Dienst auf dem AMR5, der die Headless-Orca-CLI kapselt, damit die
App schon vor dem Android-Engine-Build end-to-end funktioniert.

```
POST /slice     multipart: model.3mf, config.json  → job-id
GET  /jobs/<id> → status | {gcode_url, stats: {time_s, grams[], flush_g}}
GET  /presets   → verfügbare machine/process/filament aus ../profiles/
```

- Python (FastAPI oder Flask), nur im LAN, keine Auth (Phase 0).
- Ruft `../engine/bin/orca-slicer-x86 --slice …` auf; Jobs unter `jobs/`
  (ignoriert).
- Kennzahlen aus dem G-Code-Header parsen.

Wird in Phase 1 durch den On-Device-Aufruf ersetzt, bleibt aber als
Referenz-Slicer für den Bytegleich-Test erhalten.
