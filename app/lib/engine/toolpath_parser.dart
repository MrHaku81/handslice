// Pflicht 7c/7d — parser for the HSPT (handslice toolpaths)
// binary that `handslice-cli --export-toolpaths` writes next
// to the g-code (or standalone via `--input-gcode`).
//
// Format v2 (little-endian throughout):
//
//   Header (24 B):
//     magic         = "HSPT"            (4 B)
//     version       = u32 2             (4 B)
//     flags         = u32 0             (4 B, reserved)
//     n_moves       = u32               (4 B)
//     density_g_cm3 = f32  (filament 0) (4 B)
//     diameter_mm   = f32  (filament 0) (4 B)
//
//   Per-move record (32 B each):
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
//     f32 time_s          Normal-mode time per move (post
//                         TimeProcessor); sum == Orca's
//                         "Total estimated time"
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

/// On-wire record size (bytes). Public so viewer code can stride
/// into the raw buffer without duplicating the magic number.
const int hsptRecordSize = 32;

/// On-wire header size (bytes).
const int hsptHeaderSize = 24;

/// Roles that count as the "model" for the silhouette / camera
/// framing — skirt, brim, wipe tower and custom gcode paint
/// outside the printed object and otherwise balloon the AABB
/// (brim can be 10 mm wider than the model on each side, and
/// the purge line sits off the bed entirely).
bool _isObjectRole(int roleCode) {
  if (roleCode == GcodeRole.skirt.index) return false;
  if (roleCode == GcodeRole.brim.index) return false;
  if (roleCode == GcodeRole.wipeTower.index) return false;
  if (roleCode == GcodeRole.custom.index) return false;
  return true;
}

