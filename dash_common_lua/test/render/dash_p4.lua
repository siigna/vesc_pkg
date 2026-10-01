-- The whole dash, every page, against the goldens dash_common/test ships.
--
-- A port of dash_common/test/render_pages.lisp rather than of one view: it
-- walks the real settings path, the real page set and the real static strip,
-- and saves each frame the way the lisp harness calls save-active-img in a
-- loop. So where the per-view cases in this directory each pin a dozen
-- globals by hand, this pins the same ride once and lets apply.all and
-- pages.apply_mask put it where it belongs -- which is the half the per-view
-- comparisons cannot check.
--
-- Everything pinned is pinned because it would otherwise come from a clock or
-- from hardware. A golden that depends on either is not a golden.

--- host bindings the renderer does not provide ---
--
-- render_host registers the drawing bindings and nothing else: there is no
-- eeprom, no clock and no CAN on a desktop. They are supplied here rather
-- than in C because this is the only caller that wants them, and test
-- harnesses are where a fake belongs.

-- A clock that does not move. The lisp harness gets the same effect from the
-- repl's clock being near zero, which is luck rather than a decision.
local NOW = 0
vesc.systime = function() return NOW end
vesc.secs_since = function(t) return (NOW - t) / 1000.0 end
vesc.sleep = function() end
vesc.set_print_prefix = function() end

-- Enough eeprom for the whole address map. An unwritten cell reads nil, which
-- is what hardware does and what the guards have to survive.
local cells = {}
vesc.eeprom_read_i = function(a)
	local v = cells[a]
	return v and math.floor(v) or nil
end
vesc.eeprom_read_f = function(a) return cells[a] end
vesc.eeprom_store_i = function(a, v) cells[a] = math.floor(v) return true end
vesc.eeprom_store_f = function(a, v) cells[a] = v return true end

-- Frames go nowhere. Nothing here sends any, but a page that did would
-- otherwise take the render down.
vesc.can_send_sid = function() end

local state = require("lib.state")
local settings = require("lib.settings")
local apply = require("lib.apply")
local colors = require("lib.colors")
local units = require("lib.units")
local signals = require("lib.signals")
local mode = require("lib.mode")
local stats = require("lib.statistics")
local conf = require("lib.controller_conf")
local pin = require("lib.pin")
local vs = require("lib.view_static")
local vp = require("lib.view_pages")
local pages = require("lib.pages")

--- the board ---

local cfg = {
	disp_w = 800, disp_h = 480,
	strip_h = 58, speed_h = 145, page_h = 120,
	page_cols = 4, page_row_h = 44,

	metric_speeds = true, metric_temps = true,
	battery_hot = 55.0, esc_hot = 80.0, motor_hot = 80.0,
	bl_bright = 1.0, bl_dim = 0.25,
	btn_actions_short = {3, 2, 1, 6},
	btn_actions_long = {0, 12, 0, 8},

	battery_cells = 12, battery_ah = 20.0, battery_usable = 0.85,
	discharge_ticks = {3.30, 3.60, 3.68, 3.73, 3.77, 3.81, 3.85, 3.90, 4.00, 4.20},
	soc_voltage_weight = 0.4,
	soc_source = "esc",
}

local shared = require("lib.config")
for k, v in pairs(cfg) do shared[k] = v end

local L = vs.set_layout(cfg)
vp.set_layout(L)

vs.font_speed = vesc.font_load(vesc.asset("font120"))
vs.font_24 = vesc.font_load(vesc.asset("font24"))
vs.font_16 = vesc.font_load(vesc.asset("font18"))
vs.drive_mode_names = {"REVERSE", "NEUTRAL", "ECO", "NORMAL", "SPORT"}
vs.light_on_is_highbeam = false
vs.overlay_showing = pages.overlay_showing

vp.font_40 = vesc.font_load(vesc.asset("font40"))
vp.font_24 = vs.font_24
vp.font_16 = vs.font_16

apply.bl_set = function() end

apply.restore(cfg)
apply.all(cfg)

--- what would otherwise come from a clock ---

