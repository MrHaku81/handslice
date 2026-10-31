// Regression-Test: Release-APK braucht android.permission.INTERNET im
// MAIN-Manifest (nicht nur im debug/-Overlay). Fehlt die Zeile, wirft
// die App am Geraet "Failed to create datagram socket" beim ersten
// UDP-Discovery (RawDatagramSocket.bind), und MQTT scheitert ebenfalls.
//
// Beleg: 2026-10-26, Release-APK 785e5cb hatte diese Zeile nicht;
// Flutter mergt debug/AndroidManifest.xml nur in Debug-Builds.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main AndroidManifest.xml enthaelt android.permission.INTERNET',
      () {
    final f = File('android/app/src/main/AndroidManifest.xml');
    expect(f.existsSync(), isTrue,
        reason: 'android/app/src/main/AndroidManifest.xml fehlt');
    final xml = f.readAsStringSync();
    // Robust gegen Whitespace/Attribut-Reihenfolge: einfach substring.
    expect(xml.contains('android.permission.INTERNET'), isTrue,
        reason:
            'INTERNET-Permission fehlt im main-Manifest. Release-APKs '
            'erben die Debug-Overlay-Permission NICHT; die App scheitert '
            'am Geraet mit "Failed to create datagram socket".');
  });

  test('main AndroidManifest.xml enthaelt EnableFlutterGPU=true (Pflicht 7a)',
      () {
    final f = File('android/app/src/main/AndroidManifest.xml');
    final xml = f.readAsStringSync();
    expect(
      xml.contains('io.flutter.embedding.android.EnableFlutterGPU'),
      isTrue,
      reason:
          'Flutter-GPU opt-in fehlt im main-Manifest. Ohne diese Zeile '
          'startet flutter_scene auf Release-Builds nicht und die '
          'Projekt-3D-Ansicht faellt auf den HSPB-Thumbnail zurueck. '
          'Entscheidung dokumentiert in docs/plate-view-benchmark.md.',
    );
    final idx = xml.indexOf('EnableFlutterGPU');
    expect(idx, greaterThan(0));
    final window = xml.substring(idx, (idx + 160).clamp(0, xml.length));
    expect(window.contains('android:value="true"'), isTrue,
        reason: 'EnableFlutterGPU meta-data value muss true sein');
  });
}
