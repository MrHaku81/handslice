// Pflicht 7c — parser for the HSPT (handslice toolpaths)
// binary that `handslice-cli --export-toolpaths` writes next
// to the g-code (or standalone via `--input-gcode`).
//
// Format (little-endian throughout):
//
//   Header (16 B):
//     magic   = "HSPT"           (4 B)
//     version = u32 1            (4 B)
//     flags   = u32 0            (4 B, reserved)
//     n_moves = u32              (4 B)
//
//   Per-move record (28 B each):
//     u8  role            libslic3r ExtrusionRole (see [GcodeRole])
//     u8  extruder        0..255
//     u8  move_type       libslic3r EMoveType     (see [MoveType])
//     u8  pad             0
//     u16 layer_id        0..65535
//     u16 width_x100      extrusion width in 0.01-mm units
//     u16 height_x100     extrusion height in 0.01-mm units
//     u16 feedrate_mm_s   0..65535
//     f32 x, y, z         mm
//     f32 delta_extruder  mm, signed
//
// The Dart g-code parser (`gcode_parser.dart`) stays as the
// fallback for files that come without a sidecar HSPT.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// Extrusion role, matching `libslic3r::ExtrusionRole` byte
/// values (see `engine/OrcaSlicer/src/libslic3r/ExtrusionEntity
/// .hpp:20`). Keep this list and its order stable: the on-wire
/// byte in HSPT is the `index` of this enum.
enum GcodeRole {
  none,                       // 0
  perimeter,                  // 1  (= Inner wall)
  externalPerimeter,          // 2  (= Outer wall)
  overhangPerimeter,          // 3
  internalInfill,             // 4
  solidInfill,                // 5
  topSolidInfill,             // 6
  bottomSurface,              // 7
  ironing,                    // 8
  bridgeInfill,               // 9
  internalBridgeInfill,       // 10
  gapFill,                    // 11
  skirt,                      // 12
  brim,                       // 13
  supportMaterial,            // 14
  supportMaterialInterface,   // 15
  supportTransition,          // 16
  wipeTower,                  // 17
  custom,                     // 18
  // libslic3r reserves index 19 for `erMixed` (= 20 in the
  // enum, but it slides into slot 19 once we drop the gap).
  mixed,                      // 19
}

/// Move type, matching `libslic3r::GCodeProcessorResult::EMoveType`
/// (hpp:30 — Noop, Retract, Unretract, Seam, Tool_change,
/// Color_change, Pause_Print, Custom_GCode, Travel, Wipe,
/// Extrude).
enum MoveType {
  noop,            // 0
  retract,         // 1
  unretract,       // 2
  seam,            // 3
  toolChange,      // 4
  colorChange,     // 5
  pausePrint,      // 6
  customGcode,     // 7
  travel,          // 8
  wipe,            // 9
  extrude,         // 10
}

const int _hspSize = 28;

/// Compact result from the HSPT parser. The byte streams are
/// stored unmodified; accessors into the per-move fields read
/// them lazily.
class Toolpaths {
  Toolpaths({
    required this.data,
    required this.moveCount,
    required this.layerCount,
    required this.layerStarts,
    required this.layerZ,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.minZ,
    required this.maxZ,
    required this.extrudedMm,
    required this.extrudedByRole,
    required this.lengthByRole,
  });

  /// Raw record stream. Length == `moveCount * 28`.
  final Uint8List data;
  final int moveCount;
  final int layerCount;
  /// First record index for each layer, length == `layerCount`.
  final Uint32List layerStarts;

  final double minX, maxX, minY, maxY, minZ, maxZ;
  /// Sum of per-move `delta_extruder`, filtered to
  /// `MoveType.extrude` and positive deltas. Matches Orca's
  /// `; filament used [mm]` footer within 0.01 % on the thumbnail
  /// cube — see `toolpath_parser_test.dart`.
  final double extrudedMm;
  /// Per-role sum of extruded `delta_extruder` (mm). Same filter
  /// as above. Length == `GcodeRole.values.length`.
  final Float64List extrudedByRole;
  /// Per-role sum of Euclidean segment lengths (mm). What Orca
  /// shows as "Length" in the Line-Type legend.
  final Float64List lengthByRole;
  /// Z-height at the start of each layer, parallel to
  /// `layerStarts`.
  final Float32List layerZ;