-- The blink phase is derived from how long ago the indicator came on, which
-- would make the turn signal pill land on or off depending on when the render
-- happened. Its arithmetic has its own test.
vs.blink_on = function() return true end

-- The strip shows what a bike-controls node reports and falls back to what
-- this display asked for when none is on the bus. Pinned reporting; the
-- fallback gets its own render further down.
signals.reported = function() return true end

-- The session page's first field is uptime. Pin that one element and leave
-- the rest of the page live, rather than dropping the page.
local session_state_live = vp.session_state
vp.session_state = function()
	local s = session_state_live()
	s[1] = 4321
	return s
end

--- a plausible ride, so nothing renders as a screen of zeroes ---

state.kmh = 42.0
state.battery_soc = 0.63
state.kw = 2.4
state.vin = 58.7
state.amps_now = 31.0
state.km = 18.4
state.odom = 1243.0
state.wh = 214.0
state.wh_chg = 12.0
state.battery_ah = 20.0
state.duty = 0.37
state.temp_esc = 44.0
state.temp_motor = 61.0
state.temp_battery = 28.0
state.kmh_max = 58.0
state.kw_max = 6.1
state.amps_now_max = 88.0
state.amps_max = 92.0
state.temp_esc_max = 52.0
state.temp_motor_max = 71.0
state.temp_battery_max = 31.0
state.indicate_l_on = true
state.highbeam_on = true
state.light_on = true
state.cruise_control_active = true
state.cruise_control_speed = 40.0
state.kill_sw_active = false
mode.current = 3

-- The PAS page is off in the default mask, since most vehicles have no
-- pedals, so every page is enabled in order to render it. Before the strip is
-- drawn: the strip shows one dot per page, so changing the count afterwards
-- would alter it part way through and every page captured after that point
-- would differ.
--
-- Stored rather than assigned, because the theme change further down reloads
-- the settings and a mask that only existed in a field would be lost there.
-- 0xFF, not every bit: the goldens were rendered from the lisp dash, whose
-- catalog is the first eight pages. The boot log is bit 8 and has no lisp
-- counterpart, so enabling it would shift the settings page, the shade and
-- the keypad by one and make eleven of the fifteen comparisons meaningless.
-- Leaving it off is also the check that adding a page disturbed none of the
-- others.
settings.write("page_mask", 0xFF)
apply.all(cfg)

-- The chart plots what has been sampled, so fill the ring rather than waiting
-- on the sampler. A fixed shape -- rise, plateau, fall -- which also
-- exercises the autoscaling at both ends.
stats.chart_reset()
for i = 0, 99 do
	local v
	if i < 30 then v = 0.08 * i
	elseif i < 60 then v = 2.4
	else v = 2.4 - 0.05 * (i - 60) end
	stats.chart_push(v)
end

-- Controller settings, as if the mirror had arrived. Parked on a gated row
-- with the kill switch off, which is the case with an appearance of its own:
-- a gated row reads dim and marked while the motor is not held, saying the
-- press would be refused before making it.
local CONF_VALS = {2.0, 0.35, 22.0, 25.0, 250.0, 1.0, 1.0, 4.0, 18.0,
	0.30, 0.25, 1.5, 70.0}
state.conf_count = 13
state.conf_seen = {}
state.conf_vals = {}
state.conf_gated = {}
for i = 0, 12 do
	state.conf_seen[i + 1] = true
	state.conf_vals[i + 1] = CONF_VALS[i + 1]
	state.conf_gated[i + 1] = conf.row(i)[5] and true or false
end
conf.now = 8

-- A 20S pack with one cell down, which is the case the aggregates on the
-- battery page cannot show and the cells page exists for.
state.battery_a_connected = true
local bms_cells = {}
for i = 0, 19 do
	bms_cells[i + 1] = (i == 7) and 3.61 or (3.92 + 0.004 * (i % 5))
end

vesc.bms_val = function(name, arg)
	if name == "cell_num" then return 20 end
	if name == "v_cell" then return bms_cells[arg + 1] end
	if name == "bal_state" then return arg == 3 end
	if name == "v_tot" then return 78.4 end
	if name == "v_cell_min" then return 3.61 end
	if name == "v_cell_max" then return 3.94 end
	if name == "i_in_ic" then return 12.3 end
	if name == "ah_cnt" then return 4.25 end
	if name == "temp_cell_max" then return 29.0 end
	if name == "hum" then return 41.0 end
	return 0.0
