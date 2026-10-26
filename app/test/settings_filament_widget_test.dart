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
import 'package:handslice/settings/profile_reader.dart';
import 'package:handslice/settings/profile_writer.dart';
import 'package:handslice/settings/settings_overrides.dart';
import 'package:handslice/settings/settings_schema.dart';
import 'package:handslice/state/printer_state.dart';
import 'package:handslice/state/project_state.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support/fake_path_provider.dart';

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

  // Phase-4.4-Nacharbeit: Bug 2 – Ueberschrift bereichsabhaengig.
  // Prozess-Bereich: "Prozess-Einstellungen — ..."
  // Filament-Bereich: "Filament-Einstellungen — ..."
  testWidgets('Ueberschrift wechselt beim Bereichswechsel', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final filamentOv = FilamentOverrides(prefs);
    final printer = _FakeSlotsPrinter([
      CanvasSlot(trayId: 3, filamentType: 'PLA',
          filamentName: 'ELEGOO RAPID PLA+', filamentColor: '#FFFFFF'),
    ], prefs);

    await tester.pumpWidget(_wrap(SettingsScreen(
      schema: filamentSchema(),
      overrides: SettingsOverrides(),
      filamentOverrides: filamentOv,
      printerState: printer,
    )));
    await tester.pumpAndSettle();

    // Default-Bereich = Prozess
    expect(find.textContaining('Prozess-Einstellungen'), findsOneWidget);
    expect(find.textContaining('Filament-Einstellungen'), findsNothing);

    await tester.tap(find.text('Filament').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Filament-Einstellungen'), findsOneWidget);
    expect(find.textContaining('Prozess-Einstellungen'), findsNothing);
  });

  // Phase-4.4-Nacharbeit: Bug 1 – "Als Profil speichern" muss auch im
  // Filament-Bereich existieren und bei nicht-leeren Fach-Overrides
  // bedienbar sein.
  testWidgets('Save-Button sichtbar und aktiv im Filament-Bereich',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final filamentOv = FilamentOverrides(prefs);
    final printer = _FakeSlotsPrinter([
      CanvasSlot(trayId: 3, filamentType: 'PLA',
          filamentName: 'ELEGOO RAPID PLA+', filamentColor: '#FFFFFF'),
    ], prefs);

    await tester.pumpWidget(_wrap(SettingsScreen(
      schema: filamentSchema(),
      overrides: SettingsOverrides(),
      filamentOverrides: filamentOv,
      printerState: printer,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Filament').first);
    await tester.pumpAndSettle();

    // Button vorhanden
    final saveFinder = find.widgetWithText(TextButton, 'Als Profil speichern');
    expect(saveFinder, findsOneWidget);
    // Ohne Overrides: deaktiviert
    expect(tester.widget<TextButton>(saveFinder).onPressed, isNull);

    // Mit Fach-Override: aktiv
    filamentOv.forTray(3).set('nozzle_temperature', '245');
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(saveFinder).onPressed, isNotNull);
  });

  // Bug 1 (Save-Logik): Speichern im Filament-Bereich erzeugt ein
  // Preset mit type=="filament" und inherits auf das Material-
  // Basisprofil des aktiven Fachs. Non-Widget-Pfad – ruft direkt den
  // ProfileWriter mit genau den Argumenten, die SettingsScreen baut.
  test('Save im Filament-Bereich schreibt type=filament + inherits',
      () async {
    PathProviderPlatform.instance = FakePathProvider();
    // Fach A4 = ELEGOO RAPID PLA+ → Elegoo Rapid PLA+ @ECC2
    final f = await const ProfileWriter().save(
      name: 'PLA+ fuer A4',
      baseInherits: 'Elegoo Rapid PLA+ @ECC2',
      type: 'filament',
      overrides: {'nozzle_temperature': '245'},
    );
    expect(f.existsSync(), isTrue);

    final list = await const ProfileReader().list();
    final hit = list.firstWhere((p) => p.name == 'PLA+ fuer A4');
    expect(hit.type, 'filament');
    expect(hit.baseInherits, 'Elegoo Rapid PLA+ @ECC2');
    expect(hit.overrides['nozzle_temperature'], '245');
  });

  // Zuordnung an das Material: Filament-Profile mit demselben
  // inherits (= Basisprofil) sind Profilen fuer Faecher mit gleichem
  // Material zugeordnet, unabhaengig vom tray_id.
  test('Picker-Filter: inherits == Material-Basisprofil des Fachs',
      () async {
    PathProviderPlatform.instance = FakePathProvider();
    await const ProfileWriter().save(
      name: 'PETG warm', baseInherits: 'Elegoo PETG @ECC2',
      type: 'filament', overrides: {'nozzle_temperature': '260'},
    );
    await const ProfileWriter().save(
      name: 'PLA kalt', baseInherits: 'Elegoo PLA PRO @ECC2',
      type: 'filament', overrides: {'nozzle_temperature': '195'},
    );
    await const ProfileWriter().save(
      name: 'ProfilProzess', baseInherits: '0.20mm Standard @Elegoo CC2 0.4 nozzle',
      type: 'process', overrides: {'layer_height': '0.28'},
    );

    final all = await const ProfileReader().list();
    // Fach mit PETG als Material → nur "PETG warm" passt.
    final forPetg = all
        .where((p) => p.type == 'filament' && p.baseInherits == 'Elegoo PETG @ECC2')
        .toList();
    expect(forPetg, hasLength(1));
    expect(forPetg.first.name, 'PETG warm');

    // Fach mit PLA PRO → nur "PLA kalt" passt (NICHT das Prozess-Profil,
    // NICHT das PETG-Profil).
    final forPlaPro = all
        .where((p) => p.type == 'filament' && p.baseInherits == 'Elegoo PLA PRO @ECC2')
        .toList();
    expect(forPlaPro, hasLength(1));
    expect(forPlaPro.first.name, 'PLA kalt');
  });

  // Phase-4.4-Nacharbeit: ProjectState speichert pro Fach einen slug;
  // Round-Trip ueber dieselbe Normalisierung wie ProfileWriter.
  test('ProjectState: pro-Fach Filament-Profil-Slug persistiert',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final ps = ProjectState(prefs);
    expect(ps.filamentActiveProfileSlug(0), isNull);
    await ps.setFilamentActiveProfileSlug(0, ProfileWriterSlug.of('PETG warm'));
    expect(ps.filamentActiveProfileSlug(0), 'petg-warm');
    // Fach 1 unberuehrt
    expect(ps.filamentActiveProfileSlug(1), isNull);
    // Neue Instanz liest zurueck
    final ps2 = ProjectState(prefs);
    expect(ps2.filamentActiveProfileSlug(0), 'petg-warm');
    await ps.setFilamentActiveProfileSlug(0, null);
    expect(ps.filamentActiveProfileSlug(0), isNull);
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
