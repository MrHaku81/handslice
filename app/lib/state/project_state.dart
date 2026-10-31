import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/bounds_check.dart';
import '../engine/gcode_parser.dart';
import '../engine/slicer.dart';
import '../engine/toolpath_parser.dart';
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

  // Pflicht 7a — plate-view preview mesh (.hspm). Built in the
  // background by the arm64 CLI (--no-slice + --export-preview-mesh)
  // after a model is picked, cached per (modelPath, mtime, target)
  // so re-opening the same file is instant.
  // Pflicht 7b — parsed g-code geometry for the layer view.
  // Lives only in RAM (the g-code file on disk is the source of
  // truth), rebuilt after every successful slice.
  GcodeGeometry? _sliceGeometry;
  bool _sliceGeometryBuilding = false;
  String? _sliceGeometryError;
  GcodeProgress? _sliceGeometryProgress;
  GcodeGeometry? get sliceGeometry => _sliceGeometry;
  bool get sliceGeometryBuilding => _sliceGeometryBuilding;
  String? get sliceGeometryError => _sliceGeometryError;
  GcodeProgress? get sliceGeometryProgress => _sliceGeometryProgress;

  // Pflicht 7c — toolpaths from the CLI's `--export-toolpaths`
  // artefact. Preferred over `_sliceGeometry` by the UI: it is
  // Orca's own GCodeProcessor output, so the roles, widths and
  // colours line up with the desktop.
  Toolpaths? _sliceToolpaths;
  String? _sliceToolpathsPath;
  Toolpaths? get sliceToolpaths => _sliceToolpaths;

  String? _previewMeshPath;
  // Raw-RGBA 'HSPB' thumbnail built next to the HSPM, used by the
  // 3D view's fallback image when flutter_scene cannot start.
  String? _previewThumbnailPath;
  bool _previewMeshBuilding = false;
  String? _previewMeshError;
  int _previewSimplifyTarget = 300000;   // overridden by device RAM at init
  Process? _previewProc;

  String? get previewMeshPath => _previewMeshPath;
  String? get previewThumbnailPath => _previewThumbnailPath;
  bool get previewMeshBuilding => _previewMeshBuilding;
  String? get previewMeshError => _previewMeshError;
  int get previewSimplifyTarget => _previewSimplifyTarget;

  void setPreviewSimplifyTarget(int target) {
    if (target == _previewSimplifyTarget) return;
    _previewSimplifyTarget = target;
    notifyListeners();
  }

  // Keys fuer die z-offset-Persistenz
  static const _kZOffsetA = 'project.z_offset.A_mm';
  static const _kZOffsetB = 'project.z_offset.B_mm';
  // Phase 5b-Nacharbeit: zuletzt geladenes User-Profil (slug) persistent.
  // null/leer = Orca-Standard.
  static const _kActiveProfile = 'project.active_profile_slug';
  // Phase 4.4-Nacharbeit: pro Fach (A1..A4, Index 0..3) der slug des
  // zuletzt gewaehlten Filament-Profils. null = Material-Basisprofil
  // (keine zusaetzlichen Overrides aus einem User-Profil).
  static String _kFilamentActiveProfile(int tray) =>
      'project.filament_profile_slug.A${tray + 1}';

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

  /// Pro Fach: slug des aktiven Filament-Profils (null = Basisprofil).
  String? filamentActiveProfileSlug(int tray) {
    assert(tray >= 0 && tray < 4);
    return _prefs.getString(_kFilamentActiveProfile(tray));
  }

  Future<void> setFilamentActiveProfileSlug(int tray, String? slug) async {
    assert(tray >= 0 && tray < 4);
    final k = _kFilamentActiveProfile(tray);
    if (slug == null || slug.isEmpty) {
      await _prefs.remove(k);
    } else {
      await _prefs.setString(k, slug);
    }
    notifyListeners();
  }

  void setModel(String path) {
    _modelPath = path;
    _lastSlice = null;
    _lastError = null;
    _previewMeshPath = null;
    _previewThumbnailPath = null;
    _previewMeshError = null;
    _sliceGeometry = null;
    _sliceGeometryError = null;
    _sliceGeometryProgress = null;
    _sliceToolpaths = null;
    _sliceToolpathsPath = null;
    notifyListeners();
  }

  // Pflicht 7b/7c — build the layer-view input from the last
  // slice: prefer the HSPT (`_sliceToolpathsPath`) written by
  // `--export-toolpaths` on the way out of the slicer; fall back
  // to the Dart g-code parser if the HSPT is missing.
  Future<void> parseSliceGeometry() async {
    final slice = _lastSlice;
    if (slice == null) return;
    if (_sliceGeometryBuilding) return;
    _sliceGeometryBuilding = true;
    _sliceGeometryError = null;
    _sliceGeometry = null;
    _sliceToolpaths = null;
    _sliceGeometryProgress = null;
    notifyListeners();
    // Try the CLI-produced HSPT first; this is the Orca-source
    // path and matches the desktop viewer.
    final tp = _sliceToolpathsPath;
    if (tp != null && await File(tp).exists()) {
      try {
        _sliceToolpaths = await loadToolpaths(tp);
      } catch (e) {
        // Fall through to the g-code parser below so the layer
        // view still shows something; keep the error for a UI
        // hint.
        _sliceGeometryError = 'toolpaths load failed: $e';
      }
    }
    if (_sliceToolpaths == null) {
      try {
        final g = await parseGcode(slice.gcodePath, onProgress: (p) {
          _sliceGeometryProgress = p;
          notifyListeners();
        });
        _sliceGeometry = g;
      } catch (e) {
        _sliceGeometryError = e.toString();
      }
    }
    _sliceGeometryBuilding = false;
    notifyListeners();
  }

  // Pflicht 7a — fire-and-forget preview-mesh build. Caller is the
  // project screen right after setModel(). If a cached HSPM for
  // (path, mtime, simplifyTarget) is already on disk, we attach it
  // and return without touching the CLI. The returned future
  // resolves when the build has either succeeded, failed, or hit
  // the cache.
  Future<void> ensurePreviewMesh(SlicerService slicer) async {
    final path = _modelPath;
    if (path == null) return;
    if (_previewMeshBuilding) return;
    final file = File(path);
    if (!await file.exists()) return;
    final stat = await file.stat();
    final key = sha256
        .convert(utf8.encode(
            '$path|${stat.modified.microsecondsSinceEpoch}|$_previewSimplifyTarget'))
        .toString()
        .substring(0, 16);
    final cacheDir = Directory(
        '${(await getApplicationCacheDirectory()).path}/preview-meshes');
    await cacheDir.create(recursive: true);
    final cachePath = '${cacheDir.path}/$key.hspm';
    final thumbCachePath = '${cacheDir.path}/$key.hspb';
    if (await File(cachePath).exists()) {
      _previewMeshPath = cachePath;
      _previewThumbnailPath =
          await File(thumbCachePath).exists() ? thumbCachePath : null;
      _previewMeshError = null;
      notifyListeners();
      return;
    }
    _previewMeshBuilding = true;
    _previewMeshError = null;
    _previewMeshPath = null;
    _previewThumbnailPath = null;
    notifyListeners();
    try {
      await slicer.exportPreviewMesh(
        modelPath: path,
        bedType: _bedType,
        outputHspmPath: cachePath,
        simplifyTarget: _previewSimplifyTarget,
        outputThumbnailPath: thumbCachePath,
        onProcessStarted: (p) { _previewProc = p; },
      );
      // Confirm the model/bed/target has not changed under us
      // while the CLI ran. If the user picked a different model
      // mid-build the result is for the old one; drop it.
      if (_modelPath == path) {
        _previewMeshPath = cachePath;
        if (await File(thumbCachePath).exists()) {
          _previewThumbnailPath = thumbCachePath;
        }
      } else {
        try { await File(cachePath).delete(); } catch (_) {}
        try { await File(thumbCachePath).delete(); } catch (_) {}
      }
    } on SliceProcessException catch (e) {
      _previewMeshPath = null;
      _previewMeshError = e.killedBySignal
          ? 'preview.oom'
          : 'preview.error:${e.exitCode}:${e.stderr.trim()}';
    } catch (e) {
      _previewMeshPath = null;
      _previewMeshError = e.toString();
    } finally {
      _previewMeshBuilding = false;
      _previewProc = null;
      notifyListeners();
    }
  }

  Future<void> cancelPreviewMesh() async {
    final p = _previewProc;
    if (p != null) p.kill();
  }

  void setBedType(BedType b) {
    _bedType = b;
    notifyListeners();
  }

  Future<void> slice(SlicerService slicer, String outputPath,
      {SettingsOverrides? overrides,
      SettingsOverrides? filamentOverrides,
      // M9-Vorstufe: aus dem gewaehlten CANVAS-Fach abgeleitete
      // Overrides (Farbe/Material), damit der G-Code die Fach-
      // Farbe traegt statt des Profil-Defaults. Caller baut diese
      // Map in `ProjectScreen._slice()` zusammen, siehe
      // docs/networking-cc2.md Abschnitt "M9 – slot colour as
      // slice override". Werte als Strings serialisiert (CLI
      // --overrides erlaubt keine Arrays).
      Map<String, String> slotOverrides = const {},
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
        // slotOverrides zuletzt – falls der Nutzer explizit
        // filament_colour via FilamentOverrides setzt, muss der
        // Nutzerwert gewinnen; wir reichen also die Fach-Werte
        // als niedrigere Prioritaet und schreiben sie NUR dann
        // in `merged`, wenn der Key noch nicht gesetzt ist.
      };
      for (final e in slotOverrides.entries) {
        merged.putIfAbsent(e.key, () => e.value);
      }
      _sliceToolpathsPath = '$outputPath.hspt';
      final r = await slicer.slice(
        modelPath: _modelPath!,
        bedType: _bedType,
        outputPath: outputPath,
        outputToolpathsPath: _sliceToolpathsPath,
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
      // Pflicht 7b: start parsing the g-code into the layer-view
      // geometry in the background. Fire-and-forget; the UI
      // reacts via `sliceGeometryBuilding` / progress updates.
      // ignore: discarded_futures
      parseSliceGeometry();
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
