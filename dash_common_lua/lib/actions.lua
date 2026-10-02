-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- What a press does.
--
-- Ported from the action dispatch in dash_common/main_body.lisp:
-- btn-do-action, btn-short, btn-long, setting-update, the chart source
-- selection, conf-nudge, walk-requested and horn-held.
--
-- Action ids are stored in eeprom, so the numbers are fixed and the list is
-- append-only. Each of the four touch regions has a short id and a long id,
-- and the six quick-shade cells each have one; they all come through
-- do_action, so a region, a shade cell and a gesture bound to the same id do
-- the same thing.
--
--   0 none            12 reset session maxima
--   1 page +          13 walk assist (held, see walk_requested)
--   2 page -          14 write controller config to flash
--   3 settings        15 revert controller config
--   4 mode +          16 quick shade
--   5 mode -          17 hazard
--   6 lights          18 indicate left
--   7 backlight dim   19 indicate right
--   8 cruise          20 high beam
--   9 logging         21 horn (momentary, see horn_held)
--                     22 lock now
--
-- Two of them are not edges at all. Walk assist and the horn are held: the
-- controller expires a walk request after half a second and a horn is
-- momentary, so both are derived from the button currently down rather than
-- fired once. That is why do_action does nothing for 13 and the transmit path
-- reads walk_requested() and horn_held() directly.

local state = require("lib.state")
local settings = require("lib.settings")
local apply = require("lib.apply")
local pages = require("lib.pages")
local vp = require("lib.view_pages")
local stats = require("lib.statistics")
local mode = require("lib.mode")
local signals = require("lib.signals")
local pin = require("lib.pin")
local conf = require("lib.controller_conf")
local comms = require("lib.comms")
local notify = require("lib.notify")
local input = require("lib.input")

local M = {}

-- Installed by the board when it has real backlight control. See action 7.
M.bl_set = nil

-- The board's config, needed by anything that writes a setting and reloads.
M.cfg = nil

--- held actions ---
--
-- True while a button whose long action is this one is being held past the
-- long-press point. Derived from the held state rather than from do_action,
-- which fires once. Releasing the button clears btn_hold_region, which stops
-- the request on the next frame.
local function long_held(id)
	local idx = input.btn_hold_region
	return idx ~= nil
		and settings.values.btn_long[idx + 1] == id
		and input.btn_hold_progress >= 1.0
end

function M.walk_requested()
	return long_held(13)
end

-- Same shape and for the same reason: the horn is momentary. A press on the
-- quick shade cannot hold anything and blips instead.
function M.horn_held()
	return long_held(21)
end

--- the settings page ---

-- Step the selected setting by its stored step, in the direction sign, and
-- write it.
--
-- The lisp builds the expression (op value step) and evals it; a sign is the
-- same thing without the eval.
function M.setting_update(sign)
	if state.setting_num <= 0 then
		return
	end

	local i = vp.setting_now + 1
	local name = vp.setting_list[i]
	local lim = apply.built.lims[i]
	local step = apply.built.steps[i]

	settings.write(name, settings.clamp(
		settings.read(name) + sign * step, lim[1], lim[2],
		settings.read(name)))

	-- Reload so a read back is current. The repaint is the worker's.
	settings.load(M.cfg)
	apply.build()
	apply.distribute()
	settings.apply_units()

	-- The theme moves every palette, and those are baked into the indexed
	-- buffers already on screen, so this one setting needs the full repaint
	-- the worker does. The rest are values rather than colours and must not
	-- trigger it: the spinner repeats while a button is held, and repainting
	-- the panel per step would make it unusable.
	if name == "theme" then
		state.settings_redraw = true
	end
end

function M.setting_next()
	if state.setting_num > 0 then
		vp.setting_now = (vp.setting_now + 1) % state.setting_num
	end
end

--- the controller settings page ---
--
-- Here rather than in lib/controller_conf.lua because it reports through
-- notify, which belongs to the dash rather than to the protocol.
function M.conf_nudge(dir)
	local row = conf.row(conf.now)
	local v = conf.value(conf.now)

	if v == nil then
		notify.show("Waiting for controller")
	elseif conf.blocked(conf.now) then
		notify.show("Kill switch off")
	else
		conf.send(0, row[1], v + dir * row[4])
	end
end

function M.conf_next()
	conf.now = (conf.now + 1) % conf.menu_len()
end

--- the chart ---

