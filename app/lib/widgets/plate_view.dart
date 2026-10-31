// Pflicht 7a — reusable 3D plate view for the project tab.
//
// Loads an .hspm (handslice preview mesh) and renders it with
// flutter_scene (Impeller / Flutter GPU) on top of a CC2
// 256×256 bed quad. Shading is a flat Lambert pre-baked into
// per-vertex colour at load time, so the material is a plain
// `UnlitMaterial(vertexColorWeight=1)` and there is no per-
// frame lighting cost.
//
// Controls:
//   one-finger drag        : orbit
//   two-finger drag        : pan (world-space, along camera axes)
//   two-finger pinch       : zoom
//   Reset / Top / Front / Oblique: standard views
//
// Fallback: when `Scene.initializeStaticResources()` or the
// first `SceneView` throws, the widget switches to a
// 2D `HSPB` image (raw-RGBA bytes rendered by the CLI's
// software rasterizer, Pflicht 6 / Variant C). The 3D controls
// hide; the Reset button becomes a reload-cache button.
//
// This widget intentionally takes no benchmark responsibility
// (fps counter, memory probe, …); it is the production surface.
// The benchmark screen keeps its own stats overlay.

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fscene;
import 'package:vector_math/vector_math.dart' as vm;

// -------- .hspm parser (duplicated small, see plate_bench_screen) --------

class HspmVolume {
  HspmVolume({required this.filamentIdx,
              required this.positions,
              required this.normals});
  final int filamentIdx;
  final Float32List positions;   // 9 floats per triangle
  final Float32List normals;     // 9 floats per triangle (flat normal × 3)
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
      final fidx = bd.getUint32(off, Endian.little); off += 4;
      final ntri = bd.getUint32(off, Endian.little); off += 4;
      final pos = Float32List(ntri * 9);
      final nml = Float32List(ntri * 9);
      for (int t = 0; t < ntri; ++t) {
        final tbase = t * 9;
        for (int vi = 0; vi < 3; ++vi) {
          final b = tbase + vi * 3;
          pos[b    ] = bd.getFloat32(off, Endian.little); off += 4;
          pos[b + 1] = bd.getFloat32(off, Endian.little); off += 4;
          pos[b + 2] = bd.getFloat32(off, Endian.little); off += 4;
          nml[b    ] = bd.getFloat32(off, Endian.little); off += 4;
          nml[b + 1] = bd.getFloat32(off, Endian.little); off += 4;
          nml[b + 2] = bd.getFloat32(off, Endian.little); off += 4;
        }
      }
      out.add(HspmVolume(filamentIdx: fidx, positions: pos, normals: nml));
    }
  }
  return HspmFile(volumes: out);
}

// -------- .hspb (fallback) parser --------
//
// 'HSPB' + u32 version=1 + u32 w + u32 h + rgba bytes.
Future<ui.Image> loadHspbImage(String path) async {
  final bytes = await File(path).readAsBytes();
  if (bytes.length < 16 ||
      bytes[0] != 0x48 || bytes[1] != 0x53 ||
      bytes[2] != 0x50 || bytes[3] != 0x42) {
    throw const FormatException('not an HSPB file');
  }
  final bd = ByteData.sublistView(bytes);
  final version = bd.getUint32(4, Endian.little);
  if (version != 1) {
    throw FormatException('unsupported HSPB version $version');
  }
  final w = bd.getUint32(8, Endian.little);
  final h = bd.getUint32(12, Endian.little);
  final pixels = Uint8List.sublistView(bytes, 16);
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888,
      completer.complete);
  return completer.future;
}

// -------- the widget --------

/// A plate-view renderer that loads [hspmPath] and shows the mesh
/// in [filamentColor] on top of a CC2 bed. If flutter_scene fails
/// to start, falls back to [fallbackImagePath] (an HSPB from the
/// CLI's software rasterizer).
class PlateView extends StatefulWidget {
  const PlateView({
    super.key,
    required this.hspmPath,
    required this.filamentColor,
    this.fallbackImagePath,
    this.onInteractionChanged,
    this.labelResetView = 'Reset view',
    this.labelTop = 'Top',
    this.labelFront = 'Front',
    this.labelOblique = 'Oblique',
    this.labelZoomIn = 'Zoom in',
    this.labelZoomOut = 'Zoom out',
    this.labelEmpty = 'Open a model to see the plate view.',
    this.labelBuilding = 'Building preview mesh…',
  });

