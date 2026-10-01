-- Clamping and range mapping, and the one text helper every view uses.
--
-- Ported from dash_common/lib/draw-utils.lisp. The clamps are here rather
-- than inlined because a value that escapes 0..1 indexes off the end of a
-- palette downstream, and one place to get that right is better than thirty.

local M = {}

function M.clamp01(v)
	if v < 0.0 then return 0.0 end
	if v > 1.0 then return 1.0 end
	return v
end

function M.clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- Map lo..hi onto 0..1, clamped at both ends.
function M.map_range_01(v, lo, hi)
	if hi == lo then
		-- The lisp version divides by zero here and produces inf or nan,
		-- which then propagates into a bar width. A degenerate range has no
		-- meaningful position in it, so say zero.
		return 0.0
	end
	return M.clamp01((v - lo) / (hi - lo))
end

-- Centre text in an image buffer, horizontally always and vertically by the
-- cap height of "D" so a line of digits sits where the eye expects rather
-- than where the font's own ascent puts it.
--
-- colors defaults to the four-entry indexed palette the views use; py
-- overrides the vertical placement.
function M.ttf_txt_center(txt, font, imgbuf, colours, py)
	local w_txt = font:measure(txt)
	local _, h_glyph = font:glyph_dims("D")
	local w_img, h_img = imgbuf:dims()

	-- Vertically by the cap height of "D" rather than the font's ascent, so a
	-- line of digits sits where the eye expects. py overrides it.
	py = py or (h_glyph + (h_img - h_glyph) // 2)

	local base, aa = M.text_colour(colours)
	imgbuf:text((w_img - w_txt) // 2, py, font, txt, base, aa)
end

-- Left-aligned at x, on a baseline derived from the font rather than guessed.
--
-- The y that img:text takes is the baseline, with the glyphs extending
-- upward from it -- which is why ttf_txt_center adds the cap height of "D"
-- rather than treating py as a top edge. Passing a row's top edge straight
-- through puts the whole line above its buffer and it renders as nothing, or
-- as the bottom two pixels of the tallest letters.
--
-- Returns the baseline used, so a caller laying out rows can step by it.
function M.ttf_txt_left(txt, font, imgbuf, x, row_top, colours)
	local _, h_glyph = font:glyph_dims("D")
	local base, aa = M.text_colour(colours)
	local py = row_top + h_glyph
	imgbuf:text(x, py, font, txt, base, aa)
	return py
end

-- Translate a lisp colour list into the base index and antialias flag the Lua
-- draw call takes.
--
-- The lisp passes one palette entry per coverage level, so (0 1 2 3) is a
-- ramp and (0 3 3 3) is a flat colour at the brightest entry -- which is how
-- the battery percentage is drawn, because the fill behind it would otherwise
-- make the ramp read as green on green.
--
-- Lua takes a base index plus a flag, which expresses exactly those two
-- shapes: antialiased means coverage k lands on base+k-1, flat means every
-- covered pixel is base. A list that skips or reorders entries has no
-- equivalent and is refused rather than approximated, because approximating
-- it would draw a colour nobody chose.
--
-- This is the cost of taking an index instead of the list. It is paid once,
-- here, rather than at every call site.
function M.text_colour(colours)
	if not colours then
		return 1, true
	end

	local c1, c2, c3 = colours[2], colours[3], colours[4]

	-- Three entries is an indexed2 glyph: one coverage level, so flat.
	if c2 == nil then
		return c1 or 1, false
	end

	if c2 == c1 + 1 and c3 == c1 + 2 then
		return c1, true
	end

	if c2 == c1 and c3 == c1 then
		return c1, false
	end

	error(string.format(
		"text colour list {%s,%s,%s,%s} is neither a ramp nor a flat colour, "
		.. "which is all a base index can express",
		tostring(colours[1]), tostring(c1), tostring(c2), tostring(c3)))
end

return M
