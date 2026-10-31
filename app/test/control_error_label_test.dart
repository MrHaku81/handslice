// M8-Nachbesserung: Prueft, dass jeder control.*-Fehlerschluessel,
// den PrinterState setzt, in der UI eine lokalisierte Uebersetzung
// bekommt. Hintergrund: Beim Pflicht-3-Geraetetest tauchte
// "control.cancel.timeout" roh in der UI auf, weil der
// Pass-through die Platzhalter-Keys unveraendert ausgab.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/l10n/app_localizations.dart';
import 'package:handslice/net/control_error_label.dart';

Future<AppLocalizations> _l(String code) async {
  // AppLocalizations.lookup(..) ist eine synchrone Factory in dem
  // generated-File; dennoch an WidgetsFlutterBinding gebunden.
  WidgetsFlutterBinding.ensureInitialized();
  return AppLocalizations.delegate.load(Locale(code));
}

void main() {
  group('mapControlErrorToText', () {
    test('alle verb × kind Kombinationen liefern einen nicht-leeren Text', () async {
      for (final loc in ['en', 'de']) {
        final l = await _l(loc);
        for (final verb in controlErrorVerbs) {
          // timeout
          final timeoutKey = 'control.$verb.timeout';
          final tText = mapControlErrorToText(l, timeoutKey);
          expect(tText, isNotNull, reason: 'timeout fuer $verb in $loc');
          expect(tText, isNot(contains('control.')),
              reason: 'rohes Schluesselfragment in UI-Text von $timeoutKey');
          expect(tText!.trim(), isNotEmpty);
          // error_code mit konkretem Code
          final errKey = 'control.$verb.error_code.1234';
          final eText = mapControlErrorToText(l, errKey);
          expect(eText, isNotNull, reason: 'error_code fuer $verb in $loc');
          expect(eText, contains('1234'));
          expect(eText, isNot(contains('control.')),
              reason: 'rohes Schluesselfragment in UI-Text von $errKey');
        }
      }
    });

    test('error_code mit negativen Zahlen wird akzeptiert', () async {
      final l = await _l('en');
      final r = mapControlErrorToText(l, 'control.cancel.error_code.-1');
      expect(r, isNotNull);
      expect(r, contains('-1'));
    });

    test('unbekannte Keys liefern null (Caller faellt auf rohen Key zurueck)', () async {
      final l = await _l('en');
      expect(mapControlErrorToText(l, null), isNull);
      expect(mapControlErrorToText(l, ''), isNull);
      expect(mapControlErrorToText(l, 'preflight.not_idle'), isNull);
      expect(mapControlErrorToText(l, 'control.light.foo'), isNull);
      // error_code ohne N → unvollstaendig
      expect(mapControlErrorToText(l, 'control.cancel.error_code'), isNull);
    });
  });
}
