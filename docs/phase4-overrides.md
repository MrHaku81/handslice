# Phase 4.3 – `--overrides`: Metrik, Einzel-Nachweise, Validate

Dieses Dokument hält die Nachweise fest, die der Vertragstest
`engine/test/cli-contract-arm64.sh` am Poco produziert. Grundlage ist
Commit `ebbded2` (CLI + Script) + die danach installierte APK.

## 1. Filament-Metrik: 1172 mm vs. 1367 mm

Beide Zahlen stammen aus **demselben Baseline-Lauf** (Kerbenwürfel,
Standardprofil). Sie unterscheiden sich nur in der Zählweise:

| Zahl | Was gezählt wird | Woher |
|---|---|---|
| **1172.33 mm** | Positive `E`-Werte **nur** bei `G1`-Zeilen mit `X` oder `Y` (echte Extrusion ohne Prime-Pumpen) | Orcas Stats-JSON (`total_filament_used_mm` aus `GCodeProcessor`) |
| 1367 mm | **Alle** positiven `E`-Werte, inkl. der Prime-Pumpen nach `Retract` (`G1 E.728 F1800`, kein X/Y) | roher Grep im G-Code |

Differenz: **195 mm**, davon ~190 mm Retract-Summe (190 Retracts
á ~1 mm). Jede Prime-Pumpe nach einem Retract gibt genau die gleiche
Menge wieder in die Düse – es ist dasselbe Filament, nur hin- und
hergezogen. Die kanonische Zahl ist Orcas `total_filament_used_mm`.

**Konsequenz für den Vertragstest:** liest die Zahl jetzt aus dem
Stats-JSON und verifiziert zusätzlich, dass die G-Code-Rekonstruktion
mit XY-Filter sich damit deckt (`extrusion_canonical()` → Diff < 1 mm).

## 2. Drei Overrides einzeln (Poco, Kerbenwürfel)

Jeweils genau EINE Änderung, Metrik ausgewählt, die genau diese
Änderung belegt. Alle Zahlen aus `cli-contract-arm64.sh` Schritt 5
mit Commit `ebbded2`.

| Lauf | Z-Moves | Wall-Linien (Outer+Inner) | Infill-Linien (Sparse) | Filament (`total_filament_used_mm`) |
|---|---:|---:|---:|---:|
| baseline (keine Overrides) | 219 | 1 845 | 2 889 | 1171.9 mm |
| nur `layer_height=0.28`     | **187** (−14.6 %) | – | – | 1202.2 mm |
| nur `wall_loops=4`          | – | **3 133** (+70 %) | – | 1521.8 mm |
| nur `sparse_infill_density=40%` | – | – | **5 931** (+105 %) | 1762.5 mm |
| alle drei zusammen          | 174 | 3 133 | 5 931 | 2016.3 mm |

- `layer_height=0.28` ist strukturell korrekt: dickere Schicht → weniger
  Z-Moves. Filament fast gleich, weil die Dickenerhöhung die
  Linienbreite kompensiert.
- `wall_loops=4` fügt zwei weitere Perimeter-Loops hinzu →
  Wandlinien verdoppeln sich fast.
- `sparse_infill_density=40%` erhöht die Füllbahnen von Default (meist
  15 %) auf 40 % → Infill-Linien mehr als verdoppelt.

## 3. SlicingErrors sauber abgefangen

`engine/cli/handslice-cli.cpp`: `main()` ist ein dünner Wrapper um
`run(argc, argv)` mit try/catch-Kette:

```
SlicingErrors         → exit 10, pro Error eine "- "-Zeile
SlicingError          → exit 10
ConfigurationError    → exit 11
Slic3r::Exception     → exit 12
std::exception        → exit 13
```

Argument-/Benutzereingabefehler (`die()` aus Overrides-Parser etc.)
bleiben bei Exit 2.

**Nachweis am Poco** (`cli-contract-arm64.sh` Schritt 7):

```
--overrides '{"layer_height":"2.0"}' am Kerbenwürfel

exit=12
handslice-cli: Slic3r-Fehler: Flow::spacing() produced negative
  spacing. Did you set some extrusion width too small?
```

Kein `terminate called`, kein Core-Dump, lesbare einzeilige Meldung.

**App-Pfad:** `SliceProcessException(exitCode, stderr)` →
`ProjectState.lastError = 'slice.error:<code>:<msg>'` →
`_formatSliceError()` in `project_screen.dart` →
`AppLocalizations.sliceErrorExit(code, msg)` →
„Slicer fehlgeschlagen (Exit 12): handslice-cli: Slic3r-Fehler …"
(deutsch) bzw. englisch analog.

Die APK wurde nach dem CLI-Rebuild (Commit-Hash `9cd024abdd`) neu
gebaut und installiert; die `libhandslice_cli.so` im App-Bundle
enthält damit die try/catch-CLI. Screenshot:
`docs/media/screenshots/handslice_sliceerror.png` — zeigt den
Fehlertext im UI nach dem per App gesetzten Override
`layer_height = 2.0`:

> Slicer fehlgeschlagen (Exit 12): handslice-cli: Slic3r-Fehler:
> Flow::spacing() produced negative spacing. Did you set some
> extrusion width too small?

Ablauf verifiziert: Modell öffnen → Einstellungen → `Schichthöhe`
auf 2.0 (Zähler oben zeigt „1 Überschreibung") → zurück ins Projekt
→ `Auf dem Gerät slicen` → der CLI-Fehler landet lesbar als
`_ErrorBox` im Projekt-Screen.
