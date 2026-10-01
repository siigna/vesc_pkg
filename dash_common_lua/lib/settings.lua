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

return M
