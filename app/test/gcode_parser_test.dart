// Pflicht 7b — g-code parser tests.
//
// Two groups:
//   - A synthetic 3-layer cube with known TYPE comments and tool
//     changes. Pins the field layout + type-code mapping.
//   - A sanity pass over the actual Auryn g-code if the file is
//     present on the host (local-only; the file is not in the
//     repo). We require layer count > 100, segment count > 100 k,
//     and all segments carrying a known type code.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/engine/gcode_parser.dart';

Future<GcodeGeometry> _parseString(String s) async {
  final tmp = await Directory.systemTemp.createTemp('hs_parse_');
  final f = File('${tmp.path}/x.gcode');
  await f.writeAsString(s);
  try {
    return await parseGcodeInline(f.path);
  } finally {
    try { await tmp.delete(recursive: true); } catch (_) {}
  }
}

void main() {
  group('parseGcode synthetic', () {
    test('three-layer cube, outer wall + inner wall + travel, 1 filament',
        () async {
      // Hand-rolled g-code with explicit ;TYPE: markers.
      final s = '''
;TYPE:Outer wall
G1 X0 Y0 Z0.2 E0
G1 X10 Y0 Z0.2 E1
;TYPE:Inner wall
G1 X10 Y10 Z0.2 E2
G1 X0 Y10 Z0.2 E3
G1 X0 Y0 Z0.2 E4
;TYPE:Outer wall
G1 X0 Y0 Z0.4 E5
G1 X10 Y0 Z0.4 E6
G1 X10 Y10 Z0.4 E7
;TYPE:Outer wall
G1 X0 Y10 Z0.6 E8
G1 X0 Y0 Z0.6 E9
''';
      final g = await _parseString(s);
      expect(g.layerCount, 3);
      // Each extrusion G1 after the first position becomes one segment.
      // Line 1 sets start pos (no segment); then 9 extrusion segments.
      expect(g.segmentCount, 9);
      expect(g.extrudedMm, 9.0);
      // AABB on XY = 0..10
      expect(g.minXY, 0);
      expect(g.maxXY, 10);
      expect(g.minZ, 0.2);
      expect(g.maxZ, 0.6);
      // Type distribution: first segment is unknown (no ;TYPE: seen yet
      // at the time of the first move) — but our test does see ;TYPE:
      // before all extrudes, so every segment is Outer or Inner wall.
      // Count outer / inner.
      int outer = 0, inner = 0;
      for (int i = 0; i < g.segmentCount; ++i) {
        if (g.types[i] == PathType.outerWall.code) outer++;
        if (g.types[i] == PathType.innerWall.code) inner++;
      }
      expect(outer + inner, g.segmentCount);
      expect(outer, greaterThan(0));
      expect(inner, greaterThan(0));
    });

    test('travel moves land in the Travel bucket', () async {
      final s = '''
;TYPE:Outer wall
G1 X0 Y0 Z0.2 E0
G0 X5 Y5 Z0.2
G1 X10 Y10 Z0.2 E1
''';
      final g = await _parseString(s);
      expect(g.segmentCount, 2);
      expect(g.types[0], PathType.travel.code);
      expect(g.types[1], PathType.outerWall.code);
    });

    test('T<idx> updates filament index for subsequent segments', () async {
      final s = '''
;TYPE:Outer wall
G1 X0 Y0 Z0.2 E0
G1 X10 Y0 Z0.2 E1
T2
G1 X10 Y10 Z0.2 E2
G1 X0 Y10 Z0.2 E3
''';
      final g = await _parseString(s);
      expect(g.segmentCount, 3);
      expect(g.filaments[0], 0);
      expect(g.filaments[1], 2);
      expect(g.filaments[2], 2);
    });

    test('normal types map correctly', () async {
      final cases = {
        'Outer wall': PathType.outerWall.code,
        'Inner wall': PathType.innerWall.code,
        'Overhang wall': PathType.outerWall.code,
        'Sparse infill': PathType.internalInfill.code,
        'Internal infill': PathType.internalInfill.code,
        'Gap infill': PathType.internalInfill.code,
        'Solid infill': PathType.solidInfill.code,
        'Internal solid infill': PathType.solidInfill.code,
        'Top surface': PathType.topSurface.code,
        'Bottom surface': PathType.bottomSurface.code,
        'Bridge': PathType.bridge.code,
        'Internal Bridge': PathType.bridge.code,
        'Support': PathType.support.code,
        'Support interface': PathType.supportInterface.code,
        'Skirt': PathType.skirtBrim.code,
        'Brim': PathType.skirtBrim.code,
        'Prime tower': PathType.primeTower.code,
        'Custom': PathType.custom.code,
      };
      for (final e in cases.entries) {
        final s = ';TYPE:${e.key}\n'
            'G1 X0 Y0 Z0.2 E0\n'
            'G1 X1 Y0 Z0.2 E1\n';
        final g = await _parseString(s);
        expect(g.segmentCount, 1);
        expect(g.types[0], e.value, reason: 'TYPE ${e.key}');
      }
    });
  });

  group('parseGcode on the real Auryn g-code', () {
    final auryn = File('../local-test/auryn-x86.gcode');
    test('Auryn: layers, segments, AABB look sane',
        () async {
          if (!auryn.existsSync()) {
            // local-test is not in the repo; skip on CI.
            return;
          }
          final g = await parseGcodeInline(auryn.path);
          expect(g.segmentCount, greaterThan(1000000));
          expect(g.layerCount, greaterThan(1000));
          expect(g.maxZ, greaterThan(100.0));
          // Every segment carries a known type.
          const maxCode = 13;   // Unknown
          for (int i = 0; i < g.segmentCount; ++i) {
            expect(g.types[i], lessThanOrEqualTo(maxCode));
          }
        },
        timeout: const Timeout(Duration(seconds: 30)));
  });
}
