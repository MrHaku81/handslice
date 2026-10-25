import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../net/elegoo_cc2_client.dart';
import '../state/printer_state.dart';
import '../theme/workshop_theme.dart';
import 'workshop_card.dart';

// Drucker-Panel im Projekt-Screen. Zeigt Pairing-Zustand +
// Verbindungstatus, oeffnet Pairing-Dialog, triggert "Verbinden &
// Faecher laden", listet die echten CANVAS-Slots.
class PrinterPanel extends StatefulWidget {
  const PrinterPanel({super.key, required this.printer});

  final PrinterState printer;

  @override
  State<PrinterPanel> createState() => _PrinterPanelState();
}

class _PrinterPanelState extends State<PrinterPanel> {
  @override
  void initState() {
    super.initState();
    widget.printer.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.printer.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _openPairDialog() async {
    final l = AppLocalizations.of(context);
    final ipCtrl = TextEditingController(text: widget.printer.ip ?? '');
    final codeCtrl = TextEditingController(); // Code NICHT prefillen
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.pairDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipCtrl,
              autofocus: true,
              decoration: InputDecoration(labelText: l.pairDialogIp),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: codeCtrl,
              obscureText: true,
              decoration: InputDecoration(labelText: l.pairDialogCode),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.pairDialogCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.pairDialogSave)),
        ],
      ),
    );
    ipCtrl.dispose();
    final code = codeCtrl.text;
    codeCtrl.dispose();
    if (ok != true || ipCtrl.text.isEmpty || code.isEmpty) return;
    await widget.printer.savePairing(ip: ipCtrl.text.trim(), accessCode: code);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = widget.printer;
    final busy = p.connection == CanvasConnection.discovering ||
        p.connection == CanvasConnection.connecting ||
        p.connection == CanvasConnection.registering;

    return WorkshopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l.projectPrinterSection,
                style: theme.textTheme.bodySmall),
          ),
          _statusLine(context),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _openPairDialog,
                  icon: const Icon(Icons.key_outlined),
                  label: Text(l.projectPrinterPair),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (busy || p.ip == null)
                      ? null
                      : () => p.connectAndLoad(),
                  icon: const Icon(Icons.wifi_tethering),
                  label: Text(l.projectPrinterConnect),
                ),
              ),
            ],
          ),
          if (p.slots.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Text(l.projectFilaments,
                  style: theme.textTheme.bodySmall),
            ),
            ..._slotRows(context, p),
          ],
        ],
      ),
    );
  }

  Widget _statusLine(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = widget.printer;
    final (icon, text, color) = switch (p.connection) {
      CanvasConnection.disconnected => p.ip == null
          ? (Icons.help_outline, l.projectPrinterNotPaired, WorkshopTokens.textMuted)
          : (Icons.wifi_off, p.ip ?? '', WorkshopTokens.textMuted),
      CanvasConnection.discovering || CanvasConnection.connecting || CanvasConnection.registering =>
        (Icons.sync, l.projectPrinterConnecting, WorkshopTokens.textMuted),
      CanvasConnection.connected => (
          Icons.check_circle_outline,
          l.projectPrinterConnected(p.discovery?.hostName ?? p.ip ?? ''),
          WorkshopTokens.accent,
        ),
      CanvasConnection.authError => (
          Icons.lock_outline,
          l.projectPrinterAuthError,
          const Color(0xFFFF6B6B),
        ),
      CanvasConnection.networkError => (
          Icons.error_outline,
          l.projectPrinterNetError(p.lastError ?? '-'),
          const Color(0xFFFF6B6B),
        ),
    };
    final info = p.discovery;
    final lanHint = (info != null && !info.lanOnly) &&
        (p.connection == CanvasConnection.authError ||
         p.connection == CanvasConnection.networkError);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ]),
        if (lanHint)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 26),
            child: Text(l.projectPrinterLanOffHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: WorkshopTokens.textMuted)),
          ),
      ],
    );
  }

  List<Widget> _slotRows(BuildContext context, PrinterState p) {
    return p.slots.map((s) {
      final selected = p.trayAssignmentForTool0 == s.trayId;
      return InkWell(
        onTap: () => p.setTrayAssignmentForTool0(s.trayId),
        borderRadius: BorderRadius.circular(WorkshopTokens.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: selected
                      ? WorkshopTokens.accent.withValues(alpha: 0.18)
                      : null,
                  border: Border.all(
                      color: selected
                          ? WorkshopTokens.accent
                          : WorkshopTokens.border),
                  borderRadius: BorderRadius.circular(WorkshopTokens.radiusSmall),
                ),
                alignment: Alignment.center,
                child: Text(s.slotLabel,
                    style: monoStyle(context,
                        fontSize: 12,
                        color: selected
                            ? WorkshopTokens.accent
                            : WorkshopTokens.textMuted,
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 10),
              Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  color: _parseColor(s.filamentColor),
                  border: Border.all(color: WorkshopTokens.border),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${s.filamentType} · ${s.filamentName}',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Color _parseColor(String hex) {
    final h = hex.replaceAll('#', '').toUpperCase();
    if (h.length != 6) return WorkshopTokens.border;
    final r = int.parse(h.substring(0, 2), radix: 16);
    final g = int.parse(h.substring(2, 4), radix: 16);
    final b = int.parse(h.substring(4, 6), radix: 16);
    return Color.fromARGB(255, r, g, b);
  }
}
