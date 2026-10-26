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

Future<void> _startMock(
    {int interruptAt = 0, bool rejectAuth = false, String? seedHistoryPath}) async {
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
      if (seedHistoryPath != null) ...['--seed-history', seedHistoryPath],
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

  test('Mock: method 1020 startPrint liefert error_code=0 vom Mock',
      () async {
    await _startMock();
    final c = _makeClient();
    try {
      final info = await c.discover('127.0.0.1');
      await c.connect(ip: '127.0.0.1', sn: info.sn, accessCode: _accessCode);
      // Mock antwortet auf 1020 generisch mit {"error_code": 0} (siehe
      // mock_cc2.py – „nichts weiter als Druck simulieren").
      final r = await c.startPrint(
        filename: 'anything.gcode',
        bedlevelForce: true,
        printerCheck: true,
        delayVideo: false,
        slotMap: const [
          SlotMapEntry(toolIndex: 0, canvasId: 0, trayId: 3),
        ],
      );
      expect(r.ok, isTrue);
      expect(r.errorCode, 0);
    } finally {
      await _stopMock();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ---- Phase 5a/5b: 1036 + 1051 + /download + 3022 ----

  Future<String> writeSeed() async {
    final f = File('${Directory.systemTemp.path}/mock_history.json');
    f.writeAsStringSync('''
[
  {"task_id":"ready-1","task_name":"ready.gcode","begin_time":1,"end_time":500,
   "task_status":1,"time_lapse_video_status":2,
   "time_lapse_video_url":"video/ready.mp4",
   "time_lapse_video_size":2048,"time_lapse_video_duration":3},
  {"task_id":"frames-1","task_name":"frames.gcode","begin_time":2,"end_time":700,
   "task_status":1,"time_lapse_video_status":1,
   "time_lapse_video_url":"picture/frames",
   "time_lapse_video_size":0,"time_lapse_video_duration":0},
  {"task_id":"nothing-1","task_name":"nothing.gcode","begin_time":3,"end_time":100,
   "task_status":1,"time_lapse_video_status":0,
   "time_lapse_video_url":"",
   "time_lapse_video_size":0,"time_lapse_video_duration":0},
  {"task_id":"stale-1","task_name":"stale.gcode","begin_time":4,"end_time":200,
   "task_status":1,"time_lapse_video_status":2,
   "time_lapse_video_url":"video/stale.mp4",
   "time_lapse_video_size":1234,"time_lapse_video_duration":2}
]
''');
    // „stale.mp4" existiert in der Mock-videos-Map, aber wir muessen die
    // Datei zum Testen des „nicht mehr verfuegbar"-Pfads vom Mock
    // entfernen. Alternative: einen Eintrag mit video_status=2 anlegen,
    // dessen URL der Mock NICHT ablegt. Loesung: beim Start das Flag
    // "stale.mp4" nicht als video seeden. Wir leeren das in einem
    // zweiten Durchgang ueber die 1036-Antwort und einen Head-Probe
    // gegen eine komplett fiktive URL.
    return f.path;
  }

  test('Mock Phase5: 1036 + Head-Probe + Download (status 2)', () async {
    final seed = await writeSeed();
    await _startMock(seedHistoryPath: seed);
    final c = _makeClient();
    try {
      final info = await c.discover('127.0.0.1');
      await c.connect(ip: '127.0.0.1', sn: info.sn, accessCode: _accessCode);
      final hist = await c.getHistory();
      // Alle 4 seeded Eintraege da
      expect(hist.length, 4);
      final ready = hist.firstWhere((t) => t.taskId == 'ready-1');
      expect(ready.hasVideo, isTrue);
      expect(ready.videoStatus, 2);
      // Head-Probe auf vorhandene Datei
      final probeOk = await c.probeTimelapse(ready.videoUrl);
      expect(probeOk.ok, isTrue);
      // Head-Probe auf fehlende Datei → Timeout → ok=false
      final probeMiss = await c.probeTimelapse('video/does-not-exist.mp4',
          timeout: const Duration(seconds: 2));
      expect(probeMiss.ok, isFalse);
      // Download der vorhandenen
      final bytes = await c.downloadTimelapse(ready.videoUrl,
          expectedBytes: ready.videoSize);
      expect(bytes.length, greaterThan(0));
      await c.disconnect();
    } finally {
      await _stopMock();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('Mock Phase5: 1051 Erfolgsfall (3020→3021), video_status 1→2', () async {
    final seed = await writeSeed();
    await _startMock(seedHistoryPath: seed);
    final c = _makeClient();
    try {
      final info = await c.discover('127.0.0.1');
      await c.connect(ip: '127.0.0.1', sn: info.sn, accessCode: _accessCode);
      final before = await c.getHistory();
      final target = before.firstWhere((t) => t.taskId == 'frames-1');
      expect(target.videoStatus, 1);
      // 1051 mit picture-URL
      final r = await c.renderTimelapse(target.videoUrl);
      expect(r['error_code'], 0);
      // Status-12 → 1-Sequenz des Mocks abwarten (~150 ms gesamt)
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final after = await c.getHistory();
      final updated = after.firstWhere((t) => t.taskId == 'frames-1');
      expect(updated.videoStatus, 2);
      expect(updated.videoUrl, startsWith('video/'));
      // Head-Probe + Download der neu entstandenen Datei
      final probe = await c.probeTimelapse(updated.videoUrl);
      expect(probe.ok, isTrue);
      await c.disconnect();
    } finally {
      await _stopMock();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('Mock Phase5: 1051 ohne Rohframes → 3022, video_status bleibt', () async {
    final seed = await writeSeed();
    await _startMock(seedHistoryPath: seed);
    final c = _makeClient();
    try {
      final info = await c.discover('127.0.0.1');
      await c.connect(ip: '127.0.0.1', sn: info.sn, accessCode: _accessCode);
      // Target: eine picture-URL, die der Mock NICHT als Status-1-Eintrag
      // hat → 3022. Wir reichen eine URL ein, die zu keinem Eintrag passt.
      final r = await c.renderTimelapse('picture/does-not-exist');
      expect(r['error_code'], 0);
      // Mock pusht 3020 → 3022 → 1 in ~100 ms. Die History-Werte duerfen
      // sich nicht aendern.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final after = await c.getHistory();
      final frames = after.firstWhere((t) => t.taskId == 'frames-1');
      expect(frames.videoStatus, 1); // unveraendert
      await c.disconnect();
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
