// Pflicht 7b — layer preview after a slice.
//
// Reads a `GcodeGeometry` (produced by `app/lib/engine/gcode_parser
// .dart`) and renders the extrusion paths of every layer up to the
// slider's current index. Current layer is tinted brighter so the
// eye can follow the slider. Rendering uses
// `flutter_scene.LineSegmentsGeometry`, which draws thousands of
// camera-facing ribbons in a single instanced call.
//
// The widget also offers a 2D top-down fallback (CustomPaint, pure
// Dart) for the current layer — useful on devices where the GPU-
// line path gets too expensive. The user can switch between 3D
// and 2D at any time.
//
// Camera orbit, pan, pinch and the standard-view buttons are the
// same as `PlateView`, so the two surfaces behave identically.
// The outer `ListView` disables its physics while a pointer is on
// the viewport (same `onInteractionChanged` callback contract as
// `PlateView`).

// ignore_for_file: depend_on_referenced_packages

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fscene;
import 'package:vector_math/vector_math.dart' as vm;

import '../engine/gcode_parser.dart';
import 'orbit_scene_bed.dart';

/// Palette used both by the 3D line-segments material and the 2D
/// painter. Shaded a touch darker than Orca's defaults so the
/// current-layer highlight (same hue, full brightness) reads as
/// "lit" against the stack.
const Map<PathType, Color> kPathTypeColors = {
  PathType.travel:           Color(0xFF6B7280),
  PathType.outerWall:        Color(0xFFEF4444),
  PathType.innerWall:        Color(0xFFF59E0B),
  PathType.internalInfill:   Color(0xFFFBBF24),
  PathType.solidInfill:      Color(0xFF84CC16),
  PathType.topSurface:       Color(0xFF22D3EE),
  PathType.bottomSurface:    Color(0xFF14B8A6),
  PathType.bridge:           Color(0xFFEC4899),
  PathType.support:          Color(0xFF8B5CF6),
  PathType.supportInterface: Color(0xFFA78BFA),
  PathType.skirtBrim:        Color(0xFF60A5FA),
  PathType.primeTower:       Color(0xFFF472B6),
  PathType.custom:           Color(0xFF94A3B8),
  PathType.unknown:          Color(0xFF9CA3AF),
};

enum LayerRendererMode { three, twoDTopDown }

class LayerViewLabels {
  const LayerViewLabels({
    required this.layer,
    required this.of,
    required this.resetView,
    required this.top,
    required this.front,
    required this.oblique,
    required this.zoomIn,
    required this.zoomOut,
    required this.pathTypes,
    required this.filamentColors,
    required this.showTravel,
    required this.renderer3d,
    required this.renderer2d,
    required this.decrementLayer,
    required this.incrementLayer,
    required this.typeLabel,
  });
  final String layer;
  final String of;
  final String resetView;
  final String top;
  final String front;
  final String oblique;
  final String zoomIn;
  final String zoomOut;
  final String pathTypes;
  final String filamentColors;
  final String showTravel;
  final String renderer3d;
  final String renderer2d;
  final String decrementLayer;
  final String incrementLayer;
  final String Function(PathType) typeLabel;
}

class LayerView extends StatefulWidget {
  const LayerView({
    super.key,
    required this.geometry,
    required this.labels,
    this.onInteractionChanged,
  });
  final GcodeGeometry geometry;
  final LayerViewLabels labels;
  final ValueChanged<bool>? onInteractionChanged;

  @override
  State<LayerView> createState() => _LayerViewState();
}

class _LayerViewState extends State<LayerView> {
  fscene.Scene? _scene;
  bool _sceneReady = false;
  String? _sceneError;
  int _currentLayer = 0;
  LayerRendererMode _mode = LayerRendererMode.three;
  // Visibility toggles per path type. Travel off by default.
  final Set<PathType> _visibleTypes = PathType.values.toSet()
    ..remove(PathType.travel);
  // Flag reserved for the "by filament" mode (not yet implemented;
  // Pflicht 7b asks us to prepare the toggle only).
  bool _colorByFilament = false;

