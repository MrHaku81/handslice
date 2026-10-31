// M9-Vorstufe: automatische Fach-Vorauswahl im Start-Dialog.
//
// Vergleicht die `color_map` einer Druckdatei (ein Eintrag pro
// Filament-Index) mit der aktuellen CANVAS-Slot-Liste. Match-
// Kriterium: Material-Typ identisch (case-insensitive, Leerzeichen
// getrimmt) UND Farbe mit RGB-Toleranz (quadratische
// Komponenten-Summe <= Schwelle).
//
// Rueckgabe ist ein `SlotMatchResult`:
//   - `trayId != null`: genau EIN Slot passt → Vorauswahl.
//   - `trayId == null, kind == ambiguous`: mehrere Slots passen,
//     Nutzer muss selbst entscheiden.
//   - `trayId == null, kind == none`: kein Slot passt – letzte
//     Wahl beibehalten, Hinweis zeigen.

import '../net/elegoo_cc2_client.dart';

enum SlotMatchKind { unique, ambiguous, none }

class SlotMatchResult {
  const SlotMatchResult(this.kind, [this.trayId]);
  final SlotMatchKind kind;
  final int? trayId;
}

/// Standard-Toleranz: `30` in jeder RGB-Komponente, als euklidische
/// Summe `~ 52` – deckt typische Spool-zu-Spool-Hex-Jitter
/// (z. B. `#F2754E` vs. `#F3754F`) und JSON-Rounding ab, verhindert
/// aber Verwechslung zwischen klar unterschiedlichen Farben
/// (`#F2754E` vs. `#E6E6FA`).
const int kDefaultColorToleranceSquared = 52 * 52;

/// Nimmt die erste `color_map`-Eintrag einer Datei (fuer die
/// Vorstufe reicht ein Filament pro Druck) und findet dazu Slots.
SlotMatchResult findSlotForFile({
  required List<ColorMapEntry> colorMap,
  required List<CanvasSlot> slots,
  int toleranceSquared = kDefaultColorToleranceSquared,
}) {
  if (colorMap.isEmpty) return const SlotMatchResult(SlotMatchKind.none);
  // M9 ist Single-Filament; wir nehmen den ersten Map-Eintrag. Fuer
  // Multi-Material (Pflicht 8) wird eine echte N→N-Zuordnung noetig.
  final e = colorMap.first;
  final needType = e.filamentType.trim().toLowerCase();
  final needRgb  = _parseHex(e.color);
  if (needRgb == null) return const SlotMatchResult(SlotMatchKind.none);

  final matches = <int>[];
  for (final s in slots) {
    final slotType = s.filamentType.trim().toLowerCase();
    if (slotType != needType) continue;
    final slotRgb = _parseHex(s.filamentColor);
    if (slotRgb == null) continue;
    final dr = needRgb[0] - slotRgb[0];
    final dg = needRgb[1] - slotRgb[1];
    final db = needRgb[2] - slotRgb[2];
    final d2 = dr * dr + dg * dg + db * db;
    if (d2 <= toleranceSquared) matches.add(s.trayId);
  }
  if (matches.isEmpty) return const SlotMatchResult(SlotMatchKind.none);
  if (matches.length == 1) {
    return SlotMatchResult(SlotMatchKind.unique, matches.first);
  }
  return const SlotMatchResult(SlotMatchKind.ambiguous);
}

/// Baut die Slice-Overrides fuer ein gewaehltes Fach. Aktuell nur
/// die Farbe (`filament_colour`); das Material wird ueber den
/// Filamentprofil-Pfad gewaehlt (`filament_mapping.dart`), nicht
/// als Override. Rueckgabe leer, wenn der Slot keine saubere Farbe
/// hat.
Map<String, String> slotOverridesFor(CanvasSlot slot) {
  final col = slot.filamentColor.trim();
  if (!RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(col)) return const {};
  return {
    'filament_colour': col.startsWith('#') ? col : '#$col',
  };
}

List<int>? _parseHex(String hex) {
  final s = hex.replaceAll('#', '').trim();
  if (s.length != 6) return null;
  try {
    final r = int.parse(s.substring(0, 2), radix: 16);
    final g = int.parse(s.substring(2, 4), radix: 16);
    final b = int.parse(s.substring(4, 6), radix: 16);
    return [r, g, b];
  } catch (_) {
    return null;
  }
}
