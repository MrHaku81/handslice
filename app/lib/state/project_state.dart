import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/bounds_check.dart';
import '../engine/slicer.dart';
import '../settings/settings_overrides.dart';

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
  bool _cancelRequested = false;
  Process? _activeProc;
  DateTime? _sliceStartedAt;
  List<BoundsViolation> _boundsViolations = const [];

  // Keys fuer die z-offset-Persistenz
  static const _kZOffsetA = 'project.z_offset.A_mm';
  static const _kZOffsetB = 'project.z_offset.B_mm';
  // Phase 5b-Nacharbeit: zuletzt geladenes User-Profil (slug) persistent.
  // null/leer = Orca-Standard.
  static const _kActiveProfile = 'project.active_profile_slug';

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
  bool get cancelRequested => _cancelRequested;
  DateTime? get sliceStartedAt => _sliceStartedAt;
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

  // --- aktives User-Profil (null = Orca-Standard) ---
  String? get activeProfileSlug => _prefs.getString(_kActiveProfile);

  Future<void> setActiveProfileSlug(String? slug) async {
    if (slug == null || slug.isEmpty) {
      await _prefs.remove(_kActiveProfile);
    } else {
      await _prefs.setString(_kActiveProfile, slug);
    }
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

  Future<void> slice(SlicerService slicer, String outputPath,
      {SettingsOverrides? overrides,
      SettingsOverrides? filamentOverrides,
      String? filamentProfileRelative}) async {
    if (_modelPath == null) return;
    _slicing = true;
    _cancelRequested = false;
    _activeProc = null;
    _sliceStartedAt = DateTime.now();
    _lastError = null;
    _boundsViolations = const [];
    notifyListeners();
    try {
      // Prozess- und Filament-Overrides mergen (disjunkte Key-Mengen,
      // Phase-4-Schema trennt die beiden Bereiche sauber). Prozess-
      // Overrides zuerst, Filament-Overrides setzen die filament-
      // spezifischen Felder.
      final merged = <String, String>{
        ...overrides?.all ?? const {},
        ...filamentOverrides?.all ?? const {},
      };
      final r = await slicer.slice(
        modelPath: _modelPath!,
        bedType: _bedType,
        outputPath: outputPath,
        zOffsetMm: zOffsetFor(_bedType),
        overrides: merged,
        filamentProfileRelative: filamentProfileRelative,
        onProcessStarted: (p) {
          _activeProc = p;
          // Falls Cancel vor dem Hochfahren kam: direkt beenden.
          if (_cancelRequested) p.kill();
        },
      );
      _lastSlice = r;
      // Grenztest sofort nach dem Slice. Uploads werden spaeter
      // blockiert, wenn Verletzungen vorliegen (siehe PrintScreen,
      // M3-Upload-Logik).
      try {
        final bounds = await slicer.loadBounds();
        _boundsViolations = await checkGcodeFile(outputPath, bounds);
      } catch (e) {
        _boundsViolations = [
          BoundsViolation(
              lineNo: 0,
              axis: 'XY',
              gcode: 'bounds-check selbst gescheitert: $e',
              x: 0, y: 0, z: 0)
        ];
      }
    } on SliceProcessException catch (e) {
      // Vom Nutzer abgebrochen: nicht als Fehler melden.
      if (_cancelRequested) {
        _lastError = null;
      } else if (e.killedBySignal) {
        // Signal-Kill ohne Cancel-Request: fast immer der LMK/OOM-
        // Killer auf Android bei grossen Modellen.
        _lastError = 'slice.oom';
      } else {
        _lastError = 'slice.error:${e.exitCode}:${e.stderr.trim()}';
      }
      _lastSlice = null;
    } catch (e) {
      _lastError = e.toString();
      _lastSlice = null;
    } finally {
      _slicing = false;
      _activeProc = null;
      notifyListeners();
    }
  }

  /// Bricht einen laufenden Slice ab. Der CLI-Prozess wird mit SIGTERM
  /// beendet und sein Output-Pfad geloescht, damit keine
  /// Halbfertig-G-Code-Datei zurueckbleibt. Idempotent.
  Future<void> cancelSlice({String? cleanupOutputPath}) async {
    if (!_slicing) return;
    _cancelRequested = true;
    notifyListeners();
    final p = _activeProc;
    if (p != null) p.kill();
    if (cleanupOutputPath != null) {
      try {
        final f = File(cleanupOutputPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}
