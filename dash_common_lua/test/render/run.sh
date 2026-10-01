#!/usr/bin/env bash
# Render a ported view and compare it against the lisp dash, pixel for pixel.
#
#   ./run.sh                 render and compare
#   KEEP=1 ./run.sh          leave the images in /tmp for inspection
#
# The comparison is exact. That is not optimism: both dashes draw through
# tinygfx and read the same prepared fonts, so a difference is a difference.
# view_static currently renders 384000 of 384000 pixels identical.
#
# Needs, and says so rather than failing obscurely:
#   - the lispBM repl, built 64-bit  (vesc_express/main/lispBM/repl/repl)
#   - render_host                    (make -C vesc_express/main/script/test render_host)
#   - dash_common/test/build         (run dash_common/test/run.sh once)
set -uo pipefail
cd "$(dirname "$0")"

PKG=../../..
VE=${VE:-$PKG/../vesc_express}
REPL=${REPL:-$VE/main/lispBM/repl/repl}
RENDER=${RENDER:-$VE/main/script/test/render_host}
DIFF=${DIFF:-$VE/tools/img_diff.py}
LISP_TEST=$PKG/dash_common/test
FONTS=$PKG/dash_p4/font

for f in "$REPL" "$RENDER"; do
    [ -x "$f" ] || { echo "not built: $f" >&2; exit 1; }
done
[ -d "$LISP_TEST/build/p4" ] || {
    echo "no $LISP_TEST/build/p4 -- run dash_common/test/run.sh once first" >&2
    exit 1
}

fail=0

# Each case is a name, the lisp tail that draws it, and the Lua script.
#
# The lisp side is derived from the harness's own page render rather than
# copied, so a reference cannot drift from what produces the goldens:
# everything up to the pages loop, then the tail below.
#
# The second static step in every tail is not optional. view-static-last is
# captured when view_static.lbm loads, which is before the harness pins its
# ride state, so the first step paints stale load-time values.
run_case() {
    local name=$1 tail=$2 script=$3

    python3 - "$LISP_TEST" "$name" "$tail" <<'PY'
import sys
base, name, tail = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(base + '/build/p4-render_pages.lisp').read()
cut = src.index('(looprange p 0 (length pages)')
body = src[:cut] + tail + '\n(save-active-img "out/p4_%s_ref.png")\n' % name
open(base + '/build/p4-%s_ref.lisp' % name, 'w').write(body)
PY

    ( cd "$LISP_TEST" && "$REPL_ABS" -H 400000 -M 4000000 \
        -s "build/p4-${name}_ref.lisp" --terminate >/dev/null 2>&1 ) || {
        echo "$name: lisp reference render failed" >&2
        return 1
    }

    python3 "$VE/tools/luapack.py" \
        --import-root .. --import-root ../.. \
        --asset font120="$FONTS/roboto-bold-120-4c.bin" \
        --asset font24="$FONTS/roboto-bold-24-4c.bin" \
        --asset font18="$FONTS/roboto-bold-18-4c.bin" \
        -o "/tmp/${name}_p4.luapkg" "$script" >/dev/null || return 1

    "$RENDER" "/tmp/${name}_p4.luapkg" "/tmp/${name}_p4.ppm" 800 480 >/dev/null || return 1

    echo "$name, p4:"
    python3 "$DIFF" "$LISP_TEST/out/p4_${name}_ref.png" "/tmp/${name}_p4.ppm" \
        --tol 0 | sed 's/^/  /' || return 1

    [ -n "${KEEP:-}" ] || rm -f "/tmp/${name}_p4.luapkg" "/tmp/${name}_p4.ppm"
    return 0
}

REPL_ABS=$(cd "$(dirname "$REPL")" && pwd)/$(basename "$REPL")

run_case static '(view-static-step)' static_p4.lua || fail=1

run_case trip '(view-static-step)
(setq page-now 1)
(page-trip true)
(page-trip false)
(view-static-step)' trip_p4.lua || fail=1

run_case session '(view-static-step)
(setq page-now 2)
(page-session true)
(page-session false)
(view-static-step)' session_p4.lua || fail=1

run_case batt '(view-static-step)
(setq page-now 3)
(page-batt true)
(page-batt false)
(view-static-step)' batt_p4.lua || fail=1

exit $fail
