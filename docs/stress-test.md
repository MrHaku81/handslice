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
- **Peak Resident Set Size** aus zwei Quellen gegenübergestellt:
  - **getrusage** (`ru_maxrss`, in die CLI eingebaut und ins Stats-JSON
    als `peak_memory_kb` geschrieben) — das ist der echte Peak, hängt
    nicht vom Poll-Intervall ab.
  - **Poll** (`/proc/<pid>/status VmHWM`) — als Vergleich, zeigt wo das
    Polling-Intervall vorbeischießt.
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

## Messung vom 2026-10-25

Modell: `auryn.stl`, 2 809 436 Dreiecke, 134 MB. STL-Bounds
`X −93.15..+93.15`, `Y −35.01..+36.76`, `Z 8.00..217.11`, Höhe 209 mm.
Modell liegt um den Nullpunkt und 8 mm über dem Boden (für Druck ohne
Stützen gekippt).

Ablauf: `bash engine/test/stress-test.sh local-test/auryn.stl --out
/tmp/stress-auryn` mit `--bed-type A`, keine Overrides, Default-
Centering. CLIs frisch gebaut (Commit `ee4da3d7b5`).

| Build | Slice-Dauer | Peak RSS (getrusage) | Peak RSS (Poll) | G-Code | Est. Druckzeit | Thermal (vorher/nachher) |
|---|---:|---:|---:|---:|---|---|
| x86 (AMR5, Ryzen 7 5800U)   | **21.8 s** | **1651.8 MB** | 1637.1 MB (200 ms) | 65 MB | 7h 11m | – |
| arm64 (Poco X3 Pro, SD860)  | **77.2 s** | **1454.9 MB** | 1339.2 MB (1 s)    | 65 MB | 7h 12m | Status 0 / Status 0 |

- Keine thermische Drosselung am Poco trotz 77 s CPU-Volllast.
- G-Code x86 vs. arm64 nicht byte-gleich (bekanntes TBB-Reorder, siehe
  `docs/engine-integration.md`).
- Grenztest: `--no-center` (altes App-Verhalten) wirft
  `Slic3r::SlicingErrors` schon im Preflight — das Modell liegt bei
  `X < 0`, außerhalb des Druckbetts. Mit Centering (neuer Default seit
  Commit `bdea4b5`) läuft es ohne Fehler durch.
- **Diff getrusage vs Poll** am Poco: 1454.9 MB vs 1339.2 MB (= 115 MB
  Differenz). Peak lag zwischen zwei 1-Sekunden-Polls; `getrusage()`
  ist die kanonische Zahl. Am x86 liegen beide Werte dicht beieinander
  (200 ms Polling trifft den Peak gut).

**Historische Zahlen** vom früheren Lauf (Commit `bdea4b5`, Poll
alleine): x86 22.2 s / 1240 MB, arm64 75.5 s / 1126 MB. Dauer ist bis
auf Mess-Jitter identisch, der Peak war systematisch unterschätzt (der
alte Poll-Loop hatte 1-s-Intervall und `kill -0`-Race am Prozess-Ende).

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

## Frei verfügbares Großmodell per `--download`

```
bash engine/test/stress-test.sh --list-downloads
bash engine/test/stress-test.sh --download neptune
```

Kuratierte Modelle in `engine/test/stress-models.json`. Pro Eintrag:
`download_url`, SHA-256-Lock (optional), `license` (freier Text,
wird 1:1 in den Sidecar geschrieben), `attribution`, `triangles`.
Script lädt, prüft Hash, entpackt, schreibt `<name>.license.txt`
neben `<name>.stl` – beide landen in `local-test/stresstest-cache/`,
also gitignored.

### Default-Eintrag: `neptune`

- **1 556 886 Dreiecke**, 74 MB STL (zip 37 MB).
- Quelle: Three D Scans (Oliver Laric), <https://threedscans.com/uncategorized/neptune/>.
- Direkt-URL: `https://threedscans.com/wp-content/uploads/2023/04/neptuneRaw.stl.zip`
- SHA256 (zip): `b3d6fbb0124fd22d9cfefb60b93ad56d8d035b92ebc372350e0806442f8976fb`
- Lizenz: Die Website ist als „Free 3D scan archive" markiert, am
  Download sind weder Copyright-Vermerk noch CC-Siegel angebracht;
  Trägerschaft (Lafayette Anticipation, Secession Vienna, …) und
  Herkunftsinstitutionen (Louvre u. a.) sind auf threedscans.com/info
  genannt. **Nicht CC0/CC-BY zertifiziert** – wer Neptune
  weiterverteilen will, prüfe die Lizenz-Lage selbst
  (contact@threedscans.com).
- **Scaling (seit 2026-10-26):** Neptune liegt in Scanner-Rohscale
  (X span 3970 mm, Y span 15 475 mm, Z span 5 828 mm) – weit über dem
  CC2-Druckbereich. `stress-models.json` hat deshalb jetzt
  `scale_factor: 0.015`; `stress-test.sh --download neptune` reicht
  den Wert als `--scale 0.015` an die handslice-cli weiter, die ihn
  über Orcas eigene `ModelObject::scale(Vec3d)`
  (`libslic3r/Model.hpp:495`, `Model.cpp:1778`) anwendet. Ergebnis
  im Nachweis-Lauf 2026-10-26 (x86, bed B):
  - `max_z_height: 87.40 mm` (= 5828.30 × 0.015, exakt).
  - Slice-Dauer 8 519 ms, Peak-RSS 701 484 kB (685 MB) per
    getrusage.
  - G-Code 14.5 MB geschrieben, kein `SlicingErrors`-Preflight-
    Abbruch mehr.
  - Vertragstest `engine/test/scale-contract.sh` grün: `--scale 2.0`
    verdoppelt `max_z_height` im G-Code-Header; `--scale 0` wird
    abgelehnt.

### Smithsonian Open Access (CC0) – nicht automatisiert

Smithsonians 3D-Modelle (`https://3d.si.edu/`) sind unter CC0 1.0
Public Domain Dedication. Direkte curl-Downloads geben leider 403/404
(Browser-Session + JavaScript-Rendering erforderlich), weshalb der
`--download`-Pfad sie momentan nicht automatisch holen kann.
`stress-models.json` enthält einen Hinweis, wie eine Entry mit
stabiler direct-OBJ/GLB-URL hinzugefügt werden kann, sobald jemand
die URL manuell aus dem Smithsonian-Browser-Download kopiert hat.

Weitere Kandidaten (nicht als Default, noch nicht als Entries
hinzugefügt):

- **Scan-the-World auf MyMiniFactory** (meist CC-BY-SA): viele
  Statuen >1 Mio. Dreiecke. Downloads sind MyMiniFactory-Session-
  gebunden – gleicher Automatisierungsvorbehalt wie Smithsonian.
- **Stanford XYZ RGB Statuette** (3D Scanning Repository): ~10 Mio.
  Dreiecke als `.ply`. Explizit zur Nutzung freigegeben, aber kein
  CC-Siegel; libslic3r kann `.ply` nicht direkt – Konvertierung zu
  `.stl` nötig.
- **Wikimedia Commons** (Kategorie „3D models from the Smithsonian
  Institution"): einzelne Dateien direkt per CDN verfügbar; war beim
  letzten Lookup leer (0 Treffer) – Smithsonian lädt bei Commons nur
  Fotos hoch, keine .stl-Scans.
