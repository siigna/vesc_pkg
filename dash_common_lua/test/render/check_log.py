#!/usr/bin/env python3
# Copyright 2026 Stephen Bouche
# SPDX-License-Identifier: GPL-3.0-or-later
"""Measure the boot log render: every row has to carry ink.

No golden to compare against -- there is no lisp boot log page -- so this
asserts the property the bug broke instead. img:text takes a baseline, so a
row laid out from its top edge draws above its own buffer and the row comes
out blank. A per-row ink count catches that; a whole-image pixel count would
not, because the middle rows still draw.
"""
import sys

def read_ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    # P6\n<w> <h>\n255\n
    parts = []
    i = 0
    while len(parts) < 4:
        while data[i:i+1].isspace():
            i += 1
        if data[i:i+1] == b"#":
            while data[i:i+1] != b"\n":
                i += 1
            continue
        j = i
        while not data[j:j+1].isspace():
            j += 1
        parts.append(data[i:j])
        i = j
    i += 1
    w, h = int(parts[1]), int(parts[2])
    return w, h, data[i:i + w * h * 3]

def main():
    path, top, line_h, rows = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    w, h, px = read_ppm(path)

    bad = []
    counts = []
    for r in range(rows):
        y0 = top + r * line_h
        y1 = min(y0 + line_h, h)
        ink = 0
        for y in range(y0, y1):
            row = px[y * w * 3:(y + 1) * w * 3]
            ink += sum(1 for k in range(0, len(row), 3) if row[k] or row[k+1] or row[k+2])
        print("  row %2d  y %3d..%3d  ink %5d" % (r, y0, y1, ink))
        counts.append(ink)
        if ink == 0:
            bad.append(r)

    if bad:
        print("FAIL rows with no ink: %s" % bad)
        return 1

    # Ink present is not enough. The bug this guards against shifts every
    # line up by about a cap height rather than removing it, so each row
    # borrows the one above and only the first and last end up wrong: the
    # first draws above its buffer and the last is nearly empty. A row that
    # is far below the median is that, and a whole-image count would miss it
    # entirely.
    #
    # The last row is the touch status line and is legitimately shorter, so
    # the floor is generous -- it still catches 443 against a median of 2400.
    inks = sorted(counts)
    median = inks[len(inks) // 2]
    floor = median * 0.4
    thin = [r for r, c in enumerate(counts) if c < floor]

    if thin:
        print("FAIL rows far below the median ink of %d: %s"
              % (median, [(r, counts[r]) for r in thin]))
        return 1

    print("every row carries ink, none below %d" % int(floor))
    return 0

sys.exit(main())
