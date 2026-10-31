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

For the benchmark we set the key **only in the debug manifest**
(`app/android/app/src/debug/AndroidManifest.xml`):

```xml
<application>
    <meta-data
        android:name="io.flutter.embedding.android.EnableFlutterGPU"
        android:value="true" />
</application>
```

Release builds stay untouched; whether we flip the switch in the
main manifest is a decision we make after this benchmark lands.

If the key is missing at runtime (or Flutter GPU rejects the device
for some other reason), the benchmark screen catches the exception,
pins the mode to `Canvas.drawVertices`, and shows a short error
card with a one-tap switch — so the Canvas numbers can still be
collected.

### Backend detection

Flutter GPU does not expose the backend name as a public API in
Flutter 3.35. We instead read `gpuContext.doesSupportFramebufferRenderMipmap`:
`true` on Vulkan/Metal, `false` on OpenGL ES (noted in the Flutter
GPU source comment). Impeller on Android picks Vulkan on API ≥ 29
and falls back to GLES on older devices or when Vulkan is force-
disabled. The guess is reported alongside the raw flags; the raw
flags are what we actually want in the report in case the heuristic
is wrong on a given device.

## Measurement table (fill after the Poco run)

The Poco X3 Pro (Adreno 619, Android 12, API 31) should default to
Impeller Vulkan.

| Model               | Tris   | Renderer   | load  | build | vram  | fps_avg | p95_frame | rss    | Δload | backend     |
|---------------------|--------|------------|-------|-------|-------|---------|-----------|--------|-------|-------------|
| notched_cube        |     24 | flutter_scene |    |       |       |         |           |        |       |             |
| notched_cube        |     24 | canvas     |       |       |       |         |           |        |       | n/a (Dart)  |
| mid_model (100 k)   | ~100 k | flutter_scene |    |       |       |         |           |        |       |             |
| mid_model (100 k)   | ~100 k | canvas     |       |       |       |         |           |        |       | n/a (Dart)  |
| big_model (300 k)   | ~300 k | flutter_scene |    |       |       |         |           |        |       |             |
| big_model (300 k)   | ~300 k | canvas     |       |       |       |         |           |        |       | n/a (Dart)  |
| big_model (500 k)   | ~500 k | flutter_scene |    |       |       |         |           |        |       |             |
| big_model (500 k)   | ~500 k | canvas     |       |       |       |         |           |        |       | n/a (Dart)  |

Big model source stays on Klaus' machine (not in the repo) — only
the numbers above come back.

## Recommendation framework

To be committed to a bullet after the Poco numbers are in:

- **If `flutter_scene` holds ≥ 50 fps at 300 k and ≥ 30 fps at
  500 k** → use `flutter_scene` as the only plate renderer. Keep
  the `Canvas.drawVertices` path alive only for widget-test
  rendering. Soft-cap the preview at 500 k triangles (the CLI
  already simplifies above that).
- **If `flutter_scene` holds 60 fps at 100 k but drops below 20 fps
  by 300 k** → use `flutter_scene` but cap plate preview at
  ~150 k; auto-call `--simplify` with a tighter target before
  export. Document the cap in `architecture.md`.
- **If `flutter_scene` fails to initialise on the Poco (Vulkan
  context creation fails or shaders don't compile)** → ship
  `Canvas.drawVertices` as the production renderer; keep
  `flutter_scene` as a build-time opt-in. Draft an upstream issue
  under `docs/upstream/` with the reproduction (stub below).

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
