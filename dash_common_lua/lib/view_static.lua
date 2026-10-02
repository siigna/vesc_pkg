-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Always-on part of the screen: status strip, speed, battery bar, nav strip.
--
-- Ported from dash_common/views/view_static.lbm.
--
-- A state list is sampled once per pass and only the entries that changed get
-- redrawn. On a parallel-RGB panel the blit is cheap but building the image
-- buffers is not, so the dirty tracking earns its keep either way.
--
-- No bitmap assets: the indicators are primitives and text, which is what
-- lets the whole thing be re-proportioned by editing the layout numbers.
--
-- Two differences from the lisp, both forced rather than chosen:
--
--   The lisp allocates its buffers out of dm-pool, a preallocated display
--   memory pool. Lua image buffers are their own objects with their own
--   lifetime, so there is no pool to pass. The dirty tracking matters more
--   here, not less.
--
--   The state list is a table indexed from 1, where the lisp indexes from 0.
--   The field numbers in the comments are the lisp's, so the two can be read
--   side by side; the code uses the Lua index.

local state = require("lib.state")
local colors = require("lib.colors")
local signals = require("lib.signals")
local battery = require("lib.battery")
local mode = require("lib.mode")
local units = require("lib.units")
local du = require("lib.draw_utils")

local M = {}

-- Set by the board: everything below is derived by stacking, so changing one
-- height moves what follows it.
M.layout = nil

-- Supplied by the board or the page view. Defaults keep a bench render
-- working without them.
M.drive_mode_names = {"REV", "NEUTRAL", "ECO", "NORMAL", "SPORT"}
M.light_on_is_highbeam = false
M.overlay_showing = function() return false end
M.font_speed = nil
M.font_24 = nil
M.font_16 = nil

function M.secs_since(t)
	return vesc.secs_since(t)
end

-- The whole screen is described here, including the page area view_pages
-- draws into, so the bands cannot drift apart.
--
-- disp_w, disp_h, strip_h, speed_h, page_h, page_cols and page_row_h come
-- from the board profile: they are the only numbers that differ between a
-- 480x480 and an 800x480 panel.
function M.set_layout(cfg)
	local L = {
		disp_w = cfg.disp_w,
		disp_h = cfg.disp_h,
		strip_h = cfg.strip_h,
		speed_h = cfg.speed_h,
		page_h = cfg.page_h,
		page_cols = cfg.page_cols,
		-- view_pages reads this from the layout rather than the board, so
		-- the two cannot disagree about row height.
		page_row_h = cfg.page_row_h,
		unit_h = 24,
		mode_h = 30,
		batt_h = 44,
	}

	L.speed_y = L.strip_h + 2
	L.unit_y = L.speed_y + L.speed_h + 2
	L.mode_y = L.unit_y + L.unit_h + 2
	L.batt_y = L.mode_y + L.mode_h + 6

	-- Page area, drawn by view_pages.
	L.page_x = 0
	L.page_w = L.disp_w
	L.page_y = L.batt_y + L.batt_h + 8

	-- Touch nav strip. Also the region split lib/input uses.
	L.nav_y = L.page_y + L.page_h + 4

	M.layout = L
	return L
end

-- Indicator blink. The controller sends the period it is flashing at and the
-- timestamp of when the indicator came on, so this blinks in step with the
-- vehicle rather than at its own rate.
--
-- indicate_ms is the half period -- on, then off -- which puts the 430 ms the
-- bike package sends at about 1.2 Hz. The producer does not say which it
-- means, and the other reading would be twice that, too fast for a turn
-- signal.
function M.blink_on()
	local per = state.indicate_ms > 50 and state.indicate_ms or 430
	local ms = math.floor(1000.0 * M.secs_since(state.indicator_timestamp))
	return ms % (2 * per) < per
end

