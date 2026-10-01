-- Unit tests for lib/settings.lua.
--
-- New: the lisp has no unit test for these, and the guards are where it has
-- already been bitten. setting-clamp carries a comment about a nil comparison
-- that took settings-load down and left the dash dead before it drew
-- anything, so the nil and NaN paths are tested first and deliberately.
vesc = require("test.vesc_stub")

local t = require("test.harness")
local settings = require("lib.settings")

-- --- the guard, which is the part with a history ---
t.ok("clamp passes a value in range", settings.clamp(5, 0, 10, 99) == 5)
t.ok("clamp takes the default below the floor", settings.clamp(-1, 0, 10, 99) == 99)
t.ok("clamp takes the default above the ceiling", settings.clamp(11, 0, 10, 99) == 99)
t.ok("clamp accepts the bounds themselves",
	settings.clamp(0, 0, 10, 99) == 0 and settings.clamp(10, 0, 10, 99) == 10)

-- nil first: a name missing from the map, or a slot never written, reads nil
-- on hardware. Comparing it with < is the error that killed the dash.
t.ok("clamp survives nil", settings.clamp(nil, 0, 10, 99) == 99)

-- NaN next: an unwritten cell reads -1 as an integer, which is NaN read as a
-- float, and NaN fails every comparison including against itself.
local nan = 0.0 / 0.0
t.ok("nan is not equal to itself", nan ~= nan)
t.ok("clamp survives nan", settings.clamp(nan, 0, 10, 99) == 99)

-- --- read and write, over the stub eeprom ---
vesc.eeprom = {}

t.ok("an unwritten integer reads nil", settings.read("whl_active") == nil)
t.ok("an unwritten float reads nil",   settings.read("whl_kd") == nil)
t.ok("a name not in the map reads nil", settings.read("not_a_setting") == nil)
t.ok("writing a name not in the map is refused",
	settings.write("not_a_setting", 1) == false)

settings.write("whl_active", 1)
t.ok("integer round trip", settings.read("whl_active") == 1)

settings.write("whl_kd", 0.0025)
t.near("float round trip", settings.read("whl_kd"), 0.0025, 1e-9)

-- An integer slot truncates rather than storing a float, which is what the
-- firmware's eeprom-store-i does.
settings.write("whl_active", 1.9)
t.ok("integer slot truncates", settings.read("whl_active") == 1)

-- Addresses must not collide: two settings sharing a slot would silently
-- overwrite each other, and the map is append-only precisely because the
-- indices are on somebody's bike.
local seen = {}
local collision = nil
for name, e in pairs(settings.addrs) do
	if seen[e[1]] then
		collision = string.format("%s and %s both at %d", name, seen[e[1]], e[1])
	end
	seen[e[1]] = name
end
t.ok("no two settings share an address", collision == nil)

-- --- flags ---
vesc.eeprom = {}
t.ok("an unwritten flag takes the default", settings.flag("units_metric", true) == true)
t.ok("and the other default too", settings.flag("units_metric", false) == false)

settings.write("units_metric", 1)
t.ok("a stored one is true", settings.flag("units_metric", false) == true)
settings.write("units_metric", 0)
t.ok("a stored zero is false", settings.flag("units_metric", true) == false)

-- Anything else is treated as unset rather than as true, because a corrupt
-- cell should fall back to the board's default and not to "on".
settings.write("units_metric", 7)
t.ok("a nonsense value takes the default", settings.flag("units_metric", false) == false)

-- --- the settings page, built from the mask ---
-- Bit 0 is the first catalog row, as the mask is written in eeprom.
local one = settings.build(0x1, 0)
t.ok("one bit shows one row", one.num == 1)
t.ok("and it is the first row", one.names[1] == "whl_active")
t.ok("with its label", one.labels[1] == "Wheelie EN")
t.ok("and its limits", one.lims[1][1] == 0 and one.lims[1][2] == 1)

local none = settings.build(0x0, 0)
t.ok("no bits shows nothing", none.num == 0)

-- The mask may select more rows than the page fits; the extras are dropped
-- rather than overflowing it.
local all = settings.build(0xFFFF, 0)
t.ok("the page is capped", all.num == settings.catalog_max)
t.ok("the cap takes the first rows in order", all.names[1] == "whl_active")

-- A gap in the mask picks the right rows, which is the thing an off-by-one
-- in the shift would break.
local gapped = settings.build(0x5, 0)      -- bits 0 and 2
t.ok("gapped mask shows two", gapped.num == 2)
t.ok("gapped mask row 1", gapped.names[1] == "whl_active")
t.ok("gapped mask row 2", gapped.names[2] == "whl_end")

-- The highest bit in the catalog must be reachable: a shift that was one out
-- would silently drop the last setting.
local last = settings.build(1 << (#settings.catalog - 1), 0)
t.ok("the last catalog row is reachable", last.num == 1)
t.ok("and it is the last row", last.names[1] == settings.catalog[#settings.catalog][1])

-- A selection past the end of the new list is reset, or the page would index
-- off it after the mask changed.
local shrunk = settings.build(0x1, 5)
t.ok("a stale selection is reset", shrunk.setting_now == 0)
local kept = settings.build(0xF, 2)
t.ok("a valid selection is kept", kept.setting_now == 2)

-- Every catalog row must name a real setting, or the page would read nil and
-- the guard would quietly show a default for a row that cannot be stored.
local unknown = nil
for _, row in ipairs(settings.catalog) do
	-- theme and smooth are catalog-only in the lisp too: they are in the
	-- settings list but their eeprom slots live in the other address block.
	if not settings.addrs[row[1]] and row[1] ~= "theme" and row[1] ~= "smooth" then
		unknown = row[1]
	end
end
t.ok("every catalog row maps to an address", unknown == nil)

t.report("settings")
