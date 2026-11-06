# Fortschritt

Laufendes Protokoll. Neueste Einträge oben. Claude Code ergänzt nach jedem
größeren Schritt; Klaus liest hier tagsüber nach.

Format: `## JJJJ-MM-TT HH:MM – <Kurztitel>` und dann drei bis fünf Zeilen:
was gemacht, Ergebnis, offene Fragen.

Older entries: `docs/progress-archive.md`.

---

## Aktueller Stand

As of 2026-11-06. Sessions start here; open the archive only when needed.

**Done**

- Engine: arm64 CLI slices on the Poco; x86 cube G-code matches the v2.4.2 GUI reference.
- Printer: CC2 network path works end to end (first print 2026-10-25).
- App: slicing, upload, print start, live status, print control, files and live camera.
- Settings: process and per-slot filament settings work in the app (Phase 4.1–4.4).
- Timelapse: download in the app confirmed on the real CC2 (2026-10-26).
- Previews: G-code thumbnail, 3D view and layer preview are built (Pflicht 6, 7, 7a–7d).
- Divergence: five uninit fixes on `fix/uninit-handslice`; arm64 filament totals are stable.
- Fork: submodule runs on `MrHaku81/OrcaSlicer`, main commit `2931023`.

**Open**

- a) Device test of the current release APK on the Poco, and Bunny test print on the CC2 (both Klaus).
- b) Before the release, rebuild CLIs and APK from the final main commit.
- c) `fix/uninit-upstream` message cleanup: done on 2026-11-05; branch is not pushed.
- d) Valgrind, 12 `export_gcode` contexts: classified as post-slicing on 2026-11-05, not fixed.
- e) Reading upstream commit `99dea01cc3`: done, findings are in the evidence doc.
- Orca: evidence is complete, the issue text comes next. The PR covers only `d2e51c4c82`.
- Pflicht 7e (tubes): plan only, the APK rebuild waits for Klaus' go-ahead.
- arm64/x86 gap: 29 paths remain; uninit stack variables no longer drive it.
- Blocker #3 (Clang host build) is still open.

**Details:** `docs/upstream/orca-uninit-evidence.md`, `docs/blockers.md`,
`docs/engine-integration.md`, `docs/networking-cc2.md`, `docs/layer-view.md`,
`docs/progress-archive.md`.

---

## 2026-11-06 15:15 UTC – Housekeeping: PROGRESS.md split, CLAUDE.md shortened

All 123 entries moved unchanged to `docs/progress-archive.md`, oldest
first. `CLAUDE.md` wording shortened, reasons and examples moved to
`docs/claude-rules-background.md`, one new rule added on large outputs
and long runs. Printer, test-model and model-name rules added to
`CLAUDE.md` in Klaus' wording. No functional change.