  int layerStart(int layer) => layerStarts[layer];
  int layerEnd(int layer) =>
      (layer + 1 < layerStarts.length) ? layerStarts[layer + 1] : moveCount;

  // Accessors into the record stream. `_bd` is a `ByteData` view
  // created once per call site to keep the hot inner loop
  // branch-free.
  ByteData get bd => ByteData.sublistView(data);
}

/// A thin typed view over a single HSPT record. Not a persistent
/// object — allocated on demand by callers that iterate records.
class Move {
  Move(this._bd, this._offset);
  final ByteData _bd;
  final int _offset;

  int get roleCode     => _bd.getUint8 (_offset);
  int get extruder     => _bd.getUint8 (_offset + 1);
  int get moveCode     => _bd.getUint8 (_offset + 2);
  int get layerId      => _bd.getUint16(_offset + 4, Endian.little);
  double get width     => _bd.getUint16(_offset + 6, Endian.little) * 0.01;
  double get height    => _bd.getUint16(_offset + 8, Endian.little) * 0.01;
  double get feedrate  => _bd.getUint16(_offset + 10, Endian.little).toDouble();
  double get x         => _bd.getFloat32(_offset + 12, Endian.little);
  double get y         => _bd.getFloat32(_offset + 16, Endian.little);
  double get z         => _bd.getFloat32(_offset + 20, Endian.little);
  double get deltaE    => _bd.getFloat32(_offset + 24, Endian.little);

  GcodeRole get role => roleCode < GcodeRole.values.length
      ? GcodeRole.values[roleCode]
      : GcodeRole.none;
  MoveType get type => moveCode < MoveType.values.length
      ? MoveType.values[moveCode]
      : MoveType.noop;

  bool get isExtrude => type == MoveType.extrude;
  bool get isTravel  => type == MoveType.travel;
}

Toolpaths _parseInline(Uint8List bytes) {
  if (bytes.length < 16 ||
      bytes[0] != 0x48 || bytes[1] != 0x53 ||
      bytes[2] != 0x50 || bytes[3] != 0x54) {
    throw const FormatException('not an HSPT file');
  }
  final bd = ByteData.sublistView(bytes);
  final version = bd.getUint32(4, Endian.little);
  if (version != 1) {
    throw FormatException('unsupported HSPT version $version');
  }
  final n = bd.getUint32(12, Endian.little);
  final expected = 16 + n * _hspSize;
  if (bytes.length != expected) {
    throw FormatException(
      'HSPT truncated: have ${bytes.length}, expected $expected');
  }
  // Pull the records out as its own view so a caller can keep
  // the Toolpaths after dropping the original bytes if they want.
  final data = Uint8List.view(bytes.buffer, bytes.offsetInBytes + 16, n * _hspSize);
  // Per-record pass: layers + bbox + extruded totals.
  final rbd = ByteData.sublistView(data);
  final layerStarts = <int>[];
  final layerZ = <double>[];
  int lastLayerId = -1;
  double minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  double maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  double extruded = 0;
  final extrudedByRole = Float64List(GcodeRole.values.length);
  final lengthByRole   = Float64List(GcodeRole.values.length);
  double px = 0, py = 0, pz = 0;
  bool hasPrev = false;
  for (int i = 0; i < n; ++i) {
    final o = i * _hspSize;
    final roleCode = rbd.getUint8(o);
    final moveCode = rbd.getUint8(o + 2);
    final layerId  = rbd.getUint16(o + 4, Endian.little);
    final x = rbd.getFloat32(o + 12, Endian.little);
    final y = rbd.getFloat32(o + 16, Endian.little);
    final z = rbd.getFloat32(o + 20, Endian.little);
    final de = rbd.getFloat32(o + 24, Endian.little);
    if (layerId != lastLayerId) {
      if (layerStarts.isEmpty || layerId > lastLayerId) {
        layerStarts.add(i);
        layerZ.add(z);
        lastLayerId = layerId;
      }
    }
    if (moveCode == MoveType.extrude.index) {
      if (x < minX) minX = x; if (x > maxX) maxX = x;
      if (y < minY) minY = y; if (y > maxY) maxY = y;
      if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
      if (de > 0) {
        extruded += de;
        final rc = roleCode < extrudedByRole.length
            ? roleCode
            : GcodeRole.none.index;
        extrudedByRole[rc] += de;
        if (hasPrev) {
          final dx = x - px, dy = y - py, dz = z - pz;
          lengthByRole[rc] += math.sqrt(dx * dx + dy * dy + dz * dz);
        }
      }
    }
    px = x; py = y; pz = z;
    hasPrev = true;
  }
  if (layerStarts.isEmpty) { layerStarts.add(0); layerZ.add(0); }
  if (minX == double.infinity) { minX = 0; maxX = 0; }
  if (minY == double.infinity) { minY = 0; maxY = 0; }
  if (minZ == double.infinity) { minZ = 0; maxZ = 0; }
  return Toolpaths(
    data: data,
    moveCount: n,
    layerCount: layerStarts.length,
    layerStarts: Uint32List.fromList(layerStarts),
    layerZ: Float32List.fromList(layerZ),
    minX: minX, maxX: maxX,
    minY: minY, maxY: maxY,
    minZ: minZ, maxZ: maxZ,
    extrudedMm: extruded,
    extrudedByRole: extrudedByRole,
    lengthByRole: lengthByRole,
  );
}

