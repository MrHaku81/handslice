// Pflicht 5: Live-Kamera (MJPEG) im Reiter „Drucker".
//
// - URL via method 1042 (GetLivingVideoUrl); kein 1054-Call
//   (Block-A-Beleg 2026-10-31: 1054 lehnt {enable} ab, der Server
//   auf :8080 laeuft permanent).
// - Stream nur aktiv wenn `visible` UND die App im Vordergrund ist.
// - Fehlerzustand explizit (nie schwarzes Bild).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../net/elegoo_cc2_client.dart';
import '../state/printer_state.dart';
import 'mjpeg_viewer.dart';
import 'workshop_card.dart';

class PrinterCameraPanel extends StatefulWidget {
  const PrinterCameraPanel({
    super.key,
    required this.printerState,
    required this.visible,
    required this.appResumed,
  });
  final PrinterState printerState;
  final bool visible;
  final bool appResumed;

  @override
  State<PrinterCameraPanel> createState() => _PrinterCameraPanelState();
}

class _PrinterCameraPanelState extends State<PrinterCameraPanel> {
  String? _url;
  String? _err;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.printerState.addListener(_onPrinter);
    _fetchUrlIfConnected();
  }

  @override
  void dispose() {
    widget.printerState.removeListener(_onPrinter);
    super.dispose();
  }

  void _onPrinter() {
    if (!mounted) return;
    setState(() {});
    _fetchUrlIfConnected();
  }

  Future<void> _fetchUrlIfConnected() async {
    if (_url != null) return;
    if (_loading) return;
    if (widget.printerState.connection != CanvasConnection.connected) return;
    setState(() { _loading = true; _err = null; });
    try {
      final r = await widget.printerState.client.getLivingVideoUrl();
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (r.ok && r.url.isNotEmpty) {
          _url = r.url;
        } else {
          _err = 'error_code=${r.errorCode}';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _err = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final active = widget.visible && widget.appResumed;
    final connected =
        widget.printerState.connection == CanvasConnection.connected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: WorkshopCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.printerCameraHeading, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildViewport(l, connected, active),
              ),
            ),
            if (!active && _url != null && connected) ...[
              const SizedBox(height: 6),
              Text(l.printerCameraPaused, style: theme.textTheme.bodySmall),
            ],
            if (_err != null) ...[
              const SizedBox(height: 6),
              Text(l.printerCameraNoUrlDetail(_err!),
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildViewport(AppLocalizations l, bool connected, bool active) {
    if (!connected) {
      return _CenterIcon(
          icon: Icons.print_disabled_outlined,
          text: l.printerNotConnected);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_err != null) {
      return _CenterIcon(
          icon: Icons.error_outline, text: l.printerCameraNoUrl);
    }
    final url = _url;
    if (url == null) {
      return _CenterIcon(
          icon: Icons.videocam_outlined, text: l.printerCameraLoading);
    }
    if (!active) {
      return _CenterIcon(
          icon: Icons.pause_circle_outline, text: l.printerCameraPaused);
    }
    return MjpegViewer(
      url: url,
      active: true,
      placeholder: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            Text(l.printerCameraLoading),
          ],
        ),
      ),
      errorBuilder: (msg) => _CenterIcon(
        icon: Icons.videocam_off_outlined,
        text: l.printerCameraStreamError(msg),
      ),
    );
  }
}

class _CenterIcon extends StatelessWidget {
  const _CenterIcon({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
