-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Units. Everything arrives as km/h, km and C; conversion happens only here.
--
-- Ported from dash_common/lib/user-settings.lisp. The lisp keeps the unit and
-- its label as a cons pair, so (car ...) is the unit and (cdr ...) the string;
-- here they are two fields, which is the same thing without the idiom.

local M = {}

M.KM_TO_MI = 0.621371
M.MS_TO_KPH = 3.6

-- "kmh" or "mph", and "celsius" or "fahrenheit". Speeds and distances move
-- together, as the lisp does: a rider who thinks in miles does not want
-- kilometres on the odometer.
M.speeds = "kmh"
M.temps = "celsius"

function M.c_to_f(c)
	return c * 1.8 + 32
end

function M.speed(kmh)
	if M.speeds == "mph" then
		return kmh * M.KM_TO_MI
	end
	return kmh
end

function M.dist(km)
	if M.speeds == "mph" then
		return km * M.KM_TO_MI
	end
	return km
end

function M.temp(c)
	if M.temps == "fahrenheit" then
		return M.c_to_f(c)
	end
	return c
end

function M.speed_str()
	return M.speeds == "mph" and "mph" or "km/h"
end

function M.temp_str()
	return M.temps == "fahrenheit" and "F" or "C"
end

function M.dist_str()
	return M.speeds == "mph" and "mi" or "km"
end

function M.eff_str()
	return M.speeds == "mph" and "Wh/mi" or "Wh/km"
end

return M
