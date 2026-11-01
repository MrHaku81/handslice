// Pflicht 7c/7d — toolpath (HSPT) parser tests.
//
// Three groups:
//   - A hand-rolled HSPT v2 buffer that pins the field layout and
//     the role / move-type byte codes.
//   - Checks on the derived summaries (object-only AABB, time
//     per role, grams from density × diameter).
//   - A sanity run against a freshly produced HSPT from
//     `handslice-cli --input-gcode --export-toolpaths` on the
//     thumbnail cube (local-only; the artefact is not in the
//     repo). The cube g-code is also pinned to Orca's layer 52
//     ≈ z=10.40 mm expectation from the reference screenshot.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/engine/toolpath_parser.dart';

Uint8List _hspt({
  required List<Map<String, dynamic>> moves,
  double density = 1.25,
  double diameter = 1.75,
}) {
  final bytes = BytesBuilder();
  // Header (24 B).
  bytes.add(const [0x48, 0x53, 0x50, 0x54]);
  final hdr = ByteData(20)
    ..setUint32(0, 2, Endian.little)
    ..setUint32(4, 0, Endian.little)
    ..setUint32(8, moves.length, Endian.little)
    ..setFloat32(12, density, Endian.little)
    ..setFloat32(16, diameter, Endian.little);
  bytes.add(hdr.buffer.asUint8List());
  for (final m in moves) {
    final b = ByteData(hsptRecordSize);
    b.setUint8(0,  m['role']     as int);
    b.setUint8(1,  m['extruder'] as int);
    b.setUint8(2,  m['moveType'] as int);
    b.setUint8(3,  0);
    b.setUint16(4,  m['layer']    as int, Endian.little);
    b.setUint16(6,  m['width100'] as int, Endian.little);
    b.setUint16(8,  m['height100'] as int, Endian.little);
    b.setUint16(10, m['feedrate'] as int, Endian.little);
    b.setFloat32(12, (m['x'] as num).toDouble(), Endian.little);
    b.setFloat32(16, (m['y'] as num).toDouble(), Endian.little);
    b.setFloat32(20, (m['z'] as num).toDouble(), Endian.little);
    b.setFloat32(24, (m['e']  as num).toDouble(), Endian.little);
    b.setFloat32(28, ((m['time'] ?? 0.0) as num).toDouble(), Endian.little);
    bytes.add(b.buffer.asUint8List());
  }
  return bytes.toBytes();
}

