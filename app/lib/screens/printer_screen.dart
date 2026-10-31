import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../net/elegoo_cc2_client.dart';
import '../state/printer_state.dart';
import '../widgets/printer_camera_panel.dart';
import '../widgets/printer_files_panel.dart';
import '../widgets/workshop_card.dart';

/// Welcher Reiter-Unterbereich sichtbar ist. Steuert u. a. das
/// Starten/Stoppen des Kamera-Streams.
enum PrinterSection { files, history, camera }

// Phase 5: Reiter „Drucker".
//
// Zeigt die Druckhistorie aus `method 1036` und bietet pro Eintrag
// die passenden Aktionen:
//
//   video_status=0 → nur Zeile mit „kein Zeitraffer"
//   video_status=1 → Button „Video erzeugen" (method 1051), Spinner
//                    waehrend `machine_status.status==12`, Erfolg
//                    nur ueber zweite 1036 + Head-Probe.
//   video_status=2 → Head-Probe (max 2 s). Nur bei HTTP 200 kommt der
//                    Download-Button; sonst „nicht mehr verfuegbar".
//   video_status=3 → „nicht erzeugbar".
//
// Zeitstempel aus `begin_time`/`end_time` werden nur als Reihenfolge-
// Schluessel gelesen (Druckeruhr steht laut docs/networking-cc2.md
// aktuell auf UTC+8). Angezeigt wird nur die relative Dauer.
class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key, required this.printerState});

  final PrinterState printerState;

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

enum _VideoAvailability { unknown, checking, available, unavailable }

class _TaskUiState {
  _TaskUiState();
  _VideoAvailability videoAvail = _VideoAvailability.unknown;
  int? probedBytes;
  bool rendering = false;
  String? renderError;
  bool downloading = false;
  double? downloadProgress; // 0..1
  String? downloadedPath;
  String? galleryUri; // MediaStore-content-URI; null, wenn nicht abgelegt
  String? downloadError;
}

