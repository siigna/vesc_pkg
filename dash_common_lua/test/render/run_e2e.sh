#!/usr/bin/env bash
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

python3 "$VE/tools/luapack.py" \
    --import-root .. --import-root ../.. \
    --asset font120="$FONTS/roboto-bold-120-4c.bin" \
    --asset font40="$FONTS/roboto-bold-40-4c.bin" \
    --asset font24="$FONTS/roboto-bold-24-4c.bin" \
    --asset font18="$FONTS/roboto-bold-18-4c.bin" \
    -o "$OUT/dash_p4.luapkg" dash_p4.lua >/dev/null || exit 1

# One run emits every frame, through vesc.save_frame. final.ppm is whatever
# was last drawn and is not compared; it exists because render_host takes an
# output path.
"$RENDER" "$OUT/dash_p4.luapkg" "$OUT/final.ppm" 800 480 || exit 1

CASES="page0 page1 page2 page3 page4 page5 page6 page7 page8 page9 page10
       live_hold sig_request theme_light slot_rules"

fail=0
for n in $CASES; do
    printf '%-12s ' "$n"
    out=$(python3 "$DIFF" "$GOLDEN/p4_$n.png" "$OUT/p4_$n.ppm" --tol 0 2>&1) || {
        echo "diff failed"; fail=1; continue
    }
    echo "$out" | grep -E 'differing at all' | sed 's/^ *//'
    echo "$out" | grep -qE 'over tolerance 0: 0 \(allowed 0\)' || fail=1
done

[ -n "${KEEP:-}" ] || rm -f "$OUT"/*.ppm "$OUT"/*.luapkg

if [ $fail -eq 0 ]; then
    echo "all 15 frames identical to the shipped goldens"
fi
exit $fail
