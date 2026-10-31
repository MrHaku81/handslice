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
  double _yaw = 0.0;
  double _pitch = -0.6;   // slightly down-tilted baseline
  double _distance = 350.0;
  Offset _pan = Offset.zero;
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
    final sw2 = Stopwatch()..start();
    await _rebuildScene(mesh);
    sw2.stop();
    _rssAfterMb = _currentRssMb();
    // Rough VRAM estimate: positions + normals = 24 bytes/vertex × 3 verts/tri.
    final vram = mesh.triangleCount * 3 * 24;
    if (!mounted) return;
    setState(() {
      _mesh = mesh;
      _loadError = null;
      _loadTime = sw1.elapsed;
      _buildTime = sw2.elapsed;
      _vramEstimateBytes = vram;
    });
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
    if (_mode == RendererMode.flutterScene) {
      for (final vol in mesh.volumes) {
        final gb = fscene.GeometryBuilder(deduplicate: false);
        for (int t = 0; t < vol.triangleCount; ++t) {
          final base = t * 9;
          final n = vm.Vector3(
              vol.normals[base], vol.normals[base + 1], vol.normals[base + 2]);
          gb.normal(n);
          final i0 = gb.addVertex(vm.Vector3(
              vol.positions[base],     vol.positions[base + 1], vol.positions[base + 2]));
          final i1 = gb.addVertex(vm.Vector3(
              vol.positions[base + 3], vol.positions[base + 4], vol.positions[base + 5]));
          final i2 = gb.addVertex(vm.Vector3(
              vol.positions[base + 6], vol.positions[base + 7], vol.positions[base + 8]));
          gb.addTriangle(i0, i1, i2);
        }
        final geom = gb.build();
        final mat = fscene.UnlitMaterial()
          ..baseColorFactor = _colorFor(vol.filamentIdx);
        _scene.add(fscene.Node(name: 'vol_${vol.filamentIdx}',
            mesh: fscene.Mesh(geom, mat)));
      }
    }
    // Canvas-mode doesn't touch the scene graph; it reads
    // `_mesh.volumes` directly in CustomPainter.
  }

  vm.Vector4 _colorFor(int idx) {
    final hues = [0.08, 0.33, 0.58, 0.83];
    final h = hues[idx % hues.length];
    final c = HSVColor.fromAHSV(1.0, h * 360.0, 0.75, 0.95).toColor();
    return vm.Vector4(c.r, c.g, c.b, 1.0);
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
        _pitch += delta.dy * 0.01;
        _pitch = _pitch.clamp(-1.4, 1.4);
      });
      _dragStart = d.focalPoint;
    } else {
      _pinchStart ??= d.scale;
      setState(() {
        _distance = (_distStart ?? _distance) / d.scale;
        _distance = _distance.clamp(50.0, 2000.0);
        _pan += d.focalPointDelta;
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
          return fscene.SceneView(
            _scene,
            camera: fscene.PerspectiveCamera(
              position: _cameraPos(),
              target: vm.Vector3(_pan.dx, 0, _pan.dy),
              fovRadiansY: math.pi / 4,
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
            pan: _pan,
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

  vm.Vector3 _cameraPos() {
    final cy = math.cos(_pitch);
    return vm.Vector3(
      _distance * math.sin(_yaw) * cy,
      _distance * math.sin(_pitch),
      _distance * math.cos(_yaw) * cy,
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
    required this.pan,
  });
  final HspmFile mesh;
  final double yaw, pitch, distance;
  final Offset pan;

  @override
  void paint(Canvas canvas, Size size) {
    // Project each triangle to screen with a simple
    // perspective-ish projection (ortho + depth-sort).
    final cx = size.width  / 2 + pan.dx;
    final cy = size.height / 2 + pan.dy;
    final scale = size.shortestSide / (distance * 1.1);
    final cosY = math.cos(yaw),   sinY = math.sin(yaw);
    final cosP = math.cos(pitch), sinP = math.sin(pitch);

    // Collect triangles with their mean depth to resolve front/back.
    final tris = <_Tri>[];
    for (final vol in mesh.volumes) {
      final col = HSVColor.fromAHSV(1.0, (vol.filamentIdx * 90) % 360.0,
                                    0.75, 0.95).toColor();
      final nTri = vol.triangleCount;
      for (int t = 0; t < nTri; ++t) {
        final base = t * 9;
        final v = List<Offset>.filled(3, Offset.zero);
        double meanZ = 0;
        for (int i = 0; i < 3; ++i) {
          final b = base + i * 3;
          final x = vol.positions[b    ];
          final y = vol.positions[b + 1];
          final z = vol.positions[b + 2];
          // Yaw around Z (vertical in printer frame), pitch around X.
          final x1 = x * cosY - y * sinY;
          final y1 = x * sinY + y * cosY;
          final y2 = y1 * cosP - z * sinP;
          final z2 = y1 * sinP + z * cosP;
          v[i] = Offset(cx + x1 * scale, cy - y2 * scale);
          meanZ += z2;
        }
        // Flat shading from triangle normal (rotate the normal
        // the same way).
        final nx = vol.normals[base], ny = vol.normals[base + 1], nz = vol.normals[base + 2];
        final nx1 = nx * cosY - ny * sinY;
        final ny1 = nx * sinY + ny * cosY;
        final ny2 = ny1 * cosP - nz * sinP;
        final nz2 = ny1 * sinP + nz * cosP;
        // Light near-top-down + a tiny fill (same model as the
        // thumbnail renderer, less-strict constants).
        final cosL = (nx1 * 0.15 + ny2 * -0.35 + nz2 * 0.95).clamp(-1.0, 1.0);
        final k = (0.2 + 0.8 * cosL.clamp(0.0, 1.0)).clamp(0.0, 1.0);
        final shade = Color.fromARGB(
          255,
          (col.r * 255 * k).round(),
          (col.g * 255 * k).round(),
          (col.b * 255 * k).round(),
        );
        tris.add(_Tri(v[0], v[1], v[2], meanZ / 3, shade));
      }
    }
    tris.sort((a, b) => b.depth.compareTo(a.depth));

    final paint = Paint()..style = PaintingStyle.fill;
    for (final t in tris) {
      final path = Path()
        ..moveTo(t.a.dx, t.a.dy)
        ..lineTo(t.b.dx, t.b.dy)
        ..lineTo(t.c.dx, t.c.dy)
        ..close();
      paint.color = t.color;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasVertexPainter old) =>
      old.mesh != mesh || old.yaw != yaw || old.pitch != pitch ||
      old.distance != distance || old.pan != pan;
}

class _Tri {
  _Tri(this.a, this.b, this.c, this.depth, this.color);
  final Offset a, b, c;
  final double depth;
  final Color color;
}
