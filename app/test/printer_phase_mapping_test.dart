// Unit-Tests fuer die Phase-Ableitung in PrinterState: machine_status
// + sub_status laut method.h, Filamentzufuhr-Fehler ueber
// exception_status=1243. Nutzt den @visibleForTesting-Hook
// injectLiveStateForTest, kein MQTT.

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/state/printer_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<PrinterState> _buildState() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return PrinterState(prefs: prefs, secure: const FlutterSecureStorage());
}

void main() {
  group('PrinterState.printPhase', () {
    test('ohne Live-State: unknown', () async {
      final s = await _buildState();
      expect(s.printPhase, PrintPhase.unknown);
    });

    test('status=1 → idle', () async {
      final s = await _buildState();
      s.injectLiveStateForTest({'machine_status': {'status': 1}});
      expect(s.printPhase, PrintPhase.idle);
    });

    test('status != 1 ohne besonderen sub_status → printing', () async {
      final s = await _buildState();
      s.injectLiveStateForTest({
        'machine_status': {'status': 2, 'sub_status': 1066},
      });
      expect(s.printPhase, PrintPhase.printing);
    });

    test('sub_status 2501/2502/2505 → paused', () async {
      for (final sub in [2501, 2502, 2505]) {
        final s = await _buildState();
        s.injectLiveStateForTest({
          'machine_status': {'status': 2, 'sub_status': sub},
        });
        expect(s.printPhase, PrintPhase.paused, reason: 'sub_status=$sub');
      }
    });

    test('sub_status 2401/2402 → resuming', () async {
      for (final sub in [2401, 2402]) {
        final s = await _buildState();
        s.injectLiveStateForTest({
          'machine_status': {'status': 2, 'sub_status': sub},
        });
        expect(s.printPhase, PrintPhase.resuming, reason: 'sub_status=$sub');
      }
    });

    test('sub_status 2503 → cancelling, 2504 → cancelled', () async {
      final s1 = await _buildState();
      s1.injectLiveStateForTest({
        'machine_status': {'status': 2, 'sub_status': 2503},
      });
      expect(s1.printPhase, PrintPhase.cancelling);

      final s2 = await _buildState();
      s2.injectLiveStateForTest({
        'machine_status': {'status': 2, 'sub_status': 2504},
      });
      expect(s2.printPhase, PrintPhase.cancelled);
    });
  });

  group('PrinterState.isFilamentFeedError', () {
    test('kein exception_status → false', () async {
      final s = await _buildState();
      s.injectLiveStateForTest({'machine_status': {'status': 2}});
      expect(s.isFilamentFeedError, isFalse);
    });

    test('exception_status enthaelt 1243 → true', () async {
      final s = await _buildState();
      s.injectLiveStateForTest({
        'machine_status': {'status': 2, 'exception_status': [1243]},
      });
      expect(s.isFilamentFeedError, isTrue);
    });

    test('exception_status enthaelt andere Codes → false', () async {
      final s = await _buildState();
      s.injectLiveStateForTest({
        'machine_status': {'status': 2, 'exception_status': [9999, 1200]},
      });
      expect(s.isFilamentFeedError, isFalse);
    });

    test('exception_status mit 1243 + weiteren Codes → true', () async {
      final s = await _buildState();
      s.injectLiveStateForTest({
        'machine_status': {
          'status': 2,
          'sub_status': 2505,         // PAUSE_FILA begleitet 1243 typisch
          'exception_status': [1200, 1243],
        },
      });
      expect(s.isFilamentFeedError, isTrue);
      expect(s.printPhase, PrintPhase.paused);
    });
  });

  group('PrinterState.lightOn', () {
    test('initial null (Firmware pusht keinen Licht-Zustand)', () async {
      final s = await _buildState();
      expect(s.lightOn, isNull);
    });
  });
}
