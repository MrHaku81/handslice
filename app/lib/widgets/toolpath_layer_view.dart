// Pflicht 7c/7d — layer preview backed by the CLI's HSPT binary.
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
//
// 7d adds: object-only silhouette (no purge line in the box),
// time + weight columns in the legend, a "Total estimation"
// footer, and a bed grid (via `addBedToScene`).

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
    required this.height,
    required this.resetView,
    required this.top,
    required this.front,
    required this.oblique,
    required this.zoomIn,
    required this.zoomOut,
    required this.pathTypes,
    required this.lineTypeLegendHeader,
    required this.lineTypeLengthHeader,
    required this.lineTypeTimeHeader,
    required this.lineTypeWeightHeader,
    required this.lineTypePercentHeader,
    required this.lineTypeNameHeader,
    required this.renderer3d,
    required this.renderer2d,
    required this.decrementLayer,
    required this.incrementLayer,
    required this.plateLabel,
    required this.roleLabel,
    required this.moveLabel,
    required this.totalEstimation,
    required this.totalFilament,
    required this.totalPrintTime,
    required this.modelOutline,
  });
  final String layer;
  final String of;
  /// "Z = X.XX mm", for the slider label.
  final String Function(double zMm) height;
  final String resetView;
  final String top;
  final String front;
  final String oblique;
  final String zoomIn;
  final String zoomOut;
  final String pathTypes;
  final String lineTypeLegendHeader;
  final String lineTypeLengthHeader;
  final String lineTypeTimeHeader;
  final String lineTypeWeightHeader;
  final String lineTypePercentHeader;
  final String lineTypeNameHeader;
  final String renderer3d;
  final String renderer2d;
  final String decrementLayer;
  final String incrementLayer;
  /// e.g. "A · Textured — 256×256×256 mm³".
  final String plateLabel;
  final String Function(GcodeRole) roleLabel;
  final String Function(MoveType) moveLabel;
  final String totalEstimation;
  final String totalFilament;
  final String totalPrintTime;
  /// Legend-options row label, Orca would call this
  /// "Model outline" — Pflicht 7d-follow-up (409e425+1).
  final String modelOutline;
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
  // The AABB-wireframe "model outline" we draw above the slider
  // is a cheap stand-in for Orca's translucent shell. Klaus
  // (409e425 device run) called the default-on wireframe
  // "unruhig" on the phone, so it's off by default now and
  // lives behind the "Model outline" option in the legend. The
  // real alpha mesh is 7e scope (needs a blend-capable custom
  // shader; `UnlitMaterial` in flutter_scene does not expose
  // one).
  bool _silhouetteVisible = false;

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
      final o = i * hsptRecordSize;
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
    // IMPORTANT: `scene.root.children.clear()` only mutates the
    // List<Node>; it does not run `Node.remove`'s unmount path,
    // so the previous frame's `_renderItems` stay registered
    // in `renderScene` and keep drawing. The slider then
    // accumulates layers instead of replacing them — Klaus
    // (b23e962 device run) saw the full cube + topSolidInfill
    // at Layer 52 because of this. Use `removeAll()`, which
    // calls `remove()` for each child and takes it out of the
    // render scene.
    scene.root.removeAll();
    addBedToScene(scene);
    final t = widget.toolpaths;
    if (t.moveCount == 0 || t.layerCount == 0) return;
    final maxLayer = _currentLayer.clamp(0, t.layerCount - 1);
    final endOfCurrent = t.layerEnd(maxLayer);
    // Draw every extrusion up to and including the current
    // layer at its full Orca palette value. Orca's own viewer
    // does the same — the current layer is "the top of the
    // stack we see" rather than a visually-distinct ribbon,
    // and the hidden-above translucent silhouette (added
    // separately below) marks where the slider is.
    for (final role in GcodeRole.values) {
      if (!_visibleRoles.contains(role)) continue;
      final color = Color(OrcaPalette.roleColor[role]!);
      final width = _widthFor(role.index);
      _emitRole(scene, t,
          roleCode: role.index,
          colorBright: color,
          widthMm: width,
          from: 0, to: endOfCurrent);
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
          from: 0, to: endOfCurrent);
    }
    // Model-outline wireframe above the current layer. Default
    // off: Klaus (409e425 device test) found the many edges
    // noisy on a 393-dp screen. User can turn it back on via the
    // legend's "Model outline" option.
    if (_silhouetteVisible && maxLayer < t.layerCount - 1) {
      _addModelSilhouette(scene, t);
    }
  }

  void _emitRole(fscene.Scene scene, Toolpaths t, {
    required int roleCode,
    required Color colorBright,
    required double widthMm,
    required int from, required int to,
  }) {
    // `buildRoleSegments` is the pure-Dart equivalent of what we
    // used to inline here. Keeping the two in sync via a single
    // helper lets `toolpath_parser_test.dart` pin the exact
    // position stream fed to the renderer for any slider
    // position, so bugs like the b23e962 scene-accumulation
    // regression surface in CI rather than on the device.
    final out = buildRoleSegments(t,
        roleCode: roleCode, fromIdx: from, toIdx: to);
    if (out.isEmpty) return;
    final data = fscene.LineSegmentData(positions: out);
    final geom = fscene.LineSegmentsGeometry(data, width: widthMm);
    // `displayReferred = true` treats `baseColorFactor` as the
    // final sRGB display value instead of linear radiance. The
    // Orca palette constants are sRGB — without this flag,
    // Impeller gamma-corrects them again and the walls read as
    // peach / salmon. Called out by Klaus on the first 7c
    // device test.
    final mat = fscene.UnlitMaterial()
      ..displayReferred = true
      ..baseColorFactor = vm.Vector4(
          colorBright.r, colorBright.g, colorBright.b, 1);
    scene.add(fscene.Node(
        name: 'role$roleCode',
        mesh: fscene.Mesh(geom, mat)));
  }

  void _emitMoveType(fscene.Scene scene, Toolpaths t, {
    required int moveCode,
    required Color colorBright,
    required double widthMm,
    required int from, required int to,
  }) {
    if (to <= from) return;
    final bd = ByteData.sublistView(t.data);
    int count = 0;
    for (int i = from; i < to; ++i) {
      if (bd.getUint8(i * hsptRecordSize + 2) == moveCode) count++;
    }
    if (count == 0) return;
    final out = Float32List(count * 6);
    int oIdx = 0;
    double px = 0, py = 0, pz = 0;
    bool hasPrev = false;
    for (int i = (from > 0 ? from - 1 : from); i < to; ++i) {
      final o = i * hsptRecordSize;
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
    final geom = fscene.LineSegmentsGeometry(data, width: widthMm);
    final mat = fscene.UnlitMaterial()
      ..displayReferred = true
      ..baseColorFactor = vm.Vector4(
          colorBright.r, colorBright.g, colorBright.b, 1);
    scene.add(fscene.Node(
        name: 'move$moveCode',
        mesh: fscene.Mesh(geom, mat)));
  }

  // Orca's "translucent-above-the-slider" model shell is a
  // real alpha-blended mesh of the sliced object, tinted with
  // the filament colour at ~20 % alpha. Reference:
  //   OrcaSlicer/src/slic3r/GUI/GCodeViewer.cpp:240
  //     m_model.set_color({ 1.0f, 1.0f, 1.0f, 0.5f });
  //   OrcaSlicer/src/slic3r/GUI/GCodeViewer.hpp:266
  //     void set_shell_transparency(float alpha = 0.15f);
  //   OrcaSlicer/src/slic3r/GUI/GLCanvas3D.hpp:1017
  //     void set_shell_transparence(float alpha = 0.2f);
  //
  // flutter_scene's `UnlitMaterial` does not expose a blend
  // mode, so a real 20 %-alpha mesh is out of reach today
  // (would need a custom shader or a sorted translucent
  // pipeline). We approximate the shell with a light-grey
  // AABB wireframe over the OBJECT-only bbox (skirt / brim /
  // wipe tower / custom excluded) at 0.1-mm line width — thin
  // enough to read as a hint, not a solid box. The reference
  // image compares against `local-test/orca-referenz-
  // schicht52.png`.
  void _addModelSilhouette(fscene.Scene scene, Toolpaths t) {
    final maxLayer = _currentLayer.clamp(0, t.layerCount - 1);
    // Top-of-current-layer Z. Use the current layer's recorded
    // z (last extrude z of that bin) so the silhouette sits on
    // top of the printed segments, not inside them.
    final currentTopZ = maxLayer < t.layerZ.length
        ? t.layerZ[maxLayer]
        : t.maxZ;
    final topZ = t.objMaxZ;
    if (currentTopZ >= topZ) return;
    final x0 = t.objMinX, x1 = t.objMaxX;
    final y0 = t.objMinY, y1 = t.objMaxY;
    final z0 = currentTopZ, z1 = topZ;
    if (x1 <= x0 || y1 <= y0) return;
    final corners = <vm.Vector3>[
      vm.Vector3(x0, y0, z0), vm.Vector3(x1, y0, z0),
      vm.Vector3(x1, y1, z0), vm.Vector3(x0, y1, z0),
      vm.Vector3(x0, y0, z1), vm.Vector3(x1, y0, z1),
      vm.Vector3(x1, y1, z1), vm.Vector3(x0, y1, z1),
    ];
    final edges = <List<int>>[
      [0, 1], [1, 2], [2, 3], [3, 0],      // bottom
      [4, 5], [5, 6], [6, 7], [7, 4],      // top
      [0, 4], [1, 5], [2, 6], [3, 7],      // vertical
    ];
    final out = Float32List(edges.length * 6);
    for (int i = 0; i < edges.length; ++i) {
      final a = corners[edges[i][0]], b = corners[edges[i][1]];
      final o = i * 6;
      out[o    ] = a.x; out[o + 1] = a.y; out[o + 2] = a.z;
      out[o + 3] = b.x; out[o + 4] = b.y; out[o + 5] = b.z;
    }
    final data = fscene.LineSegmentData(positions: out);
    final geom = fscene.LineSegmentsGeometry(data, width: 0.1);
    final mat = fscene.UnlitMaterial()
      ..displayReferred = true
      // Light cool-grey (sRGB 0.78) ≈ `(1, 1, 1)` × α 0.22
      // against the near-black viewport. Lets the wireframe
      // read as "faded hint" rather than a solid box.
      ..baseColorFactor = vm.Vector4(0.78, 0.80, 0.82, 1);
    scene.add(fscene.Node(name: 'silhouette',
        mesh: fscene.Mesh(geom, mat)));
  }

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
    final currentLayer =
        _currentLayer.clamp(0, widget.toolpaths.layerCount - 1);
    if (_mode == _RendererMode.twoDTopDown) {
      return _wrapPlateLabel(_TopDownPainterView(
        toolpaths: widget.toolpaths,
        visibleRoles: _visibleRoles,
        visibleMoves: _visibleMoves,
        currentLayer: currentLayer,
        onInteractionChanged: widget.onInteractionChanged,
      ));
    }
    final scene = _scene;
    if (_sceneError != null || scene == null) {
      return _wrapPlateLabel(_TopDownPainterView(
        toolpaths: widget.toolpaths,
        visibleRoles: _visibleRoles,
        visibleMoves: _visibleMoves,
        currentLayer: currentLayer,
        onInteractionChanged: widget.onInteractionChanged,
      ));
    }
    if (!_sceneReady) {
      return Container(
        color: Colors.black26,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }
    final target = _orbitCentre + _panOffset;
    return _wrapPlateLabel(Listener(
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
    ));
  }

  // Static overlay in the top-left of the viewport that names
  // the plate and its size — Orca shows a bed label too, Klaus
  // asked us to match it in both the model and layer views.
  Widget _wrapPlateLabel(Widget child) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: 6,
          left: 8,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.labels.plateLabel,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _layerControlsRow(ToolpathLayerViewLabels l) {
    final t = widget.toolpaths;
    final maxLayer = (t.layerCount - 1).clamp(0, 1 << 30);
    final value = _currentLayer.clamp(0, maxLayer);
    final z = value < t.layerZ.length ? t.layerZ[value] : t.minZ;
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
            label: '${l.layer} ${value + 1} ${l.of} ${t.layerCount}'
                ' · ${l.height(z)}',
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
          width: 96,
          child: Text(
            '${value + 1}/${t.layerCount}\n${l.height(z)}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
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

  // Format helpers for the legend. "9m25s" / "35s" / "1h12m" —
  // Orca drops the hours bucket when zero, and the seconds
  // bucket when hours are present.
  String _fmtDuration(double seconds) {
    if (!seconds.isFinite || seconds <= 0.5) return '—';
    final total = seconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) return '${h}h${m}m';
    if (m > 0) return '${m}m${s}s';
    return '${s}s';
  }

  Widget _legend(ToolpathLayerViewLabels l) {
    final theme = Theme.of(context);
    final t = widget.toolpaths;
    // Only show roles with non-zero extruded filament — the
    // full 20-row list is noisy on a plain cube. We mirror
    // Orca's `get_extrusion_roles()`, which returns the roles
    // present in the current print.
    final roles = GcodeRole.values
        .where((r) => t.extrudedByRole[r.index] > 0.05)
        .toList();
    final moveTypes = [
      MoveType.travel, MoveType.wipe,
      MoveType.retract, MoveType.unretract, MoveType.seam,
    ];
    // Percent in Orca's "Line Type" legend is BY TIME, not by
    // length. Reference:
    //   OrcaSlicer/src/slic3r/GUI/GCodeViewer.cpp:3410-3418
    //   role_time_and_percent, travel_time_and_percent.
    final totalTimeSec = t.totalTimeSec;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.lineTypeLegendHeader, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        _LegendTable(
          labels: l,
          rows: [
            for (final r in roles)
              _LegendRowData(
                name: l.roleLabel(r),
                color: Color(OrcaPalette.roleColor[r]!),
                timeSec: t.timeByRole[r.index],
                percent: totalTimeSec > 0
                    ? t.timeByRole[r.index] / totalTimeSec * 100
                    : 0,
                // Orca's "Length" column for a role is the
                // extruded FILAMENT length in metres, not the
                // path length. Reference:
                //   OrcaSlicer/src/slic3r/GUI/GCodeViewer.cpp
                //   :3432-3440 used_filament_per_role (returns
                //   model_used_filament_m / _g), and the usage
                //   formula at :3443-3448. On the thumbnail
                //   cube: 1177.15 mm extruded ⇒ 1.17 m total,
                //   same as the reference screenshot.
                lengthMetres: t.extrudedByRole[r.index] * 0.001,
                weightG: t.gramsForRole(r.index),
                visible: _visibleRoles.contains(r),
                onToggle: (v) {
                  setState(() {
                    if (v) {
                      _visibleRoles.add(r);
                    } else {
                      _visibleRoles.remove(r);
                    }
                  });
                  _rebuildScene();
                },
              ),
            for (final m in moveTypes)
              _LegendRowData(
                name: l.moveLabel(m),
                color: Color(OrcaPalette.moveColor[m]!),
                timeSec: t.timeByMove[m.index],
                percent: totalTimeSec > 0
                    ? t.timeByMove[m.index] / totalTimeSec * 100
                    : 0,
                // Option rows show distance in metres (Orca's
                // `m_move_type_distances`, GCodeViewer.cpp
                // :3806-3809) and no weight.
                lengthMetres: t.distanceByMove[m.index] * 0.001,
                weightG: null,
                visible: _visibleMoves.contains(m),
                onToggle: (v) {
                  setState(() {
                    if (v) {
                      _visibleMoves.add(m);
                    } else {
                      _visibleMoves.remove(m);
                    }
                  });
                  _rebuildScene();
                },
              ),
            // Model-outline toggle. No time / %, no palette
            // swatch — the colour cell is a neutral grey chip
            // so it reads as a hint, not an extrusion colour.
            _LegendRowData(
              name: l.modelOutline,
              color: const Color(0xFFC6CBD1),
              timeSec: 0,
              percent: 0,
              lengthMetres: 0,
              weightG: null,
              visible: _silhouetteVisible,
              onToggle: (v) {
                setState(() { _silhouetteVisible = v; });
                _rebuildScene();
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        _totalEstimation(l,
            // Reference: GCodeViewer.cpp:3443-3448
            // get_used_filament_from_volume. Our `extrudedMm`
            // is the sum of positive extruder deltas, i.e. the
            // filament length that left the spool — same thing
            // Orca puts on the "Total Filament" line.
            totalFilamentMetres: t.extrudedMm * 0.001,
            totalWeightG: t.gramsFromExtrudedMm(t.extrudedMm),
            totalTimeSec: t.totalTimeSec),
      ],
    );
  }

  // Orca's "Total estimation" box in the lower right. We follow
  // the same layout — total filament metres + grams on one line,
  // total time on the next.
  Widget _totalEstimation(ToolpathLayerViewLabels l,
      {required double totalFilamentMetres,
       required double totalWeightG,
       required double totalTimeSec}) {
    final theme = Theme.of(context);
    final filamentLine = '${totalFilamentMetres.toStringAsFixed(2)} m '
        '· ${totalWeightG.toStringAsFixed(2)} g';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.totalEstimation, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          _totalEstimationRow(l.totalFilament, filamentLine),
          _totalEstimationRow(l.totalPrintTime, _fmtDuration(totalTimeSec)),
        ],
      ),
    );
  }

  Widget _totalEstimationRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
          Text(value,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFamily: 'monospace')),
        ],
      ),
    );
  }

}

