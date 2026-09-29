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
