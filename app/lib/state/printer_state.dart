import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../net/elegoo_cc2_client.dart';

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

  DiscoveryInfo? _discovery;
  CanvasConnection _state = CanvasConnection.disconnected;
  String? _lastError;
  List<CanvasSlot> _slots = const [];
  int _trayAssignmentForTool0 = 3; // Default A4 (RAPID PLA+ beim Testdrucker)

  String? get ip => prefs.getString(_kIp);
  String? get sn => prefs.getString(_kSn);
  DiscoveryInfo? get discovery => _discovery;
  CanvasConnection get connection => _state;
  String? get lastError => _lastError;
  List<CanvasSlot> get slots => _slots;
  int get trayAssignmentForTool0 => _trayAssignmentForTool0;
  ElegooCc2Client get client => _client;

  Future<bool> hasAccessCode() async {
    final c = await secure.read(key: _kAccessCode);
    return c != null && c.isNotEmpty;
  }

  // Pairing: IP + Access-Code werden hier bekannt gemacht. Access-Code
  // wandert sofort in secure storage, Rohwert wird nicht gelogged.
  Future<void> savePairing({required String ip, required String accessCode}) async {
    await prefs.setString(_kIp, ip);
    await secure.write(key: _kAccessCode, value: accessCode);
    notifyListeners();
  }

  Future<void> clearPairing() async {
    await prefs.remove(_kIp);
    await prefs.remove(_kSn);
    await secure.delete(key: _kAccessCode);
    _discovery = null;
    _state = CanvasConnection.disconnected;
    _slots = const [];
    _lastError = null;
    notifyListeners();
  }

  void setTrayAssignmentForTool0(int trayId) {
    _trayAssignmentForTool0 = trayId;
    notifyListeners();
  }

  // Fuehrt Discovery + Register + Canvas-Status in einem Schritt aus.
  // Fehler aktualisieren _lastError + _state statt zu throw-en, damit
  // die UI sauber reagieren kann.
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
      notifyListeners();
    } on ElegooAuthException catch (e) {
      _state = CanvasConnection.authError;
      _lastError = e.message;
      notifyListeners();
    } on ElegooNetworkException catch (e) {
      _state = CanvasConnection.networkError;
      _lastError = e.message;
      notifyListeners();
    } on SocketException catch (e) {
      _state = CanvasConnection.networkError;
      _lastError = 'Netzwerk: ${e.message}';
      notifyListeners();
    } catch (e) {
      _state = CanvasConnection.networkError;
      _lastError = e.toString();
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

  @override
  void dispose() {
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
