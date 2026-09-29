# Dash ESC

CAN-server for the VESC Labs [Dash16](https://www.vesclabs.com/product/vesc-dash-16l/) and [Dash35B](https://www.vesclabs.com/product/vesc-dash-35b/) displays. This package should be installed on the ESC on the CAN-bus that provides data for the Dash. This package also implements the drive modes, cruise control and maps the analog lever to ADC2 on the ADC app.

**Note**  
Version 2.4 goes with the 2.4 Dash packages.

**Note**  
To use cruise control it needs to be enabled in APP ADC.

**Note**  
To use reverse APP ADC needs to use the mode **Current Reverse Button** or **Current Reverse ADC2 Brake Button**. On the Dash16 **Current Reverse ADC2 Brake Button** is recommended as it allows using the lever on the dash as a brake while enabling the reverse mode.

## Logging

A display button can start and stop logging, using the settings already on this page. The display shows Log Started or Log Stopped when the controller reports the change, so it says what actually happened rather than what the button asked for.

The log is closed when a display reports that power is about to go, as well as on the controller's own shutdown, so the last records are not lost when the bike is switched off at the display.

## Lights and the aux outputs

A display's light button is carried out here, on the controller's auxiliary
outputs. **Light output** on this page picks which: none, AUX1, AUX2 or both.
Both is the default and is what this package has always done.

It is a setting rather than a constant because `set-aux` on port 1 sets the
controller's `m_out_aux_mode` to unused in the running configuration. Anything
else on that pin stops working -- **Auxiliary Output Mode**, which is how a Ubox
runs its cooling fan, being the case that matters. There is no way to set the
mode back from a script, so a controller whose AUX1 belongs to the fan has to be
able to keep the lights off that pin. Set **Light output** to AUX2 and port 1 is
never touched for as long as this package runs.

The change is to the running configuration only, so a power cycle restores the
mode either way.

The light command is also applied **on a change** rather than on every frame
from the display. That matters more than it looks: at the display's 10 Hz frame
rate the old code re-asserted both outputs ten times a second, so the aux mode
was cleared again immediately however it got set, and a fan could never run
while a display was attached. The assumed starting state is "off", which a
freshly booted controller really is, so with the default setting nothing is
written to either output until the rider switches the lights on.

The fan indicator on the displays reads AUX1 and is **suppressed while the
lights own that pin**: its state is then the light state, which the display
already shows on its own, and reporting it as a fan as well would be wrong.

## PIN lock

A display can ask this controller to require a code at every power up. **Light
output** aside, this is the one setting here that a display writes rather than
reads: SID 205 command 3 sets the requirement and command 4 releases the
current power cycle.

**The requirement is stored here and the release is not**, so a power cycle
comes back locked. That is the whole reason this half exists. A display-only
lock is defeated by unplugging the display: the configured limits are restored
five seconds after a display stops talking, so the bike would be unlocked by
pulling a connector.

While it is holding, this package applies neutral's own drive profile from its
periodic thread rather than from a display frame, skips the no-display limit
restore, and **remembers but does not apply** the mode a display asks for --
so a second display, or one whose code has been cleared, cannot undo the hold
by sending a real mode.

Neither command needs the kill switch. Refusing to lock would be unhelpful, and
refusing to unlock would make the kill switch a second lock with no way past it.

Bit 3 of the SID 25 status byte says the lock is being held, which is what lets
a display show `LOCKD` even when it is not the display that set the code.

**A forgotten code means VESC Tool over USB**: clear `pin-req` from this page's
Defaults, or write the eeprom slot directly. That is the price of the lock
surviving the display being removed, and it is deliberate. The code itself
lives on the display, in plain eeprom that anything on the bus can read -- this
is a deterrent, not security.

## Servicing

Drive modes work by scaling the motor current, so anything the controller measures with current is measured wrong while a mode is applied. Motor detection is the usual case: in neutral the scale is zero and the motor will not turn at all, and in a drive mode it completes but stores values that were measured at part current.

Tick **Suspend drive profiles** on this page before detecting a motor or writing configuration. The configured limits become the live ones, and the displays show SERVICE while it is set. It clears itself at the next power cycle.

If the stored motor parameters cannot describe a real motor, the profile is suspended without being asked and the displays show MOTOR CONFIG BAD. That is what lets the motor be detected again. The profile goes back when a drive mode is selected, so recovering is just: detect, then pick a mode.

**Capture these limits as the baseline** records the limits to restore whenever a display goes away or the profile is suspended. Press it once the controller is configured the way you want it.

## Changelog

**Version 2.7 (2026-09-29)**

- PIN lock, held here rather than only on the display, so unplugging the
  display no longer unlocks the bike. SID 205 command 3 sets the requirement
  and 4 releases the power cycle; the requirement is stored and the release is
  not. While holding, neutral's profile is applied from the periodic thread,
  the no-display limit restore is skipped, and a mode a display asks for is
  remembered but not applied.
- SID 25 status bit 3 reports that the lock is being held.
- Added at eeprom slot 22 without bumping the settings version, so nothing
  stored here is reset.

**Version 2.6 (2026-09-29)**

- Light command is applied when it changes instead of ten times a second. The
  old behaviour re-asserted AUX1 at the display's frame rate, and `set-aux` on
  port 1 clears `m_out_aux_mode`, so Auxiliary Output Mode -- a Ubox cooling fan
  -- was held disabled for as long as a display was attached.
- **Light output** setting: none, AUX1, AUX2 or both. Set it to AUX2 to leave
  port 1 alone entirely, for a controller that uses it for a fan. Added without
  bumping the settings version, so nothing stored here is reset; an install from
  before this reads it as both, which is what it did.
- Fan indicator no longer reports the lights as the fan when they share AUX1.

**Version 2.5 (2026-09-29)**

- Sends PAS telemetry: cadence, crank torque, rider power and assist power on
  SID 26, with the status flags and output in the two spare bytes of SID 25.
  Probed once at startup, since the getters beyond the pedal RPM need ESC
  firmware 7.02, and nothing is sent when they are absent.

**Version 2.4 (2026-09-13)**
* Drive profile is written when it changes rather than ten times a second, so it no longer fights anything else writing configuration
* Configured limits are restored when no display is present, so a motor can be detected without a power cycle first
* Drive profile is suspended automatically while the stored motor parameters cannot describe a real motor, and can be suspended from this page for servicing
* Drive mode is held here and reported to the displays, so two displays can no longer disagree about it
* Configuration is not stored on shutdown unless the real limits are known
* Logging can be started and stopped from a display button

**Version 2.1 (2026-09-04)**
* Trap proc-sid

**Version 1.4 (2026-08-01)**
* Use native lib for setting profile
* Detach button in all modes

**Version 1.3 (2026-07-18)**
* Better multi-ESC support

**Version 1.2 (2026-07-14)**
* New app UI
* Configurable mode settings in UI

**Version 1.1 (2026-07-14)**
* Cruise control support
* Reverse support

**Version 1.0 (2026-07-03)**

* Initial Release

### Build Info

- Version: 2.7
- Build Date: 2026-09-29 16:02:05-07:00
- Git Commit: #43bdf68
