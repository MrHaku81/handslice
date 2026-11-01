// Small formatting helpers shared by the Project and Print
// cards (and anywhere else that shows raw bytes / g-code
// metadata). Kept locale-aware so a German build uses "216,8
// KB" (comma decimal) and an English build uses "216.8 KB".

import 'package:intl/intl.dart';

/// Format a seconds-count the way Orca's "Total time" line
/// does: `9m25s` / `7h11m` / `1d2h3m` / `35s`, no spaces.
///
/// Mirrors `short_time(get_time_dhms(seconds))` from
/// `OrcaSlicer/src/libslic3r/Utils.hpp:494-537`. Orca itself
/// uses this exact formatter for the "Total time" row in the
/// G-code preview, see `OrcaSlicer/src/slic3r/GUI/
/// GCodeViewer.cpp:4023`.
///
/// Rounding mirrors Orca: when hours or days are shown we drop
/// the seconds bucket and round the minutes up when seconds
/// ≥ 30 (Orca's `short_time` body does the same).
String formatDurationShort(double seconds) {
  if (!seconds.isFinite || seconds <= 0.5) return '—';
  final total = seconds.round();
  int days = total ~/ 86400;
  int rem = total % 86400;
  int hours = rem ~/ 3600;
  rem %= 3600;
  int minutes = rem ~/ 60;
  int secs = rem % 60;
  // Round the minutes up when secs ≥ 30 and we are past the
  // minute bucket (`Utils.hpp:513-521`).
  if ((days > 0 || hours > 0) && secs >= 30) {
    minutes++;
    if (minutes == 60) { minutes = 0; hours++;
      if (hours == 24) { hours = 0; days++; } }
  }
  if (days > 0)    return '${days}d${hours}h${minutes}m';
  if (hours > 0)   return '${hours}h${minutes}m';
  if (minutes > 0) return '${minutes}m${secs}s';
  return '${secs}s';
}

/// Convert a raw byte count into a human-readable string.
///
/// Uses SI prefixes (KB / MB / GB) with a base of 1000 — the
/// same scheme Klaus asked for ("216 KB" for a 216 834-byte
/// cube, "64,5 MB" for an auryn-sized file). We stop at GB
/// because the g-code we show is capped there by any
/// reasonable slicer.
///
/// `localeTag` is the Dart locale (e.g. `'de'`, `'en'`). Pass
/// `Localizations.localeOf(context).toLanguageTag()` from a
/// widget, or an explicit tag from a test.
String formatBytes(int bytes, String localeTag) {
  if (bytes < 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  if (unit == 0) {
    return '$bytes B';
  }
  // Show one decimal below 100, no decimals at 100+. Mirrors
  // the "216 KB" vs "64,5 MB" examples in the brief.
  final nf = NumberFormat(value < 100 ? '#,##0.0' : '#,##0', localeTag);
  return '${nf.format(value)} ${units[unit]}';
}
