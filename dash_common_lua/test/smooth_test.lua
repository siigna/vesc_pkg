-- Unit tests for smooth_step. A port of dash_common/test/smooth_test.lisp,
-- asserting the same numbers.
local t = require("test.harness")
local stats = require("lib.statistics")

local smooth = stats.smooth_step

-- A gain outside 0..1 exclusive is off: 0 never moves, and 1 or more either
-- jumps or oscillates, so both are treated as off rather than clamped.
t.ok("k zero",  smooth(0.0, 42.0, 0.0, 0.0, 100.0) == 42.0)
t.ok("k one",   smooth(0.0, 42.0, 1.0, 0.0, 100.0) == 42.0)
t.ok("k over",  smooth(0.0, 42.0, 1.4, 0.0, 100.0) == 42.0)

-- An unwritten slot takes the first reading as-is.
t.ok("nil start", smooth(nil, 42.0, 0.3, 0.0, 100.0) == 42.0)

-- One step of a third of the way.
t.near("one step", smooth(0.0, 30.0, 1.0 / 3.0, 0.0, 100.0), 10.0)

-- Already there.
t.ok("settled", smooth(42.0, 42.0, 0.3, 0.0, 100.0) == 42.0)

-- Converges, and exactly, within a bounded number of refreshes. At 20 Hz the
-- live page gets 40 of these in two seconds, so the bound is what says the
-- number settles rather than drifting for the rest of the ride.
local function steps_to(from, to, k, lo, hi)
	local sv = from
	local n = 0
	while sv ~= to and n < 200 do
		sv = smooth(sv, to, k, lo, hi)
		n = n + 1
	end
	return n
end

t.ok("converges",            steps_to(0.0, 100.0, 0.3, 0.0, 100.0) < 30)
t.ok("converges down",       steps_to(100.0, 0.0, 0.3, 0.0, 100.0) < 30)
t.ok("converges slow gain",  steps_to(0.0, 100.0, 0.1, 0.0, 100.0) < 90)
t.ok("converges negative",   steps_to(0.0, -50.0, 0.3, -100.0, 100.0) < 40)

-- Never past the target, from either side, on the way in.
local function overshoots(from, to, k, lo, hi)
	local sv = from
	for _ = 1, 200 do
		sv = smooth(sv, to, k, lo, hi)
		if (to > from and sv > to) or (to < from and sv < to) then
			return true
		end
	end
	return false
end

t.ok("no overshoot up",        not overshoots(0.0, 100.0, 0.3, 0.0, 100.0))
t.ok("no overshoot down",      not overshoots(100.0, 0.0, 0.3, 0.0, 100.0))
t.ok("no overshoot high gain", not overshoots(0.0, 100.0, 0.9, 0.0, 100.0))

-- The snap threshold scales with the range, so a wide one settles at a
-- coarser absolute distance. A cell with no range set gets the 0.05 floor,
-- which keeps a small reading from snapping a visible distance.
t.ok("snap wide",         smooth(9999.0, 10000.0, 0.3, 0.0, 10000.0) == 10000.0)
t.ok("snap floor holds",  smooth(0.9, 1.0, 0.3, 0.0, 0.0) ~= 1.0)
t.ok("snap floor snaps",  smooth(0.99, 1.0, 0.3, 0.0, 0.0) == 1.0)

-- An unset range is lo == hi, which must not divide or produce a negative
-- threshold that snaps nothing.
t.near("zero range",     smooth(0.0, 10.0, 0.5, 0.0, 0.0), 5.0)
t.near("inverted range", smooth(0.0, 10.0, 0.5, 100.0, 0.0), 5.0)

t.report("smooth")
