import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

// Lade- und Zugriffs-Schicht fuer das in Phase 4.1 erzeugte
// settings-schema.json. Keine Hand-Pflege: Datei kommt aus
// engine/scripts/build_settings_schema.py, das Orca v2.4.2 Tab.cpp +
// PrintConfig + de-Uebersetzungen mechanisch zusammenfuehrt.

/// Stufen entsprechen Klaus' Vorgabe:
///   basis           = simple
///   fortgeschritten = simple + advanced
///   experte         = simple + advanced + expert + develop
enum SettingTier {
  basis(0, {'simple'}),
  fortgeschritten(1, {'simple', 'advanced'}),
  experte(2, {'simple', 'advanced', 'expert', 'develop'});

  const SettingTier(this.index_, this.modes);
  final int index_;
  final Set<String> modes;

  bool includes(String mode) => modes.contains(mode);
}

@immutable
class SettingOption {
  const SettingOption({
    required this.key,
    required this.type,
    required this.mode,
    required this.tier,
    required this.labelEn,
    required this.labelDe,
    required this.tooltipEn,
    required this.tooltipDe,
    required this.sidetext,
    required this.defaultSerialized,
    required this.min,
    required this.max,
    required this.enumValues,
    required this.enumLabels,
    required this.enumLabelsDe,
    required this.nullable,
    required this.readonly,
    required this.ratioOver,
    required this.sourceLine,
  });

  final String key;
  final String type;    // "float", "int", "bool", "string", "enum", "percent", "float_or_percent", …
  final String mode;    // "simple" | "advanced" | "expert" | "develop"
  final String tier;    // "basis" | "fortgeschritten" | "experte" – kleinster Tier, der zeigt
  final String labelEn;
  final String labelDe;
  final String tooltipEn;
  final String tooltipDe;
  final String sidetext;        // Einheit, z. B. "mm", "%"
  final String defaultSerialized;
  final num? min;
  final num? max;
  final List<String> enumValues;
  final List<String> enumLabels;
  final List<String> enumLabelsDe;
  final bool nullable;
  final bool readonly;
  final String ratioOver;
  final int sourceLine;         // Tab.cpp-Zeile als Belegstelle

  String label(String locale) =>
      (locale.startsWith('de') && labelDe.isNotEmpty) ? labelDe : labelEn;
  String tooltip(String locale) =>
      (locale.startsWith('de') && tooltipDe.isNotEmpty) ? tooltipDe : tooltipEn;

  /// Zeigt die Option auf gegebener Stufe?
  bool visibleIn(SettingTier t) => t.includes(mode);
}

@immutable
class SettingGroup {
  const SettingGroup({
    required this.name,
    required this.nameDe,
    required this.options,
  });
  final String name;
  final String nameDe;
  final List<SettingOption> options;
  String display(String locale) =>
      (locale.startsWith('de') && nameDe.isNotEmpty) ? nameDe : name;
}

@immutable
class SettingPage {
  const SettingPage({
    required this.name,
    required this.nameDe,
    required this.groups,
  });
  final String name;
  final String nameDe;
  final List<SettingGroup> groups;
  String display(String locale) =>
      (locale.startsWith('de') && nameDe.isNotEmpty) ? nameDe : name;
}

@immutable
class SettingsSchema {
  const SettingsSchema({
    required this.orcaVersion,
    required this.pagesByArea,
  });

  final String orcaVersion;
  final Map<String, List<SettingPage>> pagesByArea; // 'print'/'filament'/'printer'

  List<SettingPage> pagesFor(String area) => pagesByArea[area] ?? const [];

  /// Flache Suche ueber alle Options eines Bereichs (unabhaengig von Tier).
  Iterable<SettingOption> allOptions(String area) sync* {
    for (final p in pagesFor(area)) {
      for (final g in p.groups) {
        yield* g.options;
      }
    }
  }

  /// Loader aus Flutter-Asset.
  static Future<SettingsSchema> loadFromAsset(
      [String path = 'assets/settings-schema.json']) async {
    final txt = await rootBundle.loadString(path);
    final json = jsonDecode(txt) as Map<String, dynamic>;
    return fromJson(json);
  }

  static SettingsSchema fromJson(Map<String, dynamic> j) {
    final src = j['source'] as Map<String, dynamic>?;
    final areas = j['areas'] as Map<String, dynamic>;
    final result = <String, List<SettingPage>>{};
    for (final a in areas.keys) {
      final pages = (areas[a] as List).map((p) {
        final pj = p as Map<String, dynamic>;
        final groups = (pj['groups'] as List).map((g) {
          final gj = g as Map<String, dynamic>;
          final opts = (gj['keys'] as List)
              .cast<Map<String, dynamic>>()
              .where((k) => k['missing_from_schema'] != true) // Platzhalter raus
              .map(_optionFromJson)
              .toList();
          return SettingGroup(
            name:   gj['group'] as String? ?? '',
            nameDe: gj['group_label_de'] as String? ?? '',
            options: opts,
          );
        }).toList();
        return SettingPage(
          name:   pj['page'] as String? ?? '',
          nameDe: pj['page_label_de'] as String? ?? '',
          groups: groups,
        );
      }).toList();
      result[a] = pages;
    }
    return SettingsSchema(
      orcaVersion: src?['orca_version']?.toString() ?? '',
      pagesByArea: result,
    );
  }
}

SettingOption _optionFromJson(Map<String, dynamic> k) {
  List<String> slist(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];
  num? toNum(dynamic v) => v is num ? v : null;
  return SettingOption(
    key:       k['key'] as String,
    type:      k['type'] as String? ?? '',
    mode:      k['mode'] as String? ?? 'simple',
    tier:      k['tier'] as String? ?? 'basis',
    labelEn:   k['label_en'] as String? ?? '',
    labelDe:   k['label_de'] as String? ?? '',
    tooltipEn: k['tooltip_en'] as String? ?? '',
    tooltipDe: k['tooltip_de'] as String? ?? '',
    sidetext:  k['sidetext'] as String? ?? '',
    defaultSerialized: k['default']?.toString() ?? '',
    min: toNum(k['min']),
    max: toNum(k['max']),
    enumValues:   slist(k['enum_values']),
    enumLabels:   slist(k['enum_labels']),
    enumLabelsDe: slist(k['enum_labels_de']),
    nullable: k['nullable'] as bool? ?? false,
    readonly: k['readonly'] as bool? ?? false,
    ratioOver: k['ratio_over'] as String? ?? '',
    sourceLine: (k['line'] as num?)?.toInt() ?? 0,
  );
}