  final String? hspmPath;
  final Color filamentColor;
  final String? fallbackImagePath;
  /// Fires `true` when a pointer lands on the viewport and `false`
  /// once the last pointer is released. Parents inside a scroll
  /// view should use this to switch the scroll physics to
  /// `NeverScrollableScrollPhysics` so pinches do not fight the
  /// outer scroll gesture — see `plate-view-benchmark.md`.
  final ValueChanged<bool>? onInteractionChanged;
  final String labelResetView;
  final String labelTop;
  final String labelFront;
  final String labelOblique;
  final String labelZoomIn;
  final String labelZoomOut;
  final String labelEmpty;
  final String labelBuilding;

  @override
  State<PlateView> createState() => _PlateViewState();
}

class _PlateViewState extends State<PlateView> {
  // Flutter GPU is required for `Scene()`, and it throws in
  // environments where Impeller is not enabled (flutter_test,
  // older release builds without the manifest opt-in). We
  // therefore construct the Scene lazily inside _initScene with
  // a try/catch so the widget degrades to the HSPB thumbnail /
  // empty-state card instead of taking down the whole screen.
  fscene.Scene? _scene;
  bool _sceneReady = false;
  String? _sceneError;
  HspmFile? _mesh;
  String? _loadedFrom;
  ui.Image? _fallbackImage;

  vm.Vector3 _orbitCentre = vm.Vector3.zero();
  double _orbitRadius = 100.0;
  double _yaw = 0.6;
  double _pitch = 0.5;
  double _distance = 500.0;
  vm.Vector3 _panOffset = vm.Vector3.zero();

  static const double _fovY = math.pi / 4;

  // World-space key light, matches the thumbnail renderer and the
  // benchmark screen so plate view and PNG fallback read the same.
  static final vm.Vector3 _keyLight = vm.Vector3(0.3, -0.3, 0.9)..normalize();
  static const double _ambient = 0.25;

  @override
  void initState() {
    super.initState();
    _initScene();
    _loadMeshIfNeeded();
  }

  @override
  void didUpdateWidget(covariant PlateView old) {
    super.didUpdateWidget(old);
    if (old.hspmPath != widget.hspmPath ||
        old.filamentColor != widget.filamentColor) {
      _loadMeshIfNeeded();
    }
    if (old.fallbackImagePath != widget.fallbackImagePath) {
      _fallbackImage = null;
    }
  }

  Future<void> _initScene() async {
    try {
      _scene = fscene.Scene();
      await fscene.Scene.initializeStaticResources();
      if (mounted) setState(() { _sceneReady = true; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _sceneError = e.toString().split('\n').first; });
    }
  }

