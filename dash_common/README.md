# dash_common

Shared source for the touch dash packages. Not a package itself: there is no
`pkgdesc.qml` and it produces no `.vescpkg`.

Currently used by `dash_s3` (Waveshare ESP32-S3-Touch-LCD-4, 480x480) and
`dash_p4` (Waveshare ESP32-P4-WIFI6-Touch-LCD-4.3, 800x480). The `lib/` files
here are the same ones `dash_vdisp` and `dash35b` carry their own copies of,
so those two could move onto this tree without changes; `dash16` has diverged
too far to be worth folding in.

## Layout

    lib/        the shared library: vehicle state, colours, statistics,
                communication, standalone fallback, settings. Board-agnostic.
    views/      view_static (the always-on bands) and view_pages (the
                swappable lower area). Sized from the board profile.
    main_body   everything in a dash's main.lisp that is not board-specific.

## What a board package provides

`config.lisp`, the board profile:

| | meaning |
|---|---|
| `disp-w` `disp-h` | panel size, after any rotation |
| `strip-h` `speed-h` `page-h` | band heights; every other band is derived by stacking from these in `views/view_static.lbm` |
| `page-cols` `page-row-h` | the label/value grid. Pages supply eight cells, so the rows follow from the column count: 2 columns means 4 rows, 4 means 2 |
| `config-dm-pool` | display memory. Image buffers are full-width strips, so this scales with the panel |
| `config-disp-rotation` | passed to `ext-disp-orientation` |
| `config-touch-transforms` | `(swap-xy mirror-x mirror-y)` |
| `config-btn-actions-short` / `-long` | action id per button or touch region |

Plus `lib/input.lisp` (buttons and touch regions differ per board), the
fonts, and three functions: `board-disp-init`, `board-touch-init`, `bl-set`.

## Status strip

Turn signals at the outer edges, then the light pill, the kickstand, one
condition slot and the cruise pill.

The turn signals **blink in step with the vehicle**: the controller sends the
period it is flashing at and the moment the indicator came on, and the pill is
derived from both. `ind-ms` is taken as the half period, which puts the 430 ms
the bike package sends at about 1.2 Hz.

The light pill reads `HIGH` when high beam is on and `LIGHT` otherwise, and is
blue for high beam, green for low. `light-on-is-highbeam` in the board config is
for hardware whose single light output *is* the high beam, where there is no
separate signal to read.

**One condition slot**, because a 480 px strip has no room for a pill each and
these are all momentary. It shows whichever is most important, worst first:

| | | |
|---|---|---|
| `KILL` | red | the kill switch is holding the motor |
| `FAULT` | red | a controller fault code |
| `BRAKE` | amber | the brake input is applied |
| `REGEN` | green | the pack is taking current back |
| `FAN` | blue | the auxiliary output is on |

`KILL` and `FAN` come from the controller in byte 7 of SID 25, since the display
cannot work them out for itself; they need ESC firmware 7.02 for `get-kill-sw`
and `get-aux`, and `dash_esc` probes for both. `BRAKE` comes from the PAS status
flags, so it needs a PAS brake source configured — there is no general "brake
applied" signal on a VESC to read otherwise. `REGEN` is derived from pack power
going negative, so it needs nothing extra.

## Rolling chart

There is a chart page showing a rolling window of one live value, autoscaled to
what is in the window, with the source and window on the left and the span on
the right.

The source is any `slot-catalog` entry, so the chart gets its label, unit and
formatting for free and can plot anything a live cell can. Two settings pick it:
`chart-src` (catalog index) and `chart-secs` (5 or 10).

Samples come from `stats-thread`, which runs whatever page is showing, so the
window is already full when the page is opened. That thread ticks at 20 Hz but
the controller only sends at 10, so it samples every other tick: sampling faster
than the data arrives would only duplicate values and make the window shorter
than it claims. The ring is a byte buffer written as f32 rather than a list,
since the sampler runs forever and appending to a list would churn the heap.

Like the PAS page it is **off in the default page mask**; enable it in the
settings page, bit 5.

## PAS

There is a PAS page showing crank cadence, crank torque, rider power, motor
assist power, the assist multiple, the PAS output, speed and a status word. The
same values are also in `slot-catalog`, so they can be put in any of the four
configurable slots on the live page instead.

The page is **off in the default page mask**, because most vehicles have no
pedals. Enable it in the settings page, bit 4 of the page mask.

The data comes from `dash_esc` over two CAN frames: SID 26 carries cadence,
torque and the two powers, and the two spare bytes of SID 25 carry the status
flags and the output. `dash_esc` probes for the PAS getters once at startup,
since everything beyond the pedal RPM needs ESC firmware 7.01 or newer, and
sends nothing when they are absent. The page then shows `no data` rather than a
screen of zeros.

If a PAS value is put in a live-page slot with the colour ramp mode enabled, the
slot's own minimum and maximum drive the green to red ramp, and the defaults of
0 to 100 suit none of these. Ranges worth starting from, which are what a Cycle
Analyst uses for its own bar graphs: rider and assist power 0 to 400 W, cadence
0 to 120 rpm. Crank torque depends on the sensor, so use its full scale.

### Walk assist

Button action 13 is walk assist, and it only works as a **long** action. Assign
it to a button, then hold that button: once the hold indicator fills, the
request goes to the controller and keeps going while the button is down.
Releasing it stops the motor on the next frame.

It is held rather than triggered on purpose. The controller expires a walk
request after half a second, so it has to be re-sent continuously; a press that
latched would leave the motor driving if this display lost power. `walk-requested`
in `main_body.lisp` therefore derives the request from `btn-hold-region` and
`btn-hold-progress` rather than from `btn-do-action`, which fires once. It rides
in byte 2 of SID 201, which already goes out every 100 ms.

The controller side needs its PAS walk assist source set to Script, and `dash_esc`
2.5 or newer. The other dashes in this family send zero in that byte, so they
simply never request it.

The status word reports the worst active condition, worst first:

| word | meaning |
|---|---|
| `no rx` | no PAS data from the controller at all |
| `nopin` | the pedal sensor pins could not be claimed |
| `trqch` · `brkch` · `wlkch` | that ADC channel does not exist on this hardware |
| `sens` | the configured sensor type is not supported |
| `notrq` | hardware torque source selected on a board without one |
| `clip` | the torque sensor is at or above the ADC reference, so torque above that point is not being measured at all |
| `brake` | the brake is applied |
| `walk` | walk assist is driving |
| `splim` | assist is being cut back by the road speed taper |
| `ok` | nothing to report |

Five characters each, because the grid sizes the value column for a number and a
four column panel cuts anything longer off mid-word. The `pas_status` terminal
command on the controller spells them out in full.

## Importing

**Every `import` has to be in the board's `main.lisp`.** vesc_tool packs
imports by scanning the top-level lisp file only, with no recursion
(`codeloader.cpp`, `lispPackImports`), so an import inside an imported file
never reaches the device. That is why `main_body.lisp` contains none, and why
each board's `main.lisp` lists the whole shared tree explicitly with `../`
paths — which resolve, because imports are looked up relative to the main
file's directory.

## Testing

Layouts render to PNG on a workstation with no hardware. See the harness notes
in `dash_s3/README_Disp.md`.
