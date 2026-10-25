import 'package:flutter/foundation.dart';

/// Projekt-weite Override-Werte, die der Nutzer gegenueber den
/// Profil-Defaults gesetzt hat. Pro Options-Key genau ein serialisierter
/// String-Wert (so, wie Orca ihn auch im G-Code-Header schreiben wuerde);
/// die konkrete Typ-Konvertierung passiert in den Bedienelement-Widgets
/// und beim CLI-Build in Phase 4.3.
///
/// Vorerst nur im Speicher – Persistenz pro Profil kommt in 4.3
/// ("Als Profil speichern").
class SettingsOverrides extends ChangeNotifier {
  final Map<String, String> _overrides = {};

  Map<String, String> get all => Map.unmodifiable(_overrides);
  bool get isEmpty => _overrides.isEmpty;
  int  get count   => _overrides.length;

  bool has(String key) => _overrides.containsKey(key);
  String? get(String key) => _overrides[key];

  void set(String key, String value) {
    _overrides[key] = value;
    notifyListeners();
  }

  void reset(String key) {
    if (_overrides.remove(key) != null) notifyListeners();
  }

  void clearAll() {
    if (_overrides.isNotEmpty) {
      _overrides.clear();
      notifyListeners();
    }
  }
}