/// Load and parse an HSPT file at [path]. For large files
/// (10+ MB) we hop the parse onto a background isolate.
Future<Toolpaths> loadToolpaths(String path) async {
  final bytes = await File(path).readAsBytes();
  if (bytes.length < (4 << 20)) {
    return _parseInline(bytes);
  }
  return Isolate.run(() => _parseInline(bytes));
}

/// Synchronous entry for tests. Does not spawn an isolate.
Toolpaths parseToolpathsInline(Uint8List bytes) => _parseInline(bytes);

/// Default Orca palette. Byte values are RGB; alpha fixed at 1.
///
/// Pulled directly from
///   `OrcaSlicer/src/libvgcode/src/ViewerImpl.cpp:283–317`
/// (DEFAULT_EXTRUSION_ROLES_COLORS, remapped to libslic3r's
/// `ExtrusionRole` enum order which is what we transmit over
/// the wire) and DEFAULT_OPTIONS_COLORS (for move types).
///
/// Keep these constants reduced to Dart ints (0xAARRGGBB) so
/// the Flutter `Color` constructor can take them directly.
class OrcaPalette {
  static const Map<GcodeRole, int> roleColor = {
    GcodeRole.none:                     0xFFE6B3B3,
    GcodeRole.perimeter:                0xFFFFE64D,
    GcodeRole.externalPerimeter:        0xFFFF7D38,
    GcodeRole.overhangPerimeter:        0xFF1F1FFF,
    GcodeRole.internalInfill:           0xFFB03029,
    GcodeRole.solidInfill:              0xFF9654CC,
    GcodeRole.topSolidInfill:           0xFFF04040,
    GcodeRole.bottomSurface:            0xFF665CC7,
    GcodeRole.ironing:                  0xFFFF8C69,
    GcodeRole.bridgeInfill:             0xFF4D80BA,
    GcodeRole.internalBridgeInfill:     0xFF4D80BA,
    GcodeRole.gapFill:                  0xFFFFFFFF,
    GcodeRole.skirt:                    0xFF00876E,
    GcodeRole.brim:                     0xFF003B6E,
    GcodeRole.supportMaterial:          0xFF00FF00,
    GcodeRole.supportMaterialInterface: 0xFF008000,
    GcodeRole.supportTransition:        0xFF004000,
    GcodeRole.wipeTower:                0xFFB3E3AB,
    GcodeRole.custom:                   0xFF5ED194,
    GcodeRole.mixed:                    0xFF808080,
  };
  static const Map<MoveType, int> moveColor = {
    MoveType.travel:        0xFF38489B,
    MoveType.wipe:          0xFFFFFF00,
    MoveType.retract:       0xFFCD22D6,
    MoveType.unretract:     0xFF49ADCF,
    MoveType.seam:          0xFFE6E6E6,
    MoveType.toolChange:    0xFFC1BE63,
    MoveType.colorChange:   0xFFDA948B,
    MoveType.pausePrint:    0xFF52F083,
    MoveType.customGcode:   0xFFE2D243,
    // Noop / Extrude handled via role colour.
    MoveType.noop:          0xFF000000,
    MoveType.extrude:       0xFF000000,
  };
}