-- One slot carries whichever condition matters most, because the strip has no
-- room for a pill each and these are all momentary. Worst first.
--
--   LOCKD  the controller is holding a lock of its own
--   KILL   the kill switch is holding the motor
--   FAULT  a controller fault code
--   BRAKE  the brake input is applied, reported by the PAS app
--   REGEN  the pack is taking current back
--   FAN    the auxiliary output is on, which is how a cooling fan is switched
--   UNSVD  a setting was changed and not stored
--
-- nil when there is nothing to say, which blanks the slot.
function M.condition_now()
	-- LOCKD outranks the kill switch: both hold the motor, and this one needs
	-- a code rather than a switch, so it is the more useful thing to say.
	if state.esc_pin_holding then
		return {"LOCKD", colors.red_icon}
	end
	if state.kill_sw_active then
		return {"KILL", colors.red_icon}
	end
	if state.fault_code ~= 0 then
		return {"FAULT", colors.red_icon}
	end
	if (state.pas_flags & 0x08) ~= 0 then
		return {"BRAKE", colors.warn_aa}
	end
	if state.kw < -0.05 then
		return {"REGEN", colors.green_icon}
	end
	if state.aux_on then
		return {"FAN", colors.blue_icon}
	end
	-- Not a hazard, so it ranks under every one, but it has to be visible
	-- somewhere or a setting changed on the move is silently lost at the next
	-- power cycle.
	if state.conf_dirty then
		return {"UNSVD", colors.warn_aa}
	end
	return nil
end

function M.condition_txt()
	local c = M.condition_now()
	return c and c[1] or ""
end

-- Rounded the way the lisp rounds, which is half away from zero rather than
-- Lua's math.floor towards negative infinity. A speed of -0.5 is not a real
-- reading, but a regen power of -0.5 kW is.
local function round(v)
	if v < 0 then
		return -math.floor(-v + 0.5)
	end
	return math.floor(v + 0.5)
end

-- The sampled state. Lisp field numbers in comments, because the two files
-- are meant to be readable side by side.
--
-- sig_*_shown rather than the received values: with a bike-controls node on
-- the bus these are what it reports, and without one they are what this
-- display asked for in byte 3 of SID 201 -- which is the only feedback a
-- rider gets on a bike where the display is the only thing asking.
--
-- The blink phase is part of the state, so a pill toggles through the
-- ordinary redraw path rather than needing a timer of its own.
function M.sample()
	return {
		signals.l_shown() and M.blink_on(),      -- 0
		signals.r_shown() and M.blink_on(),      -- 1
		signals.beam_shown(),                    -- 2
		state.kickstand_down,                    -- 3
		mode.current,                            -- 4
		state.cruise_control_active,             -- 5
		round(100.0 * battery.soc()),            -- 6
		state.battery_a_charging,                -- 7
		state.fault_code,                        -- 8
		state.light_on,                          -- 9
		state.page_now,                          -- 10
		round(units.speed(state.kmh)),           -- 11
		state.service_mode,                      -- 12
		round(state.cruise_control_speed),       -- 13
		M.condition_txt(),                       -- 14
	}
end

-- Which fields changed, and what they were, kept on the module rather than as
-- locals of a thread so one pass can be run on its own. The offline render
-- harness drives step() directly for that reason: with a thread running
-- alongside, whether a changed field had been painted before the frame was
-- saved was a race.
M.update = {}
M.last = {}

function M.reset()
	M.last = M.sample()
	M.update = {}
	for i = 1, #M.last do
		M.update[i] = true
	end
end

-- Never changes with the vehicle state, so it is not in the state list. Also
-- used to repaint over anything that drew on top, such as the splash or a
-- notification banner.
function M.frame()
	local L = M.layout
	vesc.disp_clear(colors.bg)

	local line = vesc.img_buffer("indexed2", L.disp_w, 2)
	line:clear(1)
	vesc.disp_render(line, 0, L.strip_h - 2, colors.theme_2)
	vesc.disp_render(line, 0, L.nav_y - 2, colors.theme_2)

	state.view_force_pages = true
end

-- A pill of text, centred in a box. Used for every status indicator so they
-- all line up and all erase their own footprint.
function M.pill(txt, x, y, w, h, on, pal)
	local buf = vesc.img_buffer("indexed4", w, h)
	buf:clear()
	if on then
		buf:rectangle(0, 0, w, h, 1, false, 1, 6)
		du.ttf_txt_center(txt, M.font_16, buf)
	end
	vesc.disp_render(buf, x, y, pal)
end

