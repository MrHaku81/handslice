// Pflicht 7c — layer preview backed by the CLI's HSPT binary.
//
// Mirrors `LayerView` (same gestures, same bed quad, same
// focus-navigable button layout) but consumes a `Toolpaths`
// object produced by `handslice-cli --export-toolpaths`. Colours
// come straight from Orca's palette (see `OrcaPalette`), default
// visibilities match Orca (`OrcaDefaults`). The current layer
// draws brighter and thicker; layers below render dimmed and
// thin so the eye can follow the slider on a dense cube top.
//
// Line thickness is per-geometry (flutter_scene limitation), so
// we use the width from the first extruding move of each role
// — a working-set that matches Orca's "0.42 mm outer / 0.42 mm
// inner" in the default CC2 process. Per-move ribbons that
// change thickness mid-path are a shader feature we leave for a
// follow-up.

// ignore_for_file: depend_on_referenced_packages

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fscene;
import 'package:vector_math/vector_math.dart' as vm;

import '../engine/toolpath_parser.dart';
import 'orbit_scene_bed.dart';

class ToolpathLayerViewLabels {
  const ToolpathLayerViewLabels({
    required this.layer,
    required this.of,
    required this.resetView,
    required this.top,
    required this.front,
    required this.oblique,
    required this.zoomIn,
    required this.zoomOut,
    required this.pathTypes,
    required this.renderer3d,
    required this.renderer2d,
    required this.decrementLayer,
    required this.incrementLayer,
    required this.roleLabel,
    required this.moveLabel,
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
  final String renderer3d;
  final String renderer2d;
  final String decrementLayer;
  final String incrementLayer;
  final String Function(GcodeRole) roleLabel;
  final String Function(MoveType) moveLabel;
}

enum _RendererMode { three, twoDTopDown }

class ToolpathLayerView extends StatefulWidget {
  const ToolpathLayerView({
    super.key,
    required this.toolpaths,
    required this.labels,
    this.onInteractionChanged,
  });
  final Toolpaths toolpaths;
  final ToolpathLayerViewLabels labels;
  final ValueChanged<bool>? onInteractionChanged;

  @override
  State<ToolpathLayerView> createState() => _ToolpathLayerViewState();
}

class _ToolpathLayerViewState extends State<ToolpathLayerView> {
  fscene.Scene? _scene;
  bool _sceneReady = false;
  String? _sceneError;
  int _currentLayer = 0;
  _RendererMode _mode = _RendererMode.three;

  final Set<GcodeRole> _visibleRoles = Set.of(OrcaDefaults.visibleRoles);
  final Set<MoveType>  _visibleMoves = Set.of(OrcaDefaults.visibleMoveOptions);

  vm.Vector3 _orbitCentre = vm.Vector3.zero();
  double _orbitRadius = 100.0;
  double _yaw = 0.6;
  double _pitch = 0.5;
  double _distance = 500.0;
  vm.Vector3 _panOffset = vm.Vector3.zero();
  static const double _fovY = math.pi / 4;

  // Per-role representative width, picked once at load. Defaults
  // to the CC2 standard 0.42 mm when no extruding move of that
  // role exists.
  late final Map<int, double> _widthByRole;

  @override
  void initState() {
    super.initState();
    _widthByRole = _collectRoleWidths(widget.toolpaths);
    _currentLayer = widget.toolpaths.layerCount - 1;
    _frameCamera();
    _initScene();
  }

  @override
  void didUpdateWidget(covariant ToolpathLayerView old) {
    super.didUpdateWidget(old);
    if (!identical(old.toolpaths, widget.toolpaths)) {
      _currentLayer = widget.toolpaths.layerCount - 1;
      _frameCamera();
      _rebuildScene();
    }
  }

  Map<int, double> _collectRoleWidths(Toolpaths t) {
    final out = <int, double>{};
    final bd = ByteData.sublistView(t.data);
    for (int i = 0; i < t.moveCount; ++i) {
      final o = i * 28;
      final moveCode = bd.getUint8(o + 2);
      if (moveCode != MoveType.extrude.index) continue;
      final roleCode = bd.getUint8(o);
      if (out.containsKey(roleCode)) continue;
      final w = bd.getUint16(o + 6, Endian.little) * 0.01;
      if (w > 0.05) out[roleCode] = w;
    }
    return out;
  }

  double _widthFor(int roleCode) => _widthByRole[roleCode] ?? 0.42;

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
        _mode = _RendererMode.twoDTopDown;
      });
    }
  }

  void _frameCamera() {
    final t = widget.toolpaths;
    final modelAabb = vm.Aabb3.minMax(
        vm.Vector3(t.minX, t.minY, t.minZ),
        vm.Vector3(t.maxX, t.maxY, t.maxZ));
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
  // Build one `LineSegmentsGeometry` per visible role for the
  // stacked below-layers (dim, half-width) and one per role for
  // the current layer (bright, full width). Move-type options
  // (travel / wipe / retract / …) are a separate pass against
  // `_visibleMoves`; they usually stay off, matching Orca.
  void _rebuildScene() {
    final scene = _scene;
    if (scene == null || !_sceneReady) return;
    scene.root.children.clear();
    addBedToScene(scene);
    final t = widget.toolpaths;
    if (t.moveCount == 0 || t.layerCount == 0) return;
    final maxLayer = _currentLayer.clamp(0, t.layerCount - 1);
    final endOfBelow = t.layerStart(maxLayer);
    final endOfCurrent = t.layerEnd(maxLayer);
    // Collect per-role, per-split segment lists. We do a single
    // pass over records and partition.
    for (final role in GcodeRole.values) {
      if (!_visibleRoles.contains(role)) continue;
      final color = Color(OrcaPalette.roleColor[role]!);
      final width = _widthFor(role.index);
      _emitRole(scene, t,
          roleCode: role.index,
          colorBright: color,
          widthMm: width,
          from: 0, to: endOfBelow, dim: true);
      _emitRole(scene, t,
          roleCode: role.index,
          colorBright: color,
          widthMm: width,
          from: endOfBelow, to: endOfCurrent, dim: false);
    }
    for (final move in [MoveType.travel, MoveType.wipe,
                        MoveType.retract, MoveType.unretract,
                        MoveType.seam, MoveType.toolChange,
                        MoveType.colorChange]) {
      if (!_visibleMoves.contains(move)) continue;
      final color = Color(OrcaPalette.moveColor[move]!);
      _emitMoveType(scene, t,
          moveCode: move.index,
          colorBright: color,
          widthMm: 0.2,
          from: 0, to: endOfBelow, dim: true);
      _emitMoveType(scene, t,
          moveCode: move.index,
          colorBright: color,
          widthMm: 0.2,
          from: endOfBelow, to: endOfCurrent, dim: false);
    }
  }

  void _emitRole(fscene.Scene scene, Toolpaths t, {
    required int roleCode,
    required Color colorBright,
    required double widthMm,
    required int from, required int to,
    required bool dim,
  }) {
    if (to <= from) return;
    final bd = ByteData.sublistView(t.data);
    // First pass: count matching segments.
    int count = 0;
    double px = 0, py = 0, pz = 0;
    bool hasPrev = false;
    for (int i = (from > 0 ? from - 1 : from); i < to; ++i) {
      final o = i * 28;
      final mc = bd.getUint8(o + 2);
      final rc = bd.getUint8(o);
      if (i >= from && hasPrev && mc == MoveType.extrude.index && rc == roleCode) {
        count++;
      }
      hasPrev = true;
      px = bd.getFloat32(o + 12, Endian.little);
      py = bd.getFloat32(o + 16, Endian.little);
      pz = bd.getFloat32(o + 20, Endian.little);
    }
    if (count == 0) return;
    final out = Float32List(count * 6);
    int oIdx = 0;
    hasPrev = false;
    for (int i = (from > 0 ? from - 1 : from); i < to; ++i) {
      final o = i * 28;
      final mc = bd.getUint8(o + 2);
      final rc = bd.getUint8(o);
      final x = bd.getFloat32(o + 12, Endian.little);
      final y = bd.getFloat32(o + 16, Endian.little);
      final z = bd.getFloat32(o + 20, Endian.little);
      if (i >= from && hasPrev && mc == MoveType.extrude.index && rc == roleCode) {
        out[oIdx    ] = px; out[oIdx + 1] = py; out[oIdx + 2] = pz;
        out[oIdx + 3] = x;  out[oIdx + 4] = y;  out[oIdx + 5] = z;
        oIdx += 6;
      }
      px = x; py = y; pz = z;
      hasPrev = true;
    }
    final data = fscene.LineSegmentData(positions: out);
    final geom = fscene.LineSegmentsGeometry(data,
        width: dim ? math.max(widthMm * 0.5, 0.15) : widthMm);
    final tint = dim ? _dim(colorBright) : colorBright;
    final mat = fscene.UnlitMaterial()
      ..baseColorFactor = vm.Vector4(tint.r, tint.g, tint.b, 1);
    scene.add(fscene.Node(
        name: 'role${roleCode}_${dim ? "dim" : "cur"}',
        mesh: fscene.Mesh(geom, mat)));
  }

  void _emitMoveType(fscene.Scene scene, Toolpaths t, {
    required int moveCode,
    required Color colorBright,
    required double widthMm,
    required int from, required int to,
    required bool dim,
  }) {
    if (to <= from) return;
    final bd = ByteData.sublistView(t.data);
    int count = 0;
    for (int i = from; i < to; ++i) {
      if (bd.getUint8(i * 28 + 2) == moveCode) count++;
    }
    if (count == 0) return;
    final out = Float32List(count * 6);
    int oIdx = 0;
    double px = 0, py = 0, pz = 0;
    bool hasPrev = false;
    for (int i = (from > 0 ? from - 1 : from); i < to; ++i) {
      final o = i * 28;
      final mc = bd.getUint8(o + 2);
      final x = bd.getFloat32(o + 12, Endian.little);
      final y = bd.getFloat32(o + 16, Endian.little);
      final z = bd.getFloat32(o + 20, Endian.little);
      if (i >= from && hasPrev && mc == moveCode) {
        out[oIdx    ] = px; out[oIdx + 1] = py; out[oIdx + 2] = pz;
        out[oIdx + 3] = x;  out[oIdx + 4] = y;  out[oIdx + 5] = z;
        oIdx += 6;
      }
      px = x; py = y; pz = z;
      hasPrev = true;
    }
    final data = fscene.LineSegmentData(positions: out);
    final geom = fscene.LineSegmentsGeometry(data,
        width: dim ? widthMm * 0.5 : widthMm);
    final tint = dim ? _dim(colorBright) : colorBright;
    final mat = fscene.UnlitMaterial()
      ..baseColorFactor = vm.Vector4(tint.r, tint.g, tint.b, 1);
    scene.add(fscene.Node(
        name: 'move${moveCode}_${dim ? "dim" : "cur"}',
        mesh: fscene.Mesh(geom, mat)));
  }

  Color _dim(Color c) => Color.from(
      alpha: 1.0, red: c.r * 0.35, green: c.g * 0.35, blue: c.b * 0.35);

  // -------- gestures (identical contract to PlateView / LayerView) --------
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
    final t = widget.toolpaths;
    final clamped = l.clamp(0, t.layerCount - 1);
    if (clamped == _currentLayer) return;
    setState(() { _currentLayer = clamped; });
    _rebuildScene();
  }

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
    if (_mode == _RendererMode.twoDTopDown) {
      return _TopDownPainterView(
        toolpaths: widget.toolpaths,
        visibleRoles: _visibleRoles,
        visibleMoves: _visibleMoves,
        currentLayer: _currentLayer.clamp(0, widget.toolpaths.layerCount - 1),
      );
    }
    final scene = _scene;
    if (_sceneError != null || scene == null) {
      return _TopDownPainterView(
        toolpaths: widget.toolpaths,
        visibleRoles: _visibleRoles,
        visibleMoves: _visibleMoves,
        currentLayer: _currentLayer.clamp(0, widget.toolpaths.layerCount - 1),
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

  Widget _layerControlsRow(ToolpathLayerViewLabels l) {
    final t = widget.toolpaths;
    final maxLayer = (t.layerCount - 1).clamp(0, 1 << 30);
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
            label: '${l.layer} ${value + 1} ${l.of} ${t.layerCount}',
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
            '${value + 1}/${t.layerCount}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _viewButtonsRow(ToolpathLayerViewLabels l) {
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
        SegmentedButton<_RendererMode>(
          segments: [
            ButtonSegment(
                value: _RendererMode.three, label: Text(l.renderer3d)),
            ButtonSegment(
                value: _RendererMode.twoDTopDown, label: Text(l.renderer2d)),
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

  Widget _legend(ToolpathLayerViewLabels l) {
    final theme = Theme.of(context);
    final roles = GcodeRole.values.where((r) =>
        r != GcodeRole.mixed && r != GcodeRole.none).toList();
    final moveTypes = [
      MoveType.travel, MoveType.wipe,
      MoveType.retract, MoveType.unretract, MoveType.seam,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.pathTypes, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8, runSpacing: 4,
          children: [
            for (final r in roles) _roleChip(r, l),
            for (final m in moveTypes) _moveChip(m, l),
          ],
        ),
      ],
    );
  }

  Widget _roleChip(GcodeRole r, ToolpathLayerViewLabels l) {
    final visible = _visibleRoles.contains(r);
    return FilterChip(
      selected: visible,
      showCheckmark: false,
      avatar: _swatch(Color(OrcaPalette.roleColor[r]!)),
      label: Text(l.roleLabel(r)),
      onSelected: (v) {
        setState(() {
          if (v) {
            _visibleRoles.add(r);
          } else {
            _visibleRoles.remove(r);
          }
        });
        _rebuildScene();
      },
    );
  }

  Widget _moveChip(MoveType m, ToolpathLayerViewLabels l) {
    final visible = _visibleMoves.contains(m);
    return FilterChip(
      selected: visible,
      showCheckmark: false,
      avatar: _swatch(Color(OrcaPalette.moveColor[m]!)),
      label: Text(l.moveLabel(m)),
      onSelected: (v) {
        setState(() {
          if (v) {
            _visibleMoves.add(m);
          } else {
            _visibleMoves.remove(m);
          }
        });
        _rebuildScene();
      },
    );
  }

  Widget _swatch(Color c) => Container(
    decoration: BoxDecoration(
      color: c, shape: BoxShape.circle,
      border: Border.all(color: Colors.black26),
    ),
    width: 14, height: 14,
  );
}

// -------- 2D top-down painter --------
//
// Pure Dart, pure CPU. Walks the record stream and paints the
// current layer's segments as 1 px lines. Uses the per-axis
// AABB so a cube that is not centred on the bed draws in the
// middle of the viewport.
class _TopDownPainterView extends StatelessWidget {
  const _TopDownPainterView({
    required this.toolpaths,
    required this.visibleRoles,
    required this.visibleMoves,
    required this.currentLayer,
  });
  final Toolpaths toolpaths;
  final Set<GcodeRole> visibleRoles;
  final Set<MoveType> visibleMoves;
  final int currentLayer;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1D23),
      child: CustomPaint(
        size: Size.infinite,
        painter: _ToolpathTopDownPainter(
          toolpaths: toolpaths,
          visibleRoles: visibleRoles,
          visibleMoves: visibleMoves,
          currentLayer: currentLayer,
        ),
      ),
    );
  }
}

