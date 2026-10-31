import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../net/elegoo_cc2_client.dart';

// Phasen des Drucks, abgeleitet aus `machine_status.status` +
// `machine_status.sub_status`. Codes stammen aus
// `elegooofficial/CentauriCarbon2/elegoo/common/method.h` und sind
// im Block-A-Mitschnitt (2026-10-31) als tatsaechlich gepusht
// belegt (siehe docs/networking-cc2.md).
enum PrintPhase {
  // machine_status.status fehlt oder noch nicht gelesen.
  unknown,
  // status == 1
  idle,
  // status != 1, Vorbereitungs-Unterstatus (Aufheizen, Nivellieren,
  // Homing) laufen. UI: Abbrechen aktiv, Pause inaktiv – ein
  // laufendes Pre-Heat laesst sich am Drucker nicht sinnvoll
  // pausieren.
  preparing,
  // status != 1, keine der besonderen sub_status-Codes aktiv.
  printing,
  // sub_status in {2501, 2502, 2505}
  paused,
  // sub_status in {2401, 2402} — Resume-Transition
  resuming,
  // sub_status == 2503 — Cancel laeuft
  cancelling,
  // sub_status == 2504 — Cancel abgeschlossen
  cancelled,
}

// Verbindungs-/Pairing-Zustand des CC2. Access-Code lebt in
// flutter_secure_storage (iOS Keychain / Android EncryptedSharedPreferences);
// nicht in SharedPreferences und nicht in Logs.
class PrinterState extends ChangeNotifier {
  PrinterState({
    required this.prefs,
    required this.secure,
    ElegooCc2Client? client,
  }) : _client = client ?? ElegooCc2Client();

  final SharedPreferences prefs;
  final FlutterSecureStorage secure;
  final ElegooCc2Client _client;

  static const _kIp = 'printer.cc2.ip';
  static const _kSn = 'printer.cc2.sn';
  // Secure-Key fuer den Access-Code (plattformverschluesselt).
  static const _kAccessCode = 'printer.cc2.access_code';

  // CC2-Firmware-Status-Enum (CC2_PROTOCOL.md), relevant fuer Sperren:
  // 1 = Idle. Alles andere = nicht idle (printing, levelling, etc.)
  static const int statusIdle = 1;

  DiscoveryInfo? _discovery;
  CanvasConnection _state = CanvasConnection.disconnected;
  String? _lastError;
  List<CanvasSlot> _slots = const [];
  int _trayAssignmentForTool0 = 3; // Default A4 (RAPID PLA+ beim Testdrucker)

  // Live-Druck-State (aus 1002 + api_status-Deltas aggregiert)
  final Map<String, dynamic> _liveState = {};
  // Aufzeichnungszeit und Dauerwert aus `print_status.print_duration`
  // beim letzten Update – aus diesen beiden berechnen wir die
  // Restzeit (nicht aus absoluten Druckerzeitstempeln, die laufen im
  // LAN-Modus nach).
  int? _lastPrintDurationSec;
  DateTime? _lastPrintDurationAt;
  int? _lastRemainingSec;

  // Letzte hochgeladene Datei (fuer Druckstart)
  String? _lastUploadedName;

  // Timers / Subscriptions
  Timer? _pingTimer;
  StreamSubscription<Map<String, dynamic>>? _statusSub;
  Timer? _reconnectTimer;
  bool _reconnecting = false;

  String? get ip => prefs.getString(_kIp);
  String? get sn => prefs.getString(_kSn);
  DiscoveryInfo? get discovery => _discovery;
  CanvasConnection get connection => _state;
  String? get lastError => _lastError;
  List<CanvasSlot> get slots => _slots;
  int get trayAssignmentForTool0 => _trayAssignmentForTool0;
  ElegooCc2Client get client => _client;
  Map<String, dynamic> get liveState => Map.unmodifiable(_liveState);
  String? get lastUploadedName => _lastUploadedName;
  bool get reconnecting => _reconnecting;

