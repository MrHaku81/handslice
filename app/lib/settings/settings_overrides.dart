import 'package:flutter/foundation.dart';

/// Nutzer-Overrides pro Options-Key. Pro Key genau ein serialisierter
/// String-Wert (so, wie Orca ihn auch im G-Code-Header schreiben wuerde).
///
/// Baseline-Logik (Phase-4.4-Nacharbeit, Orca-Verhalten):
/// Ist ein User-Profil geladen, zaehlen UI-Counter und ↺-Marker nur die
/// Abweichungen gegenueber dem *geladenen Profil*, nicht gegenueber dem
/// Orca-Basisprofil. Dafuer kennt die Instanz einen Baseline-Snapshot
/// (= `profile.overrides` zum Zeitpunkt des Ladens). Ist keine Baseline
/// gesetzt (Orca-Standard aktiv), zaehlt jeder gesetzte Override als
/// Abweichung – wie vorher.
///
/// Reset setzt den Key auf den Baseline-Wert zurueck (falls vorhanden)
/// bzw. loescht ihn (zurueck auf Orca-Default).
class SettingsOverrides extends ChangeNotifier {
  final Map<String, String> _overrides = {};
  Map<String, String> _baseline = const {};

  Map<String, String> get all => Map.unmodifiable(_overrides);
  Map<String, String> get baseline => Map.unmodifiable(_baseline);

  /// true, wenn keine Abweichung gegenueber der aktiven Baseline
  /// existiert (nicht: wenn `_overrides` leer ist).
  bool get isEmpty => count == 0;

  /// Anzahl Keys, die vom Baseline-Wert abweichen. Enthaelt auch
  /// Baseline-Keys, die der Nutzer absichtlich geloescht hat
  /// (Reset auf Orca-Default); das ist eine Abweichung vom Profil.
  int get count {
    if (_baseline.isEmpty) return _overrides.length;
    var c = 0;
    for (final e in _overrides.entries) {
      if (_baseline[e.key] != e.value) c++;
    }
    for (final k in _baseline.keys) {
      if (!_overrides.containsKey(k)) c++;
    }
    return c;
  }

  /// true, wenn der Key gesetzt ist UND vom Baseline-Wert abweicht
  /// (bzw. wenn kein Baseline-Wert existiert, aber ein Override steht).
  bool has(String key) {
    if (!_overrides.containsKey(key)) return false;
    if (_baseline.isEmpty) return true;
    return _baseline[key] != _overrides[key];
  }

  String? get(String key) => _overrides[key];

  void set(String key, String value) {
    _overrides[key] = value;
    notifyListeners();
  }

  /// Setzt den Key auf den Baseline-Wert zurueck. Fehlt eine Baseline
  /// oder enthaelt sie den Key nicht, wird der Override geloescht
  /// (= zurueck auf Orca-Default).
  void reset(String key) {
    final baseVal = _baseline[key];
    final before = _overrides[key];
    if (baseVal == null) {
      if (_overrides.remove(key) != null) notifyListeners();
    } else {
      _overrides[key] = baseVal;
      if (before != baseVal) notifyListeners();
    }
  }

  void clearAll() {
    if (_overrides.isNotEmpty) {
      _overrides.clear();
      notifyListeners();
    }
  }

  /// Setzt die aktive Baseline (= geladenes User-Profil). Leer bedeutet
  /// "kein Profil geladen, Orca-Standard als Vergleich". Loescht
  /// bestehende Overrides nicht automatisch – der Aufrufer entscheidet,
  /// ob vorher `clearAll` passieren soll (so, wie `applyProfile` es tut).
  void setBaseline(Map<String, String> b) {
    _baseline = Map.of(b);
    notifyListeners();
  }

  /// Overrides komplett auf das Profil ausrichten: Baseline setzen,
  /// bisherige Werte verwerfen, Profil-Werte uebernehmen. Nach diesem
  /// Aufruf ist `count == 0`.
  void applyProfile(Map<String, String> profileOverrides) {
    _baseline = Map.of(profileOverrides);
    _overrides
      ..clear()
      ..addAll(profileOverrides);
    notifyListeners();
  }

  /// Baseline zuruecksetzen (= Orca-Standard aktiv) und Overrides
  /// loeschen. Entspricht "Profil-Picker → Orca-Standard".
  void clearProfile() {
    final had = _baseline.isNotEmpty || _overrides.isNotEmpty;
    _baseline = const {};
    _overrides.clear();
    if (had) notifyListeners();
  }
}
