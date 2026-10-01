-- Unit tests for the statistics sampler: lib/statistics.lua tick().
--
-- A port of the stats-thread body in dash_common/lib/statistics.lisp, which
-- has no test of its own. What is worth pinning is the part that is not a
-- plain maximum: the two timers only accumulate when an interval closes, the
-- voltage floor ignores the zero it reads before the first frame, the fault
-- list keeps first appearances, and a reset clears the session without
-- touching the live values.
local t = require("test.harness")
local state = require("lib.state")
local stats = require("lib.statistics")

local clock = 0          -- systime, in ms
stats.now = function() return clock end

-- Live fields the sampler folds in, back to the state defaults.
local function reset_live()
	state.kmh, state.kw = 0.0, 0.0
	state.temp_battery, state.temp_esc, state.temp_motor = 0.0, 0.0, 0.0
	state.amps_now, state.fault_code, state.vin = 0.0, 0, 0.0
	state.kmh_max, state.kw_max = 0.0, 0.0
	state.temp_battery_max, state.temp_esc_max, state.temp_motor_max = 0.0, 0.0, 0.0
	state.amps_now_max, state.amps_now_min = 0.0, 0.0
	state.vin_min = nil
	state.fault_codes_observed = {}
	state.active_timer, state.active_timestamp = 0, nil
	state.elapsed_timer, state.elapsed_timestamp = 0, nil
	stats.chart_tick = 0
	stats.reset_now = false
	stats.chart_reset()
	clock = 0
end

--- maxima ---
reset_live()

state.kmh, state.kw = 31.5, 2.25
state.temp_motor, state.temp_esc, state.temp_battery = 64.0, 51.0, 28.0
state.amps_now = 84.0
stats.tick(0)

t.near("speed max taken",   state.kmh_max, 31.5)
t.near("power max taken",   state.kw_max, 2.25)
t.near("motor temp max",    state.temp_motor_max, 64.0)
t.near("esc temp max",      state.temp_esc_max, 51.0)
t.near("pack temp max",     state.temp_battery_max, 28.0)
t.near("amps max",          state.amps_now_max, 84.0)
t.near("amps min untouched by a positive current", state.amps_now_min, 0.0)

-- A lower reading does not lower a maximum.
state.kmh, state.amps_now = 12.0, 10.0
stats.tick(0)
t.near("speed max held", state.kmh_max, 31.5)
t.near("amps max held",  state.amps_now_max, 84.0)

-- Regen is a negative motor current, and the minimum is what records it.
state.amps_now = -37.5
stats.tick(0)
t.near("regen recorded as the minimum", state.amps_now_min, -37.5)
t.near("and not as a maximum",          state.amps_now_max, 84.0)

--- the voltage floor ---
--
-- Zero is what vin reads before any frame arrives. Taking it would stick the
-- floor at zero for the whole session.
reset_live()
stats.tick(0)
t.ok("no floor before a frame", state.vin_min == nil)

state.vin = 58.2
stats.tick(0)
t.near("first real reading sets the floor", state.vin_min, 58.2)

state.vin = 61.0
stats.tick(0)
t.near("a higher voltage does not raise it", state.vin_min, 58.2)

state.vin = 49.7
stats.tick(0)
t.near("sag lowers it", state.vin_min, 49.7)

state.vin = 0.0
stats.tick(0)
t.near("a zero after a real reading is still ignored", state.vin_min, 49.7)

