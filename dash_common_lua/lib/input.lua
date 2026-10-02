-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Touch input: four virtual buttons, long press with hold progress, repeat,
-- and vertical swipes.
--
-- Ported from dash_p4/lib/input.lisp, which is identical in dash_s3.
--
-- The other dashes in this family have two to four physical buttons and map
-- them through btn-actions-short / btn-actions-long. A touch board has none,
-- so the screen is divided into regions that stand in for those buttons and
-- the same action codes are reused. That keeps the action dispatch, the
-- settings page navigation and the stored button-action settings working
-- unchanged.
--
--   +------------------------------------------+
--   |                                          |
--   |   btn 1 (left half)   btn 2 (right half) |  y < nav_y: paging
--   |                                          |
--   +------------------------------------------+ nav_y
--   |  btn 0   |    btn 3   |    btn 2         |  bottom strip
--   +------------------------------------------+
--
-- A press fires on release, so a drag out of a region cancels it, and a hold
-- past long_press_s fires the long action instead.
--
-- Two differences from the lisp, both mechanical:
--
--   The lisp has eight on-btn-N-* globals and a maybe-call macro that expands
--   to an if. Here the handlers are tables keyed by region, which makes the
--   four-way cond a lookup and the nil check an ordinary one.
--
--   The lisp runs this as its own thread; the Lua engine has one timer and no
--   threads, so the loop body is step() and the dash drives it. That is also
--   what lets the gesture rules be tested on a host with a fake clock instead
--   of a finger.

local du = require("lib.draw_utils")

local M = {}

--- configuration ---

-- Overwritten by set_layout. The defaults are a 480x480 profile so a bench
-- harness works without a board.
M.disp_w = 480
M.nav_y = 440

-- How long a press has to be held to count as long, and how often the repeat
-- fires once it has.
M.long_press_s = 0.6
M.repeat_s = 0.15

-- A flick rather than a tap: this far, mostly vertically, and quick enough
-- not to have become a long press. The quick shade rides on this, since it
-- has to be reachable from every page without spending one of the four
-- regions on it.
M.swipe_min_px = 60

function M.set_layout(L)
	M.disp_w = L.disp_w
	M.nav_y = L.nav_y
end

--- what the views read ---

M.touch_x = 0
M.touch_y = 0

