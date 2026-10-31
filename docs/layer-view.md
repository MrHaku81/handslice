# Layer preview — Pflicht 7b

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