  // Nur fuer Widget-Tests gedacht: ersetzt bzw. merge-t den Live-State
  // ohne echten MQTT-Pfad. Nicht im Produktionscode aufrufen.
  @visibleForTesting
  void injectLiveStateForTest(Map<String, dynamic> delta,
      {bool replace = true}) {
    if (replace) _liveState.clear();
    _mergeStatus(delta);
  }

  // --- Hilfs-Getter fuer die UI (lesen aggregierten Live-State) ---

  int? get machineStatus => _getInt(['machine_status', 'status']);
  // Beim Realdruck 2026-10-25 09:18 beobachtet: `print_status.progress`
  // wandert in der echten Firmware nicht gleichmaessig mit, waehrend
  // `current_layer`/`total_layer` zuverlaessig per Delta kommen. Deshalb
  // ist der Layer-Quotient die primaere Fortschrittsquelle; das Firmware-
  // Feld dient nur als Rueckfall, wenn die Layer-Zahlen (noch) fehlen.
  int? get printProgress {
    final cl = currentLayer;
    final tl = totalLayer;
    if (cl != null && tl != null && tl > 0) {
      return ((cl * 100) / tl).round().clamp(0, 100);
    }
    return _getInt(['print_status', 'progress']);
  }
  int? get currentLayer => _getInt(['print_status', 'current_layer']);
  int? get totalLayer => _getInt(['print_status', 'total_layer']);
  bool? get printEnable => _getBool(['print_status', 'enable']);
  String? get printState => _getString(['print_status', 'state']);
  num? get bedTemperature => _getNum(['heater_bed', 'temperature']);
  num? get bedTarget => _getNum(['heater_bed', 'target']);
  num? get nozzleTemperature => _getNum(['extruder', 'temperature']);
  num? get nozzleTarget => _getNum(['extruder', 'target']);
  List? get exceptionStatus => _get(['machine_status', 'exception_status']) as List?;
  int? get chassisCameraConfigured =>
      _getInt(['external_device', 'chassis_camera', 'configured']);

  bool get isIdle => machineStatus == statusIdle;
  bool get isPrinting =>
      machineStatus != null && machineStatus != statusIdle;

  // --- M6: Phase + Steuerungs-Zustand ---

  int? get subStatus => _getInt(['machine_status', 'sub_status']);

  // Codes gemaess method.h / Daniels const.py / Block-A-Mitschnitt:
  //   Vorbereitung (preparing):
  //     1045 HOTEND_PREHEATING, 1096 HOTEND_COOLING,
  //     1405 ?,                  1906 ?,
  //     2801 BED_LEVELING_START, 2802 BED_LEVELING_END,
  //     2901 HOMING_START,       2902 HOMING_END.
  //     Im eigenen Sniff-Log (logs/cc2-sniff-2026-10-26.jsonl)
  //     als tatsaechlich gepusht gesehen: 1045/1405/2801/2802/2901/2902.
  //     1096 und 1906 steuert fw 02.01.01.07 im Abnahmedruck nicht an,
  //     aber Daniels const.py nennt sie und wir folgen seiner Liste.
  //   Pause: 2501 PRINT_PAUSE_SUCCESS, 2502 PAUSE_STATE,
  //     2505 PAUSE_FILA (Filament-Pause)
  //   Resume: 2401 PRINT_RESUME_SUCCESS,
  //     2402 CONTINUE_HEAT (Transition zur Printing-Phase)
  //   Cancel: 2503 PRINT_CANCEL_START, 2504 PRINT_CANCEL_SUCCESS
  // "paused" sammelt die drei Pause-Varianten; die UI unterscheidet
  // Filament-Zufuhr-Fehler erst zusaetzlich ueber exception_status
  // (siehe isFilamentFeedError).
  PrintPhase get printPhase {
    final s = machineStatus;
    if (s == null) return PrintPhase.unknown;
    if (s == statusIdle) return PrintPhase.idle;
    final sub = subStatus;
    switch (sub) {
      case 1045:
      case 1096:
      case 1405:
      case 1906:
      case 2801:
      case 2802:
      case 2901:
      case 2902:
        return PrintPhase.preparing;
      case 2501:
      case 2502:
      case 2505:
        return PrintPhase.paused;
      case 2401:
      case 2402:
        return PrintPhase.resuming;
      case 2503:
        return PrintPhase.cancelling;
      case 2504:
        return PrintPhase.cancelled;
      default:
        return PrintPhase.printing;
    }
  }

