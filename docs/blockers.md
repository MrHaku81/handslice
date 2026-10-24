# Blocker

Offene Probleme, die Claude Code nach der Drei-Versuche-Regel (`CLAUDE.md`)
hier ablegt. Neueste oben. Gelöste Einträge nach unten unter „Gelöst"
verschieben, nicht löschen.

Format pro Eintrag:

```
## #N – <Kurztitel>  (JJJJ-MM-TT, Phase X)
**Symptom:** was passiert
**Probiert:** 1. … 2. … 3. …
**Beobachtet:** was die Versuche gezeigt haben
**Vermutung:** wo die Ursache liegen könnte
**Frage an Klaus:** was zur Entscheidung gebraucht wird
```

---

## #1 – Orca v2.4.2 koppelt CLI an wxWidgets+GLFW  (2026-10-24, Phase A→B)

**Symptom:** `cmake --build … --target OrcaSlicer` mit `SLIC3R_GUI=OFF`
bricht in genau einer Datei ab: `src/OrcaSlicer.cpp:78 fatal error:
wx/stdpaths.h`. libslic3r selbst (255 von 258 Build-Schritten) baut sauber
durch.

**Probiert:**
1. `-DSLIC3R_GUI=OFF -DSLIC3R_STATIC=1 -DSLIC3R_PCH=OFF -DBUILD_TESTS=OFF
   -DORCA_TOOLS=OFF -DSLIC3R_BUILD_SANDBOXES=OFF` – libslic3r + alle
   `libslic3r_*`-Statik-Bibliotheken bauen, Linken des `OrcaSlicer`-
   Executables scheitert an `wx/stdpaths.h`.

(Weitere Versuche abgebrochen auf Klaus' Anweisung – Befund dokumentieren
statt vier Versuche durchprobieren.)

**Beobachtet:** `OrcaSlicer.cpp` (CLI-Entry, 7 545 Zeilen) hat ab Zeile 78
neun ungeguardete Includes: `<wx/stdpaths.h>`, 7× `slic3r/GUI/*.hpp`,
`<GLFW/glfw3.h>`. Insgesamt 88 Nutzungen von `Slic3r::GUI::*`, `wx*` und
`glfw*` außerhalb der `#ifdef SLIC3R_GUI`-Guards – fast alles für
Thumbnail-OpenGL-Rendering (Offscreen-FBO + GLFW-Hidden-Window) sowie für
die zentrale Datenstruktur `PartPlateList`, die historisch im
`Slic3r::GUI`-Namespace liegt. Die GUI-Header ziehen transitiv `<wx/wx.h>`,
`<wx/panel.h>`, `<wx/colour.h>` etc. in die Übersetzungseinheit.

**Vermutung:** Keine saubere CLI/GUI-Trennung bei Orca v2.4.2. Zwei
Ursachen: (a) `PartPlateList`/`PartPlate` ist semantisch Core, lebt aber
im GUI-Namespace; (b) CLI-Thumbnail-Rendering nutzt denselben
`GLCanvas3D`-Code wie die GUI, inklusive GLFW als Window-Backend.

**Konsequenz für Phase 1 (ARM64):** wxWidgets gibt es nicht offiziell
für Android, GLFW auch nicht. Das kann Cross-Compilation nicht lösen – es
ist strukturell. Vollständige Analyse: `docs/engine-integration.md`,
Abschnitt „Harter Befund: Orca v2.4.2 hat keine saubere CLI/GUI-Trennung".

**Frage an Klaus:** Welchen Weg nehmen? Fünf Kandidaten (ausführlich mit
Risiken in `docs/engine-integration.md`):

- **A:** lokaler Minimal-Patch an `OrcaSlicer.cpp` (CLAUDE.md-Grenzfall –
  kein Fork-Patch, aber eigener Patch; ca. 2 h; löst x86 **und**
  vermutlich auch Android).
- **B:** `SLIC3R_GUI=ON`-Vollbuild nur für Schritt A (x86). gtk3/
  webkit2gtk-4.1 als System-Deps über pacman (sudo nötig). Löst Android
  nicht – doppelter Pfad.
- **C:** PR an Orca-Upstream für saubere CLI-Option. Strukturell richtig,
  unabsehbare Zeitachse.
- **D:** älterer Orca-Tag prüfen (v2.0.0 … v2.3.2). Historisch war die
  Kopplung eher stärker, nicht schwächer – vermutlich dieselbe Mauer.
- **E:** Engine-Wechsel auf PrusaSlicer-Upstream. PrusaSlicer hat echtes
  CLI-Binary ohne wxWidgets-Pflicht. Elegoo-Profile sind aber nicht 1:1
  kompatibel; widerspricht der Grundentscheidung „Orca ist die Engine".

Phase 0 (Server auf AMR5) kann **jetzt schon** mit dem gebündelten
Desktop-AppImage laufen. Der Testlauf (Elegoo-CC2 0.4 Düse +
0.20 mm Standard + Elegoo PLA auf einem 20-mm-Würfel) erzeugt gültigen
G-Code: `engine/test/out-appimage/plate_1.gcode`, 209 KB, 100 Layer,
`result.json` → `return_code: 0`.

---

(keine weiteren)

---

## Gelöst

(noch keine)
