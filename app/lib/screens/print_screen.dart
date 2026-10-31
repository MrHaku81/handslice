import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/slicer.dart';
import '../l10n/app_localizations.dart';
import '../net/cc2_exception_codes.dart';
import '../net/control_error_label.dart';
import '../net/elegoo_cc2_client.dart';
import '../state/printer_state.dart';
import '../state/project_state.dart';
import '../theme/workshop_theme.dart';
import '../widgets/workshop_card.dart';
import '../widgets/workshop_row.dart';

// Drucken-Screen fuer M4: Slice-Metadaten, Switches, Upload-Button
// (M3), Druck-Button (M4a) + Live-Status (M4b).
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
  // M8-Nachbesserung: ein einziger Nivellier-Schalter steht fuer
  // `bedlevel_force` UND `printer_check` – beim Senden werden
  // beide auf denselben Wert gesetzt. Zuvor war das in zwei
  // Switches aufgeteilt, obwohl die Semantik "Bett nivellieren
  // ja/nein" ist.
  bool _bedLevel = true;
  bool _timelapse = false;

  double? _uploadProgress;
  String? _uploadError;
  String? _uploadOk;

  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.projectState.addListener(_onStateChanged);
    widget.printerState.addListener(_onStateChanged);
    // 1-Sekunden-Tick fuer Live-Restzeit-Rechnung (nicht aus
    // Drucker-Absolutzeit).
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.printerState.isPrinting) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
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
    final remoteName =
        'handslice_${DateTime.now().millisecondsSinceEpoch}.gcode';
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

  Future<void> _startPrint() async {
    final r = await widget.printerState.startPrint(
      levelBed: _bedLevel,
      enableTimelapse: _timelapse,
      boundsOk: widget.projectState.boundsOk,
    );
    if (!mounted || r == null) return;
    // Reaktion auf das Ergebnis nur ueber den PrinterState (lastError)
    // und den Live-Status; dieser Pfad zieht sich die Delta-Events
    // automatisch nach.
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final slice = widget.projectState.lastSlice;
    final printer = widget.printerState;

    final preflightKey = printer.printPreflight(
      boundsOk: widget.projectState.boundsOk,
    );
    final startEnabled = preflightKey == null &&
        !printer.isPrinting &&
        !printer.reconnecting;

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
                  label: l.printLevelBed,
                  value: _bedLevel,
                  onChanged: (v) => setState(() => _bedLevel = v),
                ),
                const Divider(),
                _ToggleRow(
                  label: l.printTimelapse,
                  value: _timelapse && printer.supportsTimelapse,
                  onChanged: printer.supportsTimelapse
                      ? (v) => setState(() => _timelapse = v)
                      : null,
                ),
                if (!printer.supportsTimelapse)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: Text(
                      l.printTimelapseNotSupported,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: WorkshopTokens.textMuted),
                    ),
                  ),
              ],
            ),
          ),

          if (slice != null) ...[
            const SizedBox(height: 12),
            _BoundsStatus(projectState: widget.projectState),
          ],

          if (printer.reconnecting) ...[
            const SizedBox(height: 12),
            _InfoBox(
              icon: Icons.wifi_tethering_off,
              color: WorkshopTokens.textMuted,
              message: _reconnectBannerText(l, printer),
            ),
          ],

          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: (slice == null ||
                    !widget.projectState.boundsOk ||
                    _uploadProgress != null ||
                    printer.connection != CanvasConnection.connected)
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
            _InfoBox(
              icon: Icons.check_circle_outline,
              color: WorkshopTokens.accent,
              message: _uploadOk!,
            ),
          ],
          if (_uploadError != null) ...[
            const SizedBox(height: 8),
            _InfoBox(
              icon: Icons.error_outline,
              color: const Color(0xFFFF6B6B),
              message: _uploadError!,
            ),
          ],

          if (preflightKey != null) ...[
            const SizedBox(height: 8),
            _InfoBox(
              icon: Icons.lock_outline,
              color: WorkshopTokens.textMuted,
              message: _preflightMessage(context, preflightKey, printer),
            ),
          ],

          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: startEnabled ? _startPrint : null,
            icon: const Icon(Icons.play_arrow_outlined),
            label: Text(l.printStartButton),
          ),

          // M8-Nachbesserung 3: 1026-Retry-Hinweis
          // ("Drucker hat keine Mesh-Daten – Nivellierung wird
          // erzwungen"). PrinterState setzt lastHint beim Retry;
          // Hinweis bleibt kurz sichtbar.
          if (printer.lastHint == 'startprint.retry_forced_level') ...[
            const SizedBox(height: 8),
            _InfoBox(
              icon: Icons.flaky_outlined,
              color: WorkshopTokens.accent,
              message: l.startPrintForcedLevelHint,
            ),
          ],

          const SizedBox(height: 20),
          Text(l.printStatusHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _LiveStatus(printer: printer),
          const SizedBox(height: 12),
          _PrintControls(printer: printer),
        ],
      ),
    );
  }
}

