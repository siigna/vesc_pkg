# dash_common tests

Renders the dash to PNG files on a workstation and compares them against
committed goldens. No hardware, no display driver, no board.

This is not a nicety: it has caught a one-row text seam at band boundaries, a
dirty-flag list silently truncated to length one, labels cropped by a
too-narrow column, a layout overflowing the bottom of the panel, and a
palette index overflowing an indexed4 buffer. None of those were visible from
reading the code.

## Setup

Build the LispBM repl from the vesc_express tree, 64-bit, with the Clay
extension:

    cd <vesc_express>/main/lispBM/repl
    make FEATURES="64 clay"

The default `make` target is 32-bit and fails on NixOS for want of
`gnu/stubs-32.h`. On NixOS the repl also needs `readline` and `libpng`:

    nix-shell -p readline libpng --run 'make FEATURES="64 clay"'

## Running

    ./run.sh                 # render and compare against golden/
    ./run.sh --update        # accept the current output as the new golden

Point it at a repl elsewhere with `REPL=/path/to/repl ./run.sh`.

Review what `--update` changes before committing it. A golden diff is either
a layout change you meant or a bug you just introduced, and the PNGs are the
only thing that tells them apart.

## What it covers

| | |
|---|---|
| `render_pages.lisp` | every page of the hand-written views, per board |
| `render_clay.lisp` | the Clay screen description, and that rendering it in bands is byte-identical to rendering it in one buffer |

Boards are listed in `run.sh`: the two real ones, plus a 480x320 profile
standing in for the VDisp 900 to keep a third aspect ratio honest.

## Why the sources are copied before loading

`@const-start` / `@const-end` are stripped from each file first. The repl's
constant heap is small and write-once, and a whole dash overflows it with
"Error writing to flash". Stripping them changes where data lives, not what
it is.

## What this cannot test

Bus timing, DSI lane rates, panel initialisation, touch, CAN. Anything that
needs the hardware. `hw_test.lbm` in the vesc_express board directory covers
that side, on the board.

## Why the strip is stepped, not threaded

Both harnesses call `view-static-step` once per captured frame instead of
spawning `view-static-thread`. With the thread running alongside, whether a
changed status field had been painted before the frame was saved depended on
how long the render took -- so a golden could pass or fail on timing, and the
demo's stills changed on every run.

That is what the one unexplained `p4_live_hold` failure was: it reported a
difference while the pixels were identical, which is what a half-written or
half-painted frame looks like.

`view-static-thread` now calls the same step in its loop, so the shipping path
and the harness path are the same code.

## lint.py

LispBM has no static checking of its own. A file loads, and an undefined symbol
or a misplaced `return` becomes a runtime error the first time that branch runs
-- which on a display means a thread dies mid-ride, and the branch that kills
it may be the one that only runs when something has already gone wrong.

    ./lint.py ../../dash_common ../../dash_s3 ../../dash_p4

Every check exists because the mistake it catches was actually made in this
package, and in each case the render tests did not catch it: they exercise the
drawing, not the paths that only run on a real vehicle.

| check | what it caught |
|---|---|
| `return` in a plain `defun` | the PIN keypad threw on every key press during a lockout; `chart-draw` threw on every frame of the chart page before the ring had two samples |
| `=` or `!=` on a string | the quick shade took the page down the first time a button had no state line |
| `setting-flag` on a `b` cell | `pin-en` took `settings-load` down on the first load |
| unbalanced parens | not yet, but it is free |
| a setting read at load but never written by `restore-settings` | the dash died before its first draw on real hardware -- an unwritten slot reads `nil` there, where the test stub returns `0`, and `setting-clamp` compares with `=` |

The first of those is the one that earns the tool: it found a second,
pre-existing instance immediately, in code that had already shipped and passed
every golden.

`--unbound` additionally reports names called but bound nowhere in the package,
which is the `shade-showing`-from-a-view and `light-on-default`-from-a-library
class of mistake. It is off by default because the builtin list it checks
against is hand-maintained, so a name missing from that list is a false
positive rather than a finding.
