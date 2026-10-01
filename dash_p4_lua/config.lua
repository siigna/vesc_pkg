-- Board constants for the Waveshare ESP32-P4-WIFI6-Touch-LCD-4.3.
--
-- The Lua counterpart of dash_p4/config.lisp. Values taken from there rather
-- than re-derived, so the two dashes agree about the panel.
--
-- This file shadows dash_common_lua/lib/config.lua by being first on the
-- packer's import path: the board's numbers win, and the shared defaults are
-- the fallback for anything a board does not set.
return {
	-- Panel, after rotation. Native is 480x800, and the rotation is what
	-- makes it landscape.
	disp_w = 800,
	disp_h = 480,
	disp_rotation = 1,

	-- MIPI-DSI, so a reset pin and a lane rate rather than a pin list.
	disp_rst = 27,
	disp_lane_mbps = 500,

	-- Backlight is real PWM here. The pin is active-LOW, so bl_set inverts.
	bl_pin = 26,
	bl_freq = 5000,
	bl_bright = 1.0,
	bl_dim = 0.25,

	touch_sda = 7,
	touch_scl = 8,
	touch_rst = 23,
	touch_int = -1,

	-- The pack, which is what the battery model needs. Placeholders, as in
	-- the lisp: an unconfigured pack should read obviously wrong.
	battery_cells = 12,
	battery_ah = 20.0,
	battery_usable = 0.85,
	discharge_ticks = {3.30, 3.60, 3.68, 3.73, 3.77, 3.81, 3.85, 3.90, 4.00, 4.20},
	soc_voltage_weight = 0.4,
	soc_source = "esc",
}
