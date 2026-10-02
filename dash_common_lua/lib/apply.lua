-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Where the loaded settings go.
--
-- Ported from settings-build, settings-apply-pages, settings-apply-visual,
-- settings-set, settings-reset and restore-settings in
-- dash_common/lib/persistent-settings.lisp.
--
-- Separate from lib/settings.lua for a reason that is structural rather than
-- stylistic: view_pages reads settings, so settings must not read view_pages,
-- or the two would require each other. In the lisp there is no such
-- constraint -- every name is global and resolved late -- which is exactly
-- why the distribution there is invisible. Here it is one function and it can
-- be read.
--
-- The order inside distribute() is the lisp's and is load-bearing twice:
-- the theme is applied before the colours that fall back to it, and the page
-- mask is applied before page_now is checked against the new page count.

local settings = require("lib.settings")
local colors = require("lib.colors")
local units = require("lib.units")
local state = require("lib.state")
local mode = require("lib.mode")
local pin = require("lib.pin")
local stats = require("lib.statistics")
local vp = require("lib.view_pages")
local pages = require("lib.pages")

local M = {}

-- Supplied by the board. The default is a no-op so a bench harness can load
-- this without a panel, which is also what the dashes with no backlight
-- control get.
M.bl_set = function(_) end

-- Also the board's: how many pixels wide the panel is only matters here for
-- the full clear a theme change needs.
M.disp_clear = function(c)
	vesc.disp_clear(c)
end

--- the settings page rows ---

-- Build the visible row list from the mask and hand it to the view. The view
-- holds the names rather than the values: it reads each one back through
-- settings.read every frame, so a value written anywhere shows up without a
-- second copy to keep in step.
function M.build()
	local b = settings.build(settings.values.setting_mask, vp.setting_now)

	M.built = b
	vp.setting_list = b.names
	vp.setting_labels = b.labels
	vp.setting_fmts = b.fmts
	vp.setting_now = b.setting_now
	state.setting_num = b.num

	return b
end

--- distribution ---

function M.distribute()
	local v = settings.values

	-- Colours. The theme first, because the three overrides fall back to it
	-- and an unset override reads -1, which the clamp turns into the default
	-- it was given here.
	colors.theme = v.theme
	colors.apply_status()
	colors.bg = v.col_bg
	colors.accent = v.col_accent
	colors.text = v.col_text
	colors.slot_cols = v.slot_cols
	colors.build()

	-- The live page.
	vp.slots = v.slots
	vp.slot_modes = v.slot_modes
	vp.slot_mins = v.slot_mins
	vp.slot_maxs = v.slot_maxs
	vp.smooth = v.smooth
	vp.shade_slots = v.shade
	vp.chart_src = v.chart_src
	vp.chart_secs = v.chart_secs
	vp.btn_actions_long = v.btn_long

	-- The chart's own source index, which the sampler reads rather than the
	-- view: the view plots what was sampled, so the two must be the same
	-- number.
	stats.chart_src = v.chart_src

	-- Drive modes. Neutral, not 0: index 0 is reverse in the order dash_esc
	-- applies, so a stored mode past the end of a shortened list used to drop
	-- the bike into reverse.
	mode.num = v.drive_modes
	if mode.current >= mode.num then
		mode.set(1)
	end

	pin.code = v.pin_code

	-- The page set, which also re-checks page_now against the new count.
	pages.apply_mask(v.page_mask)
end

--- the whole sequence ---
--
-- load, build, distribute, units. The lisp's main calls these four in this
-- order; having one name for the sequence is what stops a caller doing three
-- of them.
function M.all(cfg)
	settings.load(cfg)
	M.build()
	M.distribute()
	settings.apply_units()
end

-- Write one setting and reload, so a read back is current. The repaint is
-- left to the caller's worker pass, which is what settings_redraw is for:
-- rebuilding every palette on each step of a held spinner would make the
-- settings page unusable.
function M.set(name, val, cfg)
	settings.write(name, val)
	M.all(cfg)
	state.settings_redraw = true
end

-- Everything on screen is the wrong colour now, so redraw the lot. Called
-- from the worker pass rather than from the press that caused it.
function M.visual()
	state.settings_redraw = false
	colors.build()
	M.disp_clear(colors.bg)
	state.view_force_static = true
	state.view_force_pages = true
	M.bl_set(state.backlight_dim and settings.values.bl_dim
		or settings.values.bl_bright)
end

