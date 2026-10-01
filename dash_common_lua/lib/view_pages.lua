-- The swappable page area.
--
-- Ported from dash_common/views/view_pages.lbm, a page at a time. The grid
-- framework and the trip page are here; the rest follow.
--
-- Pages are drawn by a function taking one argument: true on a page switch,
-- which repaints everything and reallocates the buffers, and false for an
-- ordinary pass, which repaints only what changed. Each page keeps its own
-- last-state list for that.
--
-- page_x/y/w/h and row_h come from view_static, which owns the layout.

local state = require("lib.state")
local colors = require("lib.colors")
local units = require("lib.units")
local battery = require("lib.battery")
local du = require("lib.draw_utils")

local M = {}

M.font_24 = nil
M.font_16 = nil
M.font_40 = nil

-- Set from view_static's layout, so the two cannot drift.
function M.set_layout(L)
	M.L = L
	M.row_h = L.page_row_h
	M.rows = 8 // L.page_cols
	M.col_w = L.page_w // L.page_cols
	M.col_gap = 12
	-- Labels are right-aligned into their share of the column and values
	-- start a fixed gap later, so the two never run together.
	M.col_lbl_w = M.col_w * 5 // 8
	M.col_val_w = M.col_w - M.col_lbl_w - M.col_gap
end

-- Round to a multiple of x, e.g. round_x(1.23, 0.1) -> 1.2
--
-- The lisp's round is half away from zero, which matters here: these values
-- feed change detection, so rounding one way on one dash and the other way on
-- the other would make a field repaint at different times.
function M.round_x(val, x)
	local q = val / x
	local r
	if q < 0 then
		r = -math.floor(-q + 0.5)
	else
		r = math.floor(q + 0.5)
	end
	return r * x
end

-- Was a bitmap of a solid rectangle in the smaller dashes.
function M.page_clear()
	local L = M.L
	local strip = vesc.img_buffer("indexed2", L.page_w, 4)
	for i = 0, L.page_h // 4 - 1 do
		vesc.disp_render(strip, L.page_x, L.page_y + i * 4, {colors.bg, colors.bg})
	end
end

