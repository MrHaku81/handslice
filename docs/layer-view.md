# Layer preview — Pflicht 7b / 7c / 7d

Pflicht 7c (2026-11-01): the authoritative data path is now the
CLI's HSPT binary produced by `handslice-cli --export-toolpaths`.
The Dart g-code parser documented below stays as a fallback for
files that do not come with an HSPT sidecar.

Pflicht 7d (2026-11-01): the HSPT format bumps to v2 to carry
per-move time (needed for the legend's time column and the
"Total estimation" footer) and the per-filament density /
diameter in the header (needed to turn extruded millimetres
into grams). The Dart parser rejects v1 files with a clear
error so a stale sidecar from before the bump surfaces
immediately rather than silently reading garbage.

## HSPT — handslice toolpaths binary (v2)

Dumped by `handslice-cli --export-toolpaths <path>` either as a
byproduct of slicing or in `--input-gcode <path>` mode (which
runs `GCodeProcessor::process_file()` on an existing .gcode and
exits without slicing). The density / diameter come from
`GCodeProcessorResult::filament_densities[0]` and
`.filament_diameters[0]`, which `process_file` populates from
the g-code's config block (`filament_density`,
`filament_diameter`), so a sidecar written by `--input-gcode`
matches a slice-time sidecar.

```
Header (24 B, little-endian):
  magic           "HSPT"                 4 B
  version         u32 = 2                4 B
  flags           u32 = 0 (reserved)     4 B
  n_moves         u32                    4 B
  density_g_cm3   f32 (filament 0)       4 B
  diameter_mm     f32 (filament 0)       4 B

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

### Object-only AABB

The parser tracks two bounding boxes:

- `minX..maxZ` over every extrude move (used for the orbit
  camera's framing — the hull-with-bed call still needs the
  outermost geometry so the camera does not clip the brim).
- `objMinX..objMaxZ` over extrude moves excluding `skirt`,
  `brim`, `wipeTower` and `custom` roles. The silhouette drawn
  above the current layer uses this one; otherwise the box
  balloons by ~10 mm for brim and off the bed for the purge
  line.

### Internal-only move filter

`GCodeProcessor` inserts a parallel "actual speed" vertex for
each real move (with `internal_only = true`). The CLI writer
drops those; otherwise the record stream triples in size and
the summed `delta_extruder` triples too. Mirrors how
`libvgcode` filters internal-only moves on load.

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

Layers below the slider are drawn at their full Orca palette
value — no stacked dimming. We **do not** render anything
above the slider by default any more. Klaus (409e425+1
device run) found the dense AABB-wireframe shell "unruhig"
on the Poco; it now hides behind a `Model outline` option
in the legend's option block and defaults to off. When the
user toggles it on, we draw the 12 edges of the object-only
AABB (`t.objMin*/objMax*`) at 0.1-mm line width in light
cool-grey `(0.78, 0.80, 0.82)` sRGB.

Orca's shell is a real alpha-blended STL mesh:
`GCodeViewer.cpp:240` sets `m_model.set_color({1.0f, 1.0f,
1.0f, 0.5f})` and `GLCanvas3D.hpp:1017` /
`GCodeViewer.hpp:266` cap the final alpha at 0.2 / 0.15
respectively, so it reads as a faint white glass shell.
`flutter_scene`'s `UnlitMaterial` has no public blend-mode
hook, so we cannot fire a 20 %-alpha fill today. Porting
the real mesh is tracked under "pipe-ribbon shader" in the
7e backlog, since both items need a custom shader anyway.

### Scene reset — use `removeAll()`, never `children.clear()`

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

A scene-level test
(`scene emit: positions handed to the renderer at Layer
1/52/100 obey the slider`) pins the exact `Float32List`
positions `_emitRole` hands to `LineSegmentsGeometry` at
three slider positions. For every role it enforces:

- `maxZ(seg) ≤ layerZ[current0] + 0.01` — nothing above the
  slider is in the vertex stream.
- At Layer 52 the `topSolidInfill` role (`0xFFF04040`,
  bright red) emits **zero** segments, because the HSPT
  places no top-surface moves in bins ≤ 51.

The view's `_emitRole` is now a thin shim around the pure
helper `buildRoleSegments(Toolpaths, roleCode, from, to)` in
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
