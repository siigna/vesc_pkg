-- Unit tests for the PIN lock. A port of dash_common/test/pin_test.lisp.
--
-- It is a deterrent rather than security -- the code is plain in eeprom -- so
-- what is worth testing is that it behaves like a lock, and that the drive
-- mode it asserts is neutral and not something that moves.
local t = require("test.harness")
local pin = require("lib.pin")

-- A clock the test drives. The lisp version sleeps 1.1 s to watch a lockout
-- expire; this advances a number, which is instant and cannot flake on a
-- loaded machine.
local clock = 5000.0
pin.now = function() return clock end
pin.secs_since = function(ts) return clock - ts end

local sends = {}
pin.on_lock = function() table.insert(sends, 1, "lock") end
pin.on_unlock = function() table.insert(sends, 1, "unlock") end

local function enter(digits)
	for _, d in ipairs(digits) do
		pin.key(d)
	end
end

pin.code = 1234
pin.drive_mode = 4

-- Unlocked to begin with, and the stored mode goes out untouched.
t.ok("starts unlocked",     not pin.locked)
t.ok("mode passes through", pin.get_drive_mode() == 4)

-- Engaging asserts neutral, which is index 1 and the mode whose current
-- scale is zero. Index 0 is reverse, so getting this wrong would be worse
-- than not locking at all.
pin.engage()
t.ok("engaged",              pin.locked)
t.ok("asserts neutral",      pin.get_drive_mode() == 1)
t.ok("stored mode untouched", pin.drive_mode == 4)
t.ok("lock sent",            sends[1] == "lock")

-- The right code, a digit at a time, opens it on the fourth without OK.
enter({1, 2, 3, 4})
t.ok("unlocked",      not pin.locked)
t.ok("mode restored", pin.get_drive_mode() == 4)
t.ok("unlock sent",   sends[1] == "unlock")
t.ok("entry cleared", pin.entry_len == 0)

-- A wrong code does not, and leaves nothing half-entered behind.
pin.engage()
enter({1, 2, 3, 5})
t.ok("wrong stays locked",  pin.locked)
t.ok("wrong clears entry",  pin.entry_len == 0)

-- A partial code plus OK is a wrong code rather than a no-op.
pin.clear()
enter({1, 2})
pin.key(-2)
t.ok("short stays locked", pin.locked)
t.ok("short clears entry", pin.entry_len == 0)

-- Clear does what it says, and does not unlock anything.
enter({1, 2, 3})
t.ok("three entered", pin.entry_len == 3)
pin.key(-1)
t.ok("cleared",               pin.entry_len == 0)
t.ok("clear does not unlock", pin.locked)

-- The entry never holds more than the code length. A fourth digit submits and
-- clears, so a fifth press starts a new attempt rather than extending the old
-- one -- which is why this checks the invariant over a long run of presses.
pin.clear()
local over_len = false
for _ = 1, 20 do
	pin.key(9)
	if pin.entry_len > pin.len then
		over_len = true
	end
end
t.ok("never over length", not over_len)
t.ok("still locked",      pin.locked)

-- The lockout escalates after three wrong tries and blocks input while it runs.
pin.tries = 0
pin.wait_s = 0
pin.tick()
t.ok("not waiting yet", not pin.waiting())
for _ = 1, 3 do enter({0, 0, 0, 0}) end
pin.tick()
t.ok("three tries free", not pin.waiting())
enter({0, 0, 0, 0})
pin.tick()
t.ok("fourth try waits", pin.waiting())

-- A correct code typed during the wait is ignored rather than accepted.
enter({1, 2, 3, 4})
t.ok("locked during wait", pin.locked)
t.ok("keys ignored",       pin.entry_len == 0)

-- The wait expires, and then the correct code works.
pin.wait_s = 1
pin.wait_ts = clock
pin.tick()
t.ok("waiting one second", pin.waiting())
clock = clock + 1.1
pin.tick()
t.ok("wait expired", not pin.waiting())
enter({1, 2, 3, 4})
t.ok("unlocks after wait", not pin.locked)

-- The wait is capped, or a few fat-fingered tries would strand a rider.
pin.engage()
pin.tries = 0
for _ = 1, 40 do
	pin.wait_s = 0
	pin.wait_left = 0
	enter({0, 0, 0, 0})
end
t.ok("wait capped", pin.wait_s <= 60)

-- A code of zero is a usable code, not "no code": whether the lock is on at
-- all is a separate setting, so 0000 must not unlock a bike set to 1234.
pin.code = 0
pin.engage()
enter({0, 0, 0, 0})
t.ok("zero code works", not pin.locked)
pin.code = 1234
pin.engage()
enter({0, 0, 0, 0})
t.ok("zero is not a master code", pin.locked)

-- Presentation: the dots track the entry, and the wait message takes
-- precedence over a sticky notification.
pin.clear()
t.ok("dots empty",  pin.dots() == "- - - - ")
enter({1, 2})
t.ok("dots partial", pin.dots() == "* * - - ")
pin.wait_left = 7
t.ok("wait message wins", pin.msg() == "wait 7 s")
pin.wait_left = 0
pin.notify("Wrong code")
t.ok("notification shows", pin.msg() == "Wrong code")
clock = clock + 2.5
t.ok("notification expires", pin.msg() == "")

t.report("pin")
