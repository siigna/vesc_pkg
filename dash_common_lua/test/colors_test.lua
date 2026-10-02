-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Unit tests for lib/colors.lua. The lisp dash has no unit test for its
-- colours -- they are only checked by the rendered goldens -- so these are
-- new, and aimed at the properties a wrong palette breaks quietly:
-- ramp endpoints, ramp length, and the theme falling back rather than
-- erroring on an index from a newer firmware.
vesc = require("test.vesc_stub")

local t = require("test.harness")
local colors = require("lib.colors")

-- --- ramps ---
local ramp = colors.make_aa(0x000000, 0xFF0000, 4)
t.ok("ramp has the asked-for length", #ramp == 4)
t.ok("ramp starts at the first colour", ramp[1] == 0x000000)
t.ok("ramp ends at the second colour",  ramp[4] == 0xFF0000)
t.ok("ramp is monotonic in red",
	ramp[1] < ramp[2] and ramp[2] < ramp[3] and ramp[3] < ramp[4])

local two = colors.make_aa(0x000000, 0xFF0000, 2)
t.ok("indexed2 ramp is the two ends", #two == 2 and two[1] == 0 and two[2] == 0xFF0000)

-- A one-entry ramp must not divide by zero. The lisp version computes
-- i/(num-1) unguarded, which is 0/0 for num = 1.
local one = colors.make_aa(0x000000, 0xFF0000, 1)
t.ok("one-entry ramp is the start", #one == 1 and one[1] == 0x000000)

-- --- shade, towards the background ---
colors.bg = 0x000000
t.ok("shade 0 is the background", colors.shade(0xFF0000, 0.0) == 0x000000)
t.ok("shade 1 is the colour",     colors.shade(0xFF0000, 1.0) == 0xFF0000)
colors.bg = 0xFFFFFF
t.ok("shade lightens on a light theme", colors.shade(0x000000, 0.5) ~= 0x000000)
colors.bg = 0x000000

-- --- the long-press fade ---
colors.text = 0xfbfcfc
local f0 = colors.fade_aa(0.0)
local f1 = colors.fade_aa(1.0)
t.ok("fade at 0 ends at the text colour", f0[4] == colors.text)
t.ok("fade at 1 ends at the background",  f1[4] == colors.bg)
t.ok("fade clamps past 1", colors.fade_aa(5.0)[4] == colors.bg)

-- --- hsv ---
t.ok("hsv red",   colors.hsv(0, 1.0, 1.0) == 0xFF0000)
t.ok("hsv green", colors.hsv(120, 1.0, 1.0) == 0x00FF00)
t.ok("hsv blue",  colors.hsv(240, 1.0, 1.0) == 0x0000FF)
t.ok("hsv wraps at 360",   colors.hsv(360, 1.0, 1.0) == colors.hsv(0, 1.0, 1.0))
t.ok("hsv wraps negative", colors.hsv(-120, 1.0, 1.0) == colors.hsv(240, 1.0, 1.0))
t.ok("zero saturation is grey", (function()
	local c = colors.hsv(100, 0.0, 1.0)
	local r, g, b = vesc.color_split(c)
	return r == g and g == b
end)())
t.ok("zero value is black", colors.hsv(100, 1.0, 0.0) == 0x000000)

-- --- the heat ramp ---
-- Teal at 0 to red at 1: what matters is that it ends hot and starts cool,
-- because a heat colour that ran backwards would read as fine at the top.
local cool = colors.heat_at(0.0)
local hot = colors.heat_at(1.0)
local cr, cg, cb = vesc.color_split(cool)
local hr, hg, hb = vesc.color_split(hot)
t.ok("cool end is not red dominant", cr < cg or cr < cb)
t.ok("hot end is red dominant",      hr > hg and hr > hb)

colors.build()
t.ok("heat has one ramp per step", #colors.heat == colors.heat_steps)
t.ok("heat ramp at 0 is the cool end",  colors.heat_ramp(0.0)[4] == cool)
t.ok("heat ramp at 1 is the hot end",   colors.heat_ramp(1.0)[4] == hot)
t.ok("heat ramp clamps past 1",         colors.heat_ramp(9.0)[4] == hot)
t.ok("heat ramp clamps below 0",        colors.heat_ramp(-9.0)[4] == cool)

-- --- themes ---
t.ok("theme 0 is the shipped palette", colors.theme_row(0)[1] == "Dark")
-- An index from a firmware with more themes must fall back, not error.
t.ok("index past the catalog falls back", colors.theme_row(99)[1] == "Dark")
t.ok("negative index falls back",         colors.theme_row(-1)[1] == "Dark")

colors.theme = 4
t.ok("light theme has a pale background", colors.theme_bg() == 0xFBFCFC)
colors.apply_status()
t.ok("light theme darkens ok",   colors.ok == 0x0A7A1C)
t.ok("light theme darkens warn", colors.warn == 0x9A6A00)
colors.theme = 0
colors.apply_status()
t.ok("default ok restored", colors.ok == 0x00C321)

-- --- build populates everything a view draws with ---
colors.build()
for _, name in ipairs({"theme_2", "accent_aa", "speed", "charging", "vesc_logo",
		"red_icon", "green_icon", "blue_icon", "hidden", "dim_icon",
		"white_icon", "purple_icon", "text_aa", "ok_aa", "warn_aa", "crit_aa",
		"ok_2", "warn_2", "crit_2", "slots", "heat", "text_sel_aa", "white_aa"}) do
	t.ok("build set " .. name, type(colors[name]) == "table" and #colors[name] > 0)
end

t.ok("one slot ramp per slot colour", #colors.slots == #colors.slot_cols)
t.ok("hidden is the background throughout",
	colors.hidden[1] == colors.bg and colors.hidden[4] == colors.bg)

t.report("colors")
