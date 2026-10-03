; Copyright 2026 Stephen Bouche
; SPDX-License-Identifier: GPL-3.0-or-later
;
; The firmware extensions garmr.lisp uses, as stubs the test drives. Only the
; six it actually calls, so a seventh appearing in the script fails here rather
; than being quietly satisfied.
;
; get-adc raises on a channel the hardware does not have, which is what the
; real one does -- ENC_SYM_EERROR from ext_get_adc's default arm -- and the
; script traps it. A stub returning nil instead would make that path untested.

(def fake-adc 0.0)
(def fake-flags 0)
(def fake-fault 0)
(def walk-calls 0)
(def last-walk 'never)

; (car 1) raises type_error, which is what this needs: the real get-adc
; returns ENC_SYM_EERROR for a channel the hardware does not have, and an
; extension returning that raises in the caller. The first version called
; (raise 'eerror) -- and raise does not exist in LispBM or in vesc_express, so
; it raised variable_not_bound instead. The trap caught it either way and the
; checks passed, which is the problem: it was testing that calling a
; nonexistent function raises, not that get-adc does.
(defun get-adc (ch) (if (= ch 1) fake-adc (car 1)))
(defun get-fault () fake-fault)
(defun app-pas-get-flags () fake-flags)
(defun app-pas-walk-set (v) {
    (setq walk-calls (+ walk-calls 1))
    (setq last-walk v)
})

; Tells garmr.lisp not to start its own loop: the test drives garmr-step.
(def garmr-test t)
