import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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
    bool noCenter = true,
  }) async {
    if (!isReady) {
      throw StateError('SlicerService.init() wurde nicht aufgerufen');
    }
    final resources = _resourcesDir!;
    final profiles = '$resources/profiles/Elegoo';
    final args = <String>[
      '--machine', '$profiles/machine/ECC2/Elegoo Centauri Carbon 2 0.4 nozzle.json',
      '--process', '$profiles/process/ECC2/0.20mm Standard @Elegoo CC2 0.4 nozzle.json',
      '--filament', '$profiles/filament/ECC2/Elegoo PLA @ECC2.json',
      '--resources', resources,
      '--output', outputPath,
      '--bed-type', bedType.cliArg,
      '--quiet',
      if (noCenter) '--no-center',
      modelPath,
    ];

    final proc = await Process.run(
      _binaryPath!,
      args,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (proc.exitCode != 0) {
      throw ProcessException(
        _binaryPath!,
        args,
        'handslice-cli exit ${proc.exitCode}: ${proc.stderr}',
        proc.exitCode,
      );
    }

    final stats = jsonDecode(proc.stdout as String) as Map<String, dynamic>;
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
