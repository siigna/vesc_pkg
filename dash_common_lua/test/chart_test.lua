-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Unit tests for the rolling chart ring in lib/statistics.lua.
--
-- New: the lisp has no unit test for it. The ring is read newest-first with
-- modular arithmetic over a head that wraps, which is the kind of index that
-- is wrong by one for a long time before anyone notices a chart is drawn
-- backwards or a sample behind.
local t = require("test.harness")
local stats = require("lib.statistics")

stats.chart_max = 8        -- small, so wrapping is reachable in a test
stats.chart_reset()
stats.chart = {}

t.ok("empty window is zero", stats.chart_window(10) == 0)

stats.chart_push(1.0)
t.ok("one sample counted",  stats.chart_count == 1)
t.ok("newest is the sample", stats.chart_at(0) == 1.0)

stats.chart_push(2.0)
stats.chart_push(3.0)
t.ok("newest is the last pushed", stats.chart_at(0) == 3.0)
t.ok("one back",                  stats.chart_at(1) == 2.0)
t.ok("two back",                  stats.chart_at(2) == 1.0)
t.ok("count follows pushes",      stats.chart_count == 3)

-- Fill it exactly.
stats.chart_reset()
stats.chart = {}
for i = 1, stats.chart_max do
	stats.chart_push(i)
end
t.ok("count stops at the ring size", stats.chart_count == stats.chart_max)
t.ok("newest when full", stats.chart_at(0) == stats.chart_max)
t.ok("oldest when full", stats.chart_at(stats.chart_max - 1) == 1)

-- Overflow: the oldest is dropped, and the order is still newest-first.
stats.chart_push(99)
t.ok("count does not grow past the ring", stats.chart_count == stats.chart_max)
t.ok("newest after wrapping", stats.chart_at(0) == 99)
t.ok("second newest after wrapping", stats.chart_at(1) == stats.chart_max)
t.ok("oldest is now the second sample", stats.chart_at(stats.chart_max - 1) == 2)

-- Read every slot after a wrap and check the sequence is contiguous and
-- descending: an off-by-one in the modular index shows up as a repeat or a
-- gap rather than as an error.
local ok_seq = true
for i = 0, stats.chart_count - 2 do
	local a = stats.chart_at(i)
	local b = stats.chart_at(i + 1)
	if not (a == b + 1 or (a == 99 and b == stats.chart_max)) then
		ok_seq = false
	end
end
t.ok("no repeats or gaps after a wrap", ok_seq)

-- Many wraps, to be sure head and count stay consistent rather than drifting.
for i = 1, 100 do
	stats.chart_push(1000 + i)
end
t.ok("count stable over many wraps", stats.chart_count == stats.chart_max)
t.ok("newest after many wraps", stats.chart_at(0) == 1100)
t.ok("oldest after many wraps",
	stats.chart_at(stats.chart_max - 1) == 1100 - stats.chart_max + 1)

-- The window reads fewer samples rather than resizing the ring, and must
-- never exceed what was allocated or what has been collected.
t.ok("window clamps to the ring", stats.chart_window(1000) == stats.chart_max)
t.ok("window follows the setting", stats.chart_window(0.5) == 5)
stats.chart_reset()
t.ok("window clamps to what has been collected", stats.chart_window(10) == 0)
stats.chart_push(1.0)
t.ok("window of one sample", stats.chart_window(10) == 1)

-- Reset forgets the history, since it belongs to the old source.
stats.chart_reset()
t.ok("reset clears the count", stats.chart_count == 0)
t.ok("reset rewinds the head", stats.chart_head == 0)

t.report("chart")
