; Copyright 2026 Stephen Bouche
; SPDX-License-Identifier: GPL-3.0-or-later
; Unit tests for the walk assist request in main_body.lisp. Pure logic, so no
; display needed.
;
; The request is deliberately derived from the held button state rather than
; from btn-do-action, because the controller expires a walk request after half a
; second and so it has to be re-sent for as long as the button is down. Three
; conditions have to line up for that, which is what these check.
(import "stubs.lisp" 'code-stubs)
(read-eval-program code-stubs)

; The pieces walk-requested reads, which normally come from the board's
; lib/input.lisp and from persistent-settings.
(def btn-hold-region nil)
(def btn-hold-progress 0.0)
(def btn-actions-long (list 0 0 0 0))

; The real walk-requested, extracted from main_body.lisp by run.sh, so this
; cannot drift from what ships. Importing main_body whole would drag in the
; views and the display.
(import "build/common/walk_fn.lisp" 'c-walk)
(read-eval-program c-walk)

(def checks 0)
(def fails 0)
(defun is (what got want) {
        (setq checks (+ checks 1))
        (if (not (eq (not got) (not want))) {
                (setq fails (+ fails 1))
                (print (list 'FAIL what 'got got 'want want))
        })
})

; Nothing held.
(setq btn-actions-long (list 13 0 0 0))
(setq btn-hold-region nil)
(setq btn-hold-progress 0.0)
(is 'nothing-held (walk-requested) nil)

; Held, but not yet past the long-press point. A tap must not walk.
(setq btn-hold-region 0)
(setq btn-hold-progress 0.5)
(is 'held-part-way (walk-requested) nil)

; Held past it, on a button whose long action is walk assist.
(setq btn-hold-progress 1.0)
(is 'held-full (walk-requested) t)

; Released. This is what stops the request, on the next frame.
(setq btn-hold-region nil)
(is 'released (walk-requested) nil)

; A different button, whose long action is something else.
(setq btn-hold-region 1)
(setq btn-hold-progress 1.0)
(is 'wrong-button (walk-requested) nil)

; Walk assist assigned to that button instead.
(setq btn-actions-long (list 0 13 0 0))
(is 'other-button-assigned (walk-requested) t)

; No button has it assigned at all.
(setq btn-actions-long (list 0 0 0 0))
(is 'unassigned (walk-requested) nil)

; Every button assigned, each held in turn.
(setq btn-actions-long (list 13 13 13 13))
(looprange i 0 4 {
        (setq btn-hold-region i)
        (is (list 'button i) (walk-requested) t)
})

(print (list 'walk checks 'checks fails 'fails))
