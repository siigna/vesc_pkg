-- A runnable dash skeleton for the P4 board, under the Lua engine.
--
-- Not the dash. This is the smallest thing that proves the ported modules
-- work together on hardware: the panel comes up, the backlight comes on,
-- fonts render, CAN frames reach the decoder, and touch is read. Everything
-- it draws comes through lib/ rather than being computed here, so when the
-- views are ported they replace the drawing and nothing else.
--
-- What it deliberately does not do: pages, settings, the quick shade, the
-- chart. Those need view_pages, which is the bulk of the port.

local config = require("config")
local state = require("lib.state")
local colors = require("lib.colors")
local battery = require("lib.battery")
local comms = require("lib.comms")
local signals = require("lib.signals")
local stats = require("lib.statistics")

vesc.set_print_prefix("DASH-")

-- --- panel ---
--
-- The order matters: the rotation has to be applied before touch is loaded,
-- because touch is told the rotated size.
assert(vesc.disp_load("st7701", config.disp_rst, config.disp_lane_mbps),
	"panel did not load")
vesc.disp_orientation(config.disp_rotation)

-- The backlight. Active-LOW, so the duty is inverted -- and the firmware
-- parks the pin off at boot, which is why nothing shows until this runs.
local function bl_set(level)
	if level < 0.0 then level = 0.0 elseif level > 1.0 then level = 1.0 end
	vesc.pwm_start(config.bl_freq, 1.0 - level, 0, config.bl_pin)
end

-- Text colour is the BASE palette index, not the colour to draw. The font
-- binding adds coverage to it: with an indexed4 glyph, coverage 1..3 becomes
-- index colour, colour+1, colour+2. So 1 is right for a four-entry ramp --
-- 0 is the background and 1..3 are the fade.
--
-- Passing 3 looks reasonable and is wrong: coverage then lands on 3, 4 and 5,
-- and a four-entry palette has no 4 or 5. The solid centre of every glyph
-- reads past the palette, which on hardware looked like text that had not
-- antialiased properly rather than like an error.
local TEXT_IDX = 1

-- --- fonts ---
local font_big = vesc.font_load(vesc.asset("font40"))
local font_small = vesc.font_load(vesc.asset("font18"))

-- --- colours ---
colors.bg = 0x000000
colors.accent = 0x00C8FF
colors.text = 0xfbfcfc
colors.build()

vesc.disp_clear(colors.bg)
bl_set(config.bl_bright)

-- --- splash, so there is something on the glass before any CAN arrives ---
do
	local h = 80
	local buf = vesc.img_buffer("indexed4", config.disp_w, h)
	buf:clear()
	local w = font_big:measure("VESC")
	buf:text((config.disp_w - w) // 2, 56, font_big, "VESC", TEXT_IDX, true)
	vesc.disp_render(buf, 0, (config.disp_h - h) // 2, colors.accent_aa)
end

vesc.sleep(1.5)
vesc.disp_clear(colors.bg)

-- --- touch ---
local touch_ok = pcall(vesc.touch_load_gt911, config.touch_sda, config.touch_scl,
	config.touch_rst, config.touch_int, config.disp_w, config.disp_h)
print("touch loaded:", touch_ok)

-- --- CAN in ---
--
-- comms owns the decode; this only has to hand it the frame. The dash's own
-- event handler does the same thing with a lisp recv loop.
comms.use_gnss_speed = false
vesc.on_can(function(id, data)
	-- Trapped: a short or unexpected frame must not take the handler down,
	-- because losing it means losing every later frame too.
	local ok, err = pcall(comms.proc_sid, id, data)
	if not ok then
		print("frame", id, "rejected:", err)
	end
end)

-- --- the one page ---
--
-- Four fields, drawn only when their text changes. Change detection on the
-- formatted string rather than the number is what keeps a 10 Hz redraw from
-- repainting a value that rounds to the same thing.
local FIELDS = {
	{label = "SPEED", unit = "km/h", get = function() return string.format("%.1f", state.kmh) end},
	{label = "VOLTS", unit = "V",    get = function() return string.format("%.1f", state.vin) end},
	{label = "SOC",   unit = "%",    get = function() return string.format("%.0f", battery.soc() * 100) end},
	{label = "POWER", unit = "kW",   get = function() return string.format("%.2f", state.kw) end},
}

local col_w = config.disp_w // #FIELDS
local shown = {}
local bufs = {}
local labels_drawn = false

local function draw_labels()
	for i, f in ipairs(FIELDS) do
		local buf = vesc.img_buffer("indexed4", col_w, 24)
		buf:clear()
		buf:text(8, 18, font_small, f.label .. " " .. f.unit, TEXT_IDX, true)
		vesc.disp_render(buf, (i - 1) * col_w, 150, colors.text_aa)
	end
	labels_drawn = true
end

local function draw_fields()
	for i, f in ipairs(FIELDS) do
		local txt = f.get()
		if txt ~= shown[i] then
			shown[i] = txt
			-- One buffer per column, kept rather than reallocated: the
			-- engine has a memory ceiling and a fresh buffer per frame per
			-- field is the easiest way to reach it.
			if not bufs[i] then
				bufs[i] = vesc.img_buffer("indexed4", col_w, 48)
			end
			local buf = bufs[i]
			buf:clear()
			buf:text(8, 40, font_big, txt, TEXT_IDX, true)
			vesc.disp_render(buf, (i - 1) * col_w, 180, colors.accent_aa)
		end
	end
end

-- Status line: whether a controller is talking at all, which is the first
-- thing worth knowing on a bench.
local status_shown = nil
local status_buf = nil

local function draw_status()
	local txt
	if comms.rx_cnt == 0 then
		txt = "no controller seen"
	else
		txt = string.format("%d frames   touch %s", comms.rx_cnt,
			touch_ok and "ok" or "off")
	end

	if txt ~= status_shown then
		status_shown = txt
		status_buf = status_buf or vesc.img_buffer("indexed4", config.disp_w, 24)
		status_buf:clear()
		status_buf:text(8, 18, font_small, txt, TEXT_IDX, true)
		vesc.disp_render(status_buf, 0, 420, colors.text_aa)
	end
end

-- A touch anywhere dims the backlight, which is the smallest proof that
-- touch, state and the panel are all live at once.
local dim = false

vesc.on_timer(100, function()
	if not labels_drawn then
		draw_labels()
	end

	draw_fields()
	draw_status()

	local x = vesc.touch_read()
	if x then
		if not dim then
			dim = true
			bl_set(config.bl_dim)
		end
	elseif dim then
		dim = false
		bl_set(config.bl_bright)
	end

	-- Keep the smoothing and chart paths exercised, so the modules the views
	-- will use are running rather than merely linked.
	state.kmh_smooth = stats.smooth_step(state.kmh_smooth, state.kmh, 0.3, 0.0, 100.0)
	stats.chart_tick = stats.chart_tick + 1
	if stats.chart_tick % 10 == 0 then
		stats.chart_push(state.kmh)
	end
end)

print("dash skeleton up")
