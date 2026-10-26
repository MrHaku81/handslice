import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'bounds_check.dart';

// Fehler aus der handslice-cli. `killedBySignal=true` bedeutet,
// dass der Prozess per Signal beendet wurde – auf Android der
// LMK/OOM-Killer bei zu wenig Speicher (siehe docs/blockers.md).
class SliceProcessException implements Exception {
  SliceProcessException({
    required this.exitCode,
    required this.killedBySignal,
    required this.stderr,
    required this.args,
    required this.binary,
  });
  final int exitCode;
  final bool killedBySignal;
  final String stderr;
  final List<String> args;
  final String binary;

  @override
  String toString() =>
      'SliceProcessException(exit=$exitCode killedBySignal=$killedBySignal): $stderr';
}

// Slice-Ergebnis. Spiegelt das JSON wider, das die CLI auf stdout
// ausgibt (siehe handslice-cli.cpp emit_statistics).
class SliceResult {
  SliceResult({
    required this.gcodePath,
    required this.sizeBytes,
    required this.layerCount,
    required this.estimatedSeconds,
    required this.estimatedTimeFmt,
    required this.filamentUsedMm,
    required this.filamentWeightG,
  });

  final String gcodePath;
  final int sizeBytes;
  final int layerCount;
  final double estimatedSeconds;
  final String estimatedTimeFmt;
  final double filamentUsedMm;
  final double filamentWeightG;
}

enum BedType {
  texturedA, // Orca btPTE
  smoothB,   // Orca btPEI
}

extension BedTypeFlag on BedType {
  String get cliArg => switch (this) {
        BedType.texturedA => 'A',
        BedType.smoothB => 'B',
      };
}

// Kapselt den Aufruf von libhandslice_cli.so (CLI-Binary im
// nativeLibraryDir) + die Erstbefuellung der Profile.
//
// Ablauf:
//  1. init() ermittelt binaryPath (ueber MethodChannel) und
//     stellt sicher, dass die Profile unter supportDir/profiles
//     liegen (einmaliges Entpacken aus dem Flutter-AssetBundle).
//  2. slice() ruft die CLI per Process.run auf und parst die
//     Stats-JSON-Ausgabe.
class SlicerService {
  SlicerService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('dev.handslice.handslice/engine');

  final MethodChannel _channel;

  String? _binaryPath;
  String? _resourcesDir;

  bool get isReady => _binaryPath != null && _resourcesDir != null;

  // Machine-Profil-Pfad fuer den Bounds-Check. Oeffentlich, damit die
  // UI das Profil fuer BoundsRect laden kann, ohne die Pfade erneut
  // zusammenzusetzen.
  String get machineProfilePath =>
      '${_resourcesDir!}/profiles/Elegoo/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json';

  Future<BoundsRect> loadBounds() async {
    final f = await File(machineProfilePath).readAsString();
    return boundsFromProfile(jsonDecode(f) as Map<String, dynamic>);
  }

  // Fuer Tests injizierbar. Produktion ruft Platform-Channel + Asset-Bundle.
  Future<void> init({
    String? binaryPathOverride,
    String? resourcesDirOverride,
  }) async {
    if (binaryPathOverride != null) {
      _binaryPath = binaryPathOverride;
    } else {
      final nativeDir = await _channel.invokeMethod<String>('nativeLibraryDir');
      if (nativeDir == null) {
        throw StateError('nativeLibraryDir ist null – Platform-Channel laeuft nicht');
      }
      _binaryPath = '$nativeDir/libhandslice_cli.so';
    }

    if (resourcesDirOverride != null) {
      _resourcesDir = resourcesDirOverride;
    } else {
      _resourcesDir = await _extractBundledProfiles();
    }
  }

  // Entpackt die Profile einmalig aus dem AssetBundle in
  // supportDir/profiles und liefert supportDir (der Pfad, den die
  // CLI als --resources erwartet; das Unterverzeichnis 'profiles/'
  // wird vom Resource-Index selbststaendig gefunden).
  Future<String> _extractBundledProfiles() async {
    final supportDir = await getApplicationSupportDirectory();
    // Manifest aus den AssetBundle-Deklarationen – muss zu pubspec.yaml
    // passen. Alternative waere AssetManifest.json zur Laufzeit zu
    // lesen; wir listen bewusst explizit, damit die Minimum-Menge
    // sichtbar bleibt.
    const assetFiles = <String>[
      'assets/profiles/Elegoo/machine/fdm_machine_common.json',
      'assets/profiles/Elegoo/machine/fdm_elegoo_3dp_001_common.json',
      'assets/profiles/Elegoo/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json',
      'assets/profiles/Elegoo/process/fdm_process_common.json',
      'assets/profiles/Elegoo/process/fdm_process_elegoo_common.json',
      'assets/profiles/Elegoo/process/fdm_process_elegoo_04020.json',
      'assets/profiles/Elegoo/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json',
      'assets/profiles/Elegoo/filament/fdm_filament_common.json',
      'assets/profiles/Elegoo/filament/fdm_filament_pla.json',
      'assets/profiles/Elegoo/filament/BASE/Elegoo PLA @base.json',
      'assets/profiles/Elegoo/filament/ECC2/Elegoo PLA @ECC2.json',
    ];
    for (final asset in assetFiles) {
      // Zielpfad spiegelt die 'profiles/'-Hierarchie 1:1.
      final rel = asset.replaceFirst('assets/', '');
      final target = File('${supportDir.path}/$rel');
      if (await target.exists()) continue;
      await target.parent.create(recursive: true);
      final data = await rootBundle.load(asset);
      await target.writeAsBytes(data.buffer.asUint8List());
    }
    return supportDir.path;
  }

