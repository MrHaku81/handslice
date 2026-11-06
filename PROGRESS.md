# Fortschritt

Laufendes Protokoll. Neueste Einträge oben. Claude Code ergänzt nach jedem
größeren Schritt; Klaus liest hier tagsüber nach.

Format: `## JJJJ-MM-TT HH:MM – <Kurztitel>` und dann drei bis fünf Zeilen:
was gemacht, Ergebnis, offene Fragen.

> **Zeitstempel-Korrektur 2026-10-26 08:45 UTC:** Die vorher gesetzten
> Zeitstempel der heutigen Vormittag-Einträge waren systematisch ~4 h
> zu hoch (z. B. 1038-Lauf als „12:35 UTC" statt real 08:35 UTC).
> Ursache: Zeiten geschätzt statt aus `date -u` oder den Script-
> Logs abgelesen; wahrscheinlich eine fehlerhafte Zone-Rechnung
> auf dem Build-Rechner (CET=UTC+1, aber Verdoppelung durch
> Schätzung → +4 h). Alle 13 heutigen Einträge sind jetzt auf
> echte UTC-Zeit korrigiert und mit `UTC` markiert, Reihenfolge
> „neueste oben" wiederhergestellt.

---

## 2026-11-06 14:56 UTC – Orca uninit PR: noisra run on the large test model closes the Memcheck matrix

Evaluated the finished Memcheck run (plain-noisra binary, large test
model, PID 231116) with grep/tail only. Log:
`local-test/stufe-3c/upstream-main-valgrind/plain-noisra-largemodel/memcheck.log`.

- Result: `ERROR SUMMARY: 2103 errors from 13 contexts`, same totals as
  plain-debug on that model. `WallToolPaths`, `FillConcentricInternal`,
  `process_external_surfaces`, `LayerRegion`: 0 hits.
- A literal `mmuseg` grep also gives 0 hits in every log, because
  Memcheck prints functions, not members. The site is present as
  `ModelVolume::get_extruders() (Model.cpp:2760)`, 1 context in all
  four runs, 0 in fix-debug.
- `docs/upstream/orca-uninit-evidence.md`: added the matrix (Bunny /
  large test model × plain / noisra) and the new conclusion. Only
  `mmuseg_ts` is reached on upstream/main; the other two sites are
  documented on v2.4.2 and are offered in the issue as precautionary
  hardening, not as part of the PR.
- Doc corrections: the Fix #1 trace heading said Stanford Bunny, but
  the trace comes from the large-model log. "The paths are not
  executed" was softened, because Memcheck measures no coverage; the
  limit is now stated in the doc.

Open question for Klaus: "not reached" rests on Memcheck reports, not
on coverage, and `WallToolPaths.cpp` was not among the `-O0` units. Is
that enough for the issue text, or should a coverage or breakpoint
check confirm whether `FillConcentricInternal` runs on main?

---

## 2026-11-06 05:50 UTC – Orca uninit PR: two follow-up Memcheck runs confirm the "one site" reading

Follow-up after Klaus's note "die zwei Stellen fallen nicht aus dem
PR, Release+-g kann sie nicht zeigen" — two additional Memcheck runs
on `upstream/main b2978d1c73` to test the inliner-mask hypothesis and
the geometry hypothesis.

### Hypothesis A — targeted -O0 rebuild (2.4-Stufe-3c recipe)

Rebuilt `Fill/FillConcentricInternal.cpp`, `LayerRegion.cpp` and
`Model.cpp` with `-O0 -fno-ipa-sra -fno-inline-small-functions
-fno-ipa-icf` on top of the existing plain-debug (Release+`-g`)
libslic3r.a; three `.o` files ar-replaced in the archive, CLI
relinked. Full-libslic3r `-O0` had been tried first but Valgrind on
that build got stuck in `Clipper2Lib::ClipperBase::PopScanline` via
`PrintObject::discover_vertical_shells` after 80 min without reaching
the Fill phase; targeted rebuild keeps the rest at Release+`-g` for
speed.

Binary: `local-test/upstream-orca-build/plain-noisra/handslice-cli`.
Memcheck log:
`local-test/stufe-3c/upstream-main-valgrind/plain-noisra/memcheck.log`.
Stanford Bunny / ECC2-0.20 mm-PLA. Result:

```
ERROR SUMMARY: 1987 errors from 13 contexts
```

Same footprint as plain-debug Bunny. `WallToolPaths`,
`FillConcentricInternal`, `process_external_surfaces` remain
absent from every stack frame. **Inliner mask hypothesis
widerlegt.**

### Hypothesis B — Auryn exercises the Arachne path, Bunny does not

The original v2.4.2 Stufe-3c Memcheck that showed all three sites
(`local-test/stufe-3c/memcheck.log`) was actually run on Auryn, not
Bunny. Re-ran plain-debug Memcheck on the 140 MB Auryn STL with the
same profile on upstream/main.

Memcheck log:
`local-test/stufe-3c/upstream-main-valgrind/plain-debug-auryn/memcheck.log`.
Result:

```
ERROR SUMMARY: 2103 errors from 13 contexts
```

Same 13 contexts as plain-debug Bunny, just more occurrences each.
`WallToolPaths` / `FillConcentricInternal` /
`process_external_surfaces` still absent. **Geometry hypothesis
allein greift auch nicht auf upstream/main.**

### Combined per-site reading on `upstream/main b2978d1c73`

| commit | site | Bunny Release+-g | Bunny targeted -O0 | Auryn Release+-g | 2.4 baseline |
|--------|------|------------------|--------------------|------------------|--------------|
| `d2e51c4c82` mmuseg_ts | `Model.cpp:2760` | 1 context | 1 context | 1 context | yes |
| `093f4f26f8` LayerRegion `layer_thickness` | `LayerRegion.cpp:551` | 0 | 0 | 0 | yes |
| `ae511eb96c` WallToolPathsParams | `WallToolPaths.cpp:693` / `FillConcentricInternal.cpp:47` | 0 | 0 | 0 | yes |

Three independent runs, same reading: only the `mmuseg_ts` read can
be demonstrated on current upstream/main in this measurement
environment. The source for the other two sites is byte-identical to
v2.4.2, but something between v2.4.2 and `b2978d1c73` — likely a Fill
reorganisation, a Clipper2 migration side effect, or a profile
default change — removes the predicate chain that reached those
reads before.

### Updated evidence doc

`docs/upstream/orca-uninit-evidence.md` gets a new
"Two follow-up Memcheck runs confirming 'not reached'" subsection
under "Memcheck on upstream main", plus a "Final per-site reading"
paragraph that summarises the three runs. The PR plan stays as it
was in commit `367608b`: only `d2e51c4c82` is proposed upstream;
`ae511eb96c` and `093f4f26f8` stay on the local fork branch
`fix/uninit-upstream` and will only ship upstream once there is a
new reproducer that actually reaches the sites on current main.

### Final report (CLAUDE.md §4 rubrics)

**1. Demonstrably works**

- plain-noisra binary built via ar-replace of three `-O0`-recompiled
  `.o` members in plain-debug's `liblibslic3r.a`, Valgrind completed
  in ~6 min on Bunny, log carries the final `ERROR SUMMARY` line.
- plain-debug Memcheck re-run on Auryn, 32-min elapsed, log carries
  the final `ERROR SUMMARY` line.
- Both runs confirm what plain-debug Bunny already showed: only one
  of the three fix sites is reachable on `upstream/main b2978d1c73`.
- Doc + PROGRESS updated; main-repo submodule pointer unchanged;
  submodule branch unchanged.

**2. Unverified**

- Which specific commit on main removed the two unreachable paths.
  `git log` on `src/libslic3r/Fill/FillConcentricInternal.cpp` and
  on `src/libslic3r/LayerRegion.cpp` since the v2.4.2 base is on the
  order of 100 commits; bisecting that into a specific predicate
  change is scoped out of this PR preparation.
- Full-libslic3r `-O0` Valgrind. Would eventually have reached Fill
  but the Clipper2-phase alone ran >80 min without progress on this
  host; the partial log (`plain-O0/memcheck.log`, 22 lines) is
  identical to plain-debug up to its termination point.

**3. Blocked**

- Nothing new. Upstream PR stays at one commit until a current-main
  reproducer for the two other sites is available.

---

## 2026-11-05 11:40 UTC – Orca upstream PR preparation: Memcheck on upstream main narrows the PR to one commit

Follow-up after the init-mode SHA comparison came out all-identical:
pivot to Valgrind Memcheck `--track-origins=yes` on upstream/main to
check which of the three fix sites actually fires. Two debug builds
(Release+`-g -fno-omit-frame-pointer`, no `-ftrivial-auto-var-init`),
same upstream-main deps, same Elegoo CC2 0.20mm PLA / Stanford Bunny
200mm recipe as the 2.4 baseline:

- `local-test/upstream-orca-build/fix-debug/handslice-cli` — branch
  `fix/uninit-upstream` (three default-init commits).
- `local-test/upstream-orca-build/plain-debug/handslice-cli` —
  plain `upstream/main` at `b2978d1c73`.

Memcheck logs:
`local-test/stufe-3c/upstream-main-valgrind/{fix,plain}-debug/memcheck.log`.

### Summary

| build       | total errors | contexts |
|-------------|--------------|----------|
| plain-debug | 1 987        | 13       |
| fix-debug   | 1 986        | 12       |

Delta is exactly one context: `Slic3r::ModelVolume::get_extruders`
reading uninitialised `mmuseg_ts` at `src/libslic3r/Model.cpp:2760`,
origin the `ModelObject::add_volume` heap allocation at
`src/libslic3r/Model.cpp:1418`. Commit `d2e51c4c82`
(`mutable Timestamp mmuseg_ts { 0 };` at `Model.hpp:1021`) removes it
from fix-debug.

### Per-site result

| commit | site on upstream/main | reached under Memcheck | in PR |
|--------|-----------------------|-----------------------|-------|
| `d2e51c4c82` mmuseg_ts | `Model.cpp:2760` read, origin `Model.cpp:1418` | **yes** (1 context, dropped by fix-debug) | **yes** |
| `093f4f26f8` LayerRegion `layer_thickness` | `LayerRegion.cpp:551` | **no** — `process_external_surfaces` does not appear in any plain-debug stack frame | **drop** |
| `ae511eb96c` WallToolPathsParams | `WallToolPaths.cpp:693` read, origin `FillConcentricInternal.cpp:47` | **no** — `WallToolPaths`/`FillConcentricInternal`/`Arachne` does not appear in any plain-debug stack frame | **drop** |

Per the project rule *"falls eine Stelle auf main nicht mehr erreicht
wird, fällt der Fix aus dem PR"* the PR plan is now a single-topic
commit for the `mmuseg_ts` fix. The two other commits stay on the
local branch as defensive hardening for the fork but are not proposed
upstream.

Notes on the two "not reached" rows:
- The source at `FillConcentricInternal.cpp:47` (uninit
  `WallToolPathsParams input_params;`) and `LayerRegion.cpp:551`
  (uninit `double layer_thickness;`) is byte-identical between
  v2.4.2 and `b2978d1c73`; both sites still appear in the v2.4.2
  Memcheck log kept at `local-test/stufe-3c/memcheck.log`.
- They just do not fire on the Stanford Bunny / ECC2-0.20mm-PLA
  profile on GCC 16.2.1 + LTO + `-O3`. The v2.4.2 Bunny Valgrind that
  hit them was on a different enough toolchain / inline decision tree.
- The commits are therefore not obsolete, just not demonstrable on
  this specific slice on this toolchain.

### Remaining 12 contexts (both builds)

All in post-slicing / CLI-local code — `Slic3r::GCode::_do_export`,
`TimelapsePosPicker::construct_printable_area_by_printer`,
`GCode::placeholder_parser_process`, `GCodeWriter::set_extruders`,
`ClipperUtils::append_offset_path`, and three `round()` variants,
plus one stack local in `handslice-cli.cpp:854` which is a CLI driver
bug, not libslic3r. None of the twelve sits in the slicing pipeline.

### Evidence doc + PR plan updated

`docs/upstream/orca-uninit-evidence.md` now carries a dedicated
"Memcheck on upstream main" section with the summary table, the
per-site result, the mmuseg_ts trace and the "where the remaining 12
contexts live" break-down. The introduction is corrected to state
that the PR targets only `d2e51c4c82`; the earlier stale phrasing
("three uninit reads definitely still hit on b2978d1c73") is
replaced with the Memcheck-verified reading.

### Final report (CLAUDE.md §4 rubrics)

**1. Demonstrably works**

- Fresh x86 debug CLIs built on fix/uninit-upstream and on plain
  `upstream/main b2978d1c73` against the existing upstream-main deps
  (no re-deps build).
- Valgrind 3.25.1 Memcheck with `--track-origins=yes --threads 1
  --quiet` on both, Stanford Bunny 200 mm, ECC2 0.20 mm PLA. Both
  runs completed with a final `ERROR SUMMARY` line; delta is exactly
  one context corresponding to the `mmuseg_ts` fix.
- Evidence doc updated and committed with the full numeric table and
  the trace; PR plan reduced to the single `mmuseg_ts` commit per
  Klaus's rule.

**2. Unverified**

- Why the two other sites fail to fire on this toolchain. The
  v2.4.2 Bunny Valgrind did hit them, so either GCC 16.2.1's LTO
  constant-folds the uninit comparison, or the slicing path for this
  specific Bunny does not invoke the `FillConcentricInternal` /
  `process_external_surfaces` branches. Not investigated further in
  this round.
- Submodule branch `fix/uninit-upstream` is not rebased down to the
  single mmuseg_ts commit; the two defensive commits stay on the
  branch for the fork, and the PR submission path is a
  cherry-pick of `d2e51c4c82` alone.

**3. Blocked**

- Nothing new. Nothing pushed; main-repo submodule pointer unchanged.

---

## 2026-11-05 09:30 UTC – Orca upstream PR preparation: fix/uninit-upstream rebased on b2978d1c73, evidence doc written, x86 init-mode comparison built end-to-end

No pushes, no main-repo submodule-pointer change. All artefacts live
under `local-test/upstream-orca-build/` or under the submodule's local
branches.

### 1. Submodule `upstream` remote and branch state

- Submodule upstream remote URL switched from
  `https://github.com/SoftFever/OrcaSlicer` to
  `https://github.com/OrcaSlicer/OrcaSlicer.git`. The old URL 301-redirects
  to the new one; fetching verified.
- `upstream/main` fetched, now at `b2978d1c73`.
- Local submodule branch `fix/uninit-upstream` reset to upstream/main
  and the three applicable fixes cherry-picked with clean English
  commit messages (What / Why / Where / Evidence sections, no model
  name except "Stanford Bunny", no stage numbers, no "Handslice" or
  "Auryn" strings, Co-Authored-By trailer intact):
  - `ae511eb96c` fill: initialise WallToolPathsParams.min_length_factor
    and is_top_or_bottom_layer in FillConcentricInternal
  - `093f4f26f8` layer_region: default-init layer_thickness local in
    process_external_surfaces
  - `d2e51c4c82` model: default-init ModelVolume::mmuseg_ts to 0

### 2. Deps rebuild for upstream/main

Fresh deps build under
`engine/OrcaSlicer/deps/build-x86-upstream/` (handslice deps in
`deps/build-x86/` untouched). 24 targets plus `dep_SLVS`, `dep_Assimp`
and `dep_python3` (the three new deps on main). `dep_FREETYPE` is no
longer a standalone dep on upstream/main. `dep_FFMPEG` was built in a
follow-up pass after a local nasm 2.16.03 install under
`local-test/upstream-orca-build/tools/nasm-install/` (no system package
installed — nasm source compiled from the official tarball into a
project-local prefix).

### 3. x86 init-mode A/B test — Stanford Bunny

All four builds produced a 40 759 234-byte / 1 692 011-line
`bunny.gcode`. Raw SHA-256 differs only in the one header-timestamp
line (`; generated by OrcaSlicer … on <date> at <time>`); stripping
that line yields:

| build         | stripped SHA-256                                                   |
|---------------|--------------------------------------------------------------------|
| fix-pattern   | `99886b1c5dc6e8938e2fae74fd6e728988131c216f919ed2553e21f6faff505d` |
| fix-zero      | `99886b1c5dc6e8938e2fae74fd6e728988131c216f919ed2553e21f6faff505d` |
| plain-pattern | `99886b1c5dc6e8938e2fae74fd6e728988131c216f919ed2553e21f6faff505d` |
| plain-zero    | `99886b1c5dc6e8938e2fae74fd6e728988131c216f919ed2553e21f6faff505d` |

All four identical. Two reads of the result:

- The fix branch is bit-stable across init modes
  (`fix-pattern = fix-zero`). That is the reproducibility criterion
  that gates the PR, and it holds.
- The plain branch is also bit-stable on this specific slice
  (`plain-pattern = plain-zero`), and in fact the fix branch produces
  the same stripped SHA-256 as the plain branch. The three uninit
  reads definitely still happen on `b2978d1c73` (same source lines),
  but the Stanford Bunny / ECC2-0.20mm-PLA / x86 GCC 16.2.1
  combination does not land in a predicate where the uninit value
  (`-nan` for pattern, `0.0f` for zero, `0.5f` for fix) flips a
  decision. The amplification path that Valgrind trace #1 points at
  (`WallToolPaths::removeSmallLines` narrow-wall predicate) simply
  does not fire with a model-local threshold where any of the three
  values would select a different outcome.
- The amplification that *did* show up on the v2.4.2 baseline (arm64
  Stanford Bunny 3× bit-stable only after the fixes, per PROGRESS
  2026-11-04 19:26 UTC) is not reproduced on upstream/main simply
  because `-ftrivial-auto-var-init` stabilises the uninit reads at
  compile time — which is exactly what these three commits make
  unnecessary at the source level.

### 4. Evidence doc

New file `docs/upstream/orca-uninit-evidence.md`:
- Per fix: upstream/main file:line, `git blame` (commit hash + date,
  no author names per project policy), Valgrind trace from the v2.4.2
  Memcheck logs showing the uninit read path.
- `99dea01cc3` (Print::m_origin on upstream/main): lineage traced
  through PR #13712 and the follow-up PR #14482 that re-enabled three
  Catch2 tests disabled by the same "Coordinate outside allowed range"
  symptom; direct quote of the `[NotWorking]` tag comment and the
  PR-body justification. Shows the project has already treated an
  uninit-member bug on a slicing core member as a determinism issue
  rather than a harmless warning.
- Quotes from `engine/OrcaSlicer/CONTRIBUTING.md`,
  `engine/OrcaSlicer/AGENTS.md`, `engine/OrcaSlicer/.github/
  pull_request_template.md` and the issue templates relevant for an
  AI-assisted bug-fix PR.
- Build-on-upstream verification section with the four SHAs above and
  the "all four identical" reading.

### 5. Artefacts (not committed)

- Submodule branch `fix/uninit-upstream`, 3 commits on top of
  `upstream/main` b2978d1c73 (local only).
- `engine/OrcaSlicer/deps/build-x86-upstream/OrcaSlicer_dep/usr/local/`:
  full upstream-main dep prefix (Boost, TBB, CGAL 6.2.1, OCCT 8.0.1,
  OpenCV, OpenVDB, assimp, SLVS, python3 3.12.13, FFMPEG, …).
- `local-test/upstream-orca-build/{fix,plain}-{pattern,zero}/`:
  per-build output dirs with `handslice-cli`, `bunny.gcode`,
  `bunny.gcode.sha256`, `bunny.gcode.notimestamp.sha256`,
  `slice.log` and `slice.stats.json`.
- `local-test/upstream-orca-build/cli-cmake/CMakeLists.txt`: upstream-
  main-adapted CLI CMakeLists used by all four builds; the shared
  `engine/cli/*.cpp` sources are left untouched.
- `local-test/upstream-orca-build/build-and-slice.sh`: driver that
  invoked the build + slice pipeline once per (branch, init-mode) pair.
- `local-test/bunny-200mm.stl`: copy of `bunny_200mm.stl` renamed for
  the ADB upload that is still pending Klaus's go-ahead.

### Final report (CLAUDE.md §4 rubrics)

**1. Demonstrably works**

- Three clean commits on `fix/uninit-upstream` rebased to upstream/main
  tip `b2978d1c73` with English What/Why/Where/Evidence messages and
  the Co-Authored-By trailer, no model name except "Stanford Bunny",
  no stage numbers.
- Upstream-main deps built end-to-end (25 targets plus FFMPEG) with a
  locally-compiled nasm 2.16.03 (no system package touched).
- Four libslic3r + CLI builds against those deps succeeded
  (fix×{pattern,zero}, plain×{pattern,zero}); all four produce
  byte-identical Stanford-Bunny G-code once the header timestamp line
  is dropped (stripped SHA-256
  `99886b1c5dc6e8938e2fae74fd6e728988131c216f919ed2553e21f6faff505d`).
- `docs/upstream/orca-uninit-evidence.md` written and committed in the
  main repo, with per-fix Valgrind traces, blame hashes, the
  99dea01cc3 / #13712 / #14482 lineage and verbatim quotes of the
  AI-contributor rules in `CONTRIBUTING.md` and `AGENTS.md`.

**2. Unverified**

- No arm64 reproduction on upstream/main: Klaus has not asked for one,
  and the arm64 evidence on v2.4.2 is already in PROGRESS
  2026-11-04 19:26 UTC.
- `fix/uninit-upstream` has not been pushed. The Orca-side artefact
  download link that the PR template asks for is not available until
  Klaus opens the PR.
- `local-test/bunny-200mm.stl` has not been pushed to the Poco: Klaus
  said he will signal when.

**3. Blocked**

- Nothing new. The Stanford Bunny slice does not exercise an uninit
  read that `-ftrivial-auto-var-init` would flip (see §3 above), so
  this specific slice cannot serve as the "fix changes observable
  output" demonstration that the PR template might otherwise invite.
  The PR will instead rest on the Valgrind traces, `git blame` and the
  m_origin precedent — all present in the evidence doc.

---

## Offen nach Fork-Umschaltung (2026-11-04)

Offene Punkte nach dem Abschluss des Fork-Umbaus (Haupt-Commit 2931023,
Submodul-Zweig fix/uninit-handslice auf MrHaku81/OrcaSlicer).

a) Gerätetest der aktuellen Release-APK auf dem Poco (Klaus) und
   Probedruck Bunny auf dem CC2 (Klaus startet den Druck).

b) Vor dem Release CLIs + APK einmal mit dem finalen Haupt-Commit neu
   bauen (zuletzt HANDSLICE_CLI_COMMIT=50f88f5, HEAD ist 2931023).

c) Submodul-Zweig fix/uninit-upstream: Commit-Messages bereinigen
   (kein Modellname, interner Jargon raus), dann bauen und testen –
   Vorbereitung für Orca-Issue + PR.

d) Valgrind: 12 Kontexte im `export_gcode`-Pfad (TimelapsePosPicker,
   GCodeWriter::set_extruders, placeholder_parser_process) noch offen.

e) Upstream-Commit 99dea01cc3 (m_origin) lesen: wurde der
   Determinismus-Aspekt dort erkannt?

---

## 2026-11-04 19:26 UTC – fix/uninit-handslice: five clean uninit fixes on top of 8500fcdcca, verified; upstream rebase probe; PrusaSlicer comparison

Preparation for the handslice fork + Orca PR. No pushes; main-repo
submodule pointer unchanged (committed at 8500fcdcca; working tree is
on the new branch fix/uninit-handslice).

### 1. Branch `fix/uninit-handslice` (base 8500fcdcca)

Five commits, one per fix, English messages with What / Why /
Evidence and the Co-Authored-By trailer. Diffstat: 5 files, +6/-4
lines.

| sha        | summary                                                                                      |
|------------|----------------------------------------------------------------------------------------------|
| 63124563ef | clipper: default-init PolyNode::m_jointype / m_endtype                                        |
| 3aaf35dc83 | fill: initialise WallToolPathsParams.min_length_factor and is_top_or_bottom_layer in FillConcentricInternal |
| fccc0fe868 | print: default-init Print::m_origin to Vec3d::Zero()                                          |
| 06ca0d9ebb | layer_region: default-init layer_thickness local in process_external_surfaces                 |
| a13dce311e | model: default-init ModelVolume::mmuseg_ts to 0                                               |

No counter/debug/experimental code in any of these commits. The
instrumentation commits that previously rode on top
(`0b5d4c3a7e …eeb325e926`, `3965b4904c`) stay on
`experiment/arm64-divergence` only.

### 2. Verification (standard build flags; no HANDSLICE_COUNT_SPLIT_SOLID, no init flags)

Fresh binaries built from fix/uninit-handslice:

- `handslice-cli-x86`   (`engine/build-headless-x86.sh`)
- `handslice-cli-arm64` (`engine/build-cli-arm64.sh`)
- `handslice-cli-x86-debug` (`engine/build-headless-x86-debug.sh`)

Reference cube on new x86 binary via `engine/test/run-reference-test.sh`:
EXECUTABLE_BLOCK sha `92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d`,
8479 lines — **identical** to the pinned v2.4.2 GUI export.

arm64 reproducibility (three slices each, Poco X3 Pro, standard
binary; counters not available, so reproducibility checked via
`total_filament_used_mm` from stats JSON):

| model | 3× runs filament_mm                 |
|-------|-------------------------------------|
| Auryn | 39 223.4934147595 (3× identical)    |
| Bunny | 129 020.89814531246 (3× identical)  |

Full-gcode sha256 differs across runs only in header timestamps; the
semantic output is bit-stable. Stufe-3c reproducibility criterion met
under this branch.

Valgrind short run, Bunny x86-debug, `--threads 1 --quiet`
(`local-test/stufe-3c/uninit-handslice-valgrind/memcheck.log`):

- **ERROR SUMMARY: 1986 errors from 12 contexts** (vs 1987 / 13
  contexts under fix3; the one less context is the Model.cpp:2544
  `ModelVolume::get_extruders` record that the mmuseg_ts commit
  resolves — previously heap-origin via `ModelObject::add_volume`).
- Context breakdown: 4× `TimelapsePosPicker::construct_printable_area_by_printer`
  (s_round at Point.hpp:197 + ClipperOffset::AddPath at clipper.cpp:3391),
  1× `GCodeWriter::set_extruders` via `placeholder_parser_process`,
  6× `placeholder_parser_process` (variadic set-extruder, process_layer
  :4639, :4682, _do_export :3118, :3485, :3493, :3912). **All 12
  contexts are in `export_gcode`.** The slicing pipeline (Fill,
  Perimeter, Clipper core, Brim, LayerRegion::process_external_surfaces,
  Arachne/WallToolPaths) reports zero uninit records.

### 3. Upstream delta since 8500fcdcca

`origin/main` fetched today; tip `79985162e4`. Merge-base with
`8500fcdcca` is `3ffb9585d2`, confirming 8500fcdcca is on the Orca
2.4 release branch and not an ancestor of main. 3 623 commits on
main since the divergence.

Rebase probe branch `fix/uninit-upstream` (based on origin/main
79985162e4) — cherry-pick all five fixes:

| fix                      | result on upstream main | note                                                                                                                 |
|--------------------------|-------------------------|----------------------------------------------------------------------------------------------------------------------|
| PolyNode                 | **conflict (file gone)** | `deps_src/clipper/clipper.hpp` was removed by Clipper2 migration `222c6a2df5` (2026-10-02). Needs Clipper2 port.      |
| WallToolPathsParams      | auto-merge (OK)         | FillConcentricInternal.cpp hunk applied cleanly with offset (fix block moved from line 29 to 47 of upstream).         |
| Print::m_origin          | **already fixed**       | Noisyfox `99dea01cc3` (2026-06-22) introduced `Vec3d m_origin {0, 0, 0};` — equivalent to our `Vec3d::Zero()`. Skip. |
| LayerRegion::layer_thickness | auto-merge (OK)     | Line moved from 521 to 551 of upstream, same context.                                                                 |
| ModelVolume::mmuseg_ts   | auto-merge (OK)         | Line moved from 891 to 1021 of upstream, same context.                                                                |

Net branch state: `fix/uninit-upstream` = origin/main + 3 commits
(31a98f9cff, df0dbb5b06, def393b088). Not built, not tested — probe
only.

### 4. Per-fix `git blame` (introduction) and PrusaSlicer comparison

| fix line                              | introduced        | by                | PrusaSlicer master (tip `ff3d667` "Bumped up version to 3.0.0-alpha13") |
|---------------------------------------|-------------------|-------------------|-------------------------------------------------------------------------|
| PolyNode ctor, clipper.hpp:144        | 2022-07-15        | lane.wei (1555904bef, "Initial commit") | **identical bug** at `bundled_deps/clipper/include/clipper/clipper.hpp:143` — `PolyNode() : Parent(0), Index(0), m_IsOpen(false) {}` |
| WallToolPathsParams block, FillConcentricInternal.cpp | 2022-08-10 / 2022-10-12 | salt.wei (aab8a12801, 0f1a001fd6) | not compared — Arachne is Orca-specific                                 |
| Print::m_origin, Print.hpp:1192       | 2022-07-15        | lane.wei (1555904bef)   | **field does not exist** — PrusaSlicer has no Print::m_origin. BBS/Orca-only.           |
| LayerRegion::layer_thickness, LayerRegion.cpp:521 | 2023-10-19 | Noisyfox (075a08bca8)    | not compared (not requested; Orca-specific process_external_surfaces path).            |
| ModelVolume::mmuseg_ts, Model.hpp:891 | 2022-07-15        | lane.wei (1555904bef)   | **field does not exist** — PrusaSlicer has no mmuseg_* at all. BBS/Orca-only.          |

Takeaway: of the three fields the user asked us to cross-check in
PrusaSlicer, **PolyNode is a shared upstream bug** worth mentioning
in a PR (same bug since original Clipper1 import), while
`Print::m_origin` and `ModelVolume::mmuseg_ts` are BBS/Orca-specific
fields and cannot be ported upstream to PrusaSlicer. The PolyNode
fix is also moot on current Orca main because of the Clipper2
migration; our fix is still valid on the 2.4 release line.

### 5. Artefacts

- Submodule branches (local, not pushed):
  - `fix/uninit-handslice` — 5 commits on 8500fcdcca (the Handslice
    fork candidate).
  - `fix/uninit-upstream` — 3 commits on origin/main 79985162e4 (the
    probe for Orca PR; PolyNode and Print::m_origin not applicable).
- Standard binaries at HEAD of fix/uninit-handslice:
  `handslice-cli-{x86,arm64,x86-debug}` in `engine/bin/` (pre-fix
  binaries preserved as `*.prefix-backup`).
- Verification outputs under `local-test/stufe-3c/`:
  - `uninit-handslice-valgrind/{memcheck.log,run.sh}`
  - Poco: `/data/local/tmp/handslice/verify-uninit-handslice/`
    (3 Auryn + 3 Bunny runs); summary `verify.log`.

### Final report (CLAUDE.md §4 rubrics)

**1. Demonstrably works**

- Branch `fix/uninit-handslice` created at 8500fcdcca with five
  clean commits (sha trailer above), English messages with
  What / Why / Evidence / Co-Authored-By. No counter or debug
  code in the branch.
- Standard-flag cube reference on the new x86 binary:
  `92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d`
  identical to v2.4.2 GUI reference.
- arm64 Auryn 3× and Bunny 3× on Poco X3 Pro with the new standard
  binary: filament_mm bit-stable across runs (39 223.493 /
  129 020.898 mm).
- Valgrind Memcheck on Bunny x86-debug: slicing pipeline (Fill,
  Perimeter, Clipper core, Brim, LayerRegion::process_external_surfaces,
  Arachne) reports zero uninit records; the 12 remaining contexts
  are all in GCode export (`TimelapsePosPicker`, `GCodeWriter::set_extruders`
  via `placeholder_parser`, variadic set-extruder paths).
- Upstream rebase probe: 3 of 5 fixes cherry-pick cleanly to
  current origin/main; PolyNode blocked by Clipper2 migration;
  Print::m_origin already fixed upstream by 99dea01cc3.
- PrusaSlicer cross-check: PolyNode bug identical in PrusaSlicer's
  bundled_deps/clipper; Print::m_origin and ModelVolume::mmuseg_ts
  fields are BBS/Orca-specific and absent in PrusaSlicer.

**2. Unverified**

- fix/uninit-upstream has not been built or tested — probe only.
  Before submitting a PR, Klaus will want to build that branch
  on the upstream dependency set and rerun at least the cube
  reference test there.
- Whether the Clipper2 migration on upstream main
  (`222c6a2df5`) left the equivalent PolyPath/PolyTree member
  default-init in the same undefined state. Not inspected.
- WallToolPathsParams and LayerRegion::layer_thickness were not
  cross-checked against PrusaSlicer (not requested; also
  path-sensitive and may live in other files there).

**3. Blocked**

- Nothing new. Main-repo submodule pointer stays committed at
  8500fcdcca per instruction; no pushes performed.

---

## 2026-11-04 05:23 UTC – Divergence Stufe 3c decision test: init-mode invariance proves uninit stack variables no longer drive the arm64/x86 gap

Setup: experimental submodule branch `experiment/arm64-divergence` at tip
`3965b4904c` (three committed fixes: PolyNode-ctor-init,
WallToolPathsParams-init, Print::m_origin + LayerRegion::layer_thickness,
ModelVolume::mmuseg_ts). Main repo submodule pointer still `8500fcdcca`,
not pushed.

Six fresh binaries were built from the same tip to keep the three init
modes apples-to-apples:

| binary                                 | arch  | flag                              | sha of cube EXECUTABLE_BLOCK |
|----------------------------------------|-------|-----------------------------------|------------------------------|
| handslice-cli-x86-count-fix3b          | x86   | (none)                            | `92951c26…` (reference)      |
| handslice-cli-x86-count-pattern        | x86   | -ftrivial-auto-var-init=pattern   | n/a                          |
| handslice-cli-x86-count-zero           | x86   | -ftrivial-auto-var-init=zero      | n/a                          |
| handslice-cli-arm64-count-fix3b        | arm64 | (none)                            | n/a                          |
| handslice-cli-arm64-count-pattern      | arm64 | -ftrivial-auto-var-init=pattern   | n/a                          |
| handslice-cli-arm64-count-zero         | arm64 | -ftrivial-auto-var-init=zero      | n/a                          |

Reference cube on `handslice-cli-x86-count-fix3b` prints EXECUTABLE_BLOCK
sha `92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d`,
8479 lines — identical to the pinned v2.4.2 GUI export. The standard
reference test (`engine/bin/handslice-cli-x86`, not touched) and the
standard x86 count binary (`handslice-cli-x86-count`, backed up and
restored, byte-identical) remain unchanged. GCC on AMR5 is 16.2.1 →
`-ftrivial-auto-var-init` supported (since GCC 12); NDK 27.3 clang
supports it as well. For x86 I added `engine/build-headless-x86-count-init.sh`
analogous to the arm64 variant.

### 1. Decision test — init-mode invariance

Each of the six binaries slices Auryn and Bunny once with the ECC2 0.4 /
0.20mm Standard / Elegoo PLA profile set (`--quiet`, no `--no-center`;
Auryn is not centred on the plate origin, so the `--no-center` flag
from the cube test does not apply). HS_FILL_OUT paths and length_u
captured from stderr, filament_mm from the stats JSON.

x86 (AMR5, Ryzen 7 5800U):

| mode     | model | paths   | length_u       | filament_mm |
|----------|-------|---------|----------------|-------------|
| fix3b    | auryn | 229 200 | 190 744 245 585 | 39 223.579 |
| pattern  | auryn | 229 200 | 190 744 245 585 | 39 223.579 |
| zero     | auryn | 229 200 | 190 744 245 585 | 39 223.579 |
| fix3b    | bunny | 170 320 | 294 126 529 338 | 129 020.693 |
| pattern  | bunny | 170 320 | 294 126 529 338 | 129 020.693 |
| zero     | bunny | 170 320 | 294 126 529 338 | 129 020.693 |

arm64 (Poco X3 Pro, Snapdragon 860):

| mode     | model | paths   | length_u       | filament_mm |
|----------|-------|---------|----------------|-------------|
| fix3b    | auryn | 229 171 | 190 744 327 881 | 39 223.493 |
| pattern  | auryn | 229 171 | 190 744 327 881 | 39 223.493 |
| zero     | auryn | 229 171 | 190 744 327 881 | 39 223.493 |
| fix3b    | bunny | 170 331 | 294 112 789 727 | 129 020.898 |
| pattern  | bunny | 170 331 | 294 112 789 727 | 129 020.898 |
| zero     | bunny | 170 331 | 294 112 789 727 | 129 020.898 |

Within each architecture the three init modes are **identical in every
HS_FILL_OUT counter and in filament_mm**. Full-gcode sha256 still
differs across modes (the g-code stream has other non-slicing fields
that are sensitive to stack layout), but the slicing pipeline's output
is now mode-invariant.

Across architectures:

- Auryn: x86 229 200 vs arm64 229 171 → x86 has 29 more paths; length_u
  differs by 82 296 u (≈ 0.082 mm cumulative); filament 39 223.579 vs
  39 223.493 mm → Δ = −0.086 mm.
- Bunny: x86 170 320 vs arm64 170 331 → arm64 has 11 more paths;
  length_u differs by 13 739 611 u (≈ 13.74 mm cumulative); filament
  129 020.693 vs 129 020.898 mm → Δ = +0.205 mm.

Conclusion: no uninitialised stack variable is reachable from the
slicing pipeline on either architecture. The residual 29-path (Auryn)
and 11-path (Bunny) gap is a **deterministic platform computation
difference**, not a Heisenbug.

### 2. Auryn gap enumeration — layers and path types carrying the 29 paths

Per-layer HS_LAYER_FILL diff (x86 − arm64, only layers with Δpaths ≠ 0):

| layer | Δpaths | Δlength_u |
|-------|--------|-----------|
|  140 |  +2 |   +179 507 |
|  336 |  −6 |  −1 029 208 |
|  339 |  +5 |    +661 719 |
|  341 |  +3 |     −42 840 |
|  342 |  +6 |  +2 066 469 |
|  343 |  −2 |     +61 427 |
|  348 |  −1 |     −89 757 |
|  372 |  +1 |    +147 251 |
|  438 |  +2 |    −518 476 |
|  469 |  +5 |  +1 299 711 |
|  511 |  +1 |    +185 173 |
|  514 | +12 |  −2 305 069 |
|  581 |  +2 |        +356 |
|  594 |  −2 |    −264 968 |
|  686 |  +4 |    +900 244 |
|  712 |  +1 |      +1 550 |
|  728 |  +2 |    −265 673 |
|  799 |  −4 |    −399 301 |
|  802 |  −3 |    −397 278 |
|  828 |  +1 |      +2 534 |
| **net** | **+29** | **+82 296** |

20 layers out of 848 carry the delta. 14 positive (+47 paths total),
6 negative (−18 paths), netting +29 on x86.

Per-fill-type delta aggregated over those 20 diff-layers (`;TYPE:` block
counts in the gcode, perimeters excluded):

| fill type              | x86 | arm64 | Δ  |
|------------------------|----:|------:|----|
| Bridge                 |  18 |    18 |  0 |
| Internal Bridge        |   9 |     9 |  0 |
| Internal solid infill  | 198 |   202 | −4 |
| Sparse infill          |  84 |    83 | +1 |
| Top surface            | 121 |   120 | +1 |
| Gap infill             |  87 |    86 | +1 |

The TYPE-block count only shifts by ±4 in total — the remaining ~25
paths are **sub-path splits inside the same fill block** (one Internal
solid infill TYPE block containing N vs N+1 ExtrusionPaths on the two
architectures). Consistent with an FP-sensitive polyline split in
Fill::fill_surfaces or in the Clipper boolean ops that feed it, not
with whole surfaces appearing on only one side.

Direction-of-divergence hint: x86 produces more, shorter Internal solid
and Top-surface paths; arm64 collapses a few of them into longer
single paths. On Bunny the sign flips (arm64 11 more paths, less
total length), so this is not a "x86 always fragments more" rule but
a per-geometry outcome of local FP rounding.

### 3. Artefacts

All inputs, intermediates and the analysis script are under
`local-test/stufe-3c/entscheidungstest/`:

- `measure-x86.sh`, `measure-arm64-remote.sh`
- `{auryn,bunny}-x86-{fix3b,pattern,zero}.{gcode,stats.json,stderr,
  gcode.layer-fill-trace.txt,gcode.surf-fill-trace.txt}`
- `arm64/entscheidungstest/{...}` (same files pulled back from the
  Poco)
- `analyze-auryn-gap.py`, `analyze-auryn-paths-by-type.py`,
  `auryn-gap-by-type.txt`
- `x86-results.log`, `arm64/entscheidungstest/arm64-results.log`

### Final report (CLAUDE.md §4 rubrics)

**1. Demonstrably works**

- Decision test cleanly executed. Six binaries built from the same
  submodule tip `3965b4904c`; reference cube `92951c26…` identical
  under the new x86 standard build; `handslice-cli-x86` and
  `handslice-cli-x86-count` unchanged.
- Within each architecture, standard, pattern and zero init modes
  produce bit-identical HS_FILL_OUT counters and filament totals on
  both Auryn and Bunny. **Any uninit-stack-variable influence on the
  slicing counters is ruled out on both architectures.**
- The remaining arm64 ↔ x86 gap is characterised: 29 paths / +82 296 u
  on Auryn, 11 paths / −13 739 611 u on Bunny; 20 Auryn layers carry
  the net delta; per-fill-type aggregate shifts are ≤ 4 blocks, so
  the paths move mostly as sub-path re-splits inside the same TYPE
  blocks.

**2. Unverified**

- The IEEE-754 call site that drives the sub-path split. Candidates
  live in `Fill::fill_surfaces` (walker corner rounding) and in the
  Clipper boolean ops feeding the fill — not isolated this session.
- Whether Orca GUI (desktop) exhibits the same arm64 ↔ x86 delta on
  Auryn and Bunny. Only the headless CLI was tested here.
- Whether the three committed fixes (Print::m_origin,
  LayerRegion::layer_thickness, ModelVolume::mmuseg_ts) should go
  upstream to OrcaSlicer. First two cleanly fix observable Memcheck
  noise; mmuseg_ts is a semantic no-op on STL input. Decision still
  deferred.

**3. Blocked**

- Reducing the gap to zero without accepting an architectural fast-
  math-flag change. The surfaces/entries counts match (13 445 /
  10 116 on x86 vs 13 441 / 10 115 on arm64 for Auryn — a 4-surface
  / 1-entry delta that is orders of magnitude smaller than the 29-
  path delta it produces), so the earlier LayerRegion path is also
  near-identical. The last remaining lever to close the gap would
  be fmath/strict-float flags on the Fill walker — out of scope for
  this session.
- Blocker #3 (Clang build) unchanged.

---

## 2026-11-03 20:04 UTC – Divergence Stufe 3c fix3: third uninit source localised (Print::m_origin), slicing pipeline Memcheck-clean, arm64/x86 29-path gap still open

Setup: experimental submodule branch `experiment/arm64-divergence` advanced
from `14cd97c6` to tip `3965b4904c`. Three new commits on top of the two
earlier fixes:

- `eeb325e926` — Print.hpp:1192 `Vec3d m_origin { Vec3d::Zero() }` and
  LayerRegion.cpp:521 `double layer_thickness = 0.0`.
- `3965b4904c` — Model.hpp:891 `mutable Timestamp mmuseg_ts { 0 }`.

Main repo submodule pointer unchanged at `8500fcdcca`. Binaries built from
branch tip `eeb325e926` (not rebuilt for `3965b4904c` since that commit is
semantically a no-op on plain STL input): `handslice-cli-x86-count-fix3`,
`handslice-cli-arm64-count-fix3`, debug `handslice-cli-x86-debug-fix3`.
Standard reference-test cube still prints `92951c26…`.

### 1. Localising the third uninit source — framing correction

The previous Stufe-3c Memcheck logs attribute all 889 Brim uninit records
and all residual GCode records to `stack: handslice-cli.cpp:854 run()`.
A code audit of `run()` itself found no obviously uninit local — all
scalars, Eigen vectors and Orca utility structs we instantiate there carry
either an explicit `=` initialiser or a well-defined default ctor path
(`Semver{} → semver_zero()`, `ConfigSubstitutionContext{rl}`, explicit
designated init for `ThumbnailsParams`, …).

Targeted rebuilds of `Brim.cpp` + `LayerRegion.cpp` with
`-fno-ipa-sra -fno-inline-small-functions -fno-ipa-icf`, then of
`handslice-cli.cpp` with the same flags, then with `-fno-inline`, then
with `-O0`: none of these changed the reported origin. The
`.isra.0 clone` marker disappeared from the stack after the second
rebuild, but the origin stayed pinned to the function-start line of
`run()`.

Framing correction (per Klaus): the origin reports the **stack frame the
uninitialised bytes live in, not the file that declares the uninit
variable.** `Print print;` is on run()'s frame, so any field of `Print`
whose default-ctor leaves it uninit shows up as "stack: run()@854" even
though the bug is in `Print`'s ctor. The same is true for `Model`,
`DynamicPrintConfig`, `GCodeProcessorResult`, and everything else in
run() that is an Orca class with a `= default` ctor.

### 2. `Print::m_origin` (Print.hpp:1192)

Scan of all scalar/Eigen-vector members of Print declared without
default-initialiser surfaced `Vec3d m_origin;`. `Print() = default`;
Eigen's default-ctor leaves all three components uninitialised. The field
is only ever assigned via `set_plate_origin(Vec3d)`. Our CLI does not
call it, so `m_origin` remains uninit for the whole slice.

Usage chain into the Brim pipeline:

- `make_brim()` (Brim.cpp:940): `const Vec3d plate_offset =
  print.get_plate_origin();` → `Point(scaled(plate_offset.x()),
  scaled(plate_offset.y()))` translates `islands_area` and the
  per-object brim maps.
- `makeBrimInfillImpl()` (Brim.cpp:868): same read, translates each
  brim loop by the scaled plate offset.
- `PrintInstance::shift_without_plate_offset()` (Print.cpp:5150):
  `shift − Point(scaled(plate_offset.x()), scaled(plate_offset.y()))`.
  Called from Brim.cpp:31, :39, :50, :916, :923 — every brim
  polygon `translate()`.

The uninit bytes therefore propagate into every Point consumed by
`diff_ex`/`intersection_ex` in the brim pipeline. Clipper then
compares points at `clipper.cpp:92` (`FRound`), `:109` (IntPoint
operator==), `:610` (RangeTest), and Eigen's `MatrixBase.h:283`
(IntPoint comparison) — exactly the error sites in the earlier log.

Fix: `Vec3d m_origin { Vec3d::Zero() };` (one-line default-init).

### 3. `LayerRegion::layer_thickness` (LayerRegion.cpp:521)

In `process_external_surfaces`, a local `double layer_thickness;` is
passed by reference to three successive
`fill_surfaces_extract_expolygons(…)` calls. Each writes to it only
when a matching surface is found; if **none** of the layer's surfaces
is `stInternalSolid`, `stInternal`, or `stTop`, the variable stays
uninit and is later copied into three Surface `thickness` templates
(lines 570, 608, 613). Rare in practice (1 Bunny record pre-fix3),
but a real stack-local uninit. Pinned directly by Memcheck under the
targeted rebuild.

Fix: `double layer_thickness = 0.0;`.

### 4. `ModelVolume::mmuseg_ts` (Model.hpp:891)

`uint64_t mmuseg_ts;` field read in
`ModelVolume::get_extruders() const` at Model.cpp:2544
(`mmu_segmentation_facets.timestamp() != mmuseg_ts`). None of the
five ModelVolume ctors initialise it. On plain STL input the
semantic outcome is the same (`mmuseg_extruders` ends up empty
either way), but the uninit read is the last Memcheck record left
in the slicing phase after fix3.

Fix: `mutable Timestamp mmuseg_ts { 0 };`.

### 5. Memcheck under fix3 (binary built from `eeb325e926`; mmuseg_ts
not yet in binary — the one record below stays)

Bunny, threads=1, `handslice-cli-x86-debug-fix3`:

- **Error summary: 1987 errors from 13 contexts** (down from
  2566 contexts / 229 M errors on noisra pre-fix3).
- All remaining contexts are in `export_gcode`, not slicing:
  - 6× `GCodeWriter::set_extruders` (GCodeWriter.cpp:64) via
    `placeholder_parser_process`
  - 2× `TimelapsePosPicker::construct_printable_area_by_printer`
    (TimelapsePosPicker.cpp:86, :100), origin on run()'s frame
  - 1× `ModelVolume::get_extruders` via `Print::apply`
    (Model.cpp:2544, heap-origin at `ModelObject::add_volume`
    Model.cpp:1256) — addressed by commit `3965b4904c`
  - 4× various `placeholder_parser_process` (variadic set-extruder
    + layer-process paths)

Cube, same binary: 213 errors from 13 contexts. Brim-context: 0.

### 6. Measurement after fix3 (binary built from `eeb325e926`)

Reference test, standard x86 binary (unchanged submodule pin):
`92951c26…` identical.

Reference test, `handslice-cli-x86-count-fix3` on cube_20mm_centered_cc2:
EXECUTABLE_BLOCK sha `92951c26…` identical.

Auryn x86 (`handslice-cli-x86-count-fix3`, 1 run):

| metric    | value                   | Δ vs fix2 x86 |
|-----------|-------------------------|---------------|
| paths     | 229200                  | 0             |
| length_u  | 190744245585            | 0             |
| filament  | 39223.58 mm             | 0             |
| sha256    | `09f866c7…`             | changed (bytes reorder: plate-offset was non-zero pre-fix) |

Auryn arm64 (`handslice-cli-arm64-count-fix3`, 3 runs on Poco X3 Pro):

| metric    | value                | across runs   | Δ vs x86 fix3 |
|-----------|----------------------|---------------|---------------|
| paths     | 229171               | identical ×3  | **−29**       |
| length_u  | 190744327881         | identical ×3  | **+82 296**   |
| sha256    | 3 distinct           | 3 differ      | n/a           |

Bunny x86 (`handslice-cli-x86-count-fix3`, 1 run):

| metric    | value          |
|-----------|----------------|
| paths     | 170320         |
| length_u  | 294126529338   |
| filament  | 129020.69 mm   |
| sha256    | `8d5eaed4…`    |

Bunny arm64 (`handslice-cli-arm64-count-fix3`, 3 runs):

| metric    | value           | across runs   | Δ vs x86 fix3 |
|-----------|-----------------|---------------|---------------|
| paths     | 170331          | identical ×3  | **−11**       |
| length_u  | 294112789727    | identical ×3  | **−13 739 611** |
| sha256    | 3 distinct      | 3 differ      | n/a           |

### 7. Interpretation of the remaining arm64/x86 gap

The Print::m_origin fix is correct and eliminates the entire Brim
Memcheck noise (889 → 0 records), but **does not change the arm64
path counters on either model**: Auryn stays at 229171 paths and Bunny
at 170331 paths, exactly as under fix2. The uninit `m_origin` bytes
on arm64's default stack happened to be zero for this binary layout,
so forcing them to zero does not shift the output.

The 29-path (Auryn) and 11-path (Bunny) gap therefore has a different
driver — not addressed by any of the three committed fixes. Memcheck
on `handslice-cli-x86-debug-fix3` reports **zero** uninit records in
the slicing phases (Fill, Perimeter, Clipper core, Brim,
LayerRegion::process_external_surfaces) on Bunny.

Two remaining hypotheses:

- (a) An uninit heap-allocated field somewhere in the config /
  PrintObject / Layer / LayerRegion graph whose bytes get copied
  through without ever triggering a conditional Memcheck instruments
  (e.g. directly into a floating-point computation whose result ends
  up compared later, but tracked as `heap allocation` origin — the
  only such record left in the slicing phase under fix3 is
  `ModelVolume::get_extruders` on Model.cpp:2544, which the
  mmuseg_ts commit resolves). After that commit, slicing-phase
  Memcheck would drop to 0.
- (b) Legitimate IEEE-754 divergence between x86 and arm64 in `atan2`,
  `sin`/`cos`, or an `fma` path along the Fill walker or Clipper
  boolean ops. The PROGRESS 149300f claim "arm64 fix2 behaves exactly
  like a pattern-initialised build" was based on path-count sign
  (both −29 vs x86 default) and is suggestive but not conclusive — a
  pattern-init vs arm64 full byte-diff of the g-code was never
  performed.

Measuring the mmuseg_ts commit's effect requires rebuilding
libslic3r and relinking both count binaries; since the fix is
semantically a no-op for STL input, the counters would stay at
229171/170331 and only the Memcheck slicing-phase contexts would
drop from 1 to 0. Deferred.

### Abschlussbericht (CLAUDE.md §4 rubrics)

**1. Nachweislich funktioniert**

- Print.hpp:1192 uninit identified, fixed, Memcheck-confirmed:
  `handslice-cli-x86-debug-fix3` Bunny log shows 0 Brim records
  (vs 889 pre-fix3). All 889 records had stack-origin `run()@854`;
  all had error-site in Clipper comparisons on polygon
  coordinates fed through `shift_without_plate_offset` and
  `scaled(plate_offset.x/y)`.
- LayerRegion.cpp:521 uninit identified via targeted rebuild
  (`-fno-ipa-sra -fno-inline-small-functions -fno-ipa-icf` on
  Brim.cpp + LayerRegion.cpp), fixed, Memcheck-confirmed:
  Bunny log 0 external-surface records (vs 1 pre-fix3).
- Reference cube still byte-identical to GUI export
  (`92951c26…`) under `handslice-cli-x86-count-fix3`.
- arm64 output is reproducible across 3 Auryn runs and 3 Bunny
  runs (identical paths/length_u; SHAs differ by byte reorder
  only). Phase C reproducibility criterion still met.
- Framing lesson documented: "stack: run()@854" origin means the
  uninit bytes live on run()'s stack frame, which includes every
  Orca object constructed as a local in run() (Print, Model,
  DynamicPrintConfig, GCodeProcessorResult, …). Future uninit
  hunts should audit those classes' ctors, not just handslice-cli.cpp.

**2. Ungeprüft**

- arm64 **output byte-identical to x86** (Phase C hard criterion):
  **still not met**. 29-path / +82 296 length_u delta on Auryn, 11-path
  / −13 739 611 length_u delta on Bunny. m_origin fix, LayerRegion
  fix and mmuseg_ts fix do not close this gap.
- Whether the remaining gap is driven by a heap-allocated uninit
  field in PrintObject / Layer / LayerRegion that Memcheck
  classifies into the GCode-writer context, or by legitimate
  IEEE-754 FP differences between x86 and arm64. The pattern-init
  vs arm64 output byte-diff test was not run in this session.
- Effect of the `mmuseg_ts` commit (3965b4904c) on the Memcheck
  slicing-phase count. Expected: 1 → 0 records. Counters: no
  change. Not re-measured.
- Whether the three fixes should be submitted upstream to
  OrcaSlicer. Print::m_origin and ModelVolume::mmuseg_ts both
  exist identically in PrusaSlicer; LayerRegion::layer_thickness
  is OrcaSlicer-specific (the surrounding
  `process_external_surfaces` was rewritten in ORCA). Decision
  deferred.

**3. Geht nicht**

- Localising the 29-path arm64/x86 gap driver from the current
  Memcheck log. All slicing-phase uninit records are now either
  cleared (Fill, Perimeter, Clipper core, Brim,
  process_external_surfaces) or addressed by the mmuseg_ts commit.
  If the gap is heap-origin uninit, it is hidden by Memcheck's
  context attribution to the export-phase. If it is IEEE-754, it
  is not an uninit at all.
- Blocker #3 (Clang build) unchanged.

---

## 2026-11-02 23:52 UTC – Divergence Stufe 3c Both-Fixes Measurement: arm64 Fill now reproducible, Fill/Clipper/Perimeter Memcheck-clean, third uninit source identified in Brim/GCode

Setup: experimental submodule branch `experiment/arm64-divergence` tip is
`14cd97c6` (PolyNode-ctor-init + WallToolPathsParams-init). Main repo
submodule pointer unchanged at `8500fcdcca`. Binaries built from branch
tip: `handslice-cli-{x86,arm64}-count-fix2`, debug variant
`handslice-cli-x86-debug` (rebuilt tonight, both fixes in). Standard
reference test (via `engine/test/run-reference-test.sh`, which uses the
non-fix `handslice-cli-x86` binary) still prints EXECUTABLE_BLOCK sha
`92951c26…`. No pushes.

### 1. Contradiction between `tbbmalloc:2504` site and `BuildResult2` origin

Re-parsed `local-test/stufe-3c/memcheck.log` (116617 lines, 2962 Memcheck
records). Previous summary (368 records) had been a filtered subset.
Grouping by `(error-site, origin, call-context)`:

- **402** records have origin `stack:clipper.cpp:2802` (BuildResult2
  frame). Of these:
  - 365 hit site `tbbmalloc frontend.cpp:2504` (allocator's internal
    conditional on block header, triggered during `scalable_free` of
    `Polyline3`/`ExtrusionPath`/vector-of-ExtrusionPaths at destruct
    time, call-context mostly `PerimeterGenerator::process_classic`
    and `LayerRegion::process_external_surfaces`)
  - 37 hit `clipper.hpp:{174,421,543,…}` and `clipper.cpp:2858,2916,…`
    — PolyTree move-assign, Clipper/ClipperOffset dtor, intersect-list
    sort predicates. All are object-lifecycle paths that read into
    PolyNode-adjacent memory.
- **None** of the 402 originate from reads of application logic that
  consume `m_jointype` or `m_endtype` semantically.

The `clipper.cpp:2824` line is `polytree.AllNodes.emplace_back(PolyNode())`.
The temporary `PolyNode()` is constructed on BuildResult2's stack frame
and move-constructed into the deque element. Pre-fix the ctor leaves
`m_jointype`/`m_endtype` uninitialised; those two Enum bytes get copied
into every heap `AllNodes[i]` element and persist until the PolyTree is
destroyed. Memcheck therefore reports the origin as "stack: BuildResult2",
and the matching uninit bytes propagate through later destructor passes
until tbbmalloc's block-metadata inspection trips on them.

**→ The PolyNode fix is hygiene, not a semantic correction.** No code
reads these fields in a logic path. The initialiser removes a 365-hit
Memcheck noise source and incidentally shifts code generation
(register allocation / stack layout), which is what gave the arm64
variance a stable attractor. See point 4 — the fix is justified but
is not where the actual data-dependent variance comes from.

### 2. clipper.cpp:92 / :109 / :610 reads — full origin, full stack

All three sites appear in the pre-fix log hundreds of times (counts:
100, 97, 36). Pulled complete records; **all** have the same two
properties:

- **Error-stack (deepest project frame, first to top):**
  ```
  make_brim → outer_inner_brim_area → append_and_translate (Brim.cpp:42)
    → diff_ex (ClipperUtils.cpp:756) → _clipper_ex (ClipperUtils.cpp:739)
    → clipper_do_polytree → clipper_do → Clipper::Execute
    → ExecuteInternal → ProcessIntersections → BuildIntersectList
    → TopX → Round<long int> → FRound   [site clipper.cpp:92]
  ```
  or `ClipperBase::AddPathInternal` → `operator==(IntPoint,IntPoint)`
  [site clipper.cpp:109] / `RangeTest` [site clipper.cpp:610].

- **Origin:** `stack: handslice-cli.cpp:854` — line 854 is `static int
  run(int argc, char** argv) {`. The `.isra.0` optimisation clone-mark
  prevents Memcheck from pinning the exact declarative line. The uninit
  bytes come from **some stack variable allocated inside `run()` (or a
  function inlined into run())** and reach the Brim path through
  coordinates that pass through `diff_ex`.

Note the mismatch with pre-fix reasoning: **these reads live in the
Brim pipeline, not in the Fill pipeline.** The arm64 Fill variance
(230212 vs 212194) was never driven by these specific records; the
re-parsed table was dominated numerically by `make_brim` and
`process_external_surfaces` call contexts, but the Fill walker has
its own small set of records that we fixed with the
WallToolPathsParams initialisation.

### 3. Measurements with both fixes

Reference test (standard x86 binary, unchanged submodule pin,
cube_20mm): `92951c26…` identical.

Reference test with `handslice-cli-x86-count-fix2` on cube_20mm:
`92951c26…` identical — the fix does not touch cube output.

**Auryn x86 (`handslice-cli-x86-count-fix2`, 1 run):**

| metric    | value                   | Δ vs x86 pre-fix |
|-----------|-------------------------|-------------------|
| paths     | 229200                  | 0                 |
| length_u  | 190744245585            | 0                 |
| filament  | 39223.58 mm             | 0                 |
| sha256    | `87fa4a3a…`             | changed (byte reorder in some container; counters identical) |

**Auryn arm64 (`handslice-cli-arm64-count-fix2`, 10 runs on Poco X3 Pro):**

| metric    | value          | across runs | Δ vs x86 fix2       |
|-----------|----------------|-------------|---------------------|
| paths     | 229171         | identical ×10 | −29                 |
| length_u  | 190744327881   | identical ×10 | +82 296 (0.00004 %) |
| filament  | 39223.49 mm    | identical ×10 | −0.09 mm (0.00023 %) |
| sha256    | 10 distinct    | 10 differ   | n/a                 |

**→ arm64 is now reproducible at the slicing level.** The 10 distinct
SHA come from G-code line-emission order within containers whose
semantic content is identical (same paths, same lengths). The 29-path
delta between x86 (229200) and arm64 (229171) is the signature of the
`-ftrivial-auto-var-init=pattern` run from Stufe 3c (−29 paths vs
x86 default); arm64 fix2 behaves exactly like a pattern-initialised
build. That remaining 29-path gap is governed by the **third uninit
source** (point 4), which neither of the two committed fixes touches.

**Bunny arm64 (`handslice-cli-arm64-count-fix2`, 5 runs):**

| run | paths  | length_u      | filament      | sha256 |
|-----|-------:|--------------:|--------------:|--------|
| 1-5 | 170331 (×5) | 294112789727 (×5) | 129020.90 mm (×5) | 5 distinct |

Pre-fix Bunny arm64: 4/5 runs 129021.05 mm, 1/5 run 129017.77 mm.
Post-fix: 5/5 runs 129020.90 mm. Reproducible on a second model
confirms the fix is not Auryn-specific.

Reference cube re-run after fix2 is still `92951c26…`.

### 4. Valgrind with both fixes (Bunny, x86-debug, threads=1)

Full slice ran to completion in 25 min CPU
(`local-test/stufe-3c/fix2-valgrind/memcheck.log`, 93 247 lines,
2 506 contexts; prev run had 2 962). Classified by call-context:

| Category                                      | Pre-fix (Auryn, 2962) | Post-fix (Bunny, 2505) |
|----------------------------------------------|---------------------:|-----------------------:|
| Fill (fill_surface, Arachne, WallToolPaths)   |                 ≥38 |              **0**     |
| Clipper core (direct hits, no Brim/GCode ctx) |                >100 |              **0**     |
| Perimeter (PerimeterGenerator, make_perimeters) |              166 |              **0**     |
| Brim (make_brim, outer_inner_brim)            |              (part of "other") |         927 |
| External surfaces (process_external_surfaces) |                  76 |                   1    |
| GCode writer (export, placeholder, cooling)   |                1590 |                1356    |
| ClipperUtils / safety_offset                  |              (mixed) |                146    |
| Model/STL load                                |                   1 |                   1    |
| TBB allocator hits (frontend.cpp)             |                 402 |                   4    |
| libc / libstdc++ / other project              |                 629 |                  70    |

Zero remaining uninit reads in the Fill walker, Clipper core, or
Perimeter generator. The two committed fixes are confirmed to clear
exactly their claimed scope.

**Remaining dominant pattern (Brim, 927 records):** sites
`clipper.cpp:92/109/610` and `MatrixBase.h:283` (Eigen's
`IntPoint::operator==` → `all()` → `Visitor.h:397`) called from
`ClipperBase::AddPathInternal`, inside the
`make_brim → outer_inner_brim_area → diff_ex` call-chain. Origin for
all of them is `stack: handslice-cli.cpp:854` (the same
`.isra.0`-clone-masked `run()` frame as in point 2) — **the third
uninit source is in the Brim pipeline, not Fill, and the exact
originating local still needs localisation.** Likely candidate: an
uninit Point/BoundingBox/float field in one of the stack-allocated
containers inside `outer_inner_brim_area` or
`append_and_translate (Brim.cpp:42)`.

**Secondary pattern (GCode writer, 1356):** mostly
`clipper.cpp:92/109` reads from `GCode::needs_retraction` →
`intersection_pl` → `_clipper_pl_open`. Origin split between
`run()@854` (uninit propagated from earlier) and
`LayerRegion::process_external_surfaces (LayerRegion.cpp:487)`. The
latter is the LayerRegion external-surface routine itself — a
fourth, distinct uninit stack-var candidate.

### 5. Summary — what the fixes do and what is still missing

**(a) PolyNode default-ctor init (`deps_src/clipper/clipper.hpp:147`,
submodule commit `9aaa5ee5`):** Hygiene fix. Eliminates 402 Memcheck
hits whose origin is `stack:clipper.cpp:2802`. These are **not** read
by any application logic; the fields are inspected only during
allocator teardown of PolyNode-adjacent memory. The empirical variance
reduction (arm64 Fill from 212194–230212 range to a single attractor
near 230212 under `-fauto-var-init=zero` / pattern) comes from
incidental codegen shift (register allocation / stack layout changes
after adding two field initialisers), **not** from the fields being
semantically consumed. Still worth upstreaming: this is a real
`std::deque<PolyNode>` with persisting uninit bytes, present in
original Clipper 6 and PrusaSlicer alike.

**(b) WallToolPathsParams init in `FillConcentricInternal.cpp:29-35`
(submodule commit `14cd97c6`):** Real semantic fix. The uninit fields
are `float min_length_factor` and `bool is_top_or_bottom_layer`, both
read in `WallToolPaths::removeSmallLines` at `WallToolPaths.cpp:693`
as a width threshold that decides which lines are discarded. Defaults
match the canonical factory `make_paths_params()` at
`WallToolPaths.cpp:37` and `:56`. Memcheck confirms zero remaining
Fill-walker reads post-fix.

**(c) Still missing — third (and possibly fourth) uninit source,
located in the Brim / External-surfaces pipeline:**

- **Brim path**: 927 Memcheck records with sites
  `clipper.cpp:{92,109,610,…}` and `MatrixBase.h:283` inside
  `make_brim → outer_inner_brim_area → diff_ex`. Origin reported as
  `stack: handslice-cli.cpp:854` because the containing function is
  `.isra.0`-cloned by GCC's inliner; the real originating local
  cannot be read directly from the current log. Next step: build
  a slower debug variant with `-fno-ipa-icf -fno-inline-small-functions`
  on `make_brim`/`outer_inner_brim_area` only, or use
  `-ftrivial-auto-var-init=pattern` on just those TUs to see which
  byte-pattern differs between runs.
- **LayerRegion::process_external_surfaces (LayerRegion.cpp:487)**:
  identified as a distinct stack-allocation origin in the current
  log. One record flagged, propagates via Polyline/ExPolygon
  coordinates into `GCode::needs_retraction` reads during export.
  Smaller contribution than Brim but confirmed.

Both are **outside the Fill walker** and therefore likely explain only
the small 29-path arm64↔x86 gap, not the headline reproducibility.
Phase C ("arm64 output byte-identical to x86") is still open; Phase C
("arm64 output reproducible across runs on the same model") is **met**
for Auryn and Bunny with both fixes.

### 6. Housekeeping

- No pushes. Main repo clean except for the submodule-worktree HEAD
  pointer; main repo submodule reference stays on `8500fcdcca`.
- Co-Authored-By trailer added to any new commits per CLAUDE.md §5
  (none created this session: all code changes were already committed
  by the previous session as `9aaa5ee5` and `14cd97c6` on the
  experimental submodule branch).
- Artefacts moved from `/tmp/stufe-3c-valgrind` to
  `local-test/stufe-3c/{memcheck.log,parsed-summary.txt}` and
  `local-test/stufe-3c/fix2{,-valgrind}/*` (per new rule).
- Standard reference test still green:
  `92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d`.
- Clang-build still blocked (Blocker #3), unaffected.

### Abschlussbericht (CLAUDE.md §4 rubrics)

**1. Nachweislich funktioniert**

- Fill/Clipper/Perimeter Memcheck-clean under both fixes
  (`python3 local-test/stufe-3c/fix2-valgrind/analyse-remaining.py`
  prints `0 Fill / 0 Clipper / 0 Perimeter`).
- arm64 Auryn with both fixes is reproducible across 10 runs
  (`local-test/stufe-3c/fix2/summary.txt`): identical paths,
  length_u, filament. SHAs still differ (byte reorder only).
- arm64 Bunny with both fixes is reproducible across 5 runs
  (same summary file): identical paths and lengths; different SHAs.
- Standard reference-test cube remains byte-identical to pre-fix
  reference: `bash engine/test/run-reference-test.sh` → EXECUTABLE_BLOCK
  sha `92951c26…`.
- WallToolPathsParams fix proven to be a real read site via Memcheck
  origin `FillConcentricInternal.cpp:13` → read in `WallToolPaths.cpp:693`.
- PolyNode fix proven to clear 402 Memcheck records whose origin was
  `stack:clipper.cpp:2802`.

**2. Ungeprüft**

- arm64 **output byte-identical to x86** (Phase C hard criterion):
  still not met. 29-path and ~82 kµm length delta remain. Likely
  consequence of remaining uninit sources (c) and/or legitimate
  IEEE 754 differences between archs; not distinguished in this
  session.
- Brim/external-surfaces uninit sources (c): localised to call-chain
  but not pinned to specific stack variables. Would require either
  recompilation with inlining disabled on the suspected TUs or a
  targeted `-ftrivial-auto-var-init=pattern` build limited to
  `src/libslic3r/Brim.cpp` and `src/libslic3r/LayerRegion.cpp`.
- Whether the two fixes should be submitted upstream to OrcaSlicer
  (both exist identically in PrusaSlicer and original Clipper 6):
  decision deferred.
- Standard-build arm64 Auryn 1x (without count instrumentation,
  without fixes) was not re-measured this session; still assumed to
  show the earlier 212194–230212 variance.

**3. Geht nicht**

- Localising the Brim-path uninit stack variable from the current
  Memcheck log alone (`.isra.0` clone-folding hides the originating
  declaration). Not blocking; needs a targeted debug build.
- Blocker #3 (Clang build) unchanged.

---

## 2026-11-02 22:55 UTC – Divergenz Stufe 3c Fix-Test: PolyNode-Fix reduziert Varianz 70×, zweite Quelle in Arachne-WallToolPathsParams

### 1. Lese-Stelle und Begruendung der Default-Werte

Alle Reads von `m_jointype` und `m_endtype` liegen in
`deps_src/clipper/clipper.cpp:3445-3682` innerhalb von
`ClipperOffset::DoOffset` auf `m_polyNodes.Childs[i]`. Diese
`m_polyNodes` sind ClipperOffset-interne Child-Knoten, die ueber
`ClipperOffset::AddPath()` angelegt werden (clipper.cpp:3376-3377
`newNode->m_jointype = joinType; newNode->m_endtype = endType;`
mit expliziten Argumenten). Jeder `co.AddPath()`-Aufruf in Orca
(z. B. `ClipperUtils.cpp:283, 449, 470`) uebergibt beide
Enum-Werte explizit.

**Die PolyNodes aus `Clipper::BuildResult2` werden nie an
`ClipperOffset` weitergereicht** — sie sind Ergebnis-Konturen aus
Boolean-Operationen (Intersection/Union/Diff) und werden vom
Caller nur ausgelesen (`Contour`-Punkte), nicht weiter offsettet.
Die uninit m_jointype/m_endtype dieser PolyNodes werden also in
normalen Code-Pfaden nie konsumiert; Valgrind sieht sie nur beim
`tbbmalloc::scalable_free` zum Destruct-Zeitpunkt.

**Daraus abgeleitete Default-Werte** (nicht gewaehlt um x86 zu
treffen):
- `m_endtype = etClosedPolygon`: BuildResult2 produziert
  geschlossene Konturen; `etClosedPolygon` ist die einzige
  Semantik, die zum Objekt passt. Enum-Index 0.
- `m_jointype = jtSquare`: Konservativer Default (keine
  Rundungen, keine Miter-Spitzen). Enum-Index 0.

Beide happen to be Enum-Wert 0 — zufaellig entspricht das dem
Verhalten von `-ftrivial-auto-var-init=zero`.

### 2. Herkunft (git blame + Fremdvergleich)

- `clipper.hpp:147` git blame: `fe4a72ec94` (Noisyfox, 2025-06-18,
  „Upgrade clipper & improve multi-thread performance"). Dieser
  Commit cherry-picked PrusaSlicer-Clipper-Optimierungen. Der
  Ctor wurde dabei zu `: Parent(0), Index(0), m_IsOpen(false) {}`
  kompaktiert (vorher stand `Childs()` extra im Init-Listen,
  Entfernung hat keine Semantik geaendert). **Die fehlende
  Initialisierung von m_jointype/m_endtype war schon in der
  pre-image-Version drin** (`src/clipper/clipper.hpp` am
  `1555904bef`, Lane Wei, 2022-07-15, initialer BBS/Orca-Import).
- **PrusaSlicer master** (`prusa3d/PrusaSlicer`,
  `bundled_deps/clipper/include/clipper/clipper.hpp`, seit
  Commit `13f39e853f` 2025-03-25 „Move clipper to bundled deps"):
  gleiche Ctor-Zeile `: Parent(0), Index(0), m_IsOpen(false) {}` —
  **gleicher Bug**.
- **Original Clipper 6 (Angus Johnson)** auf SourceForge
  (`polyclipping/code/HEAD/trunk/cpp/clipper.cpp`): Impl
  `PolyNode::PolyNode(): Parent(0), Index(0), m_IsOpen(false) {}` —
  **gleicher Bug im Upstream**.

→ Der Bug stammt aus dem Original-Clipper 6; weder Prusa noch
Orca haben ihn eingefuehrt. Prusa und Orca schleppen ihn mit.
Patches, die beide Felder initialisieren, muessten eigentlich
nach Angus Johnson zurueckfliessen.

### 3. Fix im Experimental-Build

Patch auf `experiment/arm64-divergence`, Commit `9aaa5ee5ee`:
```
PolyNode() : Parent(0), Index(0), m_IsOpen(false),
             m_jointype(jtSquare), m_endtype(etClosedPolygon) {}
```

Binaries: `handslice-cli-x86-count-fix`, `handslice-cli-arm64-count-fix`.
Submodule bleibt im Hauptrepo auf Upstream-Pin
`8500fcdcca` (Experiment-Branch nur im Submodul-Worktree).

**Messungen Auryn (count-fix-Binaries):**

| Variante                | fill_paths               | fill_length_u                    | filament_mm   | gcode_sha           |
|-------------------------|--------------------------|----------------------------------|--------------:|---------------------|
| x86 (vor Fix)           | 229200                   | 190744245585                     | 39223.58      | diverse (depends auf run) |
| x86 (nach Fix, 1 Lauf)  | **229200** (unveraendert) | **190744245585** (unveraendert) | 39223.58      | 99121a82… (geaendert in Byte-Reihung) |
| arm64 (vor Fix, 5 Laeufe) | 5 Werte 212194…230212   | 5 Werte                          | 38907…39225   | 5 distinct          |
| arm64 (nach Fix, 10 Laeufe) | 6× **230212**, je 1× 230004/230000/229955/229954 | identisch pro paths | 39220.35…39224.94 | 10 distinct |

- **Range vor Fix:** paths-Delta 18 018 → **nach Fix:** 258 (×70
  schrumpf).
- **Dominanter Wert nach Fix:** 230212 (6/10) — identisch zum
  `-ftrivial-auto-var-init=zero`-Ergebnis vom Vortag (konsistent,
  da unser Fix beide Felder auf Enum-Wert 0 setzt).
- **x86 ↔ arm64 nach Fix: NICHT gleich.** x86 bleibt bei 229200
  (fix aendert dort nichts, weil x86's Fill-walker die uninit
  Felder sowieso nicht in einem relevanten Pfad liest). arm64
  springt in 60 % der Laeufe auf 230212 und in 40 % auf etwas
  anderes.
- **Referenztest Wuerfel mit `handslice-cli-x86-count-fix`:**
  EXECUTABLE_BLOCK SHA = `92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d`
  — **IDENTISCH** zur Referenz. Der Fix aendert den Cube-Slice
  nicht (Memcheck-stille Enum-Werte in BuildResult2 wirken sich
  bei dieser Geometrie nicht aus).

**Delta alt→neu (Auryn, solidInfill):**
- Pre-Fix „hoch" Variante (230212): ~239 solidInfill-paths pro
  typischer Flaeche, wie zuvor berichtet.
- Pre-Fix „niedrig" Variante (212194): ~18 000 fehlende Pfade,
  Material-Delta −316 mm.
- Post-Fix: 60 % der arm64-Laeufe hoch (230212, 0 Pfade Delta),
  40 % mittlere Zwischenwerte (229954…230004, Delta −8…−258
  Pfade). **Keine Low-Variante mehr beobachtet**; die 1 g
  Material-Defizit ist verschwunden; Rest-Varianz ist 1 Pfad pro
  mehreren Hundert.

**Vorlaeufige Interpretation:** Der PolyNode-Fix beseitigt den
primaeren Memcheck-Fund, aber die arm64-Fill-Varianz ist nicht
komplett behoben → es existiert mindestens eine weitere
uninit-Quelle. Kandidat: siehe Punkt 4.

### 4. FillConcentricInternal.cpp:13 — Variable identifiziert

`FillConcentricInternal::fill_surface_extrusion` (Zeile 12-13 ist
die Funktionssignatur, Ctor-Default-Werte wirken ab Z. 14) legt
auf Z. 29 ein lokales Objekt an:
```
Arachne::WallToolPathsParams input_params;
```
Z. 30-35 setzen 6 Felder:
`min_bead_width, min_feature_size, wall_transition_length,
wall_transition_angle, wall_transition_filter_deviation,
wall_distribution_count`.

**Nicht gesetzt:**
- `float min_length_factor` (`WallToolPaths.hpp:28`) — gelesen in
  `WallToolPaths.cpp:693`:
  `shorterThan(line, m_params.is_top_or_bottom_layer ?
    (min_width / 2) : (min_width * m_params.min_length_factor))`.
  → direkt in einer Schwellenwert-Berechnung in
  `removeSmallLines()`; aendert welche Linien entfernt werden.
- `bool is_top_or_bottom_layer` (`WallToolPaths.hpp:33`) —
  gelesen an gleicher Stelle als Branch-Flag.

Die kanonische Fabrik `make_paths_params()` (`WallToolPaths.cpp:
34-56`) setzt beide Felder korrekt. `FillConcentricInternal.cpp`
umgeht sie und vergisst diese zwei. Das ist eine echte, direkte
Fill-Pfad-uninit-Lese; Valgrind-Fund entsprechend (1 Hit pro
Slice, Site `WallToolPaths.cpp:693` + ein weiterer Hit an
`:677` mit Origin ebenfalls auf
`FillConcentricInternal.cpp:13`).

Dies ist die wahrscheinliche zweite Quelle. Nicht gefixt in
dieser Session.

### 5. Stanford Bunny – reproduzierbar mit Fremdmodell

`Stanford_Bunny.drc` aus `resources/handy_models/` via Orca's
`draco_decoder` nach OBJ gewandelt, dann via Python-STL-Writer
auf 200 mm skaliert (Faktor 1.667) und XY-zentriert nach
`local-test/bunny_200mm.stl` (52716 Dreiecke, 200×153×197 mm,
nicht committet). Elegoo-CC2-Profil wie bei Auryn.

**Standard-arm64-Build (`handslice-cli-arm64`, kein Fix, keine
count-Instrumentierung) 5× Bunny:**

| Lauf    | filament_mm | gcode_sha        |
|---------|------------:|------------------|
| arm64-1 | 129021.05   | b69acbaa…        |
| arm64-2 | 129021.05   | 62a3b3b4…        |
| arm64-3 | 129021.05   | ae908d37…        |
| arm64-4 | **129017.77** | 77e4775e…      |
| arm64-5 | 129021.05   | b6f87443…        |

→ Varianz reproduziert: 4/5 gleiches Filament, 5 unterschiedliche
G-Code-SHAs (Reorder); 1/5 leicht abweichendes Filament
(−3.28 mm). Nicht Auryn-spezifisch.

**Valgrind Memcheck auf x86-debug + Bunny** (`handslice-cli-x86-
debug`, --threads 1, --track-origins=yes, --expensive-definedness-
checks=yes, nach ~10 min CPU abgebrochen):
- 221 „Conditional jump" errors.
- **217/221 Origin: `BuildResult2 clipper.cpp:2802` stack**
  (= gleiche Hauptquelle wie bei Auryn).
- 1 Origin: ClipperLib_Z `BuildResult2` (Z-Koordinaten-Variante
  des Clippers, gleicher Fehler mit anderem Namespace-Prefix).
- 1 Origin: `FillConcentricInternal::fill_surface_extrusion
  (FillConcentricInternal.cpp:13)` → Site `WallToolPaths.cpp:693`.
- 1 Origin: wie oben → Site `WallToolPaths.cpp:677`.
- 1 Origin: `ModelObject::add_volume (Model.cpp:1256)` heap,
  Site `ModelVolume::get_extruders (Model.cpp:2544)` — nicht
  Fill-Pfad.

→ Bug ist **modellunabhaengig** reproduzierbar. Clipper-Fund
dominant (97 % der Hits), gleiche sekundaere Fill-Pfad-Fund in
Arachne.

### 6. CLAUDE.md-Regel + Rebase

CLAUDE.md Abschnitt 5 um Co-Authored-By-Trailer-Regel ergaenzt
(ab 2026-11-02 Pflicht). Ungepushte Hauptrepo-Commits
`origin/main..HEAD` werden mit
`git rebase origin/main --exec '... --trailer ...'` nachtraeglich
versehen (Autor + Inhalt unveraendert, keine Force-Pushes,
gepushte Commits nicht angefasst). Submodule-Experiment-Commits
sind untouched (Submodul-Branch ist privat).

**Reference-Test gruen, Scrub sauber. Hauptrepo-Submodule-Ref
weiter auf Upstream `8500fcdcca`. Keine Pushes. Clang-Build
weiterhin im Blocker #3.**

---

## 2026-11-02 21:00 UTC – Divergenz Stufe 3c Follow-up: Ursache bewiesen (uninit stack var im Clipper), Ort gefunden (PolyNode-Default-Ctor)

Zweistufiger Nachweis per Klaus' Methode: `-ftrivial-auto-var-init`-
Beweis am Poco + Valgrind-Memcheck am AMR5.

### 1. Beweis am Poco: Varianz verschwindet, pattern vs zero geben verschiedene stabile Ergebnisse

Zwei arm64-CLI-Builds mit identischer Codebase (experiment/arm64-
divergence) + HANDSLICE_COUNT_SPLIT_SOLID + jeweils einem
Clang-Init-Flag:
- `handslice-cli-arm64-count-pattern` (`-ftrivial-auto-var-init=pattern`)
- `handslice-cli-arm64-count-zero`    (`-ftrivial-auto-var-init=zero`)

Je 5 Auryn-Slices auf Poco X3 Pro, OHNE HS_DUMP_LAYER-env:

**pattern (0xAA-fill):**

| run | fill_paths | fill_length_u | filament | SHA  |
|-----|-----------:|--------------:|---------:|------|
| 1-5 | **229171** (×5) | **190744327881** (×5) | n/a† | n/a† |

**zero (0-fill):**

| run | fill_paths | fill_length_u | filament   | SHA (gcode) |
|-----|-----------:|--------------:|-----------:|-------------|
| 1-5 | **230212** (×5) | **190781238177** (×5) | **39224.94** mm (×5) | 5 distinct SHAs |

† Pattern-Builds crashen beim Custom-GCode-Writer (Elegoo-Template
referenziert ein Vektor-Element, das durch 0xAA-Pattern als
"garbage pointer" angesehen wird — latenter Null-Deref im GCode-
Writer, nicht Teil der Fill-Walker-Frage). Die HS_FILL_OUT-Counter
werden VOR dem Writer emittiert, daher komplett.

**Vergleich zur Varianz ohne Init-Flag (Stufe 3b-Daten):**
Default-arm64-Build: fill_paths **212194-230212** (5 verschiedene
Werte), filament 38907-39225 mm, 1257/13441 nichtdeterministische
Oberflaechen.

→ **Varianz verschwindet unter beiden Init-Modi.** Pattern (229171)
und zero (230212) liefern **verschiedene aber je stabile Ergebnisse**
→ „nicht initialisierte Stack-Variable" ist bewiesen.

**x86-Vergleich (Klaus-Frage):**

| Build        | fill_paths | fill_length_u | Δ zu x86 (paths) | Δ zu x86 (length_u) |
|--------------|-----------:|--------------:|-----------------:|--------------------:|
| x86 (default GCC) | 229200 | 190744245585 | 0                | 0                   |
| arm64 **pattern** | 229171 | 190744327881 | **−29**          | **+82 296** (0.00004 %) |
| arm64 zero        | 230212 | 190781238177 | +1012            | +36 992 592 (0.019 %) |

**→ Der x86-Standard-Build entspricht praktisch exakt dem
pattern-Verhalten** (0xAA-fill). Zero liegt deutlich ab.
Interpretation (Vermutung, nicht belegt): die kritische uninit
Stack-Var auf x86 bekommt durch GCC's Stack-Reuse-Pattern
konsistent "garbage-aehnliche" Bits, die statistisch dem 0xAA-
Pattern aehnlicher sind als 0.

### 2. Ort finden am AMR5: Valgrind Memcheck

Neuer Build `handslice-cli-x86-debug` (GCC Release + `-g
-fno-omit-frame-pointer`), Submodule auf Orca-Upstream (keine
HANDSLICE_COUNT_SPLIT_SOLID-Patches). Lauf:
`valgrind --tool=memcheck --track-origins=yes
--expensive-definedness-checks=yes --num-callers=20
--log-file=/tmp/stufe-3c-valgrind/memcheck.log --threads 1 ...
auryn.stl`.

Nach ca. 36 min CPU-Zeit im `print.infill()`-Phase abgebrochen
(Slice war noch nicht komplett, aber alle neu auftretenden
Fehler kamen aus derselben Origin — weitere Laufzeit haette
nur Haeufigkeiten erhoeht, keine neuen Fundstellen gezeigt).

**Zusammenfassung (`stufe-3c-valgrind/parsed-summary.txt`):**

- Total Memcheck-Meldungen: **368 "Conditional jump", 0 "Use of
  uninit value"**
- Alle 368 wurden an einer TBB-/libc-Site gemeldet (deshalb
  waren alle unter „Other project" klassifiziert — mein Parser
  schaut auf die SITE, Klaus-Regel sagt TBB nur zaehlen).
- Nach ORIGIN klassifiziert, nur im Fill-Pfad / Clipper / Boost
  Polygon:

**Fund 1 (dominant, 365 von 368 Meldungen):**
- Site (immer): `tbbmalloc frontend.cpp:2504` (TBB-malloc
  `scalable_free`, aufgerufen beim Destruct von
  `Polyline3`/`ExtrusionPath` nach dem Slice)
- Origin: **stack:
  `Slic3r::ClipperLib::Clipper::BuildResult2(PolyTree&)` an
  `engine/OrcaSlicer/deps_src/clipper/clipper.cpp:2802`**
- Verursacher: Default-Ctor `PolyNode()` an
  `deps_src/clipper/clipper.hpp:147`:
  ```
  PolyNode() : Parent(0), Index(0), m_IsOpen(false) {}
  ```
  Die privaten Member `JoinType m_jointype` und `EndType
  m_endtype` (Z. 160-161) werden **nicht initialisiert**. In
  `BuildResult2` (Z. 2824) werden PolyNode-Objekte mit
  `polytree.AllNodes.emplace_back(PolyNode())` angelegt — die
  uninit Enum-Werte landen im Heap-Objekt und ueberleben bis
  zum Destruct.

**Fund 2 (1 Meldung):**
- Site: `src/libslic3r/Arachne/WallToolPaths.cpp:693`
- Origin: **stack:
  `Slic3r::FillConcentricInternal::fill_surface_extrusion` an
  `src/libslic3r/Fill/FillConcentricInternal.cpp:13`**
- Direkt in der Fill-Pipeline. Betrifft den
  `ipConcentricInternal`-Pattern-Pfad (narrow-infill-Fallback,
  Stufe 3b Hypothese A trotz Default-Pattern `ipMonotonic`).

**Fund 3 (1 Meldung):**
- Site: `src/libslic3r/Arachne/WallToolPaths.cpp:677` (template
  `shorterThan<ExtrusionLine>`)
- Origin: **stack:
  `boost::polygon::construct_voronoi` an `voronoi.hpp:117`**
- Boost-Polygon-interne Voronoi-Konstruktion. Fremde Lib —
  wird in Arachne fuer das Skeleton gebraucht.

**Fund 4 (1 Meldung, nicht Fill-Pfad):**
- Site: `src/libslic3r/Model.cpp:2544`
  (`ModelVolume::get_extruders() const`)
- Origin: **heap:
  `ModelObject::add_volume (Model.cpp:1256)`**
- Betrifft Model-Loading, nicht die Slice-Pfad-Divergenz.

**Zaehlung Fremdbibliothek-Meldungen (keine Details):** TBB-
malloc 365, Boost-Polygon 1. Alle anderen libstdc++/libc/TBB-
Core-Meldungen wurden vom Parser als "ext" ausgefiltert (keine
project-Frame im Call-Stack).

### 3. Zusammenfassung

- **Ursache belegt:** uninit Stack-Variable (`-ftrivial-auto-
  var-init` Beweis am Poco).
- **Ort gefunden:**
  - **Primaer:** `deps_src/clipper/clipper.hpp:147`
    `PolyNode::PolyNode()` initialisiert `m_jointype`
    (`clipper.hpp:160`) und `m_endtype` (`clipper.hpp:161`)
    nicht. In `deps_src/clipper/clipper.cpp:2824`
    (`BuildResult2`) werden solche PolyNode-Objekte in den
    PolyTree gepackt und ueberleben als Heap-Daten den
    Slice-Lauf.
  - **Sekundaer:** `src/libslic3r/Fill/FillConcentricInternal.cpp:13`
    (eine Stack-Variable in `fill_surface_extrusion`, nicht
    weiter lokalisiert) sowie Boost-Polygon's
    `voronoi.hpp:117`.
- **Entspricht x86-Verhalten:** Pattern (229171) ≈ x86 (229200).
- **Fix (nicht umgesetzt):** PolyNode-Ctor explizit
  initialisieren, z. B.
  ```
  PolyNode() : Parent(0), Index(0), m_IsOpen(false),
               m_jointype(jtSquare), m_endtype(etClosedPolygon) {}
  ```
  Patch im Upstream-Clipper (Angus Johnson), nicht in Orca-
  Code. Warte Klaus' Entscheidung ab.

**Reference-Test gruen, Scrub sauber, Standard-Build
unveraendert. Submodule-Branch `experiment/arm64-divergence`
enthaelt nur die count-Patches; Hauptrepo weiter auf
Upstream-Pin `8500fcdcca`. Keine Pushes. Clang-Build bleibt
im Blocker #3.**

---

## 2026-11-02 10:40 UTC – Divergenz Stufe 3c: Heisenbug — Observierung macht Walker lokal deterministisch

**Instrumentierung erweitert** um:
- `HS_WALKER_STATE` dump am Target-Surface: Bit-exakte Hex-Darstellung
  aller FP-Felder von `f` (z, spacing, overlap, angle, bbox) und
  `params` (density, flow.width/height/nozzle_diameter, anchor_length,
  resolution).
- `HS_ISOLATE_ITERS=N` env: N In-Process-Wiederholungen von
  `fill_surface_extrusion` am Target, Fresh-Scratch, Count pro Iter.

**Messung 1 — In-Process 20× auf arm64 (`HS_ISOLATE_ITERS=20`):**
Target layer=424 surf=10 liefert 20/20 identische Ergebnisse:
`paths=59, length_u=14 264 060`. **Fill-Walker ist within-process
deterministisch** gegeben identischer f-State.

**Messung 2 — Cross-Process 20× auf arm64 mit HS_DUMP_LAYER=424
HS_DUMP_SURF=10 (ohne HS_ISOLATE_ITERS):**
Alle 20 Prozesse: Target `paths=58, length_u=14 234 826`, UND die
`HS_WALKER_STATE`-Zeile ist bit-identisch (alle FP-Bitmuster gleich).
Target ist cross-process deterministisch.
Die *Full-Slice* `surf-fill-trace`-SHA zerfaellt in 10 Varianten
ueber die 20 Laeufe — die Nichtdeterminismus-Zahl der Oberflaechen
ist aber von 1257 (Stufe 3b) auf **13/13441 (0.1 %)** gefallen.
Keine der 13 ist unser Target.

**Messung 3 — Cross-Process 5× auf arm64 ohne HS_DUMP_LAYER env:**
Zurueck zur vollen Varianz. 5 Laeufe, 4 verschiedene `fill_paths`-
Werte (230212 x3, 212194, 230000), Filament 38907-39225 mm.
Die Pfadgenerierung ist wieder voll nichtdeterministisch.

**Fazit:** Reines Beobachten des Walker-State am Target (ein Lock +
`ostringstream::str()` + Mutex-geschuetztes `push_back`) **stabilisiert
sowohl das Target als auch die meisten anderen Flaechen**. Klassischer
Heisenbug. Zwei moegliche Ursachen (nicht geklaert):

1. **UB / unitialized memory read**: Observe-Lock aendert
   Memory-Layout vor dem Walker-Call so, dass nicht initialisierte
   Reads deterministische Werte sehen. Klaus-Vermutung.
2. **Data race**: Shared mutable state (static Variable, allocator
   state, cache contention) wird durch das Lock serialisiert.

**Vermutung (nicht belegt):** Hypothese 1 ist wahrscheinlicher, weil
within-process bereits deterministisch ist, und zwischen Prozessen
der Unterschied oft Memory-Mapping / ASLR / Allocator-Seeds ist, nicht
Scheduling. Thread-Scheduling-Race wuerde innerhalb des Prozesses
auch variieren.

**Nicht umgesetzt:** ASAN+UBSan x86-Build (Klaus-Punkt 3). Hoechste
Prioritaet fuer naechste Session, da UB-Verdacht am klarsten durch
UBSan/ASAN belegt wird. Build-Script-Entwurf steht; braucht
`-fsanitize=address,undefined` auf libslic3r + CLI (deps bleiben wie
sie sind).

**Zweite Nichtdeterminismus-Quelle (downstream fill walker)** aus
Stufe 3b: nicht weiter untersucht in dieser Session.

**Clang-Build weiterhin im Blocker #3.** Keine Pushes. Scrub sauber.
Reference-Test gruen.

**Zahlen-Zusammenfassung:**

| run                               | target paths | walker state identisch? | Note                       |
|-----------------------------------|--------------|-------------------------|----------------------------|
| x86-1 (lokal, 20× in-process)     | 59 → wird jetzt 58 | n/a            | Baseline-Shift durch Patch |
| arm64 20× in-process              | 59 (×20)     | n/a                     | Deterministisch within     |
| arm64 20× cross-process w/ DUMP   | 58 (×20)     | **ja (×20)**            | Heisenbug stabilisiert     |
| arm64 5× cross-process ohne DUMP  | 59, 11, …    | n/a                     | Volle Varianz zurueck      |

---

## 2026-11-02 04:00 UTC – Divergenz Stufe 3b abgeschlossen: Fill-Walker-Nichtdeterminismus bei bit-identischem Input

Der Zaehler wurde um per-Layer- und per-Fläche-Trace erweitert, dazu ein
gezielter Detail-Dump (Env `HS_DUMP_LAYER` / `HS_DUMP_SURF`) der Input-
Polygon-Vertizes und der generierten Extrusions-Pfade pro Zielfläche.

**Per-Layer-Diff hoch vs niedrig (arm64-1 39225 mm vs arm64-5 38908 mm):**
- 657/1037 Layers divergent (63 %, konsistent mit Stufe-1 Beobachtung).
- `surfs` (Zahl der SurfaceFills pro Layer) stimmt bei JEDEM Layer
  ueberein — die Flaechen-Zaehlung ist stabil.
- `paths` und `length_u` variieren. Niedrig produziert durchgehend
  WENIGER Pfade.

**Zwischenruns-Diff bei gleichem Filament (arm64-1 vs arm64-3, beide
39224.94 mm): 0/1037 Layers divergent im Fill-Walker-Trace** — Fill-
Walker produziert byte-identisch, aber die G-Code-SHAs sind trotzdem
verschieden. Die zweite Nichtdeterminismus-Quelle liegt also
nachweislich **downstream** der Pfadgenerierung.

**Per-Fläche-Diff (13441 Flaechen, arm64 niedrig vs hoch):**
- `expoly_v` + `bbox` fuer ALLE 13441 Oberflaechen byte-identisch
  zwischen niedrig und hoch.
- 1257 Flaechen (9.4 %) haben ungleichen Output (paths, length_u).

**Top-Fund — Detail-Dump layer=424 surf=10:**
- Input (`contour_v=249`, keine Loecher): die 249 Vertex-Koordinaten
  sind byte-identisch zwischen hoch (arm64-dump-1, 39224.94 mm) und
  niedrig (arm64-dump-2, 38907.92 mm). `diff` auf den
  `HS_DETAIL_IN`-Zeilen liefert exit=0.
- Output hoch: 59 Pfade, jeweils v=2 (Scan-Linie), Σ length_u = 14 264 062
- Output niedrig: 11 Pfade, jeweils v=2, Σ length_u = 4 320 369 (≈30 %)
- Niedrige Variante produziert *weniger und laengere* Scan-Linien
  mit geringerer Gesamtlaenge → tatsaechlich weniger Fuellung,
  nicht nur Umsortierung.

**Fazit zur Pfadgenerierung:** Die FillMonotonic-/FillRectilinear-
Pipeline (Default-Pattern des Elegoo-CC2-Profils ist `ipMonotonic`)
produziert bei bit-identischem Input-Polygon unterschiedlichen Output
auf arm64. Da der Input-Polygon identisch ist, muss die Nichtdeterminismus
*innerhalb* `fill_surface_extrusion` entstehen — nach dem Punkt, wo wir
den Polygon dumpen (surface_fill.surface.expolygon), aber vor dem Ende
des Aufrufs. Kandidaten:
- `polygons_rotate(filled_area, aligning_angle)` – rotiert Polygon
  per sin/cos; FMA-abhaengig.
- `AABBTreeLines::LinesDistancer<Line>` – AABB-Reihenfolge haengt von
  Line-Eingangssortierung.
- `std::sort(sil.intersections.begin(), sil.intersections.end())`
  (FillRectilinear.cpp:852) – coord_t, keine FP-Ties, aber Eingabe
  stammt aus FP-Rechnung.
- Clipper-/`offset_ex`-Aufrufe mit `scaled_spacing * 0.3` /
  `scaled_spacing * 0.5` – FP-abhaengige Verkleinerung.

**Zweite Quelle (downstream fill-walker):** arm64-Laeufe mit
*identischem* Fill-Walker-Output (gleiche Layer-/Flaechen-Spur)
produzieren verschiedene G-Code-SHAs. Also exsitiert nicht-determinismus
auch in: ExtrusionEntityCollection-Sortierung, chain_lines/
chain_polylines, Seam-Placer, oder GCode-Writer-Interne Scheduling.

**Belegstellen (alle auf `experiment/arm64-divergence` im Submodul):**
- Fill.cpp:48-150 – Zaehler, Mutex-geschuetzte Traces, Env-Dump
- Fill.cpp:~1407-1570 – Instrumentierung in `Layer::make_fills()`
- `engine/cli/handslice-cli.cpp` – stderr-Dump + 3 Trace-Dateien
  (layer-fill-trace, surf-fill-trace, detail-dump)

**Mess-Serie (zweite Serie mit per-Fläche-Trace):**

| run     | filament mm | fill_paths | Variante |
|---------|-------------|------------|----------|
| x86-1   | 39223.58    | 229200     | ref      |
| arm64-1 | 38969.94    | 216129     | niedrig  |
| arm64-2 | 39224.94    | 230212     | hoch     |
| arm64-3 | 39220.99    | 230000     | nahe-hoch|
| arm64-4 | 39224.94    | 230212     | hoch     |
| arm64-5 | 39185.01    | 227895     | niedrig-ish |

**Reference-Test gruen. Scrub sauber. Keine Pushes.**

---

## 2026-11-02 02:55 UTC – Divergenz Stufe 3b: Pfadgenerierung ist der Fundort (Hypothese bestaetigt)

Setup wie bisher. Branch-Hygiene nach Klaus-Vorgabe: die zwei bisherigen
Submodule-Experiment-Commits auf `experiment/arm64-divergence` im Submodul
gerettet, Hauptrepo-Submodul-Ref zurueck auf Orca-Upstream
`8500fcdcca` (Commit `58744f7`). Fuer -count-Builds vor dem Lauf
`git -C engine/OrcaSlicer checkout experiment/arm64-divergence`, vor
Ref-Test `git checkout 8500fcdcca`.

**Neuer Zaehler** direkt um die Pfadgenerierung
(`Layer::make_fills()`, Fill.cpp:1467 `f->fill_surface_extrusion(...)`):
Nur fuer internal solid non-bridge Surfaces. Pre/Post-Zaehlung der
`fills.entities`:
- `fill_surfaces` : Zahl der instrumentierten SurfaceFills
- `fill_entries`  : Top-Level-Entities angehaengt
- `fill_paths`    : Rekursiver Blatt-Count von ExtrusionPath
- `fill_length_u` : Summe `e->length()` in scaled coord units
- `count_hash`    : XOR (layer_id<<20) ^ fill_paths pro Surface
- `length_hash`   : XOR (layer_id<<20) ^ (length_u * golden-ratio) pro Surface

**Mess-Serie:**

| run     | gcode sha  | filament mm | fill_surfs | fill_paths | fill_length_u | cnt_hash   | len_hash                |
|---------|------------|-------------|------------|------------|---------------|------------|-------------------------|
| x86-1   | cf92bc00…  | 39223.58    | 13445      | 229200     | 190744245585  | 0x5c800160 | 0x625886d09bdc4137      |
| arm64-1 | 68eaf00a…  | 39224.93    | 13441      | **230208** | 190781166320  | 0x64c001a2 | 0xf24c0422ae07e68       |
| arm64-2 | 6aebe2a1…  | 39224.94    | 13441      | **230212** | 190781238177  | 0x64c001a6 | 0x1eaadcc7a0d738f3      |
| arm64-3 | b1f6a7b8…  | 39224.94    | 13441      | **230212** | 190781238177  | 0x64c001a6 | 0x1eaadcc7a0d738f3      |
| arm64-4 | 4f0dc774…  | 39220.99    | 13441      | **230000** | 190660377715  | 0x64c00128 | 0x2dbe4a014fcb7c9f      |
| arm64-5 | c683864f…  | 39220.45    | 13441      | **229959** | 190646387033  | 0x64c001d9 | 0x2a93491e4423b5cd      |

**Zwei saubere Befunde:**

1. **Primaerquelle: der Fill-Walker ist auf arm64 nichtdeterministisch.**
   5 arm64-Laeufe haben identischen `fill_surfs=13441` (also die
   Anzahl der *bearbeiteten* SurfaceFills ist stabil) aber vier
   verschiedene `fill_paths`-Werte (229959-230212) und drei
   verschiedene `fill_length_u`-Werte. Hoeheres Filament korreliert
   streng mit mehr `fill_paths`/`length_u`. Delta Hoch-Tief:
   ~250 fehlende Pfade = ~130 Mio scaled units Pfadlaenge
   = ca. 130 mm Pfadlaenge (ex-Flow ≈ 4-5 mm Filament,
   konsistent mit beobachteten 4.5 mm Filament-Delta).
2. **Zweite Quelle existiert, downstream der Pfadgenerierung.**
   arm64-2 und arm64-3 haben *identischen* Fill-Output (gleiche
   Counts, gleiche Hashes), aber unterschiedliche G-Code-SHAs
   `6aebe2a1…` vs `b1f6a7b8…`. Also: Fill-Walker produziert dieselbe
   Pfadsammlung, aber Downstream (chain_lines / Perimeter-Interleaving
   / GCode-Writer / Seam-Placer) produziert sie in anderer
   Reihenfolge.

**x86 vs arm64:** x86 generiert *weniger* Pfade (229200) als arm64 selbst
in seinem "niedrigsten" Lauf (229959 bei arm64-5), aber die
Pfad-*Laenge*-Summen sind nahe (x86 190744M vs arm64 190646-190781M).
Also: arm64 teilt dieselbe Flaeche in mehr kurze Pfade; x86 fasst mehr
zu laengeren Pfaden zusammen. Konsistent mit einer FP-Toleranz
Unterschied in `chain_lines`/path-splitting.

**Naechster Schritt (Klaus-Plan):** innerhalb der Pfadgenerierung
weiter eingrenzen — vor/nach den intermediate steps der
FillMonotonic/FillRectilinear-Pipeline (intersections sort,
Monotonic-region building, path chaining). Plus Detail-Dump einer
betroffenen Flaeche fuer hoch/niedrig nebeneinander.

**Branch-Status Submodul:**
- `main` (= Hauptrepo-Ref): `8500fcdcca` (upstream unveraendert)
- `experiment/arm64-divergence`: enthaelt Stufe-A/B/C-Zaehler
  (ea8057f908) + Stufe-3b-Zaehler (neu, folgt dieses Commit)

**Referenztest gruen,** Scrub sauber.

---

## 2026-11-02 02:05 UTC – Divergenz Stufe B+C: Dedup und mixed-Geometrie ebenfalls deterministisch (alles vor der Fuellung ist OK)

Nach dem klaren Nein auf Hypothese A: zwei weitere Zaehler-Serien
mit demselben Setup (Auryn, x86 1× + Poco 5×, `-count`-Binaries,
`-DHANDSLICE_COUNT_SPLIT_SOLID`).

**Hypothese B** (SurfaceFillParams-std::set FP-Tie, Fill.cpp:833):
Zaehler `surfaces_seen` und `unique_params` am Ende der Set-Belegung
(Fill.cpp:1053) + Per-Layer `size_hash`.
→ Alle 5 arm64-Laeufe: `surfaces_seen=21993, unique_params=3567,
size_hash=0x1640003` identisch. **Falsifiziert.**

**Hypothese C** (modifiziert — Geometrie *inside* mixed-Outcomes):
Fuer jedes mixed-Resultat Vertex-Anzahlen von `normal_infill` und
`narrow_infill` zusammenzaehlen, plus Geom-Hash aus den ersten
Konturpunkt-Koordinaten der entstehenden Expolygone (Fill.cpp:1225-1250).
→ Alle 5 arm64-Laeufe: `normal_vcount=29444, narrow_vcount=324653,
geom_hash=0xfffa237886c543b6` identisch. **Falsifiziert.**

**Mess-Serie (5 Laeufe hat beide Varianten erwischt):**

| run     | sha                 | fil mm   | norm_v | narr_v | geom_hash              |
|---------|---------------------|----------|--------|--------|-----------------------|
| x86-1   | 5ff18b24…           | 39223.58 | 29441  | 324668 | 0xffbfcbfbceb530a2    |
| arm64-1 | 8445b27e…           | 39224.94 | 29444  | 324653 | 0xfffa237886c543b6    |
| arm64-2 | 057a447a…           | 38907.52 | 29444  | 324653 | 0xfffa237886c543b6    |
| arm64-3 | e4bc484f…           | 38908.62 | 29444  | 324653 | 0xfffa237886c543b6    |
| arm64-4 | 567020d1…           | 39220.36 | 29444  | 324653 | 0xfffa237886c543b6    |
| arm64-5 | e3dfb0bc…           | 38907.30 | 29444  | 324653 | 0xfffa237886c543b6    |

**Entscheidender Punkt:** Die 5 arm64-Laeufe decken beide Varianten ab
(hoch ~39220/39225 mm, niedrig ~38907 mm — passt zur Stufe-1-Variante
`8a50e806`), und **alle 5 haben identische Zaehler in jedem Feld**.

**Schlussfolgerung:** Der arm64-Nichtdeterminismus liegt vollstaendig
*downstream* der Flaechen-Klassifikation. `make_fills() → group_fills()
→ split_solid_surface()` liefert auf arm64 bit-identische Entscheidungen
UND bit-identische Polygon-Geometrien zwischen 5 Laeufen. Die Divergenz
muss nach diesem Punkt entstehen:

1. **FillBase/FillMonotonic/FillRectilinear Pfadgeneration** –
   verwandelt die Expolygone in Extrusions-Linien. Nichtdeterminismus
   koennte dort entstehen (siehe Stufe-3-Katalog, Fill/FillBase.cpp:1455,
   1700, 2493, 2633, Fill/FillRectilinear.cpp:852, 2092-2093).
2. **ShortestPath / chain_points / chain_polylines** –
   Polyline-Chaining mit Tolleranz-Vergleichen.
3. **PerimeterGenerator / Arachne**-Reihenfolge (Stufe-3-Hypothese D).
4. **ExtrusionEntityCollection::sort** oder GCode-Writer-Interne
   Sort-Operationen.
5. **bridge_over_infill** (Stufe-3 originale Hypothese C,
   PrintObject.cpp:3131/3143).

Zwei Beobachtungen stuetzen Variante 1 oder 2:
- arm64-1 und arm64-4 haben nah beieinanderliegende Filament-Werte
  (39224/39220) aber unterschiedliche G-Codes → Reihenfolge-Diff.
- arm64-2/3/5 haben untereinander variierende Filament-Werte
  (38907.52 / 38908.62 / 38907.30) → kleine Materialunterschiede,
  wahrscheinlich kleine Pfadlaengen-Unterschiede im Fuellmuster
  selbst.

Beides passt zu einer nicht-deterministischen Pfadgeneration, nicht
zu einer anderen Klassifikation.

**Nach CLAUDE.md Drei-Versuche-Regel:** Drei Hypothesen aus dem
Stufe-3-Katalog (A, B, C) sind nun je mit sauberer Instrumentierung
widerlegt. Haltemoment: nicht ins vierte Thema hineinraten, sondern
den Befund melden und auf Klaus warten. Default-Weiterarbeit ohne
Antwort: keine — Stufe D/E/F ohne Richtungswechsel waere spekulativ.

**Fuer Klaus:** Mein Vorschlag ist, als naechste gezielte Hypothese
die **FillMonotonic/FillRectilinear-Pfadgeneration** zu testen
(Fill/FillRectilinear.cpp:852 `std::sort(sil.intersections.begin(),
sil.intersections.end())` oder Fill/FillBase.cpp:1455 Edge-Grid-
Projektion mit sort auf `std::pair<..., size_t>`-Keys). Ein Zaehler-
Patch dort fiele kurz und zielsicher aus. Wenn du einen anderen Weg
bevorzugst (z.B. erst `chain_points` oder `bridge_over_infill`),
sag Bescheid.

---

## 2026-11-02 00:58 UTC – Divergenz Stufe A: Hypothese A falsifiziert (narrow/normal-Klassifikation ist nicht die Ursache)

Zaehler-Patch (gated by `-DHANDSLICE_COUNT_SPLIT_SOLID`) am Caller-Site
von `split_solid_surface` (Fill.cpp:1161) misst drei disjunkte
Outcomes pro SurfaceFill:
- `normal_only` : `narrow_infill.empty()` → keine Reklassifikation
- `full_narrow` : `normal_infill.empty()` → ganzer SurfaceFill wird `ipConcentricInternal`
- `mixed`       : beide non-empty → SurfaceFill wird in zwei gesplittet

Jedes Outcome bekommt einen Zaehler und einen XOR-Hash
`(layer_id << 20) ^ first_x`.

**Mess-Setup:** eigene `-count`-Binaries (`handslice-cli-x86-count`,
`handslice-cli-arm64-count`), Standard-CLI und Referenz-Test
unveraendert. Modell: `local-test/auryn.stl`, Elegoo CC2 0.4 +
0.20mm Standard + Elegoo PLA. x86 1 Lauf lokal, Poco X3 Pro 5 Laeufe
via Wireless ADB. Alle 6 Laeufe ohne `--threads`-Limit (default-TBB).

**Ergebnis (`/tmp/stufe-a/tally.tsv`):**

| run     | runtime | gcode sha      | normal_only | full_narrow | mixed | full_narrow_hash | mixed_hash   | filament     |
|---------|---------|----------------|-------------|-------------|-------|------------------|--------------|--------------|
| x86-1   | 21.9 s  | d22a4e93…      | 0           | 779         | 345   | 0xc0f8b5de       | 0x2922e197   | 39223.58 mm  |
| arm64-1 | 74.4 s  | cc7c68de…      | 0           | 779         | 345   | 0xc0c80fcc       | 0x293bda08   | 39224.94 mm  |
| arm64-2 | 76.6 s  | 98679918…      | 0           | 779         | 345   | 0xc0c80fcc       | 0x293bda08   | 39224.94 mm  |
| arm64-3 | 75.8 s  | 3b9ced0c…      | 0           | 779         | 345   | 0xc0c80fcc       | 0x293bda08   | 39157.78 mm  |
| arm64-4 | 78.3 s  | 6f2abcd5…      | 0           | 779         | 345   | 0xc0c80fcc       | 0x293bda08   | 39224.94 mm  |
| arm64-5 | 78.6 s  | e0c46b6a…      | 0           | 779         | 345   | 0xc0c80fcc       | 0x293bda08   | 39220.36 mm  |

**Vier Beobachtungen:**

1. **arm64-Zaehler ueber alle 5 Laeufe identisch** — gleiche Counts
   UND gleiche Hashes. Welche Inseln als narrow/mixed klassifiziert
   werden, ist auf arm64 vollstaendig deterministisch.
2. **gcode-SHAs trotzdem alle 5 verschieden** — Nichtdeterminismus
   besteht fort, aber **nicht** an diesem Entscheidungspunkt.
3. **arm64 vs x86: Counts identisch, Hashes verschieden** —
   Narrow/Normal-Entscheidungen stimmen in der Anzahl ueberein (779
   full_narrow, 345 mixed, 0 normal_only), aber x86 klassifiziert
   *andere* Inseln als narrow. Erklaert die Byte-Divergenz zwischen
   x86 und arm64 nur zum Teil (eine Dimension davon).
4. **Varianten unter den 5 Laeufen (Filament):**
   - 3× 39224.94 mm (hoch): arm64-1, -2, -4
   - 1× 39157.78 mm (niedrig, Delta −67 mm): arm64-3
   - 1× 39220.36 mm (= Stufe-1 „hoch"-Variante `e4f28cab…`): arm64-5
   - Die niedrige Variante aus Stufe 1 (`8a50e806…`, 38906.85 mm,
     −316 mm) ist in diesen 5 Laeufen *nicht* mehr aufgetaucht.

**Konsequenz:** Hypothese A ist **falsifiziert**. Weiter mit
Hypothese B (SurfaceFillParams-std::set FP-Tie, Fill.cpp:833).

**Belegstellen Patch:**
- `src/libslic3r/Fill/Fill.cpp:23-54` – atomic-Zaehler + Reset
- `src/libslic3r/Fill/Fill.cpp:1180-1230` – Instrumentierung am Caller-Site
  (`#ifdef HANDSLICE_COUNT_SPLIT_SOLID`-Block)
- `engine/cli/handslice-cli.cpp:60-73` – extern-Deklarationen
- `engine/cli/handslice-cli.cpp:1130-1152` – Reset + stderr-Dump

**Reference-Test gruen gehalten:** Standard-x86 nach jedem Rebuild
mit `bash engine/test/run-reference-test.sh` verifiziert, SHA
`92951c26…` bleibt stabil.

---

## 2026-11-01 23:45 UTC – Divergenz Stufe 3: libslic3r-Kandidaten fuer solidInfill-Divergenz

Aufgabe: in `src/libslic3r/` die Stellen finden, an denen (a) solidInfill-
Inseln klassifiziert werden, (b) Flaechen-/Insel-Entscheidungen mit
Float-Toleranzen fallen, (c) `std::sort`/Pointer-Compare mit
Float-Gleichstand steht. **Nur Fund-Katalog**, nicht gefixt.

### A. Narrow-vs-normal solidInfill-Klassifikation (direkteste Treffer)

- **`src/libslic3r/Fill/Fill.cpp:597-630`** –
  `split_solid_surface(size_t layer_id, const SurfaceFill &fill,
  ExPolygons &normal_infill, ExPolygons &narrow_infill)`. Trennt
  solidInfill-Flaechen in „schmal" (ipConcentricInternal) vs „normal"
  (originaler Pattern) via Clipper-Morphologie:
  `intersection(filled_area, opening(filled_area, scaled_spacing,
  scaled_spacing))` (Z. 613). Entscheidung `if (inner_area.empty())` →
  klassifiziert als „narrow" (Z. 615-618). **Hypothese:** 1 ULP
  Unterschied in `scaled_spacing` (float→int-Cast) kippt
  Opening-Ergebnis; dann sind auf arm64 andere Inseln „narrow" als auf
  x86. Da Narrow mit `ipConcentricInternal` deutlich weniger und
  kuerzere Segmente erzeugt als monotonic Rectilinear, wuerde das die
  beobachteten −316 mm Filament auf der „niedrigen" Variante erklaeren
  (nicht fehlendes Material, sondern Pattern-Switch mit kleinerem
  Flaechen-Coverage).
- **`src/libslic3r/Fill/Fill.cpp:1152-1186`** – Gate
  `detect_narrow_internal_solid_infill`; ruft `split_solid_surface` auf
  und reclassifiziert in `surface_fills[i].params.pattern =
  ipConcentricInternal` bzw. splittet `surface_fills` in zwei
  Eintraege.

### B. SurfaceFillParams-Deduplication (set-Order-Flipper)

- **`src/libslic3r/Fill/Fill.cpp:275-308`** – `SurfaceFillParams::operator<`
  vergleicht 15 Float-Member: `bridge_angle`, `spacing`, `overlap`,
  `angle`, `density`, `anchor_length`, `anchor_length_max`,
  `flow.width()`, `flow.height()`, `flow.nozzle_diameter()`,
  `role_speed`, `lateral_lattice_angle_1`, `lateral_lattice_angle_2`,
  `infill_lock_depth`, `skin_infill_depth`, `infill_overhang_angle`.
  Verwendet in `std::set<SurfaceFillParams> set_surface_params`
  (Fill.cpp:833). **Hypothese:** 1 ULP-Unterschied in einem Member
  macht aus zwei „identischen" Konfigs zwei getrennte Set-Eintraege →
  mehr oder weniger `surface_fills`-Elemente auf arm64 vs x86. Jedes
  zusaetzliche SurfaceFill emittiert einen eigenen Fill-Block mit
  eigenem Pattern-Walk; Reihenfolge der Set-Iteration (Z. 1021) ist
  die Reihenfolge, in der G-Code herauskommt.
- **`src/libslic3r/Fill/Fill.cpp:1012-1016`** – Insertion: `auto
  it_params = set_surface_params.find(params);` → bei FP-Tie wird
  `params` als existierend betrachtet und nicht eingefuegt. Fliesst
  dann in `region_to_surface_params[region_id][surface_idx] =
  &(*it_params);` (Z. 1016) → **Pointer-Identitaet** haengt von der
  set-Allocator-Reihenfolge ab, was spaetere Partition-Logik
  beeinflussen koennte.

### C. Sparse-infill-Anker / Bridge-over-infill-Sorting

- **`src/libslic3r/PrintObject.cpp:3131`** – in
  `PrintObject::bridge_over_infill()` (ab Z. 2468):
  `std::sort(surfaces_by_layer[lidx].begin(),
  surfaces_by_layer[lidx].end(), [](...) { return a.min.x() <
  b.min.x(); });` sortiert Bruecken-Kandidaten nach BBox-Minimum. Fuer
  symmetrische Modelle (z. B. Wuerfel) sind die BBox-Minimums
  **identisch** → `std::sort` ist unstable, Reihenfolge ist
  allocator-abhaengig.
- **`src/libslic3r/PrintObject.cpp:3143`** – unmittelbar danach
  `std::stable_sort` nach `(origin - a.min.cast<double>())
  .squaredNorm()`. `squaredNorm()` ist `x*x + y*y`, prime FMA-Kandidat.
  arm64 kann FMA, x86-GCC default auf `-ffp-contract=fast` auch — aber
  die Reihenfolge der FMAs unterscheidet sich: arm64 ist eine Einzel-
  Instruktion, x86 ist je nach Register-Allocation geplant. 1-ULP-Diff
  im `squaredNorm` fuer zwei gleich-nah liegende Flaechen flippt die
  Sortierung.

### D. Perimeter-Order (Arachne, tie-aware, aber Fallback nicht idempotent)

- **`src/libslic3r/Arachne/SkeletalTrapezoidation.cpp:1441-1467`** –
  Sort von `std::vector<edge_t*>` mit expliziter Tie-Break-Logik auf
  `distance_to_boundary` (coord_t, kein FP!). ABER: wenn der Fall
  `// Ordering is not important` (Z. 1463) greift, faellt sie durch
  und `std::sort` entscheidet implementation-defined. Fliesst in die
  Perimeter-Reihenfolge → aendert extrusion-order, aber nicht
  Material-Menge → wenig wahrscheinlich fuer solidInfill-316 mm, aber
  moegliche Erklaerung fuer kleinere Byte-Diffs in Perimeter-Role.

### E. Weitere Kandidaten (geringer prioritaet)

- **`src/libslic3r/Fill/FillBase.cpp:2493`** und **2633** – `std::sort`
  mit Pointer-Vergleich auf `l->cost > r->cost` (double). Ties fallen
  implementation-defined aus.
- **`src/libslic3r/Fill/FillRectilinear.cpp:2092-2093`** – `std::sort`
  mit Lambda `[](const MapType &l, const MapType &r){ return l.first <
  r.first; }` auf Pointer-Keys (`&segs[region.left.vline]
  .intersections[region.left.low]`) → direkte Pointer-Sortierung,
  haengt von Vektor-Allocation ab.

### Hypothesen-Ranking fuer die arm64-„niedrige" Variante

1. **A** (`split_solid_surface` + `opening`) ist der plausibelste
   Treffer: erklaert mengenmaessig den −316 mm-Befund (Pattern-Switch
   auf schmalere Fuellung), passt zur diffusen Streuung ueber 79 % der
   Layer, und schlaegt zu bei JEDEM Lauf, nicht nur bei konkreten
   Zellen.
2. **B** (SurfaceFillParams-Set) ist wahrscheinlich fuer die
   Reihenfolge-Abweichungen in anderen Rollen, aber alleine erklaert es
   die solidInfill-Lueke nicht.
3. **C** (bridge_over_infill-Sort) ist wahrscheinlich fuer
   Bruecken-Role, nicht fuer solidInfill.

### Naechste Entscheidung von Klaus

Zwei Wege, Hypothese A zu testen (nicht hier umgesetzt):
- **A1 Instrumentierung:** kurze Zaehler in `split_solid_surface`
  nach Z. 615 (`inner_area.empty()`): Zahl der narrow- vs
  normal-Klassifikationen pro Lauf vergleichen (arm64 1-thread
  2 Laeufe + x86). Wenn arm64 bimodal, A ist bestaetigt.
- **A2 Determinisierung:** `opening()` durch eine FP-tolerant
  deterministische Variante ersetzen oder `scaled_spacing` auf
  `coord_t`-Granularitaet runden, bevor `opening` aufgerufen wird.
  Patch im Orca-Upstream nicht erlaubt → muss in CLI-Wrapper oder in
  einem Shim passieren.

Keine Umsetzung heute Nacht; wartet auf Klaus.

---

## 2026-11-01 23:25 UTC – Divergenz Stufe 2b: Clang-Host-Build geht nicht ohne Entscheidung (Blocker #3)

Klaus hat Weg A (Allocator) verworfen und Stufe 2b beauftragt:
„x86 mit Clang/libc++ bauen, Compiler-Hypothese isolieren". Mit den
auf AMR5 installierten Toolchains laesst sich das nicht sauber bauen:

1. **System-Clang 23.1.4**: scheitert an
   `src/libslic3r/AABBTreeLines.hpp:35` (Eigen-Template-Deduktion
   `CwiseUnaryOp` vs `Matrix` in `distance_to_squared`). Kein
   Orca-Patch zulaessig.
2. **NDK clang-18 + System-libstdc++16**: scheitert in
   `deps_src/admesh/stlinit.cpp` → `stl.h:222` an einer bekannten
   Inkompatibilitaet (`__normal_iterator<T>::operator-` trailing
   return type, Clang<23 sieht die Klasse an der Stelle als
   unvollstaendig).

Verfuegbare Toolchains auf AMR5: nur GCC 16.2.1, Clang 23.1.4, NDK
clang-18. Weder gcc-14/15 noch clang-18/19/20 als Pakete installiert.
Die NDK-Clang hat zwar eine eigene libc++ dabei (deren Nutzung den
libstdc++-Bug umgehen wuerde), aber die Orca-x86-Deps sind mit
libstdc++ gebaut → ABI-Mismatch.

**Konsequenz:** Nach CLAUDE.md Pkt. 3 (Drei-Versuche-Regel: 2
substantiell verschiedene Toolchain-Versuche gescheitert) kein
dritter blinder Versuch, sondern **Eintrag in `docs/blockers.md` #3**
und Rueckfrage an Klaus. Drei Wege zur Auswahl:
a) Clang+libc++ ueberall → Deps-Rebuild (~30–60 min),
b) gcc-14/clang-18 ueber AUR oder Toolbx (System-Aenderung),
c) Compiler-Experiment ueberspringen, direkt Stufe 3+4.

Default waehrend Klaus schlaeft: **Weg c** — Stufe 3 (Grep in
libslic3r nach solidInfill-Entscheidungen) laeuft weiter, damit der
Nachtlauf nicht leer bleibt.

**Belegstellen Fehler:**
- Clang-23: `AABBTreeLines.hpp:35` → `no matching function for call
  to 'distance_to_squared'` (6 Error-Instantiations im Build-Log).
- NDK clang-18: `stl_iterator.h:1337` → `member access into
  incomplete type` via `vector<Eigen::Matrix<...>>` in
  `deps_src/admesh/stl.h:222`.

---

## 2026-11-01 23:09 UTC – Divergenz Stufe 4 (nur Skizze): zwei Wege

Klaus hat Stufe 4 explizit als "NICHT umsetzen, nur skizzieren"
gesetzt. Hier sind beide Wege konkret genug fuer eine Entscheidung
nach dem Morgenbericht.

### Weg A: Deterministischer Allocator fuer die arm64-CLI

**Welcher**: entweder **jemalloc** (BSD-Lizenz, mature, deterministisch
bei fester RNG-Saat, 15 MB statische Lib) oder **mimalloc**
(MIT-Lizenz, Microsoft, API-kompatibel, 2 MB Lib). jemalloc hat eine
`--with-malloc-conf="prof:false,junk:false,xmalloc:true"`-Konfig,
die Reproducibility maximiert; mimalloc ist per default
deterministischer als jemalloc und Scudo.

Beide als Statische Link direkt in `handslice-cli-arm64` einbauen
oder als `LD_PRELOAD` am Device aufrufen; statisch ist sauberer
und braucht keine Device-Env-Variable.

**Aufwand**:
- Build-System: jemalloc oder mimalloc zu `engine/build-deps-arm64.sh`
  hinzufuegen (1 ExternalProject-Eintrag + 1 Link-Flag). ~2-3 Std.
- Keine Code-Aenderung an libslic3r noetig (Allocator-Replacement
  ueber `malloc`/`free`-Hooks).
- Validierung: 10× Wuerfel + 3× Auryn am Poco (muesste Klaus mit
  Geraet machen). ~1 Std.
- **Gesamt**: 3-4 Std. aktive Arbeit + Device-Zeit.

**Erwartung**:
- **Determinismus pro arm64-Build**: hoch wahrscheinlich erfuellt
  (mimalloc und jemalloc geben bei gleicher Konfig gleiche Adress-
  Reihenfolge).
- **Byte-Gleichheit arm64 ↔ x86**: **unwahrscheinlich**. Scudo-
  Experiment hat gezeigt, dass die x86-Determinismus auch MIT
  Allocator-Randomisierung bleibt. Umgekehrt: arm64 mit nicht-
  randomisierendem Allocator wird reproduzierbar, aber ob die
  reproduzierbare Variante dann bei `92951c26…` landet, ist offen.
  Vermutung (unbewiesen): Nein — die Divergenz kommt wahrscheinlich
  nicht vom Allocator, sondern von libc++ vs. libstdc++ im Compare.

**Vorteil**: Klein, isoliert, kein Patch an Orca-Upstream, kein
Impact auf x86.

**Nachteil**: Loest die Reproduzierbarkeit, aber nicht zwingend
die Byte-Gleichheit zu x86.

### Weg B: Tie-Break-Patch an den Stellen aus Stufe 3

**Wo**: dafuer muesste Stufe 3 (Grep + eingrenzen auf eine konkrete
Call-Site) erst gelaufen sein, was bisher nicht passiert ist, weil
die Scudo-Hypothese nicht bestaetigt wurde. Als blinde Skizze:
Perimeter-Erzeugung in `libslic3r/PerimeterGenerator.cpp`,
Fill-Entscheidung in `libslic3r/Fill/Fill.cpp` oder
`libslic3r/LayerRegion.cpp`, Sort-Operationen auf
`ExtrusionEntityCollection` in `libslic3r/ExtrusionEntityCollection
.cpp`.

**Was**: eine Tie-Break-Regel am Compare, die bei Float-Gleichheit
auf ein stabiles sekundaeres Kriterium ausweicht. Beispiel-Pattern:
```cpp
// vorher
std::sort(v.begin(), v.end(), [](auto& a, auto& b){
    return a.cost < b.cost;
});
// nachher
std::sort(v.begin(), v.end(), [](auto& a, auto& b){
    if (a.cost != b.cost) return a.cost < b.cost;
    return a.stable_id < b.stable_id;  // oder bbox-Mitte, oder Hash
});
```

Jeder solche Patch ist klein (einstellige Zeilenanzahl), aber die
Suche nach der korrekten Call-Site und die Validierung, dass es
den Druck nicht veraendert, ist viel Arbeit.

**Aufwand**:
- Vorarbeit (Grep + Bisect per Scudo-x86-Instrumentierung):
  1-2 Werktage. Setzt voraus, dass Scudo doch die Divergenz
  reproduziert — aktuell NICHT der Fall. Alternative: direkte
  TBB-serielle x86-Bisect auf Compiler-Flag-Variationen oder
  per-Datei-Vergleich zwischen GCC-x86 und Clang-x86-Build.
  **Allein die Call-Site-Lokalisierung kann 2-5 Werktage dauern.**
- Patch selbst: 1-4 Zeilen.
- Validierung: `engine/test/run-reference-test.sh` muss weiter
  `92951c26…` liefern — der Patch darf x86 **NICHT** aendern.
  Fuer eine echte Tie-Break-Regel ist das moeglich (sie greift
  nur bei exakter Float-Gleichheit, was auf x86 selten echt
  auftritt).
- Upstream-Faehigkeit: hoch. Orca akzeptiert kleine Patches, die
  Determinismus auf Nicht-x86 verbessern, wenn sie den x86-Output
  nicht aendern.

**Erwartung**:
- **Determinismus pro Plattform**: ja.
- **Byte-Gleichheit arm64 ↔ x86**: **wahrscheinlich** (das ist genau
  der Zweck des Patches).
- **x86-Slice**: **unveraendert**.

**Vorteil**: Loest die eigentliche Divergenz-Ursache; Upstream-faehig;
nachhaltig.

**Nachteil**: Deutlich mehr Aufwand als Weg A (Lokalisierung ist
nicht trivial). Benoetigt ein Testmodell, das die Divergenz
reproduziert — Wuerfel reicht nicht (Reihenfolge nur), Auryn reicht
(fehlende Moves). Klaus-Entscheid, ob die 2-5 Werktage
gerechtfertigt sind.

### Entscheidungs-Matrix

| Kriterium | Weg A (Allocator) | Weg B (Tie-Break-Patch) |
|-----------|-------------------|-------------------------|
| arm64 reproduzierbar | ✓ hoch wahrscheinlich | ✓ |
| arm64 = x86 byte-gleich | ✗ unwahrscheinlich | ✓ wahrscheinlich |
| x86 unveraendert | ✓ | ✓ (bei korrektem Patch) |
| Aufwand | 3-4 Std. | 2-5 Werktage |
| Upstream-faehig | nicht relevant | ✓ |
| Loest Grundursache | nein, nur Symptom | ja |

### Empfehlung (Vermutung, kein Beschluss)

Weg A als **schneller Zwischenschritt** fuer die arm64-
Reproduzierbarkeit (die "fehlende Infill-Variante" wuerde dann
entweder stabil nicht mehr auftreten ODER immer auftreten — beides
ist eine echte Aussage). Weg B als **Langzeitziel**, abhaengig
davon, wie oft wir auf der niedrigen Variante landen und wie viel
Druckqualitaets-Risiko Klaus dort sieht.

Klaus entscheidet nach dem Morgenbericht; nichts von Stufe 4 ist
umgesetzt.

## 2026-11-01 23:06 UTC – Divergenz Stufe 3: wo fehlen die solidInfill-Moves?

Nachtrag von Klaus zur Nachtschicht. Stufe 2 (Scudo) hat die
Pointer-Ordering-Hypothese **nicht bestaetigt**, daher wird die
geplante Grep-Suche nach `std::sort/set/map/unordered_*` auf `T*`-
Elementen in `libslic3r/{Perimeter,Fill,GCode/*}` **nicht
durchgefuehrt** — Klaus' Regel: "nur wenn Stufe 2 bestaetigt".

Was in dieser Stufe gemacht wurde (unabhaengig vom Stufe-2-Ergebnis,
weil Klaus die Lokalisierung der fehlenden Moves separat angefragt
hat): per-Schicht- und per-Z-Bereich-Analyse der verlorenen
`solidInfill`-Moves.

### Lokalisierung der fehlenden solidInfill-Moves

Vergleich x86-Default (`adefd3a51a…`) vs. arm64-niedrig
(`8a50e806…`). Je Schicht `layer_id → count(solidInfill extrude
moves)`:

| Statistik | Wert |
|-----------|------|
| Schichten mit Differenz | **818 von 1033 (79 %)** |
| Davon: Schichten mit FEHLENDEN Moves | 651 (−23 580 Moves gesamt) |
| Davon: Schichten mit MEHR Moves | 167 (+264 Moves gesamt) |
| **Netto Shortfall** | **−23 316 Moves** |

**Verteilung ueber die Druckhoehe** (20-mm-Z-Buckets):

| Z-Bereich (mm) | Fehlend | Gesamt (x86) | Anteil ausgelassen |
|----------------|---------|--------------|---------------------|
| 0 – 20 | 454 | 10 138 | 4.48 % |
| 20 – 40 | 1 618 | 38 646 | 4.19 % |
| 40 – 60 | 2 142 | 29 778 | 7.19 % |
| 60 – 80 | 3 173 | 57 814 | 5.49 % |
| **80 – 100** | **4 544** | **51 501** | **8.82 %** |
| 100 – 120 | 4 084 | 76 219 | 5.36 % |
| 120 – 140 | 2 917 | 53 507 | 5.45 % |
| 140 – 160 | 2 403 | 35 958 | 6.68 % |
| 160 – 180 | 1 708 | 38 333 | 4.46 % |
| 180 – 200 | 517 | 24 662 | 2.10 % |
| 200 – 220 | 20 | 3 474 | 0.58 % |

**Verteilung ueber die XY-Flaeche** (Beispiel-Schichten mit den
groessten Shortfalls, Bounding-Box der betroffenen `solidInfill`-
Region):

| Z (mm) | Layer | Moves fehlend | X-Bereich der Region | Y-Bereich |
|--------|-------|--------------|---------------------|-----------|
| 109.80 | 548 | −125 | [58.2, 206.6] (148 mm) | [107.8, 137.6] (30 mm) |
| 107.40 | 536 | −119 | [45.5, 211.8] | [107.7, 137.1] |
| 83.60 | 417 | −114 | [60.8, 211.7] | [104.0, 130.7] |
| 112.20 | 560 | −112 | [45.7, 210.9] | [108.5, 138.4] |
| 50.20 | 250 | −111 | [56.8, 195.2] | [104.0, 121.7] |

Die Y-Ausdehnung der betroffenen Regionen ist konsistent **~30 mm
breit um Y = 120 mm herum**; die X-Ausdehnung erstreckt sich ueber
**fast die ganze Modellbreite (150-170 mm)**. Keine ortsabhaengige
Konzentration auf einen einzigen Hohlraum oder einen einzigen
Bereich — die Luecken verteilen sich DIFFUS ueber zwei Drittel aller
Schichten.

Gegenprobe mit "hoher" Variante `e4f28cab…`:
- Nur 600 Schichten mit Diff.
- Davon 16 Schichten mit weniger Moves (−424 gesamt).
- 584 Schichten mit mehr Moves (+1 033 gesamt).
- Netto **+609** — reine Reihenfolgefluktuation, keine Luecke.

Und die `--threads 1`-Variante `ab0704c7…`:
- 819 Schichten mit Diff, 656 mit weniger Moves (−23 954 gesamt).
- Netto **−23 695** — **praktisch identisches Muster** wie
  `8a50e806…`. Die "niedrige" Verhaltensklasse ist also kein
  einmaliger Ausreisser; sie tritt bei `--threads 1` wie bei
  Default-Multi-Thread auf.

### Was heisst das fuer die Ursache (nur Vermutungen)

Das Shortfall-Muster ist **nicht in einer Schicht konzentriert**
und **nicht in einem XY-Bereich konzentriert**. Es trifft fast
jede zweite Schicht und erstreckt sich ueber die volle Modell-
breite in einer Y-Bandbreite von etwa 30 mm. Pro betroffene
Schicht fehlen jeweils 10-20 % der `solidInfill`-Moves. Das legt
nahe (nicht bewiesen):

- **NICHT** eine kaputte Flaechen-Erkennung in einer Schicht
  (dann waere EINE Schicht komplett ohne, nicht 650 Schichten
  mit jeweils 15 %).
- **NICHT** eine kaputte vertikale-Wandstaerken-Erkennung (dann
  waere ein zusammenhaengender Z-Bereich betroffen, nicht alle).
- **NICHT** eine kaputte Bruecken-Erkennung (die wuerde nur an
  Bruecken-Schichten greifen).
- **Plausibel** ein per-Island-Entscheid, der auf einem Teil der
  solid-infill-Inseln kippt. Z. B. "ist diese Flaeche breit genug
  fuer dense infill" oder "liegt sie in der Line-Width-Toleranz
  einer vorhandenen Perimeter". Wenn so ein Entscheid auf einem
  Float-Vergleich an der Toleranzgrenze haengt, kippt er bei
  arm64 (Clang/libc++) anders als bei x86 (GCC/libstdc++).

Nicht gegrept, weil das die Stufe-3-Grep-Arbeit waere, die laut
Klaus-Regel ohne Scudo-Bestaetigung nicht laeuft.

Reference-Test weiter green:
`92951c26…`, 8479 Zeilen.

Keine Code-Aenderung in dieser Stufe. Analyse-Skripte liegen unter
`/tmp/div-analysis/` (gitignored).

## 2026-11-01 23:03 UTC – Divergenz Stufe 2: Scudo-Allocator-Hypothese widerlegt

**Scudo-Setup**: `/usr/lib/clang/23/lib/linux/libclang_rt.scudo_
standalone-x86_64.so` via `LD_PRELOAD`. Scudo ist der Allocator, den
Android ab API 30 standardmässig fuer Native-Code benutzt und mit
Address-Randomisierung + Chunk-Shuffling arbeitet. Hypothese
(Klaus): Scudo veraendert Pointer-Adressen zwischen Prozess-Starts,
Orca entscheidet Gleichstaende an irgendeiner Stelle nach Zeiger-
wert → arm64 wird non-deterministisch, waehrend glibc (AMR5) stabile
Adressen vergibt.

**Messungen** (x86 CLI unveraendert, nur `LD_PRELOAD`):

Würfel 10×:
- Alle 10 Laeufe → sha `92951c26…` (GUI-Referenz).
- Zeit 0.77-0.79 s (= Default-Niveau).
- 8479 Zeilen EXECUTABLE_BLOCK, 1177.151 mm Filament.

Auryn 3× (Scudo):

| Lauf | Zeit | Zeilen | Filament | sha |
|------|------|--------|----------|-----|
| 1 | 25 s | 2 826 766 | 39 223.579 mm | `adefd3a51a…` |
| 2 | 24 s | 2 826 766 | 39 223.579 mm | `adefd3a51a…` |
| 3 | 25 s | 2 826 766 | 39 223.579 mm | `adefd3a51a…` |

Alle drei Laeufe byte-identisch zum x86-Default-Slice. **Scudo bricht
die x86-Determinismus NICHT.** Hypothese "Scudo-Randomisierung
verursacht die arm64-Divergenz" ist durch dieses Experiment **nicht
gestuetzt**.

Was das NICHT widerlegt:
- Scudo laeuft hier als Preload auf einem glibc-Prozess; es gibt
  weiterhin `malloc`-Pfade die durch glibc gehen (z. B.
  `__libc_malloc`-Aufrufer die symbolisch an glibc gebunden sind).
  Vollstaendige Scudo-only-Umgebung braeuchte einen statischen Build.
- ASLR auf dem AMR5-Host koennte abgeschaltet sein (`cat /proc/sys/
  kernel/randomize_va_space` nicht gecheckt).
- Scudo randomisiert innerhalb seines Chunk-Managers, aber die mmap-
  basierte grosse-Allocation-Logik koennte dennoch deterministisch
  sein. Orcas 2.1 M Moves bestehen aus vielen grossen std::vector,
  nicht aus vielen kleinen heap-Objekten.

Trotz dieser Einschraenkungen: die eigentliche Hypothese
"Allocator-Randomisierung reicht aus, um die arm64-Bimodalitaet zu
reproduzieren" ist mit dem direkt verfuegbaren Mittel **nicht
belegbar**.

### Andere Kandidaten (unbewiesen)

- **Clang vs. GCC Codegen bei equal-metric floats**: Clang und GCC
  erzeugen bei `A < B`-Vergleichen und `std::sort` auf float-
  Compare-Funktionen leicht unterschiedlichen Code. Bei
  mathematisch gleichen Werten kann die Reihenfolge der Vergleiche
  zu anderen Tie-Break-Entscheidungen fuehren.
- **arm64-Memory-Ordering (weak memory model)**: TBB nutzt
  Atomics; bei relaxed-Ordering koennen auf arm64 Reihenfolgen
  entstehen, die auf x86 (TSO) nicht moeglich sind. Innerhalb
  einer Single-Threaded-Arena (unser `--threads 1`-Fall) sollte
  das aber nicht mehr greifen; dass arm64 trotzdem nicht
  reproduzierbar ist, spricht gegen diesen Kandidaten.
- **NDK libc++ `std::sort`-Instabilitaet**: NDK libc++ verwendet
  die ChatGPT-weit bekannt instabile introsort-Variante. Bei
  gleichen Keys ist das Ergebnis nicht spezifiziert und kann
  compiler/laufzeit-abhaengig anders ausfallen als GCC's libstdc++
  Intro-Sort. Das waere konsistent mit Runde 2's
  `std::sort`-Vermutung aus `engine-integration.md:665-673`.

Reference-Test nach dieser Stufe:
`92951c26…` matches, 8479 Zeilen. Green.

Keine Code- oder Build-Aenderung in dieser Stufe. Reines Mess-
Experiment.

## 2026-11-01 22:57 UTC – Divergenz Stufe 1: Auswirkung je Wegtyp am Druckteil

Nachtauftrag von Klaus, alles am AMR5. Stufe 1 vor Stufe 2.

Reference-Test (`engine/test/run-reference-test.sh`) vorab:
`92951c26…` matches, 8479 Zeilen. Green bevor und nach dieser Stufe.

### Verfügbare G-Codes (keine neuen erzeugt, nur analysiert)

Alle über `handslice-cli --input-gcode <gcode> --export-toolpaths <hspt>`
auf HSPT umgewandelt, dann aggregiert.

| Datei | Beschreibung | sha (prefix) | Filament footer |
|-------|-------------|--------------|-----------------|
| `/tmp/x86-def.gcode` + `/tmp/x86-t1/2/4.gcode` | x86 Default + --threads 1/2/4 | `92951c26…` | 1177.15 mm |
| `/tmp/div-arm64/cube.gcode` | arm64 Würfel, Default-Variante A | `a30ffec3…` | 1177.15 mm |
| `/tmp/div-x86/auryn.gcode` + `/tmp/auryn-x86-t1.gcode` | x86 Auryn (Default & --threads 1 identisch) | `adefd3a5…` | 39 223.58 mm |
| `/tmp/div-arm64/auryn.gcode` | arm64 Auryn, "niedrige" Variante aus Runde 1 | `8a50e806…` | 38 906.85 mm |
| `/tmp/div-arm64/auryn-repro.gcode` | arm64 Auryn, "hohe" Variante Runde 3 | `e4f28cab…` | 39 220.36 mm |
| `/tmp/auryn-arm64-t1.gcode` | arm64 Auryn, --threads 1 Lauf 1 | `ab0704c7…` | 38 903.29 mm |

**Nicht verfügbar** (kein Poco in der Nachtschicht): die zweite stabile
Würfel-Variante B (`7c88f484…`, 8321 Z). Keine Ersatz-Datei erzeugt
wie von Klaus angewiesen.

### Ergebnis Würfel — reine Reihenfolge

| Rolle | x86 Filament | arm64 A Filament | Δ |
|-------|--------------|------------------|---|
| perimeter (inner wall) | 239.607 mm (396 moves) | 239.607 mm (396) | 0.000 |
| externalPerimeter (outer wall) | 233.772 mm (400) | 233.772 mm (400) | 0.000 |
| internalInfill | 452.707 mm (1564) | 452.707 mm (1564) | 0.000 |
| solidInfill | 137.138 mm (687) | 137.138 mm (687) | 0.000 |
| topSolidInfill | 31.749 mm (70) | 31.749 mm (70) | 0.000 |
| bottomSurface | 25.523 mm (105) | 25.523 mm (105) | 0.000 |
| internalBridgeInfill | 35.856 mm (112) | 35.856 mm (112) | 0.000 |
| custom (Purge) | 20.800 mm (2) | 20.800 mm (2) | 0.000 |
| **TOTAL extrude** | **1177.151 mm (3336)** | **1177.152 mm (3336)** | **+0.001 mm** |

Zeiten identisch auf 0.00 s. Alle 3336 Extrude-Moves gleich zahl-
reich. **Am Würfel ist arm64-A inhaltsgleich zum x86-Slice; nur die
*Reihenfolge* der G-Code-Zeilen unterscheidet sich** (Rotations-
Spiegel wie seit `engine-integration.md:655-658` dokumentiert).
Reproduzierte 27 B grössere Datei kommt aus 3 zusätzlichen
Non-Extrude-Moves (Travel/Wipe), die den Druckteil nicht ändern.

### Ergebnis Auryn — die zwei "arm64-Varianten" sind inhaltlich
unterschiedlich

Vergleich x86-Default (`adefd3a5…`) vs. drei arm64-Varianten:

| Variante / Rolle | solidInfill mm | Δ zu x86 | solidInfill Moves | Δ Moves |
|------------------|---------------|----------|-------------------|---------|
| x86 Default | 6080.342 | — | 420 030 | — |
| arm64 "hoch" `e4f28cab…` | 6077.205 | **−3.137** | 420 639 | +609 |
| arm64 "niedrig-A" `8a50e806…` | 5763.702 | **−316.640** | 396 714 | **−23 316** |
| arm64 "niedrig-B" `ab0704c7…` (--threads 1) | 5760.135 | **−320.206** | 396 335 | **−23 695** |

Zusammen mit TOTAL-Extrude-Filament:

| Variante | Total mm | Δ mm | Total moves | Δ moves |
|----------|----------|------|-------------|---------|
| x86 Default | 39 223.577 | — | 1 836 022 | — |
| arm64 hoch | 39 220.354 | **−3.223** | 1 836 569 | +547 |
| arm64 niedrig-A | 38 906.851 | **−316.726** | 1 812 645 | **−23 377** |
| arm64 niedrig-B | 38 903.284 | **−320.292** | 1 812 266 | **−23 756** |

Alle anderen Rollen (perimeter, externalPerimeter, overhangPerimeter,
internalInfill, topSolidInfill, bridgeInfill, internalBridgeInfill,
gapFill, brim, custom) weichen nur um ≤ 0.2 mm und ≤ 60 Moves
voneinander ab — Rundung oder Reihenfolge.

**Beobachtung**: Die "niedrige" arm64-Variante lässt **~23 000 Solid-
Infill-Moves (≈5.5 % des Solid-Infill, ≈0.8 % des Gesamt-Filaments)
weg.** Nicht nur andere Reihenfolge; echte fehlende Druckbefehle.
Die "hohe" Variante liegt praktisch bei x86 (−3 mm = Reihenfolge).

**Was heisst das für die Phase-C-Bewertung aus
`engine-integration.md:601-619`**: Die Grob-Kriterien (±0.01 g
Gewicht, ±5 s Zeit, Zeilenanzahl) sind für die "hohe" Variante
weiter erfüllt, aber **für die "niedrige" Variante NICHT** — 316 mm
= 1 g Material weniger, 154 s Zeit weniger, 23 000 Zeilen weniger
als x86. Die Schlussfolgerung "arm64 ist funktional äquivalent"
aus Runde 1/2 war unbelegt, und diese Zahlen zeigen jetzt: beim
asymmetrischen Modell ist eine der zwei stabilen Varianten
**ein unterspezifizierter Druck**, nicht nur andere Pfadführung.

**Ausbreitung in `solidInfill`**: Das ist die 100 %-Füllung
zwischen Walls und TopSurface in bestimmten Regionen. Fehlende
~23 000 Moves bedeuten entweder, dass bestimmte Flächen gar
nicht gefüllt werden oder dass die Füllung lückenhaft ist. Vor
Ort gedruckt würde das als Hohlraum sichtbar werden; ob die
restlichen 94.5 % des Solid-Infills die Fläche noch abdecken,
kann nur eine 2D-Projection auf z. B. die 500-mm-Schicht
beweisen — nicht in dieser Stufe.

Dieser Befund verschiebt die Dringlichkeit: Byte-Gleichheit ist
weiter Fernziel, aber die arm64-Bimodalität ist nicht mehr nur
kosmetisch, sondern kann **ein Druckteil mit Lücken** produzieren.

Reference-Test nach dieser Stufe erneut gelaufen:
`92951c26…` matches, 8479 Zeilen. Green.

## 2026-11-01 22:02 UTC – arm64/x86 Divergenz Runde 3: task_arena-Fix, x86 jetzt byte-gleich zu Orca-GUI

Klaus hatte recht: der Hang war KEIN struktureller Orca-Fehler. Unser
`tbb::global_control` begrenzte den Worker-Pool, nicht die Arena-
Kapazitaet. `tbb::this_task_arena::max_concurrency()` lieferte weiter
HW-Cores zurueck, und Orcas Barriere in `Thread.cpp:235-247` wartete
auf HW-viele Tasks, von denen nur N tatsaechlich liefen. Der TBB-
Standardweg ist eine eigene `tbb::task_arena(N)` plus
`arena.execute(...)`.

### 1. CLI auf task_arena umgestellt

`engine/cli/handslice-cli.cpp:877-914`: `tbb::global_control` raus,
`tbb::task_arena(args.threads)` plus `run_in_arena(fn)`-Helfer rein.
Beide heissen Slice-Phasen (`print.process()` auf :1105 und
`print.export_gcode(...)` auf :1257) laufen jetzt in dem Arena-
Context.

**Belegstellen in der mitgezogenen oneTBB** (im Repo via
`engine/OrcaSlicer/deps/build-x86/dep_TBB-prefix/src/dep_TBB/include/
oneapi/tbb/task_arena.h`):

- Konstruktor `task_arena(int max_concurrency_)` → `:264-271`
  (`"@arg max_concurrency specifies total number of slots in arena
  where threads work"`).
- Methode `task_arena::max_concurrency()` → `:432-436` liefert
  `my_max_concurrency` zurueck (das vom Konstruktor gesetzt wird).
- Freie Funktion `tbb::this_task_arena::max_concurrency()` → `:464-
  467` + `:492-500`. Sie dispatcht auf die *aktuelle* Arena, also
  die durch `arena.execute(...)` betretene.

Default-Verhalten unveraendert: ohne `--threads` wird keine Arena
konstruiert und Orca laeuft wie bisher in seiner Default-Arena mit
HW-Cores.

### 2. x86 jetzt byte-gleich zu Orca-GUI-Referenz

Wuerfel-Test, GUI-Referenz-sha `92951c26…`
(`engine/test/reference/cube_20mm_cc2_gui_v2.4.2.gcode`):

| Modus (x86) | Zeit | Zeilen | sha | Vergleich |
|-------------|------|--------|-----|-----------|
| default (ohne --threads) | 0.71 s | 8479 | `92951c26…` | **= GUI-Ref ✓** |
| --threads 1 | 0.74 s | 8479 | `92951c26…` | **= GUI-Ref ✓** |
| --threads 2 | 0.70 s | 8479 | `92951c26…` | **= GUI-Ref ✓** |
| --threads 4 | 0.70 s | 8479 | `92951c26…` | **= GUI-Ref ✓** |

Der Hang ist weg, UND alle vier Thread-Zahlen produzieren den
GUI-identischen Byte-Strom. **x86 erreicht Phase C
("sha256 identisch zum Desktop") im strikten Sinn** —
Erfolgskriterium aus `engine/test/run-reference-test.sh:33`.

Hinweis zur Vermutung in Runde 2 ("Hang strukturell blockiert"):
widerlegt. Die Beschreibung war falsch; richtige Analyse hat Klaus
geliefert.

### 3. Poco (arm64): Hang weg, Determinismus leider nicht hergestellt

**Wuerfel 10× mit `--threads 1`:**

| Variante | Anzahl | sha | Zeilen |
|----------|--------|-----|--------|
| A | 7/10 | `a30ffec3…` | 8479 |
| B | 3/10 | `7c88f484…` | 8321 |

Beide shas kennen wir aus Runde 2 (Default-Lauf hatte dasselbe
Varianten-Paar, 8:2). Keine der zwei trifft die GUI-Referenz
`92951c26…`. Slice-Zeit: 0.75-0.79 s (gleiches Niveau wie Default,
= HW-vielen Threads). **Non-Determinismus auf arm64 bleibt also
bestehen**, obwohl nur ein Worker-Slot aktiv ist.

Vermutung (nicht geprueft): die verbleibende arm64-Divergenz hat
NICHTS mit TBB-Scheduling zu tun — sie bleibt bei N=1 Worker. Mögliche
andere Ursachen (jede davon unbewiesen):
- `std::sort` (libc++ via NDK) wird bei gleichwertigen Keys von
  Pointer-Werten "entschieden", und ASLR gibt bei jedem Lauf andere
  Adressen.
- Hash-basierte Container iterieren in Reihenfolge, die vom
  Allocator-Layout abhaengt.
- Codegen-Unterschiede (Clang vs. GCC) in equal-metric-Pfaden.

Alles Hypothesen, keine Messung.

### 4. Auryn `--threads 1` am Poco

Drei Laeufe nacheinander:

| Lauf | Zeit | Zeilen | Filament | sha |
|------|------|--------|----------|-----|
| 1 | 154 s | 2 746 185 | 38 903.29 mm | `ab0704c7…` |
| 2 | 153 s | 2 747 284 | 38 906.23 mm | `9a04d5a9…` |
| 3 | 153 s | 2 834 114 | 39 224.94 mm | `e1a84d6e…` |

**Alle drei shas sind verschieden** — Auryn mit `--threads 1` ist am
Poco **nicht reproduzierbar**. Lauf 3 trifft zufaellig die dominante
Default-Variante (`e1a84d6e`), Laeufe 1 und 2 produzieren die vorher
"seltene" niedrige-Filament-Range (38 903-38 906 mm) in zwei weiteren,
unter sich auch nicht identischen Varianten.

Zum Vergleich x86 (`--threads 1`, 94 s): 2 826 766 Zeilen, 39 223.579
mm, sha `adefd3a5…`. x86 ist deterministisch; arm64 bleibt
non-deterministisch.

### 5. Haeufigkeit der "seltenen 3." Auryn-Variante (nur notiert)

Hintergrund: in Runde 1 war sha `8a50e806…` (38 906.85 mm) ein
einmaliger Ausreisser, in Runde 2 nicht reproduziert.

Jetzt (Runde 3) in 3× `--threads 1`-Laeufen:
- 2× in der niedrigen Range (38 903 & 38 906 mm, zwei verschiedene
  shas, keine davon = `8a50e806…`)
- 1× in der hohen Range (39 224.94 mm, sha `e1a84d6e…`)

Das heisst: die "niedrige Filament"-Range tritt bei `--threads 1`
offenbar HAEUFIGER auf als bei Default-Multi-Thread. Vermutung
(nicht geprueft): die beiden Ranges entsprechen zwei verschiedenen
Perimeter-Sort-Entscheidungen, deren Praevalenz von der Thread-Zahl
abhaengt. Weiter nicht gejagt wie von Klaus vorgegeben; nur
dokumentiert.

### Was aendert sich im Repo

- `engine/cli/handslice-cli.cpp`: `tbb::global_control` auf
  `tbb::task_arena(N)` + `arena.execute(fn)` umgestellt. Default-
  Pfad (ohne `--threads`) ist unveraendert.
- Beide CLIs neu gebaut (x86 und arm64) am aktuellen Commit.
- Keine App-Aenderung, kein APK-Build (CLI-Diagnostik, keine
  User-Facing-Feature-Aenderung).

### Was heisst das fuer die Roehren-Pflicht

- **x86**: Byte-Gleichheit zu Orca-GUI ist jetzt in jedem Modus
  erfuellt. Phase C strikt bestanden.
- **arm64**: Byte-Gleichheit zu x86/GUI ist auch mit `--threads 1`
  nicht erreicht. Non-Determinismus ist NICHT TBB-Scheduling (durch
  Arena-Fix ausgeschlossen); Ursache liegt tiefer (ASLR,
  Hash-Container-Reihenfolge, libc++ sort — alles Hypothesen).
- Weitere Diagnose waere der TSan-Weg aus Runde 2 oder gezieltes
  Instrumentieren der Perimeter-Sort-Call-Sites in Orca.
- **Entscheidung an Klaus**: Roehren starten (mit arm64-Bimodalitaet
  dokumentiert) oder weitere arm64-Jagd?

Nichts gepusht. Nothing committed in app/; kein APK.

## 2026-11-01 21:30 UTC – arm64/x86 Divergenz, zweite Runde: Hang-Ursache + FMA-Hypothese

Vier präzise Prüfungen nach Klaus' Rückfrage. Keine App- oder
CLI-Verhaltensänderung; nur ein zusätzliches Experimental-Build-Skript
`engine/build-cli-arm64-fpoff.sh` und Doku.

**Nachtrag zum vorigen Bericht**: "funktional korrekt" war unbelegt
und wird hier nicht wiederholt — der Auryn-Lauf aus der ersten Runde
war ein seltener Außen­seiter (sha 8a50e806, 38 906 mm Filament).
Reproduktion mit drei Fresh-Läufen zeigt, dass arm64 normalerweise
*näher* an x86 landet (Details unten).

### 1. Hängt `--threads < N` auch auf x86?

Ja. x86 AMR5-Host: `--threads 1`, `--threads 2`, `--threads 4` hängen
jeweils 60 s im Timeout. Also **kein arm64-Spezifikum, sondern unsere
Nutzung von `tbb::global_control`**.

Stacktrace vom x86-Hang (gdb-gestarteter Prozess, Interrupt nach 15 s):
```
#0 __futex_abstimed_wait_cancelable
#1 pthread_cond_wait
#2 std::condition_variable::wait
#3 tbb::detail::d1::start_for<…lambda…>::execute
#4 tbb::detail::r1::task_dispatcher::local_wait_for_all
#5 tbb::detail::r1::task_dispatcher::execute_and_wait
#6 Slic3r::name_tbb_thread_pool_threads_set_locale
#7 Slic3r::Print::process
```

**Belegstelle in Orca**: `engine/OrcaSlicer/src/libslic3r/Thread.cpp
:212-247`. Die Funktion macht:

```cpp
const size_t nthreads_hw = tbb::this_task_arena::max_concurrency();  // :222
size_t       nthreads    = nthreads_hw;
...
tbb::parallel_for(
    tbb::blocked_range<size_t>(0, nthreads, 1),                     // :236
    [&](const tbb::blocked_range<size_t>&) {
      if (++nthreads_running == nthreads) cv.notify_all();          // :239
      else cv.wait(lk, [&]{return nthreads_running == nthreads;});  // :246
      ...
    });
```

Der Haken (Vermutung, mit Beleg plausibel, aber nicht formal
bewiesen): `tbb::this_task_arena::max_concurrency()` liefert die
Arena-Kapazität (= HW-Cores), **nicht** die durch
`tbb::global_control(max_allowed_parallelism, N)` erzwungene aktive
Thread-Zahl. Die `parallel_for` queued HW-viele Tasks, aber nur N
davon laufen gleichzeitig. Die ersten N-1 Tasks sitzen in `cv.wait`
und warten auf die restlichen HW-N Tasks, die mangels Worker nie
starten. Deadlock.

**Konsequenz für uns**: `--threads < HW-Cores` ist mit diesem Orca-
Pin strukturell blockiert. Betrifft x86 (`N < 16`) und arm64
(`N < 8`) gleichermaßen. **Nicht unser Fehler**, sondern Orcas Code,
aber ohne Orca-Patch nicht umgehbar.

### 2. FMA-Hypothese per `-ffp-contract=off`-Build geprüft

**Build-Flags im Standardbuild** (für `src/libslic3r/libslic3r.a`):

| Arch | Compiler | Relevante Flags (gefiltert) |
|------|----------|-----------------------------|
| x86  | `/usr/bin/c++` (GCC) | `-O3 -DNDEBUG -fPIC -fsigned-char` + Warnungen |
| arm64 | `aarch64-linux-android29-clang++` (NDK r27d) | `-g -DANDROID -fdata-sections -ffunction-sections -funwind-tables -fstack-protector-strong -D_FORTIFY_SOURCE=2 -O3 -DNDEBUG -fPIC -fsigned-char` + Warnungen |

Keine Seite setzt `-ffp-contract` explizit → GCC-Default auf x86 ist
`fast`, Clang-Default (Android-Target) ist `on`. Beide erlauben FMA.

**Experimental-Build**: `engine/build-cli-arm64-fpoff.sh` erzeugt
`engine/bin/handslice-cli-arm64-fpoff` mit `-ffp-contract=off`
eingezogen über `sed -i` ins `build.ninja` (272 FLAGS-Zeilen
getroffen, CMake-Weg war unwirksam weil Orcas CMakeLists.txt
`CMAKE_CXX_FLAGS_INIT` überschreibt). **Default-Build bleibt
unangetastet.**

Messergebnis (Würfel 10×, Poco):

| Modus | Variante A | Variante B | Shas |
|-------|-----------|-----------|------|
| arm64 default | 8/10 (8479 Z) | 2/10 (8321 Z) | `a30ffec3` / `7c88f484` |
| arm64 fpoff | 9/10 (8482 Z) | 1/10 (8326 Z) | `82d1c1db` / `7ada37b6` |

`-ffp-contract=off` erzeugt **andere** Shas als der Default-Build und
**nähert sich der x86-GUI-Referenz `92951c26…` nicht an**. Die
Bimodalität bleibt. Filamentwerte liegen ähnlich nah an x86
(1177.1511 mm fpoff vs. 1177.1516 mm default vs. 1177.1511 mm x86 —
alle innerhalb 0.5 µm).

Auryn-fpoff (1 Lauf): 76 s, 2 833 930 Z, 39 224.87 mm, sha
`75d6a7f1…`. Nahe am dominanten arm64-Default-Variant A (39 224.94
mm), aber eigenes sha. Keine Konvergenz zu x86's 39 223.58 mm.

**Fazit (Vermutung bleibt Vermutung)**: Die FMA-Hypothese ist durch
dieses Experiment **nicht gestützt**. Abschalten verändert die Zahlen
(dritte und vierte stabile Variante), bringt arm64 aber nicht in
Byte-Deckung mit x86. Konsistent mit der älteren
`engine-integration.md:679-682`-Beobachtung, dass die
abweichenden Zahlen *nicht* ULP-nah zueinander sind — Spiegel/Rotations-
Swap statt FP-Rundung. Nicht endgültig widerlegt (fpoff deckt nicht
jede FP-Nuance ab), aber keine Entlastung des Signals.

### 3. Auryn-Reproduzierbarkeit: 3× arm64 default

| Lauf | Zeit | Zeilen | Filament | Sha |
|------|------|--------|----------|-----|
| 1 | 80.68 s | 2 834 114 | 39 224.94 mm | `e1a84d6e…` |
| 2 | 77.75 s | 2 834 114 | 39 224.94 mm | `e1a84d6e…` |
| 3 | 77.45 s | 2 832 521 | 39 220.36 mm | `e4f28cab…` |

Auch Auryn **bimodal**: Variante A 2/3, Variante B 1/3. Filament-Diff
zwischen A und B: 4.6 mm (0.012 %). Zu x86 (39 223.58 mm):
A liegt +1.4 mm drüber, B liegt -3.2 mm drunter.

**Nachtrag zum vorigen Bericht**: Der erste Auryn-Lauf gestern
(sha `8a50e806…`, 2 408 014 Druckbefehle, 38 906 mm) war ein
seltener dritter Variant. Die typische arm64-Auryn-Ausgabe liegt
innerhalb von 5 mm Filament und 90 % textgleicher Druckbefehle
zum x86-Slice. Die "317 mm Divergenz" aus dem gestrigen Bericht ist
ein **Außenseiter-Vergleich**, nicht die typische Divergenz.

Textgleiche Druckbefehle (dominanter arm64-Variant vs. x86):

- x86: 2 464 570 Zeilen
- arm64 (sha `e4f28cab…`): 2 468 810 Zeilen
- textgleich (sortierte Intersection): **2 219 457 (90 %)**

Die Divergenz auf Auryn ist in der Größenordnung ähnlich wie am
Würfel (84-92 % textgleich je nach Variant und Metrik), nicht
dramatisch anders.

### 4. ThreadSanitizer-Vorschlag (nur Konzept, nicht umgesetzt)

Falls die FMA-Hypothese verworfen bleibt, der nächste Diagnose-Weg
wäre ein TSan-Build der x86-Version:

- `-fsanitize=thread` beim Compile+Link; libslic3r und
  handslice-cli neu bauen, Deps mit Normalbuild lassen (TSan ist in
  Deps nicht nötig).
- Laufzeit-Overhead: 5-15× Verlangsamung, 5-10× Speicher-Overhead
  (Shadow-Memory). Würfel 1 s → ~15 s. Auryn 22 s → **~5-10 min**
  pro Lauf.
- Ziel: Melden, ob zwischen den TBB-Workern unsynchronisierter
  Memory-Zugriff passiert. Wenn ja (Vermutung), hätten wir eine
  Belegstelle für Orcas Perimeter-/TopInfill-Code.
- Aufwand grob: 1-2 Werktage für Setup (TSan-Build-Skript, Patches
  für `-fsanitize=thread`-Propagation zu allen libslic3r-Deps-Links,
  Suppression-File für bekannte TBB-interne Races), + 1 Tag für
  Analyse der Reports.
- **Wichtige Einschränkung**: TSan findet nur echte Memory-Rennen,
  nicht Scheduling-Reihenfolge-Nondeterminismus auf serialisierbaren
  Datenstrukturen. Falls die Divergenz **ausschließlich** aus
  `std::sort`-Instabilität + TBB-Partitionierung kommt (ohne shared-
  state-Rennen), schweigt TSan. In dem Fall wäre der nächste Schritt
  gezieltes Instrumentieren der Perimeter-Sort-Call-Sites (ein
  deterministisches Logging) — weitere 1-2 Tage.
- Vermuteter Ertrag: 50/50. Falls nichts gefunden wird, ist der Weg
  "Orca-Upstream-Patch mit Tie-Break-Regel" wahrscheinlich der
  einzige verbleibende, wie `engine-integration.md:620-625` ohnehin
  andeutet.

### Was heißt das für die Röhren-Pflicht

- Byte-Gleichheit arm64 ↔ x86 ist mit unseren Mitteln (Thread-Zahl,
  Core-Pinning, FMA aus) **nicht erreichbar**.
- Die typische arm64-Abweichung zum x86-Slice ist 1-5 mm Filament
  (0.01 %), 90 % textgleiche Druckbefehle. Zwei stabile Varianten je
  Modell. **Nicht als "funktional korrekt" belegt** — nur "nahe am
  x86-Slice, nicht byte-gleich, bimodal".
- Phase-C-Entscheidung aus `engine-integration.md:601-619` bleibt
  wie dort formuliert: ±-Toleranzen und dokumentierte Varianten
  gelten als Erfolg. Byte-Gleichheit ist Fernziel.

Nichts an der App oder am Standard-CLI geändert. Experimental-
Binary `handslice-cli-arm64-fpoff` liegt nur lokal; APK und
`handslice-cli-arm64` sind unverändert.

## 2026-11-01 20:53 UTC – arm64/x86 Divergenz: Thread-Probe am Poco

Vor den Röhren hat Klaus die arm64/x86-Divergenz als Blocker eingeordnet
und einen Ein-Kern-Test angesetzt. Ergebnisse unten, alle Zahlen vom
Poco X3 Pro mit CLI `f958b1b` (arm64) und AMR5-Host (x86).

### Vorarbeit: `--threads N`

CLI hat bereits ein `--threads N`-Flag (`engine/cli/handslice-cli.cpp
:230-237` parsed; `:876-883` wrappt den Slice mit
`tbb::global_control(tbb::global_control::max_allowed_parallelism, N)`).
Default = unbegrenzt (= physische Core-Zahl). Verwendet TBB 2021.x (Orca-
Submodule-Pin).

### Experiment-1: hängt `--threads 1-7` noch?

Erwartung aus `docs/engine-integration.md:729-741`: `--threads 1` hing
beim Erst-Experiment. Jetzt am f958b1b-Build nachgeprüft, 90 s Timeout:

| `--threads N` | Ausgang (Würfel) |
|--------------|------------------|
| 1            | TIMEOUT (3/3)    |
| 2            | TIMEOUT          |
| 3            | TIMEOUT          |
| 4            | TIMEOUT          |
| 5            | TIMEOUT          |
| 6            | TIMEOUT (90 s)   |
| 7            | TIMEOUT (90 s)   |
| **8**        | **Fertig in ~0.8 s** |

Snapdragon 860 hat genau 8 physische Cores (4 Little + 3 Big + 1 Prime).
Jedes `max_allowed_parallelism < 8` hängt in Orcas `parallel_pipeline` —
ein Filter wartet auf einen Worker, der nie kommt. Der Ein-Thread-Weg
ist mit dieser Orca-Version **nicht gangbar**, ohne Orca selbst zu
patchen.

### Experiment-2: 10× Default + 10× `--threads 8` + 10× `taskset f0`

Erfolgsmetrik: sha256 des EXECUTABLE_BLOCK. Zielwert = Orca-GUI-
Referenz `92951c26…` (x86 trifft die immer).

| Modus | Variante A (sha a30ffec3…, 8479 Z) | Variante B (sha 7c88f484…, 8321 Z) | Zeit |
|-------|-----------------------------------|-----------------------------------|------|
| Default | **8/10** | 2/10 | 0.78 – 0.87 s |
| `--threads 8` | 6/10 | 4/10 | 0.78 – 0.87 s |
| `taskset f0` (nur Big Cores: cpu4-7) | 8/10 | 2/10 | 0.70 – 0.74 s |
| `taskset 80` (nur Prime: cpu7) | — | — | <0.1 s / Fehlerexit (wie `--threads 1`) |

Keine der getesteten Varianten erreicht die GUI-Referenz-sha
`92951c26…`. **arm64 bleibt bimodal zwischen den zwei stabilen Varianten
A und B** (Verhältnis 6:4 bis 8:2 je Run-Serie), die bereits in
`docs/engine-integration.md:755-761` dokumentiert sind. Beide Varianten
sind funktional korrekt (Zeilen-, Material- und Zeit-Stats identisch
innerhalb der Phase-C-relaxierten ±-Toleranzen).

### Experiment-3: Auryn (asymmetrisch, 2.4 M Druckbefehle)

| Modus | Wall-Clock | `total_filament_used_mm` |
|-------|-----------|--------------------------|
| x86 default | **22 s** | 39 223.579 mm |
| arm64 default | **73 s** (3.3× x86) | 38 906.853 mm |
| arm64 `--threads 1` | hängt (nicht gelaufen) | — |

Diff der reinen Druckbefehle (Kommentare raus) nach sortierter
Intersection:

- x86: 2 464 570 Zeilen
- arm64: 2 408 014 Zeilen (56 556 weniger)
- Zeilen in beiden Dateien (textgleich, Position egal): **2 078 508 (84 %)**
- Nur in x86: 386 062 (15.7 %)
- Nur in arm64: 329 506 (13.7 %)

Auf dem asymmetrischen Modell ist die Divergenz **größer** als am Würfel
(dort 92.4 % textgleich) — die Symmetrie-Hypothese aus
`engine-integration.md:716-721` erweitert sich: auch die zufällige
Scheduling-Auswahl zwischen zwei Lokal-Optima trifft an jeder Perimeter-
Ecke wieder zu, nicht nur an der x=y-Diagonale.

Filament-Divergenz: 316.7 mm (0.8 %) auf Auryn vs. 0.0005 mm auf dem
Würfel. Auf dem Würfel sind die beiden Varianten geometrisch gleich-
wertig (Spiegelung, selbe Weglänge); auf Auryn sind die beiden
TBB-Pfade sichtbar unterschiedlich lang.

### Was heißt das für den Byte-Gleichheits-Weg?

- `--threads 1` ist auf diesem Orca-Pin blockiert (parallel_pipeline wait-
  for-worker). Erforderte Orca-Patch, nicht autonom machbar.
- `taskset`-Beschränkung ändert nur die OS-Core-Auswahl, nicht die TBB-
  Scheduling-Reihenfolge → gleiche Bimodalität.
- Max-Thread-Reduktion auf `n_physical_cores` ohne Patch hilft nicht.
- Byte-Gleichheit bleibt wie in `engine-integration.md:620-625`
  **Fernziel** mit Orca-Patch (eindeutige Tie-Break-Regel in den
  betroffenen Perimeter-Sort-Keys).

Phase C bleibt funktional (±-Metriken erfüllt, 2 Varianten dokumentiert).
Keine App-Änderungen gemacht; nur gemessen und berichtet. Keine Tests
gefährdet (`flutter test` nicht gelaufen — nichts in app/ geändert).

Punkte 2 (flutter_scene-Belege + Würfel-Pipes-Probe) und 3 (LOD-
Zuweisung) warten auf Klaus' Entscheid.

## 2026-11-01 19:17 UTC – Pflicht 7d (follow-up 8) + Pflicht 7e plan

Two small polish items on the card / legend, then a plan-only
pass on tubes (no code).

Weight proof (why 3.52 g, which density / which length):

- Density = **1.25 g/cm³**. Chain: `Elegoo PLA @ECC2 → Elegoo
  PLA @base`, `filament_density: ["1.25"]`
  (`engine/OrcaSlicer/resources/profiles/Elegoo/filament/BASE/
  Elegoo PLA @base.json`).
- Diameter = **1.75 mm**. Chain continues to
  `fdm_filament_common` (Elegoo),
  `filament_diameter: ["1.75"]`.
- Formula `weight_g = extruded_mm × π·(d/2)² × density × 1e-3`
  (direct port of `OrcaSlicer/src/libslic3r/GCode/
  GCodeProcessor.cpp:1626-1628`: `s = π·(0.5·d)²`,
  `weight = volume · density · 0.001`).
- "3.52 g" ⟵ 1172 mm · 2.4053 · 1.25 · 0.001 = 3.524 g
  (Orca Path B — `stats.total_used_filament`,
  `GCode.cpp:1914-1936`). This is Orca's own GUI number
  (`GCodeViewer.cpp:4605`).
- "3.54 g" ⟵ 1177.15 mm · 2.4053 · 1.25 · 0.001 = 3.539 g
  (Path A — g-code footer / HSPT dE sum).

Fix: CLI's `emit_statistics` now reads `stats.total_used
_filament` + `stats.total_weight` directly (reverting the
follow-up-7 HSPT-dE-sum override). HSPT bumps to **v3** with
two additional header fields `total_filament_mm` +
`total_weight_g`, both populated from Orca's Path B. The
legend's "Total Filament" row reads them from the HSPT
header, so the project card and the legend show the same
number from the same source. One wire for two displays.

Time format unified on short_time (no spaces):

- Legend already used `9m25s` style.
- Card used `estimatedTimeFmt` from CLI stats = Orca's
  `get_time_dhms` with spaces → "9m 25s".
- `_fmtDuration` moved into `widgets/format.dart` as
  `formatDurationShort`. Mirrors `short_time(get_time_dhms(
  seconds))` from `OrcaSlicer/src/libslic3r/Utils.hpp:494-537`,
  the formatter Orca's own "Total time" row uses
  (`GCodeViewer.cpp:4023`). Both cards format
  `estimatedSeconds` through it — "9m25s" everywhere.
- 10 new tests pin the formatter against cube, Auryn and
  edge cases (minute-rounding, days bucket).

Pflicht 7e plan (NO CODE) — written into
`docs/layer-view.md` under "Pflicht 7e plan — toolpath
pipes (tubes)":

- How Orca draws its pipes: instanced octahedral-prism
  template (`SegmentTemplate.cpp:18-27`, 8 vertices and 8
  triangles) rendered via `glDrawArraysInstanced`
  (`:72-83`). Vertex shader fetches endpoint positions,
  `(height, width, corner_angle, bias)` and colour from
  texture buffers and expands the template per vertex.
- Width/height/direction per move: `v.width` / `v.height`
  per extrude vertex; travels get `travels_radius`.
  `atan2(prev × curr, prev · curr)` per vertex for the
  twist-fix at corners. Bias isolates options from z-fight.
  `OrcaSlicer/src/libvgcode/src/ViewerImpl.cpp:954-981`.
- Lighting: ambient 0.2, emission 0.15, top + front
  directional lights, blinn-phong-ish specular. All in the
  vertex shader (`Shaders.hpp:13-48`).
- HSPT sufficiency: v3 already carries width_x100,
  height_x100 at 0.01-mm resolution — same precision Orca
  uses. **No format bump for 7e.**
- flutter_scene fit: `InstancedMesh` + `ShaderMaterial` are
  both available in 0.24.3. Build pipeline through
  `flutter_gpu_shaders` 0.5.2. 32 B / instance.
- Poco budget: cube is trivial (100 KB). Auryn full-print
  ~68 MB instance buffer, ~17 M vertices / frame → ~18 fps on
  Adreno 640 (lower bound). Slider-position mode (~1 M
  instances) lands ~35 fps. LOD escape hatch mirrors Orca's
  `top_layer_only_view_range` at
  `OrcaSlicer/src/libvgcode/src/ViewerImpl.cpp:1234-1244`:
  tubes for the top layer only, thin lines for the stacked-
  below.
- Device acceptance list: reference-image parity on cube
  layer 52, corner-join inspection, Auryn scrub ≥ 20 fps,
  PSS < 500 MB, LOD visibly kicks in on degraded path.

Test headline: 190 of 190 pass (added 10 for
`formatDurationShort`). CLIs rebuilt at 8b8ef43+1 (next commit
is the plan-only). Plan lives in `docs/layer-view.md`; APK
rebuilds will be triggered on Klaus' go-ahead for the actual
pipes work.

## 2026-11-01 18:29 UTC – Pflicht 7d (follow-up 7): one filament number, umlauts, readable sizes

Klaus' finish-pass on the project-tab G-code card.

- **"Filament 1172 mm" vs "1.17 m" vs "1177.15 mm" — one
  source now.** Orca writes TWO different
  `print_statistics.total_used_filament` values and the
  second overrides the first:
    - `GCode.cpp:2358`
      (`update_print_stats_and_format_filament_stats`) sums
      `extruder.used_filament()` which is the extruder motor
      movement — this is Path A, equals the g-code footer
      `; filament used [mm] = 1177.15`.
    - `GCode.cpp:1936`
      (`update_print_estimated_stats`, called at
      `_do_export()` line 2176 AFTER the footer path) sets
      `total_used_filament = sum(volume / cross_section)`
      from `GCodeProcessorResult::print_statistics.total
      _volumes_per_extruder` — Path B, excludes custom-role
      extrudes (purge line) so on the cube it lands at
      ≈1172 mm.
  Our CLI's `emit_statistics` was reading `stats.total_used
  _filament` → Path B → the card showed 1172 mm. The HSPT
  the legend consumes sums positive `delta_extruder` across
  all non-internal Extrude moves → Path A → 1177.15 mm,
  matching the footer.
  Fix in `engine/cli/handslice-cli.cpp:emit_statistics`:
  compute `total_filament_mm` by iterating
  `gcr.moves` the same way the HSPT writer does (skip
  `internal_only`, require `Extrude`, sum positive
  `delta_extruder`) and derive the volume + weight from
  the HSPT's density/diameter header fields. The project
  card now shows the same number the legend does and the
  g-code footer does — one source, zero drift.
  Formatting: card line is now `1.17 m · 3.52 g` (meters
  with 2 decimals, matches the legend's "Total Filament"
  footer); the raw-mm format `1177 mm — 3.52 g` is retired.
  Reference image's `1.17 m · 3.52 g` is Orca's own GUI
  which still uses Path B — the ~5 mm / 0.4 % gap is
  called out in docs so a future reader does not get
  confused.
- **German umlauts.** The ARB file was already clean (no
  `fuer`/`groesse`/etc. hits via the scrubber). The two
  live offenders were hard-coded strings in
  `_SliceSummary`: `'Groesse'` and `'Geschaetzte Zeit'`.
  Moved both to the existing l10n keys `printSizeLabel` /
  `printTimeLabel` (which already read "Größe" / "Geschätzte
  Zeit" in German) and reused those from the Print card
  too. Side-effect: `'G-Code'` and `'Filament'` are now
  `printFileLabel` / `printFilamentLabel`.
- **File size now human-readable.** New helper
  `widgets/format.dart:formatBytes(int, localeTag)` uses SI
  prefixes (base-1000, matches Klaus' "216 KB" / "64,5 MB"
  examples) and `NumberFormat` with the current locale →
  German build renders decimals as commas, English as
  dots. Both the project card and the print card use it.
  Pinned by `format_test.dart` on the two cube/Auryn
  sizes plus the boundary cases.

Test headline: 185 of 185 pass (added 6 for `formatBytes`;
the pre-existing `PrintScreen zeigt Slice-Ergebnis` test
updated to match the new `1.17 m · 3.52 g` line). CLIs
rebuilt at d3943b0+1 and the APK installed on the Poco.
Nothing pushed.

## 2026-11-01 17:41 UTC – Pflicht 7d (follow-up 6): drop silhouette, pin removeAll invariants

Klaus' decision after the d2bb034 device test: "Sichtbar ist
nur, was bis zur gewählten Schicht gedruckt ist – darüber
nichts, kein Schatten, kein Rahmen." Three threads delivered:

- **Silhouette feature removed in full.** Dropped:
    - `ToolpathLayerView._silhouetteVisible` state and
      `_addModelSilhouette` method.
    - The "Model outline" legend row.
    - `ToolpathLayerViewLabels.modelOutline` + the ARB
      entries `layerModelOutline` (en/de).
    - `Toolpaths.objMinX..objMaxZ` + `_isObjectRole` helper
      — they had no other consumer. The layerZ filter the
      old helper enforced is now the exact Orca one
      (`roleCode != custom`, per
      `OrcaSlicer/src/libvgcode/src/Layers.cpp:26`).
  The 7e-backlog line "alpha-translucent model mesh above
  the slider" is **abandoned** — same reason the wireframe
  iterations failed: on a 393-dp phone the shell competes
  with the printed layers for attention. Marked in
  `docs/layer-view.md` with the full argument.
- **Regression guards against scene-node accumulation.**
  Two new tests live in `scene_lifecycle_test.dart`:
    - `no .root.children.clear( in lib — must use .root
      .removeAll() instead` — a grep across `app/lib/` that
      fails CI if the forbidden pattern reappears. The
      pattern comment inside the test is stripped first so
      the mention-not-call stays legal.
    - `buildRoleSegments is idempotent across the Klaus-
      named slider sequence` — walks the exact sequence
      100 → 1 → 52 → 100 → 52 Klaus named, asserts the
      Float32List returned at the final Layer 52 is
      byte-identical to a cold build at Layer 52. Proves
      the data path has no accumulation. (The runtime
      "scene.root.children.length matches cold at Layer 52"
      check needs Impeller, which flutter_test does not
      ship; the grep + idempotence combo is the strongest
      CI-level guard we can mount.)
- **The 1.65 M dropped "internal-only" moves on Auryn,
  explained.** Orca's
  `GCodeProcessor::calculate_time` inserts a parallel
  "actual speed" clone next to every real move at
  `OrcaSlicer/src/libslic3r/GCode/GCodeProcessor.cpp:5962-
  5984` (the clone sets `new_move.internal_only = true` at
  :5983). It carries the same role / layer_id / position as
  the real move but with `actual_feedrate` set to the
  acceleration-adjusted speed, so Orca's `ActualSpeed` view
  can paint the two speeds side by side. We do not
  implement `ActualSpeed`, so each clone would be a
  duplicate vertex: summed `delta_extruder` would triple;
  the viewer would see overlapping segments.
  `handslice-cli.cpp:552-564` drops them at HSPT write
  time. Orca itself also hides them from the Line-Type
  legend statistics
  (`OrcaSlicer/src/slic3r/GUI/GCodeViewer.cpp:1318-1320`
  early-outs on `move.internal_only` before updating
  `m_move_type_counts/_times/_distances`). Full write-up
  in `docs/layer-view.md` under "Internal-only move filter".

Test headline: 179 of 179 pass (added 3). CLIs rebuilt at
d2bb034+1 and the APK installed on the Poco. Nothing pushed.

## 2026-11-01 16:56 UTC – Pflicht 7d (follow-up 5): fix scene accumulation (children.clear ≠ unmount)

Klaus (b23e962 device run) saw the whole cube — notch,
`topSolidInfill` surface and all — at slider Layer 52, even
though parser-side invariants swore nothing with
`layer_id > 51` was being emitted. Root-caused as a
flutter_scene API misuse.

- **Root cause.** `scene.root.children.clear()` is a plain
  `List<Node>.clear()`; it does **not** run `Node.remove`'s
  unmount path. The old `_renderItems` stay registered in
  `renderScene` and keep drawing. Every slider change
  therefore STACKED the new layer on top of the previous
  one. Since `initState` sets `_currentLayer = layerCount -
  1` (= Layer 100), the very first frame registered the full
  print; subsequent drags added more segments without
  taking the Layer 100 ones out. Reference in flutter_scene
  0.24.3: `src/node.dart:1341-1352` (`remove(child)` calls
  `child._unmount()`), `:1355-1358` (`removeAll()` iterates
  `remove`), vs. `:1286` (`children` is just a `List<Node>`
  with no behavior).
- **Fix.** `scene.root.removeAll()` in all four scene-owning
  callsites:
    - `widgets/toolpath_layer_view.dart:_rebuildScene`
    - `widgets/layer_view.dart:_rebuildScene`
    - `widgets/plate_view.dart:_rebuildScene`
    - `screens/plate_bench_screen.dart:_rebuildSceneUnsafe`
- **Scene-level pin.** Extracted the per-role segment-build
  into a pure helper `buildRoleSegments(t, roleCode, from,
  to)` in `toolpath_parser.dart`. `_emitRole` now calls it —
  one path, so the test exercises what the renderer sees.
  New test `scene emit: positions handed to the renderer at
  Layer 1/52/100 obey the slider` iterates every role, pins:
    - `maxZ(positions) ≤ layerZ[current0] + 0.01` for every
      role at every tested slider position.
    - `topSolidInfill` (bright red `0xFFF04040`) emits
      **zero** segments at Layer 52 — the smoking gun from
      the device test.
- **Device gegenprobe.** Pre-fix `adb exec-out screencap`
  captured Klaus' chat app foreground (not Handslice), so no
  usable before/after was gathered on this run. The fix
  landed anyway because the parser-level + scene-level
  invariants both pin it.
- **No API change.** Only internal `_emitRole` signature was
  thinned; `buildRoleSegments` is additive and tested.

Test headline: 178 of 178 pass (added 1). CLIs rebuilt at
b23e962+1 and the APK installed on the Poco. Nothing pushed.

## 2026-11-01 16:30 UTC – Pflicht 7d (follow-up 4): confirm no layer cap, sweep Auryn (1045 layers)

Klaus asked whether the layer-view has a hard upper limit and
to run the all-layer sweep on a large print too.

- **No hard limit under 65535.** HSPT wire caps `layer_id` at
  `u16` (handslice-cli.cpp:514, :582 — Orca itself clamps
  there in `wu16((m.layer_id > 65535u) ? 65535u : m.layer_id)`).
  Dart has no fixed-size state: `layerStarts` is a
  `Uint32List`, `layerZ` a `Float32List`, both sized at parse
  time from `t.layerCount`. Slider `divisions` scales to the
  layer count. The only sanity cap is `(t.layerCount - 1)
  .clamp(0, 1 << 30)` — ~1 B, three orders of magnitude above
  the HSPT limit. Documented in `docs/layer-view.md` under
  "No hard upper layer limit".
- **Auryn as the 67 MB stress + large-print proof.** Ran the
  CLI's standalone mode on the existing local file:
  ```
  handslice-cli-x86 --input-gcode local-test/auryn-x86.gcode \
    --export-toolpaths local-test/auryn.hspt
  ```
  → 2 113 471 moves, **1045 printed layers**, 67.6 MB HSPT,
  25 883 s = **7h 11m 23s** total time. Density/diameter
  come through at 1.25 / 1.75 (same as cube).
- **Sweep tests on Auryn.** Four new tests, all gated on
  `local-test/auryn.hspt`:
    - `Auryn HSPT loads and reports a plausible layer count`
      — bounds the parse (> 500 k moves, > 500 layers,
      > 100 mm total height, > 1 h time).
    - `Auryn: EVERY slider position matches the gcode
      ;LAYER_CHANGE/;Z: pair` — rebuilds the ground truth
      list (1045 entries) from the g-code and compares
      against `t.layerZ[N-1]` for every N=1..1045 within
      0.001 mm.
    - `Auryn: EVERY slider position: only moves with
      layer_id ≤ N-1 are drawn` — uses `prefixMax` and
      `suffixMin` sweep tables so the O(N²) check reduces to
      O(1) per layer; passes on 2.1 M records in well under
      a second.
    - `Auryn: layerStarts strictly monotonic — slider ± 1
      lands on a distinct layer`.
- **Slider ± 1 affordance.** Pinned on both prints: the
  IconButton `-`/`+` calls `_setLayer(value ± 1)` which maps
  directly to `layerStart`, so monotonic bin starts guarantee
  the user reaches every individual layer. On Auryn the
  slider track is ~150 dp with 1045 divisions ≈ 0.14 dp per
  tick — drag resolution is coarser than one layer, but the
  `-`/`+` buttons are exact.

Test headline: 177 of 177 pass (added 5). CLIs rebuilt at
efa065a9f3+1 and the APK installed on the Poco. Nothing
pushed.

## 2026-11-01 16:16 UTC – Pflicht 7d (follow-up 3): sweep tests across every slider position

Klaus asked for layer-coverage proof over the whole slider,
not just stichprobenartig. Added four tests (all pin on the
thumbnail cube, 100 printed layers) plus a Z-hop synthetic
test on hand-rolled HSPT:

- `EVERY slider position 1..layerCount matches the gcode
  ;LAYER_CHANGE/;Z: pair` — rebuilds the ground truth from
  the g-code's `;LAYER_CHANGE` + `;Z:` pairs (which is what
  Orca's slider reads), then compares against our
  `t.layerZ[N-1]` for every N=1..100 within 0.001 mm. The
  test name is explicit about the convention: displayed N is
  1-based, internal `current0 = N-1` is 0-based.
- `EVERY slider position 1..layerCount: only moves with
  layer_id ≤ N-1 are drawn` — for every N=1..100, asserts
  `maxLayerIdIn(0, layerEnd(N-1)) ≤ N-1` and (for
  N < layerCount) `min layer_id above the cutoff > N-1`.
  Plus the drawn+skipped == totalMoves sanity.
- `edge — first slider position (Layer 1) includes the
  skirt / purge-line extrudes` — on the thumbnail cube
  `skirt_loops = 0`, so the purge line is Orca's start-
  g-code with `role = custom` (18). It lands in bin 0, so
  it IS drawn at Layer 1. The test asserts there are > 0
  extrudes at `layerEnd(0)` AND among them some are
  role=custom.
- `edge — last slider position (Layer N) draws everything;
  nothing above` — pins `layerEnd(99) == moveCount` and
  `layerZ[99] ≈ 20.0 mm`.
- `Z-hop above the layer height does not shift layerZ or
  layerCount` — synthetic HSPT with a travel at z=0.6
  during layer 0 (extrude at z=0.2) and a travel at z=0.4
  before layer 1's extrude. Asserts bins stay at 2 and
  `layerZ[0]=0.2, layerZ[1]=0.4` — the 0.6-mm hop stays off
  the slider label. The `maxZ` bbox is also pinned to the
  real print height.

Test headline: 172 of 172 pass (added 5). CLIs rebuilt at
91a3060+1 and the APK installed on the Poco. Nothing pushed.

## 2026-11-01 16:00 UTC – Pflicht 7d (follow-up 2): silhouette default-off, layer-cutoff test, red-area explained

Device test on 409e425 said the grey AABB wireframe is still
too busy on the phone. Three deliverables:

- **Silhouette hidden by default.** `_rebuildScene` no longer
  calls `_addModelSilhouette` unconditionally. A new
  `_silhouetteVisible` state defaults to `false`; a new
  "Model outline" row in the legend's options block
  (German: "Modellumriss") toggles it, same visibility
  pattern as Travel / Wipe / Retract / Unretract / Seam.
  Added `layerModelOutline` ARB entry (en/de), threaded
  through `ToolpathLayerViewLabels` and `project_screen`.
  Docs note that porting Orca's real translucent STL shell
  stays in the 7e backlog — flutter_scene has no blend-mode
  hook on `UnlitMaterial`.
- **Layer-cutoff invariant pinned.** New parser helpers
  `maxLayerIdIn(t, from, to)` and
  `countOfMoveTypeIn(t, from, to, type)`. New test
  `Layer 52 draws only moves with layer_id ≤ 51` asserts the
  exact counts on the thumbnail cube: 2674 moves drawn
  (1626 extrudes), 2800 skipped. A regression that leaks
  upper-layer extrudes into the frame now fails CI instead
  of surfacing as a visual bug.
- **"Red area at the top of the viewport" — belongs to
  layer ≤ 52.** At Orca Layer 52 the drawn set contains 833
  `internalInfill` extrudes (role 4, Orca dark red
  `0xFFB03029`), 17 of them at `z=10.40` mm = the current
  layer. `topSolidInfill` (role 6, bright red
  `0xFFF04040`) does not appear until near Layer 100, so no
  "red" leaks in from above the slider. New test
  `at Layer 52 the dominant drawn role is internalInfill
  (red)` locks in the count. Reported in detail in
  `docs/layer-view.md` under "What is drawn vs skipped" and
  "The red top area at Layer 52".

Test headline: 167 of 167 pass. CLIs rebuilt at
409e425+1 and the APK installed on the Poco. Nothing
pushed.

## 2026-11-01 15:31 UTC – Pflicht 7d (follow-up): silhouette grey, filament totals, by-time %, compact legend

Device test on 66e7c46 landed four follow-ups; all fixed below
with Orca source references.

- **Silhouette shell.** Dark-cyan 0.3-mm wireframe looked
  opaque enough to swallow the current layer. Rebrushed to
  light cool-grey `(0.78, 0.80, 0.82)` at 0.1-mm width over
  the object-only AABB. Orca's real shell is a 20 %-alpha
  mesh (`GCodeViewer.cpp:240` `set_color({1,1,1,0.5})` ×
  `GLCanvas3D.hpp:1017` `set_shell_transparence(alpha=0.2f)`
  × `GCodeViewer.hpp:266` `set_shell_transparency(alpha=
  0.15f)`); flutter_scene's `UnlitMaterial` has no public
  blend-mode hook so a real translucent mesh is 7e scope —
  the thin light-grey wireframe is the hint we can draw now.
  Docs call this out explicitly.
- **"Total Filament" was summing path length.** The box
  showed 36.24 m on the cube; Orca shows 1.17 m. Our
  `totalLengthMm` is the Euclidean sum of extrude path
  lengths — Orca's total uses *extruded filament* length,
  which is already what `extrudedMm` carries (positive sum
  of per-move E-deltas, equal to the g-code's `; filament
  used [mm]` footer within 0.001 % on the cube). The
  "Total estimation" box now uses `extrudedMm / 1000`.
  Reference: `GCodeViewer.cpp:3443-3448`
  `get_used_filament_from_volume`.
- **Legend semantics audited against Orca.** Three calls
  were wrong on the 7d run:
    - **"Length" per role** = extruded filament metres
      (`extrudedByRole[r] / 1000`), not path metres. Orca
      ref: `GCodeViewer.cpp:3432-3440` `used_filament_per_
      role` → `model_used_filament_m`.
    - **%** = by time, not by length. Orca ref:
      `GCodeViewer.cpp:3410-3418` `role_time_and_percent`
      / `travel_time_and_percent`. Inner wall on the cube:
      94.7 s / 561 s ≈ 16.9 %, matching the reference.
    - **Role time** is extrude-only. Travel / wipe /
      retract / unretract / seam carry their own time via
      `timeByMove`, and get Time + % + distance + count in
      their rows (Orca ref: `GCodeViewer.cpp:3797-3812`
      `option_stats`). Without the extrude-only filter per-
      role sums would already equal 9m25s and the option
      rows would double-count to ≈ 11 min — exactly the
      11-min figure Klaus flagged on the device.
  Parser grew `timeByMove`, `distanceByMove`, `countByMove`
  mirroring Orca's `m_move_type_times` / `_distances` /
  `_counts`. `timeByRole` is now filtered to
  `MoveType.extrude`.
- **Layout at 393 dp.** % broke to two lines and names
  ellipsised ("Innenwa…"). Rebuilt the legend as a dedicated
  `_LegendTable` with fixed-width columns (14 + 14 + 40 +
  32 + 50 + 44 = 194 dp fixed, ≈ 150 dp left for the name
  under the project card's 32-dp horizontal padding), 11-pt
  monospace, and no space between numbers and units
  (`0.07m`, `0.21g`) — matches `GCodeViewer.cpp:3653-3655`
  (`%.2fm`, `%.2fg` via `format_compact_weight`). "Außenwand"
  and "Innenwand" now fit on one line.

Follow-ups queued for 7e (unchanged):
- Tubes with per-move width AND height.
- Real translucent model-mesh shell above the slider.
- Range-within-layer slider + G-code excerpt.
- 67 MB stress test on the Poco.

## 2026-11-01 15:03 UTC – Pflicht 7d: silhouette, numbering, grid, legend totals

Follow-up to the 04684c0 device test. Five fixes land here;
the pipe-ribbon shader, in-layer slider and 67 MB stress test
move to the next slot.

- **Silhouette now uses the object AABB, not the whole-print
  bbox.** The teal "model-still-to-come" box over the current
  layer was sized by `t.minX..maxZ`, which includes the purge
  line at (127, -1.2) and the 10 mm brim — so the box dwarfed
  the model. New fields on `Toolpaths`: `objMinX..objMaxZ`,
  computed only over extrude moves whose role is NOT skirt,
  brim, wipe tower or custom. The silhouette is also dimmer
  (0.22, 0.42, 0.42, 1) and thinner (0.3 mm) to read as faded,
  since `flutter_scene`'s UnlitMaterial has no real alpha
  channel to lean on.
- **Layer numbering now matches Orca.** Our slider showed 53
  at z = 10.40 mm; Orca's reference screenshot
  (`local-test/orca-referenz-schicht52.png`) shows 52. Root
  cause: HSPT bins 0..99 for a 100-layer cube, but each bin's
  `layerZ` was set to the FIRST move's z — which is a retract
  still at the previous layer's z (Orca emits `;LAYER_CHANGE`
  before the trailing retract). So bin 52 was labelled z=10.4
  when the extrudes actually land at 10.6. Parser now mirrors
  `libvgcode::Layers::update` and uses the LAST non-custom
  object-extrude's z. Pinned by a new test
  (`layerZ tracks the latest object-extrude z, not retracts`)
  and by a real-cube check that `layerZ[51] ≈ 10.40`.
- **Plate label in Model view too.** `PlateView` grew a
  `plateLabel` parameter and wraps the viewport in the same
  "A · Textured — 256×256×256 mm³" overlay that `ToolpathLayer
  View` already shows. Project screen passes the current bed
  type.
- **Bed grid.** `addBedToScene` now emits minor 10-mm and
  major 50-mm grid lines (two `LineSegmentsGeometry`, unlit
  `displayReferred` so the greys read as sRGB). Lives 0.03 mm
  above the quad to beat depth-fighting. Both Model and Layer
  views pick it up because they both call `addBedToScene`.
- **Legend time + weight + totals.** HSPT bumped to **v2**
  (header 24 B incl. filament density/diameter; per-record
  32 B adding `f32 time_s`). CLI writes it from
  `MoveVertex::time[Normal]` + `GCodeProcessorResult::
  filament_densities[0]` / `filament_diameters[0]`. The Dart
  parser rejects v1 with a clear error so a stale sidecar
  surfaces instead of silently being misread. `Toolpaths`
  grows `timeByRole`, `totalTimeSec`, `filamentDensityGcm3`,
  `filamentDiameterMm` plus `gramsFromExtrudedMm()`. The
  legend grows Time and Weight columns, and the role table is
  followed by a Total-estimation box with "Total Filament
  <m> m · <g> g" and "Total time <h/m/s>". The reference
  screenshot's `1.17 m · 3.52 g · 9m25s` is the target; a new
  test pins density/diameter populate on the thumbnail cube.

Follow-ups queued for 7e:
- Tubes with per-move width AND height (needs a custom
  `LineSegmentsGeometry`-equivalent shader).
- Range-within-layer slider + G-code excerpt.
- 67 MB stress test on the Poco (parse time, RSS, FPS scrub).

## 2026-11-01 11:00 UTC – Pflicht 7c fixes: Orca-accurate colours + table legend

Device test (`7b6ec2a`) said we were close but off on four
counts. All fixed below.

- Colours washed out (orange outer wall rendering as peach,
  dark red infill as salmon pink). Root cause:
  `UnlitMaterial.displayReferred` defaults to `false`, which
  tells Impeller to treat `baseColorFactor` as *linear* radiance.
  Our Orca palette constants are sRGB display values, so the
  pipeline gamma-corrected them a second time. Fix: flip
  `displayReferred = true` on every UnlitMaterial in the
  toolpath view; also drop the dimming of stacked layers so the
  whole visible stack sits at the Orca palette value, same as
  what the desktop viewer paints.
- Translucent "rest of the model" outline above the slider was
  missing. New `_addModelSilhouette` draws the 12 edges of the
  print's XY/Z AABB (from `currentTopZ` up to `maxZ`) in a cyan
  tint via a cheap `LineSegmentsGeometry`.
- 2D top-down was fitting the whole-print XY bbox, which
  included brim / purge-line and shrunk the model to a corner.
  New `layerXyBounds(Toolpaths, from, to)` helper computes the
  per-slider-layer object bbox, and the painter fits the
  viewport to it with a 10 % margin. 2D also gets pinch-zoom
  and single-finger pan (same `Listener` + manual pointer
  tracking as the 3D view).
- Self-check: the earlier +15 % discrepancy was indeed the
  Unretract moves. Dart's `_parseInline` already filters by
  `MoveType.extrude`, so `t.extrudedMm` on the thumbnail-cube
  HSPT lands at 1177.151 mm — within 0.001 % of Orca's footer
  `; filament used [mm] = 1177.15`. Pinned by a new test.

Table legend now matches Orca's Line Type widget: eye-icon
toggle, swatch, name, length in metres, percent. The two
derived columns come from the new `Toolpaths.lengthByRole`
(Euclidean, filtered to `MoveType.extrude`). Weight and time
columns are planned for the next pass once we propagate the
total weight / per-role time from the slice stats.

Slider label now shows `Z = X.XX mm` alongside the layer index,
and both bed views (plate + layer) carry a small top-left
overlay naming the selected plate (`A · Textured — 256×256×256
mm³`) — Klaus asked for the bed labelling to live in the shared
scene starting with model loading.

Follow-ups queued for 7d:
- Tubes with per-move width AND height (needs a custom
  `LineSegmentsGeometry`-equivalent shader).
- Time and weight columns in the legend (needs per-role time +
  the slice-stats weight propagation).
- Bed grid lines + world-anchored axis labels.
- Range-within-layer slider + G-code excerpt.

## 2026-11-01 01:30 UTC – Pflicht 7c: toolpaths from Orca's GCodeProcessor

Dart g-code parser is now the fallback; the authoritative path
emits a packed HSPT binary from `GCodeProcessor::moves` so the
layer view consumes the same data Orca's desktop viewer does.

- CLI gained `--export-toolpaths <path>` (byproduct of slicing)
  and `--input-gcode <path>` (runs
  `GCodeProcessor::process_file()` on an existing g-code,
  so printer-downloaded files also flow through the same path).
  Record layout: 16 B header + 28 B per move (role, extruder,
  move_type, layer_id, width×100, height×100, feedrate,
  x/y/z/delta_e). GCodeProcessor's internal-only moves are
  filtered out (otherwise the "actual speed" duplicates triple
  the sum).
- `app/lib/engine/toolpath_parser.dart`: streaming TypedData
  reader. Loads a 65 MB HSPT via `Isolate.run` so the UI
  thread is never pinned on parse. Carries per-role summed
  extrusion in `Toolpaths.extrudedByRole` + a bounding box
  (per-axis, not the earlier square XY).
- Orca palette and default visibilities ported from
  `libvgcode/src/ViewerImpl.cpp` + `libvgcode/src/Settings.hpp`
  (every extrusion role on, travel / wipe / retract / … off,
  seam on). `OrcaPalette` + `OrcaDefaults` are plain Dart
  constants, no runtime theme.
- New `ToolpathLayerView` widget mirrors `LayerView`'s
  gestures, bed quad and standard-view buttons but renders
  one `LineSegmentsGeometry` per role at that role's recorded
  width (CC2 default: 0.42 mm). The legend uses the Orca
  swatches and lets the user toggle both roles and move-type
  options.
- `ProjectState.parseSliceGeometry` now prefers the HSPT path:
  loads `.gcode.hspt` and populates `sliceToolpaths`; falls
  back to the Dart parser only when the HSPT is missing.
  `SlicerService.slice` passes `--export-toolpaths` so every
  slice writes the HSPT next to the g-code.
  `SlicerService.processGcodeToToolpaths()` wraps the
  `--input-gcode` CLI mode for files pulled from the printer.
- Self-check (measurement): HSPT's summed positive
  `delta_extruder` on `thumbnail-cube.gcode` lands at
  ~1356 mm vs the footer's `; filament used [mm] = 1177.15`
  — about 15 % higher, from start-purge/retract extrusions
  that Orca excludes from the footer. Role mapping is correct;
  the Dart g-code parser keeps its ±1 % footer check as the
  tighter reference.
- Docs: `docs/layer-view.md` gained a Pflicht-7c section with
  the HSPT schema, palette source, internal-only filter note
  and self-check numbers; the earlier Pflicht-7b parser doc is
  now marked as the fallback path.
- 67 MB stress-test on the Poco is Klaus' pass; parse time,
  RSS peak, FPS during slider scrub are the numbers to report.

## 2026-11-01 01:00 UTC – Pflicht 7b fixes: arcs + relative-E + 2D centring + widths

Device test on `a4e5b86` of the notched cube: layer count,
auto-switch, bed, centring and header now right; path geometry
is not. 3D shows closed faces with a slanted "roof", 2D shows
only infill (walls missing) and is offset off-centre. Root
causes and fixes:

- Walls missing because the parser ran absolute-E delta math on
  Orca's M83 (relative) output. Every same-length wall segment
  then showed `eDelta == 0` and got bucketed as a travel move
  (travels hidden by default). Parser now tracks M82/M83 mode
  (also M83 after `M82`), and G92 E0 resets the baseline. In
  M83 mode each `E` value IS the delta.
- Arc moves (G2/G3) were silently falling through, so any arc-
  fitted file would also lose segments. Parser now interpolates
  I/J-form arcs into short straight segments (~0.4 mm each,
  min 8, max 128 per arc). CC2 process has `enable_arc_fitting
  = 0` by default, but the start-g-code uses G2 for the
  initial Z-dip and other profiles can turn arc fitting on.
- Self-check wired as a test: sum of E deltas on the real
  `thumbnail-cube.gcode` is now within 1 % of the Orca footer
  `; filament used [mm] = 1177.15`. Per-type path lengths are
  also tracked (new `lengthByType` field on `GcodeGeometry`)
  so wall / infill / support totals can be reported later.
- 2D top-down painter was off-centre on a cube not centred on
  the bed because it used a single square XY union. Separate
  per-axis bounds (`minX / maxX / minY / maxY`) feed the
  projection; Y stays inverted so the bed's back wall is at
  the top of the viewport (Orca convention).
- 3D line widths were 1.1 mm (current) / 0.5 mm (dim); on a
  dense cube top those ribbons overlapped into solid faces,
  which read as a closed roof. Widths now match the real
  extrusion (0.42 mm current, 0.25 mm dim), so bahnen stay
  distinguishable at a layer-ready zoom level.
- Reference image from Orca at the AMR5 was declined for now
  (no Orca GUI binary built on this host, see
  `docs/blockers.md`). Klaus can drop one into `local-test/`
  if he opens the model in Orca on another machine.
- Tests: new synthetic cases for M83 relative-E, G2 I/J arc
  interpolation and G92 E0 reset. Real-file cases on the cube
  cover the 1 %-footer check and per-type lengths.

## 2026-11-01 00:20 UTC – Pflicht 7b fixes: layer count, bed, auto-switch, highlight, header

Five issues surfaced by the device test on `b48863d`.

- Layer count was 399 instead of 100 on a 20 mm cube. The parser
  counted every z-hop as a layer. Fixed by trusting Orca's
  `;LAYER:<N>` comments (and `;LAYER_CHANGE` as a weaker
  "explicit markers present" signal); z-step detection is now
  only a legacy fallback for g-code without those markers. Also
  honour `TOTAL_LAYER=<N>` so the trailing `;LAYER:<TOTAL>`
  sentinel (seen on the cube: 101 markers for 100 real layers)
  does not add a phantom layer. New parser tests pin the
  behaviour on the real cube and auryn g-code and on a synthetic
  z-hop sample.
- Current layer highlight was too subtle: dim stacks dropped to
  0.55 × brightness, same line width. Dim now 0.35 × brightness
  and current layer draws with 1.1 vs 0.5 line width so the
  slider's position reads cleanly on dense layers.
- Auto-switch to the Layers tab after a slice did not fire — the
  previous didUpdateWidget compared `old.projectState` vs
  `widget.projectState`, both the same `ProjectState` instance,
  so the geometry change never looked like an edge. Replaced
  with a listener that tracks the geometry-null → non-null
  transition.
- Bed plate was missing in LayerView, and the camera was framed
  on the model AABB alone, so the viewer could end up above or
  outside the bed. Extracted the shared bed quad into a new
  `widgets/orbit_scene_bed.dart` (`addBedToScene` +
  `hullWithBed`); both PlateView and LayerView now use it.
  Camera frames the AABB joined with the 256 × 256 bed.
- Project-card header: title and tab-control were in a Row; the
  tab control ate horizontal space and "Schichtvorschau" wrapped
  into "Schichtvorsch-au" on narrow screens. Stacked vertically
  (title, subtitle, then tabs). Narrow-screen widget test
  extended with a case that renders the title + subtitle +
  tabs at 320 px and asserts the title stays on one line
  > 80 px wide.

## 2026-10-31 23:40 UTC – Pflicht 7b: layer preview + path-type legend

Device test is Klaus' pass.

- `app/lib/engine/gcode_parser.dart`: streaming line-by-line
  parser in a background isolate. Reacts to `G0`/`G1` moves,
  `;TYPE:<name>` comments (14-value `PathType` enum covering
  Orca's current emission including Overhang wall, Gap infill,
  Internal Bridge, Internal solid infill), `T<idx>` tool
  changes. Compact result: `positions: Float32List` (6 floats
  per segment), `types: Uint8List`, `filaments: Uint8List`,
  `layers: Uint32List` (segment index per layer). No per-
  segment Dart object. On the x86 host the Auryn `auryn-x86
  .gcode` (67.5 MB, ~2.4 M G1 lines) parses in **2.8 s** to
  2.0 M segments, 4180 layers, 46.6 MB positions + 1.9 MB
  types.
- `app/lib/widgets/layer_view.dart`: new `LayerView` widget.
  One `flutter_scene.LineSegmentsGeometry` per visible path
  type for the stacked below-layers (dim) and another for the
  current layer (bright); legend is a `Wrap` of `FilterChip`s
  for toggling each type (travel off by default). Camera /
  orbit / pan / pinch mirror `PlateView`; the "3D / 2D top-
  down" segmented control switches to a pure-Dart `CustomPaint`
  renderer that only draws the current layer — used
  automatically when `Scene.initializeStaticResources()` fails.
  Slider + `± 1` buttons for layer navigation, all focus-
  navigable (`OrderedTraversalPolicy`).
- `ProjectState.parseSliceGeometry` is fired on every
  successful slice (`parseSliceGeometry()` call next to
  `_lastSlice = r`). Exposes `sliceGeometry`,
  `sliceGeometryBuilding`, `sliceGeometryError`,
  `sliceGeometryProgress`. The Project screen's new
  `_PlateViewCard` carries a Model / Layers segmented tab;
  Layers appears once a slice completes.
- UI copy makes clear that path simplification is display-only
  — subtitle under both the Model and Layers tabs.
- l10n: 25 new ARB keys for layer-view labels + path-type
  names in English and German.
- Tests: `gcode_parser_test.dart` — synthetic 3-layer cube
  (segment count, Z-step layer detection, incremental-E
  bookkeeping, travel bucketing, tool-change filament index,
  TYPE mapping across all 18 Orca spellings) plus a sanity run
  on the real Auryn g-code when `local-test/auryn-x86.gcode`
  is present on the host.
- Doc: `docs/layer-view.md` covers the architecture, the
  parser's compact result layout, the path-type palette table,
  and the 2D fallback.

## 2026-10-31 23:00 UTC – Pflicht 7a device test passed, pushed

Klaus verified on the Poco with `98610b1`:

- Plate-view card header and simplify-note render correctly on the
  phone-portrait layout.
- Pinch-zoom works in the project tab and the +/- buttons give
  sensible steps.
- Model loaded as a white Lambert-shaded cube with the notch
  visible on the plate.
- Chamber-light switch now mirrors the device state live, even when
  the light is toggled directly at the printer.

Pflicht 7a closed on the device. Pushed by Klaus.

## 2026-10-31 22:40 UTC – Pflicht 7a fixes: layout, pinch, chamber-light state

Device test (`e8234d1`) uncovered four issues; all fixed below.

- `_PlateViewCard` header: heading and simplify-note were in a
  Row; the note was unflexed and ate the heading's horizontal
  space, so "Druckplatten-Ansicht" rendered as a vertical stack
  of single letters and the note was cut off. Stacked them
  vertically in a Column; note is allowed to wrap. Heading now
  uses `titleSmall`, note stays `bodySmall · muted`.
- Pinch-zoom was lost to the outer `ListView` scroll gesture.
  Rewrote PlateView gestures with `Listener` + manual pointer
  tracking (`_pointers` map, centroid pan, pairwise distance for
  zoom) so the arena is not involved at all; the project screen
  additionally switches its `ListView.physics` to
  `NeverScrollableScrollPhysics` while a finger is on the
  viewport, via the new `PlateView.onInteractionChanged`
  callback. Added two zoom buttons (+ / −) in a second button
  row so the operation is focus-navigable.
- Chamber-light state: read from `_liveState['led']['status']`
  (match Daniel's upstream models.py:176–182, confirmed on our
  2026-10-31 capture — the CC2 does push
  `{"method":6000,"result":{"led":{"status":N}}}` on
  `api_status`). The last user-set value stays as a fallback for
  the gap between the 1029 response and the next 6000 delta,
  but the printer is now the authority.
- Label-squeeze audit: extracted the chamber-light row into the
  new `LabeledSwitchRow` widget. Pattern: Expanded(Column(label,
  optional-subtitle)) + Switch. Switch stays right of the column
  regardless of subtitle length. Replaced the inline Row in
  print_screen with this widget. Added a widget test
  (`narrow_screen_labels_test.dart`) that renders the row at
  320 px with a long subtitle and asserts the label stays on one
  line, > 60 px wide, and the Switch sits to the right.
- Also: `PlateView._scene` is now constructed lazily inside
  `_initScene` with a try/catch so flutter_test (no Impeller)
  degrades to the empty-state card instead of taking down the
  whole screen.

## 2026-10-31 22:10 UTC – Pflicht 7a: 3D view in the project tab

Not yet device-tested — Klaus runs that pass.

CLI changes (bumps the arm64 and x86 sidecars):

- `--no-slice`: stop after step 6a (arrange + preview-mesh
  export). `--output` is optional in this mode. Guards: at
  least one of `--export-preview-mesh` or
  `--export-thumbnail-raw` must be given.
- `--export-thumbnail-raw <path>` + `--thumbnail-size WxH`:
  render a standalone thumbnail with the Pflicht 6 software
  rasterizer and dump it as raw-RGBA `HSPB` (magic + u32
  version + u32 w + u32 h + rgba bytes). Only valid with
  `--no-slice`. Used by the project 3D view as the fallback
  image when Flutter GPU does not initialise on a device.

App:

- `SlicerService.exportPreviewMesh` wraps the CLI's `--no-slice`
  path (optionally also writing the HSPB thumbnail).
  `SlicerService.totalMemoryBytes` reads
  `ActivityManager.MemoryInfo.totalMem` through the engine
  method channel.
- `ProjectState` gained `ensurePreviewMesh(slicer)` + fields
  `previewMeshPath` / `previewThumbnailPath` / `previewMeshError`
  / `previewMeshBuilding`. Fire-and-forget from the project
  screen right after a model is picked. Cache keyed on
  `sha256(abs path | mtime | simplifyTarget)` in
  `applicationCacheDirectory/preview-meshes/`.
- `app/lib/widgets/plate_view.dart` is the shared plate-view
  renderer: orbit + pan + pinch like the benchmark, four
  focus-navigable buttons (Reset / Top / Front / Oblique
  wrapped in an `OrderedTraversalPolicy`), bed quad baked in.
  On flutter_scene failure it falls back to the HSPB
  thumbnail via `ui.decodeImageFromPixels`.
- Project tab shows a new `_PlateViewCard` under the model-
  info card. Filament colour comes from the slot assigned to
  tool 0; the heading row carries the "preview ≤ N triangles ·
  display only · slicing uses the full mesh" subtitle.
- `src/main/AndroidManifest.xml` opts in to Flutter GPU for
  release builds. Debug and profile overlays unchanged.
- ARB: 7 new keys for the plate-view UI, English source +
  German translation.
- Tests: `preview_mesh_test.dart` (HSPM parser roundtrip +
  rejection, `previewTargetForTotalRam` thresholds) and a new
  `android_manifest_test.dart` case for the GPU opt-in.

Benchmark screen stays `kDebugMode || kProfileMode` only — not
touched in this pass.

## 2026-10-31 21:20 UTC – Pflicht 7 device test passed, pushed

Klaus verified on the Poco:

- First model after launch: 101 fps (vs. 46 before the warm-up
  fix). No perceptible stutter on the first draw.
- All movement axes correct: single-finger rotate L/R and U/D,
  two-finger pan L/R and U/D, pinch zoom.

Pflicht 7 closed on the device. Pushed by Klaus.

## 2026-10-31 21:00 UTC – Pflicht 7: shader warm-up, vertical gesture fix, LOD/system-req updates

Pass-2 numbers on the Poco (profile):

- 100 k: load 43 ms, build 24 ms, vram 9.2 MB, fps 46.1, p95 23.6 ms, Δload 20 MB
- 300 k: load 57 ms, build 45 ms, vram 27.5 MB, fps 127.6, p95 10.3 ms, Δload 81 MB
- 500 k: load 78 ms, build 75 ms, vram 45.8 MB, fps 108.3, p95 11.6 ms, Δload 141 MB

Build time ~30× faster, Δload RSS ~6× smaller than Pass 1
(~0.28 KB per preview triangle on Dart heap now vs. ~1.8 KB
before).

Observed artefact in both passes: the FIRST model after launch
measured ~46 fps regardless of size (Pass 1: 500 k, Pass 2: 100 k),
subsequent models hit 100+ fps. Impeller/Flutter GPU compiled the
`UnlitFragment` pipeline on first use. Fixes:

- `SceneView(..., warmUp: true)` so flutter_scene calls
  `Scene.warmUp` before the first reveal.
- Fps counter now discards the first 30 frames after any (re)build
  and shows `warming up (N frames left)` in the status line.

Vertical input: Klaus called it out as inverted on both the
rotation and the pan. Signs flipped so down-drag rotates the top
of the model toward the viewer (trackball convention) and
two-finger down-drag scrolls the view target in the same
direction — point under the fingers tracks.

Docs: Pass-2 table in `plate-view-benchmark.md`, auto-LOD
thresholds grounded in the new per-triangle costs (≥ 8 GB → 500 k,
4 – 8 GB → 300 k, < 4 GB → 100 k; budget bounded by slicing
head-room, not by renderer saturation), System-requirements draft
updated with the measured plate-view costs and the warm-up note.

## 2026-10-31 20:30 UTC – Pflicht 7: flutter_scene chosen, memory refactor, pan fix

Klaus measured on the Poco (profile build, Impeller OpenGL ES):

- notched_cube: fps 114, p95 12 ms
- 100 k: load 31 ms, build 642 ms, vram 9.2 MB, fps 138, p95 9.4 ms, Δload 185 MB
- 300 k: load 66 ms, build 2149 ms, vram 27.5 MB, fps 137, p95 10.4 ms, Δload 559 MB
- 500 k: load 87 ms, build 3964 ms, vram 45.8 MB, fps 46, p95 23.4 ms, Δload 896 MB

Decision: **flutter_scene is the plate renderer.** Even on a
Vulkan-denylisted Adreno 640 the benchmark holds 60+ fps up to
300 k and stays interactive at 500 k. The Canvas comparison was
skipped — the flutter_scene numbers were already clearly good
enough to decide.

Side-finding: ~1.8 KB RSS per triangle during the build step,
GPU VRAM only a tenth of that. Root cause: the GeometryBuilder
path held every attribute stream in three forms (List<double>,
Float32List, packed interleaved) on the Dart heap until the node
was attached.

Changes in this run:

- `_rebuildSceneUnsafe` drops the GeometryBuilder path and feeds
  `MeshGeometry.fromArrays` directly with the HSPM's own
  Float32Lists (zero-copy for positions and normals). Vertex
  colors (RGBA, Lambert pre-baked) are a single Float32List.
  `retainCpuData: false` lets the CPU streams go after the GPU
  upload. Pass-2 numbers in `docs/plate-view-benchmark.md` are
  staged as a blank table — Klaus fills after the next
  device run.
- Two-finger pan: flipped the sign on both axes so the point
  under the fingers tracks the fingers (Blender / Fusion
  convention).
- `docs/plate-view-benchmark.md`: Pass-1 table filled, decision
  bullet committed, Pass-2 table placeholder, plus two drafts —
  automatic LOD by device RAM (not built yet; thresholds settle
  after Pass 2) and a "System requirements" draft for the user
  docs.

## 2026-10-31 19:50 UTC – Pflicht 7 benchmark: profile build + Vulkan/Adreno-Fundstelle

Debug-APK zeigt beim leeren Benchmark-Screen auf dem Poco fps=24,
p95=135 ms – nicht aussagekräftig, weil Debug ohne AOT läuft. Fix:

- `app/scripts/build_apk.sh` akzeptiert jetzt zusätzlich
  `--profile`. Dieselben Prüfungen laufen durch; der Hash-Check
  pickt dann `lib/arm64-v8a/libapp.so` (AOT, wie bei `--release`),
  nicht `kernel_blob.bin`.
- Neuer Overlay `app/android/app/src/profile/AndroidManifest.xml`
  setzt `io.flutter.embedding.android.EnableFlutterGPU=true` so,
  dass das Profile-APK Flutter GPU aktivieren darf. Release bleibt
  bewusst unberührt – die Produktionsentscheidung fällt nach den
  Messwerten.

Fundstelle zur Vulkan-Frage auf dem Poco (Adreno 640, Android 12):

- Flutter 3.47.8 Engine,
  `engine/src/flutter/impeller/renderer/backend/vulkan/driver_info_vk.cc`,
  `DriverInfoVK::IsKnownBadDriver()`:
  `if (adreno_gpu_ && *adreno_gpu_ <= AdrenoGPU::kAdreno650) return true;`
  → **jede Adreno ≤ 650** fällt auf OpenGL ES zurück. Hintergrund
  laut Kommentar: "additional workarounds in the Impeller Vulkan
  back end such as disabling framebuffer fetch" (Flutter-Issues
  #178285, #178498). Betrifft u.a. Poco X3 Pro (Adreno 640),
  Pixel 4, OnePlus 7 Pro usw.
- Konsequenz für den Benchmark: der Poco liefert eine
  Lower-Bound-auf-Mainstream-Hardware-Zahl, keine
  Vulkan/Metal-Zahl. Dokumentiert in
  `docs/plate-view-benchmark.md`.

Test-Dateien für Klaus liegen nach dem Run unter
`/sdcard/Download/Handslice/bench/` auf dem Poco: notched_cube.hspm
(1752 B, 24 Dreiecke) + auryn-100000.hspm / auryn-300000.hspm /
auryn-500000.hspm (Simplify-Ziel per `--simplify N`, nur Vorschau,
Slice-Pfad unverändert). Weder Modell noch Exporte wandern ins
Repo (siehe stress-test.md).

## 2026-10-31 18:40 UTC – build_apk.sh: expliziter --debug-Modus, selbe Prüfungen

Beim ersten Debug-Build für Pflicht 7 wurde direkt `flutter build apk
--debug` genutzt – ohne die `--dart-define`-Hashes. Startup-Guard
blockte die App auf dem Poco ("Build-Metadaten fehlen"). Fix:

- `app/scripts/build_apk.sh` akzeptiert jetzt explizit `--debug` und
  `--release` (Default bleibt `--debug`). Unbekannte Argumente werden
  mit Nutzungshinweis abgewiesen.
- Verifikation gilt auch im Debug-Modus: der Commit-Hash wird im
  entsprechenden Dart-Blob gesucht —
  `assets/flutter_assets/kernel_blob.bin` (debug, JIT) bzw.
  `lib/arm64-v8a/libapp.so` (release, AOT). Vorher gab es nur den
  AOT-Pfad; auf einer Debug-APK wäre das stillschweigend
  fehlgeschlagen oder gar nicht ausgeführt worden.
- CLI-Guard (arm64 vs x86, Side-Car `*.commit`) und
  INTERNET-Permission-Check bleiben unverändert, laufen jetzt für
  beide Modi.
- Startup-Guard in `main.dart` nicht angefasst.

Benchmark-APK neu gebaut (`2f96c68edc`, SHA
`cbfb40e618626df7bf61b235bea6385823fef2a77c7162d1f9875576592386c2`,
~138 MB) und installiert. CLI-Hash im Side-Car ist noch
`7fc19b07eb` (vor dem --export-preview-mesh-Commit) – auf dem
Poco macht das für den Bench-Screen keinen Unterschied, aber vor
der ersten Nutzung von `--export-preview-mesh` auf dem Rechner
muss die x86-CLI nachgezogen werden.

## 2026-10-31 18:30 UTC – Pflicht 7 scaffolding: CLI export + bench screen + Canvas fallback

Benchmark scaffolding for the plate renderer is in place. Numbers
pending Klaus' Poco X3 Pro run.

- CLI gained `--export-preview-mesh <path>` (`handslice-cli` arg
  block + export in step 6a, right before thumbnail prep).
  Reuses the arranged `preview_meshes` so slicing stays
  untouched; reference-g-code test still green. 24-tri notched
  cube serialises to 1752 bytes with magic `HSPM`.
- `flutter_scene: 0.24.3` pinned (exact, not caret). F-Droid
  check passed: no prebuilt native blobs under the package root,
  shader sources (`.vert`, `.frag`, `.glsl`) ship from source,
  MIT. Transitive `flutter_gpu` is the Flutter SDK stub.
- `lib/screens/plate_bench_screen.dart`: hidden plate-view
  screen (only shown in `kDebugMode`, bottom row in Settings).
  Loads a `.hspm`, one-finger rotate, two-finger pan/zoom,
  toggle between `flutter_scene` and `Canvas.drawVertices`,
  reports load/build time, triangle count, approximate VRAM,
  rolling FPS + p95 frame time, RSS, Δload RSS, and a backend
  guess from `gpuContext.doesSupportFramebufferRenderMipmap`
  (true = Vulkan/Metal, false = GLES — Impeller does not expose
  the name directly).
- Debug APK builds cleanly (`JAVA_HOME=java-21-openjdk`
  required; the system `java` is the headless 27 JRE and lacks
  `javac`).
- Report scaffold under `docs/plate-view-benchmark.md` with the
  measurement-table template, procedure, F-Droid eligibility
  recap, HSPM format spec, and a three-branch recommendation
  framework to commit to after the numbers come in.

Open: Poco run on Klaus' notched cube + big model (not in repo).
After the numbers come back, pick one of the three
recommendation bullets, and fill or drop the upstream-notice
stub (`docs/upstream/`).

---

## 2026-11-01 09:00 UTC – Pflicht 6 device test passed (`7fc19b0`)

Klaus verified on the printer:

- Cube: white, three distinct face greys, right-side-up, in-app
  and on the printer's display.
- Auryn-sized model: slices in ~1 min end-to-end **including**
  the thumbnail — no measurable regression from the renderer.
- Black filament on a dark display background renders similarly
  to Orca's own export (near-silhouette). Treated as expected,
  **not** a renderer defect — the background stays transparent
  so this is a display-theme/colour interaction. **No change.**

Pflicht 6 closed. First English-only Pflicht closed under the
new project-language rule.

Pushed by Klaus.

---

## 2026-10-31 23:30 UTC – Pflicht 6 follow-up 2: z-buffer sign fix + notched-cube test

Device test of `aca76ac` passed on colour, shading and background,
but the model rendered upside-down (notch of the notched cube on
the bottom instead of the top). First hypothesis — buffer row
order collides with Orca's export flip — turned out wrong after
proper measurement.

### Verified

- Instrumented the renderer with a 1-row red stripe at
  buffer-row 20 and read back the resulting PNG: the stripe
  appeared at PNG row 123 (= `144-1-20`). Orca's PNG encoder
  (`tdefl_write_image_to_png_file_in_memory_ex`, miniz
  `flip = 1`) does flip the buffer. So that part was correct.
- A second instrumentation (world-Z + view-Y + computed py per
  triangle vertex) showed the actual root cause: **view-space Z
  had the wrong sign.** `to_view()` returned
  `-dot(d, V.forward)`, so points further away from the camera
  got MORE-negative z values, and the rasterizer's `z < depth`
  test preferred the far side of the model. Result: the
  invisible bottom face occluded the visible top face and the
  silhouette ended up mirrored vertically.
- Fix in `engine/cli/thumbnail_renderer.cpp`: `to_view()` now
  returns `+dot(d, V.forward)` — positive distance along the
  camera axis, "smaller = closer" is intuitive. Comment in the
  code explains why the sign was wrong before.
- `engine/test/run-thumbnail-test.sh` grew a 6th check that
  slices `cube_notched_20mm_centered_cc2.stl`, decodes the PNG,
  measures the standard-deviation of the uppermost opaque y
  coordinate per column vs. the bottommost, and asserts
  `stdev(upper) > stdev(lower)` plus `max(upper) - min(upper) >=
  12 px`. On a right-side-up notched cube the top edge has the
  step from the notch and the bottom edge is straight; on an
  upside-down render those swap. Current measurement:
  upper stdev 12.46, lower stdev 10.16 → PASS.
- All six script checks + reference test still green.
  EXECUTABLE_BLOCK sha256 unchanged (`92951c26…`, 8479 lines).
- `local-test/` artefacts regenerated:
  - `thumbnail-cube.png` (orange, standard)
  - `thumbnail-cube-white.png` (white filament override, grey
    range `[120..250]`)
  - `thumbnail-notched.png` (white filament, notch now visibly
    at the top).
- Builds on x86 + arm64 (NDK r27d) carry the fix.

### Firmware finding also captured

- `docs/networking-cc2.md` new section
  "Firmware behaviour: cancel during auto-levelling leaves the
  display stuck (2026-10-31)". Klaus hit Cancel in the app
  around 15:25 while the printer was auto-levelling. The
  network side went back to idle correctly, but the printer's
  own display froze on the "Druck wird gestoppt …" dialog and
  only recovered after a power cycle.
- App proposal captured, **not** implemented:
  either block Cancel while `PrintPhase.preparing` AND the
  sub_status is a levelling code, or warn in a confirmation
  dialog that the display may need a power cycle.
- Decision deferred to Klaus after one or two more live tests
  and whether to raise it upstream (firmware repo).

### Not verified at the printer

- The fixed orientation live. Klaus will upload the next slice
  to confirm the notch appears on the top of the display
  thumbnail.

### Does not go

- (no new blockers.)

---

## 2026-10-31 22:40 UTC – Pflicht 6 follow-up: shader + background fixes

Klaus live-tested `ab67cbb` and found two deficiencies: white
filament (`filament_colour=#FFFFFF` from slot A4) rendered as
dark grey, and the model's three visible faces had no useful
shading spread — the cube looked like a flat silhouette with
the notches only visible on the outline.

### Verified

- Compared our output (`local-test/thumbnail-cube.png`) to the
  GUI reference (`local-test/thumbnail-cube-gui-reference.png`)
  and traced three distinct problems in
  `engine/cli/thumbnail_renderer.cpp`:

  1. **Background was opaque light grey** (`#F2F2F2`), while
     Orca's GUI thumbnail is RGBA color-type 6 with alpha = 0
     everywhere. A near-white model on a near-white background
     disappears. Fixed: background pixels now stay transparent
     (alpha = 0); `ThumbnailData::set()` initialises to 0xFF,
     so we explicitly zero the buffer after `set()`.
  2. **STL winding wasn't being normalised.** Our per-triangle
     normal came from `vcross(a-v0, b-v0)` and pointed outward
     for some triangles and inward for others, depending on
     admesh's load order. Lambert then put half the cube's
     visible surface in ambient-only. Fix: orient each
     triangle's normal toward the camera (`V.eye`) before
     shading — the visible side is by definition the one
     facing us, so this is loss-free.
  3. **Shader was too tame.** Original `k = 0.35 + 0.65·cosA`
     capped the top face at ~0.86 even in favourable light, so
     white filament never climbed past #DADADA. New model:
     ```
     k = 0.20 + 0.80·max(0, dot(n, key))
                + 0.15·max(0, dot(n, fill))
     ```
     with `key = (0.15, -0.35, 0.95)` (near top-down, slight
     front-right tilt) and `fill = (-0.60, 0.40, 0.20)`
     (behind-left). A camera-facing surface hits the key near
     cos ≈ 0.95, so top ≈ 0.98 → ~250 (near-white). Side faces
     drop to ~145, back-facing side to ~82 — three clearly
     separable greys at any base colour.
  4. **Camera tilted a bit steeper** (`dir (0.55, -0.90, 0.95)`
     instead of `(0.6, -1.0, 0.75)`) so the top face reads as
     a top face, not a wide front.

- `engine/test/run-thumbnail-test.sh` extended with a 5th step
  that re-renders the cube with
  `--overrides '{"filament_colour":"#FFFFFF"}'`, decodes the
  PNG, de-filters it, samples the opaque centre column and
  asserts:
    - background pixel at (0,0) is alpha = 0,
    - all opaque pixels on a white model are greyscale
      (`r == g == b`),
    - top-face peak greyvalue is ≥ 240 (near-white),
    - spread between min and max is ≥ 60 (three faces
      distinguishable).
  Current measurement: grey range `[120..250]`, spread 130.
  All 4 checks (base) + 5th (white) pass.
- `engine/test/run-reference-test.sh` still passes:
  EXECUTABLE_BLOCK sha256 = `92951c26…`, 8479 lines, unchanged.
- `local-test/thumbnail-cube-white.png` and
  `local-test/thumbnail-cube.png` are regenerated artefacts for
  side-by-side review (both gitignored).
- Builds on x86 and arm64 (NDK r27d) both carry the new
  shader; CLI commit hash will be refreshed by the APK build
  after this commit.

### Not verified at the printer

- On-device look of the fixed thumbnail. Klaus will upload the
  next slice; the firmware's `method 1045` should now show
  near-white top / mid-grey front / dark-grey side instead of
  flat dark grey.

### Does not go

- (no new blockers.)

---

## 2026-10-31 22:00 UTC – Pflicht 6: G-code thumbnail (Variant C, CLI software rasterizer)

Implemented the "CLI draws its own thumbnail" plan from
`docs/preview-research.md` follow-up: `handslice-cli` now ships a
~400 LoC flat-shaded software rasterizer, hands the result to
Orca's own `export_thumbnails_to_file` through `thumbnail_cb`,
and emits the `; THUMBNAIL_BLOCK` into the G-code — same format
as the GUI export. No GPU, no WebView, no splice logic in Dart.

### Verified

- `--simplify <N>` CLI flag added. Runs
  `its_quadric_edge_collapse` on a per-volume copy that lives
  only in the thumbnail renderer; the slicing path keeps the
  original mesh. `0` or absent = no simplification.
- Software rasterizer in `engine/cli/thumbnail_renderer.{hpp,cpp}`:
  Z-buffer, flat shading, one directional light + fixed ambient,
  orthographic projection, 8 % margin. Camera angled from
  front-upper-right (dir `(0.6, -1.0, 0.75)`), neutral light
  grey background `#F2F2F2`.
- Per-volume colour from `filament_colour[extruder_idx]` in the
  active print config — so the Pflicht-9-slot-colour override
  (`filament_colour: "#FFFFFF"`) renders as white in the
  thumbnail, matching what will show up at the printer.
- Thumbnail size + format come from `print.config()`'s
  `thumbnails` option (CC2 profile: `"144x144"`, format PNG).
  Not hardcoded.
- `print.export_gcode(output, &result, thumbnail_cb)` wiring in
  `handslice-cli.cpp` — unchanged slicing path otherwise.
- `engine/test/run-reference-test.sh` still **PASSES**:
  `EXECUTABLE_BLOCK` sha256 =
  `92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d`,
  8479 lines, byte-identical to the GUI reference. The new
  thumbnail block sits before the executable section and does
  not change motion planning.
- New smoke test `engine/test/run-thumbnail-test.sh`:
  1. Slice the test cube with handslice-cli-x86.
  2. Assert `; THUMBNAIL_BLOCK_START` / `_END` present.
  3. Assert header `; thumbnail begin 144x144 <size>`.
  4. Decode base64 payload, verify PNG signature + IHDR
     dimensions (144×144), reject suspiciously-uniform output.
  5. Side-by-side artefacts in `local-test/` (gitignored):
     `thumbnail-cube.png` (678 B, ours) and
     `thumbnail-cube-gui-reference.png` (1 133 B, GUI).
- Build on x86 (host) + arm64 (NDK r27d, Android API 29) both
  succeed; `handslice-cli-{x86,arm64}.commit` match (both
  carry the pre-commit HEAD now; after this commit the APK
  build will refresh them to the new HEAD).
- Baseline timing on x86 for the 684-byte test cube: 0.72 s
  wall-clock end-to-end (slice + thumbnail). No measurable
  perf regression vs. before — the rasterizer only touches
  144×144 pixels regardless of model size.

### Not verified at the printer

- Big model (`Auryn` 140 MB) is not present in the repo —
  the `--simplify` path is unit-safe (QEC is Orca's own code)
  but a measured end-to-end run against a 1.5M-triangle model
  comes with the next session.
- Firmware's `method 1045` extraction of the new block: Klaus
  will upload the next slice and check that the preview on the
  printer display and in `method 1045` matches what
  `local-test/thumbnail-cube.png` looks like.

### Does not go

- (no new blockers.)

---

## 2026-10-31 21:00 UTC – M9 Vorstufe am Geraet bestaetigt (App f602d1d)

- **Fach-Farbe im G-Code**: Klaus hat frisch gesliced; neue Datei
  zeigt am Drucker **Weiss** statt Orange (Fach-Farbe uebernommen,
  Profil-Default `#F2754E` ueberschrieben). 1046-Verifikation
  implizit bestanden.
- **Auto-Fach-Vorauswahl**:
  - weisse Datei → A4 vorgewaehlt, kein Hinweis (unique-Match).
  - orange Datei → Hinweis „Kein Fach passt …" (none-Match),
    letzte Wahl blieb stehen.

Beide Vorstufen zu Pflicht 8 damit live abgesegnet. Live-Test ist
jetzt an die Hauptbranch gepusht (Klaus-Push).

---

## 2026-10-31 20:40 UTC – M9 Vorstufe: Fach-Farbe im G-Code + Auto-Fach-Vorauswahl

Kleiner Schritt vor Pflicht 8 (Multicolor), hier noch mono:
1. Beim Slicen wandert die Farbe des gewaehlten Fachs als
   `filament_colour`-Override in den G-Code (statt Orcas
   Standardfarbe).
2. Der Druck-Dialog fuer vorhandene Dateien waehlt das Fach
   automatisch vor, wenn `color_map[0]` eindeutig zu genau einem
   Slot passt (Material-Vergleich + RGB-Toleranz).

### Nachweislich

- **`settings/slot_matcher.dart`** (pure functions, 76 LoC):
  - `findSlotForFile(colorMap, slots)` → `SlotMatchResult`
    (`unique`/`ambiguous`/`none`). Material case-insensitive +
    getrimmt; Farb-Toleranz = euklidische RGB-Summe ≤ 52²
    (`kDefaultColorToleranceSquared`), faengt Spool-Jitter und
    Hex-Rounding.
  - `slotOverridesFor(slot)` → Map, aktuell nur
    `{"filament_colour": "#RRGGBB"}`; leer bei ungueltiger Farbe.
- **`state/project_state.dart`**: `slice(...)` nimmt jetzt einen
  weiteren `slotOverrides: Map<String,String>`-Parameter.
  Reihenfolge im `merged`: `overrides` → `filamentOverrides` →
  `slotOverrides` nur `putIfAbsent` (User-Overrides gewinnen,
  Fach-Werte fuellen nur den Profil-Default auf).
- **`screens/project_screen.dart`**: `_slice()` baut
  `slotOverrides` aus `slot.filamentColor` ueber den Helper.
  `filamentOverrides` + Filamentprofil-Pfad bleiben wie bisher.
- **`widgets/printer_files_panel.dart`**:
  `_PrintSettingsDialog` bekommt zusaetzlich `colorMap` und ruft
  `findSlotForFile(..)` in `initState()`. Bei `unique` wird das
  Fach vorgewaehlt; bei `ambiguous`/`none` bleibt die letzte
  Nutzer-Wahl, und unter dem Picker steht ein kurzer kursiver
  Hinweis.
- **L10n (en + de)**: zwei neue Keys
  `printerFilesSlotAmbiguous`,
  `printerFilesSlotNoMatch`.
- **Tests** (`test/slot_matcher_test.dart`, 12 Faelle):
  - `slotOverridesFor`: Hex-Normalisierung mit/ohne `#`,
    leere Map bei ungueltiger Farbe.
  - `findSlotForFile`: eindeutig / eindeutig-im-Toleranzbereich /
    mehrdeutig / kein Treffer wegen falschem Material /
    kein Treffer wegen zu weit entfernter Farbe / leere
    `color_map` / leere Slot-Liste / ungueltige Hex-Werte /
    Material-Case- und Trim-Vergleich.
  - Vollsuite **126/126 gruen** (+12 ggue M8-NB3).

- **Scrub strict**: 0 Treffer.
- **Doku**: englischer Abschnitt
  "M9 (Vorstufe) – slot colour as slice override + auto slot
  preselect" in `docs/networking-cc2.md`.

### Ungeprueft

- **1046-Verifikation am echten Drucker**: `color_map[0].color`
  nach Upload+Druckstart muss die neue Fach-Farbe tragen. Klaus
  prueft das in der naechsten Session (die bisherige
  Abnahmedruck-Datei trug `#F2754E` als Profil-Default; mit
  einem anders gefaerbten Fach-Slot zeigt sich der Unterschied).
- **Auto-Vorauswahl am Geraet**: Dialog-Vorauswahl + Hinweise
  sind nur Unit-getestet; Live-Verhalten (mehrfach-Slots mit
  gleicher Farbe) kommt mit Pflicht 8 (Multicolor-Mapping)
  realistischer in den Blick.

### Geht nicht

- (keine offenen Blocker.)

---

## 2026-10-31 20:00 UTC – M8 Nachbesserung 3: bedlevel_force vs printer_check (Orca 1:1)

Klaus hat vor dem Push den Verdacht gehabt, dass `bedlevel_force`
und `printer_check` zwei verschiedene Funktionen sind. Beleg im
Orca-Bundle angesehen – es sind zwei Felder, aber Orca hat trotzdem
nur EINEN sichtbaren Switch, und `bedlevel_force` ist ein
Retry-Flag, kein User-Toggle. Freigabe fuer "A — Orca 1:1":
EIN Switch bindet an `printer_check`, `bedlevel_force` wird nur im
Retry nach `error_code=1026 BedMeshDataMissing` auf `true` gesetzt.

### Nachweislich

- **Fundstellen in Orca** (dokumentiert in
  `docs/networking-cc2.md` "M8 follow-ups 3"): Multicolor- und
  Monocolor-Start-Pfad binden `printer_check` an denselben
  User-Switch; `bedlevel_force` ist initial `false` und wird nur
  im 1026-Retry-Pfad auf `true` gedreht.
- **PrinterState**:
  - `startPrint` und `startPrintFile` haben jetzt genau einen
    Nutzer-Parameter `levelBed` (statt `bedlevelForce` +
    `printerCheck`).
  - `_startPrintCore` sendet den Erstversuch IMMER mit
    `bedlevel_force=false`. Bei `error_code=1026` **genau ein**
    Retry mit `bedlevel_force=true`, gleicher restlicher Config.
    Danach wird das Resultat durchgereicht.
  - Vor dem Retry wird `_lastHint =
    'startprint.retry_forced_level'` gesetzt (neuer transienter
    Hint-Getter `lastHint`).
- **UI**:
  - `print_screen.dart` und `widgets/printer_files_panel.dart`:
    EIN Switch mit neuem Label
    "Bett vor dem Druck nivellieren (ca. 200 s)" /
    "Level bed before printing (~200 s)".
  - Hint-Anzeige: im Upload-Flow als `_InfoBox` neben dem
    Start-Button; im Datei-Druck-Flow als `SnackBar` nach
    Abschluss des Dialog-Flows (Panel wechselt gleich auf
    Druckstatus).
- **L10n**: neue Keys `startPrintForcedLevelHint` in en + de;
  `printLevelBed`-Text aktualisiert
  ("ca. 200 s" / "~200 s" eingefuegt).
- **Tests**: `files_and_camera_test.dart` neu
  "M8 1026-Retry (BedMeshDataMissing)". Fake-Client gibt beim
  ersten `startPrint` 1026, danach 0; Asserts:
    - genau zwei `startPrint`-Calls,
    - erster Call `bedlevel_force=false, printer_check=true`,
    - zweiter Call `bedlevel_force=true, printer_check=true`,
    - `lastHint == 'startprint.retry_forced_level'`.
  Vollsuite **114/114 gruen** (+1 ggue vorher). Scrub strict:
  0 Treffer.

### Ungeprueft

- **1026-Fall am echten Drucker**: nur wenn der CC2 wirklich ohne
  Mesh-Daten startet (nach Factory-Reset oder gewisser
  Firmware-Zustaende). Klaus kann das forcieren, muss aber nicht –
  der Pfad ist auf Orca-Code gestuetzt und Unit-getestet.
- **UI-Live-Verifikation** der neuen Switch-Beschriftung und des
  Hint-Banners am Geraet.

### Geht nicht

- (keine offenen Blocker.)

---

## 2026-10-31 19:30 UTC – M8 Nachbesserung 2: Start-Dialog, Cancel-Semantik, control-Labels

Klaus-Test mit App d6849c8: Dateiliste / Thumbnails / Farben / Groesse,
Live-Kamera (inkl. Vollbild), Download+Open/Share, Delete+Dialog,
Print+A4-Pull, Running-File-Protection – **alles OK**.

Zwei Punkte waren offen:
1. Abbrechen waehrend des Nivellierens → App zeigte "Abbruch vom
   Drucker abgelehnt: control.cancel.timeout" (zwei Fehler: Timeout
   ist keine Ablehnung; roher Schluessel in der UI).
2. Start-Dialog zeigte nur "Aktuelles Fach: A4" ohne Auswahl.

### Nachweislich

- **Firmware-Verhalten dokumentiert** (nicht unser Fehler): Cancel
  waehrend `sub_status 2901`/`2902` (Levelling/Homing) wird vom
  CC2 fw 02.01.01.07 **erst nach Abschluss der Nivellierung**
  ausgefuehrt. Die 1022-Response kam ~Minuten verspaetet; das lag
  nicht an Netzwerk oder App, sondern an der nicht-unterbrechbaren
  Firmware-Motion-Planning-Phase. Jetzt in
  `docs/networking-cc2.md` im Abschnitt "M8 follow-ups 2"
  festgehalten.
- **Cancel/Pause-Semantik angepasst** (`PrinterState.pausePrint`,
  `cancelPrint`):
  - Client-Wait auf 5 s verkuerzt.
  - `error_code == 0` → UI still, Status-Watcher uebernimmt.
  - `error_code != 0` → **echte Ablehnung** →
    `lastError = control.<verb>.error_code.N`.
  - **`TimeoutException` → keine Ablehnung**: `lastError` bleibt
    null, Rueckgabe `true`. UI verfolgt den Erfolg ueber
    `sub_status 2501/2502` (Pause) bzw. `2503/2504` (Cancel).
  - Resume (1023) bleibt fire-and-forget wie zuvor.
- **control.*-Keys lokalisieren**
  (`app/lib/net/control_error_label.dart`): neuer Mapper
  `mapControlErrorToText(l, key)` uebersetzt
  `control.<verb>.error_code.N` → "Verb vom Drucker abgelehnt
  (error_code=N)" und `control.<verb>.timeout` → "Verb: keine
  Antwort in der erwarteten Zeit". UI im `PrintScreen._PrintControls`
  nutzt den Mapper, bevor ein lastError ausgegeben wird – so taucht
  der rohe Schluessel nicht mehr auf.
- **Guard-Test** (`test/control_error_label_test.dart`): fuer jede
  verb × kind Kombination in en und de muss der Mapper einen
  nicht-leeren Text liefern, der KEIN `control.`-Fragment enthaelt.
  Deckt die Rueckregression aus dem Live-Test ab.
- **Start-Dialog fuer vorhandene Dateien** zeigt jetzt denselben
  Fach-Picker (A1..A4, Radio + Farbkreis + Material-Label) wie
  der Upload-Flow und persistiert die Auswahl via
  `PrinterState.setTrayAssignmentForTool0`.
- **Zwei Nivellier-Switches → einer**: ein Schalter "Bett vor dem
  Druck nivellieren" in beiden Dialogen; beim Senden werden
  `bedlevel_force` und `printer_check` auf denselben Wert gesetzt.
- **Farbchip-Beschriftung** in der Dateiliste: `color_map[].t` ist
  der Filament-Index aus der G-Code-Datei, NICHT das Fach. Jetzt
  "Filament 1" statt "A1" (lokalisiert ueber neuen Key
  `printerFilesFilamentIndex`), damit niemand Fach und Filament
  verwechselt. Das physische Fach-Mapping passiert erst beim
  Druckstart ueber `trayAssignmentForTool0`.

**Tests**: `flutter test` → **113/113 gruen** (+5 ggue M8-Basis).
Scrub strict: 0 Treffer.

### Ungeprueft

- Live-Verifikation der neuen Nachbesserungen am echten Drucker:
  Fach-Picker-Verhalten, "Bricht ab …" bei Cancel-waehrend-
  Nivellieren statt Timeout-Meldung – macht Klaus bei der naechsten
  Session.

### Geht nicht

- (keine offenen Blocker.)

---

## 2026-10-31 18:30 UTC – M8 Nachbesserungen: MediaStore-Downloads + UI-Kleinigkeiten

Klaus-Test mit App 55ae65f ergab:
- Dateiliste + Thumbnails + Farben/Faecher: OK.
- Live-Kamera: OK.
- Download: Datei landete in `/Android/data/dev.handslice.handslice/
  files/handslice-downloads/` (ADB-Nachweis), **im Datei-Manager
  nicht sichtbar** (Scoped Storage seit Android 11). Fix: MediaStore.

### Nachweislich

- **ADB-Nachforschung (nur lesen):** Datei lag in
  `/Android/data/dev.handslice.handslice/files/handslice-downloads/
  handslice_1793449708341.gcode` – richtig geschrieben, aber nicht
  nutzer-sichtbar. Nichts an das Geraet geschickt.
- **Native-Bruecke** `MainActivity.kt`:
  - `saveGcodeToDownloads(srcPath, displayName, mime)` – legt die
    Datei via `MediaStore.Downloads.EXTERNAL_CONTENT_URI` unter
    `Download/Handslice/` an. Benoetigt keine zusaetzliche
    Permission (Scoped Storage, API 29+; `minSdk` ist 29).
  - `openUri(uri, mime)` – startet `ACTION_VIEW` auf dem
    content://-URI, damit der Nutzer die Datei im Datei-Manager
    oder Viewer oeffnen kann ohne READ_EXTERNAL_STORAGE.
  - `saveVideoToGallery(..)` bleibt unveraendert fuer die
    Zeitraffer-Flow (Movies/Handslice).
- **Dart-UI** (`PrinterFilesPanel`):
  - Nach dem lokalen Schreiben ruft die Panel die
    `saveGcodeToDownloads`-Methode; URI wird in
    `_downloadUris` gemerkt.
  - UI zeigt "Gespeichert unter Download/Handslice (sichtbar im
    Datei-Manager)" + zwei OutlinedButtons **Oeffnen** (URI via
    Platform-Intent) und **Teilen** (`share_plus` auf
    app-interner Datei).
- **UI-Kleinigkeiten** aus Klaus' Rueckmeldung:
  - Section-abhaengiger Header: "Dateien am Drucker" /
    "Druckhistorie" / "Live-Kamera" statt starr "Druckhistorie".
  - Refresh-Icon nur im Historie-Reiter (Pull-to-refresh deckt
    Dateien ab).
  - "Herunterladen" bricht nicht mehr im Wort um – jetzt reiner
    IconButton mit Tooltip, analog zum Loeschen-Button.
  - Kamerabild Tap → Vollbild (`MaterialPageRoute
    fullscreenDialog: true`, Scaffold black, eigener
    WidgetsBindingObserver). Panel-Stream pausiert waehrend
    Vollbild offen ist, damit nicht zwei HTTP-Streams parallel
    laufen.
- **Tests**: `printer_screen_test.dart` Fall "Section-
  abhaengiger Header" angepasst (Default-Section ist "Dateien"
  → Refresh fehlt; nach Tap auf "Historie" sind Druckhistorie
  + Refresh wieder da). **108/108 gruen** (unveraendert).
- **L10n**: neue Keys `printerCameraTapHint`,
  `printerCameraFullscreenClose`, `printerFilesHeading`,
  `printerFilesDownloadDoneDownloads`, `printerFilesDownloadOpen`,
  `printerFilesDownloadShare` in en + de.
- **Scrub** strict: 0 Treffer.

### Ungeprueft

- MediaStore-Pfad live im Datei-Manager: Klaus prueft, ob die
  Download-Button-Variante jetzt die Datei in
  `Download/Handslice/` zeigt und ob der Open-Button auf dem
  Poco (MIUI Datei-Manager) einen passenden Handler findet. Bei
  "kein Handler" liefert der Platform-Channel `false` ohne
  Fehler; die App zeigt dann nur Teilen.
- Share-Button nutzt den app-privaten Pfad – FileProvider
  Konfiguration ist im bestehenden Timelapse-Flow abgenommen,
  fuer G-Code identisch.
- Fullscreen-Kamera-Rotation: Scaffold passt sich automatisch
  an Portrait/Landscape an; nicht am Geraet rotiert getestet.

### Geht nicht

- (keine offenen Blocker.)

---

## 2026-10-31 18:00 UTC – M8: Dateien am Drucker + Live-Kamera (Pflicht 4+5)

Neuer "Dateien"- und "Kamera"-Bereich im Reiter „Drucker". Nur zwei
Methoden am echten Geraet live angetastet (1045/1046 lesen), alles
andere baut Klaus selbst in der App.

### Nachweislich

**Teil A – Dateien**
- Live-Pruefung 1045 + 1046 am idle Drucker:
  - **1046 `{storage_media, filename}`**: `error_code=0`,
    Felder `color_map, create_time, filename, last_print_time,
    layer, print_time, size, total_filament_used, total_print_times`.
    Belegt an `handslice_1793449708341.gcode` (221 kB, 100 Schichten).
  - **1045 `{storage_media, file_name}`** (file_name **mit**
    Unterstrich): bei kleiner Testdatei `error_code=1015
    ThumbnailNotExist`, bei groesserer Datei
    (`Elegoo-Bauplattenhalter-1.gcode`, 12 MB) `error_code=0` +
    2 684 B base64-PNG im `thumbnail`-Feld.
  - Rohantworten anonymisiert in `docs/networking-cc2.md`
    Abschnitt M8.
- Client-API in `app/lib/net/elegoo_cc2_client.dart`:
  - `RemoteFile.fromJson(..)` liest jetzt die vollen 1044-Felder
    (`layer`, `print_time`, `create_time`, `last_print_time`,
    `total_filament_used`, `color_map[]`); neue Klasse
    `ColorMapEntry`.
  - `getFileThumbnail/getFileDetail/deleteFile` neu (Shape wie
    oben, `deleteFile` sendet `file_path` als **Liste**).
  - `probeFile`/`downloadFile` als duenne Alias auf die
    vorhandenen Timelapse-Pfade (gleicher `/download`-Endpunkt).
  - `getLivingVideoUrl()` fuer method 1042.
- `PrinterState`:
  - `runningFilename` aus `print_status.filename`.
  - `startPrintFile(filename, …)` fuer vorhandene Dateien;
    gleicher Preflight (ohne bounds) + delay_video-Logik wie
    beim Upload-Flow.
  - `deleteFile(filename)` mit Guards:
    `not_connected`, `running_file`, Firmware-Error.
- UI (`widgets/printer_files_panel.dart`): Karten pro Datei mit
  Thumbnail (lazy via 1045), Groesse/Schichten/Druckzeit,
  Farb-Chips aus `color_map`, "Currently printing"-Marker.
  Aktionen Print/Download/Delete; Lauf-Datei bekommt
  deaktivierten Delete-Button mit lokalisiertem Tooltip.
  Download via geteiltem `_DownloadLimiter(maxConcurrent: 2)`
  mit Head-Probe, Ziel `getExternalStorageDirectory()/
  handslice-downloads/`.

**Teil B – Kamera**
- `widgets/mjpeg_viewer.dart`: eigener schlanker Decoder
  (~230 LoC), parst `multipart/x-mixed-replace`, extrahiert
  JPEG-Frames per `Content-Length`, rendert ueber
  `Image.memory(..., gaplessPlayback: true)`. **Kein Fremd-
  Paket** – F-Droid-tauglich, AGPL-3.0-kompatibel.
- `widgets/printer_camera_panel.dart`: holt URL via 1042,
  startet Stream nur wenn `visible && appResumed`.
  Fehlerzustaende (kein URL, HTTP != 200, no-first-frame-10s,
  Stream ended, SocketException) kommen als eindeutige
  lokalisierte Texte – **nie** schwarzes Bild.
  **Kein 1054-Call** (Block-A-Beleg: 1054 lehnt {enable} ab).
- `screens/printer_screen.dart` ist jetzt ein 3-way
  SegmentedButton (Dateien / Historie / Kamera). Screen hat
  `WidgetsBindingObserver`-Hook fuer `_appResumed`; Section-
  Wechsel + Lifecycle steuern zusammen den Kamera-Stream.

**Tests (`flutter test` → 108/108 gruen, +9 ggue M7)**
- `files_and_camera_test.dart`:
  - Payload-Form 1047 (`file_path` als Liste), `RemoteFile.fromJson`,
    `ThumbnailResult.ok`-Semantik (1015 → false), `LivingVideoResult.ok`.
  - Delete-Guards: running_file, not_connected, erlaubter Fall.
  - MJPEG-Dekoder: zwei Frames, byteweise fragmentierter Input
    wird reassembliert.

**Doku + Scrub**
- Englischer Abschnitt
  "M8 – File management + live camera (CC2 fw 02.01.01.07,
  2026-10-31)" in `docs/networking-cc2.md` mit Rohantworten.
- Scrub-Check (strict): 0 Treffer.

### Ungeprueft

- **Print/Download/Delete am echten Drucker in der App**:
  macht Klaus beim naechsten Session. Die zwei lesen-only-
  Methoden sind heute live belegt; mutierende Aufrufe nicht.
- **MJPEG-Live gegen die echte Kamera**: Stream-Server-URL ist
  per 1042 belegt (Block A), der Decoder ist nur gegen
  synthetische Frames getestet (Unit-Test). Fehlerzweige wie
  "Server haengt mitten im Stream" sind nicht am Geraet
  gepruft.
- **1046-Felder bei Multi-Color-Dateien**: `color_map` wurde
  heute nur mit einem Eintrag (PLA) belegt; die UI unterstuetzt
  mehrere Chips, aber eine Datei mit >1 Material war beim
  Testlauf nicht angetippt.

### Geht nicht

- (keine offenen Blocker.)

---

## 2026-10-31 16:30 UTC – M7 Nachbesserungen am Geraet bestaetigt

Klaus hat die M7-Nachbesserung mit App `aaea699` am echten CC2
durchgespielt:

### Nachweislich

- **WLAN aus → ein: Reconnect sofort** (nicht mehr nach ~30 s
  Backoff-Wartezeit). Der neue `connectivity_plus`-Hook aus
  `main.dart` → `PrinterState.networkAvailability` →
  `_triggerImmediateReconnect()` greift wie entworfen.
- Preparing-Text und Reconnect-Flow-Test bleiben unveraendert.

### Ungeprueft

- Fehler-Banner-Trigger am Geraet weiterhin nicht ausloesbar
  ohne echten Printer-Error.

### Geht nicht

- (keine offenen Blocker.)

---

## 2026-10-31 16:15 UTC – M7-Nachbesserungen: OS-Netz-Signal, Preparing-Text, Reconnect-Flow-Test

Klaus hat Pflicht 3 am Geraet (App 0c469228e5) durchgespielt:
- WLAN aus: Banner sofort, Countdown wie geplant.
- WLAN wieder an: Reconnect **nach ~30 s** (volle Backoff-Wartezeit).
- App im Hintergrund 2–3 min, dann Resume: in ~2 s wieder verbunden.
- Fehler-Banner am Geraet nicht ausloesbar → bleibt "ungeprueft".

Drei Nachbesserungen vor dem naechsten Live-Test:

### Nachweislich

- **Netzwerk-Signal vom OS triggert Sofort-Reconnect.**
  `connectivity_plus: ^7.3.2` als Dep aufgenommen. Im `main.dart`
  wird `Connectivity().onConnectivityChanged` auf einen bool-Strom
  (`.distinct()`) reduziert und als `networkAvailability` an
  `PrinterState` uebergeben. In `PrinterState` neuer Subscriber:
  wenn `_reconnecting==true` und das Signal `true` eintrifft,
  bricht `_triggerImmediateReconnect()` den Backoff-Timer ab und
  ruft sofort `connectAndLoad()`. **Attempt-Counter wird NICHT
  zurueckgesetzt** – scheitert der Sofort-Versuch, laeuft die
  2→5→10→20→30-Progression weiter.
- **Preparing-Label gekuerzt.** `printPhasePreparing` ist jetzt
  "Preparing" / "Vorbereitung". Grund: `sub_status 1066` ist eine
  Pre-Print Hotend-Stabilisierung, weder Aufheizen noch
  Nivellieren – der Zusatz in Klammern war irrefuehrend.
- **Volle Reconnect-Flow-Tests** in `app/test/reconnect_flow_test.dart`:
  - `_FakeCc2Client extends ElegooCc2Client` mit Zaehlern fuer
    `discover/connect/disconnect/getCanvas/getStatus/ping` und
    fuer die Steuerbefehle `pause/resume/cancel/setLight`.
  - **Trennung → Banner → Reconnect → neuer Vollstatus-Zyklus**:
    `connectAndLoad()` einmal; `fake.dropConnection()` +
    `triggerReconnectForTest()`; `state.reconnecting==true`;
    nach 3 s warten → `connectCalls==2`, `canvasCalls==2`,
    `statusCalls==2`. Hart gesichert: `pauseCalls=resumeCalls=
    cancelCalls=setLightCalls=0` – kein Command-Replay.
  - **Netzwerk-wieder-da-Signal bricht Backoff ab**:
    `netCtrl.add(true)` waehrend `_reconnecting==true` → nach
    100 ms Micro-Yield ist `connectCalls==2` erreicht, ohne die
    2-s-Backoff-Wartezeit.
  - **Idle-Fall**: Netzwerk-Signal bei bestehender Verbindung
    loest **keinen** zusaetzlichen Reconnect aus.
- Tests gesamt: **99/99 gruen** (+3 ggue M7-Basis).
- Scrub-Check (strict): 0 Treffer.
- Englischer Doku-Abschnitt
  "M7 device test – reconnect behaviour (CC2 fw 02.01.01.07,
  2026-10-31)" in `docs/networking-cc2.md`.

### Ungeprueft

- **Live-Verifikation der neuen Nachbesserungen** am Geraet:
  Klaus muss den WLAN-Toggle erneut durchspielen und schauen, ob
  der Reconnect jetzt im Sekunden- statt im 30-Sekunden-Rhythmus
  passiert.
- **Fehler-Banner am echten Drucker**: unveraendert ungeprueft
  (kein 1243-Trigger-Pfad in Reichweite).

### Geht nicht

- **APK-Installation per adb kann heute fehlschlagen** – der
  WLAN-ADB wurde durch den WLAN-Toggle moeglicherweise
  verloren. Falls `adb install` nicht durchkommt, meldet
  Claude das zurueck statt herumzuprobieren (Klaus-Vorgabe).

---

## 2026-10-31 15:30 UTC – M7: Fehlermeldungen + Reconnect-Behandlung

Pflicht 3 der Pflichtliste in zwei Teilen umgesetzt. Kein Befehl
an den echten Drucker – Klaus macht den Live-Test.

### Nachweislich

**Teil A: Druckerfehler-Tabelle**
- Komplette Code → Klartext-Tabelle aus dem Orca-ElegooLink-Bundle
  (PR #14024, v2.4.2) extrahiert: 77 Codes mit englischem Freitext
  aus Objekt `Zve` (locale "en") in
  `engine/OrcaSlicer/resources/web/elegoolink/lan_service_web/
  index.html`. Daniels `const.py` fuehrt keine exception-code-Liste.
- `app/lib/net/cc2_exception_codes.dart`: `cc2ExceptionEn` (77,
  Orca-Text 1:1) + `cc2ExceptionDe` (77, sinngemaess uebersetzt).
  Codes mit gleichem EN-Text teilen sich den DE-Text
  (z. B. 1203/1241 → beide "Zufuhr … fehlgeschlagen").
- UI (`print_screen.dart`): `_PrinterErrorBanner` zeigt alle
  aktiven `exception_status`-Codes als rot gerahmte Infobox
  solange sie in dem Array stehen. 1243 behaelt den
  Klaus-definierten Text aus `printStatusException1243`. Unbekannte
  Codes landen auf `exceptionCodeUnknown(code)` ("Druckerfehler N" /
  "Printer error N"). Rohes Array wird nicht mehr gerendert.
- L10n (`app_en.arb` + `app_de.arb`): neue Keys
  `printerErrorBannerTitle`, `printerErrorsBannerTitle(count)`,
  `exceptionCodeUnknown(code)`.

**Teil B: Reconnect-Logik**
- Detektion:
  - **PING-Fail** (bestehend, 10 s-Loop) → Reconnect.
  - **Status-Watchdog**: 10 s-Timer, prueft ob der letzte
    `api_status`-Delta hoechstens 30 s zurueckliegt. Im Idle
    inaktiv (Firmware schweigt dann), nur im laufenden Druck.
- Backoff: 2 → 5 → 10 → 20 → 30 s, danach 30 s als Dach.
  Delay-Serie als statische Konstante `_reconnectBackoffSec` +
  `@visibleForTesting`-Static.
- Reconnect-Schritte (bestehender `connectAndLoad()`): Discovery
  → CONNECT → `api_register` → subscribe → initiales 1002 holen
  → Watchdog neu starten → Attempt-Counter + "due at" ruecksetzen.
- **Keine Wiederholung von Steuerbefehlen** nach dem Reconnect
  (kein Pause/Resume/Cancel/Start-Replay). Steht im Reconnect-
  Pfad als Nicht-Aktion drin + Testbeleg via Pflicht-3-Vorgabe.
- UI (`print_screen.dart`):
  - `_reconnectBannerText(l, printer)` liefert
    "Verbindung verloren – verbinde neu …" wenn kein Countdown,
    sonst "Erneuter Verbindungsversuch in Ns …".
  - Steuerknoepfe (Pause/Resume/Cancel/Light) bleiben gesperrt
    solange `connection != connected` (unveraendert, Guard
    deckt reconnecting mit ab).
- Lifecycle-Hook: `_RootShellState` ist jetzt
  `WidgetsBindingObserver`, ruft bei `AppLifecycleState.resumed`
  `printerState.checkAliveOnResume()`. Diese Methode prueft
  `_client.isConnected` + Watchdog-Alter; wenn stale, reset
  Attempt-Counter und sofortiger Reconnect-Versuch.
- L10n: neue Keys `reconnectBannerLost`,
  `reconnectBannerRetrying(seconds)`, `reconnectBannerBackoff`.

**Tests (`flutter test` → 96/96 gruen, +12 ggue. M6)**
- `cc2_exception_codes_test.dart` (8 Faelle): EN-/DE-Lookup fuer
  Stichproben aller drei Kernkategorien, `en-US`/`de-DE`-Locale-
  Fallbacks, unbekannte Codes → null, Keys-Konsistenz zwischen
  EN und DE, nicht-leere Texte, Count 77/77, 1243-Praesenz.
- `reconnect_backoff_test.dart` (4 Faelle):
  `reconnectDelaySecForAttempt(0..99)` → gesamte Serie plus
  Dach-Verhalten; `secondsUntilReconnect` positiv/Null/null je
  nach gesetztem `_reconnectDueAt`.

**Doku**
- Englischer Abschnitt
  "M7 – Printer-error table + reconnect behaviour (2026-10-31)"
  in `docs/networking-cc2.md`.
- Scrub-Check (strict): 0 Treffer.

### Ungeprueft

- **Reconnect am echten Drucker**: WLAN-Flap, Broker-Kill,
  App-Suspend/Resume – alle drei macht Klaus live. Die
  Watchdog-30-s-Grace, Backoff-Progression und das Nicht-
  Replay-Verhalten sind nur per Unit-Test belegt.
- **Fehler-Banner-Live-Trigger**: 1243 ist in den Mitschnitten
  nicht aufgetreten; Klaus muss einen echten Printer-Error
  provozieren, damit der Banner-Text in Druck-Kontext sichtbar
  wird. Die Tabelle selbst ist durch die Orca-Quelle direkt
  belegt.
- **Backoff-Trigger-Pfad**: Das pure Delay-Mapping ist getestet,
  der Weg "echter MQTT-Disconnect → _scheduleReconnect → Timer
  feuert → connectAndLoad" ist nur manuell am Geraet
  nachvollziehbar.

### Geht nicht

- (keine offenen Blocker.)

### Konsequenz

- Pflicht 3 vorlaeufig umgesetzt; Klaus-Test entscheidet, ob
  der Watchdog-Threshold von 30 s zu lang oder zu kurz ist
  (ist konfigurierbar via `_watchdogGrace`-Konstante).
- Pflicht 4+ (Datei-Loeschen, Kamera-Panel) folgt in getrennten
  Commits.

---

## 2026-10-31 14:30 UTC – M6 Geraetetest bestanden; zwei UI-Bugs + 1066-Phase gefixt

Klaus hat heute mit App 0c36fb3250 Pause/Fortsetzen/Abbrechen/Licht am
echten CC2 (fw 02.01.01.07) durchgespielt. Mitschnitt
`logs/cc2-sniff-2026-10-31-133328.jsonl` (gitignored, 564 Nachrichten).

### Nachweislich

- **Geraetetest bestanden** (Klaus-Rueckmeldung + Mitschnitt):
  - Licht ein/aus schaltet sofort, beide Richtungen.
  - Nivellieren (2801/2802) + Homing (2901/2902): Pause-Button grau,
    Cancel aktiv – korrekt.
  - **Pause** 2501 → 2502 in 3.9 s; Kopf parkt, App zeigt "Pausiert"
    + "Fortsetzen".
  - **Resume** 2401 → 2402 in **18.4 s** (Temperaturen gehalten,
    kein voller Reheat) – deutlich unter Daniels 122-s-Cold-Case.
    Rechtfertigt die fire-and-forget-Semantik: 60 s Timeout von
    Orca wuerde den Kaltfall verfehlen; wir blockieren einfach gar
    nicht und beobachten den Statuswechsel.
  - **Cancel** 2503 → 2504 in 8.7 s inklusive Bestaetigungs-Dialog.
- **1066 nachgezogen in `PrintPhase.preparing`**. Analyse ueber
  **drei Mitschnitte**: 27 Vorkommen, **ausschliesslich bei
  `current_layer=0`**, Hotend-Ist jeweils ±1 °C am Target,
  Nachbarcodes 1045/2801/2802/2901/2902/2075 (allesamt
  Vorbereitungs- und Druck-Codes). Daniels `const.py` benennt
  1066 nicht; wir uebernehmen es mit Verweis auf die eigenen
  Mitschnitte (`docs/networking-cc2.md` Abschnitt "sub_status 1066
  analysis").
- **Fortschrittsbalken-Fix**: Firmware pusht `print_status.progress`
  **nicht** im Delta; `total_layer` kam heute 1x als 0 im initialen
  1002-Snapshot und blieb so. `.clamp(0,100)` pinnte den Balken
  dauerhaft auf 100 %. **Fix**:
  - `printProgress` (int?) ersetzt durch
    `printProgressFraction` (double?) und `printProgressPct` (int?).
  - Nur noch aus `current_layer / total_layer`, und **nur** wenn
    `total_layer > 0`.
  - Progress-Fallback-Feld entfernt (irrefuehrend). UI blendet
    den Balken aus, wenn kein Wert belastbar ist.
- **Preflight-Rohwert-Fix**: `printPreflightNotIdle` nahm `code:int`
  und druckte `status=2`. Jetzt `status:String` + CC2-Status-
  Labels (16 Codes aus Daniels `CC2_STATUS_*`), inklusive Fallback
  "status N" fuer unbekannte Werte. "status 2" ist jetzt
  "printing" (EN) / "Druck läuft" (DE).
- **L10n**: 17 neue Keys (`machineStatusUnknown` + 15 Status-Namen +
  `machineStatusOther`) in en.arb (Quelle) und de.arb.
- **Tests** (`flutter test` → **84/84 gruen**):
  - `printer_phase_mapping_test.dart`: 1066 im preparing-Fall
    ergaenzt; "printing"-Default-Fall auf 2075 (echter PRINTING-
    Code) umgestellt, 1066 ist jetzt kein Default-Fall mehr.
  - `widget_test.dart`: `printProgress`-Tests auf
    `printProgressFraction`/`printProgressPct` angepasst; neuer
    Fall "ohne total_layer null" sichert den Bugfix.
- Englischer Testergebnis-Abschnitt in `docs/networking-cc2.md`:
  "M6 device test – print control (CC2 fw 02.01.01.07, 2026-10-31)".

### Ungeprueft

- Cold-Pause-Resume-Dauer: heute waren die Temperaturen gehalten,
  18.4 s war der Idealfall. Daniels 122 s fuer den Kaltfall ist
  weiterhin ungeprueft.
- Filamentzufuhr-Fehler-Pfad (sub_status 2505 + exception_status
  1243 live): kein Trigger im heutigen Lauf.
- `sub_status 1096/1906`: wieder nicht gesichtet. Mapping bleibt
  spekulativ aus Daniels Liste.

### Geht nicht

- (keine offenen Blocker.)

---

## 2026-10-31 13:45 UTC – M6-Nachbesserung: Phase "preparing" (Aufheizen/Nivellieren)

Vor dem Geraetetest Klaus-Rueckmeldung umgesetzt.

### Nachweislich

- **Neues Phase-Element `PrintPhase.preparing`** in
  `app/lib/state/printer_state.dart`. Mapping aus Daniels const.py +
  method.h fuer die Vorbereitungs-Unterstatus:
  - 1045 HOTEND_PREHEATING, 1096 HOTEND_COOLING
  - 1405, 1906 (weitere Vorbereitungs-Codes aus Daniels Liste)
  - 2801/2802 Bed-Levelling (start/end)
  - 2901/2902 Homing (start/end)
- **Mitschnitt-Gegenprobe** ueber alle `logs/cc2-sniff-*.jsonl`
  (Python-Script in-memory): Vorkommen bei dieser Firmware
  (fw 02.01.01.07, Abnahmedruck 2026-10-26 + Block A 2026-10-31):
  - 1045: 19 Nachrichten – belegt
  - 1405:  3 Nachrichten – belegt
  - 2801:  5 Nachrichten – belegt
  - 2802:  5 Nachrichten – belegt
  - 2901:  3 Nachrichten – belegt
  - 2902:  1 Nachricht  – belegt
  - 1096 und 1906: 0 Treffer in unseren Mitschnitten. In Daniels
    `const.py` dokumentiert; wir uebernehmen die beiden ohne
    eigenen Live-Beleg, Kommentar im Code weist darauf hin.
- **UI-Gating** (`screens/print_screen.dart`): Cancel aktiv in
  `preparing`, Pause **inaktiv**. Resume bleibt nur in `paused`.
  Entsprechender Guard auch in `PrinterState.cancelPrint()`
  (preparing in erlaubte Phasen aufgenommen).
- **L10n**: neue Keys `printPhasePreparing` (EN "Preparing
  (heating/levelling)", DE "Vorbereitung (Aufheizen/Nivellieren)")
  in beiden ARB-Dateien; Generated-Files regeneriert.
- **Tests** (`cd app && flutter test` → **83/83 gruen**):
  - Erweiterung in `printer_phase_mapping_test.dart`: alle 8
    prep-Codes muessen zu `PrintPhase.preparing` auflösen.
  - Alle bisherigen 82 Faelle weiter gruen (keine Rueckregression).

### Ungeprueft

- 1096/1906 am echten Drucker: in unseren Mitschnitten nicht
  gesichtet. Code uebernimmt sie trotzdem (Daniels Liste); falls
  die Firmware noch andere Codes fuer diese Phasen nutzt, wird
  die UI dort weiterhin "Printing" zeigen statt "Preparing" –
  **falsch-sicher**, keine falsche Pause-Freigabe moeglich, weil
  die Pause nur in `printing` aktiv ist.
- Alles was Klaus zum Geraetetest beisteuert (echte Transitionen
  idle → preparing → printing → paused → resuming → printing →
  cancelling → cancelled) ist weiterhin offen – wie geplant.

### Geht nicht

- (keine offenen Blocker.)

---

## 2026-10-31 13:15 UTC – M6 Druck-Steuerung + Licht: Code steht, APK auf Poco

Phase 6 Punkt 1+2 der Pflichtliste umgesetzt (Pause/Fortsetzen/Abbrechen
+ Licht). Kein 1007, keine Kamera, keine Dateien in diesem Schritt.
Geraetetest macht Klaus selbst mit einem kurzen Druck.

### Nachweislich

- `app/lib/net/elegoo_cc2_client.dart`
  - `pausePrint()` → publish `method 1021` ohne params-Objekt
    (Orca-Form @2510582, docs/networking-cc2.md).
  - `cancelPrint()` → publish `method 1022` ohne params (Orca @2511241).
  - `resumePrint()` → publish `method 1023` ohne params; **fire-and-
    forget**, kein Timeout, kein Retry (Daniels gemessene
    ~122 s-Latenz plus Orca-60-s-Timeout → wir warten gar nicht,
    sondern lesen den Erfolg aus der sub_status-Transition
    2401 → 2402).
  - `setLight(bool)` → publish `method 1029 {"power": 0|1}`.
    Orcas Minimal-Form; Daniels zusaetzliches `brightness` fliegt
    raus, Fundstellen-Kommentar im Code.
  - `_request()` nimmt jetzt `Map? params`: `null` = params-Key
    weglassen (Orca-Shape fuer 1021/22/23), `{}` sendet weiter
    einen leeren Objekt-Params fuer die bestehenden 1002/1044/1036.
- `app/lib/state/printer_state.dart`
  - **Neues Enum `PrintPhase`** (`unknown/idle/printing/paused/
    resuming/cancelling/cancelled`), abgeleitet aus
    `machine_status.status` + `machine_status.sub_status`:
    - 2501/2502/2505 → paused
    - 2401/2402       → resuming
    - 2503            → cancelling
    - 2504            → cancelled
  - `isFilamentFeedError` → true, wenn `exception_status` den
    Code `1243` enthaelt (method.h FILAMENT_FEED_FAIL).
  - `pausePrint()/cancelPrint()` async mit `error_code`-Auswertung;
    `resumePrint()` synchron fire-and-forget;
    `setLight(bool)` async, aktualisiert lokalen `_lightOn`-Cache.
  - `_lightOn` als lokaler Zustand – die CC2-Firmware pusht **keinen**
    Light-State auf `api_status` (Sniff-Logs grepping: 0 Treffer).
    UI zeigt "unbekannt", bis zum ersten Set-Aufruf.
  - `controlInFlight`-Guard verhindert Doppelauslösung.
- `app/lib/screens/print_screen.dart`
  - Neue Card `_PrintControls` unter dem Live-Status: Pause/Fortsetzen
    als **ein** Button (Label + Icon je nach Phase), Abbrechen mit
    `AlertDialog`-Bestaetigung, Licht-Switch.
  - Gating:
    - Pause aktiv nur in Phase `printing`
    - Fortsetzen aktiv nur in Phase `paused`
    - Abbrechen aktiv in `printing` oder `paused`
    - Licht-Switch aktiv immer wenn verbunden
    - Alle Buttons deaktiviert waehrend `controlInFlight`
  - `_LiveStatus` zeigt jetzt die vollstaendige Phase (incl.
    "Pausiert", "Setzt fort", "Bricht ab …", "Abgebrochen").
  - `isFilamentFeedError`-Vorrang: wenn aktiv, Infobox
    "Filamentzufuhr-Fehler – PTFE-Schläuche prüfen" statt rohem
    `exception_status`-Dump.
- L10n (`app/lib/l10n/app_{en,de}.arb` + regenerated):
  neue Keys `printControlSectionLabel`, `printControlPause/Resume/
  Cancel`, `printControlCancelConfirm*`, `printControlLightLabel/
  Unknown`, `printControlResumeHint`, `printControlFailed*`,
  `printPhaseCancelling/Cancelled`. Englisch Quelle, Deutsch
  Uebersetzung.
- Tests (**82/82 gruen**, `cd app && flutter test`):
  - Neu: `test/elegoo_control_payloads_test.dart` (4 Faelle) –
    sichert, dass 1021/1022/1023 **ohne** params-Key gesendet
    werden und 1029 nur `{power:0|1}` ohne brightness.
  - Neu: `test/printer_phase_mapping_test.dart` (11 Faelle) –
    deckt alle sub_status-Codes aus method.h + den
    exception_status-1243-Pfad ab; nutzt
    `injectLiveStateForTest`, kein MQTT.
  - Bestehende Mock-CC2-Tests weiter gruen.
- Release-APK:
  - `app/build/app/outputs/flutter-apk/app-release.apk`,
    32 039 444 Byte, SHA256
    `238e21088c97a9835ec4c7a43b67cbfec246420f62a0ac167464ab1fc2ea9cef`.
  - Commit `b1a01c0a79` + CLI `761249e97b` einbrennt (CLI-Guard
    gruen, INTERNET-Permission vorhanden).
  - Installiert auf dem Poco X3 Pro via WLAN-ADB
    (`adb install -r -g`, `Success`).

### Ungeprueft

- **Geraetetest am echten Drucker**: Pause/Fortsetzen/Abbrechen und
  Licht sind in diesem Schritt bewusst **nicht** am realen CC2
  getestet (Klaus macht das selbst mit einem kurzen Druck).
- Die 2401→2402-Transition als Erfolgs-Beleg fuer Resume ist in
  method.h belegt und im alten Mitschnitt gesichtet, aber noch nicht
  live gegen diesen App-Pfad gegengeprueft.
- 1029-Antwort fuer `power=0|1` am echten Geraet nochmal: in Block
  A (2026-10-31) kam `error_code=0`; dass die App-Logik dasselbe
  erreicht, muss ein App-Live-Test zeigen.

### Geht nicht

- (keine offenen Blocker; `docs/blockers.md` unveraendert.)

### Konsequenz fuer den naechsten App-Schritt

- Punkt 3+ der Pflichtliste (Datei-Loeschen in der App, Kamera-
  Panel) kommt in getrennten Commits. Fuer Datei-Loeschen gilt
  die in Block A entschiedene Shape (`file_path: [<name>]`), fuer
  die Kamera reicht laut Block A der 1042-URL-Getter plus
  MJPEG-Decoder – kein 1054.

---

## 2026-10-31 12:40 UTC – Block A am Drucker: 1047/1042/1054/1029 geklaert, Doku ergaenzt

Hands-on-Test am CC2 (fw 02.01.01.07), Klaus daneben, Drucker idle.
Nur die vier Methoden aus dem Auftrag; MQTT-Mitschnitt
`logs/cc2-sniff-2026-10-31.jsonl` (gitignored, 356 Zeilen Payload).
Nichts committed, nichts gepusht.

**Hinweis zu aelteren Eintraegen (nicht umgeschrieben, bleiben zur
Historie stehen):** Die Aussagen aus dem 1047-Nachweislauf vom
2026-10-25 und aus Test E (2026-10-26 09:30 UTC), `method 1047`
loesche auf fw 02.01.01.07 nichts, sind **ueberholt**. Beide
testeten `filename`-Keys mit String-Wert; die akzeptierte Form
ist `{"storage_media":"local","file_path":[<name>]}` (Key
`file_path`, Wert als Liste). Die Rohbefunde beider Laeufe (jeweils
`error_code=1003`) sind damit konsistent – es waren wirklich
Parameter-Fehler, nicht "nicht serviert". Korrektur-Hinweise sind
in-place in `docs/networking-cc2.md` eingezogen (an den
Nachweislauf-Abschnitten + an der "fuer die App"-Konsequenz).

### Nachweislich

- **1047 DeleteFile – Shape entschieden.**
  Vorstufe: 112-B-Testdatei `cc2_probe_delete_test.gcode` per
  `PUT http://<cc2-ip>:80/upload` hochgeladen (HTTP 200,
  `error_code=0`, `offset=111`); in 1044 verifiziert (total 27→28).
  Dann zwei 1047-Versuche auf exakt diese Datei:
  - **Orca-Form** `{"storage_media":"local","file_path":"<name>"}`
    (String) → `error_code=1003`, Datei bleibt. **Verworfen.**
  - **Array-Form** `{"storage_media":"local","file_path":["<name>"]}`
    (Liste) → `error_code=0`, 1044 danach ohne die Datei (total
    28→27). **Akzeptiert.**
  Der obere Caller im Orca-Vue-Bundle (`onDeletePrintFile` @2622179)
  packt den String ja genau in ein Ein-Element-Array, bevor er die
  composable-Methode aufruft; die Statik-Analyse hatte diesen Wrap
  gesehen, aber die beiden Formen offen gelassen. Heute entschieden.
  Daniels Shape (`filename` als String, `cc2/client.py:2634–2636`)
  ist auf dieser FW nach wie vor nicht die richtige (sowohl Key
  als auch Typ divergieren).
- **1042 ist URL-Getter, Stream always-on.**
  `method 1042` ohne Params → `error_code=0`,
  `url=http://<cc2-ip>:8080/?action=stream`.
  GET auf diese URL liefert durchgehend `HTTP 200`,
  `multipart/x-mixed-replace; boundary=frame`, JPEG-SOI im Body —
  **vor** jedem 1054-Call genauso wie **nach** jedem. Der
  MJPEG-Server laeuft kontinuierlich; keine 1054-Variante hat
  daran etwas veraendert.
- **1054 `{"enable":0|1}` → `error_code=1003`.**
  Beide Richtungen abgewiesen; Daniels Shape passt also nicht auf
  diese FW. Welche Shape 1054 akzeptiert, bleibt offen (per
  Auftrag heute nicht weiter sondiert).
- **1029 `{"power":1}` schaltet die Kammer-LED EIN**, Klaus
  visuell am Panel bestaetigt. `1029 {"power":0}` schaltet sie
  wieder AUS, Ausgangszustand restauriert. **Orcas Minimal-Form
  reicht**, Daniels zusaetzlicher `brightness`-Key ist auf dieser
  FW nicht noetig.
- **Klaus-Beobachtung fuer die Doku** (Kamera):
  Der CC2 hat **keine Anzeige-LED fuer die Kamera**. Eine
  Rueckmeldung "Kamera an" gibt es nur im Druckbetrieb mit
  aktivem Zeitraffer. **Im Leerlauf ist der Stream-Zustand nur
  ueber HTTP-Probe pruefbar**, nicht am Geraet.
- Englischer Abschnitt
  "Block A device test – results (CC2 fw 02.01.01.07, 2026-10-31)"
  in `docs/networking-cc2.md` (+120 Zeilen).

### Ungeprueft

- **1054 mit anderer Params-Shape** (`{"state":…}`, `{"on":…}`,
  `{"storage_media":…}`, usw.) — nicht angetastet, waere eine
  separate Shape-Probe wert.
- **1023 ResumePrint Reply-Latenz** und **1031 Mode-Range**
  bleiben offen; beide brauchen einen laufenden Druck und
  gehoeren damit in einen spaeteren Block, nicht in Block A
  (idle-only).
- Ob `1047` auf `storage_media=udisk` dasselbe Array-Shape braucht
  und ob dort ein fuehrender Slash erforderlich ist — nicht
  getestet (kein USB-Stick angeschlossen).

### Geht nicht

- (keine offenen Blocker; `docs/blockers.md` unveraendert.)

### Konsequenz fuer den App-Einbau

- **Delete-Flow**: `method 1047` mit
  `{"storage_media":"local","file_path":[<name>]}` — Liste, nicht
  String; Key `file_path`, nicht `filename`.
- **Kamera-Flow**: Nur `method 1042` fuer die URL, dann MJPEG-
  Decoder auf `:8080/?action=stream`. **Kein `1054` beim Oeffnen
  des Panels** (bringt nur 1003).
- **Licht-Flow**: `method 1029 {"power": 0|1}` — kein
  `brightness`, keine Range.
- `tools/cc2-block-a.py` bleibt als Repro-Script fuer kuenftige
  Shape-Probes im Repo (Subcommands: `status`, `list`, `upload`,
  `delete [--as-array]`, `camera-get`, `camera-set 0|1`,
  `light-set 0|1`).

---

## 2026-10-31 11:00 UTC – CC2-Steuerbefehle: Orca-Belege gelesen, Diffs zu Daniel/method.h festgehalten

Nur lesen; nichts an den Drucker gesendet. Neuer englischer Abschnitt
"Print control commands – sources (Orca ElegooLink, Elegoo method.h,
elegoo-homeassistant)" in `docs/networking-cc2.md`.

### Nachweislich

- **PR #14024 ist in v2.4.2 drin.** `src/slic3r/Utils/ElegooLink.cpp`
  (1293 Zeilen) + `resources/web/elegoolink/lan_service_web/`
  (3,6 MB minified Vue-Bundle) vollstaendig vorhanden auf Commit
  `8500fcdcca`. Kein zusaetzlicher Clone noetig.
- **Transport**: Orcas eingebette WebView redet MQTT ueber
  **WebSocket Port 9001**
  (`index.html @1119975: ws://${Ni.ip}:9001`), Daniel + unser
  Client reden MQTT ueber **Plain TCP 1883**
  (`const.py:23 CC2_MQTT_PORT = 1883`). Broker hoert auf beiden –
  **kein Umbau unseres MQTT-Clients noetig**.
- **Topics**: `elegoo/<sn>/api_register`,
  `elegoo/<sn>/<req_id>/register_response`,
  `elegoo/<sn>/<client_id>/api_request`,
  `elegoo/<sn>/<client_id>/api_response`,
  `elegoo/<sn>/api_status`. Brief sagte `_register`, tatsaechlich
  ist es `api_register` – Orca und Daniel sind sich hier einig.
- **Vollstaendige Params/Response-Tabelle** fuer die Pflichtliste
  (1007 / 1021 / 1022 / 1023 / 1028 / 1029 / 1030 / 1031 / 1042 /
  1044 / 1045 / 1046 / 1047 / 1048 / 1054) mit Datei+Offset in
  `docs/networking-cc2.md` → neuer Abschnitt.
- **Drei konkrete Divergenzen zu Daniel aufgedeckt**:
  - **1047 DeleteFile**: Orca schickt `{storage_media, file_path}`,
    Daniel schickt `{storage_media, filename}`. Erklaert vermutlich
    das 11×1003 aus Test E (2026-10-26 09:30 UTC) – Klaus' Probe
    hat `file_path` nicht getestet.
  - **1029 LightSwitch**: Orca schickt nur `{power: 0|1}`, Daniel
    schickt zusaetzlich `{brightness: 0|255}`.
  - **1042 vs 1054 (Kamera)**: Orca-UI nutzt 1042 **als URL-Getter**
    (ohne Params, liest `.url`), **1054 ist deklariert, wird aber
    nirgends aufgerufen**. Daniel nutzt 1042 als Toggle
    (`{enable}`). method.h steht hier auf Orcas Seite.
- **Native C++ Seite** (`ElegooLink.cpp:343..369`) redet selbst
  **kein MQTT**. Sie macht nur HTTP-GET auf `/system/info` zum
  SN-Holen und oeffnet dann `file://.../lan_service_web/index.html?
  access_code=…&ip=…&sn=…&id=elegoo_123456`. Das heisst: wenn wir
  Orca-Verhalten 1:1 nachbilden wollen, muessen wir die Logik aus
  dem Vue-Bundle lesen, nicht aus dem C++.

### Ungeprueft

- **1048 GetCapacity** und **1054 StartVideoStream**: in Orcas Enum
  deklariert, aber **in der UI nie aufgerufen**. Params-Form
  unbekannt. Vermutung (klar als solche gekennzeichnet in der Doku):
  1048 ohne Params; 1054 analog zu Daniels 1042-Toggle
  `{enable: 0|1}`.
- **Orca `main` nicht gezogen.** Da PR #14024 bereits in v2.4.2 ist
  und alle angefragten Method-IDs im v2.4.2-Bundle unmissverstaendlich
  belegt sind, kein zusaetzlicher Shallow-Clone. Eine spaetere
  ElegooLink-Refaktorierung in Orca-main koennte Enums umbenennen –
  die Method-IDs 10xx bleiben per method.h stabil.

### Geht nicht / Konsequenz

- (keine offenen Blocker; `docs/blockers.md` unveraendert.)

### Vor App-Einbau noch am echten Drucker gegenpruefen (Prioritaet)

1. **1047 `{storage_media, file_path}`** – ist das die Form, die der
   CC2 akzeptiert? Eine der 12 Probe-Dateien von Klaus (2026-10-26)
   damit loeschen und 1044 vorher/nachher vergleichen.
2. **1054 `{enable: 1}` vs. 1042 als Toggle** – welchen Pfad nutzt
   die Firmware tatsaechlich fuer den Kamera-Schalter? 1054 testen,
   dann 1042-URL vorher/nachher pruefen.
3. **1029 nur `{power}` vs. `{power, brightness}`** – ob
   Orcas minimale Form auf fw 02.01.01.07 reicht.
4. **1031 PrintSpeedControl mode-Range** – gueltige Integer-Werte
   nicht dokumentiert; 0/1/2/3 durchtesten.
5. **1023 ResumePrint Reply-Latenz** – Daniel misst ~122 s, Orcas
   UI setzt 60 s Timeout. Einmal messen, damit unser Client den
   richtigen Timeout waehlt (nicht erneut sendet).

### Artefakte

- `docs/networking-cc2.md` – neuer Abschnitt "Print control
  commands – sources" (englisch, +168 Zeilen).
- Nichts committed, nichts gepusht.

---

## 2026-10-26 14:40 UTC – Phase 4.4-Nacharbeit: Filament-Save + Material-Picker + Ueberschrift

Zwei Befunde aus der Poco-Abnahme (APK 5699b13) adressiert.

### Nachweislich

- Code: Commit `1bc94ad4d5` (lokal, nicht gepusht).
  - `app/lib/screens/settings_screen.dart`: Save-Button jetzt auch im
    Filament-Bereich; `_saveAsProfile` schreibt type=`filament`,
    inherits=Material-Basisprofil des aktiven Fachs (via
    `FilamentMapping.resolve`). Picker-Zeile `_FilamentProfilePickerRow`
    oeffnet Dialog, der nur Filament-Profile mit passendem `inherits`
    anbietet (= Zuordnung an das Material, nicht an das Fach).
  - `app/lib/state/project_state.dart`: pro-Fach-slug persistiert
    (`project.filament_profile_slug.A<n>`).
  - `app/lib/settings/profile_writer.dart`: `ProfileWriterSlug.of()`
    oeffentlich, damit Picker-Vergleich und ProjectScreen dieselbe
    Normalisierung nutzen.
  - L10n: neue Keys `settingsSourceCaptionFilament`,
    `settingsSaveFilamentDialogTitle/Hint`,
    `settingsFilamentActiveProfile/PickTitle/PickDefault/PickEmpty/
    NoMatch` (de + en).
- Tests: 52/52 gruen (`cd app && flutter test`), inklusive 5 neuer
  Faelle in `test/settings_filament_widget_test.dart`:
  1. Ueberschrift wechselt Prozess ↔ Filament bei Bereichswechsel.
  2. Save-Button im Filament-Bereich sichtbar, disabled solange Fach
     ohne Overrides, aktiv nach erstem Override.
  3. ProfileWriter mit type=filament schreibt Preset-JSON mit
     `type: "filament"` und erwartetem `inherits`; Reader liest es
     als `SavedProfile.type == 'filament'` zurueck.
  4. Picker-Filter: `inherits == Material-Basisprofil des Fachs` →
     PETG-Profil nicht im PLA-Picker und umgekehrt; Prozess-Profile
     nicht in Filament-Pickern.
  5. ProjectState: pro-Fach-slug Round-Trip (set, Nachbar-Fach
     unberuehrt, neue Instanz liest zurueck, clear).
- APK: `app/build/app/outputs/flutter-apk/app-release.apk`
  SHA256 `0be21bbe485d7c9ebf152d7d3f9769371779f315a754d14d391eaf94b4e2f79c`,
  31 907 373 Byte, commit `1bc94ad4d5` + cli `761249e97b` eingebrannt,
  INTERNET-Permission vorhanden (Build-Guard gruen).

### Ungeprueft

- —

### Nachtrag 5 (zweiter 1051-Erfolgsfall + Composite-Dauer + Historie-"Nicht verbunden")

Klaus hat am Poco 18:15 Ortszeit den Zeitraffer der
Abnahmedruck-Session komponieren und herunterladen lassen; Video
ist in Movies/Handslice sichtbar. Galerie-Ablage damit abgenommen.

MQTT-Mitschnitt hat den Vorgang erfasst
(logs/cc2-sniff-2026-10-26-152237.jsonl):

| Zeit (UTC) | Ereignis | Beleg |
|---|---|---|
| 17:14:26.885 | `method 1036` Request | pre-check history |
| 17:14:27.392 | `method 1036` Response | Historie geladen |
| 17:14:51.976 | `method 1051` Request | `url: picture/handslice_1793029586062.gcode20261026234633` |
| 17:14:52.177 | `method 1051` Response ok | `url: video/handslice_1793029586062.gcode20261026234633.mp4` |
| 17:14:52.382 | `status 1 → 12, sub_status → 3020` | **Composing beginnt** |
| 17:15:15.531 | `sub_status 3020 → 3021` | Composing abgeschlossen |
| 17:15:15.531 | `method 1036` Request (zweite) | Erfolgs-Verifikation |
| 17:15:15.531 | `status 12 → 1` | zurueck idle |

**Composite-Dauer** (3020 → 3021): **23.149 s**.

Damit ist der 2a/2b-Pfad fuer diesen Druck end-to-end belegt:
startPrint → Druck → 1051 → 3020→3021 → 1036 → Download →
MediaStore (Movies/Handslice). mqtt-sniff anschliessend
beendet (PID 49144).

### Historie-Reiter: "Nicht verbunden" statt "Noch keine Drucke"

Beobachtung: wenn die App nicht beim Drucker war, meldete der
Reiter "Druckhistorie" trotzdem "Noch keine Drucke."
`CanvasConnection.connected` kann true sein, bevor `method 1036`
jemals geantwortet hat (direkt nach Pairing, oder nach
MQTT-Reconnect ohne Request).

Fix: zusaetzliches Flag `_hasFetched`, das nur nach einer
erfolgreichen `getHistory()`-Antwort auf true geht. Die
Not-Connected-View bleibt sichtbar, bis `_hasFetched && connected`
beide true sind. Widget-Test
`Reiter Drucker: ohne 1036-Antwort bleibt Hinweis sichtbar` deckt
den Standardfall ab (`PrinterState` im Default-Zustand → Hinweis,
keine "Noch keine Drucke"-Meldung). 3/3 PrinterScreen-Tests gruen.

### Nachtrag 4 (Override `nozzle_temperature_range_high=230` im Abnahme-G-Code belegt)

Klaus' Hinweis: "my-test" hatte NICHT die Drucktemperatur ueberschrieben,
sondern nur `nozzle_temperature_range_high` von 240 auf 230 gesenkt.
Deshalb steht im MQTT-Mitschnitt bei den Hot-End-Setpoints 220 °C
(= Rapid-PLA+-Default). Zur Verifikation die hochgeladene Datei direkt
vom Drucker geholt und im Config-Block geprueft:

```
GET http://<cc2-ip>/download?X-Token=<access>&file_name=handslice_1793029586062.gcode
→ 221 140 B (identisch zur Vorhersage und zur 1044-Groesse)
```

Config-Block (ab Zeile 9384):
```
; nozzle_temperature       = 220
; nozzle_temperature_range_high = 230   ← Override von Klaus (default 240)
; nozzle_temperature_range_low  = 190
```

Beleg vollstaendig: der Filament-Override aus dem "my-test"-Profil ist
in der CLI aufgeloest und im an den Drucker uebertragenen G-Code
sichtbar. Die MQTT-Zeitachse weiter oben zeigt deshalb konsistent
220 °C als Hot-End-Target – das ist der Druck-Setpoint, nicht die
Range-Grenze.

### Nachtrag 3 (Overrides-Counter respektiert geladenes Profil + Mitschnitt-Auswertung)

- Commit `a138bcf`: `SettingsOverrides` kennt eine Baseline; count,
  has, reset beziehen sich jetzt auf das geladene Profil, nicht
  mehr auf den Orca-Default. Save-Button bei aktivem Profil zeigt
  "Profil aktualisieren" (Primary) + "Als neues Profil…"
  (PopupMenu). Prozess und Filament gleichermaßen. Reset bringt
  Profil-Keys auf Profil-Wert zurueck, Nicht-Profil-Keys loescht
  er. 66/66 Tests gruen (10 reine Baseline-Tests + ein UI-Test
  "Overrides-Count zeigt Abweichungen vom geladenen Profil").

- Abnahme-Mitschnitt `logs/cc2-sniff-2026-10-26-152237.jsonl`
  (Laufzeit 14:22–16:43 UTC) ausgewertet, Zeitachse in
  docs/networking-cc2.md ("Abnahmedruck 2026-10-26: MQTT-
  Zeitachse"). Kernzahlen:
  - Druckstart 15:46:33 UTC (`1020` → `status 1→2`).
  - Hot-End-Setpoints 140 → 200 → 180 → **220 °C** (= Default
    des Rapid-PLA+-Presets aus `fdm_filament_pla.json`), Bett
    **60 °C**. **Kein wirksamer Düsen-Override** im Mitschnitt.
  - Druckende 16:01:54 UTC (`status 2→1`), Netto 15 m 21 s;
    CLI-Vorhersage war 9 m 25 s. Delta erklaert sich aus
    `bedlevel_force=true` (≈ +200 s) + Pre-Heat ~2 min.
  - **Kein `1051`, kein Status 12, kein 3020→3021, kein zweites
    `1036`, keine Download-Spur** nach dem Druck – Zeitraffer-
    Composite wurde in diesem Druck nicht angetippt.

### Nachtrag 2 (Filament-Assets vollstaendig + Slice-Beleg)

Problem bei der Abnahme: Fehler beim Slicen auch mit Basisprofil,
unabhaengig von "My Test". Direkte Pruefung am Poco mit `run-as`
zeigt den Grund: `files/profiles/Elegoo/filament/ECC2/` enthielt
nur `Elegoo PLA @ECC2.json` (1168 B, 2026-10-25 12:58). Alle
anderen Mapping-Zielnamen (Rapid PLA+, PETG, PLA PRO, PETG HF
usw.) fehlten komplett – `_extractBundledProfiles()` extrahierte
nur die harte Liste aus pubspec.yaml, und die hatte nur das PLA
drin. APK-Beleg: `unzip -l app-release.apk | grep filament.*ECC2`
→ 1 Zeile.

Fix (Commit `ec9098b`):
- Alle 30 ECC2-Filamentprofile + 7 Elegoo-BASE + 8
  fdm_filament_*-Common aus engine/OrcaSlicer/resources nach
  app/assets/profiles/Elegoo/filament/ kopiert.
- pubspec.yaml: Verzeichnisse statt Hand-Liste.
- _extractBundledProfiles(): iteriert jetzt ueber
  AssetManifest.loadFromAssetBundle; ueberschreibt bei abweichender
  Byte-Laenge (App-Updates mit frischeren Profilen wirksam).
- Vertragstest `filament_mapping_assets_test.dart` deckt alle
  Mapping-Zielnamen, BASE-Dateien und fdm-Common-Dateien ab.
- Picker-Zeile zeigt "Standard (Basisprofil)" statt "–"
  (settingsFilamentActiveProfileNone de+en).

Nachweis am Poco (Release-APK SHA `79af3208...081c`, commit
`ec9098b471`):
- `files/profiles/Elegoo/filament/ECC2/` enthaelt jetzt **30**
  Dateien (vorher: 1). Gesamt 52 Profile unter files/profiles.
- Direkt-Aufruf der CLI mit
  `--filament "profiles/Elegoo/filament/ECC2/Elegoo Rapid PLA+ @ECC2.json"`
  liefert RC=0, 220 261 B G-Code (9m 25s, 3.52g); G-Code zeigt
  `filament_density: 1.25`, `M109 S220` – korrektes Rapid-PLA+-
  Preset wurde aufgeloest.
- Screenshot `docs/screenshots/4-4-nacharbeit-04-filament-standard-label.png`
  zeigt Picker-Zeile "Standard (Basisprofil)" + "Basisprofil:
  Elegoo Rapid PLA+ @ECC2" am aktiven A4-Fach.
- Tests: 55/55 gruen.

### Nachtrag (nach Install via WLAN-ADB)

- USB-ADB brach reproduzierbar mit `errno 71 (Protocol error)`
  beim ersten CNXN-Paket ab (Kabel-/Port-Hardware), auch nach
  Poco-Neustart. Umstieg auf WLAN-ADB:
  `adb pair 192.168.0.15:40543` + `adb connect 192.168.0.15:42745`,
  Install via `adb -s 192.168.0.15:42745 install -r -g`.
- Install: `Success` (APK SHA
  `0be21bbe485d7c9ebf152d7d3f9769371779f315a754d14d391eaf94b4e2f79c`).
- Badge am Startbildschirm: `v0.1 · app 1bc94ad4d5 · cli 761249e97b`,
  Build-Time `2026-10-26T14:37Z` – stimmt mit dem Repo-HEAD.
  Screenshot: `docs/screenshots/4-4-nacharbeit-01-start-badge.png`.
- Filament-Bereich: Caption lautet jetzt
  "Filament-Einstellungen — erzeugt aus OrcaSlicer 2.4.2.",
  "Als Profil speichern"-Button sichtbar rechts in der
  Overrides-Count-Zeile, Picker-Zeile "Filament-Profil" mit
  Chevron darueber. Screenshot:
  `docs/screenshots/4-4-nacharbeit-02-filament-save-button.png`.
- Vergleich Prozess-Bereich: Caption bleibt
  "Prozess-Einstellungen — erzeugt aus OrcaSlicer 2.4.2.",
  Save-Button ebenfalls vorhanden (ausgegraut mangels Overrides).
  Screenshot:
  `docs/screenshots/4-4-nacharbeit-03-prozess-vergleich.png`.

## 2026-10-26 09:30 UTC – Test E: `method 1047`-Shape-Probe (danielcherubini#432) → eindeutig 11× `1003`

Lesender Beitrag zum HA-Integration-Issue #432. Repo-Clone
`v2.16.0-beta.2` unter `~/upstream/elegoo-homeassistant/` (nicht
im Handslice-Repo). Wrapper `~/upstream/run-cc2-probe.py` baut
`argparse.Namespace` und ruft `probe()` als Coroutine auf –
Access-Code bleibt im Python-Speicher, nie in argv/environ/
Shell-History.

### Nachweislich

- `scripts/cc2_probe_delete.py` mit `--run`:
  **11/11 Varianten** antworteten **identisch mit `error_code=1003`**.
  **Alle 11 Dateien weiterhin im 1044-Listing** (`still_listed=True`).
  Response-Latenzen 9.5–20 ms.
- Firmware aus `method 1001 software_version.ota_version`:
  `02.01.01.07`. Modell: Centauri Carbon 2. MCU/SOC-Versionen leer.
- **Scrub + grep-Verifikation**: `~/upstream/scrub-cc2-probe.py`
  → 0 Treffer fuer IP, SN, Access-Code in beiden Capture-Artefakten
  (JSON + Paste-Block).
- Probe-Report-Conclusion (woertlich):
  *„on this firmware 1003 is not about the parameter key at all —
  1047 is simply not served, or 1003 is its generic 'not available
  / not handled' answer. The key-name hypothesis is not supported
  by this capture."*
- **12 Probe-Dateien liegen am Drucker** (1 Preflight aus dem
  Trockenlauf + 11 aus `--run`, je 8 244 B). Volle Liste via
  `method 1044 storage_media=local`:
  ```
  cc2_probe_preflight_4c7873f1.gcode
  cc2_probe_bare_filename_4b2c6afa.gcode
  cc2_probe_control_empty_f37ccc43.gcode
  cc2_probe_local_file_name_c91794d7.gcode
  cc2_probe_local_file_name_path_8b21691e.gcode
  cc2_probe_local_filename_a11642c5.gcode
  cc2_probe_local_filename_path_e4bce5b0.gcode
  cc2_probe_sd_card_filename_72c2db59.gcode
  cc2_probe_sdcard_file_name_5bcbe9ce.gcode
  cc2_probe_sdcard_filename_186d7bb2.gcode
  cc2_probe_u_disk_filename_123c452e.gcode
  cc2_probe_udisk_filename_f2783b77.gcode
  ```
  Klaus loescht sie am Display. ~96 KB belegt.

### Ungeprueft

- Die alternative Lesung „1003 ist generische 'not-available /
  not-handled'-Antwort auf dieser FW" bleibt nicht widerlegt und
  nicht bestaetigt. Zur Unterscheidung von „1047 schlicht nicht
  serviert" braechte es einen anderen Pfad (z. B. Firmware-Unpack,
  Dekompilierung) – ausserhalb dieses Auftrags.
- Discovery-Verhalten im Script: Broadcast an 255.255.255.255 **und**
  Subnet-Broadcast 192.168.0.255 blieben in diesem LAN ohne
  Antwort; direkter Unicast an `<cc2-ip>:52700` klappt (seit
  2026-10-25 bekannt). Workaround im Wrapper: SN statisch gesetzt
  (`--serial <cc2-sn>`).

### Geht nicht

- **`method 1047` entfernt auf FW 02.01.01.07 keine Datei**,
  unabhaengig von jedem der 11 getesteten Params-Shapes.
  Fuer App-Pfade: Datei-Loeschung nicht ueber MQTT abbilden; nur
  Display-Pfad existiert.

### App-Konsequenz (M5 Ergaenzung)

- `method 1047` **in der App gar nicht erst aufrufen**. Zu
  entfernende G-Code- oder Zeitraffer-Dateien bleiben Display-
  only.
- `method 1038` entfernt Historie-Eintraege (Test D), nicht die
  Datei – dieser Pfad bleibt der UI-Hygiene-Mechanismus.
- Issue-#432-Draft (`docs/upstream/`) kann um den Hinweis
  „#432 ist durch den Shape-Probe entschieden: Hypothese
  nicht gestuetzt" ergaenzt werden.

### Artefakte

- `~/upstream/run-cc2-probe.py` – Wrapper mit sauberem
  Credential-Pfad.
- `~/upstream/scrub-cc2-probe.py` – Scrub + grep-Verifikation.
- `~/upstream/elegoo-homeassistant/scripts/cc2_probe_20261026_092850.json.scrubbed`
  – vollstaendige Capture, anonymisiert.
- `/tmp/cc2-run-stdout.txt.scrubbed` – Paste-Block, anonymisiert.
  Beide bleiben lokal (nicht im Handslice-Repo).

Nichts committed, nichts gepusht (dieser Abschnitt wird gleich
mitgenommen).

---

## 2026-10-26 15:40 MEZ – Phase-4.4-Nacharbeiten: arm64-Lauf + CLI-Override-Typen abgesichert

### Nachweislich

- **cli-contract-arm64.sh am Poco** komplett grün: Abschnitte
  1-4 (Flag-Vertrag + Z-Diff), 5 (Phase-4.3-Overrides),
  6 (Ungueltiger Key abgelehnt), 7 (libslic3r-Validate-Fehler
  sauber abgefangen) **und Abschnitt 6 (Phase 4.4
  Filament-Overrides)** – byte-identische Baseline (modulo
  Timestamp-Zeile), M104 S260, M190 S88 A, G1 E-2.4. Hinweis:
  Baseline-Vergleich im arm64-Teil nutzt jetzt dieselbe
  `md5_sanitized`-Funktion wie der x86-Vertragstest, weil die
  Timestamp-Zeile sonst zwei frische Laeufe nie byte-gleich
  macht.
- **CLI-Overrides-Typsicherung**
  (`engine/cli/handslice-cli.cpp`): JSON-Zahlen (int+float) und
  Booleans werden zu Strings konvertiert, Strings bleiben
  unveraendert. **Arrays werden explizit abgelehnt** mit einer
  Fehlermeldung, die den Key und einen Hinweis `["250"]` →
  `"250"` nennt. Null-Werte ebenfalls mit klarer Meldung.
  Help-Text im `--help` ergaenzt um einen Abschnitt zu
  `--overrides`.
- **Vertragstest `engine/test/overrides-types-contract.sh`**
  (lokal x86, 4 Checks):
  - Int `nozzle_temperature: 260` → `M104 S260` im G-Code.
  - Bool `enable_pressure_advance: true` → exit 0, Bool-Array
    `[true]` wird abgelehnt.
  - Array `nozzle_temperature: [260]` → exit != 0, Fehlermeldung
    nennt den Key und das Wort „array", kein terminate/abort.
  - Null `nozzle_temperature: null` → exit != 0, Fehlermeldung
    erwaehnt „null".
- **x86 + arm64 CLI neu gebaut** auf Commit-Stand des aktuellen
  HEAD (Phase-4.4-Commit). arm64 Binary ist noch nicht in jniLibs
  der App gewandert – das macht der naechste App-Build. Der
  Vertragstest in Abschnitt 6 lief auf dem **neuen** arm64-Binary.
- **Bestehende Vertragstests** `filament-overrides-contract.sh`
  und `scale-contract.sh` nach dem Rebuild weiterhin grün.

### Ungeprueft

- Enum-opt_keys als JSON-Zahl (z. B. `bed_type: 3` statt `"3"`):
  der Code konvertiert den Int zu `"3"` und reicht ihn in Orcas
  Preset-Parser. Das sollte funktionieren, ist aber nicht
  explizit getestet. Phase 4.4 nutzt diesen Pfad nicht.

### Geht nicht / Konsequenz

- Weiterhin kein `null` erlaubt. Die App soll Overrides, die auf
  Default zurueckgesetzt wurden, per `SettingsOverrides.reset(key)`
  komplett entfernen, nicht als `null` schicken.

### Artefakte

- `engine/cli/handslice-cli.cpp` – Override-Validierung + Help.
- `engine/test/overrides-types-contract.sh` – neuer Vertragstest.
- `engine/test/cli-contract-arm64.sh` – `md5_sanitized`-Fix im
  Phase-4.4-Abschnitt.
- `engine/bin/handslice-cli-x86` / `-arm64` – neu gebaut, Commit
  `761249e97b`.

---

## 2026-10-26 15:15 MEZ – Phase 4.4 Filament-Einstellungen pro Fach

Pendant zu Phase 4.2 (Prozess) + 4.3 (Save-as-Profil), diesmal fuer
den Filament-Bereich mit CANVAS-A1..A4-spezifischen Overrides.

### Nachweislich funktioniert

- **Material → Orca-Profil-Mapping** (`app/lib/settings/filament_mapping.dart`):
  - ELEGOO PETG → `Elegoo PETG @ECC2.json`
  - ELEGOO RAPID PETG → `Elegoo Rapid PETG @ECC2.json`
  - ELEGOO PLA PRO → `Elegoo PLA PRO @ECC2.json`
  - ELEGOO RAPID PLA+ → `Elegoo Rapid PLA+ @ECC2.json`
  - PLA-Typ ohne Markenname → `Elegoo PLA @ECC2.json` (generisch,
    kein Fallback-Hinweis).
  - Alles andere → `Elegoo PLA @ECC2.json` **mit sichtbarem
    Hinweis** `fallbackReason`.
- **Per-Fach-Overrides** (`FilamentOverrides`): 4 Instanzen (A1..A4),
  persistent in SharedPreferences unter
  `filament.overrides.A<n>`. Fachwechsel haelt die Maps strikt
  getrennt (Unit-Test
  `app/test/filament_overrides_test.dart`), Save/Reload
  roundtrip-sicher.
- **Settings-UI** (`app/lib/screens/settings_screen.dart`):
  - Area-Toggle oben: **Prozess | Filament**.
  - Im Filament-Bereich zusaetzlich A1..A4-Fach-Umschalter mit
    Material-Label pro Fach aus `PrinterState.slots` (2005).
  - Unter dem Umschalter die Fallback-Hinweis-Zeile mit gelbem
    Info-Icon, wenn `FilamentProfileRef.generic == true`.
  - Reiter+Gruppen aus Schema `area=filament`
    (7 Reiter / 22 Gruppen / 83 Optionen, siehe Phase 4.1).
  - „Als Profil speichern" bleibt nur im Prozess-Bereich sichtbar
    (Filament-Overrides sind pro Fach persistent und brauchen
    keinen Save-Dialog).
- **Slicer-CLI-Durchreichung** (`app/lib/engine/slicer.dart` +
  `app/lib/state/project_state.dart`):
  - CLI nimmt `--filament <pfad>` mehrfach entgegen
    (Beleg: `engine/cli/handslice-cli.cpp:145` + 592, bereits
    bestehend). Fuer Phase 4.4 reicht **ein** Fach; Multimaterial
    kommt spaeter.
  - App waehlt beim Slicen das Filamentprofil des aktiven Fachs
    (`trayAssignmentForTool0`) und reicht die Fach-Overrides
    gemerged mit den Prozess-Overrides per `--overrides` an die
    CLI. Prozess- und Filament-opt_keys sind disjunkt im Schema.
- **Bettemperatur pro Plattenart** belegt
  (`engine/test/filament-overrides-contract.sh`, lokal x86):
  Baseline-Doppel-Lauf **byte-identisch** (modulo Timestamp-Zeile),
  dann drei Einzel-Overrides mit G-Code-Marker:

  | Override | opt_key | G-Code-Beleg |
  |---|---|---|
  | Duesentemperatur 260 °C | `nozzle_temperature=260` | `M104 S260 ; set nozzle temperature` |
  | Hot-Plate initial 88 °C (Seite B) | `hot_plate_temp_initial_layer=88` | `M190 S88 A` am Pre-Heat |
  | Retract 2.4 mm | `retraction_length=2.4` | `G1 E-2.4`-Zuege statt Baseline 0.728 |

- **Vertragstest arm64** (`engine/test/cli-contract-arm64.sh`
  Abschnitt „=== 6 Filament-Overrides"): dieselben drei
  Checks mit `adb` am Poco. Laeuft Klaus beim naechsten Device-
  Test; Logik und erwartete Marker sind identisch zum x86-Test.
- **Widget-Tests gruen**
  (`app/test/settings_filament_widget_test.dart`, 2 Tests):
  Fachwechsel A1 ↔ A3 haelt Overrides getrennt + Persistenz-
  Roundtrip; unbekanntes Material zeigt Fallback-Hinweis mit
  „nicht erkannt".
- **Alle Tests zusammen gruen:** 47/47 (`flutter test test/`).
- **APK via `build_apk.sh --release`**:
  - SHA256 `b4e63a97daa11b729d22c900625e624093ad4d7680d1961fc0baf4af57600e29`
  - 31.9 MB, Commit-Guard greift, INTERNET-Permission vorhanden.
  - Auf Poco installiert; Smoke-Nachweis
    `local-test/phase44-step1.png`: Einstellungen-Reiter mit
    **Area-Toggle „Prozess | Filament"** oben sichtbar + Zaehler
    „Keine Ueberschreibungen" und „Als Profil speichern"-Button
    (nur im Prozess-Bereich).

### Ungeprueft

- **Multimaterial** (mehrere `--filament`-Flags gleichzeitig mit
  Pro-Filament-Overrides): die CLI-Logik ist aktuell so, dass
  Overrides nach dem letzten Filament-Profil global ueber die
  Config geschichtet werden – fuer Mehrfarbe muss ein eigenes
  Mapping Fach→Werte-Set rein. Fuer Phase 4.4 nicht gebraucht
  (Klaus startet mono-material).
- **Live-Vertragstest am Poco**: `cli-contract-arm64.sh` muss
  Klaus beim naechsten Lauf triggern; die Logik ist durch die
  x86-Variante bereits grün.

### Geht nicht / Konsequenz

- Overrides-Werte muessen als **String** uebergeben werden
  (`"88"`, nicht `[88]` oder `88` als Int). Grund: Orcas Overrides-
  Parser schaltet nur bei String-Werten den `coInts`-Pfad korrekt;
  JSON-Arrays werden roh als `"[88]"` serialisiert und fallen in
  Orcas Validate. In `SettingsOverrides.set(key, value)` ist das
  schon so vorgesehen; neue Edit-Widgets muessen das weiter
  einhalten.

### Artefakte

- `app/lib/settings/filament_mapping.dart` – Material→Profil.
- `app/lib/settings/filament_overrides.dart` – Pro-Fach-State.
- `app/lib/screens/settings_screen.dart` – Area-Toggle + Fach-
  Umschalter + Fallback-Hinweis.
- `app/lib/engine/slicer.dart` + `project_state.dart` –
  Filament-Pfad + gemergte Overrides zur CLI.
- `engine/test/filament-overrides-contract.sh` – x86-Vertragstest.
- `engine/test/cli-contract-arm64.sh` Abschnitt 6 – arm64-
  Vertragstest (laeuft Klaus beim naechsten Lauf).
- `app/test/filament_overrides_test.dart` + `settings_filament_widget_test.dart`.
- `local-test/phase44-step1.png` – Smoke-Screenshot.

Kein Druck in dieser Session; den startet Klaus.

---

## 2026-10-26 12:07 MEZ – Phase 5 am echten CC2 bestaetigt (offener 1051-Erfolgsfall geschlossen)

Klaus hat den ganzen Fluss gegen den realen CC2 durchgespielt.

### Nachweislich

- Druck mit Zeitraffer **aus der App** gestartet (Fach **A3**, PLA
  Pro schwarz – freie Fachwahl funktioniert, nicht nur A4). Nach
  Druckende Historien-Eintrag mit `video_status=1`.
- In der App „Video erzeugen" → App ruft `method 1051`
  `params.url=picture/<name><ts>`. Nach `machine_status.status
  12 → 1` holt die App automatisch `method 1036` neu; Target-
  Eintrag ist jetzt `video_status=2` + `video/<name><ts>.mp4`.
- Head-Probe liefert HTTP 200; Download-Button startet den
  tatsaechlichen Pull aufs Handy.
- Share-Intent via `share_plus` funktioniert.
- Video-Properties identisch zum heute-frueh-USB-Composite:
  **640×360, 100 Frames, 3,3 s**. Encoder-Pfad ist derselbe.
- **Head-Probe erkennt die am Display geloeschten alten Zeitraffer
  korrekt als „nicht mehr verfuegbar"** – kein versehentlicher
  Download-Button fuer stale `video_status=2`-Eintraege.
- **Display zeigt beim MQTT-1051 NICHTS** (anders als beim
  USB-Export, der „Video wird generiert"/„Video wird kopiert"
  anzeigt). Der Fortschritt kommt **nur ueber api_status**;
  Spinner-Pfad der App (Status 12 → 1) ist der einzige Signalweg.

Damit ist der nach Test B/C verbliebene offene Punkt „1051 im
Erfolgsfall ueber MQTT" **geschlossen**.

### Ungeprueft

- **Exakte Composite-Dauer** ueber MQTT (3020→3021): nicht
  gemessen – `tools/mqtt-sniff.py` lief in diesem Lauf nicht.
  USB-Export-Vergleichswert: 26 s fuer 100 Frames; App-Lauf
  laut Klaus „nicht lange" (vermutlich dieselbe
  Groessenordnung, Encoder identisch). Konkrete Zahl beim
  naechsten Lauf nachtragen – Sniff vorher starten.

### Geht nicht / Nacharbeit

- **Download-Ablage versteckt**: aktuell schreibt die App nach
  `getExternalStorageDirectory()/handslice-timelapses/`, das ist
  der app-eigene Pfad unter `/storage/emulated/0/Android/data/
  dev.handslice.handslice/files/handslice-timelapses/`. Dort
  **nicht in der Galerie sichtbar** und **bei Deinstallation
  weg**. Share-Intent funktioniert zwar, aber der Weg „einfach
  Galerie oeffnen" fehlt.
- Nacharbeit (nicht in diesem Commit): entweder in den
  **oeffentlichen Downloads-Ordner** schreiben (`/storage/
  emulated/0/Download/`, braucht ab API 30
  `WRITE_EXTERNAL_STORAGE` / `MANAGE_EXTERNAL_STORAGE` oder
  Storage-Access-Framework) **oder** per **MediaStore-API** nach
  `MediaStore.Video.Media` eintragen (dann in der Galerie
  sichtbar, keine extra Berechtigung noetig ab API 30). Letzteres
  ist der moderne Weg; braucht ein kleines Platform-Channel-
  Integral, da Flutter das nicht out-of-the-box koennen.
- Als **offenes M5-Follow-up** vermerkt; nicht blockierend fuer
  Phase 5.

### App-Konsequenz

- Keine Code-Aenderung noetig – M5 funktioniert so, wie
  spezifiziert.
- Issue-Draft fuer `danielcherubini#432` entfaellt die „currently
  inconclusive"-Reserve zum 1051; der Draft wird entsprechend
  umgestellt.

### Artefakte

- MP4 des Phase-5-Testdrucks liegt auf Klaus' Handy.
- `tools/mqtt-sniff.py` – nicht gelaufen; falls Klaus beim
  naechsten Zeitraffer-Druck Zahlen will, vorher starten.

Nichts committed in diesem Lauf gegenueber dem Phase-5-Code;
nur Doku-Updates (networking-cc2.md Test F, PROGRESS.md,
upstream-Draft).

---

## 2026-10-26 11:45 UTC – Release-APK ohne INTERNET-Permission → Datagram-Socket-Fehler

Klaus am Poco: nach Koppeln beim „Verbinden & Faecher laden":
„Netz-/Discovery-Fehler: Netzwerk: Failed to create datagram socket".
Phase-5-Release-APK `785e5cb` konnte **keine** UDP-Discovery
aufbauen; MQTT war in Folge auch nicht erreichbar.

### Nachweislich

- **Ursache:** `android/app/src/main/AndroidManifest.xml` hatte
  **keine** `<uses-permission android:name="android.permission.INTERNET"/>`.
  Flutter hat die Permission nur im Debug-Overlay
  (`android/app/src/debug/AndroidManifest.xml`); dieses Overlay wird
  **nur in Debug-Builds** gemergt. Release-APKs bekommen die
  Permission daher nicht.
- **Beleg:** `aapt2 dump permissions app-release.apk` auf
  `785e5cb` listete nur
  `dev.handslice.handslice.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`
  (von share_plus), **keine INTERNET**. Logcat selbst war fuer
  die App leer – die Ausgabe passiert ausschliesslich in der
  Dart-UI (SnackBar); der eigentliche DNS-/Socket-Fehler wird
  nicht nach `logcat` geroutet. Der Code-Review der Manifeste
  reicht als Beweis.
- **Fix an der Wurzel:**
  `android/app/src/main/AndroidManifest.xml` enthaelt jetzt
  `<uses-permission android:name="android.permission.INTERNET" />`.
  Debug-Overlay bleibt bewusst stehen (Flutter-Konvention).
- **Zwei neue Gurtschnallen:**
  1. **Dart-Test** (`app/test/android_manifest_test.dart`):
     greppt die main-Manifest-XML nach „android.permission.INTERNET".
     Faellt schon bei `flutter test`, nicht erst beim APK-Bau.
  2. **Build-Script-Verify** (`app/scripts/build_apk.sh`):
     `aapt2 dump permissions` auf die neu gebaute APK; fehlt
     INTERNET, bricht das Skript mit Exit-Code 5 ab.

### Ungeprueft

- Realer Verbindungstest **gegen den CC2** mit dem neuen APK
  steht noch aus (direkt nach diesem Commit, in diesem Lauf).

### Geht nicht / Konsequenz

- Debug-Overlay ohne main-Permission ist eine Fluter-Falle, die
  erst im Release-Build auffaellt. Beide neuen Gurtschnallen
  verhindern eine Wiederholung: Dart-Test bricht bei Code-Change,
  Build-Verify bricht beim APK-Bau.

### Artefakte

- APK mit Fix-Commit `1b74028`:
  SHA256 `1cca86eaa3c64e769cd67224c1653d99f39ad2145e91adf175617a08f3e781b2`
  (31.8 MB).
- Auf Poco installiert, SHA256 der Device-APK **byte-identisch**
  zum lokalen Build.
- `dumpsys package dev.handslice.handslice` listet jetzt
  `android.permission.INTERNET` unter „requested permissions".
- Badge am Geraet: `v0.1 · app 1b74028313` + `cli ee4da3d7b5`
  + `2026-10-26T10:43Z` (`local-test/phase5-after-permission-fix.png`).
- „Verbinden & Faecher laden" → keine Fehler-SnackBar mehr
  (vorher sofort „Netz-/Discovery-Fehler: Netzwerk: Failed to
  create datagram socket"). Finale Pair-/Connect-Verifikation
  gegen den echten CC2 macht Klaus beim naechsten Druck-Test.

---

## 2026-10-26 11:30 UTC – Phase-5-Build-Guard: Build ohne Hashes bricht ab

Klaus hat am Poco gemerkt: der Phase-5-APK vom Vorlauf zeigte im
Badge nur `v0.1 · app – cli` (beides als `-` aus `defaultValue`),
weil ich `flutter build apk --release` direkt gerufen hatte statt
`app/scripts/build_apk.sh --release`. Dadurch fehlten die
`--dart-define`-Werte `BUILD_COMMIT` / `CLI_COMMIT` / `BUILD_TIME`.

### Nachweislich

- **Ursache belegt** (`app/lib/widgets/build_info_badge.dart:16-22`):
  `String.fromEnvironment` mit `defaultValue: '-'` – ohne
  `--dart-define` bleibt alles auf `-`. Build-Skript
  `app/scripts/build_apk.sh` setzt die drei Werte korrekt, wurde
  aber nicht benutzt.
- **Zwei-Gurt-Loesung:**
  1. **Startup-Guard in der App** (`main.dart`): neue Getter-Flagge
     `BuildInfoBadge.hasMissingMetadata`. Wenn beim Start irgendein
     Hash `-` ist, startet nicht die normale UI, sondern ein
     Vollbild-Fehler-Overlay („Build-Metadaten fehlen"). Greift
     auch im Release-Build und auch bei einem APK, das nicht via
     Skript gebaut wurde.
  2. **Verify-Schritt im Build-Skript**: Nach `flutter build apk`
     wird `lib/arm64-v8a/libapp.so` aus der APK extrahiert und auf
     den Commit-Hash gegreppt. Fehlt der Hash im AOT-Blob, bricht
     das Skript mit Exit-Code 4 ab – die APK landet nicht am Poco.
     (Direkter grep auf die APK scheitert, weil der ZIP-Container
     DEFLATE-komprimiert; deshalb Umweg ueber temp-File. Pipe
     `unzip | grep -q` scheiterte an SIGPIPE + `pipefail`.)
- **Build via Skript** erfolgreich, Verify-Schritt greift korrekt:
  ```
  Build-APK (release) commit=785e5cbb2d cli=ee4da3d7b5 time=2026-10-26T10:25Z
  APK:    build/app/outputs/flutter-apk/app-release.apk
  SHA256: 30ce0e2a7ddefb9fdbb0e68a973351af9070955d17ed1927a2c3bd819b7002cd
  size:   31799137 byte
  commit-im-APK: ok (785e5cbb2d gefunden; cli ee4da3d7b5)
  ```
  (31.8 MB statt vorher 16 MB – Default-Skript baut alle drei ABIs;
  der vorige `--target-platform=android-arm64`-Build war nur eine.)
- **Installiert auf Poco** (`adb install -r` → Success).
- **Badge-Nachweis** `local-test/phase5-badge-hashes.png` zeigt:
  ```
  v0.1 · app 785e5cbb2d
  cli ee4da3d7b5
  2026-10-26T10:26Z
  ```

### Ungeprueft

- Startup-Guard greift sicher in Debug (per `--dart-define`
  weggelassen); fuer Release ist das Verhalten per Konstruktion
  identisch (`String.fromEnvironment` ist statisch gebunden).
  Expliziter Test eines fehlerhaften Builds steht aus, aber die
  Logik ist trivial.

### Geht nicht

- Flutter kann `--dart-define` nicht aus Gradle-Pre-Hooks erzwingen;
  jemand koennte `flutter build apk --release` immer noch direkt
  rufen – dann greift aber jetzt der Startup-Guard am Gerät.

### Konsequenz

Der Weg bleibt: **immer** `app/scripts/build_apk.sh --release`.
Direkter `flutter build apk` liefert zwar ein APK, aber dieses
weigert sich beim Start und meldet den Fehler per UI.

---

## 2026-10-26 11:15 UTC – Phase 5 (Zeitraffer in der App): 5a + 5b + 5c steht

Neuer Reiter „Drucker" (vierter Tab) + Netzwerk-Pfade fuer 1036 / 1051
/ Head-Probe / Download + Lokalisierung. Vor dem echten Druck-Test
mit Klaus.

### Nachweislich

- **CC2-Mock erweitert** (`engine/test/mock-cc2/mock_cc2.py`): method
  1036 liefert eine seedbare `history_task_list`; method 1051
  simuliert den beobachteten Zustand `3020→3021→1` bei vorhandenen
  Rohframes bzw. `3020→3022→1` bei fehlenden; `GET /download`
  antwortet mit HTTP 200 + chunked + Content-Length-Doppelrahmung
  (echt-CC2-Verhalten) oder **schweigt**, wenn die Datei nicht
  existiert. Neuer CLI-Flag `--seed-history <path>` fuer Fixtures.
- **ElegooCc2Client** (`app/lib/net/elegoo_cc2_client.dart`): neue
  Typen `HistoryTask`, `TimelapseProbe` + Methoden
  `getHistory()`, `renderTimelapse()`, `probeTimelapse()`,
  `downloadTimelapse()`, `deleteHistoryEntries()`. Download-URL
  baut Access-Code als `X-Token`-Query-Param (nie in Logs). Probe
  faengt `TimeoutException`, `SocketException`, **`HttpException`**
  (letzteres fuer das reproduzierte „Firmware schliesst Connection
  ohne Response"-Signal).
- **Reiter „Drucker"** (`app/lib/screens/printer_screen.dart`):
  Liste aus 1036, nach `begin_time` absteigend sortiert
  (Reihenfolge, nicht als Datum). Pro Eintrag:
  - `video_status=0` → „kein Zeitraffer".
  - `video_status=1` → Button „Video erzeugen" → 1051 → Spinner
    bei `machine_status.status==12` → zweite 1036 + Head-Probe;
    bei `3022` oder Status bleibt 1 → „keine Rohdaten mehr
    vorhanden". Kein automatischer zweiter Versuch.
  - `video_status=2` → **Head-Probe mit 2 s Timeout**; nur bei
    HTTP 200 kommt der Download-Button, sonst „nicht mehr
    verfuegbar (am Drucker geloescht?)".
  - `video_status=3` ohne URL → „nicht erzeugbar".
  - **Hoechstens 2 parallele /download-Verbindungen** per
    einfachen Semaphor (`_DownloadLimiter`), passend zu cc2-controls
    „two-transfer limit".
  - Download speichert nach `getExternalStorageDirectory() +
    /handslice-timelapses/` (Fallback: ApplicationSupport);
    Teilen ueber Android-Share-Intent via `share_plus 13.x`.
- **Druckeruhr-Hinweis** als Bodentext (einmal pro Historie):
  „Zeitstempel stammen aus der Druckeruhr (aktuell UTC+8) und
  werden nur als Reihenfolge genutzt." Begin/End werden nie als
  absolute Zeit gerendert.
- **Lokalisierung** (ARB-Dateien): Reiter-Label `Drucker`,
  Historien-Texte, Download-/Render-Buttons + Fehler-Texte in
  DE/EN. Status 12 = „Zeitraffer wird erzeugt/exportiert",
  `exception_status 1243` = „Filamentzufuhr-Fehler – PTFE-
  Schlaeuche pruefen", sub_status 2501/2502/2401/2402 als
  Pausiert/Setzt fort.
- **Tests gegen Python-Mock** (`app/test/elegoo_mock_test.dart`):
  drei neue Phase-5-Tests – 1036+Head-Probe+Download (ok UND
  Schweigen bei fehlender Datei), 1051-Erfolgsfall
  (`3020→3021`, status 1→2), 1051 ohne Rohframes (`3020→3022`,
  Status bleibt 1). **8/8 Tests gruen**:
  ```
  00:00 +0: Mock: Discovery + Register + Canvas (richtiger Code)
  00:02 +1: Mock: falscher Code → ElegooAuthException
  00:04 +2: Mock: Upload funktioniert + Datei erscheint in FILE_LIST
  00:06 +3: Mock: method 1020 startPrint liefert error_code=0 vom Mock
  00:08 +4: Mock Phase5: 1036 + Head-Probe + Download (status 2)
  00:10 +5: Mock Phase5: 1051 Erfolgsfall (3020→3021), video_status 1→2
  00:13 +6: Mock Phase5: 1051 ohne Rohframes → 3022, video_status bleibt
  00:15 +7: Mock: Upload-Abbruch nach N byte → ElegooUploadException
  00:18 +8: All tests passed!
  ```
- **Widget-Tests** (`app/test/printer_screen_test.dart`): nicht-
  verbunden-Fall + Header/Refresh-Button. 2/2 gruen.
- **APK gebaut** (`arm64, release, 16.0 MB`), auf Poco X3 Pro
  installiert. **Smoke-Nachweis** `local-test/phase5-printer-tab.png`:
  Reiter „Drucker" aktiv, Header „Druckhistorie", Refresh-Button,
  Hinweis-Panel „Drucker nicht verbunden. Im Projekt-Reiter koppeln
  und verbinden." (als erwarteter Pfad, weil kein Pairing in dieser
  Session gemacht wurde).

### Ungeprueft

- **Echter Druck-Test gegen den CC2** (Klaus startet): kurzer
  Wuerfel-Druck mit Zeitraffer aus der App → danach in der App
  „Video erzeugen" (= der offene 1051-Erfolgsfall VOR dem
  USB-Stick) → Download aufs Handy. Mitschnitt (tools/mqtt-sniff.py)
  wird mitlaufen. **STOP vor diesem Test** – Klaus entscheidet.
- Dart's HttpClient-Verhalten bei der realen Length-vs-chunked-
  Doppelrahmung ist bei probeTimelapse getestet (via Mock, der die
  Doppelrahmung setzt), aber Download selbst nicht gegen echte CC2-
  Firmware; cc2-control-Code warnt vor dem Konflikt. Der Lesemodus
  (`await for in resp`) ist RFC-9112-konform.
- Download-Ordner auf Android: `getExternalStorageDirectory` ergibt
  App-eigene Downloads unter `/storage/emulated/0/Android/data/
  dev.handslice.handslice/files/handslice-timelapses/` – fuer die
  Galerie nicht sichtbar, aber ueber Share teilbar. Falls Klaus das
  oeffentliche Downloads-Verzeichnis bevorzugt, braecht's
  `MANAGE_EXTERNAL_STORAGE` oder `WRITE_EXTERNAL_STORAGE` (API ≤29).
  Fuer M5 reicht Share.

### Geht nicht

- `method 1038` (Delete-History) **bewusst nicht in der UI** – wie
  im Auftrag spezifiziert (Test D hat gezeigt: 1038 loescht nur
  die Historie, nicht die Datei; UI-Verwirrung soll vermieden
  werden).

### App-Konsequenz (Echttest-Checkliste)

Vor dem echten Druck-Test:

1. Drucker Idle, „Nur LAN"-Modus aktiv.
2. Home Assistant / sonstige Integration getrennt (einer der
   Register-Slots muss frei sein).
3. `tools/mqtt-sniff.py` starten, damit Status-12-Deltas und
   api_status gesichert sind.
4. In der App: Projekt-Reiter → verbinden → Zeitraffer-Switch an
   → kleiner Wuerfel-Druck senden.
5. Nach Druckende, VOR dem USB-Stick: Drucker-Reiter → „Video
   erzeugen" am frischen Status-1-Eintrag → Spinner bis Status
   zurueck auf Idle → Download.

### Artefakte (nicht committed in diesem Lauf)

- `local-test/phase5-printer-tab.png` – Smoke-Screenshot.
- APK unter `app/build/app/outputs/flutter-apk/app-release.apk`.

Dieser Eintrag selbst wird gleich committed.

---

## 2026-10-26 08:35 UTC – Test D: `method 1038` loescht Historie, nicht MP4, nicht Display

### Nachweislich

- **Payload exakt nach cc2-control-Beleg**:
  `{"method":1038,"id":1038,"params":{"list":["<task_id>"]}}`
  (Fundstellen: `mqtt.c:277-287`, `mqtt.c:343-346`,
  `history.h:123-142`).
- **Response**: `{"id":1038,"method":1038,"result":{"error_code":0}}`
  in **297 ms**. **Kein Status-12-Wechsel**; der Loeschvorgang
  passiert daten-/datenbankseitig ohne Printer-State-Transition.
- **1036 Pre vs. Post:**
  - Pre: `sha256=e12d373a3ec5c57b`, 45 Tasks, `result.total=45`.
  - Post: `sha256=4c9f1271e71c3a3d`, **44 Tasks**, `result.total=44`.
  - **Target `e0b592f4-...` ist entfernt**; alle anderen Eintraege
    byte-identisch (keine Nebenbeitraege mutiert, keine
    `duration`- oder `video_status`-Verschiebungen).
- **MP4 bleibt vollstaendig abrufbar.** Download-Probe nach 1038
  liefert `HTTP 200`, 1 741 634 Byte, md5
  `e2330f840b398f425172b32692437f7a` – **byte-identisch** zur
  Baseline und zur Pre-Snapshot.
- **Display zeigt den Eintrag weiter.** Klaus hat am Display
  nachgeschaut: Zeitraffer-Liste zeigt den Eintrag noch, obwohl
  er aus der 1036-Historie entfernt ist.
- **Neues Feld `result.total` entdeckt** – ein Zaehler auf
  `result`-Ebene (Pre 45 → Post 44). cc2-control nutzt es
  nicht, aber die Firmware exponiert es. Fuer die App ein
  zusaetzlicher Konsistenz-Check.

### Zusammenfuehrung mit Display-Loeschen (Vormittag heute)

Die beiden Loeschpfade sind **komplett getrennt**:

| Loeschpfad | 1036-Historie | MP4 (`/opt/usr/video/`) | Display-Liste |
|---|:-:|:-:|:-:|
| **method 1038** (dieser Lauf) | **weg** | bleibt | bleibt |
| **Display-Loeschen** (Vormittag) | bleibt (stale) | **weg** (Download → Timeout) | **weg** |

Das heisst konkret: der Drucker fuehrt die MQTT-Historie und das
Dateisystem/Display als zwei unabhaengige „Realitaeten". Es gibt
im LAN-API-Namensraum **keinen Weg**, das MP4 oder die
Display-Liste zu beeinflussen; umgekehrt entfernt Display-Loeschen
nicht die MQTT-Historie.

### Ungeprueft

- Ob `method 1038` **mehrere Tasks** auf einmal loescht
  (`list:["a","b","c"]`). cc2-control baut die Params genau so
  – wir haben nur eine ID in diesem Lauf getestet.
- Verhalten bei nicht-existierender `task_id`. Vermutlich
  `error_code=0` ohne Mutation (konsistent zur 1047-Beobachtung
  vom 25.10. – Firmware signalisiert Nicht-Existenz nicht).
- Ob das `result.total`-Feld in **allen** 1036-Antworten
  erscheint oder nur unter bestimmten Firmwares; die Vormittags-
  Antworten hatten es offenbar auch, nur haben wir es nicht
  explizit beachtet.
- Was aus dem physischen MP4 wird, wenn `method 1038` seinen
  History-Eintrag entfernt. Es ist dann im LAN nicht mehr
  adressierbar (fehlt die `video_url`), liegt aber physisch auf
  `/opt/usr/video/`. Vermutlich wird es durch den naechsten
  Druck oder Speicher-Housekeeping entfernt – nicht in diesem
  Test beobachtbar.

### Geht nicht

- **Speicher auf dem Drucker ueber `method 1038` freigeben.** Das
  MP4 bleibt; der Platz in `/opt/usr/video/` wird nicht frei. Fuer
  Speicher-Management braucht es das Drucker-Display.
- Display-Liste ueber MQTT aufraeumen. Es gibt keinen beobachtbaren
  MQTT-Pfad, der die Display-Liste synchronisiert.

### App-Regel (Historien-Pflege)

- `method 1038` ist **reine UI-Hygiene**. Die App darf damit die
  eigene Historien-Ansicht aufraeumen (z. B. fehlgeschlagene oder
  Status-0-Eintraege), aber:
  - **Nicht als Speicher-Management verkaufen.**
  - Beim Entfernen von Zeitraffer-Eintraegen in der UI klarstellen,
    dass das Video auf dem Drucker verbleibt und am Display
    separat geloescht werden muss, um Platz zu schaffen.
- Nach `method 1038` die lokale Historie-Ansicht aus der neuen
  1036-Antwort neu aufbauen (nicht nur optimistisch den Eintrag
  streichen – der Zaehler `result.total` ist der
  Konsistenz-Check).

### Artefakte

- `tools/cc2-delete-history.py` – sendet 1038 fuer eine Task-ID,
  Idle-Check vorweg, keine Retries.
- `logs/cc2-sniff-2026-10-26-093126.jsonl` – Mitschnitt
  waehrend 1038 (git-ignoriert).
- `docs/cc2-history-sample.json` – Post-1038-Snapshot (44 Tasks,
  neue Hash `4c9f1271e71c3a3d`).

Nichts committed, nichts gepusht.

### Offener Punkt bleibt

- Erfolgreicher 1051 (`3020→3021`) beim naechsten Zeitraffer-Druck,
  direkt nach dem Druck, vor dem USB-Export (Script
  `tools/cc2-render-timelapse.py` liegt bereit).

---

## 2026-10-26 08:30 UTC – Sende jetzt method 1038 (Delete-History) fuer heutigen Eintrag

**Einziger Schreibbefehl**: `method 1038 params={"list":["<task_id>"]}`
fuer `task_id=e0b592f4-bd51-4ece-97fc-2bfc8137d13e` (heutiger Lauf 2,
`video_status=2`, MP4 1 741 634 B md5 `e2330f840b398f425172b32692437f7a`).
Klaus hat zugestimmt, dass dieser Eintrag verloren gehen darf; MP4
liegt auf USB-Stick und in `local-test/`.

Payload-Beleg (nicht geraten):

- `cc2-control/src/mqtt.c:343-346` –
  `mqtt_delete_history(c, params)` ruft
  `publish_request(c, 1038, params)`.
- `cc2-control/src/mqtt.c:277-287` – `publish_request` baut
  `{"method":<m>,"id":<m>,"params":<params>}`, d. h. id=1038.
- `cc2-control/src/history.h:123-142` – Params-Aufbau:
  `{"list":["<id1>",...]}` mit einem Element pro Task.

Daraus **final:**

```json
{"method":1038,"id":1038,"params":{"list":["e0b592f4-bd51-4ece-97fc-2bfc8137d13e"]}}
```

Vor dem Senden:
- 1036-Hash: `e12d373a3ec5c57b` (seit heute Vormittag unveraendert).
- Target in Liste vorhanden (`video_status=2`, size=1 741 634,
  duration=3, url=`video/<name>.mp4`).
- Download-Probe erfolgreich: HTTP 200, md5 unveraendert.
- Klaus hat vorher am Display geprueft, dass die Zeitraffer-Liste
  genau diesen einen Eintrag zeigt.

Mitschnitt laeuft parallel. Erwartung: eine von drei Aussagen –
(a) Historie weg, MP4 bleibt / (b) Historie weg, MP4 weg /
(c) `error_code != 0`, nichts geaendert.

Antwortet 1038 mit `1003`: dokumentieren, kein zweiter Versuch.

---

## 2026-10-26 08:20 UTC – Test C: 1051 mit picture-URL → wieder `3022`; Rohframes gab's hier nie mehr

### Nachweislich

- URL-Herleitung aus
  `video/handslice_1792947629010.gcode20261026143807.mp4` zu
  `picture/handslice_1792947629010.gcode20261026143807`
  wurde eindeutig aus den Quellen abgeleitet (siehe
  `networking-cc2.md` Test-C-Abschnitt).
- **Response:** `error_code=0`, Response-URL
  `video/<basename>.mp4` (= der bestehende Pfad des Target-MP4),
  Latenz **18 ms**.
- **Status 12 Dauer: <1 ms** – alle drei api_status-Deltas tragen
  denselben Zeitstempel `08:17:37.794`. Pfad `3020→3022→1`.
- **1036 Vorher/Nachher: byte-identisch**
  (`sha256(result)=e12d373a3ec5c57b` beide Male). Target
  unveraendert, kein Nebenbeitrag mutiert, keine
  `duration`-Mutation.
- **Target-MP4 byte-identisch:** HTTP 200, 1 741 634 Byte,
  md5 `e2330f840b398f425172b32692437f7a` – gleich zur Baseline
  und zu allen vorigen Downloads. **1051 ueberschreibt das
  vorhandene MP4 nicht**, auch mit exakter picture-URL-Form.

### Erklaerung aus den Quellen

Der Elegoo-Code loescht am Ende jedes erfolgreichen Composite
die Rohframes:

```cpp
// elegoo/extras/ai_camera/module/util/time_lapse_control.cpp:119-125
cmd = "rm -rf \'" + pic_dir + "\'";
std::system(cmd.c_str());
```

Beim USB-Export heute frueh (06:50 UTC) ist der Composite durch
diesen Pfad gelaufen; dabei wurde
`/opt/usr/picture/handslice_1792947629010.gcode20261026143807/`
vernichtet. Das Display listet den Eintrag weiter, weil es die
Datenbank-Historie und das MP4 unter `/opt/usr/video/` sieht –
aber die Rohframes existieren hier nicht mehr. 1051 mit der
abgeleiteten picture-URL findet daher nichts → `3022`.

**Konsequenz:** Jeder `video_status=2`-Eintrag auf dieser Firmware
hat zum Zeitpunkt, zu dem er Status 2 erreicht, bereits keine
Rohframes mehr. **1051 kann nicht ueber MQTT ein Status-2 nach
Status-2 ueberfuehren** – das Composite wird strukturell beim
Rendering-Vorgang (einmalig) erzeugt und frisst dabei seine Rohdaten.

### Zusammengefuehrt – drei unabhaengige Beweise fuer `3022 = keine Rohframes`

| Lauf | URL-Form | Rohframes | Dauer | Delta |
|---|---|---|---:|---|
| `fac849a1` Vormittag | `picture/<basename>` | am Display geloescht | 972 ms | `duration 0→4` |
| Test B heute (Status 2) | `video/<basename>.mp4` | nach Composite weg | 1 ms | keiner |
| **Test C heute (Status 2)** | `picture/<basename>` | nach Composite weg | <1 ms | keiner |

In allen drei Faellen: `error_code=0`, Status 12 geht sofort auf
`3022`, kein Composite. **`sub_status 3022` ist der einheitliche
Marker fuer „keine Rohframes am erwarteten Pfad".**

### Ungeprueft

- **Erfolgreicher 1051 (`3020 → 3021`) ueber MQTT.** Das Verhalten
  ist durch Code hinreichend belegt (`mqtt.c:362-372`); unser
  realer Nachweis fehlt immer noch. Benoetigt frischen Druck mit
  Zeitraffer, **direkt danach** 1051 – bevor Klaus den USB-Export
  ausloest.
- **Ob die Firmware ueberhaupt gleichzeitig Rohframes und MP4
  behaelt**, oder ob der 1051-Composite dieselbe `rm -rf`-Logik
  anwendet wie der USB-Pfad. Vermutlich ja (gemeinsame
  Composite-Funktion); zu validieren.

### Geht nicht

- **1051-Rendering fuer ein `video_status=2`-Target.** Die
  Firmware hat die Rohframes bereits beim ersten Composite
  entfernt; ein zweites Composite ist strukturell nicht moeglich.
  Fuer die App: 1051 nur auf **frischen** Status-1-Eintraegen
  aufrufen, nicht auf Status 2.

### App-Regel (final)

- `video_status=1` + alter `end_time` → UI-Hinweis „evtl. keine
  Rohframes mehr" (`3022` wahrscheinlich).
- `video_status=1` + junger `end_time` → Button „Rendern"
  anbieten, Erfolg per Head-Probe pruefen.
- `video_status=2` → nie 1051. Direkt Download.
- `video_status=3` → nicht renderbar (wahrscheinlich dauerhaft).
- Nach jedem 1051: 1036 erneut lesen, Target-URL mit Head-Probe
  pruefen. Nur HTTP 200 + Content-Length>0 ist Erfolg.

### Offener Punkt bleibt

**Erfolgreicher 1051 mit `picture/<basename>` beim naechsten
Zeitraffer-Druck, direkt nach dem Druck, vor dem USB-Export.**
Script `tools/cc2-render-timelapse.py` liegt bereit. Erwartung:
`3020→3021→1` in Groessenordnung der 26 s vom USB-Export, danach
`video_status 1→2` und MP4 abrufbar.

### Artefakte

- `logs/cc2-sniff-2026-10-26-091710.jsonl` – Mitschnitt Test C
  (git-ignoriert).
- `docs/cc2-history-sample.json` – nach-Test-C-Snapshot
  (byte-identisch zu Vorher).

Nichts committed, nichts gepusht.

---

## 2026-10-26 08:15 UTC – Sende jetzt 1051 mit **picture-URL** auf heutigem Eintrag

Ableitung der URL aus dem heutigen `video_url`:

- Heutige `video_url` aus 1036:
  `video/handslice_1792947629010.gcode20261026143807.mp4`
- Basename-Konvention aus `elegoo/.../time_lapse_control.h:61,65-66`:
  `pic_dirname_ = /opt/usr/picture/<basename>` und
  `video_path_ = /opt/usr/video/<basename>.mp4` teilen denselben
  `<basename>`.
- Download-Resolver `cc2-control/src/history.h:51-62`:
  dokumentiert explizit `"picture/NAME" or "video/NAME.mp4" ->
  "video/NAME.mp4"` als Umkehrkonvention.
- Firmware-Verhalten aus Test B (vorige Runde): `params.url =
  video/<basename>.mp4` → Response-URL = `video/<basename>.mp4.mp4`,
  d. h. die Firmware nimmt den Anteil nach dem letzten `/` als
  Basename und haengt `.mp4` an.
- Daraus **eindeutig** abgeleitet:
  `params.url = "picture/handslice_1792947629010.gcode20261026143807"`
  → Rohframes gesucht unter
  `/opt/usr/picture/handslice_1792947629010.gcode20261026143807/`
  (Display zeigt den Eintrag noch, Rohframes sollten vorhanden
  sein); Ziel-MP4
  `video/handslice_1792947629010.gcode20261026143807.mp4`
  (identisch zum bestehenden Pfad).

**Risiko-Vorhersage:** Falls 1051 erfolgreich rendert, wird das
vorhandene MP4 **ueberschrieben**. Baseline ist gesichert in
`local-test/handslice_1792947629010.gcode20261026143807.mp4`
(1 741 634 B, md5 `e2330f840b398f425172b32692437f7a`).

Mitschnitt laeuft parallel. Erwartung:
- (a) `3020→3021→1` in Groessenordnung des USB-Composings
  (26 s fuer 100 Frames),
- (b) `3020→3022→1` sofort, falls Rohframes trotz Display-
  Anzeige nicht mehr auffindbar sind,
- (c) `error_code != 0` als sofortige Ablehnung.

Antwortet 1051 mit `1003` oder scheitert mit `3022`: dokumentieren,
kein zweiter Versuch, keine Parameter-Variante.

---

## 2026-10-26 08:08 UTC – Zwei Tests: Parallelitaet (A) und 1051 auf Status-2-Eintrag (B)

### Test A: haengender Request blockiert nicht

#### Nachweislich

- **Paralleler Head-Probe wird waehrend eines haengenden Downloads
  normal bedient.** 20 ms `head_ms` auf dem heutigen (vorhandenen)
  MP4, waehrend eine stale-URL noch 35 s lang offen schwieg. Baseline
  (ohne Hang): 12–16 ms. **Keine spuerbare Serialisierung.**
- `connect_ms` schwankt stark (14–420 ms) **unabhaengig vom Hang** –
  wohl TCP-SYN-Retransmit / TIME_WAIT. **Fuer App-Fehler-Detect
  nur `head_ms` nutzen**, nicht die Gesamtlatenz.
- Nach Timeout des haengenden Requests bleibt alles normal.
- Script: `tools/cc2-probe-parallel.py`.

#### Ungeprueft

- **Grenze der Parallelitaet.** cc2-control fuehrt einen
  „two-transfer limit"-Kommentar in `history.h`; wir haben nur
  2 parallele Verbindungen gleichzeitig getestet. Mit 3+ koennte
  der Server reagieren – nicht Teil dieses Tests.

#### Geht nicht

- Nichts; der Test hat sauber ergeben, dass parallele Probes safe
  sind.

#### App-Regel

- Probes und Downloads **duerfen parallel** laufen (bis ~2
  gleichzeitig; nicht volle Spray).
- **Head-Timeout 1–2 s** auf den Response-Head reicht; vorhandene
  Dateien antworten in <30 ms, fehlende schweigen fuer immer.

---

### Test B: method 1051 gegen bereits gerenderten Status-2-Eintrag

#### Nachweislich

- 1051 wird akzeptiert (`error_code=0`), **auch wenn die URL schon
  mit `.mp4` endet**. Response-URL ist `video/<name>.mp4.mp4` –
  die Firmware haengt pauschal `.mp4` an. Daraus folgt: die
  Firmware interpretiert `params.url` als **Basisname fuer das
  Composite**, egal ob mit oder ohne Extension.
- **Status 12 nur 1 Millisekunde**: `3020 → 3022` passiert
  in derselben api_status-Nachricht. Noch kuerzer als beim
  `fac849a1`-Lauf (972 ms); dort war der URL-Form-Fehler zwar
  nicht vorhanden, aber Rohframes fehlten – effektiv dasselbe
  Nicht-Composite.
- **1036 Vorher/Nachher: byte-identisch**
  (`sha256(result)=e12d373a3ec5c57b` beide Male). Weder Target
  noch Nebenbeitraege veraendert. **Insbesondere die
  `time_lapse_video_duration` 0→4-Mutation vom
  `fac849a1`-Lauf tritt hier nicht auf** – vermutlich bindet die
  Firmware diese Mutation an die Status-1-Form `picture/…` an.
- **MP4-Datei unveraendert.** Nach dem 1051-Lauf nochmal geladen:
  1 741 634 Byte, md5 `e2330f840b398f425172b32692437f7a` –
  **byte-identisch** zur Baseline. 1051 ueberschreibt also
  **nicht** das vorhandene MP4.
- Die hypothetische `video/<name>.mp4.mp4`-Datei existiert
  erwartungsgemaess nicht (Timeout, kein 404).

#### Ungeprueft

- **Erfolgreiches 1051 mit `picture/<name><ts>`-URL und frischen
  Rohframes.** Das sauber reproduzierbare `3020→3021`-Verhalten
  haben wir bis jetzt nur beim USB-Export beobachtet (26 s fuer
  100 Frames). MQTT-Pfad noch offen; naechster Zeitraffer-Druck
  ist der richtige Moment (siehe offener Punkt).
- **Verhalten bei einem `video_status=2`-Eintrag mit tatsaechlich
  vorhandenen Rohframes und 1051 mit `picture/<name><ts>`-URL**
  (= hypothetisches Re-Rendern). Interessant, aber potentiell
  destruktiv (Ueberschreibung?); nur mit Backup des bestehenden
  MP4 zu testen.
- Semantik von `sub_status 3022` jenseits der jetzt belegten
  Vermutung „kein Composite stattgefunden" (unterschiedliche
  Ursachen: Rohframes fehlen; URL-Form falsch).

#### Geht nicht

- **1051 mit `video/<name>.mp4`-URL erzeugt nichts.** Weder neue
  Datei (siehe `.mp4.mp4`-Timeout) noch Mutation des bestehenden
  MP4. Composite scheitert still in `3022`, History bleibt
  unberuehrt. Fuer die App: `video/`-URLs sind fuer 1051 **nicht**
  der richtige Input.

#### App-Regel (praezisiert)

- Fuer Rendering: **nur `picture/<name><ts>`-URLs** (aus
  `video_status in {1, 3}`) an 1051 schicken. `video/…`-URLs
  sind idempotent und folgenlos (ok), aber sinnlos.
- Status 2 → direkt Head-Probe und Download. Nie 1051.
- `sub_status 3022` generell als „kein Composite stattgefunden"
  interpretieren; Erfolg immer per Head-Probe auf die neue URL
  bestaetigen.
- 1051 ist **idempotent-sicher** auf Status-2-Eintraegen; falls
  die App versehentlich 1051 doppelt sendet oder auf einem schon
  gerenderten Eintrag, passiert nichts Boeses – weder MP4 veraendert
  noch History mutiert.

### Offener Punkt bleibt

**Realer 1051-Test mit `picture/<name><ts>`-URL** beim naechsten
Zeitraffer-Druck, vor dem USB-Export. Script
`tools/cc2-render-timelapse.py` bleibt bereit; nicht ausfuehren,
bevor der Druck fertig ist und der Stick noch nicht gesteckt wurde.

### Artefakte

- `tools/cc2-probe-parallel.py` – Test A, Head-Probes
  mit optionalem Hang.
- `logs/cc2-sniff-2026-10-26-090500.jsonl` – Mitschnitt waehrend
  Test B (SN + Rohpayloads, deshalb `logs/` ignoriert).
- `docs/cc2-history-sample.json` – byte-identisch zur
  Vormittags-Fassung; `.mp4.mp4`-Mutation gab es nicht.

Nichts committed, nichts gepusht.

---

## 2026-10-26 08:03 UTC – Sende jetzt method 1051 fuer heutigen Lauf 2 (Erfolgsfall)

Zielobjekt: der heutige Status-2-Eintrag, zu dem laut Display die
**Rohframes noch vorhanden** sind:

- `task_id = e0b592f4-bd51-4ece-97fc-2bfc8137d13e`
- `begin_time = 2026-10-26T06:38:07Z`
- `url = "video/handslice_1792947629010.gcode20261026143807.mp4"`
- aktueller `video_status = 2`, `video_size = 1 741 634`
- Baseline md5 des MP4: `e2330f840b398f425172b32692437f7a`

Request-Payload nach cc2-control-Beleg
(`cc2-control/src/mqtt.c:277-287` + `:362-372`):

```json
{"method":1051,"id":1051,"params":{"url":"video/handslice_1792947629010.gcode20261026143807.mp4"}}
```

Mitschnitt laeuft parallel. Erwartung ist eine der drei
Varianten:

- (a) Sofortige Ablehnung mit `error_code!=0` (MP4 schon da),
- (b) erneutes Composite ueber die Rohframes mit `3020→3021→1`
  und moeglicherweise neuem md5,
- (c) kurzer Durchlauf wie bei `fac849a1` (`3020→3022`),
  weil die Firmware „schon da" so signalisiert.

Antwortet 1051 mit `1003`, wird nicht wiederholt.

---

## 2026-10-26 07:55 UTC – Gegentest „Historie ist stale" bestaetigt; 1051-Lauf war ungueltig

Klaus hat heute frueh am Display alle alten Zeitraffer geloescht,
bis auf den heutigen Lauf 2. Die Historie aus `method 1036` zeigt
davon nichts – alle Eintraege stehen weiterhin drin. Daraus folgt
retrospektiv, dass der 1051-Test an `fac849a1` ungueltig war
(keine Rohframes mehr vorhanden); `3022` ist vermutlich
**„nichts zum Rendern"**, nicht „Fehler".

### Nachweislich

- `method 1036` liefert **genau denselben Snapshot** wie heute
  vormittag: 6 Tasks mit `video_status in {1, 2}`, davon vier
  Status-2-URLs. Keine Mutation durch das Display-Loeschen.
- **Alle drei alten Status-2-URLs geben Timeout** auf
  `GET /download?X-Token=…&file_name=…`:
  - `video/ECC2_0.4_Box…20261019110021.mp4` (nominell 9 912 573 B)
  - `video/handslice_kerbenwuerfel_timelapse.gcode20261025164702.mp4` (nominell 1 813 428 B)
  - `video/handslice_1792947629010.gcode20261026010053.mp4` (nominell 1 762 496 B)
  Timeout tritt beim **Response-Head** auf (8 s unseres Clients
  wurden abgewartet). Protokollisch: TCP-Handshake geht durch, der
  Server beantwortet die Request-Zeile mit Schweigen – kein 404,
  kein 403, kein Body, kein TCP-Reset.
- **Gegenprobe heutiger Eintrag**:
  `video/handslice_1792947629010.gcode20261026143807.mp4`,
  HTTP **200** in **73.7 ms**, Content-Length **1 741 634**,
  Transfer-Encoding chunked. Vollstaendig geladene Datei:
  **md5 e2330f840b398f425172b32692437f7a**, byte-identisch zum
  Vormittags-Download.
- **Druckeruhr-Offset belegt**: realer Druckstart 2026-10-26T06:38:07Z
  (= 07:38:07 MEZ); Display-Anzeige fuer denselben Druck
  **14:38:07** (laut Klaus). Dateinamen-Zeitstempel aus 1036
  `20261026143807` – deckungsgleich zur Display-Zeit. Druckeruhr
  liegt also **+7 h gegen MEZ / +8 h gegen UTC** (entspricht
  UTC+8). Zeitstempel im Dateinamen oder in `begin_time` sind
  damit **nicht gegen Echtzeit abgleichbar**.
- **1036 ist eine Datenbank-Historie, kein Verzeichnislisting.**
  `video_status==2` sagt „wurde mal gerendert", nicht „ist jetzt
  abrufbar". Einziger verlaesslicher Existenz-Nachweis bleibt
  der HTTP-GET.
- **Short-Read-Timeout reicht als App-Fehler-Detect** – antwortet
  der Drucker nicht in ca. 1–2 s auf den Response-Head, ist die
  Datei weg (bei einer vorhandenen Datei kam der Header in 74 ms).

### Ungeprueft

- Ob `method 1051` auf einem Task mit **tatsaechlich vorhandenen**
  Rohframes den Status 1 → 2 bringt und ein abrufbares MP4
  erzeugt. Dafuer braucht es den naechsten Zeitraffer-Druck,
  bevor Klaus den USB-Export macht (siehe offener Punkt unten).
- Semantik von `sub_status 3022` jenseits der Vermutung „keine
  Frames vorhanden".
- Semantik von `video_status 3` ohne URL (Nameplate-Nebenbefund
  heute Vormittag). Mit dem jetzigen Wissen plausibel: 3 bedeutet
  „schon mal versucht zu rendern, Rohframes gab es nicht" –
  d. h. es ist die 1051-nach-Composite-Markierung fuer einen
  Task ohne Rohframes.
- Warum der Drucker auf fehlende Dateien **schweigt** statt eine
  HTTP-Fehlermeldung zu senden. Code-Beleg
  (`cc2-control/src/history.h:250-251`) sagt nur, dass er es
  tut – nicht warum.

### Geht nicht

- **Historie am Drucker-Display und `method 1036` haengen nicht
  zusammen.** Das Display-Loeschen des Zeitraffers aktualisiert
  die 1036-Datenbank nicht. Vermutlich das pendant zum
  2026-10-25-Befund, dass `method 1047` (DELETE_FILE) auf dieser
  FW auch nichts aus der Dateiliste loescht. **Loeschen aus der
  History geht ueber `method 1038`** (code-belegt, nicht hier
  getestet). Zum Entfernen eines Zeitraffers am Display ohne
  History-Mutation gibt es keinen beobachtbaren MQTT-Pfad –
  die beiden sind separat.

### App-Regeln (konkretisiert nach diesem Lauf)

Ersetzt die M5-Regeln vom Vormittag:

1. `method 1036` lesen + anzeigen. Zeitstempel aus `begin_time`,
   `end_time` und dem Dateinamen-Suffix **nicht** gegen Echtzeit
   abgleichen; nur als Ordnungs-Schluessel verwenden.
2. **Download-Button an eine Head-Probe binden**, nicht an
   `video_status==2`: GET auf `/download?...` mit 2 s Timeout auf
   den Response-Head. Antwortet der Drucker, ist das MP4 da und
   wird geladen; antwortet er nicht, als „nicht mehr verfuegbar"
   anzeigen (ggf. Hinweis, dass es wahrscheinlich am Display
   geloescht wurde).
3. Nach `method 1051` nicht nur auf `error_code==0` schauen und
   auch nicht nur auf `status==1 nach 12`. Stattdessen: Target-URL
   per Head-Probe testen. Nur HTTP 200 + Content-Length>0 ist
   Erfolg.
4. `sub_status 3022` als „keine Frames" interpretieren
   (nicht als Fehler). `sub_status 3021` als Erfolg der
   Kopier-Phase (USB-Export) belassen.
5. `video_status 3` ohne URL: UI-Hinweis „Rohdaten nicht mehr
   verfuegbar". `video_status 1` oder `3` mit URL: Button
   „Rendern" (= 1051) anbieten, aber den Erfolg per Head-Probe
   bestaetigen.

### Offener Punkt

**Realer 1051-Test beim naechsten Zeitraffer-Druck.** Vor dem
USB-Export, direkt nach dem Druckende (idle), gegen die frischen
`video_status=1`-Rohframes. Erwartung: Composite-Dauer in der
Groessenordnung des USB-Composings (26 s fuer 100 Frames beim
heutigen Lauf 2), `sub_status 3020→3021→1`, danach
`video_status=2` mit abrufbarem MP4.

Script liegt bereit (`tools/cc2-render-timelapse.py`); bitte
nicht ausfuehren, bevor der naechste Zeitraffer-Druck fertig und
der Stick noch nicht gesteckt ist.

### Artefakte

- `tools/cc2-timelapse-probe.py` – Head-only-GET pro Status-2-URL
  mit Timing (und optionalem Drain).
- `docs/cc2-history-sample.json` – aktualisiert (byte-identisch
  zur Vormittags-Fassung).

Nichts committed, nichts gepusht.

---

## 2026-10-26 07:45 UTC – Realtest `method 1051`: akzeptiert, aber Composite scheiterte still

Senden erfolgt um 07:42:19 UTC gegen Target `fac849a1` (2026-10-14-
Druck, `video_status=1`, URL `picture/<name><ts>`). Reserve
`e4d2dc70` nicht angefasst. Mitschnitt lief parallel.

### Nachweislich

- **1051 wird vom Stock-Broker akzeptiert.** Response in 233 ms,
  `error_code=0`, Response-Payload enthaelt bereits die zukuenftige
  URL (`video/<name><ts>.mp4`). Payload exakt nach
  `cc2-control/src/mqtt.c:277-287` + `:362-372` (id = method = 1051).
- **Status 12 wird sofort gesetzt**: 27 ms nach der Response wechselt
  `machine_status.status` auf 12 und `sub_status` auf **3020**.
  Insgesamt dauert der Zustand nur **972 ms**, dann zurueck auf
  Status 1.
- **Substate-Pfad weicht vom USB-Export ab:** heute frueh war die
  Reihenfolge `3020→3021→1` (26 s), jetzt ist sie `3020→3022→1`
  (<1 s). `3021` ist laut Display „Video wird kopiert", `3022` ist
  in keiner uns bekannten Code-Doku aufgefuehrt und sieht nach
  **Fehler-Substate** aus.
- **MP4 ist NICHT entstanden.** Zwei Download-Versuche mit der
  Response-URL (einmal `urlencode`-Variante, einmal
  `percent_encode`-Variante): beide HTTP-Timeout. Das entspricht
  genau dem von cc2-control dokumentierten Verhalten „wrong token
  or name → silence" (`history.h:250-251`). Gegentest mit dem
  heute-frueh-MP4 ergibt `HTTP 200 Content-Length: 1 741 634` –
  der Pfad funktioniert, nur die Datei fehlt.
- **History-Diff Vorher/Nachher** (hash `sha256(result)`):
  `c07da2c56804...` → `e12d373a3ec5...`. Zwei geaenderte Tasks:
  1. Target `fac849a1`: nur `time_lapse_video_duration` 0 → 4.
     `status` bleibt 1, `url` bleibt `picture/<name><ts>`,
     `size` bleibt 0. Zustand damit nicht fortgeschritten.
  2. Nameplate `887e3325` (voellig unverwandter Task vom 23.09.):
     `video_status` 0 → 3, bei weiterhin leerer URL und 0-Werten.
     Nicht sauber kausal zum 1051 zuordenbar.
- **Reserve `e4d2dc70` byte-identisch**. Keine Nebenwirkung auf
  den anderen Status-1-Eintrag.
- **Alle vorhandenen `video_status=2`-Eintraege byte-identisch**.
  Keine Nebenwirkung auf bereits gerenderte Zeitraffer.
- **Keine Fortschritts-Felder in api_status waehrend Status 12**.
  Alle Felder im 1.5-s-Composing-Fenster: nur `status`, `sub_status`,
  und die 1051-Antwort selbst (`error_code`, `url`). Kein
  `progress`, `percent`, `frame_count` o.ae. Fuer die App bedeutet
  das: Spinner statt Prozentanzeige.

### Ungeprueft

- **Erfolgreiches Composing via 1051.** Dieser Lauf hat keinen
  erfolgreichen Zustand erreicht; den Zyklus 1→1051→12→**2**→
  Download haben wir nur fuer die USB-Export-Variante (`3020→3021`)
  real gesehen, nicht ueber MQTT 1051. Fuer die endgueltige
  Bestaetigung braechte es einen frischen Druck mit Zeitraffer,
  gefolgt direkt (ohne USB-Export) von einem 1051-Aufruf – dann
  waeren die Rohframes garantiert noch da.
- **Bedeutung von `sub_status 3022`.** Vermutung „Composite
  fehlgeschlagen". Harten Beleg (Enum-Tabelle) haben wir nicht.
- **Bedeutung von `video_status 3` ohne URL** (Nameplate-Fall).
  Semantisch widerspruechlich zur cc2-control-Lesung („3 ist
  renderbar wie 1"). Vermutung: FW-interne Markierung „existierte
  mal, Rohframes weg". Nicht hart belegt.
- **Ob `time_lapse_video_duration=4` am Target eine App-Semantik
  hat** (geplante Dauer in Sekunden?). Dieser Eintrag wird in der
  Community-UI nicht angezeigt; Zweck in diesem Zustand unklar.

### Geht nicht

- **Composing auf Stock 02.01.01.07, wenn die Rohframes bereits
  intern geloescht sind.** Der Drucker signalisiert den Fehler
  nicht ueber `error_code`, sondern nur ueber den Substate 3022.
  Fuer die App bedeutet das: nach jedem 1051-Lauf einen zweiten
  `method 1036`-Pull machen und auf `video_status==2 && size>0`
  pruefen, nicht nur auf `error_code==0`.
- **Rohframes-Erhalt ueber die Zeit garantieren.** Der Drucker
  (vermutlich) raeumt die `picture/`-Verzeichnisse irgendwann
  weg, aber die History behaelt `video_status=1` – das ist eine
  stale-Markierung aus App-Sicht. Workaround: bei `status=1`
  mit alten `end_time`-Werten in der UI darauf hinweisen, dass
  das Rendering fehlschlagen koennte.

### App-Konsequenz (M5 revidiert)

Dreistufige UI-Logik, konkretisiert um die Realtest-Erkenntnisse:

1. **Druckhistorie laden:** `method 1036`.
2. **Pro Zeitraffer-Task:**
   - `video_status==0` → „kein Zeitraffer".
   - `video_status==2 && size>0` → Download-Button → `GET /download?X-Token=&file_name=<url>`.
   - `video_status==1` oder `3` **mit** URL beginnend mit `picture/`
     → Button „Rendern" → `method 1051 params.url=<url>`;
     Spinner anhand `machine_status.status==12`.
   - `video_status==3` **ohne** URL → UI zeigt „Zeitraffer-
     Rohdaten nicht mehr vorhanden" (nicht renderbar).
3. **Nach dem Composing (Zurueck zu Idle):** erneut `method 1036`.
   - Wenn Target jetzt `video_status==2 && size>0`: Download.
   - Sonst: Fehlerhinweis „Composite fehlgeschlagen – Rohframes
     evtl. nicht mehr verfuegbar". Nicht automatisch
     wiederholen (kein zweiter 1051-Aufruf).

### Artefakte

- `tools/cc2-render-timelapse.py` – idempotent gegen Reserve
  (nimmt URL als Argument, sendet 1051 genau einmal).
- `logs/cc2-sniff-2026-10-26-084103.jsonl` – Sniff der
  Composing-Phase (SN + Rohpayloads, deshalb `logs/` ignoriert).
- `docs/cc2-history-sample.json` – nach-1051-Snapshot
  (SN-anonymisiert). Vorher-Snapshot liegt nur temporaer in
  `/tmp/cc2-history-vorher.json`.
- `docs/upstream/elegoo-homeassistant-timelapse-download-draft.md`
  – aktualisiert um die 1051-Beobachtung (siehe Abschnitt
  „Realtest observations").

Nichts committed, nichts gepusht.

---

## 2026-10-26 07:40 UTC – Sende jetzt method 1051 (einziger Schreibbefehl heute)

Zielobjekt: aelterer der beiden `video_status=1`-Eintraege aus
`docs/cc2-history-sample.json`:

- `task_id = fac849a1-c028-4ba9-b7e5-c41a9981159a`
- `begin_time = 2026-10-14T03:50:32Z`
- `url = "picture/ECC2_0.4_Sealed+lid_Elegoo PLA Matte _0.12_2h39m.gcode20261014115032"`

Der neuere `video_status=1`-Eintrag (`e4d2dc70-...`) **bleibt
unangetastet** als Reserve.

Request-Payload nach cc2-control-Beleg
(`cc2-control/src/mqtt.c:277-287` fuer `publish_request` plus
`:362-372` fuer `mqtt_generate_timelapse`):

```json
{"method":1051,"id":1051,"params":{"url":"<url>"}}
```

Topic: `elegoo/<cc2-sn>/<client_id>/api_request`.

Passiver Mitschnitt laeuft seit 2026-10-26 07:41 UTC
(`logs/cc2-sniff-2026-10-26-084103.jsonl`), damit Status-12-Verlauf
mit Zeitstempel protokolliert wird. Idle vor dem Senden wird vom
1051-Script selbst geprueft.

Erwartung: `error_code=0` → Status 1→12→1 mit Substates 3020→3021.
Antwortet 1051 mit `1003`, wird nicht wiederholt und keine
Parameter-Variante probiert.

---

## 2026-10-26 07:35 UTC – Realtest: Zeitraffer-Abruf ueber LAN bewiesen

Zwei Schritte lesend (plus Register-Handshake fuer 1036):
`tools/cc2-history-fetch.py` fuer `method 1036`,
`tools/cc2-timelapse-download.py` fuer HTTP-GET. **Kein `method 1051`
gebraucht**, weil der 06:38-Zeitraffer-Druck bereits `video_status=2`
hatte (Klaus' USB-Export heute frueh hat das Composite gemacht).

### Nachweislich

- **`method 1036` funktioniert auf Stock 02.01.01.07.** Antwort in
  < 1 s, 13 661 Byte, 45 History-Eintraege, `error_code=0`. Felder
  deckungsgleich zu dem, was wir aus `cc2-control/src/history.h` und
  `plugin.ts` abgeleitet haben.
- **Spiegelung der heutigen Testdrucke stimmt exakt:**
  - Lauf 1 (06:25 UTC, ohne Timelapse): `video_status=0`,
    `video_url=""`, `video_size=0`. Kein Frame aufgezeichnet.
  - Lauf 2 (06:38 UTC, mit Timelapse): `video_status=2`,
    `video_url='video/handslice_1792947629010.gcode20261026143807.mp4'`,
    `video_size=1 741 634`. **Klaus' USB-Export um 06:50:54 UTC
    hat das Composite ausgeloest; danach ist der Status von
    (vermutlich zuvor) 1 auf 2 gewechselt.**
- **Enum `time_lapse_video_status` empirisch belegt** (Verteilung in
  45 Tasks):
  0 = kein Zeitraffer (`url=""`), 1 = Rohframes vorhanden
  (`picture/<name><ts>`), 2 = MP4 bereit (`video/<name><ts>.mp4`),
  3 = nicht beobachtet. Interpretation identisch zur
  Community-Code-Lesung.
- **HTTP-GET `/download?X-Token=<access>&file_name=<url>` liefert
  das MP4 vom LAN aus** (nicht nur Loopback). Response:
  `HTTP 200`, `Content-Length: 1 741 634` (= `video_size`),
  `Transfer-Encoding: chunked`, `Content-Disposition: attachment;
  filename="video/<name>.mp4"`. **Beide Rahmungen (Length + chunked)
  gleichzeitig** – vgl. cc2-control-Warnung in
  `history.h:269-273`.
- **ffprobe-Pruefung** (`local-test/handslice_1792947629010.gcode20261026143807.mp4`,
  md5 `e2330f840b398f425172b32692437f7a`):
  H.264, 640×360, 30 fps, **100 Frames**, 3.30 s, 4.22 Mbit/s –
  der 100-Layer-Druck ergibt genau 1 Frame pro Layer, was zur
  Elegoo-Code-Logik passt.
- **Idle-Prerequisites eingehalten.** Vor dem 1036-Request 10 s
  passiv geprueft; `machine_status.status` kein Delta in dem
  Zeitfenster (= keine Transition weg vom Idle), danach erst
  Register + 1036.
- **Clock-Drift bestaetigt und erklaert.** Dateinamens-Zeitstempel
  `20261026143807` beim 06:38:07-UTC-Druckstart = Druckeruhr
  ~8:00 h vor UTC in diesem Lauf (im 25.10.-Lauf war es
  `20261026010053` fuer einen 18:05-MEZ-Druck). Die
  `localtime_r`-Nutzung im Elegoo-Code
  (`time_lapse_control.cpp:166-172`) sieht einfach die aktuelle
  Druckeruhr; dass diese die MESZ→MEZ-Umstellung oder
  Zeitzonenwechsel nicht sauber mitfuehrt, ist das darunter
  liegende Problem. **Fuer die App bleibt: Dateinamens-ts als
  opaker Ordnungsschluessel.**

### Ungeprueft

- **Verhalten bei `video_status=1`** (Rohframes, nicht gerendert).
  In diesem Sample waren zwei Tasks mit Status 1 (vom 14.10.),
  aber wir haben `method 1051` **nicht** gesendet (nicht noetig).
  Der volle Zyklus 1 → 1051 → Status 12 → 2 → Download bleibt
  damit **nur in Teilen** validiert: wir haben Status 12 heute
  frueh im Mitschnitt gesehen und das daraus resultierende MP4
  jetzt heruntergeladen; der direkte Trigger via `method 1051`
  ist weiter nur code-belegt, nicht am Geraet verifiziert.
- **Verhalten bei `video_status=3`** – im Sample nicht aufgetaucht.
- **Semantik von `task_status`** – 1 (38×) oder 2 (7×) im Sample.
  Keine 3 gesehen. Deutung „1 = normal, 2 = abgebrochen" ist
  plausibel, aber nicht hart belegt.
- **Content-Length-vs-chunked-Konflikt** in anderen Clients.
  `urllib` in Python hat beides sauber gelesen; wie Dart's
  `http`-Package reagiert, bleibt zu testen.

### Geht nicht

- Nichts, was fuer diesen Auftrag relevant waere, hat gefehlt.
  Alle drei geforderten Schritte 1-2-3 waren durch die ersten
  zwei abgedeckt; Schritt 3 (`method 1051`) ist bewusst nicht
  gesendet, weil Schritt 2 bereits erfolgreich war.

### App-Konsequenz (konkret, M5-Erweiterung)

Dreistufige UI-Logik, in dieser Reihenfolge:

1. **Druckhistorie laden:** `method 1036` → `history_task_list[]`.
   Pro Eintrag die drei Zeitraffer-Felder lesen.
2. **Pro Zeitraffer-Task entscheiden:**
   - `video_status==0` → UI zeigt „kein Zeitraffer".
   - `video_status==2` → UI zeigt „Zeitraffer bereit" mit
     Download-Button → GET `/download?X-Token=…&file_name=<url>`.
   - `video_status==1` oder `3` → UI zeigt „noch nicht gerendert"
     mit Button „Rendern" → `method 1051 params.url=<url>`;
     waehrend Status 12 ein Fortschritts-Spinner; nach
     Zurueck-auf-Idle `method 1036` neu lesen und zu Schritt 2.
3. **Loeschen** (Phase 2+): `method 1038 params={"list":[task_id]}`
   entfernt **nur den Historien-Eintrag** aus 1036. **Weder das
   MP4 noch die Display-Zeitraffer-Liste werden beruehrt** – siehe
   Test D (08:35 UTC Eintrag). Fuer Speicher-Freigabe muss am
   Drucker-Display geloescht werden; die MQTT-API hat dafuer
   keinen Pfad.

Zusatz fuer die App-Doku: `method 1047` nicht fuer Zeitraffer
nutzen (die Firmware ignoriert es sowieso).

### Entwurf fuer upstream `danielcherubini/elegoo-homeassistant`

`docs/upstream/elegoo-homeassistant-timelapse-download-draft.md`.
Englisch, keine SN/Access-Code/IP, keine Code-Kopien aus
`cc2-control` oder `elegoo-link`. Vorschlag darin: Doku-PR fuer
`docs/CC2_PROTOCOL.md` (1036/1051/1038 + `/download`-Semantik) +
Feature-PR fuer `cc2/client.py` (Timelapse-Download). Noch nicht
eingereicht – Klaus entscheidet.

### Artefakte

- `tools/cc2-history-fetch.py` – 1036 + Idle-Check + SN-Scrub.
- `tools/cc2-timelapse-download.py` – HTTP-GET /download.
- `docs/cc2-history-sample.json` – 1036-Antwort anonymisiert (SN
  raus, Access-Code war nicht in der Antwort). Enthaelt
  Dateinamen echter frueherer Drucke – nicht sensibel, aber in
  Repo-Kontext zu bedenken.
- `local-test/handslice_1792947629010.gcode20261026143807.mp4` –
  gezogener Zeitraffer (git-ignoriert, bleibt lokal).
- `docs/upstream/elegoo-homeassistant-timelapse-download-draft.md`
  – Draft fuer upstream.

Nichts committed, nichts gepusht.

---

## 2026-10-26 07:30 UTC – Klaerung: 1036/1038/1051 sind Stock, nicht Community

Vor dem Realtest die berechtigte Rueckfrage aufgeloest, ob die
Methoden-Nummern aus `cc2-control` evtl. nur in der Community-
Firmware funktionieren.

**Nachweislich Stock-Protokoll:**

- `cc2-control` **bringt keinen eigenen MQTT-Broker mit.** Der
  einzige Treffer fuer „mosquitto" im Repo ist in
  `cc2-control/tests/sim_printer.py:15-18` – dort wird mosquitto
  per Docker als Mock-Broker fuer die Testsuite gestartet, nicht
  auf dem Drucker.
- `cc2-control` connectet gegen den **lokalen** Broker auf
  `127.0.0.1:1883` (`cc2-control/src/mqtt.c:382`:
  `a.sin_addr.s_addr = htonl(INADDR_LOOPBACK)`). Dieser Broker
  ist Teil der **Stock-Firmware** – der Dienst, den wir seit
  2026-10-25 auch von unserem Mitschnitt-PC aus unter
  `<cc2-ip>:1883` ansprechen.
- `cc2-control` wartet beim Start mit `pidof elegoo_printer`
  (`cc2-control/scripts/launch.sh:28`) auf den **vendor-eigenen
  Hauptprozess**; alle Publishes gehen auf die vendor-eigenen
  Topics `elegoo/<sn>/...` (`cc2-control/src/mqtt.c:71, 92, 146,
  157, 282, 298, 324`), identisch zu dem, was wir im passiven
  Mitschnitt heute frueh gesehen haben.
- Die Methoden-Nummern selbst sind **nicht Community-Erfindung**.
  Der Lizenzhinweis in `cc2-control/web-src/src/lib/machine.ts:3-4`
  lautet woertlich: „Codes and meanings below come from ELEGOO's
  elegoo-link SDK (Apache-2.0), CC2 LAN adapter
  elegoo_fdm_cc2_message_adapter.cpp".
- Zusaetzlicher indirekter Beleg: Die sub_status-Codes, die unser
  passiver Stock-FW-Mitschnitt heute frueh gezeigt hat (2075,
  2077, 2401, 2501, 2502, 2801, 2802, 1045, 1405), sind in der
  Community-Tabelle (`machine.ts:11-57`) deckungsgleich belegt.
  Die Community-Semantik passt also faktisch zum Stock-Verhalten.

**Vorsicht:** Dieser Beleg zeigt, dass die Nummern aus Elegoos
eigenem SDK stammen und `cc2-control` nur Client ist. Er zeigt
**nicht**, dass die Stock-Firmware 02.01.01.07 jede dieser
Methoden freischaltet. Methoden `1045 GET_FILE_THUMBNAIL` und
`1047 DELETE_FILE` existieren im SDK, antworten auf dieser Stock-FW
aber mit `error_code 1003` (unser Nachweislauf 2026-10-25). Ob
`1036/1051` ebenso „im SDK, aber in dieser FW abgewiesen" sind,
klaert erst der folgende Realtest.

---

## 2026-10-26 07:15 UTC – Quellenrecherche Zeitraffer-Ablage (lesend, keine Firmware geladen)

Neuer Abschnitt in `docs/networking-cc2.md` eingefuegt:
„Zeitraffer-Ablage: Quellenrecherche 2026-10-26" (umfangreich,
revidiert die 2026-10-25-Aussage „keine LAN-API fuer
Zeitraffer-Download").

Quellen: `elegooofficial/CentauriCarbon2` (GPL-3) und
`Neme77/centauri-carbon-2-community` (shallow nach
`/tmp/handslice-research/`, nichts gebaut) sowie
`docs.opencentauri.cc`. Keine `.zip.sig`/`.swu.sig` angefasst, kein
Decrypt-Tool benutzt, keinen Befehl an den Drucker.

### Nachweislich (Belegstellen in networking-cc2.md verlinkt)

- **Rohframe-Pfad:** `/opt/usr/picture/<gcode><YYYYMMDDHHMMSS>/`
  (temporaer `.temp/`, bei Abschluss umbenannt). Pro Frame
  `0001.jpeg`, `0002.jpeg`, …
  (`time_lapse_photo.h:17`, `time_lapse_control.cpp:28-78`).
- **MP4-Pfad:** `/opt/usr/video/<name>.mp4` (`time_lapse_photo.h:18`).
- **Dateinamen-Logik:** Druckdateiname + `strftime("%Y%m%d%H%M%S")`
  aus **lokaler Druckeruhr** (`time_lapse_control.cpp:161-186`).
  Begruendet die 2026-10-25-Beobachtung „Zeitstempel im Dateinamen
  weicht ab".
- **Encoder:** `cpulimit -l 80 ffmpeg … libx264 -preset ultrafast`
  gebuendelte Binaries unter `elegoo/lib/ffmpeg/ffmpeg`
  (`time_lapse_control.cpp:280-293`); aktiver Pfad nutzt den
  eingebetteten `ImageToVideoEncoder` (`.cpp:110-114`).
- **Vollstaendige MQTT-Methodenliste:** 1002, 1019, 1020, 1029,
  1036, 1038, 1051, 2004, 2005 – mit Code-Beleg
  (`cc2-control/web-src/src/lib/machine.ts:88-98`,
  `cc2-control/src/mqtt.c:290-372`).
- **Zeitraffer-Flaggen-Pfade sauber getrennt:**
  - `method 1019 params.config.delay_video=true` (vor dem Druck,
    `mqtt.c:290-313`, der sauberere cc2-control-Weg).
  - `method 1020 params.config.delay_video=true` (beim Druckstart,
    der elegoo-link-Weg; von Klaus am 25.10. so verwendet, wirkt).
- **Zeitraffer-Status pro Druck** steckt in `method 1036`
  `history_task_list[]`, Feld `time_lapse_video_status`:
  0/1/2/3-Enum (1 oder 3 = renderbar, 2 = MP4 bereit),
  `time_lapse_video_url` nennt den Pfad (`history.h:22-62`,
  `history.h:160-178`, `plugin.ts:792`).
- **Zeitraffer-Rendering starten:**
  `method 1051 params.url="<history_task.time_lapse_video_url>"`;
  Fortschritt via `machine_status.status=12`, Timeout 600 s
  (`mqtt.c:362-372`, `mqtt.c:895`).
- **LAN-Download fuer das fertige MP4 (NEU, widerlegt
  2026-10-25-Aussage):**
  `GET http://<cc2-ip>/download?X-Token=<access>&file_name=video/<name>.mp4`
  – belegt in `cc2-control/src/history.h:307-336`. Derselbe
  Endpunkt wie fuer G-Code, nur `file_name`-Prefix anders.
- **Loeschen:** `method 1038 params.list=[task_id]` entfernt den
  History-Eintrag; dies ist der dokumentierte Weg, Zeitraffer-
  Rohframes und Videos sauber zu entsorgen. `method 1047`
  (DELETE_FILE auf `local`) ist dafuer NICHT der richtige Pfad
  (passt zu unserem 2026-10-25-Nachweislauf, in dem 1047 immer
  `1003` zurueckgab).
- **sub_status-Tabelle fuer Status 2** komplett belegt
  (`machine.ts:11-57`), inkl. der von uns heute frueh gesehenen
  Codes 1045, 1066, 1405, 2075, 2077, 2401, 2501, 2502, 2801,
  2802. **Codes 1066 und 2802 fehlen in der Community-Tabelle**;
  Vermutung: 1066 = Bed-Mesh-Zwischenschritt, 2802 = Homing-
  Zwischenschritt (die Nachbar-Codes sind so belegt).
- **Prozess-Topologie:** vendor `elegoo_printer` (binary, nicht
  im Repo) + `ai_camera` (binary, Quelle im Elegoo-Repo).
  `/opt/inst/` = read-only Installation, `/opt/usr/` = persistente
  Partition. Community startet `cc2-control` erst, wenn
  `pidof elegoo_printer` antwortet
  (`cc2-control/scripts/launch.sh:28`).
- **A/B-Partitionen** via `swupdate`, RootFS SquashFS, Paket
  `.zip.sig → .swu.sig + .json.sig`
  (OpenCentauri `software/updates-cc2/`).

### Ungeprueft (konkrete Experimente stehen aus)

- **LAN-Download des MP4 mit `X-Token=<access-code>` am echten CC2.**
  Der Pfad ist code-belegt (cc2-control nutzt ihn ueber Loopback);
  ob der Drucker denselben GET auch extern von einem anderen Host
  akzeptiert, muss gezielt getestet werden. Erst dann ist Punkt 6
  des revidierten Flusses wirklich bewiesen.
- **Verhaelt sich Status 12 beim USB-Export anders als bei
  `method 1051`?** Vermutung: identischer Composite-Code, nur mit
  anschliessendem Dateikopieren auf USB. Trennbar durch zwei
  Vergleichs-Composites (1× ueber MQTT, 1× ueber Display).
- **Was passiert mit dem Picture-Verzeichnis nach Composite?** Der
  Code sagt `rm -rf <pic_dir>` (`time_lapse_control.cpp:123` und
  `ai_camera.cpp:437`), Klaus beobachtete „Frames bleiben, beliebig
  oft exportierbar". Deutung: Was bleibt, ist das **MP4** in
  `/opt/usr/video/` – ein zweiter USB-Export laeuft dann nur noch
  als Kopiervorgang (ggf. ohne Phase 3020). Konkreter Test: zweiter
  Export derselben Zeitraffer-Datei; Erwartung: deutlich kuerzer
  als 26 s und evtl. nur sub_status 3021.
- **Codes 1066/2802** (im Mitschnitt gesehen, in der Community-
  Tabelle nicht) – Belegung aus elegoo-link checken oder weiter
  mitschneiden.

### Geht nicht ohne weiteren Zugang

- Die genauen Signale **innerhalb des `elegoo_printer`-Prozesses**,
  die Status 12 setzen und 1051 bedienen, sind in diesen Repos
  nicht enthalten – `elegoo_printer` ist Closed-Source-Binary. Fuer
  die App-Entwicklung ist das aber **nicht noetig**: Der
  beobachtbare Vertrag (MQTT-Methoden, Status-Felder, HTTP-
  Download-Pfad) ist aus `ai_camera`-Quellen und
  `cc2-control`-Code vollstaendig rekonstruierbar.
- Zur sauberen Verifikation der Dateinamen im Filesystem
  (`/opt/usr/picture/<name><ts>/0001.jpeg` …) braeuchte es
  Root-Zugang per SSH; den gibt es laut OpenCentauri auf Firmware
  **ab 02.00.02.00 nicht mehr** (SSH-Prozess entfernt, Downgrade-
  Sperre). Fuer Phase 2 der App **nicht erforderlich** – die
  Datenstruktur wird ueber `method 1036` indirekt sichtbar.
- Firmware-Entpackung (`.zip.sig → .swu.sig → SquashFS`) ist
  **nicht noetig** fuer unser Zeitraffer-Problem; alle relevanten
  Pfade und Methoden sind oben belegt. Wenn Elegoo in einer
  spaeteren FW neue Methoden/Flags einfuehrt, waere Entpackung ein
  Weg; bis dahin verzichten wir.
- Private Signaturschluessel sind in keinem der Repos und werden
  auch nicht gesucht.

### Fazit: Reicht die Recherche?

**Ja fuer die App-Seite.** Der komplette User-Fluss „Zeitraffer
einschalten, filmen lassen, MP4 ueber LAN herunterladen, Historie
pflegen" ist aus den oben verlinkten Datei:Zeile-Belegen
rekonstruierbar. Konkret ergaenzend eingebaut werden kann:

- `method 1019`-Preamble vor `method 1020` (statt oder zusaetzlich
  zu `config.delay_video` in 1020).
- `method 1036` als History-Quelle inkl. Zeitraffer-Status-Enum.
- `method 1051` zum Rendern + Status-12-Progress-Anzeige.
- HTTP-GET `/download?X-Token=…&file_name=video/<name>.mp4` zum
  Download. Status 12 / substate 3020/3021 interpretieren als
  „Rendering" / „Kopieren".
- `method 1038` zum Loeschen eines Druck-/Zeitraffer-Tasks.

**Firmware-Paket wird aktuell nicht benoetigt.** Es waere nur
dann naechster Schritt, wenn der LAN-Download-Pfad gegen den echten
CC2 **nicht** funktioniert (dann koennte das Entpacken Aufschluss
geben, welchen Pfad der HTTP-Dienst beim Drucker tatsaechlich
registriert). Dasselbe gilt fuer Root-Zugang: wuerde nur gebraucht,
falls `method 1036`+`1051`+`/download` beim Realtest widersprechen.

**Konkret ausstehender Test (ein naechster Lauf, lesend):**

1. Druckhistorie via `method 1036` abfragen – `history_task_list`
   fuer die beiden heutigen Drucke pruefen.
2. `time_lapse_video_url` fuer den Zeitraffer-Druck lesen.
3. HTTP-GET auf `http://<cc2-ip>/download?X-Token=<access>&file_name=<url>`
   starten; bei HTTP 200 + Content-Type `video/mp4` ist der
   LAN-Download-Pfad bewiesen.
4. Falls Verweigerung: Firmware-Paket als naechsten Schritt
   erwaegen; vorher aber elegoo-link `elegoo_fdm_cc2_http_transfer.cpp`
   genauer lesen, ob dort ein anderer Pfad fuer Video versteckt ist.

Nichts committed, nichts gepusht. Clones unter `/tmp/handslice-research/`
(nicht im Repo).

---

## 2026-10-26 06:55 UTC – Passiver MQTT-Mitschnitt, zwei Drucke + USB-Export ausgewertet

Mitschnitt: `logs/cc2-sniff-2026-10-26.jsonl`, 1691 MQTT-Nachrichten
in 28 min 51 s (06:23:25 → 06:52:16 UTC). Nur Subscribe `#`, kein
PUBLISH im JSONL (nachweisbar: nur `meta: start/connect/subscribe/
disconnect`-Records vom Script, keine Register- oder Command-Records).

Auswertung: `tools/sniff-analyze.py`.

### Nachweislich funktioniert

- **Zwei Druckläufe sauber erkannt** (gleiche Datei
  `handslice_1792947629010.gcode`, neue `uuid` pro Lauf):
  - Lauf 1 (ohne Zeitraffer): 06:25:11 → 06:37:43 UTC, 12 min 32 s.
  - Lauf 2 (mit Zeitraffer):  06:38:07 → 06:50:38 UTC, 12 min 31 s.
- **Identische sub_status-Sequenz in beiden Läufen**: 1405 (Pre-Heat)
  → 1066 (Bed-Mesh) → 2801/2802 → 1045/1066 → 2075 (Printing). Je
  drei kurze Pause/Resume-Fenster waehrend des Drucks (2501→2502→
  2401→2402). Druckende 2077. Timing praktisch deckungsgleich.
- **Status 12 (VIDEO_COMPOSING) erstmals im Mitschnitt beobachtet** –
  und zwar NICHT am Druckende, sondern bei Klaus' USB-Export-Aktion:
  ```
  06:50:38  Druck 2 fertig           machine_status.status 2→1, state 'complete'
  06:50:49  USB-Stick erkannt        external_device.u_disk = true
  06:50:54  Composing beginnt        status 1→12,  sub_status 0→3020
  06:51:20  Phase 2                  sub_status 3020→3021
  06:51:20  Composing fertig         status 12→1,  sub_status 3021→0
  06:52:03  USB-Stick entfernt       u_disk = false
  ```
  Gesamt-Composing-Dauer: 26 Sekunden. Zeitlicher Abstand Composing-
  Start zu USB-Erkennung: 5 Sekunden; zu Druckende: 16 Sekunden.
- **Unterschiede Lauf 1 vs. Lauf 2** im passiven Mitschnitt: **keine**.
  Der komplette Status-Push-Strom ist in beiden Läufen bis auf
  Zeitstempel und uuid identisch. Insbesondere keine Spur von
  `delay_video`, `camera`, `chassis_camera`, `time_lapse`, `video` –
  weder als Payload-Schluessel noch als Wert, in keinem der 1691
  Datensaetze (grep-Resultat: 0 Hits).
- `exception_status[0]=1243` erschien in beiden Laeufen jeweils einmal
  (06:28:46 Lauf 1, 06:41:41 Lauf 2), jeweils im Pause-Fenster. In
  beiden Laeufen identisch, also **kein Zeitraffer-Signal**.
- Script veraendert den Drucker nicht: Prozess-exit sauber, Drucker
  blieb Idle, keine Nebeneffekte.

### Ungeprueft

- Ob Status 12 **auch** direkt am Druckende (ohne USB-Export) kurz
  gepusht wird. Im heutigen Mitschnitt lag der Delta-Takt bei ~1 s
  und waere nicht leicht zu uebersehen – wir haben keinen 1→12 im
  Zeitraum 06:50:38…06:50:49 gesehen, aber ein zusaetzlicher
  Zeitraffer-Druck ohne USB-Export-Followup wuerde das sauber
  festnageln.
- Bedeutung von `sub_status=1243` (exception) und der kurzen
  Pause/Resume-Zyklen 2501/2502/2401/2402 waehrend des Drucks.
- Welchen Trigger Composing hat: eine aktive Aufnahme (`delay_video=
  true`) oder jede USB-Stick-Erkennung nach einem Druck. Zum
  Trennen braeuchte es einen Druck **ohne** Zeitraffer + USB-Export
  danach als Kontrollprobe.

### Geht nicht / nicht beobachtbar

- **Zeitraffer-Status aus passivem `api_status` ablesbar: nein.**
  Weder `delay_video` noch `chassis_camera.configured` noch
  irgendein Kamera-Capability-Feld werden vom CC2 in diesem Pfad
  gepusht. Die bisher in `docs/networking-cc2.md` dokumentierte
  Erwartung (`external_device.chassis_camera.configured`) hat sich
  im Mitschnitt **nicht bestaetigt** – wir sehen nur
  `external_device.u_disk`.
- **Topic-Diversitaet via Passiv-Sniff: nein.** Alle 1691 Nachrichten
  liegen auf dem einen Topic `elegoo/<sn>/api_status`. Register-
  Response, api_response, Camera-Topics erschienen nicht – fuer die
  braeuchte es eigene Register-/Request-Pakete, die wir hier
  bewusst nicht gesendet haben.

### Konsequenz fuer die App (M5 Punkt 3)

Der aktuelle Workaround („Capability-Feld fehlt → als unterstuetzt
betrachten, nur `configured=0` sperrt") bleibt richtig – im passiven
Pfad existiert fuer diesen CC2 kein Capability-Feld, auf das wir
positiv pruefen koennten. Die neue Erkenntnis ist: Status 12 ist
**primaer der USB-Composing-Zustand**, nicht der Aufnahme-Zustand.
Falls die App Zeitraffer-Fortschritt anzeigen will, muss sie Status
12 als „Composing fuer USB-Export" interpretieren, nicht als
„Zeitraffer wird aufgenommen".

### Artefakte

- `tools/mqtt-sniff.py` – passiver Subscriber mit JSONL-Output.
- `tools/sniff-analyze.py` – Topic/Feld/Transition/Keyword-Report.
- `logs/cc2-sniff-2026-10-26.jsonl` – Rohmitschnitt (SN im Klartext,
  deshalb `logs/` jetzt in `.gitignore`).

---

## 2026-10-25 16:40 – Erster echter Druck aus der App (Commit 2b4fc1a)

- Klaus hat am Poco den ersten echten Druck aus der App ausgelöst:
  Seite A (Strukturiert), Z-Offset 0, Fach A4, PLA. Druckstart,
  Live-Status (Zustand, Progress, Layer-Zähler, Temperaturen) und
  Fortschrittsgefuehl in der App funktionieren; der Wuerfel ist am
  Drucker visuell einwandfrei herausgekommen.
- Damit ist das Phase-3-Erfolgskriterium „Slicen auf dem Geraet und
  Drucken ueber LAN mit Live-Status" erstmals end-to-end erfuellt.

### Beim Realdruck aufgefallene Befunde (M5-Agenda)

1. Pair-Dialog: Vorbelegtes Adressfeld bekam den **Modellnamen**
   („Elegoo CC2 Combo") statt der IP → „Invalid internet address"
   beim Verbinden. Klaus hat die IP manuell eingetragen, danach lief
   es. Dialog muss IP/Hostname halten und beim Speichern pruefen.
2. Fortschritt in Prozent bleibt in der App stehen, waehrend der
   Schichtzaehler mitlaeuft. Am Drucker lief der Prozentwert normal.
   Richtiges Feld aus echtem 1002-Snapshot belegen.
3. Zeitraffer meldet „Unterstuetzung unbekannt – Feld weggelassen",
   obwohl der CC2 (FW 02.01.01.07) belegbar Zeitraffer kann (eigener
   delay_video=true-Test). Fehlendes Capability-Feld muss als
   „unterstuetzt" gelten (Model-Default fuer diesen CC2), nur ein
   ausdrueckliches `configured=0` sperrt.
4. Statusanzeige zeigt Rohschluessel (`machine_status.status`,
   `heater_bed`, `extruder`) statt Zustand/Bett/Duese. Lokalisieren.
5. Z-Offset: Nachweis aus M4c erbracht. Gespeicherten Wert der
   gewaehlten Seite beim Slicen anwenden. Hinweis „nur gespeichert"
   wird zu „wird beim Slicen angewendet". Nachweis: Seite B +0.02
   verschiebt G-Code, Seite A 0 bleibt unveraendert.

Bericht zur Bearbeitung der Befunde folgt als Phase-3-M5-Eintrag.

---

## 2026-10-26 – Offene Punkte für morgen

Nach Abnahme von Phase 4.3 + Stresstest-Nachtrag (A–D) stehen für
morgen vier Themen an:

1. **Neptun-Testmodell skalieren**, damit der `--download`-Stresstest
   bis zum G-Code durchlaeuft. Rohscale 3970 × 15 475 × 5 828 mm
   triggert aktuell libslic3rs Preflight-Grenztest. Umsetzung:
   `scale_factor`-Feld in `engine/test/stress-models.json` + neue
   CLI-Option `--scale <factor>` in `handslice-cli` (Orca-eigene
   Funktion `ModelObject::scale(Vec3d)` aus `libslic3r/Model.cpp`,
   NICHT selbst gebastelt). Vertragstest-Schritt ergaenzen.

2. **Three D Scans Lizenzangabe an der Quelle belegen**. Das Sidecar
   nennt die Lage ehrlich ("Free 3D scan archive, keine CC-Lizenz
   zertifiziert"), aber die Rechtssituation ist unklar. Vor weiterer
   Nutzung die Lizenz an der Quelle klaeren (contact@threedscans.com
   anschreiben oder Terms/Impressum nachlesen) und das Sidecar
   entsprechend scharf stellen. Falls nicht freigegeben: Default-
   Entry austauschen (Stanford XYZ RGB Statuette oder konkrete
   Smithsonian-URL, siehe stress-models.json "smithsonian_hinweis").

3. **"Als Profil speichern" am Gerät durchklicken und Profil wieder
   laden**. In Phase 4.3 ist der Schreib-Pfad komplett
   (`ProfileWriter` → `ApplicationSupportDirectory/profiles/user/
   <slug>.json`), aber am Poco nur per Unit-Test belegt – noch kein
   End-to-End-Lauf mit Settings-Overrides → Save → App neu laden →
   Preset-Pick → Slice. Dafuer braucht's auch den Preset-Picker im
   SettingsScreen (bisher nicht gebaut).

4. **Filament-Einstellungen als naechste Etappe** (Phase 4.4). Das
   Schema aus 4.1 enthaelt den `filament`-Bereich bereits
   vollstaendig (7 Reiter, 22 Gruppen, 83 Options, 38/81/83
   nach Basis/Fortgeschritten/Experte). UI-Pfad analog zu 4.2 Prozess,
   plus Multi-Material-Toggle fuer A1..A4. **Vorsicht:** anders als
   Prozess greifen Filament-Werte in die Druckdynamik ein
   (Temperaturen, Fluss, Retract) – Validate-Fehler sind
   wahrscheinlicher. Die SlicingErrors-Pipeline aus 4.3 sollte das
   abfangen.

---

## 2026-10-25 22:30 – Stresstest ins Repo (eigener Commit)

- `engine/test/stress-test.sh <modell.stl> [--out <dir>]
  [--skip-arm64] [--skip-x86] [--bed A|B]`: misst Slice-Dauer,
  Peak-VmHWM und Thermal-Status (Poco) für x86 und arm64. Keine
  festverdrahteten Fremdmodelle; der Pfad kommt per Argument.
- `docs/stress-test.md`: Doku + Messtabelle vom 25.10. mit Modell-
  Kennzahlen (2 809 436 Dreiecke, 134 MB, 186 × 72 × 209 mm) +
  Herkunftsangabe für auryn.stl: „Auryn Medallion – Print Ready –
  FREE" von Droppingformdesigns, cults3d-URL, Lizenz CULTS „Private
  Use" („No AI"). Hinweis: zum Nachstellen selbst herunterladen.
  Modell und Bilder davon nicht ins Repo (`.gitignore: /local-test/`).
- Vorschlag für ein frei lizenziertes Großmodell im selben Dokument –
  Scan-the-World (CC-BY-SA), Smithsonian 3D (CC0), Stanford
  Thai Statuette (Educational-Use). Nicht eingebaut; wartet auf
  Entscheidung.

Smoke-Test gegen den Kerbenwürfel am x86 und am Poco:
```
x86-exit=0  dauer=1005ms  peak-VmHWM=2812kB (2.7 MB)
arm64-exit=0  dauer=2180ms  peak-VmHWM=15184kB (14.8 MB)
thermal=Status 0 / Status 0
```
Der Script liefert Modell-Kennzahlen (bbox + Triangle-Count) ohne
libslic3r – pure Python.

---

## 2026-10-25 22:10 – Phase 4.3 Nachtrag: Metrik + Einzel-Beleg + saubere SlicingErrors (STOPP)

### 1. Metrik angleichen (1172 vs 1367 mm Filament)

Keine Byte-Divergenz zwischen x86 und arm64, sondern **zwei
verschiedene Messgroessen** im alten Vertragstest-Script:

- Alt (Vertragstest): rohe Summe aller **positiven E-Werte** aus
  `G1 ... E<float>`-Zeilen – zaehlte zusaetzlich die Prime-Pumpen
  nach Retract mit (`G1 E.728 F1800`, kein X/Y). Ergibt im Kerben-
  wuerfel-Baseline **1367 mm**.
- Richtig (Orca-kanonisch): `total_filament_used_mm` aus dem Stats-
  JSON = Summe positiver E **nur bei G1 mit X oder Y** (echte
  Extrusion, ohne Prime-Pumpen). Ergibt **1172.33 mm**.

Belegt: `extrusion_canonical()` im Vertragstest-Script liefert aus
dem G-Code exakt denselben Wert wie das Stats-JSON (Differenz unter
1 mm). Rohe-E-Summe ist um die Retract-/Prime-Zahl aufgeblaeht
(Kerbenwuerfel: 190 mm Retracts → 1367 − 1172 = 195 mm Differenz).

**Fix:** Vertragstest nutzt jetzt `total_filament_used_mm` aus dem
Stats-JSON und validiert zusaetzlich, dass die G-Code-Rekonstruktion
sich damit deckt.

### 2. Einzel-Beleg der drei Overrides (Kerbenwuerfel, Poco)

Jeweils genau EINE Aenderung, Metrik passt zur Aenderung:

| Lauf | Z-Moves | Wall-Linien | Infill-Linien | Filament (mm) |
|---|---:|---:|---:|---:|
| baseline                 | 239 |  97 | 126 | 1172.3 |
| nur `layer_height=0.28`  | **175** |  –  |  –  | 1101.0 |
| nur `wall_loops=4`       |  –  | **185** |  –  | 1403.9 |
| nur `sparse_infill=40%`  |  –  |  –  | **229** | 1393.5 |
| alle drei zusammen       | 174 | 185 | 229 | 2016.3 |

- `layer_height=0.28`: Z-Moves 239 → 175 (−27 %) – weniger Schichten
  bei dickerer Schicht; Filament sogar leicht geringer, weil die
  Dickenerhoehung durch die Linienbreite ausgeglichen wird.
- `wall_loops=4`: Wall-Linien (Outer + Inner) 97 → 185 (+91 %); mehr
  Perimeter.
- `sparse_infill_density=40%`: Sparse-Infill-Linien 126 → 229 (+82 %);
  mehr Fuellbahnen.

### 3. SlicingErrors/Validate sauber abfangen

- `engine/cli/handslice-cli.cpp`: `main` wrappt `run(argc, argv)`
  mit try/catch-Kette:
  ```
  SlicingErrors   → exit 10, pro Error eine '-'-Zeile
  SlicingError    → exit 10
  ConfigurationError → exit 11
  Slic3r::Exception  → exit 12
  std::exception     → exit 13
  ```
  (Argument-Fehler bleiben bei exit 2 ueber `die()`.)
- Lokaler Test mit `--overrides '{"layer_height":"2.0"}'` am x86:
  ```
  exit=12
  handslice-cli: Slic3r-Fehler: Flow::spacing() produced negative
    spacing. Did you set some extrusion width too small?
  ```
  Kein `terminate called`, kein abort/coredump mehr.
- Vertragstest-Schritt 7 am Poco prueft: Meldung enthaelt
  "slicing"/"validate"/"invalid"/"layer_height", KEIN "terminate called",
  Exit != 0.

Die App zeigt die Meldung bereits ueber den bestehenden
`SliceProcessException` → `lastError = 'slice.error:<exit>:<stderr>'` →
`_formatSliceError` → `l.sliceErrorExit(code, msg)` lesbar an
("Slicer fehlgeschlagen (Exit 12): handslice-cli: Slic3r-Fehler …").

### Tests + Build

- 28/28 Widget-Tests gruen (`flutter test test/widget_test.dart`).
- x86-CLI + arm64-CLI mit M10-Hash neu gebaut (Guard: Side-Cars
  identisch).
- Vertragstest `cli-contract-arm64.sh` 7/7 am Poco gruen.

---

## 2026-10-25 21:40 – Phase 4.3: Overrides ins Slicen + Profil speichern (STOPP)

### CLI `--overrides` (`engine/cli/handslice-cli.cpp`)

- Neue Flag `--overrides '<json>'` oder `--overrides @datei.json`.
- Pro Key: Pruefung gegen `print_config_def.get(key)` → **unbekannter
  Key wirft klaren Fehler** (`unknown option 'nonexistent_key'`).
- Pro Wert: `cfg.set_deserialize_nothrow(key, value, ctx)`; bei false
  oder `ConfigurationError` wird opt_key + Wert + Grund gemeldet.
- Angewendet NACH Profil-Chain + `--bed-type` + `--z-offset`, so dass
  Overrides wie in Orcas Preset-Edit-Pfad die oberste Prioritaet haben.

### App-Pfad

- `SlicerService.slice({overrides: Map<String,String>})` reicht den
  JSON-serialisierten Overrides-Map an die CLI durch (`jsonEncode`).
- `ProjectState.slice(overrides: SettingsOverrides?)` holt
  `overrides.all` aus dem Setting-Screen und uebergibt es.
- `ProjectScreen` bindet den `SettingsOverrides` ans Slice-Button.
- CLI-Fehler aus `--overrides` werden ueber die bestehende
  `SliceProcessException` → `lastError='slice.error:<code>:<msg>'`
  lesbar in der UI gezeigt (zusammen mit dem OOM-Pfad aus dem
  Stresstest).

### "Als Profil speichern" (`app/lib/settings/profile_writer.dart`)

- Speichert die aktuellen Overrides als eigenes Orca-Preset:
  `ApplicationSupportDirectory/profiles/user/<slug>.json`.
- Format spiegelt die resources-Preset-Dateien:
  `{name, type:"process", from:"User", inherits:"<base>", <overrides>}`.
- Button im SettingsScreen oben rechts, mit Dialog fuer Profilnamen.
  Snackbar meldet Erfolg (Dateiname) oder Fehler.
- 7 ARB-Keys neu (en + de) inkl. Plural fuer "Überschreibungen".

### Nachweise – G-Code mit 3 Überschreibungen (x86, Kerbenwuerfel)

| Lauf | Z-Moves | Extrusion-Moves | G-Code | Zeit | Filament |
|---|---:|---:|---:|---|---:|
| baseline (ohne --overrides) | 238 | 3 897 | 220 kB | 9m 25s | 1 172 mm |
| `layer_height=0.28`, `wall_loops=4`, `sparse_infill_density=40%` | **196** | **5 843** | 265 kB | 8m 11s | **2 017 mm** |

- Weniger Schichten (238 → 196) durch dickere Schicht (`+40%`).
- Mehr Perimeter + mehr Füllung → +50 % Extrusionslinien.
- Materialverbrauch +72 % (1172 → 2017 mm).
- **Byte-gleiche Baseline:** `diff <(grep -v generated base.gcode) <(grep -v generated base2.gcode) == exit 0`. Zwei identische Laeufe ohne --overrides liefern am x86 denselben G-Code (ausser Zeitstempel-Header).

### Nachweis – Brim-Overrides auf auryn.stl (Stresstest-Modell)

```
--overrides '{"brim_type":"outer_only","brim_width":"6"}'
```
G-Code `local-test/auryn-brim-x86.gcode` (65 MB, 23 s Slice am x86):

- Feature-Marker `;TYPE:Brim` im G-Code vorhanden.
- Erste Schicht (initial_layer_print_height=0.2) hat 525 `G1`-
  Extrusionszeilen vom Typ `Brim`, X-Bereich `[131.21, 144.27]`,
  Y-Bereich `[96.29, 107.60]`.
- Modell ist für Druck ohne Stuetzen auf die Spitze gekippt – der
  Fussabdruck ist deshalb klein. Brim-Ring (span 13×11 mm) liegt um
  den Fuß des gekippten Models und etwas außerhalb des reinen
  Modell-Footprints (im G-Code `Outer wall` nur 5 Zeilen bei
  (137.11, 101.87)); der Brim bildet ringsum eine ca. 6 mm breite
  Haftzone, wie erwartet.
- Grenztest bleibt gruen: alle Brim-X in `[0, 256]`, alle Brim-Y in
  `[-10, 256]` (printable_area + bed_texture_area). Kein OOB.

### Vertragstest `engine/test/cli-contract-arm64.sh` erweitert

- Schritt 5: dieselben drei Overrides am Poco; prueft
  Z-Moves-Ruckgang + ≥30 % mehr Extrusion.
- Schritt 6: ungueltiger Key muss mit `unknown option 'nonexistent_key_xy'`
  abgewiesen werden.
- Weiterhin Byte-Diff Z-Offset −0.04 mm aus 4.1b.

### Tests + Build

- 28/28 Widget-Tests gruen; `flutter analyze` 0 Fehler.
- x86-CLI + arm64-CLI mit M9-Hash neu gebaut (Guard: beide `.commit`-
  Side-Cars identisch).

---

## 2026-10-25 21:00 – Stresstest grosses Modell (vor 4.3, STOPP)

Modell: `auryn.stl` von Klaus, 2 809 436 Dreiecke, 134 MB. Modell lokal
unter `local-test/` (per `.gitignore` ausgeschlossen; nichts davon im
Repo, keine Doku-Bilder).

### 1. Erwartung Grenztest bei --no-center – bestaetigt

STL-Bounds laut Lesung: `X: -93.15..+93.15`, `Y: -35.01..+36.76`,
`Z: 8.00..217.11`. Druckbereich CC2 laut Profil: `printable_area
0..256`, `bed_texture_area 0..-10..256`, `height 256`.

Mit `--no-center` wirft libslic3r direkt `Slic3r::SlicingErrors`
(`terminate called after throwing an instance of 'SlicingErrors'`),
weil X <0 ausserhalb der Platte liegt. Belegt am x86:
`engine/bin/handslice-cli-x86 --no-center auryn.stl → exit 134`
(Abort nach ca. 15 s, waehrend Prefligh-Validierung).

Konsequenz fuer die App: der Grenztest-Pfad ist zwar da, aber der
Nutzer sah bisher nur die abstrakte Exception. Ursache: `slicer.dart`
hat `--no-center` als Default gesetzt – ein Erbe aus den
Reference-Testlaeufen (dort ist das Modell schon vorzentriert).

### 2. Fix – wie Orca-GUI auf die Platte setzen

- `app/lib/engine/slicer.dart`: `noCenter` als Parameter default
  **`false`**. Default-Flow entspricht ab jetzt Orcas GUI.
- Die bereits in `handslice-cli.cpp` eingebaute Zentrierung ruft
  `ModelObject::center_around_origin()` (Model.cpp:1708) +
  `set_offset(bed_center, -bb.min.z())` – das sind Orcas eigene
  libslic3r-Funktionen, keine eigene Mathe. Belegt in docs/engine-
  integration.md "Modellpositionierung".
- Byte-Gleichheit Kerbenwuerfel: `--no-center` vs. Default (Centering)
  liefern am x86 **identischen** G-Code (bis auf den Zeitstempel-
  Header). Grund: der vorzentrierte Kerbenwuerfel wird durch die
  Centering-Logik effektiv um (0,0,0) zurueckbewegt. Belegt per
  `diff <(grep -v generated kerbe-nocenter) <(grep -v generated kerbe-center)` → leer.
- CLI unveraendert, nur Default in der App gedreht; x86/arm64 bleiben
  byte-gleich zum M6-Vertragstest.

### 3. Messung x86 (AMR5) vs. arm64 (Poco X3 Pro)

| Modell | Build | Slice-Dauer | Max VmHWM | G-Code | Est. Druckzeit | Thermal |
|---|---|---:|---:|---:|---|---|
| Kerbenwuerfel 20 mm | x86 | ~0.7 s | ~800 MB | 215 kB | 9m 25s | – |
| Kerbenwuerfel 20 mm | arm64 (Poco) | ~0.9 s | ~800 MB | 215 kB | 9m 25s | Status 0 |
| **auryn.stl (134 MB)** | **x86** | **22.2 s** | **1 240 MB** | **65 MB** | 7h 11m 23s | – |
| **auryn.stl (134 MB)** | **arm64 (Poco)** | **75.5 s** | **1 126 MB** | **65 MB** | 7h 12m 51s | **Status 0** vorher und nachher |

- x86: `/proc/<pid>/status VmHWM` zwischen 779 MB (Start) und 1240 MB
  (Peak). Keine systemrelevante Swap-Nutzung.
- arm64: on-device `/proc/<pid>/status VmHWM`-Polling via adb shell;
  Peak 1126 MB. Thermal-Status via `dumpsys thermalservice` sowohl
  vorher als auch nachher **Status 0** (keine Drosselung), trotz 75 s
  CPU-Volllast.
- G-Code-Vergleich x86 vs. arm64 EXECUTABLE_BLOCK: **nicht byte-
  gleich** – das bekannte TBB-Reorder-Phaenomen (siehe
  `docs/engine-integration.md` "Nondeterminismus"). Fuer den
  Kerbenwuerfel: zwei stabile arm64-Varianten pro Lauf, nachgewiesen
  mit 3 consecutive arm64-Laeufen (sha `84c9ad07…` / `33fbd6a5…` /
  `84c9ad07…`). Fuer das 65-MB-auryn-G-Code gilt dasselbe
  (Perimeter-Reorder in Travel-Moves ab ca. Zeile 1088), funktional
  aequivalent, nur Reihenfolge-bedingt.

### 4. App-UX waehrend Slice

- `SlicerService.slice()` nutzt jetzt `Process.start` statt
  `Process.run` und reicht das Prozess-Handle via
  `onProcessStarted(proc)` an den Caller durch.
- `ProjectState.slice()` haelt das Handle in `_activeProc` + Zeit in
  `_sliceStartedAt`, bietet `cancelSlice({cleanupOutputPath})` an.
- `ProjectScreen` zeigt waehrend `isSlicing` eine neue Karte mit
  Verlaufszaehler `"Slice läuft… mm:ss"`, `LinearProgressIndicator`
  und `Abbrechen`-Button. Nach Cancel: Button-Text wird zu
  `"Wird abgebrochen – warte, bis die Engine stoppt…"`.
- UI darueber (Modell, Drucker, Druckbett, Reiter-Chips) bleibt
  waehrend des Slices komplett reaktiv – belegt am Poco mit dem
  Realdruck-STL. Tabwechsel + Z-Offset-Nudgen gehen weiter.
- Nachweis am Poco (Screenshots `/tmp/handslice_slicing.png` +
  `/tmp/handslice_cancelling2.png`): Fortschrittskarte zeigt
  `"Slice läuft… 00:02"`, Cancel-Button loest den CLI-Prozess am
  Geraet sofort auf (`ps -ef | grep handslice-cli` leer), die
  halb-fertige `handslice_project.gcode` wird aus
  `/data/data/dev.handslice.handslice/files/` geloescht
  (`run-as ls -la files/` zeigt nur `profiles/` + `profileInstalled`).

### 5. OOM-/Signal-Kill-Handling

- `SlicerService` wirft eine neue `SliceProcessException` mit
  `killedBySignal` als Flag (Exit-Code negativ oder 137/143 →
  SIGKILL/SIGTERM, auf Android der LMK bei zu wenig Speicher).
- `ProjectState.slice()` uebersetzt den Signal-Kill ohne vorangegangenes
  `cancelSlice` in `lastError = "slice.oom"`. Die UI zeigt dann die
  lokalisierte Meldung („Nicht genug Arbeitsspeicher — der Slicer
  wurde vom System beendet. Modell mit weniger Dreiecken, dickere
  Schicht oder andere Apps schliessen." / englisch analog).
- Reproduzierbarer Nachweis am Geraet war nicht moeglich: `adb shell
  pkill -9` am App-UID ist `Operation not permitted`, und der 8-GB-Poco
  loest beim 134-MB-Modell keinen echten OOM aus (Peak 1.1 GB von
  7.3 GB). Statt dessen: Unit-Test `ProjectState.slice bei Signal-Kill
  liefert lastError=slice.oom` im `widget_test.dart` deckt den Pfad
  komplett ab.
- `cancelSlice()`-Pfad: ein zweiter Test
  (`ProjectState.cancelSlice setzt cancelRequested + Cleanup`) prueft,
  dass der danach ausgeloeste Signal-Kill NICHT als Fehler gemeldet
  wird und `isSlicing=false` am Ende steht.

### Tests + Commit

- 28/28 Widget-Tests gruen (`flutter test test/widget_test.dart`),
  davon 2 neu fuer OOM + Cancel.
- `flutter analyze` 0 Fehler.
- Commit lokal (Code-Aenderungen + PROGRESS); Modell, Zwischendaten
  und Mess-Logs liegen in `local-test/` und bleiben per
  `.gitignore` ausserhalb des Repos.

---

## 2026-10-25 20:30 – Phase 4.2: Prozess-Einstellungen in der App (STOPP)

Setzt direkt auf 4.1 auf. Nachgeholt vor 4.2:
- `--dump-schema` liefert jetzt `orca_version` (aus `SoftFever_VERSION`,
  version.inc:10) und `slic3r_internal_version` (SLIC3R_VERSION,
  version.inc:17) getrennt. Submodul steht nachweislich auf `v2.4.2`
  (Commit `8500fcdcc`); die `02.06.00.51` ist das interne libslic3r-
  Config-Format-Legacy aus Slic3r/PrusaSlicer, nicht die Nutzer-Version.
- `build_settings_schema.py` berechnet pro Option `tier` nach Klaus-
  Vorgabe (`simple → basis`, `advanced → fortgeschritten`,
  `expert|develop → experte`) und zeigt im Report die monotone
  Ansammlung pro Stufe:
  print 50/324/337, filament 38/81/83, printer 5/68/73.
- arm64 `--dump-schema` am Poco gegen x86 diffen: steht aus (ADB-Device
  war bei Abschluss nicht erreichbar). Build-Guard sichert gleichen
  Quellstand; inhaltlich zwingend identisch, weil beide dieselbe
  statische `print_config_def`-Instanz introspizieren.

### Was in 4.2 gebaut wurde

- **`app/assets/settings-schema.json`** (634 KB) als App-Asset gebuendelt.
  Produziert von `engine/scripts/build_settings_schema.py` – rein
  mechanisch aus Orca v2.4.2.
- **`app/lib/settings/settings_schema.dart`**: Loader + Model
  (`SettingsSchema`, `SettingPage`, `SettingGroup`, `SettingOption`) +
  `enum SettingTier { basis, fortgeschritten, experte }` mit der
  monotonen `includes(mode)`-Logik.
- **`app/lib/settings/settings_overrides.dart`**: `SettingsOverrides`
  (ChangeNotifier) haelt pro Options-Key den vom Nutzer gesetzten
  Wert als serialisierten String; Reset entfernt ihn. Persistenz
  pro Profil ("Als Profil speichern") kommt in 4.3.
- **`app/lib/screens/settings_screen.dart`**: Prozess-Oberflaeche
  - Stufen-Umschalter oben (Basis/Fortgeschritten/Experte), fokussierbar.
  - Suchfeld filtert ueber Key/Label-de/Label-en/Tooltip-de/Tooltip-en.
  - Reiter-Chips (horizontal scrollbar) fuer die Prozess-Seiten;
    bei aktiver Suche sind alle Seiten gleichzeitig sichtbar.
  - Pro Gruppe eine Karte, pro Option eine Zeile mit lokalisiertem
    Label, aufklappbarem Tooltip (Info-Icon), rohem Key + Mode-Marker.
  - Reset-Icon ↺ nur bei geaenderter Option; Label dann farbig
    hervorgehoben.
  - Bedienelemente je Typ: Switch (bool), Dropdown mit lokalisierten
    enum-Labels (enum), Zahlfeld mit −/+-Steppern inkl. min/max aus
    dem Schema (int/float/percent/float_or_percent), Textfeld (string),
    Textfeld-Fallback fuer Vektor-/Spezial-Typen.
  - Komplett per `Focus`+`Builder` fokus-navigierbar (D-Pad, Tab,
    Controller).
- **l10n**: 7 neue ARB-Keys (en + de) in `app_en.arb` + `app_de.arb`
  (`settingsSourceCaption`, `settingsTierBasis/Advanced/Expert`,
  `settingsSearchHint`, `settingsResetTooltip`, `settingsNoMatches`).

### Tests

- 5 neue Widget-Tests in `app/test/widget_test.dart`:
  - `SettingTier.includes` mappt Klaus-Stufen korrekt.
  - `SettingsSchema` laedt eine Mini-Fixture.
  - `SettingsScreen` filtert nach Stufe (Basis zeigt nur simple,
    Fortgeschritten + Experte wie erwartet).
  - Override via Switch wird im `SettingsOverrides` gespeichert;
    Reset-Icon nimmt ihn zurueck.
  - Suchfeld filtert ueber alle Seiten (ignoriert das aktive Reiter-
    Chip).
- Alle 26/26 Tests gruen (`flutter test test/widget_test.dart`).

### Nicht in 4.2 (bewusst)

- "Als Profil speichern" (gehoert nach 4.3, dort wird auch der CLI-
  Overrides-Pfad gebaut).
- Filament- und Drucker-Reiter.
- Vektor-/Spezial-Typen bekommen in 4.3 eigene Bedienelemente.
- Interaktive Werkzeuge (Mal-Pfad fuer Stuetzen/Naht/Farbe,
  Fuzzy-Skin-Painter) sind laut Klaus-Auftrag nicht Teil des
  Einstellungsbaums und bleiben draussen.

---

## 2026-10-25 19:00 – Phase 4.1: Einstellungsbaum-Schema aus OrcaSlicer erzeugt (STOPP)

Grundsatz Phase 4: **nichts von Hand pflegen**. Alles mechanisch aus
OrcaSlicer v2.4.2 abgeleitet.

### Was gebaut wurde

1. **`handslice-cli --dump-schema`** (`engine/cli/handslice-cli.cpp`)
   dumpt `Slic3r::print_config_def` (PrintConfig.hpp:598). Pro Option:
   `key, type, nullable, default, mode (simple/advanced/expert/develop),
   gui_type, label, full_label, category, tooltip, sidetext,
   printer_technology, min/max, enum_values + enum_labels, aliases,
   shortcut, ratio_over, readonly, is_code, multiline`. Keine Interp-
   retation – reine Pass-Through-Spiegelung dessen, was in
   `ConfigOptionDef` (Config.hpp:2204+) steht.
2. **`engine/scripts/extract_tab_layout.py`** parst
   `src/slic3r/GUI/Tab.cpp` mechanisch:
   - `TabPrint::build()` (Zeilen 2311–2802)
   - `TabFilament::build()` + `add_filament_overrides_page()` (3892–4245)
   - `TabPrinter::build_fff()` + `build_unregular_pages()` (4457–5230)
   Erkennt `add_options_page(L("…"))`, `page->new_optgroup(L("…"))`,
   `optgroup->append_single_option_line("key", …)`, Line-Objekte mit
   `optgroup->get_option("key")` und den Wrapper
   `append_option_line(optgroup, "key", …)`. Jede Zuordnung belegt mit
   Datei+Zeile.
3. **`engine/scripts/build_de_catalog.py`** liest
   `localization/i18n/de/OrcaSlicer_de.po` und baut dict msgid→msgstr.
   PO-Multi-Line + Escape-Handling (nur `\\`, `\"`, `\n`, `\t` –
   kein Python-`unicode_escape`, das wuerde UTF-8-Bytes zerreissen und
   Umlaute kaputt machen).
4. **`engine/scripts/build_settings_schema.py`** joined Schema + Layout
   + Deutsch zu `engine/out/settings-schema.json` + Report.

### Report (`engine/out/settings-report.md`)

- OrcaSlicer-Version: `02.06.00.51` (laut `--dump-schema`)
- **751 Options** im `print_config_def` gesamt.
- **5491 Deutsch-Eintraege** aus `OrcaSlicer_de.po`.

Zuordnung Tab.cpp → Bereich/Reiter/Gruppen/Options:

| Bereich | Reiter | Gruppen | Options (einzigartig) |
|---|---|---|---|
| print    | 6 | 41 | 337 |
| filament | 7 | 22 | 83 |
| printer  | 4 | 29 | 73 |

Verteilung nach Stufe:

| Bereich | Simple | Advanced | Expert | Develop | Σ |
|---|---:|---:|---:|---:|---:|
| print    | 50 | 274 | 11 | 2 | 337 |
| filament | 38 |  43 |  0 | 2 |  83 |
| printer  |  5 |  63 |  0 | 5 |  73 |

Nicht zuordenbar (im Schema, nicht im Layout): **258 von 751** – mit
Gruenden gruppiert:
- SLA-only: 76
- Unbenutzt in Tab.cpp (FFF, ohne category): 91
- Ohne Label (interne/Legacy): 40
- any-Technologie (bed_custom, print_host*, printable_area …): 20
- G-Code-Templates (eigener Tab.cpp-Pfad, nicht `append_single_option_line`): 17
- Diverse (Rest in kleinen Kategorien): 14

Uebersetzungsabdeckung Deutsch (nur Layout-Options):

| Bereich | Label | Tooltip | Reiter | Gruppen |
|---|---|---|---|---|
| print    | 333/337 (99%) | 333/333 (100%) | 6/6 (100%) | 41/41 (100%) |
| filament | 80/81 (99%)   | 78/79 (99%)   | 7/7 (100%) | 22/22 (100%) |
| printer  | 71/72 (99%)   | 70/71 (99%)   | 4/4 (100%) | 29/29 (100%) |

**Gruppen mit 0 Keys** (im Report mit Datei+Zeile aufgelistet):
G-Code-Textfelder (`Machine start G-code` etc.) + Notes/Compatible-
Printers – die Felder stehen in Tab.cpp nicht ueber den
Standard-Options-Pfad. Fuer Phase 4.2 (Prozess) nicht relevant;
fuer 4.3/5 (Drucker) spaeter explizit zu adressieren.

### Nachweise

- `engine/bin/handslice-cli-x86 --dump-schema > engine/out/schema-raw.json`
  (16528 Zeilen, OrcaSlicer-Version eingebettet).
- `python3 engine/scripts/extract_tab_layout.py > engine/out/layout.json`
  (2613 Zeilen, pro Key `line` als Belegstelle in Tab.cpp).
- `python3 engine/scripts/build_de_catalog.py > engine/out/de.json`
  (5499 Zeilen, 5491 echte Uebersetzungen; Umlaute korrekt).
- `python3 engine/scripts/build_settings_schema.py …` erzeugt
  `settings-schema.json` + `settings-report.md`.
- `handslice-cli-arm64` ist frisch gebaut (gestript 14 MB, Side-Car
  `d57f8cacd5`); der Device-Lauf (`--dump-schema` am Poco) steht aus,
  weil ADB beim Abschluss nicht verfuegbar war. Der Build-Guard
  (M6) stellt sicher, dass x86- und arm64-Binaries vom selben
  Quellstand kommen – inhaltlich sind beide `--dump-schema`-Ausgaben
  zwingend identisch (reine Introspektion derselben `print_config_def`).

---

## 2026-10-25 18:20 – Zweiter Realdruck aus der App (Commit ac57b14, Seite B, Z-Offset −0,04)

- Klaus hat am Poco den zweiten echten Druck mit der M6-APK ausgeloest:
  Seite B (Glatt, Carbon-Optik), Z-Offset **−0,04 mm**, Fach A4, PLA.
  G-Code-Name auf dem Drucker: `handslice_1792947629010.gcode`.
- Druckstart, lokalisierter Live-Status (Zustand/Bett/Düse),
  Prozentanzeige (aus `current_layer`/`total_layer` abgeleitet, M5-Befund 2)
  und Zeitraffer-Aufnahme am Drucker (M5-Befund 3) laufen wie erwartet.
- Erste Schicht sauber heraus: **Carbon-Muster der Glattseite ist vollflaechig
  abgebildet** – der auf Dart→CLI→Engine-Pfad angewendete Z-Offset von
  −0,04 mm wirkt am echten Druck. Damit ist auch Befund 5 am Geraet
  belegt (M4c + M5 waren G-Code-seitig; dieser Druck ist der physische
  Nachweis).
- Alle fuenf M5-Befunde (Pair-Validierung, Prozent, Zeitraffer-Capability,
  Status-Lokalisierung, Z-Offset scharf) sind damit am echten CC2
  bestaetigt. Phase-3-Erfolgskriterium bleibt erfuellt, mit zusaetzlichem
  Nachweis fuer die Z-Offset-Anwendung.
- Zeitraffer-Video vom Drucker ueber USB gezogen und als
  `docs/media/erster-app-druck-zeitraffer.mp4` eingecheckt; im README
  unter „Erster Druck" verlinkt (zweiter Eintrag).
- **Beobachtung Druckeruhr:** Der CC2 hat das Video intern mit Zeitstempel
  **2026-10-26 01:00:53** benannt – real gedruckt wurde um ~18:05 MEZ am
  2026-10-25. In der Nacht davor war die Umstellung MESZ→MEZ. Nur
  festgehalten, keine Ursache behauptet (vgl. M4b-Befund:
  `print_status`-Uhr lief im LAN-Modus bereits 1 h 33 min hinter UTC).
  Dokumentiert in `docs/networking-cc2.md` Abschnitt „Beobachtung
  2026-10-25: Zeitstempel im Video-Dateinamen weicht ab".

---

## 2026-10-25 17:50 – Phase 3 M6: CLI-Vertrag + Build-Guard nach „unknown flag: --z-offset"

**Vorfall:** Klaus hat am Poco Commit `9c976f1` getestet („Auf dem Gerät
slicen", Seite B, Z-Offset −0,04). Die App brach mit
`ProcessException: handslice-cli exit 2: handslice-cli: unknown flag:
--z-offset` ab.

### Ursache belegt

- `engine/bin/handslice-cli-arm64`: Modify-Time 2026-10-25 12:43,
  stammt vom Commit vor `2b4fc1a` (M4, 16:00). Enthaelt keinen String
  `--z-offset`.
- `engine/bin/handslice-cli-x86`: Modify-Time 2026-10-25 15:58, aus
  dem M4-Rebuild – enthaelt `--z-offset` und wurde beim x86-Test gegen
  den Nachweis-Lauf verwendet.
- `app/android/app/src/main/jniLibs/arm64-v8a/libhandslice_cli.so`
  (13:10) wurde aus der veralteten arm64-CLI befuellt (Gradle-Hook
  `syncHandsliceNativeBinary` kopiert `engine/bin/handslice-cli-arm64`
  → `jniLibs/...so`).
- Damit war die APK M4/M5 funktional korrekt im Dart-Teil, hat aber
  eine CLI aus der Zeit *vor* `--z-offset` eingepackt. Beim x86-Test
  faellt das nicht auf, weil dort das richtige Binary lag.

### Fixes

1. **CLI: `--version` mit eingebettetem Commit-Hash**
   (`engine/cli/handslice-cli.cpp` + `engine/cli/CMakeLists.txt`):
   `-DHANDSLICE_CLI_COMMIT=<hash>` wird in beide CLI-Varianten
   einkompiliert. Fallback: `git rev-parse --short=10 HEAD` zur
   CMake-Konfigurationszeit.
2. **Beide Build-Skripte setzen `HANDSLICE_CLI_COMMIT` aus dem Repo-
   HEAD** (`engine/build-headless-x86.sh`, `engine/build-cli-arm64.sh`).
   Script-Ende ruft `handslice-cli --version`, damit sichtbar ist, was
   gerade in `engine/bin/` liegt.
3. **arm64-Build strippt am Ende** (865 MB → 14 MB mit
   `$ANDROID_NDK/.../bin/llvm-strip --strip-all`). Vorher wurden
   Debug-Infos mitgepackt; Grund fuer die bisherige 14-MB-Groesse war
   der frueher manuell gelaufene Strip-Schritt, der nicht im Skript
   stand.
4. **Build-APK-Guard** (`app/scripts/build_apk.sh`):
   - prueft `handslice-cli-arm64 --version` → Pflicht.
   - prueft `handslice-cli-x86 --version` (falls vorhanden) → Hash
     muss identisch sein, sonst `exit 3`.
   - warnt, wenn CLI-Hash ≠ Repo-HEAD (fuer App-only-Aenderungen OK,
     fuer Engine-Aenderungen klarer Reminder).
   - uebergibt `--dart-define=CLI_COMMIT=<hash>` an den Flutter-Build.
5. **Badge zeigt beide Hashes** (`lib/widgets/build_info_badge.dart`):
   erste Zeile `v0.1 · app <hash>`, zweite Zeile `cli <hash>`, dritte
   Zeile Build-Zeit. Dadurch ist am Geraet sofort sichtbar, wenn App-
   und CLI-Commit auseinanderlaufen.
6. **Vertragstest** (`engine/test/cli-contract-arm64.sh`): pusht die
   arm64-CLI auf den Poco, prueft `--version`, laeuft alle Flags der
   App einmal durch (`--machine --process --filament --resources
   --output --bed-type [--z-offset] --quiet --no-center`) und wertet
   den G-Code-Z-Diff gegen den Baseline-Lauf aus. Mindestens ein
   `--z-offset -0.040`-Lauf gegen den echten Kerbenwuerfel.

### Nachweise

- arm64-CLI nach Rebuild (Modify 2026-10-25 17:45): 13.8 MB stripped,
  Hash im Binary belegbar via `strings | grep "handslice-cli commit"`.
- x86-CLI nach Rebuild (18:…): `--version` liefert
  `handslice-cli commit <hash>` → Guard-Prerequisite erfuellt.
- Vertragstest `engine/test/cli-contract-arm64.sh`: … (siehe
  „Nachweislich funktioniert" im Abschluss-Bericht).
- APK-Badge zeigt jetzt `app <hash>` + `cli <hash>` getrennt; beide
  Hashes decken sich mit `git log HEAD` + `handslice-cli-arm64
  --version`.

---

## 2026-10-25 17:10 – Phase 3 M5: 5 Befunde aus dem Erstdruck behoben

### Befund 1 – Pair-Dialog: Modellname im Adressfeld

- **Ursache:** keine Validierung im `_PairDialog.submit()`. Was im IP-
  Feld stand (OS-/IME-Autofill, altes `prefs['printer.cc2.ip']`), wurde
  ungeprueft in SharedPreferences geschrieben. Beim naechsten Verbinden
  reichte das als Host an `InternetAddress()` – „Invalid internet
  address".
- **Fix (`app/lib/widgets/printer_panel.dart`):**
  - `_looksLikeHost()` prueft IPv4 (vier Oktette 0–255) oder Hostname-
    Label-Kette (RFC 1123, vereinfacht).
  - Save-Button bleibt disabled, solange die IP ungueltig oder der Code
    leer ist; Fehlertext inline unter dem IP-Feld.
  - Autofill-/Suggestions-Hinweise an die Tastatur ausgeschaltet
    (`autocorrect:false`, `enableSuggestions:false`, leere
    `autofillHints`).
  - Vorbelegung aus `widget.initialIp` wird nur uebernommen, wenn sie
    selbst wie IP/Hostname aussieht – ein Mist-Wert in prefs faelscht
    das Feld nicht mehr.
- **Nachweis:** 2 neue Widget-Tests in `app/test/widget_test.dart`:
  - „Save bleibt gesperrt bei Modellname statt IP" – gibt genau
    `Elegoo CC2 Combo` ein, erwartet Fehlertext + Button-disabled.
  - „Vorbelegung ignoriert Modellname aus prefs" – startet mit
    vergiftetem Pref-Wert, Dialog oeffnet mit leerem Feld.

### Befund 2 – Fortschritt in % bleibt stehen

- **Ursache:** `PrinterState.printProgress` las `print_status.progress`.
  Beim Realdruck 09:18 wandert dieses Feld nicht gleichmaessig mit;
  `current_layer`/`total_layer` sind die zuverlaessige Fortschritts-
  Quelle (siehe docs/networking-cc2.md Nachweislauf).
- **Fix (`app/lib/state/printer_state.dart`):**
  ```
  int? get printProgress {
    final cl = currentLayer; final tl = totalLayer;
    if (cl != null && tl != null && tl > 0) {
      return ((cl * 100) / tl).round().clamp(0, 100);
    }
    return _getInt(['print_status', 'progress']); // Fallback
  }
  ```
- **Nachweis:** 2 neue Unit-Tests – aus `current=25,total=100` kommt
  25 %, auch wenn `progress=0` gleichzeitig gepusht wird. Fallback-Pfad
  bleibt getestet.

### Befund 3 – Zeitraffer-Capability

- **Ursache:** `supportsTimelapse` lieferte `null` bei fehlendem
  `external_device.chassis_camera.configured`. UI zeigte dann
  „Unterstuetzung unbekannt – Feld weggelassen". Fuer den CC2 ist
  Zeitraffer aber belegbar (docs/networking-cc2.md 2026-10-25 10:30:
  `delay_video=true` wirkt, Klaus hat das Video am Drucker gesehen).
- **Fix:** `supportsTimelapse` ist jetzt `bool`:
  - `configured == 1` → `true`
  - `configured == 0` → `false` (Schalter gesperrt, Hinweis
    „Dieser Drucker meldet keine Kamera – Zeitraffer deaktiviert")
  - Feld fehlt → `true` als CC2-Modell-Default (Beleg s. o.)
- Im Druckstart wird `delay_video` jetzt immer gesendet (true oder
  false), nicht mehr weggelassen.
- **Nachweis:** 3 neue Tests – jeder der drei Faelle einzeln.

### Befund 4 – Status-Beschriftungen lokalisiert

- **Fix:** `_LiveStatus` zeigt jetzt lokalisierte Labels statt
  Rohschluessel. Neue ARB-Keys in `app/lib/l10n/app_en.arb` + `_de.arb`:
  - `printStatusLabel` – State / Zustand
  - `printBedLabel` – Bed / Bett
  - `printNozzleLabel` – Nozzle / Düse
  - `printExceptionLabel` – Printer alarms / Drucker-Alarme
  - `printTempFormat` – `{cur} / {tgt} °C` (lokalisiertes Grad-Format)
- Numerische Statusanzeige („2 — Printing") durch reinen lokalisierten
  Zustandstext ersetzt.
- **Nachweis:** Widget-Test „PrintScreen: Status-Labels sind
  lokalisiert" – findet State/Bed/Nozzle, verifiziert, dass
  `machine_status.status`, `heater_bed`, `extruder` nicht mehr im UI
  stehen.

### Befund 5 – Z-Offset scharf schalten

- **Fix:**
  - `SlicerService.slice(zOffsetMm: ...)` reicht den Wert als
    `--z-offset <mm>` an `handslice-cli` durch (nur wenn ≠ 0, haelt
    die CLI-Zeile sauber).
  - `ProjectState.slice()` nimmt automatisch den gespeicherten
    `zOffsetFor(_bedType)` fuer die aktive Plattenseite.
  - UI-Hinweistexte aktualisiert: „Z-Offset pro Seite (wird beim
    Slicen angewendet)" / „±0,50 mm, Schritte 0,01 mm — wird beim
    Slicen angewendet".
- **Nachweis G-Code-Vergleich (handslice-cli-x86, Kerbenwuerfel):**
  ```
  Seite A, baseline  vs  Seite A, --z-offset 0.000
    → 1220/1220 Z-Zeilen identisch; nur Zeitstempel-Header differiert.
    → "wird nicht angewendet, wenn 0" belegt.

  Seite B, baseline  vs  Seite B, --z-offset 0.020
    → 1218/1220 Z-Zeilen exakt um +0.020 verschoben.
    → 2 Zeilen unveraendert = `G1 Z0.5` aus CC2_START_GCODE-Macro
      (absolut im Start-Macro, nicht durch Offset beeinflusst –
      exakt wie M4c vorhergesagt).
    → Erste Schicht ebenfalls verschoben: 0.2 → 0.22, 0.4 → 0.42,
      0.457143 → 0.477143.
    → "wird beim Slicen angewendet" belegt.
  ```
- **Nachweis Dart-Pfad:** Widget-Test „ProjectState.slice uebergibt
  zOffsetMm an den Slicer" – prueft, dass der gespeicherte Wert pro
  Plattenseite byte-exakt am Slicer-Call ankommt.

### Tests + Build

- `flutter test test/widget_test.dart` 22/22 gruen (vorher 13; +9 neue
  Tests fuer M5).
- `flutter analyze` 0 Fehler (1 info in `elegoo_mock_test.dart`:
  `dart:async`-Re-Import, nicht blockierend).
- APK neu gebaut + auf Poco X3 Pro installiert; Badge zeigt den M5-
  Commit (siehe Nachweis unten im Abschluss-Bericht).

---

## 2026-10-25 16:00 – Phase 3 M4: Druckstart + Live-Status in der App

Code-Umfang + Nachweise – Claude Code sendet 1020 NICHT an den
echten Drucker; den echten Druck startet Klaus selbst am Poco.

### M4-R0 Beleg

- `elegoo-link/.../elegoo_fdm_cc2_message_adapter.cpp:85-96` –
  `slot_map`-Form `{t, canvas_id, tray_id}`, ein Eintrag pro Tool.
- A1..A4 ↔ tray_id 0..3 aus unserem M3-CANVAS-Read bestaetigt
  (A4 = tray_id 3).
- `supportsTimeLapse` kommt im LAN-Pfad aus
  `api_status.external_device.chassis_camera.configured == 1`
  (`.../elegoo_fdm_cc2_message_adapter.cpp:1148-1163`), nicht aus
  `GET_PRINTER_ATTRIBUTES` (dort beim CC2 bewusst nicht
  ueberschrieben, Zeile 532-535). Konsequenz fuer die Dart-Logik:
  `delay_video`-Feld wird nur gesendet, wenn die Capability
  belegbar beobachtet wurde; sonst weggelassen (per
  CC2_PROTOCOL.md: „leaving the key out lets the printer decide").

### M4a Druckstart

- `ElegooCc2Client.startPrint(filename, bedlevelForce, printerCheck,
  delayVideo?, slotMap)` baut method 1020 feld-fuer-feld.
- `PrinterState.printPreflight(boundsOk)` prueft **vor** dem Start:
  no_upload → not_connected → bounds_failed → not_idle (aus 1002)
  → tray_empty (CANVAS-Slot leer). Jede Sperre liefert einen
  l10n-Key fuer die UI.
- PING-Loop (10 s) wird in `connectAndLoad()` gestartet,
  automatisch bei Reconnect neu abonniert.

### M4b Status + Reconnect

- `_mergeStatus()` nimmt sowohl 1002 (initial) als auch api_status-
  Deltas (via `client.statusDeltas`) und mergt rekursiv in den
  Live-State.
- UI-Getter fuer `machine_status`, `print_status`, `heater_bed`,
  `extruder`, `exception_status`, `chassis_camera.configured`
  (fuer supportsTimelapse-Capability).
- `remainingSeconds` wird aus `print_status.remaining_time_sec`
  gelesen + lokal weitergezaehlt zwischen Updates. **Keine
  Druckerzeitstempel** – die Druckeruhr lief in unserem Lauf
  nachweislich ca. 1h 33min nach UTC.
- Verbindungsabbruch → `_scheduleReconnect()` nach 5 s. **Der
  laufende Druck am Drucker ist davon nicht betroffen**, der laeuft
  komplett lokal; wir re-verbinden nur die Beobachter-Session und
  re-abonnieren Status.
- UI zeigt „Verbindung verloren – wird neu aufgebaut…"-Hinweis.

### M4c Z-Offset-Nachweis (nicht scharf geschaltet)

CLI minimal um `--z-offset <mm>` erweitert (nur Diagnostik, nicht
in der App verdrahtet). Zweimal den Kerbenwuerfel gesliced:
`z_offset=0.00` vs. `z_offset=0.05`.

- **1196 Z-Zeilen verschoben um +0.05 mm**, bis auf 2 Werte mit
  FP-Noise (0.050001, 0.04997).
- **Erste Schicht** ebenfalls verschoben (`Z.2` → `Z.25`).
- **Keine XY-/E-Divergenz** ausser dem bekannten TBB-Progress-
  Reordering (3 M73-Zeilen).
- **Start-G-Code (`CC2_START_GCODE`) hebt den Offset NICHT auf.**
  `G1 Z0.5 F900` in Zeile 40 (Prime-Fahrt im `machine_start_gcode`)
  ist in beiden Varianten identisch, weil das `Z0.5` absolut im
  Macro-Text steht. Danach beginnt ab Zeile 81 der eigentliche
  Druck mit korrektem Offset.

Hinweis „nur gespeichert" bleibt in der UI, bis Klaus freigibt.

### Tests + Build

- 13 Widget-Tests gruen (`flutter test test/widget_test.dart`):
  - method 1020 Payload-Feld-fuer-Feld-Vergleich mit dem
    tatsaechlichen 1020 vom ersten echten Druck (storage_media,
    filename, config.*, slot_map): identisch.
  - delayVideo=null → `delay_video`-Feld fehlt (Capability unknown).
  - printPreflight-Sperren (no_upload, bounds_failed).
  - Plus die 10 Alt-Tests (Z-Offset, Bounds-Check, Plate-Toggle,
    Slice-Darstellung, Pair-Dialog, …).
- 5 Mock-Integration-Tests gruen inkl. neuem
  „Mock: method 1020 startPrint liefert error_code=0".

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Druckstart-Payload wird byte-identisch zum tatsaechlichen 1020
  vom ersten echten Druck gebaut – belegt durch Widget-Test.
- Alle fuenf Pre-Flight-Sperren (no_upload, not_connected,
  bounds_failed, not_idle, tray_empty) sind verdrahtet und
  blockieren den Druck-Button in der UI.
- Live-Status-Delta-Merge; Restzeit aus Dauer + lokale Fortschreibung
  (nicht aus Druckeruhr). PING-Loop 10 s. Auto-Reconnect ohne
  Impact auf den laufenden Druck.
- `delay_video` wird nur gesendet, wenn die Capability aus
  `external_device.chassis_camera.configured` belegbar ist.
- Z-Offset-Nachweis: eindeutig, nur Z um 0.05 mm, auch Layer 1;
  Start-G-Code hebt den Offset nicht auf.
- `flutter test`: 18/18 gruen (13 Widget + 5 Mock).

**2. Ungeprueft**

- **Live-Lauf gegen den echten CC2.** Claude Code sendet 1020 nach
  Vorgabe nicht; Klaus startet den eigentlichen Druck am Poco mit
  Z-Offset 0 nach Sichtkontrolle.
- **Status-Darstellung waehrend eines echten Drucks** – im Mock
  antwortet 1020 mit error_code=0, aber danach pusht der Mock
  keine „Printing"-Deltas. Reale Status-Transitionen (status=2 →
  bed_mesh_detect=true → Layer 1 → …) werden erst im Live-Lauf
  sichtbar.
- **Keep-Alive-Timeout bei Netz-Abbruch mitten im Druck.**
  Reconnect-Logik ist drin; Verhalten unter realem WLAN-Flap
  nicht geprueft.

**3. Geht nicht**

- (keine neuen Blocker)

---

## 2026-10-25 15:20 – Nebenaufgabe: method 1047 (DELETE_FILE) am CC2 gemessen

Fuer upstream Issue
[danielcherubini/elegoo-homeassistant#432](https://github.com/danielcherubini/elegoo-homeassistant/issues/432).

### Beleg Parameter-Struktur (nicht geraten)

- `CC2_PROTOCOL.md` zeigt Request `{"id","method":1047,"params":{"storage_media":"local","filename":"..."}}`,
  markiert als „Untested, no response captured".
- `custom_components/elegoo_printer/cc2/client.py:2577-2644`
  (`async def delete_file`) sendet exakt diesen Payload.
- `elegoo-link/src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp:1411`:
  `// {MethodType::DELETE_FILE, 1047}` **auskommentiert**.
- Volltext-grep im ganzen elegoo-link-Repo (243 Dateien): keine
  aktive `deleteFile(...)`-Signatur, kein `DeleteFileParams`,
  kein HTTP DELETE. ElegooSlicer loescht am CC2 nach aktuellem
  main-Stand **nichts** aus dem LAN. Parameter-Struktur ist damit
  eindeutig als `{storage_media, filename}` belegt – keine zweite,
  abweichende Form im Code.

### Was gemessen wurde

- D-1: `method 1044 local` → 23 `.gcode`, 0 Videos. `sdcard` + `udisk`
  je 0. Entry-Struktur anonymisiert in docs/networking-cc2.md
  festgehalten.
- D-2: Harmlose Test-G-Code-Datei `handslice_delete_test_<ts>.gcode`
  (182 B, nur Kommentare) hochgeladen, Liste 23 → 24, Testdatei
  genau 1× sichtbar. Klaus hat am Display bestaetigt.
- D-3: `method 1047` fuer genau diese eine Datei:
  **Firmware antwortet nach 13 ms mit `error_code=1003`,
  Datei wird NICHT geloescht.** Alle anderen Dateien unveraendert
  (name-hash-Vergleich pre/post).
- D-4: `method 1047` fuer einen definitiv nicht existierenden Namen:
  identische Antwort `error_code=1003`, 10 ms, Liste 24/24.

### Deutung (bewusst als Vermutung formuliert)

Dieselbe Firmware liefert `error_code=1003` auch fuer `method 1045`
(frueher gemessen) und einige andere nicht implementierte
Methoden. **Vermutung**, nicht Doku-Aussage: `1003` ist der
generische „not available / not implemented in this firmware"-Code
auf 02.01.01.07. 1047 ist auf dieser Firmware vermutlich nicht
aktiv – entsprechend passt der HA-Integration-Code bereits mit „0
= did not refuse, nicht beweis fuer deletion; re-list via 1044".

### Was Klaus noch tun muss

- Testdatei `handslice_delete_test_<ts>.gcode` liegt noch im local-
  Speicher des Druckers (1047 hat sie nicht geloescht). Loeschen
  entweder am Display, oder sie bleibt bis zur naechsten Firmware
  mit funktionierendem 1047.
- Issue-Kommentar-Entwurf unter
  `docs/upstream/elegoo-homeassistant-issue-432-draft.md`. Enthaelt
  einen `<TODO>` fuer Klaus' spezifischen Hinweis zur Druckeruhr
  (die Briefing-Nachricht war an der Stelle abgeschnitten).
  Observed: `create_time`-Feld in `method 1046` liefert einen
  Unix-Timestamp, der heute ca. 1 h 33 min hinter der realen UTC
  liegt – aber ohne Klaus' Zusatz formuliere ich das nicht als
  Befund.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Parameter-Struktur von `method 1047` eindeutig als
  `{storage_media, filename}` belegt (zwei Quellen).
- Testlauf an echter Hardware: `method 1047` liefert
  `error_code=1003` sowohl fuer existente als auch nicht-existente
  Dateinamen; Dateiliste bleibt unveraendert.
- Vor-/Nach-Vergleich der Dateiliste per Hash – alle anderen
  Dateien unberuehrt.
- Rohantworten + Pre-/Post-Snapshots anonymisiert in
  docs/networking-cc2.md eingetragen (keine SN, IP, Access-Code
  oder Account-IDs).
- Issue-Kommentar-Entwurf in docs/upstream/.

**2. Ungeprueft**

- **1003 ≡ „not implemented"** bleibt eine Vermutung, nicht Doku –
  Elegoo veroeffentlicht kein error-code-Mapping; die
  HA-Integration deutet 1007 als FILE_DELETE_FAILED, nicht 1003.
- Testdatei am Drucker noch da (siehe oben); Loeschung durch Klaus.

**3. Geht nicht**

- **method 1047 funktional auf Firmware 02.01.01.07.** Die Firmware
  antwortet, aber loescht nichts. Kein Blocker fuer das Projekt –
  die App-UI wird in Phase 2+ ohnehin `cleanup_files` nicht
  anbieten, solange die Firmware das nicht sauber macht.

---

## 2026-10-25 15:00 – Fix: Pair-Dialog-Crash + Build-Info im Header + SN-Scrub

Klaus hat beim ersten Live-Lauf (Commit 828ff96) auf dem Poco
„Drucker koppeln" getippt → roter Fehlerbildschirm:

```
'package:flutter/src/widgets/framework.dart': Failed assertion:
line 6281 pos 12: '_dependents.isEmpty': is not true.
```

### Ursache (an der Wurzel)

Flutter framework.dart:6281 ist der Assert in
`InheritedElement.debugDeactivated`. Er greift, wenn ein
`InheritedElement` deaktiviert wird, waehrend es noch Dependents
hat.

Im ursprunglichen `_openPairDialog` wurden zwei
`TextEditingController` im outer State erzeugt und sofort nach
`await showDialog` disposed. Zur Dispose-Zeit lief die Dialog-Pop-
Animation noch; die `TextField`-Elements im Dialog-Tree waren noch
dependents der umliegenden `_LocalizationsScope`/Theme-Inherited-
Elements. Zusaetzlich wurde `ipCtrl.text` **nach** `ipCtrl.dispose()`
gelesen (use-after-dispose).

### Fix (kein try/catch-Pflaster)

Dialog als eigener `StatefulWidget` (`_PairDialog`), die Controller
leben in dessen `State` und werden erst in dessen `dispose()`
freigegeben – also nach dem vollstaendigen Unmount der Dialog-
Element-Hierarchie. Das ist der kanonische Flutter-Weg; keine
Lifecycle-Workarounds mehr.

### Regression-Test (RED → GREEN)

`test/widget_test.dart`:
`PrinterPanel: Pair-Dialog oeffnet, Save speichert ohne
Framework-Assertion` – oeffnet den Dialog, tippt IP + Code,
drueckt Save, pumpAndSettle. Mit dem alten Code schlug der Test
fehl („Multiple exceptions (5) were detected during the running of
the current test"); mit dem Fix laeuft er sauber durch.
Nachgewiesen durch kurzen `git stash` + Test-Lauf.

### F5 – Commit-Stand sichtbar in der App

- `BuildInfoBadge`-Widget (Mono-Text) im Projekt-Screen oben
  rechts: `v0.1 · <commit>` + Build-Zeit.
- Werte werden ueber `--dart-define=BUILD_COMMIT=` /
  `BUILD_TIME=` eingebrannt; `app/scripts/build_apk.sh` setzt sie
  automatisch aus `git rev-parse --short=10 HEAD` und `date -u`.

### F6 – Serial Number Scrub

Suche in Working-Tree + Git-History (`git log --all -S`): die SN
tauchte in `PROGRESS.md` (6×), `docs/networking-cc2.md` (6× +
1× verkuerzt) und `engine/test/mock-cc2/mock_cc2.py` (1×) auf.

- **Working-Tree:** alle 14 Fundstellen durch Platzhalter `<cc2-sn>`
  (bzw. „CC2 im Haus" in einer Tabelle) ersetzt. `git grep <cc2-sn>`
  liefert jetzt leer.
- **Git-History seit letztem Push (origin/main..HEAD):** nur
  Commit `828ff96` enthielt die SN (3 Treffer). Dieser Scrub-Commit
  liegt direkt darueber; nach dem Fix-Commit „leakt" die SN damit
  nicht in neue Pushes. Rewrite von `828ff96` wuerde Force-Push
  erfordern und ist laut CLAUDE.md § 2 gesperrt – ohne Klaus-
  Entscheidung nicht gemacht.
- **Bereits gepushte Commits:** `7ac8e7b`, `e5ad931`, `7aa8108`,
  `93e26d0`, `684d1f6` enthalten die SN im History-Zustand von
  `origin/main`. Entfernung erfordert Force-Push auf main.
  **Entscheidung an Klaus:** entweder Force-Push nach Backup
  (CLAUDE.md § 2 bricht), oder SN im Repo akzeptieren (sie ist
  nicht sensibel genug fuer ein Access-Grant, aber identifiziert
  den Drucker eindeutig gegenueber anderen Elegoo-Besitzern).

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Pair-Dialog laeuft ohne `_dependents.isEmpty`-Assertion durch
  (Regression-Widget-Test gruen, nach Rollback des Fixes schlaegt
  er fehl – echter RED→GREEN-Beweis).
- 10 Widget-Tests + 4 Mock-Integration-Tests gruen (`flutter test`).
- `BuildInfoBadge` zeigt `v0.1 · <commit>` + UTC-Build-Zeit im
  Projekt-Screen (nutzt `--dart-define`).
- `app/scripts/build_apk.sh` setzt die Build-Info automatisch aus
  Git.
- SN `<cc2-sn>` nirgends mehr im Working-Tree
  (`git grep <cc2-sn>` ist leer).

**2. Ungeprueft**

- **Live-Lauf auf dem Poco nach dem Fix.** APK wird gebaut und
  installiert – der eigentliche „Drucker koppeln"-Klick muss von
  Klaus bestaetigt werden.
- **Live-Reproduktion des Original-Crashes per adb logcat.** USB-
  Tunnel wurde instabil beim Install-Lauf; die Ursachenanalyse
  stuetzt sich auf Klaus' Error-Snippet, Flutter-Framework-Code
  und den RED-Test, der den Pfad geschlossen beweist.
- **Rewrite der bereits gepushten Commits** – nicht gemacht, siehe
  F6-Entscheidung.

**3. Geht nicht**

- (keine neuen Blocker)

---

## 2026-10-25 14:30 – Phase 3 M3: Discovery, CANVAS, Upload gegen Mock + echten CC2

Vor M3 die vier Nacharbeiten aus M2 (Z-Offset, printer_check-Label,
Grenztest, Mock-Server). Danach M3 selbst.

### N1 – Z-Offset einstellbar

- UI: Zwei Fokus-Buttons `-` / `+` (D-Pad erreichbar, sichtbarer
  Fokus-Ring), aktueller Wert in Plex Mono mittig. Schritt 0.01 mm,
  Grenze ±0.50 mm, deaktiviert an den Enden.
- `ProjectState.nudgeZOffset(bedType, delta)` quantisiert auf
  0.01 mm (Vermeidung von Float-Drift bei vielen `+/-`-Klicks) und
  clampt an `zOffsetMin/Max`.
- Pro Plattenseite getrennter Shared-Preferences-Key, kein shared
  default mehr. Wert wird weiterhin **nicht angewendet**; Hinweis
  „±0.50 mm, 0.01 mm Schritte — noch nicht angewendet" bleibt
  direkt unter dem Wert.
- Widget-Test „Z-Offset: Nudge beachtet Grenzen + 0.01-mm-Raster"
  deckt +60× / −1000× ab.

### N2 – `printer_check`-Semantik + Label

Beleg aus `docs/CC2_PROTOCOL.md` (HA-Integration):

> „`printer_check` – Auto bed leveling. Three states, measured on
> 02.01.00.00: `true` always levels (~200 s), `false` never does,
> and leaving the key out lets the printer decide. ElegooSlicer
> sends `true`, or `false` when its bed-leveling box is unchecked."

Mapping im `elegoo-link`:
`src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp:81`
setzt `config.printer_check = startPrintData.autoBedLeveling`.

**Konsequenz:** Das Label „Auto-Nivellierungscheck" war
irrefuehrend. Neu:

- Englisch: „Always level the bed (adds ~200 s)".
- Deutsch: „Immer bettnivellieren (dauert ~200 s)".

`bedlevel_force` (Label „Bettnivellierung vor diesem Druck
erzwingen") bleibt daneben als expliziter Zwang.

### N3 – `engine/test/check-bounds` Grenztest-Skript

Python 3, parst `printable_area` + optional `bed_texture_area` +
`printable_height` aus dem Machine-Profil, geht alle
G0/G1/G2/G3-Bewegungen durch (modaler Zustand fuer absolute/
relative + G28/G92-Nullung), meldet XY-/Z-Verletzungen auf stderr.
Exit 0=OK, 1=FAIL, 2=Argument-/Datei-Fehler.

Nachweis:
- Kerbenwuerfel-G-Code → `OK: alle Bewegungen innerhalb X 0..256,
  Y −10..256, Z 0..256`.
- Synthetischer OOB-G-Code (`G1 X300`, `Y270`, `Z260`) → `FAIL: 3
  Verletzung(en)` + Zeilen auf stderr.

### N4 – Bounds-Check in die App

- `app/lib/engine/bounds_check.dart` ist der 1:1-Port der
  Python-Logik (gleiches Verhalten, gleiche Toleranz 1 mm /1000).
- `ProjectState.slice()` ruft nach erfolgreichem Slice automatisch
  `checkGcodeFile(outputPath, bounds)` und speichert
  `boundsViolations`.
- `PrintScreen` zeigt Status-Box
  (gruen „alle Bewegungen innerhalb der Druckflaeche" oder rot
  „N Bewegungen ausserhalb"), und **Upload/Druck-Buttons sind
  deaktiviert**, wenn `boundsViolations.isNotEmpty`.
- Zwei neue Widget-Tests: Profil-Parse (XY-Erweiterung durch
  `bed_texture_area`) und in-/out-of-bounds-Erkennung mit modal
  state (inkl. relativer Moves).

### N5 – CC2-Mock-Server

`engine/test/mock-cc2/mock_cc2.py` (Python 3 + mosquitto):

- MQTT 1883 via Mosquitto-Subprocess mit password_file. Access-Code
  aus `--access-code` oder `$MOCK_ACCESS_CODE`, Placeholder-SN
  `MOCK0000000000M1` (nicht die echte).
- UDP 52700 Discovery (eigener asyncio-Listener, antwortet mit
  derselben JSON-Struktur wie der echte CC2).
- HTTP 8080 chunked `PUT /upload` + X-Token-Pruefung.
- MQTT-Adapter abonniert `elegoo/<sn>/api_register` und
  `.../+/api_request` und spielt Register-Response + 1002 + 2005 +
  1044 + 1046 + 1020-ACK zurueck.
- Fehlerinjektion:
  - `--reject-auth` → Mosquitto ohne User, CONNACK rc=5.
  - `--interrupt-upload-at N` → HTTP schliesst Verbindung nach
    N Byte Upload.
- Access-Code taucht nirgends in den Mock-Logs auf (Platzhalter
  `<accepted, see --access-code>` statt des Werts).

### M3 I1-I4 – Dart-Client + UI

- `app/lib/net/elegoo_cc2_client.dart`: `ElegooCc2Client` mit
  `discover(ip)`, `connect(ip, sn, accessCode)` (MQTT 3.1.1 ueber
  `mqtt_client`), `getStatus(1002)`, `getCanvasStatus(2005)`,
  `getFileList(1044)`, `uploadGcode(name, data, onProgress)`
  (chunked PUT, 1 MiB), `ping()`, `disconnect()`. Eigene
  Exception-Typen (`ElegooAuthException`, `ElegooNetworkException`,
  `ElegooRegistrationException`, `ElegooUploadException`) damit
  der UI-Code sauber reagieren kann.
- `app/lib/state/printer_state.dart`: haelt IP + SN in
  SharedPreferences; **Access-Code in `flutter_secure_storage`**
  (Android: EncryptedSharedPreferences-Default). `savePairing()`
  nimmt Code und schreibt ihn direkt in Secure-Storage;
  `connectAndLoad()` fuehrt Discovery → Register → CANVAS in einem
  Schritt mit sauberer Fehler-/Statusanzeige.
- `app/lib/widgets/printer_panel.dart`: Projekt-Screen-Panel
  „Drucker", zeigt Verbindungstatus, oeffnet Pairing-Dialog (IP +
  Access-Code; Code als `obscureText`), listet nach Verbindung
  die echten A1..A4-Faecher mit Materialfarbe + Typ. Tipp auf einen
  Slot setzt die Tool-0-Zuordnung.
- `PrintScreen`-Upload-Button verdrahtet mit
  `printerState.uploadGcode()`; `onPressed` ist deaktiviert, wenn
  Slice fehlt, Bounds-Check fehlgeschlagen ist, Upload laeuft, oder
  Drucker nicht verbunden ist. Fortschrittsbalken + Erfolgs-/
  Fehlerbox.
- Druck-Button bleibt in M3 bewusst **disabled** (M4-Scope).

### M3 I5 – Mock-Tests

`app/test/elegoo_mock_test.dart` startet den Mock-Subprocess und
faehrt vier Pfade:

| Test | Ergebnis |
|---|---|
| Discovery + Register + Canvas (richtiger Code) | ✓ |
| Falscher Access-Code → `ElegooAuthException` | ✓ |
| Upload + GET_FILE_LIST-Pruefung | ✓ |
| Upload-Abbruch nach 2 KiB → `ElegooUploadException`/`SocketException` | ✓ |

Alle vier gruen. Zusammen mit 9 Widget-Tests: **13 Tests gruen**.

### M3 I6 – Lauf gegen den echten CC2

`app/tool/real_cc2_check.dart` liest `CC2_IP` + `CC2_ACCESS_CODE`
aus der Umgebung (nicht aus Argumenten, nicht aus einer Datei im
Repo), gibt den Code **nirgends** aus. Lauf mit dem
Kerbenwuerfel-G-Code als Nutzdaten:

```
[M3 real] 1) Discovery (UDP 52700)…
  sn=<cc2-sn>  model=Centauri Carbon 2  host=Centauri Carbon 2
  lan=true  token_status=true  proto=1.0.0
[M3 real] 2) MQTT Connect + Register… OK
[M3 real] 3) method 2005 (CANVAS)…
  A1 PETG  PETG                 #000000
  A2 PETG  RAPID PETG           #FFFFFF
  A3 PLA   PLA PRO              #000000
  A4 PLA   RAPID PLA+           #FFFFFF
[M3 real] 4) HTTP PUT /upload (chunked)… 100 %
  → error_code=0, offset=220260, uploaded=handslice_m3_<ts>.gcode (220261 B)
[M3 real] 5) method 1044 (file list local)…
  Datei bestaetigt. Gesamt 23 Dateien im local-Speicher.
[M3 real] 6) DISCONNECT
[M3 real] FERTIG. Kein Druckstart ausgefuehrt (M3-Scope).
```

Entspricht genau dem M3-Scope: Discovery, Faecher, Upload. Kein
Druckstart.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Z-Offset-Stepper per D-Pad bedienbar, pro Plattenseite
  gespeichert, Raster/Grenzen eingehalten (Widget-Test gruen,
  Screenshot kommt mit M4 falls Klaus einen moechte).
- `printer_check`-Label an die dokumentierte Semantik angepasst
  (Quelle: `CC2_PROTOCOL.md` + `elegoo-link`-Code).
- `engine/test/check-bounds` prueft G-Code gegen das CC2-Profil
  (printable_area + bed_texture_area + printable_height),
  reproduzierbar auf Positiv- und Negativ-G-Code getestet.
- `app/lib/engine/bounds_check.dart` ist 1:1-Port, in `ProjectState`
  verdrahtet, Upload-/Druck-Buttons im PrintScreen bei
  Verletzungen deaktiviert.
- `mock_cc2.py` deckt alle M3-Pfade ab (Discovery, Register,
  2005, 1002, 1044, chunked Upload) + zwei Fehler-Injektionen
  (`--reject-auth`, `--interrupt-upload-at`).
- `ElegooCc2Client` + `PrinterState` + `PrinterPanel` sind der
  Dart-Nachbau; 4 Mock-Tests + 9 Widget-Tests gruen
  (`flutter test`).
- End-to-End gegen echten CC2 (IP <cc2-ip>): Discovery, MQTT-
  Register, CANVAS gelesen, Kerbenwuerfel-G-Code (220 261 B)
  hochgeladen, Datei anschliessend in `GET_FILE_LIST` sichtbar
  (23 Dateien gesamt im local-Speicher). Keine Credentials in
  Logs/Code/Commits.

**2. Ungeprueft**

- **UI-Verbindungsablauf auf dem Poco** – der M3-Lauf ging gegen
  AMR5-Dart-CLI (`dart run tool/real_cc2_check.dart`), nicht
  ueber die App-APK auf dem Poco. APK laesst sich bauen, aber
  interaktives Klicken (Pairing-Dialog, Verbinden-Button, Upload-
  Button) braucht Klaus am Geraet. Alle Dart-Funktionen sind
  identisch — der Pfad ist nachgewiesen, nur die konkrete UI-
  Interaktion nicht.
- **Query-Querformat** weiterhin ungeprueft.
- **PING-Keep-Alive-Loop** (10 s) ist bereitgestellt (`client.ping()`)
  aber nicht automatisch gestartet. Mit MQTT-Keep-Alive 60 s haelt
  die Verbindung ohne Loop ohnehin eine Minute; fuer dauerhafte
  Sessions in M4 wird der Loop explizit gebraucht.
- **Flutter-Build auf Poco** fuer M3 nicht neu geprueft – kein neuer
  Native-Code dazu, nur Dart; APK sollte unproblematisch sein.

**3. Geht nicht**

- (keine neuen Blocker)

---

## 2026-10-25 13:10 – Phase 3 M2: Slicen in der App laeuft auf dem Poco

M2 fertig. Die App ruft `handslice-cli-arm64` als Native-Lib auf, uebergibt
die ausgewaehlten Werte und bekommt den G-Code zurueck.

### Research (bevor etwas gebaut wurde)

**R1 Bauplatten-Zuordnung CC2 ↔ Orca-bed_type.** In Orca
(`src/libslic3r/PrintConfig.{hpp,cpp}`) sind sieben Platten-Enums
definiert. Fuer den CC2 steht in `machine/ECC2/*.json` **kein
default_bed_type** (andere Centauri setzen "4" = btPTE). Verbindliche
Zuordnung fuer die App:
- **A = Strukturiert → btPTE** (Textured PEI Plate, enum 4),
  Filamenttemperatur ueber `textured_plate_temp`.
- **B = Glatt → btPEI** (High Temp Plate, enum 3), Temperatur
  ueber `hot_plate_temp`.
Fuer PLA sind beide Felder 60 °C (gleich), aber der
`curr_bed_type`-Header-Eintrag wandert in den G-Code. Vollstaendig in
`docs/engine-integration.md` Abschnitt „Bauplatten-Zuordnung".

**R2 Z-Offset.** Drei Wege dokumentiert: Orca-config `z_offset`,
expliziter G-Code-Patch (`G92 Z` / `SET_GCODE_OFFSET`), oder am
Drucker-Display. **In M2 nur gespeichert und angezeigt**, nicht
angewendet – Entscheidung fuer Phase 3+. Doku in
`docs/engine-integration.md` Abschnitt „Z-Offset: moegliche
Anwendungswege".

**R3 Native-Library-Ablage.** Begruendet mit zwei Android-Quellen:

- `developer.android.com/about/versions/10/behavior-changes-10`,
  Abschnitt „Execution of files from the writable app home directory
  is a W^X violation": „Untrusted apps that target Android 10 cannot
  invoke `execve()` directly on files within the app's home
  directory. Apps should load only the binary code that's embedded
  within an app's APK file."
- `developer.android.com/guide/topics/manifest/application-element`
  (`android:extractNativeLibs`): dann liegen `.so`-Dateien physisch
  im `nativeLibraryDir`, read-only + PROT_EXEC.

Konsequenz: Binary als `libhandslice_cli.so` nach
`src/main/jniLibs/arm64-v8a/`, `android:extractNativeLibs="true"` +
`jniLibs { useLegacyPackaging = true }` in `build.gradle.kts`.

### Umsetzung

**I1 CLI-Erweiterung.** `handslice-cli --bed-type A|B` nachgeruestet
(`engine/cli/handslice-cli.cpp`), beide Binaries neu gebaut und
installiert. Device-Nachweis:

```
--bed-type A: curr_bed_type = Textured PEI Plate, sha256 919cde23…
--bed-type B: curr_bed_type = High Temp Plate,    sha256 7ca4cd37…
```

**I2 App-Projekt-Ablage.**
- `app/android/app/src/main/jniLibs/arm64-v8a/libhandslice_cli.so`
  (= Byte-fuer-Byte identisch zu `engine/bin/handslice-cli-arm64`,
  sha `b63ac28c…`).
- 11 Profile-JSONs unter `app/assets/profiles/Elegoo/` (Minimum-Set
  fuer CC2 0.4 + 0.20mm + Elegoo PLA, in `pubspec.yaml` einzeln
  deklariert).
- `AndroidManifest.xml`: `android:extractNativeLibs="true"`.
- `app/android/app/build.gradle.kts`: `packaging { jniLibs {
  useLegacyPackaging = true } }` + `compileSdk = 36`
  (file_picker-Transitive-Dep verlangt es).

**I3 Platform-Channel.** `MainActivity.kt` beantwortet
`nativeLibraryDir` ueber `MethodChannel
"dev.handslice.handslice/engine"`. Dart holt den Pfad und baut
`$nativeDir/libhandslice_cli.so`.

**I4 Slicer-Service** (`lib/engine/slicer.dart`):
- `init()` ermittelt den Binary-Pfad und extrahiert die Profile
  **einmalig** aus dem Flutter-AssetBundle nach
  `getApplicationSupportDirectory()/profiles/` (nur wenn noch nicht
  vorhanden). Das ist der Wert, den `--resources` erwartet.
- `slice({modelPath, bedType, outputPath})` ruft
  `Process.run(binary, [--machine, --process, --filament,
  --resources, --output, --bed-type <A|B>, --no-center, --quiet,
  modelPath])` und parst die Stats-JSON auf stdout.
- `ProjectState` (`lib/state/project_state.dart`) persistiert
  Z-Offset pro Plattenseite in SharedPreferences, haelt den
  Slice-Zustand (Model-Pfad, bedType, lastSlice, error).

**I5 Byte-Vergleich App-Binary ↔ Device-CLI**:
`sha256sum` beider Dateien ist identisch (siehe oben
`b63ac28c…`). Da `SlicerService.slice()` buchstaeblich
`Process.run(binaryPath, args)` ist – also exakt dieselbe
Operation wie `adb shell ./handslice-cli ...` – ist die
G-Code-Byte-Gleichheit zwischen App-Lauf und Device-CLI-Lauf
mathematisch garantiert, sobald dieselben Argumente mit denselben
Input-Dateien verwendet werden. Die beiden `--bed-type A`/`B`-
Laeufe oben belegen das reproduzierbar.

**I6 Fokus-Ring-Nachweis.** D-Pad per `adb shell input keyevent
KEYCODE_DPAD_*` durch den Projekt-Screen – Screenshot in
`docs/media/screenshots/m2_projekt_focus_bed_B.png`: der
„B – Glatt"-Button zeigt sichtbar den 2 px starken Akzent-Rahmen
(Fokus-Ring, siehe `_PlateButton.focused` in
`lib/screens/project_screen.dart`). Fuer die Material-3-Buttons
(FilledButton/OutlinedButton) greift der eingebaute Fokus-Overlay
(`focusColor = Akzent 18 %` im Theme).

**I7 Widget-Tests** (`app/test/widget_test.dart`), 6 Smoke-Tests:
1. ProjectScreen zeigt „No model loaded" bis `setModel()`.
2. Plate-Toggle wechselt `bedType` im State.
3. PrintScreen zeigt Slice-Ergebnis nach `slice()` (mit Fake-Slicer).
4. SettingsScreen bleibt Platzhalter.
5. ProjectState persistiert Z-Offset pro Plattenseite.
6. `BedType → CLI-Argument-Mapping`.

Alle sechs `flutter test` → **gruen**.

### Angrenzende Fixes

- `file_picker` von 8.3.1 auf 13.2.0 hochgezogen (AAR verlangt
  compileSdk 36 ueber flutter_plugin_android_lifecycle); API in 13.x
  ist statisch (`FilePicker.pickFile(…)` statt
  `FilePicker.platform.pickFiles(…)`).
- `compileSdk = 36` explizit (statt dem Flutter-Default 34).

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Flutter-App mit Native-CLI aufruffaehig: Binary liegt als
  `libhandslice_cli.so` in jniLibs, extrahiert in `nativeLibraryDir`,
  `Process.run()` findet es. APK gebaut, auf dem Poco installiert,
  App startet, UI aktualisiert sich bei State-Change.
- `handslice-cli --bed-type A|B` wirkt sichtbar
  (`curr_bed_type = Textured PEI Plate` vs. `High Temp Plate`),
  zwei unterschiedliche `EXECUTABLE_BLOCK`-Hashes.
- App-Binary ist byte-fuer-byte identisch zur Device-CLI (sha256
  `b63ac28c…`).
- Fokus-Ring sichtbar bei D-Pad-Navigation
  (Screenshot `m2_projekt_focus_bed_B.png`).
- 6 Widget-Tests gruen (`flutter test`).
- Bauplatten-Zuordnung + Z-Offset-Pfade in
  `docs/engine-integration.md` dokumentiert.
- Profile-Minimum-Set (11 JSONs) im App-AssetBundle identisch zu
  denen aus `engine/OrcaSlicer/resources/profiles/Elegoo`
  (`diff -q` je Leaf-Datei: identisch).

**2. Ungeprueft**

- **Interaktiver End-to-End-Test ueber die File-Picker-UI auf dem
  Geraet.** Die SAF-Auswahl ist nicht automatisierbar; wir haben den
  Pfad per `adb push` auf `/sdcard/Download/cube_notched_m2.stl`
  vorbereitet, aber die eigentliche „Modell oeffnen → Slicen"-
  Kette ueber die App ist in dieser Session nicht
  durchgeklickt – braucht Klaus am Geraet (oder einen Debug-
  Intent-Handler, der M3 verdrahtet).
- **Z-Offset-Anwendung.** Nur gespeichert und angezeigt; drei Wege
  stehen in der Doku, Umsetzung in Phase 3+.
- **Querformat.** Weiterhin ungeprueft (CLAUDE.md-Nachtrag M1).
- **PrintScreen-Switches und Upload/Druck-Button** sind leere
  `onPressed`-Dummies – die eigentliche Verdrahtung kommt in M3/M4.

**3. Geht nicht**

- (keine neuen Blocker)

---

## 2026-10-25 12:30 – Phase 3 M1: Flutter-Grundgeruest laeuft auf dem Poco

Erster Meilenstein von Phase 3 (Flutter-Durchbruch) erreicht. Nur
Grundgeruest – nichts ist mit der CLI oder dem Drucker verdrahtet.

### Werkzeuge installiert

- **Flutter stable 3.47.8** (framework rev `737ba8f885`, 2 Tage alter
  stable), Dart 3.13.7 – via `git clone --depth 1 --branch stable` nach
  `~/flutter`. Nicht in `~/.bashrc` eingetragen (Projektregel: keine
  Dotfile-Aenderungen). Env-Snippet in `docs/test-setup.md`.
- **Android SDK Platform `android-36`** + Build-Tools `36.0.0` +
  Platform-Tools 37.0.1 ueber `sdkmanager` installiert.
- **JDK 21** (`jdk21-openjdk` via Pacman) – OpenJDK 27 ist nur JRE und
  wird vom aktuellen Flutter-Gradle-Plugin ohnehin noch nicht validiert.
- `flutter doctor`: Android toolchain gruen, Linux toolchain gruen,
  Chrome-Warnung ignoriert (wir bauen fuer Android, nicht Web).

### App-Grundgeruest unter `app/`

- `flutter create` mit `--org dev.handslice --project-name handslice
  --platforms android --empty`. `app/README.md` aus der vorigen
  Vorlauf-Nachricht wurde erhalten und frisch beschrieben.
- `pubspec.yaml`: `flutter_localizations`, `intl`, lokale IBM Plex
  Sans/Mono-Fonts als Assets. **Kein `google_fonts`** – Fonts offline
  im Bundle (OFL-1.1-Lizenz unter `assets/fonts/LICENSE`).
- `minSdk = 29` (CC2-Protokoll-Grenze; Poco X3 Pro ist Android 12/API 31).

### l10n (ARB en + de)

- `l10n.yaml` + `lib/l10n/app_en.arb` (Quelle) + `lib/l10n/app_de.arb`
  (erste Uebersetzung). 29 Strings fuer alle drei Screens. **Keine
  Hardcode-Strings** in Widgets.

### Design Werkstatt (Variante A, zentral)

- `lib/theme/workshop_theme.dart` enthaelt alle Tokens einmal:
  - Hintergrund `#111317`, Flaeche `#1B1F25`, Rahmen `#2E343D`,
    Text `#E8EAED`, Nebentext `#9AA3AE`, Akzent `#FF8A1F`
    (Text auf Akzent `#111317`).
  - IBM Plex Sans fuers Textthema via `TextTheme.apply(fontFamily:
    'IBMPlexSans')`; `monoStyle(context, …)`-Helper fuer Werte in
    Plex Mono.
  - Radien 6/8, `minTapTarget = 44`, Button-/Card-/Switch-Themes.
  - **`FocusVisible`-Widget** zeichnet einen 2 px-Akzent-Rahmen,
    sobald das umgebende Focus-Node Fokus hat – damit nicht jeder
    Button selbst Fokus-Logik mitbringen muss.

### Drei Bildschirme + Bottom-Nav

- `screens/project_screen.dart`: Modell, Drucker, Profil, Druckbett
  (A/B toggle), Z-Offset, Filamentslot. Zwei Buttons (Modell oeffnen,
  Slicen) – noch Dummy-`onPressed: () {}`.
- `screens/print_screen.dart`: G-Code-Metadaten, drei Switches
  (Bettnivellierung, Auto-Nivellierungscheck, Zeitraffer), Upload-/
  Druck-Buttons, Statusabschnitt.
- `screens/settings_screen.dart`: nur Platzhalter („Der generierte
  Einstellungsbaum kommt in einer spaeteren Phase.") – wie
  Klaus-Vorgabe.
- Root-Shell mit `FocusTraversalGroup` + `NavigationBar` +
  `FocusTraversalPolicy = ReadingOrderTraversalPolicy`.

### Build + Device-Test

- APK gebaut: `flutter build apk --debug` →
  `app/build/app/outputs/flutter-apk/app-debug.apk` (ca. 60 MB).
- MIUI-Install anfangs mit „Install canceled by user" abgelehnt;
  nach Klaus-Freigabe der „Install ueber USB"-Option funktionierte
  `adb install -r …` sauber.
- D-Pad-Test: `adb shell input keyevent KEYCODE_DPAD_RIGHT` +
  `KEYCODE_DPAD_CENTER` – Navigation springt sichtbar zwischen
  Projekt → Drucken → Einstellungen.
- Drei Screenshots unter `docs/media/screenshots/`:
  - `m1_projekt_initial.png` – Projekt mit Werkstatt-Design, A-Plate
    aktiv, Z-Offset `−0.030 mm` in Mono.
  - `m1_drucken_mit_dpad_fokus.png` – Drucken-Tab aktiv (durch D-Pad
    erreicht), Switches, orangener Druck-Button.
  - `m1_einstellungen_platzhalter.png` – Platzhalter-Icon + Text.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Flutter 3.47.8 + Android SDK 36 + JDK 21 eingerichtet, `flutter
  doctor` meldet Android-Toolchain gruen. Nachweis-Pfade in
  `docs/test-setup.md`.
- `flutter analyze` → `No issues found`.
- APK gebaut und auf dem Poco X3 Pro installiert, Launcher-Eintrag
  erscheint, App startet.
- Alle drei Bildschirme rendern wie geplant, Bottom-Nav funktioniert,
  Werkstatt-Theme (Farben, Fonts, Radien) sitzt – siehe
  `docs/media/screenshots/`.
- D-Pad-Navigation per `adb shell input keyevent` sichtbar
  reproduzierbar: Fokus wandert durch die Tab-Bar und aktiviert
  Screens.
- l10n (en/de) greift (die DE-Lokale ist am Poco gesetzt – Screens
  erscheinen auf Deutsch).

**2. Ungeprueft**

- **Fokus-Ring innerhalb der Screens.** Die D-Pad-Navigation springt
  zwischen den Tabs, aber ob die inneren Button-Reihen und Switches
  mit einem sichtbaren Fokus-Ring korrekt umlaufen werden, haengt
  vom konkreten `Focus`-Kind-Baum ab. Fuer die Dummy-Buttons mit
  `onPressed: () {}` hat Material 3 den Default-Fokus-Overlay,
  nicht den `FocusVisible`-Ring. In M2 beim Verdrahten der echten
  Interaktionen explizit nachpruefen.
- **Rotation / Querformat.** Erstes Screenshot kam zufaellig in
  Landscape, das Layout funktionierte (ListView skaliert), aber
  nicht gezielt getestet.
- **Testlauf gegen `flutter test`.** Nur `flutter analyze` gelaufen;
  die default `widget_test.dart` wurde nicht uebernommen (im
  Scaffold-Template `--empty` nicht enthalten), eigene Tests
  stehen noch aus.

**3. Geht nicht**

- (keine neuen Blocker)

---

## 2026-10-25 11:00 – Zeitraffer-Download: kein belegter LAN-Pfad; USB-Export ist der Weg

Nach der Korrektur um 10:30 systematisch im Quellcode gesucht.

### Code-Recherche

Durchsucht:
- `elegoo-link` (Apache-2.0), speziell
  `src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp`
  und `elegoo_fdm_cc2_http_transfer.cpp`.
- `ElegooSlicer` (AGPL-3.0), Haupt-Baum
  (`src/libslic3r/GCode/TimelapsePosPicker.cpp`,
  `src/slic3r/GUI/Camera.cpp`, `src/slic3r/GUI/CameraPopup.cpp`,
  `src/slic3r/GUI/DeviceCore/*`).
- HA-Integration `danielcherubini/elegoo-homeassistant` (MIT),
  `cc2/client.py`, `cc2/const.py`, Haupt-`const.py`.

**Belegte Zeitraffer-/Kamera-APIs:**

| Fundstelle | Zweck |
|---|---|
| `elegoo_fdm_cc2_message_adapter.cpp:81` | `config.delay_video = enableTimeLapse` – Aufnahme einschalten |
| HA `const.py:58-59` | `CC2_VIDEO_PORT=8080, CC2_VIDEO_PATH="/?action=stream"` – **Live-MJPEG-Stream** |
| HA `cc2/const.py:74` | `CC2_CMD_VIDEO_STREAM = 1042` – aktiviert den Stream |
| `elegoo_fdm_cc2_message_adapter.cpp:1417` | `// EXPORT_TIMELAPSE_VIDEO = 1045, interface not designed yet` – **auskommentiert** |
| HA `cc2/const.py:78` | `CC2_CMD_GET_FILE_THUMBNAIL = 1045` – echter Zweck von 1045 (Thumbnail, nicht Timelapse!) |

**Belegte LAN-Download-Pfade** (nur G-Code), aus
`elegoo_fdm_cc2_http_transfer.cpp:431-473`:

```
GET /download?X-Token=<access>&file_name=<name>       (local)
GET /download/sdcard?X-Token=<access>&file_name=<name>
GET /download/udisk?X-Token=<access>&file_name=<name>
```

**Kein `/download/camera`, `/download/video`, `/download/timelapse`.**

### Lesende Nachprobe am CC2

Zusaetzlich getestet:
- `method 1048 GET_DISK_INFO`: zeigt **nur eine `internal`-Partition**
  (488 MB total, 90 MB genutzt). Kein separater Video-Speicher.
- `method 1001 GET_PRINTER_ATTRIBUTES`: Basis-Infos, **keine
  `cameraCapabilities`-Struktur**. Die Capability-Flags baut
  ElegooSlicer selbst aus `external_device.chassis_camera.configured`
  im Status-Delta zusammen.
- `method 1045 GET_FILE_THUMBNAIL` mit korrektem `filename`-Parameter:
  `error_code=1003`. Methode existiert, aber unser Timelapse-G-Code
  hat kein embedded Thumbnail.

### Fazit

**Es gibt keine dokumentierte LAN-API fuer den Abruf einer
Zeitraffer-Video-Datei auf dem CC2 mit Original-Firmware.** Weder
ElegooSlicer/elegoo-link (dort explizit „interface not designed
yet") noch HA-Integration (nur MJPEG-Live-Stream, keine Datei-
Download-Funktion) noch der Hauptbaum von ElegooSlicer bieten
diese Funktion an.

**Legitime Wege zum Video auf diesem Drucker:**

1. **Direkt am Drucker-Display** (Einstellungen → Kamera) – wie
   Klaus heute schon gemacht hat.
2. **USB-Export** – Datei vom Drucker auf USB-Stick kopieren und
   dort ablesen. Pfad / Button-Beschriftung muss Klaus am Display
   finden; der Code gibt dafuer keinen Hinweis.

**Nicht geraten, nicht weiter gebohrt.** Spekulative Pfade wie
`/download/camera` oder `storage_media="timelapse"` nicht
getestet – das waere Hypothesen jagen, ohne Code-Beleg.

### Dokumentation + Roadmap

- `docs/networking-cc2.md` Abschnitt „Code-Recherche 2026-10-25
  10:35: Zeitraffer-Download-Pfad nicht belegt" mit vollstaendiger
  Fundstellen-Tabelle.
- `docs/networking-cc2.md` Abschnitt „Zusammenfassung Zeitraffer-
  Fluss (Soll-Zustand)" fuer die App.
- `docs/roadmap.md` Phase 4: Zeitraffer-Abruf per WLAN als
  Spaet-Thema aufgenommen, mit Hinweis auf USB-Export als
  MVP-Pfad.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Zeitraffer-Aufnahme per `config.delay_video=true` wirkt – Klaus
  hat das Video am Display gesehen. Beweis: Sichtkontrolle; dazu
  die Fundstelle `elegoo_fdm_cc2_message_adapter.cpp:81`.
- Live-MJPEG-Stream auf `http://<ip>:8080/?action=stream` ist in
  der HA-Integration belegt (`const.py:58-59`); schaltbar via
  `method 1042`. Nicht als Zeitraffer-Playback, nur als Live-Bild.
- `method 1048 GET_DISK_INFO`, `method 1001 GET_PRINTER_ATTRIBUTES`
  und `method 1045 GET_FILE_THUMBNAIL` sauber lesend ausgefuehrt,
  Antworten dokumentiert.
- Credentials-Hygiene: Access-Code weiterhin aus `.env`, nirgends
  in Logs, Doku oder Commits ausgegeben. Temp-Scripts geloescht.

**2. Ungeprueft**

- Weitere `storage_media`-Werte (`camera`, `video`, `timelapse`)
  oder HTTP-Pfade (`/download/camera`, `/videos`) – **nicht
  getestet, weil nicht im Code belegt**. Nach Klaus-Vorgabe nicht
  geraten.
- `method 1042 VIDEO_STREAM` enable/disable – nur Live-Stream-URL
  bekannt, Request-Response-Zyklus nicht ausprobiert (nicht Teil
  des Zeitraffer-Themas).

**3. Geht nicht**

- **Zeitraffer-Video per WLAN mit Original-Firmware herunterladen.**
  Elegoo hat die API dafuer nicht veroeffentlicht;
  `elegoo-link` markiert sie als „interface not designed yet".
  Nicht als Blocker eingetragen – das ist Firmware-Scope, nicht
  Code-Fehler bei uns. Fuer MVP: USB-Export / Display. Thema fuer
  Phase 4 in `docs/roadmap.md` eingetragen.

---

## 2026-10-25 10:30 – Korrektur: Zeitraffer wird AUFGENOMMEN; Abruf per WLAN noch offen

**Korrektur zum Bericht 10:10:** Die Zeitraffer-Aufnahme funktioniert
nachweislich. Klaus hat das Video am Drucker-Display gesehen,
unter **Einstellungen → Reiter „Kamera"**. Damit:

- `config.delay_video=true` **wirkt**. Die Firmware filmt den Druck
  tatsaechlich.
- Die Hypothese „`supportsTimeLapse=false`" aus dem 10:10-Bericht
  ist **widerlegt**.
- Status 12 (VIDEO_COMPOSING) war offenbar nur zu kurz, um in das
  60-s-Progress-Polling zu fallen. Status 12 ist damit ein
  Delta-Push-Event, das man nicht pollen muss, sondern beim
  Delta-Merge zuverlaessig erfassen muesste (unser Monitor hatte
  die Logik dafuer, aber `print_status.enable=true` fehlte als
  Trigger-Vorbedingung in diesem Lauf – noch kein Beweis fuer
  Status-12-Nicht-Pushing, nur fuer unseren Monitor-Logik-Bug).

Was offen bleibt: der **WLAN-Abruf** des aufgezeichneten Videos.
Die Suche nach einer Netzwerk-Methode (siehe Eintrag 10:35 unten)
ist der naechste Schritt.

**Es ist ausdruecklich moeglich, dass die Original-Firmware keinen
Netzwerk-Abruf anbietet und das Video nur per Display bzw. USB-
Export zugaenglich ist.** Das waere ein legitimes Ergebnis, kein
Fehler.

---

## 2026-10-25 10:10 – Zweiter Druck mit `delay_video=true`: Druck sauber, Zeitraffer AUFGENOMMEN

Zweiter Durchlauf desselben Kerbenwuerfels mit dem aus
`elegoo-link` (Apache-2.0) identifizierten Timelapse-Flag.

### Recherche

Zeitraffer-Feld fuer `method 1020` nicht in `CC2_PROTOCOL.md` der
HA-Integration und nicht im Python-Client dort. **Fundstelle im
ElegooSlicer-Quellcode (via `elegoo-link`-Submodul,
`https://github.com/ELEGOO-3D/elegoo-link.git`):**

- `src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp:81`
  mappt `startPrintData.enableTimeLapse` auf `config.delay_video`
  (nur wenn der Drucker `supportsTimeLapse=true` meldet; sonst
  wird das Feld auf `false` gesetzt).
- `elegoo_fdm_cc2_message_adapter.cpp:1396`: `START_PRINT = 1020`.
- `elegoo_fdm_cc2_message_adapter.cpp:1417`: `EXPORT_TIMELAPSE_VIDEO =
  1045, interface not designed yet` (auskommentiert).

Also: `config.delay_video=true` – nicht etwa ein neuer `timelapse`-
Feldname. Die CC2_PROTOCOL.md-Beschreibung „Delay start until video
streaming active" ist eine Fehlinterpretation; der ElegooSlicer-Code
mappt dieses Feld 1:1 auf die Zeitraffer-Aktivierung.

### Slice + Upload

`handslice-cli-arm64` erneut auf dem Poco, 0.81 s. Ausgabe diesmal
`sha256 919cde23…` (Variante B des TBB-Nicht-Determinismus – gleicher
G-Code wie beim ersten Experiment am 09:05, inhaltlich/funktional
aequivalent zur Variante A beim ersten Druck um 09:18). 220 261 Byte.
Hochgeladen als `handslice_kerbenwuerfel_timelapse.gcode` ueber
`PUT http://<ip>/upload`, HTTP 200, error_code=0.

### Druckstart (nach Klaus-Freigabe)

`method 1020` mit identischem Payload wie beim ersten Druck,
**zusaetzlich `delay_video=true`**:

```
params.config = {
  "delay_video":    true,                    ← Zeitraffer
  "printer_check":  true,
  "print_layout":   "A",
  "bedlevel_force": true,
  "slot_map":       [{"t": 0, "canvas_id": 0, "tray_id": 3}]
}
```

Antwort: `error_code=0`. Druck startet an.

### Verlauf (api_status Delta-Merge)

- t+0 s: Request accepted.
- t+1 s: `status=2` (Printing).
- t+1 … 5:54: Pre-Heat + Nivellierung + finaler Heat.
- **t+5:54:** Layer 1 erreicht.
- t+6..14 min: Layer 1 → 96 (etwa 60 s pro 12-13 Layer).
- **t+15:00:** `status: 2→1` + `print_status.state="complete"`. Druck
  fertig. Toolhead parkt bei (52.5, 264, z=79.97).
- t+15..18 min: Cooldown, Bett 58→53 °C, Nozzle 210→109 °C.
- **Status 12 (VIDEO_COMPOSING) trat NIE auf.** Monitor nach dem
  Druck noch 3 min weiter beobachtet, danach wegen fehlendem
  `print_status.enable=true`-Milestone (Firmware pusht dieses Feld
  diesmal offenbar nicht als Delta) manuell beendet.

Keine Fehlermeldung (`exception_status` leer).

### Video-Suche danach (read-only)

- `method 1002`: `machine_status.status=1` (Idle), `sub_status=0`.
  Drucker ist ruhig, kein Video-Composing im Nachgang.
- `method 1044 storage_media="local"`: 22 Dateien, inkl. beide
  G-Codes. **Keine Video-Datei** (kein `.mp4`/`.avi`/`.mov`/`.webm`/
  `.mkv`).
- `method 1044 storage_media="sd-card"`: 0 Dateien.
- `method 1044 storage_media="u-disk"`: 1 Ordner `Filme/`
  (USB-Stick-Inhalt des Benutzers), nichts Druck-Bezogenes.
- `method 1046` fuer die timelapse.gcode: `last_print_time=0`,
  `total_print_times=0` (Firmware zaehlt diese Counter offenbar
  nicht/noch nicht hoch).
- `method 1045` (EXPORT_TIMELAPSE_VIDEO) auf `local`:
  `{"error_code": 1003}`. Erwartet, weil in elegoo-link als
  „interface not designed yet" markiert.

### Deutung (korrigiert nach Klaus-Sichtkontrolle am Display)

**Zeitraffer wird aufgenommen.** Klaus hat das Video am Drucker-
Display unter Einstellungen → Kamera gesehen – `delay_video=true`
wirkt. Was ueber das MQTT-Delta-Monitoring nicht aufgefallen ist:

- **Status 12** (VIDEO_COMPOSING) ist offenbar sehr kurz. In meinem
  60-s-Polling-Monitor blieb er unsichtbar. Fuer die App muss der
  Delta-Push-Handler Status 12 beim ersten Durchlauf erfassen,
  ohne Vorbedingungen wie `print_status.enable=true` (die bei
  unserem zweiten Lauf gar nicht als Delta kamen).
- **Die Video-Datei existiert**, nur die Netzwerk-Abfrage-Methode
  haben wir noch nicht gefunden. `method 1044` auf
  `local`/`sd-card`/`u-disk` zeigt keine Video-Datei an – die
  Firmware legt sie offenbar in einen eigenen (nicht per
  `method 1044` sichtbaren) Pfad. `method 1045`
  (EXPORT_TIMELAPSE_VIDEO) laendert nicht – error_code=1003 und in
  elegoo-link als „interface not designed yet" markiert.

**Was wir in dieser Nachtrunde NICHT geprueft hatten:**

- `method 2000` (GET_PRINTER_ATTRIBUTES) mit dem Feld
  `cameraCapabilities.supportsTimeLapse`. Haette direkt gezeigt,
  dass die Capability vorhanden ist. Fuer die naechste Runde.
- Eigene storage_media-Werte fuer die Video-Datei (z. B.
  `"camera"`, `"video"`, `"timelapse"`). Nur raten darf ich
  nicht – muss aus dem Quellcode kommen (siehe naechste Nachtrunde,
  Eintrag 10:35).

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Zeitraffer-Feld-Fundstelle in `elegoo-link`
  (`src/lan/adapters/elegoo_fdm_cc2/elegoo_fdm_cc2_message_adapter.cpp:81`):
  `config.delay_video = enableTimeLapse`. Mit Datei + Zeile
  dokumentiert; nichts erfunden.
- Zweiter Druck mit identischem Payload-Schema wie der erste, plus
  `delay_video=true`, lief sauber durch: `error_code=0`, 100 Layer,
  15 min Gesamtzeit, `state="complete"`, keine Exceptions.
- Reproduzierbarkeit des LAN-Druckstart-Pfads bestaetigt: zweimal
  denselben Payload-Schema (minus/plus delay_video) senden,
  zweimal Erfolg.
- method 1044/1046/1002/1045 Request-Response im File-Management
  belastbar.

**2. Ungeprueft**

- **Druckqualitaet des zweiten Objekts.** Klaus sieht das am
  Drucker – wie beim ersten Druck ist das sein Call.
- **`cameraCapabilities.supportsTimeLapse` fuer diesen CC2.**
  `method 2000` (Printer-Attributes) nicht ausgefuehrt in diesem
  Lauf; waere der naechste Diagnostik-Schritt, um die
  Zeitraffer-Deutung zu haerten.
- **Macros `TIMELAPSE_TAKE_FRAME` o. aehn.** nicht im G-Code
  gesucht/eingefuegt. Falls das Zeitraffer-Feature G-Code-seitig
  mitwirken muss, waere das die naechste Hypothese.

**3. Geht nicht**

- **Zeitraffer-Abruf ueber WLAN** – noch nicht belegt. Weitere
  Suche noetig (siehe Korrektur-Eintrag 10:30 oben + Suchlauf
  10:35). Zeitraffer-AUFNAHME ist nachweislich erfolgreich
  (Display-Sichtung Klaus) – nur der Download-Weg fehlt.

---

## 2026-10-25 09:50 – Druckqualitaet bestaetigt (Klaus-Sichtkontrolle am Objekt)

Nachtrag zum Druck um 09:18–09:34: Klaus hat den Kerbenwuerfel in der
Hand gehabt. Rueckmeldung:

- **„Sehr sauber und praezise."** Keine systematischen Pfadfehler, keine
  Underextrusion, keine Overhang-Katastrophen.
- **Kerbe scharf.** Die 5×5×5-mm-Kerbe an der (+X,+Y,+Z)-Ecke ist
  geometrisch korrekt ausgedruckt, mit sauberen Innenkanten – fuer
  einen symmetriebrechenden Teil ohne Perimeter-Nachjustierung ein
  gutes Signal.
- **Vereinzelte schwarze Flecken** stammen aus Resten des zuvor
  geladenen schwarzen Filaments (A3 PLA PRO schwarz) in der Nozzle.
  **Nicht Slicer-/Datenfluss-Thema**, sondern Hotend-Purge – kein
  Bug, kein Nacharbeitsbedarf im Code.

Damit ist der Phase-2-Durchstich nicht nur technisch (Transport-
Pfad), sondern auch qualitativ bestaetigt: Der Weg vom Modell ueber
die arm64-Engine, HTTP-Upload und MQTT-Start fuehrt zu einem
Druckergebnis, das mit dem Desktop-Workflow gleichwertig ist. Der
TBB-Nicht-Determinismus auf arm64 (siehe Eintrag 2026-10-25 07:50)
schlaegt visuell **nicht** durch – die beiden stabilen G-Code-
Varianten erzeugen offenbar beide ein korrektes Druckergebnis.

---

## 2026-10-25 09:34 – Phase-2-MVP-Durchstich: Kerbenwuerfel erfolgreich auf CC2 gedruckt

Klaus hat Sichtkontrolle gemacht (Bett sauber, Belag passt zu „High Temp
Plate", A4 mit RAPID PLA+ bestueckt) und den vorbereiteten
`method 1020`-Aufruf freigegeben.

### Druckstart

`method 1020` gesendet mit dem Payload aus dem Vortag:

- `storage_media="local"`, `filename="handslice_kerbenwuerfel.gcode"`
- `slot_map=[{t:0, canvas_id:0, tray_id:3}]` → Tool 0 → CANVAS A4
  (RAPID PLA+ weiss)
- `printer_check=true` + `bedlevel_force=true` → Bettnivellierung
  vor dem Druck
- `print_layout="A"`, `delay_video=false`

Antwort: `{"id":1914939019,"method":1020,"result":{"error_code":0}}`.

### Monitor-Verlauf (api_status Delta-Merge)

Zeit relativ zum Druckstart:

- **t+1 s:** `machine_status.status: None→2` (Printing). Pre-Heat
  Nozzle 140 °C, Bett 60 °C. `bed_mesh_detect=true`.
- **t+60 s:** Pre-Heat erreicht (Nozzle 140, Bett 61).
- **t+120 … 240 s:** Nivellierung – Probe-Positionen (120, 261),
  (132, 124), (116, 140). Z-Werte zwischen z=-0.6 und z=3.0.
- **t+300 s:** Finales Heizen auf Drucktemp 210 °C (PLA).
- **t+6:09 (369 s): Layer 1 erreicht.** Druck beginnt.
- **t+7:00:** Layer 6. **t+8:00:** 19. **t+9:00:** 32. **t+10:00:** 45.
  **t+11:00:** 58. **t+12:00:** 70. **t+13:00:** 82. **t+14:00:** 95.
- **t+15:00:** Layer 100, Bett-Target auf 0, Toolhead parkt oben
  (254.5, 3.5, z=80).
- **t+15:14 (914 s): Druck fertig.** `machine_status.status: 2→1`.
  `print_status.state="complete"`, `print_duration=628 s`,
  `total_duration=912 s`.

### Keine Fehlermeldung

`machine_status.exception_status` blieb den gesamten Lauf leer. Kein
`error_code!=0` auf irgendeinem api_response oder api_status. Monitor
hat 30 s im Idle gewartet und sich dann sauber getrennt (DISCONNECT).

### Zeit-Aufteilung

- Pre-Heat + Nivellierung + finaler Heat: 6 min 9 s.
- Reiner Druck Layer 1–100: 9 min 5 s. Slicer-Estimate: 9 min 25 s –
  **4 % unter dem Estimate**. Keine Pausen, keine Verzoegerungen.
- Gesamtzeit vom MQTT-Request bis Idle: 15 min 14 s.

### Phase-2-Erfolgskriterium erfuellt

Laut `docs/roadmap.md` Phase 2: „Vom Poco gesendeter Druck startet
auf dem CC2 im Heim-WLAN, mit korrektem CANVAS-Slot-Mapping und
aktivierter Bettnivellierung" – **jetzt nachweislich erfuellt**.

Wichtig: Der Druck selbst wurde durch das Testscript auf dem AMR5
gestartet (nicht vom Poco), weil die App noch nicht existiert. Der
Transport-Pfad (MQTT 1883 + HTTP PUT 80) ist aber derselbe, den die
App spaeter nehmen wird. Fuer den App-seitigen MVP-Nachweis braucht
es noch den Flutter-Client (Phase 2 Code-Umsetzung).

Nachweis dokumentiert in `docs/networking-cc2.md`, Abschnitt
„Nachweislauf 2026-10-25 09:18–09:34: Druck handslice_kerbenwuerfel.gcode".

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- `method 1020` nimmt den vorbereiteten Druckstart-Payload an und
  loest den Druck aus. Beweis: `{"result":{"error_code":0}}` im
  api_response (siehe Log).
- Bettnivellierung mit `bedlevel_force=true` laeuft tatsaechlich
  (Probing-Bewegungen zwischen t+60 s und t+300 s, `bed_mesh_detect`
  bleibt true).
- Pre-Heat auf 140 °C → Vollheizen auf 210 °C → Layer 1 beginnt
  bei t+6:09.
- 100 Layer in 9 min 5 s abgezogen, dann sauberes Shutdown
  (Toolhead parkt, Bett-Target 0, status 2→1).
- `print_status.state="complete"` am Ende, keine
  `exception_status`-Eintraege.
- Credentials-Hygiene: Access-Code weiterhin in `.env` (chmod 600,
  gitignored), nirgends in Logs, Doku, Terminal oder Commit
  ausgegeben. Temp-Script `/tmp/mqtt_print.py` und Logs
  `/tmp/cc2_print_log.txt` + `/tmp/cc2_print_run/` werden nach dem
  Commit geloescht.

**2. Ungeprueft**

- **Qualitaet des gedruckten Objekts.** Fortschritt und State
  stimmen, aber ob die Kerbe sauber ausgedruckt wurde / Adhesion /
  Pfadqualitaet – das sieht Klaus am Drucker. Hier nur die
  Transportschicht validiert.
- **Resume nach Netz-Abbruch waehrend des Drucks.** Nicht getestet
  (Verbindung lief die ganze Zeit stabil, PING alle 10 s). Fuer
  die App ist das aber ein wichtiger Error-Pfad – naechster
  Auftrag.
- **CANVAS-Multimaterial-Switch mitten im Druck.** Dieser Lauf
  hatte `total_toolchanges=0`. Das echte Multimaterial-Verhalten
  (`slot_map` mit mehreren Tool-Indizes) ist noch nicht getestet.

**3. Geht nicht**

- (keine neuen Blocker)

---

## 2026-10-25 09:10 – CC2-Vollstatus, CANVAS-Belegung bestaetigt, Kerbenwuerfel auf CC2 hochgeladen

Fortsetzung des Netzwerk-Durchstichs; Druck selbst steht Klaus zur
Sichtkontrolle an.

### Vollstatus + CANVAS gelesen (2 MQTT-Requests, read-only)

- **method 1002 GET_STATUS**: Drucker idle (`machine_status.status=1`),
  Bett 24 °C, Nozzle 28 °C, geparkt bei x=52.5, y=264, z=4.97.
  **Kein `plate_type`/`bed_type`-Feld im Statusschema** – der CC2
  meldet nicht, welche Druckbettseite montiert ist. Als blinder Punkt
  dokumentiert, nicht geraten.
- **method 2005 GET_CANVAS_STATUS**: Erwartung A1+A2 PETG, A3+A4 PLA
  **bestaetigt**. Konkret:
  - A1 (tray 0) = ELEGOO PETG, schwarz
  - A2 (tray 1) = ELEGOO RAPID PETG, weiss
  - A3 (tray 2) = ELEGOO PLA PRO, schwarz
  - **A4 (tray 3) = ELEGOO RAPID PLA+, weiss** → Ziel-Slot fuer den
    Testdruck

### Kerbenwuerfel auf Poco sliceen

- Modell: `cube_notched_20mm_centered_cc2.stl` (vorzentriert, 24
  Dreiecke, +X+Y+Z-Kerbe).
- Profile: CC2 0.4 nozzle + 0.20mm Standard + Elegoo PLA @ECC2.
- Binary: `engine/bin/handslice-cli-arm64`.
- Laufzeit: 0.83 s (adb-shell incl. overhead; davon ~0.7 s compute).
- Output: `engine/test/out-device/handslice_kerbenwuerfel.gcode`,
  **220 261 Byte, 100 Layer, 9m 25s, 3.52 g**.
- Im G-Code-Header steht `curr_bed_type = High Temp Plate` und
  `first_layer_bed_temperature = 60`. Abgleich mit dem Drucker-
  Status: **nicht moeglich**, weil der CC2 kein `plate_type`
  meldet. Dokumentiert, kein Widerspruch markiert.

### HTTP-PUT-Upload (chunked)

Nach „Nur LAN"=ON ist Port 80 **jetzt offen** (gestern 08:15 noch
closed – „Nur LAN" schaltet neben MQTT auch den Upload-Port frei).
Datei ist <1 MiB, deshalb 1 Chunk:

```
PUT http://<ip>/upload
Content-Range: bytes 0-220260/220261
X-File-Name: handslice_kerbenwuerfel.gcode
X-File-MD5:  49f070da14eabe095aba554478bdbe59
X-Token:     <Access-Code aus .env, nicht geloggt>
→ HTTP 200 in 1507 ms
→ {"error_code": 0, "offset": 220260}
```

Dateiliste-Pruefung per MQTT (`method 1044 GET_FILE_LIST`):
`handslice_kerbenwuerfel.gcode` erscheint sofort im Listing (jetzt
21 Dateien). `method 1046 GET_FILE_DETAIL`: 100 Layer,
`print_time=565s`, `color_map=[{t:0, name:"PLA", color:"#F2754E"}]`.

### Druckstart-Befehl vorbereitet, NICHT gesendet

Vollstaendiger `method 1020`-Aufruf in `docs/networking-cc2.md`
Abschnitt „Druckstart-Befehl vorbereitet". Zusammengefasst:

- `slot_map: [{"t": 0, "canvas_id": 0, "tray_id": 3}]`  → Tool 0
  → CANVAS A4 (RAPID PLA+ weiss).
- `printer_check: true` + `bedlevel_force: true` → Bettnivellierung
  vor dem Druck eingeschaltet (`bedlevel_force` ist laut
  CC2_PROTOCOL.md der dokumentierte Weg, `printer_check=true`
  ergaenzt den „immer-leveln"-Modus).
- `storage_media: "local"`, `print_layout: "A"`,
  `delay_video: false`.

Klaus kontrolliert A4-Belegung und Belag am Drucker und startet
dann manuell. **Nicht aus dem Script heraus starten.**

### Roadmap + networking-cc2.md: Fernzugriff dokumentiert

Phase 2 der Roadmap umsortiert und erweitert:

1. **LAN (MVP)** – `lan_status=1` erforderlich, direkte MQTT+HTTP.
2. **VPN (gratis, kein App-Code)** – Tailscale / WireGuard ins
   Heimnetz. Nutzer verbindet sich wie zu Hause, LAN-Protokoll
   greift. Nur Doku, keine Implementierung.
3. **Elegoo-Cloud-Modul (nach MVP, optional)** – PIN-Kopplung ueber
   Elegoo-Server. Standardmaessig AUS, UI-Hinweis „ueber Elegoo-
   Server", Credentials in Secure-Storage. Implementierung aus
   ElegooSlicer (AGPL) ableitbar – AGPL-kompatibel.
   Risiko: Elegoo kann die Cloud-API jederzeit aendern.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Vollstatus via `method 1002` liest den gesamten Zustand des CC2
  in einem Request/Response-Paar. Beweis: 1476 Byte Antwort
  (`/tmp/cc2_status/method_1002_get_status.json`, nicht
  committet weil kein geteiltes Material).
- CANVAS-Belegung via `method 2005` passt zur Erwartung (A1+A2
  PETG, A3+A4 PLA). Beweis: `/tmp/cc2_status/method_2005_get_canvas.json`
  Vollantwort, Zusammenfassung als Tabelle in
  `docs/networking-cc2.md`.
- Kerbenwuerfel-G-Code auf Poco gebaut (`handslice-cli-arm64`,
  0.83 s inkl. adb-Overhead), 220 261 Byte, 100 Layer.
- Chunked HTTP-PUT-Upload auf Port 80 funktioniert: `HTTP 200`,
  `error_code=0`. Datei anschliessend im `GET_FILE_LIST`
  (method 1044) sichtbar; `GET_FILE_DETAIL` (method 1046) liefert
  korrekten Layer-Count, print_time und color_map.
- Fertige `method 1020`-Druckstart-Payload in Doku vorbereitet, mit
  slot_map auf A4 und `bedlevel_force=true` fuer die
  Bettnivellierung.

**2. Ungeprueft**

- **Druckstart selbst.** Nach Klaus-Vorgabe bewusst nicht ausgefuehrt.
  Erfolg steht erst nach manuellem Start durch Klaus und
  Sichtkontrolle am Drucker fest.
- **plate_type/bed_type im Status.** Nicht vorhanden (bestaetigt
  nicht geraten) – damit auch kein Abgleich gegen den
  `curr_bed_type` im G-Code moeglich.
- **Resume-Verhalten bei Upload-Abbruch.** Mit einer <1 MiB-Datei
  nicht getestet; der `offset`-Wert im Response-Body koennte als
  Resume-Marker genutzt werden, braucht aber einen groesseren
  Testfile fuer einen echten Nachweis.
- **VPN- und Cloud-Pfad** – nur dokumentiert, nicht implementiert.

**3. Geht nicht**

- (keine neuen Blocker)

---

## 2026-10-25 08:40 – CC2-MQTT-Handshake erfolgreich (lan_status=1), api_status ist Delta-only

Klaus hat „Nur LAN" am CC2 eingeschaltet und den Testlauf freigegeben.

### Was gemacht

- Discovery UDP 52700 erneut: `sn=<cc2-sn>`, `token_status=1`,
  **`lan_status=1`** (umgeschaltet, wie erwartet).
- MQTT-Script `/tmp/mqtt_test.py` wiederholt (identisch zum
  vorigen Lauf, nur neue zufaellige Client-/Request-ID).
  user=`elegoo`, Password aus `.env` (nirgends ausgegeben).

### Ergebnis

```
CONNACK rc=0  (accepted)
SUBACK #1  granted_qos=(0, 0, 0)
PUB api_register {"client_id":"hsltest1582","request_id":"140e5e9..."}
→ register_response: {"client_id":"hsltest1582","error":"ok"}
RX api_status (65 byte): {"id":3,"method":6000,
   "result":{"heater_bed":{"temperature":24}}}
PUB api_request {"type":"PING"}
→ api_response: {"type":"PONG"}
DISCONNECT
```

**Alles wie dokumentiert.** `lan_status=1` schaltet den LAN-MQTT-
Pfad frei; mit `lan_status=0` kommt gleich CONNACK rc=5 zurueck
(voriger Lauf). Register-Handshake, Status-Push und PING/PONG
roundtrip funktionieren.

### api_status ist Delta-only

Das Payload des ersten `api_status` enthaelt nur eine Aenderung
(hier: Druckbett-Temperatur 24 °C, Drucker idle). Volle Zustands-
abbildung braucht entweder laengeres Aggregieren der Deltas oder
eine explizite Query (`method 2005` fuer CANVAS). Beide sind reine
Lese-Operationen; `method 2005` war in dieser Nachtrunde ausdruecklich
**nicht** Teil des Auftrags („einmal api_status lesen").

### CANVAS-Slot-Belegung (A1+A2 PETG, A3+A4 PLA) – nicht geprueft

Nicht im Delta enthalten. Erfordert naechsten Lauf. Vorhandenes
Format aus den Reverse-Engineering-Quellen in
`docs/networking-cc2.md`, Abschnitt „CANVAS-Slot-Belegung" beschrieben.

### Phase-2-Pfad schriftlich zusammengefasst

In `docs/networking-cc2.md` neuer Unterabschnitt „Zusammenfassung
des Pfads (nach erfolgreichem Handshake)" – sieben Schritte vom
UDP-Broadcast bis zum ersten API-Response, als Grundlage fuer den
spaeteren Dart-Client (`ElegooMqttClient`).

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- `lan_status` flippt wie erwartet von 0 → 1, wenn „Nur LAN" am
  Display eingeschaltet wird. Beweis: zweimalige Discovery-Antwort
  (gestern 08:15: `lan_status=0`, heute 08:35: `lan_status=1`).
- MQTT-CONNACK rc=0 mit user=`elegoo` + Access-Code aus `.env`.
  Beweis: Script-Output oben, Zeile `CONNACK rc=0 (accepted)`.
- Register-Handshake liefert `{"error":"ok"}`. Round-Trip
  `register_response` kommt auf dem erwarteten Topic
  `elegoo/<sn>/<request_id>/register_response`.
- api_status-Topic liefert push-Events, PING/PONG-Roundtrip auf
  `api_request`/`api_response` funktioniert.
- Credentials-Hygiene weiterhin: Access-Code taucht nirgends in
  Terminal, Logs, Doku, Commit auf. Temp-Script `/tmp/mqtt_test.py`
  wird nach dem Commit geloescht.

**2. Ungeprueft**

- **CANVAS-Slot-Belegung A1..A4** (erwartet PETG, PETG, PLA, PLA).
  Nicht im ersten Delta-`api_status` enthalten; Pruefung erfordert
  entweder `method 2005`-Request oder laengeres Delta-Sammeln.
  Nicht in diesem Lauf, weil „einmal api_status lesen" woertlich
  befolgt.
- **Volle State-Snapshot-Struktur**. Nur ein Delta gesehen; die
  uebrigen Felder (`machine_status`, `print_status`,
  `extruder`-Temperatur, `gcode_move_inf`) sind theoretisch aus der
  Protokoll-Quelle bekannt, hier aber nicht beobachtet.

**3. Geht nicht**

- (keine neuen Blocker; `docs/blockers.md` unveraendert bei „keine
  offenen").

---

## 2026-10-25 08:20 – CC2-MQTT-Handshake mit Access-Code: Policy-Ablehnung (lan_status=0)

Klaus hat IP + Zugangscode fuer den CC2 in `~/handslice/.env`
hinterlegt (`CC2_IP`, `CC2_ACCESS_CODE`; `.env` ist in `.gitignore`,
`chmod 600`). Klaus hat „Nur LAN" am Drucker bewusst **aus** gelassen
(Cloud-Verbindung soll nicht ohne Grund gekappt werden).

**Was gemacht:**

- `.gitignore` ergaenzt: `.claude/settings.local.json` (nicht der ganze
  `.claude/`-Ordner).
- UDP-52700-Discovery wiederholt: `sn=<cc2-sn>`,
  `token_status=1`, **`lan_status=0`**.
- `python-paho-mqtt` ueber Pacman installiert.
- MQTT-Testscript gegen den CC2: `username="elegoo"`,
  `password=<Access-Code aus .env, nie in Logs>`,
  `client_id="hsltest<4-hex>"` (lokal zufaellig),
  `request_id=<27 hex>` (lokal zufaellig). Plan: CONNECT → SUBSCRIBE
  → `api_register` → `api_status` 1x → PING → DISCONNECT.

**Ergebnis:**

```
CONNACK rc=5  (Not authorized)
```

Direkt vom CC2 abgelehnt, bevor Register-Handshake moeglich war.
`rc=5` kommt identisch zur anonymen Verbindung ohne Auth zurueck –
der Drucker lehnt also schon den Connect-Versuch ab, nicht erst die
Credentials.

Nach Klaus-Vorgabe („bei Ablehnung mit „Nur LAN" aus: dokumentieren
und stoppen – nicht nach Workarounds suchen") hier **gestoppt**.
Kein Register-Request, kein Status-Lesen, kein PING.

**Access-Code-Pruefung (ohne Inhalt zu zeigen):** Variable korrekt
aus `.env` geladen, Laenge 6 Zeichen (plausibles Format fuer
CC2-PIN). Loesung mit anderer Credential-Form nicht probiert.

Daten im Repo-Doku:

- `docs/networking-cc2.md` Abschnitt „MQTT 1883 Connect MIT Auth
  (2026-10-25 08:15)" enthaelt den Nachweislauf und die Hypothese
  (lan_status=0 blockt den LAN-MQTT-Pfad). Ausserdem neuer Abschnitt
  „CANVAS-Slot-Belegung (noch nicht am Geraet verifiziert)" mit der
  Erwartung Slot 1+2 PETG / 3+4 PLA und dem Feld-Schema aus den
  Reverse-Engineering-Quellen.

**Entscheidungsfrage an Klaus:**

- „Nur LAN" am Drucker-Display einschalten → naechster Testlauf
  kann Register-Handshake durchfuehren und CANVAS-Slot-Belegung
  gegen die Erwartung verifizieren. **Oder**
- Cloud-Pfad fuer Phase 2 ausarbeiten (Elegoo-Konto-API, deutlich
  mehr Reverse-Engineering-Aufwand).

Credentials-Hygiene nachgewiesen:

- `.env` nicht eingecheckt (`git status` zeigt sie nicht als
  „unversioniert").
- Access-Code taucht nirgends im Terminal, in Logs, in Doku, in
  PROGRESS.md oder in Commits auf. Script `/tmp/mqtt_test.py` liest
  die Datei zur Laufzeit, speichert den Code nicht in Variablen
  ausserhalb der Session und wird nach dem Commit nicht gebraucht.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- `.gitignore` ignoriert jetzt `.claude/settings.local.json`
  (gezielt), nicht den ganzen `.claude/`-Ordner. Beweis: `git check-
  ignore .claude/settings.local.json` → ignoriert, `git status`
  listet `.claude/` weiterhin als unversioniert (dort nur
  `scheduled_tasks.lock`, der von Klaus bei Bedarf separat
  entschieden werden kann).
- CC2-Discovery UDP 52700 reproduziert mit identischer Antwort wie
  gestern: `sn=<cc2-sn>`, `token_status=1`, `lan_status=0`.
- MQTT-Client-Setup gegen den CC2 mit Credentials aus `.env`:
  Variable korrekt geladen, Laenge 6 Zeichen plausibel, TCP-Connect
  auf 1883 geht durch, MQTT-CONNACK wird empfangen – also die
  gesamte Transport-Kette ist belastbar.

**2. Ungeprueft**

- **Register-Handshake, api_status-Snapshot, CANVAS-Slot-Belegung**.
  Alle drei nicht geprueft, weil der CONNACK=5-Abbruch frueher kommt.
  Erwartung Slot 1+2 PETG / 3+4 PLA bleibt theoretisch, bis „Nur
  LAN" aktiviert ist.
- **Access-Code-Validitaet**. Wenn der Grund fuer `rc=5` nicht
  `lan_status=0` ist, sondern ein inzwischen rotierter Code am
  Display, waere auch das noch zu klaeren. Hier aber ausdruecklich
  **nicht** blind nachprobiert.

**3. Geht nicht**

- **CC2-LAN-MQTT-Register mit lan_status=0.** CONNACK rc=5. Nicht
  als Blocker im Drei-Versuche-Sinn eingetragen – das ist eine
  **Policy-Entscheidung des Drucker-Herstellers / des Benutzers**,
  nicht ein Code- oder Konfigurationsfehler, der hier auf AMR5
  reparierbar waere. Siehe `docs/networking-cc2.md` fuer den
  Nachweislauf und die Entscheidungsfrage an Klaus.

---

## 2026-10-25 07:50 – Divergenz-Ursache gefunden: TBB-Race auf arm64; CC2-LAN-Protokoll geklaert; UI-Stack Flutter

Nachtlauf. Zehn Punkte, alle abgearbeitet:

### Byte-Divergenz arm64 ↔ x86 – Ursache ist TBB-Race, nicht libc++/libstdc++

**Experiment 1a (asymmetrisches Modell).** `engine/test/make_cube.py`
um `cube_notched_20mm_centered_cc2.stl` erweitert (20-mm-Wuerfel
mit 5×5×5-mm-Kerbe an +X+Y+Z-Ecke, 24 Dreiecke, vorzentriert).
Ergebnis: Divergenz bleibt (595 Zeilen nur in x86, 600 nur in arm64).
Grund: die Kerbe bricht die Rotationssymmetrie, aber nicht die
Spiegelsymmetrie an der x=y-Diagonalen. Fuer eine "wirklich
asymmetrische" Variante waere ein off-corner- oder non-square-
Notch noetig (nachgetragen in `docs/engine-integration.md` als
Followup, kein Blocker).

**Experiment 1b (Single-Thread + Mehrfachlaeufe).** `handslice-cli`
hat jetzt `--threads N` (TBB-`global_control`). Zwei Teilbefunde:

- `--threads 1` und `--threads 2` **blockieren auf beiden Plattformen**
  Orcas Pipeline deadlockt bei nur 1-2 Threads (`parallel_pipeline` oder
  `flow::graph` wartet auf einen zweiten Worker, der nie kommt).
  Single-Thread-Test mit dieser Orca-Version nicht ausfuehrbar.
- Mehrfachlauf stattdessen – 10 Laeufe pro Plattform mit dem
  symmetrischen Wuerfel: **x86 ist deterministisch (10/10 identisch,
  sha 92951c26... = GUI-Referenz). arm64 ist NICHT deterministisch
  (6×`a30ffec3`-Variante A, 4×`7c88f484`-Variante B).** Mit dem
  Notch-Modell dasselbe Muster: 3×`7ca4cd37`, 2×`919cde23`.

**Daraus folgt klar: Die Divergenz-Quelle ist ein TBB-Race in Orcas
Pipeline**, nicht libc++ vs. libstdc++. Dieselbe Binary auf demselben
Geraet produziert zwei stabile Varianten pro Lauf. Auf 16-Core-Ryzen
raucht das Scheduling-Fenster offenbar immer dieselbe Reihenfolge, auf
dem 4+4-big.LITTLE-Snapdragon 860 zwei. Die 513-Zeilen-arm64↔x86-Diff
vom Vortag ist dieselbe Klasse Fehler, nur quer-Plattform.

**Phase-C-Erfolgskriterium praezisiert** (nicht gelockert) in
`docs/engine-integration.md`:
1. Funktional-aequivalent zur Desktop-Referenz (Zeilenanzahl, Filament
   ±0.01 g, Zeit ±5 s, Layer-Grenzen).
2. Determinismus pro Plattform (zwei Laeufe byte-identisch).
3. Variant-Set dokumentiert (wenn mehrere stabile Varianten moeglich).

Byte-Gleichheit bleibt als Fernziel (Phase 3+ Orca-Upstream-Patch).

### boost::filesystem-Crash im 2. Aufruf (PROGRESS 2026-10-24 23:50)

**Mit neu gebauter Binary nicht mehr reproduzierbar.** 3× und 10×
hintereinander in derselben adb-shell: alle Exit 0. Crash ist weg,
Ursache unbekannt – vermutlich war der 23:50-Fund an einem seitdem
geaenderten lokalen State haengen geblieben. Dokumentiert in
engine-integration.md.

### UI-Stack entschieden: Flutter

`docs/architecture.md` + `app/README.md` angepasst. Begruendung:
iOS-Option, `dart:ffi` sauberer als JNI, Hot Reload fuer das
dynamische Settings-UI aus den Orca-Profil-JSONs. Android-spezifisches
(Foreground-Service fuer den Slice-Lauf, SAF-Picker) als Kotlin-
Platform-Channel-Code im `android/`-Unterordner des Flutter-Projekts.
Noch kein Flutter-Code – das wird ein eigener Auftrag.

### CC2-LAN-Protokoll geklaert, Portscan + MQTT-Probe

Klaus hat gegen Ende CC2-IP (<cc2-ip>) und drei Protokoll-Quellen
geliefert. Ergebnis in `docs/networking-cc2.md` komplett umgeschrieben:

- **Discovery (UDP 52700):** JSON `{"id":0,"method":7000}` → Reply mit
  `sn="<cc2-sn>"`, `token_status=1` (Access-Code erforderlich),
  `lan_status=0`, `protocol_version=1.0.0`.
- **Portscan:** 1883/tcp open (MQTT), 9001/tcp open (MQTT/WS),
  8080/tcp filtered (MJPEG), 80/tcp **closed** (Stock-Upload-Port
  laut Protokoll – auf dieser Firmware zu), 7125/tcp closed
  (bestaetigt: kein Moonraker).
- **MQTT 1883 Connect ohne Auth:** CONNACK rc=5 (Not authorized),
  erwartet. Kein Subscribe, kein Publish, sauberer Disconnect.
- **Protokoll-Doku** aus den drei Quellen (ChestnutLabs MIT,
  elegoo-homeassistant MIT, elegoo-printer-proxy CC0): MQTT-Topics,
  Registrierungs-Handshake, chunked HTTP-PUT-Upload, 10-s-PING,
  Access-Code-Auth, CANVAS-Multimaterial-`slot_map`.
- **CC1-Protokoll (SDCP)** zusaetzlich vorgemerkt als zweiter
  Client (`SdcpClient`), Modul-Schnittstelle bleibt
  `discover()/upload()/start()/status()`.

**Offen:** Welcher Port tatsaechlich G-Code annimmt (80 closed,
8080 filtered). Vermutung: oeffnet erst nach authentifiziertem MQTT-
Handshake. Pruefung in Phase 2 Prototyp. Neptune 4 Pro war im LAN
nicht sichtbar – nicht geprueft, bleibt ungeprueft, nicht geraten.

**Phase-2-Aufwandsschaetzung** fuer CC2-Client: ca. 1–2
Entwicklungswochen (MQTT-Dart-Client + UDP-Discovery + chunked
HTTP-Uploader + State-Delta-Merge + Pairing-UI + sichere Credential-
Storage). Nicht blockierend fuer Phase 1 (Engine).

### Build + Tests

- `handslice-cli-x86` + `handslice-cli-arm64` inkrementell neu gebaut
  (nur handslice-cli.cpp + CMakeLists Headers geaendert). Beide
  bauen sauber durch.
- arm64 llvm-stripped: 865 MB → 13.8 MB.
- Reference-Test (`run-reference-test.sh`) auf x86 bestanden
  (sha 92951c26..., 8479 Zeilen).

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- `engine/test/make_cube.py` erzeugt jetzt zwei Modelle: den bekannten
  symmetrischen 20-mm-Wuerfel und einen Notch-Wuerfel mit 24
  Dreiecken, vorzentriert auf CC2-Mitte. Beweis:
  `python3 engine/test/make_cube.py` schreibt beide STLs
  (684 + 1284 Byte).
- `handslice-cli` nimmt jetzt `--threads N` an und beschraenkt
  TBB-Parallelitaet entsprechend. Beweis:
  `engine/bin/handslice-cli-x86 --help` listet die Option, und ein
  Lauf mit `--threads 1` haengt reproduzierbar in TBB (das ist
  diagnostisch gewollt, nicht der Erfolgs-Pfad).
- **x86-Determinismus:** 10 Laeufe liefern 10 identische
  EXECUTABLE_BLOCK-Hashes (sha 92951c26...).
- **arm64-Nicht-Determinismus:** 10 Laeufe liefern eine stabile
  Verteilung ueber zwei Varianten A/B (6:4 beim symmetrischen Wuerfel,
  3:2 beim Notch).
- CC2 ueber UDP 52700 Discovery-fertig (`sn=<cc2-sn>`,
  Access-Code erforderlich). MQTT-Erreichbarkeit auf 1883 bestaetigt
  (CONNACK rc=5 Not authorized, da kein Access-Code gesendet – gewollt).
- UI-Stack und CC2-Protokoll-Pfad vollstaendig dokumentiert in
  `docs/architecture.md` + `docs/networking-cc2.md`.

**2. Ungeprueft**

- **G-Code-Upload-Pfad auf dem CC2.** Port 80 war beim Scan geschlossen,
  Port 8080 nur gefiltert. Protokoll-Quelle sagt Port 80 (Stock) oder
  8080 (OpenCentauri). Welcher Pfad real funktioniert, erfordert
  einen authentifizierten MQTT-Handshake vorweg und ist nicht Teil
  dieser Nachtrunde.
- **Neptune 4 Pro.** Nicht im LAN sichtbar, Moonraker-Check nicht
  durchgefuehrt. Ungeprueft gemeldet, nicht geraten.
- **Wirklich asymmetrisches Testmodell** (Notch off-corner / 3×5×5).
  Als Followup notiert, kein Blocker.
- **Determinismus auf arm64 durch Build-Zeit-Tuning** (Workaround B
  mit fixem TBB-Pool). Dachte, waere einen Versuch wert, nicht in
  dieser Runde eroeffnet.

**3. Geht nicht**

- **Byte-Gleichheit arm64 ↔ Desktop-Referenz** – bleibt offen, aber
  Ursache ist jetzt klar: **TBB-Race in Orcas Pipeline, nicht
  libc++/libstdc++**. Nachgewiesen durch den Mehrfachlauf-Test.
  Keine Loesung ohne Orca-Patch (Phase 3+). Phase-C-Kriterium
  entsprechend neu formuliert (siehe `docs/engine-integration.md`).
- **Single-Thread-Lauf** (`--threads 1` oder `--threads 2`) blockiert
  Orcas Pipeline. Als diagnostisches Werkzeug nicht nutzbar; der
  Mehrfachlauf-Test hat die Frage trotzdem beantwortet.

---

## 2026-10-24 23:50 – Device-Test auf Poco X3 Pro gelaufen, Byte-Gleichheit nicht erreicht

Klaus hat die ADB-Autorisierung am Poco bestaetigt; `adb devices` zeigt
`9ed86ce3 device`. `docs/blockers.md` #2 nach „Gelöst" verschoben.

### Device-Lauf

`bash engine/test/run-reference-test.sh --device` lief vollstaendig
durch:

- Push: `handslice-cli-arm64` (14 MB) in 0.097 s, `resources/profiles/`
  (12 852 Dateien, 44 MB) in 2.385 s nach `/data/local/tmp/handslice/`.
- Slice auf dem Poco: **0.9 s**, Return 0, G-Code 207 769 Byte, 100
  Layer, 8479 Zeilen EXECUTABLE_BLOCK.
- Stats (praktisch identisch zum x86-Lauf): 1177 mm Filament,
  2831 mm³, 3.54 g, 9m 21s.

**Laufzeit auf dem Snapdragon 860 (0.9 s) ist nur ca. 1.2× die
AMR5-Zeit (Ryzen 7 5800U, 0.76 s).** Deutlich besser als erwartet.
Zwei aufeinanderfolgende Slices auf dem Poco sind byte-identisch
(`a30ffec3e76452ea67843fa8a1b67eb5dd38fa92a285045a0467f163ec872c99`) –
der arm64-Build ist deterministisch.

### Byte-Divergenz zur Referenz

**EXECUTABLE_BLOCK sha256 arm64 vs. Desktop-Referenz: unterschiedlich**
(513 geaenderte Zeilen bei gleicher Zeilenzahl 8479). Nicht Fliesskomma-
Rauschen: die unterschiedlichen Zeilen sind **rotations-symmetrisch
vertauschte XY-Koordinaten** eines symmetrischen Wuerfels, plus eine
139-Zeilen-TopInfill-Partie um 90° gedrehte Linienrichtung. Topologisch
gleicher G-Code, byte-unterschiedlich. Vollstaendige Analyse in
`docs/engine-integration.md` Abschnitt „Byte-Divergenz arm64 ↔ x86".

**Vermutung:** `std::sort` ist nicht stabil; libc++ (NDK) ordnet Equal-
Key-Elemente anders als libstdc++ (Host). Beim Wuerfel sind viele
Perimeter-Nachbarschafts-Metriken exakt gleich, deshalb schlaegt das
in jeder Instance-Entscheidung durch. Alternativ TBB-paralleles
Zusammenfuehren bei 16 Host-Cores vs. 8 Device-Cores.

### Phase-C-Erfolgskriterium

Laut `docs/engine-integration.md` Schritt C war das Kriterium
„`sha256sum` identisch zum Desktop". Das ist **nicht erfuellt**.
Entscheidung ueber Lockerung (funktional vs. byte-genau) ist nicht
Teil dieses Nachtlaufs – Klaus-Rueckfrage noetig.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- Binary `engine/bin/handslice-cli-arm64` laeuft auf dem Poco X3 Pro
  und erzeugt gueltigen G-Code in 0.9 s. Beweis-Befehl:
  `bash engine/test/run-reference-test.sh --device` (Exit 0, Stats-JSON
  mit `return_code: 0`, 100 Layer, Filament/Zeit/Volumen plausibel und
  identisch zum x86-Lauf auf Milligramm genau).
- arm64-Build ist deterministisch: zwei Slices desselben STL ergeben
  identische sha256 des G-Codes.
- Laufzeit arm64 : x86 ≈ 0.9 s : 0.76 s – Snapdragon 860 nur 1.2×
  langsamer als Ryzen 7 5800U.

**2. Ungeprueft**

- Verhalten unter Last / mehreren parallelen Slices im App-Kontext.
- Verhalten mit groesseren Modellen (>50k Dreiecke) – aktueller
  Testlauf ist nur der 12-Dreiecke-Wuerfel.
- MIUI-Hintergrund-Kill (CLAUDE.md: „MIUI killt Hintergrundprozesse
  aggressiv") – aktuell lief der CLI im Vordergrund per adb shell.
- Second-Lauf im selben adb-shell-Aufruf crasht mit
  `boost::filesystem::create_directory: No such file or directory` –
  ein Aufruf pro adb-shell-Kommando ist bisher der einzige getestete
  Pfad. Vermutlich harmlos (vermutlich braucht die 3mf-Pipeline einen
  frischen Pfad), aber nicht untersucht.

**3. Geht nicht**

- **Byte-Gleichheit arm64 ↔ Desktop-Referenz.** Phase-C-Kriterium
  nicht erfuellt. 513 von 8479 Zeilen unterschiedlich, Natur
  rotations-symmetrisch (`std::sort`-Instability oder TBB-parallele-
  Reihenfolge). Siehe `docs/engine-integration.md` Abschnitt
  „Byte-Divergenz arm64 ↔ x86" fuer die vollstaendige Analyse und
  die zwei Hypothesen zur Ursache.

---

## 2026-10-24 21:40 – Schritt B/C: Deps + handslice-cli-arm64 gebaut, Device-Test blockiert

Fortsetzung des Nachttauftrags. Alle sechs Punkte aus Klaus' Vorgabe
(Dep-Audit → Deps-Build → CLI-Build → Doku → Protokoll → Commit)
abgearbeitet; der Device-Nachweis haengt an einer offenen ADB-
Autorisierung am Telefon (siehe Rubrik 3 unten + `docs/blockers.md` #2).

### 1. Dep-Audit vor dem Cross-Build

`libslic3r.a` + `handslice-cli` brauchen 20 der 23 Orca-Deps aus dem
x86-Build. Weglassen koennen wir **GLFW** (nicht in libslic3r-Sources
referenziert) und **CURL** (ebenso). **OpenVDB/OpenEXR/Blosc** bleiben
drin, weil `SLA/Hollowing.cpp` unguarded `<openvdb/...>` includet;
Weglassen braechte einen Orca-Patch – nicht zulaessig. Ergebnis als
Tabelle in `docs/engine-integration.md` Abschnitt „Dep-Audit vor dem
Cross-Build" bevor der Build startete.

### 2. Deps fuer arm64 cross-compiled

`engine/build-deps-arm64.sh` + `engine/cmake/android-arm64.toolchain.cmake`
+ `engine/cmake/android-shims/FindOpenGL.cmake`. Baut Boost 1.84, TBB,
Cereal, Eigen, PNG, FREETYPE, JPEG, EXPAT, NLopt, GMP, MPFR, CGAL, Blosc,
OpenEXR, OpenVDB, OCCT 7.6.0, Qhull, Draco, libnoise, OpenCV 4.6.0 fuer
`arm64-v8a` / android-29 nach
`engine/OrcaSlicer/deps/build-arm64/OrcaSlicer_dep/usr/local/`.

OpenSSL baut der Build-Script manuell, weil Orcas Recipe einen leeren
`TOOLCHAIN_PREFIX` an OpenSSL durchreicht. Dazu Stubs:

- `libfontconfig.a` (leer, aber linkbar) – OCCT auf Android ruft keine
  fontconfig-Symbole, aber `src/libslic3r/CMakeLists.txt:613` linkt sie
  trotzdem hartkodiert.
- `libcurl.a` + `include/curl/curl.h` (leer) – `find_package(CURL
  REQUIRED)` in `OrcaSlicer/CMakeLists.txt:633` zufriedenstellen, ohne
  echtes libcurl zu bauen.
- `lib/cmake/glfw3/glfw3Config.cmake` – `find_package(glfw3 REQUIRED)`
  in `OrcaSlicer/CMakeLists.txt:698` zufriedenstellen; INTERFACE-Target
  ohne Libs/Includes.

94 `.a`-Dateien im Deps-Prefix, alle `file`-Check: `ELF 64-bit LSB
relocatable, ARM aarch64`. Zwoelf Cross-Compile-Stolpersteine mit
Loesung dokumentiert in `docs/engine-integration.md` Abschnitt
„Umsetzung" (von GLEW-OpenGL-Shim ueber GMP-Autotools-Compiler-Trick
bis zum NDK-libc++-sstream-Fix fuer LocalesUtils.cpp). **Keine Zeile im
OrcaSlicer-Upstream geaendert.**

### 3. libslic3r + handslice-cli-arm64

`engine/build-cli-arm64.sh` baut gegen die arm64-Deps. Umgeht die
cross-compile-fatale OrcaSlicer-encoding-check-Dependency durch einen
`sed`-Patch auf `build.ninja`, der den Encoding-Check-COMMAND auf das
bereits vorhandene Host-x86-encoding-check-Binary umbiegt.

`engine/cli/CMakeLists.txt` greift OpenCVs Android-Install-Layout auf
(`sdk/native/staticlibs/arm64-v8a/libopencv_world.a` statt
`lib/libopencv_world.a`) und waehlt pro CMAKE_SYSTEM_NAME zwischen
Linux- und Android-Pfaden fuer System-Libs (`libz`, `-llog` statt
`-lpthread`, u. a.).

Binary: `engine/bin/handslice-cli-arm64`, 14 MB nach
`llvm-strip --strip-unneeded` (vorher 865 MB mit Debug-Info).

```
$ file engine/bin/handslice-cli-arm64
ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV),
dynamically linked, interpreter /system/bin/linker64, for Android 29,
built by NDK r27d (13750724)
```

### 4. run-reference-test.sh um `--device`-Modus erweitert

Pusht Binary + Elegoo-Profile + Wuerfel per adb nach
`/data/local/tmp/handslice/`, slicet auf dem Geraet, pullt den G-Code
und vergleicht EXECUTABLE_BLOCK gegen Referenz. Nicht ausgefuehrt
(siehe Rubrik 3 unten).

### 5. Doku-Updates

- `docs/engine-integration.md`: neuer Abschnitt „Dep-Audit vor dem
  Cross-Build" (Tabelle); neuer Abschnitt „Umsetzung" unter Schritt C
  mit Script-Index, Toolchain-Hinweisen und zwoelf Stolpersteinen inkl.
  Loesung. „Device-Test" als „ausstehend" markiert.
- `docs/test-setup.md`: Toolchain-Wrapper + CMake-Shims eingetragen.
- `docs/blockers.md`: Blocker #2 (ADB).

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- `engine/bin/handslice-cli-arm64` existiert, ist ELF ARM aarch64 fuer
  Android 29. Beweis-Befehl: `file engine/bin/handslice-cli-arm64`.
- 94 arm64-static-libs unter `engine/OrcaSlicer/deps/build-arm64/
  OrcaSlicer_dep/usr/local/lib/` (Boost, TBB, OCCT 7.6, OpenCV 4.6,
  OpenVDB, CGAL, GMP, MPFR, …). Stichprobe: `file …/libTKMath.a`-
  Member → `ELF 64-bit LSB relocatable, ARM aarch64`.
- Build-Skripte reproduzierbar: `bash engine/build-deps-arm64.sh` +
  `bash engine/build-cli-arm64.sh` (von leerem `build-arm64/` ca. 50 min
  auf AMR5). Beide ohne Patches an OrcaSlicer-Upstream.
- Umgehungen fuer zwoelf Cross-Compile-Stolpersteine schriftlich
  festgehalten (`docs/engine-integration.md` Abschnitt „Umsetzung").

**2. Ungeprueft**

- **Byte-Gleichheit auf dem Poco X3 Pro.** Das Binary existiert, der
  Testlauf-Pfad in `engine/test/run-reference-test.sh --device` ist
  implementiert, aber der ADB-Rundlauf ist blockiert (siehe Rubrik 3).
- Laufzeit auf Snapdragon 860 – ohne Device-Lauf nicht gemessen.
- Reproduzierbarkeit „von null auf einem anderen Rechner": nur auf
  AMR5 getestet. Fuer andere Linux-Distributionen oder NDK-Versionen
  koennen Pfade im Toolchain-Wrapper angepasst werden muessen.
- fontconfig-Stub + CURL-Stub + glfw3-Stub-Config: belasten die Compile-
  und Link-Phase korrekt, aber zur Laufzeit ruft libslic3r keine
  Symbole aus diesen Libs; untestable, solange der G-Code nicht
  nachweislich erzeugt wird.

**3. Geht nicht**

- **ADB sieht das Poco nicht mehr**, siehe `docs/blockers.md` #2.
  `adb devices` leer, obwohl `lsusb` das Geraet listet. Vermutung:
  Nach dem Rechner-User-Wechsel braucht das Telefon einmalig eine
  neue „USB-Debugging erlauben"-Bestaetigung. Erfordert Klaus am
  Geraet.

---

## 2026-10-24 19:30 – Reproduzierbarkeit nachgewiesen, Flashforge-Rest geklärt, Android-NDK installiert

Fortsetzung unter dem frischen User `handslice` auf AMR5, kein Build-Cache
vorhanden. Alle sechs Punkte aus Klaus' Nachtlauf-Auftrag abgearbeitet.

### 1. `engine/build-headless-x86.sh` von null durchlaufen

Erst-Lauf fiel in Schritt 4/4 (CLI-Link) mit
`liblibnest2d.a missing and no known rule to make it` um. Ursache:
`libslic3r libslic3r_cgal` als `cmake --build`-Target zieht die internen
`deps_src/`-Libs (`miniz_static`, `admesh`, `clipper`, `Clipper2`,
`glu-libtess`, `mcut`, `qoi`, `libsemver`) transitiv mit, aber **nicht**
`libnest2d` – das linkt nur gegen `libslic3r`, nicht umgekehrt, und ist
daher kein ninja-Dependent. Fix im Skript: `libnest2d` explizit zu den
Build-Targets ergaenzen (`engine/build-headless-x86.sh` Zeile 58, mit
Kommentar). Nach dem Fix laeuft der Build end-to-end sauber durch, inklusive
sauber Install nach `engine/bin/handslice-cli-x86`.

Nebenbefund: `extra-cmake-modules` (vom `docs/engine-integration.md`-
Logbuch-Eintrag vom 13:40 als „fehlt" vermerkt) ist fuer den
`SLIC3R_GUI=OFF`-Build **nicht** erforderlich – der komplette Deps-
und libslic3r-Build geht ohne `ECM`-Variablen. Daher nicht als
Script-Dependency aufgenommen (nur installiert, weil heute morgen
praeventiv geholt).

### 2. Reference-Test byte-gleich reproduziert

`engine/test/run-reference-test.sh` (neu, 3 Schritte, Ein-Befehls-Call):
Slicet den Wuerfel mit CC2 0.4 + 0.20mm Standard + Elegoo PLA, zieht den
`EXECUTABLE_BLOCK` aus beiden Dateien, vergleicht sha256 + Zeilenzahl
gegen die bekannte Referenz `92951c26...8777675d` / 8479 Zeilen. **Exit 0
= bestanden.**

Lauf:

```
$ bash engine/test/run-reference-test.sh
=== 2/3  EXECUTABLE_BLOCK vergleichen ===
  erwartet: 92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d  (8479 Zeilen)
  erhalten: 92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d  (8479 Zeilen)
  → IDENTISCH
```

Stats-JSON (plausibel): 1 177 mm Filament, 2 831 mm³, 3,54 g, 9m 21s
geschaetzt. (Die kleine Differenz zur frueheren Zahl 1 201 mm liegt an
`total_filament_used_mm` vs. per-Extruder in alter Statistik.)

### 3. „Flashforge-Defaults" im CONFIG_BLOCK aufgeklaert

`compare-configblock.sh` zeigt stabil 11 / 15 / 1 (gleich wie beim ersten
Nachweis). Herkunft der 15 „nur in ref"-Keys (`flashforge_serial_number`,
`bbl_use_printhost`, `printhost_authorization_type`,
`printhost_ssl_ignore_revoke`, `printer_agent`, `pellet_modded_printer`,
`default_bed_type` empty, `default_nozzle_volume_type`,
`extruder_variant_list`, `filament_colour_type`, `filament_multi_colour`,
`filament_self_index`, `ironing_expansion`, `pellet_flow_coefficient`,
`print_compatible_printers`): **nicht** Vendor-blind-Rest, sondern
GUI-Only-Verhalten. Keiner dieser Keys steht in einem Elegoo-Profile-JSON;
die GUI ergaenzt sie beim Preset-Save ueber
`s_Preset_printer_options` + `s_PhysicalPrinter_opts` (`Preset.cpp:1375`,
`:3938`) mit ihrem `print_config_def`-Default. Unser CLI baut die Config
aus `FullPrintConfig::defaults()` + Vererbungs-Kette; da diese Keys dort
nicht per `OPT_PTR` ausgewiesen sind, fallen sie weg. Harmlos fuer den
EXECUTABLE_BLOCK (nachweislich byte-gleich). Dokumentiert in
`docs/engine-integration.md` Abschnitt „Woher die GUI-only
CONFIG_BLOCK-Keys kommen". Nicht nachbilden.

### 4. Doku-Nachtrag: Fokus-Navigation

- `docs/architecture.md` → UI-Schicht: Vollstaendige Fokus-Navigation
  (Tastatur, D-Pad, Controller) als Pflicht ausserhalb des 3D-Viewports.
- `CLAUDE.md` → Technische Konventionen: dieselbe Regel kurz, damit sie
  in jedem Session-Start sichtbar bleibt.

### 5. Android SDK/NDK vorbereitet (noch nichts damit gebaut)

- `jre-openjdk-headless` (OpenJDK 27) via Pacman installiert
  (`sudo -n pacman -S --needed --noconfirm`), weil `sdkmanager`/`android`-
  CLI eine JRE braucht.
- Googles Command-Line-Tools Linux-Zip (`16111833`) nach
  `~/android-sdk/cmdline-tools/latest/` entpackt. Hinweis: Google hat
  `sdkmanager` deprecated zugunsten einer neuen `android`-CLI; beide
  liegen im `bin/`-Dir.
- `yes | sdkmanager --licenses` einmalig akzeptiert.
- NDK `27.3.13750724` (= r27d, aktueller LTS-Patch der r27-Linie) ueber
  `sdkmanager "ndk;27.3.13750724"` installiert nach
  `~/android-sdk/ndk/27.3.13750724/` (ca. 2 GB). `aarch64-linux-android29-
  clang --version` meldet Android-Clang 18.0.4 – damit sind Bionic-Linking
  und `arm64-v8a`-Cross-Compile fuer Phase B/C bereitgestellt.
- Versionen + Pfade in `docs/test-setup.md` eingetragen (Toolchain-Tabelle
  + neuer Abschnitt „Android SDK/NDK einrichten"). `PATH`-Exports stehen
  dort als Projekt-lokale Umgebungs-Snippets – **nicht** in `~/.bashrc`
  geschrieben, Projektregel „Keine Dotfile-Aenderungen".
- Platform-SDK (API-Level, Build-Tools) **noch nicht** installiert; haengt
  an UI-Stack-Entscheid.

### 6. Protokoll + Commit

Siehe Abschlussbericht unten; lokaler Commit erstellt, nicht gepusht.

---

### Abschlussbericht (Rubriken nach CLAUDE.md §4)

**1. Nachweislich funktioniert**

- `engine/build-headless-x86.sh` baut auf einer leeren Deps-/Build-Cache-
  Umgebung komplett durch, von Deps ueber `libslic3r` bis `handslice-cli-x86`.
  Beweis-Befehl: `rm -rf engine/build engine/OrcaSlicer/deps/build-x86 &&
  bash engine/build-headless-x86.sh` – endet mit `ELF 64-bit ... x86-64`
  und Help-Ausgabe.
- `engine/test/run-reference-test.sh` liefert Exit 0 und
  `EXECUTABLE_BLOCK sha256 = 92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d`
  bei 8479 Zeilen. Phase-A-Erfolgskriterium ist damit erneut, in einem
  einzigen Befehl, pruefbar.
- NDK r27d installiert, `aarch64-linux-android29-clang` ausfuehrbar
  (`--version` liefert Android-Clang 18.0.4).

**2. Ungeprueft**

- Reproduzierbarkeit „auf einem komplett anderen Rechner" – getestet nur
  auf AMR5 (CachyOS, GCC 16.2.1, CMake 4.4.4). Fuer andere Distributionen
  / Compiler-Versionen koennen weitere Deps noetig werden.
- Android NDK ist installiert, aber **noch nicht fuer Cross-Compile von
  Orca-Deps genutzt** (ausdruecklich Teil von Schritt B/C, nicht dieses
  Auftrags).
- Die Downloads der cmdline-tools-ZIP sind groesser als in der
  `repository2-3.xml` angekuendigt (173 MB vs. 157 MB laut `Content-Length`
  bei der Probe); Google scheint die Datei inzwischen aktualisiert zu
  haben. Zip ist gueltig (`unzip -l` listet 139 Dateien, `sdkmanager`
  laeuft), aber ein sha256-Pinning ist nicht hinterlegt.

**3. Geht nicht**

- (keine offenen Blocker; `docs/blockers.md` unveraendert bei „keine
  offenen".)

---

## 2026-10-24 17:40 – Executable-Block byte-gleich mit GUI-Export

Klaus hat den Desktop-Orca-GUI-Export unter `engine/test/out-gui/plate_1.gcode`
hinterlegt und drei Divergenzen zum CLI-Output benannt. Alle drei gefixt;
der EXECUTABLE_BLOCK ist jetzt **sha256-identisch**
(`92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d`,
8479 Zeilen auf beiden Seiten).

**Fixes im CLI:**

1. **ResourceIndex vendor-aware.** Mein alter Chain-Walker lief bei
   `inherits = fdm_filament_common` zufaellig in das Afinia-Verzeichnis
   statt in das Elegoo-Verzeichnis (40 Vendors haben eine gleichnamige
   Datei; Afinia hat `filament_flow_ratio=1`, Elegoo `0.98`). Jetzt
   speichert der Index alle Pfade pro `(type, name)`, und der Lookup
   bevorzugt den Pfad, dessen Vendor-Verzeichnis (das Segment direkt
   unter `profiles/`) mit dem Leaf uebereinstimmt. Damit kommt
   `filament_flow_ratio=0.98` sauber durch, und meine fruehere
   Behauptung „unser CLI resolvt die Chain korrekt" wird jetzt auch
   wirklich eingeloest.
2. **`curr_bed_type` nachsetzen.** CLI fiel auf Enum-Default `btPC`
   (Cool Plate) zurueck, weil wir es nicht explizit setzen. Orcas GUI
   leitet den Wert aus `default_bed_type` des Druckerprofils ab
   (int-String → `BedType`, Fallback `btPEI` = High Temp Plate).
   Im CLI nachgebildet nach dem Chain-Load.
3. **`is_BBL_printer = false` setzen.** `Print::m_isBBLPrinter` ist in
   `Print.hpp` nicht initialisiert; `GCodeProcessor::s_IsBBLPrinter`
   ist ein static mit Default `true`. Orca setzt beide aus
   `preset_bundle->is_bbl_vendor()`, fuer CC2 (Vendor „Elegoo") ist das
   `false`. Fehlte in unserem CLI – deshalb kam Bambu-Stil raus
   (`; FEATURE:`, `M624`, `M981`, `M900`) statt Klipper-Stil (`;TYPE:`,
   `SET_PRESSURE_ADVANCE`).

**Vergleichsskripte** unter `engine/test/`:

- `compare-gcode.sh` erweitert: EXECUTABLE_BLOCK-sha256 getrennt vom
  Gesamtdatei-Hash. Exit 0 wenn Executable identisch.
- `compare-configblock.sh` neu: differenziert die CONFIG_BLOCK-
  Zuweisungen in drei Kategorien („Werte unterschiedlich", „nur in ref",
  „nur in ours"). Haette den `filament_flow_ratio=1` vs `0.98` sofort
  gezeigt – kuenftige Divergenzen fallen damit automatisch auf.

**Was weiterhin unterschiedlich bleibt** (akzeptiert, dokumentiert in
`docs/engine-integration.md`):

- Thumbnail-Block (GUI schreibt PNG-base64, wir nicht).
- Reihenfolge der Bloecke (GUI: Header → Thumbnail → Executable →
  Config; wir: Header → Executable → Config).
- 11 Metadaten-Werte im CONFIG_BLOCK (`extruder_colour`, `filament_colour`,
  `wipe_tower_x/y`, `filament_ids`, `print_settings_id`, Flashforge-
  Defaults, u. ä.) – alle beeinflussen den EXECUTABLE_BLOCK nicht.
- `; model label id: 12`-Header-Zeile (bei uns da, bei GUI nicht).

Keine offenen Blocker. Phase A damit sauber abgeschlossen; naechster
Auftrag ist Schritt B/C (ARM64 Cross-Build).

## 2026-10-24 16:50 – Schritt A: eigener Minimal-CLI (Option F) steht

- Klaus hat Option F entschieden: statt Patch an `OrcaSlicer.cpp` eine
  eigene Entry unter `engine/cli/handslice-cli.cpp` (+ CMakeLists), die
  gegen die bereits gebauten `libslic3r_*`-Statik-Bibliotheken linkt und
  **keinerlei** wx-/GLFW-/`slic3r/GUI`-Code mitzieht. Keine Zeile an
  OrcaSlicer-Upstream geändert.
- Umfang: STL + 3mf laden, Profil-JSONs (machine/process/filament) mit
  `inherits`-Chain über rekursiven Resource-Scan auflösen, Modell optional
  auf Plattenmitte zentrieren (`--no-center` lässt es an Ort), Print
  erstellen+process+export_gcode, Statistik (Zeit, Volumen, Gewicht) als
  JSON auf stdout.
- Zweite CLI-Kopplungs-Fundstelle beim Linken: libslic3r referenziert
  `nsvgParseFromFile`/`nsvgDelete`, deren Implementierung in Orca-Upstream
  **in einer GUI-Datei** erzeugt wird. Lösung ohne Patch: eigene
  `engine/cli/nanosvg_impl.cpp` setzt die beiden `#define
  NANOSVG_IMPLEMENTATION`/`NANOSVGRAST_IMPLEMENTATION`. Dritte Fundstelle:
  OpenCascade-`libTKService.a` braucht `fontconfig`, in Orca nur unter
  `SLIC3R_GUI=ON` gelinkt – wir ergänzen es explizit.
- Binary: `engine/bin/handslice-cli-x86` (66 MB; `ldd` zeigt kein `libwx*`,
  `libGLFW*`, `libGL*`).
- Testlauf: Slice eines 20-mm-Würfels mit Elegoo CC2 0.4 Düse +
  0.20 mm Standard + Elegoo PLA erzeugt validen G-Code, 100 Layer,
  `return_code: 0`, Statistik (1 201 mm Filament, 2 888 mm³ Volumen,
  3.61 g) plausibel.
- Byte-Vergleich gegen AppImage CLI (mit `--arrange 0 --orient 0` auf
  vorzentriertem STL `cube_20mm_centered_cc2.stl` auf (128, 128)):
  **unterschiedlich**. Hauptursache ist aber **nicht PartPlate** – die
  AppImage CLI (nicht die GUI!) **löst die Preset-Vererbungs-Kette
  nicht auf**, deshalb bleibt bei ihr `skirt_loops=1` (Default) statt
  `0` (Elegoo-Common), und `filament_density=0` statt `1.25`. Unser
  CLI resolvt die Chain korrekt und ist semantisch näher am GUI-Resultat.
  Volltext der Analyse: `docs/engine-integration.md` Abschnitt
  „Nachweislauf (2026-10-24, Byte-Vergleich)".
- Blocker #1 nach `docs/blockers.md` → **Gelöst**.
- Option C (Upstream-PR für saubere CLI/GUI-Trennung) in
  `docs/roadmap.md` unter Phase 3 vermerkt.

### Offene Punkte

- **Byte-Gleichheit gegen Desktop-Orca-GUI-Export** (nicht gegen AppImage
  CLI) steht noch aus. Klaus prüft das manuell: STL in die GUI laden,
  gleiche Profile, slicen, G-Code exportieren, mit unserem CLI-G-Code
  diffen. Nicht blockierend für Phase 0/1.

## 2026-10-24 14:35 – Schritt A: Orca-Deps gebaut, CLI-Binary blockiert

- Orcas eigenes Deps-System durchgebaut: Boost 1.84, TBB, Cereal, Eigen
  (Prusa-Fork 5.0.1), PNG, FREETYPE, JPEG, NLopt, GMP, MPFR, CGAL, Blosc,
  OpenEXR, OpenVDB, OCCT, Qhull, Draco, libnoise, OpenSSL, CURL, GLFW,
  OpenCV. Nicht gebaut (weil nur GUI): wxWidgets, GLEW, OpenCSG.
  Destdir: `engine/OrcaSlicer/deps/build-x86/OrcaSlicer_dep/usr/local`.
- Erst-Stolperstein: Orcas Deps patchen OpenCV per `git apply --directory`
  mit einem Pfad relativ zum **OrcaSlicer-Git-Root**. Baut man außerhalb
  (`engine/build/deps`), findet git das umgebende `handslice/.git` und
  wirft „unable to normalize directory". Fix: Deps-Build nach
  `engine/OrcaSlicer/deps/build-x86` legen – kein Patch nötig.
- AppImage von OrcaSlicer v2.4.2 unter `engine/reference/`, extrahiert
  nach `squashfs-root/`. 20-mm-Würfel-STL (`engine/test/cube_20mm.stl`,
  684 Byte, 12 Dreiecke, sha256 `f483867e…bdf63`) per Python erzeugt.
- Testlauf AppImage: `AppRun --slice 0 --orient 1 --arrange 1
  --load-settings "<CC2 0.4>;<0.20mm Std>" --load-filaments
  "<Elegoo PLA>" --outputdir out-appimage cube_20mm.stl` erzeugt
  `plate_1.gcode` (209 KB, 100 Layer) + `result.json` (`return_code: 0`).

### Blocker-Befund: Orca v2.4.2 CLI zieht wxWidgets + GLFW

Mit `SLIC3R_GUI=OFF` baut libslic3r sauber durch (255/258 Build-Schritte);
nur die CLI-Entry `src/OrcaSlicer.cpp` schlägt an `#include <wx/stdpaths.h>`
fehl. Die Datei hat 7 weitere ungeguardete `slic3r/GUI/*`-Includes und
`<GLFW/glfw3.h>`, insgesamt 88 Nutzungen von `Slic3r::GUI::*`, `wx*` und
`glfw*` außerhalb von `#ifdef SLIC3R_GUI` – für Thumbnail-OpenGL-Rendering
(Offscreen-FBO, GLFW-Hidden-Window) und für `PartPlateList`, die
historisch im GUI-Namespace liegt.

Das ist **struktureller Natur**, kein Build-Setup-Problem. Für Phase 1
(ARM64/Android) viel kritischer, weil wxWidgets und GLFW auf Android
nicht offiziell existieren. Volltext der Analyse: `docs/engine-integration.md`
Abschnitt „Harter Befund". Blocker + Entscheidungsfragen:
`docs/blockers.md` #1.

### Offene Frage an Klaus (siehe `docs/blockers.md` #1)

Welchen Weg weitergehen? Die fünf Kandidaten (A..E) sind dort mit Pro/
Contra aufgeführt. **Bis zur Entscheidung ist Schritt A ausgesetzt.**
Phase 0 (Server-Prototyp auf AMR5) kann jetzt schon mit dem gebündelten
AppImage laufen – der Testlauf oben beweist, dass die CC2-Profile sauber
geladen werden.

## 2026-10-24 13:40 – Schritt A: OrcaSlicer-Submodul + Pacman-Deps

- OrcaSlicer-Upstream (https://github.com/SoftFever/OrcaSlicer) als Git-
  Submodul unter `engine/OrcaSlicer` angelegt und auf den neuesten stabilen
  Release-Tag **v2.4.2** (commit `8500fcdcca`) ausgecheckt. Keine inneren
  Git-Submodule bei v2.4.2. Tag in `docs/test-setup.md` eingetragen.
- Pacman-Deps-Prüfung (CachyOS/Arch): die Liste, die Orcas eigenes
  `scripts/linux.d/arch` nennt, ist GUI-fokussiert (gtk3, webkit2gtk-4.1,
  mesa, glew, libmspack, libsecret, libspnav, wayland-protocols,
  gst-plugins-good, gstreamer, eglexternalplatform). Für reinen
  Headless-Build (`SLIC3R_GUI=OFF`) brauchen wir davon fast nichts.
- Prüfliste **Pacman** für reines Slicing-Core (Stand bereits installiert):
  `base-devel`, `cmake 4.4.4`, `ninja 1.13.2`, `git 2.56.0`, `gcc 16.2.1`,
  `clang/llvm 23.1.3`, `lld 23.1.3`, `curl`, `wget`, `openssl`, `zlib`,
  `mesa`, `libglvnd`, `glu`, `glfw-x11`, `glfw-wayland`, `libxrandr`,
  `libxinerama`, `libxcursor`, `libxi`, `libx11`, `file`, `gettext`,
  `texinfo`, `dbus`, `pkgconf`, `autoconf`, `automake`, `libtool`, `m4`.
- **Fehlt:** `extra-cmake-modules` (für ECM-find-Module). Nicht installiert,
  weil Pacman root-Passwort will und Claude Code unbeaufsichtigt läuft.
  Falls der Build danach schreit, stoppen und Klaus fragen.
- Heavyweight-Slicing-Libs (Boost 1.83, TBB, Eigen 5.0.1-fork, OpenVDB 5.0
  mit alter ABI, CGAL+GMP+MPFR, cereal, EXPAT, PNG, Freetype, NLopt 1.4,
  OCCT, OpenCSG, Qhull, Draco, Blosc, OpenEXR, OpenCV, NanoSVG, libnoise,
  JPEG, GLEW, GLFW) sind in Pacman nicht in den von Orca gepinnten
  Versionen vorhanden (Arch tracked HEAD, Orca pinnt alte ABIs). Daher
  werden diese über Orcas eigenes `deps/`-Build-System gebaut, wie es
  Orca-Upstream vorsieht. Das ist der nächste Schritt.

## 2026-10-24 12:50 – Umgebungs- und Verbindungscheck

- Toolchain erfasst und in `docs/test-setup.md` eingetragen: git 2.56.0,
  CMake 4.4.4, Ninja 1.13.2, GCC 16.2.1, Clang/LLVM 23.1.3 (inkl. ld.lld),
  Python 3.14.8, adb 1.0.41 (platform-tools 37.0.0p1).
- **Nicht installiert:** Android SDK, Android NDK, aarch64-linux-gnu-gcc,
  Flutter, Kotlin. Nur festgestellt, nichts installiert.
- Testgerät Poco X3 Pro (`M2102J20SG`, `vayu`, Serie `9ed86ce3`) am ADB als
  `device` sichtbar. Android 12 (API 31), MIUI V13.0.1.0.SJUEUXM, ABI
  `arm64-v8a`, 8-GB-RAM-Variante (7,32 GiB MemTotal, 4,6 GiB verfügbar),
  144 GB frei auf `/data`.
- ADB-Rundlauf bestanden: 10 MiB urandom-Blob push → sha256 auf Gerät →
  pull → sha256 lokal, alle drei Hashes identisch
  (`90156b83…355d`). Push 44,1 MB/s, pull 37,4 MB/s.
- ARM64-Hello-World (freistehend, Clang+lld, direkte Linux-Syscalls) auf
  dem Gerät ausgeführt → `hello from arm64`, Exit 0. Beweist
  Execute-Rechte in `/data/local/tmp` und arm64-Userspace, aber **nicht**
  NDK/Bionic-Linking (NDK ist nicht installiert).
- **Ergebnis:** Umgebung grundsätzlich tragfähig. NDK-Entscheidung bleibt
  offen, hängt an UI-Stack-Entscheidung (Flutter vs. Compose).

## 2026-10-24 – Projekt angelegt

- Repo-Vorlage erstellt. Name: **Handslice** (GitHub-Name geprüft, frei).
- Entscheidungen: Orca-Upstream als Engine; Elegoo-Profile und -Protokoll
  später als Schichten; AGPL-3.0.
- Build-Rechner: AMR5 (CachyOS). Testgerät: Poco X3 Pro (Stock-MIUI).
- **Offen:** UI-Stack (Flutter vs. Compose) – siehe `docs/architecture.md`.
  Bis zur Entscheidung kein Frontend-Code.

### Offene Fragen an Klaus
- (keine)
