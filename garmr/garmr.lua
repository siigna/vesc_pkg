-- Copyright 2026 Stephen Bouche
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Garmr -- a set-and-forget assist level.
--
-- Idea from a Discord suggestion, with thanks:
-- https://discordapp.com/users/1440099786974826528
--
-- The suggestion was mechanical: take a throttle with a toggle switch, remove
-- the return spring and add friction so it holds position, and you have an
-- assist level you set once and switch on and off. The aim, in the author's
-- words, is "a gentle amount of assistance all the way over my riding range,
-- not that stupid cruise control style pedal assistance that stops above a
-- certain speed".
--
-- This does the same thing without touching the throttle, which keeps its
-- spring. That matters: a throttle held by friction cannot return itself, so
-- if the toggle fails closed or is forgotten there is nothing to release it.
--
-- WHAT THIS IS
--
-- A prototype. It holds the level by driving the firmware's walk-assist
-- keepalive, which already does almost everything wanted: a constant relative
-- current, no dependence on cadence, brake cancel, throttle combining, and a
-- half-second expiry so a script that stops running releases the motor.
--
-- What it does NOT do, and why the firmware work in the plan exists:
--   * no ramp. Walk assist returns early in pas_compute_output, before the
--     ramp, so engage and release are current steps. Keep the level modest.
--   * no watts. The level is a fraction of the motor current limit, so the
--     power it delivers rises with speed.
--   * no settings UI. These constants are the configuration; changing one
--     means re-uploading. A package with a native library is what buys a
--     settings page, and that is the next step, not this one.
--
-- BEFORE IT WILL DO ANYTHING
--
-- Set these once in ESCargot Tool, under App Settings -> PAS. The script
-- cannot set them: walk_* has no config symbol in either script engine.
--
--   App to use            PAS or ADC+PAS      (ADC+PAS keeps your throttle)
--   Walk source           Lisp                 this script is the source
--   Walk max speed        200 km/h             the cap must be out of the way;
--                                              <= 0.01 means disabled, not
--                                              unlimited
--   Walk current          your level           fraction of the current limit
--   Walk require pedal    off                  the point is no interlock
--   Brake source          ADC, with a channel  MANDATORY. Without it there is
--                         and threshold set    no brake cancel at all.
--
-- The script refuses to engage if the brake is not configured.

local cfg = {
  -- Which ADC channel the toggle switch is on, and the voltages that count
  -- as on and off. Two thresholds, not one, so a switch sitting near the
  -- boundary cannot chatter.
  adc_ch         = 1,      -- 0 = EXT1/ADC1, 1 = EXT2/ADC2, 2.. = EXT3 up
  on_above_v     = 2.00,
  off_below_v    = 1.50,
  invert         = false,

  -- Outside this the pin is treated as disconnected or shorted, and the
  -- assist is released. A floating input reading mid-rail is the failure
  -- this catches, and the one most likely to look like a working switch.
  valid_min_v    = 0.10,
  valid_max_v    = 3.20,

  -- How long the switch has to hold its new state before it counts.
  debounce_s     = 0.06,

  -- How often to refresh the keepalive. The firmware releases after 0.5 s
  -- without one, so this has to be comfortably faster than that.
  period_ms      = 100,
}

local M = {
  engaged = false,
  reason  = "starting",
  raw_v   = 0.0,
}

-- Pending switch state and when it was first seen, for the debounce.
local pending = false
local pending_since = nil

-- PAS flag bits, from applications/app.h. Checked against that file, not
-- guessed: the first draft had BRAKE_ENGAGED at the wrong bit.
local PAS_FLAG_BRAKE_CH_INVALID = 1 << 2
local PAS_FLAG_BRAKE_ENGAGED    = 1 << 3
local PAS_FLAG_SPEED_LIMITED    = 1 << 7
local PAS_FLAG_WALK_ACTIVE      = 1 << 8
local PAS_FLAG_WALK_CH_INVALID  = 1 << 9

local function read_switch()
  local v = vesc.get_adc(cfg.adc_ch)

  if v == nil then
    return nil, "no such ADC channel"
  end

  M.raw_v = v

  if (v < cfg.valid_min_v) or (v > cfg.valid_max_v) then
    return nil, string.format("switch input out of range (%.2f V)", v)
  end

  -- A Schmitt trigger: which threshold applies depends on where we are now.
  local on
  if M.engaged ~= cfg.invert then
    on = v > cfg.off_below_v
  else
    on = v > cfg.on_above_v
  end

  if cfg.invert then
    on = not on
  end

  return on, nil
end

-- True when the firmware would refuse to hold anyway, so we do not ask.
local function blocked()
  if vesc.get_fault() ~= 0 then
    return "fault"
  end

  local flags = vesc.pas_get_flags()

  if (flags & PAS_FLAG_BRAKE_ENGAGED) ~= 0 then
    return "brake"
  end

  if (flags & PAS_FLAG_BRAKE_CH_INVALID) ~= 0 then
    return "brake channel invalid"
  end

  return nil
end

function M.step(dt)
  local want, err = read_switch()
  local why = blocked()

  if err ~= nil then
    want = false
  end

  -- Debounce: a new state has to persist before it is believed. Releasing is
  -- not debounced -- when in doubt, stop driving.
  if want == false then
    pending = false
    pending_since = nil
    M.engaged = false
    M.reason = err or why or "off"
  elseif want == true then
    if not pending then
      pending = true
      pending_since = vesc.systime()
    end

    if why ~= nil then
      M.engaged = false
      M.reason = why
    elseif vesc.secs_since(pending_since) >= cfg.debounce_s then
      M.engaged = true
      M.reason = "holding"
    else
      M.reason = "debouncing"
    end
  end

  -- The keepalive. Called every pass while engaged, and once on release;
  -- stopping the calls is itself the release, after half a second.
  vesc.pas_walk_set(M.engaged)

  return M.engaged
end

-- Whether the firmware actually took the request.
--
-- There is no way to read pas_brake_source or any of the walk_* settings from
-- a script -- they have no config symbol in either engine -- so the only
-- settings check available is to ask for the hold and see whether the
-- firmware starts driving. Reporting that is worth more than it sounds: the
-- likely reasons for it not to are all Tool settings, and silence would look
-- identical to a broken switch.
local function diagnose(engaged)
  local flags = vesc.pas_get_flags()

  if (flags & PAS_FLAG_WALK_CH_INVALID) ~= 0 then
    return "walk channel invalid"
  end

  if engaged and ((flags & PAS_FLAG_WALK_ACTIVE) == 0) then
    return "requested, but PAS is not holding -- check Walk source is Lisp "
        .. "and Walk current is above zero"
  end

  if engaged and ((flags & PAS_FLAG_SPEED_LIMITED) ~= 0) then
    return "speed limited -- Walk max speed is cutting in; raise it"
  end

  return nil
end

if not GARMR_TEST then
  local last = ""

  print("Garmr: switch on ADC " .. cfg.adc_ch .. ", level is the PAS Walk "
        .. "current. Brake cancel needs Brake source set in App Settings -> "
        .. "PAS; there is none without it.")

  vesc.on_timer(cfg.period_ms, function()
    M.step(cfg.period_ms / 1000.0)

    -- One pass later, so the firmware has acted on the request.
    local note = diagnose(M.engaged)
    local say = note or M.reason

    if say ~= last then
      print("Garmr: " .. say .. string.format(" (%.2f V)", M.raw_v))
      last = say
    end
  end)
end

return M
