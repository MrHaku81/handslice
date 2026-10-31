// Pflicht 7 (benchmark only): hidden plate-view screen that
// loads a .hspm (handslice preview mesh) file exported by the
// CLI (`--export-preview-mesh`), renders it with either
// `flutter_scene` or `Canvas.drawVertices`, and measures:
//   - load time (file → GPU/paint buffers)
//   - draw-time per frame (FrameTiming callback)
//   - approximate resident-memory delta (Dart VM only)
//   - which graphics backend is in use (Impeller/Vulkan on
//     Android API 29+, GLES otherwise; reported via
//     `flutter_gpu.gpuContext` capability flags, since the
//     SDK does not expose the backend name directly).
//
// Hidden from normal UI: only reached via the "Open plate-view
// benchmark" row at the bottom of the Settings tab (M10
// developer-only).

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

// ignore_for_file: depend_on_referenced_packages
// flutter_gpu / vector_math arrive transitively via flutter_scene;
// adding them to pubspec just to silence the lint would be noise.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart' as fscene;
import 'package:flutter_gpu/gpu.dart' as fgpu;
import 'package:vector_math/vector_math.dart' as vm;

// -------- .hspm parsing --------
//
// Layout: HSPM + u32 version=1 + u32 n_objects
//   per object: u32 n_volumes
//     per volume:
//       u32 filament_idx
//       u32 n_tris
//       per triangle: 3 x (f32 x, f32 y, f32 z, f32 nx, f32 ny, f32 nz)
// Flat normal (same for all three vertices of a triangle).

class HspmVolume {
  HspmVolume({required this.filamentIdx,
              required this.positions,
              required this.normals});
  final int filamentIdx;
  // Interleaved flat buffers so we can pass them to both
  // `GeometryBuilder` and `Canvas.drawVertices` without copying.
  final Float32List positions;   // length = n_tris * 3 * 3
  final Float32List normals;     // length = n_tris * 3 * 3
  int get triangleCount => positions.length ~/ 9;
}

class HspmFile {
  HspmFile({required this.volumes});
  final List<HspmVolume> volumes;
  int get triangleCount =>
      volumes.fold<int>(0, (a, v) => a + v.triangleCount);
}

HspmFile parseHspm(ByteData bd) {
  if (bd.lengthInBytes < 12 ||
      bd.getUint8(0) != 0x48 || bd.getUint8(1) != 0x53 ||
      bd.getUint8(2) != 0x50 || bd.getUint8(3) != 0x4D) {
    throw const FormatException('not an HSPM file');
  }
  final version = bd.getUint32(4, Endian.little);
  if (version != 1) {
    throw FormatException('unsupported HSPM version $version');
  }
  int off = 8;
  final nObj = bd.getUint32(off, Endian.little); off += 4;
  final out = <HspmVolume>[];
  for (int o = 0; o < nObj; ++o) {
    final nVol = bd.getUint32(off, Endian.little); off += 4;
    for (int v = 0; v < nVol; ++v) {
      final fidx  = bd.getUint32(off, Endian.little); off += 4;
      final ntri  = bd.getUint32(off, Endian.little); off += 4;
      final pos = Float32List(ntri * 9);
      final nml = Float32List(ntri * 9);
      for (int t = 0; t < ntri; ++t) {
        final tbase = t * 9;
        for (int vi = 0; vi < 3; ++vi) {
          final b = tbase + vi * 3;
          pos[b + 0] = bd.getFloat32(off, Endian.little); off += 4;
          pos[b + 1] = bd.getFloat32(off, Endian.little); off += 4;
          pos[b + 2] = bd.getFloat32(off, Endian.little); off += 4;
          nml[b + 0] = bd.getFloat32(off, Endian.little); off += 4;
          nml[b + 1] = bd.getFloat32(off, Endian.little); off += 4;
          nml[b + 2] = bd.getFloat32(off, Endian.little); off += 4;
        }
      }
      out.add(HspmVolume(
          filamentIdx: fidx, positions: pos, normals: nml));
    }
  }
  return HspmFile(volumes: out);
}

