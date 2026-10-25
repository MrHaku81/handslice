// Dart-CLI-Test gegen den ECHTEN CC2 im LAN. Faehrt nur die
// M3-Operationen: Discovery, Register, 2005 (Canvas), Upload,
// 1044 (file list). Kein Druckstart.
//
// Lauf (aus app/-Verzeichnis):
//   CC2_IP=<cc2-ip> \
//   MOCK_ACCESS_CODE="$(grep '^CC2_ACCESS_CODE=' ~/handslice/.env | cut -d= -f2)" \
//   dart run tool/real_cc2_check.dart <gcode-pfad>
//
// Access-Code wird aus der Umgebung gelesen und NIEMALS ausgegeben.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:handslice/net/elegoo_cc2_client.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/real_cc2_check.dart <gcode>');
    exit(2);
  }
  final gcodePath = args[0];
  final ip = Platform.environment['CC2_IP'];
  final code = Platform.environment['MOCK_ACCESS_CODE'] ??
      Platform.environment['CC2_ACCESS_CODE'];
  if (ip == null || code == null) {
    stderr.writeln('CC2_IP + CC2_ACCESS_CODE (oder MOCK_ACCESS_CODE) muessen gesetzt sein.');
    exit(2);
  }

  final client = ElegooCc2Client();
  stdout.writeln('[M3 real] ip=$ip  gcode=$gcodePath');

  stdout.writeln('[M3 real] 1) Discovery (UDP 52700)…');
  final info = await client.discover(ip);
  stdout.writeln(
      '  sn=${info.sn}  model=${info.model}  host=${info.hostName}  '
      'lan=${info.lanOnly}  token_status=${info.needsAccessCode}  '
      'proto=${info.protocolVersion}');

  stdout.writeln('[M3 real] 2) MQTT Connect + Register…');
  await client.connect(ip: ip, sn: info.sn, accessCode: code);
  stdout.writeln('  OK');

  stdout.writeln('[M3 real] 3) method 2005 (CANVAS)…');
  final slots = await client.getCanvasStatus();
  for (final s in slots) {
    stdout.writeln('  ${s.slotLabel}  ${s.filamentType.padRight(5)}  '
        '${s.filamentName.padRight(20)}  ${s.filamentColor}');
  }

  stdout.writeln('[M3 real] 4) HTTP PUT /upload (chunked)…');
  final data = Uint8List.fromList(await File(gcodePath).readAsBytes());
  final name = 'handslice_m3_${DateTime.now().millisecondsSinceEpoch}.gcode';
  final r = await client.uploadGcode(
    remoteName: name,
    data: data,
    onProgress: (sent, total) {
      // nur alle 25 % was ausgeben
      if (total > 0 && sent * 4 ~/ total != (sent - 1) * 4 ~/ total) {
        stdout.writeln('  … ${((sent / total) * 100).toStringAsFixed(0)} %');
      }
    },
  );
  stdout.writeln('  → ${r.toString().length} byte response, '
      'error_code=${r['error_code']}, offset=${r['offset']}, '
      'uploaded=$name (${data.length} B)');

  stdout.writeln('[M3 real] 5) method 1044 (file list local)…');
  final files = await client.getFileList(storageMedia: 'local');
  final found = files.where((f) => f.filename == name).toList();
  if (found.isEmpty) {
    stderr.writeln('  !! Datei nicht in GET_FILE_LIST aufgetaucht');
    exit(3);
  }
  stdout.writeln(
      '  Datei bestaetigt: ${found.first.filename} '
      '(${found.first.sizeBytes} B).  '
      'Gesamt ${files.length} Dateien im local-Speicher.');

  stdout.writeln('[M3 real] 6) DISCONNECT');
  await client.disconnect();
  stdout.writeln('[M3 real] FERTIG. Kein Druckstart ausgefuehrt (M3-Scope).');
}
