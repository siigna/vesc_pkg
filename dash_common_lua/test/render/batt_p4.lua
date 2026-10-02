-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Battery page against its lisp reference. See run.sh.
-- Renders the ported trip page for the P4 profile against its lisp
-- reference. Same pinning as static_p4.lua, plus the values only this page
-- reads. See run.sh.
local state = require("lib.state")
local colors = require("lib.colors")
local units = require("lib.units")
local signals = require("lib.signals")
local mode = require("lib.mode")
local battery = require("lib.battery")
local config = require("lib.config")
local vs = require("lib.view_static")

vs.font_speed = vesc.font_load(vesc.asset("font120"))
vs.font_24 = vesc.font_load(vesc.asset("font24"))
vs.font_16 = vesc.font_load(vesc.asset("font18"))
vs.drive_mode_names = {"REVERSE", "NEUTRAL", "ECO", "NORMAL", "SPORT"}
vs.light_on_is_highbeam = false

vs.set_layout({
	disp_w = 800, disp_h = 480,
	strip_h = 58, speed_h = 145, page_h = 120, page_cols = 4, page_row_h = 44,
})

colors.bg = 0x000000
colors.accent = 0x00C8FF
colors.text = 0xfbfcfc
colors.theme = 0
colors.apply_status()
colors.build()

-- The ride the reference pins.
state.kmh = 42.0
state.battery_soc = 0.63
state.kw = 2.4
state.vin = 58.7
state.battery_a_connected = true
state.battery_a_charging = false
state.indicate_l_on = true
state.indicate_r_on = false
state.highbeam_on = true
state.light_on = true
state.cruise_control_active = true
state.cruise_control_speed = 40.0
state.kill_sw_active = false
state.fault_code = 0
state.page_now = 0
-- 8, not 3: the reference derives page_num from the page mask in
-- persistent-settings and lands on 8, and its nav strip reads "Page 1/8".
-- "8" and "3" have the same advance width, so the centring matched and only
-- that one glyph differed -- which is why the last 32 pixels looked like a
-- rasteriser problem and were a pinned constant.
state.page_num = 8
mode.current = 3

config.soc_source = "esc"
units.speeds = "kmh"

-- Pinned on, as the reference pins it: the blink phase would otherwise depend
-- on when the render happened.
vs.blink_on = function() return true end

-- Reporting, which is what the reference does: sig_rx_last is zero and the
-- repl's clock is near enough zero that secs_since(0) is inside the timeout,
-- so the indicators show what the node reports rather than this display's own
-- request. Worth pinning explicitly instead of inheriting a clock.
signals.rx_last = 0
signals.secs_since = function() return 0.0 end

local vp = require("lib.view_pages")
vp.font_24 = vs.font_24
vp.font_16 = vs.font_16
vp.set_layout(vs.layout)

-- The ride the reference pins, for whichever page reads it.
state.km = 18.4
state.odom = 1243.0
state.wh = 214.0
state.wh_chg = 12.0
state.battery_ah = 20.0
state.duty = 0.37
state.kmh_max = 58.0
state.kw_max = 6.1
state.amps_now_max = 88.0
state.amps_max = 92.0
state.temp_esc_max = 52.0
state.temp_motor_max = 71.0
state.temp_battery_max = 31.0

-- The BMS getter, with the same values render_pages.lisp supplies. Not zeros:
-- the harness overrides its own stub with a plausible pack so the page shows
-- something, and a render against zeros compares a different picture.
--
-- render_host does not register the real BMS bindings, since they read
-- firmware state with no host equivalent.
local bms_cells = {}
for i = 0, 19 do
	bms_cells[i + 1] = (i == 7) and 3.61 or (3.92 + 0.004 * (i % 5))
end

vesc.bms_val = function(name, idx)
	if name == "cell_num" then return 20 end
	if name == "v_cell" then return bms_cells[idx + 1] end
	if name == "bal_state" then return idx == 3 end
	if name == "v_tot" then return 78.4 end
	if name == "v_cell_min" then return 3.61 end
	if name == "v_cell_max" then return 3.94 end
	if name == "i_in_ic" then return 12.3 end
	if name == "ah_cnt" then return 4.25 end
	if name == "temp_cell_max" then return 29.0 end
	if name == "hum" then return 41.0 end
	return 0.0
end

vs.reset()
vs.frame()
vs.step()

state.page_now = 3
vp.page_batt(true)
vp.page_batt(false)
vs.step()

print("lua batt rendered")
