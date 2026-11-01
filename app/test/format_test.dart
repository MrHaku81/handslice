// Formatting-helper tests. Covers the three cases Klaus named
// in the follow-up brief: "216 KB" for a cube-sized file,
// "64,5 MB" for an Auryn-sized one, and raw bytes for small
// counts. Also pins the German decimal-comma vs English
// decimal-dot behaviour so a locale regression surfaces here.

import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/widgets/format.dart';

void main() {
  group('formatBytes', () {
    test('small count → raw bytes', () {
      expect(formatBytes(0, 'en'), '0 B');
      expect(formatBytes(999, 'en'), '999 B');
      // boundary — 1000 bytes flips to KB.
      expect(formatBytes(1000, 'en'), '1.0 KB');
      expect(formatBytes(1000, 'de'), '1,0 KB');
    });

    test('cube-sized gcode → "216 KB" (English) / "216 KB" (German)',
        () {
      // local-test/thumbnail-cube.gcode weighs 216 834 B.
      // 216 834 / 1000 = 216.834, formats as "217 KB" at >=100
      // (no decimals).
      expect(formatBytes(216834, 'en'), '217 KB');
      expect(formatBytes(216834, 'de'), '217 KB');
    });

    test('MB range with German decimal comma', () {
      // 64.5 MB = 64_500_000 bytes (SI).
      expect(formatBytes(64500000, 'de'), '64,5 MB');
      expect(formatBytes(64500000, 'en'), '64.5 MB');
    });

    test('Auryn-sized gcode → "67,6 MB" (German)', () {
      // local-test/auryn-x86.gcode weighs 67 570 564 B.
      expect(formatBytes(67570564, 'de'), '67,6 MB');
      expect(formatBytes(67570564, 'en'), '67.6 MB');
    });

    test('GB range', () {
      expect(formatBytes(1_500_000_000, 'en'), '1.5 GB');
      expect(formatBytes(1_500_000_000, 'de'), '1,5 GB');
    });

    test('negative or garbage → "0 B"', () {
      expect(formatBytes(-1, 'en'), '0 B');
    });
  });

  group('formatDurationShort', () {
    // Mirrors Orca's `short_time(get_time_dhms(seconds))` at
    // `OrcaSlicer/src/libslic3r/Utils.hpp:494-537`. The
    // "Total time" row in the g-code preview uses this
    // formatter (`GCodeViewer.cpp:4023`), so both the layer-
    // view legend and the project / print card now render
    // the same string.
    test('seconds-only range', () {
      expect(formatDurationShort(0), '—');
      expect(formatDurationShort(1), '1s');
      expect(formatDurationShort(35), '35s');
      expect(formatDurationShort(59), '59s');
    });
    test('minutes bucket (no space, no rounding)', () {
      expect(formatDurationShort(60), '1m0s');
      expect(formatDurationShort(565), '9m25s'); // the cube
      expect(formatDurationShort(3599), '59m59s');
    });
    test('hours bucket drops seconds, rounds minutes', () {
      // 1h 0m 0s
      expect(formatDurationShort(3600), '1h0m');
      // 1h 11m 29s — seconds < 30 → no round.
      expect(formatDurationShort(1 * 3600 + 11 * 60 + 29),
          '1h11m');
      // 1h 11m 30s — round the minute up (Utils.hpp:513-521).
      expect(formatDurationShort(1 * 3600 + 11 * 60 + 30),
          '1h12m');
      // The Auryn example: 7h 11m 23s.
      expect(formatDurationShort(25883), '7h11m');
    });
    test('days bucket', () {
      // 1d 2h 3m 29s
      expect(formatDurationShort(86400 + 7200 + 180 + 29),
          '1d2h3m');
    });
  });
}
