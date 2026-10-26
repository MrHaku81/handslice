// Phase-4.4-Tests:
//   1. FilamentOverrides-Persistenz: pro Fach eigene Overrides-Map
//      (Fachwechsel haelt sie strikt getrennt, Save/Reload round-trip).
//   2. FilamentMapping: PETG/Rapid PETG/PLA PRO/Rapid PLA+ aus 2005
//      werden korrekt zugeordnet; unbekannte Materialien liefern einen
//      Fallback MIT fallbackReason-Text fuer die UI.

import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/settings/filament_mapping.dart';
import 'package:handslice/settings/filament_overrides.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FilamentOverrides', () {
    test('Fachwechsel haelt Overrides pro Fach getrennt', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final fo = FilamentOverrides(prefs);

      fo.forTray(0).set('hot_plate_temp_initial_layer', '88');
      fo.forTray(2).set('nozzle_temperature', '220');

      expect(fo.forTray(0).all,
          equals({'hot_plate_temp_initial_layer': '88'}));
      expect(fo.forTray(2).all,
          equals({'nozzle_temperature': '220'}));
      expect(fo.forTray(1).all, isEmpty);
      expect(fo.forTray(3).all, isEmpty);
      expect(fo.totalCount(), 2);
    });

    test('Persistenz: nach Reload sind Overrides pro Fach wieder da',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = FilamentOverrides(prefs);
      first.forTray(2).set('retraction_length', '2.4');
      first.forTray(2).set('nozzle_temperature', '260');

      // Simulated Neustart: neue Instanz auf denselben prefs.
      final second = FilamentOverrides(prefs);
      expect(second.forTray(2).all,
          equals({'retraction_length': '2.4', 'nozzle_temperature': '260'}));
      expect(second.forTray(0).all, isEmpty);
    });
  });

  group('FilamentMapping', () {
    const map = FilamentMapping();

    test('Haupt-Materialien → spezifische ECC2-Profile', () {
      final a1 = map.resolve(filamentName: 'ELEGOO PETG', filamentType: 'PETG');
      expect(a1.assetName, 'Elegoo PETG @ECC2.json');
      expect(a1.generic, isFalse);

      final a2 = map.resolve(
          filamentName: 'ELEGOO RAPID PETG', filamentType: 'PETG');
      expect(a2.assetName, 'Elegoo Rapid PETG @ECC2.json');
      expect(a2.generic, isFalse);

      final a3 = map.resolve(
          filamentName: 'ELEGOO PLA PRO', filamentType: 'PLA');
      expect(a3.assetName, 'Elegoo PLA PRO @ECC2.json');
      expect(a3.generic, isFalse);

      final a4 = map.resolve(
          filamentName: 'ELEGOO RAPID PLA+', filamentType: 'PLA');
      expect(a4.assetName, 'Elegoo Rapid PLA+ @ECC2.json');
      expect(a4.generic, isFalse);
    });

    test('Unbekanntes Material → Fallback mit sichtbarem Hinweis', () {
      final unknown = map.resolve(
          filamentName: 'Fremdherstellermaterial XY',
          filamentType: 'PLA');
      expect(unknown.generic, isFalse,  // PLA-Typ wird noch erkannt
          reason: 'PLA-Typ sollte Elegoo PLA @ECC2 ergeben, nicht Fallback');
      expect(unknown.assetName, 'Elegoo PLA @ECC2.json');

      final totallyUnknown = map.resolve(
          filamentName: 'MYSTERY', filamentType: 'TPU');
      expect(totallyUnknown.generic, isTrue);
      expect(totallyUnknown.fallbackReason, isNotNull);
      expect(totallyUnknown.fallbackReason, contains('MYSTERY'));
    });
  });
}
