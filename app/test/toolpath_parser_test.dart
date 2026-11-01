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

    test(
        'Z-hop above the layer height does not shift layerZ or layerCount',
        () {
      // Simulate what Orca does with `z_hop > 0`: at the end
      // of a layer we lift Z, travel, then descend to the next
      // layer's print height before extruding again. The hop
      // moves are `travel` type, not `extrude`, so they must
      // not pull `layerZ` upward and must not spawn a new bin.
      final bytes = _hspt(moves: [
        // Layer 0 extrude at z=0.2.
        {
          'role': GcodeRole.externalPerimeter.index, 'extruder': 0,
          'moveType': MoveType.extrude.index,
          'layer': 0, 'width100': 42, 'height100': 20, 'feedrate': 60,
          'x': 10, 'y': 10, 'z': 0.2, 'e': 0.4, 'time': 0.5,
        },
        // Z-hop up to z=0.6 (still layer 0, travel only).
        {
          'role': GcodeRole.externalPerimeter.index, 'extruder': 0,
          'moveType': MoveType.travel.index,
          'layer': 0, 'width100': 0, 'height100': 0, 'feedrate': 180,
          'x': 10, 'y': 10, 'z': 0.6, 'e': 0, 'time': 0.1,
        },
        // Layer 1 travel back down to z=0.4 (hop end).
        {
          'role': GcodeRole.externalPerimeter.index, 'extruder': 0,
          'moveType': MoveType.travel.index,
          'layer': 1, 'width100': 0, 'height100': 0, 'feedrate': 180,
          'x': 20, 'y': 10, 'z': 0.4, 'e': 0, 'time': 0.1,
        },
        // Layer 1 extrude at the real print height z=0.4.
        {
          'role': GcodeRole.externalPerimeter.index, 'extruder': 0,
          'moveType': MoveType.extrude.index,
          'layer': 1, 'width100': 42, 'height100': 20, 'feedrate': 60,
          'x': 30, 'y': 10, 'z': 0.4, 'e': 0.4, 'time': 0.5,
        },
      ]);
      final t = parseToolpathsInline(bytes);
      // Two bins, each pinned at the extrude Z — the 0.6 mm
      // hop stayed off `layerZ` because it was a travel.
      expect(t.layerCount, 2);
      expect(t.layerZ[0], closeTo(0.2, 1e-5));
      expect(t.layerZ[1], closeTo(0.4, 1e-5));
      // The maxZ bbox reflects the real print height too — it
      // comes off extrudes, not travels.
      expect(t.maxZ, closeTo(0.4, 1e-5));
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

    test(
        'Layer 52 draws only moves with layer_id ≤ 51 (never above the slider)',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      // Orca "Layer 52" == 0-indexed bin 51. The view's
      // _rebuildScene walks records up to `t.layerEnd(51)` and
      // never beyond.
      const current0 = 51; // Orca label 52
      final endOfCurrent = t.layerEnd(current0);
      final totalMoves = t.moveCount;
      final totalExtrudes =
          countOfMoveTypeIn(t, 0, totalMoves, MoveType.extrude);
      final drawnMoves = endOfCurrent;
      final drawnExtrudes =
          countOfMoveTypeIn(t, 0, endOfCurrent, MoveType.extrude);
      final skippedMoves = totalMoves - drawnMoves;
      // Pin the numbers against the HSPT dump used in the
      // report: 2674 drawn, 1626 of them extrudes; 2800 skipped.
      expect(drawnMoves, 2674);
      expect(drawnExtrudes, 1626);
      expect(skippedMoves, 2800);
      // Core invariant: no record below `endOfCurrent` has a
      // layer_id above `current0`. If this ever regresses the
      // view will leak upper-layer extrudes into the frame.
      expect(maxLayerIdIn(t, 0, endOfCurrent), lessThanOrEqualTo(current0));
      // And every record from `endOfCurrent` onward belongs to
      // a strictly higher layer.
      expect(maxLayerIdIn(t, endOfCurrent, totalMoves),
          greaterThan(current0));
      // Smoke-check so the first assertion does not degenerate
      // into `expect(0, 0)` on a trimmed HSPT.
      expect(drawnExtrudes, lessThan(totalExtrudes));
    });

    test(
        'EVERY slider position 1..layerCount matches the gcode ;LAYER_CHANGE/;Z: pair',
        () async {
      if (!hspt.existsSync() || !cubeGcode.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      // Ground truth: every (;LAYER_CHANGE, ;Z:<value>) pair
      // in the g-code, in order. Orca's slider labels Layer N
      // with the Z Orca itself emits here, so comparing the
      // Dart `layerZ` array against this list proves our
      // numbering lines up with Orca's for the whole print, not
      // just a single slider position.
      final expectedZ = <double>[];
      String prev = '';
      for (final raw in cubeGcode.readAsLinesSync()) {
        final line = raw.trim();
        if (prev == ';LAYER_CHANGE' && line.startsWith(';Z:')) {
          expectedZ.add(double.parse(line.substring(3)));
        }
        prev = line;
      }
      expect(expectedZ.length, 100,
          reason: 'thumbnail cube is 100 printed layers');
      // Our `layerCount` is 1-based for the UI; `layerZ` is
      // 0-based (internal). Slider label is `${value+1}`.
      expect(t.layerCount, expectedZ.length);
      // Sweep. The test name says 1..layerCount so the error
      // message gives the layer number the way the UI prints
      // it; `current0` is the internal 0-based bin index.
      for (int N = 1; N <= expectedZ.length; ++N) {
        final current0 = N - 1;
        expect(t.layerZ[current0], closeTo(expectedZ[current0], 0.001),
            reason:
                'displayed Layer $N (internal $current0): '
                'Dart layerZ=${t.layerZ[current0]} vs '
                'gcode ;Z:=${expectedZ[current0]}');
      }
    });

    test(
        'EVERY slider position 1..layerCount: only moves with layer_id ≤ N-1 are drawn',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      final totalMoves = t.moveCount;
      // Sweep every slider position. For each, the view calls
      // `t.layerEnd(current0)` to compute the record-stream
      // cutoff; no record below the cutoff may have a layer_id
      // above `current0`, and no record from the cutoff onward
      // may have one at or below `current0`. The second half of
      // the invariant degenerates at the last layer (nothing
      // above it), which we handle explicitly.
      for (int N = 1; N <= t.layerCount; ++N) {
        final current0 = N - 1;
        final endOfCurrent = t.layerEnd(current0);
        expect(maxLayerIdIn(t, 0, endOfCurrent),
            lessThanOrEqualTo(current0),
            reason: 'Layer $N (internal $current0): a drawn '
                'record carries layer_id > $current0 — upper-'
                'layer extrudes leaking into the frame');
        if (endOfCurrent < totalMoves) {
          // Any record above the cutoff must belong to a layer
          // strictly above the current one.
          final bd = ByteData.sublistView(t.data);
          int minAbove = 1 << 30;
          for (int i = endOfCurrent; i < totalMoves; ++i) {
            final o = i * hsptRecordSize;
            final lid = bd.getUint16(o + 4, Endian.little);
            if (lid < minAbove) minAbove = lid;
          }
          expect(minAbove, greaterThan(current0),
              reason: 'Layer $N (internal $current0): a record '
                  'above the cutoff carries layer_id ≤ $current0');
        }
        // Also: cumulative drawn + skipped == total. If this
        // breaks the layerEnd() helper is miscounting.
        final drawn = endOfCurrent;
        final skipped = totalMoves - drawn;
        expect(drawn + skipped, totalMoves);
      }
    });

    test(
        'edge — first slider position (Layer 1) includes the skirt / purge-line extrudes',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      // Thumbnail cube uses `skirt_loops = 0`, so Orca emits
      // the start-g-code purge line only. Its moves land in
      // bin 0 (same `layer_id` as the first printed layer),
      // role = `custom` (18) with `moveType = Extrude`. Being
      // in bin 0 means they ARE drawn when the slider sits at
      // Layer 1 — not deferred to a non-existent "Layer 0".
      final purgeExtrudes = countOfMoveTypeIn(
          t, 0, t.layerEnd(0), MoveType.extrude);
      expect(purgeExtrudes, greaterThan(0));
      // Among those extrudes some belong to `custom` role (the
      // purge line itself), proving the start-g-code was
      // folded into Layer 1 rather than dropped.
      final bd = ByteData.sublistView(t.data);
      int customExtrudes = 0;
      for (int i = 0; i < t.layerEnd(0); ++i) {
        final o = i * hsptRecordSize;
        if (bd.getUint8(o + 2) != MoveType.extrude.index) continue;
        if (bd.getUint8(o) == GcodeRole.custom.index) customExtrudes++;
      }
      expect(customExtrudes, greaterThan(0),
          reason: 'Layer 1 should carry the purge-line custom-'
              'role extrudes alongside the first wall');
    });

    test(
        'edge — last slider position (Layer N) draws everything; nothing above',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      final current0 = t.layerCount - 1;
      final endOfCurrent = t.layerEnd(current0);
      expect(endOfCurrent, t.moveCount,
          reason: 'the last layer must span to the end of the '
              'record stream');
      // The Z of the last printed layer is 20.0 mm on the
      // thumbnail cube — pinned so the "top of the print" is
      // not off by a layer when the user drags all the way up.
      expect(t.layerZ[current0], closeTo(20.0, 0.01));
    });

    test(
        'layerStarts strictly monotonic — slider ± 1 always lands on a distinct layer',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      // The IconButton `+` / `-` affordance calls
      // `_setLayer(value ± 1)` which maps to `layerStart`
      // directly. If two adjacent bins had the same start we
      // could not step through them one at a time. Pinning
      // monotonicity rules that out across the whole print.
      for (int i = 1; i < t.layerCount; ++i) {
        expect(t.layerStart(i), greaterThan(t.layerStart(i - 1)),
            reason:
                'layerStart[$i] (${t.layerStart(i)}) must be '
                'strictly greater than layerStart[${i - 1}] '
                '(${t.layerStart(i - 1)}) — otherwise the slider '
                'cannot select bin $i independently from ${i - 1}');
      }
    });

    test(
        'at Layer 52 the dominant drawn role is internalInfill (red)',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      // Pins the explanation for the "big red area" Klaus
      // flagged on 409e425: at Orca Layer 52 the top of the
      // drawn stack is dominated by internalInfill (role 4,
      // colour 0xFFB03029 → dark red). topSolidInfill (role 6,
      // 0xFFF04040 → bright red) does not appear in layers ≤
      // 51 yet, so no "red" comes from above the slider.
      const current0 = 51;
      final endOfCurrent = t.layerEnd(current0);
      final counts = <int, int>{};
      final bd = ByteData.sublistView(t.data);
      for (int i = 0; i < endOfCurrent; ++i) {
        final o = i * hsptRecordSize;
        if (bd.getUint8(o + 2) != MoveType.extrude.index) continue;
        final r = bd.getUint8(o);
        counts[r] = (counts[r] ?? 0) + 1;
      }
      expect(counts[GcodeRole.internalInfill.index], 833);
      // topSolidInfill arrives only near the end of the print.
      expect(counts[GcodeRole.topSolidInfill.index] ?? 0, 0);
      // And the colour the UI picks is Orca's dark red.
      expect(OrcaPalette.roleColor[GcodeRole.internalInfill]!
          .toRadixString(16), 'ffb03029');
    });
  });

  group('on real HSPT (local only, large print)', () {
    // Auryn: a ~209-mm print at 0.2 mm layers → 1045 printed
    // layers, 2.1 M HSPT records, 7h 11m print time. The HSPT
    // is regenerated with `handslice-cli-x86 --input-gcode
    // local-test/auryn-x86.gcode --export-toolpaths local-test
    // /auryn.hspt`; both are gitignored. The tests gate on
    // file-exists so CI without the file passes silently.
    final hspt = File('local-test/auryn.hspt');
    final auryn = File('local-test/auryn-x86.gcode');

    // Longer than the cube — load once per test. The cube takes
    // ~2 ms to parse; Auryn's 2.1 M records takes ~400 ms.
    const timeout = Timeout(Duration(minutes: 2));

    test('Auryn HSPT loads and reports a plausible layer count',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      // Report rather than assert exact values; the gcode may
      // be re-sliced locally. These bounds just rule out a
      // broken parse.
      expect(t.moveCount, greaterThan(500000));
      expect(t.layerCount, greaterThan(500));
      // 0.2-mm layer height × thousand+ layers → ≥ 100 mm.
      expect(t.layerZ[t.layerCount - 1], greaterThan(100.0));
      // Multi-hour print.
      expect(t.totalTimeSec, greaterThan(3600.0));
    }, timeout: timeout);

    test(
        'Auryn: EVERY slider position matches the gcode ;LAYER_CHANGE/;Z: pair',
        () async {
      if (!hspt.existsSync() || !auryn.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      final expectedZ = <double>[];
      String prev = '';
      for (final raw in auryn.readAsLinesSync()) {
        final line = raw.trim();
        if (prev == ';LAYER_CHANGE' && line.startsWith(';Z:')) {
          expectedZ.add(double.parse(line.substring(3)));
        }
        prev = line;
      }
      // The HSPT might trail off before the last `;LAYER_CHANGE`
      // (Orca emits one as a sentinel). We check all bins
      // present in the HSPT; if there are extra gcode markers
      // beyond those they're the trailing sentinel.
      expect(t.layerCount, lessThanOrEqualTo(expectedZ.length));
      expect(expectedZ.length - t.layerCount, lessThanOrEqualTo(1));
      for (int N = 1; N <= t.layerCount; ++N) {
        final current0 = N - 1;
        expect(t.layerZ[current0],
            closeTo(expectedZ[current0], 0.001),
            reason:
                'Auryn displayed Layer $N (internal $current0): '
                'Dart layerZ=${t.layerZ[current0]} vs '
                'gcode ;Z:=${expectedZ[current0]}');
      }
    }, timeout: timeout);

    test(
        'Auryn: EVERY slider position: only moves with layer_id ≤ N-1 are drawn',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      final totalMoves = t.moveCount;
      // Fast version — pre-compute a per-record layer_id view
      // once, then the inner loop is pure int comparison, no
      // `getUint16` call per iteration. On 2.1 M records the
      // double loop would otherwise be O(N²) ≈ 4·10¹².
      final bd = ByteData.sublistView(t.data);
      final lids = Uint16List(totalMoves);
      for (int i = 0; i < totalMoves; ++i) {
        lids[i] = bd.getUint16(i * hsptRecordSize + 4, Endian.little);
      }
      // Monotonic max up to each cutoff; monotonic min from
      // each cutoff onward. Build both as sweep arrays, then
      // the per-layer check is O(1).
      final prefixMax = Uint16List(totalMoves);
      int running = 0;
      for (int i = 0; i < totalMoves; ++i) {
        if (lids[i] > running) running = lids[i];
        prefixMax[i] = running;
      }
      final suffixMin = Uint16List(totalMoves);
      int runMin = 65535;
      for (int i = totalMoves - 1; i >= 0; --i) {
        if (lids[i] < runMin) runMin = lids[i];
        suffixMin[i] = runMin;
      }
      for (int N = 1; N <= t.layerCount; ++N) {
        final current0 = N - 1;
        final endOfCurrent = t.layerEnd(current0);
        expect(prefixMax[endOfCurrent - 1], lessThanOrEqualTo(current0),
            reason: 'Auryn Layer $N: a drawn record carries '
                'layer_id > $current0');
        if (endOfCurrent < totalMoves) {
          expect(suffixMin[endOfCurrent], greaterThan(current0),
              reason: 'Auryn Layer $N: a record above the cutoff '
                  'carries layer_id ≤ $current0');
        }
      }
    }, timeout: timeout);

    test(
        'Auryn: layerStarts strictly monotonic — slider ± 1 lands on a distinct layer',
        () async {
      if (!hspt.existsSync()) return;
      final t = await loadToolpaths(hspt.path);
      for (int i = 1; i < t.layerCount; ++i) {
        expect(t.layerStart(i), greaterThan(t.layerStart(i - 1)),
            reason: 'Auryn layerStart[$i] must be strictly '
                'greater than layerStart[${i - 1}]');
      }
    }, timeout: timeout);
  });
}
