// Pflicht 4: Dateiverwaltung auf dem CC2.
//
// - 1044 fuer die Liste, 1045 fuer Thumbnails (lazy, on-demand),
//   1046 fuer Details (bisher nicht gebraucht; falls spaeter das
//   UI mehr Felder zeigen soll).
// - Drucken: ruft `PrinterState.startPrintFile` – gleicher Flow
//   wie Upload+Druck, inkl. Nivellieren/Zeitraffer-Switches und
//   Sichtkontroll-Hinweis.
// - Herunterladen: `/download` mit Head-Probe und einem geteilten
//   DownloadLimiter (max 2 gleichzeitig), Zieldatei unter
//   /storage/.../handslice-downloads.
// - Loeschen: 1047 mit Bestaetigungsdialog; UI blockiert das
//   Loeschen der aktiven Druckdatei grundsaetzlich.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';
import '../net/elegoo_cc2_client.dart';
import '../state/printer_state.dart';
import 'workshop_card.dart';

typedef DownloadLimiter = Future<T> Function<T>(Future<T> Function() op);

class PrinterFilesPanel extends StatefulWidget {
  const PrinterFilesPanel({
    super.key,
    required this.printerState,
    required this.downloadLimiter,
  });
  final PrinterState printerState;
  final DownloadLimiter downloadLimiter;

  @override
  State<PrinterFilesPanel> createState() => _PrinterFilesPanelState();
}

class _PrinterFilesPanelState extends State<PrinterFilesPanel> {
  List<RemoteFile> _files = const [];
  bool _loading = false;
  String? _error;
  final Map<String, Uint8List?> _thumbs = {}; // null = tried + unavailable
  final Set<String> _thumbPending = {};
  final Set<String> _downloading = {};
  final Map<String, String> _downloaded = {}; // filename -> path
  final Map<String, String> _downloadErr = {};
  final Set<String> _deleting = {};

  @override
  void initState() {
    super.initState();
    widget.printerState.addListener(_onPrinter);
    _refreshIfConnected();
  }

  @override
  void dispose() {
    widget.printerState.removeListener(_onPrinter);
    super.dispose();
  }

  void _onPrinter() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _refreshIfConnected() async {
    if (widget.printerState.connection != CanvasConnection.connected) return;
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await widget.printerState.client.getFileList();
      list.sort((a, b) => b.createTime.compareTo(a.createTime));
      if (!mounted) return;
      setState(() {
        _files = list;
        _loading = false;
      });
      for (final f in list) {
        if (_thumbs.containsKey(f.filename)) continue;
        if (_thumbPending.contains(f.filename)) continue;
        _loadThumb(f.filename);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _loadThumb(String name) async {
    _thumbPending.add(name);
    try {
      final t =
          await widget.printerState.client.getFileThumbnail(name);
      if (!mounted) return;
      setState(() {
        if (t.ok && t.base64Png != null) {
          try {
            _thumbs[name] = base64Decode(t.base64Png!);
          } catch (_) {
            _thumbs[name] = null;
          }
        } else {
          _thumbs[name] = null; // 1015 ThumbnailNotExist etc. – kein Preview
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _thumbs[name] = null; });
    } finally {
      _thumbPending.remove(name);
    }
  }

  Future<Directory> _downloadDir() async {
    if (Platform.isAndroid) {
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final sub = Directory('${ext.path}/handslice-downloads');
          if (!sub.existsSync()) sub.createSync(recursive: true);
          return sub;
        }
      } catch (_) {}
    }
    final supp = await getApplicationSupportDirectory();
    final sub = Directory('${supp.path}/downloads');
    if (!sub.existsSync()) sub.createSync(recursive: true);
    return sub;
  }

  Future<void> _download(RemoteFile f) async {
    final l = AppLocalizations.of(context);
    setState(() { _downloading.add(f.filename); _downloadErr.remove(f.filename); });
    try {
      // Head-Probe: wenn der Drucker still schweigt, meldet die
      // Probe `ok=false` und wir brechen den Download gleich ab.
      final probe = await widget.downloadLimiter(() =>
          widget.printerState.client.probeFile(f.filename));
      if (!probe.ok) {
        if (!mounted) return;
        setState(() {
          _downloading.remove(f.filename);
          _downloadErr[f.filename] = l.printerFilesDownloadUnavailable;
        });
        return;
      }
      final bytes = await widget.downloadLimiter(() =>
          widget.printerState.client.downloadFile(
            f.filename,
            expectedBytes: f.sizeBytes,
          ));
      final dir = await _downloadDir();
      final out = File('${dir.path}/${f.filename}');
      await out.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() {
        _downloading.remove(f.filename);
        _downloaded[f.filename] = out.path;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading.remove(f.filename);
        _downloadErr[f.filename] = e.toString();
      });
    }
  }

