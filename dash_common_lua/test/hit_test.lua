-- Unit tests for the coordinate-to-cell maps: the long press that sends a
-- live cell to the chart page, and the six-button quick shade.
--
-- A port of dash_common/test/hit_test.lisp, asserting the same things over
-- the same board profiles. Pure arithmetic, so no display needed.
--
-- The strong property is the round trip: the forward geometry that draws a
-- cell and the inverse that hits it come from the same numbers, so every cell
-- the view draws must map back to itself.
local t = require("test.harness")
local geom = require("lib.geom")

-- The page band, which normally comes from the board config and view_static.
local PAGE_X, PAGE_Y, PAGE_H = 0, 100, 144

local function check_live(name, page_w, page_cols)
	local g = geom.live(PAGE_X, PAGE_Y, page_w, PAGE_H, page_cols)

	-- Every cell centre hits its own cell.
	for i = 0, 3 do
		local cx = g.cell_x(i) + (g.cell_w - 16) // 2
		local cy = g.cell_y(i) + g.cell_h // 2
		t.ok(name .. " centre " .. i, g.hit(cx, cy) == i)
	end

	-- Corners of the grid.
	t.ok(name .. " top left", g.hit(PAGE_X, PAGE_Y) == 0)
	t.ok(name .. " last px",
		g.hit(PAGE_X + g.cols * g.cell_w - 1, PAGE_Y + g.rows * g.cell_h - 1) == 3)

	-- Outside, on all four sides. Left and above matter most: integer
	-- division truncating towards zero would land both in cell 0.
	t.ok(name .. " left of",  g.hit(PAGE_X - 1, PAGE_Y) == nil)
	t.ok(name .. " above",    g.hit(PAGE_X, PAGE_Y - 1) == nil)
	t.ok(name .. " right of", g.hit(PAGE_X + g.cols * g.cell_w, PAGE_Y) == nil)
	t.ok(name .. " below",    g.hit(PAGE_X, PAGE_Y + g.rows * g.cell_h) == nil)

	-- The nav strip sits 4 px past the last row, so a press there is below
	-- the grid and must not chart anything.
	t.ok(name .. " nav strip", g.hit(PAGE_X, PAGE_Y + PAGE_H + 6) == nil)

	-- No coordinate inside the band may map outside 0..3. Sampled on a
	-- coprime stride, which keeps the sweep off the column boundaries it
	-- would otherwise line up with.
	local bad = nil
	local y = PAGE_Y
	while y < PAGE_Y + PAGE_H do
		local x = PAGE_X
		while x < PAGE_X + page_w do
			local c = g.hit(x, y)
			if c and (c < 0 or c > 3) then
				bad = string.format("(%d,%d)->%s", x, y, tostring(c))
			end
			x = x + 7
		end
		y = y + 11
	end
	t.ok(name .. " every pixel in range", bad == nil)

	return g
end

-- 480x480 panel: 2 columns, so 2x2.
local s3 = check_live("s3", 480, 2)
t.ok("s3 cols", s3.cols == 2)
t.ok("s3 rows", s3.rows == 2)

-- 800x480 panel: 4 columns in one row.
local p4 = check_live("p4", 800, 4)
t.ok("p4 cols", p4.cols == 4)
t.ok("p4 rows", p4.rows == 1)

-- A profile nothing ships, to show the map follows the constants rather than
-- either shipped grid.
check_live("odd", 600, 2)

-- --- Quick shade grid ---
local function check_shade(name, disp_w, nav_y)
	local g = geom.shade(disp_w, nav_y)
	local cells = g.cols * g.rows

	for i = 0, cells - 1 do
		local cx = g.cell_x(i) + g.cell_w // 2
		local cy = g.cell_y(i) + g.cell_h // 2
		t.ok(name .. " shade centre " .. i, g.hit(cx, cy) == i)
	end

	t.ok(name .. " shade origin", g.hit(0, 0) == 0)
	t.ok(name .. " shade last px",
		g.hit(g.cols * g.cell_w - 1, g.rows * g.cell_h - 1) == cells - 1)
	t.ok(name .. " shade left of",  g.hit(-1, 0) == nil)
	t.ok(name .. " shade above",    g.hit(0, -1) == nil)
	t.ok(name .. " shade right of", g.hit(g.cols * g.cell_w, 0) == nil)

	-- The nav strip is below the last row, and a press there has to fall
	-- through to the region actions or there is no way off the shade.
	t.ok(name .. " shade nav strip", g.hit(0, nav_y) == nil)

	-- Nothing may map outside 0..5, and every button has to be reachable: a
	-- column of zero width would pass the centre test while being untappable.
	local seen, bad = {}, nil
	local y = 0
	while y < g.rows * g.cell_h do
		local x = 0
		while x < g.cols * g.cell_w do
			local c = g.hit(x, y)
			if c then
				if c < 0 or c >= cells then
					bad = string.format("(%d,%d)->%d", x, y, c)
				end
				seen[c] = true
			end
			x = x + 5
		end
		y = y + 7
	end
	t.ok(name .. " shade every pixel in range", bad == nil)

	local n = 0
	for _ in pairs(seen) do n = n + 1 end
	t.ok(name .. " shade all reachable", n == cells)
end

check_shade("s3", 480, 450)
check_shade("p4", 800, 430)

t.report("hit")
