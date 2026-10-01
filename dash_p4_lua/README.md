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

Three things it does that the lisp one does not:

- **A boot log**, on the glass and as a page. The firmware keeps the last
  lines said during bring-up, which otherwise go to whichever port last spoke
  to the board -- on this board, with the console off, nowhere at all.
- **A touch region overlay**, briefly after startup, labelled from the region
  map itself rather than from a copy of it.
- **A working backlight dim action.** The lisp accepts action 7 and ignores
  it, because the dashes it came from have no backlight control. This board
  drives the backlight on a PWM pin.

And one thing it deliberately does not do: the package UI's channel carries
three parsed commands here, where the lisp dash evaluates whatever arrives as
code. Anything that can put a custom app data packet on the wire can run
arbitrary code on a lisp dash. The Lua sandbox removes `load` for that
reason, and the channel was narrowed to match rather than the sandbox
widened.

## Building

    make            # the package
    make upload     # straight to the board over serial, no VESC Tool
    make test       # unit suites, the config comparison, and the renders

`make` needs `vesc_express` beside this checkout for the packer and the
prepared fonts; set `VE=` if it is elsewhere.
