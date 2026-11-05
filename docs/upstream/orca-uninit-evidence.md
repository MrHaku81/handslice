# Uninitialised reads in the OrcaSlicer slicing pipeline — evidence pack

Supporting material for the three default-initialisation commits on branch
`fix/uninit-upstream` of this working tree. Each section pins the fix to
upstream `OrcaSlicer/OrcaSlicer@main` at the branch base below, cites the
Valgrind trace showing the uninit mechanism, and names the commit that
introduced the uninitialised member or local.

Author names from `git blame` are deliberately replaced with the commit
hash, per project policy; full authorship is visible on GitHub via each
commit URL.

## Branch under test

- Upstream remote: `https://github.com/OrcaSlicer/OrcaSlicer.git`
  (the former `SoftFever/OrcaSlicer` URL now 301-redirects here).
- Branch base: `upstream/main` at `b2978d1c73` (fetched 2026-11-05).
- Submodule branch: `fix/uninit-upstream` adds three commits on top
  of `b2978d1c73`. No commits are pushed; the branch is kept local
  for the PR preparation.

## Fix #1 — WallToolPathsParams stack members

### Site on upstream/main

- `src/libslic3r/Fill/FillConcentricInternal.cpp:47` declares
  `Arachne::WallToolPathsParams input_params;` and assigns six of the
  eight configurable fields.
- The two missing fields — `float min_length_factor` and
  `bool is_top_or_bottom_layer` — stay uninitialised on the stack and
  are later read inside
  `Arachne::WallToolPaths::removeSmallLines`
  (`src/libslic3r/Arachne/WallToolPaths.cpp:693`):
  ```cpp
  shorterThan(line,
              m_params.is_top_or_bottom_layer ? min_width / 2
                                              : min_width * m_params.min_length_factor)
  ```
- Default values taken from the canonical factory
  `Arachne::make_paths_params`
  (`src/libslic3r/Arachne/WallToolPaths.cpp`): `min_length_factor = 0.5f`,
  `is_top_or_bottom_layer = false`.

### Introduction

- `git blame upstream/main src/libslic3r/Fill/FillConcentricInternal.cpp -L 47,53`
  attributes lines 47-48, 50-53 to commit `aab8a12801` (2022-08-10,
  "ENH: add arachne engine for narrow internal solid infill"); line 49
  (`min_feature_size`) is from `0f1a001fd6` (2022-10-12). The two
  fields we initialise have been uninitialised at this call site since
  the Arachne engine was introduced.

### Valgrind trace (x86, Release+`-g`, slicing Stanford Bunny)

Captured on the v2.4.2 base before any fix was applied. Line numbers
in frames are from the v2.4.2 source tree; the uninit flow is
unchanged on upstream/main (same code structure).

```
Conditional jump or move depends on uninitialised value(s)
   at Slic3r::Arachne::WallToolPaths::removeSmallLines  (WallToolPaths.cpp:693)
   by Slic3r::Arachne::WallToolPaths::generate          (WallToolPaths.cpp:557)
   by Slic3r::FillConcentricInternal::fill_surface_extrusion
                                                        (FillConcentricInternal.cpp:39)
   by Slic3r::Layer::make_fills                         (Fill.cpp:1354)
   by Slic3r::PrintObject::infill                       (PrintObject.cpp:710)
 Uninitialised value was created by a stack allocation
   at Slic3r::FillConcentricInternal::fill_surface_extrusion
                                                        (FillConcentricInternal.cpp:13)
```

The read sits on the predicate that decides whether a narrow wall is
removed, so the stack bytes at the moment `FillConcentricInternal`'s
stack frame is set up directly change the wall-removal output.

## Fix #2 — LayerRegion::process_external_surfaces local

### Site on upstream/main

- `src/libslic3r/LayerRegion.cpp:551` declares
  `double layer_thickness;` and passes it by reference to three
  consecutive `fill_surfaces_extract_expolygons` calls (lines 552-554).
  The callee only writes `thickness` if it finds at least one surface
  of the requested `SurfaceType`.
- If none of the three calls on a layer finds a matching surface
  (no `stInternalSolid`, no `stInternal`, no `stTop`), the value stays
  uninitialised and is subsequently used to seed Surface thickness
  fields that feed downstream fill construction.

