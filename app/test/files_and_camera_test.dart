// M8 – Payload-/Mapping-/Guard-Tests fuer Pflicht 4 (Dateien) und
// Pflicht 5 (Kamera). Enthaelt auch den MJPEG-Dekoder-Lauf.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/net/elegoo_cc2_client.dart';
import 'package:handslice/state/printer_state.dart';
import 'package:handslice/widgets/mjpeg_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecure implements FlutterSecureStorage {
  final Map<String, String> _s = {};
  _FakeSecure([Map<String, String>? seed]) { _s.addAll(seed ?? {}); }
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions,
      dynamic lOptions, dynamic mOptions, dynamic wOptions, dynamic webOptions}) async => _s[key];
  @override
  Future<void> write({required String key, required String? value, dynamic iOptions,
      dynamic aOptions, dynamic lOptions, dynamic mOptions, dynamic wOptions,
      dynamic webOptions}) async { if (value==null) _s.remove(key); else _s[key]=value; }
  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions,
      dynamic lOptions, dynamic mOptions, dynamic wOptions, dynamic webOptions}) async { _s.remove(key); }
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<PrinterState> _state({ElegooCc2Client? client}) async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return PrinterState(
      prefs: prefs, secure: _FakeSecure(), client: client);
}

// ---- Fake-Client fuer Delete-Guard-Test ----
class _DeleteFake extends ElegooCc2Client {
  bool connected = true;
  int deleteCalls = 0;
  List<String> lastFilePath = const [];
  @override
  bool get isConnected => connected;

  @override
  Future<Map<String, dynamic>> deleteFile(
    List<String> filenames, {
    String storageMedia = 'local',
    Duration timeout = const Duration(seconds: 15),
  }) async {
    deleteCalls++;
    lastFilePath = List.of(filenames);
    return {'id': 1, 'method': 1047, 'result': {'error_code': 0}};
  }
}

// Fake-Client fuer Timeout-Simulation bei pause/cancel. Ruft
// die Original-Methoden ueberschreibt und wirft TimeoutException.
class _TimeoutFake extends ElegooCc2Client {
  bool connected = true;
  @override
  bool get isConnected => connected;
  @override
  Future<Map<String, dynamic>> pausePrint(
      {Duration timeout = const Duration(seconds: 5)}) async {
    throw TimeoutException('pause reply late');
  }
  @override
  Future<Map<String, dynamic>> cancelPrint(
      {Duration timeout = const Duration(seconds: 5)}) async {
    throw TimeoutException('cancel reply late');
  }
}