  // exception_status 1243 = Filament-Zufuhr-Fehler (method.h,
  // Enumeration FILAMENT_FEED_FAIL). Erscheint im Mitschnitt als
  // Eintrag im `exception_status`-Array; die Phase wechselt dabei
  // ueblicherweise auf sub_status 2505 (PAUSE_FILA).
  bool get isFilamentFeedError {
    final list = exceptionStatus;
    if (list == null) return false;
    return list.contains(1243);
  }

  // --- Licht-Zustand ---
  //
  // Die CC2-Firmware pusht KEIN `light`/`chamber_light`-Feld
  // auf `api_status` – im Block-A-Mitschnitt und in allen frueheren
  // Capture-Logs: 0 Treffer. Deshalb halten wir den zuletzt vom
  // Nutzer gesetzten Wert hier lokal; `lightOn` ist `null`, bis zum
  // ersten `setLight(...)`-Aufruf (UI zeigt dann "unbekannt" an).

  bool? _lightOn;
  bool? get lightOn => _lightOn;

  // Zeitraffer-Capability. Reihenfolge der Belege:
  //  - `external_device.chassis_camera.configured == 1` → unterstuetzt
  //    (elegoo-link cpp:1148-1163).
  //  - `… == 0` → ausdruecklich nicht unterstuetzt → gesperrt.
  //  - Feld fehlt → unterstuetzt per Model-Default fuer den CC2
  //    (docs/networking-cc2.md 2026-10-25 10:30: delay_video=true am
  //    CC2 FW 02.01.01.07 wirkt nachweislich). Fruehere "unbekannt →
  //    Feld weglassen"-Variante hat beim Realdruck fehlgeleitet.
  bool get supportsTimelapse {
    final c = chassisCameraConfigured;
    if (c == null) return true;
    return c == 1;
  }

  dynamic _get(List<String> path) {
    dynamic cur = _liveState;
    for (final p in path) {
      if (cur is! Map || !cur.containsKey(p)) return null;
      cur = cur[p];
    }
    return cur;
  }
  int? _getInt(List<String> p) {
    final v = _get(p);
    return v is int ? v : (v is num ? v.toInt() : null);
  }
  num? _getNum(List<String> p) { final v = _get(p); return v is num ? v : null; }
  String? _getString(List<String> p) { final v = _get(p); return v is String ? v : null; }
  bool? _getBool(List<String> p) { final v = _get(p); return v is bool ? v : null; }

  // Restzeit NICHT aus absoluten Zeitstempeln – die Druckeruhr laeuft
  // im LAN-Modus bei uns nach. Stattdessen: initiale geschaetzte
  // Druckzeit (print_time aus 1046) minus bisher gelaufene print_duration,
  // monoton extrapoliert mit der realen Wall-Clock.
  int? get remainingSeconds {
    final r = _getInt(['print_status', 'remaining_time_sec']);
    if (r != null && r > 0) {
      // Firmware liefert selbst eine Angabe – nutzen, aber live
      // weiterzaehlen zwischen Updates.
      if (_lastRemainingSec != r || _lastPrintDurationAt == null) {
        _lastRemainingSec = r;
        _lastPrintDurationAt = DateTime.now();
      }
      final elapsed = DateTime.now()
          .difference(_lastPrintDurationAt!)
          .inSeconds;
      final live = (_lastRemainingSec ?? r) - elapsed;
      return live < 0 ? 0 : live;
    }
    return null;
  }

  Future<bool> hasAccessCode() async {
    final c = await secure.read(key: _kAccessCode);
    return c != null && c.isNotEmpty;
  }

  Future<void> savePairing({required String ip, required String accessCode}) async {
    await prefs.setString(_kIp, ip);
    await secure.write(key: _kAccessCode, value: accessCode);
    notifyListeners();
  }

