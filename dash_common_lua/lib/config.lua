-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Board constants. A board package overwrites these fields before loading
-- anything that reads them; the values here are the placeholders the lisp
-- dash also ships, and they are deliberately conservative rather than
-- plausible, so an unconfigured pack reads obviously wrong instead of
-- subtly wrong.
return {
	battery_cells = 12,
	battery_ah = 20.0,
	battery_usable = 0.85,

	-- Per-cell voltages at equally spaced states of charge, empty first.
	discharge_ticks = {3.30, 3.60, 3.68, 3.73, 3.77, 3.81, 3.85, 3.90, 4.00, 4.20},

	-- 1.0 is voltage only, 0.0 is coulomb counting only.
	soc_voltage_weight = 0.4,

	-- "esc", "voltage", "coulomb" or "model".
	soc_source = "esc",
}
