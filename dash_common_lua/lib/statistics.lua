-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Live values and the smoothing that makes them readable.
--
-- Ported from dash_common/lib/statistics.lisp. The state itself lives in
-- lib/state.lua; this module holds the arithmetic over it.

local state = require("lib.state")

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

--- live page sources ---
--
-- (label, unit) by index. Stored by index in the settings, so only append.
M.slot_catalog = {
	{"Speed", ""}, {"Battery", "%"}, {"Motor Amps", "A"}, {"Batt Amps", "A"},
	{"Power", "kW"}, {"Voltage", "V"}, {"Motor Temp", ""}, {"ESC Temp", ""},
	{"Pack Temp", ""}, {"Duty", "%"}, {"Trip", ""}, {"Odometer", ""},
	{"Energy", "Wh"}, {"Regen", "Wh"}, {"Amp Hours", "Ah"}, {"Peak Amps", "A"},
	{"Top Speed", ""}, {"Pitch", "deg"}, {"Min Pack", "V"}, {"Avg Speed", ""},
	{"Moving", ""}, {"Elapsed", ""}, {"SOC Volts", "%"}, {"SOC Count", "%"},
	{"SOC Model", "%"}, {"Cadence", "rpm"}, {"Crank Trq", "Nm"},
	{"Rider", "W"}, {"Assist", "W"}, {"Assist x", ""},
}

function M.now()
	return vesc.systime()
end

-- Both timers accumulate only when their interval closes, so a live reader
-- has to add the interval still in progress or the number sits still while
-- you ride.
--
-- The timers are kept in systime units and divided here, which is correct
-- only because systime is FreeRTOS ticks and CONFIG_FREERTOS_HZ is 1000 on
-- every board in the tree. The lisp makes the same assumption; it is written
-- down here because nothing enforces it.
function M.moving_secs()
	local extra = state.active_timestamp
		and (M.now() - state.active_timestamp) or 0
	return (state.active_timer + extra) / 1000.0
end

function M.elapsed_secs()
	local extra = state.elapsed_timestamp
		and (M.now() - state.elapsed_timestamp) or 0
	return (state.elapsed_timer + extra) / 1000.0
end

-- Over moving time, not elapsed: an average that counts time at the lights
-- tells you about the lights.
function M.avg_kmh()
	local t = M.moving_secs()
	if t > 1.0 then
		return state.km / (t / 3600.0)
	end
	return 0.0
end

-- What each slot index reads. The index is stored in the settings, so the
-- order is fixed: only append.
function M.slot_value(i)
	local units = require("lib.units")
	local battery = require("lib.battery")

	if i == 0 then return units.speed(state.kmh) end
	if i == 1 then return 100.0 * state.battery_soc end
	if i == 2 then return state.amps_now end
	if i == 3 then
		-- Battery amps from power and pack voltage, guarded because a pack
		-- voltage of zero is what an unseen controller reads as.
		if state.vin == 0 then return 0.0 end
		return state.kw * 1000.0 / state.vin
	end
	if i == 4 then return state.kw end
	if i == 5 then return state.vin end
	if i == 6 then return units.temp(state.temp_motor) end
	if i == 7 then return units.temp(state.temp_esc) end
	if i == 8 then return units.temp(state.temp_battery) end
	if i == 9 then return state.duty * 100.0 end
	if i == 10 then return units.dist(state.km) end
	if i == 11 then return units.dist(state.odom) end
	if i == 12 then return state.wh end
	if i == 13 then return state.wh_chg end
	if i == 14 then return state.battery_ah end
	if i == 15 then return state.amps_max end
	if i == 16 then return units.speed(state.kmh_max) end
	if i == 17 then return state.angle_pitch end
	if i == 18 then return state.vin_min or 0.0 end
	if i == 19 then return units.speed(M.avg_kmh()) end
	if i == 20 then return M.moving_secs() end
	if i == 21 then return M.elapsed_secs() end
	-- The three state-of-charge estimates, so they can be compared before
	-- config.soc_source is pointed at one of them.
	if i == 22 then return 100.0 * battery.voltage_soc(state.vin) end
	if i == 23 then return 100.0 * battery.coulomb_soc(state.battery_ah) end
	if i == 24 then return 100.0 * battery.model_soc() end
	if i == 25 then return state.pas_cadence end
	if i == 26 then return state.pas_torque end
	if i == 27 then return state.pas_rider_w end
	if i == 28 then return state.pas_assist_w end
	-- How many times the rider's own effort the motor is adding. Guarded
	-- because rider power is near zero whenever the cranks are barely
	-- turning, which would otherwise divide to something meaningless.
	if i == 29 then
		if state.pas_rider_w > 5 then
			return state.pas_assist_w / state.pas_rider_w
		end
		return 0.0
	end
	return 0.0
end

-- Units that follow the unit setting rather than being fixed.
function M.slot_unit(i)
	local units = require("lib.units")
	if i == 0 or i == 16 or i == 19 then return units.speed_str() end
	if i == 6 or i == 7 or i == 8 then return units.temp_str() end
	if i == 10 or i == 11 then return units.dist_str() end
	return M.slot_catalog[i + 1][2]
end

function M.slot_label(i)
	return M.slot_catalog[i + 1][1]
end

-- One decimal for the small numbers, none for the ones that get large.
local SLOT_FMT_0 = {[1]=true, [5]=true, [9]=true, [12]=true, [13]=true,
	[15]=true, [2]=true, [3]=true, [6]=true, [7]=true, [8]=true,
	[22]=true, [23]=true, [24]=true}