// -------- Legend table --------
//
// Pulled into its own widget so the Row widths can collapse
// cleanly at 393 dp (Poco X3 Pro portrait). The row data is
// a plain record struct; the widget renders all rows with the
// same compact column widths so the %-column never breaks into
// two lines and the name column always has room for the full
// German label ("Innenwand", "Außenwand") without ellipsising.

class _LegendRowData {
  _LegendRowData({
    required this.name,
    required this.color,
    required this.timeSec,
    required this.percent,
    required this.lengthMetres,
    required this.weightG,
    required this.visible,
    required this.onToggle,
  });
  final String name;
  final Color color;
  final double timeSec;
  final double percent;
  final double lengthMetres;
  /// `null` for option rows (travel / wipe / retract / …) —
  /// Orca hides their weight column (`GCodeViewer.cpp:3804-3812`).
  final double? weightG;
  final bool visible;
  final ValueChanged<bool> onToggle;
}

class _LegendTable extends StatelessWidget {
  const _LegendTable({required this.labels, required this.rows});
  final ToolpathLayerViewLabels labels;
  final List<_LegendRowData> rows;

  // Compact column widths — fit the whole table on a 393-dp
  // Poco X3 Pro portrait viewport without any column breaking
  // to a second line or the name ellipsising. The six fixed
  // widths sum to 194 dp (14 + 14 + 40 + 32 + 50 + 44), leaving
  // ≈ 150 dp of width for the name under the project-card
  // padding (16 + 16 dp horizontal). "0.07m" fits in 40 dp at
  // the 10-px monospace font.
  static const double _wSwatch = 14;
  static const double _wEye    = 14;
  static const double _wTime   = 40;
  static const double _wPct    = 32;
  static const double _wUsage  = 50;
  static const double _wWeight = 44;
  static const double _rowFont = 11;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headStyle = theme.textTheme.bodySmall!.copyWith(
        color: Colors.white60, fontSize: _rowFont);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: DefaultTextStyle(
            style: headStyle,
            child: Row(children: [
              const SizedBox(width: _wSwatch + _wEye + 6),
              Expanded(child: Text(labels.lineTypeNameHeader)),
              SizedBox(width: _wTime,
                  child: Text(labels.lineTypeTimeHeader,
                      textAlign: TextAlign.right)),
              SizedBox(width: _wPct,
                  child: Text(labels.lineTypePercentHeader,
                      textAlign: TextAlign.right)),
              SizedBox(width: _wUsage,
                  child: Text(labels.lineTypeLengthHeader,
                      textAlign: TextAlign.right)),
              SizedBox(width: _wWeight,
                  child: Text(labels.lineTypeWeightHeader,
                      textAlign: TextAlign.right)),
            ]),
          ),
        ),
        for (final r in rows) _row(theme, r),
      ],
    );
  }

  Widget _row(ThemeData theme, _LegendRowData r) {
    final cellStyle = theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        fontSize: _rowFont,
        color: r.visible ? null : Colors.white38);
    final nameStyle = theme.textTheme.bodySmall?.copyWith(
        fontSize: _rowFont,
        color: r.visible ? null : Colors.white38);
    return InkWell(
      onTap: () => r.onToggle(!r.visible),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            SizedBox(width: _wEye,
              child: Icon(
                r.visible ? Icons.visibility : Icons.visibility_off,
                size: 12,
                color: r.visible ? Colors.white70 : Colors.white24),
            ),
            const SizedBox(width: 2),
            SizedBox(width: _wSwatch, child: _swatch(r.color)),
            const SizedBox(width: 4),
            Expanded(child: Text(r.name,
                style: nameStyle, maxLines: 1,
                overflow: TextOverflow.ellipsis)),
            SizedBox(width: _wTime,
              child: Text(_fmtDuration(r.timeSec),
                  textAlign: TextAlign.right, style: cellStyle)),
            SizedBox(width: _wPct,
              child: Text(_fmtPercent(r.percent),
                  textAlign: TextAlign.right, style: cellStyle)),
            SizedBox(width: _wUsage,
              child: Text(_fmtMetres(r.lengthMetres),
                  textAlign: TextAlign.right, style: cellStyle)),
            SizedBox(width: _wWeight,
              child: Text(
                  r.weightG == null ? '—' : _fmtWeight(r.weightG!),
                  textAlign: TextAlign.right, style: cellStyle)),
          ],
        ),
      ),
    );
  }

  Widget _swatch(Color c) => Container(
    decoration: BoxDecoration(
      color: c, shape: BoxShape.circle,
      border: Border.all(color: Colors.black26),
    ),
    width: 10, height: 10,
  );

  // Orca prints these values without a space between the number
  // and its unit ("0.07m", "0.21g") — see
  // `GCodeViewer.cpp:3653-3655` ("%.2fm", "%.2fg" via
  // `format_compact_weight`). Mirroring saves ~2 dp per cell.
  static String _fmtDuration(double seconds) {
    if (!seconds.isFinite || seconds <= 0.5) return '—';
    final total = seconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) return '${h}h${m}m';
    if (m > 0) return '${m}m${s}s';
    return '${s}s';
  }
  static String _fmtPercent(double pct) {
    if (!pct.isFinite || pct <= 0.05) return '—';
    if (pct < 0.1) return '<0.1';
    return pct.toStringAsFixed(1);
  }
  static String _fmtMetres(double m) {
    if (!m.isFinite || m < 0.001) return '—';
    return '${m.toStringAsFixed(2)}m';
  }
  static String _fmtWeight(double g) {
    if (!g.isFinite || g < 0.005) return '—';
    return '${g.toStringAsFixed(2)}g';
  }
}

