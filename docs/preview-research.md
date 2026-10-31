# Preview research — thumbnail (Pflicht 6) + plate view / layer view / arrange (Pflicht 7)

Read-only reconnaissance before any implementation. All claims
are grounded in Orca 2.4.2 source, our own reference G-code
(`engine/test/reference/cube_20mm_cc2_gui_v2.4.2.gcode`), the
Elegoo CC2 machine profile, and a pub.dev survey of Flutter 3D
packages (2026-10-31).

## Teil A — thumbnail (Pflicht 6)

### How Orca 2.4.2 builds the thumbnail

- Entry point: `Print::export_gcode(path, result, thumbnail_cb)`
  takes a `ThumbnailsGeneratorCallback` and forwards it to
  `GCode::do_export` → `GCode::_do_export` →
  `GCodeThumbnails::export_thumbnails_to_file`.
  (`src/libslic3r/Print.cpp:2618` /
  `src/libslic3r/GCode.cpp:2030`/`2461`.)
- The callback is only wired on the **GUI side**:
  `BackgroundSlicingProcess::render_thumbnails(params)` captures
  it with `m_fff_print->export_gcode(..., [this](const ThumbnailsParams& p){
  return this->render_thumbnails(p); });`
  (`src/slic3r/GUI/BackgroundSlicingProcess.cpp:244`).
- Rendering uses offscreen OpenGL:
  `GLCanvas3D::render_thumbnail(...)` →
  `GLCanvas3D::render_thumbnail_framebuffer(...)`
  (`src/slic3r/GUI/GLCanvas3D.hpp:925..959`). Needs a GL context,
  wxGLContext/GLFW, and all the GUI state (`PartPlateList`,
  `ModelObjectPtrs`).
- Encoding to the G-code happens in
  `src/libslic3r/GCode/Thumbnails.hpp:45..100`
  (`export_thumbnails_to_file`): PNG/JPG/QOI → base64 → wrapped
  into a `; THUMBNAIL_BLOCK_START` … `; THUMBNAIL_BLOCK_END`
  comment block. Other formats (`BTT_TFT`, `ColPic`) use
  different markers; the CC2 does not use them.

**Why our CLI currently emits no thumbnail:** `handslice-cli.cpp`
calls `print.export_gcode(path, result)` without a
`thumbnail_cb`. The callback is `nullptr`, so
`export_thumbnails_to_file` returns on its first line
(`if (thumbnail_cb == nullptr) return;`) and no block is
written. That is also why `method 1045` returned
`error_code = 1015 ThumbnailNotExist` for our 221-byte test
file on 2026-10-31 (Block A device test).

### What the CC2 machine profile asks for

File:
`engine/OrcaSlicer/resources/profiles/Elegoo/machine/ECC2/
Elegoo Centauri Carbon 2 0.4 nozzle.json`

```
"thumbnails": ["144x144"]
```

Format defaults to PNG (`PrintConfig.cpp:208`,
`Preset.cpp:3457`): "'thumbnails' can not contain extensions
in old config but they are valid and use PNG extension by
default".

### What a real CC2 G-code actually contains

`engine/test/reference/cube_20mm_cc2_gui_v2.4.2.gcode`
(205 kB, 9 173 lines), Elegoo-GUI export:

- Thumbnail block occupies **lines 10..35**:
  `; THUMBNAIL_BLOCK_START` → blank-comment separator `;` →
  `; thumbnail begin 144x144 1512` → **22 base64 lines**
  (each `; <78 chars>`) → `; thumbnail end` → `;
  THUMBNAIL_BLOCK_END`.
- 1 512 is the base64-encoded size of the PNG; raw PNG about
  1 134 bytes.
- Footer config confirms the setting:
  `; thumbnails = 144x144/PNG`,
  `; thumbnails_format = PNG`
  (lines 9082/9083).
- No `gimage`/`simage`/`bigtree` markers — those are for
  Flashforge/Creality/BTT firmware, not the CC2.

### What method 1045 ships to the app and the display

