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
    Stream<bool>? networkAvailability,
  }) : _client = client ?? ElegooCc2Client() {
    // Pflicht-3-Nachbesserung: wenn das OS „Netzwerk ist wieder da"
    // meldet, nicht die restliche Backoff-Wartezeit abstehen – sofort
    // reconnecten. Nur relevant waehrend wir im reconnecting-Zustand
    // sind UND bereits gekoppelt waren (keine erste Verbindung).
    if (networkAvailability != null) {
      _netSub = networkAvailability.listen((available) {
        if (!available) return;
        if (_state == CanvasConnection.disconnected) return;
        if (!_reconnecting) return;
        _triggerImmediateReconnect(reason: 'network available');
      });
    }
  }

  final SharedPreferences prefs;
  final FlutterSecureStorage secure;
  final ElegooCc2Client _client;
  StreamSubscription<bool>? _netSub;

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
  Timer? _watchdogTimer;
  bool _reconnecting = false;

  // Reconnect-Backoff. Delays in Sekunden; nach dem letzten Index
  // bleibt der letzte Wert als Dach bestehen. Die Folge ist bewusst
  // kurz: Verbindungsabrisse im Heim-WLAN sind meist Sekunden-Events,
  // nicht Minuten.
  static const List<int> _reconnectBackoffSec = [2, 5, 10, 20, 30];

  // Public fuer Unit-Tests der Backoff-Progression.
  @visibleForTesting
  static int reconnectDelaySecForAttempt(int attempt) {
    final idx = attempt.clamp(0, _reconnectBackoffSec.length - 1);
    return _reconnectBackoffSec[idx];
  }

  int _reconnectAttempt = 0;
  DateTime? _reconnectDueAt;

  @visibleForTesting
  int get reconnectAttempt => _reconnectAttempt;

  @visibleForTesting
  void setReconnectDueAtForTest(DateTime? due) {
    _reconnectDueAt = due;
    notifyListeners();
  }

  @visibleForTesting
  void triggerReconnectForTest() => _scheduleReconnect();

  @visibleForTesting
  void setConnectionForTest(CanvasConnection s) {
    _state = s;
    notifyListeners();
  }

  // Status-Watchdog: haertet die Verbindungserkennung, falls der
  // Broker die TCP-Verbindung still kappt (keine CONNACK-Fehlerspur,
  // der mqtt_client meldet keinen Disconnect). Wenn in `_watchdogGrace`
  // kein api_status-Delta auftaucht und wir im Druckbetrieb sind,
  // triggern wir einen Reconnect.
  static const Duration _watchdogGrace = Duration(seconds: 30);
  DateTime? _lastDeltaAt;

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

  // Sekunden bis zum naechsten Reconnect-Versuch, oder null wenn
  // gerade nicht geplant. UI nutzt das fuer einen Countdown.
  int? get secondsUntilReconnect {
    final due = _reconnectDueAt;
    if (due == null) return null;
    final diff = due.difference(DateTime.now()).inSeconds;
    return diff < 0 ? 0 : diff;
  }

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

  // Fortschritt als Bruch 0.0..1.0 oder `null`, wenn kein belastbarer
  // Wert vorliegt. Primaere Quelle: `current_layer / total_layer` –
  // einzige in allen Mitschnitten konsistent beobachtete Groesse.
  //
  // Das Fallback-Feld `print_status.progress` wurde entfernt: der
  // Live-Test 2026-10-31 zeigte, dass die Firmware es im api_status-
  // Delta ueberhaupt nicht pusht und der aus dem initialen 1002-
  // Snapshot gemergte Wert zusammen mit `.clamp(0,100)` den Balken
  // immer "voll" zeichnet. Lieber ehrlich keinen Balken zeigen als
  // einen irrefuehrenden.
  //
  // Rueckgabewert ist bewusst `double?`, nicht `int?`, damit die UI
  // direkt den LinearProgressIndicator-value verwenden kann und
  // nicht erneut durch 100 teilen muss.
  double? get printProgressFraction {
    final cl = currentLayer;
    final tl = totalLayer;
    if (cl == null || tl == null || tl <= 0) return null;
    return (cl / tl).clamp(0.0, 1.0);
  }

  // Prozent-Form fuer Anzeigen wie "Schicht X von Y (Z%)". Null,
  // wenn `printProgressFraction` null ist.
  int? get printProgressPct {
    final f = printProgressFraction;
    return f == null ? null : (f * 100).round();
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

  // Dateiname der gerade laufenden Druckaufgabe (fuer den
  // "aktive Datei nicht loeschen"-Guard und fuer die Live-UI).
  // `null`, wenn die Firmware keinen `print_status.filename`
  // gepusht hat oder der Drucker idle ist.
  String? get runningFilename {
    final s = _getString(['print_status', 'filename']);
    if (s == null || s.isEmpty) return null;
    return s;
  }

  bool get isIdle => machineStatus == statusIdle;
  bool get isPrinting =>
      machineStatus != null && machineStatus != statusIdle;

  // --- M6: Phase + Steuerungs-Zustand ---

  int? get subStatus => _getInt(['machine_status', 'sub_status']);

  // Codes gemaess method.h / Daniels const.py / eigenem Mitschnitt:
  //   Vorbereitung (preparing):
  //     1045 HOTEND_PREHEATING, 1096 HOTEND_COOLING,
  //     1405 BED_PREHEATING,     1906 BED_PREHEATING_2,
  //     2801 BED_LEVELING_START, 2802 BED_LEVELING_END,
  //     2901 HOMING_START,       2902 HOMING_END.
  //     1066 Pre-Print Hotend-Stabilisierung – NICHT in Daniels
  //     const.py genannt, aber in drei Mitschnitten (2026-10-26 x2,
  //     2026-10-31) ausschliesslich mit `current_layer=0` **und**
  //     Hotend-Ist nahe Target gesehen; Nachbarcodes sind 1045/2801/
  //     2901/2075. Siehe docs/networking-cc2.md Abschnitt
  //     "sub_status 1066 analysis (2026-10-31)".
  //     Im eigenen Sniff-Log als tatsaechlich gepusht gesehen:
  //     1045/1066/1405/2801/2802/2901/2902. 1096 und 1906 steuert
  //     fw 02.01.01.07 nicht an, Daniels const.py nennt sie – wir
  //     folgen seiner Liste.
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
      case 1066:   // Pre-Print Hotend-Stabilisierung (Mitschnitt-Beleg)
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

  // Nur die bisher ganzzahligen und > 0 Eintraege. Firmware pusht
  // gelegentlich `null` oder `0` als Platzhalter; die filtern wir
  // weg, damit die UI keinen leeren Error-Banner zeigt.
  List<int> get activeExceptionCodes {
    final list = exceptionStatus;
    if (list == null) return const [];
    final out = <int>[];
    for (final v in list) {
      if (v is int && v > 0) out.add(v);
    }
    return out;
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
    _stopWatchdog();
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
      // Initial-Status laden + Delta-Stream abonnieren + PING-Loop +
      // Status-Watchdog starten. Reconnect-Zaehler zuruecksetzen.
      await _refreshStatus();
      _startStatusSub();
      _startPing();
      _startWatchdog();
      _reconnectAttempt = 0;
      _reconnectDueAt = null;
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
    return _startPrintCore(
      filename: _lastUploadedName!,
      bedlevelForce: bedlevelForce,
      printerCheck: printerCheck,
      enableTimelapse: enableTimelapse,
    );
  }

  // M8 Pflicht 4: Druckstart fuer eine BEREITS AM DRUCKER liegende
  // Datei. Preflight ohne bounds-Check (die liegt nur in der
  // Upload-Pipeline vor); ansonsten identisch zum Upload-Flow.
  Future<StartPrintResult?> startPrintFile({
    required String filename,
    required bool bedlevelForce,
    required bool printerCheck,
    required bool enableTimelapse,
  }) async {
    if (_state != CanvasConnection.connected) {
      _lastError = 'preflight.not_connected';
      notifyListeners();
      return null;
    }
    if (!isIdle) {
      _lastError = 'preflight.not_idle';
      notifyListeners();
      return null;
    }
    final slot = _slots.firstWhere(
      (s) => s.trayId == _trayAssignmentForTool0,
      orElse: () => CanvasSlot(
          trayId: -1, filamentType: '', filamentName: '', filamentColor: ''),
    );
    if (slot.trayId < 0 || slot.filamentType.isEmpty) {
      _lastError = 'preflight.tray_empty';
      notifyListeners();
      return null;
    }
    return _startPrintCore(
      filename: filename,
      bedlevelForce: bedlevelForce,
      printerCheck: printerCheck,
      enableTimelapse: enableTimelapse,
    );
  }

  Future<StartPrintResult?> _startPrintCore({
    required String filename,
    required bool bedlevelForce,
    required bool printerCheck,
    required bool enableTimelapse,
  }) async {
    final bool delayVideo = supportsTimelapse && enableTimelapse;
    try {
      final r = await _client.startPrint(
        filename: filename,
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

  // M8 Pflicht 4: Datei(en) am Drucker loeschen. Shape nach dem
  // 2026-10-31 Block-A-Beleg: `file_path` MUSS Liste sein. Hier
  // nehmen wir trotzdem nur eine Datei entgegen – die UI entscheidet
  // Multi-Delete ggf. spaeter.
  //
  // Guard: die gerade laufende Datei (`runningFilename`) wird NIE
  // gesendet. Rueckgabe `null` bei Guard-Verletzung.
  Future<int?> deleteFile(String filename) async {
    if (_state != CanvasConnection.connected) {
      _lastError = 'delete.not_connected';
      notifyListeners();
      return null;
    }
    if (runningFilename == filename) {
      _lastError = 'delete.running_file';
      notifyListeners();
      return null;
    }
    try {
      final r = await _client.deleteFile([filename]);
      final code = ((r['result'] as Map?)?['error_code'] ?? -1) as int;
      _lastError = code == 0 ? null : 'delete.error_code.$code';
      notifyListeners();
      return code;
    } on TimeoutException {
      _lastError = 'delete.timeout';
      return null;
    } catch (e) {
      _lastError = e.toString();
      return null;
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
    _lastDeltaAt = DateTime.now();
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

  // Status-Watchdog: feuert periodisch, prueft wie lange das letzte
  // api_status-Delta her ist. Wenn > _watchdogGrace und wir glauben
  // verbunden zu sein → Reconnect ausloesen. Baendigt zwei Faelle:
  //   1. Broker-TCP-Halbschluss, bei dem mqtt_client keinen
  //      Disconnect meldet.
  //   2. WLAN-Flap, bei dem die TCP-Verbindung ins Nirgendwo laeuft.
  // Pre-Print laeuft die Firmware oft minutenlang ohne 6000-Delta,
  // daher nur beim laufenden Druck pruefen (status != idle); im
  // Idle bleiben wir ruhig.
  void _startWatchdog() {
    _stopWatchdog();
    _lastDeltaAt = DateTime.now();
    _watchdogTimer =
        Timer.periodic(const Duration(seconds: 10), (_) {
      if (_state != CanvasConnection.connected) return;
      if (isIdle) return;
      final last = _lastDeltaAt;
      if (last == null) return;
      if (DateTime.now().difference(last) > _watchdogGrace) {
        _scheduleReconnect();
      }
    });
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  // Verbindungs-Dropouts: der laufende Druck am Drucker darf NICHT
  // betroffen sein – der laeuft komplett lokal. Wir re-verbinden
  // nur die Beobachter-Session, re-registrieren und re-abonnieren
  // Status. Keine Wiederholung von vorherigen Steuerbefehlen –
  // Pause/Resume/Cancel/Start werden nach dem Reconnect NICHT
  // erneut geschickt (Pflicht-3-Vorgabe).
  //
  // Exponential-ish backoff:  2 → 5 → 10 → 20 → 30 s, danach 30 s.
  void _scheduleReconnect() {
    if (_reconnecting || _state == CanvasConnection.disconnected) return;
    _reconnecting = true;
    _stopPing();
    _stopStatusSub();
    _stopWatchdog();
    _reconnectTimer?.cancel();
    final idx = _reconnectAttempt.clamp(0, _reconnectBackoffSec.length - 1);
    final delaySec = _reconnectBackoffSec[idx];
    _reconnectAttempt++;
    _reconnectDueAt = DateTime.now().add(Duration(seconds: delaySec));
    notifyListeners();
    _reconnectTimer = Timer(Duration(seconds: delaySec), () async {
      _reconnecting = false;
      _reconnectDueAt = null;
      notifyListeners();
      await connectAndLoad();
    });
  }

  void _stopReconnect() {
    _reconnecting = false;
    _reconnectAttempt = 0;
    _reconnectDueAt = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  // Von Lifecycle-Observer (AppLifecycleState.resumed) aufgerufen.
  // Wenn wir aktuell nicht verbunden sind oder der Watchdog die
  // Verbindung fuer stale haelt, triggere einen frischen Versuch.
  // Reset Backoff vorher: nach dem App-Resume geht's beim ersten
  // Versuch mit 2 s los, nicht bei dem alten Zaehler.
  Future<void> checkAliveOnResume() async {
    if (_state == CanvasConnection.disconnected) return;
    final isConn = _client.isConnected;
    final stale = _lastDeltaAt != null &&
        DateTime.now().difference(_lastDeltaAt!) > _watchdogGrace;
    if (!isConn || stale) {
      _reconnectAttempt = 0;
      _scheduleReconnect();
    }
  }

  // Bricht die laufende Backoff-Wartezeit ab und startet sofort
  // einen Reconnect-Versuch. Setzt den Attempt-Zaehler NICHT zurueck;
  // scheitert der Sofort-Versuch, laeuft die normale Progression
  // weiter. Rufende Pfade: OS-Netzwerk-Signal, App-Resume.
  void _triggerImmediateReconnect({required String reason}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnecting = false;
    _reconnectDueAt = null;
    notifyListeners();
    // Keine _scheduleReconnect()-Rekursion: direkt verbinden.
    () async {
      await connectAndLoad();
    }();
  }

  @override
  void dispose() {
    _netSub?.cancel();
    _stopPing();
    _stopStatusSub();
    _stopWatchdog();
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