-- How many polls reported a finger, and how many presses and gestures came
-- out the other end. Diagnostics, and the only ones that separate the three
-- ways touch can be useless on a board where it is the sole input: the bus
-- not answering (the firmware's own tally, which stays flat), the panel
-- answering but reporting nothing (reads is zero), and the panel reporting
-- fine while the regions or the dispatch are wrong (reads climbs and fires
-- does not).
M.reads = 0
M.fires = 0

M.btn_pressed = {[0] = false, false, false, false}

-- How far through its long press each region is, 0.0 to 1.0, and nil when
-- nothing is held. A view can use this to fade the value the press is about
-- to reset, so the thing being destroyed is the progress bar -- no dialog, no
-- extra pixels, and it shows which value the press targets. Releasing early
-- leaves the value alone and it fades back.
--
-- The idea is from DAVEga (github.com/janpom/davega), which dims the number
-- white to black as you hold.
M.btn_hold_region = nil
M.btn_hold_progress = 0.0

--- handlers ---

-- Keyed by region, 0 to 3. A missing entry is not called.
M.on_pressed = {}
M.on_long_pressed = {}
M.on_repeat_press = {}

M.on_swipe_down = nil
M.on_swipe_up = nil

-- Drop every handler, which is what a page change does before installing its
-- own. The lisp calls this input-cleanup-on-pressed.
function M.clear_handlers()
	M.on_pressed = {}
	M.on_long_pressed = {}
	M.on_repeat_press = {}
	M.on_swipe_down = nil
	M.on_swipe_up = nil
end

--- the gesture machine ---

function M.now()
	return vesc.systime()
end

function M.secs_since(t)
	return vesc.secs_since(t)
end

-- Integer division truncating towards zero, as LispBM's / does. Every value
-- here is positive, so this agrees with // -- but the halves and thirds have
-- to be taken in the lisp's order regardless: 2 * (800 / 3) is 532 where
-- (2 * 800) / 3 is 533, and the region boundary is the first of those.
local function idiv(a, b)
	local q = a / b
	if q < 0 then
		return math.ceil(q)
	end
	return math.floor(q)
end

-- Which virtual button a coordinate belongs to. Never nil for an on-screen
-- point: the bottom strip's last case is a catch-all, as in the lisp.
function M.region(x, y)
	if y < M.nav_y then
		if x < idiv(M.disp_w, 2) then
			return 1
		end
		return 2
	end

	if x < idiv(M.disp_w, 3) then
		return 0
	end
	if x < 2 * idiv(M.disp_w, 3) then
		return 3
	end
	return 2
end

-- Live press state, exposed so a test can see why a decision went the way it
-- did rather than only its effect.
M.btn_now = nil
M.btn_start = 0
M.long_fired = false
M.repeat_ts = 0
M.down_x = 0
M.down_y = 0

local function call(fn)
	if fn then
		M.fires = M.fires + 1
		fn()
	end
end

-- A flick: mostly vertical, or a sloppy tap on a button would open the shade,
-- and only while the long press has not fired, since by then the press has
-- already done something else.
local function swiped()
	if M.long_fired then
		return false
	end

	local dx = M.touch_x - M.down_x
	local dy = M.touch_y - M.down_y

	return math.abs(dy) > M.swipe_min_px and
		math.abs(dy) > 2 * math.abs(dx)
end

local function fire_swipe()
	if M.touch_y - M.down_y > 0 then
		call(M.on_swipe_down)
	else
		call(M.on_swipe_up)
	end
end

local function release()
	M.btn_now = nil
	M.btn_hold_region = nil
	M.btn_hold_progress = 0.0
end

-- One pass of the loop. x and y are the touch point, or nil for no touch.
--
-- The coordinates are kept when the finger lifts rather than cleared, because
-- the release branch measures the swipe against them: the last position the
-- panel reported is where the finger went up.
function M.step(x, y)
	local touching = x ~= nil

	if touching then
		M.touch_x = x
		M.touch_y = y
		M.reads = M.reads + 1
	end

	local region = touching and M.region(M.touch_x, M.touch_y) or nil

	if region and not M.btn_now then
		-- Finger down in a new region.
		M.btn_now = region
		M.btn_start = M.now()
		M.repeat_ts = M.btn_start
		M.long_fired = false
		M.btn_hold_region = region
		M.btn_hold_progress = 0.0
		M.down_x = M.touch_x
		M.down_y = M.touch_y

	elseif region and M.btn_now then
		-- Held. Dragging into another region cancels rather than
		-- retargeting, which is what a button would do.
		if region ~= M.btn_now then
			-- Crossing out of the region cancels the press, but a swipe
			-- that started above the nav strip and ran down into it has
			-- still been made, so it counts here rather than being lost.
			if swiped() then
				fire_swipe()
			end
			release()
		else
			M.btn_hold_progress =
				du.clamp01(M.secs_since(M.btn_start) / M.long_press_s)

			if not M.long_fired and
					M.secs_since(M.btn_start) >= M.long_press_s then
				M.long_fired = true
				call(M.on_long_pressed[M.btn_now])
			end

			-- Repeat lets the settings page scroll a value without tapping
			-- once per step.
			if M.long_fired and M.secs_since(M.repeat_ts) >= M.repeat_s then
				M.repeat_ts = M.now()
				call(M.on_repeat_press[M.btn_now])
			end
		end

	elseif not region and M.btn_now then
		-- Released. A flick counts instead of the tap, never as well as it.
		local btn = M.btn_now

		if swiped() then
			fire_swipe()
		elseif not M.long_fired then
			call(M.on_pressed[btn])
		end

		release()
	end

	for i = 0, 3 do
		M.btn_pressed[i] = M.btn_now == i
	end
end

-- One pass driven by the dash's timer, reading the panel itself.
--
-- The lisp runs this as its own thread at 50 Hz. The Lua engine has one timer
-- and no threads, so the dash calls this from that timer instead.
--
-- Polled rather than hung off vesc.on_touch, even though the event exists:
-- a hold that does not move produces no events, and the hold progress and the
-- repeat both have to advance while the finger sits still. Polling is also
-- what the lisp does, which keeps the two dashes deciding the same way.
--
-- A read failure means the controller fell off the bus. Report no touch
-- rather than letting it propagate, so a loose connector does not cost the
-- whole UI.
function M.poll()
	local ok, x, y = pcall(vesc.touch_read)
	if not ok then
		x, y = nil, nil
	end

	M.step(x, y)
end

return M
