#!/usr/bin/env python3
"""Erzeugt STL-Testmodelle fuer die Byte-Vergleichs-Reference-Tests.

Binary STL mit festen Dreiecks-Normalen, damit Hashes reproduzierbar bleiben.

Modelle:
  * cube_20mm.stl
      20x20x20 mm Wuerfel, Ursprung in (0,0,0). Vollsymmetrisch.
  * cube_notched_20mm_centered_cc2.stl
      20x20x20 mm Wuerfel mit 5x5x5 mm Kerbe an einer +X+Y+Z-Ecke
      (also an Ecke P6=(20,20,20) im Modell-System). Nach Abzug der
      Kerbe spannt die aktive Geometrie 24 Dreiecke. Die Kerbe bricht
      jede Rotations- und Spiegel-Symmetrie um die Z-Achse: kein
      Perimeter-Punkt hat auf der Platte mehr einen rotations-aequivalenten
      Partner. Dadurch gibt es keine Tie-Break-Mehrdeutigkeit mehr,
      die arm64 (libc++) und x86 (libstdc++) unterschiedlich aufloesen
      koennten – siehe docs/engine-integration.md, Abschnitt
      „Byte-Divergenz arm64 ↔ x86".
      Vertices sind pre-translated um (+118, +118, 0), damit das Modell
      auf dem CC2-Druckbett (printable_area 0..256) bei (128, 128)
      zentriert liegt. So laeuft derselbe `handslice-cli --no-center`-
      Pfad wie beim symmetrischen Wuerfel in `cube_20mm_centered_cc2.stl`.
"""

from __future__ import annotations

import pathlib
import struct
from typing import List, Tuple

Vec3 = Tuple[float, float, float]
Face = Tuple[Vec3, int, int, int]  # (normal, a, b, c)

SIDE_MM = 20.0

# --- Modell 1: einfacher Wuerfel ---------------------------------------------

CUBE_VERTICES: List[Vec3] = [
    (0.0, 0.0, 0.0),       # 0
    (SIDE_MM, 0.0, 0.0),   # 1
    (SIDE_MM, SIDE_MM, 0.0),  # 2
    (0.0, SIDE_MM, 0.0),   # 3
    (0.0, 0.0, SIDE_MM),   # 4
    (SIDE_MM, 0.0, SIDE_MM),  # 5
    (SIDE_MM, SIDE_MM, SIDE_MM),  # 6
    (0.0, SIDE_MM, SIDE_MM),  # 7
]

# 12 Dreiecke, Reihenfolge der Flaechen: -Z, +Z, -Y, +Y, -X, +X
CUBE_FACES: List[Face] = [
    ((0.0, 0.0, -1.0), 0, 2, 1),
    ((0.0, 0.0, -1.0), 0, 3, 2),
    ((0.0, 0.0, 1.0), 4, 5, 6),
    ((0.0, 0.0, 1.0), 4, 6, 7),
    ((0.0, -1.0, 0.0), 0, 1, 5),
    ((0.0, -1.0, 0.0), 0, 5, 4),
    ((0.0, 1.0, 0.0), 2, 3, 7),
    ((0.0, 1.0, 0.0), 2, 7, 6),
    ((-1.0, 0.0, 0.0), 0, 4, 7),
    ((-1.0, 0.0, 0.0), 0, 7, 3),
    ((1.0, 0.0, 0.0), 1, 2, 6),
    ((1.0, 0.0, 0.0), 1, 6, 5),
]

# --- Modell 2: Wuerfel mit Kerbe an +X+Y+Z-Ecke -------------------------------
#
# Kerbe im Oktanten (15..20)^3. Die ehemalige Ecke P6=(20,20,20) ist weg.
# Drei neue Innen-Flaechen bilden die Kerbe (bei x=15, y=15, z=15); je eine
# der aeusseren +X-, +Y-, +Z-Flaechen zerfaellt in zwei Rechtecke
# (L-Form). Normalen zeigen aus dem Vollmaterial heraus.
#
# Index-Tabelle:
#   0..5, 7         die 7 Original-Ecken ohne P6
#   7..9            drei Mittelpunkt-Vertices auf den Original-Kanten
#   10..16          sieben Kerbe-Vertices Q0..Q5, Q7 (Q6 = P6 entfaellt)

NOTCH_VERTICES: List[Vec3] = [
    # (0..6): die sieben verbleibenden Original-Wuerfel-Ecken
    (0.0, 0.0, 0.0),              # 0  P0
    (SIDE_MM, 0.0, 0.0),          # 1  P1
    (SIDE_MM, SIDE_MM, 0.0),      # 2  P2
    (0.0, SIDE_MM, 0.0),          # 3  P3
    (0.0, 0.0, SIDE_MM),          # 4  P4
    (SIDE_MM, 0.0, SIDE_MM),      # 5  P5
    (0.0, SIDE_MM, SIDE_MM),      # 6  P7
    # (7..9): Hilfs-Vertices auf Original-Kanten (fuer L-Form der aeusseren
    # +X-, +Y-, +Z-Flaechen).
    (SIDE_MM, 15.0, 0.0),         # 7  V_a   auf Kante P1-P2
    (15.0, SIDE_MM, 0.0),         # 8  V_c   auf Kante P2-P3? (nein: P3-P2)
    (15.0, 0.0, SIDE_MM),         # 9  V_e   auf Kante P4-P5
    # (10..16): Kerbe-Vertices Q0..Q5, Q7 (Q6 = (20,20,20) ist entfernt)
    (15.0, 15.0, 15.0),           # 10 Q0  (innerer unterer Innen-Eckpunkt)
    (SIDE_MM, 15.0, 15.0),        # 11 Q1
    (SIDE_MM, SIDE_MM, 15.0),     # 12 Q2
    (15.0, SIDE_MM, 15.0),        # 13 Q3
    (15.0, 15.0, SIDE_MM),        # 14 Q4
    (SIDE_MM, 15.0, SIDE_MM),     # 15 Q5
    (15.0, SIDE_MM, SIDE_MM),     # 16 Q7
]

