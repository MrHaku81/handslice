// Smoke-Tests fuer M1 + M2. Kein Device, kein Platform-Channel,
// kein echter Slicer-Prozess: wir verifizieren nur, dass die Screens
// aus ProjectState bauen und auf Zustandsaenderungen reagieren.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:handslice/engine/bounds_check.dart';
import 'package:handslice/engine/slicer.dart';
import 'package:handslice/l10n/app_localizations.dart';
import 'package:handslice/net/elegoo_cc2_client.dart';
import 'package:handslice/screens/print_screen.dart';
import 'package:handslice/screens/project_screen.dart';
import 'package:handslice/screens/settings_screen.dart';
import 'package:handslice/state/printer_state.dart';
import 'package:handslice/state/project_state.dart';
import 'package:handslice/theme/workshop_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: buildWorkshopTheme(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Material(child: w),
    );

Future<ProjectState> _makeState() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProjectState(prefs);
}

// In-Memory FlutterSecureStorage-Fake fuer Widget-Tests – ohne Platform-
// Channel, ohne Persistenz.
class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic mOptions, dynamic wOptions, dynamic webOptions}) async => _store[key];
  @override
  Future<void> write({required String key, required String? value, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic mOptions, dynamic wOptions, dynamic webOptions}) async {
    if (value == null) { _store.remove(key); } else { _store[key] = value; }
  }
  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic mOptions, dynamic wOptions, dynamic webOptions}) async { _store.remove(key); }
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<PrinterState> _makePrinter({ElegooCc2Client? client}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return PrinterState(
    prefs: prefs,
    secure: _FakeSecureStorage(),
    client: client,
  );
}

// Fake Slicer: antwortet synthetisch – kein Process.run, kein Binary.
class _FakeSlicer extends SlicerService {
  _FakeSlicer();

  @override
  bool get isReady => true;

