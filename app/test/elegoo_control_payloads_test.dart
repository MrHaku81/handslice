// Unit-Tests fuer die M6-Druck-Steuerungs- und Licht-Payloads
// (methods 1021 / 1022 / 1023 / 1029). Prueft nur die reinen
// Payload-Builder; die MQTT-Transportschicht ist ueber den
// Mock-CC2 in elegoo_mock_test.dart abgedeckt.
//
// Belege fuer die Formen stehen in docs/networking-cc2.md unter
// "Per-method request/response shapes".

import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/net/elegoo_cc2_client.dart';

void main() {
  group('Druck-Steuerung + Licht Payloads (Orca-Shape)', () {
    test('1021 PausePrint: params-Objekt wird komplett ausgelassen', () {
      // Orca-UI @2510582: `const Ie = {method: Pt.PausePrint};` – kein
      // params-Key.
      expect(ElegooCc2Client.buildPauseParams(), isNull);
    });

    test('1022 CancelPrint: params-Objekt wird komplett ausgelassen', () {
      // Orca-UI @2511241: `const Ie = {method: Pt.CancelPrint};`.
      expect(ElegooCc2Client.buildCancelParams(), isNull);
    });

    test('1023 ResumePrint: params-Objekt wird komplett ausgelassen', () {
      // Orca-UI @2510915: `const Be = {method: Pt.ResumePrint};`.
      // Die Antwort trifft erst nach Abschluss (~122 s laut Daniel);
      // der Client ruft resumePrint() fire-and-forget auf und
      // beobachtet den Erfolg ueber die sub_status-Transition
      // 2401 -> 2402.
      expect(ElegooCc2Client.buildResumeParams(), isNull);
    });

    test('1029 LightSwitch: params nur {power:0|1}, keine brightness', () {
      // Orca-UI @2517873: `{method:Pt.LightSwitch, params:{power: Ie?1:0}}`.
      // Daniel schickt zusaetzlich {brightness:0|255} – auf fw
      // 02.01.01.07 nicht noetig (Block A device test 2026-10-31),
      // deshalb Orca-Form.
      expect(ElegooCc2Client.buildLightParams(true), equals({'power': 1}));
      expect(ElegooCc2Client.buildLightParams(false), equals({'power': 0}));
      // Explizit absichern, dass KEIN brightness-Key gesetzt wird.
      expect(
          ElegooCc2Client.buildLightParams(true).containsKey('brightness'),
          isFalse);
    });
  });
}
