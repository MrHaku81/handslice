import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/workshop_theme.dart';
import '../widgets/workshop_banner.dart';
import '../widgets/workshop_card.dart';
import '../widgets/workshop_row.dart';

// Sample-Daten fuer Meilenstein 1 – echte Werte kommen in M2/M3/M4.
class PrintScreen extends StatefulWidget {
  const PrintScreen({super.key});

  @override
  State<PrintScreen> createState() => _PrintScreenState();
}

class _PrintScreenState extends State<PrintScreen> {
  bool _bedlevelForce = true;
  bool _printerCheck = true;
  bool _timelapse = false;

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
          Text(l.printHeading, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),

          WorkshopCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WorkshopRow(
                  label: l.printFileLabel,
                  value: 'handslice_kerbenwuerfel.gcode',
                  mono: true,
                ),
                const Divider(),
                WorkshopRow(label: l.printSizeLabel, value: '220 261 B', mono: true),
                const Divider(),
                WorkshopRow(label: l.printLayersLabel, value: '100', mono: true),
                const Divider(),
                WorkshopRow(label: l.printTimeLabel, value: '9m 25s', mono: true),
                const Divider(),
                WorkshopRow(label: l.printFilamentLabel, value: '1172 mm — 3.52 g', mono: true),
              ],
            ),
          ),

          const SizedBox(height: 16),
          WorkshopCard(
            child: Column(
              children: [
                _ToggleRow(
                  label: l.printBedLeveling,
                  value: _bedlevelForce,
                  onChanged: (v) => setState(() => _bedlevelForce = v),
                ),
                const Divider(),
                _ToggleRow(
                  label: l.printAutoLevelCheck,
                  value: _printerCheck,
                  onChanged: (v) => setState(() => _printerCheck = v),
                ),
                const Divider(),
                _ToggleRow(
                  label: l.printTimelapse,
                  value: _timelapse,
                  onChanged: (v) => setState(() => _timelapse = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.upload_outlined),
            label: Text(l.printUploadButton),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.play_arrow_outlined),
            label: Text(l.printStartButton),
          ),

          const SizedBox(height: 20),
          Text(l.printStatusHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          WorkshopCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WorkshopRow(
                  label: 'machine_status.status',
                  value: '1 — ${l.printStatusIdle}',
                  mono: true,
                ),
                const Divider(),
                WorkshopRow(
                  label: 'heater_bed',
                  value: '24 / 0 °C',
                  mono: true,
                ),
                const Divider(),
                WorkshopRow(label: 'extruder', value: '28 / 0 °C', mono: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(WorkshopTokens.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