  Future<void> clearPairing() async {
    _stopPing();
    _stopStatusSub();
    _stopReconnect();
    await prefs.remove(_kIp);
    await prefs.remove(_kSn);
    await secure.delete(key: _kAccessCode);
    _discovery = null;
    _state = CanvasConnection.disconnected;
    _slots = const [];
    _liveState.clear();
    _lastError = null;
    notifyListeners();
  }

  void setTrayAssignmentForTool0(int trayId) {
    _trayAssignmentForTool0 = trayId;
    notifyListeners();
  }

  Future<void> connectAndLoad() async {
    final ipV = ip;
    if (ipV == null) {
      _state = CanvasConnection.disconnected;
      _lastError = 'IP nicht gesetzt – zuerst koppeln';
      notifyListeners();
      return;
    }
    _state = CanvasConnection.discovering;
    _lastError = null;
    notifyListeners();

    try {
      final info = await _client.discover(ipV);
      _discovery = info;
      await prefs.setString(_kSn, info.sn);
      _state = CanvasConnection.connecting;
      notifyListeners();

      final code = await secure.read(key: _kAccessCode);
      if (code == null || code.isEmpty) {
        _state = CanvasConnection.authError;
        _lastError = 'Kein Access-Code hinterlegt';
        notifyListeners();
        return;
      }
      _state = CanvasConnection.registering;
      notifyListeners();
      await _client.connect(ip: ipV, sn: info.sn, accessCode: code);
      _state = CanvasConnection.connected;
      _slots = await _client.getCanvasStatus();
      // Initial-Status laden + Delta-Stream abonnieren + PING-Loop
      await _refreshStatus();
      _startStatusSub();
      _startPing();
      notifyListeners();
    } on ElegooAuthException catch (e) {
      _state = CanvasConnection.authError;
      _lastError = e.message;
      notifyListeners();
    } on ElegooNetworkException catch (e) {
      _state = CanvasConnection.networkError;
      _lastError = e.message;
      _scheduleReconnect();
      notifyListeners();
    } on SocketException catch (e) {
      _state = CanvasConnection.networkError;
      _lastError = 'Netzwerk: ${e.message}';
      _scheduleReconnect();
      notifyListeners();
    } catch (e) {
      _state = CanvasConnection.networkError;
      _lastError = e.toString();
      _scheduleReconnect();
      notifyListeners();
    }
  }

  Future<UploadResult> uploadGcode({
    required String gcodePath,
    required String remoteName,
    UploadProgress? onProgress,
  }) async {
    if (_state != CanvasConnection.connected) {
      return UploadResult.failed('Nicht verbunden – zuerst "Verbinden" druecken');
    }
    try {
      final bytes = await File(gcodePath).readAsBytes();
      final r = await _client.uploadGcode(
        remoteName: remoteName,
        data: bytes,
        onProgress: onProgress,
      );
      final files = await _client.getFileList(storageMedia: 'local');
      final seen = files.any((f) => f.filename == remoteName);
      if (!seen) {
        return UploadResult.failed(
            'Upload fertig gemeldet (error_code=${r['error_code']}), '
            'aber Datei erscheint nicht in GET_FILE_LIST – ignoriert');
      }
      _lastUploadedName = remoteName;
      notifyListeners();
      return UploadResult.ok(remoteName, bytes.length);
    } on ElegooAuthException catch (e) {
      return UploadResult.failed('Auth-Fehler beim Upload: ${e.message}');
    } on ElegooUploadException catch (e) {
      return UploadResult.failed(e.message);
    } on SocketException catch (e) {
      return UploadResult.failed('Netzabbruch: ${e.message}');
    } catch (e) {
      return UploadResult.failed(e.toString());
    }
  }

  // --- Druckstart (method 1020) ---

