#!/usr/bin/env bash
# Render the dash off-target and compare against the goldens.
#
#   ./run.sh              render and compare
#   ./run.sh --update     accept the current output as the new goldens
#
# Needs the LispBM repl built 64-bit with the clay feature; see README.md.
set -uo pipefail
cd "$(dirname "$0")"

REPL=${REPL:-../../../vesc_express/main/lispBM/repl/repl}
UPDATE=0
[ "${1:-}" = "--update" ] && UPDATE=1

if [ ! -x "$REPL" ]; then
    echo "no repl at $REPL -- see README.md, or set REPL=" >&2
    exit 1
fi

# board : package dir : scripts : speed : big : mid : small
#
# vd900 is not a package. It is the S3 profile at 480x320, there to keep a
# third aspect ratio covered, and it runs the Clay check only: the
# hand-written views derive their bands from per-board constants and there is
# no 480x320 board to have tuned them for, so at that height they produce an
# invalid layout. That is the difference being tested -- the Clay description
# adapts to the panel, the hand-written views are configured for one.
#
# The real VDisp 900 is an esp32c3 and cannot run this dash at all; only its
# geometry is borrowed.
BOARDS=(
  "s3:../../dash_s3:render_pages render_clay:roboto-bold-108-4c.bin:roboto-bold-40-4c.bin:roboto-bold-24-4c.bin:roboto-bold-16-4c.bin"
  "p4:../../dash_p4:render_pages render_clay:roboto-bold-120-4c.bin:roboto-bold-40-4c.bin:roboto-bold-24-4c.bin:roboto-bold-18-4c.bin"
  "vd900:../../dash_s3:render_clay:roboto-bold-40-4c.bin:roboto-bold-40-4c.bin:roboto-bold-24-4c.bin:roboto-bold-16-4c.bin"
)

rm -rf build out
mkdir -p build/common/lib build/common/views out

# The repl's constant heap is small and write-once, so a whole dash overflows
# it. Stripping the const markers changes where data lives, not what it is.
strip_const() { grep -v '^@const-\(start\|end\)' "$1" > "$2"; }

for f in ../lib/*.lisp;  do strip_const "$f" "build/common/lib/$(basename "$f")"; done
for f in ../views/*.lbm; do strip_const "$f" "build/common/views/$(basename "$f")"; done

# walk-requested, pulled out of the real main_body rather than copied into the
# test, so the test cannot drift from what ships. Importing main_body whole
# would drag in the views and the display.
awk '/^\(defun walk-requested /,/^\}\)/' ../main_body.lisp > build/common/walk_fn.lisp
if [ ! -s build/common/walk_fn.lisp ]; then
    echo "could not extract walk-requested from main_body.lisp" >&2
    exit 1
fi

# The live cell grid and its inverse, pulled out of the real view_pages so the
# round-trip test cannot drift from what ships. Everything in the block is
# derived at load from page-w and page-cols, so hit_test re-evaluates it once
# per board profile.
awk '/^\(def live-cols /,/^\}\)/' ../views/view_pages.lbm > build/common/live_geom.lisp
if ! grep -q 'defun live-cell-hit' build/common/live_geom.lisp; then
    echo "could not extract the live cell geometry from view_pages.lbm" >&2
    exit 1
fi

# smooth-step, pulled out of the real statistics.lisp for the same reason.
awk '/^\(defun smooth-step /,/^\}\)/' ../lib/statistics.lisp > build/common/smooth_fn.lisp
if [ ! -s build/common/smooth_fn.lisp ]; then
    echo "could not extract smooth-step from statistics.lisp" >&2
    exit 1
fi

# The quick shade grid and its hit test, same deal.
awk '/^\(def shade-cols /,/^\}\)/' ../views/view_pages.lbm > build/common/shade_geom.lisp
if ! grep -q 'defun shade-cell-hit' build/common/shade_geom.lisp; then
    echo "could not extract the shade grid from view_pages.lbm" >&2
    exit 1
fi

# The signal request bitfield, from the start of its own section to the last
# of the three shown-state helpers at the end of the file.
sed -n '/^; --- Signal requests /,/^; --- end signal requests /p' \
    ../lib/vehicle-state.lisp > build/common/signal_fn.lisp
if ! grep -q 'defun sig-byte' build/common/signal_fn.lisp; then
    echo "could not extract the signal request helpers from vehicle-state.lisp" >&2
    exit 1
fi

# The PIN lock state machine, between its own markers.
sed -n '/^; --- PIN lock /,/^; --- end PIN lock /p' \
    ../lib/vehicle-state.lisp > build/common/pin_fn.lisp
if ! grep -q 'defun pin-submit' build/common/pin_fn.lisp; then
    echo "could not extract the PIN lock helpers from vehicle-state.lisp" >&2
    exit 1
fi

fail=0

# Unit tests first: pure arithmetic, no board or display involved.
for unit in battery_test walk_test hit_test smooth_test signal_test pin_test; do
    out=$("$REPL" -H 400000 -M 8000000 --terminate --silent -s "$unit.lisp" 2>&1)
    echo "$out" | grep -E "^\(|Error" | sed "s/^/  /"
    if echo "$out" | grep -qE "Error|FAIL|[1-9][0-9]* fails"; then fail=1; fi
done

for spec in "${BOARDS[@]}"; do
    IFS=: read -r board pkg scripts fspeed fbig fmid fsmall <<< "$spec"
    mkdir -p "build/$board/lib" "build/$board/font"
    strip_const "$pkg/config.lisp"    "build/$board/config.lisp"
    strip_const "$pkg/lib/input.lisp" "build/$board/lib/input.lisp"
    cp "$pkg"/font/*.bin "build/$board/font/"

    # vd900 is the S3 profile at 480x320 with a bigger pool for the
    # full-screen comparison buffer
    if [ "$board" = vd900 ]; then
        sed -i 's/^(def disp-h 480)$/(def disp-h 320)/' "build/$board/config.lisp"
    fi

    for script in $scripts; do
        sed -e "s|BOARD|$board|g" -e "s|F_SPEED|$fspeed|" -e "s|F_BIG|$fbig|" \
            -e "s|F_MID|$fmid|" -e "s|F_SMALL|$fsmall|" "$script.lisp" > "build/$board-$script.lisp"
        out=$("$REPL" -H 400000 -M 12000000 --terminate --silent \
                -s "build/$board-$script.lisp" 2>&1)
        echo "$out" | grep -E "^\(|Error|Reason" | sed "s/^/  /"
        if echo "$out" | grep -qE "Error|FAIL"; then fail=1; fi
    done

    # Banded and one-buffer rendering must agree exactly
    if ! cmp -s "out/${board}_clay.png" "out/${board}_clay_full.png"; then
        echo "  FAIL $board: banded render differs from one-buffer render"
        fail=1
    fi
    rm -f "out/${board}_clay_full.png"
done

if [ "$UPDATE" = 1 ]; then
    if [ "$fail" != 0 ]; then
        echo "not updating goldens: a render failed above" >&2
        exit 1
    fi
    mkdir -p golden
    rm -f golden/*.png
    cp out/*.png golden/
    echo "goldens updated -- review the diff before committing"
    exit 0
fi

for f in out/*.png; do
    g="golden/$(basename "$f")"
    if [ ! -f "$g" ]; then
        echo "FAIL no golden for $(basename "$f") -- run ./run.sh --update"
        fail=1
    elif ! cmp -s "$f" "$g"; then
        echo "FAIL $(basename "$f") differs from its golden"
        fail=1
    fi
done

[ "$fail" = 0 ] && echo "all renders match their goldens"
exit $fail
