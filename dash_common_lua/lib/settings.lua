-- Settings, and the eeprom they live in.
--
-- Ported from dash_common/lib/persistent-settings.lisp, minus the PIN lock
-- which is lib/pin.lua.
--
-- Two things here are load-bearing and neither is obvious from the shapes:
-- the address map is append-only because the indices are in eeprom on
-- somebody's bike, and every read goes through a guard that degrades to a
-- default rather than failing. A setting that cannot be read must not stop
-- the display coming up.

local M = {}

-- Bump when the meaning of a slot changes, not when one is added.
M.version = 54

-- name -> {address, type}. Types: "i" integer, "f" float, "b" a flag stored
-- as an integer.
--
-- APPEND ONLY. The address is what is written on hardware, so reordering this
-- silently reinterprets a rider's settings as each other.
M.addrs = {
	ver_code    = {0,  "i"},
	pf1_speed   = {1,  "f"},
	pf1_brake   = {2,  "f"},
	pf1_accel   = {3,  "f"},
	pf2_speed   = {4,  "f"},
	pf2_brake   = {5,  "f"},
	pf2_accel   = {6,  "f"},
	pf3_speed   = {7,  "f"},
	pf3_brake   = {8,  "f"},
	pf3_accel   = {9,  "f"},
	pf_active   = {10, "i"},

	whl_active  = {11, "i"},
	whl_start   = {12, "f"},
	whl_end     = {13, "f"},
	whl_kd      = {14, "f"},

	units_metric = {15, "i"},
	temps_metric = {16, "i"},
	batt_hot     = {17, "f"},
	esc_hot      = {18, "f"},
	motor_hot    = {19, "f"},
	bl_bright    = {20, "i"},
	bl_dim       = {21, "i"},

	drive_modes   = {22, "i"},
	page_mask     = {23, "i"},
	setting_mask  = {24, "i"},

	btn0_short = {25, "i"},
	btn1_short = {26, "i"},
	btn2_short = {27, "i"},
	btn3_short = {28, "i"},
	btn0_long  = {29, "i"},
	btn1_long  = {30, "i"},
	btn2_long  = {31, "i"},
	btn3_long  = {32, "i"},

	esc_mode = {33, "i"},
	esc_id   = {34, "i"},

	-- 35 to 51 and 53 to 54 are holes. They held settings that were removed,
	-- and the addresses stay unused rather than being reclaimed: somebody's
	-- eeprom still has the old values in them, and reusing an address would
	-- read one setting as another.
	icon_mask = {52, "i"},

	col_accent = {55, "i"},
	col_text   = {56, "i"},

	slot_0 = {57, "i"},
	slot_1 = {58, "i"},
	slot_2 = {59, "i"},
	slot_3 = {60, "i"},

	slot_col_0 = {61, "i"},
	slot_col_1 = {62, "i"},
	slot_col_2 = {63, "i"},
	slot_col_3 = {64, "i"},

	slot_mode_0 = {65, "i"},
	slot_mode_1 = {66, "i"},
	slot_mode_2 = {67, "i"},
	slot_mode_3 = {68, "i"},

	slot_min_0 = {69, "f"},
	slot_min_1 = {70, "f"},
	slot_min_2 = {71, "f"},
	slot_min_3 = {72, "f"},

	slot_max_0 = {73, "f"},
	slot_max_1 = {74, "f"},
	slot_max_2 = {75, "f"},
	slot_max_3 = {76, "f"},

	batt_ramp  = {77, "i"},
	splash_en  = {78, "i"},
	chart_src  = {79, "i"},
	chart_secs = {80, "i"},
	theme      = {81, "i"},
	col_bg     = {82, "i"},
	smooth     = {83, "f"},

	shade_0 = {84, "i"},
	shade_1 = {85, "i"},
	shade_2 = {86, "i"},
	shade_3 = {87, "i"},
	shade_4 = {88, "i"},
	shade_5 = {89, "i"},

	-- A plain four digit number. Anything on the bus can read it; the note on
	-- the PIN lock in lib/pin.lua says what this is and is not.
	pin_code = {90, "i"},
	-- "i", not "b", like every other flag here: flag() compares the value
	-- against 1, and a "b" cell reads back as a boolean, which makes that a
	-- type error rather than false.
	pin_en   = {91, "i"},
}

function M.read(name)
	local e = M.addrs[name]
	if not e then
		-- A name not in the map reads as nothing, which the guards then turn
		-- into a default. The lisp does the same by returning nil out of the
		-- cond, and setting-clamp's comment is about exactly this path.
		return nil
	end

	local addr, ty = e[1], e[2]
	if ty == "f" then
		return vesc.eeprom_read_f(addr)
	end

	local v = vesc.eeprom_read_i(addr)
	if ty == "b" then
		if v == nil then return nil end
		return v ~= 0
	end
	return v
end

function M.write(name, val)
	local e = M.addrs[name]
	if not e then
		return false
	end

	local addr, ty = e[1], e[2]
	if ty == "f" then
		return vesc.eeprom_store_f(addr, val)
	end
	if ty == "b" then
		return vesc.eeprom_store_i(addr, val and 1 or 0)
	end
	return vesc.eeprom_store_i(addr, val)
