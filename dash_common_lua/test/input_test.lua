-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Unit tests for lib/input.lua. New: the lisp dash has no test for input.lisp
-- at all, because its loop body only exists inside a thread that polls real
-- hardware.
--
-- What is worth pinning is every rule the comments in input.lisp claim:
-- a press fires on release and not before, a drag out of the region cancels
-- it, a long press suppresses the tap, the repeat is rate limited, and a
-- swipe counts instead of a tap rather than as well as one.
local t = require("test.harness")
local input = require("lib.input")

local clock = 0.0
input.now = function() return clock end
input.secs_since = function(ts) return clock - ts end

-- Tap and release in one region, and nothing else.
local fired = {}
local function record(name)
	return function() fired[name] = (fired[name] or 0) + 1 end
end

local function reset(w, nav)
	input.set_layout({disp_w = w or 800, nav_y = nav or 440})
	input.clear_handlers()
	input.btn_now = nil
	input.long_fired = false
	input.btn_hold_region = nil
	input.btn_hold_progress = 0.0
	input.touch_x = 0
	input.touch_y = 0
	clock = 0.0
	fired = {}

	for i = 0, 3 do
		input.on_pressed[i] = record("p" .. i)
		input.on_long_pressed[i] = record("l" .. i)
		input.on_repeat_press[i] = record("r" .. i)
	end
	input.on_swipe_down = record("down")
	input.on_swipe_up = record("up")
end

--- regions ---
--
-- The numbers are the lisp's arithmetic, evaluated in the lisp's order: the
-- bottom strip's second boundary is 2 * (disp_w / 3), not (2 * disp_w) / 3.
-- On an 800 wide panel those are 532 and 533, so the order is observable.
reset(800, 440)

t.ok("above the strip, left is 1",  input.region(0, 0) == 1)
t.ok("399 is still left",           input.region(399, 0) == 1)
t.ok("400 is right",                input.region(400, 0) == 2)
t.ok("far right is 2",              input.region(799, 439) == 2)

t.ok("strip left third is 0",       input.region(0, 440) == 0)
t.ok("265 is still 0",              input.region(265, 440) == 0)
t.ok("266 is the middle, 3",        input.region(266, 440) == 3)
t.ok("531 is still 3",              input.region(531, 440) == 3)
t.ok("532 is the right third, 2",   input.region(532, 479) == 2)

-- A square panel splits at 240 and 160/320.
reset(480, 440)
t.ok("square: 239 is left",   input.region(239, 0) == 1)
t.ok("square: 240 is right",  input.region(240, 0) == 2)
t.ok("square: 159 is 0",      input.region(159, 450) == 0)
t.ok("square: 160 is 3",      input.region(160, 450) == 3)
t.ok("square: 320 is 2",      input.region(320, 450) == 2)

--- a tap fires on release ---
reset()

input.step(100, 450)                   -- down in region 0
t.ok("down fires nothing",     fired.p0 == nil)
t.ok("btn_now is the region",  input.btn_now == 0)
t.ok("pressed flag set",       input.btn_pressed[0])
t.ok("other flags clear",      not input.btn_pressed[1] and not input.btn_pressed[3])
t.ok("hold region set",        input.btn_hold_region == 0)
t.near("hold progress starts at zero", input.btn_hold_progress, 0.0)

clock = clock + 0.1
input.step(100, 450)                   -- still held, same region
t.ok("holding fires nothing",  fired.p0 == nil)
t.near("progress is the fraction of the long press", input.btn_hold_progress, 0.1 / 0.6)

input.step(nil, nil)                   -- release
t.ok("release fires the press", fired.p0 == 1)
t.ok("btn_now cleared",         input.btn_now == nil)
t.ok("pressed flag cleared",    not input.btn_pressed[0])
t.ok("hold region cleared",     input.btn_hold_region == nil)
t.near("hold progress cleared", input.btn_hold_progress, 0.0)

input.step(nil, nil)                   -- idle, no repeat of the press
t.ok("an idle pass fires nothing more", fired.p0 == 1)

--- dragging out of the region cancels ---
reset()

input.step(100, 450)                   -- down in 0
clock = clock + 0.05
input.step(400, 450)                   -- drag into 3: a short, horizontal move
t.ok("crossing out cancels",      input.btn_now == nil)
t.ok("no press fired for either", fired.p0 == nil and fired.p3 == nil)
t.ok("hold region cleared",       input.btn_hold_region == nil)

