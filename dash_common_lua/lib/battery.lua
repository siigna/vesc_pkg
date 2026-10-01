-- State of charge from the pack itself, rather than taking the controller's
-- word for it.
--
-- Ported from dash_common/lib/battery.lisp, asserting the same numbers in
-- test/battery_test.lua. The idea and the shape of the voltage table are from
-- DAVEga (github.com/janpom/davega, GPLv3). Reimplemented, not copied.
--
-- Two estimates, each wrong in its own direction:
--
--   voltage   tracks the pack directly and needs no calibration, but sags
--             under load, so it reads low under throttle and jumps back when
--             you coast.
--   coulomb   integrates amp hours out of the pack, so it is steady under
--             load, but it drifts: it only knows what it has counted since
--             something last told it where full was.
--
-- Blending them with a fixed weight gives a figure that neither sags nor
-- drifts much. config.soc_voltage_weight is the knob: 1.0 is voltage only,
-- 0.0 is coulomb only.
--
-- None of this replaces the controller's own figure unless you ask for it.
-- config.soc_source selects, and the default is the controller, because the
-- model is only as good as the pack capacity and cell count you configured
-- and those default to placeholders.

local config = require("lib.config")
local state = require("lib.state")
local du = require("lib.draw_utils")

local M = {}

--- voltage -> state of charge ---
--
-- config.discharge_ticks holds per-cell voltages at equally spaced states of
-- charge: the first entry is empty, the last is full, and the rest divide the
-- range evenly. A ten-entry table means 0%, 11.1%, 22.2% and so on, so
-- configuring a different chemistry is editing voltages rather than pairs.
--
-- Points are worth crowding where the curve is flat -- most of a lithium
-- pack's discharge sits between 3.6 and 3.9 V per cell, and a table that
-- ignores that reads nearly full for most of a ride.
function M.voltage_soc(v)
	local ticks = config.discharge_ticks
	local n = #ticks
	local cells = config.battery_cells

	if n < 2 or cells < 1 or v <= 0.0 then
		return 0.0
	end

	local vc = v / cells

	if vc <= ticks[1] then
		return 0.0
	end
	if vc >= ticks[n] then
		return 1.0
	end

	-- Find the interval this voltage falls in and interpolate within it.
	-- One-based indexing, so interval i runs from ticks[i] to ticks[i+1] and
	-- marks states of charge (i-1)/(n-1) to i/(n-1).
	for i = 2, n do
		local hi = ticks[i]
		if vc < hi then
			local lo = ticks[i - 1]
			local span = hi - lo
			local frac = span > 0.0 and (vc - lo) / span or 0.0
			return (i - 2 + frac) / (n - 1)
		end
	end

	return 1.0
end

--- amp hours -> state of charge ---
--
-- Against the usable capacity rather than the rated one, so 0% is the reserve
-- you decided on and not cell damage. A pack run to its real floor every ride
-- does not last.
function M.usable_ah()
	return config.battery_ah * config.battery_usable
end

function M.coulomb_soc(ah_spent)
	local cap = M.usable_ah()
	if cap <= 0.0 then
		return 0.0
	end
	return du.clamp01(1.0 - ah_spent / cap)
end

--- the blend ---
--
-- Clamped, because two independently derived fractions can land outside 0..1
-- between them -- a voltage above the top tick, or a counter re-anchored
-- while the pack was resting. Anything downstream that scales a bar by this
-- would index off the end of its palette.
function M.model_soc()
	local w = config.soc_voltage_weight
	return du.clamp01(w * M.voltage_soc(state.vin) +
			(1.0 - w) * M.coulomb_soc(state.battery_ah))
end

-- What the rest of the dash should use. "esc" trusts the controller,
-- "voltage" and "coulomb" take one estimate alone, "model" blends them.
-- Anything else falls back to the controller, as the lisp version does.
function M.soc()
	local src = config.soc_source

	if src == "voltage" then
		return M.voltage_soc(state.vin)
	elseif src == "coulomb" then
		return M.coulomb_soc(state.battery_ah)
	elseif src == "model" then
		return M.model_soc()
	end

	return state.battery_soc
end

return M
