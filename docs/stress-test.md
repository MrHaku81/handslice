# Stresstest für die Slice-Pipeline

Reproduzierbare Messungen für ein beliebiges STL-Modell auf x86 (AMR5)
und arm64 (Poco X3 Pro über ADB).

## Script

```
bash engine/test/stress-test.sh <pfad/zur/modell.stl> \
    [--out <dir>] [--skip-arm64] [--skip-x86] [--bed A|B]
```

Was es misst:

- Slice-Dauer in ms (Wall-Clock, von vor dem Prozess-Start bis Exit).
- Peak-RSS aus `/proc/<pid>/status VmHWM` (Polling 1 s).
- Thermal-Status am Poco: `dumpsys thermalservice | grep "Thermal Status"`
  vor und nach dem Slice.
- Exit-Code (nicht-0 → Grenztest hat angeschlagen oder Preflight-Fehler,
  siehe `handslice-cli` Exit-Codes 10/11/12/13).
- Modell-Kennzahlen (Triangle-Anzahl, Bounding-Box) ganz ohne libslic3r.

Ausgabe:

- `<out>/<basename>-summary.txt` — alles in einem.
- `<out>/<basename>-x86.gcode`, `<basename>-arm64.gcode` — G-Code (falls
  erfolgreich).
- `<out>/<basename>-x86.log`, `<basename>-arm64.log` — stderr.
- `<out>/<basename>-x86-mem.log`, `<basename>-arm64-mem.log` — Mem-Polling.
- `<out>/<basename>-{x86,arm64}-stats.json` — Orca-Stats.

Modell und Zwischendateien bleiben lokal. `engine/test/stress-test.sh`
hat **keinen** fest verdrahteten Modellpfad.

## Messung vom 2026-10-25 (vor Phase 4.3)

Modell: `auryn.stl`, 2 809 436 Dreiecke, 134 MB. STL-Bounds
`X −93.15..+93.15`, `Y −35.01..+36.76`, `Z 8.00..217.11`, Höhe 209 mm.
Modell liegt um den Nullpunkt und 8 mm über dem Boden (für Druck ohne
Stützen gekippt).

Alle Werte am 25.10. erhoben. Ablauf: `--bed-type A`, keine Overrides,
Default-Centering an.

| Build | Slice-Dauer | Peak VmHWM | G-Code | Est. Druckzeit | Thermal (vorher/nachher) |
|---|---:|---:|---:|---|---|
| x86 (AMR5, Ryzen 7 5800U) | 22.2 s | 1 240 MB | 65 MB | 7h 11m 23s | – |
| arm64 (Poco X3 Pro, SD860) | 75.5 s | 1 126 MB | 65 MB | 7h 12m 51s | Status 0 / Status 0 |

- Keine thermische Drosselung am Poco trotz 75 s CPU-Volllast.
- G-Code x86 vs. arm64 nicht byte-gleich (bekanntes TBB-Reorder, siehe
  `docs/engine-integration.md`).
- Grenztest: `--no-center` (altes App-Verhalten) wirft
  `Slic3r::SlicingErrors` schon im Preflight — das Modell liegt bei
  `X < 0`, außerhalb des Druckbetts. Mit Centering (neuer Default seit
  Commit `bdea4b5`) läuft es ohne Fehler durch.

## Modell-Herkunft (auryn.stl)

Das Testmodell ist **nicht** Teil des Repositories.

- Titel: „Auryn Medallion – Print Ready – FREE"
- Autor: Droppingformdesigns
- Fundstelle: <https://cults3d.com/en/3d-model/art/auryn-medallion-print-ready-free>
- Lizenz: CULTS „Private Use" („No AI")

Zum Nachstellen bitte die Datei dort selbst herunterladen. Weder die
STL-Datei noch Renderings oder vom Druck entstandene Bilder landen im
Repo (siehe `.gitignore: /local-test/`). Das Modell wird ausschließlich
durch den Slicer verarbeitet — keine Weiterverarbeitung, keine
Analyse-Pipeline, kein Training.

## Vorschlag: frei lizenziertes Großmodell

Der Stresstest wäre ohne proprietäres Modell reproduzierbar, wenn das
Script selbst ein CC0-/CC-BY-lizenziertes Modell herunterladen und
abspeichern könnte. Vorschläge (zuerst nennen, nicht einbauen — Klaus
entscheidet):

- **Stanford Thai Statuette** (3Dscanrep / Stanford Graphics Lab) —
  ~10 Mio. Dreiecke, direkt lizenzfrei als Educational-Use. Download:
  <http://graphics.stanford.edu/data/3Dscanrep/>. Formell steht dort
  „Please be sure to acknowledge the source" — kein CC-Siegel, aber
  explizit zur Nutzung freigegeben. Für Repro-Zwecke wäre eine
  CC-BY-Variante aus Scan-the-World oder Smithsonian 3D sauberer.
- **Smithsonian Open Access 3D** (CC0): <https://3d.si.edu/>. Z. B.
  „Gorgoneion" (CC0, ca. 1,5–3 Mio. Dreiecke je nach Dezimierung),
  Lizenz explizit CC0 angegeben. Herunterladbar als OBJ/GLB, Konvertierung
  nach STL ist trivial.
- **Scan-the-World auf MyMiniFactory**: viele CC-BY-SA- und CC-BY-
  Statuen (Louvre, British Museum, V&A). Beispiel: „Diana of Versailles"
  — oft mehrere Mio. Dreiecke, CC-BY-SA. Downloadlink im Modell-
  Metadata jeweils einzeln angegeben.

Umsetzungsidee (nicht gemacht): `engine/test/stress-test.sh --download
<auswahl>` lädt und cached unter `local-test/stresstest-cache/<slug>.stl`,
schreibt die Lizenz-Metadaten als `<slug>.license.txt` daneben. Der
Default des Stresstests bleibt der mitgelieferte Kerbenwürfel – damit
geht das Skript auch offline, auch ohne Fremdlizenz.
