-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Unit tests for lib/comms.lua, the frame decoder.
--
-- New: the lisp dash has no unit test for this. It is the module where a
-- width or endianness mistake produces a plausible wrong number rather than
-- an error -- a speed that reads 2560 instead of 10 is obvious, but one that
-- reads 25.6 is not -- so the frames are built here with string.pack and
-- decoded back, which pins both.
vesc = require("test.vesc_stub")

local t = require("test.harness")
local state = require("lib.state")
local mode = require("lib.mode")
local signals = require("lib.signals")
local comms = require("lib.comms")

local clock = 500.0
comms.now = function() return clock end
mode.now = function() return clock end
mode.secs_since = function(ts) return clock - ts end
signals.secs_since = function(ts) return clock - ts end

-- --- endianness, which everything else depends on ---
-- 0x0102 big-endian is 258. Little-endian would read 513, and a tenths scale
-- would turn that into 51.3 km/h instead of 25.8 -- both plausible.
local f20 = string.pack(">i2i2i2i2", 500, 250, 258, 1500)
state.battery_a_connected = false
state.battery_b_connected = false
t.ok("frame 20 handled", comms.proc_sid(20, f20))
t.near("soc scaled by 1000", state.battery_soc, 0.5)
t.near("duty scaled by 1000", state.duty, 0.25)
t.near("speed is big-endian tenths", state.kmh, 25.8)
t.near("power scaled by 100", state.kw, 15.0)
t.ok("updated flagged", state.updated)

-- Negative values have to survive the signed unpack: regen is negative power
-- and a downhill pitch is negative too.
local f20neg = string.pack(">i2i2i2i2", 500, 250, 100, -1500)
comms.proc_sid(20, f20neg)
t.near("negative power", state.kw, -15.0)

-- --- the BMS wins where it is present ---
state.battery_a_connected = true
state.battery_soc = 0.99
comms.proc_sid(20, f20)
t.near("soc not overwritten when a BMS is connected", state.battery_soc, 0.99)
state.battery_a_connected = false

-- --- gnss override ---
comms.use_gnss_speed = true
comms.gnss_speed = function() return 42.0 end
comms.proc_sid(20, f20)
t.near("gnss speed replaces the controller's", state.kmh, 42.0)
comms.use_gnss_speed = false

-- --- temperatures and pitch ---
local f21 = string.pack(">i2i2i2i2", 253, 412, 678, -1234)
comms.proc_sid(21, f21)
t.near("battery temp", state.temp_battery, 25.3)
t.near("esc temp",     state.temp_esc, 41.2)
t.near("motor temp",   state.temp_motor, 67.8)
t.near("negative pitch scaled by 100", state.angle_pitch, -12.34)

-- --- energy counters, unsigned ---
-- 60000 does not fit a signed 16-bit value, so reading these as i16 would
-- give a negative watt hour count.
local f22 = string.pack(">I2I2I2I2", 60000, 1234, 5000, 7)
comms.proc_sid(22, f22)
t.near("wh is unsigned",  state.wh, 6000.0)
t.near("wh charged",      state.wh_chg, 123.4)
t.near("km",              state.km, 500.0)
t.ok("fault code", state.fault_code == 7)

-- --- amps, mixed signedness in one frame ---
local f23 = string.pack(">I2I2i2I2", 40000, 50000, -300, 170)
state.battery_a_connected = false
comms.proc_sid(23, f23)
t.ok("average amps unsigned", state.amps_avg == 40000)
t.ok("max amps unsigned",     state.amps_max == 50000)
t.ok("now amps signed",       state.amps_now == -300)
t.ok("ah taken when no BMS",  state.battery_ah == 170)

-- --- a 32-bit odometer ---
-- 4 million tenths of a km is 400 000 km, which is past what 16 bits holds
-- and the reason this field is u32.
local f24 = string.pack(">I2I4I2", 480, 4000000, 255)
comms.proc_sid(24, f24)
t.near("vin", state.vin, 48.0)
t.near("odometer is 32 bit", state.odom, 400000.0)
t.near("cruise speed", state.cruise_control_speed, 25.5)

