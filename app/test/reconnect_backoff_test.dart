// Unit-Tests fuer die Reconnect-Backoff-Progression in PrinterState.
// Fuer den Trigger-Pfad an echter MQTT-Trennung ist ein Fake-Client
// noetig (nicht Teil dieses Tests – siehe PROGRESS 2026-10-31 „Teil B
// ungeprueft am echten Geraet").

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/state/printer_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<PrinterState> _build() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return PrinterState(prefs: prefs, secure: const FlutterSecureStorage());
}

void main() {
  group('Reconnect-Backoff-Progression', () {
    test('Delay-Serie 2 → 5 → 10 → 20 → 30 s, danach 30 s als Dach', () {
      // Die Zahlen stehen in PrinterState._reconnectBackoffSec; die
      // @visibleForTesting-Static mappt attempt → Sekunden.
      expect(PrinterState.reconnectDelaySecForAttempt(0),  equals(2));
      expect(PrinterState.reconnectDelaySecForAttempt(1),  equals(5));
      expect(PrinterState.reconnectDelaySecForAttempt(2),  equals(10));
      expect(PrinterState.reconnectDelaySecForAttempt(3),  equals(20));
      expect(PrinterState.reconnectDelaySecForAttempt(4),  equals(30));
      // Dach: alles jenseits der Liste bleibt auf dem letzten Wert.
      expect(PrinterState.reconnectDelaySecForAttempt(5),   equals(30));
      expect(PrinterState.reconnectDelaySecForAttempt(99),  equals(30));
      // Negative attempts (defensive) → auf 0 geklippt → 2 s.
      expect(PrinterState.reconnectDelaySecForAttempt(-1),  equals(2));
    });

    test('secondsUntilReconnect liefert positive Rest-Sekunden', () async {
      final s = await _build();
      // simuliere "naechster Versuch in 10 s"
      s.setReconnectDueAtForTest(
          DateTime.now().add(const Duration(seconds: 10)));
      final v = s.secondsUntilReconnect;
      expect(v, isNotNull);
      expect(v, greaterThanOrEqualTo(9));
      expect(v, lessThanOrEqualTo(10));
    });

    test('secondsUntilReconnect clamps auf 0 bei Faelligkeit in der Vergangenheit',
        () async {
      final s = await _build();
      s.setReconnectDueAtForTest(
          DateTime.now().subtract(const Duration(seconds: 3)));
      expect(s.secondsUntilReconnect, equals(0));
    });

    test('secondsUntilReconnect ist null wenn kein Versuch geplant', () async {
      final s = await _build();
      expect(s.secondsUntilReconnect, isNull);
      s.setReconnectDueAtForTest(DateTime.now().add(const Duration(seconds: 5)));
      expect(s.secondsUntilReconnect, isNotNull);
      s.setReconnectDueAtForTest(null);
      expect(s.secondsUntilReconnect, isNull);
    });
  });
}