  Future<void> _delete(RemoteFile f) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.printerFilesDeleteConfirmTitle),
        content: Text(l.printerFilesDeleteConfirmBody(f.filename)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.printerFilesDeleteConfirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.printerFilesDeleteConfirmYes),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() { _deleting.add(f.filename); });
    try {
      final code = await widget.printerState.deleteFile(f.filename);
      if (!mounted) return;
      if (code == 0) {
        // frisch listen – zuerst Lokal-Status aktualisieren, dann
        // 1044 neu holen, damit die UI die Datei weg sieht.
        _thumbs.remove(f.filename);
        _downloaded.remove(f.filename);
        _downloadErr.remove(f.filename);
        setState(() { _deleting.remove(f.filename); });
        await _refresh();
      } else {
        setState(() {
          _deleting.remove(f.filename);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _deleting.remove(f.filename); });
    }
  }

  Future<void> _printDialog(RemoteFile f) async {
    final result = await showDialog<_PrintChoice>(
      context: context,
      builder: (ctx) => _PrintSettingsDialog(filename: f.filename,
                                             printerState: widget.printerState),
    );
    if (result == null || !mounted) return;
    final r = await widget.printerState.startPrintFile(
      filename: f.filename,
      bedlevelForce: result.bedLevel,
      printerCheck: result.printerCheck,
      enableTimelapse: result.timelapse,
    );
    if (!mounted || r == null) return;
    // Erfolg zeigt sich im Live-Status; wir setzen hier nichts weiter.
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_loading && _files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorState(
          error: _error!, onRetry: _refresh, retryLabel: l.printerFilesRefresh);
    }
    if (_files.isEmpty) {
      return Center(child: Text(l.printerFilesEmpty));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemBuilder: (ctx, i) => _FileRow(
          file: _files[i],
          thumb: _thumbs[_files[i].filename],
          downloading: _downloading.contains(_files[i].filename),
          downloaded: _downloaded[_files[i].filename],
          downloadErr: _downloadErr[_files[i].filename],
          deleting: _deleting.contains(_files[i].filename),
          isRunning:
              widget.printerState.runningFilename == _files[i].filename,
          onDownload: () => _download(_files[i]),
          onDelete: () => _delete(_files[i]),
          onPrint: () => _printDialog(_files[i]),
          canStart:
              widget.printerState.isIdle && !widget.printerState.reconnecting,
        ),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemCount: _files.length,
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.thumb,
    required this.downloading,
    required this.downloaded,
    required this.downloadErr,
    required this.deleting,
    required this.isRunning,
    required this.canStart,
    required this.onDownload,
    required this.onDelete,
    required this.onPrint,
  });

  final RemoteFile file;
  final Uint8List? thumb;
  final bool downloading;
  final String? downloaded;
  final String? downloadErr;
  final bool deleting;
  final bool isRunning;
  final bool canStart;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sizeMb = (file.sizeBytes / 1024 / 1024);
    final sizeText = sizeMb >= 1
        ? '${sizeMb.toStringAsFixed(1)} MB'
        : '${(file.sizeBytes / 1024).toStringAsFixed(0)} kB';
    final mins = file.printTimeSec ~/ 60;
    final hrs = mins ~/ 60;
    final printTimeText = hrs > 0
        ? '${hrs}h ${(mins % 60).toString().padLeft(2, '0')}m'
        : '${mins}m';
    final deleteDisabled = deleting || isRunning;
    return WorkshopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64, height: 64,
                child: thumb != null
                    ? Image.memory(thumb!, fit: BoxFit.contain)
                    : Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: theme.colorScheme.outlineVariant),
                        ),
                        child: const Icon(Icons.insert_drive_file_outlined),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(file.filename,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${l.printerFilesSizeLabel}: $sizeText  ·  '
                      '${l.printerFilesLayersLabel}: ${file.layer}  ·  '
                      '${l.printerFilesPrintTimeLabel}: $printTimeText',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (file.colorMap.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4, runSpacing: 4,
                        children: [
                          for (final c in file.colorMap)
                            _ColorChip(entry: c),
                        ],
                      ),
                    ],
                    if (isRunning) ...[
                      const SizedBox(height: 4),
                      Text(l.printerFilesCurrentPrint,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontStyle: FontStyle.italic)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: (!canStart || isRunning) ? null : onPrint,
                icon: const Icon(Icons.play_arrow_outlined, size: 18),
                label: Text(l.printerFilesPrintButton),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: downloading ? null : onDownload,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text(l.printerFilesDownloadButton),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: isRunning
                  ? l.printerFilesDeleteBlockedRunning
                  : l.printerFilesDeleteButton,
              onPressed: deleteDisabled ? null : onDelete,
              icon: deleting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline),
            ),
          ]),
          if (downloading) ...[
            const SizedBox(height: 6),
            const LinearProgressIndicator(),
          ],
          if (downloaded != null) ...[
            const SizedBox(height: 6),
            Text(l.printerFilesDownloadDone(downloaded!),
                style: theme.textTheme.bodySmall),
          ],
          if (downloadErr != null) ...[
            const SizedBox(height: 6),
            Text(l.printerFilesDownloadFailed(downloadErr!),
                style:
                    theme.textTheme.bodySmall?.copyWith(color: Colors.redAccent)),
          ],
        ],
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({required this.entry});
  final ColorMapEntry entry;
  @override
  Widget build(BuildContext context) {
    Color parse(String hex) {
      final s = hex.replaceAll('#', '');
      if (s.length != 6) return Colors.grey;
      try {
        return Color(int.parse('FF$s', radix: 16));
      } catch (_) { return Colors.grey; }
    }
    final c = parse(entry.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12, height: 12,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black26),
            ),
          ),
          const SizedBox(width: 4),
          Text('${entry.filamentType} · A${entry.toolIndex + 1}',
              style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry, required this.retryLabel});
  final String error;
  final VoidCallback onRetry;
  final String retryLabel;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(retryLabel),
          ),
        ],
      ),
    );
  }
}

