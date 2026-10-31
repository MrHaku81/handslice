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

    test('Z-hops between layers do not fake extra layers', () async {
      // Two real layers at Z=0.2 and Z=0.4, with a travel-with-
      // z-hop in between. Without the explicit-marker trust this
      // would count as three layers.
      final s = '''
;LAYER:0
G1 X0 Y0 Z0.2 E0
G1 X10 Y0 Z0.2 E1
G1 X10 Y10 Z0.2 E2
;LAYER_CHANGE
;Z:0.4
;WIPE_START
G0 X10 Y10 Z1.0 F30000
G0 X0 Y0 Z1.0
;LAYER:1
G1 X0 Y0 Z0.4 E3
G1 X10 Y0 Z0.4 E4
G1 X10 Y10 Z0.4 E5
''';
      final g = await _parseString(s);
      expect(g.layerCount, 2);
    });

    test('legacy g-code without ;LAYER: markers falls back to Z-step',
        () async {
      final s = '''
G1 X0 Y0 Z0.2 E0
G1 X10 Y0 Z0.2 E1
G1 X10 Y10 Z0.4 E2
G1 X0 Y10 Z0.4 E3
G1 X0 Y0 Z0.6 E4
''';
      final g = await _parseString(s);
      expect(g.layerCount, 3);
    });

    test('M83 relative-E: identical E values are not treated as travel',
        () async {
      // Regression: an M83 g-code with two consecutive extrusions
      // of the same length (common on walls, same perimeter edge
      // length) used to bucket the second as travel, because the
      // parser was running the delta subtraction regardless of
      // mode. Here each move extrudes 1 mm.
      final s = '''
M83
;TYPE:Outer wall
G1 X0 Y0 Z0.2 E0
G1 X10 Y0 Z0.2 E1
G1 X10 Y10 Z0.2 E1
G1 X0 Y10 Z0.2 E1
G1 X0 Y0 Z0.2 E1
''';
      final g = await _parseString(s);
      // All four moves after the first should be Outer wall.
      final outerCount = <int>[
        for (int i = 0; i < g.segmentCount; ++i)
          if (g.types[i] == PathType.outerWall.code) i,
      ].length;
      expect(outerCount, 4);
      expect(g.extrudedMm, closeTo(4.0, 1e-6));
    });

    test('G2 arc interpolates into many short segments', () async {
      // A quarter circle from (1,0) around centre (0,0) going CCW
      // to (0,1). Expect several interpolated segments and
      // every emitted segment length to be short.
      final s = '''
M83
G1 X1 Y0 Z0.2 E0
;TYPE:Outer wall
G3 X0 Y1 Z0.2 I-1 J0 E1
''';
      final g = await _parseString(s);
      expect(g.segmentCount, greaterThan(5));
      // Chord of the quarter circle is sqrt(2) ≈ 1.414; the
      // interpolated path should run along the arc (length
      // = π/2 ≈ 1.571), measurably longer than the chord.
      final totalLen = g.lengthByType[PathType.outerWall.code];
      expect(totalLen, greaterThan(1.5));
      expect(totalLen, lessThan(1.7));
    });

    test('G92 E0 resets the absolute-E baseline', () async {
      final s = '''
M82
;TYPE:Outer wall
G1 X0 Y0 Z0.2 E0
G1 X10 Y0 Z0.2 E5
G92 E0
G1 X10 Y10 Z0.2 E5
''';
      final g = await _parseString(s);
      // Two extruded 10 mm segments, each adding 5 mm to the
      // E counter (second one after the G92 reset).
      expect(g.extrudedMm, closeTo(10.0, 1e-6));
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

  group('parseGcode on real g-code samples', () {
    final auryn = File('../local-test/auryn-x86.gcode');
    final cube  = File('../local-test/thumbnail-cube.gcode');

    test('Auryn: layers, segments, AABB look sane',
        () async {
          if (!auryn.existsSync()) return; // local-test not in repo
          final g = await parseGcodeInline(auryn.path);
          expect(g.segmentCount, greaterThan(1000000));
          // Auryn's "TOTAL_LAYER=1046" header matches what we see.
          expect(g.layerCount, inInclusiveRange(1040, 1050));
          expect(g.maxZ, greaterThan(100.0));
          const maxCode = 13;   // Unknown
          for (int i = 0; i < g.segmentCount; ++i) {
            expect(g.types[i], lessThanOrEqualTo(maxCode));
          }
        },
        timeout: const Timeout(Duration(seconds: 30)));

    test('notched cube: 100 layers (20 mm / 0.2 mm)', () async {
      if (!cube.existsSync()) return;
      final g = await parseGcodeInline(cube.path);
      // Prior bug counted ~399 layers because every z-hop looked
      // like a new layer. The physical cube is 100 layers.
      expect(g.layerCount, 100);
      // maxZ reflects every Z the toolhead visited, including the
      // post-print park-head-up move (G1 Z80 at the end), so we
      // check that the model-height range is in there, not an
      // exact value.
      expect(g.maxZ, greaterThanOrEqualTo(19.8));
    });

    test('notched cube: parsed filament matches Orca footer within 1 %',
        () async {
      if (!cube.existsSync()) return;
      // Footer:  ; filament used [mm] = 1177.15
      // Parser must count every extrusion delta (M83 relative,
      // retract/un-retract balancing out, G92 E0 resets around
      // retracts). Allow 1 % slack; retracts are kept out of
      // the sum because we only add positive deltas.
      final footerMm = _footerFilamentMm(cube);
      final g = await parseGcodeInline(cube.path);
      final rel = (g.extrudedMm - footerMm).abs() / footerMm;
      expect(rel, lessThan(0.01),
          reason: 'parsed=${g.extrudedMm.toStringAsFixed(3)} '
              'footer=${footerMm.toStringAsFixed(3)}');
    });

    test('notched cube: per-type lengths add up and cover walls',
        () async {
      if (!cube.existsSync()) return;
      final g = await parseGcodeInline(cube.path);
      final outer = g.lengthByType[PathType.outerWall.code];
      final inner = g.lengthByType[PathType.innerWall.code];
      // A 20 mm cube with 100 layers of ~75 mm outer perimeter
      // gives ≈ 7500 mm of outer wall. We only check the order
      // of magnitude.
      expect(outer, greaterThan(5000));
      expect(inner, greaterThan(5000));
    });
  });
}

double _footerFilamentMm(File gcode) {
  final text = gcode.readAsStringSync();
  final re = RegExp(r'^;\s*filament used \[mm\]\s*=\s*([\d.]+)',
      multiLine: true);
  final match = re.firstMatch(text);
  if (match == null) {
    throw StateError('no "; filament used [mm]" line in ${gcode.path}');
  }
  return double.parse(match.group(1)!);
}
