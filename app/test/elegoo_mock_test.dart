// Integration-Tests gegen den Python-Mock unter
// engine/test/mock-cc2/mock_cc2.py. Startet den Mock als Subprocess,
// faehrt die relevanten Pfade durch, stoppt ihn.
//
// Lauf: `flutter test test/elegoo_mock_test.dart`
// Erfordert: python3 + mosquitto + python-paho-mqtt am Host.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/net/elegoo_cc2_client.dart';

const _mockSn = 'MOCK0000000000M1';
const _accessCode = 'mocksec'; // Platzhalter, nicht echter CC2-Code
const _wrongCode = 'wrong42';

const _udpPort = 52710;
const _mqttPort = 11883;
const _httpPort = 18080;

late Process _mock;

Future<void> _startMock({int interruptAt = 0, bool rejectAuth = false}) async {
  final env = Map<String, String>.from(Platform.environment)
    ..['MOCK_ACCESS_CODE'] = _accessCode;
  _mock = await Process.start(
    'python3',
    [
      '../engine/test/mock-cc2/mock_cc2.py',
      '--bind', '127.0.0.1',
      '--udp-port', '$_udpPort',
      '--mqtt-port', '$_mqttPort',
      '--http-port', '$_httpPort',
      if (interruptAt > 0) ...['--interrupt-upload-at', '$interruptAt'],
      if (rejectAuth) '--reject-auth',
    ],
    environment: env,
  );
  // Startup abwarten (mosquitto + adapter)
  await Future<void>.delayed(const Duration(seconds: 2));
}

Future<void> _stopMock() async {
  _mock.kill(ProcessSignal.sigterm);
  await _mock.exitCode.timeout(const Duration(seconds: 3),
      onTimeout: () => _mock.kill(ProcessSignal.sigkill) ? 137 : 0);
}

ElegooCc2Client _makeClient() => ElegooCc2Client(
      udpDiscoveryPort: _udpPort,
      mqttPort: _mqttPort,
      httpPort: _httpPort,
    );

void main() {
  test('Mock: Discovery + Register + Canvas (richtiger Code)', () async {
    await _startMock();
    final c = _makeClient();
    try {
      final info = await c.discover('127.0.0.1');
      expect(info.sn, _mockSn);
      expect(info.needsAccessCode, true);
      await c.connect(ip: '127.0.0.1', sn: info.sn, accessCode: _accessCode);
      final slots = await c.getCanvasStatus();
      expect(slots.length, 4);
      expect(slots[0].filamentType, 'PETG');
      expect(slots[3].filamentType, 'PLA');
      expect(slots[3].slotLabel, 'A4');
      await c.disconnect();
    } finally {
      await _stopMock();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('Mock: falscher Code → ElegooAuthException', () async {
    await _startMock();
    final c = _makeClient();
    try {
      final info = await c.discover('127.0.0.1');
      await expectLater(
        c.connect(ip: '127.0.0.1', sn: info.sn, accessCode: _wrongCode),
        throwsA(isA<ElegooAuthException>()),
      );
    } finally {
      await _stopMock();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('Mock: Upload funktioniert + Datei erscheint in FILE_LIST',
      () async {
    await _startMock();
    final c = _makeClient();
    try {
      final info = await c.discover('127.0.0.1');
      await c.connect(ip: '127.0.0.1', sn: info.sn, accessCode: _accessCode);
      final data = Uint8List.fromList(
          List.generate(50_000, (i) => (i * 7) & 0xff));
      final r = await c.uploadGcode(remoteName: 'smoke.gcode', data: data);
      expect(r['error_code'], 0);
      final files = await c.getFileList(storageMedia: 'local');
      expect(files.any((f) => f.filename == 'smoke.gcode'), isTrue);
    } finally {
      await _stopMock();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('Mock: Upload-Abbruch nach N byte → ElegooUploadException', () async {
    // Mock schliesst die TCP-Verbindung nach 2 KiB → unser Client sieht
    // einen Socket-Fehler bzw. HTTP-End-Of-Stream.
    await _startMock(interruptAt: 2048);
    final c = _makeClient();
    try {
      final info = await c.discover('127.0.0.1');
      await c.connect(ip: '127.0.0.1', sn: info.sn, accessCode: _accessCode);
      final data = Uint8List.fromList(List<int>.filled(50_000, 0x42));
      await expectLater(
        c.uploadGcode(remoteName: 'crash.gcode', data: data),
        throwsA(anyOf(
          isA<ElegooUploadException>(),
          isA<SocketException>(),
          isA<HttpException>(),
        )),
      );
    } finally {
      await _stopMock();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