// -------- the screen --------

enum RendererMode { flutterScene, canvasVertices }

class PlateBenchScreen extends StatefulWidget {
  const PlateBenchScreen({super.key});
  @override
  State<PlateBenchScreen> createState() => _PlateBenchScreenState();
}

class _PlateBenchScreenState extends State<PlateBenchScreen> {
  HspmFile? _mesh;
  String? _loadError;
  Duration? _loadTime;
  Duration? _buildTime;
  int? _vramEstimateBytes;
  RendererMode _mode = RendererMode.flutterScene;
  bool _sceneReady = false;
  // Non-null when flutter_scene init, scene-build, or SceneView
  // construction throws. We keep the mode toggle enabled so the
  // Canvas fallback is still reachable for comparison.
  String? _sceneError;
  final fscene.Scene _scene = fscene.Scene();
  // Orbit around the AABB centre of the loaded scene (model +
  // plate), not the world origin. Set after a .hspm is loaded.
  vm.Vector3 _orbitCentre = vm.Vector3.zero();
  double _orbitRadius = 100.0;
  double _yaw = 0.6;          // azimuth around world +Z
  double _pitch = 0.5;        // elevation above the XY plane
  double _distance = 500.0;   // metres from orbit centre
  // Pan offset in world units applied to orbit centre each frame.
  vm.Vector3 _panOffset = vm.Vector3.zero();
  // FPS running stats via WidgetsBinding.addTimingsCallback.
  final List<int> _frameMicros = []; // last ~60 frames
  double _fpsAvg = 0.0;
  double _rasterMsP95 = 0.0;
  int _rssBeforeMb = 0;   // RSS captured right before pickFile().
  int _rssAfterMb  = 0;   // RSS captured right after _rebuildScene().
  late final TimingsCallback _timingsCb;
  // Backend info (reported in UI).
  final List<String> _backendCaps = [];

  @override
  void initState() {
    super.initState();
    _timingsCb = _onFrameTimings;
    WidgetsBinding.instance.addTimingsCallback(_timingsCb);
    _initScene();
    _probeBackend();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(_timingsCb);
    super.dispose();
  }