class _ToolpathTopDownPainter extends CustomPainter {
  _ToolpathTopDownPainter({
    required this.toolpaths,
    required this.visibleRoles,
    required this.visibleMoves,
    required this.currentLayer,
  });
  final Toolpaths toolpaths;
  final Set<GcodeRole> visibleRoles;
  final Set<MoveType> visibleMoves;
  final int currentLayer;

  @override
  void paint(Canvas canvas, Size size) {
    final t = toolpaths;
    if (t.moveCount == 0 || t.layerCount == 0) return;
    final from = t.layerStart(currentLayer);
    final to   = t.layerEnd(currentLayer);
    if (to <= from) return;
    final rangeX = (t.maxX - t.minX).clamp(1.0, double.infinity);
    final rangeY = (t.maxY - t.minY).clamp(1.0, double.infinity);
    final maxRange = math.max(rangeX, rangeY);
    final scale = math.min(size.width, size.height) / maxRange * 0.9;
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final midX = (t.minX + t.maxX) * 0.5;
    final midY = (t.minY + t.maxY) * 0.5;
    double toX(double x) => cx + (x - midX) * scale;
    double toY(double y) => cy - (y - midY) * scale;

    final bd = ByteData.sublistView(t.data);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    // Walk once, grouping into paths per colour.
    final paths = <int, Path>{};
    double px = 0, py = 0;
    bool hasPrev = false;
    for (int i = (from > 0 ? from - 1 : from); i < to; ++i) {
      final o = i * 28;
      final mc = bd.getUint8(o + 2);
      final rc = bd.getUint8(o);
      final x = bd.getFloat32(o + 12, Endian.little);
      final y = bd.getFloat32(o + 16, Endian.little);
      bool include = false;
      int argb = 0;
      if (mc == MoveType.extrude.index) {
        final role = rc < GcodeRole.values.length
            ? GcodeRole.values[rc]
            : GcodeRole.none;
        if (visibleRoles.contains(role)) {
          include = true;
          argb = OrcaPalette.roleColor[role] ?? 0xFFCCCCCC;
        }
      } else {
        final mt = mc < MoveType.values.length
            ? MoveType.values[mc]
            : MoveType.noop;
        if (visibleMoves.contains(mt)) {
          include = true;
          argb = OrcaPalette.moveColor[mt] ?? 0xFF888888;
        }
      }
      if (i >= from && hasPrev && include) {
        final path = paths.putIfAbsent(argb, () => Path());
        path.moveTo(toX(px), toY(py));
        path.lineTo(toX(x),  toY(y));
      }
      px = x; py = y;
      hasPrev = true;
    }
    for (final entry in paths.entries) {
      paint.color = Color(entry.key);
      canvas.drawPath(entry.value, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ToolpathTopDownPainter old) =>
      old.toolpaths != toolpaths ||
      old.currentLayer != currentLayer ||
      !_setEquals(old.visibleRoles, visibleRoles) ||
      !_setEquals(old.visibleMoves, visibleMoves);

  static bool _setEquals<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    for (final x in a) {
      if (!b.contains(x)) return false;
    }
    return true;
  }
}
