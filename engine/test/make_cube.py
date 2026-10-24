#!/usr/bin/env python3
"""Erzeugt engine/test/cube_20mm.stl – 20x20x20 mm, Ursprung in (0,0,0).

Binary STL mit festen Dreiecks-Normalen, damit Hashes reproduzierbar bleiben.
"""

from __future__ import annotations

import pathlib
import struct

SIDE_MM = 20.0

VERTICES = [
    (0.0, 0.0, 0.0),       # 0
    (SIDE_MM, 0.0, 0.0),   # 1
    (SIDE_MM, SIDE_MM, 0.0),  # 2
    (0.0, SIDE_MM, 0.0),   # 3
    (0.0, 0.0, SIDE_MM),   # 4
    (SIDE_MM, 0.0, SIDE_MM),  # 5
    (SIDE_MM, SIDE_MM, SIDE_MM),  # 6
    (0.0, SIDE_MM, SIDE_MM),  # 7
]

# 12 Dreiecke, Reihenfolge der Flächen: -Z, +Z, -Y, +Y, -X, +X
FACES = [
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


def main() -> None:
    out = pathlib.Path(__file__).resolve().parent / "cube_20mm.stl"
    with out.open("wb") as fh:
        fh.write(b"\x00" * 80)
        fh.write(struct.pack("<I", len(FACES)))
        for normal, a, b, c in FACES:
            fh.write(struct.pack("<3f", *normal))
            fh.write(struct.pack("<3f", *VERTICES[a]))
            fh.write(struct.pack("<3f", *VERTICES[b]))
            fh.write(struct.pack("<3f", *VERTICES[c]))
            fh.write(b"\x00\x00")
    print(f"wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
