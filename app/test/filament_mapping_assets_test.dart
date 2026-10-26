// Vertragstest Phase 4.4-Nacharbeit: Alle von FilamentMapping
// aufloesbaren Filamentprofil-Dateinamen MUESSEN als Repo-Asset
// unter app/assets/profiles/Elegoo/filament/ECC2/ liegen, sonst
// scheitert der Slice auf dem Geraet mit "Datei nicht gefunden".
//
// Hintergrund: 2026-10-26 Abnahme am Poco – `_extractBundledProfiles`
// extrahierte nur `Elegoo PLA @ECC2.json`, weil die Asset-Liste in
// pubspec.yaml alle anderen Materialien vergessen hatte. Jetzt
// werden die Assets per Verzeichnis eingebunden und ueber das
// AssetManifest extrahiert; dieser Test stellt sicher, dass die
// Mapping-Namen auch wirklich im Verzeichnis existieren.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/settings/filament_mapping.dart';

void main() {
  // Alle Materialkombinationen aus docs/networking-cc2.md und den
  // zusaetzlichen Entscheidungszweigen in FilamentMapping. Erzeugt
  // die genauen Zielnamen, die resolve() liefern koennte.
  const probes = <(String, String)>[
    ('ELEGOO PLA',         'PLA'),
    ('ELEGOO PLA PRO',     'PLA'),
    ('ELEGOO PLA+',        'PLA'),
    ('ELEGOO PLA Matte',   'PLA'),
    ('ELEGOO Rapid PLA+',  'PLA'),
    ('ELEGOO PETG',        'PETG'),
    ('ELEGOO Rapid PETG',  'PETG'),
    ('ELEGOO PETG PRO',    'PETG'),
    ('ELEGOO PETG HF',     'PETG'),
    ('ELEGOO ABS',         'ABS'),
    // Fallbacks: ein unbekanntes PETG und ein voellig unbekanntes
    // Material (PLA-Default) muessen ebenfalls auf vorhandene
    // Asset-Dateinamen zeigen.
    ('MYSTERY PETG BRAND', 'PETG'),
    ('WAS AUCH IMMER',     ''),
  ];

  test('alle FilamentMapping-Zielnamen existieren als Asset-Datei',
      () {
    // Testlauf aus app/, daher relativer Pfad reicht.
    final dir = Directory('assets/profiles/Elegoo/filament/ECC2');
    expect(dir.existsSync(), isTrue,
        reason: 'Asset-Verzeichnis muss im Repo liegen: ${dir.path}');

    final missing = <String>[];
    for (final p in probes) {
      final ref = const FilamentMapping().resolve(
        filamentName: p.$1,
        filamentType: p.$2,
      );
      final f = File('${dir.path}/${ref.assetName}');
      if (!f.existsSync()) {
        missing.add('${p.$1} / ${p.$2} → ${ref.assetName}');
      }
    }
    expect(missing, isEmpty,
        reason: 'Diese Mapping-Zielnamen haben keine Asset-Datei:\n'
            '${missing.join('\n')}');
  });

  test('BASE-Profile fuer alle Material-Familien liegen vor', () {
    // Jedes ECC2-Profil erbt von einer dieser 7 BASE-Dateien.
    // Fehlt eine, scheitert die Preset-Chain beim Slicen trotz
    // vorhandenem ECC2-Profil.
    const needed = <String>[
      'Elegoo PLA @base.json',
      'Elegoo PETG @base.json',
      'Elegoo ABS @base.json',
      'Elegoo ASA @base.json',
      'Elegoo PAHT @base.json',
      'Elegoo PC @base.json',
      'Elegoo TPU @base.json',
    ];
    final base = Directory('assets/profiles/Elegoo/filament/BASE');
    expect(base.existsSync(), isTrue);
    final missing = needed
        .where((n) => !File('${base.path}/$n').existsSync())
        .toList();
    expect(missing, isEmpty,
        reason: 'Fehlende BASE-Dateien: ${missing.join(', ')}');
  });

  test('fdm_filament_* Common-Dateien fuer alle BASE-Inherits', () {
    const needed = <String>[
      'fdm_filament_common.json',
      'fdm_filament_pla.json',
      'fdm_filament_pet.json',
      'fdm_filament_abs.json',
      'fdm_filament_asa.json',
      'fdm_filament_pa.json',
      'fdm_filament_pc.json',
      'fdm_filament_tpu.json',
    ];
    final root = Directory('assets/profiles/Elegoo/filament');
    final missing = needed
        .where((n) => !File('${root.path}/$n').existsSync())
        .toList();
    expect(missing, isEmpty,
        reason: 'Fehlende fdm_filament_* Common-Dateien: '
            '${missing.join(', ')}');
  });
}
