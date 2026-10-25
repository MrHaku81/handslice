import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/workshop_theme.dart';
import '../widgets/workshop_banner.dart';
import '../widgets/workshop_card.dart';
import '../widgets/workshop_row.dart';

// Sample-Daten: Platzhalter-UI fuer Meilenstein 1. Keine echten
// Interaktionen – nichts ist mit der CLI/dem Drucker verdrahtet.
class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  // Lokaler UI-State (noch kein echter Business-State).
  String _plate = 'A'; // A = Strukturiert, B = Glatt

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: ListView(
        children: [
          const WorkshopBanner(),
          const SizedBox(height: 12),
          Text(l.projectHeading, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),

          WorkshopCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WorkshopRow(
                  label: l.projectModelFile,
                  value: 'cube_notched_20mm_centered_cc2.stl',
                  mono: true,
                ),
                const Divider(),
                WorkshopRow(
                  label: l.projectPrinter,
                  value: 'Elegoo Centauri Carbon 2 — 0.4 nozzle',
                ),
                const Divider(),
                WorkshopRow(
                  label: l.projectProfile,
                  value: '0.20mm Standard @Elegoo CC2 0.4 nozzle',
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.projectPlate, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 6),
                      _PlateChooser(
                        value: _plate,
                        onChanged: (p) => setState(() => _plate = p),
                        textured: l.projectPlateTextured,
                        smooth: l.projectPlateSmooth,
                      ),
                    ],
                  ),
                ),
                const Divider(),
                WorkshopRow(
                  label: l.projectZOffset,
                  value: _plate == 'A' ? '−0.030 mm' : '+0.015 mm',
                  mono: true,
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.projectFilaments, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 8),
                      _FilamentSlotRow(index: 0, slot: 'A4', material: 'Elegoo RAPID PLA+ (weiß)'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {}, // M2 verdrahtet
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(l.projectOpenModel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {}, // M2 verdrahtet
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(l.projectSliceButton),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlateChooser extends StatelessWidget {
  const _PlateChooser({
    required this.value,
    required this.onChanged,
    required this.textured,
    required this.smooth,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String textured;
  final String smooth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PlateButton(
            label: textured,
            selected: value == 'A',
            onTap: () => onChanged('A'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PlateButton(
            label: smooth,
            selected: value == 'B',
            onTap: () => onChanged('B'),
          ),
        ),
      ],
    );
  }
}

class _PlateButton extends StatelessWidget {
  const _PlateButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Focus(
      child: FocusVisible(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: WorkshopTokens.minTapTarget),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? WorkshopTokens.accent.withValues(alpha: 0.18) : null,
              border: Border.all(
                color: selected ? WorkshopTokens.accent : WorkshopTokens.border,
              ),
              borderRadius: BorderRadius.circular(WorkshopTokens.radiusMedium),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? WorkshopTokens.accent : WorkshopTokens.text,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilamentSlotRow extends StatelessWidget {
  const _FilamentSlotRow({required this.index, required this.slot, required this.material});

  final int index;
  final String slot;
  final String material;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            border: Border.all(color: WorkshopTokens.border),
            borderRadius: BorderRadius.circular(WorkshopTokens.radiusSmall),
          ),
          alignment: Alignment.center,
          child: Text('T$index', style: monoStyle(context, fontSize: 12, color: WorkshopTokens.textMuted)),
        ),
        const SizedBox(width: 10),
        const Icon(Icons.arrow_right_alt, color: WorkshopTokens.textMuted, size: 20),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: WorkshopTokens.accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(WorkshopTokens.radiusSmall),
          ),
          child: Text(slot, style: monoStyle(context, fontSize: 13, color: WorkshopTokens.accent, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(material, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}