// -------- 2D top-down painter --------
//
// Pure Dart, pure CPU. Walks the record stream and paints the
// current layer's segments as 1 px lines. Fits the viewport to
// the current layer's XY bounding box (not the whole-print bbox,
// which would include brim / purge and shrink the model to a
// corner). Supports pinch zoom + pan.
class _TopDownPainterView extends StatefulWidget {
  const _TopDownPainterView({
    required this.toolpaths,
    required this.visibleRoles,
    required this.visibleMoves,
    required this.currentLayer,
    required this.onInteractionChanged,
  });
  final Toolpaths toolpaths;
  final Set<GcodeRole> visibleRoles;
  final Set<MoveType> visibleMoves;
  final int currentLayer;
  final ValueChanged<bool>? onInteractionChanged;

  @override
  State<_TopDownPainterView> createState() => _TopDownPainterViewState();
}

class _TopDownPainterViewState extends State<_TopDownPainterView> {
  double _zoom = 1.0;
  Offset _pan = Offset.zero;
  double? _pinchStartDist;
  double? _pinchStartZoom;
  Offset? _lastCentroid;
  final Map<int, Offset> _pointers = {};

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    _pinchStartDist = null;
    _pinchStartZoom = null;
    _lastCentroid = null;
    if (_pointers.length == 1) widget.onInteractionChanged?.call(true);
  }
  void _move(PointerMoveEvent e) {
    final prev = _pointers[e.pointer] ?? e.localPosition;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      final delta = e.localPosition - prev;
      setState(() { _pan += delta; });
    } else if (_pointers.length >= 2) {
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
      _pinchStartDist ??= dist;
      _pinchStartZoom ??= _zoom;
      _lastCentroid   ??= centroid;
      setState(() {
        _zoom = (_pinchStartZoom! * (dist / math.max(_pinchStartDist!, 1e-3)))
            .clamp(0.25, 16.0);
        _pan += centroid - _lastCentroid!;
        _lastCentroid = centroid;
      });
    }
  }
  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) {
      _pinchStartDist = null;
      _pinchStartZoom = null;
      _lastCentroid = null;
    }
    if (_pointers.isEmpty) widget.onInteractionChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1D23),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: CustomPaint(
          size: Size.infinite,
          painter: _ToolpathTopDownPainter(
            toolpaths: widget.toolpaths,
            visibleRoles: widget.visibleRoles,
            visibleMoves: widget.visibleMoves,
            currentLayer: widget.currentLayer,
            zoom: _zoom,
            pan: _pan,
          ),
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
    required this.zoom,
    required this.pan,
  });
  final Toolpaths toolpaths;
  final Set<GcodeRole> visibleRoles;
  final Set<MoveType> visibleMoves;
  final int currentLayer;
  final double zoom;
  final Offset pan;

  @override
  void paint(Canvas canvas, Size size) {
    final t = toolpaths;
    if (t.moveCount == 0 || t.layerCount == 0) return;
    final from = t.layerStart(currentLayer);
    final to   = t.layerEnd(currentLayer);
    if (to <= from) return;
    // Fit the viewport to the *current layer's* object bbox so a
    // small cube stays large on the screen regardless of how big
    // the whole-print bbox is (brim, purge line etc. inflate it).
    final layerBbox = layerXyBounds(t, from, to) ??
        (minX: t.minX, maxX: t.maxX, minY: t.minY, maxY: t.maxY);
    final rangeX = (layerBbox.maxX - layerBbox.minX).clamp(1.0, double.infinity);
    final rangeY = (layerBbox.maxY - layerBbox.minY).clamp(1.0, double.infinity);
    final maxRange = math.max(rangeX, rangeY);
    final fitScale = math.min(size.width, size.height) / maxRange * 0.9;
    final scale = fitScale * zoom;
    final cx = size.width  / 2 + pan.dx;
    final cy = size.height / 2 + pan.dy;
    final midX = (layerBbox.minX + layerBbox.maxX) * 0.5;
    final midY = (layerBbox.minY + layerBbox.maxY) * 0.5;
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
      final o = i * hsptRecordSize;
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
      old.zoom != zoom || old.pan != pan ||
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
