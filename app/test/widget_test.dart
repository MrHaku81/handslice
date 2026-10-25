// Smoke-Tests fuer M1 + M2. Kein Device, kein Platform-Channel,
// kein echter Slicer-Prozess: wir verifizieren nur, dass die Screens
// aus ProjectState bauen und auf Zustandsaenderungen reagieren.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:handslice/engine/slicer.dart';
import 'package:handslice/l10n/app_localizations.dart';
import 'package:handslice/screens/print_screen.dart';
import 'package:handslice/screens/project_screen.dart';
import 'package:handslice/screens/settings_screen.dart';
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
      ProjectScreen(slicer: _FakeSlicer(), projectState: state),
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
      ProjectScreen(slicer: _FakeSlicer(), projectState: state),
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
      PrintScreen(projectState: state),
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
}
