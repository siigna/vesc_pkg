-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Unit tests for lib/actions.lua: the stored action ids, the per-page claims
-- on a press, and the two held actions.
--
-- Ported from btn-do-action, btn-short, btn-long and the chart source
-- selection in dash_common/main_body.lisp, none of which has a test.
--
-- The claim order is the part worth pinning hardest. Every claim exists
-- because something must not fall through to a stored action, and the worst
-- case is the keypad: a region bound to paging that reached do_action would
-- walk straight off a lock that is holding the bike in neutral.
vesc = require("test.vesc_stub")
vesc.disp_clear = function() end

-- Frames go into a list instead of onto a bus.
local sent = {}
vesc.can_send_sid = function(id, data) sent[#sent + 1] = {id, data} end

local t = require("test.harness")
local state = require("lib.state")
local settings = require("lib.settings")
local units = require("lib.units")
local colors = require("lib.colors")
local mode = require("lib.mode")
local signals = require("lib.signals")
local pin = require("lib.pin")
local conf = require("lib.controller_conf")
local stats = require("lib.statistics")
local notify = require("lib.notify")
local input = require("lib.input")
local vs = require("lib.view_static")
local vp = require("lib.view_pages")
local pages = require("lib.pages")
local apply = require("lib.apply")
local actions = require("lib.actions")

local cfg = {
	metric_speeds = true, metric_temps = true,
	battery_hot = 55.0, esc_hot = 80.0, motor_hot = 80.0,
	bl_bright = 1.0, bl_dim = 0.25,
	btn_actions_short = {3, 2, 1, 6},
	btn_actions_long = {0, 12, 0, 8},
}

-- The P4 profile, so nav_y and both cell grids are real numbers.
local L = vs.set_layout({
	disp_w = 800, disp_h = 480, strip_h = 56, speed_h = 120,
	page_h = 150, page_cols = 4, page_row_h = 40,
})
vp.set_layout(L)
input.set_layout(L)
notify.layout = L

actions.cfg = cfg

-- Nothing here draws, so the pages are never called; only their identity
-- matters, which is what pages.current() compares.
-- Button actions are written to eeprom rather than poked into
-- settings.values, because anything that writes a setting reloads them all --
-- setting_update does, which quietly undid a value poked in afterwards.
local function setup(mask, short, long)
	vesc.eeprom = {}
	apply.restore(cfg)
	settings.write("page_mask", mask or 0xFF)
	for i = 0, 3 do
		if short then settings.write("btn" .. i .. "_short", short[i + 1]) end
		if long then settings.write("btn" .. i .. "_long", long[i + 1]) end
	end
	apply.all(cfg)
	actions.bind()
	actions.bl_set = nil
	state.page_now = 0
	state.kmh = 0.0
	signals.req = 0
	notify.txt = nil
	sent = {}
	input.btn_hold_region = nil
	input.btn_hold_progress = 0.0
	input.touch_x, input.touch_y = 0, 0
end

--- paging ---
setup()
t.ok("eight pages enabled", state.page_num == 8)

actions.do_action(1)
t.ok("action 1 is page +", state.page_now == 1)
actions.do_action(2)
t.ok("action 2 is page -", state.page_now == 0)
actions.do_action(2)
t.ok("and wraps backwards into the rotation",
	state.page_now == state.page_num - 1)

actions.do_action(3)
t.ok("action 3 opens settings", state.page_now == state.page_num)
actions.do_action(3)
t.ok("and closes it",           state.page_now == 0)

actions.do_action(16)
t.ok("action 16 opens the shade", pages.shade_showing())
actions.do_action(16)
t.ok("and closes it",             state.page_now == 0)

--- drive mode ---
setup()
mode.num = 5
mode.current = 2
mode.cmd_ts = 0

actions.do_action(4)
t.ok("action 4 is mode +", mode.current == 3)
actions.do_action(5)
t.ok("action 5 is mode -", mode.current == 2)

mode.current = mode.num - 1
actions.do_action(4)
t.ok("mode + stops at the top", mode.current == mode.num - 1)

mode.current = 0
actions.do_action(5)
t.ok("mode - stops at reverse", mode.current == 0)

--- lights, cruise, logging ---
setup()
state.light_on = false
actions.do_action(6)
t.ok("action 6 turns the lights on",  state.light_on)
actions.do_action(6)
t.ok("and off again",                 not state.light_on)

actions.do_action(8)
t.ok("action 8 sends one frame",      #sent == 1)
t.ok("on SID 250",                    sent[1][1] == 250)
t.ok("event 0, which is cruise",      string.byte(sent[1][2], 1) == 0)

sent = {}
actions.do_action(9)
t.ok("action 9 is event 2, logging",  string.byte(sent[1][2], 1) == 2)

--- the backlight ---
--
-- A no-op without a bl_set, which is the lisp's behaviour on the dashes this
-- came from. Those panels have no backlight control, so the action is
-- accepted and ignored rather than renumbered -- renumbering would change
-- what every stored setting means. This board does have control.
setup()
state.backlight_dim = false
actions.do_action(7)
t.ok("no bl_set: nothing happens", not state.backlight_dim)

local bl = nil
actions.bl_set = function(l) bl = l end
actions.do_action(7)
t.ok("with one: dimmed",       state.backlight_dim)
t.near("and the level applied", bl, settings.values.bl_dim)
actions.do_action(7)
t.ok("and back to bright",     not state.backlight_dim)
t.near("at the bright level",   bl, settings.values.bl_bright)

--- the session reset ---
setup()
stats.reset_now = false
actions.do_action(12)
t.ok("action 12 requests a reset", stats.reset_now)

--- signals ---
setup()
actions.do_action(18)
t.ok("action 18 asks for left", signals.on(signals.LEFT))
actions.do_action(19)
t.ok("19 asks for right",       signals.on(signals.RIGHT))
t.ok("and cancels left",        not signals.on(signals.LEFT))
actions.do_action(17)
t.ok("17 is the hazard",        signals.on(signals.HAZARD))

signals.horn_ts = 0
actions.do_action(21)
t.ok("21 blips the horn", signals.horn_blipping())

--- the lock ---
--
-- Refused while moving: the display asserts neutral while locked, and taking
-- the drive away mid-ride is not something a mis-tap should be able to do.
setup()
pin.locked = false
state.kmh = 12.0
actions.do_action(22)
t.ok("moving: the lock is refused", not pin.locked)
t.ok("and says why",                notify.txt == "Stop first")

notify.txt = nil
state.kmh = 0.4
actions.do_action(22)
t.ok("below walking pace it engages", pin.locked)
t.ok("with no message",               notify.txt == nil)

-- Reverse is a negative speed, and the guard is on the magnitude.
setup()
pin.locked = false
state.kmh = -12.0
actions.do_action(22)
t.ok("reversing is also refused", not pin.locked)

--- held actions ---
--
-- Walk assist and the horn are not edges. The controller expires a walk
-- request after half a second and a horn is momentary, so both are read from
-- the button currently down.
setup(nil, nil, {13, 21, 0, 0})

t.ok("nothing held: no walk", not actions.walk_requested())
t.ok("nor horn",              not actions.horn_held())

input.btn_hold_region = 0
input.btn_hold_progress = 0.5
t.ok("a half-filled hold is not yet a walk request",
	not actions.walk_requested())

input.btn_hold_progress = 1.0
t.ok("a full hold on region 0 is",      actions.walk_requested())
t.ok("and is not the horn",             not actions.horn_held())

input.btn_hold_region = 1
t.ok("a full hold on region 1 is the horn", actions.horn_held())
t.ok("and not a walk request",              not actions.walk_requested())

input.btn_hold_region = 2
t.ok("a region bound to neither is neither",
	not actions.walk_requested() and not actions.horn_held())

-- Releasing clears the region, which stops the request on the next frame.
input.btn_hold_region = nil
t.ok("release stops the walk request", not actions.walk_requested())

--- the chart ---
setup()
settings.write("slot_0", 0) settings.write("slot_1", 5)
settings.write("slot_2", 5) settings.write("slot_3", 12)
apply.all(cfg)

local srcs = actions.chart_sources()
t.ok("sources are the live slots without duplicates", #srcs == 3)
t.ok("in cell order", srcs[1] == 0 and srcs[2] == 5 and srcs[3] == 12)

-- Pointing the chart somewhere clears the ring: what is in it is a history of
-- the old source. The lisp defines chart-reset for this and never calls it,
-- so there a source change leaves up to ten seconds of the previous signal
-- plotted against the new one's axis.
stats.chart_reset()
stats.chart_push(42.0)
t.ok("the ring has a sample", stats.chart_count == 1)

actions.chart_set_src(5)
t.ok("the view got the source",     vp.chart_src == 5)
t.ok("so did the sampler",          stats.chart_src == 5)
t.ok("the ring was cleared",        stats.chart_count == 0)
t.ok("it was written through",      settings.read("chart_src") == 5)
t.ok("and the page is the chart",   pages.current() == vp.page_chart)
t.ok("with a message naming it",    notify.txt == "Charting " .. stats.slot_label(5))

-- Stepping walks the live slots and stays put.
local pg = state.page_now
actions.chart_step(1)
t.ok("step forward",      vp.chart_src == 12)
t.ok("and stays on the page", state.page_now == pg)
actions.chart_step(1)
t.ok("and wraps",         vp.chart_src == 0)
actions.chart_step(-1)
t.ok("step back wraps the other way", vp.chart_src == 12)

-- A source that is not in the live slots at all steps from the first.
actions.chart_point_at(29)
actions.chart_step(1)
t.ok("an off-list source steps from the start", vp.chart_src == 5)

-- The window toggles between the two the setting allows.
t.ok("ten seconds to start", vp.chart_secs == 10)
actions.chart_step_secs()
t.ok("stepped to five",      vp.chart_secs == 5)
t.ok("written through",      settings.read("chart_secs") == 5)
actions.chart_step_secs()
t.ok("and back to ten",      vp.chart_secs == 10)

-- With the chart page masked off, setting a source is refused rather than
-- pointing at a page nothing will draw.
setup(0xF)
t.ok("the chart page is off", pages.index_of(vp.page_chart) == nil)
local before = vp.chart_src
actions.chart_set_src(9)
t.ok("the source is unchanged", vp.chart_src == before)
t.ok("and it says so",          notify.txt == "Chart page off")

--- the settings page spinner ---
setup()
settings.write("setting_mask", 0x3)     -- two rows: whl_active, whl_start
apply.all(cfg)
state.page_now = state.page_num
vp.setting_now = 0

t.ok("two rows",            state.setting_num == 2)
t.ok("row 0 is whl_active", vp.setting_list[1] == "whl_active")

actions.setting_update(1)
t.ok("stepped up", settings.read("whl_active") == 1)
actions.setting_update(1)
t.ok("and clamps at its maximum", settings.read("whl_active") == 1)
actions.setting_update(-1)
t.ok("stepped down", settings.read("whl_active") == 0)
actions.setting_update(-1)
t.ok("and clamps at its minimum", settings.read("whl_active") == 0)

actions.setting_next()
t.ok("the selection moves", vp.setting_now == 1)
actions.setting_update(1)
t.near("and steps the new row by its own step",
	settings.read("whl_start"), 20.5)
actions.setting_next()
t.ok("and wraps", vp.setting_now == 0)

-- The theme is the one setting that needs the full repaint, because the
-- palettes are baked into the buffers already on screen. The rest must not
-- trigger it, or a held spinner would repaint the panel per step.
setup()
settings.write("setting_mask", 1 << 11) -- theme only
apply.all(cfg)
state.page_now = state.page_num
vp.setting_now = 0
state.settings_redraw = false
t.ok("the row is the theme", vp.setting_list[1] == "theme")

actions.setting_update(1)
t.ok("a theme step asks for a repaint", state.settings_redraw)
t.ok("and moved the theme",             settings.read("theme") == 1)

setup()
settings.write("setting_mask", 0x3)
apply.all(cfg)
state.page_now = state.page_num
state.settings_redraw = false
actions.setting_update(1)
t.ok("another setting does not", not state.settings_redraw)

-- No rows at all: the spinner must not index off an empty list.
setup()
state.setting_num = 0
actions.setting_update(1)
actions.setting_next()
t.ok("no rows is not an error", state.setting_num == 0)

--- the controller settings page ---
setup()
conf.now = 0
state.conf_seen = {}
state.conf_vals = {}
state.kill_sw_active = true
notify.txt = nil
sent = {}

actions.conf_nudge(1.0)
t.ok("an unreported value sends nothing", #sent == 0)
t.ok("and says it is waiting", notify.txt == "Waiting for controller")

-- Reported now.
local row = conf.row(0)
state.conf_seen[row[1] + 1] = true
state.conf_vals[row[1] + 1] = 10.0
notify.txt = nil

actions.conf_nudge(1.0)
t.ok("a reported value sends a frame", #sent == 1)
t.ok("on SID 205",                     sent[1][1] == 205)
t.ok("with no message",                notify.txt == nil)

-- A gated row needs the kill switch, and the dash says so rather than letting
-- the controller refuse it silently.
local gated = nil
for i = 0, conf.menu_len() - 1 do
	if conf.row(i)[5] then gated = i end
end
if gated then
	conf.now = gated
	local id = conf.row(gated)[1]
	state.conf_seen[id + 1] = true
	state.conf_vals[id + 1] = 1.0
	state.kill_sw_active = false
	sent = {}
	notify.txt = nil

	actions.conf_nudge(1.0)
	t.ok("a gated row with the switch off sends nothing", #sent == 0)
	t.ok("and says why", notify.txt == "Kill switch off")
end

conf.now = 0
actions.conf_next()
t.ok("the selection moves", conf.now == 1)
conf.now = conf.menu_len() - 1
actions.conf_next()
t.ok("and wraps",           conf.now == 0)

--- press dispatch: the claim order ---
--
-- Every one of these claims exists because something must not fall through to
-- a stored action.
local PAGES = {1, 1, 1, 1}                 -- every region pages
setup(nil, PAGES)

-- The keypad claims everything. A region bound to paging that reached
-- do_action would walk straight off a lock holding the bike in neutral.
state.page_now = state.page_num + 2
t.ok("the keypad is up", pages.pin_showing())
pin.clear()
input.touch_x, input.touch_y = 10, 100     -- over a key

actions.short(0)
t.ok("the page did not move", pages.pin_showing())
t.ok("and the key was taken",  pin.entry_len == 1)

-- A press outside the keypad grid still does not page.
input.touch_x, input.touch_y = 10, 470     -- in the nav strip, below the keys
actions.short(0)
t.ok("a press off the grid still does not page", pages.pin_showing())

-- And a long press does nothing at all while locked.
settings.write("btn0_long", 1)
settings.load(cfg)
actions.long(0)
t.ok("no long action while locked", pages.pin_showing())

-- The shade claims presses above the nav strip, by position rather than by
-- region. Below the strip the regions keep their own actions, so there is a
-- way off the shade without the gesture.
setup(nil, PAGES)
state.page_now = state.page_num + 1
state.light_on = false
vp.shade_slots = {6, 0, 0, 0, 0, 0}        -- cell 0 is lights

input.touch_x, input.touch_y = 10, 10      -- shade cell 0
actions.short(1)
t.ok("the shade ran its own cell", state.light_on)
t.ok("and did not page",           pages.shade_showing())

-- An empty cell does nothing rather than falling through.
input.touch_x, input.touch_y = 300, 10     -- cell 1, action 0
actions.short(1)
t.ok("an empty shade cell is inert", pages.shade_showing())

-- Below the strip the region's own action runs.
input.touch_x, input.touch_y = 10, 470
actions.short(0)
t.ok("below the strip the region pages", not pages.shade_showing())

--- the settings page claim ---
setup(nil, PAGES)
settings.write("setting_mask", 0x3)
apply.all(cfg)
state.page_now = state.page_num
vp.setting_now = 0

actions.short(0)
t.ok("region 0 scrolls rather than paging", vp.setting_now == 1)
t.ok("and the page did not move",           state.page_now == state.page_num)

vp.setting_now = 0
actions.short(2)
t.ok("region 2 steps the value up", settings.read("whl_active") == 1)

actions.short(3)
t.ok("region 3 falls through to its action", state.page_now ~= state.page_num)

--- the chart page claim ---
setup(nil, PAGES)
state.page_now = pages.index_of(vp.page_chart)
actions.chart_point_at(vp.slots[1])

input.touch_y = 10                          -- above the nav strip
actions.short(1)
t.ok("region 1 steps the source backwards", vp.chart_src ~= vp.slots[1])
t.ok("and stays on the chart", pages.current() == vp.page_chart)

-- The strip is region 1 and 2 as well, and claiming it would leave no way to
-- page off the chart.
input.touch_y = 470
local src = vp.chart_src
actions.short(2)
t.ok("a press in the strip pages instead", pages.current() ~= vp.page_chart)
t.ok("and left the source alone",          vp.chart_src == src)

--- the conf page claim ---
setup(nil, PAGES)
state.page_now = pages.index_of(vp.page_conf)
conf.now = 0

actions.short(0)
t.ok("region 0 scrolls the conf menu", conf.now == 1)
t.ok("and does not page",              pages.current() == vp.page_conf)

actions.short(3)
t.ok("region 3 falls through", pages.current() ~= vp.page_conf)

--- long presses ---
setup(nil, nil, {0, 12, 0, 0})

-- On the live page a hold over a cell charts that cell.
state.page_now = pages.index_of(vp.page_live)
input.touch_x, input.touch_y = 10, L.page_y + 10
local cell = vp.live_geom.hit(input.touch_x, input.touch_y)
t.ok("the press is over a live cell", cell ~= nil)

actions.long(1)
t.ok("the hold charted that cell",  vp.chart_src == vp.slots[cell + 1])
t.ok("and went to the chart page",  pages.current() == vp.page_chart)

-- A hold outside the grid falls through to the stored action, so the session
-- reset on a held region still works everywhere except over a cell.
setup(nil, nil, {0, 12, 0, 0})
state.page_now = pages.index_of(vp.page_live)
input.touch_x, input.touch_y = 10, 470      -- the nav strip, outside the grid
t.ok("not over a cell", vp.live_geom.hit(input.touch_x, input.touch_y) == nil)
stats.reset_now = false
actions.long(1)
t.ok("the stored action ran", stats.reset_now)

-- Walk assist and the horn are never claimed: both read the held state
-- directly, so claiming the region would leave the request running while the
-- chart page opened.
setup()
settings.write("btn1_long", 13)
settings.load(cfg)
state.page_now = pages.index_of(vp.page_live)
input.touch_x, input.touch_y = 10, L.page_y + 10
local was = vp.chart_src
actions.long(1)
t.ok("a walk-bound region is not claimed by a live cell", vp.chart_src == was)
t.ok("and stays on the live page", pages.current() == vp.page_live)

settings.write("btn1_long", 21)
settings.load(cfg)
actions.long(1)
t.ok("nor a horn-bound one", vp.chart_src == was)

-- On the chart page a hold above the strip toggles the window.
setup(nil, nil, {0, 12, 0, 0})
state.page_now = pages.index_of(vp.page_chart)
input.touch_y = 10
t.ok("ten seconds", vp.chart_secs == 10)
actions.long(1)
t.ok("the hold toggled the window", vp.chart_secs == 5)

-- In the strip it falls through to the stored action instead.
input.touch_y = 470
stats.reset_now = false
actions.long(1)
t.ok("a hold in the strip runs the action", stats.reset_now)
t.ok("and left the window alone",           vp.chart_secs == 5)

--- gestures ---
setup()
state.page_now = 2
actions.swipe_down()
t.ok("a swipe down opens the shade", pages.shade_showing())

-- Not from on top of an overlay: the shade is already up, and the keypad must
-- not be swiped away.
actions.swipe_down()
t.ok("and does not toggle it back", pages.shade_showing())

actions.swipe_up()
t.ok("a swipe up closes it", state.page_now == 0)

state.page_now = state.page_num + 2
actions.swipe_down()
t.ok("the keypad ignores a swipe down", pages.pin_showing())
actions.swipe_up()
t.ok("and a swipe up",                  pages.pin_showing())

--- binding ---
setup(nil, PAGES)
state.page_now = 0

-- The input layer dispatches through the handlers bind() installed, which is
-- the seam between the two modules.
input.step(10, 470)
input.step(nil, nil)
t.ok("a tap through the input layer paged", state.page_now == 1)

-- Repeats only exist on the settings page, where they scroll a value;
-- elsewhere they would fire a page change over and over.
state.page_now = 3
input.on_repeat_press[1]()
t.ok("a repeat off the settings page does nothing", state.page_now == 3)

t.report("actions")