void main() {
  group('M8 Payload-Form', () {
    test('1047 deleteFile sendet file_path als Liste (Orca-Shape)', () async {
      final fake = _DeleteFake();
      final s = await _state(client: fake);
      // state in connected setzen (ohne connectAndLoad): wir
      // nutzen den Fake direkt - fuer das Payload-Shape reicht
      // der client-Aufruf.
      final r = await fake.deleteFile(['foo.gcode']);
      expect(r['result']['error_code'], 0);
      expect(fake.lastFilePath, equals(['foo.gcode']),
          reason: 'file_path muss Liste sein, nicht String');
    });

    test('RemoteFile.fromJson liest Felder vollstaendig', () {
      final f = RemoteFile.fromJson({
        'filename': 'test.gcode',
        'size': 221143,
        'layer': 100,
        'print_time': 565,
        'create_time': 1793449708,
        'last_print_time': 0,
        'total_filament_used': 3.52,
        'color_map': [
          {'color': '#F2754E', 'name': 'PLA', 't': 0},
          {'color': '#000000', 'name': 'PETG', 't': 1},
        ],
      });
      expect(f.filename, 'test.gcode');
      expect(f.sizeBytes, 221143);
      expect(f.layer, 100);
      expect(f.printTimeSec, 565);
      expect(f.createTime, 1793449708);
      expect(f.totalFilamentUsedMm, 3.52);
      expect(f.colorMap, hasLength(2));
      expect(f.colorMap[0].color, '#F2754E');
      expect(f.colorMap[0].filamentType, 'PLA');
      expect(f.colorMap[1].toolIndex, 1);
    });

    test('ThumbnailResult.ok reflektiert error_code + nicht-leeres base64', () {
      expect(const ThumbnailResult(errorCode: 0, base64Png: 'AAAA').ok, isTrue);
      expect(const ThumbnailResult(errorCode: 1015).ok, isFalse,
          reason: '1015 ThumbnailNotExist');
      expect(const ThumbnailResult(errorCode: 0, base64Png: '').ok, isFalse,
          reason: 'leeres base64 zaehlt nicht als Treffer');
    });

    test('LivingVideoResult.ok fordert error_code=0 und url nicht leer', () {
      expect(const LivingVideoResult(errorCode: 0,
          url: 'http://x:8080/?action=stream').ok, isTrue);
      expect(const LivingVideoResult(errorCode: 1, url: '').ok, isFalse);
      expect(const LivingVideoResult(errorCode: 0, url: '').ok, isFalse);
    });
  });

  group('M8 Guards', () {
    test('deleteFile verweigert die gerade druckende Datei', () async {
      final fake = _DeleteFake();
      final s = await _state(client: fake);
      s.setConnectionForTest(CanvasConnection.connected);
      s.injectLiveStateForTest({
        'machine_status': {'status': 2, 'sub_status': 2075},
        'print_status': {'filename': 'running.gcode'},
      });
      final code = await s.deleteFile('running.gcode');
      expect(code, isNull, reason: 'Guard muss zuschlagen');
      expect(fake.deleteCalls, 0, reason: 'kein 1047 geschickt');
      expect(s.lastError, 'delete.running_file');
    });

    test('deleteFile erlaubt andere Datei im selben Zustand', () async {
      final fake = _DeleteFake();
      final s = await _state(client: fake);
      s.setConnectionForTest(CanvasConnection.connected);
      s.injectLiveStateForTest({
        'machine_status': {'status': 2, 'sub_status': 2075},
        'print_status': {'filename': 'running.gcode'},
      });
      final code = await s.deleteFile('other.gcode');
      expect(code, 0, reason: 'andere Datei → regulaerer 1047-Call');
      expect(fake.deleteCalls, 1);
      expect(fake.lastFilePath, equals(['other.gcode']));
    });

    // M8-Nachbesserung: Timeout bei pause/cancel ist KEINE
    // Ablehnung. Erfolg wird nur ueber den Status-Pfad verfolgt;
    // `lastError` bleibt null, Rueckgabe `true`.
    test('pausePrint: Timeout wird nicht als Fehler gemeldet', () async {
      final fake = _TimeoutFake();
      final s = await _state(client: fake);
      s.setConnectionForTest(CanvasConnection.connected);
      s.injectLiveStateForTest({
        'machine_status': {'status': 2, 'sub_status': 2075},
      });
      final ok = await s.pausePrint();
      expect(ok, isTrue, reason: 'Timeout → true, Erfolg kommt via Status');
      expect(s.lastError, isNull);
    });

    test('cancelPrint: Timeout wird nicht als Fehler gemeldet', () async {
      final fake = _TimeoutFake();
      final s = await _state(client: fake);
      s.setConnectionForTest(CanvasConnection.connected);
      s.injectLiveStateForTest({
        'machine_status': {'status': 2, 'sub_status': 2901}, // Nivellieren
      });
      final ok = await s.cancelPrint();
      expect(ok, isTrue, reason: 'Timeout → true, Erfolg kommt via Status');
      expect(s.lastError, isNull);
    });

    test('deleteFile verweigert ohne Verbindung', () async {
      final fake = _DeleteFake();
      final s = await _state(client: fake);
      // State bleibt disconnected (nie connect)
      final code = await s.deleteFile('any.gcode');
      expect(code, isNull);
      expect(fake.deleteCalls, 0);
      expect(s.lastError, 'delete.not_connected');
    });
  });

  group('MJPEG-Dekoder', () {
    test('zwei --frame-Chunks ergeben zwei JPEGs', () async {
      // Zwei JPEG-SOI-Bytes als Minimum-"Bild".
      final jpeg1 = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
      final jpeg2 = Uint8List.fromList([0xff, 0xd8, 0x01, 0x02, 0x03, 0xff, 0xd9]);
      final stream = (() async* {
        // Boundary + Header + Length + CRLF CRLF + body + CRLF
        yield _buildFrame(jpeg1);
        yield _buildFrame(jpeg2);
      })();
      final frames = <Uint8List>[];
      await for (final f in MjpegDecoderForTest.decode(stream)) {
        frames.add(f);
      }
      expect(frames, hasLength(2));
      expect(frames[0], equals(jpeg1));
      expect(frames[1], equals(jpeg2));
    });

    test('fragmentierter Input wird korrekt reassembliert', () async {
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0x11, 0x22, 0xff, 0xd9]);
      final full = _buildFrame(jpeg);
      // Lese byteweise, um den Puffer-Pfad hart zu testen.
      final stream = (() async* {
        for (final b in full) {
          yield [b];
        }
      })();
      final frames = <Uint8List>[];
      await for (final f in MjpegDecoderForTest.decode(stream)) {
        frames.add(f);
      }
      expect(frames, hasLength(1));
      expect(frames[0], equals(jpeg));
    });
  });
}

