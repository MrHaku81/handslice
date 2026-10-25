import 'package:flutter/material.dart';

import '../engine/slicer.dart';
import '../l10n/app_localizations.dart';
import '../state/project_state.dart';
import '../theme/workshop_theme.dart';
import '../widgets/workshop_card.dart';
import '../widgets/workshop_row.dart';

// Drucken-Screen fuer M2: zeigt den Slice-Status aus dem ProjectState.
// Upload / Druckstart kommen in M3/M4.
class PrintScreen extends StatefulWidget {
  const PrintScreen({super.key, required this.projectState});

  final ProjectState projectState;

  @override
  State<PrintScreen> createState() => _PrintScreenState();
}

class _PrintScreenState extends State<PrintScreen> {
  bool _bedlevelForce = true;
  bool _printerCheck = true;
  bool _timelapse = false;

  @override
  void initState() {
    super.initState();
    widget.projectState.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.projectState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final slice = widget.projectState.lastSlice;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: ListView(
        children: [
          Text(l.printHeading, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),

          if (slice == null)
            WorkshopCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    l.printNoGcode,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: WorkshopTokens.textMuted),
                  ),
                ),
              ),
            )
          else
            _SliceDetails(slice: slice),

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
            onPressed: slice == null ? null : () {},
            icon: const Icon(Icons.upload_outlined),
            label: Text(l.printUploadButton),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: slice == null ? null : () {},
            icon: const Icon(Icons.play_arrow_outlined),
            label: Text(l.printStartButton),
          ),
        ],
      ),
    );
  }
}

class _SliceDetails extends StatelessWidget {
  const _SliceDetails({required this.slice});

  final SliceResult slice;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return WorkshopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkshopRow(
            label: l.printFileLabel,
            value: slice.gcodePath.split('/').last,
            mono: true,
          ),
          const Divider(),
          WorkshopRow(
            label: l.printSizeLabel,
            value: '${slice.sizeBytes} B',
            mono: true,
          ),
          const Divider(),
          WorkshopRow(
            label: l.printTimeLabel,
            value: slice.estimatedTimeFmt,
            mono: true,
          ),
          const Divider(),
          WorkshopRow(
            label: l.printFilamentLabel,
            value:
                '${slice.filamentUsedMm.toStringAsFixed(0)} mm — ${slice.filamentWeightG.toStringAsFixed(2)} g',
            mono: true,
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
