-- PIN lock.
--
-- Ported from the PIN section of dash_common/lib/persistent-settings.lisp.
--
-- A deterrent, not security. The code is a plain number in eeprom that
-- anything on the bus can read, and while only this display enforces it,
-- unplugging the display defeats it: dash_esc puts the real limits back five
-- seconds after a display stops talking. dash_esc 2.7 can hold the lock
-- itself, which closes that at the price of needing VESC Tool over USB to
-- recover a forgotten code.
--
-- What the display can do is assert neutral, whose current scale is zero, so
-- the motor will not turn. It cannot hold the kill switch: that is an input,
-- and there is no setter for it.

local M = {}

-- Digits entered so far, as a number and a count, which is enough for a
-- four-digit code and avoids a list to append to on every key.
M.entered = 0
M.entry_len = 0

M.locked = false
M.len = 4

-- Wrong tries, and when the current wait started. Escalating, because four
-- digits is ten thousand guesses and a tap is quick.
M.tries = 0
M.wait_ts = 0
M.wait_s = 0
M.wait_left = 0

-- Sticky for a couple of seconds so the rider sees why a press did nothing.
M.msg_txt = ""
M.msg_ts = 0

-- The code to check against, and the drive mode to restore. The lisp version
-- reads settings-pin-code and drive-mode as globals; here they are set by
-- whoever owns them.
M.code = 0
M.drive_mode = 0

-- Sent when the lock changes. Defaults to doing nothing so a host test can
-- drive the logic without comms, and the dash replaces them.
M.on_lock = function() end
M.on_unlock = function() end

-- The clock, replaceable for the same reason as in lib/signals.lua.
function M.now()
	return vesc.systime()
end

function M.secs_since(t)
	return vesc.secs_since(t)
end

function M.notify(txt)
	M.msg_txt = txt
	M.msg_ts = M.now()
end

function M.msg()
	if M.wait_left > 0 then
		return string.format("wait %d s", M.wait_left)
	end
	if M.secs_since(M.msg_ts) < 2.0 then
		return M.msg_txt
	end
	return ""
end

function M.dots()
	local out = {}
	for i = 0, M.len - 1 do
		out[#out + 1] = i < M.entry_len and "*" or "-"
	end
	return table.concat(out, " ") .. " "
end

function M.clear()
	M.entered = 0
	M.entry_len = 0
end

-- Counted down here rather than computed in the view, so the view redraws
-- when the number changes and not on every frame.
function M.tick()
	local left = 0
	if M.wait_s > 0 then
		left = M.wait_s - math.floor(M.secs_since(M.wait_ts))
	end

	M.wait_left = left > 0 and left or 0

	if M.wait_left == 0 and M.wait_s > 0 then
		M.wait_s = 0
	end
end

function M.waiting()
	return M.wait_left > 0
end

function M.submit()
	if M.entry_len == M.len and M.entered == M.code then
		M.tries = 0
		M.locked = false
		M.clear()
		M.on_unlock()
		return
	end

	M.tries = M.tries + 1
	M.clear()

	-- Three free tries, then five seconds a try, capped at a minute: long
	-- enough to be tedious, short enough that a rider who fumbled their own
	-- code is not stranded.
	if M.tries > 3 then
		local w = 5 * (M.tries - 3)
		M.wait_s = w > 60 and 60 or w
		M.wait_ts = M.now()
	end

	M.notify("Wrong code")
end

-- A key: a digit, -1 to clear, -2 to submit. Submitting a short code is
-- treated as a wrong one rather than ignored, so a rider who mistypes gets
-- the same feedback either way.
--
-- A press during a lockout returns rather than falling through. In the lisp
-- version that needed defunret, and without it every key press during a wait
-- threw variable_not_bound instead of being ignored.
function M.key(v)
	if M.waiting() then
		return
	end

	if v == -1 then
		M.clear()
	elseif v == -2 then
		M.submit()
	elseif M.entry_len < M.len then
		M.entered = M.entered * 10 + v
		M.entry_len = M.entry_len + 1
		-- Submit on the last digit, so a four digit code needs four taps
		-- rather than five.
		if M.entry_len == M.len then
			M.submit()
		end
	end
end

-- Lock now, or at startup. Clears any entry in progress and any wait, so the
-- rider is not made to sit out a penalty they earned before locking.
function M.engage()
	M.locked = true
	M.tries = 0
	M.wait_s = 0
	M.wait_left = 0
	M.clear()
	M.on_lock()
end

-- What goes out as the drive mode while the lock is up. Neutral, index 1,
-- whose current scale is zero. The stored mode is left alone so unlocking
-- puts the rider back in the mode they were in.
function M.get_drive_mode()
	if M.locked then
		return 1
	end
	return M.drive_mode
end

return M
