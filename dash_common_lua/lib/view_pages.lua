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

return M
