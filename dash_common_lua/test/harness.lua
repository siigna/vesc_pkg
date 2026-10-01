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

return M
