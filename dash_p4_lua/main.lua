-- The dash, on the Waveshare ESP32-P4-WIFI6-Touch-LCD-4.3, under the Lua
-- engine.
--
-- The Lua counterpart of dash_p4/main.lisp plus the board-specific parts of
-- dash_common/main_body.lisp. Everything not specific to this panel is in
-- dash_common_lua; this file is the board: the display, the touch controller,
-- the backlight, the fonts, and the handful of values only the board knows.
--
-- Unlike the lisp there is no import list to maintain. vesc_tool packs lisp
-- imports by scanning the top-level file with no recursion, which is why
-- dash_p4/main.lisp has to name all nineteen of them; tools/luapack.py
-- follows require() through the tree instead.

local config = require("config")
local colors = require("lib.colors")
local units = require("lib.units")
local vs = require("lib.view_static")
local vp = require("lib.view_pages")
local comms = require("lib.comms")
local standalone = require("lib.standalone")
local notify = require("lib.notify")
local dash = require("lib.dash")

vesc.set_print_prefix("DISP-")

--- the panel ---
--
-- This panel is supported upstream, so unlike the S3 board there is no
-- board-specific init sequence: disp_load takes the two numbers it needs.
--
-- Native is 480x800, so the rotation is what makes it landscape, and it has
-- to be applied before touch is loaded because touch is told the rotated
-- size.
assert(vesc.disp_load("st7701", config.disp_rst, config.disp_lane_mbps),
	"panel did not load")
vesc.disp_orientation(config.disp_rotation)

-- Real PWM backlight. The pin is active-LOW, so the duty is inverted; the
-- firmware parks it off in hw_init so nothing shows before the first draw.
local function bl_set(level)
	if level < 0.0 then level = 0.0 elseif level > 1.0 then level = 1.0 end
	vesc.pwm_start(config.bl_freq, 1.0 - level, 0, config.bl_pin)
end

--- touch ---
--
-- Optional. Every control on this board is touch, so a dead controller costs
-- the whole UI -- but a dash that still shows the speed is worth more than
-- one that refuses to start, and the message says which it is.
local touch_ok = pcall(vesc.touch_load_gt911, config.touch_sda,
	config.touch_scl, config.touch_rst, config.touch_int,
	config.disp_w, config.disp_h)

if touch_ok then
	pcall(vesc.touch_transform, config.touch_transforms[1],
		config.touch_transforms[2], config.touch_transforms[3])
else
	print("touch init failed; the dash will run but nothing can be pressed")
end

--- fonts ---
--
-- Pre-rendered by dash_p4/font/generate_fonts. Preparing them on the device
-- would mean shipping Roboto-Bold.ttf, which is larger than the fonts and the
-- whole source put together. The two big ones carry only the glyphs they can
-- draw, plus a "D" that ttf_txt_center measures to find the baseline.
local font_speed = vesc.font_load(vesc.asset("font120"))
local font_40 = vesc.font_load(vesc.asset("font40"))
local font_24 = vesc.font_load(vesc.asset("font24"))
local font_16 = vesc.font_load(vesc.asset("font18"))

--- layout ---
--
-- view_static owns it and view_pages reads it back, so the bands cannot
-- drift apart.
local L = vs.set_layout(config)
vp.set_layout(L)

vs.font_speed = font_speed
vs.font_24 = font_24
vs.font_16 = font_16
vs.drive_mode_names = config.drive_mode_names
vs.light_on_is_highbeam = config.light_on_is_highbeam

vp.font_40 = font_40
vp.font_24 = font_24
vp.font_16 = font_16

notify.font = font_24

dash.font_40 = font_40
dash.font_24 = font_24
dash.bl_set = bl_set
dash.version = require("version")

--- board values the shared code asks for ---

-- lib/battery.lua reads its pack from lib/config.lua, which ships
-- conservative placeholders. The board's numbers are copied over them rather
-- than the file being shadowed on the import path: require("lib.config")
-- resolves to the shared file whatever this package puts at "config", so
-- shadowing would only have worked if the board file were also at lib/.
--
-- On this board the two happen to hold the same pack, so nothing read wrong;
-- it read right by duplication, which is the kind of thing that stops being
-- true the first time one of them is edited.
local shared_config = require("lib.config")
for k, v in pairs(config) do
	shared_config[k] = v
end

colors.bg = 0x000000

-- GNSS speed, when the board has it. This one does not, so standalone mode
-- falls back to the controller's own estimate.
standalone.use_gnss_speed = config.gnss_use_speed
comms.use_gnss_speed = config.gnss_use_speed

require("lib.state").light_on = config.light_on_default

--- go ---

dash.start(config)

print("dash up")
