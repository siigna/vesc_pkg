# Log Analysis

Adds a log analysis tab to the VESC Tool **mobile** UI.

The desktop UI already has a full log analysis page, but it is built on Qt
Widgets and so is unreachable in the QML mobile build. This package ships the
same idea as QML: VESC Tool reads it off the device and instantiates it as a
tab, which means it works with the app as shipped — no custom APK.

## What it does

- Browses log files on the connected device over whatever transport is already
  in use (BLE, USB or WiFi)
- Parses the VESC CSV log format, including the field metadata in the header
- Draws one chart per related group of channels, with a shared time axis
- Drag to scrub the cursor and pan, pinch to zoom; every chart follows
- Recomputes duration, distance, top speed, energy and efficiency for whatever
  range is on screen

Channels the log does not contain are skipped, as are channels that only ever
read zero — an unconnected motor temperature sensor does not get a chart.

## Notes

- Reading a log is a blocking transfer. Large files over BLE are slow; WiFi or
  USB is much quicker.
## Installing replaces the whole package slot

A VESC device holds **one** package at a time, covering both its QML and its
LispBM slot. `CodeLoader::installVescPackage()` erases the lisp slot when the
package being installed has no lisp of its own, so:

**Installing this will remove any LispBM script currently on the device.**

Back the script up first if you need it (VESC Tool can read the running script
off the device). If you want to keep a script alongside this page, point
`pkgLisp` in pkgdesc.qml at it and rebuild, so the package carries both.

## Which device to install to

Install it to the device that holds the logs — normally the VESC Express, not
the motor controller. `fileBlockList`/`fileBlockRead` address the device VESC
Tool is connected to, so installing it on a controller gives you the tab but an
empty file list.
