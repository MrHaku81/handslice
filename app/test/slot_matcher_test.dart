// M9-Vorstufe: Tests fuer die Fach-Auto-Zuordnung aus color_map
// einer Druckdatei zu den aktuellen CANVAS-Slots.

import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/net/elegoo_cc2_client.dart';
import 'package:handslice/settings/slot_matcher.dart';

ColorMapEntry _cm(int t, String color, String type) =>
    ColorMapEntry(toolIndex: t, color: color, filamentType: type);

CanvasSlot _slot(int trayId, String color, String type) => CanvasSlot(
      trayId: trayId,
      filamentColor: color,
      filamentType: type,
      filamentName: '$type',
    );

void main() {
  group('slotOverridesFor', () {
    test('normalisiert Hex-Wert ohne Praefix', () {
      final o = slotOverridesFor(_slot(0, 'F2754E', 'PLA'));
      expect(o, equals({'filament_colour': '#F2754E'}));
    });
    test('reicht Praefix-Form durch', () {
      final o = slotOverridesFor(_slot(1, '#1EFFA3', 'PETG'));
      expect(o, equals({'filament_colour': '#1EFFA3'}));
    });
    test('leere Map bei ungueltiger Farbe', () {
      expect(slotOverridesFor(_slot(0, '', 'PLA')), isEmpty);
      expect(slotOverridesFor(_slot(0, '#xyz', 'PLA')), isEmpty);
      expect(slotOverridesFor(_slot(0, '#1234', 'PLA')), isEmpty);
    });
  });

  group('findSlotForFile', () {
    test('eindeutig: genau ein Slot mit Material + Farbe passt', () {
      final r = findSlotForFile(
        colorMap: [_cm(0, '#F2754E', 'PLA')],
        slots: [
          _slot(0, '#E6E6FA', 'PLA'),
          _slot(1, '#F2754E', 'PLA'),   // ← trifft
          _slot(2, '#F2754E', 'PETG'),  // falsches Material
          _slot(3, '#000000', 'PLA'),
        ],
      );
      expect(r.kind, SlotMatchKind.unique);
      expect(r.trayId, 1);
    });

    test('eindeutig mit kleiner Farb-Toleranz', () {
      // Datei #F2754E, Slot #F3754F – unter Toleranz = Treffer.
      final r = findSlotForFile(
        colorMap: [_cm(0, '#F2754E', 'PLA')],
        slots: [_slot(0, '#F3754F', 'PLA')],
      );
      expect(r.kind, SlotMatchKind.unique);
      expect(r.trayId, 0);
    });

    test('mehrdeutig: zwei Slots mit demselben Material und nahen Farben', () {
      final r = findSlotForFile(
        colorMap: [_cm(0, '#F2754E', 'PLA')],
        slots: [
          _slot(0, '#F2754E', 'PLA'),
          _slot(1, '#F3754F', 'PLA'),   // auch unter Toleranz
          _slot(2, '#000000', 'PETG'),
        ],
      );
      expect(r.kind, SlotMatchKind.ambiguous);
      expect(r.trayId, isNull);
    });

    test('kein Treffer: Material stimmt nicht', () {
      final r = findSlotForFile(
        colorMap: [_cm(0, '#F2754E', 'PLA')],
        slots: [_slot(0, '#F2754E', 'PETG')],
      );
      expect(r.kind, SlotMatchKind.none);
    });

    test('kein Treffer: Farbe weit weg', () {
      final r = findSlotForFile(
        colorMap: [_cm(0, '#F2754E', 'PLA')],
        slots: [_slot(0, '#E6E6FA', 'PLA')],
      );
      expect(r.kind, SlotMatchKind.none);
    });

    test('leere color_map → none', () {
      final r = findSlotForFile(
        colorMap: const [],
        slots: [_slot(0, '#F2754E', 'PLA')],
      );
      expect(r.kind, SlotMatchKind.none);
    });

    test('leere Slot-Liste → none', () {
      final r = findSlotForFile(
        colorMap: [_cm(0, '#F2754E', 'PLA')],
        slots: const [],
      );
      expect(r.kind, SlotMatchKind.none);
    });

    test('ungueltige Hex-Werte → none statt Crash', () {
      final r = findSlotForFile(
        colorMap: [_cm(0, 'not-a-color', 'PLA')],
        slots: [_slot(0, '#F2754E', 'PLA')],
      );
      expect(r.kind, SlotMatchKind.none);
    });

    test('Material-Vergleich ist case-insensitive + getrimmt', () {
      final r = findSlotForFile(
        colorMap: [_cm(0, '#F2754E', '  pla  ')],
        slots: [_slot(0, '#F2754E', 'PLA')],
      );
      expect(r.kind, SlotMatchKind.unique);
      expect(r.trayId, 0);
    });
  });
}
