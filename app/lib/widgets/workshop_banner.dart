import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/workshop_theme.dart';

// Hinweis-Banner fuer Pre-Alpha / Meilenstein 1. Zeigt an, dass nichts
// verdrahtet ist. Entfaellt in spaeteren Meilensteinen.
class WorkshopBanner extends StatelessWidget {
  const WorkshopBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: WorkshopTokens.accent.withValues(alpha: 0.12),
        border: Border.all(color: WorkshopTokens.accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(WorkshopTokens.radiusSmall),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_outlined, size: 18, color: WorkshopTokens.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l.sampleBannerPlaceholder,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: WorkshopTokens.text),
            ),
          ),
        ],
      ),
    );
  }
}
