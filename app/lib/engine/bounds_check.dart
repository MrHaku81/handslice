import 'dart:io';
import 'dart:math' as math;

// Dart-Port von engine/test/check-bounds. Prueft jede G-Code-Bewegung
// (G0/G1/G2/G3) gegen die aus dem Druckerprofil geladenen Grenzen –
// inklusive Brim, Skirt, Reinigungsturm (die stehen regulaer im
// EXECUTABLE_BLOCK). Logik 1:1 identisch zum Python-Skript, damit
// die App-seitige Pruefung mit dem CLI-Skript nachpruefbar ist
// (Widget-Test gegen dieselbe G-Code-Datei).
//
// Wichtig: die bed_texture_area aus Elegoo-Profilen erweitert die
// erlaubte Flaeche (fuer Nozzle-Prime/Wisch vor dem Bett), damit
// G-Code mit Prime-Line nicht faelschlich als OOB gemeldet wird.

class BoundsRect {
  BoundsRect({
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
    required this.zMax,
  });

  final double xMin;
  final double xMax;
  final double yMin;
  final double yMax;
  final double zMax;

  bool containsXY(double x, double y, {double tol = 1e-3}) =>
      x >= xMin - tol && x <= xMax + tol && y >= yMin - tol && y <= yMax + tol;

  bool containsZ(double z, {double tol = 1e-3}) =>
      z >= -tol && z <= zMax + tol;

  @override
  String toString() =>
      'BoundsRect(X $xMin..$xMax, Y $yMin..$yMax, Z 0..$zMax)';
}

class BoundsViolation {
  BoundsViolation({
    required this.lineNo,
    required this.axis, // 'XY' oder 'Z'
    required this.gcode,
    required this.x,
    required this.y,
    required this.z,
  });

  final int lineNo;
  final String axis;
  final String gcode;
  final double x;
  final double y;
  final double z;

  @override
  String toString() =>
      'Line $lineNo [$axis] ($x, $y, z=$z): $gcode';
}

// Parst "x[sep]y"-Eintraege (Elegoo-Profile nutzen "x" als Trenner,
// manche Profile ",").
BoundsRect _rectFromPoints(List points) {
  final re = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*[xX,]\s*(-?\d+(?:\.\d+)?)\s*$');
  final xs = <double>[], ys = <double>[];
  for (final raw in points) {
    final m = re.firstMatch(raw.toString());
    if (m == null) {
      throw FormatException('bed-area entry nicht parsbar: $raw');
    }
    xs.add(double.parse(m.group(1)!));
    ys.add(double.parse(m.group(2)!));
  }
  return BoundsRect(
    xMin: xs.reduce(math.min),
    xMax: xs.reduce(math.max),
    yMin: ys.reduce(math.min),
    yMax: ys.reduce(math.max),
    zMax: 0, // z wird separat gesetzt
  );
}

// Erwartet die drei Profilfelder: printable_area (zwingend),
// bed_texture_area (optional, erweitert XY), printable_height (zwingend).
BoundsRect boundsFromProfile(Map<String, dynamic> prof) {
  final area = prof['printable_area'];
  final height = prof['printable_height'];
  if (area is! List || height == null) {
    throw FormatException(
        'Profil hat kein printable_area / printable_height');
  }
  var r = _rectFromPoints(area);
  final tex = prof['bed_texture_area'];
  if (tex is List) {
    final t = _rectFromPoints(tex);
    r = BoundsRect(
      xMin: math.min(r.xMin, t.xMin),
      xMax: math.max(r.xMax, t.xMax),
      yMin: math.min(r.yMin, t.yMin),
      yMax: math.max(r.yMax, t.yMax),
      zMax: 0,
    );
  }
  return BoundsRect(
    xMin: r.xMin,
    xMax: r.xMax,
    yMin: r.yMin,
    yMax: r.yMax,
    zMax: double.parse(height.toString()),
  );
}

final _moveRe = RegExp(r'^\s*G[0123](\b|\s)', caseSensitive: false);
final _coordRe =
    RegExp(r'([XYZ])(-?\d+(?:\.\d+)?)', caseSensitive: false);
final _homeRe = RegExp(r'^\s*G28\b', caseSensitive: false);
final _setPosRe = RegExp(r'^\s*G92\b', caseSensitive: false);
final _absRe = RegExp(r'^\s*G90\b', caseSensitive: false);
final _relRe = RegExp(r'^\s*G91\b', caseSensitive: false);

List<BoundsViolation> checkGcodeLines(
  List<String> lines,
  BoundsRect bounds, {
  double tolerance = 1e-3,
}) {
  final violations = <BoundsViolation>[];
  double x = 0, y = 0, z = 0;
  bool absolute = true;
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    final semi = raw.indexOf(';');
    final line = semi < 0 ? raw : raw.substring(0, semi);
    if (line.trim().isEmpty) continue;
    if (_absRe.hasMatch(line)) { absolute = true; continue; }
    if (_relRe.hasMatch(line)) { absolute = false; continue; }
    if (_homeRe.hasMatch(line)) { x = y = z = 0; continue; }
    if (_setPosRe.hasMatch(line)) {
      for (final m in _coordRe.allMatches(line)) {
        final v = double.parse(m.group(2)!);
        switch (m.group(1)!.toUpperCase()) {
          case 'X': x = v; break;
          case 'Y': y = v; break;
          case 'Z': z = v; break;
        }
      }
      continue;
    }
    if (!_moveRe.hasMatch(line)) continue;
    var nx = x, ny = y, nz = z;
    for (final m in _coordRe.allMatches(line)) {
      final v = double.parse(m.group(2)!);
      switch (m.group(1)!.toUpperCase()) {
        case 'X': nx = absolute ? v : x + v; break;
        case 'Y': ny = absolute ? v : y + v; break;
        case 'Z': nz = absolute ? v : z + v; break;
      }
    }
    if (!bounds.containsXY(nx, ny, tol: tolerance)) {
      violations.add(BoundsViolation(
          lineNo: i + 1, axis: 'XY', gcode: line.trim(), x: nx, y: ny, z: nz));
    }
    if (!bounds.containsZ(nz, tol: tolerance)) {
      violations.add(BoundsViolation(
          lineNo: i + 1, axis: 'Z', gcode: line.trim(), x: nx, y: ny, z: nz));
    }
    x = nx; y = ny; z = nz;
  }
  return violations;
}

// Convenience: direkt gegen File.
Future<List<BoundsViolation>> checkGcodeFile(
    String path, BoundsRect bounds) async {
  final lines = await File(path).readAsLines();
  return checkGcodeLines(lines, bounds);
}