-- --- one controller setting per frame, with a float payload ---
local f27 = string.pack(">I1fI1I1I1", 3, 1.5, 1, 9, 0)
comms.proc_sid(27, f27)
t.near("conf value is a float", state.conf_vals[4], 1.5)
t.ok("conf gated flag", state.conf_gated[4] == 1)
t.ok("conf seen",       state.conf_seen[4] == true)
t.ok("conf count",      state.conf_count == 9)

-- An index past the table is dropped rather than growing it.
local f27bad = string.pack(">I1fI1I1I1", 99, 1.0, 0, 0, 0)
comms.proc_sid(27, f27bad)
t.ok("out-of-range conf index ignored", state.conf_vals[100] == nil)

-- --- indicators, and the animation timestamp ---
state.indicate_l_on = false
state.indicate_r_on = false
state.indicator_timestamp = 0
local f30 = string.pack(">I1I1I2I1I1I1I1", 1, 0, 350, 1, 0, 0, 0)
comms.proc_sid(30, f30)
t.ok("left indicator on",  state.indicate_l_on)
t.ok("right indicator off", not state.indicate_r_on)
t.ok("indicate ms", state.indicate_ms == 350)
t.ok("highbeam on", state.highbeam_on)
t.ok("timestamp set when an indicator starts", state.indicator_timestamp == clock)
t.ok("signal reporting noted", signals.rx_last == clock)

-- Already on, so the timestamp must not be restamped every frame or the
-- animation would never advance.
state.indicator_timestamp = 0
comms.proc_sid(30, f30)
t.ok("timestamp not restamped while already on", state.indicator_timestamp == 0)

-- --- the kickstand is inverted on the wire ---
comms.proc_sid(31, string.pack(">I1I1I1I1I1I1I1I1", 0, 0, 0, 0, 0, 0, 0, 0))
t.ok("zero means down", state.kickstand_down)
comms.proc_sid(31, string.pack(">I1I1I1I1I1I1I1I1", 1, 0, 0, 0, 0, 0, 0, 0))
t.ok("one means up", not state.kickstand_down)

-- --- frame 25: mode follow, pas, and the condition bits ---
mode.num = 5
mode.current = 1
mode.cmd_ts = 0
clock = 500.0
local logged = nil
comms.on_log_change = function(v) logged = v end
state.log_active = false
local f25 = string.pack(">I1I1I1I1I2I1I1", 1, 3, 1, 0, 0x0102, 100, 0x0F)
comms.proc_sid(25, f25)
t.ok("log start notified", logged == true)
t.ok("log active",         state.log_active)
t.ok("mode followed",      mode.current == 3)
t.ok("service mode",       state.service_mode)
t.ok("motor not bad",      not state.motor_bad)
t.ok("pas flags are 16 bit", state.pas_flags == 0x0102)
t.near("pas output scaled by 200", state.pas_output, 0.5)
t.ok("kill switch bit",  state.kill_sw_active)
t.ok("aux bit",          state.aux_on)
t.ok("conf dirty bit",   state.conf_dirty)
t.ok("esc pin bit",      state.esc_pin_holding)

-- The same frame again must not re-notify: a notification per frame at 10 Hz
-- would be a wall of them.
logged = nil
comms.proc_sid(25, f25)
t.ok("no notification without a change", logged == nil)

-- Only the low four bits are conditions; the rest must not bleed in.
local f25clear = string.pack(">I1I1I1I1I2I1I1", 1, 3, 0, 0, 0, 0, 0xF0)
comms.proc_sid(25, f25clear)
t.ok("high bits do not set kill", not state.kill_sw_active)
t.ok("high bits do not set aux",  not state.aux_on)

