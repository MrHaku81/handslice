import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/slicer.dart';

// Zentraler Zustand des aktiven Projekts. Nicht persistent (ausser
// den z_offsets pro Plattenseite), weil die eigentliche Session beim
// App-Neustart neu angelegt wird.
class ProjectState extends ChangeNotifier {
  ProjectState(this._prefs);

  final SharedPreferences _prefs;

  String? _modelPath;
  BedType _bedType = BedType.texturedA;
  SliceResult? _lastSlice;
  String? _lastError;
  bool _slicing = false;

  // Keys fuer die z-offset-Persistenz
  static const _kZOffsetA = 'project.z_offset.A_mm';
  static const _kZOffsetB = 'project.z_offset.B_mm';

  String? get modelPath => _modelPath;
  BedType get bedType => _bedType;
  SliceResult? get lastSlice => _lastSlice;
  String? get lastError => _lastError;
  bool get isSlicing => _slicing;

  double zOffsetFor(BedType b) {
    final k = b == BedType.texturedA ? _kZOffsetA : _kZOffsetB;
    return _prefs.getDouble(k) ?? (b == BedType.texturedA ? -0.030 : 0.015);
  }

  Future<void> setZOffsetFor(BedType b, double mm) async {
    final k = b == BedType.texturedA ? _kZOffsetA : _kZOffsetB;
    await _prefs.setDouble(k, mm);
    notifyListeners();
  }

  void setModel(String path) {
    _modelPath = path;
    _lastSlice = null;
    _lastError = null;
    notifyListeners();
  }

  void setBedType(BedType b) {
    _bedType = b;
    notifyListeners();
  }

  Future<void> slice(SlicerService slicer, String outputPath) async {
    if (_modelPath == null) return;
    _slicing = true;
    _lastError = null;
    notifyListeners();
    try {
      final r = await slicer.slice(
        modelPath: _modelPath!,
        bedType: _bedType,
        outputPath: outputPath,
      );
      _lastSlice = r;
    } catch (e) {
      _lastError = e.toString();
      _lastSlice = null;
    } finally {
      _slicing = false;
      notifyListeners();
    }
  }
}
