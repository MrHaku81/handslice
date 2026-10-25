import 'package:flutter/material.dart';

import '../theme/workshop_theme.dart';

// Zweispaltige Label/Value-Zeile. Werte in IBM Plex Mono wenn mono=true.
class WorkshopRow extends StatelessWidget {
  const WorkshopRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: WorkshopTokens.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: mono
                  ? monoStyle(context, fontSize: 13.5, color: WorkshopTokens.text)
                  : theme.textTheme.bodyMedium,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
