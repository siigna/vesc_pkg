; Copyright Benjamin Vedder
; Copyright 2026 Stephen Bouche
;
; Parts of this file were moved here from dash35b/lib/vehicle-state.lisp;
; git blame -C records 10 lines as Benjamin Vedder's.
; SPDX-License-Identifier: GPL-3.0-or-later

(def indicate-l-on nil)
(def indicate-r-on nil)
(def indicate-ms 0)
(def indicator-timestamp 0)
(def highbeam-on false)

(def kickstand-down false)

; --- Signal requests --------------------------------------------------------
;
; What this display is asking for on the bike's own outputs, as a bitfield in
; byte 3 of SID 201. Nothing in the VESC ecosystem drives these today: a
; controller has exactly two script-drivable outputs, set-aux ports 1 and 2,
; and dash_esc uses those for the lights. This is for a second node on the bus
; that owns the switch gear and has GPIO to spare -- an rmcore, whose shipped
; demo already reads the light bit out of the same frame.
;
; So the frame goes out whether or not anything listens, which costs one byte
; of a frame that was already being sent every 100 ms, and the requests do
; nothing at all until something acts on them.
;
; Not persisted. An indicator that came back on after a power cycle would be
; both surprising and, on a road bike, worse than that.
(def sig-hazard 1)
(def sig-left 2)
(def sig-right 4)
(def sig-beam 8)
(def sig-horn 16)

(def sig-req 0)

; The horn is momentary, and a tap cannot hold anything. A press on the quick
; shade blips it for this long; a held button asserts it for as long as it is
; held, which is what the request byte carries either way.
(def sig-horn-blip-s 0.6)

; systime of the last blip. Measured with secs-since rather than compared
; against a deadline, so nothing here assumes what a systime tick is worth. A
; zero start is simply a blip that finished long ago.
(def sig-horn-ts 0)

; systime of the last SID 30, which is the frame a bike-controls node sends to
; report what the signals are actually doing. While that is recent the reported
; state is what gets displayed and the request is only a request. With no such
; node on the bus the display falls back to showing what it asked for, which is
; the only feedback there is.
(def sig-rx-last 0)
(def sig-rx-timeout 2.0)

(defun sig-reported () (< (secs-since sig-rx-last) sig-rx-timeout))

(defun sig-on (bit) (!= 0 (bitwise-and sig-req bit)))

; Hazard outranks the indicators, and the two indicators cancel each other:
; asking for both is the hazard, and a bike that lit one while the other was on
; would be lying about which way it was going.
(defun sig-toggle (bit) {
        (if (sig-on bit)
            (setq sig-req (bitwise-and sig-req (bitwise-xor bit 0xFF)))
            {
                (if (= bit sig-left)
                    (setq sig-req (bitwise-and sig-req (bitwise-xor sig-right 0xFF))))
                (if (= bit sig-right)
                    (setq sig-req (bitwise-and sig-req (bitwise-xor sig-left 0xFF))))
                (setq sig-req (bitwise-or sig-req bit))
            })
})

(defun sig-horn-blip () (setq sig-horn-ts (systime)))

(defun sig-horn-blipping () (< (secs-since sig-horn-ts) sig-horn-blip-s))

; The byte on the wire. The horn is the one bit that is not latched: it is set
; while a bound button is held or a blip is still running.
(defun sig-byte (held) {
        (var v (bitwise-and sig-req (bitwise-xor sig-horn 0xFF)))
        (if (or held (sig-horn-blipping))
            (bitwise-or v sig-horn)
            v)
})

; What the status strip should show. The reported state when a bike-controls
; node is on the bus, otherwise what this display asked for -- so the
; indicators mean something on a bike where the display is the only thing
; asking. Hazard lights both sides, which is what hazard is.
(defun sig-l-shown ()
    (if (sig-reported) indicate-l-on (or (sig-on sig-left) (sig-on sig-hazard))))

(defun sig-r-shown ()
    (if (sig-reported) indicate-r-on (or (sig-on sig-right) (sig-on sig-hazard))))

(defun sig-beam-shown ()
    (if (sig-reported) highbeam-on (sig-on sig-beam)))

; --- end signal requests ----------------------------------------------------
; test/run.sh extracts everything between the two markers for signal_test, so
; nothing below here can be moved above them.

(def drive-mode 1)

; --- PIN lock ---------------------------------------------------------------
;
; A deterrent, not security. The code is a plain number in eeprom that anything
; on the bus can read, and while only this display enforces it, unplugging the
; display defeats it: dash_esc puts the real limits back five seconds after a
; display stops talking. dash_esc 2.7 can hold the lock itself, which closes
; that at the price of needing VESC Tool over USB to recover a forgotten code.
;
; What the display can do is assert neutral, whose current scale is zero, so
; the motor will not turn. It cannot hold the kill switch: that is an input,
; and there is no setter for it.

; Digits entered so far, as a number and a count, which is enough for a
; four-digit code and avoids a list to append to on every key.
(def pin-entered 0)
(def pin-entry-len 0)

(def pin-locked false)
(def pin-len 4)