function M.grid_col_x(i)
	return M.L.page_x + (i // M.rows) * M.col_w
end

function M.grid_lbl_x(i)
	return M.grid_col_x(i)
end

function M.grid_val_x(i)
	return M.grid_col_x(i) + M.col_lbl_w + M.col_gap
end

function M.grid_y(i)
	return M.L.page_y + (i % M.rows) * M.row_h
end

-- Right-aligned into the buffer, which is what keeps a column of labels
-- lined up against its values.
function M.txt_right(buf, x, y, str, pal)
	local w_txt = M.font_24:measure(str)
	local w_img = buf:dims()
	buf:clear()
	buf:text(w_img - w_txt, 22, M.font_24, str, 1, true)
	vesc.disp_render(buf, x, y, pal or colors.text_aa)
end

function M.txt_left(buf, x, y, str, pal)
	buf:clear()
	buf:text(0, 22, M.font_24, str, 1, true)
	vesc.disp_render(buf, x, y, pal or colors.text_aa)
end

-- The eight static labels of a text page. Every text page supplies eight
-- cells, so the rows per column follow from the column count: a square panel
-- gets 2x4, a wide one 4x2, and no page has to know which.
function M.grid_labels(labels)
	local buf = vesc.img_buffer("indexed4", M.col_lbl_w, M.row_h)
	for i = 1, #labels do
		M.txt_right(buf, M.grid_lbl_x(i - 1), M.grid_y(i - 1), labels[i])
	end
end

function M.grid_values(update, strs, pal)
	local buf = M.resources.val_img
	for i = 1, #strs do
		if update[i] then
			M.txt_left(buf, M.grid_val_x(i - 1), M.grid_y(i - 1), strs[i], pal)
		end
	end
end

-- Buffers allocated for the visible page. Replaced on a page switch so the
-- previous page's buffers can be collected.
M.resources = {}

local function changed(old, new)
	local out = {}
	for i = 1, #new do
		out[i] = old[i] ~= new[i]
	end
	return out
end

local function all_true(n)
	local out = {}
	for i = 1, n do
		out[i] = true
	end
	return out
end

-- --- Trip page ---

function M.trip_state()
	return {
		-- Ride-average consumption, not the instantaneous figure: coasting
		-- drives the latter to zero and the range estimate to infinity.
		M.round_x(
			(state.km > 0.1 and state.wh > 0.5)
				and (state.battery_ah * battery.soc() * state.vin)
					/ (state.wh / state.km)
				or 0.0, 0.1),                          -- 1 Range
		M.round_x(state.km, 0.1),                      -- 2 Trip
		M.round_x(state.odom, 0.1),                    -- 3 ODO
		M.round_x(state.km > 0.1 and state.wh / state.km or 0, 0.1), -- 4 Efficiency
		M.round_x(state.wh, 0.1),                      -- 5 Energy
		M.round_x(state.wh_chg, 0.1),                  -- 6 Regen
		M.round_x(state.battery_ah, 0.1),              -- 7 Amp hours
		M.round_x(state.vin, 0.1),                     -- 8 Voltage
	}
end

M.trip_last = {}

function M.page_trip(switched)
	local curr = M.trip_state()
	local update = changed(M.trip_last, curr)

	if switched then
		update = all_true(#curr)
		M.resources = {
			val_img = vesc.img_buffer("indexed4", M.col_val_w, M.row_h),
		}
		M.page_clear()
		M.grid_labels({"Range", "Trip", "ODO", "Efficiency",
			"Energy", "Regen", "Amp Hours", "Voltage"})
	end

	-- Efficiency is divided rather than passed through units.dist because the
	-- figure is Wh per distance: the distance is in the denominator, so it
	-- scales the other way.
	local eff_div = units.speeds == "mph" and units.KM_TO_MI or 1.0

	M.grid_values(update, {
		string.format("%.1f", units.dist(curr[1])),
		string.format("%.1f", units.dist(curr[2])),
		string.format("%.0f", units.dist(curr[3])),
		string.format("%.0f", curr[4] / eff_div),
		string.format("%.0f", curr[5]),
		string.format("%.0f", curr[6]),
		string.format("%.1f", curr[7]),
		string.format("%.1f", curr[8]),
	})

	M.trip_last = curr
end

-- --- Session page: maxima and totals since the last reset ---

-- Which touch region resets the session, and how far through a hold it is.
-- Injected by the input layer; the defaults make a bench render work.
M.btn_actions_long = {}
M.btn_hold_region = nil
M.btn_hold_progress = 0.0
M.session_fade = 0.0

function M.secs_since(t)
	return vesc.secs_since(t)
end

-- btn_actions_long holds an action id per region; 12 is "reset the session
-- maxima". Whichever region is bound to it is the one whose hold fades this
-- page.
function M.session_reset_region()
	for i, a in ipairs(M.btn_actions_long) do
		if a == 12 then
			return i
		end
	end
	return nil
end

function M.session_state()
	local stats = require("lib.statistics")
	return {
		M.round_x(M.secs_since(state.session_start), 1),  -- 1 Time
		M.round_x(units.speed(state.kmh_max), 1),         -- 2 Speed max
		M.round_x(state.kw_max * 1000.0, 1),              -- 3 Power max
		M.round_x(state.amps_now_max, 0.1),               -- 4 Current max
		M.round_x(units.temp(state.temp_motor_max), 1),   -- 5 Motor temp max
		M.round_x(units.temp(state.temp_esc_max), 1),     -- 6 ESC temp max
		M.round_x(units.temp(state.temp_battery_max), 1), -- 7 Pack temp max
		M.round_x(state.duty, 0.01),                      -- 8 Duty
	}
end

M.session_last = {}

function M.page_session(switched)
	local stats = require("lib.statistics")
	local curr = M.session_state()
	local update = changed(M.session_last, curr)

	-- While the reset region is held, every value fades towards the
	-- background in step with the hold, and comes back if you let go.
	local rst = M.session_reset_region()
	local fade = 0.0
	if rst and M.btn_hold_region and M.btn_hold_region == rst then
		fade = M.btn_hold_progress
	end
	if fade ~= M.session_fade then
		M.session_fade = fade
		update = all_true(#curr)
	end

	if switched then
		update = all_true(#curr)
		M.resources = {
			val_img = vesc.img_buffer("indexed4", M.col_val_w, M.row_h),
		}
		M.page_clear()
		M.grid_labels({"Time", "Speed Max", "Power Max", "I Max",
			"T Mot Max", "T ESC Max", "T Pack Max", "Duty"})
	end

	M.grid_values(update, {
		stats.slot_time_str(curr[1]),
		string.format("%.0f", curr[2]),
		string.format("%.0f", curr[3]),
		string.format("%.0f", curr[4]),
		string.format("%.0f", curr[5]),
		string.format("%.0f", curr[6]),
		string.format("%.0f", curr[7]),
		string.format("%.0f", 100.0 * curr[8]),
	}, colors.fade_aa(M.session_fade))

	M.session_last = curr
end

-- --- Battery page ---
--
-- Everything here comes from the BMS over CAN rather than from the
-- controller.

function M.batt_state()
	return {
		M.round_x(vesc.bms_val("v_tot"), 0.1),
		M.round_x(vesc.bms_val("v_cell_min"), 0.01),
		M.round_x(vesc.bms_val("v_cell_max"), 0.01),
		vesc.bms_val("cell_num"),
		M.round_x(vesc.bms_val("i_in_ic"), 0.1),
		M.round_x(vesc.bms_val("ah_cnt"), 0.01),
		M.round_x(vesc.bms_val("temp_cell_max"), 1),
		M.round_x(vesc.bms_val("hum"), 1),
	}
end

M.batt_last = {}

function M.page_batt(switched)
	-- The BMS values all read zero with nothing connected, which is
	-- indistinguishable from a real reading, so say so outright.
	local curr
	if state.battery_a_connected then
		curr = M.batt_state()
	else
		curr = {0, 0, 0, 0, 0, 0, 0, 0}
	end

	local update = changed(M.batt_last, curr)

	if switched then
		update = all_true(#curr)
		M.resources = {
			val_img = vesc.img_buffer("indexed4", M.col_val_w, M.row_h),
		}
		M.page_clear()

		if not state.battery_a_connected then
			local buf = vesc.img_buffer("indexed4", M.L.page_w, 30)
			buf:clear()
			du.ttf_txt_center("No BMS on the bus", M.font_24, buf)
			vesc.disp_render(buf, M.L.page_x, M.L.page_y + 58, colors.dim_icon)
		else
			M.grid_labels({"Pack V", "Cell Min", "Cell Max", "Cells",
				"Current", "Ah Count", "T Cell Max", "Humidity"})
		end
	end

	if state.battery_a_connected then
		M.grid_values(update, {
			string.format("%.1f", curr[1]),
			string.format("%.2f", curr[2]),
			string.format("%.2f", curr[3]),
			string.format("%d", curr[4]),
			string.format("%.1f", curr[5]),
			string.format("%.2f", curr[6]),
			string.format("%.0f", curr[7]),
			string.format("%.0f", curr[8]),
		})
	end

	M.batt_last = curr
end

-- --- PAS page: what the rider contributes and what the motor adds ---

-- How many times the rider's own effort the motor is adding. Guarded because
-- rider power is near zero whenever the cranks are barely turning, which
-- would otherwise divide to something meaningless.
--
-- This is slot 29 of the lisp's slot-value table; the rest of that table
-- belongs with the live page and follows with it.
function M.assist_multiple()
	if state.pas_rider_w > 5 then
		return state.pas_assist_w / state.pas_rider_w
	end
	return 0.0
end

-- The flag bits app_pas_get_flags reports. Only the most significant is
-- shown, since there is one field for it, and the order here is worst first.
--
-- Kept to five characters. The grid sizes the value column for a number, and
-- on a four column panel anything longer is cut off mid-word: a demo render
-- of the speed limited state came out as "sp lim". The pas_status terminal
-- command spells each of these out in full.
function M.pas_status_str(flags)
	if not state.pas_rx then return "no rx" end
	if (flags & 0x10) ~= 0 then return "nopin" end
	if (flags & 0x02) ~= 0 then return "trqch" end
	if (flags & 0x04) ~= 0 then return "brkch" end
	if (flags & 0x20) ~= 0 then return "sens" end
	if (flags & 0x40) ~= 0 then return "notrq" end
	if (flags & 0x01) ~= 0 then return "clip" end
	if (flags & 0x200) ~= 0 then return "wlkch" end
	if (flags & 0x08) ~= 0 then return "brake" end
	if (flags & 0x100) ~= 0 then return "walk" end
	if (flags & 0x80) ~= 0 then return "splim" end
	return "ok"
end

-- Rounded so the page only redraws when a displayed digit changes, rather
-- than on every sample of a noisy torque signal.
function M.pas_state()
	return {
		M.round_x(state.pas_cadence, 1),          -- 1 Cadence
		M.round_x(state.pas_torque, 0.1),         -- 2 Crank torque
		M.round_x(state.pas_rider_w, 1),          -- 3 Rider power
		M.round_x(state.pas_assist_w, 1),         -- 4 Assist power
		M.round_x(M.assist_multiple(), 0.1),      -- 5 Assist multiple
		M.round_x(state.pas_output * 100.0, 1),   -- 6 Output
		M.round_x(units.speed(state.kmh), 1),     -- 7 Speed
		state.pas_flags,                          -- 8 Status
	}
end

M.pas_last = {}

function M.page_pas(switched)
	local curr = M.pas_state()
	local update = changed(M.pas_last, curr)

	if switched then
		update = all_true(#curr)
		M.resources = {
			val_img = vesc.img_buffer("indexed4", M.col_val_w, M.row_h),
		}
		M.page_clear()
		M.grid_labels({"Cadence", "Crank Trq", "Rider", "Assist",
			"Assist x", "Output", "Speed", "Status"})
	end

	M.grid_values(update, {
		string.format("%.0f", curr[1]),
		string.format("%.1f", curr[2]),
		string.format("%.0f", curr[3]),
		string.format("%.0f", curr[4]),
		string.format("%.1f", curr[5]),
		string.format("%.0f", curr[6]),
		string.format("%.0f", curr[7]),
		M.pas_status_str(curr[8]),
	})

	M.pas_last = curr
end

-- --- Live page: four configurable slots ---
--
-- The four slots follow the page grid rather than always being 2x2: a wide
-- panel lays them in one row, a square one in two. A 2x2 on the short page
-- area a wide panel leaves would overflow the nav strip. lib/geom.lua owns
-- that geometry and its inverse.

M.font_40 = nil

-- The slot configuration, injected by the settings layer so a render does not
-- need it.
M.slots = {0, 1, 2, 3}
M.slot_modes = {0, 0, 0, 0}
M.slot_mins = {0.0, 0.0, 0.0, 0.0}
M.slot_maxs = {100.0, 100.0, 100.0, 100.0}
M.smooth = 0.0

-- Where a hold is, from the input layer.
M.touch_x = 0
M.touch_y = 0

-- A slot is a number unless it is one of the timers, which read as a
-- duration. A timer is never smoothed: it only counts up, so there is nothing
-- to glide towards, and a smoothed clock would read the wrong time.
function M.slot_str(i)
	local stats = require("lib.statistics")
	local src = M.slots[i + 1]
	if stats.slot_is_time(src) then
		return stats.slot_time_str(stats.slot_value(src))
	end
	return string.format(stats.slot_fmt(src),
		stats.slot_shown(i, M.slots, M.smooth, M.slot_mins, M.slot_maxs))
end

function M.live_state()
	return {M.slot_str(0), M.slot_str(1), M.slot_str(2), M.slot_str(3)}
end

M.live_last = {}

-- (cell, progress) of the hold last drawn, so the cell redraws as it fills.
M.live_hold = {nil, 0.0}

-- How a live cell is coloured. Mode 0 is its own fixed colour; the rest are
-- rules over where the value sits in the cell's min..max range. Mode order is
-- stored in eeprom, so only append.
--
--   0 fixed     the slot colour
--   1 ramp      green, then amber from 0.6, then red from 0.85
--   2 heat      teal to red, continuous, from a prebuilt 16-step table
--   3 low-warn  the ramp read the other way: red at the bottom of the range,
--               which is what a state of charge or a pack voltage wants
--   4 sign      accent while positive, green while negative, so regen on
--               power or current reads at a glance
function M.slot_colors(i)
	local stats = require("lib.statistics")
	local mode = M.slot_modes[i + 1]

	if mode == 0 then
		return colors.slots[i + 1]
	end

	local lo = M.slot_mins[i + 1]
	local hi = M.slot_maxs[i + 1]

	-- The shown value, not the raw one, so the colour cannot disagree with
	-- the number beside it while it is gliding. slot_str runs first each
	-- frame, so this reads the step it already took rather than taking
	-- another.
	local v = stats.slot_smooth[i + 1]
	if v == nil or M.smooth <= 0.0 then
		v = stats.slot_value(M.slots[i + 1])
	end

	local f = (hi <= lo) and 0.0 or (v - lo) / (hi - lo)

	if mode == 2 then
		return colors.heat_ramp(f)
	end
	if mode == 3 then
		if f < 0.15 then return colors.crit_aa end
		if f < 0.4 then return colors.warn_aa end
		return colors.ok_aa
	end
	if mode == 4 then
		return v < 0.0 and colors.ok_aa or colors.accent_aa
	end
	if f > 0.85 then return colors.crit_aa end
	if f > 0.6 then return colors.warn_aa end
	return colors.ok_aa
end

function M.live_hold_cell()
	if not M.btn_hold_region then
		return nil
	end
	return M.live_geom.hit(M.touch_x, M.touch_y)
end

-- A held cell's value drifts from the text colour towards the accent colour
-- as the hold fills, which is the affordance for the long press that sends
-- that cell to the chart page. The session page fades towards the background
-- for the opposite reason: there the hold destroys the value.
function M.slot_hold_colors(f)
	return colors.make_aa(colors.bg,
		vesc.color_mix(colors.text, colors.accent, du.clamp01(f)), 4)
end

function M.page_live(switched)
	local stats = require("lib.statistics")
	local geom = require("lib.geom")
	local L = M.L

	M.live_geom = M.live_geom or geom.live(L.page_x, L.page_y, L.page_w,
		L.page_h, L.page_cols)
	local g = M.live_geom

	-- Entering the page snaps rather than gliding up from whatever was shown
	-- when it was last open, which could be minutes stale.
	if switched then
		stats.slot_smooth_reset()
	end

	local curr = M.live_state()
	local update = changed(M.live_last, curr)

	-- A ramped slot can change colour while its text does not.
	for i = 1, 4 do
		if M.slot_modes[i] == 1 then
			update[i] = true
		end
	end

	-- The held cell, and the one held a frame ago, both have to be redrawn
	-- even when their text has not changed: one takes the hold colour and the
	-- other has to lose it.
	local hold = M.live_hold_cell()
	local hold_f = hold and M.btn_hold_progress or 0.0
	if hold ~= M.live_hold[1] or hold_f ~= M.live_hold[2] then
		if M.live_hold[1] then
			update[M.live_hold[1] + 1] = true
		end
		if hold then
			update[hold + 1] = true
		end
		M.live_hold = {hold, hold_f}
	end

	if switched then
		update = all_true(#curr)
		M.resources = {
			val_img = vesc.img_buffer("indexed4", g.cell_w - 16, g.val_h),
		}
		M.page_clear()

		local lbl = vesc.img_buffer("indexed4", g.cell_w - 16, g.lbl_h)
		for i = 0, 3 do
			local src = M.slots[i + 1]
			lbl:clear()
			lbl:text(4, 18, M.font_16,
				stats.slot_label(src) .. "  " .. stats.slot_unit(src), 1, true)
			vesc.disp_render(lbl, g.cell_x(i), g.cell_y(i) + 2, colors.text_aa)
		end
	end

	local val = M.resources.val_img
	for i = 0, 3 do
		if update[i + 1] then
			val:clear()
			val:text(8, 36, M.font_40, curr[i + 1], 1, true)
			vesc.disp_render(val, g.cell_x(i), g.cell_y(i) + g.lbl_h + 2,
				(hold == i) and M.slot_hold_colors(hold_f) or M.slot_colors(i))
		end
	end

	M.live_last = curr
end

return M
