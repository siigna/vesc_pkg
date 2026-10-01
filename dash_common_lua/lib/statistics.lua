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

--- the rolling chart ---
--
-- A ring of samples, newest first when read. The lisp keeps it in a byte
-- buffer written as f32 because a hundred-element list would be allocated and
-- walked on every redraw; a Lua array of numbers is already that, so the
-- buffer goes away and the indexing stays.
--
-- chart_max is ten seconds at the 10 Hz the stats thread pushes. The window
-- setting reads fewer of them rather than making the ring bigger, which is
-- why window() clamps: a longer setting must not read past what was
-- allocated. That constraint is inherited rather than necessary here, and
-- kept so both dashes show the same history for the same setting.
M.chart_max = 100
M.chart_head = 0
M.chart_count = 0
M.chart_tick = 0
M.chart = {}

-- One sample into the ring. The oldest is dropped once it is full.
function M.chart_push(v)
	M.chart[M.chart_head + 1] = v
	M.chart_head = (M.chart_head + 1) % M.chart_max
	if M.chart_count < M.chart_max then
		M.chart_count = M.chart_count + 1
	end
end

-- Sample i counting back from the newest, 0 being the newest.
function M.chart_at(i)
	local idx = (M.chart_head - 1 - i + 2 * M.chart_max) % M.chart_max
	return M.chart[idx + 1]
end

-- How many samples the window covers.
function M.chart_window(chart_secs)
	local n = 10 * chart_secs
	if n > M.chart_max then
		n = M.chart_max
	end
	if n > M.chart_count then
		return M.chart_count
	end
	return n
end

-- Cleared when the charted source changes, since the history is of the old
-- one.
function M.chart_reset()
	M.chart_head = 0
	M.chart_count = 0
end

return M
