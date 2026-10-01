-- The firmware bindings the host Lua does not have, so the pure modules can
-- be tested off-target.
--
-- Same idea as dash_common/test/stubs.lisp, which stubs color-mix and
-- color-make for the lispBM repl. The colour maths mirrors
-- vesc_express/main/display/color_core.c, including its truncation: these
-- values end up compared against goldens rendered on the real thing, so a
-- stub that rounded differently would show up as a one-off palette entry and
-- be blamed on the port.
--
-- If this and color_core ever disagree, the firmware is right and this is
-- wrong.

local function clamp8(v)
	if v < 0 then return 0 end
	if v > 255 then return 255 end
	return math.floor(v)
end

-- A channel at or below 1.001 is a 0..1 fraction, anything above is 0..255.
-- That rule is color_channel_from_float.
local function channel(v)
	if math.type(v) == "integer" then
		return clamp8(v)
	end
	if v < 1.001 then
		v = v * 255.0
	end
	return clamp8(v)
end

local function pack(r, g, b, w)
	return (w << 24) | (r << 16) | (g << 8) | b
end

local vesc = {}

function vesc.color_make(r, g, b, w)
	return pack(channel(r), channel(g), channel(b), w and channel(w) or 0)
end

function vesc.color_split(c)
	return (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF, (c >> 24) & 0xFF
end

function vesc.color_mix(c1, c2, ratio)
	if ratio < 0.0 then ratio = 0.0 elseif ratio > 1.0 then ratio = 1.0 end
	local inv = 1.0 - ratio

	local function mix(shift)
		local a = (c1 >> shift) & 0xFF
		local b = (c2 >> shift) & 0xFF
		return math.floor(a * inv + b * ratio)
	end

	return pack(mix(16), mix(8), mix(0), mix(24))
end

function vesc.color_scale(c, s)
	local function sc(shift)
		local v = ((c >> shift) & 0xFF) * s
		if v < 0.0 then v = 0.0 elseif v > 255.0 then v = 255.0 end
		return math.floor(v)
	end
	return pack(sc(16), sc(8), sc(0), sc(24))
end

-- eeprom, as 32 slots of either an integer or a float.
--
-- The firmware's eeprom-read-i on a slot that has never been written returns
-- nil; the lisp test stub returns 0 instead, and the comment on
-- setting-clamp records what that cost -- a nil compared with = is a type
-- error that took settings-load down and left the dash dead before it drew
-- anything. So this stub returns nil for an unwritten slot, which is what the
-- hardware does and what the guards have to survive.
vesc.eeprom = {}

function vesc.eeprom_read_i(addr)
	local v = vesc.eeprom[addr]
	if v == nil then return nil end
	return math.floor(v)
end

function vesc.eeprom_read_f(addr)
	return vesc.eeprom[addr]
end

function vesc.eeprom_store_i(addr, v)
	vesc.eeprom[addr] = math.floor(v)
	return true
end

function vesc.eeprom_store_f(addr, v)
	vesc.eeprom[addr] = v
	return true
end

-- The clock. systime is FreeRTOS ticks, which is milliseconds on every board
-- in the tree -- CONFIG_FREERTOS_HZ is 1000 in all ten sdkconfig.defaults --
-- and the timer arithmetic in statistics divides by 1000.0 on that basis. A
-- stub returning seconds would make those timers read 1000x short, so this
-- returns milliseconds as an integer the way the binding does.
--
-- secs_since is seconds, as its name and its binding both say.
local t0 = os.clock()
function vesc.systime() return math.floor((os.clock() - t0) * 1000.0) end
function vesc.secs_since(t) return (os.clock() - t0) - t / 1000.0 end

return vesc
