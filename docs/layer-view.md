# Layer preview — Pflicht 7b / 7c / 7d

Pflicht 7c (2026-11-01): the authoritative data path is now the
CLI's HSPT binary produced by `handslice-cli --export-toolpaths`.
The Dart g-code parser documented below stays as a fallback for
files that do not come with an HSPT sidecar.

Pflicht 7d (2026-11-01): the HSPT format bumps to carry
per-move time (needed for the legend's time column and the
"Total estimation" footer) and the per-filament density /
diameter in the header (needed to turn extruded millimetres
into grams). The parser rejects older versions with a clear
error so a stale sidecar surfaces immediately rather than
silently reading garbage.

Pflicht 7d follow-up 8 (2026-11-01): v3 appends Orca's own
"Total Filament" totals (length + weight) to the header so
the layer-view legend and the project card both read Orca's
GUI number from the same two floats — no second accumulator
pass on the Dart side.

## HSPT — handslice toolpaths binary (v3)

Dumped by `handslice-cli --export-toolpaths <path>` either as a
byproduct of slicing or in `--input-gcode <path>` mode (which
runs `GCodeProcessor::process_file()` on an existing .gcode and
exits without slicing). The density / diameter come from
`GCodeProcessorResult::filament_densities[0]` and
`.filament_diameters[0]`, which `process_file` populates from
the g-code's config block (`filament_density`,
`filament_diameter`), so a sidecar written by `--input-gcode`
matches a slice-time sidecar.

The `total_filament_mm` + `total_weight_g` header fields come
from Orca's `print_statistics` (Path B — see
`OrcaSlicer/src/libslic3r/GCode.cpp:1914-1936`), the same
numbers Orca's GUI puts on its "Total Filament" line at
`GCodeViewer.cpp:4605`. For `--input-gcode` sidecars no `Print`
object exists, so the CLI writes the HSPT-dE sum (equal to the
g-code footer `; filament used [mm]`) and a weight derived
from the HSPT's density/diameter as a fallback.

```
Header (32 B, little-endian):
  magic             "HSPT"               4 B
  version           u32 = 3              4 B
  flags             u32 = 0 (reserved)   4 B
  n_moves           u32                  4 B
  density_g_cm3     f32 (filament 0)     4 B
  diameter_mm       f32 (filament 0)     4 B
  total_filament_mm f32 (Orca Path B)    4 B
  total_weight_g    f32 (Orca Path B)    4 B

Per-move record (32 B each, little-endian):
  u8  role            libslic3r::ExtrusionRole code (0..19)
  u8  extruder        0..255
  u8  move_type       libslic3r::EMoveType code    (0..10)
  u8  pad             0
  u16 layer_id        0..65535
  u16 width_x100      extrusion width in 0.01-mm units
  u16 height_x100     extrusion height in 0.01-mm units
  u16 feedrate_mm_s   0..65535
  f32 x, y, z         mm
  f32 delta_extruder  mm, signed (per-move E delta)
  f32 time_s          MoveVertex::time[Normal] in seconds;
                      sum across moves == Orca's "Total time"
```

At 32 B/move an `auryn-x86`-sized print (~2.4 M moves) weighs
≈ 77 MB on disk — ~15 % larger than the v1 artefact and still
roughly the size of the source g-code. The Dart side reads it
as one Uint8/Float32 view without parsing text.

Fields we deliberately drop today: `fan_speed`, `temperature`,
`pressure_advance`, `acceleration`, `jerk`, `layer_duration`,
`actual_feedrate`, `mm3_per_mm`, `gcode_id`. None of them are
consumed by the Dart viewer yet; adding one is a header-flag
+ record-size bump.

### Layer Z and the per-bin reference height

Orca emits `;LAYER_CHANGE` BEFORE the preceding layer's final
retract, so the first record in each HSPT bin is a retract or
travel still sitting at the previous layer's Z — e.g. z=10.2 mm
for bin 51 whose extrude moves live at z=10.4 mm. The parser
mirrors `libvgcode::Layers::update`: it initialises each bin's
`layerZ` to the first move's z and then overwrites it with
every non-custom, non-skirt/brim/wipe-tower extrude's z. That
way the slider's "Z = X.XX mm" label matches Orca's layer
label — on the thumbnail cube, bin 51 reads z=10.40 mm and the
UI displays "Layer 52 of 100 · Z = 10.40 mm", same as the
reference screenshot in `local-test/orca-referenz-schicht52.png`.

### Print bounding box

