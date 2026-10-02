-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Shared assertions for the dash unit tests.
--
-- near() rather than equality for everything numeric: these are fractions
-- derived through division, and the firmware's Lua is LUA_32BITS where the
-- host's is not, so exact comparison would pass here and fail on target.
local M = {checks = 0, fails = 0}

function M.near(what, got, want, tol)
	M.checks = M.checks + 1
	tol = tol or 0.001
	if type(got) ~= "number" or math.abs(got - want) > tol then
		M.fails = M.fails + 1
		print(string.format("FAIL %s: got %s want %s", what, tostring(got), tostring(want)))
	end
end

function M.ok(what, cond)
	M.checks = M.checks + 1
	if not cond then
		M.fails = M.fails + 1
		print("FAIL " .. what)
	end
end

function M.report(name)
	print(string.format("%s: %d checks, %d failures", name, M.checks, M.fails))
	if M.fails > 0 then
		os.exit(1)
	end
end

-- Make a read of an undefined global an error.
--
-- Lua resolves an unknown name to nil silently, so a local referenced before
-- its definition -- or a typo -- is a nil call at the point of use and
-- nowhere else. That cost a round trip: `guard` in lib/dash.lua was defined
-- below one of its callers, so inside that caller it resolved as a global,
-- and calling nil took down the tick. luac -p cannot see it, because the
-- lookup is legal; only running the code finds it.
--
-- Opt-in per test file, after the requires, so a module that legitimately
-- writes a global at load time is unaffected.
function M.strict_globals()
	setmetatable(_G, {
		__index = function(_, k)
			error("read of undefined global '" .. tostring(k) .. "'", 2)
		end,
	})
end

function M.unstrict_globals()
	setmetatable(_G, nil)
end

return M