-- --- the cruise authority ---
state.cruise_control_active = false
comms.proc_sid(202, string.pack(">I1I1I1I1I1I1I1I1", 1, 0, 0, 0, 0, 0, 0, 0))
t.ok("cruise from 202", state.cruise_control_active)
t.ok("202 switches authority", comms.cruise_new_msg_rx)
-- Now frame 30 must not override it.
comms.proc_sid(30, string.pack(">I1I1I2I1I1I1I1", 0, 0, 0, 0, 0, 0, 0))
t.ok("cruise not overridden by frame 30", state.cruise_control_active)

-- --- ambient and clock ---
comms.proc_sid(203, string.pack(">i2I2I2I2", -55, 0, 0, 0))
t.near("negative ambient", state.temp_ambient, -5.5)
t.ok("ambient rx flagged", state.temp_ambient_rx)

comms.proc_sid(204, "\1\2\3\4\5\6")
t.ok("date time length", #state.date_time == 6)
t.ok("date time bytes",  state.date_time[1] == 1 and state.date_time[6] == 6)
t.ok("date time rx flagged", state.date_time_rx)

-- --- dispatch ---
t.ok("an unknown id is not handled", not comms.proc_sid(999, f20))

-- rx_cnt counts controller frames only: an ambient or clock frame from
-- another node must not make a silent controller look alive.
local before = comms.rx_cnt
comms.proc_sid(203, string.pack(">i2I2I2I2", 0, 0, 0, 0))
comms.proc_sid(204, "\1\2\3")
t.ok("other nodes do not count as the controller", comms.rx_cnt == before)
comms.proc_sid(21, f21)
t.ok("controller frames count", comms.rx_cnt == before + 1)

-- A short frame raises rather than decoding garbage.
t.ok("a truncated frame raises", not pcall(comms.proc_sid, 20, "\1\2"))

-- --- transmit ---
--
-- The builders are checked by decoding what they produce, which is the same
-- trick as the receive tests and catches the same class of mistake: a frame
-- the controller would read as a different mode or a different speed.

-- SID 201. Neutral is 1, and a locked bike must assert exactly that.
local f201 = comms.build_201(1, true, false, 0x0A)
t.ok("201 is eight bytes", #f201 == 8)
local m, light, walk, sigb = string.unpack(">I1I1I1I1", f201)
t.ok("201 carries the mode",      m == 1)
t.ok("201 carries the light",     light == 1)
t.ok("201 carries walk as false", walk == 0)
t.ok("201 carries the signal byte", sigb == 0x0A)

local f201b = comms.build_201(4, false, true, 0)
local m2, light2, walk2 = string.unpack(">I1I1I1", f201b)
t.ok("201 mode 4",        m2 == 4)
t.ok("201 light off",     light2 == 0)
t.ok("201 walk requested", walk2 == 1)

-- SID 202. Byte 1 is a deliberate gap, and the scales are part of the
-- protocol: a kd of 0.0025 goes out as 25.
local f202 = comms.build_202(1, 12.5, 30.0, 0.0025)
t.ok("202 is eight bytes", #f202 == 8)
local act, gap, start, fin, kd = string.unpack(">i1i1i2i2i2", f202)
t.ok("202 active",        act == 1)
t.ok("202 byte 1 is zero", gap == 0)
t.ok("202 start in tenths", start == 125)
t.ok("202 end in tenths",   fin == 300)
t.ok("202 kd scaled by 10000", kd == 25)

-- SID 205, and that it is sent more than once.
local frames205 = comms.pin_cmd_frames(3, 1)
t.ok("pin command repeats", #frames205 == 3)
local cmd, val = string.unpack(">I1I1", frames205[1])
t.ok("pin command id",   cmd == 3)
t.ok("pin command value", val == 1)
t.ok("every repeat is identical", frames205[1] == frames205[3])

-- SID 250.
local f250 = comms.build_250(1)
t.ok("250 is two bytes", #f250 == 2)
t.ok("250 carries the event", string.unpack(">I1", f250) == 1)

-- send() is replaceable, which is the point of splitting build from send.
local sent = {}
comms.send = function(id, data) table.insert(sent, {id = id, data = data}) end
comms.send(201, f201)
t.ok("send is interceptable", #sent == 1 and sent[1].id == 201)

t.report("comms")
