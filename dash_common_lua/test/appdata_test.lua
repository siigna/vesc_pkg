-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Unit tests for lib/appdata.lua, the channel the package UI drives the dash
-- over.
--
-- New: the lisp dash has nothing to test here, because its handler is
-- (eval (read data)) and the surface is the whole language. The point of
-- parsing instead is that the surface is small enough to enumerate, so this
-- enumerates it -- including every malformed shape, because the packets come
-- from off the board.
vesc = require("test.vesc_stub")

local t = require("test.harness")
local appdata = require("lib.appdata")

local sent = {}
vesc.send_data = function(s) sent[#sent + 1] = s end

local writes = {}
local resets = 0

local function reset_spies()
	sent = {}
	writes = {}
	resets = 0
	appdata.last_reply = nil
	appdata.send_cfg = function() return "cfg 1 2 3" end
	appdata.settings_set = function(name, val)
		-- Stands in for the address map: only these two names exist.
		if name ~= "theme" and name ~= "smooth" then
			return false
		end
		writes[#writes + 1] = {name, val}
		return true
	end
	appdata.settings_reset = function() resets = resets + 1 return true end
end

--- cfg ---
reset_spies()
local ok, err = appdata.handle("cfg")
t.ok("cfg is understood",     ok)
t.ok("and replies",           sent[1] == "cfg 1 2 3")
t.ok("with nothing written",  #writes == 0)

-- The trailing NUL both senders append, and surrounding whitespace.
reset_spies()
t.ok("a trailing NUL is stripped", appdata.handle("cfg\0"))
t.ok("and replied to",             sent[1] == "cfg 1 2 3")

reset_spies()
t.ok("trailing junk after the NUL is ignored", appdata.handle("cfg\0rubbish"))

reset_spies()
t.ok("surrounding space is stripped", appdata.handle("  cfg  "))

--- set ---
reset_spies()
ok, err = appdata.handle("set theme 3")
t.ok("set is understood",  ok)
t.ok("the name arrived",   writes[1][1] == "theme")
t.near("and the value",    writes[1][2], 3)
t.ok("and it replies with the new state", sent[1] == "cfg 1 2 3")

-- A float value, which is what smoothing and the thresholds are.
reset_spies()
t.ok("a float value is accepted", appdata.handle("set smooth 0.35"))
t.near("and parsed",              writes[1][2], 0.35)

-- Negative, which the slot minimums use.
reset_spies()
t.ok("a negative value is accepted", appdata.handle("set smooth -10"))
t.near("and parsed",                 writes[1][2], -10)

-- Hex, because the colours are written that way in the lisp UI.
reset_spies()
t.ok("hex is accepted", appdata.handle("set theme 0x1F"))
t.near("and parsed",    writes[1][2], 31)

--- reset ---
reset_spies()
t.ok("reset is understood", appdata.handle("reset"))
t.ok("and resets once",     resets == 1)
t.ok("and replies with the new state", sent[1] == "cfg 1 2 3")

--- everything malformed ---
--
-- These arrive from off the board, so each one has to be refused rather than
-- half-applied. None of them may write anything.
local bad = {
	{"", "empty"},
	{"\0", "nothing but a NUL"},
	{"   ", "only whitespace"},
	{"frobnicate", "an unknown verb"},
	{"set", "set with no name"},
	{"set theme", "set with no value"},
	{"set theme 3 4", "set with too many words"},
	{"set theme banana", "a value that is not a number"},
	{"set nosuch 3", "a name that is not a setting"},
	{"cfgx", "a verb that merely starts like one"},
	{"SET theme 3", "the wrong case"},
}

for _, case in ipairs(bad) do
	reset_spies()
	local okb, errb = appdata.handle(case[1])
	t.ok("refused: " .. case[2], not okb)
	t.ok("  with a reason: " .. case[2], type(errb) == "string" and #errb > 0)
	t.ok("  and no write: " .. case[2], #writes == 0 and resets == 0)
	t.ok("  and no reply: " .. case[2], #sent == 0)
end

-- A non-string payload, which is what a binary app data packet would be.
reset_spies()
ok, err = appdata.handle(nil)
t.ok("nil is refused",       not ok)
ok, err = appdata.handle(42)
t.ok("a number is refused",  not ok)
t.ok("and nothing was written", #writes == 0)

-- A failed write is reported rather than silently replying, or the UI would
-- read the unchanged value back as though it had taken.
reset_spies()
appdata.settings_set = function() return false end
ok, err = appdata.handle("set theme 3")
t.ok("a refused write is reported", not ok)
t.ok("and not replied to",          #sent == 0)

t.report("appdata")
