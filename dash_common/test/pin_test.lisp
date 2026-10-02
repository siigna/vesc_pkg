; Copyright 2026 Stephen Bouche
; SPDX-License-Identifier: GPL-3.0-or-later
; Unit tests for the PIN lock state machine in lib/vehicle-state.lisp.
;
; It is a deterrent rather than security -- the code is plain in eeprom -- so
; what is worth testing is that it behaves like a lock rather than that it
; resists an attacker: that it starts locked, that a wrong code never opens it,
; that a partial code does not, that the lockout escalates and expires, and
; that the drive mode it asserts is neutral and not something that moves.
(import "stubs.lisp" 'code-stubs)
(read-eval-program code-stubs)

; What the block reads from elsewhere.
(def settings-pin-code 0)
(def drive-mode 4)
(def pin-sends nil)
(defun pin-lock-send () (setq pin-sends (cons 'lock pin-sends)))
(defun pin-unlock-send () (setq pin-sends (cons 'unlock pin-sends)))

(import "build/common/pin_fn.lisp" 'c-pin)
(read-eval-program c-pin)

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

(defun enter (code) (loopforeach d code (pin-key d)))

(setq settings-pin-code 1234)

; Unlocked to begin with, and the stored mode goes out untouched.
(is 'starts-unlocked pin-locked nil)
(is-n 'mode-passes-through (pin-drive-mode) 4)

; Engaging asserts neutral, which is index 1 and the mode whose current scale
; is zero. Index 0 is reverse, so getting this wrong would be worse than not
; locking at all.
(pin-engage)
(is 'engaged pin-locked t)
(is-n 'asserts-neutral (pin-drive-mode) 1)
(is-n 'stored-mode-untouched drive-mode 4)
(is 'lock-sent (eq (car pin-sends) 'lock) t)

; The right code, entered a digit at a time, opens it on the fourth without
; needing OK.
(enter '(1 2 3 4))
(is 'unlocked pin-locked nil)
(is-n 'mode-restored (pin-drive-mode) 4)
(is 'unlock-sent (eq (car pin-sends) 'unlock) t)
(is-n 'entry-cleared pin-entry-len 0)

; A wrong code does not, and leaves nothing half-entered behind.
(pin-engage)
(enter '(1 2 3 5))
(is 'wrong-stays-locked pin-locked t)
(is-n 'wrong-clears-entry pin-entry-len 0)

; A partial code plus OK is a wrong code rather than a no-op, so a mistype
; gives the same feedback either way.
(pin-clear)
(enter '(1 2))
(pin-key -2)
(is 'short-stays-locked pin-locked t)
(is-n 'short-clears-entry pin-entry-len 0)

; Clear does what it says, and does not unlock anything.
(enter '(1 2 3))
(is-n 'three-entered pin-entry-len 3)
(pin-key -1)
(is-n 'cleared pin-entry-len 0)
(is 'clear-does-not-unlock pin-locked t)

; The entry never holds more than the code length. A fourth digit submits and
; clears, so a fifth press starts a new attempt rather than extending the old
; one -- which is why this checks the invariant over a long run of presses
; instead of a single expected count.
(pin-clear)
(def over-len nil)
(looprange i 0 20 {
        (pin-key 9)
        (if (> pin-entry-len pin-len) (setq over-len t))
})
(is 'never-over-length over-len nil)
(is 'still-locked pin-locked t)

; The lockout escalates after three wrong tries and blocks input while it runs.
(setq pin-tries 0)
(setq pin-wait-s 0)
(pin-tick)
(is 'not-waiting-yet (pin-waiting) nil)
(looprange i 0 3 (enter '(0 0 0 0)))
(pin-tick)
(is 'three-tries-free (pin-waiting) nil)
(enter '(0 0 0 0))
(pin-tick)
(is 'fourth-try-waits (pin-waiting) t)

; A correct code typed during the wait is ignored rather than accepted.
(enter '(1 2 3 4))
(is 'locked-during-wait pin-locked t)
(is-n 'keys-ignored pin-entry-len 0)

; The wait expires, and then the correct code works. Shortened to a second and
; actually slept through rather than backdating the timestamp: pin-tick
; measures with secs-since and nothing here should assume what a systime tick
; is worth, which is the same reason the code does not compare deadlines.
(setq pin-wait-s 1)
(setq pin-wait-ts (systime))
(pin-tick)
(is 'waiting-one-second (pin-waiting) t)
(sleep 1.1)
(pin-tick)
(is 'wait-expired (pin-waiting) nil)
(enter '(1 2 3 4))
(is 'unlocks-after-wait pin-locked nil)

; The wait is capped, or a few fat-fingered tries would strand a rider.
(pin-engage)
(setq pin-tries 0)
(looprange i 0 40 {
        (setq pin-wait-s 0)
        (setq pin-wait-left 0)
        (enter '(0 0 0 0))
})
(is 'wait-capped (<= pin-wait-s 60) t)

; A code of zero is a usable code, not "no code": whether the lock is on at
; all is a separate setting, so 0000 must not unlock a bike set to 1234.
(setq settings-pin-code 0)
(pin-engage)
(enter '(0 0 0 0))
(is 'zero-code-works pin-locked nil)
(setq settings-pin-code 1234)
(pin-engage)
(enter '(0 0 0 0))
(is 'zero-is-not-a-master-code pin-locked t)

(print (list 'pin checks 'checks fails 'fails))
