#!/usr/bin/env bash
# Copyright 2026 Stephen Bouche
# SPDX-License-Identifier: GPL-3.0-or-later
# The config packet, Lua against lisp, byte for byte.
#
#   ./run.sh
#
# send-cfg is how the package UI reads the dash's settings, and the format is
# positional with no length, no version and no field names on the wire: the UI
# splits on spaces and indexes the result. So a field inserted anywhere but
# the end silently reinterprets every later one, and the only thing holding
# the two dashes together is that their strings are identical.
#
# The lisp is the oracle rather than the format strings in it. Reading those
# got three fields wrong, and all three produced a plausible-looking string.
#
# The lisp side is derived from the render harness's own preamble rather than
# written out here, so the settings state both sides start from cannot drift
# from what the goldens use.
#
# Needs, and says so rather than failing obscurely:
#   - the lispBM repl, built 64-bit  (vesc_express/main/lispBM/repl/repl)
#   - dash_common/test/build         (run dash_common/test/run.sh once)
set -uo pipefail
# From the package root, not this directory: the Lua side requires lib.* and
# test.* the same way the packer resolves them on target, and those are
# relative to the root.
cd "$(dirname "$0")/../.."

HERE=test/cfg
PKG=..
VE=${VE:-$PKG/../vesc_express}
REPL=${REPL:-$VE/main/lispBM/repl/repl}
LISP_TEST=$PKG/dash_common/test
LUA=${LUA:-lua5.4}
command -v "$LUA" >/dev/null || LUA=lua
command -v "$LUA" >/dev/null || { echo "no lua interpreter; set LUA=" >&2; exit 1; }

[ -x "$REPL" ] || { echo "not built: $REPL" >&2; exit 1; }
[ -d "$LISP_TEST/build/p4" ] || {
    echo "no $LISP_TEST/build/p4 -- run dash_common/test/run.sh once first" >&2
    exit 1
}

REPL_ABS=$(cd "$(dirname "$REPL")" && pwd)/$(basename "$REPL")
fail=0

# The lisp settings writes for a case, as lisp source. Kept beside the Lua
# ones in cfg_p4.lua; the two lists have to say the same thing, which is what
# the comparison then proves.
lisp_setup() {
    case "$1" in
    default)
        echo '(settings-set (quote page-mask) 0xFF)'
        ;;
    custom)
        cat <<'LISP'
(settings-set (quote page-mask) 0x1F)
(settings-set (quote setting-mask) 0x3FF)
(settings-set (quote units-metric) 0)
(settings-set (quote temps-metric) 0)
(settings-set (quote drive-modes) 3)
(settings-set (quote batt-hot) 48.5)
(settings-set (quote esc-hot) 72.0)
(settings-set (quote motor-hot) 91.5)
(settings-set (quote bl-dim) 1)
(settings-set (quote esc-mode) 2)
(settings-set (quote esc-id) 17)
(settings-set (quote icon-mask) 0x2A)
(settings-set (quote theme) 3)
(settings-set (quote chart-src) 9)
(settings-set (quote chart-secs) 5)
(settings-set (quote smooth) 0.35)
(settings-set (quote pin-code) 4821)
(settings-set (quote pin-en) 1)
(settings-set (quote batt-ramp) 1)
(settings-set (quote splash-en) 0)
(settings-set (quote col-accent) 0x3366FF)
(settings-set (quote slot-col-1) 0xFF8800)
(looprange i 0 4 {
        (settings-set (ix (list (quote slot-0) (quote slot-1) (quote slot-2) (quote slot-3)) i) (+ 4 (* i 5)))
        (settings-set (ix (list (quote slot-mode-0) (quote slot-mode-1) (quote slot-mode-2) (quote slot-mode-3)) i) i)
        (settings-set (ix (list (quote slot-min-0) (quote slot-min-1) (quote slot-min-2) (quote slot-min-3)) i) (* -10.0 i))
        (settings-set (ix (list (quote slot-max-0) (quote slot-max-1) (quote slot-max-2) (quote slot-max-3)) i) (+ 55.0 i))
        (settings-set (ix (list (quote btn0-short) (quote btn1-short) (quote btn2-short) (quote btn3-short)) i) (+ 17 i))
        (settings-set (ix (list (quote btn0-long) (quote btn1-long) (quote btn2-long) (quote btn3-long)) i) (- 20 i))
})
(looprange i 0 6
    (settings-set (ix (list (quote shade-0) (quote shade-1) (quote shade-2) (quote shade-3) (quote shade-4) (quote shade-5)) i) (- 21 i)))
LISP
        ;;
    esac
}

for case in default custom; do
    setup=$(lisp_setup "$case")

    python3 - "$LISP_TEST" "$case" "$setup" <<'PY'
import sys
base, case, setup = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(base + '/build/p4-render_pages.lisp').read()
# Everything up to the page loop: the config, the libraries, the fonts and
# settings-load. The seeded ride below it does not reach send-cfg.
cut = src.index('(looprange p 0 (length pages)')
body = src[:cut] + '''
; send-data is the firmware's framed-packet call and the harness has no port
; for it. Capturing the string is the whole point of the comparison.
(defun send-data (s) (print s))

; standalone.lisp is not loaded by the render harness and send-cfg reports two
; of its values. Bound to the defaults the module declares, which is the state
; of a board with dash_esc present.
(def standalone-active false)
(def standalone-esc-id -1)

''' + setup + '''
(print "---CFG---")
(send-cfg)
'''
open(base + '/build/p4-cfg_%s.lisp' % case, 'w').write(body)
PY

    ( cd "$LISP_TEST" && "$REPL_ABS" -H 400000 -M 4000000 \
        -s "build/p4-cfg_${case}.lisp" --terminate 2>&1 ) \
        | sed -n '/---CFG---/,$p' | sed -n '2p' > "/tmp/cfg_${case}_lisp.txt"

    "$LUA" "$HERE/cfg_p4.lua" "$case" > "/tmp/cfg_${case}_lua.txt"

    if diff -q "/tmp/cfg_${case}_lisp.txt" "/tmp/cfg_${case}_lua.txt" >/dev/null; then
        n=$(wc -w < "/tmp/cfg_${case}_lua.txt")
        echo "$case: identical, $n fields"
    else
        echo "$case: DIFFER"
        echo "  lisp: $(cat /tmp/cfg_${case}_lisp.txt)"
        echo "  lua : $(cat /tmp/cfg_${case}_lua.txt)"
        # Name the first field that differs, which is the only one that
        # matters: everything after it is shifted.
        python3 - "/tmp/cfg_${case}_lisp.txt" "/tmp/cfg_${case}_lua.txt" <<'PY'
import sys
a = open(sys.argv[1]).read().split()
b = open(sys.argv[2]).read().split()
for i in range(max(len(a), len(b))):
    x = a[i] if i < len(a) else "<missing>"
    y = b[i] if i < len(b) else "<missing>"
    if x != y:
        print("  first difference at field %d: lisp %s, lua %s" % (i, x, y))
        break
PY
        fail=1
    fi
done

exit $fail