  vm.Vector3 _orbitCentre = vm.Vector3.zero();
  double _orbitRadius = 100.0;
  double _yaw = 0.6;
  double _pitch = 0.5;
  double _distance = 500.0;
  vm.Vector3 _panOffset = vm.Vector3.zero();
  static const double _fovY = math.pi / 4;

  @override
  void initState() {
    super.initState();
    _currentLayer = widget.geometry.layerCount - 1;
    _frameCamera();
    _initScene();
  }

  @override
  void didUpdateWidget(covariant LayerView old) {
    super.didUpdateWidget(old);
    if (!identical(old.geometry, widget.geometry)) {
      _currentLayer = widget.geometry.layerCount - 1;
      _frameCamera();
      _rebuildScene();
    }
  }

  Future<void> _initScene() async {
    try {
      _scene = fscene.Scene();
      await fscene.Scene.initializeStaticResources();
      if (!mounted) return;
      setState(() { _sceneReady = true; });
      _rebuildScene();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sceneError = e.toString().split('\n').first;
        // Fall back to 2D so the user still sees something.
        _mode = LayerRendererMode.twoDTopDown;
      });
    }
  }

  void _frameCamera() {
    // Same framing logic as PlateView: AABB of the content joined
    // with the CC2 bed, orbit around its centre, start distance
    // = radius / sin(fovY/2) * 1.3.
    final g = widget.geometry;
    final modelAabb = vm.Aabb3.minMax(
        vm.Vector3(g.minX, g.minY, g.minZ),
        vm.Vector3(g.maxX, g.maxY, g.maxZ));
    final aabb = hullWithBed(modelAabb);
    final centre = (aabb.min + aabb.max) * 0.5;
    final extent = aabb.max - aabb.min;
    final radius = math.max(extent.length * 0.5, 50.0);
    _orbitCentre = centre;
    _orbitRadius = radius;
    _distance = radius / math.sin(_fovY / 2) * 1.3;
    _panOffset.setZero();
    _yaw = 0.6; _pitch = 0.5;
  }

  // -------- scene rebuild --------
  //
  // Keep one node per path type (dim, layers 0..L-1) plus one
  // node per visible type for the current layer (bright). Travel
  // moves are hidden by default. Scene is cleared and rebuilt on
  // every layer-slider change — a sparse-byte copy per rebuild;
  // for 2 M segments this is well under 100 ms on the Poco.
  void _rebuildScene() {
    final scene = _scene;
    if (scene == null || !_sceneReady) return;
    // `children.clear()` leaves nodes mounted in the render
    // scene — see the long comment in ToolpathLayerView._rebuild
    // Scene. `removeAll()` is the correct unmount path.
    scene.root.removeAll();
    // CC2 bed — same shared quad PlateView uses.
    addBedToScene(scene);
    final g = widget.geometry;
    if (g.segmentCount == 0 || g.layerCount == 0) return;
    final maxLayer = _currentLayer.clamp(0, g.layerCount - 1);
    final endOfBelow = g.layerStart(maxLayer);
    final endOfCurrent = g.layerEnd(maxLayer);
    for (final type in PathType.values) {
      if (!_visibleTypes.contains(type)) continue;
      final color = kPathTypeColors[type]!;
      // Line widths tuned to the CC2 default extrusion width
      // (0.42 mm — matches `;WIDTH:0.42` lines Orca emits for
      // outer walls on the 0.4 nozzle profile). Earlier 1.1 mm
      // ribbons on dense layers merged into solid faces, which
      // is what Klaus hit on the 7b device test. Dim stacks run
      // at 0.25 mm so wall topology is still readable.
      _emitSlice(scene,
          g: g, type: type, color: color,
          dim: true,
          width: 0.25,
          from: 0, to: endOfBelow);
      _emitSlice(scene,
          g: g, type: type, color: color,
          dim: false,
          width: 0.42,
          from: endOfBelow, to: endOfCurrent);
    }
  }

  void _emitSlice(fscene.Scene scene, {
    required GcodeGeometry g,
    required PathType type,
    required Color color,
    required bool dim,
    required double width,
    required int from,
    required int to,
  }) {
    if (to <= from) return;
    // Count matches first so we allocate exactly.
    final typeCode = type.code;
    final types = g.types;
    int count = 0;
    for (int i = from; i < to; ++i) {
      if (types[i] == typeCode) count++;
    }
    if (count == 0) return;
    final out = Float32List(count * 6);
    final src = g.positions;
    int o = 0;
    for (int i = from; i < to; ++i) {
      if (types[i] != typeCode) continue;
      final s = i * 6;
      out[o    ] = src[s    ]; out[o + 1] = src[s + 1]; out[o + 2] = src[s + 2];
      out[o + 3] = src[s + 3]; out[o + 4] = src[s + 4]; out[o + 5] = src[s + 5];
      o += 6;
    }
    final data = fscene.LineSegmentData(positions: out);
    final geom = fscene.LineSegmentsGeometry(data, width: width);
    final tint = dim ? _dimmed(color) : color;
    final mat = fscene.UnlitMaterial()
      ..baseColorFactor = vm.Vector4(
          tint.r, tint.g, tint.b, 1.0);
    scene.add(fscene.Node(
        name: 'type${type.code}_${dim ? "dim" : "cur"}',
        mesh: fscene.Mesh(geom, mat)));
  }

  // Stronger dim factor than before (0.35 vs 0.55) so the bright
  // current-layer tint pops against the stack. Picked by eye on
  // the x86 host; Klaus can tune on the device run.
  Color _dimmed(Color c) => Color.from(
      alpha: 1.0, red: c.r * 0.35, green: c.g * 0.35, blue: c.b * 0.35);

  // -------- gestures (same contract as PlateView) --------
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDist;
  double? _pinchStartDistance;
  Offset? _lastCentroid;

  void _handlePointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    _pinchStartDist = null;
    _pinchStartDistance = null;
    _lastCentroid = null;
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
      final ptrs = _pointers.values.toList();
      final cx = ptrs.fold<double>(0, (a, p) => a + p.dx) / ptrs.length;
      final cy = ptrs.fold<double>(0, (a, p) => a + p.dy) / ptrs.length;
      final centroid = Offset(cx, cy);
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

  vm.Vector3 _cameraPos(vm.Vector3 target) {
    final cp = math.cos(_pitch), sp = math.sin(_pitch);
    return target + vm.Vector3(
      _distance * cp * math.sin(_yaw),
      -_distance * cp * math.cos(_yaw),
       _distance * sp,
    );
  }

  // -------- view presets --------
  void _applyView({required double yaw, required double pitch}) {
    setState(() {
      _yaw = yaw;
      _pitch = pitch;
      _distance = _orbitRadius / math.sin(_fovY / 2) * 1.3;
      _panOffset.setZero();
    });
  }
  void _nudgeZoom(double factor) {
    setState(() {
      _distance = (_distance * factor)
          .clamp(_orbitRadius * 0.3, _orbitRadius * 20.0);
    });
  }
  void _setLayer(int l) {
    final g = widget.geometry;
    final clamped = l.clamp(0, g.layerCount - 1);
    if (clamped == _currentLayer) return;
    setState(() { _currentLayer = clamped; });
    _rebuildScene();
  }

  // -------- build --------
  @override
  Widget build(BuildContext context) {
    final l = widget.labels;
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
        _layerControlsRow(l),
        const SizedBox(height: 6),
        _viewButtonsRow(l),
        const SizedBox(height: 8),
        _legend(l),
      ],
    );
  }

  Widget _viewport() {
    if (_mode == LayerRendererMode.twoDTopDown) {
      return _TopDownPainterView(
        geometry: widget.geometry,
        visibleTypes: _visibleTypes,
        currentLayer: _currentLayer.clamp(0, widget.geometry.layerCount - 1),
      );
    }
    final scene = _scene;
    if (_sceneError != null || scene == null) {
      // Fallback to 2D if 3D is dead.
      return _TopDownPainterView(
        geometry: widget.geometry,
        visibleTypes: _visibleTypes,
        currentLayer: _currentLayer.clamp(0, widget.geometry.layerCount - 1),
      );
    }
    if (!_sceneReady) {
      return Container(
        color: Colors.black26,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }
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
  }

  Widget _layerControlsRow(LayerViewLabels l) {
    final g = widget.geometry;
    final maxLayer = (g.layerCount - 1).clamp(0, 1 << 30);
    final value = _currentLayer.clamp(0, maxLayer);
    return Row(
      children: [
        IconButton(
          tooltip: l.decrementLayer,
          icon: const Icon(Icons.remove),
          onPressed: value > 0 ? () => _setLayer(value - 1) : null,
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: maxLayer.toDouble(),
            divisions: maxLayer > 0 ? maxLayer : null,
            label: '${l.layer} ${value + 1} ${l.of} ${g.layerCount}',
            onChanged: (v) => _setLayer(v.round()),
          ),
        ),
        IconButton(
          tooltip: l.incrementLayer,
          icon: const Icon(Icons.add),
          onPressed: value < maxLayer ? () => _setLayer(value + 1) : null,
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 72,
          child: Text(
            '${value + 1}/${g.layerCount}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _viewButtonsRow(LayerViewLabels l) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(children: [
        Row(children: [
          Expanded(child: _viewBtn(l.resetView, Icons.center_focus_strong,
              onPressed: () => _applyView(yaw: 0.6, pitch: 0.5))),
          const SizedBox(width: 6),
          Expanded(child: _viewBtn(l.top, Icons.vertical_align_top,
              onPressed: () => _applyView(yaw: 0.0, pitch: 1.3))),
          const SizedBox(width: 6),
          Expanded(child: _viewBtn(l.front, Icons.align_horizontal_center,
              onPressed: () => _applyView(yaw: 0.0, pitch: 0.0))),
          const SizedBox(width: 6),
          Expanded(child: _viewBtn(l.oblique, Icons.threed_rotation,
              onPressed: () => _applyView(yaw: 0.6, pitch: 0.5))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _viewBtn(l.zoomOut, Icons.zoom_out,
              onPressed: () => _nudgeZoom(1.25))),
          const SizedBox(width: 6),
          Expanded(child: _viewBtn(l.zoomIn, Icons.zoom_in,
              onPressed: () => _nudgeZoom(0.8))),
        ]),
        const SizedBox(height: 6),
        SegmentedButton<LayerRendererMode>(
          segments: [
            ButtonSegment(
                value: LayerRendererMode.three, label: Text(l.renderer3d)),
            ButtonSegment(
                value: LayerRendererMode.twoDTopDown, label: Text(l.renderer2d)),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() { _mode = s.first; }),
        ),
      ]),
    );
  }

  Widget _viewBtn(String label, IconData icon, {VoidCallback? onPressed}) =>
      OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, overflow: TextOverflow.ellipsis),
      );

  Widget _legend(LayerViewLabels l) {
    // Toggle: by type vs by filament (prepared, 7b builds only the
    // by-type path; the by-filament branch is a view-only switch
    // we flesh out once multi-filament prints land).
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text(l.pathTypes,
              style: theme.textTheme.titleSmall)),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(l.pathTypes)),
              ButtonSegment(value: true, label: Text(l.filamentColors)),
            ],
            selected: {_colorByFilament},
            onSelectionChanged: (s) {
              setState(() { _colorByFilament = s.first; });
            },
          ),
        ]),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final type in PathType.values)
              _legendChip(type, l),
          ],
        ),
      ],
    );
  }

  Widget _legendChip(PathType type, LayerViewLabels l) {
    final visible = _visibleTypes.contains(type);
    final c = kPathTypeColors[type]!;
    return FilterChip(
      selected: visible,
      showCheckmark: false,
      avatar: Container(
        decoration: BoxDecoration(
          color: c, shape: BoxShape.circle,
          border: Border.all(color: Colors.black26),
        ),
        width: 14, height: 14,
      ),
      label: Text(l.typeLabel(type)),
      onSelected: (v) {
        setState(() {
          if (v) {
            _visibleTypes.add(type);
          } else {
            _visibleTypes.remove(type);
          }
        });
        _rebuildScene();
      },
    );
  }
}

