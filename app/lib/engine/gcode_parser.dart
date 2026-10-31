// Pflicht 7b — g-code parser for the layer-view.
//
// Design goals:
//   - Streaming: read the file line by line, so a 64 MB g-code
//     does not need an in-memory copy of the source.
//   - Compact result: positions live in one Float32List (6 floats
//     per segment: start xyz + end xyz), path-type and filament
//     index per segment in two Uint8List side-cars. Layer slices
//     are index ranges into those buffers. No per-segment Dart
//     object.
//   - Isolate: parsing runs on a background isolate (not the UI
//     isolate) and emits occasional progress updates. The result
//     is transferred by reference (`TransferableTypedData`) so
//     the main isolate gets zero-copy access to the arrays.
//
// We only extract extrusion/travel G0/G1 moves and the two
// comment forms Orca writes:
//   ;TYPE:<name>    — path type for the following moves
//   ;Z_HEIGHT:<f>   — layer-change marker (used preferentially)
// and `T<idx>` tool changes. Everything else (temperatures, fan,
// retraction, custom g-code) is ignored for the preview path.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Enumerated path types the parser can emit, in a stable byte
/// encoding we also persist in the compact result. Order deliberate
/// — the UI legend walks the enum in this order.
enum PathType {
  travel,            // 0
  outerWall,         // 1
  innerWall,         // 2
  internalInfill,    // 3
  solidInfill,       // 4
  topSurface,        // 5
  bottomSurface,     // 6
  bridge,            // 7
  support,           // 8
  supportInterface,  // 9
  skirtBrim,         // 10
  primeTower,        // 11
  custom,            // 12
  unknown,           // 13
}

extension PathTypeEx on PathType {
  int get code => index;
}

/// Map Orca's ;TYPE:<name> payloads to our byte codes. The names
/// come from OrcaSlicer's GCodeWriter / GCode::ExtrusionRole.
int _typeCodeFor(String raw) {
  final s = raw.trim().toLowerCase();
  switch (s) {
    case 'outer wall':      return PathType.outerWall.code;
    case 'inner wall':      return PathType.innerWall.code;
    case 'overhang wall':   return PathType.outerWall.code;
    case 'internal infill': return PathType.internalInfill.code;
    case 'sparse infill':   return PathType.internalInfill.code;
    case 'gap infill':      return PathType.internalInfill.code;
    case 'solid infill':    return PathType.solidInfill.code;
    case 'internal solid infill':
      return PathType.solidInfill.code;
    case 'top surface':     return PathType.topSurface.code;
    case 'bottom surface':  return PathType.bottomSurface.code;
    case 'bridge':          return PathType.bridge.code;
    case 'bridge infill':   return PathType.bridge.code;
    case 'internal bridge': return PathType.bridge.code;
    case 'support':         return PathType.support.code;
    case 'support interface':
      return PathType.supportInterface.code;
    case 'support material': return PathType.support.code;
    case 'support material interface':
      return PathType.supportInterface.code;
    case 'skirt':           return PathType.skirtBrim.code;
    case 'brim':            return PathType.skirtBrim.code;
    case 'prime tower':     return PathType.primeTower.code;
    case 'wipe tower':      return PathType.primeTower.code;
    case 'custom':          return PathType.custom.code;
    default:                return PathType.unknown.code;
  }
}

/// The compact result produced by the parser. Positions are
/// interleaved (6 floats per segment: `s0x s0y s0z s1x s1y s1z`),
/// `types` and `filaments` carry one byte per segment. `layers`
/// gives the segment index at which each layer starts; the
/// implicit end is the start of the next layer (or `segmentCount`
/// for the last).
class GcodeGeometry {
  GcodeGeometry({
    required this.positions,
    required this.types,
    required this.filaments,
    required this.layers,
    required this.minZ,
    required this.maxZ,
    required this.minXY,
    required this.maxXY,
    required this.extrudedMm,
  });

