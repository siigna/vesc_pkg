-- Unit tests for boot_log.touch_line.
--
-- The point is not the formatting for its own sake: the lisp dash reports the
-- same three numbers in the same words, so a reading from either board says
-- the same thing, and these literals are what hold the two together. The lisp
-- side asserts the identical strings in dash_common/test/bootlog_test.lisp.
--
-- Three numbers because there are three ways touch can be useless on a board
-- where it is the sole input, and they need different fixes: the bus not
-- answering, the panel answering but never reporting a finger, and a finger
-- reported while the regions or the dispatch are wrong.
vesc = require("test.vesc_stub")

local t = require("test.harness")
local boot_log = require("lib.boot_log")
local input = require("lib.input")

input.reads, input.fires = 12, 5
vesc.touch_loaded = function() return true end

-- A healthy bus. The counters are what separate "nobody has touched it" from
-- "it is not reporting".
vesc.touch_stats = function() return 4321, 0, 0 end
t.ok("healthy", boot_log.touch_line() ==
	"touch: bus ok (4321), 12 fingers, 5 actions")

-- A bus that has started failing. The error count and the last error are what
-- say a controller fell off rather than a finger being absent.
vesc.touch_stats = function() return 100, 7, -1 end
t.ok("failing", boot_log.touch_line() ==
	"touch: 100 ok, 7 FAILED, last err -1, 12 fingers")

-- No binding at all, which is a firmware without the counters rather than a
-- panel without a finger. Said rather than guessed at.
local saved = vesc.touch_stats
vesc.touch_stats = nil
t.ok("no binding", boot_log.touch_line() == "touch: no stats binding")
vesc.touch_stats = saved

-- A panel that did not come up at all, which the loaded flag reports and the
-- tallies cannot.
vesc.touch_loaded = function() return false end
vesc.touch_stats = function() return 0, 0, 0 end
t.ok("not loaded", boot_log.touch_line() == "touch: not loaded")

--- the transition watch ---
--
-- Transitions rather than a sample: a line a second would fill the ring with
-- news that nothing has changed. "silent" is not a state change -- a read
-- that neither succeeded nor failed means the poll did not run, which is the
-- scheduler rather than the panel.
-- touch_watch records through boot_log.step, which also prints. Silenced here
-- because on hardware that print is the point and in a suite it is noise.
local real_print = print
print = function() end

vesc.touch_loaded = function() return true end
boot_log.touch_err_last, boot_log.touch_ok_last = 0, 0
boot_log.touch_state = nil
boot_log.own = {}

vesc.touch_stats = function() return 10, 0, 0 end
t.ok("first healthy reading reports", boot_log.touch_watch() ~= nil)
t.ok("and says the bus answers",
	boot_log.own[#boot_log.own]:find("touch bus answering") ~= nil)

t.ok("no change is not reported", boot_log.touch_watch() == nil)

vesc.touch_stats = function() return 10, 3, -1 end
local line = boot_log.touch_watch()
t.ok("a new failure reports", line ~= nil)
t.ok("and names it", line:find("STOPPED ANSWERING") ~= nil)

t.ok("still failing is not re-reported", boot_log.touch_watch() == nil)

vesc.touch_stats = function() return 20, 3, -1 end
line = boot_log.touch_watch()
t.ok("recovery reports", line ~= nil)
t.ok("as a recovery, not a first sighting",
	line:find("answering again") ~= nil)

print = real_print

t.report("boot_log")
