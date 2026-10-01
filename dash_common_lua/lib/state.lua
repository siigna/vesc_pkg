-- Live values, written by whichever thread owns them and read everywhere.
-- The lisp dash keeps these as stats-* globals; one table is the same thing
-- with a name on it.
return {
	vin = 0.0,
	battery_ah = 0.0,
	battery_soc = 0.5,
}
