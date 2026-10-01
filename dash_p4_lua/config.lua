-- Board constants for the Waveshare ESP32-P4-WIFI6-Touch-LCD-4.3.
--
-- The Lua counterpart of dash_p4/config.lisp. Values taken from there rather
-- than re-derived, so the two dashes agree about the panel.
--
-- Not a shadow of dash_common_lua/lib/config.lua, despite holding some of the
-- same fields: require("lib.config") resolves to that file regardless of what
-- this package puts at "config". main.lua copies these over it at startup,
-- which is what makes the board's numbers win.
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

	-- Bands, stacked by view_static.set_layout. Changing one height moves
	-- what follows it, so these are the only numbers that differ between a
	-- 480x480 and an 800x480 panel.
	strip_h = 58,      -- status strip along the top
	speed_h = 145,     -- big speed readout
	page_h = 120,      -- swappable page area
	page_cols = 4,     -- label/value columns; 8 cells, so 4 cols = 2 rows
	page_row_h = 44,   -- must fit the font the page grid draws with

	-- Touch, as (swap_xy, mirror_x, mirror_y). The panel is rotated in the
	-- display driver and the controller is told the rotated size, so nothing
	-- is left to undo here.
	touch_transforms = {false, false, false},

	-- Which action each of the four touch regions runs, short and long. See
	-- lib/actions.lua for the ids. Only the board knows a sensible default,
	-- because which region index 0 to 3 means differs per board.
	--
	--   0 settings, 1 page-, 2 page+, 3 lights
	btn_actions_short = {3, 2, 1, 6},
	--   region 1 long-presses to reset the session
	btn_actions_long = {0, 12, 0, 8},

	drive_mode_names = {"REVERSE", "NEUTRAL", "ECO", "NORMAL", "SPORT"},

	-- For hardware whose single light output is the high beam, where there is
	-- no separate signal.
	light_on_default = false,
	light_on_is_highbeam = false,

	-- Prefer GNSS speed over the controller's estimate. Off: this board has
	-- no GNSS of its own.
	gnss_use_speed = false,

	-- Defaults the settings fall back to when their eeprom cells are unset.
	metric_speeds = true,
	metric_temps = true,
	battery_hot = 55.0,
	esc_hot = 80.0,
	motor_hot = 80.0,

	-- The pack, which is what the battery model needs. Placeholders, as in
	-- the lisp: an unconfigured pack should read obviously wrong.
	battery_cells = 12,
	battery_ah = 20.0,
	battery_usable = 0.85,
	discharge_ticks = {3.30, 3.60, 3.68, 3.73, 3.77, 3.81, 3.85, 3.90, 4.00, 4.20},
	soc_voltage_weight = 0.4,
	soc_source = "esc",
}
