// Shared bed quad for the orbit-camera scenes (PlateView, Pflicht
// 7a; LayerView, Pflicht 7b). CC2 bed is 256×256 mm at z=0; we
// draw it with the same Lambert-pre-baked colour the thumbnail
// renderer uses so the two surfaces (plate thumbnail and the
// on-device 3D views) read identically.
//
// Keeping this in one place is deliberate — Klaus called out on
// the 7b device test that LayerView was drawing its scene without
// the bed; owners of the orbit scene should call `addBedToScene`
// first thing and `hullWithBed` on their model AABB.

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_scene/scene.dart' as fscene;
import 'package:vector_math/vector_math.dart' as vm;

const double kBedSizeMm = 256.0;

/// Append the CC2 bed quad as a Node named "bed" to [scene]. The
/// quad is Lambert-shaded with the same key light the thumbnail
/// renderer and plate-view both use.
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
