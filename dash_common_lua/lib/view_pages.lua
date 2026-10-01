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

return M