function M.slot_fmt(i)
	return SLOT_FMT_0[i] and "%.0f" or "%.1f"
end

-- The two timers are drawn as h:mm:ss rather than a number of seconds.
function M.slot_is_time(i)
	return i == 20 or i == 21
end

-- Smoothed value per live cell, nil until the cell has been drawn once.
M.slot_smooth = {nil, nil, nil, nil}

function M.slot_smooth_reset()
	M.slot_smooth = {nil, nil, nil, nil}
end

-- What cell i should display: the real value with smoothing off, the glided
-- one with it on. Both the number and its colour go through here, so a rule
-- cannot disagree with the number it is colouring.
--
-- settings is passed in rather than read from a global so this can be
-- rendered without the settings layer.
function M.slot_shown(i, slots, smooth, mins, maxs)
	local v = M.slot_value(slots[i + 1])
	if smooth <= 0.0 then
		return v
	end
	local n = M.smooth_step(M.slot_smooth[i + 1], v, smooth,
		mins[i + 1], maxs[i + 1])
	M.slot_smooth[i + 1] = n
	return n
end

-- Elapsed time as m:ss under an hour and h:mm over it, which is what fits a
-- grid cell. The lisp relies on integer division truncating; Lua's // floors,
-- and these are never negative, so the two agree.
function M.slot_time_str(secs)
	local s = math.floor(secs)
	if s < 3600 then
		return string.format("%d:%02d", s // 60, s % 60)
	end
	return string.format("%d:%02d", s // 3600, (s // 60) % 60)
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

--- the sampler ---
--
-- The lisp runs this as its own 20 Hz thread and pushes a chart sample every
-- other tick, which is 10 Hz because that is the rate the controller sends
-- at: sampling faster would only duplicate values and make the window
-- shorter than the setting says.
--
-- The Lua engine has one timer, so the base rate here is the input layer's
-- 50 Hz and chart_div is what brings the chart back to 10 Hz. The divisor is
-- the thing to change if the base rate moves; the comment above chart_max
-- about ten seconds depends on it.
M.chart_div = 5

-- A reset is a request rather than an action, applied at the top of the next
-- tick. The lisp needs that because the action fires on a different thread
-- from the one owning these values; here it buys something smaller but real,
-- which is that a reset cannot land between the maxima and the timers and
-- clear half a session.
M.reset_now = false

function M.reset_max()
	M.reset_now = true
end

local function apply_reset()
	state.kmh_max = 0.0
	state.kw_max = 0.0
	state.temp_battery_max = 0.0
	state.temp_esc_max = 0.0
	state.temp_motor_max = 0.0
	state.amps_now_max = 0.0
	state.amps_now_min = 0.0
	state.vin_min = nil
	state.active_timer = 0
	state.active_timestamp = nil
	state.elapsed_timer = 0
	state.elapsed_timestamp = nil
	M.reset_now = false
end

-- One pass: fold the live values into the session maxima, then advance the
-- timers.
--
-- chart_src is the slot index the chart is set to, from the settings. Passed
-- in rather than read, because this module is below the settings and the
-- render tests drive it without them.
--
-- Idempotent except for the chart push and the timers, which is what lets it
-- run at the input rate rather than needing its own.
function M.tick(chart_src)
	if M.reset_now then
		apply_reset()
	end

	M.chart_tick = M.chart_tick + 1
	if M.chart_tick % M.chart_div == 0 then
		M.chart_push(M.slot_value(chart_src))
	end

	if state.kmh > state.kmh_max then state.kmh_max = state.kmh end
	if state.kw > state.kw_max then state.kw_max = state.kw end
	if state.temp_battery > state.temp_battery_max then
		state.temp_battery_max = state.temp_battery
	end
	if state.temp_esc > state.temp_esc_max then
		state.temp_esc_max = state.temp_esc
	end
	if state.temp_motor > state.temp_motor_max then
		state.temp_motor_max = state.temp_motor
	end

	-- Motor current both ways: the maximum is how hard it was driven, the
	-- minimum how hard it was braked.
	if state.amps_now > state.amps_now_max then
		state.amps_now_max = state.amps_now
	end
	if state.amps_now < state.amps_now_min then
		state.amps_now_min = state.amps_now
	end

	-- Fault codes, first appearance kept. Zero is "no fault", not a code.
	if state.fault_code > 0 then
		local seen = false
		for _, c in ipairs(state.fault_codes_observed) do
			if c == state.fault_code then
				seen = true
				break
			end
		end
		if not seen then
			state.fault_codes_observed[#state.fault_codes_observed + 1] =
				state.fault_code
		end
	end

	-- Lowest pack voltage. Zero is ignored: it is what the field reads
	-- before the first frame arrives, and a minimum of zero would stick
	-- for the rest of the session.
	if state.vin > 0.0 then
		if not state.vin_min or state.vin < state.vin_min then
			state.vin_min = state.vin
		end
	end

	-- Elapsed runs from the first tick onward, moving or not.
	if not state.elapsed_timestamp then
		state.elapsed_timestamp = M.now()
	end

	-- Moving accumulates only while there is speed, and only when the
	-- interval closes -- which is why moving_secs adds the open one.
	if state.kmh > 0.0 and not state.active_timestamp then
		state.active_timestamp = M.now()
	elseif state.kmh == 0.0 and state.active_timestamp then
		state.active_timer =
			state.active_timer + (M.now() - state.active_timestamp)
		state.active_timestamp = nil
	end
end

return M