Captured on 2026-10-31 (M8 live-read) against
`Elegoo-Bauplattenhalter-1.gcode`:
`{"id":…,"method":1045,"result":{"error_code":0,
"thumbnail":"<base64, 2 684 B>"}}`.
The firmware parses the `THUMBNAIL_BLOCK_START..END` block out
of the G-code, re-encodes it as a single base64 string, and
returns it in the `thumbnail` field. If the block is missing
(our CLI output): `error_code = 1015 ThumbnailNotExist`.

### Variants to make Handslice emit a thumbnail

| Approach | Where the render happens | Effort | Risks |
|---|---|---|---|
| **A — Headless renderer in the CLI** | Native C++ in `handslice-cli`, software rasterizer (no GL context on Android) over the loaded `Print` object; feed as `thumbnail_cb` into `export_gcode`. | high (6–10 d) — need our own triangle rasterizer; must avoid pulling in Orca's wx/GLFW GUI code (blocker from Block A). | risk of looking different from Orca's PNG; still cheaper than a full OpenGL offscreen pipeline. |
| **B — Flutter-side render + post-splice** | After CLI exits, Dart reads the G-code, renders the preview with the plate-view renderer (Pflicht 7), inserts the `THUMBNAIL_BLOCK` right after `HEADER_BLOCK_END`. | medium (2–3 d) — reuses whatever renderer we pick for Pflicht 7; splice is a text-level insert; no engine recompile. | depends on Pflicht 7 landing first; must respect the firmware's parser (base64 line length 78, exact markers). |
| C — GUI build with offscreen GL | reuse Orca's `GLCanvas3D::render_thumbnail_framebuffer`. | very high — needs wxWidgets + GLFW on Android, which Block A ruled out. | not an option. |

**Recommended path: B.** It avoids a second renderer, keeps the
engine CLI pure, and the splice is a well-understood text edit
(the firmware parser is a plain line-prefix matcher, not an MD5
check). The thumbnail block adds ~2 KB to the file — upload cost
is negligible. Depends on Pflicht 7 landing a working preview
renderer first; that is the right order anyway.

## Teil B — plate view (Pflicht 7)

### Flutter 3D packages (pub.dev survey)

Rendering a 140 MB STL ("Auryn", ~1.5–3 M triangles binary) at
interactive rates on a Snapdragon 860. Hard filters:
F-Droid-safe (no `<model-viewer>`/Google-CDN WebView, no AAR
blobs of unknown provenance), AGPL-3.0 compatible license,
STL binary support, maintained within the last 12 months.

| Package | Last release | License | Rendering | STL? | F-Droid? | Verdict |
|---|---|---|---|---|---|---|
| **three_js** (Knightro63) | 0.3.0 pub 2026-04, commit 2026-09 (active) | MIT | ANGLE on mobile, WebGL2 on web, Flutter GPU in progress | yes (`three_js_simple_loaders` STLLoader, ASCII + binary) | yes — ANGLE is BSD, no Google deps | **primary candidate** |
| flutter_scene (bdero) | 0.24.3 ~2026-10 (very active) | MIT | pure Flutter GPU/Impeller | no (own `MeshGeometry` only) | yes | strong fallback / DIY backbone |
| flutter_cube (zesage) | 0.1.1 last commit 2021-03 (stale) | Apache-2.0 | pure Dart `Canvas.drawVertices` | no (OBJ only) | yes | useful as a code sketch, not a dep |
| flutter_3d_controller | 2.3.0 2025-09 | MIT | WebView + Google `<model-viewer>` | no (GLB/glTF/OBJ) | **no** | drop |
| model_viewer_plus | 1.10.0 2025-11 | Apache-2.0 | WebView + bundled model-viewer.min.js | no | grenzwertig — AR features pull Play Services | drop |
| babylonjs_viewer | 1.3.0 2024-04 (stale) | MIT | WebView + BabylonJS | no | **no** — Babylon samples load from CDN | drop |
| flutter_gl, flgl, three_dart | 2021 (stale) | MIT | OpenGL via `.aar` blobs or platform channels | varies | **no** — blobs or dead | drop |
| three_d_viewer, ply_viewer | 2026-08 | MIT | WebView + Three.js | yes | **no** (WebView) | drop |
| DIY: `Canvas.drawVertices` | — | — | pure Dart (Skia/Impeller software) | self-parse | yes | baseline for thumbnails & small previews only |

