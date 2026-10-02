-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Unit tests for lib/mode.lua. New: the lisp dash has no unit test for the
-- mode-follow rule, which is spread across vehicle-state and communication.
--
-- The rule is worth pinning because both halves of it are about not losing a
-- rider's input: the display's own assertion wins for a window, and an
-- out-of-range report is ignored rather than shown.
local t = require("test.harness")
local mode = require("lib.mode")

local clock = 100.0
mode.now = function() return clock end
mode.secs_since = function(ts) return clock - ts end

mode.num = 5
mode.current = 1
mode.cmd_ts = 0
clock = 100.0      -- well past hold_s since cmd_ts, so not asserting

t.ok("not asserting after a long gap", not mode.asserting())

-- With no recent assertion the controller wins.
t.ok("follows the controller", mode.follow(3))
t.ok("mode adopted",           mode.current == 3)
t.ok("no change is not a change", not mode.follow(3))

-- Asserting locally stamps the clock and holds off the controller.
mode.set(1)
t.ok("set applies immediately", mode.current == 1)
t.ok("asserting after set",     mode.asserting())
t.ok("controller ignored while asserting", not mode.follow(4))
t.ok("mode unchanged",                     mode.current == 1)

-- The window is two seconds; just inside it the display still wins.
clock = clock + mode.hold_s - 0.1
t.ok("still asserting just inside the window", mode.asserting())
t.ok("still ignored", not mode.follow(4))

-- Just outside, the controller wins again.
clock = clock + 0.2
t.ok("no longer asserting", not mode.asserting())
t.ok("controller wins again", mode.follow(4))
t.ok("mode followed",         mode.current == 4)

-- Out of range is ignored rather than displayed.
t.ok("mode at the count is refused", not mode.follow(mode.num))
t.ok("mode past the count is refused", not mode.follow(99))
t.ok("negative mode is refused",       not mode.follow(-1))
t.ok("mode unchanged by refusals",     mode.current == 4)

-- The highest valid index is num - 1. Stepped away first, because follow()
-- reports whether the mode changed and the previous case already left it
-- there -- which is what this check got wrong the first time.
t.ok("step away before the edge case", mode.follow(2))
t.ok("highest valid index accepted", mode.follow(mode.num - 1))
t.ok("highest valid index applied",  mode.current == mode.num - 1)

-- Neutral is 1, which is what the PIN lock and the kickstand assert. Reverse
-- is 0, so a lock that asserted the wrong one would be worse than no lock.
mode.set(1)
t.ok("neutral is index 1", mode.current == 1)

t.report("mode")
