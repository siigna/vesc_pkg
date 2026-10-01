-- Unit tests for the signal request bitfield. A port of
-- dash_common/test/signal_test.lisp, asserting the same values.
--
-- Two rules are the point of it and neither is visible in the bit values: the
-- two indicators cancel each other, because a bike that lit one while the
-- other was on would be lying about which way it is going; and the horn is
-- not latched, because a latched horn is a stuck horn.
local t = require("test.harness")
local state = require("lib.state")
local sig = require("lib.signals")

-- A clock the test drives, rather than sleeping through a blip as the lisp
-- test does. now() counts in seconds here, which is all secs_since needs.
local clock = 1000.0
sig.now = function() return clock end
sig.secs_since = function(ts) return clock - ts end

-- Far enough past rx_last that nothing is reporting, which is the fallback
-- case the first half of this test is about.
sig.rx_last = 0

sig.req = 0
t.ok("clean start", not sig.on(sig.LEFT))
t.ok("clean byte",  sig.byte(false) == 0)

-- Latching, and toggling back off.
sig.toggle(sig.LEFT)
t.ok("left on",       sig.on(sig.LEFT))
t.ok("left byte",     sig.byte(false) == sig.LEFT)
sig.toggle(sig.LEFT)
t.ok("left off",      not sig.on(sig.LEFT))
t.ok("left off byte", sig.byte(false) == 0)

-- The indicators cancel each other rather than both being on.
sig.toggle(sig.LEFT)
sig.toggle(sig.RIGHT)
t.ok("right wins",     sig.on(sig.RIGHT))
t.ok("left cleared",   not sig.on(sig.LEFT))
sig.toggle(sig.LEFT)
t.ok("left wins back", sig.on(sig.LEFT))
t.ok("right cleared",  not sig.on(sig.RIGHT))

-- Hazard is independent of both, and turning an indicator on must not clear it.
sig.toggle(sig.HAZARD)
t.ok("hazard on",            sig.on(sig.HAZARD))
t.ok("left still on",        sig.on(sig.LEFT))
sig.toggle(sig.RIGHT)
t.ok("hazard survives",      sig.on(sig.HAZARD))
t.ok("right on with hazard", sig.on(sig.RIGHT))
t.ok("left off with hazard", not sig.on(sig.LEFT))

-- The beam is independent of everything.
sig.toggle(sig.BEAM)
t.ok("beam on",          sig.on(sig.BEAM))
t.ok("hazard untouched", sig.on(sig.HAZARD))
sig.toggle(sig.BEAM)
t.ok("beam off",         not sig.on(sig.BEAM))

-- The horn is never latched, whatever else is set.
sig.req = 0
sig.toggle(sig.HORN)
t.ok("horn not in byte",  (sig.byte(false) & sig.HORN) == 0)
t.ok("horn on when held", (sig.byte(true) & sig.HORN) == sig.HORN)

-- A blip sets it for as long as the blip lasts, then clears itself.
sig.req = 0
sig.horn_ts = 0
t.ok("not blipping", not sig.horn_blipping())
sig.horn_blip()
t.ok("blipping",     sig.horn_blipping())
t.ok("blip in byte", (sig.byte(false) & sig.HORN) == sig.HORN)
clock = clock + sig.horn_blip_s + 0.1
t.ok("blip expired",        not sig.horn_blipping())
t.ok("blip gone from byte", (sig.byte(false) & sig.HORN) == 0)

-- Everything at once still fits in a byte, which is all there is on the wire.
sig.req = 0
sig.toggle(sig.HAZARD)
sig.toggle(sig.LEFT)
sig.toggle(sig.BEAM)
t.ok("all set", sig.byte(true) == (sig.HAZARD | sig.LEFT | sig.BEAM | sig.HORN))
t.ok("fits in a byte", sig.byte(true) <= 255)

-- What the strip shows. With a node reporting, the received values; without
-- one, the request -- and hazard lights both sides either way it is asked.
sig.req = 0
state.indicate_l_on = true
state.indicate_r_on = false
state.highbeam_on = true
sig.rx_last = clock                 -- reporting, as of now
t.ok("reported left",  sig.l_shown())
t.ok("reported right", not sig.r_shown())
t.ok("reported beam",  sig.beam_shown())

sig.rx_last = clock - sig.rx_timeout - 1.0    -- stale, so fall back
t.ok("fallback left off", not sig.l_shown())
t.ok("fallback beam off", not sig.beam_shown())
sig.toggle(sig.HAZARD)
t.ok("hazard lights left",  sig.l_shown())
t.ok("hazard lights right", sig.r_shown())
sig.toggle(sig.HAZARD)
sig.toggle(sig.RIGHT)
t.ok("fallback right only",     sig.r_shown())
t.ok("fallback left still off", not sig.l_shown())

t.report("signal")
