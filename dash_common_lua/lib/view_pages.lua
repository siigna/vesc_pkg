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

	-- The live cell grid, and the quick shade's. Built here rather than
	-- lazily inside the page that draws them, because the action layer hit
	-- tests against both and a long press can land before either page has
	-- been drawn once.
	local geom = require("lib.geom")
	M.live_geom = geom.live(L.page_x, L.page_y, L.page_w, L.page_h,
		L.page_cols)
	M.shade_geom = geom.shade(L.disp_w, L.nav_y)
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

-- --- Cells page: one bar per cell ---
--
-- The battery page shows aggregates, which cannot show a weak cell: a pack
-- with one cell 0.3 V down reads as a slightly low minimum and nothing else.
-- This draws every cell, so the odd one out is visible at a glance.
--
-- bms_val takes a cell index for v_cell and bal_state and errors outside
-- 0..cell_num, so the count is read first and trusted for the bounds.

M.cells_max = 24

function M.cells_count()
	if not state.battery_a_connected then
		return 0
	end
	local n = vesc.bms_val("cell_num")
	if n < 0 then return 0 end
	if n > M.cells_max then return M.cells_max end
	return n
end

-- A read can fail on a pack that reports a count it cannot then produce cells
-- for, which would take the page down rather than showing the rest.
function M.cell_v(i)
	local ok, v = pcall(vesc.bms_val, "v_cell", i)
	return ok and v or 0.0
end

function M.cell_balancing(i)
	local ok, v = pcall(vesc.bms_val, "bal_state", i)
	return ok and v or false
end

function M.cells_state()
	local n = M.cells_count()
	local lo, hi, sum = 9.9, 0.0, 0.0

	for i = 0, n - 1 do
		local v = M.cell_v(i)
		if v < lo then lo = v end
		if v > hi then hi = v end
		sum = sum + v
	end

	-- Rounded to 10 mV: the readings jitter in the last digit, and an
	-- unrounded state would redraw the whole page every frame.
	return {
		n,
		M.round_x(lo, 0.01),
		M.round_x(hi, 0.01),
		M.round_x(n > 0 and sum / n or 0.0, 0.01),
	}
end

M.cells_last = {}