/// Compact result from the HSPT parser. The byte stream is
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
    required this.objMinX,
    required this.objMaxX,
    required this.objMinY,
    required this.objMaxY,
    required this.objMinZ,
    required this.objMaxZ,
    required this.extrudedMm,
    required this.extrudedByRole,
    required this.lengthByRole,
    required this.timeByRole,
    required this.timeByMove,
    required this.distanceByMove,
    required this.countByMove,
    required this.totalTimeSec,
    required this.filamentDensityGcm3,
    required this.filamentDiameterMm,
  });

  /// Raw record stream. Length == `moveCount * hsptRecordSize`.
  final Uint8List data;
  final int moveCount;
  final int layerCount;
  /// First record index for each layer, length == `layerCount`.
  final Uint32List layerStarts;

  /// Whole-print AABB over extrude moves (incl. skirt/brim/
  /// purge/wipe-tower). Used for render-level camera framing.
  final double minX, maxX, minY, maxY, minZ, maxZ;

  /// Object-only AABB over extrude moves — excludes skirt,
  /// brim, wipe tower and custom g-code so the "rest-of-the-
  /// model" silhouette drawn above the slider matches what Orca
  /// shows (purge line is to the side of the bed, brim is 10 mm
  /// wider than the model; both would otherwise balloon the
  /// box).
  final double objMinX, objMaxX, objMinY, objMaxY, objMinZ, objMaxZ;

  /// Sum of per-move `delta_extruder`, filtered to
  /// `MoveType.extrude` and positive deltas. Matches Orca's
  /// `; filament used [mm]` footer within 0.01 % on the thumbnail
  /// cube — see `toolpath_parser_test.dart`.
  final double extrudedMm;
  /// Per-role sum of extruded `delta_extruder` (mm). Same filter
  /// as above. Length == `GcodeRole.values.length`.
  final Float64List extrudedByRole;
  /// Per-role sum of Euclidean path lengths of EXTRUDE moves
  /// (mm). Kept for the 2D painter's debug uses; not used in
  /// the legend any more — Orca shows filament length there.
  final Float64List lengthByRole;
  /// Per-role sum of per-move `time_s` (Normal mode, seconds),
  /// filtered to `MoveType.extrude` moves. Mirrors Orca's
  /// `Viewer::get_extrusion_role_estimated_time(role)` (see
  /// `OrcaSlicer/src/slic3r/GUI/GCodeViewer.cpp:3410-3413` →
  /// `role_time_and_percent`). Travels/retracts/wipes carry
  /// their own time via [timeByMove].
  final Float64List timeByRole;
  /// Per-move-type sum of per-move `time_s` (seconds). Mirrors
  /// Orca's `m_move_type_times` (see `OrcaSlicer/src/slic3r/
  /// GUI/GCodeViewer.cpp:3798`). Lets the legend attribute
  /// travel/retract/… time without a full re-scan.
  final Float64List timeByMove;
  /// Per-move-type sum of Euclidean segment lengths (mm).
  /// Mirrors Orca's `m_move_type_distances`
  /// (`GCodeViewer.cpp:3806`). The "Travel" distance Orca
  /// shows in the legend's "Usage" column equals
  /// `distanceByMove[MoveType.travel.index]`.
  final Float64List distanceByMove;
  /// Per-move-type record count. Mirrors Orca's
  /// `m_move_type_counts` (`GCodeViewer.cpp:3810`).
  final Uint32List countByMove;
  /// Total print time (seconds), sum of per-move Normal-mode
  /// time across every move. Matches Orca's
  /// `get_estimated_time()` and the g-code footer.
  final double totalTimeSec;
  /// Filament density (g/cm³) for extruder 0; comes from the
  /// g-code's config block via `filament_density`.
  final double filamentDensityGcm3;
  /// Filament diameter (mm) for extruder 0; comes from
  /// `filament_diameter`.
  final double filamentDiameterMm;

  /// Z-height at the start of each layer, parallel to
  /// `layerStarts`. Set from the LAST non-custom extrude move of
  /// each bin (mirrors Orca's `libvgcode::Layers::update`), so a
  /// retract that still sits at the previous layer's z does not
  /// mislabel the slider.
  final Float32List layerZ;

  int layerStart(int layer) => layerStarts[layer];
  int layerEnd(int layer) =>
      (layer + 1 < layerStarts.length) ? layerStarts[layer + 1] : moveCount;

  /// Total filament length (mm) across all roles, which equals
  /// Orca's "Total Filament" footer in metres.
  double get totalLengthMm {
    double s = 0;
    for (final v in lengthByRole) {
      s += v;
    }
    return s;
  }

  /// Volume per mm of extruded filament, derived from the
  /// filament diameter (mm³/mm). Zero when the diameter was not
  /// present in the HSPT header.
  double get filamentMm3PerMm {
    final r = filamentDiameterMm * 0.5;
    return math.pi * r * r;
  }

  /// Convert an extruded length (mm of filament extruded) into
  /// grams, using the HSPT's density/diameter. Zero when either
  /// is missing.
  double gramsFromExtrudedMm(double extrudedMm) {
    final volMm3 = extrudedMm * filamentMm3PerMm;
    // mm³ → cm³ then × g/cm³ = g.
    return volMm3 * filamentDensityGcm3 * 1e-3;
  }

  /// Per-role weight in grams, derived from `extrudedByRole`.
  double gramsForRole(int roleCode) =>
      gramsFromExtrudedMm(extrudedByRole[roleCode]);

  // Accessors into the record stream. `bd` is a `ByteData` view
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
  double get timeS     => _bd.getFloat32(_offset + 28, Endian.little);

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
  if (bytes.length < 8 ||
      bytes[0] != 0x48 || bytes[1] != 0x53 ||
      bytes[2] != 0x50 || bytes[3] != 0x54) {
    throw const FormatException('not an HSPT file');
  }
  final bd = ByteData.sublistView(bytes);
  final version = bd.getUint32(4, Endian.little);
  if (version != 2) {
    throw FormatException(
        'unsupported HSPT version $version (expected 2); re-slice to '
        'regenerate the HSPT');
  }
  if (bytes.length < hsptHeaderSize) {
    throw FormatException(
        'HSPT truncated: have ${bytes.length}, expected at least '
        '$hsptHeaderSize for the header');
  }
  final n = bd.getUint32(12, Endian.little);
  final density  = bd.getFloat32(16, Endian.little);
  final diameter = bd.getFloat32(20, Endian.little);
  final expected = hsptHeaderSize + n * hsptRecordSize;
  if (bytes.length != expected) {
    throw FormatException(
      'HSPT truncated: have ${bytes.length}, expected $expected');
  }
  // Pull the records out as its own view so a caller can keep
  // the Toolpaths after dropping the original bytes if they want.
  final data = Uint8List.view(
      bytes.buffer, bytes.offsetInBytes + hsptHeaderSize,
      n * hsptRecordSize);
  // Per-record pass: layers + bbox + extruded totals + time.
  final rbd = ByteData.sublistView(data);
  final layerStarts = <int>[];
  final layerZ = <double>[];
  int lastLayerId = -1;
  double minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  double maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  double objMinX = double.infinity, objMinY = double.infinity, objMinZ = double.infinity;
  double objMaxX = -double.infinity, objMaxY = -double.infinity, objMaxZ = -double.infinity;
  double extruded = 0;
  final extrudedByRole = Float64List(GcodeRole.values.length);
  final lengthByRole   = Float64List(GcodeRole.values.length);
  final timeByRole     = Float64List(GcodeRole.values.length);
  final timeByMove     = Float64List(MoveType.values.length);
  final distanceByMove = Float64List(MoveType.values.length);
  final countByMove    = Uint32List(MoveType.values.length);
  double totalTime = 0;
  double px = 0, py = 0, pz = 0;
  bool hasPrev = false;
  for (int i = 0; i < n; ++i) {
    final o = i * hsptRecordSize;
    final roleCode = rbd.getUint8(o);
    final moveCode = rbd.getUint8(o + 2);
    final layerId  = rbd.getUint16(o + 4, Endian.little);
    final x = rbd.getFloat32(o + 12, Endian.little);
    final y = rbd.getFloat32(o + 16, Endian.little);
    final z = rbd.getFloat32(o + 20, Endian.little);
    final de = rbd.getFloat32(o + 24, Endian.little);
    final tSec = rbd.getFloat32(o + 28, Endian.little);
    totalTime += tSec;
    final rc = roleCode < extrudedByRole.length
        ? roleCode
        : GcodeRole.none.index;
    final mc = moveCode < timeByMove.length
        ? moveCode
        : MoveType.noop.index;
    timeByMove[mc] += tSec;
    countByMove[mc] += 1;
    // Role-time is extrude-only — mirrors Orca's
    // `get_extrusion_role_estimated_time` (see
    // `GCodeViewer.cpp:3410-3413`). Travels and retracts have
    // their own per-move-type bucket above, otherwise we'd
    // double-count them in both the role rows and the Travel
    // row and show ~11 min for a 9m25s cube.
    if (moveCode == MoveType.extrude.index) {
      timeByRole[rc] += tSec;
    }
    if (layerId != lastLayerId) {
      if (layerStarts.isEmpty || layerId > lastLayerId) {
        layerStarts.add(i);
        // Placeholder; the FIRST extrude move of this bin will
        // overwrite it below. Matches Orca's
        // `libvgcode::Layers::update`: non-custom extrude moves
        // own the layer's `z`; retracts and travels drag over
        // from the previous layer's height and would mislabel
        // the slider.
        layerZ.add(z);
        lastLayerId = layerId;
      }
    }
    if (moveCode == MoveType.extrude.index) {
      if (x < minX) minX = x; if (x > maxX) maxX = x;
      if (y < minY) minY = y; if (y > maxY) maxY = y;
      if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
      if (_isObjectRole(roleCode)) {
        if (x < objMinX) objMinX = x; if (x > objMaxX) objMaxX = x;
        if (y < objMinY) objMinY = y; if (y > objMaxY) objMaxY = y;
        if (z < objMinZ) objMinZ = z; if (z > objMaxZ) objMaxZ = z;
        if (roleCode != GcodeRole.custom.index && layerStarts.isNotEmpty) {
          // Track the layer's reference Z against the latest
          // object-extrude. Needed because Orca's g-code emits
          // `;LAYER_CHANGE` BEFORE the preceding retract, so
          // the first record in a bin is a retract still at the
          // previous layer's z (e.g. 10.2 mm instead of 10.4
          // for layer 52).
          layerZ[layerZ.length - 1] = z;
        }
      }
      if (de > 0) {
        extruded += de;
        extrudedByRole[rc] += de;
        if (hasPrev) {
          final dx = x - px, dy = y - py, dz = z - pz;
          lengthByRole[rc] += math.sqrt(dx * dx + dy * dy + dz * dz);
        }
      }
    }
    if (hasPrev) {
      final dx = x - px, dy = y - py, dz = z - pz;
      distanceByMove[mc] += math.sqrt(dx * dx + dy * dy + dz * dz);
    }
    px = x; py = y; pz = z;
    hasPrev = true;
  }
  if (layerStarts.isEmpty) { layerStarts.add(0); layerZ.add(0); }
  if (minX == double.infinity) { minX = 0; maxX = 0; }
  if (minY == double.infinity) { minY = 0; maxY = 0; }
  if (minZ == double.infinity) { minZ = 0; maxZ = 0; }
  if (objMinX == double.infinity) {
    objMinX = minX; objMaxX = maxX;
    objMinY = minY; objMaxY = maxY;
    objMinZ = minZ; objMaxZ = maxZ;
  }
  return Toolpaths(
    data: data,
    moveCount: n,
    layerCount: layerStarts.length,
    layerStarts: Uint32List.fromList(layerStarts),
    layerZ: Float32List.fromList(layerZ),
    minX: minX, maxX: maxX,
    minY: minY, maxY: maxY,
    minZ: minZ, maxZ: maxZ,
    objMinX: objMinX, objMaxX: objMaxX,
    objMinY: objMinY, objMaxY: objMaxY,
    objMinZ: objMinZ, objMaxZ: objMaxZ,
    extrudedMm: extruded,
    extrudedByRole: extrudedByRole,
    lengthByRole: lengthByRole,
    timeByRole: timeByRole,
    timeByMove: timeByMove,
    distanceByMove: distanceByMove,
    countByMove: countByMove,
    totalTimeSec: totalTime,
    filamentDensityGcm3: density,
    filamentDiameterMm: diameter,
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

/// Return the maximum `layer_id` of any record in the range
/// `[fromIdx, toIdx)`. Used by tests to pin "the view at Layer
/// N draws nothing with layer_id > N-1".
int maxLayerIdIn(Toolpaths t, int fromIdx, int toIdx) {
  if (toIdx <= fromIdx) return -1;
  final bd = ByteData.sublistView(t.data);
  int maxLid = -1;
  for (int i = fromIdx; i < toIdx; ++i) {
    final o = i * hsptRecordSize;
    final lid = bd.getUint16(o + 4, Endian.little);
    if (lid > maxLid) maxLid = lid;
  }
  return maxLid;
}

/// Count records of a given move type in the range
/// `[fromIdx, toIdx)`. Mirrors the "I only drew these moves"
/// invariant the view enforces when the slider sits below the
/// top layer.
int countOfMoveTypeIn(Toolpaths t, int fromIdx, int toIdx,
    MoveType type) {
  if (toIdx <= fromIdx) return 0;
  final bd = ByteData.sublistView(t.data);
  int count = 0;
  for (int i = fromIdx; i < toIdx; ++i) {
    final o = i * hsptRecordSize;
    if (bd.getUint8(o + 2) == type.index) count++;
  }
  return count;
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
    final o = i * hsptRecordSize;
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
    final o = i * hsptRecordSize;
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
