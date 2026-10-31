# Plate-view renderer benchmark — Pflicht 7

Status: scaffolding in place, numbers pending a device run on the
Poco X3 Pro. Report is in English per the current project-language
rule.

## What we are picking between

The app needs a plate view that shows the arranged printables after
`handslice-cli` has done centring and drop-to-bed. We want to know
whether `flutter_scene` (GPU, Impeller) is good enough for our worst
case or whether we need the pure-Dart `Canvas.drawVertices` fallback.
"Good enough" here means: interactive rotation on the Poco X3 Pro
(our weakest supported target) at or near 60 fps for the triangle
counts that users will actually see.

Target triangle counts to decide at:

| Bucket     | Triangles | Typical content                           |
|------------|-----------|-------------------------------------------|
| S          | 100 000   | A handful of calibration / small parts    |
| M          | 300 000   | A full plate of medium-resolution models  |
| L          | 500 000   | One big organic / high-resolution model   |

Simplification runs in the CLI (`--simplify N`, QEM via
`its_quadric_edge_collapse`) and is a slicing-independent step, so
"load time" below means `file → GPU buffers` only. The CLI's
simplification cost is tracked separately in `PROGRESS.md` and is
constant per run.

## Running the benchmark

1. Export a scene from the CLI, keeping the slice output intact:
   ```
   handslice-cli --orca-dir … --input model.stl \
                 --output /dev/null \
                 --export-preview-mesh /tmp/preview.hspm \
                 [--simplify 100000]
   ```
2. Push the `.hspm` to the Poco via `adb push`.
3. Open the app, go to **Settings → Open plate-view benchmark**
   (visible in debug builds only).
4. Tap the folder icon, pick `preview.hspm`. The screen shows:
   `triangles`, `load=ms`, `build=ms`, `vram≈MB`, `fps_avg`,
   `p95_frame=ms`, `rss=MB`, `Δload=MB`, and the probed GPU
   capability flags with a `backend ≈` guess.
5. Rotate the model with one finger for 10 seconds, then record the
   row from the stats bar.
6. Switch to **Canvas.drawVertices** with the segmented control and
   repeat the 10-second rotate.

### Android: Flutter GPU opt-in

Flutter GPU (which `flutter_scene` is built on) is still gated
behind a manifest opt-in on Android as of Flutter 3.35. Without it
the first `Scene.initializeStaticResources()` call throws:

```
Flutter GPU must be enabled via the Flutter GPU manifest setting …
io.flutter.embedding.android.EnableFlutterGPU metadata key to true
in the AndroidManifest.xml
```

For the benchmark we set the key in the **debug and profile**
manifests only
(`app/android/app/src/debug/AndroidManifest.xml`,
`app/android/app/src/profile/AndroidManifest.xml`):

```xml
<application>
    <meta-data
        android:name="io.flutter.embedding.android.EnableFlutterGPU"
        android:value="true" />
</application>
```

Release builds stay untouched; the production decision follows the
benchmark results below. The debug build only ran the empty scene at
~24 fps (JIT + Impeller shader warm-up), so the numbers below were
taken from `--profile` builds, which run the same AOT Dart code and
Impeller pipeline a release build would.

If the key is missing at runtime (or Flutter GPU rejects the device
for some other reason), the benchmark screen catches the exception,
pins the mode to `Canvas.drawVertices`, and shows a short error
card with a one-tap switch — so the Canvas numbers can still be
collected.

### Backend detection

Flutter GPU does not expose the backend name as a public API in
Flutter 3.47. We instead read
`gpuContext.doesSupportFramebufferRenderMipmap`: `true` on
Vulkan/Metal, `false` on OpenGL ES (noted in the Flutter GPU source
comment). The guess is reported alongside the raw flags; the raw
flags are what we actually want in the report in case the heuristic
is wrong on a given device.

### Why the Poco X3 Pro (Adreno 640) reports GLES, not Vulkan

Confirmed from Flutter 3.47.8 engine source
(`engine/src/flutter/impeller/renderer/backend/vulkan/driver_info_vk.cc`,
`DriverInfoVK::IsKnownBadDriver()`):

