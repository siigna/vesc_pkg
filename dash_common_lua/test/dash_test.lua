-- Unit tests for lib/dash.lua: the tick, the dividers, the transmit frames
-- and the worker pass.
--
-- Ported from main() and the thread set in dash_common/main_body.lisp, where
-- each of these is a thread with a sleep. The thread set has no test; the
-- properties worth pinning are the ones the rewrite could get wrong -- that
-- every job still runs at its own rate, that one failing job does not stop
-- the others, and that the two rules about the lock still hold.
vesc = require("test.vesc_stub")

local sent = {}
vesc.can_send_sid = function(id, data) sent[#sent + 1] = {id, data} end
vesc.disp_clear = function() end
vesc.disp_render = function() end
vesc.on_can = function() end

local t = require("test.harness")
local state = require("lib.state")
local settings = require("lib.settings")
local apply = require("lib.apply")
local mode = require("lib.mode")
local pin = require("lib.pin")
local signals = require("lib.signals")
local comms = require("lib.comms")
local stats = require("lib.statistics")
local standalone = require("lib.standalone")
local notify = require("lib.notify")
local input = require("lib.input")
local actions = require("lib.actions")
local pages = require("lib.pages")
local vp = require("lib.view_pages")
local vs = require("lib.view_static")
local dash = require("lib.dash")

local cfg = {
	metric_speeds = true, metric_temps = true,
	battery_hot = 55.0, esc_hot = 80.0, motor_hot = 80.0,
	bl_bright = 1.0, bl_dim = 0.25,
	btn_actions_short = {3, 2, 1, 6},
	btn_actions_long = {0, 12, 0, 8},
}

local L = vs.set_layout({
	disp_w = 800, disp_h = 480, strip_h = 56, speed_h = 120,
	page_h = 150, page_cols = 4, page_row_h = 40,
})
vp.set_layout(L)
input.set_layout(L)
notify.layout = L

vesc.eeprom = {}
apply.restore(cfg)
settings.write("page_mask", 0xFF)
apply.all(cfg)
actions.cfg = cfg

-- The real implementations, captured before anything is replaced: require
-- returns the same table, so reaching for lib.dash again gives back the stub.
local real = {
	tx_step = dash.tx_step,
	worker_step = dash.worker_step,
	static_step = dash.static_step,
	vs_step = vs.step,
	input_poll = input.poll,
	stats_tick = stats.tick,
	pages_step = pages.step,
	notify_step = notify.step,
	standalone_step = standalone.step,
}

-- Count calls instead of drawing. The views and the sampler are replaced
-- wholesale: this file is about the schedule, not about what they draw.
local ran = {}
local function counter(name)
	return function() ran[name] = (ran[name] or 0) + 1 end
end

local function instrument()
	ran = {}
	input.poll = counter("input")
	stats.tick = counter("stats")
	standalone.step = counter("standalone")
	dash.tx_step = counter("tx")
	dash.worker_step = counter("worker")
	dash.static_step = counter("static")
	pages.step = counter("pages")
	notify.step = counter("notify")
	dash.n = 0
	dash.fail_count = {}
	dash.pending = {}
end

-- From here on, reading an undefined global is an error. This file drives
-- M.tick, which is where a local referenced above its own definition shows
-- up -- as a nil call, at runtime, and nowhere else.
t.strict_globals()

--- the dividers ---
--
-- Ten base ticks is 200 ms, which is one period of the slowest job.
instrument()
for _ = 1, 10 do dash.tick() end

t.ok("input every tick",      ran.input == 10)
t.ok("stats every tick",      ran.stats == 10)
t.ok("pages every other",     ran.pages == 5)
t.ok("static every other",    ran.static == 5)
t.ok("tx every fifth",        ran.tx == 2)
t.ok("worker every fifth",    ran.worker == 2)
t.ok("standalone every fifth", ran.standalone == 2)
t.ok("notify every tenth",    ran.notify == 1)

-- The transmit rate is the one the controller depends on: it expires a walk
-- assist request after half a second, and decides a display is gone after
-- five.
t.near("transmit period in ms", dash.period_ms * dash.div.tx, 100.0)
t.ok("which is inside the walk expiry",
	dash.period_ms * dash.div.tx < 500)

-- The base period is the input rate, since it is the only one a rider feels.
t.ok("base tick is the input rate", dash.div.input == 1)
t.near("and is 50 Hz", dash.period_ms, 20.0)

--- one failing job does not stop the others ---
--
-- The lisp wraps each thread in a trap and restarts it after five seconds, so
-- a broken page costs that page. One timer has no such boundary, so each step
-- is guarded.
instrument()
pages.step = function() error("page broke") end

-- The guard reports every failure, which is the right trade on hardware --
-- the dash keeps running and says what is wrong -- and only noise here.
local said = 0
local real_print = print
print = function() said = said + 1 end
for _ = 1, 4 do dash.tick() end
print = real_print

t.ok("and says so each time", said == 2)
t.ok("the failing job is counted",  dash.fail_count.pages == 2)
t.ok("input kept running",          ran.input == 4)
t.ok("and so did the transmit path", ran.stats == 4)

--- the transmit frames ---
instrument()
pin.locked = false
mode.current = 3
mode.num = 5
state.light_on = true
signals.req = signals.LEFT
-- Far enough in the past that the blip has expired. horn_ts is in systime
-- units, so zero is only "long ago" once the clock has run for a while --
-- which it has not, in a test.
signals.horn_ts = -10000
input.btn_hold_region = nil

dash.tx_step = real.tx_step
sent = {}
dash.tx_step()

t.ok("two frames go out",   #sent == 2)
t.ok("SID 201 first",       sent[1][1] == 201)
t.ok("then SID 202",        sent[2][1] == 202)

local f = sent[1][2]
t.ok("byte 0 is the drive mode", string.byte(f, 1) == 3)
t.ok("byte 1 is the light",      string.byte(f, 2) == 1)
t.ok("byte 2 is walk assist, not asked for", string.byte(f, 3) == 0)
t.ok("byte 3 is the signal request", string.byte(f, 4) == signals.LEFT)

-- The lock asserts neutral on the wire and leaves the stored mode alone, so
-- unlocking restores it.
pin.locked = true
pin.drive_mode = mode.current
sent = {}
dash.tx_step()
t.ok("locked: the wire says neutral", string.byte(sent[1][2], 1) == 1)
t.ok("and the stored mode is untouched", mode.current == 3)

pin.locked = false
sent = {}
dash.tx_step()
t.ok("unlocked: the mode is back", string.byte(sent[1][2], 1) == 3)

-- Walk assist and the horn come from the button currently held, not from an
-- edge: the controller expires both.
settings.write("btn1_long", 13)
settings.load(cfg)
input.btn_hold_region = 1
input.btn_hold_progress = 1.0
sent = {}
dash.tx_step()
t.ok("a held walk button sets byte 2", string.byte(sent[1][2], 3) == 1)

settings.write("btn1_long", 21)
settings.load(cfg)
sent = {}
dash.tx_step()
t.ok("a held horn button sets the horn bit",
	(string.byte(sent[1][2], 4) & signals.HORN) ~= 0)

input.btn_hold_region = nil
signals.horn_ts = -10000
sent = {}
dash.tx_step()
t.ok("releasing clears it on the next frame",
	(string.byte(sent[1][2], 4) & signals.HORN) == 0)

--- queued frames ---
--
-- The PIN commands go out three times because they are single frames with no
-- acknowledgement. The lisp sleeps 60 ms between them; a timer callback must
-- not sleep, so they are drained one per frames-divider tick, which is the
-- same spacing.
instrument()
dash.queue(205, comms.pin_cmd_frames(4, 0))
t.ok("three frames queued", #dash.pending == 3)
t.near("drained 60 ms apart",
	dash.period_ms * dash.div.frames, 60.0)

sent = {}
for _ = 1, 9 do dash.tick() end
t.ok("all three went out",  #sent == 3)
t.ok("on SID 205",          sent[1][1] == 205)
t.ok("and the queue is empty", #dash.pending == 0)

-- An empty queue costs nothing.
sent = {}
for _ = 1, 6 do dash.tick() end
t.ok("nothing more is sent", #sent == 0)

--- the worker pass ---
instrument()
dash.worker_step = real.worker_step

-- Neutral when charging, and when the kickstand is down. Asserted rather than
-- requested, so the controller's echo of the old mode loses for the window
-- mode.set opens.
mode.current = 3
mode.cmd_ts = 0
state.battery_a_charging = true
state.kickstand_down = false
pin.locked = false
state.page_now = 1
dash.worker_step()
t.ok("charging asserts neutral", mode.current == 1)
t.ok("and holds it against the controller", mode.asserting())

mode.current = 3
state.battery_a_charging = false
state.kickstand_down = true
dash.worker_step()
t.ok("the kickstand asserts neutral", mode.current == 1)

state.kickstand_down = false

-- The theme repaint is consumed here, not at the press: rebuilding every
-- palette on each step of a held spinner would make the settings page
-- unusable.
local bl = nil
dash.bl_set = function(l) bl = l end
apply.bl_set = dash.bl_set
state.settings_redraw = true
dash.worker_step()
t.ok("the repaint flag is consumed", not state.settings_redraw)
t.ok("and the backlight was set",    bl ~= nil)

--- the lock cannot be navigated off ---
--
-- The press dispatch already refuses to and so does the swipe, but a
-- notification path or a second display could still move the page. The cost
-- of being wrong is a bike that drives while it is supposed to be locked.
pin.locked = true
state.page_now = 2
dash.worker_step()
t.ok("a locked dash is put back on the keypad", pages.pin_showing())

state.page_now = state.page_num           -- the settings page
dash.worker_step()
t.ok("from the settings page too", pages.pin_showing())

-- Unlocking leaves the keypad up until something moves off it.
pin.locked = false
dash.worker_step()
t.ok("unlocking moves to page 0", state.page_now == 0)

dash.worker_step()
t.ok("and stays there", state.page_now == 0)

--- the static view stops under an overlay ---
--
-- Both overlays cover the whole panel above the nav strip. The strip, the
-- speed and the battery bar have to stop repainting while one is up or they
-- would draw over it a field at a time. Holding the force flag means closing
-- it repaints the lot, because their dirty tracking was paused and has no
-- idea what the overlay covered.
instrument()
dash.static_step = real.static_step
local stepped = 0
vs.step = function() stepped = stepped + 1 end

state.page_now = 0
state.view_force_static = false
dash.static_step()
t.ok("no overlay: the view steps",   stepped == 1)
t.ok("and the force flag is not set", not state.view_force_static)

state.page_now = state.page_num + 1       -- the shade
dash.static_step()
t.ok("under the shade it does not step", stepped == 1)
t.ok("and holds the force flag",         state.view_force_static)

state.page_now = state.page_num + 2       -- the keypad
state.view_force_static = false
dash.static_step()
t.ok("nor under the keypad",     stepped == 1)
t.ok("and holds the flag there", state.view_force_static)

--- the views read the touch point from the input layer ---
--
-- Copied rather than reached for, so view_pages does not depend on input and
-- can be driven by the host render harness.
instrument()
input.poll = function()
	input.touch_x, input.touch_y = 123, 234
	input.btn_hold_region = 2
	input.btn_hold_progress = 0.75
end

dash.tick()
t.ok("the touch point reached the view", vp.touch_x == 123 and vp.touch_y == 234)
t.ok("so did the hold region",           vp.btn_hold_region == 2)
t.near("and its progress",               vp.btn_hold_progress, 0.75)

--- the startup overlay phases ---
--
-- A list of phases driven from the tick: a gap, then the region overlay, with
-- the boot log before both when it is enabled. Driven through M.tick rather
-- than by calling the step directly, so the test covers the wiring -- which
-- is what catches a nil guard, the overlay being the only job dispatched from
-- outside the guarded list.
--
-- Nothing here sleeps. The boot log used to hold the main chunk for four
-- seconds with vesc.sleep, and because the engine task blocks there it
-- drained no events and refreshed no subscriptions: every packet arriving in
-- that window was dropped before it reached the queue. These phases exist so
-- the chunk returns promptly.
instrument()
dash.boot_log_s = 0.0
dash.region_overlay_s = 5.0
dash.region_overlay_delay_s = 1.0
dash.phases = nil
dash.phase_i = 0
dash.phase_until = 0.0

local drew = 0
dash.region_overlay = function() drew = drew + 1 end
dash.static_step = counter("static")
pages.step = counter("pages")

-- The boundaries are exact, so the counts are too. At 20 ms a tick the gap
-- ends on the tick whose time reaches 1.0 s, which is the 51st: the first
-- tick is at 0.02 s, not 0.
for _ = 1, 50 do dash.tick() end
t.ok("nothing drawn during the gap", drew == 0)
t.ok("and the views ran through it", (ran.static or 0) > 0)

local static_at_show = ran.static
dash.tick()
t.ok("drawn on the tick the gap ends", drew == 1)

-- Well inside the window: still one draw, views still down.
for _ = 1, 100 do dash.tick() end
t.ok("not redrawn every tick", drew == 1)
t.ok("the views stood down",   ran.static == static_at_show)
t.ok("pages too",              ran.pages == static_at_show)

-- Still inside just before the end. The draw landed on tick 51, so the window
-- closes on the first tick at or past 6.02 s, which is tick 301.
for _ = 1, 149 do dash.tick() end
t.ok("still one draw",   drew == 1)
t.ok("views still down", ran.static == static_at_show)

-- Past it: the repaint is forced, because the views' dirty tracking was
-- paused and has no idea what the overlay covered.
state.view_force_static = false
state.view_force_pages = false
dash.tick()
t.ok("a static repaint was forced", state.view_force_static)
t.ok("and a page repaint",          state.view_force_pages)

for _ = 1, 10 do dash.tick() end
t.ok("the views resumed", ran.static > static_at_show)

drew = 0
for _ = 1, 400 do dash.tick() end
t.ok("the phases are one-shot", drew == 0)

--- the boot log phase ---
--
-- Drawn once on entry and updated every tick while it is up, which is what
-- lets the touch probe under it follow a finger without the phase sleeping.
instrument()
dash.boot_log_s = 2.0
dash.region_overlay_s = 0.0
dash.phases = nil
dash.phase_i = 0
dash.phase_until = 0.0

local log_drawn, log_updates = 0, 0
dash.boot_log_splash = function() log_drawn = log_drawn + 1 end
dash.boot_log_probe = function() log_updates = log_updates + 1 end
dash.static_step = counter("static")
pages.step = counter("pages")

dash.tick()
t.ok("the boot log is drawn on the first tick", log_drawn == 1)
t.ok("and the views stand down immediately",    (ran.static or 0) == 0)

for _ = 1, 50 do dash.tick() end
t.ok("drawn once",          log_drawn == 1)
t.ok("and updated per tick", log_updates == 50)
t.ok("views still down",     (ran.static or 0) == 0)

-- 2.0 s is tick 100; past it the views take over.
for _ = 1, 60 do dash.tick() end
t.ok("the views resumed after the window", (ran.static or 0) > 0)
t.ok("and the log was not redrawn",        log_drawn == 1)

-- Both disabled: the views run from the very first tick, which is what a
-- dash being ridden should do.
instrument()
dash.boot_log_s = 0.0
dash.region_overlay_s = 0.0
dash.phases = nil
dash.phase_i = 0
dash.static_step = counter("static")
log_drawn, drew = 0, 0
dash.boot_log_splash = function() log_drawn = log_drawn + 1 end
dash.region_overlay = function() drew = drew + 1 end

-- Two ticks, not one: the static view runs on every second tick, so one tick
-- proves nothing about whether it was allowed to.
dash.tick()
dash.tick()
t.ok("no phases: the views run at once", (ran.static or 0) > 0)
for _ = 1, 400 do dash.tick() end
t.ok("and nothing overlays them", log_drawn == 0 and drew == 0)

t.unstrict_globals()

t.report("dash")
