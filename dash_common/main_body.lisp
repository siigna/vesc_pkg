; Shared body of the touch dash packages. Everything here is independent of
; the panel and the board.
;
; NOTE: this file deliberately contains no (import ...) lines. vesc_tool packs
; imports by scanning the top-level lisp file only, with no recursion
; (codeloader.cpp, lispPackImports), so an import in here would never make it
; into the package. Each board's main.lisp does all the importing and loads
; this last.
;
; What the board must have set up before this is loaded:
;   config.lisp       disp-w disp-h strip-h speed-h page-h page-cols
;                     config-dm-pool config-touch-transforms
;                     config-btn-actions-short config-btn-actions-long
;   lib/*             the shared library and the board's own input.lisp
;   views/*           view_static and view_pages
;   fonts             font-speed font-40 font-24 font-16
;   board-disp-init   brings the panel up and applies the rotation
;   board-touch-init  loads the touch controller
;   bl-set            backlight, 0..1

@const-start

(defun setting-update (op) {
        (if (> setting-num 0) {
                (var setting (ix setting-list-page1 setting-now))
                (var lim (ix setting-lim-page1 setting-now))
                (var step (ix setting-step-page1 setting-now))

                (write-setting setting
                    (clamp
                        (eval (list op (read-setting setting) step))
                        (first lim)
                        (second lim)
                ))

                (settings-load)
                (settings-apply-units)
        })
})

; Stored in eeprom, so these keep their meaning.
; 0 none  1 page+  2 page-  3 settings  4 mode+  5 mode-
; 6 lights  7 backlight dim  8 cruise
; True while a button whose long action is walk assist is being held past the
; long-press point. Derived from the held state rather than from btn-do-action,
; which fires once: the controller expires a walk request after half a second,
; so it has to be re-sent for as long as the button is down. Releasing the
; button clears btn-hold-region, which stops the request on the next frame.
(defun walk-requested () {
        (var idx btn-hold-region)
        (and idx
             (= (ix btn-actions-long idx) 13)
             (>= btn-hold-progress 1.0))
})

; conf-nudge stays here rather than in the library because it
; reports through notify, which is part of the main loop.
(defun conf-nudge (dir) {
        (var row (conf-row conf-now))
        (var v (conf-value conf-now))
        (if (eq v nil)
            (notify "Waiting for controller")
            (if (conf-blocked conf-now)
                (notify "Kill switch off")
                (conf-send 0 (ix row 0) (+ v (* dir (ix row 3))))))
})

(defun btn-do-action (a)
    (cond
        ((= a 1) (setq page-now (mod (+ page-now 1) page-num)))
        ((= a 2) (setq page-now (mod (+ page-now (- page-num 1)) page-num)))
        ((= a 3) (setq page-now (if (= page-now page-num) 0 page-num)))
        ((= a 4) (if (< drive-mode (- drive-mode-num 1)) (mode-set (+ drive-mode 1))))
        ((= a 5) (if (> drive-mode 0) (mode-set (- drive-mode 1))))
        ((= a 6) (setq light-on (not light-on)))
        ; Action 7 dims the backlight on the other dashes. This panel has no
        ; backlight control, so it is accepted and ignored rather than
        ; renumbered, which would change what stored settings mean.
        ((= a 7) nil)
        ; Action 13 is walk assist, which is held rather than triggered: the
        ; controller releases it unless the request keeps being refreshed. So
        ; there is nothing to do on the edge, and walk-requested below derives
        ; it from the button that is currently held instead.
        ((= a 13) nil)
        ; 14 writes the running configuration to flash, 15 throws the unsaved
        ; changes away. Both are refused by the controller unless the kill
        ; switch is on, since writing fights anything else touching the
        ; configuration and reverting mid-ride would change the feel abruptly.
        ((= a 14) (conf-send 1 0 0.0))
        ((= a 15) (conf-send 2 0 0.0))
        ((= a 8) (comm-send-event 0))
        ((= a 9) (comm-send-event 2)) ; start or stop logging on the controller
        ; Clears the session maxima, the voltage floor and both timers. Bound
        ; to a long press: while it is held the session page fades the values
        ; it is about to clear, so the press is its own confirmation.
        ((= a 12) (stats-reset-max))
        (t nil)
))

; Index of a page in the enabled set, or nil when settings-page-mask has that
; page switched off.
(defun page-index (p) (list-find pages p))

; Which live slots the chart can be pointed at, in cell order and without
; duplicates. The gesture can only reach what is on the live page, so the
; button fallback steps through the same set rather than the whole catalog.
(defun chart-sources () {
        (var out nil)
        (looprange i 0 4 {
                (var src (ix settings-slots i))
                (if (not (list-find out src)) (setq out (cons src out)))
        })
        (reverse out)
})

; Point the chart at a slot-catalog source and go to the chart page. A live cell
; already holds a catalog index, which is the same thing the chart page plots,
; so no new mapping is needed. Written through so the choice survives a power
; cycle.
(defun chart-set-src (src) {
        (var pg (page-index page-chart))
        (if (eq pg nil)
            (notify "Chart page off")
            {
                (setq settings-chart-src src)
                (write-setting 'chart-src src)
                (setq page-now pg)
                (notify (str-merge "Charting " (slot-label src)))
            })
})

; Step the chart source along the live slots. For the chart page's own buttons,
; so the source is reachable without the gesture; stays on the chart page.
(defun chart-step (dir) {
        (var srcs (chart-sources))
        (var n (length srcs))
        (var at (list-find srcs settings-chart-src))
        (var next (ix srcs (mod (+ (if at at 0) dir n) n)))
        (setq settings-chart-src next)
        (write-setting 'chart-src next)
        (notify (slot-label next))
})

(defun chart-step-secs () {
        (setq settings-chart-secs (if (= settings-chart-secs 10) 5 10))
        (write-setting 'chart-secs settings-chart-secs)
})

; Long presses go through here so that a page can claim the gesture, the way
; btn-short lets the settings and controller pages claim short ones. On the live
; page a hold over a cell charts that cell, which is the only way to pick what
; the chart plots by pointing at it. A hold that lands outside the cell grid, or
; on any other page, falls through to the action stored for that region -- so
; the session reset on a held region still works everywhere except over a live
; cell, where the cell highlight says what the press will do instead.
(defun btn-long (idx) {
        (var pg (ix pages page-now))
        ; Walk assist is not claimable. It is held rather than triggered, and
        ; walk-requested reads the held state directly, so claiming the region
        ; would leave the walk request running while the chart page opened.
        (var walk (= (ix btn-actions-long idx) 13))
        (var cell (if (and (eq pg page-live) (not walk))
                      (live-cell-hit touch-x touch-y) nil))
        (cond
            (cell (chart-set-src (ix settings-slots cell)))
            ((and (eq pg page-chart) (< touch-y nav-y) (not walk))
                (chart-step-secs))
            (t (btn-do-action (ix btn-actions-long idx)))
        )
})

; On the settings page short presses always navigate it
(defun btn-short (idx)
    (cond
        ((= page-now page-num)
            (cond
                ((= idx 0) (if (> setting-num 0)
                              (setq setting-now (mod (+ setting-now 1) setting-num))))
                ((= idx 1) (setting-update -))
                ((= idx 2) (setting-update +))
                (t (btn-do-action (ix btn-actions-short idx)))
            ))
        ; The chart page steps its source, but only for a press above the nav
        ; strip: regions 1 and 2 are both the screen halves and the strip, and
        ; claiming the strip too would leave no way to page off the chart.
        ((and (eq (ix pages page-now) page-chart) (< touch-y nav-y))
            (cond
                ((= idx 1) (chart-step -1))
                ((= idx 2) (chart-step 1))
                (t (btn-do-action (ix btn-actions-short idx)))
            ))
        ; The controller settings page scrolls and adjusts the same way, but
        ; the values live on the controller so a press sends a frame rather
        ; than writing eeprom.
        ((eq (ix pages page-now) page-conf)
            (cond
                ((= idx 0) (setq conf-now (mod (+ conf-now 1) (conf-menu-len))))
                ((= idx 1) (conf-nudge -1.0))
                ((= idx 2) (conf-nudge 1.0))
                (t (btn-do-action (ix btn-actions-short idx)))
            ))
        (t (btn-do-action (ix btn-actions-short idx)))
))

; A short-lived banner over the normal views, used for things the controller
; reports back such as logging starting and stopping. Cleared by forcing the
; views to redraw rather than by repainting what was underneath.
(def notify-txt nil)
(def notify-ts 0)

(defun notify (txt) {
        (setq notify-txt txt)
        (setq notify-ts (systime))
})

(defun notify-draw (txt) {
        (var imgbuf (img-buffer dm-pool 'indexed4 360 48))
        (img-clear imgbuf)
        (img-rectangle imgbuf 0 0 360 48 1 '(rounded 8))
        (ttf-txt-center txt font-24 imgbuf)
        (disp-render imgbuf 60 216 colors-text-aa)
})

(defun notify-thread () {
        (var service-last false)

        (loopwhile t {
                ; Leaving service mode uncovers whatever the banner sat on
                (if (and service-last (not (or service-mode motor-bad))) {
                        (setq view-force-static true)
                        (setq view-force-pages true)
                })
                (setq service-last (or service-mode motor-bad))

                (cond
                    ; The motor will not run at all in this state, so this
                    ; outranks everything else on screen.
                    (motor-bad (notify-draw "MOTOR CONFIG BAD"))

                    ; The mode on screen means nothing while the drive profile
                    ; is suspended, and neutral no longer holds the throttle
                    ; shut, so keep saying so until it is switched back.
                    (service-mode (notify-draw "SERVICE"))

                    (notify-txt
                        (if (> (secs-since notify-ts) 2.5) {
                                (setq notify-txt nil)
                                (setq view-force-static true)
                                (setq view-force-pages true)
                        }
                        (notify-draw notify-txt)))
                )

                (sleep 0.2)
        })
})

(defun show-splash () {
        (print "Splash")

        (var imgbuf (img-buffer dm-pool 'indexed4 disp-w 60))
        (img-clear imgbuf)
        (ttf-txt-center "VESC" font-40 imgbuf)
        (disp-render imgbuf 0 190 colors-vesc)

        (var verimg (img-buffer dm-pool 'indexed4 disp-w 30))
        (img-clear verimg)
        (ttf-txt-center splash-version font-24 verimg)
        (disp-render verimg 0 260 colors-text-aa)

        (sleep 1.5)
        (disp-clear color-bg)
})

(defun main () {
        (if (and
                (> (conf-get 'wifi-mode) 0)
                (> (conf-get 'ble-mode) 0)
                ) {
                (print "WiFi and BLE enabled, not enough memory to run UI. Disabling wifi...")
                (conf-set 'wifi-mode 0)
                (conf-set 'controller-id 4)
                (conf-store)
                (sleep 5)
                (reboot)
        })

        ; Image buffers are full-panel-width strips, so the pool scales with
        ; the panel: an indexed4 strip costs disp-w * h / 4 bytes and the
        ; speed readout is the tallest of them.
        (def dm-pool (dm-create config-dm-pool))

        (set-print-prefix "DISP-")

        (def init-complete nil)
        (def rx-cnt-can 0)

        (if (eq (car (trap {
                            (settings-load)
                            (settings-build)
                            (colors-build)
                })) 'exit-error) {
                (print "Settings failed to load, using defaults")

                (trap {
                        (restore-settings)
                        (settings-load)
                        (settings-build)
                        (colors-build)
                })
        })

        (settings-apply-units)

        (if config-code-server (start-code-server)) ; Enable remote code execution

        ; The board profile owns every pin and the panel bring-up sequence.
        (board-disp-init)
        (disp-clear color-bg)

        ; Touch is optional: paging is the only thing it drives, so a dead
        ; controller costs the page buttons and nothing else.
        (match (trap (board-touch-init))
            ((exit-error (? e)) (print (list "Touch init failed" e)))
            (_ (apply touch-apply-transforms config-touch-transforms))
        )

        (if settings-splash (trap (show-splash)))

        (event-register-handler (spawn event-handler))
        (event-enable 'event-can-sid)
        (event-enable 'event-data-rx)

        (loopwhile-thd ("Stats" 200) t {
                (print "Starting stats-thread")
                (match (trap (stats-thread))
                    ((exit-ok (? a)) (print "Stats-thread exit"))
                    (_ (print "Stats-thread crashed"))
                )
                (sleep 5.0)
        })

        (input-cleanup-on-pressed)
        (loopwhile-thd ("Input" 200) t {
                (print "Starting Input-thread")
                (match (trap (input-thread))
                    ((exit-ok (? a)) (print "Input-thread exit"))
                    (_ (print "Input-thread crashed"))
                )
                (sleep 5.0)
        })

        (loopwhile-thd ("CommTX" 200) t {
                (print "Starting CommTX-thread")
                (match (trap (comm-tx-thread))
                    ((exit-ok (? a)) (print "CommTX-thread exit"))
                    (_ (print "CommTX-thread crashed"))
                )
                (sleep 5.0)
        })

        (loopwhile-thd ("Notify" 120) t {
                (print "Starting Notify-thread")
                (match (trap (notify-thread))
                    ((exit-ok (? a)) (print "Notify-thread exit"))
                    (_ (print "Notify-thread crashed"))
                )
                (sleep 5.0)
        })

        (loopwhile-thd ("ViewStatic" 200) t {
                (print "Starting ViewStatic-thread")
                (match (trap (view-static-thread))
                    ((exit-ok (? a)) (print "ViewStatic-thread exit"))
                    (_ (print "ViewStatic-thread crashed"))
                )
                (sleep 5.0)
        })

        (loopwhile-thd ("ViewPages" 200) t {
                (print "Starting ViewPages-thread")
                (match (trap (view-pages-thread))
                    ((exit-ok (? a)) (print "ViewPages-thread exit"))
                    (_ (print "ViewPages-thread crashed"))
                )
                (sleep 5.0)
        })

        (loopwhile-thd ("Standalone" 200) t {
                (print "Starting Standalone-thread")
                (match (trap (standalone-thread))
                    ((exit-ok (? a)) (print "Standalone-thread exit"))
                    (_ (print "Standalone-thread crashed"))
                )
                (sleep 5.0)
        })

        (loopwhile-thd ("Worker" 150) t {
                (if settings-redraw (trap (settings-apply-visual)))
                (if battery-a-charging (mode-set 1)) ; Put in neutral when charging
                (if kickstand-down (mode-set 1)) ; Put in neutral when kickstand is down
                (sleep 0.1)
        })

        (def init-complete true)

        ; Touch regions stand in for the buttons the other dashes have, so the
        ; same action tables apply. See lib/input.lisp for the region map.
        (def on-btn-0-pressed (fn () (btn-short 0)))
        (def on-btn-1-pressed (fn () (btn-short 1)))
        (def on-btn-2-pressed (fn () (btn-short 2)))
        (def on-btn-3-pressed (fn () (btn-short 3)))

        (def on-btn-0-long-pressed (fn () (btn-long 0)))
        (def on-btn-1-long-pressed (fn () (btn-long 1)))
        (def on-btn-2-long-pressed (fn () (btn-long 2)))
        (def on-btn-3-long-pressed (fn () (btn-long 3)))

        ; Repeats only make sense on the settings page, where they scroll a
        ; value; elsewhere they would fire a page change over and over.
        (def on-btn-1-repeat-press (fn () (if (= page-now page-num) (setting-update -))))
        (def on-btn-2-repeat-press (fn () (if (= page-now page-num) (setting-update +))))
})

@const-end

(image-save)
(main)
