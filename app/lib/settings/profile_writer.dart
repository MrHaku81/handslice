import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Schreibt Nutzer-Overrides als eigenes Orca-Profil mit `inherits`-
/// Kette auf das Basisprofil. Ablagepfad:
/// `ApplicationSupportDirectory/profiles/user/<slug>.json`.
///
/// Das Format spiegelt Orcas Preset-Dateien (resources/profiles/*):
///   {
///     "name": "<slug>",
///     "type": "process",
///     "from": "User",
///     "inherits": "<base_preset>",
///     "layer_height": "0.28",
///     "wall_loops": "4",
///     "sparse_infill_density": "40%"
///   }
///
/// Phase 4.3: nur `type == "process"`, nur lokale Ablage. In 4.x+
/// kommt dann noch Picker fuer gespeicherte Profile und Sync.
class ProfileWriter {
  const ProfileWriter();

  Future<File> save({
    required String name,
    required String baseInherits,
    required String type, // "process" | "filament" | "machine"
    required Map<String, String> overrides,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Profilname darf nicht leer sein');
    }
    final slug = _slugify(name);
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/profiles/user');
    await dir.create(recursive: true);
    final target = File('${dir.path}/$slug.json');
    final body = <String, dynamic>{
      'name': name,
      'type': type,
      'from': 'User',
      'inherits': baseInherits,
      ...overrides,
    };
    await target.writeAsString(const JsonEncoder.withIndent('  ').convert(body));
    return target;
  }

  static String _slugify(String s) => ProfileWriterSlug.of(s);
}

/// Oeffentlicher Zugriff auf die exakte Slugify-Regel von
/// [ProfileWriter]. UI-Code (Picker, Vergleich mit persistiertem
/// `active_profile_slug`) muss dieselbe Normalisierung nutzen, damit
/// Round-Trip gespeichert → geladen funktioniert.
class ProfileWriterSlug {
  const ProfileWriterSlug._();
  static String of(String s) {
    final down = s.toLowerCase();
    final out = StringBuffer();
    for (final cu in down.runes) {
      final c = String.fromCharCode(cu);
      if (RegExp(r'[a-z0-9]').hasMatch(c)) {
        out.write(c);
      } else if (RegExp(r'[\s_\-\.]').hasMatch(c)) {
        out.write('-');
      }
    }
    final cleaned = out.toString().replaceAll(RegExp(r'-+'), '-');
    return cleaned.replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