  Future<void> _initScene() async {
    try {
      await fscene.Scene.initializeStaticResources();
      if (mounted) setState(() { _sceneReady = true; });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _sceneError = _shortError(e);
        _mode = RendererMode.canvasVertices;
      });
      debugPrint('flutter_scene init failed: $e\n$st');
    }
  }

  String _shortError(Object e) {
    final s = e.toString();
    // Keep it to the first sentence / line — SceneView errors are
    // multi-paragraph and would overflow the status card.
    final cut = s.indexOf('\n');
    return cut < 0 ? s : s.substring(0, cut);
  }

  void _probeBackend() {
    try {
      final ctx = fgpu.gpuContext;
      // Impeller does not expose the backend name, but its capability
      // flags differ: doesSupportFramebufferRenderMipmap is `true` on
      // Vulkan/Metal and `false` on GLES — a solid proxy for "GLES
      // fallback". We record all probed caps for the report, too.
      _backendCaps
        ..add('offscreenMSAA=${ctx.doesSupportOffscreenMSAA}')
        ..add('fbRenderMipmap=${ctx.doesSupportFramebufferRenderMipmap}')
        ..add('manuallyMippedTex=${ctx.doesSupportManuallyMippedTextures}')
        ..add('maxAniso=${ctx.maxSamplerAnisotropy}')
        ..add('colorFmt=${ctx.defaultColorFormat.name}');
    } catch (e) {
      _backendCaps.add('flutter_gpu not available: $e');
    }
  }

  int _currentRssMb() {
    try {
      return (ProcessInfo.currentRss / 1024 / 1024).round();
    } catch (_) {
      return 0;
    }
  }

  String get _backendGuess {
    final caps = _backendCaps.join(' ');
    if (caps.contains('fbRenderMipmap=true')) return 'Impeller (Vulkan/Metal)';
    if (caps.contains('fbRenderMipmap=false')) return 'Impeller (OpenGL ES)';
    return 'unknown';
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _frameMicros.add(t.totalSpan.inMicroseconds);
      if (_frameMicros.length > 60) _frameMicros.removeAt(0);
    }
    if (_frameMicros.isEmpty) return;
    final avgUs = _frameMicros.reduce((a, b) => a + b) / _frameMicros.length;
    _fpsAvg = avgUs > 0 ? 1e6 / avgUs : 0;
    final sorted = List<int>.from(_frameMicros)..sort();
    _rasterMsP95 = sorted[(sorted.length * 0.95).floor()
        .clamp(0, sorted.length - 1)] / 1000.0;
    // Rebuild only the status card, not the heavy scene.
    if (mounted) setState(() {});
  }

  Future<void> _pickFile() async {
    final pf = await FilePicker.pickFile(type: FileType.any);
    if (pf == null || pf.path == null) return;
    final path = pf.path!;
    _rssBeforeMb = _currentRssMb();
    final sw1 = Stopwatch()..start();
    final bytes = await File(path).readAsBytes();
    final mesh = parseHspm(bytes.buffer.asByteData());
    sw1.stop();
    // Frame the camera on the mesh AABB joined with the plate.
    // CC2 bed is 256×256 at z=0; AABB.center of model gives us the
    // orbit target. Radius = half the diagonal of the joined box.
    final aabb = _computeAabb(mesh);
    aabb.hull(vm.Aabb3.minMax(vm.Vector3(0, 0, 0),
                              vm.Vector3(256, 256, 0)));
    final centre = (aabb.min + aabb.max) * 0.5;
    final extent = aabb.max - aabb.min;
    final radius = math.max(extent.length * 0.5, 1.0);
    final fitDist = radius / math.sin(_fovY / 2) * 1.3;
    _orbitCentre = centre;
    _orbitRadius = radius;
    _distance = fitDist;
    _panOffset.setZero();
    _yaw = 0.6;
    _pitch = 0.5;
    final sw2 = Stopwatch()..start();
    await _rebuildScene(mesh);
    sw2.stop();
    _rssAfterMb = _currentRssMb();
    // Rough VRAM estimate: positions + normals + rgba vertex colours
    // = 32 bytes/vertex × 3 verts/tri.
    final vram = mesh.triangleCount * 3 * 32;
    if (!mounted) return;
    setState(() {
      _mesh = mesh;
      _loadError = null;
      _loadTime = sw1.elapsed;
      _buildTime = sw2.elapsed;
      _vramEstimateBytes = vram;
    });
  }

  static const double _fovY = math.pi / 4;

  vm.Aabb3 _computeAabb(HspmFile mesh) {
    double minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
    for (final vol in mesh.volumes) {
      final p = vol.positions;
      for (int i = 0; i < p.length; i += 3) {
        final x = p[i], y = p[i + 1], z = p[i + 2];
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (z < minZ) minZ = z;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
        if (z > maxZ) maxZ = z;
      }
    }
    if (minX == double.infinity) {
      return vm.Aabb3.minMax(vm.Vector3.zero(), vm.Vector3.zero());
    }
    return vm.Aabb3.minMax(
      vm.Vector3(minX, minY, minZ),
      vm.Vector3(maxX, maxY, maxZ));
  }

  Future<void> _rebuildScene(HspmFile mesh) async {
    if (_mode != RendererMode.flutterScene) return;
    if (_sceneError != null) return;
    try {
      _rebuildSceneUnsafe(mesh);
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _sceneError = _shortError(e);
        _mode = RendererMode.canvasVertices;
      });
      debugPrint('flutter_scene rebuild failed: $e\n$st');
    }
  }

  void _rebuildSceneUnsafe(HspmFile mesh) {
    _scene.root.children.clear();
    if (_mode != RendererMode.flutterScene) return;
    // 1. The CC2 bed (256×256 at z=0). Only four vertices, so we
    //    keep using GeometryBuilder for brevity.
    _addPlate();
    // 2. Each volume: build the vertex streams directly as
    //    Float32Lists and feed MeshGeometry.fromArrays with
    //    retainCpuData=false. This bypasses GeometryBuilder's
    //    List<double> intermediates (which, for 500 k tris, were
    //    the dominant allocation in the earlier `GeometryBuilder`
    //    path — see `docs/plate-view-benchmark.md`). The HSPM
    //    buffers are already Float32List, so positions and
    //    normals are reused in place without copy.
    for (final vol in mesh.volumes) {
      final nTris = vol.triangleCount;
      if (nTris == 0) continue;
      final tint = _colorFor(vol.filamentIdx);
      final tintR = tint.r, tintG = tint.g, tintB = tint.b;
      final lx = _keyLight.x, ly = _keyLight.y, lz = _keyLight.z;
      final a = _ambient;
      final b = 1.0 - a;
      final nVerts = nTris * 3;
      final colors = Float32List(nVerts * 4);
      final normals = vol.normals;
      // One Lambert factor per triangle (flat shading), replicated
      // across its three vertices.
      for (int t = 0; t < nTris; ++t) {
        final nBase = t * 9;
        final nx = normals[nBase];
        final ny = normals[nBase + 1];
        final nz = normals[nBase + 2];
        final dot = nx * lx + ny * ly + nz * lz;
        final k = a + b * (dot < 0 ? -dot : dot);
        final r = tintR * k, g = tintG * k, bl = tintB * k;
        final cBase = t * 12;
        colors[cBase     ] = r; colors[cBase +  1] = g;
        colors[cBase +  2] = bl; colors[cBase +  3] = 1.0;
        colors[cBase +  4] = r; colors[cBase +  5] = g;
        colors[cBase +  6] = bl; colors[cBase +  7] = 1.0;
        colors[cBase +  8] = r; colors[cBase +  9] = g;
        colors[cBase + 10] = bl; colors[cBase + 11] = 1.0;
      }
      final geom = fscene.MeshGeometry.fromArrays(
        positions: vol.positions,  // reused in place
        normals: normals,          // reused in place
        colors: colors,
        retainCpuData: false,      // release CPU streams after GPU upload
      );
      final mat = fscene.UnlitMaterial()
        ..baseColorFactor = vm.Vector4(1, 1, 1, 1);
      _scene.add(fscene.Node(name: 'vol_${vol.filamentIdx}',
          mesh: fscene.Mesh(geom, mat)));
    }
  }

  // World-space key light (down-and-forward, Z-up world). Values
  // chosen to match the thumbnail renderer so the plate view and
  // the G-code thumbnail read the same way.
  static final vm.Vector3 _keyLight =
      vm.Vector3(0.3, -0.3, 0.9)..normalize();
  static const double _ambient = 0.25;

  vm.Vector4 _lambertShade(vm.Vector4 tint, vm.Vector3 normal) {
    // Flip the normal to face the light so both sides of a
    // non-manifold or flipped-winding mesh still read as "lit";
    // same trick the thumbnail renderer uses, which is what the
    // user compares to visually.
    final dot = normal.dot(_keyLight).abs();
    final k = _ambient + (1.0 - _ambient) * dot;
    return vm.Vector4(tint.r * k, tint.g * k, tint.b * k, 1.0);
  }

  void _addPlate() {
    final gb = fscene.GeometryBuilder(deduplicate: false);
    final n = vm.Vector3(0, 0, 1);
    final plateRgb = _lambertShade(vm.Vector4(0.18, 0.19, 0.21, 1), n);
    gb.normal(n);
    gb.color(plateRgb);
    final a = gb.addVertex(vm.Vector3(0,   0,   0));
    final b = gb.addVertex(vm.Vector3(256, 0,   0));
    final c = gb.addVertex(vm.Vector3(256, 256, 0));
    final d = gb.addVertex(vm.Vector3(0,   256, 0));
    gb.addTriangle(a, b, c);
    gb.addTriangle(a, c, d);
    final geom = gb.build();
    final mat = fscene.UnlitMaterial()
      ..baseColorFactor = vm.Vector4(1, 1, 1, 1);
    _scene.add(fscene.Node(name: 'bed', mesh: fscene.Mesh(geom, mat)));
  }

  vm.Vector4 _colorFor(int idx) {
    // Vivid, filament-reel-style palette, so each volume reads
    // distinctly even without a texture. First entry is a solid
    // red because that is the most common "default" slot value
    // on the CC2 after a factory reset.
    const palette = <List<double>>[
      [0.86, 0.17, 0.17],  // red
      [0.11, 0.46, 0.90],  // blue
      [0.18, 0.75, 0.37],  // green
      [0.98, 0.78, 0.11],  // yellow
    ];
    final c = palette[idx % palette.length];
    return vm.Vector4(c[0], c[1], c[2], 1.0);
  }

  // -------- gestures --------
  Offset? _dragStart;
  double? _pinchStart;
  double? _distStart;

  void _onScaleStart(ScaleStartDetails d) {
    _dragStart = d.focalPoint;
    _pinchStart = null;
    _distStart = _distance;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount == 1) {
      final delta = d.focalPoint - (_dragStart ?? d.focalPoint);
      setState(() {
        _yaw   += delta.dx * 0.01;
        _pitch -= delta.dy * 0.01;
        _pitch = _pitch.clamp(-1.4, 1.4);
      });
      _dragStart = d.focalPoint;
    } else {
      _pinchStart ??= d.scale;
      setState(() {
        _distance = (_distStart ?? _distance) / d.scale;
        _distance = _distance.clamp(_orbitRadius * 0.3,
                                    _orbitRadius * 20.0);
        // Pan in world units along the camera right / up axes so
        // the user drags *the scene* not an abstract offset.
        final k = _distance * 0.0025;
        final right = vm.Vector3(math.cos(_yaw), math.sin(_yaw), 0);
        // Screen-up in world ≈ Z-up tilted by pitch.
        final up = vm.Vector3(
            -math.sin(_pitch) * math.sin(_yaw),
             math.sin(_pitch) * math.cos(_yaw),
             math.cos(_pitch));
        // Drag the scene with the fingers: target moves along the
        // finger direction so the point under the fingers tracks.
        _panOffset += right * (d.focalPointDelta.dx  * k)
                    + up    * (-d.focalPointDelta.dy * k);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plate-view benchmark'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _pickFile,
            tooltip: 'Open .hspm',
          ),
        ],
      ),
      body: Column(children: [
        _statsBar(),
        _modeToggle(),
        Expanded(
          child: GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: _viewport(),
          ),
        ),
      ]),
    );
  }

  Widget _statsBar() {
    final tris = _mesh?.triangleCount ?? 0;
    final load = _loadTime?.inMilliseconds;
    final build = _buildTime?.inMilliseconds;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.all(8),
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('triangles=$tris  '
                 'load=${load ?? '-'}ms  build=${build ?? '-'}ms  '
                 'vram≈${_vramEstimateBytes == null ? '-' : (_vramEstimateBytes! / 1024 / 1024).toStringAsFixed(1)}MB'),
            Text('fps_avg=${_fpsAvg.toStringAsFixed(1)}  '
                 'p95_frame=${_rasterMsP95.toStringAsFixed(1)}ms  '
                 'rss=${_currentRssMb()}MB  '
                 'Δload=${_rssAfterMb - _rssBeforeMb}MB'),
            if (_backendCaps.isNotEmpty) ...[
              Text('gpu backend ≈ $_backendGuess'),
              Text(_backendCaps.join('  '),
                  overflow: TextOverflow.ellipsis, maxLines: 2),
            ],
            if (_loadError != null)
              Text('ERR: $_loadError',
                  style: const TextStyle(color: Colors.redAccent)),
          ],
        ),
      ),
    );
  }

  Widget _modeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SegmentedButton<RendererMode>(
        segments: const [
          ButtonSegment(value: RendererMode.flutterScene, label: Text('flutter_scene')),
          ButtonSegment(value: RendererMode.canvasVertices, label: Text('Canvas.drawVertices')),
        ],
        selected: {_mode},
        onSelectionChanged: (s) async {
          setState(() { _mode = s.first; });
          if (_mesh != null) {
            final sw = Stopwatch()..start();
            await _rebuildScene(_mesh!);
            sw.stop();
            if (mounted) setState(() { _buildTime = sw.elapsed; });
          }
        },
      ),
    );
  }

  Widget _viewport() {
    if (_mesh == null) {
      return const Center(child: Text(
        'Open a .hspm file to begin.\n'
        '(generated by handslice-cli --export-preview-mesh)',
        textAlign: TextAlign.center));
    }
    switch (_mode) {
      case RendererMode.flutterScene:
        if (_sceneError != null) return _sceneErrorCard();
        if (!_sceneReady) {
          return const Center(child: CircularProgressIndicator());
        }
        try {
          final target = _orbitCentre + _panOffset;
          return fscene.SceneView(
            _scene,
            camera: fscene.PerspectiveCamera(
              position: _cameraPos(target),
              target: target,
              up: vm.Vector3(0, 0, 1),           // Z is up in printer world
              fovRadiansY: _fovY,
              fovNear: _distance * 0.01,
              fovFar: _distance * 50.0,
            ),
          );
        } catch (e) {
          _sceneError = _shortError(e);
          return _sceneErrorCard();
        }
      case RendererMode.canvasVertices:
        return CustomPaint(
          size: Size.infinite,
          painter: _CanvasVertexPainter(
            mesh: _mesh!,
            yaw: _yaw,
            pitch: _pitch,
            distance: _distance,
            orbitCentre: _orbitCentre + _panOffset,
            colorFor: _colorFor,
          ),
        );
    }
  }

  Widget _sceneErrorCard() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text('flutter_scene could not start',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_sceneError ?? '(unknown)',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 16),
            const Text(
              'Tip: on Android, flutter_scene needs the\n'
              'io.flutter.embedding.android.EnableFlutterGPU\n'
              'manifest key set to true (debug manifest only, for now).\n'
              'The Canvas fallback below works regardless.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Switch to Canvas.drawVertices'),
              onPressed: () => setState(() {
                _mode = RendererMode.canvasVertices;
              }),
            ),
          ],
        ),
      ),
    );
  }

  vm.Vector3 _cameraPos(vm.Vector3 target) {
    final cp = math.cos(_pitch);
    final sp = math.sin(_pitch);
    // Camera placed on a sphere around `target`. Z is world up.
    // At yaw=0 the camera looks along +Y, matching the thumbnail
    // renderer's "front view".
    return target + vm.Vector3(
      _distance * cp * math.sin(_yaw),
      -_distance * cp * math.cos(_yaw),
       _distance * sp,
    );
  }
}

