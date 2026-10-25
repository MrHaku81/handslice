import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/workshop_theme.dart';
import '../widgets/workshop_card.dart';

// Platzhalter fuer Meilenstein 1. Der generierte Einstellungsbaum
// (aus den Orca-Profil-JSONs) kommt in einer spaeteren Phase.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: ListView(
        children: [
          Text(l.settingsHeading, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          WorkshopCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
              child: Column(
                children: [
                  const Icon(Icons.construction_outlined,
                      size: 36, color: WorkshopTokens.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    l.settingsPlaceholder,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: WorkshopTokens.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
