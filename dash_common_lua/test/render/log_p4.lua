-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- The boot log page, rendered on the host.
--
-- No golden: there is no lisp counterpart to compare against, because the
-- firmware had nothing to read until now. So this renders the page and
-- check_log.py measures it instead -- specifically that the first and last
-- rows actually carry ink.
--
-- That is the bug this exists to catch. img:text takes a baseline, not a top
-- edge, so a row laid out from its top edge draws above its own buffer: the
-- first line renders as nothing and the last as the bottom two pixels of its
-- tallest letters. It looked like clipping and it was an off-by-a-cap-height,
-- and it took a photograph of the panel to notice.

vesc.systime = function() return 1234 end
vesc.secs_since = function(t) return (1234 - t) / 1000.0 end
vesc.sleep = function() end

-- Lines with descenders and capitals in the first and last, so a baseline
-- that is off in either direction loses ink somewhere measurable.
--
-- The whole list is stubbed, not just the firmware ring, because the lisp
-- dash's page is compared against this render: what is being compared is the
-- drawing -- baseline, clipping, palette -- and both sides have to be handed
-- the same text for that to mean anything.
local FAKE = {}
for i = 1, 30 do
	FAKE[i] = string.format("[%7.3f] Qgjpy line %d ABCDEFG 0123456789", i * 0.1, i)
end

local boot_log = require("lib.boot_log")
boot_log.lines = function() return FAKE end

vesc.log_lines = function() return FAKE, 0 end
vesc.touch_stats = function() return 4321, 0, 0 end
vesc.touch_loaded = function() return true end

local colors = require("lib.colors")
local vs = require("lib.view_static")
local vp = require("lib.view_pages")
local state = require("lib.state")

local L = vs.set_layout({
	disp_w = 800, disp_h = 480,
	strip_h = 58, speed_h = 145, page_h = 120, page_cols = 4, page_row_h = 44,
})
vp.set_layout(L)

vp.font_16 = vesc.font_load(vesc.asset("font18"))
vp.font_24 = vp.font_16
vp.font_40 = vp.font_16

colors.bg = 0x000000
colors.accent = 0x00C8FF
colors.text = 0xfbfcfc
colors.theme = 0
colors.apply_status()
colors.build()

vesc.disp_clear(colors.bg)
vp.page_log(true)

local g = vp.log_geom()
print(string.format("geom line_h=%d rows=%d top=%d", g.line_h, g.rows, g.top))

vesc.save_frame("/tmp/dash_e2e/p4_log.ppm")
