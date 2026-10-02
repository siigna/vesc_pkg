-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Unit tests for lib/units.lua. New: the lisp has none, and a conversion
-- applied twice or not at all is the kind of thing that looks plausible on a
-- dash -- 40 mph and 40 km/h are both believable speeds.
local t = require("test.harness")
local u = require("lib.units")

u.speeds = "kmh"
u.temps = "celsius"
t.near("metric speed is unchanged", u.speed(100.0), 100.0)
t.near("metric distance is unchanged", u.dist(50.0), 50.0)
t.near("celsius is unchanged", u.temp(25.0), 25.0)
t.ok("metric speed label", u.speed_str() == "km/h")
t.ok("metric distance label", u.dist_str() == "km")
t.ok("celsius label", u.temp_str() == "C")
t.ok("metric efficiency label", u.eff_str() == "Wh/km")

u.speeds = "mph"
t.near("100 km/h is 62.1 mph", u.speed(100.0), 62.1371, 0.001)
t.near("distance converts with speed", u.dist(100.0), 62.1371, 0.001)
t.ok("imperial speed label", u.speed_str() == "mph")
t.ok("imperial distance label", u.dist_str() == "mi")
t.ok("imperial efficiency label", u.eff_str() == "Wh/mi")

-- Temperature is a separate setting, so switching speeds must not move it.
t.near("temps unaffected by the speed unit", u.temp(25.0), 25.0)

u.temps = "fahrenheit"
t.near("0 C is 32 F", u.temp(0.0), 32.0)
t.near("100 C is 212 F", u.temp(100.0), 212.0)
t.near("-40 is the same either way", u.temp(-40.0), -40.0)
t.ok("fahrenheit label", u.temp_str() == "F")

u.speeds = "kmh"
u.temps = "celsius"
t.near("back to metric", u.speed(100.0), 100.0)

t.report("units")
