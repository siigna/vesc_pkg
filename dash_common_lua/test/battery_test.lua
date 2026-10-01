-- Unit tests for lib/battery.lua. Pure arithmetic, so no display needed.
--
-- A port of dash_common/test/battery_test.lisp, asserting the same numbers:
-- if the two dashes ever disagree about state of charge, it should show up
-- here rather than as a wrong reading on a bike.

local t = require("test.harness")
local config = require("lib.config")
local state = require("lib.state")
local batt = require("lib.battery")

-- The configuration the tests assume, rather than whichever board's.
config.battery_cells = 12
config.battery_ah = 20.0
config.battery_usable = 0.85
config.discharge_ticks = {3.30, 3.60, 3.68, 3.73, 3.77, 3.81, 3.85, 3.90, 4.00, 4.20}
config.soc_voltage_weight = 0.4
config.soc_source = "esc"
state.vin = 0.0
state.battery_ah = 0.0
state.battery_soc = 0.5

-- --- voltage curve ---
-- Ten ticks, so the states of charge they mark are i/9.
t.near("empty tick",        batt.voltage_soc(12 * 3.30), 0.0)
t.near("full tick",         batt.voltage_soc(12 * 4.20), 1.0)
t.near("below empty",       batt.voltage_soc(12 * 3.00), 0.0)
t.near("above full",        batt.voltage_soc(12 * 4.35), 1.0)
t.near("tick 1",            batt.voltage_soc(12 * 3.60), 1.0 / 9.0)
t.near("tick 7",            batt.voltage_soc(12 * 3.90), 7.0 / 9.0)
t.near("tick 8",            batt.voltage_soc(12 * 4.00), 8.0 / 9.0)
-- Halfway between tick 1 and tick 2, whose states of charge are 1/9 and 2/9.
t.near("interpolated",      batt.voltage_soc(12 * 3.64), 1.5 / 9.0)
-- A quarter of the way from tick 4 (3.77) to tick 5 (3.81).
t.near("interpolated high", batt.voltage_soc(12 * 3.78), 4.25 / 9.0)
t.near("zero volts",        batt.voltage_soc(0.0), 0.0)
t.near("negative volts",    batt.voltage_soc(-5.0), 0.0)

-- Cell count must scale it: the same per-cell voltage on a 6S pack.
config.battery_cells = 6
t.near("6S at tick 7",      batt.voltage_soc(6 * 3.90), 7.0 / 9.0)
config.battery_cells = 12

-- A table too short to interpolate must not divide by zero.
config.discharge_ticks = {3.5}
t.near("one-entry table",   batt.voltage_soc(12 * 3.8), 0.0)
config.discharge_ticks = {3.30, 3.60, 3.68, 3.73, 3.77, 3.81, 3.85, 3.90, 4.00, 4.20}

-- --- coulomb ---
-- Usable capacity is 20 * 0.85 = 17 Ah, so that is what 0% means.
t.near("nothing spent",     batt.coulomb_soc(0.0), 1.0)
t.near("half spent",        batt.coulomb_soc(8.5), 0.5)
t.near("usable exhausted",  batt.coulomb_soc(17.0), 0.0)
t.near("past usable",       batt.coulomb_soc(20.0), 0.0)
t.near("regen past full",   batt.coulomb_soc(-2.0), 1.0)
t.near("usable ah",         batt.usable_ah(), 17.0)

-- --- the blend, and that it is clamped ---
state.vin = 12 * 3.90        -- voltage says 7/9
state.battery_ah = 8.5       -- counting says 0.5
t.near("blend 0.4/0.6", batt.model_soc(), 0.4 * (7.0 / 9.0) + 0.6 * 0.5)

config.soc_voltage_weight = 1.0
t.near("weight 1 is voltage only", batt.model_soc(), 7.0 / 9.0)
config.soc_voltage_weight = 0.0
t.near("weight 0 is counting only", batt.model_soc(), 0.5)
config.soc_voltage_weight = 0.4

-- Both estimates at their extremes must still land inside 0..1.
state.vin = 12 * 4.35
state.battery_ah = -5.0
t.near("clamped high", batt.model_soc(), 1.0)
state.vin = 0.0
state.battery_ah = 99.0
t.near("clamped low", batt.model_soc(), 0.0)

-- --- source selection ---
state.vin = 12 * 3.90
state.battery_ah = 8.5
state.battery_soc = 0.25
config.soc_source = "esc"
t.near("source esc",     batt.soc(), 0.25)
config.soc_source = "voltage"
t.near("source voltage", batt.soc(), 7.0 / 9.0)
config.soc_source = "coulomb"
t.near("source coulomb", batt.soc(), 0.5)
config.soc_source = "model"
t.near("source model",   batt.soc(), 0.4 * (7.0 / 9.0) + 0.6 * 0.5)
config.soc_source = "nonsense"
t.near("unknown source falls back to esc", batt.soc(), 0.25)

t.report("battery")