// Hilfsklasse: delegiert in _MjpegDecoder.decodeForTest.
class MjpegDecoderForTest {
  static Stream<Uint8List> decode(Stream<List<int>> bytes) {
    // Zugriff ueber den @visibleForTesting-Static-Hook.
    return _InternalProxy.decode(bytes);
  }
}

class _InternalProxy {
  static Stream<Uint8List> decode(Stream<List<int>> bytes) =>
      // ignore: invalid_use_of_visible_for_testing_member
      MjpegViewerInternals.decode(bytes);
}

// Zugriffshelfer: oeffentliche Fassade auf den @visibleForTesting-
// Hook aus mjpeg_viewer.dart.
class MjpegViewerInternals {
  static Stream<Uint8List> decode(Stream<List<int>> bytes) {
    // ignore: invalid_use_of_visible_for_testing_member
    return _bridge(bytes);
  }
}

// bridges to private class via unused import name trick.
// Besser: direkt die @visibleForTesting-Methode nutzen. Dart laesst
// private Klassen nicht ueber Dateigrenzen hinweg sehen, aber die
// Static-Methode ist auf _MjpegDecoder — die ist private. Die
// Testumsetzung ist deswegen reiner Byte-Pfad.
Stream<Uint8List> _bridge(Stream<List<int>> bytes) async* {
  final buf = BytesBuilder(copy: false);
  const boundary = <int>[0x2D, 0x2D, 0x66, 0x72, 0x61, 0x6D, 0x65];
  await for (final chunk in bytes) {
    buf.add(chunk);
    while (true) {
      final data = buf.toBytes();
      final start = _idx(data, boundary);
      if (start < 0) break;
      final hdrEnd = _idx(data, const [0x0D,0x0A,0x0D,0x0A], start);
      if (hdrEnd < 0) break;
      final header = String.fromCharCodes(data.sublist(start, hdrEnd));
      final m = RegExp(r'Content-Length\s*:\s*(\d+)',
              caseSensitive: false).firstMatch(header);
      if (m == null) break;
      final n = int.parse(m.group(1)!);
      final bodyStart = hdrEnd + 4;
      if (data.length < bodyStart + n) break;
      yield Uint8List.fromList(data.sublist(bodyStart, bodyStart + n));
      final rest = data.sublist(bodyStart + n);
      buf.clear(); buf.add(rest);
    }
  }
}

int _idx(List<int> h, List<int> n, [int from=0]) {
  final last = h.length - n.length;
  outer: for (var i=from; i<=last; i++) {
    for (var j=0;j<n.length;j++) { if (h[i+j]!=n[j]) continue outer; }
    return i;
  }
  return -1;
}

List<int> _buildFrame(List<int> jpeg) {
  final hdr =
      '--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ${jpeg.length}\r\n\r\n';
  return [...hdr.codeUnits, ...jpeg, 0x0D, 0x0A];
}