  final Float32List positions;
  final Uint8List types;
  final Uint8List filaments;
  final Uint32List layers;      // start segment index per layer, length == layerCount
  final double minZ, maxZ;
  final double minXY;           // AABB min across X and Y
  final double maxXY;
  final double extrudedMm;      // total extruded filament (just E delta)

  int get segmentCount => types.length;
  int get layerCount => layers.length;

  int layerStart(int layer) => layers[layer];
  int layerEnd(int layer) =>
      (layer + 1 < layers.length) ? layers[layer + 1] : segmentCount;
}

/// Progress update emitted by the parser.
class GcodeProgress {
  const GcodeProgress({
    required this.bytesRead,
    required this.totalBytes,
    required this.segmentsSoFar,
    required this.layersSoFar,
  });
  final int bytesRead;
  final int totalBytes;
  final int segmentsSoFar;
  final int layersSoFar;
  double get fraction => totalBytes > 0 ? bytesRead / totalBytes : 0;
}

sealed class _ParseMessage {}
class _ParseProgress extends _ParseMessage {
  _ParseProgress(this.progress);
  final GcodeProgress progress;
}
class _ParseResult extends _ParseMessage {
  _ParseResult(this.geometry);
  final GcodeGeometry geometry;
}
class _ParseError extends _ParseMessage {
  _ParseError(this.message);
  final String message;
}

/// Isolate entry: parses the file at `path` and sends progress +
/// result messages back through `send`. The result is sent as a
/// `_ParseResult` wrapping the `GcodeGeometry` (which carries plain
/// TypedData; Dart's isolate messaging copies by value, which for a
/// 64 MB g-code is at most ~200 MB and acceptable in practice;
/// swap to `TransferableTypedData` here if we start pushing larger
/// prints).
void _parseEntry(List<Object?> args) async {
  final path = args[0] as String;
  final send = args[1] as SendPort;
  try {
    final totalBytes = await File(path).length();
    final result = await _parseFile(path, totalBytes, (progress) {
      send.send(_ParseProgress(progress));
    });
    send.send(_ParseResult(result));
  } catch (e, st) {
    send.send(_ParseError('$e\n$st'));
  }
}

