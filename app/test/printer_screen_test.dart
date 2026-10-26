// Widget-Tests fuer Phase 5a/b (Reiter „Drucker").
//
// Rein lokal; kein Mock-Prozess. Faelle:
//   * Nicht verbunden → Hinweis-Panel.
//   * Verbunden + leere Historie → „keine Drucke".
// Die 1036-/Download-Pfade werden in test/elegoo_mock_test.dart
// Phase5-Tests gegen den echten Python-Mock gefahren; hier geht es
// nur um den Reiter-Shell + L10n.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:handslice/l10n/app_localizations.dart';
import 'package:handslice/screens/printer_screen.dart';
import 'package:handslice/state/printer_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('de'),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('Reiter Drucker: nicht verbunden → Hinweis', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const secure = FlutterSecureStorage();
    final state = PrinterState(prefs: prefs, secure: secure);

    await tester.pumpWidget(_wrap(PrinterScreen(printerState: state)));
    await tester.pumpAndSettle();

    expect(find.text('Drucker nicht verbunden.'), findsOneWidget);
    expect(find.textContaining('Projekt-Reiter'), findsOneWidget);
  });

  testWidgets('Reiter Drucker: Header + Refresh-Button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const secure = FlutterSecureStorage();
    final state = PrinterState(prefs: prefs, secure: secure);

    await tester.pumpWidget(_wrap(PrinterScreen(printerState: state)));
    await tester.pumpAndSettle();

    expect(find.text('Druckhistorie'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}
