#!/usr/bin/env python3
"""Parse Valgrind Memcheck log → focused list of Fill-path uninit errors.

Classification by first in-project frame (dropping TBB/Boost/libstdc++):
- fill   : libslic3r/Fill/, ClipperUtils, deps_src/clipper, libslic3r/clipper.cpp
- other  : any other project file (handslice-cli, PrintObject, ...)
- ext    : TBB, Boost, libstdc++, libc, ld (never qualifies as "first project frame")

Groups entries by error-site file:line, kind (CJ/UV), origin.
"""
import re
import sys
from collections import Counter

FILLPATH_PATTERNS = (
    "/libslic3r/Fill/",
    "/libslic3r/ClipperUtils",
    "/libslic3r/clipper.cpp",
    "/deps_src/clipper/",
    "/libslic3r/Fill.cpp",
)
EXT_PATTERNS = (
    "oneapi/tbb", "task_dispatcher", "task_arena", "arena.cpp",
    "parallel_for.h", "_task.h",
    "boost/", "/libboost", "libstdc++", "libc.so", "ld-linux", "ld.so",
    "libpthread",
)

HEAD_CJ = "Conditional jump or move depends on uninitialised value"
HEAD_UV = "Use of uninitialised value"
STACK_HDR = "Uninitialised value was created by a stack allocation"
HEAP_HDR  = "Uninitialised value was created by a heap allocation"

frame_re = re.compile(r"==\d+==\s+(at|by)\s+0x[0-9A-Fa-f]+:\s+(.+?)\s+\(([^)]+):(\d+)\)")

def classify(path):
    if any(p in path for p in FILLPATH_PATTERNS):
        return "fill"
    if any(p in path for p in EXT_PATTERNS):
        return "ext"
    return "other"

def first_project_frame(frames):
    for fn, path, line in frames:
        c = classify(path)
        if c != "ext":
            return (fn, path, line, c)
    return None

def main(logpath):
    with open(logpath) as f:
        text = f.read()
    # Split into blocks separated by the empty "==PID== " marker lines.
    # Each error block starts with CJ or UV header and may be followed by
    # an "Uninitialised value was created by" origin block.
    blocks = re.split(r"\n==\d+==\s*\n", text)
    total_cj = 0
    total_uv = 0
    fill_errors = []
    other_errors = []
    skipped = 0
    for b in blocks:
        if HEAD_CJ in b:
            kind = "CJ"; total_cj += 1
        elif HEAD_UV in b:
            kind = "UV"; total_uv += 1
        else:
            skipped += 1
            continue
        # Split at the ORIGIN header
        site_part, _, origin_part = b.partition(STACK_HDR)
        origin_kind = "stack"
        if not origin_part:
            site_part, _, origin_part = b.partition(HEAP_HDR)
            origin_kind = "heap" if origin_part else "none"
        # Collect frames in site_part
        site_frames = frame_re.findall(site_part)
        site_frames = [(fn.strip(), path.strip(), int(line)) for _, fn, path, line in site_frames]
        origin_frames = frame_re.findall(origin_part)
        origin_frames = [(fn.strip(), path.strip(), int(line)) for _, fn, path, line in origin_frames]
        # Classify by first project frame in site
        first = first_project_frame(site_frames)
        if first is None:
            # No project frame at all; count as ext-only
            continue
        fn, path, line, cls = first
        origin_desc = "no-origin"
        if origin_frames:
            o_fn, o_path, o_line = origin_frames[0]
            origin_desc = f"{origin_kind}:{o_fn} ({o_path}:{o_line})"
        entry = {"kind": kind, "fn": fn, "file": path, "line": line, "origin": origin_desc}
        if cls == "fill":
            fill_errors.append(entry)
        else:
            other_errors.append(entry)
    print(f"=== Valgrind Memcheck summary ===")
    print(f"Conditional jump errors: {total_cj}")
    print(f"Use of uninit errors:    {total_uv}")
    print(f"Total errors (CJ+UV):    {total_cj + total_uv}")
    print(f"Blocks skipped (no header): {skipped}")
    print()
    # Count errors by first-project classification
    print(f"Classified by first project frame:")
    print(f"  Fill-path   (Fill*, ClipperUtils, clipper.cpp): {len(fill_errors)}")
    print(f"  Other       (handslice-cli, PrintObject, ...): {len(other_errors)}")
    print()
    def bucket(errs, title, n=30):
        print(f"=== {title} — collapsed by (file, line, kind, origin) — top {n} ===")
        key = lambda e: (e["file"], e["line"], e["kind"], e["origin"])
        c = Counter(key(e) for e in errs)
        fns = {}
        for e in errs:
            fns[key(e)] = e["fn"]
        for (f, ln, k, o), n_hits in sorted(c.items(), key=lambda x: -x[1])[:n]:
            short = f
            for prefix in ("/home/handslice/handslice/engine/OrcaSlicer/",
                           "/home/handslice/handslice/engine/"):
                if short.startswith(prefix):
                    short = short[len(prefix):]
            short_fn = fns.get((f, ln, k, o), "?")
            if len(short_fn) > 90: short_fn = short_fn[:90] + "..."
            print(f"  [{k} x{n_hits:5d}] {short}:{ln}")
            print(f"             fn: {short_fn}")
            print(f"             origin: {o}")
    bucket(fill_errors, "Fill-path")
    bucket(other_errors, "Other project")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: stufe-3c-valgrind-parse.py <memcheck.log>", file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1])
