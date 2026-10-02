-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- The palettes, rebuilt from the theme and the colour settings.
--
-- Ported from dash_common/lib/colors.lisp.
--
-- Everything the views draw with is a prebuilt ramp rather than a colour
-- computed per frame: a continuous rule would allocate a fresh four-entry
-- palette on every redraw of every cell, and the live page redraws a cell
-- whenever its text changes.
--
-- Arrays are one-based here where the lisp ones are zero-based, which is the
-- one thing to watch when porting a view: heat_ramp does the conversion.

local M = {}

-- The current colours. build() derives every ramp from these, so a theme
-- change is three assignments and a rebuild.
M.bg = 0x000000
M.accent = 0x00C8FF
M.text = 0xfbfcfc

-- The three status colours, held here rather than written as literals at each
-- use so a theme can move them: a yellow warning is unreadable on a light
-- background, and a night theme wants all three dimmed rather than only the
-- accent.
M.ok = 0x00C321
M.warn = 0xFFD400
M.crit = 0xFF3030

M.slot_cols = {0xfbfcfc, 0xfbfcfc, 0xfbfcfc, 0xfbfcfc}

-- {name, bg, accent, text, ok, warn, crit}
--
-- Row 1 is the palette the dash shipped with, value for value, so the default
-- look does not move. The index is stored in eeprom, so only append.
--
-- Night is for riding after dark: every colour is pulled down and towards
-- red, which is what keeps a bright panel from destroying dark adaptation.
-- Light is the only row with a pale background, and its status colours are
-- darkened rather than reused -- the default yellow and green have almost no
-- contrast against white.
M.theme_catalog = {
	{"Dark",  0x000000, 0x00C8FF, 0xfbfcfc, 0x00C321, 0xFFD400, 0xFF3030},
	{"Amber", 0x000000, 0xFFA000, 0xfbfcfc, 0x00C321, 0xFFD400, 0xFF3030},
	{"Green", 0x000000, 0x00E05A, 0xfbfcfc, 0x00C321, 0xFFD400, 0xFF3030},
	{"Night", 0x000000, 0xC03030, 0xB07070, 0x2E7D32, 0xA06000, 0xC01010},
	{"Light", 0xFBFCFC, 0x0067A8, 0x101010, 0x0A7A1C, 0x9A6A00, 0xC01010},
}

M.theme = 0

-- The stored index is zero-based, as eeprom holds it. Out of range falls back
-- to the shipped palette rather than erroring: an eeprom cell written by a
-- later firmware with more themes must not take the dash down.
function M.theme_row(i)
	if i < 0 or i >= #M.theme_catalog then
		i = 0
	end
	return M.theme_catalog[i + 1]
end

-- Theme colours, as the defaults the individual colour settings fall back to.
-- A colour the rider actually picked in VESC Tool keeps winning, because an
-- unwritten eeprom cell reads -1 and the clamp hands back the default for
-- anything below zero.
function M.theme_bg()     return M.theme_row(M.theme)[2] end
function M.theme_accent() return M.theme_row(M.theme)[3] end
function M.theme_text()   return M.theme_row(M.theme)[4] end

-- The status colours come from the theme only. Overriding them one by one is
-- three more eeprom cells and a picker each, for a choice that has to stay
-- legible against the background to mean anything.
function M.apply_status()
	local row = M.theme_row(M.theme)
	M.ok = row[5]
	M.warn = row[6]
	M.crit = row[7]
end

-- A ramp of num entries from color1 to color2.
function M.make_aa(color1, color2, num)
	local out = {}
	for i = 0, num - 1 do
		out[i + 1] = vesc.color_mix(color1, color2, num > 1 and i / (num - 1) or 0)
	end
	return out
end

-- Towards the background rather than towards black, so this still darkens on
-- a dark theme and lightens on a light one. Identical on the default theme,
-- whose background is black.
function M.shade(c, f)
	return vesc.color_mix(M.bg, c, f)
end

-- A text ramp faded towards the background by f, where f is how far through a
-- long press the finger is. At 0 it is the normal text ramp; at 1 the value
-- has gone, which is what the press is about to do to it. The value being
-- destroyed is its own progress bar.
function M.fade_aa(f)
	if f < 0.0 then f = 0.0 elseif f > 1.0 then f = 1.0 end
	return M.make_aa(M.bg, vesc.color_mix(M.text, M.bg, f), 4)
