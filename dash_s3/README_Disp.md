# Dash S3

A VESC dash for the **Waveshare ESP32-S3-Touch-LCD-4**: a 4" 480x480 ST7701
panel with GT911 touch and an onboard CAN transceiver.

This is a sibling of `dash16`, `dash35b` and `dash_vdisp`. It speaks the same
CAN protocol, reuses the same settings and statistics layers, and has the same
page and settings structure. What differs is the screen size, and that there
are no buttons.

## Requirements

- `vesc_express` firmware built with `HW_NAME="WS S3 Touch LCD 4"`. The
  display needs 20 GPIOs for the RGB bus, so the pin map lives in the hardware
  config and this package only calls `disp-init`. Stock firmware for another
  board will not have that extension and the package will not start.
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
+------------------------------------------+  y = 450
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
- There are no bitmap assets. The other dashes ship icons sized for a
  240-wide panel, which would be lost here, so the status indicators are drawn
  as text pills. The layout is driven by the constants at the top of
  `views/view_static.lbm`.
- The panel has no backlight control, so the brightness settings are carried
  for compatibility but do nothing.
