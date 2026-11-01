// Regression guards for the d2bb034 scene-accumulation bug.
//
// Short version of the story: `scene.root.children.clear()` is a
// plain `List<Node>.clear()`. It does not call `Node.remove`'s
// unmount path, so the renderer keeps drawing the previous
// frame's meshes. On a slider change we were stacking the new
// layer on top of the previous one. Klaus caught this at Layer
// 52 of the thumbnail cube on b23e962.
//
// The runtime regression test ("the number of nodes in the
// scene after 100 → 1 → 52 → 100 → 52 must equal a single
// build at 52") requires Impeller, which flutter_test does not
// ship. So we guard the regression from two sides without
// touching the GPU:
//
//   (a) GREP: no `.root.children.clear(` call appears in
//       `app/lib`. Prevents the pattern from sneaking back in
//       (there were four call-sites — ToolpathLayerView,
//       LayerView, PlateView, PlateBenchScreen — and all
//       four regressed together, so one grep catches all four
//       at once).
//
//   (b) DATA-PATH IDEMPOTENCE: `buildRoleSegments` is the pure
//       helper that `_emitRole` feeds to the renderer. Call it
//       at the Klaus-named sequence of slider positions and
//       assert the Float32List it returns at Layer 52 is
//       byte-identical to a cold build at Layer 52. Proves the
//       data path has no accumulation / cached state.
//
// Both tests live together so a future `ToolpathLayerView`
// rewrite that drops either guard is loud about it.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/engine/toolpath_parser.dart';

void main() {
  test(
      'no .root.children.clear( in lib — must use .root.removeAll() instead',
      () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue,
        reason: 'run `flutter test` from the app directory');
    final offenders = <String>[];
    for (final f in lib.listSync(recursive: true)) {
      if (f is! File) continue;
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      // The four call sites that regressed were all of the shape
      // `<scene>.root.children.clear()`. Match loosely so a copy
      // of the pattern against a different variable name still
      // trips the test. Strip single-line comments first so a
      // `// `-prefixed mention of the forbidden pattern does
      // not trip the guard.
      final stripped = src
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
          .toList();
      final re = RegExp(r'\.root\.children\.clear\s*\(');
      for (int i = 0; i < stripped.length; ++i) {
        if (re.hasMatch(stripped[i])) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason:
            'the b23e962 scene-accumulation bug came from calling '
            '`scene.root.children.clear()` directly on the List — '
            'that bypasses `Node.remove`, so the renderer keeps '
            'drawing the previous layer. Use `scene.root.removeAll()` '
            'instead (flutter_scene src/node.dart:1341-1358). '
            'Offending call sites: $offenders');
  });

  group('on real HSPT (local only, cube)', () {
    final hspt = File('local-test/cube.hspt');

    test(
        'buildRoleSegments is idempotent across the Klaus-named slider sequence',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      // The exact sequence Klaus named: 100 → 1 → 52 → 100 → 52.
      // At the final 52 we must get the same positions as a
      // cold build at 52. We check every role that carries
      // extrudes.
      Map<int, Float32List> buildAll(int displayedLayer) {
        final current0 = displayedLayer - 1;
        final end = t.layerEnd(current0);
        final map = <int, Float32List>{};
        for (final r in GcodeRole.values) {
          final seg = buildRoleSegments(t,
              roleCode: r.index, fromIdx: 0, toIdx: end);
          if (seg.isNotEmpty) map[r.index] = seg;
        }
        return map;
      }

      Map<int, Float32List> cold = buildAll(52);
      for (final n in <int>[100, 1, 52, 100, 52]) {
        buildAll(n); // warms would-be caches; must have no effect
      }
      final afterSequence = buildAll(52);

      // Same keys.
      expect(afterSequence.keys.toSet(), cold.keys.toSet(),
          reason:
              'Roles emitted at Layer 52 after the sequence '
              '100 → 1 → 52 → 100 → 52 differ from a cold build');
      // Byte-identical positions.
      for (final k in cold.keys) {
        final a = cold[k]!;
        final b = afterSequence[k]!;
        expect(b.length, a.length,
            reason: 'role $k: segment count after sequence '
                'differs from cold at Layer 52');
        for (int i = 0; i < a.length; ++i) {
          if (a[i] != b[i]) {
            fail('role $k position[$i] drifted: cold=${a[i]} '
                'vs after-sequence=${b[i]}');
          }
        }
      }
    });

    test(
        'buildRoleSegments at Layer 52 twice returns identical bytes',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      final current0 = 51;
      final end = t.layerEnd(current0);
      final a = buildRoleSegments(t,
          roleCode: GcodeRole.internalInfill.index,
          fromIdx: 0, toIdx: end);
      final b = buildRoleSegments(t,
          roleCode: GcodeRole.internalInfill.index,
          fromIdx: 0, toIdx: end);
      expect(a.length, b.length);
      for (int i = 0; i < a.length; ++i) {
        if (a[i] != b[i]) {
          fail('byte $i differs: $a vs $b');
        }
      }
    });
  });
}
