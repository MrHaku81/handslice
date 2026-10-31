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

// Phase 5a: ein Eintrag aus `method 1036` (`history_task_list[]`).
// Enum-Interpretation von `videoStatus` steht in docs/networking-cc2.md
// unter "Test E (Verteilung der 45 Tasks)":
//   0 = kein Zeitraffer (`url=""`)
//   1 = Rohframes vorhanden (`url=picture/<name><ts>`)
//   2 = MP4 gerendert (`url=video/<name><ts>.mp4`, size > 0)
//   3 = schon mal versucht; Rohframes fehlen → nicht renderbar
class HistoryTask {
  const HistoryTask({
    required this.taskId,
    required this.taskName,
    required this.beginTime,
    required this.endTime,
    required this.taskStatus,
    required this.videoStatus,
    required this.videoUrl,
    required this.videoSize,
    required this.videoDuration,
  });

  final String taskId;
  final String taskName;
  // Druckeruhr-Sekunden; **nicht als UTC-Zeit interpretieren** – nur
  // als Reihenfolge-Schluessel verwenden (Druckeruhr steht auf UTC+8,
  // siehe docs/networking-cc2.md Druckeruhr-Offset).
  final int beginTime;
  final int endTime;
  final int taskStatus;
  // 0..3; siehe Enum-Kommentar oben.
  final int videoStatus;
  // Entweder "" (status 0), "picture/<basename>" (status 1 oder 3) oder
  // "video/<basename>.mp4" (status 2).
  final String videoUrl;
  final int videoSize;
  final int videoDuration;

  bool get hasVideo => videoStatus == 2 && videoSize > 0 && videoUrl.isNotEmpty;
  bool get isRenderable => (videoStatus == 1 || videoStatus == 3) &&
      videoUrl.startsWith('picture/');

  // Dauer in Sekunden (Druckeruhr, aber Zeitspanne ist relativ und daher
  // belastbar).
  int get durationSeconds => (endTime - beginTime).clamp(0, 1 << 31);

  static HistoryTask fromJson(Map<String, dynamic> j) => HistoryTask(
        taskId: (j['task_id'] ?? '') as String,
        taskName: (j['task_name'] ?? '') as String,
        beginTime: ((j['begin_time'] ?? 0) as num).toInt(),
        endTime: ((j['end_time'] ?? 0) as num).toInt(),
        taskStatus: ((j['task_status'] ?? -1) as num).toInt(),
        videoStatus: ((j['time_lapse_video_status'] ?? 0) as num).toInt(),
        videoUrl: (j['time_lapse_video_url'] ?? '') as String,
        videoSize: ((j['time_lapse_video_size'] ?? 0) as num).toInt(),
        videoDuration: ((j['time_lapse_video_duration'] ?? 0) as num).toInt(),
      );
}

// Phase 5a: Head-Probe-Antwort auf GET /download. `ok=true` bedeutet
// HTTP 200 + Content-Length>0 innerhalb des Timeouts.
class TimelapseProbe {
  const TimelapseProbe({
    required this.ok,
    required this.contentLength,
    required this.elapsed,
  });
  final bool ok;
  final int? contentLength;
  final Duration elapsed;
}

typedef DownloadProgress = void Function(int received, int? total);

// Ein Eintrag im slot_map-Array von method 1020. Form eins-zu-eins
// aus elegoo-link cpp:85-96:
//   { "t": <tool-index>, "canvas_id": <int>, "tray_id": <int> }
class SlotMapEntry {
  const SlotMapEntry({
    required this.toolIndex,
    required this.canvasId,
    required this.trayId,
  });
  final int toolIndex;
  final int canvasId;
  final int trayId;

  Map<String, dynamic> toJson() =>
      {'t': toolIndex, 'canvas_id': canvasId, 'tray_id': trayId};
}

