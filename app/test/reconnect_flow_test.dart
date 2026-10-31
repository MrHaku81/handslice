// Volle Reconnect-Flow-Tests mit Fake-MQTT (als Subclass von
// ElegooCc2Client ohne echten MQTT-Transport). Simuliert:
//   1. Erfolgreiche Erstverbindung.
//   2. Verbindungsabriss (Fake meldet isConnected=false).
//   3. Reconnect-Trigger → Banner → connect/register/subscribe/
//      Vollstatus-Fetch erneut.
//   4. Keine Steuerbefehle (Pause/Resume/Cancel/Light/Start) werden
//      wiederholt (Pflicht-3-Vorgabe).
//   5. Netzwerk-wieder-da-Signal (connectivity_plus) bricht die
//      Backoff-Wartezeit sofort ab.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/net/elegoo_cc2_client.dart';
import 'package:handslice/state/printer_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- Fakes ---

class _FakeSecureStorage implements FlutterSecureStorage {
  _FakeSecureStorage([Map<String, String>? seed])
      : _store = {...?seed};
  final Map<String, String> _store;
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions,
      dynamic lOptions, dynamic mOptions, dynamic wOptions, dynamic webOptions}) async =>
      _store[key];
  @override
  Future<void> write({required String key, required String? value, dynamic iOptions,
      dynamic aOptions, dynamic lOptions, dynamic mOptions, dynamic wOptions,
      dynamic webOptions}) async {
    if (value == null) { _store.remove(key); } else { _store[key] = value; }
  }
  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions,
      dynamic lOptions, dynamic mOptions, dynamic wOptions, dynamic webOptions}) async {
    _store.remove(key);
  }
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Fake-Transport: zaehlt Handshake-Steps und Steuerbefehle. Keine
/// echte MQTT-/UDP-/HTTP-Kommunikation. Jeder Reconnect laeuft komplett
/// durch (discover → connect → canvas → status).
class _FakeCc2Client extends ElegooCc2Client {
  int discoverCalls = 0;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int canvasCalls = 0;
  int statusCalls = 0;
  int pingCalls = 0;
  // Steuerbefehle (duerfen nach Reconnect NICHT erneut auftreten).
  int pauseCalls = 0;
  int resumeCalls = 0;
  int cancelCalls = 0;
  int setLightCalls = 0;

  bool _connected = false;
  final StreamController<Map<String, dynamic>> _deltas =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  bool get isConnected => _connected;

  @override
  Stream<Map<String, dynamic>> get statusDeltas => _deltas.stream;

  @override
  Future<DiscoveryInfo> discover(String ip,
      {Duration timeout = const Duration(seconds: 3)}) async {
    discoverCalls++;
    return DiscoveryInfo(
      sn: 'FAKE-SN-00000000',
      hostName: 'Fake CC2',
      model: 'Centauri Carbon 2',
      protocolVersion: '1.0.0',
      lanOnly: true,
      needsAccessCode: true,
    );
  }

  @override
  Future<void> connect({
    required String ip,
    required String sn,
    required String accessCode,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    connectCalls++;
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    _connected = false;
  }

  // Simuliert einen vom Broker/Netz ausgehenden Abriss.
  void dropConnection() {
    _connected = false;
  }

  @override
  Future<List<CanvasSlot>> getCanvasStatus() async {
    canvasCalls++;
    return const <CanvasSlot>[];
  }

  @override
  Future<Map<String, dynamic>> getStatus() async {
    statusCalls++;
    return <String, dynamic>{
      'result': {'machine_status': {'status': 1}},
    };
  }

  @override
  Future<void> ping() async {
    pingCalls++;
  }

  @override
  Future<Map<String, dynamic>> pausePrint(
      {Duration timeout = const Duration(seconds: 10)}) async {
    pauseCalls++;
    return {'result': {'error_code': 0}};
  }

  @override
  Future<Map<String, dynamic>> cancelPrint(
      {Duration timeout = const Duration(seconds: 10)}) async {
    cancelCalls++;
    return {'result': {'error_code': 0}};
  }

  @override
  void resumePrint() {
    resumeCalls++;
  }

  @override
  Future<Map<String, dynamic>> setLight(bool power,
      {Duration timeout = const Duration(seconds: 10)}) async {
    setLightCalls++;
    return {'result': {'error_code': 0}};
  }
}

Future<PrinterState> _makeState(
    {_FakeCc2Client? client, Stream<bool>? networkAvailability}) async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{
    'printer.cc2.ip': '192.0.2.1',
  });
  final prefs = await SharedPreferences.getInstance();
  final secure = _FakeSecureStorage({'printer.cc2.access_code': 'secret'});
  return PrinterState(
    prefs: prefs,
    secure: secure,
    client: client ?? _FakeCc2Client(),
    networkAvailability: networkAvailability,
  );
}