  @override
  Future<SliceResult> slice({
    required String modelPath,
    required BedType bedType,
    required String outputPath,
    bool noCenter = true,
  }) async {
    return SliceResult(
      gcodePath: outputPath,
      sizeBytes: 220261,
      layerCount: 100,
      estimatedSeconds: 565,
      estimatedTimeFmt: '9m 25s',
      filamentUsedMm: 1172.33,
      filamentWeightG: 3.52,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Verhindert, dass file_picker beim Smoke-Test echte Plugin-Channels aufruft.
  FilePicker.skipEntitlementsChecks();

  // flutter_test rendert in Default-Lokale (en). Deshalb matchen wir
  // auf die Englisch-Strings aus lib/l10n/app_en.arb.

  testWidgets('ProjectScreen: "No model loaded" bis setModel()',
      (tester) async {
    final state = await _makeState();
    await tester.pumpWidget(_wrap(
      ProjectScreen(
        slicer: _FakeSlicer(),
        projectState: state,
        printerState: await _makePrinter(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No model loaded'), findsOneWidget);

    state.setModel('/some/path/kerbe.stl');
    await tester.pumpAndSettle();

    expect(find.text('kerbe.stl'), findsOneWidget);
    expect(find.text('No model loaded'), findsNothing);
  });

  testWidgets('ProjectScreen: Plate-Toggle wechselt bedType im State',
      (tester) async {
    final state = await _makeState();
    expect(state.bedType, BedType.texturedA);

    await tester.pumpWidget(_wrap(
      ProjectScreen(
        slicer: _FakeSlicer(),
        projectState: state,
        printerState: await _makePrinter(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('B — Smooth'));
    await tester.pumpAndSettle();

    expect(state.bedType, BedType.smoothB);
  });

  testWidgets('PrintScreen zeigt Slice-Ergebnis nach slice()', (tester) async {
    final state = await _makeState();
    state.setModel('/x/kerbe.stl');

    await tester.pumpWidget(_wrap(
      PrintScreen(
        projectState: state,
        printerState: await _makePrinter(),
      ),
    ));
    await tester.pumpAndSettle();

    // Ohne Slice: Hinweis-Text sichtbar.
    expect(find.textContaining('slice a project first'), findsOneWidget);

    await state.slice(_FakeSlicer(), '/tmp/x.gcode');
    await tester.pumpAndSettle();

    expect(find.text('9m 25s'), findsOneWidget);
    expect(find.text('x.gcode'), findsOneWidget);
    expect(find.textContaining('1172 mm'), findsOneWidget);
  });

  testWidgets('SettingsScreen bleibt Platzhalter', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('settings tree'), findsOneWidget);
  });

  test('ProjectState persistiert z-offset pro Plattenseite', () async {
    final s = await _makeState();
    await s.setZOffsetFor(BedType.texturedA, -0.040);
    await s.setZOffsetFor(BedType.smoothB, 0.020);
    expect(s.zOffsetFor(BedType.texturedA), -0.040);
    expect(s.zOffsetFor(BedType.smoothB), 0.020);
  });

  test('BedType -> CLI-Argument-Mapping', () {
    expect(BedType.texturedA.cliArg, 'A');
    expect(BedType.smoothB.cliArg, 'B');
  });

  test('Z-Offset: Nudge beachtet Grenzen + 0.01-mm-Raster', () async {
    final s = await _makeState();
    await s.setZOffsetFor(BedType.texturedA, 0.0);
    expect(s.zOffsetFor(BedType.texturedA), 0.0);
    for (var i = 0; i < 10; i++) {
      await s.nudgeZOffset(BedType.texturedA, 0.01);
    }
    // zehnmal +0.01 → 0.10 (float-stabil durch Quantisierung)
    expect(s.zOffsetFor(BedType.texturedA), 0.10);
    // Grenze +0.50
    for (var i = 0; i < 60; i++) {
      await s.nudgeZOffset(BedType.texturedA, 0.01);
    }
    expect(s.zOffsetFor(BedType.texturedA), ProjectState.zOffsetMax);
    // Grenze -0.50
    for (var i = 0; i < 1000; i++) {
      await s.nudgeZOffset(BedType.texturedA, -0.01);
    }
    expect(s.zOffsetFor(BedType.texturedA), ProjectState.zOffsetMin);
  });

  test('Bounds-Check: CC2-Profil parsen (printable_area + bed_texture_area)',
      () {
    final prof = <String, dynamic>{
      'printable_area': ['0x0', '256x0', '256x256', '0x256'],
      'bed_texture_area': ['0x-10', '256x-10', '256x256', '0x256'],
      'printable_height': '256',
    };
    final b = boundsFromProfile(prof);
    expect(b.xMin, 0.0);
    expect(b.xMax, 256.0);
    expect(b.yMin, -10.0); // bed_texture_area erweitert
    expect(b.yMax, 256.0);
    expect(b.zMax, 256.0);
  });

  test('Bounds-Check: in-bound + out-of-bound Bewegungen', () {
    final b = BoundsRect(xMin: 0, xMax: 256, yMin: -10, yMax: 256, zMax: 256);
    final lines = <String>[
      'G90',
      'G28',
      'G1 X128 Y128 Z0.3',
      'G1 X300 Y128 Z0.3',  // OOB X
      'G1 X128 Y270 Z0.3',  // OOB Y
      'G1 X128 Y128 Z260',  // OOB Z
      'G91',
      'G1 X-200 Y0 Z0',     // relativ: 128-200=-72 → OOB X
    ];
    final v = checkGcodeLines(lines, b);
    // Erwartet 5 Verletzungen:
    //   - X=300 (XY)
    //   - Y=270 (XY)
    //   - Z=260 (Z)
    //   - X=-72 nach relativem Move (XY)
    //   - Z bleibt bei 260 nach dem relativen Move (Z=260+0) → noch
    //     einmal eine Z-Verletzung
    expect(v.length, 5);
    expect(v[0].axis, 'XY');
    expect(v[0].x, 300);
    final relXy = v.firstWhere((x) => x.x == -72);
    expect(relXy.axis, 'XY');
  });
}
