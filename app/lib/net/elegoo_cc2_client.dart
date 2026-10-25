import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

// Discovery-Antwort des CC2 (UDP 52700 → method 7000). Felder gemaess
// docs/networking-cc2.md Abschnitt "Discovery (UDP 52700, Broadcast)".
class DiscoveryInfo {
  DiscoveryInfo({
    required this.sn,
    required this.hostName,
    required this.model,
    required this.protocolVersion,
    required this.lanOnly,
    required this.needsAccessCode,
  });

  final String sn;
  final String hostName;
  final String model;
  final String protocolVersion;
  final bool lanOnly;         // lan_status == 1
  final bool needsAccessCode; // token_status == 1

  static DiscoveryInfo fromJson(Map<String, dynamic> result) => DiscoveryInfo(
        sn: result['sn'] as String,
        hostName: (result['host_name'] ?? '') as String,
        model: (result['machine_model'] ?? '') as String,
        protocolVersion: (result['protocol_version'] ?? '') as String,
        lanOnly: (result['lan_status'] ?? 0) == 1,
        needsAccessCode: (result['token_status'] ?? 0) == 1,
      );
}

enum CanvasConnection {
  disconnected,
  discovering,
  connecting,
  registering,
  connected,
  authError,
  networkError,
}

class CanvasSlot {
  CanvasSlot({
    required this.trayId,
    required this.filamentType,
    required this.filamentName,
    required this.filamentColor,
  });

  final int trayId;
  final String filamentType;
  final String filamentName;
  final String filamentColor;

  String get slotLabel => 'A${trayId + 1}';
}

class RemoteFile {
  RemoteFile({required this.filename, required this.sizeBytes});
  final String filename;
  final int sizeBytes;
}

typedef UploadProgress = void Function(int sent, int total);

class ElegooCc2Client {
  ElegooCc2Client({
    this.udpDiscoveryPort = 52700,
    this.mqttPort = 1883,
    this.httpPort = 80,
    this.chunkSize = 1 * 1024 * 1024, // 1 MiB laut Protokoll
  });

  final int udpDiscoveryPort;
  final int mqttPort;
  final int httpPort;
  final int chunkSize;

  // Session-Zustand nach register().
  String? _ip;
  String? _sn;
  String? _accessCode;
  String? _clientId;
  MqttServerClient? _mqtt;
  final Map<int, Completer<Map<String, dynamic>>> _pendingResponses = {};
  final StreamController<Map<String, dynamic>> _statusDeltas =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get statusDeltas => _statusDeltas.stream;

  bool get isConnected =>
      _mqtt != null && _mqtt!.connectionStatus?.state == MqttConnectionState.connected;

  // ---------- Discovery ----------

