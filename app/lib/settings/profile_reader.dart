import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Liest die unter `ApplicationSupportDirectory/profiles/user/`
/// abgelegten User-Profile ein (via `ProfileWriter.save` geschrieben).
///
/// Fuer die UI ist nur `name`, `baseInherits` und das `overrides`-Map
/// relevant – die restlichen Felder (`type`, `from`) sind
/// Orca-Metadata.
class SavedProfile {
  const SavedProfile({
    required this.file,
    required this.name,
    required this.baseInherits,
    required this.type,
    required this.overrides,
  });

  final File file;
  final String name;
  final String baseInherits;
  final String type;
  final Map<String, String> overrides;
}

class ProfileReader {
  const ProfileReader();

  static const Set<String> _reserved = {
    'name', 'type', 'from', 'inherits',
  };

  Future<List<SavedProfile>> list() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/profiles/user');
    if (!dir.existsSync()) return const [];
    final entries = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final out = <SavedProfile>[];
    for (final f in entries) {
      try {
        final body = jsonDecode(f.readAsStringSync());
        if (body is! Map) continue;
        final overrides = <String, String>{};
        for (final e in body.entries) {
          if (_reserved.contains(e.key)) continue;
          overrides[e.key.toString()] = e.value.toString();
        }
        out.add(SavedProfile(
          file: f,
          name: (body['name'] ?? f.uri.pathSegments.last) as String,
          baseInherits: (body['inherits'] ?? '') as String,
          type: (body['type'] ?? 'process') as String,
          overrides: overrides,
        ));
      } catch (_) {
        // defekte Datei → wird in der UI nicht angezeigt
      }
    }
    return out;
  }
}