  Future<void> _loadMeshIfNeeded() async {
    final path = widget.hspmPath;
    if (path == null) {
      setState(() { _mesh = null; _loadedFrom = null; });
      return;
    }
    if (path == _loadedFrom) {
      // Only the tint changed — rebuild the scene with new colors.
      _rebuildScene();
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      final mesh = parseHspm(bytes.buffer.asByteData());
      if (!mounted) return;
      _mesh = mesh;
      _loadedFrom = path;
      _frameCameraOnMesh(mesh);
      _rebuildScene();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sceneError = 'HSPM load failed: ${e.toString().split('\n').first}';
      });
    }
  }

  void _frameCameraOnMesh(HspmFile mesh) {
    double minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
    for (final v in mesh.volumes) {
      final p = v.positions;
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
    // Hull with the bed so the plate stays visible even on tiny
    // models.
    if (0 < minX) minX = 0; if (0 < minY) minY = 0; if (0 < minZ) minZ = 0;
    if (256 > maxX) maxX = 256; if (256 > maxY) maxY = 256;
    final centre = vm.Vector3((minX + maxX) * 0.5, (minY + maxY) * 0.5,
                              (minZ + maxZ) * 0.5);
    final extent = vm.Vector3(maxX - minX, maxY - minY, maxZ - minZ);
    final radius = math.max(extent.length * 0.5, 1.0);
    _orbitCentre = centre;
    _orbitRadius = radius;
    _distance = radius / math.sin(_fovY / 2) * 1.3;
    _panOffset.setZero();
    _yaw = 0.6;
    _pitch = 0.5;
  }

  void _rebuildScene() {
    final scene = _scene;
    if (scene == null) return;   // Flutter GPU not available on this host
    final mesh = _mesh;
    scene.root.children.clear();
    _addPlate(scene);
    if (mesh == null) return;
    final tintR = widget.filamentColor.r;
    final tintG = widget.filamentColor.g;
    final tintB = widget.filamentColor.b;
    final lx = _keyLight.x, ly = _keyLight.y, lz = _keyLight.z;
    const a = _ambient;
    const b = 1.0 - a;
    for (final vol in mesh.volumes) {
      final nTris = vol.triangleCount;
      if (nTris == 0) continue;
      final nVerts = nTris * 3;
      final colors = Float32List(nVerts * 4);
      final normals = vol.normals;
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
        positions: vol.positions,
        normals: normals,
        colors: colors,
        retainCpuData: false,
      );
      final mat = fscene.UnlitMaterial()
        ..baseColorFactor = vm.Vector4(1, 1, 1, 1);
      scene.add(fscene.Node(name: 'vol_${vol.filamentIdx}',
          mesh: fscene.Mesh(geom, mat)));
    }
  }

  void _addPlate(fscene.Scene scene) {
    final gb = fscene.GeometryBuilder(deduplicate: false);
    final n = vm.Vector3(0, 0, 1);
    const a = _ambient;
    const b = 1.0 - a;
    final dot = (n.x * _keyLight.x + n.y * _keyLight.y + n.z * _keyLight.z).abs();
    final k = a + b * dot;
    final c = vm.Vector4(0.18 * k, 0.19 * k, 0.21 * k, 1.0);
    gb.normal(n);
    gb.color(c);
    final i0 = gb.addVertex(vm.Vector3(0,   0,   0));
    final i1 = gb.addVertex(vm.Vector3(256, 0,   0));
    final i2 = gb.addVertex(vm.Vector3(256, 256, 0));
    final i3 = gb.addVertex(vm.Vector3(0,   256, 0));
    gb.addTriangle(i0, i1, i2);
    gb.addTriangle(i0, i2, i3);
    final geom = gb.build();
    final mat = fscene.UnlitMaterial()
      ..baseColorFactor = vm.Vector4(1, 1, 1, 1);
    scene.add(fscene.Node(name: 'bed', mesh: fscene.Mesh(geom, mat)));
  }

  // -------- gestures --------
  //
  // We handle pointer events via `Listener` rather than
  // `GestureDetector` because the project screen is inside a
  // `ListView` and the gesture arena will not reliably give
  // `ScaleGestureRecognizer` the two-finger pinch — the scroll
  // view wins. `Listener` sits outside the arena, so we always
  // get the raw events; the outer scroll is suppressed by the
  // project-screen `ListView` switching its physics to
  // `NeverScrollableScrollPhysics()` while a pointer is on the
  // viewport (see `onInteractionChanged`).
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDist;
  double? _pinchStartDistance;
  Offset? _lastCentroid;

  void _handlePointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    _resetPinchAnchors();
    if (_pointers.length == 1) widget.onInteractionChanged?.call(true);
  }

  void _handlePointerMove(PointerMoveEvent e) {
    final prev = _pointers[e.pointer] ?? e.localPosition;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      final delta = e.localPosition - prev;
      setState(() {
        _yaw   += delta.dx * 0.01;
        _pitch += delta.dy * 0.01;
        _pitch = _pitch.clamp(-1.4, 1.4);
      });
    } else {
      _applyMultiPointer();
    }
  }

  void _handlePointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) {
      _pinchStartDist = null;
      _pinchStartDistance = null;
      _lastCentroid = null;
    }
    if (_pointers.isEmpty) widget.onInteractionChanged?.call(false);
  }

  void _resetPinchAnchors() {
    _pinchStartDist = null;
    _pinchStartDistance = null;
    _lastCentroid = null;
  }

  void _applyMultiPointer() {
    final ptrs = _pointers.values.toList();
    final centroid = Offset(
        ptrs.fold<double>(0, (a, p) => a + p.dx) / ptrs.length,
        ptrs.fold<double>(0, (a, p) => a + p.dy) / ptrs.length);
    double dist = 0;
    for (int i = 0; i < ptrs.length; ++i) {
      for (int j = i + 1; j < ptrs.length; ++j) {
        dist += (ptrs[i] - ptrs[j]).distance;
      }
    }
    _pinchStartDist     ??= dist;
    _pinchStartDistance ??= _distance;
    _lastCentroid       ??= centroid;
    final zoomFactor = _pinchStartDist! / math.max(dist, 1e-3);
    final panDelta = centroid - _lastCentroid!;
    _lastCentroid = centroid;
    setState(() {
      _distance = (_pinchStartDistance! * zoomFactor)
          .clamp(_orbitRadius * 0.3, _orbitRadius * 20.0);
      final k = _distance * 0.0025;
      final right = vm.Vector3(math.cos(_yaw), math.sin(_yaw), 0);
      final up = vm.Vector3(
          -math.sin(_pitch) * math.sin(_yaw),
           math.sin(_pitch) * math.cos(_yaw),
           math.cos(_pitch));
      _panOffset += right * (panDelta.dx * k)
                  + up    * (panDelta.dy * k);
    });
  }

  void _nudgeZoom(double factor) {
    setState(() {
      _distance = (_distance * factor)
          .clamp(_orbitRadius * 0.3, _orbitRadius * 20.0);
    });
  }

  vm.Vector3 _cameraPos(vm.Vector3 target) {
    final cp = math.cos(_pitch);
    final sp = math.sin(_pitch);
    return target + vm.Vector3(
      _distance * cp * math.sin(_yaw),
      -_distance * cp * math.cos(_yaw),
       _distance * sp,
    );
  }

  // -------- standard views --------
  void _applyView({required double yaw, required double pitch,
                   bool resetPan = true, bool resetZoom = true}) {
    setState(() {
      _yaw = yaw;
      _pitch = pitch;
      if (resetZoom) {
        _distance = _orbitRadius / math.sin(_fovY / 2) * 1.3;
      }
      if (resetPan) _panOffset.setZero();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hspmPath == null) {
      return _emptyStateBox(widget.labelEmpty);
    }
    if (_sceneError != null || widget.fallbackImagePath != null && !_sceneReady) {
      // Try fallback image if we have a path to one — do not block
      // on scene init if we already have a static image we can show.
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _viewport(),
          ),
        ),
        const SizedBox(height: 8),
        _viewButtonsRow(),
      ],
    );
  }

  Widget _emptyStateBox(String msg) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
        ),
      ),
    );
  }

  Widget _viewport() {
    if (_sceneError != null) return _fallbackViewport();
    if (!_sceneReady || _mesh == null) {
      return Container(
        color: Colors.black26,
        alignment: Alignment.center,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }
    final scene = _scene;
    if (scene == null) return _fallbackViewport();
    try {
      final target = _orbitCentre + _panOffset;
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerUp,
        child: fscene.SceneView(
          scene,
          warmUp: true,
          camera: fscene.PerspectiveCamera(
            position: _cameraPos(target),
            target: target,
            up: vm.Vector3(0, 0, 1),
            fovRadiansY: _fovY,
            fovNear: _distance * 0.01,
            fovFar: _distance * 50.0,
          ),
        ),
      );
    } catch (e) {
      _sceneError = e.toString().split('\n').first;
      return _fallbackViewport();
    }
  }

  Widget _fallbackViewport() {
    final path = widget.fallbackImagePath;
    if (path == null) {
      return _emptyStateBox('3D preview unavailable on this device.');
    }
    // Lazy-load the HSPB.
    if (_fallbackImage == null) {
      loadHspbImage(path).then((img) {
        if (mounted) setState(() { _fallbackImage = img; });
      }).catchError((_) {});
      return Container(
        color: Colors.black26,
        alignment: Alignment.center,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return RawImage(image: _fallbackImage, fit: BoxFit.contain);
  }

  Widget _viewButtonsRow() {
    final usingFallback = _sceneError != null;
    // Focus traversal: wrap in a FocusTraversalGroup so the six
    // buttons form their own group inside the project ListView.
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _viewBtn(widget.labelResetView,
                  Icons.center_focus_strong,
                  onPressed: usingFallback ? null : () => _applyView(
                      yaw: 0.6, pitch: 0.5))),
              const SizedBox(width: 6),
              Expanded(child: _viewBtn(widget.labelTop,
                  Icons.vertical_align_top,
                  onPressed: usingFallback ? null : () => _applyView(
                      yaw: 0.0, pitch: 1.3))),
              const SizedBox(width: 6),
              Expanded(child: _viewBtn(widget.labelFront,
                  Icons.align_horizontal_center,
                  onPressed: usingFallback ? null : () => _applyView(
                      yaw: 0.0, pitch: 0.0))),
              const SizedBox(width: 6),
              Expanded(child: _viewBtn(widget.labelOblique,
                  Icons.threed_rotation,
                  onPressed: usingFallback ? null : () => _applyView(
                      yaw: 0.6, pitch: 0.5))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _viewBtn(widget.labelZoomOut, Icons.zoom_out,
                  onPressed: usingFallback ? null : () => _nudgeZoom(1.25))),
              const SizedBox(width: 6),
              Expanded(child: _viewBtn(widget.labelZoomIn, Icons.zoom_in,
                  onPressed: usingFallback ? null : () => _nudgeZoom(0.8))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _viewBtn(String label, IconData icon, {VoidCallback? onPressed}) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}
