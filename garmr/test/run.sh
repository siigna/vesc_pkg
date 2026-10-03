#!/usr/bin/env bash
# Copyright 2026 Stephen Bouche
# SPDX-License-Identifier: GPL-3.0-or-later
# The LispBM Garmr's engage logic, in the repl, off-target.
#
#   ./run.sh
#
# Needs the LispBM repl from the vesc_express checkout, the same one the dash
# render tests use -- which is why this is not in CI: the repl lives in another
# repository and has to be built there.
set -uo pipefail
cd "$(dirname "$0")"

REPL=${REPL:-../../../vesc_express/main/lispBM/repl/repl}

if [ ! -x "$REPL" ]; then
    echo "no repl at $REPL -- build it in vesc_express, or set REPL=" >&2
    exit 2
fi

out=$("$REPL" -H 400000 -M 8000000 --silent --terminate \
    -s stubs.lisp -s ../garmr.lisp -s engage_test.lisp 2>&1)
echo "$out" | grep -E "^  (ok|FAIL)|checks, |Error" | sed 's/^/  /'

if echo "$out" | grep -qE "Error|FAIL|[1-9][0-9]* fails"; then
    echo "  FAILED" >&2
    exit 1
fi

exit 0