  Future<SliceResult> slice({
    required String modelPath,
    required BedType bedType,
    required String outputPath,
    double zOffsetMm = 0.0,
    // Standardverhalten: Modell wie Orca-GUI auf die Platte setzen –
    // XY mittig auf das Druckbett (ModelObject::center_around_origin
    // + Instance-Offset auf bed_center) und min_z=0 (ensure_on_bed).
    // Mit `noCenter: true` bleibt die STL-Position erhalten; das wird
    // nur fuer den Reference-Test gebraucht, dessen Modell bereits
    // vorzentriert auf (128,128,0) sitzt.
    bool noCenter = false,
    void Function(Process proc)? onProcessStarted,
    // Phase 4.3: Nutzer-Overrides als key→value-Serialisierungen,
    // werden nach der Profil-Chain + --bed-type / --z-offset
    // angewendet. Leer → Flag wird weggelassen, G-Code bleibt
    // byte-gleich zum Baseline.
    Map<String, String> overrides = const {},
    // Phase 4.4: optionaler Pfad zum Filamentprofil
    // (relativ zum Resources-Verzeichnis, ohne fuehrenden Slash),
    // z. B. "profiles/Elegoo/filament/ECC2/Elegoo PLA PRO @ECC2.json".
    // Leer = Default "Elegoo PLA @ECC2.json" (vorige Phase).
    String? filamentProfileRelative,
  }) async {
    if (!isReady) {
      throw StateError('SlicerService.init() wurde nicht aufgerufen');
    }
    final resources = _resourcesDir!;
    final profiles = '$resources/profiles/Elegoo';
    // --z-offset nur mitgeben, wenn nicht genau 0 (vermeidet unnoetige
    // Config-Overrides und haelt die CLI-Zeile sauber).
    final bool applyZ = zOffsetMm.abs() > 1e-9;
    final filamentPath = (filamentProfileRelative == null ||
            filamentProfileRelative.isEmpty)
        ? '$profiles/filament/ECC2/Elegoo PLA @ECC2.json'
        : '$resources/$filamentProfileRelative';
    final args = <String>[
      '--machine', '$profiles/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json',
      '--process', '$profiles/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json',
      '--filament', filamentPath,
      '--resources', resources,
      '--output', outputPath,
      '--bed-type', bedType.cliArg,
      if (applyZ) ...['--z-offset', zOffsetMm.toStringAsFixed(3)],
      if (overrides.isNotEmpty)
        ...['--overrides', jsonEncode(overrides)],
      '--quiet',
      if (noCenter) '--no-center',
      modelPath,
    ];

    // Process.start statt Process.run – gibt uns ein Handle fuer Cancel
    // und bleibt waehrenddessen fuer Progress-UI nicht blockierend. UI
    // bleibt reaktiv, weil das await nur auf die Future wartet.
    final proc = await Process.start(_binaryPath!, args);
    if (onProcessStarted != null) onProcessStarted(proc);
    // stdout/stderr parallel sammeln (sonst kann die Pipe volllaufen).
    final stdoutFut = proc.stdout.transform(utf8.decoder).join();
    final stderrFut = proc.stderr.transform(utf8.decoder).join();
    final exitCode  = await proc.exitCode;
    final stdoutStr = await stdoutFut;
    final stderrStr = await stderrFut;
    if (exitCode != 0) {
      // Signal-getoetete Prozesse (OOM-Killer: SIGKILL=9 → Dart-Exit
      // negativ, Linux-Shell 128+signal) klar unterscheiden – die App
      // soll das als "vom System beendet" statt als Slicer-Fehler
      // melden koennen.
      final killed = exitCode < 0 || exitCode == 137 || exitCode == 143;
      throw SliceProcessException(
        exitCode: exitCode,
        killedBySignal: killed,
        stderr: stderrStr,
        args: args,
        binary: _binaryPath!,
      );
    }
    final stats = jsonDecode(stdoutStr) as Map<String, dynamic>;
    final out = File(outputPath);
    return SliceResult(
      gcodePath: outputPath,
      sizeBytes: await out.length(),
      layerCount: _countLayers(stats),
      estimatedSeconds: (stats['estimated_time_s'] as num?)?.toDouble() ?? 0,
      estimatedTimeFmt: stats['estimated_time_fmt'] as String? ?? '-',
      filamentUsedMm: (stats['total_filament_used_mm'] as num?)?.toDouble() ?? 0,
      filamentWeightG: (stats['total_filament_weight_g'] as num?)?.toDouble() ?? 0,
    );
  }

  int _countLayers(Map<String, dynamic> _) {
    // Die handslice-cli JSON-Ausgabe liefert aktuell keinen expliziten
    // layer_count-Key – wir koennten den G-Code grep-en, aber fuer das
    // UI genuegt der Zeitwert. Fuer M2 geben wir 0 zurueck und ziehen
    // die Layer-Zahl nach, wenn der CLI das Feld expandiert.
    return 0;
  }
}