String _preflightMessage(
    BuildContext context, String key, PrinterState printer) {
  final l = AppLocalizations.of(context);
  switch (key) {
    case 'preflight.no_upload':
      return l.printPreflightNoUpload;
    case 'preflight.not_connected':
      return l.printPreflightNotConnected;
    case 'preflight.bounds_failed':
      return l.printPreflightBoundsFailed;
    case 'preflight.not_idle':
      return l.printPreflightNotIdle(
          _machineStatusLabel(l, printer.machineStatus));
    case 'preflight.tray_empty':
      return l.printPreflightTrayEmpty(printer.trayAssignmentForTool0 + 1);
    default:
      return key;
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
          WorkshopRow(label: l.printFileLabel, value: slice.gcodePath.split('/').last, mono: true),
          const Divider(),
          WorkshopRow(label: l.printSizeLabel, value: '${slice.sizeBytes} B', mono: true),
          const Divider(),
          WorkshopRow(label: l.printTimeLabel, value: slice.estimatedTimeFmt, mono: true),
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

class _BoundsStatus extends StatelessWidget {
  const _BoundsStatus({required this.projectState});
  final ProjectState projectState;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final v = projectState.boundsViolations;
    final ok = v.isEmpty;
    final color = ok ? WorkshopTokens.accent : const Color(0xFFFF6B6B);
    return _InfoBox(
      icon: ok ? Icons.check_circle_outline : Icons.error_outline,
      color: color,
      message: ok ? l.printBoundsOk : l.printBoundsFail(v.length),
    );
  }
}

class _LiveStatus extends StatelessWidget {
  const _LiveStatus({required this.printer});
  final PrinterState printer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final phase = printer.printPhase;
    final stateText = switch (phase) {
      PrintPhase.unknown => l.printStatusUnknown,
      PrintPhase.idle => l.printStatusIdle,
      PrintPhase.preparing => l.printPhasePreparing,
      PrintPhase.paused => l.substatePaused,
      PrintPhase.resuming => l.substateResuming,
      PrintPhase.cancelling => l.printPhaseCancelling,
      PrintPhase.cancelled => l.printPhaseCancelled,
      PrintPhase.printing => l.printStatusPrinting,
    };
    return WorkshopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkshopRow(
            label: l.printStatusLabel,
            value: stateText,
          ),
          if (printer.currentLayer != null &&
              printer.totalLayer != null &&
              printer.totalLayer! > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l.printLayerProgress(
                  printer.currentLayer ?? 0,
                  printer.totalLayer ?? 0,
                  printer.printProgressPct ?? 0,
                ),
                style: monoStyle(context, fontSize: 13),
              ),
            ),
          if (printer.printProgressFraction != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: LinearProgressIndicator(
                value: printer.printProgressFraction,
              ),
            ),
          const Divider(),
          WorkshopRow(
            label: l.printBedLabel,
            value: l.printTempFormat(
              _fmtTemp(printer.bedTemperature),
              _fmtTemp(printer.bedTarget),
            ),
            mono: true,
          ),
          const Divider(),
          WorkshopRow(
            label: l.printNozzleLabel,
            value: l.printTempFormat(
              _fmtTemp(printer.nozzleTemperature),
              _fmtTemp(printer.nozzleTarget),
            ),
            mono: true,
          ),
          if (printer.remainingSeconds != null) ...[
            const Divider(),
            WorkshopRow(
              label: l.printRemainingTime(_fmtDuration(printer.remainingSeconds!)),
              value: '',
            ),
          ],
          // M7 Teil A: aktive Druckerfehler als lokalisierte Infobox.
          // 1243 behaelt den speziellen "Filamentzufuhr-Fehler"-Text
          // aus der ARB (Klaus-Vorgabe). Alle anderen Codes zieht
          // _formatExceptionCode aus cc2_exception_codes.dart.
          if (printer.activeExceptionCodes.isNotEmpty) ...[
            const Divider(),
            _PrinterErrorBanner(codes: printer.activeExceptionCodes),
          ],
        ],
      ),
    );
  }
}

