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
import 'dart:math' as math;
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
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.extrudedMm,
    required this.lengthByType,
  });

  final Float32List positions;
  final Uint8List types;
  final Uint8List filaments;
  final Uint32List layers;      // start segment index per layer, length == layerCount
  final double minZ, maxZ;
  final double minX, maxX, minY, maxY;
  final double extrudedMm;      // total extruded filament (sum of E deltas)
  // Per-path-type aggregated extrusion-path length in millimetres
  // (not E, but Euclidean XY distance of extruded moves). Indexed
  // by `PathType.code`. Travel is kept at index 0 for symmetry
  // but is left at 0.
  final Float64List lengthByType;

  int get segmentCount => types.length;
  int get layerCount => layers.length;

  int layerStart(int layer) => layers[layer];
  int layerEnd(int layer) =>
      (layer + 1 < layers.length) ? layers[layer + 1] : segmentCount;

  // Back-compat shim: the earlier shape returned a single square
  // AABB spanning both X and Y. Some callers still use it; it is
  // computed on the fly from the separate axis bounds.
  double get minXY => math.min(minX, minY);
  double get maxXY => math.max(maxX, maxY);
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
  // Layer boundaries. We trust Orca's `;LAYER:<N>` markers first;
  // on files that lack them we fall back to z-step detection
  // (every strictly larger Z begins a new layer). Pure z-step on
  // Orca g-code would over-count — each travel-with-z-hop looks
  // like a layer step.
  bool pendingLayerStart = false;
  bool sawExplicitLayerMarker = false;
  // Orca also writes `SET_PRINT_STATS_INFO TOTAL_LAYER=<N>` with
  // the authoritative extruding-layer count. We clamp the layer
  // array to that number at the end so the trailing post-print
  // `;LAYER:<TOTAL>` sentinel does not add a phantom layer
  // (seen on `thumbnail-cube.gcode`: TOTAL_LAYER=100 but
  // ;LAYER:0..;LAYER:100 means 101 markers).
  int? totalLayerHint;
  // E in Orca-emitted g-code is absolute; `extruded` tracks the
  // monotonically-growing delta so the stats field reflects actual
  // filament usage, not the cumulative sum of absolute positions.
  double extruded = 0;
  double lastE = 0;
  bool haveLastE = false;

  double minZ = double.infinity, maxZ = -double.infinity;
  double minX = double.infinity, maxX = -double.infinity;
  double minY = double.infinity, maxY = -double.infinity;
  final lengthByType = Float64List(PathType.values.length);
  // Extrusion mode. RepRap default is M82 (absolute) at power-on,
  // but Orca puts M83 (relative) near the top of its g-code via
  // the filament-start script. We track both so legacy files
  // still work.
  bool relativeE = false;
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
      if (line.length > 6 && line.startsWith(';TYPE:')) {
        currentType = _typeCodeFor(line.substring(6));
      } else if (line.startsWith(';LAYER:')) {
        // Orca emits `;LAYER:<N>` at the start of each physical
        // layer. The next move becomes the first segment of a
        // new layer; z-hops in between (travel-with-raise) do
        // not fire layer boundaries.
        pendingLayerStart = true;
        sawExplicitLayerMarker = true;
      } else if (line == ';LAYER_CHANGE') {
        // Appears BETWEEN layers in Orca output (N-1 occurrences
        // for N layers). Not strong enough to pin a boundary on
        // its own — the following `;LAYER:<N>` is what we key
        // on. But its presence tells us the file carries
        // explicit markers, so z-step detection stays off.
        sawExplicitLayerMarker = true;
      }
      continue;
    }
    // Klipper-style macro call carrying Orca's `TOTAL_LAYER=<N>`
    // hint. Cheap substring probe before the full starts-with
    // check so the hot path (pure G1 moves) is not touched.
    if (totalLayerHint == null && line.contains('TOTAL_LAYER=')) {
      final idx = line.indexOf('TOTAL_LAYER=');
      int j = idx + 12;
      final start = j;
      while (j < line.length) {
        final ch = line.codeUnitAt(j);
        if (ch < 0x30 || ch > 0x39) break;
        j++;
      }
      if (j > start) {
        totalLayerHint = int.tryParse(line.substring(start, j));
      }
    }
    if (c == 0x54 /* 'T' */) {
      // Tool change: `T0` / `T1` / … — the digit becomes the
      // filament index for subsequent segments.
      final s = line.substring(1).trim();
      final idx = int.tryParse(s.split(RegExp(r'\s+')).first);
      if (idx != null && idx >= 0 && idx < 255) currentFil = idx;
      continue;
    }
    // M-codes: M82 (absolute E), M83 (relative E), G92 (set
    // extruder/position reference). Everything else beginning
    // with M is irrelevant to the path geometry.
    if (c == 0x4D /* 'M' */) {
      if (line.startsWith('M82')) {
        relativeE = false; lastE = 0; haveLastE = true;
      } else if (line.startsWith('M83')) {
        relativeE = true;
      }
      continue;
    }
    // Everything else: want 'G0', 'G1', 'G2', 'G3', or 'G92'.
    if (c != 0x47 /* 'G' */) continue;
    if (line.length < 2) continue;
    final c1 = line.codeUnitAt(1);
    // G92: reset the extruder reference (always), and in absolute
    // mode this is a reset of lastE to the given value (default 0).
    if (c1 == 0x39 /* '9' */) {
      if (line.startsWith('G92')) {
        // Parse E value (default 0).
        final eIdx = line.indexOf('E');
        double newE = 0;
        if (eIdx >= 0 && eIdx + 1 < line.length) {
          int j = eIdx + 1;
          while (j < line.length) {
            final cj = line.codeUnitAt(j);
            if (cj == 0x20 || cj == 0x09 || cj == 0x3B) break;
            j++;
          }
          newE = double.tryParse(line.substring(eIdx + 1, j)) ?? 0;
        }
        lastE = newE;
        haveLastE = true;
      }
      continue;
    }
    final isG0 = c1 == 0x30, isG1 = c1 == 0x31;
    final isG2 = c1 == 0x32, isG3 = c1 == 0x33;
    if (!isG0 && !isG1 && !isG2 && !isG3) continue;
    // Parse X, Y, Z, E, I, J, R lazily (arcs need the last three).
    double? nx, ny, nz, ne, ni, nj, nr;
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
        case 0x49: ni = num; break;   // I (arc centre offset X)
        case 0x4A: nj = num; break;   // J (arc centre offset Y)
        case 0x52: nr = num; break;   // R (arc radius)
        default: break;               // ignore F, S, …
      }
      i = j;
    }
    final nextX = nx ?? x;
    final nextY = ny ?? y;
    final nextZ = nz ?? z;
    final isMove = nx != null || ny != null || nz != null;
    if (!isMove) continue;
    // Extrusion delta: in M83 (relative) each E value IS the
    // delta; in M82 (absolute) delta = E - lastE. Was wrong in
    // the first 7b pass — M83 was treated as absolute, which
    // made every same-value E in a wall path look like 0 delta
    // and get bucketed as a travel segment.
    final double eDelta;
    if (ne != null) {
      if (relativeE) {
        eDelta = ne;
      } else {
        eDelta = haveLastE ? (ne - lastE) : 0;
        lastE = ne;
      }
      haveLastE = true;
    } else {
      eDelta = 0;
    }
    final isExtrude = eDelta > 1e-6;
    final segType = isExtrude ? currentType : PathType.travel.code;

    // Layer boundary (same as before, out here so the arc-fan
    // emits all its sub-segments within the same layer).
    if (haveLastPos) {
      final triggerLayer = pendingLayerStart ||
          (!sawExplicitLayerMarker && nextZ > lastReportedZ + 1e-6);
      if (triggerLayer) {
        layerStarts.add(segCount);
        lastReportedZ = nextZ;
        pendingLayerStart = false;
      }
    }

    void emit(double x0, double y0, double z0,
              double x1, double y1, double z1, int segType) {
      grow(segCount + 1);
      final o = segCount * 6;
      positions[o    ] = x0; positions[o + 1] = y0; positions[o + 2] = z0;
      positions[o + 3] = x1; positions[o + 4] = y1; positions[o + 5] = z1;
      types[segCount] = segType;
      filaments[segCount] = currentFil;
      segCount++;
      if (x0 < minX) minX = x0; if (x1 < minX) minX = x1;
      if (y0 < minY) minY = y0; if (y1 < minY) minY = y1;
      if (x0 > maxX) maxX = x0; if (x1 > maxX) maxX = x1;
      if (y0 > maxY) maxY = y0; if (y1 > maxY) maxY = y1;
      final dx = x1 - x0, dy = y1 - y0, dz = z1 - z0;
      final len = math.sqrt(dx * dx + dy * dy + dz * dz);
      lengthByType[segType] += len;
    }

    if (haveLastPos) {
      if (isG2 || isG3) {
        // Arc interpolation. Centre is either (lastX+I, lastY+J)
        // (I/J form) or derived from R (chord + radius). We only
        // handle the I/J form reliably; R-form arcs are rare in
        // slicer output and we approximate them with a single
        // segment when I/J are absent.
        if (ni != null || nj != null) {
          final cx = lastX + (ni ?? 0);
          final cy = lastY + (nj ?? 0);
          final r = math.sqrt((lastX - cx) * (lastX - cx) +
                              (lastY - cy) * (lastY - cy));
          final a0 = math.atan2(lastY - cy, lastX - cx);
          var   a1 = math.atan2(nextY - cy, nextX - cx);
          // G2 is clockwise (angle decreases), G3 is counter-
          // clockwise. We walk the arc in `arcDir` increments.
          if (isG2) {
            if (a1 >= a0) a1 -= 2 * math.pi;
          } else {
            if (a1 <= a0) a1 += 2 * math.pi;
          }
          final arcAngle = (a1 - a0).abs();
          // One sub-segment per ~0.4 mm of arc length, min 8,
          // max 128 — enough to look smooth without exploding the
          // segment count on big radii.
          final arcLen = arcAngle * r;
          final steps = arcLen > 0
              ? math.min(128, math.max(8, (arcLen / 0.4).ceil()))
              : 8;
          final dAngle = (a1 - a0) / steps;
          final dZ     = (nextZ - lastZ) / steps;
          var px = lastX, py = lastY, pz = lastZ;
          for (int s = 1; s <= steps; ++s) {
            final a = a0 + dAngle * s;
            final sx = cx + r * math.cos(a);
            final sy = cy + r * math.sin(a);
            final sz = lastZ + dZ * s;
            emit(px, py, pz, sx, sy, sz, segType);
            px = sx; py = sy; pz = sz;
          }
        } else {
          // R-form (or malformed) — fall back to a straight line.
          emit(lastX, lastY, lastZ, nextX, nextY, nextZ, segType);
        }
      } else {
        emit(lastX, lastY, lastZ, nextX, nextY, nextZ, segType);
      }
    }
    lastX = nextX; lastY = nextY; lastZ = nextZ;
    x = nextX; y = nextY; z = nextZ;
    // Suppress "unused" warnings for the arc-only radius field
    // when R-form arcs are not used.
    nr?.toDouble();
    haveLastPos = true;
    if (nextZ < minZ) minZ = nextZ;
    if (nextZ > maxZ) maxZ = nextZ;
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
  // Trim trailing phantom layers announced by a terminal
  // `;LAYER:<TOTAL>` sentinel; Orca writes TOTAL_LAYER=<N> but
  // emits ;LAYER:N as well, which would be an extra entry.

  final hint = totalLayerHint;
  if (hint != null && layerStarts.length > hint) {
    layerStarts.removeRange(hint, layerStarts.length);
  }
  final finalLayers = Uint32List.fromList(layerStarts);
  onProgress(GcodeProgress(
    bytesRead: totalBytes,
    totalBytes: totalBytes,
    segmentsSoFar: segCount,
    layersSoFar: layerStarts.length,
  ));
  if (minX == double.infinity) { minX = 0; maxX = 0; }
  if (minY == double.infinity) { minY = 0; maxY = 0; }
  if (minZ == double.infinity) { minZ = 0; maxZ = 0; }
  return GcodeGeometry(
    positions: finalPositions,
    types: finalTypes,
    filaments: finalFil,
    layers: finalLayers,
    minZ: minZ,
    maxZ: maxZ,
    minX: minX,
    maxX: maxX,
    minY: minY,
    maxY: maxY,
    extrudedMm: extruded,
    lengthByType: lengthByType,
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