// -------- Canvas.drawVertices fallback --------

class _CanvasVertexPainter extends CustomPainter {
  _CanvasVertexPainter({
    required this.mesh,
    required this.yaw,
    required this.pitch,
    required this.distance,
    required this.orbitCentre,
    required this.colorFor,
  });
  final HspmFile mesh;
  final double yaw, pitch, distance;
  final vm.Vector3 orbitCentre;
  final vm.Vector4 Function(int) colorFor;

  @override
  void paint(Canvas canvas, Size size) {
    // Z-up orbit matched to the flutter_scene path. Simple ortho
    // projection with painter's-algorithm depth sort.
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final scale = size.shortestSide / (distance * 1.1);
    final cosY = math.cos(yaw),   sinY = math.sin(yaw);
    final cosP = math.cos(pitch), sinP = math.sin(pitch);
    final ocx = orbitCentre.x, ocy = orbitCentre.y, ocz = orbitCentre.z;

    // World-space key light (same vector as flutter_scene path).
    const double lx = 0.3, ly = -0.3, lz = 0.9;
    final double lLen = math.sqrt(lx * lx + ly * ly + lz * lz);
    final double lnx = lx / lLen, lny = ly / lLen, lnz = lz / lLen;

    // Project a world point to screen + camera-space depth.
    // World axes (x,y,z) → camera axes:
    //   right = (cosY, sinY, 0)              (screen +x)
    //   forward = (-sinY*cosP, cosY*cosP, sinP)  (into screen)
    //   up    = (sinY*sinP, -cosY*sinP, cosP)    (screen +y)
    void project(double x, double y, double z, List<double> out) {
      final rx = x - ocx, ry = y - ocy, rz = z - ocz;
      final sx = rx * cosY + ry * sinY;
      final sy = rx * sinY * sinP - ry * cosY * sinP + rz * cosP;
      final depth = -rx * sinY * cosP + ry * cosY * cosP + rz * sinP;
      out[0] = cx + sx * scale;
      out[1] = cy - sy * scale;
      out[2] = depth;
    }

    final triangles = <_Tri>[];
    final scratch = List<double>.filled(3, 0);

    // Plate first.
    final plateCol = _shade(0.18, 0.19, 0.21, 0, 0, 1,
                            lnx, lny, lnz);
    final plateCoords = <List<double>>[
      [0,   0,   0], [256, 0,   0], [256, 256, 0], [0, 256, 0],
    ];
    final plateV = <Offset>[];
    double plateDepth = 0;
    for (final p in plateCoords) {
      project(p[0], p[1], p[2], scratch);
      plateV.add(Offset(scratch[0], scratch[1]));
      plateDepth += scratch[2];
    }
    plateDepth /= 4;
    triangles.add(_Tri(plateV[0], plateV[1], plateV[2], plateDepth, plateCol));
    triangles.add(_Tri(plateV[0], plateV[2], plateV[3], plateDepth, plateCol));

    // Model volumes.
    for (final vol in mesh.volumes) {
      final tint = colorFor(vol.filamentIdx);
      final nTri = vol.triangleCount;
      for (int t = 0; t < nTri; ++t) {
        final b0 = t * 9;
        final nx = vol.normals[b0], ny = vol.normals[b0 + 1], nz = vol.normals[b0 + 2];
        final shade = _shade(tint.r, tint.g, tint.b, nx, ny, nz,
                             lnx, lny, lnz);
        final verts = <Offset>[];
        double depth = 0;
        for (int i = 0; i < 3; ++i) {
          final bi = b0 + i * 3;
          project(vol.positions[bi], vol.positions[bi + 1], vol.positions[bi + 2],
                  scratch);
          verts.add(Offset(scratch[0], scratch[1]));
          depth += scratch[2];
        }
        triangles.add(_Tri(verts[0], verts[1], verts[2],
                           depth / 3, shade));
      }
    }
    triangles.sort((a, b) => b.depth.compareTo(a.depth));

    final paint = Paint()..style = PaintingStyle.fill;
    for (final t in triangles) {
      final path = Path()
        ..moveTo(t.a.dx, t.a.dy)
        ..lineTo(t.b.dx, t.b.dy)
        ..lineTo(t.c.dx, t.c.dy)
        ..close();
      paint.color = t.color;
      canvas.drawPath(path, paint);
    }
  }

  Color _shade(double r, double g, double b,
               double nx, double ny, double nz,
               double lnx, double lny, double lnz) {
    final dot = (nx * lnx + ny * lny + nz * lnz).abs();
    final k = (0.25 + 0.75 * dot).clamp(0.0, 1.0);
    return Color.fromARGB(255,
        (r * 255 * k).round(),
        (g * 255 * k).round(),
        (b * 255 * k).round());
  }

  @override
  bool shouldRepaint(covariant _CanvasVertexPainter old) =>
      old.mesh != mesh || old.yaw != yaw || old.pitch != pitch ||
      old.distance != distance || old.orbitCentre != orbitCentre;
}

class _Tri {
  _Tri(this.a, this.b, this.c, this.depth, this.color);
  final Offset a, b, c;
  final double depth;
  final Color color;
}
