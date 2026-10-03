; Copyright 2026 Stephen Bouche
; SPDX-License-Identifier: GPL-3.0-or-later
;
; Garmr -- a set-and-forget assist level.
;
; Idea from a Discord suggestion, with thanks:
; https://discordapp.com/users/1440099786974826528
;
; The suggestion was mechanical: take a throttle with a toggle switch, remove
; the return spring and add friction so it holds position, and you have an
; assist level you set once and switch on and off. The aim, in the author's
; words, is "a gentle amount of assistance all the way over my riding range,
; not that stupid cruise control style pedal assistance that stops above a
; certain speed".
;
; This does the same thing without touching the throttle, which keeps its
; spring. That matters: a throttle held by friction cannot return itself, so
; if the toggle fails closed or is forgotten there is nothing to release it.
;
; This is the LispBM version. There is a Lua one in garmr_lua, and it is the
; same logic -- but on an STM32F405 a firmware carries one script engine, not
; both: LispBM alone leaves .ram4 at 99.6% of 62 KB. So running the Lua
; prototype means a build with no LispBM, and therefore no Refloat, no Float,
; no dashboards. This version is the one most bikes can actually run.
;
; WHAT THIS IS
;
; A prototype. It holds the level by driving the firmware's walk-assist
; keepalive, which already does almost everything wanted: a constant relative
; current, no dependence on cadence, brake cancel, throttle combining, and a
; half-second expiry so a script that stops running releases the motor.
;
; What it does NOT do, and why the firmware work in the plan exists:
;   * no ramp. Walk assist returns early in pas_compute_output, before the
;     ramp, so engage and release are current steps. Keep the level modest.
;   * no watts. The level is a fraction of the motor current limit, so the
;     power it delivers rises with speed.
;   * no settings UI. These constants are the configuration; changing one
;     means re-uploading.
;
; BEFORE IT WILL DO ANYTHING
;
; Set these once in ESCargot Tool, under App Settings -> PAS. The script
; cannot set them: walk-* has no config symbol in either script engine.
;
;   App to use            PAS or ADC+PAS      (ADC+PAS keeps your throttle)
;   Walk source           Lisp                 this script is the source
;   Walk max speed        200 km/h             the cap must be out of the way;
;                                              <= 0.01 means disabled, not
;                                              unlimited
;   Walk current          your level           fraction of the current limit
;   Walk require pedal    off                  the point is no interlock
;   Brake source          ADC, with a channel  MANDATORY. Without it there is
;                         and threshold set    no brake cancel at all.

; Which ADC channel the toggle switch is on, and the voltages that count as on
; and off. Two thresholds, not one, so a switch sitting near the boundary
; cannot chatter.
(def cfg-adc-ch 1)          ; 0 = EXT1/ADC1, 1 = EXT2/ADC2, 2.. = EXT3 up
(def cfg-on-above-v 2.00)
(def cfg-off-below-v 1.50)
(def cfg-invert nil)

; Outside this the pin is treated as disconnected or shorted, and the assist
; is released. A floating input reading mid-rail is the failure this catches,
; and the one most likely to look like a working switch.
(def cfg-valid-min-v 0.10)
(def cfg-valid-max-v 3.20)

; How long the switch has to hold its new state before it counts.
(def cfg-debounce-s 0.06)

; How often to refresh the keepalive. The firmware releases after 0.5 s
; without one, so this has to be comfortably faster than that.
(def cfg-period-s 0.1)

(def garmr-engaged nil)
(def garmr-reason "starting")
(def garmr-raw-v 0.0)

; Pending switch state and when it was first seen, for the debounce.
(def garmr-pending nil)
(def garmr-pending-since 0)

; PAS flag bits, from applications/app.h. Checked against that file, not
; guessed: the first draft of the Lua version had BRAKE-ENGAGED at the wrong
; bit.
(def pas-flag-brake-ch-invalid (shl 1 2))
(def pas-flag-brake-engaged (shl 1 3))
(def pas-flag-speed-limited (shl 1 7))
(def pas-flag-walk-active (shl 1 8))
(def pas-flag-walk-ch-invalid (shl 1 9))

(defun flag-set (flags bit) (not (= (bitwise-and flags bit) 0)))