// Antwort auf method 1020 (Druckstart). `errorCode == 0` ist das in
// unserem M3-Lauf beobachtete Erfolgs-Signal; weitere Felder haengen
// an der Firmware und werden hier roh durchgereicht.
class StartPrintResult {
  const StartPrintResult({required this.errorCode, required this.raw});
  final int errorCode;
  final Map<String, dynamic> raw;
  bool get ok => errorCode == 0;
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

  // Baut die method-1020-Payload. `delayVideo` nur mitsenden, wenn
  // bekannt ist, ob der Drucker Zeitraffer unterstuetzt (`null` =
  // Feld weglassen, wie "leaving the key out lets the printer decide"
  // in CC2_PROTOCOL.md).
  Map<String, dynamic> buildStartPrintPayload({
    required String filename,
    required bool bedlevelForce,
    required bool printerCheck,
    required bool? delayVideo,
    required List<SlotMapEntry> slotMap,
    String storageMedia = 'local',
    String printLayout = 'A',
  }) {
    final cfg = <String, dynamic>{
      'printer_check': printerCheck,
      'print_layout': printLayout,
      'bedlevel_force': bedlevelForce,
      'slot_map': slotMap.map((e) => e.toJson()).toList(),
    };
    if (delayVideo != null) {
      cfg['delay_video'] = delayVideo;
    }
    return {
      'storage_media': storageMedia,
      'filename': filename,
      'config': cfg,
    };
  }