-- The finger is still down, so the next pass is a fresh press in the new
-- region. That is the lisp's behaviour and it is what makes a drag across
-- the strip end as a tap on wherever it settles.
input.step(400, 450)
t.ok("re-acquires in the new region", input.btn_now == 3)
input.step(nil, nil)
t.ok("and that one taps", fired.p3 == 1)

--- long press suppresses the tap ---
reset()

input.step(300, 100)                   -- down in region 1
clock = clock + 0.59
input.step(300, 100)
t.ok("not long yet",                fired.l1 == nil)
t.near("progress just under full",  input.btn_hold_progress, 0.59 / 0.6)

clock = clock + 0.02                   -- 0.61 total
input.step(300, 100)
t.ok("long press fires once",   fired.l1 == 1)
t.near("progress clamps at one", input.btn_hold_progress, 1.0)
t.ok("long press also arms the repeat", fired.r1 == 1)

clock = clock + 0.1
input.step(300, 100)
t.ok("repeat is rate limited", fired.r1 == 1)

clock = clock + 0.06                   -- 0.16 since the last repeat
input.step(300, 100)
t.ok("repeat fires again", fired.r1 == 2)

clock = clock + 1.0
input.step(300, 100)
t.ok("long press does not fire twice", fired.l1 == 1)

input.step(nil, nil)
t.ok("release after a long press is not a tap", fired.p1 == nil)

--- swipes ---
--
-- Measured from where the finger went down to the last position the panel
-- reported, which is why the coordinates are kept on release.
reset()

input.step(300, 100)
clock = clock + 0.1
input.step(305, 100 + input.swipe_min_px + 1)
input.step(nil, nil)
t.ok("a downward flick swipes down", fired.down == 1)
t.ok("and does not also tap",        fired.p1 == nil)
t.ok("and not up",                   fired.up == nil)

reset()
input.step(300, 300)
clock = clock + 0.1
input.step(300, 300 - input.swipe_min_px - 1)
input.step(nil, nil)
t.ok("an upward flick swipes up", fired.up == 1)

-- Exactly the threshold is not far enough: the test is strictly greater.
reset()
input.step(300, 100)
input.step(300, 100 + input.swipe_min_px)
input.step(nil, nil)
t.ok("the threshold itself is a tap", fired.p1 == 1 and fired.down == nil)

-- Mostly horizontal is not a swipe, however far it went.
reset()
input.step(300, 100)
input.step(300 + 100, 100 + 70)        -- dy 70, dx 100: not 2x
t.ok("a diagonal out of the region cancels", input.btn_now == nil)
t.ok("and does not swipe",                   fired.down == nil)

-- A swipe that stays inside one region still counts on release.
reset()
input.step(300, 100)
input.step(310, 300)                   -- dy 200, same region 1
input.step(nil, nil)
t.ok("a swipe within one region fires", fired.down == 1)
t.ok("and does not tap",                fired.p1 == nil)

-- A swipe that runs from the page area down into the nav strip crosses a
-- region boundary. The lisp counts it there rather than losing it.
reset()
input.step(300, 300)                   -- region 1
clock = clock + 0.1
input.step(300, 460)                   -- region 3: dy 160, mostly vertical
t.ok("a swipe across the boundary fires there", fired.down == 1)
t.ok("and cancels the press",                   input.btn_now == nil)
t.ok("without tapping either region",           fired.p1 == nil and fired.p3 == nil)

-- Held too long and it is a long press, not a swipe, even if the finger then
-- travels. By then the press has already done something else.
reset()
input.step(300, 100)
clock = clock + 0.7
input.step(300, 100)
t.ok("long fired", fired.l1 == 1)
input.step(300, 300)
input.step(nil, nil)
t.ok("no swipe after a long press", fired.down == nil)
t.ok("and no tap",                  fired.p1 == nil)

--- missing handlers ---
--
-- A page installs only the handlers it uses, so every dispatch point has to
-- tolerate nil. The lisp's maybe-call macro is what this replaces.
reset()
input.clear_handlers()
input.step(100, 450)
clock = clock + 1.0
input.step(100, 450)
input.step(nil, nil)
t.ok("no handlers is not an error", input.btn_now == nil)

--- no touch at all ---
--
-- touch_read returning nil on a board whose panel did not come up must leave
-- everything alone rather than synthesise a release.
reset()
input.step(nil, nil)
t.ok("idle with nothing held",   input.btn_now == nil)
t.ok("no flags set",             not input.btn_pressed[0] and not input.btn_pressed[2])
t.ok("nothing fired",            next(fired) == nil)

t.report("input")
