import 'package:flutter/material.dart';

import '../theme/workshop_theme.dart';

class WorkshopCard extends StatelessWidget {
  const WorkshopCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: WorkshopTokens.surface,
        border: Border.all(color: WorkshopTokens.border),
        borderRadius: BorderRadius.circular(WorkshopTokens.radiusMedium),
      ),
      child: child,
    );
  }
}
