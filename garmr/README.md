# Garmr — a set-and-forget assist level

**Prototype.** It works and it is rideable, but the level is a current rather
than a wattage, there is no ramp, and the settings are constants at the top of
`garmr.lisp`. See *What this is not* below.

This is the LispBM version, and on most bikes it is the one to use. An
STM32F405 carries one script engine, not both: LispBM alone leaves `.ram4` at
99.6% of 62 KB, so running the Lua sibling in `garmr_lua` means a firmware
build with no LispBM at all -- and therefore no Refloat, no Float, no TNT, no
dashboards. The two scripts are the same logic.

Idea from a Discord suggestion, with thanks:
<https://discordapp.com/users/1440099786974826528>

The suggestion was mechanical: take a throttle with a toggle switch, remove
the return spring, add friction so it holds position, and you have an assist
level you set once and switch on and off. The aim, in the author's words:

> I want a gentle amount of assistance all the way over my riding range, not
> that stupid cruise control style pedal assistance that stops above a certain
> speed […] I kinda already ride like this, except I need to manually hold the
> throttle in position constantly.

This does the same thing **without modifying the throttle**, which keeps its
spring. That is not fussiness: a throttle held by friction cannot return
itself, so if the toggle fails closed, or you forget it, nothing releases it.

## How it works

It drives the firmware's pedal-assist **walk keepalive**, which already does
nearly all of this: a constant relative current, no dependence on cadence,
brake cancel, throttle combining, and a half-second expiry so a script that
stops running releases the motor rather than leaving it driving.

The script decides *when* to ask:

- a toggle switch on an ADC pin, read with two thresholds so it cannot chatter
- a validity window, so a disconnected or shorted pin releases instead of
  reading as "on" — a floating input sitting mid-rail is the failure most
  likely to look like a working switch
- a debounce before engaging, and none before releasing
- brake, fault and an invalid brake channel all release immediately

## Before it will do anything

Set these once in ESCargot Tool, under **App Settings → PAS**. The script
cannot set them: the `walk_*` fields have no config symbol in either script
engine, which is deliberate — these are the settings that decide how hard the
motor pushes, and they should be visible in the Tool rather than buried in a
script.

| setting | value |
|---|---|
| App to use | `PAS` or `ADC+PAS` — the latter keeps your throttle |
| Walk source | `Lisp` — this script is the source |
| Walk max speed | `200` km/h — the cap must be out of the way. **`<= 0.01` means disabled, not unlimited** |
| Walk current | your level, as a fraction of the motor current limit |
| Walk require pedal | off — no interlock is the point |
| **Brake source** | **ADC, with a channel and threshold.** Mandatory: without it there is no brake cancel at all |

Then edit the `cfg-*` definitions at the top of `garmr.lisp` for your
switch's pin and voltages, and `make`.

If the switch does nothing, the script says why on the console: it reports
when it has asked for the hold and the firmware has not started driving,
which almost always means `Walk source` or `Walk current` is wrong.

## What this is not

- **No watts.** The level is a fraction of the current limit, so the power it
  delivers rises with speed. A watt setpoint needs the firmware's
  power-to-current loop, which walk assist does not run.
- **No ramp.** Walk assist returns early in `pas_compute_output`, before the
  ramp, so engage and release are current steps. Keep the level modest.
- **No settings page.** Tool-rendered settings need a package with a native C
  library registering `conf_custom`; a script cannot register one.
- **One config slot.** When that native library arrives, note the firmware
  supports exactly one custom config and the second registrant silently wins
  — so it will not coexist with Refloat, Float or TNT.

Those four are what the firmware work is for. This exists to answer the
question none of it can: whether a fixed level actually feels right across a
whole ride.

## Safety

Releases on: brake, any motor fault, an invalid brake channel, the switch
going out of its validity window, and the script stopping for any reason
(the keepalive expires in half a second). Under all of that, the firmware's
own timeout coasts the motor one second after the last command.

**No speed cutout**, by design. That is the point of the feature, and it also
means the assist keeps pushing at any speed — which in the EU and UK is a
throttle rather than pedal assist, and changes how the bike is classified.

## Tests

31 checks on the engage logic: the Schmitt trigger including its hysteresis —
a value between the two thresholds keeps the current state, which a single
threshold would not — the validity window, the debounce on engage but not on
release, the brake, brake-channel and fault vetoes, that every pass makes a
keepalive call rather than latching, and what `diagnose` reports for each PAS
flag. They run this file, not a copy of it.

Two ways, the same checks:

```sh
make test                                        # in the LispBM repl
cd bldc/tests/qemu && ./run.sh test_garmr_lisp    # on a simulated STM32F405
```

The repl needs the one from the `vesc_express` checkout, the same the dash
render tests use. The QEMU image needs neither that nor a board, which is how
these checks get into CI.

That image gives LispBM the firmware's own sizes — 2428 cons cells and a 28K
arena, the numbers from `lispif.c` rather than a comfortable set chosen for a
test — so running there is also the check that this script fits on a board. It
leaves 1326 cells free.

No C stand-ins were needed for the pedal-assist side: `test/stubs.lisp` defines
those six firmware calls as ordinary Lisp functions, and the image registers no
real ones to collide with. The image does supply `print`, `systime`,
`secs-since` and `sleep` in C, because those are host services rather than PAS
behaviour — the debounce has to be measured against a real clock, and a Lisp
fake would be measuring itself.

Four mutations confirm the checks bite, in both runners: removing the validity
window fails three, flattening the Schmitt trigger to a single threshold fails
the hysteresis check exactly, turning the keepalive into a latch fails three,
and removing the brake veto fails three.