// Reconnect-Banner: "Verbindung verloren – verbinde neu …" wenn
// gerade kein konkreter Countdown; sobald der Countdown steht,
// wird er als "nächster Versuch in Ns" angezeigt.
String _reconnectBannerText(AppLocalizations l, PrinterState printer) {
  final sec = printer.secondsUntilReconnect;
  if (sec == null || sec <= 0) return l.reconnectBannerLost;
  return l.reconnectBannerRetrying(sec);
}

// Klartext fuer machine_status.status laut Daniels const.py
// (CC2_STATUS_*). Fallback: numerischer Code in Klammern, damit
// unbekannte Werte nicht spurlos verschwinden.
String _machineStatusLabel(AppLocalizations l, int? code) {
  switch (code) {
    case null:  return l.machineStatusUnknown;
    case 0:     return l.machineStatusInitializing;
    case 1:     return l.machineStatusIdle;
    case 2:     return l.machineStatusPrinting;
    case 3:
    case 4:     return l.machineStatusFilamentOp;
    case 5:     return l.machineStatusAutoLeveling;
    case 6:     return l.machineStatusPidCalibrating;
    case 7:     return l.machineStatusResonanceTesting;
    case 8:     return l.machineStatusSelfChecking;
    case 9:     return l.machineStatusUpdating;
    case 10:    return l.machineStatusHoming;
    case 11:    return l.machineStatusFileTransferring;
    case 12:    return l.machineStatusVideoComposing;
    case 13:    return l.machineStatusExtruderOp;
    case 14:    return l.machineStatusEmergencyStop;
    case 15:    return l.machineStatusPowerLossRecovery;
    default:    return l.machineStatusOther(code);
  }
}

String _fmtTemp(num? v) =>
    v == null ? '—' : (v is int ? '$v' : v.toStringAsFixed(0));

