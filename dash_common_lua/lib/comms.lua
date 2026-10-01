-- Decoding the frames dash_esc and a bike-controls node put on the bus.
--
-- Ported from the receive half of dash_common/lib/communication.lisp. The
-- transmit thread and the event loop are not here yet; this is the part that
-- is pure enough to test, and the part where a width or endianness mistake
-- produces a plausible-looking wrong number rather than an error.
--
-- Endianness: big. The lisp calls bufget-i16 with no endian argument, and
-- LispBM's decode_get_args sets big-endian as the default -- the local
-- `bool be = false` a few lines above it is overwritten immediately, which is
-- a good way to read it backwards. So every format string here starts with
-- ">".
--
-- Frames carry fixed-point integers and this scales them back: a speed is
-- tenths, a duty is thousandths, a pitch is hundredths. The scale is part of
-- the protocol, so it is written at the unpack rather than hidden in a
-- helper.

local state = require("lib.state")
local mode = require("lib.mode")
local signals = require("lib.signals")

local M = {}

-- Frames seen, which the standalone thread watches to decide whether dash_esc
-- is alive at all.
M.rx_cnt = 0
M.dash_esc_last = 0

-- Set when a dedicated cruise frame (202) has been seen, after which the
-- cruise bit in frame 30 is ignored -- the node that sends 202 is the
-- authority and the bit in 30 is the older path.
M.cruise_new_msg_rx = false

-- True when a GNSS speed should replace the controller's. From the board
-- config in the lisp; here the dash sets it.
M.use_gnss_speed = false
M.gnss_speed = function() return 0.0 end

function M.now()
	return vesc.systime()
end

-- Unpack helpers, named for what the protocol calls them rather than for the
-- format string, so a frame layout reads like the table it comes from.
local function i16(d, off) return (string.unpack(">i2", d, off + 1)) end
local function u16(d, off) return (string.unpack(">I2", d, off + 1)) end
local function u32(d, off) return (string.unpack(">I4", d, off + 1)) end
local function u8(d, off)  return (string.unpack(">I1", d, off + 1)) end
local function f32(d, off) return (string.unpack(">f", d, off + 1)) end

-- Per-frame decoders, keyed by SID. A table rather than the lisp's cond
-- chain: the ids are sparse and the dispatch is then a lookup.
local frames = {}

frames[20] = function(d)
	-- The BMS figure wins when there is one, because it is measured at the
	-- pack rather than inferred at the controller.
	if not state.battery_a_connected and not state.battery_b_connected then
		state.battery_soc = i16(d, 0) / 1000.0
	end
	state.duty = i16(d, 2) / 1000.0

	if M.use_gnss_speed then
		state.kmh = M.gnss_speed()
	else
		state.kmh = i16(d, 4) / 10.0
	end

	state.kw = i16(d, 6) / 100.0
	state.updated = true
end

frames[21] = function(d)
	state.temp_battery = i16(d, 0) / 10.0
	state.temp_esc = i16(d, 2) / 10.0
	state.temp_motor = i16(d, 4) / 10.0
	state.angle_pitch = i16(d, 6) / 100.0
end

frames[22] = function(d)
	state.wh = u16(d, 0) / 10.0
	state.wh_chg = u16(d, 2) / 10.0
	state.km = u16(d, 4) / 10.0
	state.fault_code = u16(d, 6)
end

frames[23] = function(d)
	state.amps_avg = u16(d, 0)
	state.amps_max = u16(d, 2)
	state.amps_now = i16(d, 4)
	-- Amp hours from the BMS when there is one, for the same reason as soc.
	if not state.battery_a_connected then
		state.battery_ah = u16(d, 6)
	end
end

frames[24] = function(d)
	state.vin = u16(d, 0) / 10.0
	state.odom = u32(d, 2) / 10.0
	state.cruise_control_speed = u16(d, 6) / 10.0
end

frames[26] = function(d)
	state.pas_cadence = u16(d, 0) / 10.0
	state.pas_torque = u16(d, 2) / 10.0
	state.pas_rider_w = u16(d, 4)
	state.pas_assist_w = u16(d, 6)
	state.pas_rx = true
