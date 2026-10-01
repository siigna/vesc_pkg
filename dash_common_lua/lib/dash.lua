-- The runtime: what runs, how often, and in what order.
--
-- Ported from main() and the thread set in dash_common/main_body.lisp, plus
-- comm-tx-thread from lib/communication.lisp and the splash.
--
-- The lisp runs eight threads. This engine has one timer and no threads, so
-- the threads become one tick function and a divider each. That is a real
-- change rather than a transcription, and it has two consequences worth
-- stating:
--
--   Everything is serialised. A page that takes 15 ms to draw delays the
--   next input poll by that much, where the lisp would have preempted it.
--   The base period is the input rate for that reason -- it is the only one
--   a rider can feel -- and the heavy work is divided down.
--
--   Nothing can crash independently. The lisp wraps each thread in a trap
--   and restarts it after five seconds, so a broken page costs that page.
--   Here one raise would take the whole timer down, so each step is called
--   through a guard that reports and continues. A page that fails every
--   frame prints every frame, which is noisy and the right trade: the dash
--   keeps running and says what is wrong.
--
-- Rates, against the lisp's:
--
--   input       50 Hz   same
--   stats       50 Hz   lisp 20 Hz; idempotent, and the chart divides itself
--                       down to the controller's 10 Hz either way
--   pages       25 Hz   lisp 20 Hz
--   static      25 Hz   lisp 20 Hz
--   tx          10 Hz   same, and the controller's expiry window depends on
--                       it: walk assist is dropped after 0.5 s
--   worker      10 Hz   same
--   standalone  10 Hz   same
--   notify       5 Hz   same

local state = require("lib.state")
local settings = require("lib.settings")
local apply = require("lib.apply")
local units = require("lib.units")
local colors = require("lib.colors")
local du = require("lib.draw_utils")
local mode = require("lib.mode")
local pin = require("lib.pin")
local signals = require("lib.signals")
local comms = require("lib.comms")
local stats = require("lib.statistics")
local standalone = require("lib.standalone")
local notify = require("lib.notify")
local input = require("lib.input")
local boot_log = require("lib.boot_log")
local appdata = require("lib.appdata")
local actions = require("lib.actions")
local pages = require("lib.pages")
local vp = require("lib.view_pages")
local vs = require("lib.view_static")

local M = {}

--- what the board supplies ---

M.cfg = nil
M.bl_set = function(_) end
M.version = "lua"

-- The base tick, in milliseconds, and how many of them each job waits for.
M.period_ms = 20
M.div = {
	input = 1,
	stats = 1,
	pages = 2,
	static = 2,
	tx = 5,
	worker = 5,
	standalone = 5,
	notify = 10,
	frames = 3,
	-- Once a second. The touch tallies only need watching for a transition,
	-- and the panel is polled fifty times in that window, so a change cannot
	-- hide between checks.
	touch_watch = 50,
}

--- transmit ---
--
-- SID 201 every 100 ms, which is well inside the half second the controller
-- allows before it expires a walk request, and the five seconds before it
-- decides this display is gone.
--
-- pin.get_drive_mode(), not mode.current: while the lock is up this asserts
-- neutral, whose current scale is zero, and leaves the stored mode alone so
-- unlocking restores it.
function M.tx_step()
	comms.send(201, comms.build_201(
		pin.get_drive_mode(),
		state.light_on,
		actions.walk_requested(),
		signals.byte(actions.horn_held())))

	comms.send(202, comms.build_202(
		settings.read("whl_active") or 0,
		settings.read("whl_start") or 0.0,
		settings.read("whl_end") or 0.0,
		settings.read("whl_kd") or 0.0))
end

--- queued frames ---
--
-- The PIN lock commands go out three times because they are single frames
-- with no acknowledgement, and a lost unlock leaves a rider tapping a correct
-- code at a bike that will not move. The lisp sleeps 60 ms between them. A
-- timer callback must not sleep, so they are queued and drained one per
-- frames-divider tick, which is the same spacing.
M.pending = {}