**Recommendation: `three_js` (Knightro63).** Only actively
maintained package (September 2026 commit) with a real binary
STL loader, no WebView, no Google deps, MIT. For the Auryn case
the mesh must be decimated before the GPU anyway — target
200–500 k triangles via quadric decimation. The same scenegraph
can be driven headlessly for Pflicht 6, so we need only one 3D
code path. Fallback if `three_js` crashes reproducibly on the
Poco: `flutter_scene` + own STL→`MeshGeometry` loader — but
only after a concrete device benchmark, not speculatively.

### Layer preview — where the per-layer polylines come from

- Our reference G-code (cube, 100 layers) is 205 kB with 5 960
  G0/G1 moves — tiny. The Auryn or any large print will have
  **millions** of G0/G1 lines, so naive parsing on the phone is
  memory-bound.
- Option **G-code parser in Dart** — simple state machine
  tracking (X, Y, Z, E), detecting extrusion on positive E
  delta, grouping polylines by Z. Fast to write (1–2 d), tiny
  code. Memory: ~2.5–3× G-code size as float32 polylines (so a
  220-KB test file → ~600 KB in RAM, OK; an 87-MB project
  file → 250+ MB in RAM, **not OK on the phone**).
- Option **CLI exports a binary layer file** — new CLI flag
  `--layer-preview out.bin` that writes a packed per-layer
  structure (uint32 layer-count, uint32 polyline-count-per-layer,
  int16 X/Y pairs scaled to printable area). The 20-mm cube
  comes out at ~24 KB; the Auryn at a few MB. Effort medium
  (2–3 d in C++), uses the already-loaded `GCode` extrusion
  path objects.
- **Recommendation**: start with the Dart parser (shortest
  path, OK for M1–M8 test files), *and* measure. The CLI
  exporter only becomes necessary once Klaus prints something
  that exceeds 500 kB of polyline memory per layer; defer it
  until that is actually hit.

### Arrange / rotate / scale — what libslic3r already provides

From `engine/OrcaSlicer/src/libslic3r/`:

- `ModelObject::rotate(angle, Axis)` and `rotate(angle, Vec3d)`
  (`Model.hpp:502..503`, `:939..940`).
- `ModelInstance::rotate/scale/translate` on the instance.
- `ModelObject::ensure_on_bed(bool allow_negative_z)`
  (`Model.hpp:489`) — drop-to-bed.
- Arrange is a full subsystem: `src/libslic3r/Arrange.hpp` /
  `src/libslic3r/arrange/` with `arrange()` and
  `ArrangeParams`. Operates on `ArrangePolygon`s derived from
  model instances.
- Bounds check: `Print::has_skirt()`-adjacent utilities,
  `BoundingBox` methods on `ModelObject`.

**App work** (not libslic3r):

- Gestures (pan/rotate/pinch) to drive `ModelInstance`
  transforms live.
- Selection UI (which object is active).
- Visual gizmos (rotation handles, scale sliders).

**CLI work:**

- Expose two new switches:
  - `--arrange` (apply `arrange()` across all loaded instances
    before slicing).
  - `--transforms <json>` (array of per-instance `{rotate_xyz,
    translate_xy, scale, drop_to_bed}` ops, applied before
    bounds check and before slicing).
- Both are mechanical additions on top of our existing
  `handslice-cli`; the libslic3r calls themselves are already
  linked in. Effort low–medium (2–3 d incl. tests).

### Grobaufwand pro Teil (Range, nicht Angebot)

