// Pflicht 7a — unit tests for the preview-mesh pipeline:
//   - HSPM parser roundtrip + rejection of bad magic / version.
//   - previewTargetForTotalRam thresholds.
//
// No flutter_scene here (we don't want to pull Flutter GPU into
// unit tests); just the parser and the RAM-budget mapping.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/engine/slicer.dart';
import 'package:handslice/widgets/plate_view.dart';

void main() {
  group('previewTargetForTotalRam', () {
    const gb = 1024 * 1024 * 1024;

    test('>= 8 GB maps to 500k', () {
      expect(previewTargetForTotalRam(8 * gb), 500000);
      expect(previewTargetForTotalRam(12 * gb), 500000);
    });

    test('4-8 GB maps to 300k', () {
      expect(previewTargetForTotalRam(4 * gb), 300000);
      expect(previewTargetForTotalRam(6 * gb), 300000);   // Poco X3 Pro
      expect(previewTargetForTotalRam(8 * gb - 1), 300000);
    });

    test('< 4 GB maps to 100k', () {
      expect(previewTargetForTotalRam(0), 100000);
      expect(previewTargetForTotalRam(3 * gb), 100000);
    });
  });

  group('parseHspm', () {
    test('rejects bad magic', () {
      final b = ByteData(16);
      b.setUint8(0, 0x00);
      expect(() => parseHspm(b), throwsA(isA<FormatException>()));
    });

    test('rejects unknown version', () {
      final b = ByteData(16);
      b.setUint8(0, 0x48); b.setUint8(1, 0x53);
      b.setUint8(2, 0x50); b.setUint8(3, 0x4D);
      b.setUint32(4, 999, Endian.little);
      expect(() => parseHspm(b), throwsA(isA<FormatException>()));
    });

    test('parses a tiny 1-object / 1-volume / 1-triangle mesh', () {
      // 1 tri × (3 verts × (3 pos + 3 nrm) × 4 B) = 72 B.
      // header + obj + vol = 4 + 4 + 4 + 4 + 8 + 72 = 96 B.
      final bytes = Uint8List(96);
      final b = ByteData.sublistView(bytes);
      // magic + version
      b.setUint8(0, 0x48); b.setUint8(1, 0x53);
      b.setUint8(2, 0x50); b.setUint8(3, 0x4D);
      b.setUint32(4, 1, Endian.little);
      int off = 8;
      b.setUint32(off, 1, Endian.little); off += 4;   // n_objects
      b.setUint32(off, 1, Endian.little); off += 4;   // n_volumes
      b.setUint32(off, 7, Endian.little); off += 4;   // filament_idx
      b.setUint32(off, 1, Endian.little); off += 4;   // n_tris
      // triangle vertices (positions + normal)
      final pos = [[0.0,0.0,0.0], [1.0,0.0,0.0], [0.0,1.0,0.0]];
      for (final p in pos) {
        for (final c in p) {
          b.setFloat32(off, c, Endian.little); off += 4;
        }
        // Normal (0,0,1).
        b.setFloat32(off, 0, Endian.little); off += 4;
        b.setFloat32(off + 0, 0, Endian.little); off += 4;
        b.setFloat32(off, 1, Endian.little); off += 4;
      }
      final file = parseHspm(b);
      expect(file.volumes.length, 1);
      final v = file.volumes.first;
      expect(v.filamentIdx, 7);
      expect(v.triangleCount, 1);
      expect(v.positions.length, 9);
      expect(v.normals.length, 9);
      expect(v.positions[0], 0.0);
      expect(v.positions[3], 1.0);
      expect(v.positions[7], 1.0);  // second vertex Y
      expect(v.normals[2], 1.0);    // first vertex normal Z
    });
  });
}
