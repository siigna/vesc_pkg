-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Unit tests for lib/settings.load and lib/apply.lua: reading every stored
-- setting through its guard, and putting the results where the views read
-- them.
--
-- Ported from settings-load, restore-settings and the settings-apply-*
-- functions in dash_common/lib/persistent-settings.lisp, none of which has a
-- test. The properties worth pinning are the failure modes, because every one
-- of them is silent: a cell that was never written, a value from an older
-- build, a colour that is supposed to follow the theme, and the clamp
-- returning the default rather than the bound.
vesc = require("test.vesc_stub")
vesc.disp_clear = function() end

local t = require("test.harness")
local settings = require("lib.settings")
local colors = require("lib.colors")
local units = require("lib.units")
local state = require("lib.state")
local mode = require("lib.mode")
local pin = require("lib.pin")
local vp = require("lib.view_pages")
local pages = require("lib.pages")
local apply = require("lib.apply")

-- A board profile, as dash_p4/config.lisp has it.
local cfg = {
	metric_speeds = true,
	metric_temps = true,
	battery_hot = 55.0,
	esc_hot = 80.0,
	motor_hot = 80.0,
	bl_bright = 1.0,
	bl_dim = 0.25,
	btn_actions_short = {3, 2, 1, 6},
	btn_actions_long = {0, 12, 0, 8},
}

local function wipe()
	vesc.eeprom = {}
end

--- the address map ---
--
-- The addresses are written on somebody's hardware, so two names sharing one
-- would silently read each setting as the other. Checked here because the map
-- is append-only by convention and nothing else enforces it.
local seen = {}
local dup = nil
for name, e in pairs(settings.addrs) do
	if seen[e[1]] then
		dup = string.format("%s and %s both at %d", name, seen[e[1]], e[1])
	end
	seen[e[1]] = name
end
t.ok("no two settings share an address: " .. tostring(dup), dup == nil)

-- Every catalog row has to be readable, or the settings page shows a row that
-- cannot be written.
local missing = nil
for _, row in ipairs(settings.catalog) do
	if not settings.addrs[row[1]] then
		missing = row[1]
	end
end
t.ok("every catalog row has an address: " .. tostring(missing), missing == nil)

--- an empty eeprom ---
--
-- The case that matters most: a board that has never been written. Every read
-- is nil, and nil compared with a number is the error that took settings-load
-- down and left the dash dead before it drew anything.
wipe()
local v = settings.load(cfg)

