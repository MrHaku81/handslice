// Shared bed quad for the orbit-camera scenes (PlateView, Pflicht
// 7a; LayerView, Pflicht 7b; ToolpathLayerView, Pflicht 7c/7d).
// CC2 bed is 256×256 mm at z=0; we draw it with the same Lambert-
// pre-baked colour the thumbnail renderer uses so the two surfaces
// (plate thumbnail and the on-device 3D views) read identically.
// Pflicht 7d adds a 10-mm grid overlay matching Orca's bed look.
//
// Keeping this in one place is deliberate — Klaus called out on
// the 7b device test that LayerView was drawing its scene without
// the bed; owners of the orbit scene should call `addBedToScene`
// first thing and `hullWithBed` on their model AABB.

// ignore_for_file: depend_on_referenced_packages

import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as fscene;
import 'package:vector_math/vector_math.dart' as vm;

const double kBedSizeMm = 256.0;
const double kBedGridStepMm = 10.0;

/// Append the CC2 bed quad plus a 10-mm grid as nodes "bed" and
/// "bed_grid" to [scene]. The quad is Lambert-shaded with the
/// same key light the thumbnail renderer and plate-view both use;
/// the grid is drawn as unlit segments slightly above the bed so
/// it reads cleanly from the oblique default view.
void addBedToScene(fscene.Scene scene) {
  final gb = fscene.GeometryBuilder(deduplicate: false);
  final n = vm.Vector3(0, 0, 1);
  final key = vm.Vector3(0.3, -0.3, 0.9)..normalize();
  final dot = (n.x * key.x + n.y * key.y + n.z * key.z).abs();
  const ambient = 0.25;
  final k = ambient + (1 - ambient) * dot;
  final c = vm.Vector4(0.18 * k, 0.19 * k, 0.21 * k, 1.0);
  gb.normal(n);
  gb.color(c);
  final i0 = gb.addVertex(vm.Vector3(0,          0,          0));
  final i1 = gb.addVertex(vm.Vector3(kBedSizeMm, 0,          0));
  final i2 = gb.addVertex(vm.Vector3(kBedSizeMm, kBedSizeMm, 0));
  final i3 = gb.addVertex(vm.Vector3(0,          kBedSizeMm, 0));
  gb.addTriangle(i0, i1, i2);
  gb.addTriangle(i0, i2, i3);
  final geom = gb.build();
  final mat = fscene.UnlitMaterial()
    ..baseColorFactor = vm.Vector4(1, 1, 1, 1);
  scene.add(fscene.Node(name: 'bed', mesh: fscene.Mesh(geom, mat)));

  // 10-mm grid overlay. Minor lines every 10 mm, a stronger line
  // every 50 mm so the eye can pick out the 50/100/150/200/256
  // "waypoints" Orca marks too. Drawn 0.02 mm above the quad to
  // beat the depth-fighter.
  final steps = <double>[];
  for (double x = 0; x <= kBedSizeMm + 1e-3; x += kBedGridStepMm) {
    steps.add(x);
  }
  // Minor + major split so we can draw each at its own intensity
  // with two separate materials.
  final minor = <double>[];
  final major = <double>[];
  for (final s in steps) {
    final isMajor = (s % 50.0).abs() < 1e-3;
    (isMajor ? major : minor).add(s);
  }
  _addGridMaterial(scene, minor, 'bed_grid_minor',
      vm.Vector4(0.42, 0.45, 0.49, 1), 0.02);
  _addGridMaterial(scene, major, 'bed_grid_major',
      vm.Vector4(0.72, 0.76, 0.80, 1), 0.03);
}

void _addGridMaterial(
    fscene.Scene scene, List<double> coords, String name,
    vm.Vector4 color, double zLift) {
  if (coords.isEmpty) return;
  // Horizontal (varying X) + vertical (varying Y) lines; each
  // line is one segment from (c, 0) → (c, bed) or (0, c) → (bed,
  // c). 6 floats per segment, 2 segments per coord.
  final out = Float32List(coords.length * 2 * 6);
  int o = 0;
  for (final c in coords) {
    out[o    ] = c;         out[o + 1] = 0;          out[o + 2] = zLift;
    out[o + 3] = c;         out[o + 4] = kBedSizeMm; out[o + 5] = zLift;
    out[o + 6] = 0;         out[o + 7] = c;          out[o + 8] = zLift;
    out[o + 9] = kBedSizeMm;out[o + 10] = c;         out[o + 11] = zLift;
    o += 12;
  }
  final data = fscene.LineSegmentData(positions: out);
  final geom = fscene.LineSegmentsGeometry(data, width: 0.08);
  final mat = fscene.UnlitMaterial()
    ..displayReferred = true
    ..baseColorFactor = color;
  scene.add(fscene.Node(name: name, mesh: fscene.Mesh(geom, mat)));
}

/// Union [modelAabb] with the bed quad's AABB so the orbit
/// camera's framing keeps the plate in frame even for tiny models
/// (notched cube) and knows how far to zoom out for very large
/// prints that may extend above the bed. Returns a new Aabb3.
vm.Aabb3 hullWithBed(vm.Aabb3 modelAabb) {
  final bed = vm.Aabb3.minMax(
      vm.Vector3(0, 0, 0),
      vm.Vector3(kBedSizeMm, kBedSizeMm, 0));
  return vm.Aabb3.copy(modelAabb)..hull(bed);
}