; Wrong tries, and the systime the current wait started. Escalating, because
; four digits is ten thousand guesses and a tap is quick.
(def pin-tries 0)
(def pin-wait-ts 0)
(def pin-wait-s 0)
(def pin-wait-left 0)

; Sticky for a couple of seconds so the rider sees why a press did nothing.
(def pin-msg-txt "")
(def pin-msg-ts 0)

(defun pin-notify (txt) {
        (setq pin-msg-txt txt)
        (setq pin-msg-ts (systime))
})

(defun pin-msg ()
    (if (> pin-wait-left 0)
        (str-from-n pin-wait-left "wait %d s")
        (if (< (secs-since pin-msg-ts) 2.0) pin-msg-txt "")))

(defun pin-dots () {
        (var out "")
        (looprange i 0 pin-len
            (setq out (str-merge out (if (< i pin-entry-len) "*" "-") " ")))
        out
})

(defun pin-clear () {
        (setq pin-entered 0)
        (setq pin-entry-len 0)
})

; Counted down by the main loop rather than computed in the view, so the view
; redraws when the number changes and not on every frame.
(defun pin-tick () {
        (var left (if (> pin-wait-s 0)
                      (- pin-wait-s (to-i (secs-since pin-wait-ts)))
                      0))
        (setq pin-wait-left (if (> left 0) left 0))
        (if (and (= pin-wait-left 0) (> pin-wait-s 0)) (setq pin-wait-s 0))
})

(defun pin-waiting () (> pin-wait-left 0))

; A key: a digit, -1 to clear, -2 to submit. Submitting a short code is
; treated as a wrong one rather than ignored, so a rider who mistypes gets the
; same feedback either way.
; defunret, not defun: the early exit below needs it, and without it every key
; press during a lockout threw variable_not_bound instead of being ignored.
(defunret pin-key (v) {
        (if (pin-waiting) (return nil))
        (cond
            ((= v -1) (pin-clear))
            ((= v -2) (pin-submit))
            ((< pin-entry-len pin-len) {
                    (setq pin-entered (+ (* pin-entered 10) v))
                    (setq pin-entry-len (+ pin-entry-len 1))
                    ; Submit on the last digit, so a four digit code needs four
                    ; taps rather than five.
                    (if (= pin-entry-len pin-len) (pin-submit))
            })
        )
})

(defun pin-submit () {
        (if (and (= pin-entry-len pin-len) (= pin-entered settings-pin-code))
            {
                (setq pin-tries 0)
                (setq pin-locked false)
                (pin-clear)
                (pin-unlock-send)
            }
            {
                (setq pin-tries (+ pin-tries 1))
                (pin-clear)
                ; Three free tries, then five seconds a try, capped at a
                ; minute: long enough to be tedious, short enough that a rider
                ; who fumbled their own code is not stranded.
                (if (> pin-tries 3) {
                        (var w (* 5 (- pin-tries 3)))
                        (setq pin-wait-s (if (> w 60) 60 w))
                        (setq pin-wait-ts (systime))
                })
                (pin-notify "Wrong code")
            })
})

; Lock now, or at startup. Clears any entry in progress and any wait, so the
; rider is not made to sit out a penalty they earned before locking.
(defun pin-engage () {
        (setq pin-locked true)
        (setq pin-tries 0)
        (setq pin-wait-s 0)
        (setq pin-wait-left 0)
        (pin-clear)
        (pin-lock-send)
})

; What goes out as the drive mode while the lock is up. Neutral, index 1, whose
; current scale is zero. The stored mode is left alone so unlocking puts the
; rider back in the mode they were in.
(defun pin-drive-mode () (if pin-locked 1 drive-mode))

; --- end PIN lock -----------------------------------------------------------
; test/run.sh extracts everything between these markers for pin_test.


; systime of the last mode this display asserted itself. While that is recent
; the controller's reported mode is not followed, so a button press, the
; kickstand or charging cannot be undone by the controller echoing back a mode
; it has not been told about yet.
(def mode-cmd-ts 0)

; The controller has suspended its drive profile for servicing
(def service-mode false)

; The controller's stored motor parameters cannot describe a real motor
(def motor-bad false)

(defun mode-set (m) {
        (setq drive-mode m)
        (setq mode-cmd-ts (systime))
})
(def performance-mode 'eco) ; 'eco 'normal 'sport UNUSED!

(def cruise-control-active false)
(def cruise-control-speed 0.0)

(def battery-a-charging false)
(def battery-a-chg-time 0)
(def battery-a-connected false) ; Has received msg from BMS A

(def battery-b-soc 0.0)
(def battery-b-charging false)
(def battery-b-chg-time 0)
(def battery-b-connected false) ; Has received msg from BMS B

(def page-now 0)
(def page-num 3)

(def setting-now 0)
(def setting-num 0)

; setting-list-page1 etc are built by settings-build.

(def light-on light-on-default)
(def backlight-dim false)

; For changes per-field detection cannot see, e.g. a unit label swap.
(def view-force-static false)
(def view-force-pages false)

(def temp-ambient 0.0)
(def temp-ambient-rx false)

(def date-time nil)
(def date-time-rx false)