t.ok("units come from the board",   v.units_metric == true)
t.near("so do the warn thresholds", v.batt_hot, 55.0)
t.near("and the backlight levels",  v.bl_dim, 0.25)
t.ok("drive modes default to five", v.drive_modes == 5)
t.ok("the page mask defaults",      v.page_mask == 0xF)
t.ok("the setting mask defaults",   v.setting_mask == 0xF)
t.ok("button actions default to none", v.btn_short[1] == 0 and v.btn_long[4] == 0)
t.ok("the chart source defaults to power", v.chart_src == 4)
t.ok("and its window to ten seconds",      v.chart_secs == 10)
t.near("smoothing is off",          v.smooth, 0.0)
t.ok("the PIN is off",              v.pin_en == false)
t.ok("and zero",                    v.pin_code == 0)
t.ok("icons are all on",            v.icon_mask == 0x3F)
t.ok("the splash is on",            v.splash == true)
t.ok("six shade cells",             #v.shade == 6)
t.ok("four slots",                  #v.slots == 4)

-- An unset colour follows the theme rather than reading as black, which is
-- what a plain clamp to 0 would have given.
colors.theme = 0
t.ok("an unset background follows the theme", v.col_bg == colors.theme_bg())
t.ok("so does the text colour",               v.col_text == colors.theme_text())
t.ok("and every slot colour",                 v.slot_cols[1] == colors.theme_text())

--- out of range, and -1 ---
--
-- clamp returns the default, not the bound. That is the lisp's behaviour and
-- the difference is visible: a stored -1 colour has to come back as the
-- theme's colour, and clamping to 0 would make it black.
wipe()
vesc.eeprom[82] = -1                         -- col_bg, "nothing picked"
vesc.eeprom[23] = 0                          -- page_mask, below its minimum
vesc.eeprom[79] = 99                         -- chart_src, past the catalog
v = settings.load(cfg)

t.ok("a -1 colour falls back to the theme", v.col_bg == colors.theme_bg())
t.ok("a page mask of zero falls back",      v.page_mask == 0xF)
t.ok("a chart source past the catalog falls back", v.chart_src == 4)

-- A NaN, which is what an integer -1 looks like read back as a float.
wipe()
vesc.eeprom[83] = 0.0 / 0.0                  -- smooth
v = settings.load(cfg)
t.near("a NaN falls back", v.smooth, 0.0)

--- stored values are honoured ---
wipe()
vesc.eeprom[15] = 0                          -- units_metric off
vesc.eeprom[16] = 0                          -- temps_metric off
vesc.eeprom[22] = 3                          -- three drive modes
vesc.eeprom[23] = 0xFF                       -- every page
vesc.eeprom[24] = 0x1FFF                     -- every setting row
vesc.eeprom[83] = 0.4                        -- smoothing on
vesc.eeprom[90] = 1234                       -- a PIN
vesc.eeprom[91] = 1
vesc.eeprom[57] = 12                         -- slot 0 -> Energy
vesc.eeprom[65] = 2                          -- slot 0 -> heat colouring
vesc.eeprom[73] = 500.0                      -- slot 0 max
for i = 0, 3 do
	vesc.eeprom[25 + i] = 1                  -- every short action is page+
	vesc.eeprom[29 + i] = 12                 -- every long action is reset
end

v = settings.load(cfg)
t.ok("metric off",              v.units_metric == false)
t.ok("three drive modes",       v.drive_modes == 3)
t.near("smoothing read",        v.smooth, 0.4)
t.ok("the PIN is read",         v.pin_code == 1234 and v.pin_en == true)
t.ok("slot 0 source read",      v.slots[1] == 12)
t.ok("slot 0 mode read",        v.slot_modes[1] == 2)
t.near("slot 0 max read",       v.slot_maxs[1], 500.0)
t.ok("short actions read",      v.btn_short[1] == 1 and v.btn_short[4] == 1)
t.ok("long actions read",       v.btn_long[2] == 12)

--- distribution ---
--
-- Where each value ends up. These are the assignments the lisp gets for free
-- from having one global namespace, which is why they are worth checking: a
-- value loaded and not distributed is a setting that silently does nothing.
apply.all(cfg)

t.ok("units applied to the unit module", units.speeds == "mph")
t.ok("and to temperatures",              units.temps == "fahrenheit")
t.ok("a unit change forces a static redraw", state.view_force_static)
t.ok("and a page redraw",                    state.view_force_pages)

t.ok("slots reach the live page",     vp.slots[1] == 12)
t.ok("slot modes too",                vp.slot_modes[1] == 2)
t.near("and the ranges",              vp.slot_maxs[1], 500.0)
t.near("smoothing reaches the page",  vp.smooth, 0.4)
t.ok("long actions reach the page",   vp.btn_actions_long[2] == 12)
t.ok("the shade cells reach it",      #vp.shade_slots == 6)
t.ok("the PIN code reaches pin",      pin.code == 1234)
t.ok("the drive mode count reaches mode", mode.num == 3)
t.ok("the page mask reaches pages",   state.page_num == 8)

-- The chart source has to be the same number in the view that plots it and
-- the sampler that fills it, or the chart is labelled as one thing and drawn
-- from another.
local stats = require("lib.statistics")
t.ok("the chart source agrees between view and sampler",
	vp.chart_src == stats.chart_src)

-- A drive mode past a shortened list goes to neutral, not to 0 -- index 0 is
-- reverse in the order dash_esc applies them.
mode.current = 4
vesc.eeprom[22] = 2
apply.all(cfg)
t.ok("a mode past the new count goes to neutral", mode.current == 1)

--- the settings page rows ---
--
-- The mask selects rows and the page caps how many fit. A mask selecting more
-- than fits must not draw off the page.
wipe()
vesc.eeprom[24] = 0x1FFF                     -- every row
apply.all(cfg)
t.ok("rows are capped at what fits", state.setting_num == settings.catalog_max)
t.ok("the view got that many names", #vp.setting_list == settings.catalog_max)
t.ok("and the same many labels",     #vp.setting_labels == settings.catalog_max)

-- A selected row past the end of a narrower list would index off it.
vp.setting_now = 5
vesc.eeprom[24] = 0x3                        -- two rows
apply.all(cfg)
t.ok("two rows now",                 state.setting_num == 2)
t.ok("and the selection was reset",  vp.setting_now == 0)

-- The view holds names, not values: it reads each one back every frame, so a
-- write anywhere shows up without a second copy to keep in step.
t.ok("the row list is names", settings.addrs[vp.setting_list[1]] ~= nil)

--- restore ---
wipe()
apply.restore(cfg)

t.ok("the version code is stamped", settings.read("ver_code") == settings.version)
t.ok("button actions come from the board",
	settings.read("btn0_short") == cfg.btn_actions_short[1])
t.ok("colours are stored as -1, not as a colour",
	settings.read("col_bg") == -1)
t.ok("so are the slot colours", settings.read("slot_col_0") == -1)

-- chart_src and chart_secs were added to the address map and to load() when
-- the chart page was written, and missed here. An unwritten cell reads nil on
-- hardware, so the clamp threw and took the whole of settings-load with it.
-- That is the one bug this file records in the lisp, so it is checked.
t.ok("the chart source is restored too", settings.read("chart_src") == 4)
t.ok("and its window",                   settings.read("chart_secs") == 10)

-- Every name load() reads must be written by restore, or the same bug comes
-- back for a different setting.
wipe()
apply.restore(cfg)
local unwritten = {}
for name, e in pairs(settings.addrs) do
	if vesc.eeprom[e[1]] == nil then
		unwritten[#unwritten + 1] = name
	end
end
table.sort(unwritten)
t.ok("restore writes every address in the map: " ..
	table.concat(unwritten, " "), #unwritten == 0)

--- a factory reset with a float backlight level ---
--
-- Found on hardware, by calling settings_reset over the REPL: the board's dim
-- level is 0.25 on a panel whose backlight is real PWM, and restore writes
-- both levels into integer cells. eeprom_store_i goes through
-- luaL_checkinteger, which refuses a float with no integer representation
-- rather than truncating, so a factory reset raised.
--
-- It passed here at the time because the stub floored silently. It does not
-- any more, which is what makes this a test rather than a comment.
wipe()
local pwm_cfg = {}
for k, v in pairs(cfg) do pwm_cfg[k] = v end
pwm_cfg.bl_bright = 1.0
pwm_cfg.bl_dim = 0.25

local ok_reset, err_reset = pcall(apply.restore, pwm_cfg)
t.ok("a restore with a float dim level does not raise: " .. tostring(err_reset),
	ok_reset)

-- And the value that lands is the truncation, which is a dark panel. That is
-- the lisp's behaviour too -- its load clamps bl-dim to 0..1 and 0 is in
-- range -- so it is asserted rather than quietly fixed. Fixing it properly
-- means float cells for the two levels, which means new addresses.
t.ok("the dim level truncates to zero", settings.read("bl_dim") == 0)

settings.load(pwm_cfg)
t.near("and loads as zero rather than the board default",
	settings.values.bl_dim, 0.0)

-- An integer-valued float is fine, which is the bright level's case.
wipe()
t.ok("an integer-valued float is accepted",
	settings.write("bl_bright", 1.0) ~= false)
t.ok("and reads back as the integer", settings.read("bl_bright") == 1)

--- the stale version check ---
wipe()
t.ok("an empty eeprom is stale", apply.restore_if_stale(cfg))
t.ok("and is not stale twice",   not apply.restore_if_stale(cfg))

vesc.eeprom[0] = settings.version - 1
t.ok("an older version is stale", apply.restore_if_stale(cfg))

--- the visual pass ---
--
-- Consumes the flag, so a theme change repaints once rather than forever.
local bl = nil
apply.bl_set = function(l) bl = l end
state.settings_redraw = true
state.backlight_dim = false
apply.all(cfg)
apply.visual()

t.ok("the redraw flag is consumed", not state.settings_redraw)
t.near("the backlight went to bright", bl, settings.values.bl_bright)

state.backlight_dim = true
apply.visual()
t.near("and to dim when dimmed", bl, settings.values.bl_dim)

t.report("apply")