; Reads the switch. Returns (list state err): state is t, nil or 'unreadable,
; and err is a string or nil.
;
; get-adc raises on a channel the hardware does not have rather than returning
; nil, so the read is trapped. A misconfigured channel must release the assist,
; not kill the thread holding the keepalive -- a thread that dies stops
; refreshing, which does release after half a second, but it also stops
; reporting why.
(defun read-switch () {
    (var r (trap (get-adc cfg-adc-ch)))

    (if (not (eq (car r) 'exit-ok))
        (list 'unreadable "no such ADC channel")
        {
            (var v (car (cdr r)))
            (setq garmr-raw-v v)

            (if (or (< v cfg-valid-min-v) (> v cfg-valid-max-v))
                (list 'unreadable
                      (str-merge "switch input out of range ("
                                 (str-from-n v "%.2f") " V)"))
                {
                    ; A Schmitt trigger: which threshold applies depends on
                    ; where we are now.
                    (var on (if (not (eq garmr-engaged cfg-invert))
                                (> v cfg-off-below-v)
                                (> v cfg-on-above-v)))

                    (list (if cfg-invert (not on) on) nil)
                })
        })
})

; A string when the firmware would refuse to hold anyway, so we do not ask.
(defun blocked () {
    (var flags (app-pas-get-flags))

    (if (not (= (get-fault) 0))
        "fault"
        (if (flag-set flags pas-flag-brake-engaged)
            "brake"
            (if (flag-set flags pas-flag-brake-ch-invalid)
                "brake channel invalid"
                nil)))
})

(defun garmr-step () {
    (var r (read-switch))
    (var want (car r))
    (var err (car (cdr r)))
    (var why (blocked))

    ; An unreadable pin is a release, like the Lua version: when in doubt,
    ; stop driving.
    (if (eq want 'unreadable) (setq want nil))

    ; Debounce: a new state has to persist before it is believed. Releasing is
    ; not debounced.
    (if want
        {
            (if (not garmr-pending) {
                (setq garmr-pending t)
                (setq garmr-pending-since (systime))
            })

            (if why
                {
                    (setq garmr-engaged nil)
                    (setq garmr-reason why)
                }
                (if (>= (secs-since garmr-pending-since) cfg-debounce-s)
                    {
                        (setq garmr-engaged t)
                        (setq garmr-reason "holding")
                    }
                    (setq garmr-reason "debouncing")))
        }
        {
            (setq garmr-pending nil)
            (setq garmr-engaged nil)
            (setq garmr-reason (if err err (if why why "off")))
        })

    ; The keepalive. Called every pass while engaged, and once on release;
    ; stopping the calls is itself the release, after half a second.
    (app-pas-walk-set garmr-engaged)

    garmr-engaged
})

; Whether the firmware actually took the request.
;
; There is no way to read pas-brake-source or any of the walk-* settings from a
; script -- they have no config symbol in either engine -- so the only settings
; check available is to ask for the hold and see whether the firmware starts
; driving. Reporting that is worth more than it sounds: the likely reasons for
; it not to are all Tool settings, and silence would look identical to a broken
; switch.
(defun garmr-diagnose (engaged) {
    (var flags (app-pas-get-flags))

    (if (flag-set flags pas-flag-walk-ch-invalid)
        "walk channel invalid"
        (if (and engaged (not (flag-set flags pas-flag-walk-active)))
            (str-merge "requested, but PAS is not holding -- check Walk "
                       "source is Lisp and Walk current is above zero")
            (if (and engaged (flag-set flags pas-flag-speed-limited))
                "speed limited -- Walk max speed is cutting in; raise it"
                nil)))
})

; GARMR-TEST is defined by the test image, which drives garmr-step itself.
(if (not (eq (car (trap garmr-test)) 'exit-ok))
    {
        (def garmr-last "")

        (print (str-merge "Garmr: switch on ADC " (str-from-n cfg-adc-ch "%d")
                          ", level is the PAS Walk current. Brake cancel "
                          "needs Brake source set in App Settings -> PAS; "
                          "there is none without it."))

        (loopwhile t {
            (garmr-step)

            ; One pass later, so the firmware has acted on the request.
            (var note (garmr-diagnose garmr-engaged))
            (var say (if note note garmr-reason))

            (if (not (eq say garmr-last)) {
                (print (str-merge "Garmr: " say
                                  " (" (str-from-n garmr-raw-v "%.2f") " V)"))
                (setq garmr-last say)
            })

            (sleep cfg-period-s)
        })
    })
