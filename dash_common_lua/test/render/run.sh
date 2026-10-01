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

# The lisp reference. Derived from the harness's own page render so it cannot
# drift from what produces the goldens: everything up to the pages loop, then
# a second static step and a save.
#
# The second step is not optional. view-static-last is captured when
# view_static.lbm loads, which is before the harness pins its ride state, so
# the first step paints stale load-time values.
python3 - "$LISP_TEST" <<'PY'
import sys
base = sys.argv[1]
src = open(base + '/build/p4-render_pages.lisp').read()
cut = src.index('(looprange p 0 (length pages)')
open(base + '/build/p4-static_ref.lisp', 'w').write(src[:cut] + '''
(view-static-step)
(save-active-img "out/p4_static_ref.png")
''')
PY

( cd "$LISP_TEST" && "$OLDPWD/$REPL" -H 400000 -M 4000000 \
    -s build/p4-static_ref.lisp --terminate >/dev/null 2>&1 ) || {
    echo "lisp reference render failed" >&2
    exit 1
}

python3 "$VE/tools/luapack.py" \
    --import-root .. --import-root ../.. \
    --asset font120="$FONTS/roboto-bold-120-4c.bin" \
    --asset font24="$FONTS/roboto-bold-24-4c.bin" \
    --asset font18="$FONTS/roboto-bold-18-4c.bin" \
    -o /tmp/static_p4.luapkg static_p4.lua >/dev/null || exit 1

"$RENDER" /tmp/static_p4.luapkg /tmp/static_p4.ppm 800 480 >/dev/null || exit 1

echo "view_static, p4:"
python3 "$DIFF" "$LISP_TEST/out/p4_static_ref.png" /tmp/static_p4.ppm --tol 0 \
    | sed 's/^/  /' || fail=1

[ -n "${KEEP:-}" ] || rm -f /tmp/static_p4.luapkg /tmp/static_p4.ppm

exit $fail
