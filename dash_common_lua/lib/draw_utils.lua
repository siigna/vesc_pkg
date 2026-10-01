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
function M.ttf_txt_center(txt, font, imgbuf, colors, py)
	local w_txt = vesc.ttf_text_dims(font, txt)
	local _, h_glyph = vesc.ttf_glyph_dims(font, "D")
	local w_img, h_img = vesc.img_dims(imgbuf)

	colors = colors or {0, 1, 2, 3}
	py = py or (h_glyph + (h_img - h_glyph) / 2)

	vesc.ttf_text(imgbuf, (w_img - w_txt) / 2, py, colors, font, txt)
end

return M