String _fmtDuration(int seconds) {
  final s = seconds.clamp(0, 365 * 24 * 3600);
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  if (m > 0) return '${m}m ${sec.toString().padLeft(2, '0')}s';
  return '${sec}s';
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  // onChanged == null → Zeile deaktiviert (etwa wenn der Drucker keine
  // Kamera meldet und Zeitraffer gesperrt ist).
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return InkWell(
      onTap: enabled ? () => onChanged!(!value) : null,
      borderRadius: BorderRadius.circular(WorkshopTokens.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:
                        enabled ? null : WorkshopTokens.textMuted),
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

// M7 Teil A: Fehler-Banner mit lokalisierten Druckerfehler-Texten.
// Mehrere Codes werden gestapelt angezeigt, bleibt sichtbar solange
// mindestens einer in `machine_status.exception_status` steht.
class _PrinterErrorBanner extends StatelessWidget {
  const _PrinterErrorBanner({required this.codes});
  final List<int> codes;

  String _formatCode(AppLocalizations l, String locale, int code) {
    // 1243 bekommt den Klaus-definierten Spezialtext in der ARB.
    if (code == 1243) return l.printStatusException1243;
    final hit = cc2ExceptionLookup(code, locale: locale);
    return hit ?? l.exceptionCodeUnknown(code);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final title = codes.length == 1
        ? l.printerErrorBannerTitle
        : l.printerErrorsBannerTitle(codes.length);
    const color = Color(0xFFFF6B6B);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(WorkshopTokens.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.error_outline, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: color)),
            ),
          ]),
          const SizedBox(height: 6),
          for (final code in codes) ...[
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 2, bottom: 2),
              child: Text(
                _formatCode(l, locale, code),
                style: TextStyle(color: color.withValues(alpha: 0.95)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// M6: Steuerungs-Panel. Zeigt genau einen Pause-/Fortsetzen-Button
// (abhaengig von phase), einen Abbrechen-Button mit Bestaetigungs-
// dialog und einen Licht-Schalter. Fokus-Navigation ergibt sich
// aus den Material-Buttons und dem Switch.
class _PrintControls extends StatefulWidget {
  const _PrintControls({required this.printer});
  final PrinterState printer;
  @override
  State<_PrintControls> createState() => _PrintControlsState();
}

class _PrintControlsState extends State<_PrintControls> {
  String? _lastHint;      // Erfolg oder Hinweis (gruen/orange)
  String? _lastError;     // Fehlermeldung (rot)

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = widget.printer;
    final phase = p.printPhase;
    final busy = p.controlInFlight;
    final connected = p.connection == CanvasConnection.connected;

    // preparing: Pause ergibt am Pre-Heat/Levelling keinen Sinn,
    // Cancel aber schon (Klaus-Vorgabe M6-Nachbesserung).
    final canPause  = connected && phase == PrintPhase.printing && !busy;
    final canResume = connected && phase == PrintPhase.paused   && !busy;
    final canCancel = connected &&
        (phase == PrintPhase.printing ||
         phase == PrintPhase.paused   ||
         phase == PrintPhase.preparing) && !busy;
    final canLight  = connected && !busy;

    // Pause/Resume ist EIN Knopf, Label je nach Phase.
    final isResume = phase == PrintPhase.paused;
    final pauseResumeLabel =
        isResume ? l.printControlResume : l.printControlPause;
    final pauseResumeIcon = isResume ? Icons.play_arrow : Icons.pause;
    VoidCallback? pauseResumeAction;
    if (canResume) {
      pauseResumeAction = () async {
        setState(() { _lastError = null; _lastHint = null; });
        final ok = p.resumePrint();
        if (!mounted) return;
        setState(() {
          if (ok) {
            _lastHint = l.printControlResumeHint;
          } else {
            _lastError =
                mapControlErrorToText(l, p.lastError) ?? p.lastError ?? '—';
          }
        });
      };
    } else if (canPause) {
      pauseResumeAction = () async {
        setState(() { _lastError = null; _lastHint = null; });
        final ok = await p.pausePrint();
        if (!mounted) return;
        setState(() {
          if (!ok) {
            _lastError =
                mapControlErrorToText(l, p.lastError) ?? p.lastError ?? '—';
          }
        });
      };
    }

    return WorkshopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.printControlSectionLabel,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: pauseResumeAction,
                icon: Icon(pauseResumeIcon),
                label: Text(pauseResumeLabel),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canCancel ? () => _confirmCancel(context, p) : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(l.printControlCancel),
              ),
            ),
          ]),
          const Divider(height: 20),
          Row(children: [
            Expanded(
              child: Text(l.printControlLightLabel,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            if (p.lightOn == null) ...[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  l.printControlLightUnknown,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: WorkshopTokens.textMuted),
                ),
              ),
            ],
            Switch(
              value: p.lightOn ?? false,
              onChanged: canLight
                  ? (v) async {
                      setState(() { _lastError = null; _lastHint = null; });
                      final ok = await p.setLight(v);
                      if (!mounted) return;
                      if (!ok) {
                        setState(() {
                          _lastError = mapControlErrorToText(l, p.lastError)
                              ?? p.lastError ?? '—';
                        });
                      }
                    }
                  : null,
            ),
          ]),
          if (_lastHint != null) ...[
            const SizedBox(height: 8),
            _InfoBox(
              icon: Icons.info_outline,
              color: WorkshopTokens.accent,
              message: _lastHint!,
            ),
          ],
          if (_lastError != null) ...[
            const SizedBox(height: 8),
            _InfoBox(
              icon: Icons.error_outline,
              color: const Color(0xFFFF6B6B),
              message: _lastError!,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, PrinterState p) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.printControlCancelConfirmTitle),
        content: Text(l.printControlCancelConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.printControlCancelConfirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.printControlCancelConfirmYes),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() { _lastError = null; _lastHint = null; });
    final success = await p.cancelPrint();
    if (!mounted) return;
    setState(() {
      if (!success) {
        _lastError =
            mapControlErrorToText(l, p.lastError) ?? p.lastError ?? '—';
      }
    });
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.color, required this.message});
  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
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
          Expanded(child: Text(message, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}
