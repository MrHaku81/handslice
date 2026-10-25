import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/bounds_check.dart';
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
  List<BoundsViolation> _boundsViolations = const [];

  // Keys fuer die z-offset-Persistenz
  static const _kZOffsetA = 'project.z_offset.A_mm';
  static const _kZOffsetB = 'project.z_offset.B_mm';

  // Projekt-Vorgabe: ±0.50 mm, Schritte 0.01 mm. Grenzen hier zentral,
  // damit UI und Tests dieselbe Quelle nutzen.
  static const double zOffsetMin = -0.50;
  static const double zOffsetMax = 0.50;
  static const double zOffsetStep = 0.01;

  String? get modelPath => _modelPath;
  BedType get bedType => _bedType;
  SliceResult? get lastSlice => _lastSlice;
  String? get lastError => _lastError;
  bool get isSlicing => _slicing;
  List<BoundsViolation> get boundsViolations => _boundsViolations;
  bool get boundsOk =>
      _lastSlice != null && _boundsViolations.isEmpty;

  double zOffsetFor(BedType b) {
    final k = b == BedType.texturedA ? _kZOffsetA : _kZOffsetB;
    return _prefs.getDouble(k) ?? (b == BedType.texturedA ? -0.030 : 0.015);
  }

  Future<void> setZOffsetFor(BedType b, double mm) async {
    final k = b == BedType.texturedA ? _kZOffsetA : _kZOffsetB;
    final clamped = mm.clamp(zOffsetMin, zOffsetMax);
    // auf 0.01-mm-Raster quantisieren (vermeidet Float-Drift bei
    // wiederholtem +/- in UI-Schritten)
    final q = (clamped * 100).roundToDouble() / 100.0;
    await _prefs.setDouble(k, q);
    notifyListeners();
  }

  Future<void> nudgeZOffset(BedType b, double deltaMm) async {
    final current = zOffsetFor(b);
    await setZOffsetFor(b, current + deltaMm);
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
    _boundsViolations = const [];
    notifyListeners();
    try {
      final r = await slicer.slice(
        modelPath: _modelPath!,
        bedType: _bedType,
        outputPath: outputPath,
        zOffsetMm: zOffsetFor(_bedType),
      );
      _lastSlice = r;
      // Grenztest sofort nach dem Slice. Uploads werden spaeter
      // blockiert, wenn Verletzungen vorliegen (siehe PrintScreen,
      // M3-Upload-Logik).
      try {
        final bounds = await slicer.loadBounds();
        _boundsViolations = await checkGcodeFile(outputPath, bounds);
      } catch (e) {
        // Bounds-Check-Fehler wird nicht als Slice-Fehler gemeldet,
        // aber in den Violations-Count als Platzhalter sichtbar.
        _boundsViolations = [
          BoundsViolation(
              lineNo: 0,
              axis: 'XY',
              gcode: 'bounds-check selbst gescheitert: $e',
              x: 0, y: 0, z: 0)
        ];
      }
    } catch (e) {
      _lastError = e.toString();
      _lastSlice = null;
    } finally {
      _slicing = false;
      notifyListeners();
    }
  }
}