end

-- h 0..360, s and v 0..1. color_make takes fractions, so the usual byte
-- packing is not needed.
function M.hsv(h, s, v)
	local hh = ((math.floor(h) % 360) + 360) % 360 / 60.0
	local c = v * s
	local sec = math.floor(hh)
	local x = c * (1.0 - math.abs(hh % 2 - 1.0))
	local m = v - c

	local r, g, b
	if sec == 0 then r, g, b = c, x, 0.0
	elseif sec == 1 then r, g, b = x, c, 0.0
	elseif sec == 2 then r, g, b = 0.0, c, x
	elseif sec == 3 then r, g, b = 0.0, x, c
	elseif sec == 4 then r, g, b = x, 0.0, c
	else r, g, b = c, 0.0, x
	end

	return vesc.color_make(r + m, g + m, b + m)
end

-- Teal at 0 through green, yellow and orange to red at 1, eased with a 1.6
-- power so it stays cool over most of the range and only goes hot near the
-- top. From the hue ramp in raskol's dashboard.
local function clamp01(v)
	if v < 0.0 then return 0.0 end
	if v > 1.0 then return 1.0 end
	return v
end

function M.heat_at(f)
	return M.hsv(165 - 170 * clamp01(f) ^ 1.6, 0.81, 0.89)
end

-- Sixteen prebuilt ramps rather than a colour computed per frame.
M.heat_steps = 16

function M.heat_ramp(f)
	-- The lisp indexes a zero-based list; this array is one-based.
	local i = math.floor(clamp01(f) * (M.heat_steps - 1))
	return M.heat[i + 1]
end

function M.build()
	M.theme_2 = M.make_aa(M.bg, M.accent, 2)
	-- The accent as a four-entry ramp. theme_2 is the indexed2 one and cannot
	-- colour text, which is drawn indexed4.
	M.accent_aa = M.make_aa(M.bg, M.accent, 4)
	-- The text colour as two entries, for text drawn into an indexed2 buffer:
	-- one bit per pixel and no antialiasing. The boot log uses it, where the
	-- ramp would cost four times the buffer and buy nothing a reader of
	-- 18-pixel console text would notice.
	M.text_2 = M.make_aa(M.bg, M.text, 2)
	M.speed = {M.bg, M.shade(M.accent, 0.55), M.accent, M.text}
	M.charging = {M.bg, 0x00C321, M.accent, M.text}

	M.vesc_logo = M.make_aa(M.bg, 0xF05A22, 4)
	M.red_icon = M.make_aa(M.bg, M.crit, 4)
	M.green_icon = M.make_aa(M.bg, M.ok, 4)
	M.blue_icon = M.make_aa(M.bg, 0x1d00e8, 4)

	-- Erases an icon's footprint. Skipping the draw would leave it on screen.
	M.hidden = M.make_aa(M.bg, M.bg, 4)

	M.dim_icon = M.make_aa(M.bg, vesc.color_mix(M.bg, M.text, 0.25), 4)
	M.white_icon = M.make_aa(M.bg, M.text, 4)
	M.purple_icon = M.make_aa(M.bg, 0x9f20f1, 4)

	M.text_aa = M.make_aa(M.bg, M.text, 4)

	M.ok_aa = M.make_aa(M.bg, M.ok, 4)
	M.warn_aa = M.make_aa(M.bg, M.warn, 4)
	M.crit_aa = M.make_aa(M.bg, M.crit, 4)

	-- Battery bar segments are indexed2.
	M.ok_2 = M.make_aa(M.bg, M.ok, 2)
	M.warn_2 = M.make_aa(M.bg, M.warn, 2)
	M.crit_2 = M.make_aa(M.bg, M.crit, 2)

	M.slots = {}
	for i, c in ipairs(M.slot_cols) do
		M.slots[i] = M.make_aa(M.bg, c, 4)
	end

	M.heat = {}
	for i = 0, M.heat_steps - 1 do
		M.heat[i + 1] = M.make_aa(M.bg, M.heat_at(i / (M.heat_steps - 1)), 4)
	end

	M.text_sel_aa = M.make_aa(M.bg, 0x00FF00, 4)
	M.white_aa = M.make_aa(M.bg, M.text, 4)
end

return M