  // Pre-Flight-Checks. Rueckgabe: null = alles OK, sonst der Grund
  // (lokalisierbar in der UI, hier als technischer Key).
  //
  // Reihenfolge der Pruefungen entspricht der Reihenfolge der Sperren
  // im Auftrag M4a: Datei, Fach, Bounds, Idle, Verbindung.
  String? printPreflight({required bool boundsOk}) {
    if (_lastUploadedName == null) return 'preflight.no_upload';
    if (_state != CanvasConnection.connected) {
      return 'preflight.not_connected';
    }
    if (!boundsOk) return 'preflight.bounds_failed';
    if (!isIdle) return 'preflight.not_idle';
    // Fach belegt? CANVAS-Slot mit tray_id = _trayAssignmentForTool0
    // suchen und pruefen, dass filament_type nicht leer ist.
    final slot = _slots.firstWhere(
      (s) => s.trayId == _trayAssignmentForTool0,
      orElse: () => CanvasSlot(
          trayId: -1, filamentType: '', filamentName: '', filamentColor: ''),
    );
    if (slot.trayId < 0 || slot.filamentType.isEmpty) {
      return 'preflight.tray_empty';
    }
    return null;
  }

  Future<StartPrintResult?> startPrint({
    required bool bedlevelForce,
    required bool printerCheck,
    required bool enableTimelapse,
    required bool boundsOk,
  }) async {
    final why = printPreflight(boundsOk: boundsOk);
    if (why != null) {
      _lastError = why;
      notifyListeners();
      return null;
    }
    // delay_video entscheidet sich aus Capability-Flag + User-Switch:
    //  - unterstuetzt (Default fuer CC2) und User aktiv → true
    //  - sonst → false (bei nicht-unterstuetzt wird false explizit
    //    gesendet, damit die Firmware es nicht raet).
    final bool delayVideo = supportsTimelapse && enableTimelapse;
    try {
      final r = await _client.startPrint(
        filename: _lastUploadedName!,
        bedlevelForce: bedlevelForce,
        printerCheck: printerCheck,
        delayVideo: delayVideo,
        slotMap: [
          SlotMapEntry(
              toolIndex: 0,
              canvasId: 0,
              trayId: _trayAssignmentForTool0),
        ],
      );
      _lastError = r.ok ? null : 'startprint.error_code.${r.errorCode}';
      notifyListeners();
      return r;
    } on ElegooAuthException catch (e) {
      _lastError = e.message; notifyListeners(); return null;
    } on ElegooNetworkException catch (e) {
      _lastError = e.message; notifyListeners(); return null;
    } catch (e) {
      _lastError = e.toString(); notifyListeners(); return null;
    }
  }

  // --- M6: Druck-Steuerung + Licht ---

  // Buttons sollen nicht doppelt feuern; `_controlInFlight` sperrt
  // waehrend des RPC-Umlaufs. Kein automatisches Retry: Klaus loest
  // Fehler visuell am Panel.
  bool _controlInFlight = false;
  bool get controlInFlight => _controlInFlight;

  Future<bool> pausePrint() async {
    if (printPhase != PrintPhase.printing || _controlInFlight) return false;
    _controlInFlight = true; _lastError = null; notifyListeners();
    try {
      final r = await _client.pausePrint();
      final code = ((r['result'] as Map?)?['error_code'] ?? -1) as int;
      if (code != 0) {
        _lastError = 'control.pause.error_code.$code';
      }
      return code == 0;
    } on TimeoutException {
      _lastError = 'control.pause.timeout';
      return false;
    } catch (e) {
      _lastError = e.toString();
      return false;
    } finally {
      _controlInFlight = false;
      notifyListeners();
    }
  }

  Future<bool> cancelPrint() async {
    const okPhases = {
      PrintPhase.printing,
      PrintPhase.paused,
      PrintPhase.preparing,
    };
    if (!okPhases.contains(printPhase) || _controlInFlight) {
      return false;
    }
    _controlInFlight = true; _lastError = null; notifyListeners();
    try {
      final r = await _client.cancelPrint();
      final code = ((r['result'] as Map?)?['error_code'] ?? -1) as int;
      if (code != 0) {
        _lastError = 'control.cancel.error_code.$code';
      }
      return code == 0;
    } on TimeoutException {
      _lastError = 'control.cancel.timeout';
      return false;
    } catch (e) {
      _lastError = e.toString();
      return false;
    } finally {
      _controlInFlight = false;
      notifyListeners();
    }
  }

