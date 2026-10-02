-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- What this display is asking for on the bike's own outputs, as a bitfield in
-- byte 3 of SID 201.
--
-- Ported from the signal section of dash_common/lib/vehicle-state.lisp.
--
-- Nothing in the VESC ecosystem drives these today: a controller has exactly
-- two script-drivable outputs, set-aux ports 1 and 2, and dash_esc uses those
-- for the lights. This is for a second node on the bus that owns the switch
-- gear and has GPIO to spare -- an rmcore, whose shipped demo already reads
-- the light bit out of the same frame.
--
-- So the frame goes out whether or not anything listens, which costs one byte
-- of a frame already being sent every 100 ms, and the requests do nothing
-- until something acts on them.
--
-- Not persisted. An indicator that came back on after a power cycle would be
-- both surprising and, on a road bike, worse than that.

local state = require("lib.state")

local M = {}

M.HAZARD = 1
M.LEFT = 2
M.RIGHT = 4
M.BEAM = 8
M.HORN = 16

M.req = 0

-- The horn is momentary, and a tap cannot hold anything. A press on the quick
-- shade blips it for this long; a held button asserts it for as long as it is
-- held, which is what the request byte carries either way.
M.horn_blip_s = 0.6

-- Timestamps of the last blip, and of the last SID 30 -- the frame a
-- bike-controls node sends to report what the signals are actually doing.
-- Zero is simply long ago.
M.horn_ts = 0
M.rx_last = 0
M.rx_timeout = 2.0

-- The clock, as two functions rather than calls to vesc.* inline, so the
-- tests can advance time instead of sleeping for it. The lisp test sleeps
-- 0.7 s to watch a blip expire; this one sets a number.
--
-- Measured with secs_since rather than against a deadline, so nothing here
-- assumes what a systime tick is worth.
function M.now()
	return vesc.systime()
end

function M.secs_since(t)
	return vesc.secs_since(t)
end

-- While a report is recent the reported state is what gets displayed and the
-- request is only a request. With no such node on the bus the display falls
-- back to showing what it asked for, which is the only feedback there is.
function M.reported()
	return M.secs_since(M.rx_last) < M.rx_timeout
end

function M.on(bit)
	return (M.req & bit) ~= 0
end

-- Hazard outranks the indicators, and the two indicators cancel each other:
-- asking for both is the hazard, and a bike that lit one while the other was
-- on would be lying about which way it was going.
function M.toggle(bit)
	if M.on(bit) then
		M.req = M.req & ~bit & 0xFF
		return
	end

	if bit == M.LEFT then
		M.req = M.req & ~M.RIGHT & 0xFF
	elseif bit == M.RIGHT then
		M.req = M.req & ~M.LEFT & 0xFF
	end

	M.req = M.req | bit
end

function M.horn_blip()
	M.horn_ts = M.now()
end

function M.horn_blipping()
	return M.secs_since(M.horn_ts) < M.horn_blip_s
end

-- The byte on the wire. The horn is the one bit that is not latched: it is
-- set while a bound button is held or a blip is still running.
function M.byte(held)
	local v = M.req & ~M.HORN & 0xFF

	if held or M.horn_blipping() then
		v = v | M.HORN
	end

	return v
end

-- What the status strip should show: the reported state when a bike-controls
-- node is on the bus, otherwise what this display asked for -- so the
-- indicators mean something on a bike where the display is the only thing
-- asking. Hazard lights both sides, which is what hazard is.
function M.l_shown()
	if M.reported() then
		return state.indicate_l_on
	end
	return M.on(M.LEFT) or M.on(M.HAZARD)
end

function M.r_shown()
	if M.reported() then
		return state.indicate_r_on
	end
	return M.on(M.RIGHT) or M.on(M.HAZARD)
end

function M.beam_shown()
	if M.reported() then
		return state.highbeam_on
	end
	return M.on(M.BEAM)
end

return M
