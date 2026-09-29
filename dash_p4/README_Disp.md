# Dash P4

A VESC dash for the **Waveshare ESP32-P4-WIFI6-Touch-LCD-4.3**: a 4.3"
800x480 ST7701 panel on MIPI-DSI, with GT911 touch, an onboard CAN
transceiver and an SD slot.

This is a sibling of `dash16`, `dash35b` and `dash_vdisp`. It speaks the same
CAN protocol, reuses the same settings and statistics layers, and has the same
page and settings structure. What differs is the screen size, and that there
are no buttons.

## Requirements

- `vesc_express` firmware built with `HW_NAME="WS P4 Touch LCD 4.3"`. Unlike
  the S3 board, the panel here is already supported upstream, so the package
  calls `disp-load-st7701` itself with the two values in `config.lisp`. What
  the hardware config supplies is the CAN and SD pins, the console kept off
  the CAN pads, and parking the backlight so nothing shows before the first
  draw.
- A VESC controller on CAN running the **dash_esc** package, which broadcasts
  the telemetry frames (CAN SIDs 20-24) this dash reads. Without it the
  standalone layer polls the controller directly, which works but updates more
  slowly and cannot drive mode profiles.

## Touch

There are no physical buttons, so screen regions stand in for them and the
stored button-action settings still apply:

```
+------------------------------------------+
|                                          |
|   tap left half        tap right half    |   previous / next page
|                                          |
+------------------------------------------+  y = 445
|   SET       |  Page 1/4  |       >       |
|  settings   |   lights   |   next page   |
+------------------------------------------+
```

The strip labels the regions under it, so what a tap does is on screen.

A press fires on release, so dragging off a region cancels it. Holding past
0.6 s fires that region's long-press action instead; by default only the
centre of the strip has one, which starts and stops logging on the controller.

On the settings page short presses always navigate it, whatever the actions
are set to: SET moves the selection, and the left and right halves of the
screen decrease and increase the selected value with hold-to-repeat. The
left of the strip reads BACK there and leaves the page.

All eight actions are configurable per region in the app UI.

If taps land in the wrong place, set `config-touch-transforms` in
`config.lisp` — `(swap-xy mirror-x mirror-y)`, each 0 or 1 — and make it match
`config-disp-rotation`.

## Pages

Which pages are in the rotation is set by the page mask in the settings page.

- **Live** — four configurable readouts, large. Pick the sources and optional
  colour ramps in the app UI.
- **Trip** — range, trip, odometer, efficiency, energy, regen, Ah, pack volts.
- **Session** — time, and the maxima since the last reset.
- **Battery** — pack and cell voltages, current, Ah count, temperature,
  humidity. Says so plainly when there is no BMS on the bus, rather than
  showing a screen of zeroes.
- **Settings** — scrolls when the list is longer than the page.

## Notes

- Fonts are pre-rendered by `font/generate_fonts`, like the other dashes.
  Preparing them on the device would be affordable here — unlike on a C3 —
  but it would mean shipping Roboto-Bold.ttf, which at ~145 kB is more than
  the fonts and the whole source put together.

  Note that the "Lisp data size ... / 131072 bytes" line the package build
  prints is not this package's real limit: that divisor is hardcoded and is
  the STM32's flash page. A VESC Express reports as a custom module and gets
  512 kB, shared between the source and the LBM image.
- Pin numbers in `config.lisp` are from the board documentation and have NOT
  been checked against hardware. Verify them before flashing.
- There are no bitmap assets. The other dashes ship icons sized for a
  240-wide panel, which would be lost here, so the status indicators are drawn
  as text pills. The layout is driven by the constants at the top of
  `views/view_static.lbm`.
- The backlight is real PWM on this board, so the brightness settings work,
  unlike on the square one. The pin is active-LOW and `bl-set` inverts the
  duty.
- The panel is 480x800 native, so landscape needs a rotation, and that
  rotation is a software transpose in `disp_st7701.c` costing two allocations
  and a CPU rotate per rendered image. That is affordable because the dash
  redraws only the fields that changed, and it is the reason not to move to
  full-frame redraws on this board without using the P4's PPA first.
- The bands are stacked vertically, which suits a square panel better than a
  1.67:1 one: the speed readout is centred with empty sides, and the settings
  page only fits two rows at a time. Using the width properly means a
  two-column arrangement, which is the first thing worth doing with a real
  layout engine.