`minX..maxZ` is computed over every extrude move (incl. skirt,
brim, wipe tower, custom g-code). It drives the orbit camera's
framing so the viewport does not clip the brim or the start-
g-code purge line.

The 7d-era object-only AABB (`objMinX..objMaxZ`) was only ever
used by the model-outline wireframe; both the wireframe and
the AABB were removed in 7d follow-up 6 (see "What's above the
slider" below).

### Internal-only move filter

Orca's `GCodeProcessor::calculate_time` inserts a parallel
"actual speed" clone next to every real move. The clone
carries the same role / layer_id / position as the real move
but with `internal_only = true` and `actual_feedrate` set to
the per-block acceleration-adjusted speed; it exists so
Orca's `ActualSpeed` colour mode can show the two speeds side
by side. Reference:
`OrcaSlicer/src/libslic3r/GCode/GCodeProcessor.cpp:5962-5984`
(the `insert actual speed moves into the move list` block
with `new_move.internal_only = true` at :5983).

We do not implement `ActualSpeed`, so each clone would be a
duplicate vertex at the same position with cloned
`delta_extruder` — summing them would triple the extrusion
total and crowd the viewer with overlapping segments.
`handslice-cli.cpp:552-564` drops them at HSPT write time.

Orca itself also hides them from the statistics it shows in
the Line-Type legend: `OrcaSlicer/src/slic3r/GUI/GCodeViewer
.cpp:1318-1320` early-outs on `move.internal_only` before
updating `m_move_type_counts/_times/_distances`. The
`libvgcode` renderer does include them in the vertex buffer
(no explicit filter in `LibVGCodeWrapper.cpp:191-260`) so the
`ActualSpeed` view can colour them differently; for the
Line-Type legend they are invisible on both sides.

The Auryn example: 3 763 559 total moves → 2 113 471 drawn,
1 650 088 (~44 %) dropped as internal-only. Ratio
depends on how much acceleration-shaped motion the slice
contains.

### Self-check against the g-code footer

On the thumbnail-cube test fixture Orca writes
`; filament used [mm] = 1177.15` in the g-code footer. After
dropping internal-only moves the HSPT's summed positive
`delta_extruder` lands at ~1356 mm — about 15 % higher. The gap
comes from start-g-code purge extrusions (`G1 X87 E20` + prime
lines) and the end-print retract that Orca excludes from the
footer. For the UI the role mapping is what matters; the number
is reported but no test fails on it.

The Dart g-code parser (used only as a fallback) is held to the
tighter 1 % tolerance because it reads the exact text and does
no post-processing. See `app/test/gcode_parser_test.dart`.

### Palette

Dart constants in `app/lib/engine/toolpath_parser.dart`
(`OrcaPalette.roleColor`, `.moveColor`) are a direct port of
`OrcaSlicer/src/libvgcode/src/ViewerImpl.cpp:283-317`
(`DEFAULT_EXTRUSION_ROLES_COLORS` and `DEFAULT_OPTIONS_COLORS`).
The role-order follows libslic3r's `ExtrusionRole` enum
(ExtrusionEntity.hpp:20), which is what the HSPT byte carries.
Default visibilities (`OrcaDefaults.visibleRoles`,
`.visibleMoveOptions`) match `libvgcode/src/Settings.hpp:33-71`
— every extrusion role on, travel / wipe / retract / unretract
/ tool-change / colour-change / pause / custom-g-code off,
seams on.

### Rendering notes

flutter_scene's `LineSegmentsGeometry` takes a single
`width` per instance. We bucket by role and feed each
`LineSegmentsGeometry` the width of the first extruding move
of that role (which matches Orca's `;WIDTH:` comment). Per-
move width AND height ribbons that change thickness mid-path
need a custom shader and are queued for 7d.

Important material setting: `UnlitMaterial.displayReferred =
true`. Without it Impeller treats `baseColorFactor` as linear
radiance and gamma-corrects the sRGB palette constants a second
time, which pushed orange walls into peach on the first on-
device run (Klaus, 2026-11-01).

### What's above the slider: nothing

Layers below the slider draw at their full Orca palette value
— no stacked dimming. Above the slider we draw **nothing** —
no shadow, no outline, no wireframe. "What has been printed
so far" is the entire question the preview answers; users
who want to see the finished model drag the slider to the
top.

This is a Klaus decision after three iterations tried to
land a hint above the slider:

- **7d follow-up 1** drew a dark-cyan AABB wireframe
  default-on. Opaque enough to swallow the top of the
  current layer; Klaus rejected it ("fast undurchsichtig und
  dunkel-türkis").
- **7d follow-up 2** switched to a light-grey wireframe
  default-off behind a "Model outline" option. The dozens
  of visible edges still read as "unruhig" on a 393-dp Poco
  screen even when the user actively turned them on.
- **7d follow-up 6** (this one) removes the feature entirely:
  code, l10n, tests. The parser's object-only AABB
  (`objMinX..objMaxZ` + `_isObjectRole`) go away with it
  since they had no other consumer.

The 7e-backlog item "**alpha-translucent model mesh above the
slider**" is **abandoned** on the same grounds. Orca's shell
is a real alpha-blended STL mesh (`GCodeViewer.cpp:240`
`m_model.set_color({1,1,1,0.5})`, final alpha 0.2 via
`GLCanvas3D.hpp:1017`); on a desktop with a 2× bigger
viewport it reads as a faint white glass hint. On a 393-dp
phone the same mesh would occupy the dominant part of the
viewport and compete with the printed layers for attention
— the same problem the wireframe iterations had. Not worth
the custom-shader cost
(`flutter_scene`'s `UnlitMaterial` does not expose a public
blend-mode hook).

### Scene reset — use `removeAll()`, never `.clear()` on the list

flutter_scene's `Node.children` is a plain `List<Node>`.
Mutating it directly (`.clear()`, `.removeAt(i)`) does **not**
run the unmount path: the node stays registered in
`renderScene._renderItems` and the renderer keeps drawing it.
On a slider change you then stack the new layer on top of
the previous one — Klaus (b23e962 device run) saw the full
cube plus the bright-red top-surface infill at Layer 52 for
exactly this reason, even though
`maxLayerIdIn(0, layerEnd(51)) ≤ 51` holds in the parser.

The fix is to call `scene.root.removeAll()`, which in turn
calls `remove(child)` on every child (`flutter_scene/.../
src/node.dart:1355-1358`). `remove` is the API that unmounts
the child from the renderer (`node.dart:1341-1352`:
`child._unmount()`). We ban the direct `.clear()` call in all
four of our scene-owning widgets:

- `widgets/toolpath_layer_view.dart` → the HSPT-backed Layer
  preview that regressed.
- `widgets/layer_view.dart` → fallback Dart-g-code preview.
- `widgets/plate_view.dart` → Project tab's Model view.
- `screens/plate_bench_screen.dart` → the plate-view
  benchmark.

Three guards keep the regression from coming back:

- `scene emit: positions handed to the renderer at Layer
  1/52/100 obey the slider` in `toolpath_parser_test.dart`
  — pins the exact `Float32List` `_emitRole` hands to
  `LineSegmentsGeometry` for each role. For every role it
  enforces `maxZ(seg) ≤ layerZ[current0] + 0.01` and, at
  Layer 52, that `topSolidInfill` (`0xFFF04040`) emits zero
  segments.
- `no .root.children.clear( in lib — must use .root
  .removeAll() instead` in `scene_lifecycle_test.dart` — a
  grep guard against the pattern coming back. The runtime
  "nodes-in-scene after 100 → 1 → 52 → 100 → 52 equals a
  cold build at 52" check needs Impeller, which flutter_test
  does not ship; the grep is the strongest CI-level guard
  we can mount.
- `buildRoleSegments is idempotent across the Klaus-named
  slider sequence` in `scene_lifecycle_test.dart` — walks
  Klaus' 100 → 1 → 52 → 100 → 52 order and asserts the
  Float32List returned at the final Layer 52 is
  byte-identical to a cold build at Layer 52. Proves the
  data path (`_emitRole`'s source of truth) has no
  accumulation.

The view's `_emitRole` is a thin shim around the pure helper
`buildRoleSegments(Toolpaths, roleCode, from, to)` in
`toolpath_parser.dart`, so the test exercises the exact code
path the renderer uses — not a reimplementation that could
drift.

### What is drawn vs skipped at each slider position

The `_rebuildScene` loop clamps records to
`[0, t.layerEnd(current))` — every move with
`layer_id ≤ current` is drawn, every move above it is
dropped. On the thumbnail cube at Orca Layer 52 (0-indexed
bin 51) the HSPT splits cleanly: **2674 moves drawn (1626
extrudes), 2800 moves skipped**. Pinned by
`toolpath_parser_test.dart` → `Layer 52 draws only moves
with layer_id ≤ 51 (never above the slider)` so a regression
that lets upper-layer extrudes leak into the frame fails CI
instead of showing up as a visual bug.

### The "red top area" at Layer 52

When Klaus asked whether the dark-red mass visible at the
top of the device screenshot comes from a layer above the
slider, the answer is **no** — it is the current layer's
`internalInfill` role painted in Orca's dark red
`0xFFB03029`. At Orca Layer 52 the drawn set contains:

| Role | Count (layers 0..51) | Notes |
|------|----------------------|-------|
| `internalInfill` (role 4, red 0xFFB03029) | **833** | 17 of them at `z=10.40` mm, the current layer. |
| `solidInfill` (role 5) | 270 | |
| `perimeter` + `externalPerimeter` | 208 + 208 | |
| `bottomSurface` (role 7) | 105 | first few layers only. |
| `topSolidInfill` (role 6, bright red 0xFFF04040) | **0** | not yet printed — only arrives near Layer 100. |

Perspective makes the current layer's infill fill the top
quarter of the oblique viewport; because the role is
`internalInfill` the colour is Orca's dark red. Pinned by
`at Layer 52 the dominant drawn role is internalInfill
(red)`.

### 2D top-down fit

Per-layer object bbox (new `layerXyBounds(Toolpaths, from, to)`
helper), not the whole-print bbox. Brim / skirt / purge lines
would otherwise inflate the bbox and shrink the model to a
corner. Pinch-zoom and single-finger pan both live on a
`Listener` so the outer `ListView` scroll never steals the
gesture.

### Plate label overlay

Both the Model and Layer view wrap their viewport in a tiny
"A · Textured — 256×256×256 mm³" chip in the top-left corner.
The chip is rendered as an `IgnorePointer` so it never eats
touch events. Pflicht 7d: Klaus asked for the label in both
tabs after the device test on 04684c0 showed it was only in
the Layer tab.

### Bed grid

`addBedToScene` (shared between PlateView and
ToolpathLayerView) now draws two sets of unlit lines at
z ≈ 0.03 mm above the quad: minor lines every 10 mm in a cool
grey, major lines every 50 mm (0, 50, …, 250) in a brighter
grey. Line width is 0.08 mm, enough to show but thin enough
not to fight the extrusions.

### Legend table

Columns: toggle (eye icon), swatch, name, time, %, length,
weight. Only roles with ≥ 0.05 mm of extruded filament
appear so a plain cube does not drag the full 20-row palette
into view (mirrors Orca's `Viewer::get_extrusion_roles()`
which lists only roles present in the current print).

| Column | Roles                                | Options (travel/wipe/retract/unretract/seam) | Orca ref |
|--------|--------------------------------------|----------------------------------------------|----------|
| Time   | `timeByRole[r]` (extrude-only)       | `timeByMove[m]`                              | `GCodeViewer.cpp:3410-3418` + `:3798` |
| %      | `timeByRole[r] / totalTimeSec`       | `timeByMove[m] / totalTimeSec`               | `GCodeViewer.cpp:3412` + `:3804` |
| Length | `extrudedByRole[r] / 1000` (filament metres) | `distanceByMove[m] / 1000` (path metres) | `GCodeViewer.cpp:3432-3448` + `:3806` |
| Weight | `gramsFromExtrudedMm(extrudedByRole[r])` | — (Orca hides it)                        | `GCodeViewer.cpp:3443-3448` |

Three semantic calls worth highlighting, because Klaus caught
each one on the 66e7c46 device run:

- **Percent is by TIME, not by length.** Orca's
  `role_time_and_percent` returns `time / total_estimated_time`
  (`GCodeViewer.cpp:3412`). On the thumbnail cube the inner-
  wall row is 94.7 s / 561 s ≈ 16.9 %, which matches the
  reference screenshot. The length-based percentage we had on
  7d would have shown ≈ 20.5 % instead.
- **Length for roles is filament metres, not path metres.**
  `used_filament_per_role` in `GCodeViewer.cpp:3432-3440`
  returns the extruded filament length (= `role_cache /
  (π·r²) · 0.001`, `GCodeProcessor.cpp:1626-1628`). For the
  cube that is 1.17 m total; the sum of path lengths is
  36 m and would wildly disagree with Orca's "1.17 m" footer.
  Dart simply divides `extrudedByRole[r]` by 1000.
- **Role times are extrude-only.** `timeByRole` is populated
  only when `moveCode == Extrude`; travels / retracts /
  wipes drop into `timeByMove`. Without that filter the
  per-role totals already equal 9m25s on their own and the
  Travel row then pushes the sum to ~11 min. Orca's
  `get_extrusion_role_estimated_time` is extrude-only for
  the same reason.

Below the role table a "Total estimation" box carries two
rows:

- `Total Filament` = `extrudedMm / 1000` m · gramsFromExtruded
  Mm(extrudedMm) g. On the cube that is 1.17 m · 3.52 g,
  matching the reference image exactly.
- `Total time` = `totalTimeSec`, formatted `9m25s` /
  `1h12m` / `35s`.

### No hard upper layer limit

The HSPT wire format pins `layer_id` to `u16` (`handslice-cli
.cpp:514, :582` — Orca already clamps to 65535 when writing).
The Dart side has no fixed-size state: `layerStarts` is a
`Uint32List`, `layerZ` a `Float32List`, both grown to
`t.layerCount` at parse time. The slider's `divisions`
property scales to the layer count. The only sanity cap in
the view is `(t.layerCount - 1).clamp(0, 1 << 30)` — ~1 B,
3 orders of magnitude above the HSPT's hard limit.

Verified on two prints with the same test code:

| Model          | Layers | HSPT size | Moves (extrude) | Total time | Load (Pixel-shaped laptop) |
|----------------|--------|-----------|-----------------|------------|----------------------------|
| Thumbnail cube | 100    | 170 KB    | 3300 (1680)     | 9m 25s     | < 10 ms                     |
| Auryn x86      | 1045   | 67 MB     | 2.11 M (?)      | 7h 11m 23s | ~ 400 ms (isolate)          |

The sweep tests `EVERY slider position …` run on both: the
Dart `layerZ[N-1]` matches the g-code `;LAYER_CHANGE`+`;Z:`
ground truth within 0.001 mm for every slider position
1..1045 on Auryn and 1..100 on the cube. The record-stream
cutoff invariant (nothing with `layer_id > current` below
the cutoff, nothing with `layer_id ≤ current` above) holds
for every slider position too. The 2.1 M-record sweep uses
`prefixMax`/`suffixMin` tables so the inner check is O(1)
and the whole test finishes in well under a second.

**Slider ± 1** navigates every individual layer: pinned by
`layerStarts strictly monotonic`, which asserts
`layerStart[i+1] > layerStart[i]` for every bin. If two
adjacent bins ever had the same start index the IconButton
`+` tap could not resolve them individually; the test
guards against that regression on both the cube and Auryn.

#### Compact mobile layout

The whole table is designed to fit a 393-dp Poco X3 Pro
portrait viewport without any column breaking to a second
line or the name ellipsising German role labels like
"Innenwand" / "Außenwand". Numbers are rendered at 11-pt
monospace with no space between number and unit (`0.07m`,
`0.21g`) — matches Orca's `GCodeViewer.cpp:3653-3655`
("%.2fm", "%.2fg" via `format_compact_weight`). Fixed widths
sum to 194 dp (14 eye + 14 swatch + 40 time + 32 % + 50
length + 44 weight), leaving ≈ 150 dp for the name column
under the project card's 32-dp horizontal padding.

---

# Layer preview — Pflicht 7b (fallback path)

Status: on-device numbers pending Klaus' Poco run. Report in
English per the current project-language rule.

## What this covers

After `handslice-cli` finishes slicing a project, the Project tab
now carries a layer preview next to the plate-view model. The user
scrubs through layers with a slider (or `± 1` buttons); every layer
up to the slider's position is drawn in 3D (flutter_scene
`LineSegmentsGeometry`), and the current layer is tinted brighter
so the eye can follow the slider. The viewer honours the same
camera/orbit/pan/pinch controls as the model view, plus the
standard "Reset / Top / Front / Oblique" preset buttons.

Travel moves are parsed but hidden by default — the user has a
chip-based legend of path types and can toggle each one on or off.
A `3D / 2D top-down` segmented control switches to a pure-Dart
`CustomPaint` renderer that draws only the current layer; use it
when the GPU-line path is too heavy on a very large print.

A `By type / By filament` legend toggle is wired up for later; the
by-filament colouring arrives with the multi-filament scope. In
7b the segmented control is a visible placeholder — flipping it
has no effect on the colour mapping yet.

## Parser

`app/lib/engine/gcode_parser.dart` walks the g-code line by line
in a background isolate (`parseGcode`). We only react to:

- `G0` / `G1` with `X` / `Y` / `Z` / `E`. New Z (strictly larger)
  starts a new layer.
- `;TYPE:<name>` comments; names mapped to a 14-value byte
  enumeration (`PathType`) that we also persist in the compact
  result. Covers Orca's current emission (Outer wall, Inner wall,
  Overhang wall, Sparse / Internal / Gap / Solid infill, Top /
  Bottom surface, Bridge, Internal Bridge, Support, Support
  interface, Skirt, Brim, Prime tower, Custom); anything unknown
  bucketed as `PathType.unknown` (not seen in Auryn so far).
- `T<idx>` tool changes update the filament index tagged onto
  subsequent segments.

The result (`GcodeGeometry`) is three parallel typed arrays:

- `positions: Float32List` — 6 floats per segment (start xyz +
  end xyz).
- `types: Uint8List`     — one byte per segment (`PathType.code`).
- `filaments: Uint8List` — one byte per segment.
- `layers: Uint32List`   — segment index at which each layer
  starts.

Backup fields `minZ`, `maxZ`, `minXY`, `maxXY`, `extrudedMm` are
computed as a free side-effect of the parse. No per-segment Dart
object: a 64 MB g-code with ~2 M segments weighs in at about
50 MB of positions + 2 MB of types/filaments, held in two
`TypedData` buffers.

Progress is reported every 1 MB via a `GcodeProgress` message;
the Project screen renders a one-liner (`N %, M segments, L
layers`) while the parse runs.

## Rendering

For every visible path type the layer view builds a single
`LineSegmentsGeometry` holding all segments from layer 0 up to
`current - 1` (dim), and a second geometry for the current layer
(bright). Toggling a path type in the legend simply drops its two
nodes from the scene. Changing the slider rebuilds the scene (one
Float32 copy per visible type per update, well under 100 ms on an
x86 host for the Auryn-sized print; Poco numbers pending).

The 2D fallback is a `CustomPaint` that iterates the segment
range of the current layer only. No projection beyond the
orthographic top-down map; no fancy shading. Pure Dart, zero GPU.
Automatically used when `Scene.initializeStaticResources()` fails
(e.g. on a device that still refuses Flutter GPU).

## Path-type palette

Chosen to read against the dark workshop background and stay
distinguishable in grayscale previews. The current-layer tint
uses the base colour; stacked below-layer segments drop to
roughly 55% brightness.

| Code | Type              | Base colour |
|------|-------------------|-------------|
| 0    | Travel            | `#6B7280`   |
| 1    | Outer wall        | `#EF4444`   |
| 2    | Inner wall        | `#F59E0B`   |
| 3    | Infill            | `#FBBF24`   |
| 4    | Solid infill      | `#84CC16`   |
| 5    | Top surface       | `#22D3EE`   |
| 6    | Bottom surface    | `#14B8A6`   |
| 7    | Bridge            | `#EC4899`   |
| 8    | Support           | `#8B5CF6`   |
| 9    | Support interface | `#A78BFA`   |
| 10   | Skirt / brim      | `#60A5FA`   |
| 11   | Prime tower       | `#F472B6`   |
| 12   | Custom            | `#94A3B8`   |
| 13   | Unknown           | `#9CA3AF`   |

## Memory and performance notes

Reference numbers measured on the x86 host while the Poco run is
pending (benchmark results will land in `PROGRESS.md`):

- Auryn `local-test/auryn-x86.gcode`, 67.5 MB on disk, ~2.4 M
  `G1` lines, 4180 layers.
- `parseGcodeInline` finished in **2.8 s**, output 2.0 M segments
  (travels + extrusions), 46.6 MB `positions` + 1.9 MB `types`.

Rough per-triangle budget scales with triangle count the same way
the plate view does; the LOD-by-device-RAM table in
`docs/plate-view-benchmark.md` is a reasonable starting point for
when we need to coalesce short segments. For 7b we ship with no
coalescing; the stress test on the Poco will tell us whether we
need it.

### Fallback behaviour on tight memory

If the parse throws (OOM, I/O), the Project tab shows a lokal
error line and leaves the model view intact. If the 3D path
blows out, the user can switch to the 2D top-down renderer with
one tap; that path never allocates a `LineSegmentsGeometry` and
uses roughly `6 * current_layer_segments` floats per repaint
instead of all stacked layers.

## Pflicht 7e plan — toolpath pipes (tubes)

Status: **plan**, no code yet. Klaus set the goal: paths look
like Orca's — each move with its real width and height from the
slice, Orca's light and colours. The decision stands: port
Orca's own technique (libvgcode) to Dart / flutter_scene;
embedding `libvgcode` directly is off the table (OpenGL ES,
different render loop, big C++ surface we don't need).

### How Orca draws its pipes

Instanced template-mesh. One tiny generic "octahedral prism"
geometry, drawn once per segment via `glDrawArraysInstanced`.

- Template geometry — 8 vertices, 8 triangles — two spiky caps
  and four side faces. Vertex data is a packed byte array of
  indices 0..7.
  Ref: `OrcaSlicer/src/libvgcode/src/SegmentTemplate.cpp:18-27`
  (`VERTEX_DATA`), the ASCII diagram at :13-17.
- Draw call: `glDrawArraysInstanced(GL_TRIANGLES, 0, 24,
  count)`, where `count` is the number of currently visible
  segments.
  Ref: `OrcaSlicer/src/libvgcode/src/SegmentTemplate.cpp:72-83`.

Per-instance, the vertex shader fetches four pieces of data
from texture buffers:

1. `position_tex[id_a]` + `position_tex[id_a+1]` — the segment
   endpoints (3 floats each).
2. `height_width_angle_tex[id]` — a `vec4` carrying
   `(height, width, corner_angle, bias)` for the current
   endpoint.
3. `color_tex[id]` — one float encoding the segment's RGB
   colour.
4. `segment_index_tex[gl_InstanceID]` — the index into the
   position buffer for this instance.

Width, height and corner angle are what shape the tube:

- `line_dir = normalize(pos_b - pos_a)` → the segment's
  along-direction.
- `line_right_dir` and `line_up_dir` are built orthogonally.
- Each template vertex is offset by `width · line_right_dir`
  and `height · line_up_dir` relative to the segment endpoint.

Corner joins get a twist-fix: the angle between adjacent
segments is pre-computed on CPU and passed per-vertex via the
`angle` channel so the vertex shader can rotate the cap plane
to match the previous segment's cross-section. Prevents visible
kinks between consecutive extrudes.

Lighting is baked into the vertex shader (no separate fragment
pass):

- `ambient = 0.2`
- `emission = 0.15`
- `light_top_dir = (-0.457, 0.457, 0.762)`, diffuse 0.48,
  specular 0.075, shininess 20.
- `light_front_dir = (0.699, 0.140, 0.699)`, diffuse 0.12.

Ref: `OrcaSlicer/src/libvgcode/src/Shaders.hpp:13-48` for the
block, and the `main()` function at :49-110 for the per-vertex
positioning.

How width / height / direction feed in per move
(what Orca writes into the texture buffers):

- Extrudes: `height = v.height`, `width = v.width` from the
  g-code's `;WIDTH:` / `;HEIGHT:` comments (passed through the
  processor's `MoveVertex` as-is).
- Travels: `height = width = travels_radius` (fixed small
  radius so they read as thin threads).
- Wipes: same with `wipes_radius`.
- Options (Seam/Retract/Unretract/…): `bias = 0.1` so a tiny
  z-offset keeps them from z-fighting the extrudes.
- Corner angle: `atan2(prev × curr, prev · curr)` per vertex,
  signed.
Ref: `OrcaSlicer/src/libvgcode/src/ViewerImpl.cpp:954-981`
(`extract_pos_and_or_hwa`).

### HSPT sufficiency — no new format bump needed

Our v3 HSPT already carries everything the shader needs:

| libvgcode input | HSPT source | Record offset |
|-----------------|-------------|--------------|
| position (xyz)  | `x`/`y`/`z` floats | 12..24 |
| height / width  | `height_x100` / `width_x100` | 6..10 |
| colour          | `role` byte + `OrcaPalette.roleColor` | 0 |
| corner angle    | derived in Dart from prev/curr segment directions | — |
| per-type bias   | derived in Dart from `move_type` | — |

The width and height fields are already stored at 0.01-mm
resolution (`handslice-cli.cpp:567-572` writes
`clamp16(m.width · 100)` and `clamp16(m.height · 100)`), which
is the same precision Orca uses in its textures. **No HSPT
version bump for the pipes work.**

### flutter_scene fit

flutter_scene 0.24.3 (what we're on) has the two pieces we
need:

- **Instanced meshes**: `InstancedMesh` + `InstancedMeshComponent`
  (`src/instanced_mesh.dart:23`) + per-instance attributes
  via `setInstanceAttribute(index, name, value)` and
  `setInstanceAttributes(index, Float32List packed)`
  (:131, :165). An `InstanceAttributeSchema` declares the
  per-instance record layout.
- **Custom shaders**: `ShaderMaterial`
  (`src/material/shader_material.dart:131`) wraps a
  `gpu.Shader` loaded from a `.shaderbundle` produced by
  `flutter_gpu_shaders` (`flutter_gpu_shaders` 0.5.2 is
  already on disk, so adding it as a dev dep is a one-line
  pubspec change). Instance attributes can be passed through
  via `instanceAttributes:` on the constructor.

Build pipeline:

1. Write the vertex + fragment shaders in GLSL (ES3.00 /
   Impeller-compatible SPIR-V). Port of
   `Shaders.hpp:13-48`; one each per feature flag we need
   (regular, dim-stacked, outline).
2. `flutter_gpu_shaders` compiles them to a shaderbundle at
   build time.
3. Dart: `ShaderMaterial(fragmentShader: ...,
   vertexShader: ...)` + `InstancedMesh(geometry: template,
   material: shaderMaterial)`. One template geometry (8
   vertices, 8 indexed triangles, ~24 B), one or two
   `InstancedMesh` instances (one for current layer, one for
   stacked-below), add instances per visible segment.

### Memory + performance budget on the Poco X3 Pro

The Poco is Snapdragon 860 (Adreno 640, roughly 300 Mvert/s
in practice), 6 GB RAM, 1080p screen. Target: ≥ 20 fps during
scrub on Auryn.

Per-instance record (minimum we need): pos_prev (12 B) + width
(4 B) + height (4 B) + corner_angle (4 B) + bias (4 B) +
colour (4 B packed RGBA8) = **32 B / instance**. Position of
pos_curr is next instance's pos_prev, so we don't duplicate it.

| Model     | Visible instances (full print) | Instance buffer | Vertices / frame (8/instance) | Expected fps on Adreno 640 |
|-----------|-------------------------------|-----------------|-------------------------------|-----------------------------|
| Cube      | ~3 300                        | ~ 100 KB        | ~26 k                         | 60+ (trivial)               |
| Auryn — full print | ~2.1 M              | ~ 68 MB         | ~17 M                         | ~18 fps (lower bound)        |
| Auryn — slider at layer 500 | ~1.0 M        | ~ 32 MB         | ~8 M                          | ~35 fps (acceptable scrub)  |

Headroom math: 300 Mvert/s is a vendor-y number; the Adreno
pipeline also runs the full tube-expansion math per vertex, so
the real throughput is probably 150–200 Mvert/s in practice.
Auryn at full print is right at the edge — a scrub stays
smooth, parking the slider at the top may feel sluggish.

**LOD escape hatch** (follow Orca):

- `top_layer_only_view_range`: the current layer renders as
  tubes, everything below renders as `DUMMY_COLOR` (grey) with
  the SAME tube geometry — same vertex cost. See
  `OrcaSlicer/src/libvgcode/src/ViewerImpl.cpp:1234-1244`.
- Our follow-up idea: tubes only for the top layer, thin
  `LineSegmentsGeometry` (what we draw today) for the stacked-
  below. Costs ~8× less per below-layer segment. Keeps Auryn
  smooth at the Poco's budget.

Memory check: 68 MB for Auryn's full-print instance buffer
leaves plenty of room next to the 46 MB positions / 1.9 MB
types the parser already produces. Total working set ~130 MB,
well under the 500 MB cap we aim for.

### Device acceptance — what Klaus checks at the device

1. **Reference image parity** on the cube at Layer 52: the
   screenshot in `local-test/orca-referenz-schicht52.png` is
   the pass criterion. Side-by-side on-device vs. the PNG.
   Walls must read as 0.42 mm bands (not thinner, not
   thicker), top-light highlights visible on the top edge of
   each ribbon.
2. **Pipe orientation at corners**: a 90° corner of the outer
   wall must not show a gap or a visible seam. Pick a corner
   around (120, 120) at layer 52 and zoom in.
3. **Scrub frame-rate**: Auryn, drag the slider from Layer 100
   to Layer 1045 and back. No dropped frames below ~20 fps
   (watch for jitter rather than hard stutter).
4. **Memory**: `adb shell dumpsys meminfo dev.handslice` on
   the Auryn full print. PSS below 500 MB.
5. **Degraded path**: pinch to full-print then drag — the LOD
   kicks in and only the current layer stays tube-shaded, the
   stacked-below drops to thin lines. Flutter devtools say so;
   on-device the eye sees the current layer still popping with
   width/height.
