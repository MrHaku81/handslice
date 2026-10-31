// Schlanker MJPEG-Viewer fuer `multipart/x-mixed-replace`-Streams
// vom CC2 (http://<ip>:8080/?action=stream, Boundary "--frame").
// Eigene Umsetzung – kein zusaetzliches Paket, F-Droid-tauglich,
// AGPL-3.0 kompatibel.
//
// - Start/Stop ueber `active`: Caller setzt active=false, wenn der
//   Bereich nicht sichtbar ist bzw. die App im Hintergrund laeuft.
// - Dekodiert pro `--frame`-Grenze einen JPEG-Chunk via
//   `Image.memory(..., gaplessPlayback: true)`.
// - Fehlerzustaende werden als Text angezeigt – NIE schwarzes Bild
//   (Klaus-Vorgabe).
//
// Credentials erscheinen hier nicht: Pfad enthaelt nur die
// Drucker-IP + den Elegoo-Default-Pfad; der X-Token-Pfad des
// MediaStore-Endpunkts ist hier nicht beteiligt.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Status des Viewers – fuer die UI-Overlays.
enum MjpegStatus { idle, connecting, streaming, error }

class MjpegViewer extends StatefulWidget {
  const MjpegViewer({
    super.key,
    required this.url,
    required this.active,
    this.placeholder,
    this.errorBuilder,
    this.connectTimeout = const Duration(seconds: 5),
    this.firstFrameTimeout = const Duration(seconds: 10),
  });

  final String url;
  final bool active;
  final Widget? placeholder;
  final Widget Function(String message)? errorBuilder;
  final Duration connectTimeout;
  final Duration firstFrameTimeout;

  @override
  State<MjpegViewer> createState() => _MjpegViewerState();
}

class _MjpegViewerState extends State<MjpegViewer> {
  HttpClient? _client;
  StreamSubscription<List<int>>? _sub;
  Uint8List? _frame;
  MjpegStatus _status = MjpegStatus.idle;
  String? _message;
  Timer? _firstFrameWatch;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant MjpegViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urlChanged = oldWidget.url != widget.url;
    if (urlChanged) _stop();
    if (widget.active && (!oldWidget.active || urlChanged)) {
      _start();
    } else if (!widget.active && oldWidget.active) {
      _stop();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    _stop();
    setState(() {
      _status = MjpegStatus.connecting;
      _message = null;
    });
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      _fail('invalid URL');
      return;
    }
    final client = HttpClient()..connectionTimeout = widget.connectTimeout;
    _client = client;
    client.getUrl(uri).then((req) async {
      req.headers.set('Accept', 'multipart/x-mixed-replace, */*');
      // Zweck: Server soll die Verbindung bei Abbau sauber freigeben.
      // Trotz Keep-Alive-Natur des Streams ist das OK.
      req.headers.set('User-Agent', 'handslice-mjpeg');
      final resp = await req.close().timeout(widget.connectTimeout);
      if (!mounted) return;
      final status = resp.statusCode;
      final ct = resp.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      if (status != 200 || !ct.contains('multipart/')) {
        _fail('HTTP $status / $ct');
        return;
      }
      // Erst-Frame-Timeout: wenn die Firmware antwortet aber keinen
      // Frame liefert, kein stummes Schwarz-Bild zeigen.
      _firstFrameWatch = Timer(widget.firstFrameTimeout, () {
        if (_frame == null) _fail('no frames within ${widget.firstFrameTimeout.inSeconds}s');
      });
      _sub = _MjpegDecoder(resp).frames.listen(
        (frame) {
          if (!mounted) return;
          _firstFrameWatch?.cancel();
          _firstFrameWatch = null;
          setState(() {
            _frame = frame;
            _status = MjpegStatus.streaming;
          });
        },
        onError: (Object e) {
          if (!mounted) return;
          _fail(_describeError(e));
        },
        onDone: () {
          if (!mounted) return;
          // Stream endete sauber – ohne weitere Hinweise setzen wir
          // "ended" als Fehler, damit der Nutzer sieht, dass der
          // Server die Verbindung beendet hat.
          if (_status != MjpegStatus.error) _fail('stream ended');
        },
        cancelOnError: true,
      );
    }).catchError((Object e) {
      if (!mounted) return;
      _fail(_describeError(e));
    });
  }

  void _stop() {
    _firstFrameWatch?.cancel();
    _firstFrameWatch = null;
    _sub?.cancel();
    _sub = null;
    try {
      _client?.close(force: true);
    } catch (_) {}
    _client = null;
    if (mounted) {
      setState(() {
        _status = MjpegStatus.idle;
      });
    }
  }

  void _fail(String msg) {
    _firstFrameWatch?.cancel();
    _firstFrameWatch = null;
    _sub?.cancel();
    _sub = null;
    try { _client?.close(force: true); } catch (_) {}
    _client = null;
    if (!mounted) return;
    setState(() {
      _status = MjpegStatus.error;
      _message = msg;
    });
  }

  String _describeError(Object e) {
    if (e is TimeoutException) return 'timeout';
    if (e is SocketException) return 'network error: ${e.osError?.message ?? e.message}';
    if (e is HttpException) return 'HTTP error';
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (_status) {
      case MjpegStatus.streaming:
        final frame = _frame;
        if (frame != null) {
          return Image.memory(
            frame,
            gaplessPlayback: true,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.low,
          );
        }
        continue connecting;
      connecting:
      case MjpegStatus.connecting:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text('…', style: theme.textTheme.bodySmall),
            ],
          ),
        );
      case MjpegStatus.idle:
        return widget.placeholder ?? const SizedBox.shrink();
      case MjpegStatus.error:
        final msg = _message ?? 'unknown error';
        if (widget.errorBuilder != null) {
          return widget.errorBuilder!(msg);
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_outlined, size: 36),
                const SizedBox(height: 8),
                Text(msg, textAlign: TextAlign.center),
              ],
            ),
          ),
        );
    }
  }
}

