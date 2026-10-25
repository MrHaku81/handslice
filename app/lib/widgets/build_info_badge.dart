import 'package:flutter/material.dart';

import '../theme/workshop_theme.dart';

// Zeigt Version + Commit-Kurzhash + Build-Zeit, damit am Geraet sichtbar
// ist, welche App-Version drauf ist. Werte kommen per --dart-define aus
// dem Build-Script (siehe app/README.md "Native + Commit-Info im Build").
class BuildInfoBadge extends StatelessWidget {
  const BuildInfoBadge({super.key});

  static const String appVersion = '0.1';
  // --dart-define=BUILD_COMMIT=<short-hash>, Default '-' wenn nicht gesetzt
  // (dann ist der Build nicht ueber unser Script gemacht worden).
  static const String buildCommit =
      String.fromEnvironment('BUILD_COMMIT', defaultValue: '-');
  static const String buildTime =
      String.fromEnvironment('BUILD_TIME', defaultValue: '-');

  @override
  Widget build(BuildContext context) {
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
          Text(
            'v$appVersion · $buildCommit',
            style: monoStyle(context, fontSize: 11, color: WorkshopTokens.textMuted),
          ),
          if (buildTime != '-')
            Text(
              buildTime,
              style: monoStyle(context,
                  fontSize: 10, color: WorkshopTokens.textMuted),
            ),
        ],
      ),
    );
  }
}