  // Fire-and-forget. Erfolg zeigt sich an der sub_status-Transition
  // 2401 → 2402 im naechsten `api_status`-Delta; die UI reagiert
  // dort. Kein Timeout, kein Retry.
  bool resumePrint() {
    if (printPhase != PrintPhase.paused || _controlInFlight) return false;
    try {
      _client.resumePrint();
      _lastError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> setLight(bool power) async {
    if (_state != CanvasConnection.connected || _controlInFlight) return false;
    _controlInFlight = true; _lastError = null; notifyListeners();
    try {
      final r = await _client.setLight(power);
      final code = ((r['result'] as Map?)?['error_code'] ?? -1) as int;
      if (code == 0) {
        _lightOn = power;
      } else {
        _lastError = 'control.light.error_code.$code';
      }
      return code == 0;
    } on TimeoutException {
      _lastError = 'control.light.timeout';
      return false;
    } catch (e) {
      _lastError = e.toString();
      return false;
    } finally {
      _controlInFlight = false;
      notifyListeners();
    }
  }

  // --- Status, PING, Reconnect ---

  Future<void> _refreshStatus() async {
    try {
      final s = await _client.getStatus();
      final res = s['result'];
      if (res is Map) {
        _mergeStatus(Map<String, dynamic>.from(res));
      }
    } catch (_) {
      // Status-Fetch darf den Zustand nicht kippen – naechster Delta
      // bzw. Reconnect raeumt auf.
    }
  }

  void _mergeStatus(Map<String, dynamic> delta) {
    _deepMerge(_liveState, delta);
    // print_duration-Marker fuer Restzeit-Rechnung
    final pd = _getInt(['print_status', 'print_duration']);
    if (pd != null && pd != _lastPrintDurationSec) {
      _lastPrintDurationSec = pd;
      _lastPrintDurationAt = DateTime.now();
    }
    notifyListeners();
  }

  void _deepMerge(Map<String, dynamic> dst, Map src) {
    src.forEach((k, v) {
      final key = k.toString();
      if (v is Map && dst[key] is Map) {
        _deepMerge(dst[key] as Map<String, dynamic>, v);
      } else if (v is Map) {
        dst[key] = Map<String, dynamic>.from(v);
      } else {
        dst[key] = v;
      }
    });
  }

  void _startStatusSub() {
    _stopStatusSub();
    _statusSub = _client.statusDeltas.listen((event) {
      final res = event['result'];
      if (res is Map) _mergeStatus(Map<String, dynamic>.from(res));
    });
  }

  void _stopStatusSub() {
    _statusSub?.cancel();
    _statusSub = null;
  }

  void _startPing() {
    _stopPing();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_state != CanvasConnection.connected) return;
      try {
        _client.ping();
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  // Verbindungs-Dropouts: der laufende Druck am Drucker darf NICHT
  // betroffen sein – der laeuft komplett lokal. Wir re-verbinden
  // nur die Beobachter-Session und re-abonnieren Status.
  void _scheduleReconnect() {
    if (_reconnecting || _state == CanvasConnection.disconnected) return;
    _reconnecting = true;
    _stopPing();
    _stopStatusSub();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      _reconnecting = false;
      await connectAndLoad();
    });
  }

  void _stopReconnect() {
    _reconnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  @override
  void dispose() {
    _stopPing();
    _stopStatusSub();
    _stopReconnect();
    _client.disconnect();
    super.dispose();
  }
}

class UploadResult {
  UploadResult._({required this.ok, required this.message, this.sizeBytes});
  factory UploadResult.ok(String name, int bytes) =>
      UploadResult._(ok: true, message: name, sizeBytes: bytes);
  factory UploadResult.failed(String why) =>
      UploadResult._(ok: false, message: why);

  final bool ok;
  final String message;
  final int? sizeBytes;
}
