import 'package:flutter/material.dart';

import '../theme/workshop_theme.dart';

// Zeigt Version + App-Commit + CLI-Commit + Build-Zeit, damit am Geraet
// sichtbar ist, welche App- UND Engine-Version drauf ist. Werte kommen
// per --dart-define aus dem Build-Script (app/scripts/build_apk.sh).
//
// Warum CLI_COMMIT eine eigene Zeile hat: beim M4-Build (Commit 2b4fc1a)
// war die arm64-CLI aelter als der App-Commit; die App rief ein
// --z-offset-freies Binary ("unknown flag"). Seit M6 bricht der Build-
// Guard bei Mismatch ab und zeigt beide Hashes nebeneinander.
class BuildInfoBadge extends StatelessWidget {
  const BuildInfoBadge({super.key});

  static const String appVersion = '0.1';
  static const String buildCommit =
      String.fromEnvironment('BUILD_COMMIT', defaultValue: '-');
  static const String cliCommit =
      String.fromEnvironment('CLI_COMMIT', defaultValue: '-');
  static const String buildTime =
      String.fromEnvironment('BUILD_TIME', defaultValue: '-');

  // Startup-Guard-Signal fuer main.dart. true = APK wurde ohne die
  // dart-defines gebaut (also wahrscheinlich mit `flutter build apk`
  // direkt statt via app/scripts/build_apk.sh). Siehe main.dart.
  static bool get hasMissingMetadata =>
      buildCommit == '-' || cliCommit == '-' || buildTime == '-';

  @override
  Widget build(BuildContext context) {
    final labelStyle =
        monoStyle(context, fontSize: 11, color: WorkshopTokens.textMuted);
    final subStyle =
        monoStyle(context, fontSize: 10, color: WorkshopTokens.textMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: WorkshopTokens.surface,
        border: Border.all(color: WorkshopTokens.border),
        borderRadius: BorderRadius.circular(WorkshopTokens.radiusSmall),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('v$appVersion · app $buildCommit', style: labelStyle),
          Text('cli $cliCommit', style: subStyle),
          if (buildTime != '-') Text(buildTime, style: subStyle),
        ],
      ),
    );
  }
}