// -------- 2D top-down painter --------
//
// Draws the current layer's segments as thin lines onto an
// orthographic top-down projection. Pure Dart, no GPU.
class _TopDownPainterView extends StatelessWidget {
  const _TopDownPainterView({
    required this.geometry,
    required this.visibleTypes,
    required this.currentLayer,
  });
  final GcodeGeometry geometry;
  final Set<PathType> visibleTypes;
  final int currentLayer;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1D23),
      child: CustomPaint(
        size: Size.infinite,
        painter: _TopDownPainter(
          geometry: geometry,
          visibleTypes: visibleTypes,
          currentLayer: currentLayer,
        ),
      ),
    );
  }
}

class _TopDownPainter extends CustomPainter {
  _TopDownPainter({
    required this.geometry,
    required this.visibleTypes,
    required this.currentLayer,
  });
  final GcodeGeometry geometry;
  final Set<PathType> visibleTypes;
  final int currentLayer;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    if (g.segmentCount == 0 || g.layerCount == 0) return;
    final from = g.layerStart(currentLayer);
    final to   = g.layerEnd(currentLayer);
    if (to <= from) return;
    // Per-axis bounds so a model that is not centred on the bed
    // (notched cube at X≈128, Y≈126) still draws in the middle
    // of the viewport instead of using a square XY union that
    // offsets both axes to the combined centre.
    final rangeX = (g.maxX - g.minX).clamp(1.0, double.infinity);
    final rangeY = (g.maxY - g.minY).clamp(1.0, double.infinity);
    final maxRange = math.max(rangeX, rangeY);
    final scale = math.min(size.width, size.height) / maxRange * 0.9;
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final midX = (g.minX + g.maxX) * 0.5;
    final midY = (g.minY + g.maxY) * 0.5;
    // Flutter screen Y points down; printer Y points away from
    // the operator (front = Y low, back = Y high). We invert so
    // the "back" of the bed sits at the top of the preview,
    // matching Orca's top-down convention.
    double toScreenX(double x) => cx + (x - midX) * scale;
    double toScreenY(double y) => cy - (y - midY) * scale;
    // Paint each type separately so the colour stroke is one path.
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final type in PathType.values) {
      if (!visibleTypes.contains(type)) continue;
      final code = type.code;
      final path = Path();
      bool any = false;
      for (int i = from; i < to; ++i) {
        if (g.types[i] != code) continue;
        final s = i * 6;
        final x0 = g.positions[s    ], y0 = g.positions[s + 1];
        final x1 = g.positions[s + 3], y1 = g.positions[s + 4];
        path.moveTo(toScreenX(x0), toScreenY(y0));
        path.lineTo(toScreenX(x1), toScreenY(y1));
        any = true;
      }
      if (!any) continue;
      paint.color = kPathTypeColors[type]!;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TopDownPainter old) =>
      old.geometry != geometry ||
      old.currentLayer != currentLayer ||
      !_setEquals(old.visibleTypes, visibleTypes);

  static bool _setEquals<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    for (final x in a) {
      if (!b.contains(x)) return false;
    }
    return true;
  }
}
