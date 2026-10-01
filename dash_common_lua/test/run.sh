#!/usr/bin/env bash
# Unit tests for the Lua dash libs, against a host Lua.
#
# These are ports of the cases in dash_common/test, asserting the same
# numbers, so the two dashes disagreeing shows up here.
set -uo pipefail
cd "$(dirname "$0")/.."

LUA=${LUA:-lua5.4}
if ! command -v "$LUA" >/dev/null; then
    LUA=lua
fi
if ! command -v "$LUA" >/dev/null; then
    echo "no lua interpreter found; set LUA=" >&2
    exit 1
fi

fail=0
for t in test/*_test.lua; do
    # Run from the package root so require() finds lib/ and test/ the same
    # way the packer resolves them on target.
    "$LUA" "$t" || fail=1
done

exit $fail
