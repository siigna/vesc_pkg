; Touch input.
;
; The other dashes in this family have two to four physical buttons and map
; them through btn-actions-short / btn-actions-long. This board has none, so
; the screen is divided into regions that stand in for those buttons and the
; same action codes are reused. That keeps btn-do-action, the settings page
; navigation and the stored button-action settings working unchanged.
;
; Regions (480x480):
;
;   +------------------------------------------+
;   |                                          |
;   |   btn 1 (left half)   btn 2 (right half) |  y < nav-y: paging
;   |                                          |
;   +------------------------------------------+ nav-y
;   |  btn 0   |    btn 3   |    btn 2         |  bottom strip
;   +------------------------------------------+
;
; A press fires on release, so a drag out of a region cancels it, and a hold
; past t-long-press fires the long action instead.

(def btn-0-pressed nil)
(def btn-1-pressed nil)
(def btn-2-pressed nil)
(def btn-3-pressed nil)

(def touch-x 0)
(def touch-y 0)

@const-start

; Evaluate expression if the function isn't nil.
(def maybe-call (macro (expr) {
            (var fun (first expr))
            `(if ,fun
                ,expr
            )
}))

(defun input-cleanup-on-pressed () {
        (def on-btn-0-pressed nil)
        (def on-btn-1-pressed nil)
        (def on-btn-2-pressed nil)
        (def on-btn-3-pressed nil)

        (def on-btn-0-long-pressed nil)
        (def on-btn-1-long-pressed nil)
        (def on-btn-2-long-pressed nil)
        (def on-btn-3-long-pressed nil)

        (def on-btn-0-repeat-press nil)
        (def on-btn-1-repeat-press nil)
        (def on-btn-2-repeat-press nil)
        (def on-btn-3-repeat-press nil)
})

; Which virtual button a coordinate belongs to, or nil for none.
(defun touch-region (x y)
    (if (< y nav-y)
        (if (< x (/ disp-w 2)) 1 2)
        (cond
            ((< x (/ disp-w 3)) 0)
            ((< x (* 2 (/ disp-w 3))) 3)
            (t 2)
        )
))

(defun input-thread () {
        (var btn-now nil)		; region the finger went down in
        (var btn-start (systime))
        (var long-fired nil)
        (var repeat-ts (systime))
        (var t-long-press 0.6)

        (loopwhile t {
                (sleep 0.02)

                ; A read failure means the controller fell off the bus. Report
                ; no touch rather than taking down the thread, so a loose
                ; connector does not cost the whole UI.
                (var p (match (trap (touch-read))
                        ((exit-ok (? v)) v)
                        (_ nil)
                ))

                (if p {
                        (setq touch-x (ix p 0))
                        (setq touch-y (ix p 1))
                })

                (var region (if p (touch-region touch-x touch-y) nil))

                (cond
                    ; Finger down in a new region
                    ((and region (not btn-now)) {
                            (setq btn-now region)
                            (setq btn-start (systime))
                            (setq repeat-ts (systime))
                            (setq long-fired nil)
                    })

                    ; Held. Dragging into another region cancels rather than
                    ; retargeting, which is what a button would do.
                    ((and region btn-now) {
                            (if (not-eq region btn-now)
                                (setq btn-now nil)
                                {
                                    (if (and (not long-fired)
                                             (>= (secs-since btn-start) t-long-press)) {
                                            (setq long-fired true)
                                            (cond
                                                ((= btn-now 0) (maybe-call (on-btn-0-long-pressed)))
                                                ((= btn-now 1) (maybe-call (on-btn-1-long-pressed)))
                                                ((= btn-now 2) (maybe-call (on-btn-2-long-pressed)))
                                                ((= btn-now 3) (maybe-call (on-btn-3-long-pressed)))
                                            )
                                    })

                                    ; Repeat lets the settings page scroll a
                                    ; value without tapping once per step
                                    (if (and long-fired (>= (secs-since repeat-ts) 0.15)) {
                                            (setq repeat-ts (systime))
                                            (cond
                                                ((= btn-now 0) (maybe-call (on-btn-0-repeat-press)))
                                                ((= btn-now 1) (maybe-call (on-btn-1-repeat-press)))
                                                ((= btn-now 2) (maybe-call (on-btn-2-repeat-press)))
                                                ((= btn-now 3) (maybe-call (on-btn-3-repeat-press)))
                                            )
                                    })
                                }
                            )
                    })

                    ; Released
                    ((and (not region) btn-now) {
                            (if (not long-fired)
                                (cond
                                    ((= btn-now 0) (maybe-call (on-btn-0-pressed)))
                                    ((= btn-now 1) (maybe-call (on-btn-1-pressed)))
                                    ((= btn-now 2) (maybe-call (on-btn-2-pressed)))
                                    ((= btn-now 3) (maybe-call (on-btn-3-pressed)))
                                )
                            )
                            (setq btn-now nil)
                    })
                )

                (setq btn-0-pressed (eq btn-now 0))
                (setq btn-1-pressed (eq btn-now 1))
                (setq btn-2-pressed (eq btn-now 2))
                (setq btn-3-pressed (eq btn-now 3))
        })
})

@const-end
