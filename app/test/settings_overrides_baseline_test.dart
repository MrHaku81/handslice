// Phase-4.4-Nacharbeit: Baseline-Logik der SettingsOverrides.
// "N Ueberschreibungen" und die ↺-Markierungen muessen sich auf das
// geladene User-Profil (= Baseline) beziehen, nicht auf das Orca-
// Basisprofil. Sonst meldet die UI dauerhaft N Abweichungen,
// obwohl der Nutzer gerade frisch das Profil geladen hat.

import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/settings/settings_overrides.dart';

void main() {
  group('SettingsOverrides.count ohne Baseline', () {
    test('leer → 0', () {
      expect(SettingsOverrides().count, 0);
    });

    test('zaehlt jeden gesetzten Key', () {
      final ov = SettingsOverrides()
        ..set('layer_height', '0.28')
        ..set('wall_loops', '4');
      expect(ov.count, 2);
      expect(ov.has('layer_height'), isTrue);
    });
  });

  group('SettingsOverrides.count mit Baseline (Orca-Verhalten)', () {
    test('applyProfile setzt Baseline UND Werte, Count ist 0', () {
      final ov = SettingsOverrides()
        ..applyProfile({'layer_height': '0.28', 'wall_loops': '4'});
      expect(ov.count, 0,
          reason: 'frisch geladenes Profil → keine Abweichungen');
      expect(ov.has('layer_height'), isFalse,
          reason: 'has() == "weicht von Baseline ab", nicht "gesetzt"');
      expect(ov.get('layer_height'), '0.28',
          reason: 'Wert selbst ist weiter da (fuer die CLI)');
    });

    test('Setzen eines Profil-Werts auf anderen Wert → count=1', () {
      final ov = SettingsOverrides()
        ..applyProfile({'layer_height': '0.28', 'wall_loops': '4'});
      ov.set('layer_height', '0.32');
      expect(ov.count, 1);
      expect(ov.has('layer_height'), isTrue);
      expect(ov.has('wall_loops'), isFalse);
    });

    test('Setzen eines Nicht-Profil-Keys → count+1', () {
      final ov = SettingsOverrides()
        ..applyProfile({'layer_height': '0.28'});
      ov.set('sparse_infill_density', '40%');
      expect(ov.count, 1);
      expect(ov.has('sparse_infill_density'), isTrue);
    });

    test('Reset: Profil-Key geht auf Profil-Wert zurueck, count-1',
        () {
      final ov = SettingsOverrides()
        ..applyProfile({'layer_height': '0.28'});
      ov.set('layer_height', '0.32');
      expect(ov.count, 1);
      ov.reset('layer_height');
      expect(ov.count, 0);
      expect(ov.get('layer_height'), '0.28',
          reason: 'Reset auf Baseline (Orca-Default), nicht loeschen');
    });

    test('Reset auf Nicht-Profil-Key loescht den Override', () {
      final ov = SettingsOverrides()
        ..applyProfile({'layer_height': '0.28'});
      ov.set('sparse_infill_density', '40%');
      ov.reset('sparse_infill_density');
      expect(ov.get('sparse_infill_density'), isNull);
      expect(ov.count, 0);
    });

    test('Profil-Key explizit entfernen zaehlt als Abweichung', () {
      // Semantik: Baseline sagt "layer_height=0.28", der User hat den
      // Key per clearAll (oder vergleichbar) rausgenommen → das IST
      // eine Abweichung vom gespeicherten Profil.
      final ov = SettingsOverrides()
        ..applyProfile({'layer_height': '0.28', 'wall_loops': '4'});
      // Simuliere "User hat den Key komplett geloescht":
      ov.set('layer_height', '0.28');
      ov.set('wall_loops', '4'); // Status: identisch zur Baseline
      expect(ov.count, 0);
      // Jetzt entfernen wir layer_height aus _overrides direkt ueber
      // clearAll + nur wall_loops wieder reinsetzen – naechstbester
      // Weg mit der oeffentlichen API.
      ov.clearAll();
      ov.set('wall_loops', '4');
      // Baseline hat 2 Keys, overrides hat 1 (gleich), 1 fehlt → count=1.
      expect(ov.count, 1);
    });

    test('clearProfile loescht Baseline + Overrides', () {
      final ov = SettingsOverrides()
        ..applyProfile({'layer_height': '0.28'});
      ov.set('other', 'x');
      ov.clearProfile();
      expect(ov.baseline, isEmpty);
      expect(ov.all, isEmpty);
      expect(ov.count, 0);
    });

    test('setBaseline ohne Werte-Overwrite', () {
      final ov = SettingsOverrides()..set('layer_height', '0.30');
      ov.setBaseline({'layer_height': '0.28'});
      expect(ov.get('layer_height'), '0.30', reason: 'Werte unangetastet');
      expect(ov.count, 1, reason: '0.30 != 0.28 → Abweichung');
    });
  });
}
