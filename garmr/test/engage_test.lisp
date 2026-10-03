; Copyright 2026 Stephen Bouche
; SPDX-License-Identifier: GPL-3.0-or-later
;
; The engage logic of the LispBM Garmr, against the stubs. The firmware side
; -- the walk keepalive itself -- is covered in the firmware tree by
; tests/app_pas; what is here is the decision about when to ask for it.
;
; The Lua version of this lives in bldc/tests/qemu/test_garmr.c and runs on a
; simulated STM32F405. This one runs in the LispBM repl, the same way the dash
; tests do, because the Lisp bindings cannot be linked into a test image on
; their own.

(def checks 0)
(def fails 0)

(defun check (label got want) {
    (setq checks (+ checks 1))
    (if (eq got want)
        (print (str-merge "  ok   " label))
        {
            (setq fails (+ fails 1))
            (print (str-merge "  FAIL " label
                              " -- got " (to-str got)
                              ", want " (to-str want)))
        })
})

; No imports: the stubs and the script are evaluated before this file, by
; whatever is running it. The repl is given all three with -s, and the QEMU
; image embeds all three and evaluates them in the same order -- there is no
; filesystem there to import from.

; --- released when the switch is off ---------------------------------------
(setq fake-adc 0.5)
(garmr-step)
(check "off: not engaged" garmr-engaged nil)
(check "off: reason" garmr-reason "off")
(check "off: keepalive still called" last-walk nil)

; --- the debounce holds off the first pass ---------------------------------
(setq fake-adc 2.5)
(garmr-step)
(check "on, first pass: not engaged yet" garmr-engaged nil)
(check "on, first pass: debouncing" garmr-reason "debouncing")

(sleep 0.1)
(garmr-step)
(check "after debounce: engaged" garmr-engaged t)
(check "after debounce: reason" garmr-reason "holding")
(check "after debounce: keepalive asked for the hold" last-walk t)

; --- the keepalive is a keepalive, not a latch -----------------------------
(def calls-before walk-calls)
(garmr-step)
(garmr-step)
(garmr-step)
(check "three passes, three keepalives" (- walk-calls calls-before) 3)

; --- brake releases, and does not wait for a debounce ----------------------
(setq fake-flags (shl 1 3))
(garmr-step)
(check "brake: released" garmr-engaged nil)
(check "brake: reason" garmr-reason "brake")
(check "brake: keepalive released" last-walk nil)

(setq fake-flags 0)
(garmr-step)
(check "brake clear: holding again" garmr-engaged t)

; --- an invalid brake channel is a veto, not a warning ---------------------
(setq fake-flags (shl 1 2))
(garmr-step)
(check "brake channel invalid: released" garmr-engaged nil)
(check "brake channel invalid: reason" garmr-reason "brake channel invalid")
(setq fake-flags 0)
(garmr-step)

; --- a fault releases ------------------------------------------------------
(setq fake-fault 3)
(garmr-step)
(check "fault: released" garmr-engaged nil)
(check "fault: reason" garmr-reason "fault")
(setq fake-fault 0)
(garmr-step)
(check "fault clear: holding again" garmr-engaged t)

; --- the validity window: a disconnected pin must not read as on ----------
;
; Held, not stepped once. A single pass cannot engage anything with the
; debounce in the way, so a one-pass check here would pass whether or not the
; window exists -- which is exactly how the first version of the Lua test was
; weak.
(setq fake-adc 3.9)
(garmr-step)
(sleep 0.1)
(garmr-step)
(garmr-step)
(check "pin above the window: released" garmr-engaged nil)
(check "pin above the window: says so"
       garmr-reason "switch input out of range (3.90 V)")
(check "pin above the window: keepalive released" last-walk nil)

(setq fake-adc 0.05)
(garmr-step)
(sleep 0.1)
(garmr-step)
(garmr-step)
(check "pin below the window: released" garmr-engaged nil)

; --- the Schmitt trigger: between the thresholds, state is kept ------------
(setq fake-adc 2.5)
(garmr-step)
(sleep 0.1)
(garmr-step)
(check "re-engaged before the hysteresis check" garmr-engaged t)

; 1.75 V is below on-above (2.00) but above off-below (1.50), so an engaged
; switch stays engaged. One threshold instead of two would drop out here.
(setq fake-adc 1.75)
(garmr-step)
(check "between thresholds while on: stays engaged" garmr-engaged t)

(setq fake-adc 1.40)
(garmr-step)
(check "below off-below: releases" garmr-engaged nil)

; And coming back up, 1.75 V is not enough to engage from released.
(setq fake-adc 1.75)
(garmr-step)
(sleep 0.1)
(garmr-step)
(check "between thresholds while off: stays off" garmr-engaged nil)

; --- diagnose reports what the firmware did with the request ---------------
(setq fake-adc 2.5)
(garmr-step)
(sleep 0.1)
(garmr-step)
(check "engaged for the diagnose checks" garmr-engaged t)

(setq fake-flags 0)
(check "asked but PAS not holding is reported"
       (eq (garmr-diagnose t) nil) nil)

(setq fake-flags (shl 1 8))
(check "PAS holding: nothing to report" (garmr-diagnose t) nil)

(setq fake-flags (+ (shl 1 8) (shl 1 7)))
(check "speed limited is reported"
       (garmr-diagnose t) "speed limited -- Walk max speed is cutting in; raise it")

(setq fake-flags (shl 1 9))
(check "walk channel invalid is reported"
       (garmr-diagnose t) "walk channel invalid")

(print (str-merge (to-str checks) " checks, " (to-str fails) " fails"))