local function same(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

function M.page_cells(switched)
	local L = M.L
	local cells_h = L.page_h - 2 - M.row_h
	local curr = M.cells_state()

	if switched then
		M.resources = {
			cells_img = vesc.img_buffer("indexed4", L.page_w, cells_h),
			cells_txt = vesc.img_buffer("indexed4", L.page_w, M.row_h),
		}
		M.page_clear()
	end

	if switched or not same(curr, M.cells_last) then
		local n = curr[1]
		local img = M.resources.cells_img
		img:clear()

		if n == 0 then
			du.ttf_txt_center("No BMS on the bus", M.font_24, img)
		else
			-- Scaled to the spread in the pack rather than to an absolute
			-- range: the whole point is the difference between cells, and on a
			-- healthy pack that is tens of millivolts, which an absolute 2.5
			-- to 4.2 V scale would render as 24 identical bars. A 20 mV floor
			-- keeps a balanced pack from magnifying noise into a skyline.
			local lo, hi = curr[2], curr[3]
			local span = (hi - lo) > 0.02 and (hi - lo) or 0.02
			local bw = L.page_w // n
			local pad = bw > 6 and 2 or 1

			for i = 0, n - 1 do
				local v = M.cell_v(i)
				local f = (v - lo) / span
				local h = 3 + math.floor(f * (cells_h - 6))
				local x = i * bw + pad
				local w = bw - 2 * pad

				-- A cell at the bottom of the spread has almost no bar left,
				-- which is the reading that matters most and the hardest to
				-- see. So the lowest cell and any balancing cell also get a
				-- full-height outline: the column stays visible whatever its
				-- level is.
				local mark = (v <= lo) or M.cell_balancing(i)
				if mark then
					img:rectangle(x, 0, w, cells_h, 1, false)
				end
				img:rectangle(x, cells_h - h, w, h, mark and 3 or 2, true)
			end
		end

		vesc.disp_render(img, L.page_x, L.page_y, colors.text_aa)

		local txt = M.resources.cells_txt
		txt:clear()
		local _, gh = M.font_16:glyph_dims("D")
		local by = gh + (M.row_h - gh) // 2

		txt:text(4, by, M.font_16, string.format("%dS  min %.2f  avg %.2f",
			n, curr[2], curr[4]), 1, true)

		local spread = string.format("spread %.0f mV", 1000.0 * (curr[3] - curr[2]))
		local iw = M.font_16:measure(spread)
		txt:text(L.page_w - iw - 4, by, M.font_16, spread, 1, true)

		vesc.disp_render(txt, L.page_x, L.page_y + cells_h + 2, colors.text_aa)
	end

	M.cells_last = curr
end

-- --- Chart page: a rolling window of one live value ---

-- Which slot is charted and how wide the window is. Injected by the settings
-- layer.
M.chart_src = 4
M.chart_secs = 10

-- The trace, autoscaled to what is in the window.
--
-- Returns the bounds, or nil with fewer than two samples -- which is every
-- frame of this page after a boot or a session reset, before the ring has
-- filled. The lisp needed defunret for that early exit and threw
-- variable_not_bound without it; in Lua it is an ordinary return, but the
-- case is just as live.
--
-- A flat line is centred rather than filling the height, which is what
-- dividing by a zero range would do.
function M.chart_draw(img, w, h, n)
	local stats = require("lib.statistics")

	if n < 2 then
		return nil
	end

	local lo = stats.chart_at(0)
	local hi = lo
	for i = 0, n - 1 do
		local v = stats.chart_at(i)
		if v < lo then lo = v end
		if v > hi then hi = v end
	end

	local span = hi - lo
	local flat = span < 0.0001

	-- Oldest on the left, newest on the right.
	local x_pre, y_pre = 0, 0
	for i = 0, n - 1 do
		local v = stats.chart_at(n - 1 - i)
		local f = flat and 0.5 or du.map_range_01(v, lo, hi)
		local x = i * (w - 1) // (n - 1)
		local y = h - 2 - math.floor(f * (h - 4))
		if i > 0 then
			img:line(x_pre, y_pre, x, y, 1, 2)
		end
		x_pre, y_pre = x, y
	end

	return {lo, hi}
end

function M.page_chart(switched)
	local stats = require("lib.statistics")
	local L = M.L
	local chart_h = L.page_h - 2 - M.row_h

	if switched then
		M.resources = {
			chart_img = vesc.img_buffer("indexed2", L.page_w, chart_h),
			chart_txt = vesc.img_buffer("indexed4", L.page_w, M.row_h),
		}
		M.page_clear()
	end

	local n = stats.chart_window(M.chart_secs)
	local img = M.resources.chart_img
	img:clear()
	local bounds = M.chart_draw(img, L.page_w, chart_h, n)
	vesc.disp_render(img, L.page_x, L.page_y, {colors.bg, colors.accent})

	-- Source, window, and what the trace spans. The newest sample is the
	-- right hand edge, so it is the same number a live cell would show.
	local txt = M.resources.chart_txt
	txt:clear()
	local unit = stats.slot_unit(M.chart_src)

	-- text takes a baseline, not a top edge, so a y of zero draws the line
	-- entirely above the buffer and nothing appears. Centred from the glyph
	-- height, so it holds for whatever row height a board profile uses.
	local _, gh = M.font_16:glyph_dims("D")
	local by = gh + (M.row_h - gh) // 2

	txt:text(4, by, M.font_16,
		stats.slot_label(M.chart_src) .. string.format("  %d s", M.chart_secs),
		1, true)

	local info = bounds
		and string.format("%.1f to %.1f %s", bounds[1], bounds[2], unit)
		or "collecting"
	local iw = M.font_16:measure(info)
	txt:text(L.page_w - iw - 4, by, M.font_16, info, 1, true)

	vesc.disp_render(txt, L.page_x, L.page_y + chart_h + 2, colors.text_aa)
end

-- --- Settings and controller settings pages ---
--
-- Both are a scrolling list of label and value with one row selected. The
-- list is taller than the page, so which rows are on screen depends on the
-- selection -- which means a selection move has to redraw the labels too,
-- not only the values.

M.rows_visible = nil
M.settings_first_row_last = -1
M.conf_first_row_last = -1

-- The display settings list, injected by the settings layer: names, labels
-- and formats as lib/settings.build returns them, plus which row is selected.
M.setting_list = {}
M.setting_labels = {}
M.setting_fmts = {}
M.setting_now = 0

-- Which row is at the top, given the selection. Keeps the selection roughly
-- centred without scrolling past either end.
local function first_row(rows, now, visible)
	if rows <= visible then
		return 0
	end
	local half = visible // 2
	if now < half then
		return 0
	end
	if now >= rows - half then
		return rows - visible
	end
	return now - half
end

function M.page_settings(switched)
	local settings = require("lib.settings")
	local L = M.L
	local visible = L.page_h // M.row_h
	local rows = #M.setting_list

	local curr = {}
	for i = 1, rows do
		curr[i] = settings.read(M.setting_list[i])
	end
	curr[rows + 1] = M.setting_now

	local update = changed(M.settings_last or {}, curr)
	local first = first_row(rows, M.setting_now, visible)

	if switched or first ~= M.settings_first_row_last then
		update = all_true(#curr)
		M.settings_first_row_last = first

		M.resources = {
			val_img = vesc.img_buffer("indexed4", L.page_w - 224, M.row_h),
		}
		M.page_clear()

		local lbl = vesc.img_buffer("indexed4", 210, M.row_h)
		for i = 0, math.min(visible, rows) - 1 do
			M.txt_right(lbl, L.page_x + 4, L.page_y + i * M.row_h,
				M.setting_labels[first + i + 1])
		end
	end

	local val = M.resources.val_img
	for i = 0, math.min(visible, rows) - 1 do
		local r = first + i + 1
		if update[r] or update[rows + 1] then
			M.txt_left(val, L.page_x + 224, L.page_y + i * M.row_h,
				string.format(M.setting_fmts[r], curr[r]),
				(curr[rows + 1] == r - 1) and colors.text_sel_aa or colors.text_aa)
		end
	end

	M.settings_last = curr
end

-- Same shape, but the values live on the controller: they are mirrored in
-- over CAN and changed by sending a frame back, so a row reads "--" until the
-- controller has reported it.
function M.page_conf(switched)
	local cc = require("lib.controller_conf")
	local L = M.L
	local visible = L.page_h // M.row_h
	local rows = cc.menu_len()

	local curr = {}
	for i = 0, rows - 1 do
		local v = cc.value(i)
		curr[i + 1] = (v == nil) and "--" or string.format(cc.row(i)[3], v)
	end
	curr[rows + 1] = cc.now
	curr[rows + 2] = state.conf_dirty
	curr[rows + 3] = state.kill_sw_active

	local update = changed(M.conf_last or {}, curr)
	local first = first_row(rows, cc.now, visible)

	-- The labels move when the list scrolls, and a gated row changes
	-- appearance when the kill switch does, so both force a full redraw.
	if switched or first ~= M.conf_first_row_last or update[rows + 3] then
		update = all_true(#curr)
		M.conf_first_row_last = first

		M.resources = {
			val_img = vesc.img_buffer("indexed4", L.page_w - 224, M.row_h),
		}
		M.page_clear()

		local lbl = vesc.img_buffer("indexed4", 210, M.row_h)
		for i = 0, math.min(visible, rows) - 1 do
			local r = first + i
			-- A gated row the kill switch is not holding is shown dim and
			-- marked, so it is clear before pressing that the press would be
			-- refused rather than after.
			M.txt_right(lbl, L.page_x + 4, L.page_y + i * M.row_h,
				cc.row(r)[2] .. (cc.blocked(r) and " *" or ""))
		end
	end

	local val = M.resources.val_img
	for i = 0, math.min(visible, rows) - 1 do
		local r = first + i
		if update[r + 1] or update[rows + 1] then
			local pal
			if cc.blocked(r) then
				pal = colors.fade_aa(0.45)
			elseif curr[rows + 1] == r then
				pal = colors.text_sel_aa
			else
				pal = colors.text_aa
			end
			M.txt_left(val, L.page_x + 224, L.page_y + i * M.row_h,
				curr[r + 1], pal)
		end
	end

	M.conf_last = curr
end

-- --- Quick shade ---
--
-- Six buttons over the whole panel above the nav strip, reachable from any
-- page by swiping down and closed by swiping up. Each cell runs one button
-- action id, so anything bindable to a button can be put here.
--
-- That is the point of it on a touch board: four regions with one short and
-- one long action each is the whole of the input, and paging and the settings
-- page already take three of the short ones. Without this a rider can reach
-- exactly one control.

-- Which action each cell runs, from the settings.
M.shade_slots = {4, 5, 6, 8, 9, 14}

-- Action 0 is an empty cell. Walk assist is deliberately absent: it is a held
-- action, and a tap cannot hold anything, so it stays on a physical region
-- where the hold indicator can fill.
local SHADE_LABELS = {
	[1] = "PAGE >", [2] = "PAGE <", [3] = "SETTINGS",
	[4] = "MODE +", [5] = "MODE -", [6] = "LIGHTS",
	[7] = "DIM", [8] = "CRUISE", [9] = "LOG",
	[12] = "RESET", [14] = "SAVE", [15] = "REVERT",
	[16] = "CLOSE",
	[17] = "HAZARD", [18] = "LEFT", [19] = "RIGHT",
	[20] = "BEAM", [21] = "HORN",
}

function M.shade_label(a)
	return SHADE_LABELS[a] or ""
end

-- The line under the label: what the control is currently doing, where that
-- is known. Logging has no feedback channel, so it says nothing rather than
-- claiming a state it cannot see.
function M.shade_state(a)
	local mode = require("lib.mode")
	local signals = require("lib.signals")

	if a == 4 or a == 5 then
		return M.drive_mode_names[mode.current + 1] or ""
	end
	if a == 6 then return state.light_on and "on" or "off" end
	if a == 8 then return state.cruise_control_active and "on" or "off" end
	if a == 14 or a == 15 then return state.conf_dirty and "unsaved" or "saved" end
	if a == 12 then return "session" end
	-- The request, not the reported state: this says what the button did, and
	-- the status strip is where what the bike is doing belongs.
	if a == 17 then return signals.on(signals.HAZARD) and "on" or "off" end
	if a == 18 then return signals.on(signals.LEFT) and "on" or "off" end
	if a == 19 then return signals.on(signals.RIGHT) and "on" or "off" end
	if a == 20 then return signals.on(signals.BEAM) and "high" or "low" end
	if a == 21 then return "press" end
	return ""
end

-- Lit when the control is on, so the grid reads at a glance.
function M.shade_active(a)
	local signals = require("lib.signals")

	if a == 6 then return state.light_on end
	if a == 8 then return state.cruise_control_active end
	if a == 14 or a == 15 then return state.conf_dirty end
	if a == 17 then return signals.on(signals.HAZARD) end
	if a == 18 then return signals.on(signals.LEFT) end
	if a == 19 then return signals.on(signals.RIGHT) end
	if a == 20 then return signals.on(signals.BEAM) end
	if a == 21 then return signals.horn_blipping() end
	return false
end

M.drive_mode_names = {"REVERSE", "NEUTRAL", "ECO", "NORMAL", "SPORT"}

-- An overlay covers the whole panel above the nav strip, which page_clear
-- does not, so it clears more.
function M.overlay_clear()
	local L = M.L
	local strip = vesc.img_buffer("indexed2", L.disp_w, 4)
	for i = 0, L.nav_y // 4 - 1 do
		vesc.disp_render(strip, 0, i * 4, {colors.bg, colors.bg})
	end
end

M.shade_last = {}

function M.shade_state_list()
	local mode = require("lib.mode")
	local signals = require("lib.signals")
	return {
		mode.current, state.light_on, state.cruise_control_active,
		state.conf_dirty, signals.req, signals.horn_blipping(),
	}
end

function M.page_shade(switched)
	local geom = require("lib.geom")
	local L = M.L
	local g = M.shade_geom
	local curr = M.shade_state_list()

	if switched then
		M.resources = {
			shade_img = vesc.img_buffer("indexed4", g.cell_w - 8, g.cell_h - 8),
		}
		M.overlay_clear()
	end

	-- Every button is redrawn whenever any state changes. Six cells is cheap,
	-- and the alternative is a per-cell dirty check over state several cells
	-- share.
	if switched or not same(curr, M.shade_last) then
		local img = M.resources.shade_img
		local bw, bh = g.cell_w - 8, g.cell_h - 8

		for i = 0, g.cols * g.rows - 1 do
			local a = M.shade_slots[i + 1] or 0
			img:clear()
			if a ~= 0 then
				img:rectangle(0, 0, bw, bh, 1, false, 1, 8)
				du.ttf_txt_center(M.shade_label(a), M.font_24, img,
					{0, 3, 3, 3}, bh // 2 - 6)
				local sub = M.shade_state(a)
				if sub ~= "" then
					du.ttf_txt_center(sub, M.font_16, img,
						{0, 2, 2, 2}, bh // 2 + 22)
				end
			end
			vesc.disp_render(img, g.cell_x(i) + 4, g.cell_y(i) + 4,
				M.shade_active(a) and colors.accent_aa or colors.text_aa)
		end
	end

	M.shade_last = curr
end

-- --- PIN keypad ---
--
-- A keypad over the whole panel, shown at startup when a PIN is set and until
-- it is entered. While it is up the display asserts neutral instead of the
-- stored drive mode, whose current scale is zero, so the motor will not turn.
--
-- Be clear about what this is: a deterrent, not security. The PIN is a plain
-- number in eeprom that anything on the bus can read, and the dash-side half
-- stops working the moment the display is unplugged.

M.pin_cols = 3
M.pin_rows = 4
M.pin_entry_h = 56

-- 1-9 then clear, zero, enter. -1 is clear and -2 is enter, so the cell value
-- is the digit everywhere else and no lookup table is needed.
M.pin_keys = {1, 2, 3, 4, 5, 6, 7, 8, 9, -1, 0, -2}

function M.pin_geom()
	local L = M.L
	local top = M.pin_entry_h + 4
	return {
		top = top,
		key_w = L.disp_w // M.pin_cols,
		key_h = (L.nav_y - top) // M.pin_rows,
	}
end

function M.pin_key_x(i, pg)
	return (i % M.pin_cols) * pg.key_w
end

function M.pin_key_y(i, pg)
	return pg.top + (i // M.pin_cols) * pg.key_h
end

function M.pin_key_label(v)
	if v == -1 then return "C" end
	if v == -2 then return "OK" end
	return string.format("%d", v)
end

-- Which key a coordinate is over, or nil. Same shape as the other two grids.
function M.pin_key_hit(x, y)
	local pg = M.pin_geom()
	if x < 0 or y < pg.top then
		return nil
	end
	local cx = x // pg.key_w
	local cy = (y - pg.top) // pg.key_h
	if cx >= M.pin_cols or cy >= M.pin_rows then
		return nil
	end
	return cy * M.pin_cols + cx
end

M.pin_last = {}

function M.page_pin(switched)
	local pin = require("lib.pin")
	local L = M.L
	local pg = M.pin_geom()
	local curr = {pin.entry_len, pin.wait_left, pin.msg()}

	if switched then
		M.resources = {
			pin_key = vesc.img_buffer("indexed4", pg.key_w - 8, pg.key_h - 8),
			pin_top = vesc.img_buffer("indexed4", L.disp_w, M.pin_entry_h),
		}
		M.overlay_clear()

		-- The keys never change, so they are drawn once on entry.
		local img = M.resources.pin_key
		for i = 0, M.pin_cols * M.pin_rows - 1 do
			img:clear()
			img:rectangle(0, 0, pg.key_w - 8, pg.key_h - 8, 1, false, 1, 8)
			-- The big font carries only "0123456789.:-% DVESC", so the digits
			-- get it and the two word keys fall back to the mid font, which
			-- has the full character set.
			local v = M.pin_keys[i + 1]
			du.ttf_txt_center(M.pin_key_label(v),
				(v < 0) and M.font_24 or M.font_40, img, {0, 3, 3, 3})
			vesc.disp_render(img, M.pin_key_x(i, pg) + 4,
				M.pin_key_y(i, pg) + 4, colors.text_aa)
		end
	end

	if switched or not same(curr, M.pin_last) then
		local top = M.resources.pin_top
		top:clear()

		-- One dot per digit entered rather than the digits, and the message
		-- line instead while there is one to show.
		local msg = pin.msg()
		if msg ~= "" then
			du.ttf_txt_center(msg, M.font_24, top, {0, 2, 2, 2})
		else
			-- Asterisks and hyphens, both of which the big font has.
			du.ttf_txt_center(pin.dots(), M.font_40, top)
		end

		vesc.disp_render(top, 0, 0,
			(pin.wait_left > 0) and colors.crit_aa or colors.text_aa)
	end

	M.pin_last = curr
end


-- --- the boot log ---------------------------------------------------------
--
-- The board's own log, on the glass. New: the lisp dash has no equivalent,
-- because until now there was nothing to read -- commands_printf sends to
-- whichever port last spoke to the board, so every line from bring-up went
-- nowhere and finding out why a display came up wrong meant a serial cable.
--
-- The plainest page on the dash on purpose. Fixed rows, oldest at the top,
-- newest at the bottom, the text drawn as it arrived. It reads like a Linux
-- console because that is what it is, and a log that has been prettified is
-- a log you cannot trust to be the log.
--
-- Left-aligned and clipped rather than scaled to fit: a proportional font
-- makes a long path wider than the panel, and cutting the end off a line is
-- better than shrinking every line to suit the worst one.
M.log_rows = nil

-- Redrawn whole whenever the text changes. There is no per-row dirty check
-- because every row moves when one line is appended, which is the common
-- case: the cheap thing here is comparing the joined text, not tracking rows.
M.log_last = ""

function M.log_geom()
	local L = M.L
	local _, cap = M.font_16:glyph_dims("D")
	local line_h = cap + 6
	local top = L.page_y
	return {
		line_h = line_h,
		top = top,
		rows = (L.page_h) // line_h,
		x = 8,
	}
end

function M.page_log(switched)
	local boot_log = require("lib.boot_log")
	local L = M.L
	local g = M.log_geom()

	local lines = boot_log.lines()

	-- The last rows that fit, because the end of a log is the part worth
	-- having when it does not all fit.
	local first = #lines - g.rows + 1
	if first < 1 then
		first = 1
	end

	local shown = {}
	for i = first, #lines do
		shown[#shown + 1] = lines[i]
	end

	local joined = table.concat(shown, "\n")

	if switched then
		M.resources = {
			log_img = vesc.img_buffer("indexed2", L.page_w, g.rows * g.line_h),
		}
	end

	if switched or joined ~= M.log_last then
		local img = M.resources.log_img
		img:clear()

		for i, line in ipairs(shown) do
			-- indexed2, so one bit per pixel and no antialiasing: at this
			-- size the ramp costs four times the buffer and buys nothing a
			-- reader would notice, and the page is the one that has to work
			-- when memory is the thing that went wrong.
			--
			-- Through the helper, because img:text takes a baseline and not a
			-- top edge -- passing the row's top renders the line above its
			-- own buffer.
			du.ttf_txt_left(line, M.font_16, img, g.x, (i - 1) * g.line_h,
				{0, 1})
		end

		vesc.disp_render(img, L.page_x, g.top, colors.text_2)
		M.log_last = joined
	end
end

return M
