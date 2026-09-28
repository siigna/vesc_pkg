@const-start

(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)

(import "version.lisp" 'code-version)
(read-eval-program code-version)

(import "config.lisp" 'code-config)
(read-eval-program code-config)

; Lib
(import "lib/vehicle-state.lisp" 'code-vehicle-state)
(read-eval-program code-vehicle-state)

(import "lib/colors.lisp" 'code-colors)
(read-eval-program code-colors)

(import "lib/user-settings.lisp" 'code-user-settings)
(read-eval-program code-user-settings)

(import "lib/persistent-settings.lisp" 'code-persistent-settings)
(read-eval-program code-persistent-settings)

(import "lib/statistics.lisp" 'code-statistics)
(read-eval-program code-statistics)

(import "lib/draw-utils.lisp" 'code-draw-utils)
(read-eval-program code-draw-utils)

(import "lib/input.lisp" 'code-input)
(read-eval-program code-input)

(import "lib/communication.lisp" 'code-communication)
(read-eval-program code-communication)

(import "lib/standalone.lisp" 'code-standalone)
(read-eval-program code-standalone)

; Fonts, pre-rendered by font/generate_fonts. Preparing them on the device
; instead would mean shipping Roboto-Bold.ttf, and at ~145 kB that alone is
; more than the package's whole lisp budget. The two large ones carry only the
; glyphs they can actually draw, plus a "D" that ttf-txt-center measures to
; find the baseline.
(import "font/roboto-bold-108-4c.bin" 'font-speed)
(import "font/roboto-bold-40-4c.bin" 'font-40)
(import "font/roboto-bold-24-4c.bin" 'font-24)
(import "font/roboto-bold-16-4c.bin" 'font-16)

; Views
(import "views/view_static.lbm" 'code-view-static)
(read-eval-program code-view-static)

(import "views/view_pages.lbm" 'code-view-pages)
(read-eval-program code-view-pages)

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
        ((= a 8) (comm-send-event 0))
        ((= a 9) (comm-send-event 2)) ; start or stop logging on the controller
        (t nil)
))

; On the settings page short presses always navigate it
(defun btn-short (idx)
    (if (= page-now page-num)
        (cond
            ((= idx 0) (if (> setting-num 0)
                          (setq setting-now (mod (+ setting-now 1) setting-num))))
            ((= idx 1) (setting-update -))
            ((= idx 2) (setting-update +))
            (t (btn-do-action (ix btn-actions-short idx)))
        )
        (btn-do-action (ix btn-actions-short idx))
))

; There is no backlight control on this board, so this exists only because the
; shared settings layer calls it.
(defun bl-set (level) nil)

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

        ; Image buffers are the whole panel width here, so the pool is much
        ; larger than the smaller dashes need. A full-width indexed4 strip is
        ; 480 * h / 4 bytes, and the speed readout alone is 480x170.
        (def dm-pool (dm-create 131072))

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

        ; disp-init comes from the board's hardware config and carries the
        ; 20-pin RGB bus map, so this package holds no display pins.
        (disp-init)
        (ext-disp-orientation config-disp-rotation)
        (disp-clear color-bg)

        ; Touch is optional: paging is the only thing it drives, so a dead
        ; controller costs the page buttons and nothing else.
        (match (trap (apply touch-load-gt911 (touch-pins)))
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

        (def on-btn-0-long-pressed (fn () (btn-do-action (ix btn-actions-long 0))))
        (def on-btn-1-long-pressed (fn () (btn-do-action (ix btn-actions-long 1))))
        (def on-btn-2-long-pressed (fn () (btn-do-action (ix btn-actions-long 2))))
        (def on-btn-3-long-pressed (fn () (btn-do-action (ix btn-actions-long 3))))

        ; Repeats only make sense on the settings page, where they scroll a
        ; value; elsewhere they would fire a page change over and over.
        (def on-btn-1-repeat-press (fn () (if (= page-now page-num) (setting-update -))))
        (def on-btn-2-repeat-press (fn () (if (= page-now page-num) (setting-update +))))
})

@const-end

(image-save)
(main)