end

-- The guard every numeric setting goes through.
--
-- Order matters. nil comes first because a name missing from the map, or a
-- slot never written, reads as nil on hardware -- and comparing nil with a
-- number is an error that took settings-load down with it and left the dash
-- dead before it drew anything. NaN is next, because an unwritten cell reads
-- -1 as an integer and that is NaN read as a float, and NaN fails every
-- comparison including against itself.
function M.clamp(v, lo, hi, dflt)
	if v == nil then return dflt end
	if v ~= v then return dflt end          -- NaN
	if v < lo then return dflt end
	if v > hi then return dflt end
	return v
end

-- A flag, where anything that is not exactly 0 or 1 is treated as unset. A
-- never-written cell reads nil, and comparing that to a number throws.
function M.flag(name, dflt)
	local v = M.read(name)
	if v == nil then return dflt end
	if v == true or v == 1 then return true end
	if v == false or v == 0 then return false end
	return dflt
end

-- {name, label, format, step, min, max}. The page fits six rows.
M.catalog = {
	{"whl_active",   "Wheelie EN",  "%d",       1,     0,   1},
	{"whl_start",    "Angle Start", "%.1f deg", 0.5,   0.0, 55.0},
	{"whl_end",      "Angle End",   "%.1f deg", 0.5,   0.0, 55.0},
	{"whl_kd",       "Damping",     "%.3f",     0.001, 0.0, 0.2},
	{"bl_bright",    "BL Bright",   "%d",       1,     1,   1},
	{"bl_dim",       "BL Dim",      "%d",       1,     0,   1},
	{"batt_hot",     "Batt Warn",   "%.0f C",   1.0,   0.0, 200.0},
	{"esc_hot",      "ESC Warn",    "%.0f C",   1.0,   0.0, 200.0},
	{"motor_hot",    "Motor Warn",  "%.0f C",   1.0,   0.0, 200.0},
	{"units_metric", "Metric Spd",  "%d",       1,     0,   1},
	{"temps_metric", "Metric Tmp",  "%d",       1,     0,   1},
	-- Bit 12. A bare index rather than a name because the settings page
	-- formats numbers, and here that is tolerable: the whole screen
	-- recolours as the number changes, so the value names itself.
	{"theme",        "Theme",       "%d",       1,     0,   4},
	-- Bit 13.
	{"smooth",       "Smoothing",   "%.1f",     0.1,   0.0, 0.9},
}

-- The page fits this many rows, and the mask may select more than that.
M.catalog_max = 6

-- Which catalog rows the settings page shows, from the mask.
--
-- Returns a table of columns rather than five parallel lists as the lisp
-- does: the view reads them by index together, and five lists that must stay
-- the same length is a bug waiting for someone to append to one of them.
function M.build(mask, setting_now)
	local out = {names = {}, labels = {}, fmts = {}, steps = {}, lims = {}}
	local shown = 0

	for i, row in ipairs(M.catalog) do
		-- Bit i-1, because the mask is written against the lisp's zero-based
		-- index and lives in eeprom.
		if (mask & (1 << (i - 1))) ~= 0 and shown < M.catalog_max then
			shown = shown + 1
			out.names[shown] = row[1]
			out.labels[shown] = row[2]
			out.fmts[shown] = row[3]
			out.steps[shown] = row[4]
			out.lims[shown] = {row[5], row[6]}
		end
	end

	out.num = shown
	-- A selection past the end of the new list would index off it.
	out.setting_now = (setting_now or 0) >= shown and 0 or setting_now or 0

	return out
end

--- loading ---
--
-- Port of settings-load. Every setting is read through a clamp with a
-- default, so a cell that was never written, or holds a value from a
-- different build, degrades to something usable rather than stopping the
-- display coming up.
--
-- The bounds are the lisp's and several of them are load-bearing in a way
-- the number does not show: each upper bound is the last valid index of
-- something that grows. Raise the bound when you append to that thing, or
-- the new entry clamps to zero and the choice quietly vanishes. Those are
-- marked below.
--
-- Values land in one table rather than on the modules that use them, because
-- the reads have to happen before anything is distributed: an unwritten
-- colour falls back to the theme, so the theme has to be known first.
M.values = {}

local function n_of(prefix, i)
	return prefix .. "_" .. i
end

-- Four or six of something stored as separate cells, which is how they are
-- addressed in eeprom.
local function load_list(prefix, count, lo, hi, dflt)
	local out = {}
	for i = 0, count - 1 do
		out[i + 1] = M.clamp(M.read(n_of(prefix, i)), lo, hi, dflt)
	end
	return out
end

