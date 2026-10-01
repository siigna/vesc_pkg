-- The board's own log, on the glass.
--
-- New: the lisp dash has no equivalent, because until now there was nothing
-- to read. commands_printf sends a COMM_PRINT packet out whichever port last
-- spoke to the board, so every line produced during bring-up -- which panel
-- came up, whether touch answered, whether the radio attached -- went
-- nowhere, and finding out why a display came up wrong meant a serial cable.
-- The firmware now keeps the last few dozen lines in a ring; this reads them.
--
-- Deliberately the plainest thing on the dash: fixed rows, oldest at the top,
-- newest at the bottom, no formatting of the text itself. It reads like a
-- Linux console because that is what it is, and a log that has been
-- prettified is a log you cannot trust to be the log.
--
-- Two sources are added on top of the firmware's: a line per bring-up step,
-- written by the board, and the touch read tallies -- which are the one fact
-- a board whose only input is touch cannot otherwise report, because a failed
-- read looks exactly like a finger that is not there.

local M = {}

-- How many lines the firmware keeps. Asking for more is harmless; this only
-- avoids a pointless copy.
M.max = 48

-- Lines the dash adds itself, oldest first. Kept separately from the
-- firmware's ring so a step can be recorded before the engine has a print
-- path, and so they survive the ring wrapping.
M.own = {}
M.own_max = 16

function M.now()
	return vesc.systime()
end

-- Record a bring-up step. Also printed, so it reaches a listening tool and
-- the firmware ring, where it will be interleaved with the ESP-IDF lines in
-- the right order.
function M.step(txt)
	local line = string.format("[%7.3f] %s", M.now() / 1000.0, txt)

	M.own[#M.own + 1] = line
	while #M.own > M.own_max do
		table.remove(M.own, 1)
	end

	print(txt)
	return line
end

-- Whether touch is answering, as a line rather than a number: the tallies on
-- their own need explaining every time they are read.
--
-- A board whose panel has stopped answering shows a climbing error count and
-- a frozen ok count, which is the difference between a wedged I2C bus and a
-- rider who has not touched the screen. Nothing else on the dash can tell
-- those apart.
function M.touch_line()
	if not vesc.touch_stats then
		return "touch: no stats binding"
	end

	local ok, err, last = vesc.touch_stats()

	if not vesc.touch_loaded() then
		return "touch: not loaded"
	end
	local input = require("lib.input")

	-- Three numbers because there are three ways touch can be useless and
	-- they need different fixes: the bus not answering, the panel answering
	-- but never reporting a finger, and a finger being reported while the
	-- regions or the dispatch are wrong.
	if err == 0 then
		return string.format("touch: bus ok (%d), %d fingers, %d actions",
			ok, input.reads, input.fires)
	end
	return string.format("touch: %d ok, %d FAILED, last err %d, %d fingers",
		ok, err, last, input.reads)
end

-- Everything to show, oldest first. The firmware's ring first, because it
-- starts earlier, then the dash's own steps, then the live lines that are
-- worked out per frame rather than recorded.
function M.lines()
	local out = {}

	local ring, dropped = vesc.log_lines(M.max)
	for _, l in ipairs(ring) do
		out[#out + 1] = l
	end

	if dropped and dropped > 0 then
		-- Said rather than hidden. A log that silently loses its beginning is
		-- worse than one that admits it.
		table.insert(out, 1, string.format("... %d earlier lines dropped", dropped))
	end

	for _, l in ipairs(M.own) do
		out[#out + 1] = l
	end

	out[#out + 1] = M.touch_line()

	return out
end

--- watching touch ---
--
-- A failed read is reported to the script as "not touched", so a panel that
-- has stopped answering looks exactly like a finger that is not there. On a
-- board whose only input is touch that is the single most expensive thing to
-- not know, and polling the tallies by hand needs a working REPL and a cable.
--
-- So the dash watches them itself and records the transitions. Transitions
-- rather than a sample: a line per second would fill the ring with news that
-- nothing has changed.
M.touch_err_last = 0
M.touch_ok_last = 0
M.touch_state = nil

-- Call periodically. Returns a line when something changed, nil otherwise.
function M.touch_watch()
	if not vesc.touch_stats then
		return nil
	end

	local ok, err, last = vesc.touch_stats()

	-- Three states worth distinguishing, and the middle one is the whole
	-- point: a panel answering but reporting nothing is a rider not touching
	-- the screen, while a panel that has stopped answering is a fault.
	local now
	if err > M.touch_err_last then
		now = "failing"
	elseif ok > M.touch_ok_last then
		now = "ok"
	else
		now = "silent"
	end

	local first = M.touch_state == nil
	local d_err = err - M.touch_err_last
	M.touch_err_last = err
	M.touch_ok_last = ok

	-- "silent" is not a state change: a read that neither succeeded nor
	-- failed means the poll did not run, which happens whenever the tick is
	-- busy, and reporting it would be reporting on the scheduler.
	if now == "silent" or now == M.touch_state then
		return nil
	end

	M.touch_state = now

	if now == "failing" then
		return M.step(string.format(
			"touch STOPPED ANSWERING: %d new errors, last err %d",
			d_err, last))
	end

	-- "again" only when it had failed. The first observation is not a
	-- recovery, and saying so read as though something had already gone
	-- wrong during bring-up.
	if first then
		return M.step("touch bus answering")
	end
	return M.step("touch answering again")
end

return M
