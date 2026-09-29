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
| `UNSVD` | amber | controller settings changed but not written to flash |

`KILL` and `FAN` come from the controller in byte 7 of SID 25, since the display
cannot work them out for itself; they need ESC firmware 7.02 for `get-kill-sw`
and `get-aux`, and `dash_esc` probes for both. `BRAKE` comes from the PAS status
flags, so it needs a PAS brake source configured — there is no general "brake
applied" signal on a VESC to read otherwise. `REGEN` is derived from pack power
going negative, so it needs nothing extra.

## Controller settings

A second settings page edits settings that live on the **controller**, as
against the display settings the first one edits. Values are mirrored in over
CAN, one per frame on SID 27, so the page fills itself in about a second without
asking for anything, and shows what the controller actually has rather than what
was last asked for — a clamped or refused change shows up as such.

Changes go out on SID 205 and are applied with `conf-set`, which is **RAM only**.
That is deliberate: a setting changed while riding should not commit itself to
flash. The strip shows `UNSVD` while there are applied-but-unwritten changes,
and button actions 14 and 15 save and revert. Both are refused by the controller
unless the kill switch is on, because writing fights anything else touching the
configuration — detection above all — and reverting mid-ride would change the
feel abruptly.

Rows fall into two tiers. The plain ones are safe to change while moving: the
assist gain, PAS current, taper speeds, power cap and the current scales. The
**starred** ones are calibration values that would step the assist mid-ride, so
the controller only accepts them while the kill switch holds the motor. The dash
shows those dim and marked when the switch is off, so it is clear before
pressing rather than after.

The ids are what travel over CAN, so `conf-menu` here and `conf-params` in
`dash_esc` must stay in the same order, and both are append-only. The
controller enforces its own limits rather than trusting the display, since a
display is on a bus anyone can put a frame on: the table here is for
presentation.

Needs ESC firmware 7.02 for the `conf-set` symbols, `get-kill-sw` and
`conf-store`.

## Theming

`theme-catalog` in `lib/colors.lisp` holds one row per theme:
`(name bg accent text ok warn crit)`. Row 0 is the palette the dash shipped
with, value for value, so the default look does not move. Index order is stored
in eeprom, so **only append**.

| theme | for |
|---|---|
| `Dark` | the original: black, cyan accent, white text |
| `Amber` | same but a warmer accent |
| `Green` | same with a green accent |
| `Night` | everything pulled down and towards red, so a bright panel does not destroy dark adaptation |
| `Light` | the only pale background. Its status colours are darkened rather than reused: the default yellow and green have almost no contrast against white |

A theme supplies **defaults**, not overrides. The background, accent, text and
the four live-cell colours each have their own setting, and a colour the rider
picked in VESC Tool keeps winning. That works without a sentinel of its own
because an unwritten eeprom cell reads `-1` and `setting-clamp` hands back the
default for anything below its lower bound, so "not picked" and "follow the
theme" are the same state. The pickers carry a **Theme** entry that writes `-1`
to get back to it. `colorIndexOf` also falls back to that entry, so a colour
outside the ten-item list shows as Theme rather than being misreported as one
that is in it.

The three status colours come from the theme only. Overriding them one at a
time is three more cells and a picker each, for a choice that has to stay
legible against the background to mean anything.

**Upgrading from a build before themes**: those installs already have a colour
written into the accent, text and live-cell cells, so switching theme will move
the background and the status colours but leave those alone -- and white text on
the Light background is unreadable. Set each to **Theme** once and they follow
from then on. Existing settings are otherwise untouched: `settings-version` is
deliberately **not** bumped for this, since that wipes every stored setting.

Nothing draws a colour behind the palette's back. Every ramp is built by
`colors-make-aa` with `color-bg` as its first entry and every full-screen wipe
is `disp-clear color-bg`, which is what lets a pale background work at all --
text and icons antialias against whatever the background is. There are two
literal colours left in the tree, both in `colors.lisp`: the initial values,
replaced on the first `settings-load`, and the blue and purple icon ramps.
`test/render_pages.lisp` renders the live page under `Light` for exactly this
reason: it is the row that would expose anything still assuming black.

Changing the theme needs a full repaint, since the palettes are baked into the
indexed buffers already on screen. `settings-set` and `setting-update` both
raise `settings-redraw` for it and the worker calls `settings-apply-visual`.
`setting-update` raises it for **this setting only**: the settings spinner
repeats while a button is held, and repainting the panel per step would make it
unusable.

## Rolling chart

There is a chart page showing a rolling window of one live value, autoscaled to
what is in the window, with the source and window on the left and the span on
the right.

The source is any `slot-catalog` entry, so the chart gets its label, unit and
formatting for free and can plot anything a live cell can. Two settings pick it:
`chart-src` (catalog index) and `chart-secs` (5 or 10).

### Picking what it plots

**Hold a cell on the live page.** The value under the finger drifts towards the
accent colour as the hold fills, and at the long-press point the chart page
opens already plotting that cell. It is the same gesture the session page uses
to reset, read the other way round: there the held value fades towards the
background because the press destroys it.

That works because a live cell already stores a `slot-catalog` index, which is
exactly what the chart plots, so pointing at a cell needs no separate menu and
no new stored setting. The 30-entry catalog is reachable by putting a source in
a live cell first, in Settings, and then holding it.

`live-cell-hit` in `view_pages.lbm` is the inverse of the `live-cell-x` /
`live-cell-y` pair that draws the grid, derived from the same three numbers, so
it follows whatever grid a board profile produced -- 2x2 on a square panel, one
row of four on a wide one. `test/hit_test.lisp` checks the round trip on both
shipped profiles and one that nothing ships.

Long presses run through `btn-long`, which lets a page claim the gesture the way
`btn-short` already lets the settings and controller pages claim short ones. A
hold that lands outside the cell grid, or on any other page, still does whatever
the region's stored long action says -- so a session reset bound to a held region
keeps working everywhere except over a live cell. **Walk assist is never
claimed**: it is held rather than triggered and `walk-requested` reads the held
state directly, so taking the region would leave the request running while the
chart page opened.

On the chart page itself, a press on the **left or right half** steps the source
through the sources the live cells hold, and a **hold** there toggles the window
between 5 and 10 seconds. Only above the nav strip: regions 1 and 2 are both the
screen halves and part of the strip, and claiming the strip too would leave no
way to page off the chart. Both write through to eeprom, so the choice survives
a power cycle.

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
