import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_overrides.dart';

/// Pro CANVAS-Fach (A1..A4, tray_id 0..3) eine eigene
/// Overrides-Map. Persistent in SharedPreferences
/// (`filament.overrides.A<n>`). Phase 4.4.
class FilamentOverrides extends ChangeNotifier {
  FilamentOverrides(this._prefs) {
    for (int tray = 0; tray < 4; tray++) {
      final ov = SettingsOverrides();
      final raw = _prefs.getString(_keyFor(tray));
      if (raw != null && raw.isNotEmpty) {
        try {
          final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
          for (final e in map.entries) {
            ov.set(e.key, e.value.toString());
          }
        } catch (_) {
          // defekte Persistenz ignorieren, nicht crashen
        }
      }
      ov.addListener(() {
        _save(tray, ov);
        notifyListeners();
      });
      _byTray[tray] = ov;
    }
  }

  final SharedPreferences _prefs;
  final Map<int, SettingsOverrides> _byTray = {};

  static String _keyFor(int tray) => 'filament.overrides.A${tray + 1}';

  /// Overrides fuer das angegebene Fach (0..3). Garantierte, stabile
  /// Instanz; UI-Code kann sie als Listenable einhaengen.
  SettingsOverrides forTray(int tray) {
    assert(tray >= 0 && tray < 4);
    return _byTray[tray]!;
  }

  int totalCount() =>
      _byTray.values.fold<int>(0, (sum, ov) => sum + ov.count);

  void _save(int tray, SettingsOverrides ov) {
    if (ov.isEmpty) {
      _prefs.remove(_keyFor(tray));
    } else {
      _prefs.setString(_keyFor(tray), jsonEncode(ov.all));
    }
  }
}