-- One pass. Draws whatever changed since the last call.
function M.step()
	local L = M.layout
	local up = M.update
	local last = M.last
	local w = L.disp_w

	-- --- Status strip ---
	-- Turn signals at the outer edges, the condition in the middle, the rest
	-- filling in from the left. All derived from disp_w, so a wider panel
	-- spreads them rather than leaving the right half empty.
	local pill_y, pill_h = 8, 40

	if up[1] then
		M.pill("<", 8, pill_y, 52, pill_h, last[1], colors.green_icon)
	end
	if up[2] then
		M.pill(">", w - 60, pill_y, 52, pill_h, last[2], colors.green_icon)
	end

	if up[15] then
		local c = M.condition_now()
		-- Centred where there is room, packed in after the kickstand slot on
		-- a narrow panel where centring it would overlap.
		local mid = w // 2 - 35
		local cx = mid < 216 and 216 or mid
		M.pill(c and c[1] or "", cx, pill_y, 70, pill_h, c ~= nil,
			c and c[2] or colors.red_icon)
	end

	if up[3] or up[10] then
		-- High beam shows as the word, not only the colour. The config flag
		-- is for hardware whose single light output is the high beam, where
		-- there is no separate signal.
		local hi = last[3] or (state.light_on and M.light_on_is_highbeam)
		M.pill(hi and "HIGH" or "LIGHT", 68, pill_y, 66, pill_h,
			state.light_on or last[3],
			last[3] and colors.blue_icon or colors.green_icon)
	end

	if up[4] then
		M.pill("STAND", 140, pill_y, 72, pill_h, last[4], colors.warn_aa)
	end

	if up[6] or up[14] then
		local txt = last[6]
			and string.format("CC %d", math.floor(units.speed(state.cruise_control_speed)))
			or "CC"
		M.pill(txt, w - 192, pill_y, 124, pill_h, last[6], colors.green_icon)
	end

	-- --- Speed ---
	if up[12] then
		local buf = vesc.img_buffer("indexed4", w, L.speed_h)
		buf:clear()
		du.ttf_txt_center(string.format("%d", math.floor(units.speed(state.kmh))),
			M.font_speed, buf)
		vesc.disp_render(buf, 0, L.speed_y,
			state.battery_a_charging and colors.charging or colors.speed)
	end

	-- --- Units and drive mode ---
	if up[12] or up[8] then
		local buf = vesc.img_buffer("indexed4", w, 26)
		buf:clear()
		du.ttf_txt_center(units.speed_str(), M.font_16, buf)
		vesc.disp_render(buf, 0, L.unit_y, colors.text_aa)
	end

	if up[5] or up[13] then
		local buf = vesc.img_buffer("indexed4", w, 32)
		buf:clear()
		local txt = last[13] and "SERVICE"
			or M.drive_mode_names[math.floor(last[5]) + 1]
		du.ttf_txt_center(txt or "", M.font_24, buf)
		vesc.disp_render(buf, 0, L.mode_y,
			last[13] and colors.warn_aa or colors.text_aa)
	end

	-- --- Battery ---
	if up[7] or up[8] then
		local soc = du.clamp01(last[7] / 100.0)
		local pad = 24
		local bw = w - 2 * pad

		local buf = vesc.img_buffer("indexed4", bw, L.batt_h)
		buf:clear()
		buf:rectangle(0, 0, bw, L.batt_h, 1, false, 1, 8)
		if soc > 0.0 then
			buf:rectangle(3, 3, math.floor((bw - 6) * soc), L.batt_h - 6,
				2, true, 1, 6)
		end
		-- The percentage sits on top of the fill, so it needs a colour of its
		-- own rather than the brightest step of the fill ramp, which would be
		-- green on green.
		du.ttf_txt_center(string.format("%d %%", math.floor(last[7])),
			M.font_24, buf, {0, 3, 3, 3})

		local fill
		if last[8] then
			fill = colors.ok
		elseif soc < 0.15 then
			fill = colors.crit
		elseif soc < 0.30 then
			fill = colors.warn
		else
			fill = colors.ok
		end

		vesc.disp_render(buf, pad, L.batt_y,
			{colors.bg, colors.shade(fill, 0.6), fill, colors.text})
	end

	-- --- Touch nav strip ---
	if up[11] then
		local page = math.floor(last[11])
		local buf = vesc.img_buffer("indexed4", w, L.disp_h - L.nav_y)
		buf:clear()

		-- Hints for the three regions lib/input splits the strip into.
		buf:text(24, 22, M.font_24, page >= state.page_num and "BACK" or "SET", 1, true)
		buf:text(w - 44, 22, M.font_24, ">", 1, true)
		du.ttf_txt_center(page >= state.page_num and "Settings"
			or string.format("Page %d/%d", page + 1, state.page_num),
			M.font_16, buf)

		vesc.disp_render(buf, 0, L.nav_y, colors.text_aa)
	end

	local force = state.view_force_static
	state.view_force_static = false
	if force then
		M.frame()
	end

	local now = M.sample()
	for i = 1, #up do
		M.update[i] = force or last[i] ~= now[i]
	end
	M.last = now
end

return M
