// Pflicht 7c — toolpath (HSPT) parser tests.
//
// Two groups:
//   - A hand-rolled HSPT buffer that pins the field layout and
//     the role / move-type byte codes.
//   - A sanity run against a freshly produced HSPT from
//     `handslice-cli --input-gcode --export-toolpaths` on the
//     notched cube (local-only; the artefact is not in the repo).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/engine/toolpath_parser.dart';

Uint8List _hspt({
  required List<Map<String, dynamic>> moves,
}) {
  final bytes = BytesBuilder();
  // Header
  bytes.add(const [0x48, 0x53, 0x50, 0x54]);
  final hdr = ByteData(12)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 0, Endian.little)
    ..setUint32(8, moves.length, Endian.little);
  bytes.add(hdr.buffer.asUint8List());
  for (final m in moves) {
    final b = ByteData(28);
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
    bytes.add(b.buffer.asUint8List());
  }
  return bytes.toBytes();
}

void main() {
  group('parseToolpathsInline', () {
    test('rejects bad magic', () {
      final b = Uint8List(28);
      expect(() => parseToolpathsInline(b),
          throwsA(isA<FormatException>()));
    });

    test('three-move scenario: travel, outer wall, inner wall', () {
      final bytes = _hspt(moves: [
        {
          'role': GcodeRole.none.index,  'extruder': 0,
          'moveType': MoveType.noop.index,
          'layer': 0, 'width100': 0, 'height100': 0, 'feedrate': 0,
          'x': 0, 'y': 0, 'z': 0, 'e': 0,
        },
        {
          // Travel to the start of the outer wall.
          'role': GcodeRole.none.index,  'extruder': 0,
          'moveType': MoveType.travel.index,
          'layer': 0, 'width100': 0, 'height100': 0, 'feedrate': 180,
          'x': 10, 'y': 10, 'z': 0.2, 'e': 0,
        },
        {
          // Outer wall segment.
          'role': GcodeRole.externalPerimeter.index, 'extruder': 0,
          'moveType': MoveType.extrude.index,
          'layer': 0, 'width100': 42, 'height100': 20, 'feedrate': 60,
          'x': 20, 'y': 10, 'z': 0.2, 'e': 0.42,
        },
        {
          // Inner wall segment.
          'role': GcodeRole.perimeter.index, 'extruder': 0,
          'moveType': MoveType.extrude.index,
          'layer': 0, 'width100': 42, 'height100': 20, 'feedrate': 60,
          'x': 20, 'y': 20, 'z': 0.2, 'e': 0.42,
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
      final move2 = Move(t.bd, 2 * 28);
      expect(move2.role, GcodeRole.externalPerimeter);
      expect(move2.width, closeTo(0.42, 1e-5));
    });
  });

  group('on real HSPT (local only)', () {
    final hspt = File('local-test/cube.hspt');
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
  });
}
