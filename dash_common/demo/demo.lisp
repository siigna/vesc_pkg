; Renders a scripted ride to a numbered frame sequence, for demo stills and
; video. demo.sh substitutes BOARD and the four font file names, the same way
; the test harness does.
;
; This is not a test: there are no goldens and nothing here is asserted. It
; exists to show the dash doing something, which a single still cannot.
(import "../test/stubs.lisp" 'code-stubs)
(read-eval-program code-stubs)

(def splash-version "demo")
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
(import (str-merge B "lib/input.lisp") 'c-input)
(import (str-merge C "views/view_static.lbm") 'c-static)
(import (str-merge C "views/view_pages.lbm") 'c-pages)

(read-eval-program c-config) (read-eval-program c-vehicle)
(read-eval-program c-colors) (read-eval-program c-user)
(read-eval-program c-persist) (read-eval-program c-stats)
(read-eval-program c-draw) (read-eval-program c-batt) (read-eval-program c-input)
(read-eval-program c-static) (read-eval-program c-pages)

(import (str-merge B "font/F_SPEED") 'font-speed)
(import (str-merge B "font/F_BIG") 'font-40)
(import (str-merge B "font/F_MID") 'font-24)
(import (str-merge B "font/F_SMALL") 'font-16)

(def dm-pool (dm-create config-dm-pool))
(def screen (img-buffer 'rgb888 disp-w disp-h))
(set-active-img screen)
(display-to-img)
(settings-load) (settings-build) (colors-build) (settings-apply-units)

; Every page, so the PAS one is reachable. Before the strip is drawn, since the
; strip shows one dot per page.
(setq settings-page-mask 0x1F)
(settings-apply-pages)

; Standing still, battery nearly full, nothing happening yet.
(def stats-vin 58.7) (def stats-battery-soc 0.92) (def stats-battery-ah 20.0)
(def stats-kmh 0.0) (def stats-kw 0.0) (def stats-amps-now 0.0)
(def stats-duty 0.0) (def stats-km 0.0) (def stats-odom 1243.0)
(def stats-wh 0.0) (def stats-wh-chg 0.0)
(def stats-temp-esc 28.0) (def stats-temp-motor 30.0) (def stats-temp-battery 24.0)
(def stats-kmh-max 0.0) (def stats-kw-max 0.0) (def stats-amps-now-max 0.0)
(def stats-amps-max 0.0) (def stats-temp-esc-max 28.0)
(def stats-temp-motor-max 30.0) (def stats-temp-battery-max 24.0)
(def drive-mode 1) (def light-on false) (def highbeam-on false)
(def indicate-l-on false) (def indicate-r-on false)
(def cruise-control-active false) (def cruise-control-speed 0.0)
(def stats-pas-rx true)
(def stats-pas-cadence 0.0) (def stats-pas-torque 0.0)
(def stats-pas-rider-w 0) (def stats-pas-assist-w 0)
(def stats-pas-output 0.0) (def stats-pas-flags 0)

(defun lerp (a b f) (+ a (* (- b a) (if (< f 0.0) 0.0 (if (> f 1.0) 1.0 f)))))

; The ride, as phases over the frame index. Roughly 10 fps.
;
;   0- 30  pedalling away from a standstill, assist building
;  30- 60  up to speed, steady assist about twice the rider's effort
;  60- 80  into the speed taper: assist falls while the rider keeps working
;  80- 95  brake: assist cut at once, speed dropping
;  95-110  stopped, walk assist nudging along at a walking pace
; 110-180  pages: trip, session, battery, back to live
(def demo-frames 180)

(defun demo-state (i) {
        (var f (to-float i))

        (cond
            ; Away from a standstill. Cadence comes up first, then torque, and
            ; the assist follows the rider.
            ((< f 30.0) {
                    (var p (/ f 30.0))
                    (setq stats-pas-cadence (lerp 0.0 64.0 p))
                    (setq stats-pas-torque (lerp 0.0 28.0 p))
                    (setq stats-kmh (lerp 0.0 19.0 p))
                    (setq stats-pas-flags 0)
            })
            ; Up to speed, steady.
            ((< f 60.0) {
                    (var p (/ (- f 30.0) 30.0))
                    (setq stats-pas-cadence (lerp 64.0 76.0 p))
                    (setq stats-pas-torque (lerp 28.0 24.0 p))
                    (setq stats-kmh (lerp 19.0 24.0 p))
                    (setq stats-pas-flags 0)
            })
            ; Through the taper. The rider is still pedalling but assist is
            ; being pulled back, and the speed limited flag is up.
            ((< f 80.0) {
                    (var p (/ (- f 60.0) 20.0))
                    (setq stats-pas-cadence 78.0)
                    (setq stats-pas-torque 26.0)
                    (setq stats-kmh (lerp 24.0 25.4 p))
                    (setq stats-pas-flags 0x80)
            })
            ; Brake. Assist gone immediately, speed coming down.
            ((< f 95.0) {
                    (var p (/ (- f 80.0) 15.0))
                    (setq stats-pas-cadence (lerp 78.0 0.0 (* p 2.0)))
                    (setq stats-pas-torque 0.0)
                    (setq stats-kmh (lerp 25.4 0.0 p))
                    (setq stats-pas-flags 0x08)
            })
            ; Walk assist, cranks still.
            ((< f 110.0) {
                    (setq stats-pas-cadence 0.0)
                    (setq stats-pas-torque 0.0)
                    (setq stats-kmh 5.4)
                    (setq stats-pas-flags 0x100)
            })
            ; Rolling again for the remaining pages.
            (t {
                    (setq stats-pas-cadence 72.0)
                    (setq stats-pas-torque 22.0)
                    (setq stats-kmh 23.0)
                    (setq stats-pas-flags 0)
            })
        )

        ; Rider and assist power follow from torque and cadence, as they do on
        ; the controller, so the numbers are consistent with each other.
        (var w (/ (* stats-pas-torque stats-pas-cadence 2.0 3.14159) 60.0))
        (setq stats-pas-rider-w (to-i w))
        (var gain (cond ((= stats-pas-flags 0x80) 0.6)
                        ((!= 0 (bitwise-and stats-pas-flags 0x08)) 0.0)
                        (t 2.0)))
        (setq stats-pas-assist-w (to-i (* w gain)))
        (setq stats-pas-output (if (> stats-pas-assist-w 0) 0.34 0.0))
        (if (!= 0 (bitwise-and stats-pas-flags 0x100))
            (setq stats-pas-output 0.05))

        ; The rest of the vehicle, driven off speed and assist.
        (setq stats-kw (/ (+ stats-pas-assist-w 40.0) 1000.0))
        (setq stats-amps-now (/ (* stats-kw 1000.0) stats-vin))
        (setq stats-duty (/ stats-kmh 45.0))
        (setq stats-km (+ 0.0 (* f 0.006)))
        (setq stats-wh (* f 0.55))
        (setq stats-battery-soc (- 0.92 (* f 0.00035)))
        (setq stats-vin (- 58.7 (* f 0.004)))
        (setq stats-temp-esc (+ 28.0 (* f 0.06)))
        (setq stats-temp-motor (+ 30.0 (* f 0.09)))
        (if (> stats-kmh stats-kmh-max) (setq stats-kmh-max stats-kmh))
        (if (> stats-kw stats-kw-max) (setq stats-kw-max stats-kw))
        (if (> stats-amps-now stats-amps-now-max)
            (setq stats-amps-now-max stats-amps-now))

        ; Some life in the top strip.
        (setq light-on (> f 40.0))
        (setq highbeam-on (and (> f 55.0) (< f 80.0)))
        (setq indicate-l-on (and (> f 84.0) (< f 96.0)))
        (setq drive-mode (cond ((< f 30.0) 1) ((< f 95.0) 3) (t 2)))
        (setq cruise-control-active (and (> f 45.0) (< f 60.0)))
        (setq cruise-control-speed 24.0)
})

; Which page is on screen for a given frame. The PAS page carries the ride, then
; the others get a look in.
(defun demo-page (i)
    (cond
        ((< i 110) 4)       ; PAS
        ((< i 128) 1)       ; Trip
        ((< i 146) 2)       ; Session
        ((< i 164) 3)       ; Battery
        (t 0)               ; Live
))

(view-static-frame)
(spawn view-static-thread)
(sleep 0.6)

(def last-page -1)

(looprange i 0 demo-frames {
        (demo-state i)

        (var p (demo-page i))
        (setq page-now p)
        (var pg (ix pages p))

        ; Force a full redraw on a page change, incremental otherwise, which is
        ; exactly what the dash does.
        (if (!= p last-page) (pg true) (pg false))
        (setq last-page p)

        ; Let the static strip thread pick up the changes.
        (sleep 0.08)

        (save-active-img (str-merge "out/BOARD_" (str-from-n i "%04d") ".png"))
})

(print (list 'BOARD 'frames demo-frames 'ok))
