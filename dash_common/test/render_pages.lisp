; Renders every page of the hand-written views for one board profile.
; run.sh substitutes BOARD and the four font file names.
(import "stubs.lisp" 'code-stubs)
(read-eval-program code-stubs)

(def splash-version "test")
(def C "build/common/")
(def B "build/BOARD/")

(import (str-merge B "config.lisp") 'c-config)
(import (str-merge C "lib/vehicle-state.lisp") 'c-vehicle)
(import (str-merge C "lib/colors.lisp") 'c-colors)
(import (str-merge C "lib/user-settings.lisp") 'c-user)
(import (str-merge C "lib/persistent-settings.lisp") 'c-persist)
(import (str-merge C "lib/statistics.lisp") 'c-stats)
(import (str-merge C "lib/draw-utils.lisp") 'c-draw)
(import (str-merge C "lib/battery.lisp") 'c-batt)
(import (str-merge C "lib/controller-conf.lisp") 'c-cconf)
(import (str-merge B "lib/input.lisp") 'c-input)
(import (str-merge C "views/view_static.lbm") 'c-static)
(import (str-merge C "views/view_pages.lbm") 'c-pages)

(read-eval-program c-config) (read-eval-program c-vehicle)
(read-eval-program c-colors) (read-eval-program c-user)
(read-eval-program c-persist) (read-eval-program c-stats)
(read-eval-program c-draw) (read-eval-program c-batt)
(read-eval-program c-cconf) (read-eval-program c-input)
(read-eval-program c-static) (read-eval-program c-pages)

(import (str-merge B "font/F_SPEED") 'font-speed)
(import (str-merge B "font/F_BIG") 'font-40)
(import (str-merge B "font/F_MID") 'font-24)
(import (str-merge B "font/F_SMALL") 'font-16)

; The indicator blink phase is derived from the time since the indicator came
; on, which would make the turn signal pill land on or off depending on when the
; render happened. Pinned on, for the same reason the uptime below is pinned:
; a golden has to be reproducible. blink-on is exercised by its own arithmetic,
; not by the comparison.
(def blink-on-live blink-on)
(defun blink-on () true)

; The session page's first field is uptime, which makes the render differ
; every run. Pin that one element and leave the rest of the page live, rather
; than dropping the page from the comparison. secs-since is a builtin and
; cannot be stubbed.
(def session-state-live get-page-session-state)
(defun get-page-session-state () (setix (session-state-live) 0 4321))

; Normally supplied by the board's main.lisp, which the harness does not load.
; settings-apply-visual calls it, since a theme change is also when the
; backlight level is reasserted.
(defun bl-set (level) nil)

(def dm-pool (dm-create config-dm-pool))
(def screen (img-buffer 'rgb888 disp-w disp-h))
(set-active-img screen)
(display-to-img)
(settings-load) (settings-build) (colors-build) (settings-apply-units)

; A plausible ride, so nothing renders as a screen of zeroes
(def stats-kmh 42.0) (def stats-battery-soc 0.63) (def stats-kw 2.4)
(def stats-vin 58.7) (def stats-amps-now 31.0) (def stats-km 18.4)
(def stats-odom 1243.0) (def stats-wh 214.0) (def stats-wh-chg 12.0)
(def stats-battery-ah 20.0) (def stats-duty 0.37) (def stats-temp-esc 44.0)
(def stats-temp-motor 61.0) (def stats-temp-battery 28.0)
(def stats-kmh-max 58.0) (def stats-kw-max 6.1) (def stats-amps-now-max 88.0)
(def stats-amps-max 92.0) (def stats-temp-esc-max 52.0)
(def stats-temp-motor-max 71.0) (def stats-temp-battery-max 31.0)
(def drive-mode 3) (def indicate-l-on true) (def highbeam-on true)
(def light-on true) (def cruise-control-active true)
(def cruise-control-speed 40.0)

; The PAS page is off in the default page mask, since most vehicles have no
; pedals, so the test enables every page in order to render it. This has to
; happen before the static strip is drawn: the strip shows one dot per page, so
; changing the page count afterwards would alter the strip part way through the
; run and every page captured after that point would differ.
; Stored rather than assigned: the theme change further down reloads the
; settings, and a mask that only existed in a variable would be lost there.
(settings-set 'page-mask 0xFF)
(settings-apply-pages)

; The chart plots whatever has been sampled, so the harness fills the ring
; itself rather than waiting on the stats thread. A fixed shape, so the trace
; is the same on every run: a rise, a plateau and a fall, which also exercises
; the autoscaling at both ends.
(setq settings-chart-src 4)
(setq settings-chart-secs 10)
(looprange i 0 100
    (chart-push (cond ((< i 30) (* 0.08 i))
                      ((< i 60) 2.4)
                      (t (- 2.4 (* 0.05 (- i 60)))))))

; Controller settings, as if the mirror had arrived. Parked on a gated row with
; the kill switch off, so the golden covers the case that actually has an
; appearance of its own: gated rows read dim and marked while the motor is not
; being held, which is what says the press would be refused before making it.
(def conf-count 13)
(looprange i 0 13 {
        (bufset-u8 conf-seen i 1)
        (bufset-f32 conf-vals (* i 4)
            (ix (list 2.0 0.35 22.0 25.0 250.0 1.0 1.0 4.0 18.0 0.30 0.25 1.5 70.0) i))
        (bufset-u8 conf-gated i (if (ix (conf-row i) 4) 1 0))
})
(setq conf-now 8)
(def kill-sw-active false)

; A 20S pack with one cell down, which is the case the aggregates on the
; battery page cannot show and the cells page exists for.
(def battery-a-connected true)
(def bms-cells (map (fn (i) (if (= i 7) 3.61 (+ 3.92 (* 0.004 (mod i 5))))) (range 20)))
(defun get-bms-val (name)
    (cond
        ((eq name 'bms-cell-num) 20)
        ((eq name 'bms-v-cell) (ix bms-cells (ix (rest-args) 0)))
        ((eq name 'bms-bal-state) (= (ix (rest-args) 0) 3))
        ((eq name 'bms-v-tot) 78.4)
        ((eq name 'bms-v-cell-min) 3.61)
        ((eq name 'bms-v-cell-max) 3.94)
        ((eq name 'bms-i-in-ic) 12.3)
        ((eq name 'bms-ah-cnt) 4.25)
        ((eq name 'bms-temp-cell-max) 29.0)
        ((eq name 'bms-hum) 41.0)
        (t 0.0)))

; Plausible PAS values, so the page shows something rather than zeros.
(def stats-pas-rx true)
(def stats-pas-cadence 68.0) (def stats-pas-torque 21.5)
(def stats-pas-rider-w 153) (def stats-pas-assist-w 298)
(def stats-pas-output 0.42) (def stats-pas-flags 0)

(view-static-frame)
(spawn view-static-thread)
(sleep 0.6)

(looprange p 0 (length pages) {
        (setq page-now p)
        (var pg (ix pages p))
        (pg true)
        (pg false)
        (sleep 0.3)
        (save-active-img (str-merge "out/BOARD_page" (str-from-n p "%d") ".png"))
})

; The live page again, with a hold part way through over cell 1, which is what
; the long press that charts that cell looks like. Pinned rather than timed: the
; hold fraction normally comes from the input thread.
; page-live is the first entry of page-catalog and every page is enabled
; above, so it is index 0 here. page-index lives in main_body, which the
; harness does not load.
(setq page-now 0)
(setq touch-x (+ (live-cell-x 1) 10))
(setq touch-y (+ (live-cell-y 1) 30))
(setq btn-hold-region (touch-region touch-x touch-y))
(setq btn-hold-progress 0.7)
(page-live true)
(page-live false)
(sleep 0.3)
(save-active-img "out/BOARD_live_hold.png")

; The cell that the hold above is over, which is the one the press would chart.
(print (list 'BOARD 'hold-cell (live-cell-hit touch-x touch-y)))

; The live page once more under the Light theme, which is the only row with a
; pale background and so the one that would expose anything still assuming a
; black one. Every palette is built against color-bg, so this is the check that
; nothing draws a literal colour behind the code's back.
; Through settings-set, which is the path VESC Tool uses, so the test covers
; the reload and the repaint rather than a hand-built palette.
(setq btn-hold-region nil)
(settings-set 'theme 4)
(settings-apply-visual)
(view-static-frame)
(sleep 0.3)
(page-live true)
(page-live false)
(sleep 0.3)
(save-active-img "out/BOARD_theme_light.png")

; Back to Dark, then one live page with a different colour rule in each cell,
; so every branch of slot-colors is drawn: ramp, heat, low-warn and sign. The
; ranges are picked so the seeded values land in different parts of each,
; otherwise three of the four would come out the same green.
(settings-set 'theme 0)
(looprange i 0 4 {
        (settings-set (ix '(slot-mode-0 slot-mode-1 slot-mode-2 slot-mode-3) i) (+ i 1))
        (settings-set (ix '(slot-min-0 slot-min-1 slot-min-2 slot-min-3) i) 0.0)
        (settings-set (ix '(slot-max-0 slot-max-1 slot-max-2 slot-max-3) i)
            (ix '(40.0 80.0 100.0 50.0) i))
})
; Cell 3 is the sign rule, so point it at power, which the seed has negative.
(settings-set 'slot-3 4)
(def stats-kw -1.8)
(settings-apply-visual)
(view-static-frame)
(sleep 0.3)
(page-live true)
(page-live false)
(sleep 0.3)
(save-active-img "out/BOARD_slot_rules.png")

; The heat table has to be sixteen distinct ramps, not one colour repeated.
(print (list 'BOARD 'heat-lo (ix (colors-heat-ramp 0.0) 3)
                    'heat-mid (ix (colors-heat-ramp 0.5) 3)
                    'heat-hi (ix (colors-heat-ramp 1.0) 3)))

; What smoothing costs. It glides a value over several frames instead of
; jumping, and the live page redraws a cell whenever its text changes, so it
; buys motion with redraws. This measures the whole page frame -- state read,
; dirty check and the disp-render of whatever changed -- with a value that
; moves every frame, which is the worst case rather than a typical one.
(settings-set 'slot-0 4)
(looprange i 0 4
    (settings-set (ix '(slot-mode-0 slot-mode-1 slot-mode-2 slot-mode-3) i) 0))
(settings-apply-visual)

(defun bench-live (n) {
        (page-live true)
        (var t0 (systime))
        (looprange i 0 n {
                (def stats-kw (+ 1.0 (* 0.37 (mod i 17))))
                (page-live false)
        })
        (/ (* 1000.0 (secs-since t0)) n)
})

(settings-set 'smooth 0.0)
(def ms-off (bench-live 120))
(settings-set 'smooth 0.3)
(def ms-on (bench-live 120))
(print (list 'BOARD 'live-ms-per-frame (round-x ms-off 0.01) 'smoothing-off
                    (round-x ms-on 0.01) 'smoothing-on))

(print (list 'BOARD 'pages (length pages) 'ok))
