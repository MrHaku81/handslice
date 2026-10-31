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
  bool _fullscreenOpen = false;

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

  Future<void> _openFullscreen() async {
    final url = _url;
    if (url == null) return;
    setState(() { _fullscreenOpen = true; });
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _CameraFullscreen(
            url: url,
            appResumed: widget.appResumed,
          ),
          fullscreenDialog: true,
        ),
      );
    } finally {
      if (mounted) setState(() { _fullscreenOpen = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Panel-Stream pausiert, waehrend Vollbild offen ist – damit nicht
    // zwei HTTP-Streams gleichzeitig geoeffnet werden.
    final active = widget.visible && widget.appResumed && !_fullscreenOpen;
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
                clipBehavior: Clip.antiAlias,
                // Tap: Vollbild oeffnen (nur wenn eine URL vorliegt
                // und der Stream aktiv waere).
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap:
                      (_url != null && connected) ? _openFullscreen : null,
                  child: _buildViewport(l, connected, active),
                ),
              ),
            ),
            if (_url != null && connected) ...[
              const SizedBox(height: 6),
              Text(
                active ? l.printerCameraTapHint : l.printerCameraPaused,
                style: theme.textTheme.bodySmall,
              ),
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

// Vollbild-Overlay: fuellt den Screen bis zum Rand, Tap/Back
// schliesst. Lifecycle-Hook synct `appResumed` ueber den eigenen
// WidgetsBindingObserver, damit der Stream auch im Vollbild sauber
// stoppt, wenn der Nutzer in die Statusleiste wechselt.
class _CameraFullscreen extends StatefulWidget {
  const _CameraFullscreen({required this.url, required this.appResumed});
  final String url;
  final bool appResumed;
  @override
  State<_CameraFullscreen> createState() => _CameraFullscreenState();
}

class _CameraFullscreenState extends State<_CameraFullscreen>
    with WidgetsBindingObserver {
  late bool _resumed = widget.appResumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final r = state == AppLifecycleState.resumed;
    if (r != _resumed) setState(() => _resumed = r);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: Center(
                  child: MjpegViewer(
                    url: widget.url,
                    active: _resumed,
                    errorBuilder: (msg) => _CenterIcon(
                      icon: Icons.videocam_off_outlined,
                      text: l.printerCameraStreamError(msg),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8, right: 8,
              child: IconButton(
                tooltip: l.printerCameraFullscreenClose,
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
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
