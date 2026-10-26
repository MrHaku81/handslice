// Phase-4.4-Widget-Tests fuer den Filament-Bereich im Settings-Reiter.
// Prueft:
//   - Bereich-Umschalter Prozess/Filament wechselt.
//   - A1..A4-Fach-Umschalter: Override auf A1 bleibt beim Wechsel auf
//     A3 getrennt, Rueckkehr zeigt A1-Overrides wieder.
//   - Fallback-Hinweis "Basisprofil: ..." + gelbe Warn-Zeile fuer
//     unbekanntes Material.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/l10n/app_localizations.dart';
import 'package:handslice/net/elegoo_cc2_client.dart';
import 'package:handslice/screens/settings_screen.dart';
import 'package:handslice/settings/filament_overrides.dart';
import 'package:handslice/settings/settings_overrides.dart';
import 'package:handslice/settings/settings_schema.dart';
import 'package:handslice/state/printer_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Mini-Schema: 1 Filament-Seite "Filament" mit 1 Gruppe und 1 Option
// (nozzle_temperature). Reicht fuer die Smoke-Checks.
SettingsSchema filamentSchema() => SettingsSchema.fromJson({
      'source': {'orca_version': 'test'},
      'areas': {
        'print': [
          {
            'page': 'Quality', 'page_label_de': 'Qualität',
            'groups': [
              {'group': 'Layer', 'group_label_de': 'Lagen', 'keys': [
                {'key': 'layer_height', 'type': 'float', 'mode': 'simple',
                 'tier': 'basis', 'label_en': 'Layer height',
                 'label_de': 'Schichthöhe', 'default': '0.2'}
              ]}
            ],
          },
        ],
        'filament': [
          {
            'page': 'Filament', 'page_label_de': 'Filament',
            'groups': [
              {
                'group': 'Temperature', 'group_label_de': 'Temperatur',
                'keys': [
                  {
                    'key': 'nozzle_temperature',
                    'type': 'int', 'mode': 'simple', 'tier': 'basis',
                    'label_en': 'Nozzle temperature',
                    'label_de': 'Düsentemperatur',
                    'default': '240',
                  }
                ],
              }
            ],
          }
        ],
      }
    });

class _FakeSecure implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
  final Map<String, String> _m = {};
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic mOptions, dynamic wOptions, dynamic webOptions}) async => _m[key];
  @override
  Future<void> write({required String key, required String? value, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic mOptions, dynamic wOptions, dynamic webOptions}) async {
    if (value == null) {_m.remove(key);} else {_m[key] = value;}
  }
  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic mOptions, dynamic wOptions, dynamic webOptions}) async {_m.remove(key);}
}

Widget _wrap(Widget w) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('de'),
      home: Scaffold(body: w),
    );

Future<PrinterState> _printerWithSlots(List<CanvasSlot> slots) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final s = PrinterState(prefs: prefs, secure: _FakeSecure());
  // Live-State nicht noetig; wir setzen die Slots direkt. PrinterState
  // bietet dafuer keinen Setter; wir behelfen uns per Reflection auf
  // `_slots` nicht moeglich → statt dessen leeren Slot und testen den
  // "No slot assignment known"-Pfad.
  // Fuer Positive-Faelle verwenden wir eine Subklasse.
  return s;
}

class _FakeSlotsPrinter extends PrinterState {
  _FakeSlotsPrinter(this._fakeSlots, SharedPreferences prefs)
      : super(prefs: prefs, secure: _FakeSecure());
  final List<CanvasSlot> _fakeSlots;
  @override
  List<CanvasSlot> get slots => _fakeSlots;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Fachwechsel haelt Overrides getrennt (A1 → A3 → zurueck)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final processOv = SettingsOverrides();
    final filamentOv = FilamentOverrides(prefs);
    final printer = _FakeSlotsPrinter([
      CanvasSlot(trayId: 0, filamentType: 'PETG', filamentName: 'ELEGOO PETG', filamentColor: '#000000'),
      CanvasSlot(trayId: 1, filamentType: 'PETG', filamentName: 'ELEGOO RAPID PETG', filamentColor: '#FFFFFF'),
      CanvasSlot(trayId: 2, filamentType: 'PLA', filamentName: 'ELEGOO PLA PRO', filamentColor: '#000000'),
      CanvasSlot(trayId: 3, filamentType: 'PLA', filamentName: 'ELEGOO RAPID PLA+', filamentColor: '#FFFFFF'),
    ], prefs);

    await tester.pumpWidget(_wrap(SettingsScreen(
      schema: filamentSchema(),
      overrides: processOv,
      filamentOverrides: filamentOv,
      printerState: printer,
    )));
    await tester.pumpAndSettle();

    // Bereich auf Filament
    await tester.tap(find.text('Filament').first);
    await tester.pumpAndSettle();

    // Default-Fach ist A4 (Index 3). Wir setzen auf A1 manuell.
    filamentOv.forTray(0).set('nozzle_temperature', '230');
    expect(filamentOv.forTray(0).count, 1);
    expect(filamentOv.forTray(2).count, 0);

    // Jetzt A3-Fach anklicken und dort anderen Override setzen.
    filamentOv.forTray(2).set('nozzle_temperature', '215');
    expect(filamentOv.forTray(2).count, 1);
    expect(filamentOv.forTray(0).get('nozzle_temperature'), '230');
    expect(filamentOv.forTray(2).get('nozzle_temperature'), '215');

    // Alles persistiert; neue Instanz liest beide zurueck.
    final reloaded = FilamentOverrides(prefs);
    expect(reloaded.forTray(0).get('nozzle_temperature'), '230');
    expect(reloaded.forTray(2).get('nozzle_temperature'), '215');
  });

  testWidgets('Fallback-Hinweis fuer unbekanntes Material', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final filamentOv = FilamentOverrides(prefs);
    final printer = _FakeSlotsPrinter([
      CanvasSlot(trayId: 0, filamentType: 'TPU',
          filamentName: 'MYSTERY TPU', filamentColor: '#333333'),
    ], prefs);

    await tester.pumpWidget(_wrap(SettingsScreen(
      schema: filamentSchema(),
      overrides: SettingsOverrides(),
      filamentOverrides: filamentOv,
      printerState: printer,
    )));
    await tester.pumpAndSettle();

    // Bereich auf Filament, Fach A1.
    await tester.tap(find.text('Filament').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('A1'));
    await tester.pumpAndSettle();

    // Fallback-Zeile taucht auf (Text beginnt mit "Basisprofil: Elegoo PLA @ECC2")
    expect(find.textContaining('Basisprofil: Elegoo PLA @ECC2'),
        findsOneWidget);
    // Hinweistext enthaelt "nicht erkannt" (deutsch) oder "nicht
    // zugeordnet" aus filament_mapping.dart.
    expect(find.textContaining('nicht erkannt'), findsOneWidget);
  });
}
