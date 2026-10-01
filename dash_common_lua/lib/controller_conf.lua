-- Controller settings the dash may change.
--
-- Ported from dash_common/lib/controller-conf.lisp. Separate from the display
-- settings in lib/settings.lua: these live on the controller, are mirrored in
-- over CAN, and are changed by sending a frame back rather than by writing
-- eeprom here.
--
-- The ids, limits and step come from this table; the controller has its own
-- copy of the ids and enforces its own limits, because a display is on a bus
-- anyone can put a frame on. So this table is for presentation, not safety.

local state = require("lib.state")

local M = {}

-- {id, label, format, step, gated}
--
-- Order must match the controller's, since the id is what goes over CAN.
M.menu = {
	{0,  "Assist Gain",  "%.2f", 0.1,  false},
	{1,  "PAS Current",  "%.2f", 0.01, false},
	{2,  "Taper Start",  "%.1f", 0.5,  false},
	{3,  "Taper End",    "%.1f", 0.5,  false},
	{4,  "Power Cap",    "%.0f", 10.0, false},
	{5,  "Regen Scale",  "%.2f", 0.05, false},
	{6,  "Accel Scale",  "%.2f", 0.05, false},
	{7,  "PAS Mode",     "%.0f", 1.0,  true},
	{8,  "Magnets",      "%.0f", 1.0,  true},
	{9,  "Start Thresh", "%.2f", 0.05, true},
	{10, "Stop Thresh",  "%.2f", 0.05, true},
	{11, "Torque Zero",  "%.3f", 0.01, true},
	{12, "Torque Nm/V",  "%.1f", 1.0,  true},
}

M.now = 0

function M.menu_len()
	return #M.menu
end

-- Zero-based, as the lisp indexes it and as the page loops over it.
function M.row(i)
	return M.menu[i + 1]
end

-- What the controller last reported for a row, or nil until it has. seen is
-- what separates a reported zero from nothing reported.
function M.value(i)
	local id = M.row(i)[1]
	if state.conf_seen[id + 1] then
		return state.conf_vals[id + 1]
	end
	return nil
end

-- A gated row is only accepted by the controller while the kill switch holds
-- the motor, so the dash says so rather than letting the press be silently
-- refused.
function M.blocked(i)
	return M.row(i)[5] and not state.kill_sw_active
end

-- cmd 0 sets a value, as the controller's own handler reads it.
function M.send(cmd, id, val)
	local comms = require("lib.comms")
	comms.send(205, string.pack(">I1I1f", cmd, id, val))
end

return M
