; Copyright chargedup3d
; Copyright jeremy
; Copyright Benjamin Vedder
; Copyright 2026 Stephen Bouche
;
; Parts of this file were moved here from dash35b/main.lisp;
; git blame -C records 36 lines as Benjamin Vedder's.
; SPDX-License-Identifier: GPL-3.0-or-later
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
;                     config-region-overlay-s config-region-overlay-delay-s
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

                ; The theme moves every palette, and those are baked into the
                ; indexed buffers already on screen, so this one setting needs
                ; the full repaint the worker does. The rest are values rather
                ; than colours and must not trigger it: the spinner repeats
                ; while a button is held, and repainting the panel per step
                ; would make it unusable.
                (if (eq setting 'theme) (setq settings-redraw true))
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

; True while a button whose long action is the horn is held past the long-press
; point. Same shape as walk-requested and for the same reason: the horn is
; momentary, so it has to be derived from the held state rather than from
; btn-do-action, which fires once. A press on the quick shade cannot hold
; anything and blips instead.
(defun horn-held () {
        (var idx btn-hold-region)
        (and idx
             (= (ix btn-actions-long idx) 21)
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
        ; The quick shade. One past the settings page, so paging cannot reach
        ; it and it does not cost a page slot; pressing it again closes it, as
        ; does a swipe up.
        ((= a 16) (setq page-now (if (= page-now (+ page-num 1)) 0 (+ page-num 1))))

        ; Signal requests, carried in byte 3 of SID 201 for a bike-controls
        ; node to act on. 17 to 20 latch; 21 is the horn, which is momentary,
        ; so a press blips it and a held button asserts it for as long as it is
        ; down -- see horn-held, which the transmit thread reads directly.
        ((= a 17) (sig-toggle sig-hazard))
        ((= a 18) (sig-toggle sig-left))
        ((= a 19) (sig-toggle sig-right))
        ((= a 20) (sig-toggle sig-beam))
        ((= a 21) (sig-horn-blip))

        ; Lock now. Refused while moving: the display asserts neutral while
        ; locked, and taking the drive away mid-ride is not something a
        ; mis-tap should be able to do.
        ((= a 22) (if (> (abs stats-kmh) 1.0)
                      (notify "Stop first")
                      (pin-engage)))
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
(defunret btn-long (idx) {
        ; Locked: a long press does nothing at all. The keypad has no long
        ; actions and everything else is out of reach.
        (if (pin-showing) (return nil))

        (var pg (ix pages page-now))
        ; Walk assist and the horn are not claimable. Both are held rather than
        ; triggered and both read the held state directly, so claiming the
        ; region would leave the request running while the chart page opened.
        (var a-long (ix btn-actions-long idx))
        (var walk (or (= a-long 13) (= a-long 21)))
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
        ; Locked: the keypad is the only thing on screen that does anything.
        ; Nothing falls through to a stored action, or a region bound to paging
        ; would walk straight off the lock.
        ((pin-showing)
            (let ((k (pin-key-hit touch-x touch-y)))
                (if k (pin-key (ix pin-keys k)) nil)))
        ; The quick shade is six buttons in the area the four touch regions
        ; cover with two, so a press there is resolved by position rather than
        ; by region. Below the nav strip the regions keep their own actions, so
        ; there is still a way off the shade without the gesture.
        ((and (shade-showing) (< touch-y nav-y))
            (let ((cell (shade-cell-hit touch-x touch-y)))
                (if cell
                    (let ((a (ix settings-shade cell)))
                        (if (!= a 0) (btn-do-action a)))
                    nil)))
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

; --- the touch region overlay ----------------------------------------------
;
; The four virtual buttons, drawn over the running dash for a few seconds so
; the regions can be seen rather than inferred from the source. Ported back
; from dash_common_lua/lib/dash.lua, where it was written first.
;
; Every label is read back out of touch-region at the point it is drawn, so
; this reports the map rather than restating it. If the two ever disagree -- a
; panel reporting mirrored coordinates, a layout change that moved nav-y --
; the overlay shows the region that is really there, which is the whole reason
; to draw it.
;
; Unlike the Lua dash this can simply block: the views run in their own
; threads and stand down on covered-by-startup, where the Lua engine has one
; timer and needed a phase machine to avoid holding it.
; config-region-overlay-s and config-region-overlay-delay-s come from the
; board, like every other config-* here. Deliberately not defaulted in this
; file: main_body is loaded last, so a def here would overwrite what the board
; config set rather than fall back to it.

@const-start

; One region's box and label. The text comes from whatever touch-region says
; about the centre of the area being drawn.
(defun region-box (x y w h) {
        (var cx (+ x (/ w 2)))
        (var cy (+ y (/ h 2)))
        (var r (touch-region cx cy))

        (var a (if r (ix btn-actions-short r) 0))
        (var al (if r (ix btn-actions-long r) 0))

        (var img (img-buffer dm-pool 'indexed4 w h))
        (img-clear img)
        (img-rectangle img 0 0 (- w 1) (- h 1) 1)

        (var cap (second (ttf-glyph-dims font-16 "D")))
        (var line-h (+ cap 6))

        ; As many rows as fit, and one compact line when only one does. The
        ; nav strip is thirty-odd pixels, which is one row: laying out four and
        ; letting the rest fall outside drew two of them over each other and
        ; the border, because the baseline arithmetic happily goes negative.
        (var fit (/ h line-h))
        (if (< fit 1) (setq fit 1))

        ; shade-label is empty for an action with no button on the quick
        ; shade, including action 0. Naming the number instead says "nothing
        ; bound" where a blank line reads as a label that failed to draw.
        (var name (fn (id) {
                (var l (shade-label id))
                (if (eq l "") (str-merge "action " (str-from-n id "%d")) l)
        }))

        (var rows (if (= fit 1)
            (list (str-merge "REGION " (if r (str-from-n r "%d") "-")
                             " - " (name a)))
            (list
                (str-merge "REGION " (if r (str-from-n r "%d") "-"))
                (str-merge "tap: " (name a))
                (str-merge "hold: " (name al))
                (str-merge "x " (str-from-n x "%d") ".." (str-from-n (+ x w -1) "%d")
                           "  y " (str-from-n y "%d") ".." (str-from-n (+ y h -1) "%d")))))

        (if (> (length rows) fit)
            (setq rows (take rows fit)))

        (var top (- (/ h 2) (/ (* (length rows) line-h) 2)))
        (if (< top 0) (setq top 0))

        (looprange i 0 (length rows) {
                (var txt (ix rows i))
                (var tw (first (ttf-text-dims font-16 txt)))
                (var tx (/ (- w tw) 2))
                (if (< tx 2) (setq tx 2))
                (ttf-text img tx (+ top (* i line-h) cap) '(0 1 2 3) font-16 txt)
        })

        (disp-render img x y colors-accent-aa)
})

(defun region-overlay () {
        ; The same arithmetic touch-region uses, in the same order. The thirds
        ; are the part that matters: 2 * (disp-w / 3) is 532 on an 800 wide
        ; panel where (2 * disp-w) / 3 is 533, and the boundary is the first.
        (var half (/ disp-w 2))
        (var third (/ disp-w 3))
        (var strip-h (- disp-h nav-y))

        ; Above the nav strip: two halves.
        (region-box 0 0 half nav-y)
        (region-box half 0 (- disp-w half) nav-y)

        ; The strip: three thirds, the last taking the remainder so the boxes
        ; cover the panel exactly rather than leaving a column at the edge.
        (region-box 0 nav-y third strip-h)
        (region-box third nav-y third strip-h)
        (region-box (* 2 third) nav-y (- disp-w (* 2 third)) strip-h)
})

; Shown once, a moment after the dash comes up, then the views take the panel
; back. Its own thread so main can finish: the views are already running by
; the time this draws, which is the point -- the regions go over the real
; screen rather than over nothing.
(defun region-overlay-thread () {
        (sleep config-region-overlay-delay-s)

        (setq covered-by-startup true)
        (trap (region-overlay))
        (sleep config-region-overlay-s)
        (setq covered-by-startup false)

        ; Closing repaints the lot: the views' dirty tracking was paused and
        ; has no idea what the overlay covered.
        (setq view-force-static true)
        (setq view-force-pages true)
})

@const-end

(defun show-splash () {
        (print "Splash")

        (var imgbuf (img-buffer dm-pool 'indexed4 disp-w 60))
        (img-clear imgbuf)
        (ttf-txt-center "ESCargot" font-40 imgbuf)
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

        ; Turn the backlight on. The board profile parks it off at boot so
        ; nothing shows before the first draw, and the only other caller of
        ; bl-set is settings-apply-visual, which the worker runs on a theme
        ; change and never at startup. Without this a board with real
        ; backlight control renders everything into a dark panel, and the
        ; symptom is intermittent rather than constant: a pwm-start left by
        ; whatever ran before survives until the next reset.
        (trap (bl-set (if backlight-dim settings-bl-dim settings-bl-bright)))

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

        ; Locked at startup when a code is set, before anything else can put a
        ; page on screen. The keypad is one past the quick shade, which is one
        ; past the settings page.
        (if settings-pin-en {
                (pin-engage)
                (setq page-now (+ page-num 2))
        })

        (loopwhile-thd ("Worker" 150) t {
                (if settings-redraw (trap (settings-apply-visual)))
                (if battery-a-charging (mode-set 1)) ; Put in neutral when charging
                (if kickstand-down (mode-set 1)) ; Put in neutral when kickstand is down

                ; Counts the lockout down here rather than in the view, so the
                ; keypad redraws when the number changes and not every frame.
                (pin-tick)

                ; Nothing may navigate off the keypad. btn-short and btn-long
                ; already refuse to, and the swipe does, but a notification
                ; path or a second display could still move the page, and the
                ; cost of being wrong here is a bike that drives while it is
                ; supposed to be locked.
                (if (and pin-locked (not (pin-showing)))
                    (setq page-now (+ page-num 2)))

                ; Unlocking leaves the keypad up until something moves off it.
                (if (and (not pin-locked) (pin-showing)) (setq page-now 0))

                (sleep 0.1)
        })

        ; The region overlay, if the board asks for one. Its own thread so the
        ; views are already drawing by the time it goes over them.
        (if (> config-region-overlay-s 0.0)
            (spawn 150 region-overlay-thread))

        (def init-complete true)

        ; Touch regions stand in for the buttons the other dashes have, so the
        ; same action tables apply. See lib/input.lisp for the region map.
        ; Swipe down opens the quick shade from any page, swipe up closes it.
        ; A gesture rather than a region, because on a touch board there is no
        ; region to spare.
        (def on-swipe-down (fn ()
            (if (and (not (overlay-showing))) (btn-do-action 16))))
        (def on-swipe-up (fn () (if (shade-showing) (setq page-now 0))))

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
