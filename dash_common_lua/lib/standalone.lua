-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Reading the controller directly, without dash_esc.
--
-- Ported from dash_common/lib/standalone.lisp.
--
-- The stock CAN status frames carry speed, duty, voltage, current and temps.
-- They do not carry Wh, Ah, the odometer or fault codes, so a dash in this
-- mode shows fewer fields rather than wrong ones -- which is why the views ask
-- whether it is active.
--
-- Every canget here returns nil when no status frame of that kind has
-- arrived, where the lisp returns 0.0. That difference matters: nil in
-- arithmetic is an error, so each read is defaulted. The lisp got the zero
-- for free and so never had to think about it.

local state = require("lib.state")
local settings = require("lib.settings")

local M = {}

M.active = false
M.esc_id = -1

-- How long dash_esc has to be silent before this takes over. The controller
-- side sends at 10 Hz, so three seconds is thirty missed frames.
M.timeout = 3.0

-- Set by the board: a P4 with GNSS can take speed from it instead of from the
-- controller's own estimate.
M.use_gnss_speed = false
M.gnss_speed = function() return 0.0 end

function M.secs_since(t)
	return vesc.secs_since(t)
end

local function num(v)
	return v or 0.0
end

-- Which controller to read. The setting names one; 0 means take the lowest
-- recently seen id, so a single-controller bike needs no configuration and a
-- two-controller one is deterministic about which it believes.
function M.pick_esc()
	local want = settings.values.esc_id
	if want > 0 then
		return want
	end

	local devs = vesc.can_list_devs()
	if not devs or #devs == 0 then
		return -1
	end

	local best = -1
	for _, d in ipairs(devs) do
		local age = vesc.can_msg_age(d, 1)
		if age and age < 2.0 and (best < 0 or d < best) then
			best = d
		end
	end

	return best
end

-- 0 auto, 1 force dash_esc, 2 force standalone.
function M.should_run()
	local m = settings.values.esc_mode
	if m == 1 then
		return false
	end
	if m == 2 then
		return true
	end

	local comms = require("lib.comms")
	return M.secs_since(comms.dash_esc_last) > M.timeout
end

function M.sample(id)
	if M.use_gnss_speed then
		state.kmh = M.gnss_speed()
	else
		state.kmh = math.abs(num(vesc.canget_speed(id))) * 3.6
	end

	state.duty = num(vesc.canget_duty(id))
	state.vin = num(vesc.canget_vin(id))
	state.temp_esc = num(vesc.canget_temp_fet(id))
	state.temp_motor = num(vesc.canget_temp_motor(id))

	local i_in = num(vesc.canget_current_in(id))
	state.amps_now = i_in
	state.kw = i_in * state.vin / 1000.0

	-- Since the controller booted, not an odometer: status msg 5 carries a
	-- tacho value, and nothing on the bus remembers across a power cycle.
	state.km = num(vesc.canget_dist(id)) / 1000.0

	-- A BMS behind this firmware, if there is one. Without it the pack fields
	-- keep whatever the battery model works out from voltage.
	if num(vesc.bms_val("cell_num")) > 0 then
		state.battery_soc = num(vesc.bms_val("soc"))
		state.battery_ah = num(vesc.bms_val("ah_cnt"))
		if num(vesc.bms_val("temp_adc_num")) > 2 then
			local temps = vesc.bms_temps()
			if temps and temps[3] then
				state.temp_battery = temps[3]
			end
		end
	end

	state.updated = true
end

-- One pass. The lisp runs it at 10 Hz in its own thread.
function M.step()
	local want = M.should_run()

	if want ~= M.active then
		M.active = want
		-- The field set changes, which per-field comparison cannot see: the
		-- numbers that stop arriving keep their last value rather than
		-- changing.
		state.view_force_static = true
		state.view_force_pages = true
		print(want and "dash_esc not seen, reading CAN status frames directly"
			or "dash_esc present")
	end

	if M.active then
		M.esc_id = M.pick_esc()
		if M.esc_id >= 0 then
			M.sample(M.esc_id)
		end
	end
end

return M
