-- Live values and the smoothing that makes them readable.
--
-- Ported from dash_common/lib/statistics.lisp. The state itself lives in
-- lib/state.lua; this module holds the arithmetic over it.

local M = {}

--- smoothing ---
--
-- One exponential step towards v, with a snap so a number actually arrives
-- rather than approaching forever.
--
-- k outside 0..1 exclusive means off: 0 never moves and 1 or more either
-- jumps or oscillates, so both return the target rather than being clamped
-- into a gain nobody asked for.
--
-- sv may be nil, which is a slot that has never been written -- the first
-- reading is taken as-is instead of being smoothed up from zero, because a
-- speed that fades in from 0 on the first frame looks like the bike moving.
function M.smooth_step(sv, v, k, lo, hi)
	if sv == nil or k <= 0.0 or k >= 1.0 then
		return v
	end

	local n = sv + k * (v - sv)

	-- Within a fifth of a percent of the range, or 0.05 for a slot with no
	-- range set, is close enough to land on. The floor matters: without it a
	-- cell whose range is unset gets a zero threshold and never snaps.
	local span = hi - lo
	local eps = 0.002 * span
	if eps <= 0.05 then
		eps = 0.05
	end

	if math.abs(v - n) < eps then
		return v
	end

	return n
end

return M