/// Orca's default visibilities (`libvgcode/src/Settings.hpp:33-71`).
/// All extrusion roles start visible; travel / wipe / retract /
/// unretract / tool-change / color-change / pause / custom
/// g-code start hidden; seam starts visible.
class OrcaDefaults {
  static const Set<GcodeRole> visibleRoles = <GcodeRole>{
    GcodeRole.perimeter,
    GcodeRole.externalPerimeter,
    GcodeRole.overhangPerimeter,
    GcodeRole.internalInfill,
    GcodeRole.solidInfill,
    GcodeRole.topSolidInfill,
    GcodeRole.bottomSurface,
    GcodeRole.ironing,
    GcodeRole.bridgeInfill,
    GcodeRole.internalBridgeInfill,
    GcodeRole.gapFill,
    GcodeRole.skirt,
    GcodeRole.brim,
    GcodeRole.supportMaterial,
    GcodeRole.supportMaterialInterface,
    GcodeRole.supportTransition,
    GcodeRole.wipeTower,
    GcodeRole.custom,
    GcodeRole.mixed,
    GcodeRole.none,
  };
  static const Set<MoveType> visibleMoveOptions = <MoveType>{
    MoveType.seam,
  };
}

// A tiny helper used by the view: pick the colour to tint a
// segment with. Extrusions use their role; non-extrusion
// options (travel, wipe, …) use the move-type palette.
int colorForMove(int roleCode, int moveCode) {
  if (moveCode == MoveType.extrude.index) {
    final r = roleCode < GcodeRole.values.length
        ? GcodeRole.values[roleCode]
        : GcodeRole.none;
    return OrcaPalette.roleColor[r] ?? 0xFFCCCCCC;
  }
  final mt = moveCode < MoveType.values.length
      ? MoveType.values[moveCode]
      : MoveType.noop;
  return OrcaPalette.moveColor[mt] ?? 0xFFCCCCCC;
}

/// Axis-aligned bounding box of extruded moves in the range
/// [[fromIdx], [toIdx]). Returns `null` when no extrude move
/// falls in the range. Used by the 2D top-down painter to fit
/// the viewport to the current layer, not the whole print.
({double minX, double maxX, double minY, double maxY})?
layerXyBounds(Toolpaths t, int fromIdx, int toIdx) {
  if (toIdx <= fromIdx) return null;
  final bd = ByteData.sublistView(t.data);
  double minX = double.infinity, minY = double.infinity;
  double maxX = -double.infinity, maxY = -double.infinity;
  bool any = false;
  for (int i = fromIdx; i < toIdx; ++i) {
    final o = i * _hspSize;
    if (bd.getUint8(o + 2) != MoveType.extrude.index) continue;
    final x = bd.getFloat32(o + 12, Endian.little);
    final y = bd.getFloat32(o + 16, Endian.little);
    if (x < minX) minX = x; if (x > maxX) maxX = x;
    if (y < minY) minY = y; if (y > maxY) maxY = y;
    any = true;
  }
  if (!any) return null;
  return (minX: minX, maxX: maxX, minY: minY, maxY: maxY);
}

// Sum of all `width×length` extrusions per role, useful for
// stress-test reports.
Float64List extrusionLengthByRole(Toolpaths t) {
  final out = Float64List(GcodeRole.values.length);
  final bd = ByteData.sublistView(t.data);
  double px = 0, py = 0, pz = 0;
  int lastMoveCode = -1;
  for (int i = 0; i < t.moveCount; ++i) {
    final o = i * _hspSize;
    final roleCode = bd.getUint8(o);
    final moveCode = bd.getUint8(o + 2);
    final x = bd.getFloat32(o + 12, Endian.little);
    final y = bd.getFloat32(o + 16, Endian.little);
    final z = bd.getFloat32(o + 20, Endian.little);
    if (lastMoveCode >= 0 && moveCode == MoveType.extrude.index) {
      final dx = x - px, dy = y - py, dz = z - pz;
      final len = math.sqrt(dx * dx + dy * dy + dz * dz);
      final rc = roleCode < out.length ? roleCode : 0;
      out[rc] += len;
    }
    px = x; py = y; pz = z;
    lastMoveCode = moveCode;
  }
  return out;
}