class _PrintChoice {
  _PrintChoice(this.bedLevel, this.printerCheck, this.timelapse);
  final bool bedLevel;
  final bool printerCheck;
  final bool timelapse;
}

class _PrintSettingsDialog extends StatefulWidget {
  const _PrintSettingsDialog({required this.filename, required this.printerState});
  final String filename;
  final PrinterState printerState;
  @override
  State<_PrintSettingsDialog> createState() => _PrintSettingsDialogState();
}

class _PrintSettingsDialogState extends State<_PrintSettingsDialog> {
  bool _bedLevel = true;
  bool _printerCheck = true;
  bool _timelapse = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final supportsTl = widget.printerState.supportsTimelapse;
    final currentSlot = widget.printerState.trayAssignmentForTool0;
    return AlertDialog(
      title: Text(l.printerFilesPrintTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.filename,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text('${l.printerFilesPrintSlot}: A${currentSlot + 1}'),
            const SizedBox(height: 10),
            SwitchListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text(l.printBedLeveling),
              value: _bedLevel,
              onChanged: (v) => setState(() => _bedLevel = v),
            ),
            SwitchListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text(l.printPrinterCheck),
              value: _printerCheck,
              onChanged: (v) => setState(() => _printerCheck = v),
            ),
            SwitchListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text(l.printTimelapse),
              value: _timelapse && supportsTl,
              onChanged: supportsTl ? (v) => setState(() => _timelapse = v) : null,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.visibility_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(l.printerFilesVisualCheckHint)),
              ]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.printerFilesPrintCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
              _PrintChoice(_bedLevel, _printerCheck, _timelapse)),
          child: Text(l.printerFilesPrintStart),
        ),
      ],
    );
  }
}
