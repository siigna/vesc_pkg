-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Controller settings page against its lisp reference. See run.sh.
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

-- The controller mirror, as the reference pins it: every row reported, parked
-- on a gated row with the kill switch off. That is the case with an
-- appearance of its own -- gated rows read dim and marked while the motor is
-- not being held, which is what says the press would be refused before
-- making it.
local cc = require("lib.controller_conf")
local vals = {2.0, 0.35, 22.0, 25.0, 250.0, 1.0, 1.0, 4.0, 18.0, 0.30, 0.25, 1.5, 70.0}
state.conf_count = 13
for i = 0, 12 do
	state.conf_seen[i + 1] = true
	state.conf_vals[i + 1] = vals[i + 1]
	state.conf_gated[i + 1] = cc.row(i)[5] and 1 or 0
end
cc.now = 8
state.kill_sw_active = false

vs.reset()
vs.frame()
vs.step()

state.page_now = 6
vp.page_conf(true)
vp.page_conf(false)
vs.step()

print("lua conf rendered")
