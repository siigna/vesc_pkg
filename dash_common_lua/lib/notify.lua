-- A short-lived banner over the normal views.
--
-- Ported from the notify section of dash_common/main_body.lisp.
--
-- For things the controller reports back rather than things the rider did:
-- logging starting and stopping, a press that was refused and why. Cleared by
-- forcing the views to redraw rather than by repainting what was underneath,
-- which is why clearing it costs a frame and showing it does not.
--
-- Two of the three messages are conditions rather than events, and they
-- outrank it: a motor configuration that cannot describe a real motor, and a
-- controller whose drive profile is suspended. Those stay up for as long as
-- they are true, so there is no timeout on them to expire.

local state = require("lib.state")
local colors = require("lib.colors")
local du = require("lib.draw_utils")

local M = {}

M.txt = nil
M.ts = 0

-- How long a message stays up. The lisp's 2.5 s, which is long enough to read
-- at a glance and short enough not to sit over the speed.
M.show_s = 2.5

-- Set by the board.
M.font = nil
M.layout = nil

M.w = 360
M.h = 48

function M.now()
	return vesc.systime()
end

function M.secs_since(t)
	return vesc.secs_since(t)
end

function M.show(txt)
	M.txt = txt
	M.ts = M.now()
end

-- Centred on the panel, where the lisp hardcodes 60 and 216. Those are the
-- centred position on the 480x480 panel it was written for, so this is the
-- same banner -- but on an 800x480 it would sit well left of centre, and
-- there is no golden pinning it, so it is derived.
function M.pos()
	local L = M.layout
	return (L.disp_w - M.w) // 2, (L.disp_h - M.h) // 2
end

function M.draw(txt)
	local buf = vesc.img_buffer("indexed4", M.w, M.h)
	buf:clear()
	buf:rectangle(0, 0, M.w, M.h, 1, {rounded = 8})
	du.ttf_txt_center(txt, M.font, buf)

	local x, y = M.pos()
	vesc.disp_render(buf, x, y, colors.text_aa)
end

-- Whether a condition banner is up, which the static view asks so it does not
-- draw underneath one.
M.service_last = false

-- One pass. Driven from the dash's timer, where the lisp sleeps 0.2 s in its
-- own thread; nothing here depends on the rate.
function M.step()
	-- Leaving service mode uncovers whatever the banner was sitting on.
	local service = state.service_mode or state.motor_bad
	if M.service_last and not service then
		state.view_force_static = true
		state.view_force_pages = true
	end
	M.service_last = service

	if state.motor_bad then
		-- The motor will not run at all in this state, so this outranks
		-- everything else on screen.
		M.draw("MOTOR CONFIG BAD")
	elseif state.service_mode then
		-- The mode on screen means nothing while the drive profile is
		-- suspended, and neutral no longer holds the throttle shut, so keep
		-- saying so until it is switched back.
		M.draw("SERVICE")
	elseif M.txt then
		if M.secs_since(M.ts) > M.show_s then
			M.txt = nil
			state.view_force_static = true
			state.view_force_pages = true
		else
			M.draw(M.txt)
		end
	end
end

return M
