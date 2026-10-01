# Dash P4 (Lua)

The touch dash for the Waveshare ESP32-P4-WIFI6-Touch-LCD-4.3, running on the
Lua script engine instead of LispBM.

Functionally the same dash as `dash_p4`: the same pages, the same settings,
the same CAN protocol with `dash_esc`. Every view is checked pixel-for-pixel
against the lisp dash's own golden renders, so what reaches the glass is the
same picture rather than a similar one.

## Requirements

A firmware built for this board **with `-DSCRIPT_ENGINE=lua`**. The two
engines are mutually exclusive in one build, and nothing in the version reply
says which is running -- so a lisp firmware will accept this package and then
fail to run it, reporting a container it does not understand.

## What differs from the lisp dash

Two things, now that the boot log and the touch region overlay have been
backported -- both were written here first and the lisp dash has them too.

- **A working backlight dim action.** The lisp accepts action 7 and ignores
  it, because the dashes it came from have no backlight control. This board
  drives the backlight on a PWM pin, so the quick shade's DIM button does
  something.

- **The package UI's channel carries three parsed commands**, where the lisp
  dash evaluates whatever arrives as code. Anything that can put a custom app
  data packet on the wire -- over USB, over CAN, from another package -- can
  run arbitrary code on a lisp dash. The Lua sandbox removes `load` for that
  reason, and the channel was narrowed to match rather than the sandbox
  widened.

One internal difference worth knowing if you read both: the startup overlays
run from the dash's timer here and block in their own thread in the lisp. The
Lua engine has one timer and no threads, and holding it during startup drops
every event that arrives in that window.

## Building

    make            # the package
    make upload     # straight to the board over serial, no VESC Tool
    make test       # unit suites, the config comparison, and the renders

`make` needs `vesc_express` beside this checkout for the packer and the
prepared fonts; set `VE=` if it is elsewhere.