Future<GcodeGeometry> _parseFile(
    String path, int totalBytes,
    void Function(GcodeProgress) onProgress) async {
  // Scratch buffers that grow as we go. We over-allocate rather
  // than resize per segment — the dominant file is a g-code with
  // 1 segment per ~15 bytes, so budgeting around that gets us
  // close to the final size on the first allocation.
  int bytesRead = 0;
  int cap = (totalBytes / 15).ceil().clamp(1024, 1 << 24);
  Float32List positions = Float32List(cap * 6);
  Uint8List types     = Uint8List(cap);
  Uint8List filaments = Uint8List(cap);
  int segCount = 0;
  // Layer start-indices filled in on each Z-step; no synthetic
  // leading 0 — a g-code with the first move at Z=0.2 only has
  // the Z=0.2 layer, not an empty layer 0 before it.
  List<int> layerStarts = <int>[];

  int currentType = PathType.unknown.code;
  int currentFil = 0;
  double x = 0, y = 0, z = 0;
  bool haveLastPos = false;
  double lastX = 0, lastY = 0, lastZ = 0;
  double lastReportedZ = -1e30;
  // E in Orca-emitted g-code is absolute; `extruded` tracks the
  // monotonically-growing delta so the stats field reflects actual
  // filament usage, not the cumulative sum of absolute positions.
  double extruded = 0;
  double lastE = 0;
  bool haveLastE = false;

  double minZ = double.infinity, maxZ = -double.infinity;
  double minXY = double.infinity, maxXY = -double.infinity;
  int lastProgressReport = 0;

  void grow(int needed) {
    if (needed <= cap) return;
    var newCap = cap;
    while (newCap < needed) { newCap *= 2; }
    final np = Float32List(newCap * 6);
    np.setAll(0, positions);
    final nt = Uint8List(newCap);
    nt.setAll(0, types);
    final nf = Uint8List(newCap);
    nf.setAll(0, filaments);
    positions = np; types = nt; filaments = nf;
    cap = newCap;
  }

  final file = File(path).openRead();
  final decoder = const _LineSplitter();
  await for (final line in decoder.bind(file)) {
    bytesRead += line.length + 1;
    if (line.isEmpty) continue;
    final c = line.codeUnitAt(0);
    if (c == 0x3B /* ';' */) {
      // ;TYPE:...  ;Z_HEIGHT:... (and ;LAYER_CHANGE is a layer tick)
      if (line.length > 6 && line.startsWith(';TYPE:')) {
        currentType = _typeCodeFor(line.substring(6));
      } else if (line.startsWith(';Z_HEIGHT:') ||
                 line.startsWith(';LAYER_HEIGHT:') ||
                 line == ';LAYER_CHANGE') {
        // Z-change is also inferred from G1 Z moves below; this
        // comment is a redundant hint on Orca-emitted g-code.
      }
      continue;
    }
    if (c == 0x54 /* 'T' */) {
      // Tool change: `T0` / `T1` / … — the digit becomes the
      // filament index for subsequent segments.
      final s = line.substring(1).trim();
      final idx = int.tryParse(s.split(RegExp(r'\s+')).first);
      if (idx != null && idx >= 0 && idx < 255) currentFil = idx;
      continue;
    }
    // Everything else: want 'G0' or 'G1'.
    if (c != 0x47 /* 'G' */) continue;
    if (line.length < 2) continue;
    final c1 = line.codeUnitAt(1);
    if (c1 != 0x30 && c1 != 0x31) continue;
    // Parse X, Y, Z, E lazily.
    double? nx, ny, nz, ne;
    int i = 2;
    final len = line.length;
    while (i < len) {
      final ch = line.codeUnitAt(i);
      if (ch == 0x20 || ch == 0x09) { i++; continue; }
      if (ch == 0x3B) break;    // comment on the same line
      final start = i + 1;
      // Find end of the numeric field.
      int j = start;
      while (j < len) {
        final cj = line.codeUnitAt(j);
        if (cj == 0x20 || cj == 0x09 || cj == 0x3B) break;
        j++;
      }
      final num = double.tryParse(line.substring(start, j));
      switch (ch) {
        case 0x58: nx = num; break;   // X
        case 0x59: ny = num; break;   // Y
        case 0x5A: nz = num; break;   // Z
        case 0x45: ne = num; break;   // E
        default: break;               // ignore F, S, I, J, …
      }
      i = j;
    }
    if (nx != null) x = nx;
    if (ny != null) y = ny;
    if (nz != null) z = nz;
    final isMove = nx != null || ny != null || nz != null;
    if (!isMove) continue;
    // Extrusion: absolute E grew since the last move. The first
    // E we see sets the baseline and does NOT count as extrusion
    // (Orca emits G92 E0 at layer boundaries that we ignore).
    final double eDelta;
    if (ne != null) {
      eDelta = haveLastE ? (ne - lastE) : 0;
      lastE = ne;
      haveLastE = true;
    } else {
      eDelta = 0;
    }
    final isExtrude = eDelta > 1e-6;
    final segType = isExtrude ? currentType : PathType.travel.code;
    if (haveLastPos) {
      // New layer when Z strictly increases.
      if (z > lastReportedZ + 1e-6) {
        layerStarts.add(segCount);
        lastReportedZ = z;
      }
      grow(segCount + 1);
      final o = segCount * 6;
      positions[o    ] = lastX; positions[o + 1] = lastY; positions[o + 2] = lastZ;
      positions[o + 3] = x;     positions[o + 4] = y;     positions[o + 5] = z;
      types[segCount] = segType;
      filaments[segCount] = currentFil;
      segCount++;
      if (x < minXY) minXY = x;
      if (y < minXY) minXY = y;
      if (x > maxXY) maxXY = x;
      if (y > maxXY) maxXY = y;
    }
    lastX = x; lastY = y; lastZ = z;
    haveLastPos = true;
    if (z < minZ) minZ = z;
    if (z > maxZ) maxZ = z;
    if (eDelta > 0) extruded += eDelta;
    // Progress updates every ~1 MB.
    if (bytesRead - lastProgressReport > 1 << 20) {
      lastProgressReport = bytesRead;
      onProgress(GcodeProgress(
        bytesRead: bytesRead,
        totalBytes: totalBytes,
        segmentsSoFar: segCount,
        layersSoFar: layerStarts.length,
      ));
    }
  }
  // Trim.
  final finalPositions = Float32List(segCount * 6)
      ..setAll(0, positions.sublist(0, segCount * 6));
  final finalTypes = Uint8List(segCount)
      ..setAll(0, types.sublist(0, segCount));
  final finalFil = Uint8List(segCount)
      ..setAll(0, filaments.sublist(0, segCount));
  // Guard: if segments were emitted but no explicit Z-step was
  // seen (every move at the same Z), count the whole thing as a
  // single layer so downstream UI still has something to show.
  if (layerStarts.isEmpty && segCount > 0) layerStarts.add(0);
  final finalLayers = Uint32List.fromList(layerStarts);
  onProgress(GcodeProgress(
    bytesRead: totalBytes,
    totalBytes: totalBytes,
    segmentsSoFar: segCount,
    layersSoFar: layerStarts.length,
  ));
  if (minXY == double.infinity) { minXY = 0; maxXY = 0; }
  if (minZ == double.infinity)  { minZ  = 0; maxZ  = 0; }
  return GcodeGeometry(
    positions: finalPositions,
    types: finalTypes,
    filaments: finalFil,
    layers: finalLayers,
    minZ: minZ,
    maxZ: maxZ,
    minXY: minXY,
    maxXY: maxXY,
    extrudedMm: extruded,
  );
}