function M.load(cfg)
	local colors = require("lib.colors")
	local v = {}

	v.units_metric = M.flag("units_metric", cfg.metric_speeds)
	v.temps_metric = M.flag("temps_metric", cfg.metric_temps)

	v.batt_hot  = M.clamp(M.read("batt_hot"),  0.0, 200.0, cfg.battery_hot)
	v.esc_hot   = M.clamp(M.read("esc_hot"),   0.0, 200.0, cfg.esc_hot)
	v.motor_hot = M.clamp(M.read("motor_hot"), 0.0, 200.0, cfg.motor_hot)

	-- 1 to 1 is not a typo. On the dashes this came from the backlight is an
	-- on/off pin, so the only storable bright level is 1; a board with real
	-- PWM gets its level from the config default, which is what the nil case
	-- returns. Only the dim level is adjustable.
	v.bl_bright = M.clamp(M.read("bl_bright"), 1, 1, cfg.bl_bright)
	v.bl_dim    = M.clamp(M.read("bl_dim"),    0, 1, cfg.bl_dim)

	-- view_static labels only 0-4, and dash_esc matches only 0-4.
	v.drive_modes = M.clamp(M.read("drive_modes"), 1, 5, 5)

	-- Bound is the last catalog page. The PAS page is bit 4 and off in the
	-- default mask, since most vehicles have no pedals. Raise when a page is
	-- added, or the new page cannot be enabled at all.
	v.page_mask = M.clamp(M.read("page_mask"), 1, 0xFF, 0xF)

	-- One bit per catalog row. Raise when the catalog grows.
	v.setting_mask = M.clamp(M.read("setting_mask"), 0, 0x1FFF, 0xF)

	-- Bound is the highest action id the dash dispatches. Raise when an
	-- action is added, or the new id clamps to 0 and the binding vanishes.
	v.btn_short = {}
	v.btn_long = {}
	for i = 0, 3 do
		v.btn_short[i + 1] = M.clamp(M.read("btn" .. i .. "_short"), 0, 21, 0)
		v.btn_long[i + 1]  = M.clamp(M.read("btn" .. i .. "_long"),  0, 21, 0)
	end

	v.esc_mode  = M.clamp(M.read("esc_mode"), 0, 2, 0)
	v.esc_id    = M.clamp(M.read("esc_id"), 0, 253, 0)
	v.icon_mask = M.clamp(M.read("icon_mask"), 0, 0x3F, 0x3F)
	v.batt_ramp = M.flag("batt_ramp", false)
	v.splash    = M.flag("splash_en", true)

	-- The theme first: it supplies the defaults the colour settings fall back
	-- to, so it has to be known before they are read. An index past the
	-- catalog falls back to row 0 inside theme_row rather than here, since
	-- the catalog length belongs with the catalog.
	v.theme = M.clamp(M.read("theme"), 0, 15, 0)
	colors.theme = v.theme

	v.col_bg     = M.clamp(M.read("col_bg"),     0, 0xFFFFFF, colors.theme_bg())
	v.col_accent = M.clamp(M.read("col_accent"), 0, 0xFFFFFF, colors.theme_accent())
	v.col_text   = M.clamp(M.read("col_text"),   0, 0xFFFFFF, colors.theme_text())

	-- Bound is the last slot_catalog index. Raise when the catalog grows, or
	-- the new sources cannot be selected at all.
	v.chart_src  = M.clamp(M.read("chart_src"), 0, 29, 4)
	v.chart_secs = M.clamp(M.read("chart_secs"), 5, 10, 10)

	-- Off by default: it raises the redraw rate while a value moves, and the
	-- S3 is the board with the least headroom for that.
	v.smooth = M.clamp(M.read("smooth"), 0.0, 0.9, 0.0)

	-- Same bound as the button actions, for the same reason.
	v.shade = load_list("shade", 6, 0, 21, 0)

	v.pin_code = M.clamp(M.read("pin_code"), 0, 9999, 0)
	v.pin_en   = M.flag("pin_en", false)

	v.slots      = load_list("slot", 4, 0, 29, 0)
	-- Same fallback as the three main colours: an unpicked cell takes the
	-- theme's text colour, so a live cell is not left white on a pale
	-- background.
	v.slot_cols  = load_list("slot_col", 4, 0, 0xFFFFFF, colors.theme_text())
	-- 0 fixed, 1 ramp, 2 heat, 3 low-warn, 4 sign. Raise when a rule is
	-- added, or it clamps to fixed and the choice vanishes.
	v.slot_modes = load_list("slot_mode", 4, 0, 4, 0)
	v.slot_mins  = load_list("slot_min", 4, -1000.0, 10000.0, 0.0)
	v.slot_maxs  = load_list("slot_max", 4, -1000.0, 10000.0, 100.0)

	M.values = v
	return v
end

--- units ---
--
-- The views read the unit, not the flag. Speeds and distances move together,
-- as the lisp has it: a rider who thinks in miles does not want kilometres on
-- the odometer.
function M.apply_units()
	local units = require("lib.units")
	local state = require("lib.state")

	units.speeds = M.values.units_metric and "kmh" or "mph"
	units.temps = M.values.temps_metric and "celsius" or "fahrenheit"

	-- A unit swap changes text the per-field comparison cannot see, because
	-- the number it is comparing did not change -- only its label and its
	-- scale did.
	state.view_force_static = true
	state.view_force_pages = true
end

-- Whether status-strip icon n is switched on.
function M.icon_on(n)
	return (M.values.icon_mask & (1 << n)) ~= 0
end

return M