end

-- One controller setting per frame, cycled by the controller, so the menu
-- fills itself without asking for anything.
frames[27] = function(d)
	local i = u8(d, 0)
	if i < 16 then
		state.conf_vals[i + 1] = f32(d, 1)
		state.conf_gated[i + 1] = u8(d, 5)
		state.conf_seen[i + 1] = true
		state.conf_count = u8(d, 6)
	end
end

frames[30] = function(d)
	local l = u8(d, 0) == 1
	local r = u8(d, 1) == 1
	state.indicate_ms = u16(d, 2)
	state.highbeam_on = u8(d, 4) == 1

	if not M.cruise_new_msg_rx then
		state.cruise_control_active = u8(d, 5) == 1
	end

	-- When an indicator starts, so the view can animate from a known point
	-- rather than from whenever it happened to redraw.
	if (l and not state.indicate_l_on) or (r and not state.indicate_r_on) then
		state.indicator_timestamp = M.now()
	end

	state.indicate_l_on = l
	state.indicate_r_on = r

	-- A bike-controls node is on the bus and reporting, so the strip shows
	-- what the signals are doing rather than what this display asked for.
	signals.rx_last = M.now()
end

frames[31] = function(d)
	-- Inverted on the wire: 0 means down. Kept as the wire says rather than
	-- normalised, because the comment in the lisp is the only record of it.
	state.kickstand_down = u8(d, 0) == 0
end

frames[25] = function(d)
	local log_new = u8(d, 0) == 1
	if log_new ~= state.log_active then
		M.on_log_change(log_new)
	end
	state.log_active = log_new

	mode.follow(u8(d, 1))

	state.service_mode = u8(d, 2) == 1
	state.motor_bad = u8(d, 3) == 1

	-- Bytes 4 and 5 were spare. PAS status and output go here rather than in
	-- a frame of their own, since one byte each is all they need.
	state.pas_flags = u16(d, 4)
	state.pas_output = u8(d, 6) / 200.0

	-- Byte 7 carries conditions the display cannot derive.
	local st = u8(d, 7)
	state.kill_sw_active = (st & 1) ~= 0
	state.aux_on = (st & 2) ~= 0
	state.conf_dirty = (st & 4) ~= 0
	-- The controller is holding a lock of its own, reported so a display can
	-- say why the bike will not move even when it did not set the code.
	state.esc_pin_holding = (st & 8) ~= 0
end

frames[202] = function(d)
	state.cruise_control_active = u8(d, 0) == 1
	M.cruise_new_msg_rx = true
end

frames[203] = function(d)
	state.temp_ambient = i16(d, 0) / 10.0
	state.temp_ambient_rx = true
end

frames[204] = function(d)
	local out = {}
	for i = 1, #d do
		out[i] = string.byte(d, i)
	end
	state.date_time = out
	state.date_time_rx = true
end

-- Notified when the controller starts or stops logging, so the dash can say
-- so. Does nothing by default, which is what lets this be tested with no UI.
M.on_log_change = function(_) end

-- Handle one frame. data is a string of bytes, as a CAN payload is.
--
-- Returns true when the id was one of ours, which is also what separates a
-- frame that was ignored from one that was short -- a truncated frame raises
-- out of string.unpack, and the caller traps it rather than this swallowing
-- it into a silently wrong reading.
function M.proc_sid(id, data)
	-- Any of these means dash_esc is alive.
	if (id >= 20 and id <= 27) or id == 30 or id == 31 then
		M.dash_esc_last = M.now()
	end

	local fn = frames[id]
	if not fn then
		return false
	end

	fn(data)

	-- Only the dash_esc frames are counted, as in the lisp: rx_cnt is what
	-- the standalone thread uses to decide whether a controller is talking,
	-- and an ambient temperature or a clock frame from some other node would
	-- make a silent controller look alive.
	if (id >= 20 and id <= 27) or id == 30 or id == 31 then
		M.rx_cnt = M.rx_cnt + 1
	end

	return true
end

return M