--- the config packet ---
--
-- Port of send-cfg. One framed packet of the whole settings state, which the
-- package UI reads to populate itself.
--
-- Positional and append-only: the UI splits on spaces and indexes the
-- result, so inserting a field anywhere but the end silently reinterprets
-- every later one. The lisp says the same and it is the only thing holding
-- the two sides together -- there is no length, no version and no names on
-- the wire.
--
-- One packet rather than per-setting prints, because the REPL channel rate
-- limits to one command every 500 ms and sixty of those would take half a
-- minute.
--
-- Returns the string as well as sending it, so a test can compare it against
-- what the lisp dash produces without a board.
function M.cfg_string()
	local v = settings.values
	local standalone = require("lib.standalone")
	local out = {"cfg "}

	local function add(fmt, val)
		out[#out + 1] = string.format(fmt, val)
	end
	local function flag(b)
		add("%d ", b and 1 or 0)
	end
	-- The stored value, not the resolved one, so the UI can show "Theme" for
	-- a colour nobody has overridden. restore writes -1 for exactly that,
	-- and an unwritten cell reads as nothing.
	local function stored(name)
		add("%d ", settings.read(name) or -1)
	end

	flag(v.units_metric)
	flag(v.temps_metric)
	add("%.1f ", v.batt_hot)
	add("%.1f ", v.esc_hot)
	add("%.1f ", v.motor_hot)
	-- %d on a level that is a float on a board with real PWM backlight. That
	-- is the lisp's format and the UI parses it as an integer, so it is kept:
	-- the two levels this UI can set are 0 and 1.
	add("%d ", math.floor(v.bl_bright))
	add("%d ", math.floor(v.bl_dim))
	add("%d ", v.drive_modes)
	add("%d ", v.page_mask)
	add("%d ", v.setting_mask)

	for i = 1, 4 do add("%d ", v.btn_short[i]) end
	for i = 1, 4 do add("%d ", v.btn_long[i]) end

	add("%d ", v.esc_mode)
	add("%d ", v.esc_id)
	flag(standalone.active)
	add("%d ", standalone.esc_id)
	add("%d ", v.icon_mask)

	stored("col_accent")
	stored("col_text")

	for i = 1, 4 do add("%d ", v.slots[i]) end
	-- Resolved, not stored, unlike the three main colours above. That is the
	-- lisp's choice and it is observable: an unpicked cell sends the theme's
	-- text colour here and -1 there. Checked against the lisp's own output,
	-- which is the only reason it is right.
	for i = 1, 4 do add("%d ", v.slot_cols[i]) end
	for i = 1, 4 do add("%d ", v.slot_modes[i]) end
	for i = 1, 4 do add("%.0f ", v.slot_mins[i]) end
	for i = 1, 4 do add("%.0f ", v.slot_maxs[i]) end

	flag(v.batt_ramp)
	flag(v.splash)
	add("%d ", v.theme)
	stored("col_bg")
	add("%d ", v.chart_src)
	add("%d ", v.chart_secs)
	add("%.2f ", v.smooth)
	for i = 1, 6 do add("%d ", v.shade[i]) end
	add("%d ", v.pin_code)
	-- No trailing space on the last field, as the lisp has it: it appends
	-- "1" or "0" rather than going through the formatter.
	out[#out + 1] = v.pin_en and "1" or "0"

	return table.concat(out)
end

function M.send_cfg()
	local s = M.cfg_string()
	vesc.send_data(s)
	return s
end

--- factory defaults ---

-- Written to eeprom rather than merely held, so the next boot reads them back
-- and a version mismatch does not restore twice.
--
-- The three colours and the four slot colours are written as -1, which is
-- "nothing picked": that is what makes them follow the theme. Writing a real
-- colour would pin them, and every later theme change would move only the
-- status colours and leave the rest behind.
function M.restore(cfg)
	local w = settings.write

	-- Power profiles. Not read by this dash -- they are dash_esc's, carried
	-- here because the eeprom is shared and a restore must not leave them
	-- holding whatever was in those cells.
	w("pf1_speed", 39.3) w("pf1_brake", 1.0) w("pf1_accel", 1.0)
	w("pf2_speed", 18.8) w("pf2_brake", 0.4) w("pf2_accel", 0.6)
	w("pf3_speed", 11.2) w("pf3_brake", 0.2) w("pf3_accel", 0.4)
	w("pf_active", 0)

	w("whl_active", 0) w("whl_start", 20) w("whl_end", 43) w("whl_kd", 0.005)

	w("units_metric", cfg.metric_speeds and 1 or 0)
	w("temps_metric", cfg.metric_temps and 1 or 0)
	w("batt_hot", cfg.battery_hot)
	w("esc_hot", cfg.esc_hot)
	w("motor_hot", cfg.motor_hot)
	w("bl_bright", cfg.bl_bright)
	w("bl_dim", cfg.bl_dim)

	w("drive_modes", 5)
	w("page_mask", 0xF)
	w("setting_mask", 0xF)

	-- From the board's config, not hardcoded: which input index 0 to 3 means
	-- differs per board, so only the board knows a sensible default.
	for i = 0, 3 do
		w("btn" .. i .. "_short", cfg.btn_actions_short[i + 1])
		w("btn" .. i .. "_long", cfg.btn_actions_long[i + 1])
	end

	w("esc_mode", 0)
	w("esc_id", 0)
	w("icon_mask", 0x3F)
	w("batt_ramp", 0)
	w("splash_en", 1)
	w("theme", 0)
	w("smooth", 0.0)

	local shade = {4, 5, 6, 8, 9, 14}
	for i = 0, 5 do
		w("shade_" .. i, shade[i + 1])
	end

	w("pin_code", 0)
	w("pin_en", 0)

	w("chart_src", 4)
	w("chart_secs", 10)

	w("col_bg", -1)
	w("col_accent", -1)
	w("col_text", -1)

	local slots = {2, 6, 7, 15}
	for i = 0, 3 do
		w("slot_" .. i, slots[i + 1])
		w("slot_col_" .. i, -1)
		w("slot_mode_" .. i, 0)
		w("slot_min_" .. i, 0.0)
		w("slot_max_" .. i, 100.0)
	end

	w("ver_code", settings.version)
end

-- Wipe and reload. The page's own reset action.
function M.reset(cfg)
	M.restore(cfg)
	M.all(cfg)
	state.settings_redraw = true
end

-- Restore if the version code does not match, which usually means something
-- else was in this eeprom. Called once at startup, before load.
function M.restore_if_stale(cfg)
	if settings.read("ver_code") ~= settings.version then
		M.restore(cfg)
		return true
	end
	return false
end

return M