void main() {
  group('parseToolpathsInline', () {
    test('rejects bad magic', () {
      final b = Uint8List(hsptHeaderSize);
      expect(() => parseToolpathsInline(b),
          throwsA(isA<FormatException>()));
    });

    test('rejects HSPT v1 with a clear error', () {
      // 16-byte v1 header + no moves.
      final b = Uint8List(16)
        ..[0] = 0x48 ..[1] = 0x53 ..[2] = 0x50 ..[3] = 0x54;
      ByteData.sublistView(b).setUint32(4, 1, Endian.little);
      expect(() => parseToolpathsInline(b),
          throwsA(isA<FormatException>()));
    });

    test('three-move scenario: travel, outer wall, inner wall', () {
      final bytes = _hspt(moves: [
        {
          'role': GcodeRole.none.index,  'extruder': 0,
          'moveType': MoveType.noop.index,
          'layer': 0, 'width100': 0, 'height100': 0, 'feedrate': 0,
          'x': 0, 'y': 0, 'z': 0, 'e': 0, 'time': 0.0,
        },
        {
          // Travel to the start of the outer wall.
          'role': GcodeRole.none.index,  'extruder': 0,
          'moveType': MoveType.travel.index,
          'layer': 0, 'width100': 0, 'height100': 0, 'feedrate': 180,
          'x': 10, 'y': 10, 'z': 0.2, 'e': 0, 'time': 0.5,
        },
        {
          // Outer wall segment.
          'role': GcodeRole.externalPerimeter.index, 'extruder': 0,
          'moveType': MoveType.extrude.index,
          'layer': 0, 'width100': 42, 'height100': 20, 'feedrate': 60,
          'x': 20, 'y': 10, 'z': 0.2, 'e': 0.42, 'time': 1.2,
        },
        {
          // Inner wall segment.
          'role': GcodeRole.perimeter.index, 'extruder': 0,
          'moveType': MoveType.extrude.index,
          'layer': 0, 'width100': 42, 'height100': 20, 'feedrate': 60,
          'x': 20, 'y': 20, 'z': 0.2, 'e': 0.42, 'time': 1.3,
        },
      ]);
      final t = parseToolpathsInline(bytes);
      expect(t.moveCount, 4);
      expect(t.layerCount, 1);
      expect(t.extrudedMm, closeTo(0.84, 1e-5));
      expect(t.extrudedByRole[GcodeRole.externalPerimeter.index],
          closeTo(0.42, 1e-5));
      expect(t.extrudedByRole[GcodeRole.perimeter.index],
          closeTo(0.42, 1e-5));
      // Bounding box is extrusion-only: travels (x,y=10,10) do
      // not count.
      expect(t.minX, 20);
      expect(t.maxX, 20);
      expect(t.minY, 10);
      expect(t.maxY, 20);
      // Object-only AABB == whole AABB here (both roles are
      // walls, not skirt/brim/wipe).
      expect(t.objMinX, 20);
      expect(t.objMaxY, 20);
      // Time: 0 + 0.5 + 1.2 + 1.3 = 3.0 s. timeByRole is
      // extrude-only (travels have their own bucket), so the
      // 0.5 s travel does NOT show up in `timeByRole[none]`;
      // it goes into `timeByMove[travel]`.
      expect(t.totalTimeSec, closeTo(3.0, 1e-5));
      expect(t.timeByRole[GcodeRole.externalPerimeter.index],
          closeTo(1.2, 1e-5));
      expect(t.timeByRole[GcodeRole.perimeter.index],
          closeTo(1.3, 1e-5));
      expect(t.timeByRole[GcodeRole.none.index], 0);
      expect(t.timeByMove[MoveType.travel.index], closeTo(0.5, 1e-5));
      expect(t.timeByMove[MoveType.extrude.index], closeTo(2.5, 1e-5));
      // distanceByMove covers every move type (travel +
      // extrude in this fixture). travel: (0,0,0) → (10,10,0.2)
      // ≈ 14.1428 mm. extrude: (10,10,0.2) → (20,10,0.2) +
      // (20,10,0.2) → (20,20,0.2) = 20 mm total.
      expect(t.distanceByMove[MoveType.travel.index],
          closeTo(14.1428, 1e-3));
      expect(t.distanceByMove[MoveType.extrude.index],
          closeTo(20.0, 1e-5));
      expect(t.countByMove[MoveType.travel.index], 1);
      expect(t.countByMove[MoveType.extrude.index], 2);
      final move2 = Move(t.bd, 2 * hsptRecordSize);
      expect(move2.role, GcodeRole.externalPerimeter);
      expect(move2.width, closeTo(0.42, 1e-5));
      expect(move2.timeS, closeTo(1.2, 1e-5));
      // Weight from density + diameter: 0.84 mm × π*(1.75/2)² mm²
      // × 1.25 g/cm³ / 1000.
      final expectedG = 0.84 *
          math.pi * (1.75 * 0.5) * (1.75 * 0.5) *
          1.25 * 1e-3;
      expect(t.gramsFromExtrudedMm(t.extrudedMm),
          closeTo(expectedG, 1e-6));
    });

    test('skirt and brim do not inflate the object AABB', () {
      final bytes = _hspt(moves: [
        // Skirt lap at (0, -2) – outside the model.
        {
          'role': GcodeRole.skirt.index, 'extruder': 0,
          'moveType': MoveType.extrude.index,
          'layer': 0, 'width100': 40, 'height100': 20, 'feedrate': 60,
          'x': 0, 'y': -2, 'z': 0.2, 'e': 0.5, 'time': 0.4,
        },
        // Model wall at (10, 10).
        {
          'role': GcodeRole.externalPerimeter.index, 'extruder': 0,
          'moveType': MoveType.extrude.index,
          'layer': 0, 'width100': 42, 'height100': 20, 'feedrate': 60,
          'x': 10, 'y': 10, 'z': 0.2, 'e': 0.5, 'time': 0.6,
        },
      ]);
      final t = parseToolpathsInline(bytes);
      // Whole-print AABB includes the skirt move.
      expect(t.minY, -2);
      // Object-only AABB excludes it.
      expect(t.objMinY, 10);
      expect(t.objMinX, 10);
    });

    test('layerZ tracks the latest object-extrude z, not retracts',
        () {
      // Bin 1 starts with a retract still at z=0.2 (prev layer),
      // then an extrude at z=0.4. Orca shows z=0.4 for that bin.
      final bytes = _hspt(moves: [
        {
          'role': GcodeRole.externalPerimeter.index, 'extruder': 0,
          'moveType': MoveType.extrude.index,
          'layer': 0, 'width100': 42, 'height100': 20, 'feedrate': 60,
          'x': 10, 'y': 10, 'z': 0.2, 'e': 0.4, 'time': 0.5,
        },
        {
          'role': GcodeRole.externalPerimeter.index, 'extruder': 0,
          'moveType': MoveType.retract.index,
          'layer': 1, 'width100': 0, 'height100': 0, 'feedrate': 60,
          'x': 10, 'y': 10, 'z': 0.2, 'e': -0.8, 'time': 0.1,
        },
        {
          'role': GcodeRole.externalPerimeter.index, 'extruder': 0,
          'moveType': MoveType.extrude.index,
          'layer': 1, 'width100': 42, 'height100': 20, 'feedrate': 60,
          'x': 20, 'y': 10, 'z': 0.4, 'e': 0.4, 'time': 0.5,
        },
      ]);
      final t = parseToolpathsInline(bytes);
      expect(t.layerCount, 2);
      expect(t.layerZ[0], closeTo(0.2, 1e-5));
      expect(t.layerZ[1], closeTo(0.4, 1e-5));
    });
  });

  group('on real HSPT (local only)', () {
    final hspt = File('local-test/cube.hspt');
    final cubeGcode = File('local-test/thumbnail-cube.gcode');
    test('decodes a thumbnail-cube HSPT if present',
        () async {
          if (!hspt.existsSync()) return;
          final t = await loadToolpaths(hspt.path);
          expect(t.moveCount, greaterThan(1000));
          // Default CC2 cube should surface the outer-wall and
          // inner-wall roles.
          expect(t.extrudedByRole[GcodeRole.externalPerimeter.index],
              greaterThan(100));
          expect(t.extrudedByRole[GcodeRole.perimeter.index],
              greaterThan(100));
        },
        timeout: const Timeout(Duration(seconds: 30)));

    test('cube HSPT extrudedMm matches the g-code footer within 1 %',
        () async {
      if (!hspt.existsSync() || !cubeGcode.existsSync()) return;
      final text = cubeGcode.readAsStringSync();
      final match = RegExp(r'^;\s*filament used \[mm\]\s*=\s*([\d.]+)',
          multiLine: true).firstMatch(text);
      expect(match, isNotNull);
      final footer = double.parse(match!.group(1)!);
      final t = await loadToolpaths(hspt.path);
      final rel = (t.extrudedMm - footer).abs() / footer;
      expect(rel, lessThan(0.01),
          reason: 'HSPT extrudedMm=${t.extrudedMm.toStringAsFixed(3)} '
              'vs footer=${footer.toStringAsFixed(3)}');
    });

    test('cube HSPT lengthByRole + extrudedByRole are reported', () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      expect(t.lengthByRole[GcodeRole.externalPerimeter.index],
          greaterThan(100));
      expect(t.lengthByRole[GcodeRole.perimeter.index],
          greaterThan(100));
      // Length and extruded E are the same order of magnitude on
      // this profile (0.42 mm × 0.2 mm cross-section → ~0.84 mm3
      // per mm of path, delta E ≈ path length in mm since the
      // flow stays flat). Sanity: ratio within an order of
      // magnitude.
      final ratio = t.extrudedByRole[GcodeRole.externalPerimeter.index]
          / t.lengthByRole[GcodeRole.externalPerimeter.index];
      expect(ratio, greaterThan(0.1));
      expect(ratio, lessThan(10));
    });

    test('layerXyBounds returns per-layer bbox not the whole print',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      // Layer 52 (1-indexed, Orca label) should fit inside the
      // whole-print XY bbox.
      final whole = layerXyBounds(t, 0, t.moveCount);
      final mid = layerXyBounds(t, t.layerStart(51), t.layerEnd(51));
      expect(whole, isNotNull);
      expect(mid,   isNotNull);
      expect(mid!.minX, greaterThanOrEqualTo(whole!.minX));
      expect(mid.maxX,  lessThanOrEqualTo(whole.maxX));
      expect(mid.minY, greaterThanOrEqualTo(whole.minY));
      expect(mid.maxY,  lessThanOrEqualTo(whole.maxY));
    });

    test('cube HSPT layer 52 lands at z=10.40 mm (matches Orca)',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      // Reference screenshot (local-test/orca-referenz-schicht52
      // .png): Orca's slider at "Layer 52" shows z = 10.40 mm.
      // Our slider is 0-indexed; label is `${value+1}`, so bin 51
      // should carry the z of the 52nd printed layer.
      expect(t.layerCount, greaterThanOrEqualTo(100));
      expect(t.layerZ[51], closeTo(10.40, 0.01));
    });

    test('cube HSPT object-only AABB excludes purge/skirt',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      // Model centres on (128, 128) with 20 mm side → object
      // AABB roughly 118..138 in X and Y. The purge line sits at
      // y=-1.2 so the whole-print AABB has minY ≤ 0.
      expect(t.objMinY, greaterThan(100));
      expect(t.objMaxY, lessThan(150));
    });

    test('cube HSPT density/diameter and totalTimeSec are populated',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      // CC2 default Elegoo PLA: 1.75 mm, 1.25 g/cm³.
      expect(t.filamentDiameterMm, closeTo(1.75, 1e-3));
      expect(t.filamentDensityGcm3, closeTo(1.25, 1e-2));
      // Reference screenshot (local-test/orca-referenz-
      // schicht52.png): 9m25s = 565 s. Our 7d regen lands at
      // 561 s — tolerance ±5 s.
      expect(t.totalTimeSec, closeTo(565, 10));
    });

    test('cube HSPT total filament = extrudedMm/1000 ≈ 1.17 m',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      // Orca reference: 1.17 m · 3.52 g. We compute both from
      // extrudedMm — the sum of positive E-deltas, which equals
      // the footer's `; filament used [mm]`.
      final filamentMetres = t.extrudedMm * 0.001;
      final weightG = t.gramsFromExtrudedMm(t.extrudedMm);
      expect(filamentMetres, closeTo(1.17, 0.01));
      expect(weightG, closeTo(3.52, 0.05));
    });

    test('cube HSPT per-move time breakdown sums to totalTimeSec',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      double sum = 0;
      for (final v in t.timeByMove) {
        sum += v;
      }
      expect(sum, closeTo(t.totalTimeSec, 1e-3));
      // And role-time (extrude-only) alone must be LESS than
      // the total — otherwise we're double-counting travel /
      // wipe / retract time, which caused the 11 min / 9m25s
      // mismatch Klaus flagged on the 66e7c46 device run.
      double roleSum = 0;
      for (final v in t.timeByRole) {
        roleSum += v;
      }
      expect(roleSum, lessThan(t.totalTimeSec));
      // Extrude-only role time should equal timeByMove[extrude]
      // because every extrude move is role-coded and we filter
      // the per-role bucket to extrude-only.
      expect(roleSum,
          closeTo(t.timeByMove[MoveType.extrude.index], 1e-3));
    });

    test('cube HSPT travel distance populated for the Travel row',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      // 20 mm cube on CC2 standard has a non-trivial travel
      // budget (bed-to-model, between walls, …). Any positive
      // number is enough to prove the Dart parser is tracking
      // `m_move_type_distances` the way Orca does.
      expect(t.distanceByMove[MoveType.travel.index],
          greaterThan(100.0));
    });
  });
}