| Teil | Range | Haupt-Risiko |
|---|---|---|
| Pflicht 6 — Thumbnail-Splice (Variant B) | 2–3 Tage | abhängig von Pflicht 7, Format-Edgecases (CRLF, Base64-Padding) |
| Pflicht 7a — 3D-Plattenansicht (`three_js` + STL-Decimation) | 5–8 Tage | 140-MB-STL im Decimator; `three_js`-Stabilität auf Snapdragon 860 |
| Pflicht 7b — Schichtvorschau (Dart-Parser v1) | 2 Tage | Memory beim nächsten Groß-Projekt (dann 7b-v2 mit CLI-Export) |
| Pflicht 7c — Anordnen/Drehen/Skalieren (CLI + UI) | 3–4 Tage | Gizmo-UI auf dem Touchscreen; Multi-Object-Edge-Cases |

### Risiken, kompakt

- **`three_js`-Stabilität auf dem Poco.** Open-Issues zu
  Android-Crashes (RGBE/Morphtargets). Risiko: Umstieg auf
  `flutter_scene` kostet zusätzlich 3–5 Tage. **Mitigation**:
  benchmark-first — frühe Device-Probe mit einem 500-kB-STL
  und einem 50-MB-STL, bevor Features drangebaut werden.
- **STL-Decimation.** Keine fertige Dart-Library gefunden;
  müsste selbst (QEM) oder serverseitig im CLI implementiert
  werden. **Mitigation**: Decimation ist das Thema, nicht die
  Rendering-Library — ein 50-k-Dreieck-Preview reicht auf jeder
  Plattform. Dart-Port in 1–2 Tagen, oder in die CLI
  verlagern (dort gibt es schon Mesh-Processing-Code).
- **Thumbnail-Deterministik.** Wenn Variant B einen anderen
  PNG-Hash erzeugt als Orcas Export, verlieren wir Byte-
  Gleichheit zum GUI-Export (ist aktuell nur im Executable-
  Block gefordert, nicht im Thumbnail — unproblematisch, aber
  dokumentieren).
- **Flutter GPU/Impeller-Reife.** `flutter_scene` ist noch
  bewegliches Ziel, `three_js` plant Umstieg auf Flutter GPU.
  **Mitigation**: nicht die neueste `-dev`-Version pinnen,
  Minor-Updates manuell nachziehen.

---

## Follow-up: three questions before we commit (2026-10-31)

### 1. Thumbnail Variant C — CLI-side software rasterizer

Weighed against Variant B (Flutter renders, Dart splices the
`THUMBNAIL_BLOCK` into the G-code before upload):

| | **Variant B** (Dart splice) | **Variant C** (CLI rasterizer) |
|---|---|---|
| Effort | 2–3 d | **4–6 d** (≈300–400 LOC C++ rasterizer + libpng + base64 + `thumbnail_cb` wiring) |
| Depends on Pflicht 7 | **yes** — needs the 3D renderer to exist | **no** — ships independently |
| Testable | only through the app | **yes** — compare x86 CLI output byte-for-byte against the GUI reference PNG, deterministic in CI |
| Who writes the block | Dart text-splice (own code path) | Orca's own `export_thumbnails_to_file` — identical formatting, no splice edge-cases |
| Visual quality | matches whatever we build for Pflicht 7 | flat-shaded, same style as Orca's own thumbnails (which are also flat; the Elegoo reference uses a 144×144 PNG with simple directional light) |
| Reusable | only for thumbnails | rasterizer could later back a CPU preview inside the app (e.g. while a Flutter GPU scenegraph warms up or fails) |

Risk comparison: B chains two risks (3D-package choice + splice
format precision); C isolates a single risk (rasterizer
quality), and that risk is testable without the device.

Given the F-Droid blocker on `three_js` (see Q2 below) which
pushes the Flutter-side renderer onto the less mature
`flutter_scene`, **Variant C becomes the lower-risk choice**:
thumbnails don't block on an evolving GPU API, and the
C++ renderer is end-to-end testable on CI.

**Updated recommendation: Variant C.** Keep B as a fallback
only if the Pflicht-7 renderer ships before we get to Pflicht 6.

### 2. three_js vs. flutter_scene — F-Droid-eligibility