```cpp
// Fall back to OpenGL ES on older Adreno devices that require
// additional workarounds in the Impeller Vulkan back end such as
// disabling framebuffer fetch.
//
// See the following issues:
// https://github.com/flutter/flutter/issues/178285
// https://github.com/flutter/flutter/issues/178498
if (adreno_gpu_ && *adreno_gpu_ <= AdrenoGPU::kAdreno650) {
  return true;
}
```

So **any Adreno ≤ 650 is deliberately denylisted**: Impeller
initialises its OpenGL ES backend on those devices and never
attempts Vulkan. The Poco X3 Pro (Snapdragon 860 → Adreno 640)
falls under this rule, which is why the backend-flag probe
reports `fbRenderMipmap=false` on it.

Practical consequence for us: the Poco measurements are a
**lower-bound-on-mainstream-hardware** data point, not a
Vulkan/Metal measurement. If `flutter_scene` is comfortable here,
newer devices (Adreno 660+, Mali G710+, Xclipse 920+) will almost
certainly do better. If it struggles, we still don't know whether
Vulkan would save it — that would need a second measurement on an
Adreno-660-or-newer device.

## Measurement results — Poco X3 Pro, Impeller OpenGL ES

Device: Poco X3 Pro, Snapdragon 860, Adreno 640, Android 12
(API 31). Profile APK commit `1b17e4215c`. Backend reported as
Impeller OpenGL ES (per the Adreno-≤650 Vulkan denylist above).
Test models: an Auryn-sized STL re-exported from `handslice-cli
--export-preview-mesh --simplify N` at 100 / 300 / 500 k targets,
plus the 24-triangle notched cube. The model source stays on
Klaus' AMR5 (not in the repo), only the numbers come back.

### Pass 1 — original GeometryBuilder path

| Model         | Tris    | load   | build    | vram    | fps_avg | p95_frame | Δload RSS | notes                                   |
|---------------|---------|--------|----------|---------|---------|-----------|-----------|-----------------------------------------|
| notched_cube  |     24  |    —   |     —    |   —     |  114    |  12 ms    |     —     | small; smooth                           |
| big_model     | 100 k   |  31 ms |   642 ms |  9.2 MB |  138    |  9.4 ms   |  185 MB   | smooth                                  |
| big_model     | 300 k   |  66 ms |  2149 ms | 27.5 MB |  137    | 10.4 ms   |  559 MB   | smooth                                  |
| big_model     | 500 k   |  87 ms |  3964 ms | 45.8 MB |   46    | 23.4 ms   |  896 MB   | still interactive, build dominates      |

Pattern: ~1.8 KB resident per triangle on the Dart heap for the
build step; GPU VRAM is a tenth of that. The dominant cost was the
`GeometryBuilder` → `Float32List.fromList` → packed-interleaved
path keeping multiple copies of every attribute on the CPU.

(Canvas.drawVertices comparison was skipped at this point — the
flutter_scene numbers were already clearly good enough to decide.)

### Pass 2 — direct `MeshGeometry.fromArrays`, `retainCpuData: false`

(Updated after Klaus re-runs on the new APK; builder path replaced
with a direct upload of the HSPM Float32Lists.)

| Model         | Tris    | load | build | vram  | fps_avg | p95_frame | Δload RSS |
|---------------|---------|------|-------|-------|---------|-----------|-----------|
| notched_cube  |     24  |      |       |       |         |           |           |
| big_model     | 100 k   |      |       |       |         |           |           |
| big_model     | 300 k   |      |       |       |         |           |           |
| big_model     | 500 k   |      |       |       |         |           |           |

## Decision — `flutter_scene` is the plate renderer

Even on an Adreno-640 Vulkan-denylisted device the baseline run
holds 60+ fps up to 300 k triangles and stays interactive at 500 k
(46 fps avg, 23 ms p95). The only pain point was the build-step
RAM footprint, which Pass 2 addresses on the Dart side.

Consequences for the rest of the app:

- `flutter_scene: 0.24.3` becomes the production plate-view
  renderer. The release manifest gets the Flutter-GPU opt-in flag
  once the main plate view (not just the benchmark) is wired up.
