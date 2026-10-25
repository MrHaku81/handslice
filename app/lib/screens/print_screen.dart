import 'package:flutter/material.dart';

import '../engine/slicer.dart';
import '../l10n/app_localizations.dart';
import '../net/elegoo_cc2_client.dart';
import '../state/printer_state.dart';
import '../state/project_state.dart';
import '../theme/workshop_theme.dart';
import '../widgets/workshop_card.dart';
import '../widgets/workshop_row.dart';

// Drucken-Screen fuer M2: zeigt den Slice-Status aus dem ProjectState.
// Upload / Druckstart kommen in M3/M4.
class PrintScreen extends StatefulWidget {
  const PrintScreen({
    super.key,
    required this.projectState,
    required this.printerState,
  });

  final ProjectState projectState;
  final PrinterState printerState;

  @override
  State<PrintScreen> createState() => _PrintScreenState();
}

class _PrintScreenState extends State<PrintScreen> {
  bool _bedlevelForce = true;
  bool _printerCheck = true;
  bool _timelapse = false;

  double? _uploadProgress; // 0..1 oder null
  String? _uploadError;
  String? _uploadOk;

  @override
  void initState() {
    super.initState();
    widget.projectState.addListener(_onStateChanged);
    widget.printerState.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.projectState.removeListener(_onStateChanged);
    widget.printerState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _upload() async {
    final slice = widget.projectState.lastSlice;
    if (slice == null) return;
    setState(() {
      _uploadError = null;
      _uploadOk = null;
      _uploadProgress = 0;
    });
    final remoteName = 'handslice_${DateTime.now().millisecondsSinceEpoch}.gcode';
    final result = await widget.printerState.uploadGcode(
      gcodePath: slice.gcodePath,
      remoteName: remoteName,
      onProgress: (sent, total) {
        if (!mounted) return;
        setState(() => _uploadProgress = total == 0 ? null : sent / total);
      },
    );
    if (!mounted) return;
    setState(() {
      _uploadProgress = null;
      if (result.ok) {
        _uploadOk = '${result.message} (${result.sizeBytes ?? 0} B)';
      } else {
        _uploadError = result.message;
      }
    });
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
                  label: l.printPrinterCheck,
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

          if (slice != null) ...[
            const SizedBox(height: 12),
            _BoundsStatus(projectState: widget.projectState),
          ],

          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: (slice == null ||
                    !widget.projectState.boundsOk ||
                    _uploadProgress != null ||
                    widget.printerState.connection != CanvasConnection.connected)
                ? null
                : _upload,
            icon: const Icon(Icons.upload_outlined),
            label: Text(l.printUploadButton),
          ),
          if (_uploadProgress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _uploadProgress),
          ],
          if (_uploadOk != null) ...[
            const SizedBox(height: 8),
            _UploadResultBox(ok: true, message: _uploadOk!),
          ],
          if (_uploadError != null) ...[
            const SizedBox(height: 8),
            _UploadResultBox(ok: false, message: _uploadError!),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            // M4 verdrahtet den eigentlichen Druckstart. In M3 bleibt
            // der Button deaktiviert – Klaus startet ab hier manuell.
            onPressed: null,
            icon: const Icon(Icons.play_arrow_outlined),
            label: Text(l.printStartButton),
          ),
        ],
      ),
    );
  }
}

class _UploadResultBox extends StatelessWidget {
  const _UploadResultBox({required this.ok, required this.message});
  final bool ok;
  final String message;
  @override
  Widget build(BuildContext context) {
    final c = ok ? WorkshopTokens.accent : const Color(0xFFFF6B6B);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        border: Border.all(color: c.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(WorkshopTokens.radiusSmall),
      ),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
            color: c, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(color: c))),
      ]),
    );
  }
}

class _BoundsStatus extends StatelessWidget {
  const _BoundsStatus({required this.projectState});

  final ProjectState projectState;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final violations = projectState.boundsViolations;
    final ok = violations.isEmpty;
    final color = ok ? WorkshopTokens.accent : const Color(0xFFFF6B6B);
    final icon = ok ? Icons.check_circle_outline : Icons.error_outline;
    final text = ok
        ? l.printBoundsOk
        : l.printBoundsFail(violations.length);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(WorkshopTokens.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color))),
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