NOTCH_FACES: List[Face] = [
    # -Z (Boden, unveraendert, 20x20)
    ((0.0, 0.0, -1.0), 0, 2, 1),
    ((0.0, 0.0, -1.0), 0, 3, 2),
    # -Y (unveraendert, 20x20)
    ((0.0, -1.0, 0.0), 0, 1, 5),
    ((0.0, -1.0, 0.0), 0, 5, 4),
    # -X (unveraendert, 20x20)
    ((-1.0, 0.0, 0.0), 0, 4, 6),  # P0, P4, P7
    ((-1.0, 0.0, 0.0), 0, 6, 3),  # P0, P7, P3
    # +X in L-Form: Rechteck A (y=0..15, z=0..20)
    ((1.0, 0.0, 0.0), 1, 7, 15),  # P1, V_a, Q5
    ((1.0, 0.0, 0.0), 1, 15, 5),  # P1, Q5, P5
    # +X Rechteck B (y=15..20, z=0..15)
    ((1.0, 0.0, 0.0), 7, 2, 12),  # V_a, P2, Q2
    ((1.0, 0.0, 0.0), 7, 12, 11), # V_a, Q2, Q1
    # +Y in L-Form: Rechteck A (x=0..15, z=0..20)
    ((0.0, 1.0, 0.0), 3, 16, 8),  # P3, Q7, V_c
    ((0.0, 1.0, 0.0), 3, 6, 16),  # P3, P7, Q7
    # +Y Rechteck B (x=15..20, z=0..15)
    ((0.0, 1.0, 0.0), 8, 12, 2),  # V_c, Q2, P2
    ((0.0, 1.0, 0.0), 8, 13, 12), # V_c, Q3, Q2
    # +Z in L-Form: Rechteck A (x=0..15, y=0..20)
    ((0.0, 0.0, 1.0), 4, 9, 16),  # P4, V_e, Q7
    ((0.0, 0.0, 1.0), 4, 16, 6),  # P4, Q7, P7
    # +Z Rechteck B (x=15..20, y=0..15)
    ((0.0, 0.0, 1.0), 9, 5, 15),  # V_e, P5, Q5
    ((0.0, 0.0, 1.0), 9, 15, 14), # V_e, Q5, Q4
    # Kerbe-Innenflaeche x=15 (Normale +X, in die weggeschnittene Zone)
    ((1.0, 0.0, 0.0), 10, 13, 16), # Q0, Q3, Q7
    ((1.0, 0.0, 0.0), 10, 16, 14), # Q0, Q7, Q4
    # Kerbe-Innenflaeche y=15 (Normale +Y)
    ((0.0, 1.0, 0.0), 10, 14, 15), # Q0, Q4, Q5
    ((0.0, 1.0, 0.0), 10, 15, 11), # Q0, Q5, Q1
    # Kerbe-Innenflaeche z=15 (Normale +Z)
    ((0.0, 0.0, 1.0), 10, 11, 12), # Q0, Q1, Q2
    ((0.0, 0.0, 1.0), 10, 12, 13), # Q0, Q2, Q3
]


def write_binary_stl(out_path: pathlib.Path,
                     vertices: List[Vec3],
                     faces: List[Face],
                     translate: Vec3 = (0.0, 0.0, 0.0)) -> None:
    tx, ty, tz = translate

    def shift(v: Vec3) -> Vec3:
        return (v[0] + tx, v[1] + ty, v[2] + tz)

    with out_path.open("wb") as fh:
        fh.write(b"\x00" * 80)
        fh.write(struct.pack("<I", len(faces)))
        for normal, a, b, c in faces:
            fh.write(struct.pack("<3f", *normal))
            fh.write(struct.pack("<3f", *shift(vertices[a])))
            fh.write(struct.pack("<3f", *shift(vertices[b])))
            fh.write(struct.pack("<3f", *shift(vertices[c])))
            fh.write(b"\x00\x00")


def main() -> None:
    base = pathlib.Path(__file__).resolve().parent

    cube_path = base / "cube_20mm.stl"
    write_binary_stl(cube_path, CUBE_VERTICES, CUBE_FACES)
    print(f"wrote {cube_path} ({cube_path.stat().st_size} bytes)")

    # CC2-Druckbett 256x256 mm, Mitte (128, 128). 20-mm-Wuerfel +118 verschoben.
    notch_path = base / "cube_notched_20mm_centered_cc2.stl"
    write_binary_stl(notch_path, NOTCH_VERTICES, NOTCH_FACES,
                     translate=(118.0, 118.0, 0.0))
    print(f"wrote {notch_path} ({notch_path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
