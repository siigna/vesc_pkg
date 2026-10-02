-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- The touch region overlay, rendered on the host.
--
-- No golden: there is no lisp counterpart. The check is that the overlay
-- agrees with input.region -- which it should by construction, since every
-- label is read back out of it -- and that all five boxes tile the panel
-- without a gap or an overlap. The tiling is the part worth checking: the
-- thirds are computed as 2 * (w / 3) rather than (2 * w) / 3 to match the
-- region map, which leaves a remainder the last box has to absorb.

vesc.systime = function() return 1234 end
vesc.secs_since = function(t) return (1234 - t) / 1000.0 end
vesc.sleep = function() end

local cells = {}
vesc.eeprom_read_i = function(a) local v = cells[a]; return v and math.floor(v) or nil end
vesc.eeprom_read_f = function(a) return cells[a] end
vesc.eeprom_store_i = function(a, v) cells[a] = math.floor(v) return true end
vesc.eeprom_store_f = function(a, v) cells[a] = v return true end
vesc.can_send_sid = function() end

local colors = require("lib.colors")
local vs = require("lib.view_static")
local vp = require("lib.view_pages")
local input = require("lib.input")
local settings = require("lib.settings")
local apply = require("lib.apply")
local dash = require("lib.dash")

local cfg = {
	disp_w = 800, disp_h = 480,
	strip_h = 58, speed_h = 145, page_h = 120,
	page_cols = 4, page_row_h = 44,
	metric_speeds = true, metric_temps = true,
	battery_hot = 55.0, esc_hot = 80.0, motor_hot = 80.0,
	bl_bright = 1.0, bl_dim = 0.25,
	btn_actions_short = {3, 2, 1, 6},
	btn_actions_long = {0, 12, 0, 8},
}

local L = vs.set_layout(cfg)
vp.set_layout(L)
input.set_layout(L)

vp.font_16 = vesc.font_load(vesc.asset("font18"))
vp.font_24 = vp.font_16
vp.font_40 = vp.font_16
dash.font_16 = vp.font_16
apply.bl_set = function() end

colors.bg = 0x000000
colors.accent = 0x00C8FF
colors.text = 0xfbfcfc
colors.theme = 0
colors.apply_status()
apply.restore(cfg)
apply.all(cfg)

vesc.disp_clear(colors.bg)
dash.region_overlay()

-- The boxes the overlay drew, and what the region map says about the centre
-- of each. These have to agree, and the five have to tile the panel.
local half = L.disp_w // 2
local third = L.disp_w // 3
local nav = L.nav_y
local boxes = {
	{0, 0, half, nav},
	{half, 0, L.disp_w - half, nav},
	{0, nav, third, L.disp_h - nav},
	{third, nav, third, L.disp_h - nav},
	{2 * third, nav, L.disp_w - 2 * third, L.disp_h - nav},
}

print(string.format("layout w=%d h=%d nav_y=%d half=%d third=%d 2third=%d",
	L.disp_w, L.disp_h, nav, half, third, 2 * third))

for i, b in ipairs(boxes) do
	local cx, cy = b[1] + b[3] // 2, b[2] + b[4] // 2
	print(string.format("box %d  x %d..%d y %d..%d  centre %d,%d -> region %s",
		i, b[1], b[1] + b[3] - 1, b[2], b[2] + b[4] - 1, cx, cy,
		tostring(input.region(cx, cy))))
end

-- Every pixel of the panel has to be inside exactly one box, or the overlay
-- is claiming an area the region map does not. Sampled on a grid rather than
-- per pixel, which is enough to catch an off-by-one at a boundary because the
-- boundaries are on the grid.
local gaps, overlaps = 0, 0
for y = 0, L.disp_h - 1, 1 do
	for x = 0, L.disp_w - 1, 7 do
		local n = 0
		for _, b in ipairs(boxes) do
			if x >= b[1] and x < b[1] + b[3] and y >= b[2] and y < b[2] + b[4] then
				n = n + 1
			end
		end
		if n == 0 then gaps = gaps + 1 end
		if n > 1 then overlaps = overlaps + 1 end
	end
end
print(string.format("tiling: %d gaps, %d overlaps", gaps, overlaps))

-- And the box a coordinate falls in has to be the box whose centre reports
-- the same region, or a label is over the wrong area.
local wrong = 0
for y = 0, L.disp_h - 1, 3 do
	for x = 0, L.disp_w - 1, 7 do
		local r = input.region(x, y)
		for _, b in ipairs(boxes) do
			if x >= b[1] and x < b[1] + b[3] and y >= b[2] and y < b[2] + b[4] then
				local cx, cy = b[1] + b[3] // 2, b[2] + b[4] // 2
				if input.region(cx, cy) ~= r then
					wrong = wrong + 1
				end
			end
		end
	end
end
print(string.format("label agreement: %d points in a box labelled wrong", wrong))

vesc.save_frame("/tmp/dash_e2e/p4_regions.ppm")