class _PrinterScreenState extends State<PrinterScreen>
    with WidgetsBindingObserver {
  // Platform-Channel fuer Android-native-Hilfen (MediaStore, nativeLibraryDir).
  static const MethodChannel _engineChannel =
      MethodChannel('dev.handslice.handslice/engine');

  // Welcher Unterbereich oben per SegmentedButton gewaehlt ist.
  PrinterSection _section = PrinterSection.files;
  bool _appResumed = true;

  List<HistoryTask> _tasks = const [];
  bool _loading = false;
  // true, sobald `method 1036` einmal erfolgreich durchgelaufen ist.
  // Bevor das passiert ist, zeigt die UI "nicht verbunden" statt
  // "keine Drucke" (Phase-4.4-Nacharbeit: Klaus beobachtete, dass
  // der Reiter "Noch keine Drucke" meldete, obwohl die MQTT-Session
  // noch gar nicht stand).
  bool _hasFetched = false;
  String? _error;
  final Map<String, _TaskUiState> _ui = {};

  // Semaphore: hoechstens zwei parallele /download-Verbindungen zum
  // Drucker (die cc2-control-eigene „two-transfer limit"-Regel).
  final _DownloadLimiter _limiter = _DownloadLimiter(maxConcurrent: 2);

  // Aktuelle Render-Watch: welches Target gerade gerendert wird
  // (zur Status-12-Auswertung aus printerState).
  String? _renderingTaskId;
  StreamSubscription<Map<String, dynamic>>? _statusSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.printerState.addListener(_onStateChanged);
    _statusSub = widget.printerState.client.statusDeltas.listen((_) {
      if (mounted) setState(() {});
    });
    _loadIfReady();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.printerState.removeListener(_onStateChanged);
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed != _appResumed) {
      setState(() => _appResumed = resumed);
    }
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
    _loadIfReady();
  }

  bool _firstLoadAttempted = false;
  void _loadIfReady() {
    if (_firstLoadAttempted) return;
    if (widget.printerState.connection != CanvasConnection.connected) return;
    _firstLoadAttempted = true;
    scheduleMicrotask(_refresh);
  }

  _TaskUiState _state(String id) => _ui.putIfAbsent(id, _TaskUiState.new);

  Future<void> _refresh() async {
    final client = widget.printerState.client;
    if (!client.isConnected) return;
    setState(() { _loading = true; _error = null; });
    try {
      final list = await client.getHistory();
      // Neueste zuerst (begin_time absteigend). Als Ordnungsschluessel
      // verwendet, nicht als Datum.
      list.sort((a, b) => b.beginTime.compareTo(a.beginTime));
      if (!mounted) return;
      setState(() {
        _tasks = list;
        _loading = false;
        _hasFetched = true;
      });
      // Fuer alle Status-2-Eintraege Head-Probe anstossen.
      for (final t in list) {
        if (t.hasVideo) {
          final ui = _state(t.taskId);
          if (ui.videoAvail == _VideoAvailability.unknown) {
            _probe(t);
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _probe(HistoryTask t) async {
    final ui = _state(t.taskId);
    setState(() => ui.videoAvail = _VideoAvailability.checking);
    try {
      final probe = await _limiter.run(() =>
          widget.printerState.client.probeTimelapse(t.videoUrl));
      if (!mounted) return;
      setState(() {
        ui.videoAvail = probe.ok
            ? _VideoAvailability.available
            : _VideoAvailability.unavailable;
        ui.probedBytes = probe.contentLength;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => ui.videoAvail = _VideoAvailability.unavailable);
    }
  }

  Future<void> _download(HistoryTask t) async {
    final ui = _state(t.taskId);
    setState(() { ui.downloading = true; ui.downloadProgress = 0;
                   ui.downloadError = null; ui.downloadedPath = null; });
    try {
      final bytes = await _limiter.run(() =>
          widget.printerState.client.downloadTimelapse(
            t.videoUrl,
            expectedBytes: t.videoSize,
            onProgress: (recv, total) {
              if (!mounted) return;
              final denom = total ?? t.videoSize;
              if (denom > 0) {
                setState(() => ui.downloadProgress = recv / denom);
              }
            },
          ));
      // Datei zuerst in den app-eigenen Downloads-Pfad schreiben
      // (fuer Share + Fallback), dann via MediaStore nach
      // Movies/Handslice spiegeln (sichtbar in der Galerie,
      // ueberlebt Deinstallation).
      final base = t.videoUrl.split('/').last;
      final dir = await _downloadDirectory();
      final file = File('${dir.path}/$base');
      await file.writeAsBytes(bytes, flush: true);
      String? galleryUri;
      if (Platform.isAndroid) {
        try {
          galleryUri = await _engineChannel.invokeMethod<String>(
            'saveVideoToGallery',
            {'srcPath': file.path, 'displayName': base, 'mime': 'video/mp4'},
          );
        } on PlatformException catch (e) {
          // Kein Deal-Breaker: Datei liegt wenigstens app-lokal.
          debugPrint('saveVideoToGallery failed: ${e.code} ${e.message}');
        }
      }
      if (!mounted) return;
      setState(() {
        ui.downloading = false;
        ui.downloadProgress = 1.0;
        ui.downloadedPath = file.path;
        ui.galleryUri = galleryUri;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { ui.downloading = false; ui.downloadError = e.toString(); });
    }
  }

  Future<Directory> _downloadDirectory() async {
    // Android: /storage/emulated/0/Download ist nicht garantiert
    // beschreibbar ohne spezielle Permissions. path_provider stellt
    // getExternalStorageDirectory bereit (app-eigener Downloads-Pfad).
    // Fallback: ApplicationSupport.
    if (Platform.isAndroid) {
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final sub = Directory('${ext.path}/handslice-timelapses');
          if (!sub.existsSync()) sub.createSync(recursive: true);
          return sub;
        }
      } catch (_) {}
    }
    final supp = await getApplicationSupportDirectory();
    final sub = Directory('${supp.path}/timelapses');
    if (!sub.existsSync()) sub.createSync(recursive: true);
    return sub;
  }

  Future<void> _share(_TaskUiState ui) async {
    final p = ui.downloadedPath;
    if (p == null) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(p)]));
  }

  Future<void> _render(HistoryTask t) async {
    final ui = _state(t.taskId);
    setState(() { ui.rendering = true; ui.renderError = null;
                   _renderingTaskId = t.taskId; });
    try {
      await widget.printerState.client.renderTimelapse(t.videoUrl);
      // Jetzt auf Status 12 → 1 warten. docs: Status 12 ist
      // "Zeitraffer wird erzeugt/exportiert". Erfolg validieren per
      // 1036 + Head-Probe.
      await _waitForRenderDone();
      await _refresh();
      final updated = _tasks.firstWhere(
        (x) => x.taskId == t.taskId,
        orElse: () => t,
      );
      if (updated.hasVideo) {
        await _probe(updated);
        final avail = _state(updated.taskId).videoAvail;
        if (avail != _VideoAvailability.available) {
          _state(updated.taskId).renderError = 'no_frames';
        }
      } else {
        // Status blieb auf 1 oder 3 → kein Composite stattgefunden
        _state(updated.taskId).renderError = 'no_frames';
      }
    } catch (e) {
      _state(t.taskId).renderError = e.toString();
    } finally {
      if (mounted) {
        setState(() { _state(t.taskId).rendering = false;
                      _renderingTaskId = null; });
      }
    }
  }

  Future<void> _waitForRenderDone() async {
    // Beobachte machine_status.status; bei Rueckkehr auf 1 fertig.
    // Timeout 10 min (laut cc2-control-Fenster).
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    bool sawTwelve = false;
    while (DateTime.now().isBefore(deadline)) {
      final s = widget.printerState.machineStatus;
      if (s == 12) sawTwelve = true;
      if (sawTwelve && s == 1) return;
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // "verbunden" fuer die Anzeige = der Reiter hat tatsaechlich schon
    // eine 1036-Antwort bekommen. Allein `CanvasConnection.connected`
    // reicht nicht: direkt nach dem Oeffnen (vor dem ersten _refresh)
    // oder nach einem Verbindungsabbruch der kein Status-Update
    // ausloeste, wuerde sonst "Noch keine Drucke" angezeigt – obwohl
    // in Wirklichkeit nur niemand mit dem Drucker gesprochen hat.
    final connected =
        widget.printerState.connection == CanvasConnection.connected &&
            _hasFetched;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(l),
        _sectionSwitcher(l),
        if (!connected)
          Expanded(child: _notConnectedView(l))
        else
          Expanded(child: _bodyForSection(l)),
      ],
    );
  }

  Widget _sectionSwitcher(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SegmentedButton<PrinterSection>(
        segments: [
          ButtonSegment(
              value: PrinterSection.files,
              icon: const Icon(Icons.folder_open),
              label: Text(l.printerSectionFiles)),
          ButtonSegment(
              value: PrinterSection.history,
              icon: const Icon(Icons.history),
              label: Text(l.printerSectionHistory)),
          ButtonSegment(
              value: PrinterSection.camera,
              icon: const Icon(Icons.videocam_outlined),
              label: Text(l.printerSectionCamera)),
        ],
        selected: {_section},
        onSelectionChanged: (s) => setState(() => _section = s.first),
      ),
    );
  }

  Widget _bodyForSection(AppLocalizations l) {
    switch (_section) {
      case PrinterSection.files:
        return PrinterFilesPanel(
          printerState: widget.printerState,
          downloadLimiter: _limiter.run,
        );
      case PrinterSection.history:
        return _historyView(l);
      case PrinterSection.camera:
        return SingleChildScrollView(
          child: PrinterCameraPanel(
            printerState: widget.printerState,
            visible: _section == PrinterSection.camera,
            appResumed: _appResumed,
          ),
        );
    }
  }

  Widget _header(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.printerHistoryHeading,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            tooltip: l.printerHistoryRefresh,
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _notConnectedView(AppLocalizations l) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.print_disabled_outlined, size: 48),
            const SizedBox(height: 12),
            Text(l.printerNotConnected,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l.printerConnectHint,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _historyView(AppLocalizations l) {
    if (_loading && _tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      );
    }
    if (_tasks.isEmpty) {
      return Center(child: Text(l.printerHistoryEmpty));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(l.printerHistoryClock,
                  style: Theme.of(context).textTheme.bodySmall),
            );
          }
          final t = _tasks[i - 1];
          return _taskCard(l, t);
        },
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemCount: _tasks.length + 1,
      ),
    );
  }

  Widget _taskCard(AppLocalizations l, HistoryTask t) {
    final ui = _state(t.taskId);
    final minutes = (t.durationSeconds / 60).round();
    return WorkshopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  t.taskName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _taskStatusChip(l, t),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.schedule, size: 16),
              const SizedBox(width: 4),
              Text(l.printerDurationShort(minutes)),
              const SizedBox(width: 16),
              Expanded(child: _videoRow(l, t, ui)),
            ],
          ),
          _actionsRow(l, t, ui),
        ],
      ),
    );
  }

  Widget _taskStatusChip(AppLocalizations l, HistoryTask t) {
    final text = switch (t.taskStatus) {
      1 => l.printerTaskStatusCompleted,
      2 => l.printerTaskStatusCancelled,
      3 => l.printerTaskStatusFailed,
      _ => l.printerTaskStatusUnknown(t.taskStatus),
    };
    final bg = switch (t.taskStatus) {
      1 => Colors.green.withOpacity(0.15),
      2 => Colors.amber.withOpacity(0.15),
      3 => Theme.of(context).colorScheme.error.withOpacity(0.15),
      _ => Theme.of(context).colorScheme.surfaceContainerHighest,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }

  Widget _videoRow(AppLocalizations l, HistoryTask t, _TaskUiState ui) {
    IconData icon;
    String text;
    Color? color;
    switch (t.videoStatus) {
      case 2:
        icon = Icons.movie;
        text = l.printerVideoReady;
        color = Colors.green;
        break;
      case 1:
        icon = Icons.photo_library_outlined;
        text = l.printerVideoRenderable;
        break;
      case 3:
        icon = Icons.movie_filter_outlined;
        text = l.printerVideoNotRenderable;
        color = Theme.of(context).colorScheme.outline;
        break;
      default:
        icon = Icons.videocam_off_outlined;
        text = l.printerVideoNone;
        color = Theme.of(context).colorScheme.outline;
    }
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Expanded(child: Text(text,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }

  Widget _actionsRow(AppLocalizations l, HistoryTask t, _TaskUiState ui) {
    final buttons = <Widget>[];

    // 1051-Pfad bei status 1 oder 3-mit-URL
    if (t.isRenderable) {
      if (ui.rendering || _renderingTaskId == t.taskId) {
        buttons.add(_pendingPill(l.printerRenderStarted));
      } else {
        buttons.add(FilledButton.tonalIcon(
          onPressed: () => _render(t),
          icon: const Icon(Icons.auto_awesome),
          label: Text(l.printerRenderButton),
        ));
      }
    }

    // Status 3 ohne URL = nicht erzeugbar
    if (t.videoStatus == 3 && !t.videoUrl.startsWith('picture/')) {
      buttons.add(_notePill(l.printerRenderNotPossible,
          color: Theme.of(context).colorScheme.outline));
    }

    // Status 2 → Head-Probe & Download
    if (t.hasVideo) {
      switch (ui.videoAvail) {
        case _VideoAvailability.unknown:
        case _VideoAvailability.checking:
          buttons.add(_pendingPill(l.printerDownloadCheck));
          break;
        case _VideoAvailability.unavailable:
          buttons.add(_notePill(l.printerDownloadUnavailable,
              color: Colors.amber));
          break;
        case _VideoAvailability.available:
          if (ui.downloading) {
            buttons.add(_downloadProgress(l, ui));
          } else if (ui.downloadedPath != null) {
            buttons.add(FilledButton.icon(
              onPressed: () => _share(ui),
              icon: const Icon(Icons.share),
              label: Text(l.printerShareButton),
            ));
          } else {
            buttons.add(FilledButton.icon(
              onPressed: () => _download(t),
              icon: const Icon(Icons.download),
              label: Text(l.printerDownloadButton),
            ));
          }
      }
    }

    if (ui.renderError != null) {
      final msg = ui.renderError == 'no_frames'
          ? l.printerRenderNoFrames
          : l.printerRenderFailed(ui.renderError!);
      buttons.add(_notePill(msg, color: Theme.of(context).colorScheme.error));
    }
    if (ui.downloadError != null) {
      buttons.add(_notePill(
          l.printerDownloadFailed(ui.downloadError!),
          color: Theme.of(context).colorScheme.error));
    }
    if (ui.downloadedPath != null) {
      final msg = ui.galleryUri != null
          ? l.printerDownloadDoneGallery
          : l.printerDownloadDone(ui.downloadedPath!);
      buttons.add(_notePill(msg,
          color: Theme.of(context).colorScheme.outline));
    }

    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 8, runSpacing: 6, children: buttons),
    );
  }

  Widget _pendingPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }

  Widget _notePill(String text, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text,
          style: Theme.of(context).textTheme.bodySmall),
    );
  }

  Widget _downloadProgress(AppLocalizations l, _TaskUiState ui) {
    final p = ui.downloadProgress;
    return SizedBox(
      width: 160,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.printerDownloadStarted,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: p),
        ],
      ),
    );
  }
}

// Simpler Semaphor: hoechstens maxConcurrent Jobs gleichzeitig.
class _DownloadLimiter {
  _DownloadLimiter({required this.maxConcurrent});
  final int maxConcurrent;
  int _active = 0;
  final _queue = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() op) async {
    if (_active >= maxConcurrent) {
      final c = Completer<void>();
      _queue.add(c);
      await c.future;
    }
    _active++;
    try {
      return await op();
    } finally {
      _active--;
      if (_queue.isNotEmpty) _queue.removeAt(0).complete();
    }
  }
}