- **`three_js` is NOT F-Droid-eligible as published.** It
  depends on `three_js_angle_renderer ^0.0.1` →
  `flutter_angle ^0.4.0`, whose Android backend consists of
  committed prebuilt blobs
  (`libEGL_angle.so` ≈ 308 kB, `libGLESv2_angle.so` ≈ 6.1 MB
  under `android/src/release/jniLibs/arm64-v8a/`). No
  CMake/build.gradle hook rebuilds ANGLE from source during
  `flutter build`; the thin JNI wrapper links against the
  committed `.so`s. F-Droid's inclusion policy rejects
  prebuilt native libraries, so `three_js` would need a
  Handslice-specific `flutter_angle` fork that builds ANGLE
  from source — a substantial side-project, not a one-day fix.
- **`flutter_scene` is on Flutter-GPU, which our Flutter
  3.47.8 does carry.** The package pins `flutter: ">=3.47.0"`
  explicitly; our installed `3.47.8 stable` meets that. BUT
  two caveats:
  - `flutter_scene` is 0.24.3 (pre-1.0, documents that minor
    releases may break APIs).
  - `package:flutter_gpu` is a Flutter-SDK stub and is still
    labelled "early preview, no API stability guarantee" in
    the engine docs. Impeller must be on; it already is on
    Android API ≥ 29 (our `minSdk` = 29).

**Consequence.** `three_js` drops from the shortlist for
Handslice. **New primary 3D path for Pflicht 7a is
`flutter_scene`**, with a known reservation that we pin an
exact minor version and read the changelog before each bump.
Fallback stack: **DIY Dart `Canvas.drawVertices`** for the
baseline/thumbnail preview path (also the rasterizer from
Variant C above is reusable here as a server-side preview
renderer for huge meshes).

### 3. libslic3r already has Quadric Edge Collapse

Fundstellen:

- `engine/OrcaSlicer/src/libslic3r/QuadricEdgeCollapse.hpp`
- `engine/OrcaSlicer/src/libslic3r/QuadricEdgeCollapse.cpp`,
  public entry at line 160:
  `void Slic3r::its_quadric_edge_collapse(
      indexed_triangle_set &its,
      uint32_t target_triangle_count,
      float *max_error = nullptr,
      ThrowOnCancel throw_on_cancel = nullptr,
      StatusFn status_fn = nullptr);`

Called by Orca's "Simplify model" GUI action. Operates in-place
on an `indexed_triangle_set`.

**Consequence for the plan.** Dart-side decimator is **dropped**.
Add a CLI switch `--simplify <target_triangles>` (optionally
`--simplify-max-error <float>`) to `handslice-cli`, which:

1. Loads the STL/3MF as today.
2. If `--simplify` present: runs
   `its_quadric_edge_collapse(its, target, &max_err)` on each
   object's mesh before `arrange_objects()`/slicing.
3. (For Pflicht 7a) can also run **once** at a smaller target
   (e.g. 50 000 triangles) and dump the decimated STL to a
   side-car file for the plate-view renderer.

Effort: **1–2 d** — flag parsing, mesh-iteration, output
sidecar. The algorithm itself is already linked into our CLI
through libslic3r.

### Revised effort + risk summary

| Teil | Vorher | **Jetzt** | Grund |
|---|---|---|---|
| Pflicht 6 Thumbnail | 2–3 d (B) | **4–6 d (C)** | eigenständig, testbar, F-Droid-neutral |
| Pflicht 7a 3D-Plattenansicht | 5–8 d (`three_js`) | **6–10 d (`flutter_scene`)** | `three_js` fällt aus, `flutter_scene` ist weniger reif |
| Pflicht 7b Schichtvorschau | 2 d (Dart v1) | 2 d — unverändert | |
| Pflicht 7c Arrange + Gizmos | 3–4 d | 3–4 d — unverändert | |
| **Decimation (Pre-Pflicht-7a)** | war Dart-Port 1–2 d | **CLI `--simplify` 1–2 d** | libslic3r hat QuadricEdgeCollapse schon |

Net-net: Pflicht 6 wird robuster (keine Pflicht-7-Kopplung),
Pflicht 7a wird vorsichtiger geplant (API-Instabilität von
`flutter_scene`), Decimation ist jetzt billig gelöst.