--- fault codes ---
reset_live()
stats.tick(0)
t.ok("no faults seen", #state.fault_codes_observed == 0)

state.fault_code = 0
stats.tick(0)
t.ok("zero is not a code", #state.fault_codes_observed == 0)

state.fault_code = 3
stats.tick(0)
stats.tick(0)
t.ok("a code is recorded once", #state.fault_codes_observed == 1)
t.ok("and it is the code",      state.fault_codes_observed[1] == 3)

state.fault_code = 7
stats.tick(0)
state.fault_code = 3
stats.tick(0)
t.ok("a second distinct code appends", #state.fault_codes_observed == 2)
t.ok("in first-appearance order",
	state.fault_codes_observed[1] == 3 and state.fault_codes_observed[2] == 7)

--- the elapsed timer ---
--
-- Runs from the first tick onward, moving or not.
reset_live()
clock = 5000
stats.tick(0)
t.ok("elapsed opens on the first tick", state.elapsed_timestamp == 5000)
t.near("and reads zero at that instant", stats.elapsed_secs(), 0.0)

clock = 12500
t.near("elapsed counts the open interval", stats.elapsed_secs(), 7.5)
stats.tick(0)
t.ok("and the open interval is not closed", state.elapsed_timestamp == 5000)
t.near("still 7.5 after a tick", stats.elapsed_secs(), 7.5)

--- the moving timer ---
--
-- Only accumulates while there is speed, and only when the interval closes,
-- which is why the live reader adds the open one.
reset_live()
clock = 1000
stats.tick(0)
t.ok("stationary opens no interval", state.active_timestamp == nil)
t.near("moving time is zero",        stats.moving_secs(), 0.0)

state.kmh = 20.0
clock = 2000
stats.tick(0)
t.ok("moving opens an interval", state.active_timestamp == 2000)
t.near("accumulator still empty", state.active_timer, 0.0)

clock = 6000
t.near("the open interval is counted live", stats.moving_secs(), 4.0)
stats.tick(0)
t.ok("still open while moving", state.active_timestamp == 2000)

state.kmh = 0.0
clock = 8000
stats.tick(0)
t.ok("stopping closes the interval", state.active_timestamp == nil)
t.near("and banks it",               state.active_timer, 6000)
t.near("moving time is the bank",    stats.moving_secs(), 6.0)

-- Moving again opens a second interval, which adds to the bank.
state.kmh = 15.0
clock = 9000
stats.tick(0)
clock = 11000
t.near("a second interval adds to the bank", stats.moving_secs(), 8.0)
state.kmh = 0.0
stats.tick(0)
t.near("banked after the second stop", state.active_timer, 8000)

-- Reverse is neither: kmh < 0 passes neither guard, so an interval neither
-- opens nor closes. That is the lisp's behaviour -- its two conditions test
-- > 0.0 and = 0.0 -- and it is why this is asserted rather than assumed.
reset_live()
state.kmh = -5.0
clock = 1000
stats.tick(0)
t.ok("reverse opens no interval", state.active_timestamp == nil)

--- average speed ---
--
-- Over moving time, and only once there is more than a second of it: a
-- distance divided by a tenth of a second is a number nobody should see.
reset_live()
state.km = 10.0
t.near("no average without moving time", stats.avg_kmh(), 0.0)

state.active_timer = 900                 -- 0.9 s, under the guard
t.near("still none just under a second", stats.avg_kmh(), 0.0)

state.active_timer = 1800000             -- 30 minutes
t.near("10 km in half an hour is 20 km/h", stats.avg_kmh(), 20.0)

--- the chart divider ---
--
-- The base tick is the input rate; chart_div is what brings the sample rate
-- back to the 10 Hz the controller sends at. Pushing every tick would
-- duplicate values and make the window shorter than the setting says.
reset_live()
state.kmh = 42.0
stats.chart_div = 5

for _ = 1, 4 do stats.tick(0) end
t.ok("nothing pushed before the divider closes", stats.chart_count == 0)

stats.tick(0)
t.ok("the fifth tick pushes",  stats.chart_count == 1)
t.near("and pushes the slot value", stats.chart_at(0), 42.0)

for _ = 1, 5 do stats.tick(0) end
t.ok("and again five ticks later", stats.chart_count == 2)

-- The slot the chart reads is the argument, not a fixed field.
state.vin = 57.0
for _ = 1, 5 do stats.tick(5) end
t.near("the charted source is the one asked for", stats.chart_at(0), 57.0)

--- reset ---
--
-- A request, applied at the top of the next tick, so it cannot land between
-- the maxima and the timers and clear half a session.
reset_live()
state.kmh, state.vin, state.amps_now = 44.0, 50.0, 90.0
clock = 1000
stats.tick(0)
clock = 4000
state.kmh = 0.0
stats.tick(0)

t.near("a session accumulated: speed max", state.kmh_max, 44.0)
t.near("voltage floor",                    state.vin_min, 50.0)
t.near("moving banked",                    state.active_timer, 3000)

stats.reset_max()
t.ok("the request is pending",        stats.reset_now)
t.near("and changes nothing by itself", state.kmh_max, 44.0)

stats.tick(0)
t.ok("applied on the next tick", not stats.reset_now)
t.near("moving timer cleared",   state.active_timer, 0.0)
t.ok("moving interval closed",   state.active_timestamp == nil)
t.near("elapsed timer cleared",  state.elapsed_timer, 0.0)

-- A maximum of something still happening comes straight back, because the
-- clear is at the top of the tick and the fold is below it. So the reset
-- forgets the session, not the present: speed is zero here and clears, while
-- the 90 A and the 50 V still being reported are re-taken on the same pass.
-- Anything else would show a top speed below the speed on the screen.
t.near("speed max cleared, since speed is zero", state.kmh_max, 0.0)
t.near("a live current is re-taken",             state.amps_now_max, 90.0)
t.near("and a live voltage re-floors",           state.vin_min, 50.0)

-- The live values survive a reset: it clears the session, not the vehicle.
t.near("live voltage untouched", state.vin, 50.0)

-- The elapsed timer reopens on the same tick it was cleared, which is what
-- makes a reset the start of a new session rather than a gap.
t.ok("elapsed reopened", state.elapsed_timestamp ~= nil)

t.report("stats")
