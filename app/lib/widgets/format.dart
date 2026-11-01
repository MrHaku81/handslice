// Small formatting helpers shared by the Project and Print
// cards (and anywhere else that shows raw bytes / g-code
// metadata). Kept locale-aware so a German build uses "216,8
// KB" (comma decimal) and an English build uses "216.8 KB".

import 'package:intl/intl.dart';

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
