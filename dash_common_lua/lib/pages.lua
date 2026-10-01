-- Which pages exist, which are switched on, and which one is drawn.
--
-- Ported from the page set and view-pages-thread at the end of
-- dash_common/views/view_pages.lbm. Split out of the view because it is
-- structure rather than drawing: the view says what a page looks like, this
-- says what the rotation contains and where the two overlays sit.
--
-- The layout of the set is the part worth stating. The rotation is the
-- catalog pages the mask selects, and the settings page, the quick shade and
-- the PIN keypad are appended after it. Paging is modulo page_num, so
-- nothing can step onto those three: each is reached by its own action or
-- gesture, and none of them costs a page slot.
--
--   pages[0 .. page_num-1]   the rotation
--   pages[page_num]          settings
--   pages[page_num + 1]      quick shade
--   pages[page_num + 2]      PIN keypad
--
-- Those indices are the lisp's, and page_now is stored against them, so the
-- table here is indexed from 1 and every lookup adds one. Keeping page_now
-- zero-based is deliberate: it is written to eeprom and compared against
-- page_num in several places, and renumbering it would make the two dashes
-- disagree about what a stored page means.

local state = require("lib.state")
local vp = require("lib.view_pages")

local M = {}

-- Index order is stored in the page mask, so only append.
--
-- The functions are the view's, referenced rather than wrapped: the dash
-- compares the selected page against these to ask which page it is on, the
-- way the lisp compares with eq.
M.catalog = {
	vp.page_live,
	vp.page_trip,
	vp.page_session,
	vp.page_batt,
	vp.page_pas,
	vp.page_chart,
	vp.page_conf,
	vp.page_cells,
	-- Bit 8. Off in the default mask: it is a diagnostic, not something to
	-- page past while riding. Adding it meant raising the page_mask bound in
	-- settings.load from 0xFF to 0x1FF, which is the note at that bound --
	-- without it the new page clamps away and cannot be enabled at all.
	vp.page_log,
}

-- The three that are not in the rotation, in the order they are appended.
M.settings = vp.page_settings
M.shade = vp.page_shade
M.pin = vp.page_pin

M.pages = {}

-- Rebuild the set from the mask. page_num becomes the length of the
-- rotation, which is what paging is taken modulo of.
--
-- An empty selection falls back to the first catalog page rather than to
-- nothing: a mask of zero is a stored setting, and a dash with no pages at
-- all would have no way to reach the settings that produced it.
function M.apply_mask(mask)
	local sel = {}

	for i, fn in ipairs(M.catalog) do
		-- Bit i-1: the mask is written against the lisp's zero-based index
		-- and lives in eeprom.
		if (mask & (1 << (i - 1))) ~= 0 then
			sel[#sel + 1] = fn
		end
	end

	if #sel == 0 then
		sel = {M.catalog[1]}
	end

	state.page_num = #sel

	sel[#sel + 1] = M.settings
	sel[#sel + 1] = M.shade
	sel[#sel + 1] = M.pin
	M.pages = sel

	-- A selection past the end of the new set would draw nothing.
	if state.page_now > state.page_num + 2 then
		state.page_now = 0
	end
end

-- The page function at a zero-based index, or nil.
function M.at(i)
	return M.pages[i + 1]
end

-- Where a page sits in the enabled set, zero-based, or nil when the mask has
-- it switched off. The lisp's page-index.
function M.index_of(fn)
	for i, p in ipairs(M.pages) do
		if p == fn then
			return i - 1
		end
	end
	return nil
end

-- The page currently selected, which is what the dash compares against the
-- catalog entries to ask where it is.
function M.current()
	return M.at(state.page_now)
end

--- the two overlays ---
--
-- Whether each is up is a function of page_now, not a flag: one number says
-- what is on screen, so the two cannot disagree.

function M.shade_showing()
	return state.page_now == state.page_num + 1
end

function M.pin_showing()
	return state.page_now == state.page_num + 2
end

-- Either of the views that cover the whole panel rather than just the page
-- area. The static strip stops drawing while one is up.
function M.overlay_showing()
	return M.shade_showing() or M.pin_showing()
end

--- rotation ---

function M.next()
	state.page_now = (state.page_now + 1) % state.page_num
end

function M.prev()
	state.page_now = (state.page_now + state.page_num - 1) % state.page_num
end

-- The settings page, the shade and the keypad each toggle: pressing the
-- action again returns to the first page rather than leaving no way off.
local function toggle(i)
	if state.page_now == i then
		state.page_now = 0
	else
		state.page_now = i
	end
end

function M.toggle_settings()
	toggle(state.page_num)
end

function M.toggle_shade()
	toggle(state.page_num + 1)
end

function M.show_pin()
	state.page_now = state.page_num + 2
end

--- the draw pass ---

-- Forces switched = true on the first pass, whatever page_now starts at.
M.last_page = -1

-- One pass. The page is passed a switched flag, which is what makes it
-- allocate its buffers and paint everything rather than only what changed.
--
-- page_now is sampled once: it is written by the touch handlers, and reading
-- it twice could dispatch to one page having decided about another.
--
-- The force flag is consumed here rather than by the page, so a forced
-- redraw cannot be left set and repaint forever.
function M.step()
	local now = state.page_now
	local pg = M.at(now)
	local force = state.view_force_pages
	state.view_force_pages = false

	if pg then
		pg(force or now ~= M.last_page)
	end

	M.last_page = now
end

return M