- The `Canvas.drawVertices` fallback stays in the tree, gated to
  the benchmark screen only, as a readable Dart-only reference
  rasterizer. It is not shipped as a user-facing option — the
  benchmark did not need it to decide.
- The CLI's `--simplify` is the knob we use to stay under the
  device's triangle budget. The next section proposes a draft
  for picking that budget automatically.

## Draft — automatic LOD by device RAM

(Proposal only; thresholds settle after Pass 2 numbers are in.)

- At app start, read `MemoryInfo.totalMem` via a `PlatformChannel`
  one-shot (one `ActivityManager.MemoryInfo` call), cache it.
- Pick a default preview triangle budget `preview_simplify_target`:
  | Device totalMem | Budget   |
  |-----------------|----------|
  | ≥ 8 GB          | 500 000  |
  | 4 – 8 GB        | 300 000  |
  | < 4 GB          | 100 000  |
  The Poco X3 Pro reports 6 GB, so it would land on 300 k.
- Expose an override under **Settings → Expert**:
  `preview_simplify_target` as an integer, with the auto-value
  shown as default and a `Reset to auto` button. Default is
  "auto"; a user who wants to push a specific device explicitly
  flips to a fixed number.
- The CLI call for `--export-preview-mesh` (and the preview path
  for the thumbnail) passes `--simplify <preview_simplify_target>`
  so the HSPM shipped to the device is already at the right
  resolution — no on-device decimation needed.

## Draft — "System requirements" section for the user docs

(For `docs/system-requirements.md`, once we have the Pass 2
numbers to commit to.)

- Android 10+ (API 29+), 64-bit arm64 only. Impeller is the only
  renderer we test against.
- 4 GB RAM minimum, 6 GB recommended. The plate-view budget scales
  with available memory (see the auto-LOD table above).
- GPU: any OpenGL ES 3.0 device will work via Impeller; newer
  devices (Adreno 660+ / Mali G710+ / Xclipse 920+) additionally
  get Vulkan.
- Storage: 300 MB for the app + a few MB per saved print profile.
- No specific minimum CPU — libslic3r runs on whatever the device
  gives it; a profile Snapdragon 7-series or newer slices an Auryn
  in roughly a minute (Pflicht 6 result).

## Appendix A — `.hspm` binary format

Written by `handslice-cli --export-preview-mesh <path>`. All
multi-byte values are little-endian.

```
magic         : u8[4]           "HSPM"
version       : u32             1
n_objects     : u32
per object:
  n_volumes   : u32
  per volume:
    fil_idx   : u32             (0-based filament/extruder index)
    n_tris    : u32
    per tri (x3 vertices):
      pos     : f32[3]          world-space (after centre + drop-to-bed)
      normal  : f32[3]          flat, same for all 3 vertices of a tri
```

Positions are world-space millimetres; the shipping unit test
confirms a 24-triangle notched cube serialises to exactly 1752
bytes.

## Appendix B — F-Droid eligibility recap

Verified on 2026-10-31 against `flutter_scene-0.24.3` from
pub.dev:

- No prebuilt native blobs (`.so`, `.aar`, `.dll`, `.dylib`,
  `.jar`) under the package root.
- Shader sources (`.vert`, `.frag`, `.glsl`) are present under
  `shaders/`; they are compiled from source as part of the Flutter
  build.
- Transitive `flutter_gpu` is a Flutter SDK stub (no third-party
  blobs). `flutter_gpu_shaders` and `scene` ship pure Dart.
- License: MIT.

This matches F-Droid's "no prebuilt code" inclusion rule and is why
we rejected `three_js` earlier (ships `libEGL_angle.so` /
`libGLESv2_angle.so` via its `flutter_angle` dependency).

## Appendix C — pending upstream notification (draft stub)

Only fill if the Poco run surfaces something `flutter_scene` /
`flutter_gpu` can act on. Expected drop-in location:
`docs/upstream/flutter-scene-poco-notice-draft.md`. Likely topics
if issues appear:

- Vulkan context creation failure on Adreno 619.
- Non-expressible backend name via public API (we currently guess
  via `doesSupportFramebufferRenderMipmap`).
- Any correctness issue in `GeometryBuilder` with flat-shaded
  triangle soups (`deduplicate: false`, per-triangle normals).