end

-- PAS, so the page shows something rather than zeros.
state.pas_rx = true
state.pas_cadence = 68.0
state.pas_torque = 21.5
state.pas_rider_w = 153
state.pas_assist_w = 298
state.pas_output = 0.42
state.pas_flags = 0

--- every page ---
--
-- Stepped rather than driven by the timer, so a changed field is always
-- painted before the frame is captured. With the tick running alongside that
-- would be a race, and a golden that depends on one is worse than no golden.

-- Where the frames go. A constant, because the firmware's Lua has no os
-- library: the sandbox drops it, and this script has to run under the same
-- interpreter the board does or it would not be testing the same thing.
-- run.sh creates the directory.
local OUT = "/tmp/dash_e2e"

vs.reset()
vs.frame()
vs.step()

for p = 0, #pages.pages - 1 do
	state.page_now = p
	local pg = pages.at(p)
	pg(true)
	pg(false)
	if pages.overlay_showing() then
		state.view_force_static = true
	else
		vs.step()
	end
	vesc.save_frame(string.format("%s/p4_page%d.ppm", OUT, p))
end

--- the live page with a hold over cell 1 ---
--
-- What the long press that charts that cell looks like. Pinned rather than
-- timed: the fraction normally comes from the input layer.
state.page_now = 0
vp.touch_x = vp.live_geom.cell_x(1) + 10
vp.touch_y = vp.live_geom.cell_y(1) + 30
vp.btn_hold_region = 1
vp.btn_hold_progress = 0.7
vp.page_live(true)
vp.page_live(false)
vesc.save_frame(OUT .. "/p4_live_hold.ppm")

print("hold cell", vp.live_geom.hit(vp.touch_x, vp.touch_y))

--- the strip with no bike-controls node on the bus ---
--
-- What a bike whose display is the only thing asking looks like: the
-- indicators and the beam show the request rather than a reported state,
-- which is the fallback the pinned reporting above hides.
signals.reported = function() return false end
signals.req = signals.HAZARD | signals.BEAM
state.view_force_static = true
vs.frame()
vs.step()
vesc.save_frame(OUT .. "/p4_sig_request.ppm")

signals.reported = function() return true end
signals.req = 0
state.view_force_static = true
vs.frame()
vs.step()

--- the live page under the Light theme ---
--
-- The only row with a pale background, so the one that would expose anything
-- still assuming a black one. Every palette is built against colors.bg, so
-- this is the check that nothing draws a literal colour behind the code's
-- back. Through the write-and-reload path rather than a hand-built palette.
vp.btn_hold_region = nil
vp.btn_hold_progress = 0.0

settings.write("theme", 4)
apply.all(cfg)
apply.visual()
vs.frame()
vs.step()
vp.page_live(true)
vp.page_live(false)
vesc.save_frame(OUT .. "/p4_theme_light.ppm")

--- one live page with a different colour rule in each cell ---
--
-- Back to Dark, then ramp, heat, low-warn and sign side by side, so every
-- branch of slot_colors is drawn. The ranges are picked so the seeded values
-- land in different parts of each, or three of the four would come out the
-- same green.
settings.write("theme", 0)
local MAXS = {40.0, 80.0, 100.0, 50.0}
for i = 0, 3 do
	settings.write("slot_mode_" .. i, i + 1)
	settings.write("slot_min_" .. i, 0.0)
	settings.write("slot_max_" .. i, MAXS[i + 1])
end
-- Cell 3 is the sign rule, so point it at power, which is negative below.
settings.write("slot_3", 4)
apply.all(cfg)
state.kw = -1.8
apply.visual()
vs.frame()
vs.step()
vp.page_live(true)
vp.page_live(false)
vesc.save_frame(OUT .. "/p4_slot_rules.ppm")

print("pages", #pages.pages, "page_num", state.page_num)
