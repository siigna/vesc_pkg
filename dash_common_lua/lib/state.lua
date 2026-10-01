-- Live values, written by whichever thread owns them and read everywhere.
-- The lisp dash keeps these as stats-* globals; one table is the same thing
-- with a name on it.
return {
	vin = 0.0,
	battery_ah = 0.0,
	battery_soc = 0.5,

	-- Reported by a bike-controls node on the bus, when there is one. Read by
	-- lib/signals.lua, which falls back to its own requests without one.
	indicate_l_on = false,
	indicate_r_on = false,
	highbeam_on = false,
}
