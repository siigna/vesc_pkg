-- Unit tests for lib/pages.lua: the page set, the mask, the rotation and the
-- two overlays.
--
-- Ported from the page set at the end of dash_common/views/view_pages.lbm,
-- which has no test of its own. The properties worth pinning are the ones a
-- stored setting can break: paging must not reach the settings page or either
-- overlay, a mask that selects nothing must still leave a way to the
-- settings that produced it, and a page_now left over from a wider mask must
-- not point past the new set.
vesc = require("test.vesc_stub")

local t = require("test.harness")
local state = require("lib.state")
local vp = require("lib.view_pages")
local pages = require("lib.pages")

-- The pages are never drawn here; they are compared by identity, which is
-- what the dash itself does to ask which page it is on.
-- Every catalog page. Nine bits now the boot log is one of them; the bound
-- in settings.load had to be raised to match, which is what lets a newly
-- appended page be enabled at all.
local ALL = 0x1FF

--- the set ---
pages.apply_mask(ALL)

t.ok("nine catalog pages",        #pages.catalog == 9)
t.ok("page_num is the rotation",  state.page_num == 9)
t.ok("three appended after it",   #pages.pages == 12)

t.ok("the rotation starts at live", pages.at(0) == vp.page_live)
t.ok("settings is at page_num",     pages.at(state.page_num) == vp.page_settings)
t.ok("the shade is one past",       pages.at(state.page_num + 1) == vp.page_shade)
t.ok("the keypad is two past",      pages.at(state.page_num + 2) == vp.page_pin)
t.ok("and nothing is three past",   pages.at(state.page_num + 3) == nil)

t.ok("index_of finds a rotation page", pages.index_of(vp.page_chart) == 5)
t.ok("and the appended ones too",      pages.index_of(vp.page_settings) == 9)

--- the mask ---
--
-- Bit i selects catalog entry i, zero-based, because the mask lives in
-- eeprom against the lisp's index.
pages.apply_mask(1 << 5)                 -- chart only
t.ok("one page selected",     state.page_num == 1)
t.ok("and it is the chart",   pages.at(0) == vp.page_chart)
t.ok("settings follows it",   pages.at(1) == vp.page_settings)
t.ok("index_of reports nil for a page the mask dropped",
	pages.index_of(vp.page_live) == nil)

-- Selection order follows the catalog, not the bit order of the mask.
pages.apply_mask((1 << 7) | (1 << 0))    -- cells and live
t.ok("two selected",            state.page_num == 2)
t.ok("live first",              pages.at(0) == vp.page_live)
t.ok("cells second",            pages.at(1) == vp.page_cells)

-- A mask of zero is a stored setting, and a dash with no pages would have no
-- way to reach the setting that produced it.
pages.apply_mask(0)
t.ok("an empty mask still gives one page", state.page_num == 1)
t.ok("and it is the first catalog page",   pages.at(0) == vp.page_live)
t.ok("settings is still reachable",        pages.at(1) == vp.page_settings)

-- Bits past the catalog select nothing rather than extending the set.
pages.apply_mask(1 << 20)
t.ok("a bit past the catalog falls back", state.page_num == 1)

--- a stale page_now ---
--
-- page_now survives a mask change, and a narrower mask can leave it pointing
-- past the new set, which would draw nothing at all.
pages.apply_mask(ALL)
state.page_now = 11                      -- the keypad, with nine pages
pages.apply_mask(ALL)
t.ok("a page_now inside the new set is kept", state.page_now == 11)

pages.apply_mask(1 << 0)                 -- one page: valid is 0..2
t.ok("and reset when it falls outside", state.page_now == 0)

-- The boundary is page_num + 2, which is the keypad and still valid.
pages.apply_mask(ALL)
state.page_now = state.page_num + 2
pages.apply_mask(ALL)
t.ok("the keypad index is not outside", state.page_now == 11)

--- the overlays ---
pages.apply_mask(ALL)
state.page_now = 0
t.ok("no overlay on a rotation page", not pages.overlay_showing())
t.ok("nor the shade",                 not pages.shade_showing())
t.ok("nor the keypad",                not pages.pin_showing())

state.page_now = state.page_num          -- settings
t.ok("the settings page is not an overlay", not pages.overlay_showing())

state.page_now = state.page_num + 1
t.ok("the shade is showing",    pages.shade_showing())
t.ok("and counts as an overlay", pages.overlay_showing())
t.ok("but is not the keypad",    not pages.pin_showing())

state.page_now = state.page_num + 2
t.ok("the keypad is showing",    pages.pin_showing())
t.ok("and counts as an overlay", pages.overlay_showing())
t.ok("but is not the shade",     not pages.shade_showing())

--- rotation ---
--
-- Modulo page_num, which is what keeps paging off the settings page and both
-- overlays however many times it is stepped.
pages.apply_mask(ALL)
state.page_now = 0

pages.next()
t.ok("next steps forward", state.page_now == 1)

for _ = 1, state.page_num - 1 do pages.next() end
t.ok("and wraps at page_num", state.page_now == 0)

pages.prev()
t.ok("prev wraps backwards to the last rotation page",
	state.page_now == state.page_num - 1)
t.ok("which is not the settings page", state.page_now < state.page_num)

-- Stepping a lot never lands on anything outside the rotation. That is the
-- whole point of the layout, so it is checked rather than reasoned about.
local reached = {}
state.page_now = 0
for _ = 1, 200 do
	pages.next()
	reached[state.page_now] = true
end
local escaped = false
for p in pairs(reached) do
	if p >= state.page_num then escaped = true end
end
t.ok("paging never reaches the settings page or an overlay", not escaped)
t.ok("and reaches every rotation page", #pages.catalog == 9 and (function()
	for i = 0, state.page_num - 1 do
		if not reached[i] then return false end
	end
	return true
end)())

-- With one page, paging is a no-op rather than an error.
pages.apply_mask(1 << 0)
state.page_now = 0
pages.next()
t.ok("one page: next stays put", state.page_now == 0)
pages.prev()
t.ok("one page: prev stays put", state.page_now == 0)

--- the toggles ---
pages.apply_mask(ALL)
state.page_now = 3

pages.toggle_settings()
t.ok("settings opens",       state.page_now == state.page_num)
pages.toggle_settings()
t.ok("and closes to page 0", state.page_now == 0)

pages.toggle_shade()
t.ok("the shade opens",      state.page_now == state.page_num + 1)
pages.toggle_shade()
t.ok("and closes to page 0", state.page_now == 0)

-- The keypad does not toggle: nothing may navigate off it except unlocking.
pages.show_pin()
t.ok("the keypad shows",   state.page_now == state.page_num + 2)
pages.show_pin()
t.ok("and showing it again leaves it up", state.page_now == state.page_num + 2)

--- the draw pass ---
--
-- switched has to be true on the first pass whatever page_now starts at, and
-- the force flag has to be consumed or a forced redraw would repaint forever.
local drawn = {}
local function spy(name)
	return function(switched) drawn[#drawn + 1] = {name, switched} end
end

pages.pages = {spy("a"), spy("b")}
state.page_num = 1
state.page_now = 0
pages.last_page = -1
state.view_force_pages = false

pages.step()
t.ok("the first pass is switched", drawn[1][1] == "a" and drawn[1][2] == true)

pages.step()
t.ok("the second is not", drawn[2][2] == false)

state.page_now = 1
pages.step()
t.ok("a page change is switched", drawn[3][1] == "b" and drawn[3][2] == true)

state.view_force_pages = true
pages.step()
t.ok("a forced pass is switched",  drawn[4][2] == true)
t.ok("and the flag is consumed",   not state.view_force_pages)
pages.step()
t.ok("so the next pass is not",    drawn[5][2] == false)

-- An index with no page draws nothing rather than raising, which is what a
-- page_now written by something else would do.
state.page_now = 9
pages.step()
t.ok("an empty slot draws nothing", #drawn == 5)

t.report("pages")
