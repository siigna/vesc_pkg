-- The drive mode, and who gets to decide it.
--
-- Ported from the mode handling in dash_common/lib/vehicle-state.lisp and the
-- rule that consumes it in lib/communication.lisp.
--
-- The controller owns the drive mode: it is what applies the current limits,
-- and two displays on one bus must never show different modes or fight over
-- it. So this follows what the controller reports -- except for a window
-- after this display has asserted a mode itself, because the controller will
-- keep echoing the old one until it has been told, and following that echo
-- would undo a button press, the kickstand or charging.

local M = {}

-- Index into the mode list. 1 is neutral, whose current scale is zero; 0 is
-- reverse. The list is drive_mode_num long and comes from the board config.
M.current = 1
M.num = 5

-- When this display last asserted a mode. Zero is long ago.
M.cmd_ts = 0

-- How long the display's own assertion outranks the controller's report. Two
-- seconds is several status frames at 10 Hz, so a report that crosses with a
-- press loses rather than racing it.
M.hold_s = 2.0

function M.now()
	return vesc.systime()
end

function M.secs_since(t)
	return vesc.secs_since(t)
end

-- Assert a mode from this display: a button, the kickstand, charging, or the
-- PIN lock going on.
function M.set(m)
	M.current = m
	M.cmd_ts = M.now()
end

-- True while this display's own assertion still outranks the controller.
function M.asserting()
	return M.secs_since(M.cmd_ts) <= M.hold_s
end

-- Adopt what the controller reports, if it is allowed to win.
--
-- Returns true when the mode changed. Out-of-range values are ignored rather
-- than displayed: a frame from a controller configured with more modes than
-- this display knows about would otherwise index off the end of the mode
-- list, and a blank mode label is worse than a stale one.
function M.follow(reported)
	if M.asserting() then
		return false
	end

	if reported < 0 or reported >= M.num then
		return false
	end

	if reported == M.current then
		return false
	end

	M.current = reported
	return true
end

return M
