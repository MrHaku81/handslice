import 'package:flutter/material.dart';

import '../theme/workshop_theme.dart';

/// A label + optional subtitle on the left, a [Switch] on the right.
///
/// Written to survive narrow screens: the label column is wrapped in
/// `Expanded`, the subtitle (if present) sits BELOW the label — not
/// to the side — so a long subtitle wraps rather than squeezing the
/// label into a one-character-wide vertical strip (bug Klaus hit on
/// the Pflicht 7a device test, where
/// "unbekannt (Drucker meldet den Zustand nicht)" pushed
/// "Kammerlicht" into a vertical stack of single letters).
class LabeledSwitchRow extends StatelessWidget {
  const LabeledSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = subtitle;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              if (sub != null) ...[
                const SizedBox(height: 2),
                Text(sub,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: WorkshopTokens.textMuted)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