void main() {
  group('Reconnect-Flow mit Fake-MQTT', () {
    test('Trennung → Banner → Reconnect → neuer Vollstatus-Zyklus', () async {
      final fake = _FakeCc2Client();
      final state = await _makeState(client: fake);

      // Erstverbindung: Discover + Connect (api_register-Phase) +
      // Canvas-Pull + 1002-Vollstatus.
      await state.connectAndLoad();
      expect(state.connection, CanvasConnection.connected);
      expect(fake.discoverCalls, 1, reason: 'erste UDP-Discovery');
      expect(fake.connectCalls, 1,
          reason: 'erster MQTT-Connect inkl. api_register');
      expect(fake.canvasCalls, 1);
      expect(fake.statusCalls, 1,
          reason: 'erster 1002-Vollstatus-Fetch');

      // Simulierter Verbindungsabriss (Broker-TCP-Halbschluss o.ae.).
      fake.dropConnection();
      expect(fake.isConnected, isFalse);

      // Reconnect anstossen (im echten Lauf durch ping-Fehler oder
      // Watchdog). Backoff-Zahl ist eine Konstante der Klasse; wir
      // moegen den Timer nicht abwarten → ersetzen die Faelligkeit
      // auf "jetzt" und ticken manuell.
      state.triggerReconnectForTest();
      expect(state.reconnecting, isTrue,
          reason: 'Banner-Zustand erreicht');
      expect(state.secondsUntilReconnect, isNotNull);

      // Backoff abwarten (Serie beginnt mit 2 s). Reicht auch fuer
      // den Timer-Tick aus; danach ist die Verbindung wieder da.
      await Future<void>.delayed(const Duration(seconds: 3));

      expect(state.connection, CanvasConnection.connected);
      expect(fake.connectCalls, 2, reason: 'zweiter MQTT-Connect = Reconnect');
      expect(fake.canvasCalls, 2);
      expect(fake.statusCalls, 2,
          reason: 'frischer 1002-Vollstatus nach dem Reconnect');
      expect(state.reconnecting, isFalse);

      // Pflicht-3: KEIN Steuerbefehl darf nach dem Reconnect
      // automatisch wiederholt werden.
      expect(fake.pauseCalls, 0, reason: 'kein auto-Pause-Replay');
      expect(fake.resumeCalls, 0, reason: 'kein auto-Resume-Replay');
      expect(fake.cancelCalls, 0, reason: 'kein auto-Cancel-Replay');
      expect(fake.setLightCalls, 0, reason: 'kein auto-Light-Replay');
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('Netzwerk-wieder-da-Signal bricht Backoff-Wartezeit ab', () async {
      final fake = _FakeCc2Client();
      final netCtrl = StreamController<bool>.broadcast();
      final state = await _makeState(
          client: fake, networkAvailability: netCtrl.stream);

      await state.connectAndLoad();
      expect(fake.connectCalls, 1);

      // Trennung + Reconnect scheduled → waere ohne Signal 2 s
      // Backoff.
      fake.dropConnection();
      state.triggerReconnectForTest();
      expect(state.reconnecting, isTrue);
      final secBefore = state.secondsUntilReconnect ?? -1;
      expect(secBefore, greaterThanOrEqualTo(1));

      // "Netzwerk kommt wieder" − Signal von connectivity_plus
      // (gemappt auf bool). PrinterState soll den Backoff-Timer
      // abbrechen und sofort reconnecten.
      netCtrl.add(true);
      // Yield → reconnect-Future gestartet → micro-task-Pause fuer
      // den aussetzenden Timer, dann kurz warten bis connectAndLoad
      // asynchron durchlaeuft (die Fake-Discovery ist sofort da).
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(fake.connectCalls, 2,
          reason: 'Reconnect lief sofort, nicht erst nach 2 s');
      expect(state.connection, CanvasConnection.connected);
      expect(state.reconnecting, isFalse);

      await netCtrl.close();
    });

    test('Netzwerk-Signal ignoriert, wenn nicht reconnecting', () async {
      // Idle-Fall: ein spurious "Netzwerk ist da"-Event darf keinen
      // unerwuenschten Reconnect ausloesen, solange die Verbindung
      // steht.
      final fake = _FakeCc2Client();
      final netCtrl = StreamController<bool>.broadcast();
      final state = await _makeState(
          client: fake, networkAvailability: netCtrl.stream);

      await state.connectAndLoad();
      expect(fake.connectCalls, 1);
      // Netzwerk-Signal — sollte NICHT reconnecten.
      netCtrl.add(true);
      netCtrl.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fake.connectCalls, 1,
          reason: 'kein zusaetzlicher Connect, da Zustand connected');
      await netCtrl.close();
    });
  });
}
