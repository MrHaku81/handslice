# Layer preview — Pflicht 7b / 7c

Pflicht 7c (2026-11-01): the authoritative data path is now the
CLI's HSPT binary produced by `handslice-cli --export-toolpaths`.
The Dart g-code parser documented below stays as a fallback for
files that do not come with an HSPT sidecar.

## HSPT — handslice toolpaths binary

Dumped by `handslice-cli --export-toolpaths <path>` either as a
byproduct of slicing or in `--input-gcode <path>` mode (which
runs `GCodeProcessor::process_file()` on an existing .gcode and
exits without slicing).

```
Header (16 B, little-endian):
  magic     "HSPT"               4 B
  version   u32 = 1               4 B
  flags     u32 = 0 (reserved)    4 B
  n_moves   u32                   4 B

Per-move record (28 B each, little-endian):
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
```

The record size is 28 B so a Pflicht-6-sized print (~2.4 M
moves on `auryn-x86.gcode`) weighs ≈ 67 MB on disk — about the
same as the source g-code, and the Dart side can mmap-style
read it as one Float32/Uint8 view without parsing text.

Fields we deliberately drop today: `fan_speed`, `temperature`,
`pressure_advance`, `acceleration`, `jerk`, `layer_duration`,
`actual_feedrate`, `mm3_per_mm`, `gcode_id`. None of them are
consumed by the Dart viewer yet; adding one is a header-flag
+ record-size bump.

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
move width ribbons that change thickness mid-path would need a
custom shader and remain a 7c follow-up.

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