function M.queue(id, frames)
	for _, f in ipairs(frames) do
		M.pending[#M.pending + 1] = {id, f}
	end
end

function M.drain_step()
	local f = table.remove(M.pending, 1)
	if f then
		comms.send(f[1], f[2])
	end
end

--- the worker pass ---

function M.worker_step()
	if state.settings_redraw then
		apply.visual()
	end

	-- Neutral when charging or when the kickstand is down. Asserted rather
	-- than requested: mode.set stamps the clock, so the controller's echo of
	-- the old mode loses for the next two seconds.
	if state.battery_a_charging then
		mode.set(1)
	end
	if state.kickstand_down then
		mode.set(1)
	end

	-- Counted down here rather than in the view, so the keypad redraws when
	-- the number changes and not every frame.
	pin.tick()

	-- Nothing may navigate off the keypad. The press dispatch already refuses
	-- to and so does the swipe, but a notification path or a second display
	-- could still move the page, and the cost of being wrong is a bike that
	-- drives while it is supposed to be locked.
	if pin.locked and not pages.pin_showing() then
		pages.show_pin()
	end

	-- Unlocking leaves the keypad up until something moves off it.
	if not pin.locked and pages.pin_showing() then
		state.page_now = 0
	end
end

--- the views ---

-- The two overlays cover the whole panel above the nav strip, so the strip,
-- the speed and the battery bar stop repainting while one is up or they would
-- draw over it a field at a time. Holding the force flag means closing the
-- overlay repaints the lot: their dirty tracking was paused and has no idea
-- what the overlay covered.
function M.static_step()
	if pages.overlay_showing() then
		state.view_force_static = true
	else
		vs.step()
	end
end

--- the splash ---

function M.splash()
	local L = vs.layout
	local h = 60

	local buf = vesc.img_buffer("indexed4", L.disp_w, h)
	buf:clear()
	du.ttf_txt_center("VESC", M.font_40, buf)
	vesc.disp_render(buf, 0, L.disp_h // 2 - 50, colors.vesc_logo)

	local ver = vesc.img_buffer("indexed4", L.disp_w, 30)
	ver:clear()
	du.ttf_txt_center(M.version, M.font_24, ver)
	vesc.disp_render(ver, 0, L.disp_h // 2 + 20, colors.text_aa)

	vesc.sleep(1.5)
	vesc.disp_clear(colors.bg)
end

-- How long the boot log is held on screen after the splash. Zero is off.
--
-- The whole panel, not the page area: this runs before the static strip is
-- drawn, so there is nothing to draw around. It is the one place the log is
-- reachable without a stored setting, which matters because the thing it
-- reports on is bring-up -- and a display that came up wrong is exactly the
-- one whose settings cannot be trusted to let you navigate to a page.
--
-- It is also the only place it is reachable at all on this board. Reading the
-- ring over serial resets the chip on the way in, because DTR and RTS drive
-- EN on the bridge and --no-reset does not work on it -- so by the time the
-- dump arrives it is a dump of a board that just booted. Whatever happened
-- before has to be read off the glass or not at all.
M.boot_log_s = 0.0

-- While the log is up, the bottom line is a live touch probe rather than
-- another log line.
--
-- This is the part worth having. Touch has three separable failure modes and
-- they need different fixes -- the bus not answering, the panel answering but
-- never reporting a finger, and a finger reported at coordinates the region
-- map reads differently than intended -- and a raw x,y with the region it
-- resolves to tells them apart in one press, with no cable and nothing to
-- navigate to.
function M.touch_probe_line()
	local x, y = nil, nil
	local okr, rx, ry = pcall(vesc.touch_read)
	if okr then
		x, y = rx, ry
	end

	local ok, err = 0, 0
	if vesc.touch_stats then
		ok, err = vesc.touch_stats()
	end

	if x == nil then
		return string.format(
			"touch: press the screen.  bus ok %d, err %d, fingers %d",
			ok, err, input.reads)
	end

	return string.format(
		"touch: x=%d y=%d -> region %s   (nav_y %d, w %d)  fingers %d",
		x, y, tostring(input.region(x, y)), input.nav_y, input.disp_w,
		input.reads)
end

function M.boot_log_splash()
	local L = vs.layout

	-- The row pitch comes from the font, not from a constant: the gap wanted
	-- is a few pixels, and how tall a line is belongs to the font.
	local _, cap = M.font_16:glyph_dims("D")
	local line_h = cap + 6
	local top = 6
	local rows = (L.disp_h - top * 2) // line_h

	local lines = boot_log.lines()
	-- One row is given to the probe, which redraws on its own.
	local log_rows = rows - 1
	local first = #lines - log_rows + 1
	if first < 1 then
		first = 1
	end

	local img = vesc.img_buffer("indexed2", L.disp_w, log_rows * line_h)
	img:clear()

	local r = 0
	for i = first, #lines do
		-- Through the helper, which puts the baseline where the font says
		-- rather than at the row's top edge. Getting that wrong rendered the
		-- first line as nothing and the last as its bottom two pixels.
		du.ttf_txt_left(lines[i], M.font_16, img, 8, r * line_h, {0, 1})
		r = r + 1
	end

	vesc.disp_clear(colors.bg)
	vesc.disp_render(img, 0, top, colors.text_2)

	-- The probe line's buffer and position are kept for boot_log_probe,
	-- which the tick calls: this draws the log once and the probe updates
	-- over it.
	M.probe_img = vesc.img_buffer("indexed2", L.disp_w, line_h)
	M.probe_y = top + log_rows * line_h
	M.probe_shown = nil
end

-- One update of the probe line under the boot log. Called from the tick, so
-- the finger is read at the input rate and the text is redrawn only when it
-- changes -- a still finger costs nothing.
function M.boot_log_probe()
	if not M.probe_img then
		return
	end

	local txt = M.touch_probe_line()
	if txt == M.probe_shown then
		return
	end

	M.probe_shown = txt
	M.probe_img:clear()
	du.ttf_txt_left(txt, M.font_16, M.probe_img, 8, 0, {0, 1})
	vesc.disp_render(M.probe_img, 0, M.probe_y, colors.theme_2)
end

-- Faults are reported and swallowed. See the note at the top: one raise here
-- would take the timer down, and with it the whole UI.
--
-- guard is a local, so it has to be defined above everything that calls it.
-- That is not style: with this block below the region overlay, `guard` inside
-- region_step resolved as a global, which is nil, and calling it took down
-- the tick before anything was drawn. The symptom was an overlay that never
-- appeared while the timing showed the views correctly standing down for
-- it -- so the state machine looked right and the thing that would have
-- reported the fault was the thing that was missing.
M.fail_count = {}

--- timing ---
--
-- Microseconds per job, accumulated, and the tick count they cover. With one
-- timer and no threads every job's cost lands on the same budget, so "the
-- dash uses N% of a core" is not actionable on its own -- which job is has to
-- be measurable or the answer is guesswork. It was: a six-fold CPU rise after
-- a change that touched eight files had no obvious owner until this existed.
--
-- vesc.micros rather than systime, which is milliseconds and too coarse for
-- one pass. Off by default: a clock read per job is cheap but not free, and
-- the measurement should not be part of what is measured.
M.timing = false
M.job_us = {}
M.job_ticks = 0

local function guard(name, fn)
	local t0 = M.timing and vesc.micros() or 0

	local ok, err = pcall(fn)
	if not ok then
		M.fail_count[name] = (M.fail_count[name] or 0) + 1
		print(name, "failed:", err)
	end

	if M.timing then
		M.job_us[name] = (M.job_us[name] or 0) + (vesc.micros() - t0)
	end
end

-- Average microseconds per tick for each job, highest first, as one line.
function M.timing_report()
	local n = M.job_ticks > 0 and M.job_ticks or 1
	local rows = {}
	for name, us in pairs(M.job_us) do
		rows[#rows + 1] = {name, us / n}
	end
	table.sort(rows, function(a, b) return a[2] > b[2] end)

	local total = 0
	local parts = {}
	for _, r in ipairs(rows) do
		total = total + r[2]
		parts[#parts + 1] = string.format("%s %.0f", r[1], r[2])
	end

	return string.format("tick %.0f us over %d ticks (%.1f%% of %d ms): %s",
		total, M.job_ticks, 100.0 * total / (M.period_ms * 1000.0),
		M.period_ms, table.concat(parts, ", "))
end

function M.timing_reset()
	M.job_us = {}
	M.job_ticks = 0
end

--- the touch region overlay ---
--
-- The four virtual buttons, drawn over the running dash for a few seconds so
-- the regions can be seen rather than inferred from the source.
--
-- After the dash is up, not during bring-up: the point is to show where the
-- regions fall on the screen as it actually looks, and the boot log has the
-- panel to itself.
--
-- Every label is read back out of input.region at the point it is drawn, so
-- the overlay reports the map rather than restating it. If the two ever
-- disagree -- a panel reporting mirrored coordinates, a layout change that
-- moved nav_y -- the overlay shows the region that is really there, which is
-- the whole reason to draw it.
M.region_overlay_s = 0.0

-- Print every app data packet as it arrives. Off by default; the UI sends one
-- per keystroke in places.
M.appdata_trace = false

-- Let the dash draw itself first, so the overlay sits on the real screen.
M.region_overlay_delay_s = 1.0

M.region_state = nil
M.region_until = 0.0

-- One region's box and label. x, y, w, h is the area; the text comes from
-- whatever input.region says about its centre.
function M.region_box(x, y, w, h)
	local cx = x + w // 2
	local cy = y + h // 2
	local r = input.region(cx, cy)

	local a = r and settings.values.btn_short[r + 1] or 0
	local al = r and settings.values.btn_long[r + 1] or 0

	local img = vesc.img_buffer("indexed4", w, h)
	img:clear()
	img:rectangle(0, 0, w - 1, h - 1, 1, false, 1, 0)

	local function name(id)
		local l = vp.shade_label(id)
		return l ~= "" and l or ("action " .. id)
	end

	local _, cap = M.font_16:glyph_dims("D")
	local line_h = cap + 6

	-- As many rows as fit, and a compact single line when only one does.
	-- The nav strip is 35 pixels on this panel, which is one row: laying out
	-- four and letting the rest fall outside drew two of them on top of each
	-- other and the border, because the baseline arithmetic happily goes
	-- negative.
	local fit = h // line_h
	if fit < 1 then
		fit = 1
	end

	local rows
	if fit == 1 then
		rows = {string.format("REGION %s - %s", tostring(r), name(a))}
	else
		rows = {
			string.format("REGION %s", tostring(r)),
			"tap: " .. name(a),
			"hold: " .. name(al),
			string.format("x %d..%d  y %d..%d", x, x + w - 1, y, y + h - 1),
		}
		while #rows > fit do
			table.remove(rows)
		end
	end

	local top = h // 2 - (#rows * line_h) // 2
	if top < 0 then
		top = 0
	end

	for i, txt in ipairs(rows) do
		local tw = M.font_16:measure(txt)
		local tx = (w - tw) // 2
		if tx < 2 then
			tx = 2
		end
		du.ttf_txt_left(txt, M.font_16, img, tx, top + (i - 1) * line_h,
			{0, 1, 2, 3})
	end

	vesc.disp_render(img, x, y, colors.accent_aa)
end

function M.region_overlay()
	local L = vs.layout

	-- The same arithmetic input.region uses, in the same order. The thirds
	-- are the part that matters: 2 * (disp_w / 3) is 532 on an 800-wide
	-- panel where (2 * disp_w) / 3 is 533, and the boundary is the first.
	local half = L.disp_w // 2
	local third = L.disp_w // 3
	local nav = L.nav_y
	local strip_h = L.disp_h - nav

	-- Above the nav strip: two halves.
	M.region_box(0, 0, half, nav)
	M.region_box(half, 0, L.disp_w - half, nav)

	-- The strip: three thirds, the last taking the remainder so the boxes
	-- cover the panel exactly rather than leaving a column at the edge.
	M.region_box(0, nav, third, strip_h)
	M.region_box(third, nav, 2 * third - third, strip_h)
	M.region_box(2 * third, nav, L.disp_w - 2 * third, strip_h)
end

-- Drive it from the tick. Three states: waiting for the dash to settle,
-- showing, and done. While it is showing the views are skipped, the way they
-- are under the quick shade -- and for the same reason, which is that they
-- would otherwise repaint over it a field at a time.
--- the startup overlays ---
--
-- The boot log and the region overlay, both driven from the tick rather than
-- by sleeping in the main chunk.
--
-- That is not a tidy-up. The chunk used to hold the boot log for four seconds
-- with vesc.sleep, which is vTaskDelay: the engine task blocks, so it drains
-- no events, and the subscription mirrors a producer checks are not refreshed
-- until the chunk returns. Every CAN frame and every app data packet arriving
-- in that window was discarded before it reached the queue.
--
-- It showed up as the package UI's channel not working, and as a race rather
-- than a steady failure -- whether a packet arrived depended on whether the
-- chunk happened to have finished, so the same test passed and failed with no
-- change to the code. Which is also why it took so long to find.
--
-- Each phase is {name, duration, draw, update}: draw runs once on entry,
-- update every tick while it is up. Returning true means the views stand down,
-- the way they do under the quick shade.
M.phases = nil
M.phase_i = 0
M.phase_until = 0.0

function M.phase_list()
	local list = {}

	if M.boot_log_s > 0.0 then
		list[#list + 1] = {
			name = "boot_log",
			secs = M.boot_log_s,
			draw = M.boot_log_splash,
			update = M.boot_log_probe,
		}
	end

	if M.region_overlay_s > 0.0 then
		-- The delay is a phase of its own rather than a special case, so the
		-- dash draws itself once before the regions go over it.
		list[#list + 1] = {name = "settle", secs = M.region_overlay_delay_s}
		list[#list + 1] = {
			name = "regions",
			secs = M.region_overlay_s,
			draw = M.region_overlay,
		}
	end

	return list
end

function M.region_step(secs)
	if M.phases == nil then
		M.phases = M.phase_list()
		M.phase_i = 0
	end

	if M.phase_i > #M.phases then
		return false
	end

	-- Entering the next phase.
	if M.phase_i == 0 or secs >= M.phase_until then
		M.phase_i = M.phase_i + 1
		local ph = M.phases[M.phase_i]

		if ph == nil then
			-- Past the last one: repaint the lot, because the views' dirty
			-- tracking was paused and has no idea what was covered.
			state.view_force_static = true
			state.view_force_pages = true
			return false
		end

		M.phase_until = secs + ph.secs
		if ph.draw then
			guard(ph.name, ph.draw)
		end
		-- A phase with no draw is a gap, and the views run through it.
		return ph.draw ~= nil
	end

	local ph = M.phases[M.phase_i]
	if ph.update then
		guard(ph.name .. "_update", ph.update)
	end
	return ph.draw ~= nil
end

--- the tick ---

M.n = 0


-- The order within a tick is the order the lisp's threads would have settled
-- into, and two parts of it are not arbitrary. Input runs first so a press is
-- acted on in the same tick it was read rather than the next. The views run
-- last so they draw the state everything else just produced.
function M.tick()
	local n = M.n + 1
	M.n = n
	local d = M.div

	if M.timing then
		M.job_ticks = M.job_ticks + 1
		-- Reported once a second and then reset, so the numbers are a recent
		-- average rather than one diluted by startup.
		if M.job_ticks >= 1000 // M.period_ms * 1 and n % 50 == 0 then
			boot_log.step(M.timing_report())
			M.timing_reset()
		end
	end

	if n % d.input == 0 then
		guard("input", input.poll)
		-- The views read the touch point and the hold from the input layer.
		-- Copied rather than reached for, so view_pages does not depend on
		-- input and can be rendered by the host harness.
		vp.touch_x = input.touch_x
		vp.touch_y = input.touch_y
		vp.btn_hold_region = input.btn_hold_region
		vp.btn_hold_progress = input.btn_hold_progress
	end

	if n % d.stats == 0 then
		guard("stats", function() stats.tick(stats.chart_src) end)
	end

	if n % d.standalone == 0 then
		guard("standalone", standalone.step)
	end

	if n % d.tx == 0 then
		guard("tx", M.tx_step)
	end

	if n % d.frames == 0 and #M.pending > 0 then
		guard("frames", M.drain_step)
	end

	if n % d.worker == 0 then
		guard("worker", M.worker_step)
	end

	-- The region overlay covers the whole panel, so the views stand down
	-- while it is up rather than drawing through it.
	local overlay = M.region_step(n * M.period_ms / 1000.0)

	if not overlay and n % d.static == 0 then
		guard("static", M.static_step)
	end

	if not overlay and n % d.pages == 0 then
		guard("pages", pages.step)
	end

	if n % d.notify == 0 then
		guard("notify", notify.step)
	end

	-- Whether touch is still answering. Recorded rather than displayed: a
	-- failed read reaches the script as "not touched", so without this a
	-- panel that has fallen off the bus is indistinguishable from a rider
	-- not touching the screen -- and on this board that is the difference
	-- between a fault and nothing being wrong.
	if n % d.touch_watch == 0 then
		guard("touch_watch", boot_log.touch_watch)
		-- A periodic line with the three counters, so the ring always holds a
		-- recent one and reading the log answers the question without having
		-- to catch a transition. One line a minute, which is a fraction of
		-- the ring over the time anyone spends looking.
		if n % (d.touch_watch * 60) == 0 then
			guard("touch_line", function() boot_log.step(boot_log.touch_line()) end)
		end
	end
end

--- bring-up ---
--
-- The board does its own panel, touch and font setup, then calls this. The
-- order here is the lisp's main(): settings before anything that reads them,
-- the backlight after the first clear, and the lock before any page can be
-- drawn.
function M.start(cfg)
	M.cfg = cfg
	M.timing = cfg.timing or false
	M.region_overlay_s = cfg.region_overlay_s or 0.0
	M.appdata_trace = cfg.appdata_trace or false
	actions.cfg = cfg
	actions.bl_set = M.bl_set
	apply.bl_set = M.bl_set

	boot_log.step("dash start")


	-- A version code that does not match usually means something else was in
	-- this eeprom.
	if apply.restore_if_stale(cfg) then
		boot_log.step("eeprom version mismatch, settings restored")
	end

	-- Defaults rather than a dead display: a setting that cannot be read must
	-- not stop the dash coming up.
	local ok, err = pcall(apply.all, cfg)
	if not ok then
		boot_log.step("settings failed to load: " .. tostring(err))
		apply.restore(cfg)
		apply.all(cfg)
		boot_log.step("defaults restored")
	else
		boot_log.step(string.format("settings loaded, %d pages, theme %d",
			state.page_num, settings.values.theme))
	end

	vs.overlay_showing = pages.overlay_showing
	notify.layout = vs.layout
	input.set_layout(vs.layout)

	vesc.disp_clear(colors.bg)

	-- Turn the backlight on. The board parks it off at boot so nothing shows
	-- before the first draw, and the only other caller is apply.visual, which
	-- the worker runs on a theme change and never at startup. Without this a
	-- board with real backlight control renders everything into a dark panel,
	-- and the symptom is intermittent rather than constant: whatever PWM the
	-- previous firmware left survives until the next reset.
	M.bl_set(state.backlight_dim and settings.values.bl_dim
		or settings.values.bl_bright)

	-- Both of these are guarded rather than pcall'd, and the difference is
	-- not cosmetic: a bare pcall here hid a nil font in the log screen, so
	-- the symptom was the logo, then the dash, and no sign that a diagnostic
	-- had failed. The one screen whose job is to report what went wrong is
	-- the last place to drop an error.
	if settings.values.splash then
		guard("splash", M.splash)
	end

	-- The boot log is a tick phase now, not something start() waits for. See
	-- the note on the phase machine: blocking the chunk here dropped every
	-- event that arrived while it was held.

	vs.frame()
	vs.reset()

	-- The lock, before anything else can put a page on screen.
	if settings.values.pin_en then
		pin.engage()
		pages.show_pin()
	end

	actions.bind()
	boot_log.step("input bound")

	-- The controller's own lock commands, queued rather than sent inline.
	pin.on_lock = function()
		M.queue(205, comms.pin_cmd_frames(3, settings.values.pin_en and 1 or 0))
	end
	pin.on_unlock = function()
		M.queue(205, comms.pin_cmd_frames(4, 0))
	end


	-- CAN in. Trapped: a short or unexpected frame must not take the handler
	-- down, because losing it means losing every later frame too.
	vesc.on_can(function(id, data)
		local okf, errf = pcall(comms.proc_sid, id, data)
		if not okf then
			print("frame", id, "rejected:", errf)
		end
	end)

	-- Let the controller report the mode it is applying before announcing
	-- one. A display that restarts mid-ride would otherwise say neutral
	-- before it has heard otherwise, dropping the rider out of gear. The
	-- controller allows five seconds of silence, so this is well inside.
	vesc.sleep(1.0)

	boot_log.step(string.format("running at %d ms", M.period_ms))
	vesc.on_timer(M.period_ms, M.tick)
end

return M