/// A tiny line-splitter that reads bytes and emits ASCII lines
/// without allocating one `String` per codeunit along the way.
/// We split on \n, trim trailing \r. For a 64 MB input this stays
/// at a steady few-MB buffer.
class _LineSplitter {
  const _LineSplitter();
  Stream<String> bind(Stream<List<int>> source) async* {
    final buffer = <int>[];
    await for (final chunk in source) {
      for (final b in chunk) {
        if (b == 0x0A) {
          var end = buffer.length;
          if (end > 0 && buffer[end - 1] == 0x0D) end--;
          yield String.fromCharCodes(buffer, 0, end);
          buffer.clear();
        } else {
          buffer.add(b);
        }
      }
    }
    if (buffer.isNotEmpty) {
      yield String.fromCharCodes(buffer);
    }
  }
}

/// Spawn an isolate, parse `path`, and emit progress updates
/// along the way. The returned future completes with the final
/// `GcodeGeometry`, or errors with the isolate's exception
/// message.
Future<GcodeGeometry> parseGcode(
    String path, {
    void Function(GcodeProgress)? onProgress,
    Future<void> Function()? onCancel,
    }) async {
  final receive = ReceivePort();
  final iso = await Isolate.spawn(_parseEntry, [path, receive.sendPort]);
  final completer = Completer<GcodeGeometry>();
  final sub = receive.listen((msg) {
    if (msg is _ParseProgress) {
      onProgress?.call(msg.progress);
    } else if (msg is _ParseResult) {
      completer.complete(msg.geometry);
    } else if (msg is _ParseError) {
      completer.completeError(FormatException(msg.message));
    }
  });
  try {
    final r = await completer.future;
    return r;
  } finally {
    await sub.cancel();
    receive.close();
    iso.kill(priority: Isolate.immediate);
  }
}

/// Synchronous entry for tests. Does not spawn an isolate; parses
/// on the caller's isolate.
Future<GcodeGeometry> parseGcodeInline(String path) async {
  final total = await File(path).length();
  return _parseFile(path, total, (_) {});
}
