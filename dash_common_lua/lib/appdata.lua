-- What the package UI is allowed to ask for.
--
-- The lisp dash takes this channel as code: its event handler is
-- (eval (read data)), so ui.qml sends "(settings-set 'theme 3)" and the dash
-- evaluates it. That works, and it means anything that can put a custom
-- app data packet on the wire -- over USB, over CAN, from another package --
-- can run arbitrary code on the display.
--
-- This does not do that, and cannot: the Lua sandbox removes load, on the
-- stated grounds that a script able to compile a string at runtime defeats
-- any static review of what was flashed. Rather than weaken that to match
-- the lisp, the channel carries three commands and a parser.
--
--   cfg                 reply with the config packet
--   set <name> <value>  write one setting and reload
--   reset               restore the factory defaults
--
-- So the surface is three verbs and a name that has to be in the address
-- map, instead of the whole language. That is a smaller surface than the
-- lisp's by a wide margin, and the parsing is testable, which eval never
-- was.
--
-- Deliberately not extended with anything that moves the vehicle. The UI
-- configures a display; a request that could apply current belongs on the
-- controller's own protocol where it can be gated on the kill switch.

local M = {}

-- Set by the board: both need its config to reload with.
M.send_cfg = function() return "" end
M.settings_set = function(_, _) return false end
M.settings_reset = function() return false end

-- Replies, which on target go out as framed app data. A table rather than a
-- call so a test can read what would have been sent.
M.last_reply = nil

function M.reply(txt)
	M.last_reply = txt
	vesc.send_data(txt)
end

-- Parse and run one command. Returns true when it was understood, plus a
-- message when it was not -- the caller logs that rather than replying,
-- because a malformed packet is not something to answer on the bus.
function M.handle(data)
	if type(data) ~= "string" then
		return false, "not text"
	end

	-- The lisp side sends a trailing NUL, and QML's sendCustomAppData
	-- appends one explicitly. Strip it and any surrounding space before
	-- anything else looks at the text.
	local line = data:gsub("%z.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")

	if line == "" then
		return false, "empty"
	end

	local verb, rest = line:match("^(%S+)%s*(.*)$")

	if verb == "cfg" then
		M.reply(M.send_cfg())
		return true
	end

	if verb == "reset" then
		M.settings_reset()
		-- Replying with the new state rather than making the UI ask: a reset
		-- changes every field, and the round trip is the one place where the
		-- UI and the dash can disagree about what just happened.
		M.reply(M.send_cfg())
		return true
	end

	if verb == "set" then
		local name, val = rest:match("^(%S+)%s+(%S+)$")
		if not name then
			return false, "set needs a name and a value"
		end

		local num = tonumber(val)
		if num == nil then
			return false, "value is not a number: " .. val
		end

		-- Unknown names are refused here rather than written: settings.write
		-- returns false for a name not in the address map, and a silent
		-- false would look to the UI like a value that did not take.
		if not M.settings_set(name, num) then
			return false, "no such setting: " .. name
		end

		M.reply(M.send_cfg())
		return true
	end

	return false, "unknown command: " .. verb
end

return M
