#!/usr/bin/env bash
# Copyright 2026 Stephen Bouche
# SPDX-License-Identifier: GPL-3.0-or-later
# The whole dash, every page, against the goldens dash_common/test ships.
#
#   ./run_e2e.sh             render and compare
#   KEEP=1 ./run_e2e.sh      leave the frames in /tmp/dash_e2e
#
# Different in kind from run.sh beside it. That one renders one view against a
# lisp reference derived live, so a per-view comparison cannot drift from the
# harness that makes the goldens. This renders the dash the way the board runs
# it -- real settings load, real page set, real static strip -- and compares
# against the committed PNGs, which is the stronger claim and the cheaper run:
# no lispBM repl, and one render for all fifteen frames.
#
# Needs, and says so rather than failing obscurely:
#   - render_host  (make -C vesc_express/main/script/test render_host)
set -uo pipefail
cd "$(dirname "$0")"

PKG=../../..
VE=${VE:-$PKG/../vesc_express}
RENDER=${RENDER:-$VE/main/script/test/render_host}
DIFF=${DIFF:-$VE/tools/img_diff.py}
GOLDEN=$PKG/dash_common/test/golden
FONTS=$PKG/dash_p4/font

# The directory the Lua script writes into. Hardcoded there as well, because
# the firmware's Lua has no os library to read an environment variable with --
# and the script has to run under the same interpreter the board does or it
# would not be testing the same thing.
OUT=/tmp/dash_e2e

[ -x "$RENDER" ] || { echo "not built: $RENDER" >&2; exit 1; }

mkdir -p "$OUT"

CASES="page0 page1 page2 page3 page4 page5 page6 page7 page8 page9 page10
       live_hold sig_request theme_light slot_rules"

fail=0

# Both boards, from one harness and one view layer. The assets are named by
# slot because the sizes differ: the speed readout is 120 pixels on the wide
# panel and 108 on the square one.
#
# That the same code renders both, pixel for pixel against each board's own
# goldens, is the parity claim worth making -- a view layer that only matched
# on the panel it was written against would have proved much less.
render_board() {
    local board=$1 w=$2 h=$3 fontdir=$4 speed=$5 big=$6 mid=$7 small=$8

    python3 "$VE/tools/luapack.py" \
        --import-root .. --import-root ../.. \
        --asset font_speed="$fontdir/$speed" \
        --asset font_big="$fontdir/$big" \
        --asset font_mid="$fontdir/$mid" \
        --asset font_small="$fontdir/$small" \
        -o "$OUT/dash_$board.luapkg" dash_board.lua >/dev/null || return 1

    # One run emits every frame, through vesc.save_frame. final.ppm is
    # whatever was last drawn and is not compared; it exists because
    # render_host takes an output path.
    "$RENDER" "$OUT/dash_$board.luapkg" "$OUT/final_$board.ppm" \
        "$w" "$h" "$board" || return 1

    echo
    echo "--- $board, ${w}x${h}"
    for n in $CASES; do
        printf '%-12s ' "$n"
        out=$(python3 "$DIFF" "$GOLDEN/${board}_$n.png" \
                "$OUT/${board}_$n.ppm" --tol 0 2>&1) || {
            echo "diff failed"; fail=1; continue
        }
        echo "$out" | grep -E 'differing at all' | sed 's/^ *//'
        echo "$out" | grep -qE 'over tolerance 0: 0 \(allowed 0\)' || fail=1
    done
}

render_board p4 800 480 "$PKG/dash_p4/font" \
    roboto-bold-120-4c.bin roboto-bold-40-4c.bin \
    roboto-bold-24-4c.bin roboto-bold-18-4c.bin

render_board s3 480 480 "$PKG/dash_s3/font" \
    roboto-bold-108-4c.bin roboto-bold-40-4c.bin \
    roboto-bold-24-4c.bin roboto-bold-16-4c.bin

# The boot log page has no golden, because there is no lisp boot log to render
# one from. It gets a measurement instead: every row has to carry ink, and
# none may fall far below the median. That is the shape of the bug it had --
# img:text takes a baseline rather than a top edge, so rows laid out from
# their top edge draw above their own buffer and the first and last lines
# come out wrong while the middle ones look fine.
echo
python3 "$VE/tools/luapack.py" \
    --import-root .. --import-root ../.. \
    --asset font18="$FONTS/roboto-bold-18-4c.bin" \
    -o "$OUT/log.luapkg" log_p4.lua >/dev/null || exit 1

geom=$("$RENDER" "$OUT/log.luapkg" "$OUT/log_final.ppm" 800 480 | grep '^geom')
echo "log page: $geom"
line_h=$(echo "$geom" | sed 's/.*line_h=\([0-9]*\).*/\1/')
rows=$(echo "$geom" | sed 's/.*rows=\([0-9]*\).*/\1/')
top=$(echo "$geom" | sed 's/.*top=\([0-9]*\).*/\1/')
python3 check_log.py "$OUT/p4_log.ppm" "$top" "$line_h" "$rows" | tail -1 || fail=1

# The touch region overlay, same arrangement: no lisp counterpart, so the
# assertions are properties rather than pixels. The five boxes have to tile
# the panel exactly, and every point inside a box has to belong to the region
# that box is labelled with -- which is what makes the overlay a report of
# input.region rather than a second copy of it that can drift.
echo
python3 "$VE/tools/luapack.py" \
    --import-root .. --import-root ../.. \
    --asset font18="$FONTS/roboto-bold-18-4c.bin" \
    -o "$OUT/regions.luapkg" regions_p4.lua >/dev/null || exit 1

reg=$("$RENDER" "$OUT/regions.luapkg" "$OUT/regions_final.ppm" 800 480) || exit 1
echo "$reg" | grep -E '^(layout|tiling|label)'
echo "$reg" | grep -q 'tiling: 0 gaps, 0 overlaps' || fail=1
echo "$reg" | grep -q 'label agreement: 0 points' || fail=1

[ -n "${KEEP:-}" ] || rm -f "$OUT"/*.ppm "$OUT"/*.luapkg

if [ $fail -eq 0 ]; then
    echo "all 15 frames identical to the shipped goldens, on both boards"
fi
exit $fail
