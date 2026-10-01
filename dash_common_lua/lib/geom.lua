-- Cell grids, and the coordinate-to-cell maps that invert them.
--
-- Ported from the geometry in dash_common/views/view_pages.lbm. The lisp
-- version derives its constants at load from page-cols and page-w, so its
-- test has to awk the block out of the view and re-evaluate it per board
-- profile. Here a profile is an argument: live() and shade() return a grid,
-- and the test calls them three times.
--
-- The property worth keeping is the round trip. The forward geometry that
-- draws a cell and the inverse that hits it come from the same three
-- numbers, so every cell the view draws maps back to itself.

local M = {}

-- Integer division that truncates towards zero, as LispBM's / does on
-- integers. Lua's // floors instead, which differs for negatives: -1 // 240
-- is -1 where the lisp gives 0. Every caller here guards the negative case
-- before dividing, so the two agree -- but the guard is what makes that true,
-- not the operator, and the lisp comments say the same thing.
local function idiv(a, b)
	local q = a / b
	if q < 0 then
		return math.ceil(q)
	end
	return math.floor(q)
end

--- the live page grid ---
--
-- Four cells, laid out as 4x1 on a wide panel and 2x2 on a square one. A 2x2
-- would overflow the nav strip on the shorter page area a wide panel leaves.
function M.live(page_x, page_y, page_w, page_h, page_cols)
	local g = {
		page_x = page_x,
		page_y = page_y,
		page_w = page_w,
		page_h = page_h,
		lbl_h = 24,
		val_h = 46,
	}

	g.cols = page_cols >= 4 and 4 or 2
	g.rows = idiv(4, g.cols)
	g.cell_w = idiv(page_w, g.cols)
	g.cell_h = idiv(page_h, g.rows)

	-- The 8 px is padding inside the cell, not a gap between cells, so the
	-- inverse does not subtract it back out.
	function g.cell_x(i)
		return page_x + (i % g.cols) * g.cell_w + 8
	end

	function g.cell_y(i)
		return page_y + idiv(i, g.cols) * g.cell_h
	end

	-- Which cell a screen coordinate falls in, or nil for none.
	--
	-- The left and above guards are not redundant: integer division
	-- truncating towards zero would put a coordinate above or left of the
	-- page area into cell 0. Below the grid needs no test of its own -- the
	-- nav strip starts 4 px past the last row, so a press there gives a row
	-- index of rows and falls out.
	function g.hit(x, y)
		if x < page_x or y < page_y then
			return nil
		end

		local cx = idiv(x - page_x, g.cell_w)
		local cy = idiv(y - page_y, g.cell_h)

		if cx >= g.cols or cy >= g.rows then
			return nil
		end

		return cy * g.cols + cx
	end

	return g
end

--- the quick shade grid ---
--
-- Six buttons over the whole panel above the nav strip, where the touch layer
-- reports only which of four regions was pressed. So a press is resolved by
-- position and the map has to be right for every pixel of it.
function M.shade(disp_w, nav_y)
	local g = {cols = 3, rows = 2}

	g.cell_w = idiv(disp_w, g.cols)
	g.cell_h = idiv(nav_y, g.rows)

	function g.cell_x(i)
		return (i % g.cols) * g.cell_w
	end

	function g.cell_y(i)
		return idiv(i, g.cols) * g.cell_h
	end

	function g.hit(x, y)
		if x < 0 or y < 0 then
			return nil
		end

		local cx = idiv(x, g.cell_w)
		local cy = idiv(y, g.cell_h)

		if cx >= g.cols or cy >= g.rows then
			return nil
		end

		return cy * g.cols + cx
	end

	return g
end

return M