  Future<DiscoveryInfo> discover(
    String ip, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      sock.send(
        utf8.encode('{"id":0,"method":7000}'),
        InternetAddress(ip),
        udpDiscoveryPort,
      );
      final completer = Completer<DiscoveryInfo>();
      final sub = sock.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = sock.receive();
        if (dg == null) return;
        try {
          final body = json.decode(utf8.decode(dg.data)) as Map<String, dynamic>;
          final result = body['result'] as Map<String, dynamic>?;
          if (result != null) completer.complete(DiscoveryInfo.fromJson(result));
        } catch (_) {}
      });
      final info = await completer.future.timeout(timeout);
      await sub.cancel();
      return info;
    } finally {
      sock.close();
    }
  }

  // ---------- MQTT connect + register ----------

  Future<void> connect({
    required String ip,
    required String sn,
    required String accessCode,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _ip = ip;
    _sn = sn;
    _accessCode = accessCode;
    _clientId = _makeClientId();
    final client = MqttServerClient.withPort(ip, _clientId!, mqttPort)
      ..logging(on: false)
      ..keepAlivePeriod = 60
      ..secure = false
      ..autoReconnect = false
      ..connectionMessage = (MqttConnectMessage()
          .withClientIdentifier(_clientId!)
          .withWillQos(MqttQos.atMostOnce)
          .authenticateAs('elegoo', accessCode)
          .startClean());
    try {
      await client.connect().timeout(timeout);
    } on NoConnectionException catch (e) {
      throw ElegooAuthException(e.toString());
    } on TimeoutException {
      throw ElegooNetworkException('MQTT connect timed out');
    } catch (e) {
      throw ElegooNetworkException(e.toString());
    }
    final state = client.connectionStatus?.state;
    if (state != MqttConnectionState.connected) {
      final rc = client.connectionStatus?.returnCode;
      if (rc == MqttConnectReturnCode.notAuthorized ||
          rc == MqttConnectReturnCode.badUsernameOrPassword) {
        throw ElegooAuthException('CONNACK: $rc');
      }
      throw ElegooNetworkException('CONNACK: $rc');
    }
    _mqtt = client;

    // Subscribe + Register-Handshake.
    final requestId = _makeHex(27);
    final regRespTopic = 'elegoo/$sn/$requestId/register_response';
    final apiRespTopic = 'elegoo/$sn/$_clientId/api_response';
    final statusTopic = 'elegoo/$sn/api_status';

    final regCompleter = Completer<Map<String, dynamic>>();
    final sub = client.updates!.listen((events) {
      for (final e in events) {
        final msg = e.payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(
            msg.payload.message);
        Map<String, dynamic> body;
        try {
          body = json.decode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        if (e.topic == regRespTopic && !regCompleter.isCompleted) {
          regCompleter.complete(body);
        } else if (e.topic == apiRespTopic) {
          final rid = body['id'];
          if (rid is int) {
            final pending = _pendingResponses.remove(rid);
            pending?.complete(body);
          }
        } else if (e.topic == statusTopic) {
          _statusDeltas.add(body);
        }
      }
    });
    client.subscribe(regRespTopic, MqttQos.atMostOnce);
    client.subscribe(apiRespTopic, MqttQos.atMostOnce);
    client.subscribe(statusTopic, MqttQos.atMostOnce);
    // Minimale Wartezeit auf die SUBACKs – mqtt_client hat keine
    // separate "subscribed"-Signalisierung in dieser API-Version.
    await Future<void>.delayed(const Duration(milliseconds: 150));

    _publishJson('elegoo/$sn/api_register', {
      'client_id': _clientId,
      'request_id': requestId,
    });
    final reg = await regCompleter.future.timeout(timeout);
    if (reg['error'] != 'ok') {
      await sub.cancel();
      await disconnect();
      throw ElegooRegistrationException('register_response: ${reg['error']}');
    }
    // sub bleibt aktiv fuer die weiteren Request/Response-Zyklen.
  }

  Future<void> disconnect() async {
    final c = _mqtt;
    if (c != null) {
      try {
        c.disconnect();
      } catch (_) {}
    }
    _mqtt = null;
    _pendingResponses.clear();
  }

  // ---------- API Requests ----------

  Future<Map<String, dynamic>> getStatus() async =>
      _request(1002, const <String, dynamic>{});

  Future<List<CanvasSlot>> getCanvasStatus() async {
    final r = await _request(2005, const <String, dynamic>{});
    final list = (r['result']['canvas_info']['canvas_list'] as List)
        .cast<Map<String, dynamic>>();
    final slots = <CanvasSlot>[];
    for (final canvas in list) {
      for (final t in (canvas['tray_list'] as List).cast<Map<String, dynamic>>()) {
        slots.add(CanvasSlot(
          trayId: t['tray_id'] as int,
          filamentType: (t['filament_type'] ?? '') as String,
          filamentName: (t['filament_name'] ?? '') as String,
          filamentColor: (t['filament_color'] ?? '#000000') as String,
        ));
      }
    }
    return slots;
  }

  Future<List<RemoteFile>> getFileList({String storageMedia = 'local'}) async {
    final r = await _request(1044, {'storage_media': storageMedia});
    final files = (r['result']['file_list'] ?? const []) as List;
    return files
        .map((e) => RemoteFile(
              filename: ((e as Map)['filename'] ?? '') as String,
              sizeBytes: ((e['size'] ?? 0) as num).toInt(),
            ))
        .toList();
  }

  Future<void> ping() async {
    final client = _mqtt!;
    final sn = _sn!;
    final cid = _clientId!;
    final b = MqttClientPayloadBuilder();
    b.addString(json.encode({'type': 'PING'}));
    client.publishMessage('elegoo/$sn/$cid/api_request',
        MqttQos.atMostOnce, b.payload!);
  }

  // ---------- Upload (chunked HTTP PUT) ----------

  Future<Map<String, dynamic>> uploadGcode({
    required String remoteName,
    required Uint8List data,
    UploadProgress? onProgress,
  }) async {
    final ip = _ip!;
    final code = _accessCode!;
    final md5 = crypto.md5.convert(data).toString();
    int offset = 0;
    Map<String, dynamic> last = const {};
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      while (offset < data.length) {
        final end = math.min(offset + chunkSize, data.length) - 1;
        final chunk = data.sublist(offset, end + 1);
        final req = await client.putUrl(Uri.parse('http://$ip:$httpPort/upload'));
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream');
        req.headers.set(HttpHeaders.contentLengthHeader, chunk.length.toString());
        req.headers.set('Content-Range', 'bytes $offset-$end/${data.length}');
        req.headers.set('X-File-Name', remoteName);
        req.headers.set('X-File-MD5', md5);
        req.headers.set('X-Token', code);
        req.add(chunk);
        final resp = await req.close().timeout(const Duration(seconds: 60));
        if (resp.statusCode == 401 || resp.statusCode == 403) {
          throw ElegooAuthException('HTTP ${resp.statusCode}');
        }
        if (resp.statusCode != 200) {
          throw ElegooUploadException(
              'HTTP ${resp.statusCode} nach $offset byte');
        }
        final body = await resp.transform(utf8.decoder).join();
        try {
          last = json.decode(body) as Map<String, dynamic>;
        } catch (_) {}
        onProgress?.call(end + 1, data.length);
        offset = end + 1;
      }
      return last;
    } finally {
      client.close(force: true);
    }
  }

  // ---------- intern ----------

  Future<Map<String, dynamic>> _request(int method, Map<String, dynamic> params,
      {Duration timeout = const Duration(seconds: 15)}) async {
    if (_mqtt == null) {
      throw StateError('Nicht verbunden');
    }
    final id = _nextRequestId();
    final completer = Completer<Map<String, dynamic>>();
    _pendingResponses[id] = completer;
    _publishJson('elegoo/$_sn/$_clientId/api_request',
        {'id': id, 'method': method, 'params': params});
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pendingResponses.remove(id);
      rethrow;
    }
  }

  void _publishJson(String topic, Map<String, dynamic> body) {
    final b = MqttClientPayloadBuilder();
    b.addString(json.encode(body));
    _mqtt!.publishMessage(topic, MqttQos.atMostOnce, b.payload!);
  }

  int _requestCounter = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
  int _nextRequestId() {
    _requestCounter = (_requestCounter + 1) & 0x7fffffff;
    return _requestCounter;
  }

  String _makeClientId() => 'handsl${_makeHex(6)}';

  String _makeHex(int len) {
    final rand = math.Random.secure();
    const chars = '0123456789abcdef';
    return List.generate(len, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}

class ElegooAuthException implements Exception {
  ElegooAuthException(this.message);
  final String message;
  @override
  String toString() => 'ElegooAuthException: $message';
}

class ElegooNetworkException implements Exception {
  ElegooNetworkException(this.message);
  final String message;
  @override
  String toString() => 'ElegooNetworkException: $message';
}

class ElegooRegistrationException implements Exception {
  ElegooRegistrationException(this.message);
  final String message;
  @override
  String toString() => 'ElegooRegistrationException: $message';
}

class ElegooUploadException implements Exception {
  ElegooUploadException(this.message);
  final String message;
  @override
  String toString() => 'ElegooUploadException: $message';
}
