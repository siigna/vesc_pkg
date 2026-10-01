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
	indicate_ms = 0,
	indicator_timestamp = 0,

	kickstand_down = false,

	-- The controller has suspended its drive profile for servicing, and its
	-- stored motor parameters cannot describe a real motor. Both come from
	-- the status frame and both are shown rather than acted on.
	service_mode = false,
	motor_bad = false,

	cruise_control_active = false,
	cruise_control_speed = 0.0,

	-- Pack A is the one the controller reports; B is a second BMS on the bus.
	-- connected means a frame has been seen, which is what separates "0%"
	-- from "no pack".
	battery_a_charging = false,
	battery_a_chg_time = 0,
	battery_a_connected = false,
	battery_b_soc = 0.0,
	battery_b_charging = false,
	battery_b_chg_time = 0,
	battery_b_connected = false,

	kill_sw_active = false,
	aux_on = false,

	page_now = 0,
	page_num = 3,
	setting_now = 0,
	setting_num = 0,

	light_on = false,
	backlight_dim = false,

	-- For changes per-field detection cannot see, such as a unit label swap.
	view_force_static = false,
	view_force_pages = false,

	-- rx flags separate "not reported" from a real zero, which matters for
	-- an ambient temperature and for a clock.
	temp_ambient = 0.0,
	temp_ambient_rx = false,
	date_time = nil,
	date_time_rx = false,

	-- Logging, as the controller reports it.
	log_active = false,

	-- From the controller's status frames. Scaled out of the fixed-point
	-- integers the protocol carries, so these are real units.
	duty = 0.0,
	kmh = 0.0,
	kw = 0.0,
	updated = false,
	temp_battery = 0.0,
	temp_esc = 0.0,
	temp_motor = 0.0,
	angle_pitch = 0.0,
	wh = 0.0,
	wh_chg = 0.0,
	km = 0.0,
	odom = 0.0,
	fault_code = 0,
	amps_avg = 0,
	amps_max = 0,
	amps_now = 0,
	conf_dirty = false,
	esc_pin_holding = false,

	-- Pedal assist, reported by a controller that has it.
	pas_flags = 0,
	pas_output = 0.0,
	pas_cadence = 0.0,
	pas_torque = 0.0,
	pas_rider_w = 0,
	pas_assist_w = 0,
	pas_rx = false,

	-- Maxima since the last session reset. Held separately from the live
	-- values because a reset clears these and not those.
	kmh_max = 0.0,
	kw_max = 0.0,
	amps_now_max = 0.0,
	temp_esc_max = 0.0,
	temp_motor_max = 0.0,
	temp_battery_max = 0.0,
	session_start = 0,

	-- Controller settings, one per frame, filled in as they arrive. seen is
	-- what separates a setting reported as zero from one not yet reported.
	conf_count = 0,
	conf_vals = {},
	conf_gated = {},
	conf_seen = {},
}