  Future<StartPrintResult> startPrint({
    required String filename,
    required bool bedlevelForce,
    required bool printerCheck,
    required bool? delayVideo,
    required List<SlotMapEntry> slotMap,
    String storageMedia = 'local',
    String printLayout = 'A',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final params = buildStartPrintPayload(
      filename: filename,
      bedlevelForce: bedlevelForce,
      printerCheck: printerCheck,
      delayVideo: delayVideo,
      slotMap: slotMap,
      storageMedia: storageMedia,
      printLayout: printLayout,
    );
    final r = await _request(1020, params, timeout: timeout);
    final result = (r['result'] ?? const <String, dynamic>{}) as Map;
    final code = (result['error_code'] ?? -1) as int;
    return StartPrintResult(errorCode: code,
                            raw: Map<String, dynamic>.from(r as Map));
  }

  // ---------- M6: Druck-Steuerung (1021/1022/1023) + Licht (1029) ----------
  //
  // Formen entsprechen Orcas Vue-UI (docs/networking-cc2.md Tabelle
  // "Per-method request/response shapes"):
  //   method 1021 PausePrint  → KEIN params-Objekt (Orca @2510582)
  //   method 1022 CancelPrint → KEIN params-Objekt (Orca @2511241)
  //   method 1023 ResumePrint → KEIN params-Objekt (Orca @2510915),
  //       Reply kommt erst nach Abschluss (~122 s laut Daniel). Daher
  //       fire-and-forget: wir pushen und beobachten den Erfolg ueber
  //       die sub_status-Transition 2401 → 2402 im PrinterState.
  //   method 1029 LightSwitch → params={"power": 0|1}  (Orca @2517873)
  //       Daniel schickt zusaetzlich {brightness:0|255} (client.py:
  //       2431-2434), auf fw 02.01.01.07 ist das jedoch unnoetig
  //       (Block A device test 2026-10-31) – wir folgen Orca.
  //
  // Public Payload-Builder sind rein funktional und ohne MQTT-
  // Abhaengigkeit; die Unit-Tests pruefen die Byte-Form.

  static Map<String, dynamic>? buildPauseParams() => null;
  static Map<String, dynamic>? buildCancelParams() => null;
  static Map<String, dynamic>? buildResumeParams() => null;
  static Map<String, dynamic> buildLightParams(bool power) =>
      {'power': power ? 1 : 0};

  Future<Map<String, dynamic>> pausePrint(
      {Duration timeout = const Duration(seconds: 10)}) async {
    return _request(1021, buildPauseParams(), timeout: timeout);
  }

  Future<Map<String, dynamic>> cancelPrint(
      {Duration timeout = const Duration(seconds: 10)}) async {
    return _request(1022, buildCancelParams(), timeout: timeout);
  }

  // Fire-and-forget: der echte Reply trifft erst nach dem Abschluss
  // der Resume-Transition ein (Daniel misst ~122 s). Blockieren bringt
  // nichts; der UI-Pfad verfolgt den Erfolg via sub_status 2401→2402.
  // Kein automatisches Retry.
  void resumePrint() {
    if (_mqtt == null) {
      throw StateError('Nicht verbunden');
    }
    final id = _nextRequestId();
    _publishJson('elegoo/$_sn/$_clientId/api_request',
        {'id': id, 'method': 1023});
  }

  Future<Map<String, dynamic>> setLight(bool power,
      {Duration timeout = const Duration(seconds: 10)}) async {
    return _request(1029, buildLightParams(power), timeout: timeout);
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

  // ---------- Phase 5: Historie, Rendering, Download ----------

  // method 1036: komplette Druckhistorie. Keine Pagination laut
  // cc2-control-Kommentar + docs/networking-cc2.md Test E.
  Future<List<HistoryTask>> getHistory({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final r = await _request(1036, const <String, dynamic>{}, timeout: timeout);
    final result = (r['result'] ?? const <String, dynamic>{}) as Map;
    final list = (result['history_task_list'] ?? const []) as List;
    return list
        .whereType<Map>()
        .map((e) => HistoryTask.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // method 1051: Rendering starten. `pictureUrl` muss die Form
  // `picture/<basename>` haben; die Firmware strippt den Prefix und
  // haengt `.mp4` an die Zieldatei (siehe docs Test B/C).
  // Response ist `{"error_code":0,"url":"video/<basename>.mp4"}` –
  // aber ERFOLG wird NICHT durch `error_code=0` belegt, sondern durch
  // einen anschliessenden erfolgreichen Head-Probe. 3022 heisst
  // "keine Rohframes am erwarteten Pfad".
  Future<Map<String, dynamic>> renderTimelapse(
    String pictureUrl, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final r = await _request(1051, {'url': pictureUrl}, timeout: timeout);
    return (r['result'] ?? const <String, dynamic>{}) as Map<String, dynamic>;
  }

  // Head-Probe: GET /download?... mit kurzem Response-Header-Timeout.
  // ok=true nur wenn HTTP 200 UND Content-Length>0 vor Timeout.
  // Timeout OR Nicht-200 OR Content-Length=0 => ok=false (die Datei
  // ist nicht abrufbar). Deckt sich mit docs Test A: head_ms<30ms
  // bei vorhandener Datei, Schweigen bei fehlender.
  Future<TimelapseProbe> probeTimelapse(
    String fileName, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final stopwatch = Stopwatch()..start();
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = timeout;
    try {
      final req = await client
          .getUrl(_downloadUri(fileName))
          .timeout(timeout);
      req.headers.set('Connection', 'close');
      final resp = await req.close().timeout(timeout);
      stopwatch.stop();
      // Dart's HttpClient liefert -1 fuer unbekannte Content-Length
      // (reine Transfer-Encoding: chunked ohne Length). Unser CC2
      // setzt beides; wir werten "ok" positiv wenn status==200 UND
      // (cl>0 ODER status==200 reicht alleine fuer chunked).
      final cl = resp.contentLength;
      final ok = resp.statusCode == 200 && (cl > 0 || cl == -1);
      // Body nicht lesen; Connection schliessen.
      await resp.drain<void>();
      return TimelapseProbe(
          ok: ok, contentLength: cl, elapsed: stopwatch.elapsed);
    } on TimeoutException {
      stopwatch.stop();
      return TimelapseProbe(
          ok: false, contentLength: null, elapsed: stopwatch.elapsed);
    } on SocketException {
      stopwatch.stop();
      return TimelapseProbe(
          ok: false, contentLength: null, elapsed: stopwatch.elapsed);
    } on HttpException {
      // Firmware schliesst die TCP-Verbindung ohne Response, wenn die
      // Datei nicht existiert oder der Token falsch ist – HttpClient
      // werft das als „Connection closed before full header was
      // received". Fuer die App ist das identisch zu „nicht abrufbar".
      stopwatch.stop();
      return TimelapseProbe(
          ok: false, contentLength: null, elapsed: stopwatch.elapsed);
    } finally {
      client.close(force: true);
    }
  }

  // GET /download → bytes-Stream mit Fortschritt. Nutzt denselben
  // Endpunkt wie G-Code-Download (siehe docs). `fileName` ist der
  // komplette path aus `history.time_lapse_video_url`
  // (z. B. `video/<basename>.mp4`).
  //
  // Dart's HttpClient toleriert die Doppel-Rahmung (Content-Length +
  // Transfer-Encoding: chunked), die der echte CC2 setzt: HttpClient
  // bevorzugt chunked, wenn beides da ist, und liest den Body sauber
  // bis zum Terminator. `expectedBytes` kommt aus der History
  // (`videoSize`) – nicht die Antwort-Header, weil die inkonsistent
  // sind.
  Future<List<int>> downloadTimelapse(
    String fileName, {
    int? expectedBytes,
    DownloadProgress? onProgress,
    Duration headTimeout = const Duration(seconds: 3),
    Duration overallTimeout = const Duration(seconds: 120),
  }) async {
    final deadline = DateTime.now().add(overallTimeout);
    final client = HttpClient()..connectionTimeout = headTimeout;
    try {
      final req = await client
          .getUrl(_downloadUri(fileName))
          .timeout(headTimeout);
      req.headers.set('Connection', 'close');
      final resp = await req.close().timeout(headTimeout);
      if (resp.statusCode != 200) {
        throw ElegooNetworkException('HTTP ${resp.statusCode}');
      }
      final out = <int>[];
      await for (final chunk in resp) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('download timeout');
        }
        out.addAll(chunk);
        onProgress?.call(out.length, expectedBytes);
      }
      return out;
    } finally {
      client.close(force: true);
    }
  }

  Uri _downloadUri(String fileName) {
    final ip = _ip!;
    final code = _accessCode!;
    final query = Uri(queryParameters: {
      'X-Token': code,
      'file_name': fileName,
    }).query;
    return Uri.parse('http://$ip:$httpPort/download?$query');
  }

  // method 1038: Historie-Eintrag loeschen. Phase 5 nutzt diese
  // Methode NICHT in der UI (siehe Auftragstext), aber die
  // Infrastruktur ist belegt (Test D). Hilft bei Tests.
  Future<Map<String, dynamic>> deleteHistoryEntries(List<String> taskIds,
      {Duration timeout = const Duration(seconds: 10)}) async {
    final r = await _request(1038, {'list': taskIds}, timeout: timeout);
    return (r['result'] ?? const <String, dynamic>{}) as Map<String, dynamic>;
  }

  // ---------- intern ----------

  Future<Map<String, dynamic>> _request(int method, Map<String, dynamic>? params,
      {Duration timeout = const Duration(seconds: 15)}) async {
    if (_mqtt == null) {
      throw StateError('Nicht verbunden');
    }
    final id = _nextRequestId();
    final completer = Completer<Map<String, dynamic>>();
    _pendingResponses[id] = completer;
    final body = <String, dynamic>{'id': id, 'method': method};
    // Orca-UI laesst `params` komplett weg, wenn die Methode keine
    // Parameter braucht (1021/1022/1023). `null` bedeutet hier:
    // Feld ganz auslassen; `{}` wuerde ein leeres Objekt senden.
    if (params != null) body['params'] = params;
    _publishJson('elegoo/$_sn/$_clientId/api_request', body);
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