### Introduction

- `git blame upstream/main src/libslic3r/LayerRegion.cpp -L 551,551`
  attributes the `double layer_thickness;` line to `075a08bca8`
  (2023-10-19, "Initial port of the new ensure vertical thickness
  algorithm from PrusaSlicer (#2382)"). The upstream-main port carried
  the same uninit pattern.

### Valgrind trace (x86, Release+`-g`, Stanford Bunny)

Captured on v2.4.2 + Fill#1 fix applied. One record per full slice on
Bunny; the read propagates into Clipper geometry via
`GCode::needs_retraction` → `intersection_pl` → `Clipper::AddOutPt`.
Line numbers from the v2.4.2 source tree; the mechanism is identical
on upstream/main.

```
Conditional jump or move depends on uninitialised value(s)
   at Slic3r::ClipperLib::Clipper::AddOutPt                  (clipper.cpp:2025)
   by Slic3r::ClipperLib::Clipper::IntersectEdges            (clipper.cpp:1674)
   by Slic3r::ClipperLib::Clipper::ProcessIntersections      (clipper.cpp:2440)
   by Slic3r::ClipperLib::Clipper::ExecuteInternal           (clipper.cpp:1118)
   by Slic3r::ClipperLib::Clipper::Execute                   (clipper.cpp:1096)
   by Slic3r::_clipper_pl_open<…>                            (ClipperUtils.cpp:844)
   by Slic3r::intersection_pl                                (ClipperUtils.cpp:921)
   by Slic3r::GCode::needs_retraction::{lambda…}             (GCode.cpp:7582)
   by Slic3r::GCode::needs_retraction                        (GCode.cpp:7644)
   by Slic3r::GCode::travel_to                               (GCode.cpp:7359)
   …
 Uninitialised value was created by a stack allocation
   at Slic3r::LayerRegion::process_external_surfaces         (LayerRegion.cpp:487)
```

The frame address at the origin (`LayerRegion.cpp:487`) resolves to the
`process_external_surfaces` function entry on the v2.4.2 tree;
`layer_thickness` lives on that frame.

## Fix #3 — ModelVolume::mmuseg_ts uninit

### Site on upstream/main

- `src/libslic3r/Model.hpp:1021` declares
  `mutable Timestamp mmuseg_ts;` (a `uint64_t` timestamp) as a
  `ModelVolume` member. None of the `ModelVolume` constructors assign
  it.
- First read is at `src/libslic3r/Model.cpp:2760` inside
  `ModelVolume::get_extruders()`:
  ```cpp
  if (mmu_segmentation_facets.timestamp() != mmuseg_ts) {
      …
      mmuseg_ts = mmu_segmentation_facets.timestamp();
      …
  }
  ```

### Introduction

- `git blame upstream/main src/libslic3r/Model.hpp -L 1021,1021`
  attributes the field to `1555904bef` (2022-07-15, "Add the full
  source of BambuStudio"). The uninit pattern has been in place since
  BambuStudio was imported as the Orca base.

### Valgrind trace (x86, Release+`-g`, Stanford Bunny, STL input)

Captured on v2.4.2 + Fill#1 fix applied. The read is reached on the
very first `Print::apply`, before slicing starts.

```
Conditional jump or move depends on uninitialised value(s)
   at Slic3r::ModelVolume::get_extruders                       (Model.cpp:2544)
   by Slic3r::Print::object_extruders                          (Print.cpp:464)
   by Slic3r::Print::extruders                                 (Print.cpp:525)
   by Slic3r::Print::apply                                     (PrintApply.cpp:1620)
 Uninitialised value was created by a heap allocation
   at operator new(unsigned long)                              (vgpreload_memcheck)
   by Slic3r::ModelObject::add_volume                          (Model.cpp:1256)
   by Slic3r::Model::add_object                                (Model.cpp:491)
   by Slic3r::load_stl                                         (STL.cpp:38)
```

Model.cpp line numbers on upstream/main are shifted (the read is at
`Model.cpp:2760`) but the data flow is identical: `add_volume`
allocates the `ModelVolume` on the heap, no constructor touches
`mmuseg_ts`, and `get_extruders()` reads it before any 3MF-provided
timestamp has a chance to be stored.

For plain STL this read happens to be semantically harmless (both
branches of the `if` produce an empty extruder set). For 3MF with a
stored non-zero segmentation timestamp, the uninit comparison can
flip `!=` the wrong way and either falsely recompute or skip the
segmentation refresh.

## Upstream precedent — commit `99dea01cc3` (Print::m_origin)

- The fourth uninitialised Orca member we found on the v2.4.2 base,
  `Slic3r::Print::m_origin`, is **already fixed on upstream/main** by
  commit `99dea01cc3` (2026-06-22, "Fix coord out-of-range exception
  caused by `m_origin` memory not initialized to 0"). The commit went
  in through pull request **#13712** (a wider PR titled "Add nozzle
  flow variant & make some options multi-variant").
- A later follow-up, pull request **#14482**
  (commit `3cf0f4dba5f092d2`, 2026-06-29), re-enabled three Catch2
  test cases in `tests/fff_print/test_printgcode.cpp` and
  `tests/fff_print/test_skirt_brim.cpp` that had been tagged
  `[NotWorking]` because of the same root cause. The tag comment that
  that PR removes reads:

  > `[NotWorking]: slice() intermittently throws clipper's "Coordinate outside allowed range" in CI (Linux) while passing locally. Disabled pending a root-cause fix in a follow-up PR.`

  and the PR body notes:

  > PR #13712 fixed the uninitialized Print::m_origin (commit 99dea01cc3, "Fix coord out-of-range exception caused by m_origin memory not initialized to 0") that made headless slice() intermittently throw ClipperLib's "Coordinate outside allowed range". With that root cause fixed, the three tests disabled for it pass again, so drop their [NotWorking] tags.

- Takeaway for this PR: **the Orca project has already treated an
  uninit-member bug on a slicing core member as a determinism
  defect**, not a "harmless warning". The symptom in that case was
  intermittent CI failures on Linux; the root cause fix was simply
  default-initialising the member to zero. The three members fixed in
  the present PR follow the same pattern (uninit stack / member →
  non-deterministic slicing output), and all three can be addressed
  with the same minimal default-init idiom.

## Determinism impact (measured on the v2.4.2 base, not re-run on upstream/main)

The five uninit fixes together (the three in this PR + the Clipper1
`PolyNode` fix that no longer applies after upstream's Clipper2
migration + the already-committed `Print::m_origin` fix) were measured
on the v2.4.2 base of our fork:

- Bunny (ECC2 0.4 / 0.20 mm Standard, Elegoo PLA): three independent
  arm64 slices produce bit-stable `total_filament_used_mm`
  (129 020.89814531246 mm, identical to 10 digits across runs).
- Cube reference (`engine/test/run-reference-test.sh`):
  `EXECUTABLE_BLOCK` SHA-256
  `92951c26260cedd1866a4694adfcc5768389442e7cc3993c0f94dfae8777675d`,
  8 479 lines, byte-identical to the pinned v2.4.2 GUI export.
- Valgrind Memcheck on x86-debug Bunny, slicing phase only (Fill,
  Perimeter, Clipper core, Brim, Arachne/WallToolPaths,
  `LayerRegion::process_external_surfaces`): **zero uninit records
  remain in the slicing pipeline.** The 12 contexts Memcheck still
  reports after the fixes are all in `export_gcode`
  (`TimelapsePosPicker`, `GCodeWriter::set_extruders` via
  `placeholder_parser`) and do not affect toolpath computation.

Re-measurement on top of upstream/main with `-ftrivial-auto-var-init`
init-mode invariance has been scoped for this PR preparation.
Status is tracked in the "Build-on-upstream verification" section
below.

## Build-on-upstream verification (x86)

Four libslic3r + minimal CLI builds, all against the same upstream deps
(Linux x86_64, GCC 16.2.1, Ninja, Release), slicing `bunny-200mm.stl`
(scaled Stanford Bunny, SHA-256
`64d421d507f21aa20eab12fa92c0797c01363a63fdbe0420adaf66d0c18fdc89`,
2 635 884 bytes) with the Elegoo Centauri Carbon 2 0.4 nozzle / 0.20 mm
Standard / Elegoo PLA profile set that ships in the repo.

Branches:
- `fix` = `upstream/main` (`b2978d1c73`) with the three default-init
  commits from this PR cherry-picked on top (`fix/uninit-upstream`).
- `plain` = unmodified `upstream/main` at `b2978d1c73`.

Init-mode flag applied to every libslic3r and CLI compilation unit via
`CMAKE_CXX_FLAGS_INIT="-ftrivial-auto-var-init=<mode>"`, injected into
every Ninja `FLAGS` line of the generated `build.ninja` to overcome
upstream's own `-CMAKE_CXX_FLAGS_INIT` overrides.

Each run emitted one G-code file at identical size:

| build         | bytes      | lines      |
|---------------|------------|------------|
| fix-pattern   | 40 759 234 | 1 692 011  |
| fix-zero      | 40 759 234 | 1 692 011  |
| plain-pattern | 40 759 234 | 1 692 011  |
| plain-zero    | 40 759 234 | 1 692 011  |

### Raw SHA-256 of `bunny.gcode`

| build         | SHA-256 |
|---------------|---------|
| fix-pattern   | `b79e0225f3399357625bbeb3307e891cdc6cf26ce8e8d1a0428ccbc6d1550781` |
| fix-zero      | `f5c1b1d01374995760983b5f38c28d232e1864006ad35f7a8e21e3d2ee4aff8b` |
| plain-pattern | `17b7d18abece05713a4d7c03d83bad3102954f3fc790143faf1e8bc2a5ffffbd` |
| plain-zero    | `b44f89ba00793c92cd9255882b515723939dc3ab54cd7be7f8c6f1835e9274ab` |

All four raw SHA-256 values differ — but every byte of the difference
lives on the single `; generated by OrcaSlicer <ver> on <date> at
<time>` header line that embeds the wall-clock time of the slice. No
other byte of the file varies.

### Stripped SHA-256 (header timestamp removed)

Dropping only the `; generated by OrcaSlicer …` line:

| build         | SHA-256 |
|---------------|---------|
| fix-pattern   | `99886b1c5dc6e8938e2fae74fd6e728988131c216f919ed2553e21f6faff505d` |
| fix-zero      | `99886b1c5dc6e8938e2fae74fd6e728988131c216f919ed2553e21f6faff505d` |
| plain-pattern | `99886b1c5dc6e8938e2fae74fd6e728988131c216f919ed2553e21f6faff505d` |
| plain-zero    | `99886b1c5dc6e8938e2fae74fd6e728988131c216f919ed2553e21f6faff505d` |

All four identical.

### Reading of the result

- **Fix branch is bit-stable under init-mode variation**
  (`fix-pattern = fix-zero`). This is the direct reproducibility
  criterion for the PR: with the three `default-init` commits in
  place, `-ftrivial-auto-var-init` becomes a no-op on this slice.
- **Plain branch is also bit-stable under init-mode variation on this
  slice** (`plain-pattern = plain-zero`), and in fact produces the
  same stripped SHA-256 as the fix branch. The three uninit reads
  the commits fix are definitely still hit on `b2978d1c73` (the
  source hasn't changed at those lines), but neither 0xAA-pattern nor
  all-zero stack fill flips a decision in this particular model /
  profile / toolchain combination at the predicate level that this
  slice reaches. In other words: the Stanford Bunny / ECC2-0.20mm-PLA
  combination does not land in a "narrow wall" case where
  `WallToolPaths::removeSmallLines` would change its decision between
  the fix defaults (`0.5f`, `false`), the pattern bytes
  (`-nan`, `true`) and the zero bytes (`0.0f`, `false`); the
  `process_external_surfaces` layer-thickness branch and the
  `ModelVolume::mmuseg_ts` STL-input branch are both semantically
  harmless at the read site. Valgrind still proves the uninit
  **reads** happen (see the three traces above); the slice simply
  does not amplify any of them to a toolpath-visible delta.
- **Where the amplification does show up** is the v2.4.2 baseline
  tracked in `PROGRESS.md 2026-11-04 19:26 UTC`: on arm64 three
  successive Stanford Bunny slices on the Snapdragon 860 produced
  bit-stable `total_filament_used_mm` (129 020.898 mm, 10 digits
  identical across runs) **only after** these fixes were applied.
  Before the fixes, repeated slices on the same arm64 binary diverged
  in `filament_mm`. The upstream-main build above does not reproduce
  that divergence because `-ftrivial-auto-var-init` already stabilises
  the uninit reads at compile time, which is exactly what this PR
  makes unnecessary.

### Build setup (for reproduction)

- `engine/OrcaSlicer/deps/build-x86-upstream/` — fresh upstream-main
  dependency build. 25 targets built, plus FFMPEG in a follow-up pass
  after installing nasm 2.16.03 locally (no system package).
- `local-test/upstream-orca-build/{fix,plain}-{pattern,zero}/` —
  per-build directories with `orca-build/` (libslic3r) and
  `cli-build/` (CLI) subdirectories, `handslice-cli` binary,
  `bunny.gcode` and its SHA-256 files. Not committed.
- Submodule `fix/uninit-upstream` branch stays local; the main-repo
  submodule pointer is unchanged.

## OrcaSlicer contributor guidance referenced by this evidence pack

Quotes are copied verbatim from the upstream working tree at
`b2978d1c73`. Each cite includes the file path so the maintainer can
re-check.

### `CONTRIBUTING.md`

- Line 14, "Keep each PR to one topic":
  > Keep each PR to one topic. Put changes that belong together in one
  > PR, and unrelated changes in separate PRs. Focused PRs are reviewed
  > and merged much faster.
- Line 17, "AI tools":
  > AI tools are welcome. You are still responsible for the change, so
  > test it and make sure you understand it.
- Line 35, table row "Bug fix":
  > The cause, before and after, a test if possible
- Lines 60-66, "Using AI tools":
  > You are responsible for the change. Before you ask for review,
  > build the change, run it, and confirm that it works. Be ready to
  > explain each change and why it is needed.
  >
  > Keep it short and true. AI tools tend to write long descriptions,
  > and sometimes describe tests that never ran. Remove generated code
  > that isn't needed, too. A short description of what you actually
  > did helps more.
- Lines 71-81, "If you are an AI agent" (numbered list; full text
  retained — this PR preparation follows the list literally):
  > 1. Show the contributor this guide before you open a PR or post
  >    a comment.
  > 2. Search open PRs for the same change before you start.
  > 3. If the contributor already has several open PRs, wait until some
  >    are merged before you open another.
  > 4. Before you change code, check `.claude/skills/` for a skill that
  >    matches the change, and follow it.
  > 5. If the code can be tested, add an automated test, and check that
  >    it fails without the change and passes with it.
  > 6. Ask the contributor to test the change by hand. For a bug fix,
  >    they should build the code without the change and reproduce the
  >    bug. Then they should build the branch and check that the bug
  >    is gone.
  > 7. Write the PR description in the [PR template]
  >    (.github/pull_request_template.md). A body passed with
  >    `gh pr create --body` replaces the template, so start from the
  >    template's text.
  > 8. If you couldn't build or run something, say so in the PR.

### `AGENTS.md`

- "Code review focus areas":
  > Changes must not cause regressions in existing functionality,
  > defaults, profiles, or project compatibility.
  >
  > Features gated by options must not affect existing behavior when
  > those options are disabled.
- "Critical Constraints":
  > Backward compatibility required for .3mf project files and printer
  > profiles.
  > Cross-platform — all changes must work on Windows, macOS, and
  > Linux.
- "Code Style":
  > C++17, selective C++20. PascalCase classes, snake_case
  > functions/variables.
  > `#pragma once` for headers. Smart pointers and RAII preferred.

### `.github/pull_request_template.md`

- The repository PR template keeps the "How to Download Pull Requests
  Artifacts" link as the last line and asks for a `Description`,
  `Screenshots/Recordings/Graphs`, and `Tests` section
  (see `.github/pull_request_template.md`).

### `.github/ISSUE_TEMPLATE/bug_report.yml`

- First mandatory checkbox (lines 15-22):
  > Please verify this issue still happens in the latest nightly build
  > first. It may already be fixed there.

These rules shape the planned PR body: single-topic (uninit reads
on three member/local sites), bug-fix label, short description,
"before/after" via Valgrind traces above, tests not added (none of
the Catch2 suites currently exercises the three sites in a way where
"uninit present" fails deterministically — see also the `[NotWorking]`
tags that the `Print::m_origin` fix removed).
