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
    // Dialog als eigener StatefulWidget – die TextEditingController leben
    // im State des Dialogs, werden also erst in dessen dispose() freigegeben
    // (nach Pop-Animation). Fruehere Variante hatte die Controller im outer
    // State und rief .dispose() direkt nach `await showDialog`; das triggert
    // _dependents.isEmpty-Assert, weil die TextField-Elements im Dialog-Tree
    // noch nicht abgebaut waren. Zusaetzlich wurde ipCtrl.text nach
    // ipCtrl.dispose() gelesen (use-after-dispose).
    final r = await showDialog<PairResult>(
      context: context,
      builder: (_) => _PairDialog(initialIp: widget.printer.ip ?? ''),
    );
    if (!mounted || r == null) return;
    if (r.ip.isEmpty || r.code.isEmpty) return;
    await widget.printer.savePairing(ip: r.ip, accessCode: r.code);
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

/// Rueckgabe aus dem Pair-Dialog. `null` entspricht Abbrechen.
class PairResult {
  const PairResult({required this.ip, required this.code});
  final String ip;
  final String code;
}

class _PairDialog extends StatefulWidget {
  const _PairDialog({required this.initialIp});
  final String initialIp;

  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  late final TextEditingController _ip;
  late final TextEditingController _code;
  String? _ipError;

  @override
  void initState() {
    super.initState();
    // Vorbelegung nur uebernehmen, wenn sie wie eine IP/Hostname aussieht.
    // Realfall 2026-10-25: ein frueherer Lauf hatte den Modellnamen
    // ("Elegoo CC2 Combo") im Feld – Validierung muss das jetzt erkennen,
    // sowohl beim Oeffnen (keine Mist-Vorbelegung) als auch beim Speichern.
    _ip = TextEditingController(
      text: _looksLikeHost(widget.initialIp) ? widget.initialIp : '',
    );
    _code = TextEditingController();
    _ip.addListener(_revalidate);
    _code.addListener(_revalidate);
  }

  @override
  void dispose() {
    _ip.removeListener(_revalidate);
    _code.removeListener(_revalidate);
    // Wird gerufen, nachdem die Pop-Animation durch ist – die TextField-
    // Elements sind dann vollstaendig unmounted. Keine _dependents mehr.
    _ip.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _ipValid => _looksLikeHost(_ip.text.trim());
  bool get _canSave => _ipValid && _code.text.isNotEmpty;

  void _revalidate() {
    // Bei jeder Eingabeaenderung rebuilden – sowohl Fehlertext als
    // auch Save-Button-Zustand haengen davon ab.
    if (!mounted) return;
    setState(() {
      _ipError = (_ip.text.isNotEmpty && !_ipValid) ? 'invalid' : null;
    });
  }

  void _submit() {
    if (!_canSave) return;
    Navigator.pop(
      context,
      PairResult(ip: _ip.text.trim(), code: _code.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final errorText =
        _ipError == null ? null : l.pairDialogIpInvalid;
    return AlertDialog(
      title: Text(l.pairDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ip,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const <String>[],
            decoration: InputDecoration(
              labelText: l.pairDialogIp,
              errorText: errorText,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            obscureText: true,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const <String>[],
            decoration: InputDecoration(labelText: l.pairDialogCode),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<PairResult>(context, null),
          child: Text(l.pairDialogCancel),
        ),
        FilledButton(
          onPressed: _canSave ? _submit : null,
          child: Text(l.pairDialogSave),
        ),
      ],
    );
  }
}

// Validierung: entweder IPv4 (vier Oktette 0–255) oder Hostname-Label-
// Kette (RFC 1123, vereinfacht). Reicht fuer das LAN-Pair-Feld und
// deckt den Realfall ab, in dem jemand/etwas den Modellnamen einfuegt.
bool _looksLikeHost(String raw) {
  final s = raw.trim();
  if (s.isEmpty || s.length > 253) return false;
  if (s.contains(' ')) return false;
  // IPv4
  final ipParts = s.split('.');
  if (ipParts.length == 4 &&
      ipParts.every((p) {
        final n = int.tryParse(p);
        return n != null && n >= 0 && n <= 255 && p == n.toString();
      })) {
    return true;
  }
  // Hostname: Labels [a-z0-9] + optional '-' (nicht am Rand), 1–63 Zeichen,
  // Punkte als Trenner. Keine Umlaute (CC2 hat eh ASCII-Hostnamen).
  final label = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$');
  for (final part in s.split('.')) {
    if (!label.hasMatch(part)) return false;
  }
  return true;
}