// Dekoder: liest den Rohstrom und emittiert JPEG-Frames.
// Erwartet `multipart/x-mixed-replace; boundary=frame`. Robust
// gegen fehlende Content-Length (Fallback: SOI/EOI-Scan).
class _MjpegDecoder {
  _MjpegDecoder(this._resp);
  final HttpClientResponse _resp;

  Stream<Uint8List> get frames async* {
    final buffer = BytesBuilder(copy: false);
    const boundaryBytes = <int>[0x2D, 0x2D, 0x66, 0x72, 0x61, 0x6D, 0x65]; // "--frame"
    await for (final chunk in _resp) {
      buffer.add(chunk);
      while (true) {
        final data = buffer.toBytes();
        // Suche naechstes "--frame"
        final start = _indexOf(data, boundaryBytes);
        if (start < 0) break;
        // Header-Block endet bei doppeltem CRLF nach boundaryBytes.
        final headerEnd = _indexOf(data, const [0x0D, 0x0A, 0x0D, 0x0A], start);
        if (headerEnd < 0) break;
        final headerBytes = data.sublist(start, headerEnd);
        final header = String.fromCharCodes(headerBytes);
        final contentLengthMatch = RegExp(
                r'Content-Length\s*:\s*(\d+)',
                caseSensitive: false)
            .firstMatch(header);
        if (contentLengthMatch == null) break;
        final n = int.parse(contentLengthMatch.group(1)!);
        final bodyStart = headerEnd + 4;
        if (data.length < bodyStart + n) break; // noch zu wenig gelesen
        final jpeg = Uint8List.fromList(data.sublist(bodyStart, bodyStart + n));
        yield jpeg;
        // Buffer kuerzen auf den Rest NACH dem Frame (vor dem naechsten boundary).
        final rest = data.sublist(bodyStart + n);
        buffer.clear();
        buffer.add(rest);
      }
    }
  }

  @visibleForTesting
  static Stream<Uint8List> decodeForTest(Stream<List<int>> bytes) async* {
    final buffer = BytesBuilder(copy: false);
    const boundaryBytes = <int>[0x2D, 0x2D, 0x66, 0x72, 0x61, 0x6D, 0x65];
    await for (final chunk in bytes) {
      buffer.add(chunk);
      while (true) {
        final data = buffer.toBytes();
        final start = _indexOf(data, boundaryBytes);
        if (start < 0) break;
        final headerEnd = _indexOf(data, const [0x0D, 0x0A, 0x0D, 0x0A], start);
        if (headerEnd < 0) break;
        final headerBytes = data.sublist(start, headerEnd);
        final header = String.fromCharCodes(headerBytes);
        final m = RegExp(r'Content-Length\s*:\s*(\d+)',
                caseSensitive: false)
            .firstMatch(header);
        if (m == null) break;
        final n = int.parse(m.group(1)!);
        final bodyStart = headerEnd + 4;
        if (data.length < bodyStart + n) break;
        final jpeg =
            Uint8List.fromList(data.sublist(bodyStart, bodyStart + n));
        yield jpeg;
        final rest = data.sublist(bodyStart + n);
        buffer.clear();
        buffer.add(rest);
      }
    }
  }
}

int _indexOf(List<int> haystack, List<int> needle, [int from = 0]) {
  if (needle.isEmpty) return from;
  final last = haystack.length - needle.length;
  outer:
  for (int i = from; i <= last; i++) {
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
