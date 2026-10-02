; Copyright 2026 Stephen Bouche
; SPDX-License-Identifier: GPL-3.0-or-later
; Unit tests for the signal request bitfield in lib/vehicle-state.lisp, which
; is what byte 3 of SID 201 carries for a bike-controls node to act on.
;
; Two rules are the point of it and neither is visible in the bit values: the
; two indicators cancel each other, because a bike that lit one while the other
; was on would be lying about which way it is going; and the horn is not
; latched, because a latched horn is a stuck horn.
(import "stubs.lisp" 'code-stubs)
(read-eval-program code-stubs)

(import "build/common/signal_fn.lisp" 'c-sig)
(read-eval-program c-sig)

(def checks 0)
(def fails 0)
(defun is (what got want) {
        (setq checks (+ checks 1))
        (if (not (eq (not got) (not want))) {
                (setq fails (+ fails 1))
                (print (list 'FAIL what 'got got 'want want))
        })
})
(defun is-n (what got want) {
        (setq checks (+ checks 1))
        (if (not (= got want)) {
                (setq fails (+ fails 1))
                (print (list 'FAIL what 'got got 'want want))
        })
})

(setq sig-req 0)
(is 'clean-start (sig-on sig-left) nil)
(is-n 'clean-byte (sig-byte false) 0)

; Latching, and toggling back off.
(sig-toggle sig-left)
(is 'left-on (sig-on sig-left) t)
(is-n 'left-byte (sig-byte false) sig-left)
(sig-toggle sig-left)
(is 'left-off (sig-on sig-left) nil)
(is-n 'left-off-byte (sig-byte false) 0)

; The indicators cancel each other rather than both being on.
(sig-toggle sig-left)
(sig-toggle sig-right)
(is 'right-wins (sig-on sig-right) t)
(is 'left-cleared (sig-on sig-left) nil)
(sig-toggle sig-left)
(is 'left-wins-back (sig-on sig-left) t)
(is 'right-cleared (sig-on sig-right) nil)

; Hazard is independent of both, and turning an indicator on must not clear it.
(sig-toggle sig-hazard)
(is 'hazard-on (sig-on sig-hazard) t)
(is 'left-still-on (sig-on sig-left) t)
(sig-toggle sig-right)
(is 'hazard-survives (sig-on sig-hazard) t)
(is 'right-on-with-hazard (sig-on sig-right) t)
(is 'left-off-with-hazard (sig-on sig-left) nil)

; The beam is independent of everything.
(sig-toggle sig-beam)
(is 'beam-on (sig-on sig-beam) t)
(is 'hazard-untouched (sig-on sig-hazard) t)
(sig-toggle sig-beam)
(is 'beam-off (sig-on sig-beam) nil)

; The horn is never latched, whatever else is set.
(setq sig-req 0)
(sig-toggle sig-horn)
(is-n 'horn-not-in-byte (bitwise-and (sig-byte false) sig-horn) 0)
(is-n 'horn-on-when-held (bitwise-and (sig-byte true) sig-horn) sig-horn)

; A blip sets it for as long as the blip lasts, then clears itself.
(setq sig-req 0)
(is 'not-blipping (sig-horn-blipping) nil)
(sig-horn-blip)
(is 'blipping (sig-horn-blipping) t)
(is-n 'blip-in-byte (bitwise-and (sig-byte false) sig-horn) sig-horn)
(sleep (+ sig-horn-blip-s 0.1))
(is 'blip-expired (sig-horn-blipping) nil)
(is-n 'blip-gone-from-byte (bitwise-and (sig-byte false) sig-horn) 0)

; Everything at once still fits in a byte, which is all there is on the wire.
(setq sig-req 0)
(sig-toggle sig-hazard)
(sig-toggle sig-left)
(sig-toggle sig-beam)
(is-n 'all-set (sig-byte true)
    (bitwise-or sig-hazard (bitwise-or sig-left (bitwise-or sig-beam sig-horn))))
(is 'fits-in-a-byte (<= (sig-byte true) 255) t)

; What the strip shows. With a node reporting, the received values; without
; one, the request -- and hazard lights both sides either way it is asked.
(setq sig-req 0)
(def indicate-l-on true)
(def indicate-r-on false)
(def highbeam-on true)
(defun sig-reported () true)
(is 'reported-left (sig-l-shown) t)
(is 'reported-right (sig-r-shown) nil)
(is 'reported-beam (sig-beam-shown) t)

(defun sig-reported () false)
(is 'fallback-left-off (sig-l-shown) nil)
(is 'fallback-beam-off (sig-beam-shown) nil)
(sig-toggle sig-hazard)
(is 'hazard-lights-left (sig-l-shown) t)
(is 'hazard-lights-right (sig-r-shown) t)
(sig-toggle sig-hazard)
(sig-toggle sig-right)
(is 'fallback-right-only (sig-r-shown) t)
(is 'fallback-left-still-off (sig-l-shown) nil)

(print (list 'signal checks 'checks fails 'fails))
