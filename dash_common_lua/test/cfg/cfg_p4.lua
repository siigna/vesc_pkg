-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- The config packet the package UI reads, built by the Lua dash.
--
-- Printed so test/cfg/run.sh can diff it against what the lisp dash's
-- send-cfg produces for the same settings. There is no length, no version and
-- no field names on the wire -- the UI splits on spaces and indexes the
-- result -- so the only thing holding the two sides together is that the
-- strings match exactly.
--
-- The lisp is the oracle here rather than the format strings in it. Reading
-- those got three fields wrong: page_mask (the harness sets its own), the
-- four slot colours (the lisp sends the resolved values where the three main
-- colours are sent as stored), and the pin_en flag at the end (appended
-- without a trailing space, bypassing the formatter).
vesc = require("test.vesc_stub")
vesc.disp_clear = function() end

local settings = require("lib.settings")
local apply = require("lib.apply")
apply.bl_set = function() end

-- The board profile, as dash_p4/config.lisp has it.
local cfg = {
	metric_speeds = true, metric_temps = true,
	battery_hot = 55.0, esc_hot = 80.0, motor_hot = 80.0,
	bl_bright = 1.0, bl_dim = 0.25,
	btn_actions_short = {3, 2, 1, 6},
	btn_actions_long = {0, 12, 0, 8},
}

-- Which case to build, matching the lisp side's.
local case = arg[1] or "default"

vesc.eeprom = {}
apply.restore(cfg)

if case == "default" then
	-- The render harness enables every page before anything else, so the
	-- reference carries that too.
	settings.write("page_mask", 0xFF)
elseif case == "custom" then
	settings.write("page_mask", 0x1F)
	settings.write("setting_mask", 0x3FF)
	settings.write("units_metric", 0)
	settings.write("temps_metric", 0)
	settings.write("drive_modes", 3)
	settings.write("batt_hot", 48.5)
	settings.write("esc_hot", 72.0)
	settings.write("motor_hot", 91.5)
	settings.write("bl_dim", 1)
	settings.write("esc_mode", 2)
	settings.write("esc_id", 17)
	settings.write("icon_mask", 0x2A)
	settings.write("theme", 3)
	settings.write("chart_src", 9)
	settings.write("chart_secs", 5)
	settings.write("smooth", 0.35)
	settings.write("pin_code", 4821)
	settings.write("pin_en", 1)
	settings.write("batt_ramp", 1)
	settings.write("splash_en", 0)
	-- Colours: one overridden, the rest left on the theme, so the stored and
	-- resolved cases are both exercised in one string.
	settings.write("col_accent", 0x3366FF)
	settings.write("slot_col_1", 0xFF8800)
	for i = 0, 3 do
		settings.write("slot_" .. i, 4 + i * 5)
		settings.write("slot_mode_" .. i, i)
		settings.write("slot_min_" .. i, -10.0 * i)
		settings.write("slot_max_" .. i, 55.0 + i)
	end
	for i = 0, 3 do
		settings.write("btn" .. i .. "_short", 17 + i)
		settings.write("btn" .. i .. "_long", 20 - i)
	end
	for i = 0, 5 do
		settings.write("shade_" .. i, 21 - i)
	end
end

apply.all(cfg)

-- Standalone reports two of the fields. Pinned, because its live value
-- depends on whether a controller has been seen.
local standalone = require("lib.standalone")
standalone.active = false
standalone.esc_id = -1

io.write(apply.cfg_string(), "\n")