-- Which live slots the chart can be pointed at, in cell order and without
-- duplicates. The gesture can only reach what is on the live page, so the
-- button fallback steps through the same set rather than the whole catalog.
function M.chart_sources()
	local out = {}
	local seen = {}

	for i = 1, 4 do
		local src = vp.slots[i]
		if not seen[src] then
			seen[src] = true
			out[#out + 1] = src
		end
	end

	return out
end

-- Point the chart at a slot_catalog source. A live cell already holds a
-- catalog index, which is the same thing the chart plots, so there is no new
-- mapping. Written through so the choice survives a power cycle.
--
-- The ring is cleared, because what is in it is a history of the old source.
-- The lisp defines chart_reset for exactly this and never calls it, so
-- changing source there leaves up to ten seconds of the previous signal
-- plotted against the new one's axis.
function M.chart_point_at(src)
	vp.chart_src = src
	stats.chart_src = src
	stats.chart_reset()
	settings.write("chart_src", src)
	settings.values.chart_src = src
end

-- Point it at a source and go to the chart page. Refused with a message when
-- the page mask has that page switched off, rather than setting a source
-- nothing will draw.
function M.chart_set_src(src)
	local pg = pages.index_of(vp.page_chart)

	if pg == nil then
		notify.show("Chart page off")
		return
	end

	M.chart_point_at(src)
	state.page_now = pg
	notify.show("Charting " .. stats.slot_label(src))
end

-- Step the source along the live slots, for the chart page's own buttons, so
-- it is reachable without the gesture. Stays on the chart page.
function M.chart_step(dir)
	local srcs = M.chart_sources()
	local n = #srcs

	local at = 0
	for i, s in ipairs(srcs) do
		if s == vp.chart_src then
			at = i - 1
		end
	end

	local next_src = srcs[(at + dir + n) % n + 1]
	M.chart_point_at(next_src)
	notify.show(stats.slot_label(next_src))
end

function M.chart_step_secs()
	local secs = vp.chart_secs == 10 and 5 or 10
	vp.chart_secs = secs
	settings.write("chart_secs", secs)
	settings.values.chart_secs = secs
end

--- the action table ---

function M.do_action(a)
	if a == 1 then
		pages.next()
	elseif a == 2 then
		pages.prev()
	elseif a == 3 then
		pages.toggle_settings()
	elseif a == 4 then
		if mode.current < mode.num - 1 then
			mode.set(mode.current + 1)
		end
	elseif a == 5 then
		if mode.current > 0 then
			mode.set(mode.current - 1)
		end
	elseif a == 6 then
		state.light_on = not state.light_on

	elseif a == 7 then
		-- Dims the backlight. On the dashes this action came from the panel
		-- had no backlight control, so the lisp accepts it and does nothing
		-- rather than renumbering, which would change what stored settings
		-- mean. This board drives the backlight on a PWM pin, so the action
		-- works here -- and the quick shade has had a DIM button that did
		-- nothing all along. Still a no-op on a board that installs no
		-- bl_set, which is the lisp's behaviour.
		if M.bl_set then
			state.backlight_dim = not state.backlight_dim
			M.bl_set(state.backlight_dim and settings.values.bl_dim
				or settings.values.bl_bright)
		end

	elseif a == 8 then
		comms.send(250, comms.build_250(0))
	elseif a == 9 then
		-- Start or stop logging on the controller.
		comms.send(250, comms.build_250(2))

	elseif a == 12 then
		-- Clears the session maxima, the voltage floor and both timers. Bound
		-- to a long press: while it is held the session page fades the values
		-- it is about to clear, so the press is its own confirmation.
		stats.reset_max()

	elseif a == 13 then
		-- Walk assist, which is held rather than triggered. Nothing to do on
		-- the edge; walk_requested derives it from the button that is down.

	elseif a == 14 then
		-- 14 writes the running configuration to flash, 15 throws the unsaved
		-- changes away. Both are refused by the controller unless the kill
		-- switch is on, since writing fights anything else touching the
		-- configuration and reverting mid-ride would change the feel
		-- abruptly.
		conf.send(1, 0, 0.0)
	elseif a == 15 then
		conf.send(2, 0, 0.0)

	elseif a == 16 then
		-- The quick shade. One past the settings page, so paging cannot reach
		-- it and it does not cost a page slot; pressing it again closes it,
		-- as does a swipe up.
		pages.toggle_shade()

	elseif a == 17 then
		signals.toggle(signals.HAZARD)
	elseif a == 18 then
		signals.toggle(signals.LEFT)
	elseif a == 19 then
		signals.toggle(signals.RIGHT)
	elseif a == 20 then
		signals.toggle(signals.BEAM)
	elseif a == 21 then
		signals.horn_blip()

	elseif a == 22 then
		-- Lock now. Refused while moving: the display asserts neutral while
		-- locked, and taking the drive away mid-ride is not something a
		-- mis-tap should be able to do.
		if math.abs(state.kmh) > 1.0 then
			notify.show("Stop first")
		else
			pin.engage()
		end
	end
end

--- press dispatch ---
--
-- A page can claim a press before it reaches the stored action. The order of
-- the claims is the order below and it matters: the keypad claims everything,
-- then the shade, then the settings page, then the two pages with their own
-- spinners.

-- Long presses. On the live page a hold over a cell charts that cell, which
-- is the only way to pick what the chart plots by pointing at it. A hold that
-- lands outside the cell grid, or on any other page, falls through to the
-- stored action -- so the session reset on a held region still works
-- everywhere except over a live cell, where the cell highlight says what the
-- press will do instead.
function M.long(idx)
	-- Locked: a long press does nothing at all. The keypad has no long
	-- actions and everything else is out of reach.
	if pages.pin_showing() then
		return
	end

	local a = settings.values.btn_long[idx + 1]

	-- Walk assist and the horn are not claimable. Both are held rather than
	-- triggered and both read the held state directly, so claiming the region
	-- would leave the request running while the chart page opened.
	local held = a == 13 or a == 21

	local pg = pages.current()
	local cell = nil
	if pg == vp.page_live and not held then
		cell = vp.live_geom.hit(input.touch_x, input.touch_y)
	end

	if cell then
		M.chart_set_src(vp.slots[cell + 1])
	elseif pg == vp.page_chart and input.touch_y < input.nav_y and not held then
		M.chart_step_secs()
	else
		M.do_action(a)
	end
end

function M.short(idx)
	local a = settings.values.btn_short[idx + 1]
	local pg = pages.current()

	-- Locked: the keypad is the only thing on screen that does anything.
	-- Nothing falls through to a stored action, or a region bound to paging
	-- would walk straight off the lock.
	if pages.pin_showing() then
		local k = vp.pin_key_hit(input.touch_x, input.touch_y)
		if k then
			pin.key(vp.pin_keys[k + 1])
		end
		return
	end

	-- The quick shade is six buttons in the area the four touch regions cover
	-- with two, so a press there is resolved by position rather than by
	-- region. Below the nav strip the regions keep their own actions, so there
	-- is still a way off the shade without the gesture.
	if pages.shade_showing() and input.touch_y < input.nav_y then
		local cell = vp.shade_geom.hit(input.touch_x, input.touch_y)
		if cell then
			local sa = vp.shade_slots[cell + 1]
			if sa ~= 0 then
				M.do_action(sa)
			end
		end
		return
	end

	-- The settings page: region 0 scrolls, 1 and 2 adjust.
	if state.page_now == state.page_num then
		if idx == 0 then
			M.setting_next()
		elseif idx == 1 then
			M.setting_update(-1)
		elseif idx == 2 then
			M.setting_update(1)
		else
			M.do_action(a)
		end
		return
	end

	-- The chart page steps its source, but only for a press above the nav
	-- strip: regions 1 and 2 are both the screen halves and the strip, and
	-- claiming the strip too would leave no way to page off the chart.
	if pg == vp.page_chart and input.touch_y < input.nav_y then
		if idx == 1 then
			M.chart_step(-1)
		elseif idx == 2 then
			M.chart_step(1)
		else
			M.do_action(a)
		end
		return
	end

	-- The controller settings page scrolls and adjusts the same way, but the
	-- values live on the controller, so a press sends a frame rather than
	-- writing eeprom.
	if pg == vp.page_conf then
		if idx == 0 then
			M.conf_next()
		elseif idx == 1 then
			M.conf_nudge(-1.0)
		elseif idx == 2 then
			M.conf_nudge(1.0)
		else
			M.do_action(a)
		end
		return
	end

	M.do_action(a)
end

--- gestures ---
--
-- Swipe down opens the quick shade from any page, swipe up closes it. A
-- gesture rather than a region, because on a touch board there is no region
-- to spare.
function M.swipe_down()
	if not pages.overlay_showing() then
		M.do_action(16)
	end
end

function M.swipe_up()
	if pages.shade_showing() then
		state.page_now = 0
	end
end

-- Install every handler on the input layer. Repeats only make sense on the
-- settings page, where they scroll a value; elsewhere they would fire a page
-- change over and over.
function M.bind()
	input.clear_handlers()

	for i = 0, 3 do
		input.on_pressed[i] = function() M.short(i) end
		input.on_long_pressed[i] = function() M.long(i) end
	end

	input.on_repeat_press[1] = function()
		if state.page_now == state.page_num then M.setting_update(-1) end
	end
	input.on_repeat_press[2] = function()
		if state.page_now == state.page_num then M.setting_update(1) end
	end

	input.on_swipe_down = M.swipe_down
	input.on_swipe_up = M.swipe_up
end

return M
