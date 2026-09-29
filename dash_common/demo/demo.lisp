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

; A 20 series pack, overriding the board profile's 12. The voltages below are
; derived from a per-cell figure for that reason: the previous demo ran 58.7 V
; against a 12S profile, which is 4.89 V per cell and above any cell's maximum,
; so the state of charge estimated from voltage was pegged.
(def config-battery-cells 20)
(def config-battery-ah 20.0)

; Cell voltage for a state of charge, over the usable range of the discharge
; curve the profile carries. Keeps pack voltage, per-cell voltage and the
; percentage telling the same story.
(defun demo-cell-v (soc) (+ 3.30 (* 0.88 (clamp01 soc))))

; The harness stubs the BMS to zero, which the battery page correctly reports as
; no BMS. Answer with a real pack instead, sagging under load like one.
; The page gates on having heard from a BMS at all, which is set when a BMS
; frame arrives, so say it has.
(def battery-a-connected true)
(def bms-soc 0.92)
(def bms-load 0.0)
; One cell 0.3 V down and one being balanced, which is the case the aggregates
; on the battery page cannot show and the cells page exists for. Derived from
; the same curve as everything else, so the bars agree with the pack voltage.
(def bms-weak-cell 7)
(def bms-balancing-cell 3)

(defun demo-cell-n (i) {
        (var vc (- (demo-cell-v bms-soc) (* 0.004 bms-load)))
        (+ (if (= i bms-weak-cell) (- vc 0.30) vc)
           (* 0.004 (mod i 5)))
})

(defun get-bms-val (k)
    (if (rest-args)
        (let ((i (ix (rest-args) 0)))
            (cond
                ((eq k 'bms-v-cell) (demo-cell-n i))
                ((eq k 'bms-bal-state) (= i bms-balancing-cell))
                (t 0.0)))
        (let ((vc (- (demo-cell-v bms-soc) (* 0.004 bms-load))))
            (cond
                ((eq k 'bms-v-tot) (* vc config-battery-cells))
                ; From the per-cell values rather than a guess either side of
                ; the average, so the battery page's minimum is the weak cell
                ; the cells page draws.
                ((eq k 'bms-v-cell-min) (demo-cell-n bms-weak-cell))
                ((eq k 'bms-v-cell-max) (+ vc 0.016))
                ((eq k 'bms-cell-num) config-battery-cells)
                ((eq k 'bms-i-in-ic) bms-load)
                ((eq k 'bms-ah-cnt) (* config-battery-ah (- 1.0 bms-soc)))
                ((eq k 'bms-wh-cnt) (* config-battery-ah 3.7
                                       config-battery-cells (- 1.0 bms-soc)))
                ((eq k 'bms-temp-cell-max) 27.0)
                ((eq k 'bms-hum) 41.0)
                ((eq k 'bms-soc) bms-soc)
                (t 0.0)))))

(def dm-pool (dm-create config-dm-pool))
(def screen (img-buffer 'rgb888 disp-w disp-h))
(set-active-img screen)
(display-to-img)
(settings-load) (settings-build) (colors-build) (settings-apply-units)

; Every page, so the PAS and cells ones are reachable. Before the strip is
; drawn, since the strip shows one dot per page.
(setq settings-page-mask 0xFF)
(settings-apply-pages)

; The strip shows the signals a bike-controls node reports and falls back to
; what the display asked for when there is none. This ride has one, so the
; indicator and high beam beats below mean the reported state. The request path
; gets its own beat, which flips this back.
(def sig-reported-live sig-reported)
(defun sig-reported () true)

; The session page's first field is uptime, which is different on every run and
; made the two session stills churn in git each time the demo was rendered.
; Pinned to a plausible ride length, the same way the test harness pins it.
(def session-state-live get-page-session-state)
(defun get-page-session-state () (setix (session-state-live) 0 1187))

; The indicator blink is normally timed off the wall clock, which made the
; frames -- and so the stills cut from them -- depend on how long the render
; took. Derived from the frame index instead: the video still blinks, at five
; frames on and five off, and every frame is the same on every run. The real
; blink-on is exercised by its own arithmetic in the test suite.
(def demo-frame 0)
(def blink-on-live blink-on)
(defun blink-on () (< (mod demo-frame 10) 5))

; Chart the speed, which is what makes the ride legible: the climb, the brake,
; the walking pace and the coast all show up in one trace. Set explicitly
; rather than left to the stored default, so the render is deliberate.
(setq settings-chart-src 0)
(setq settings-chart-secs 10)

; Standing still, battery nearly full, nothing happening yet.
(def stats-vin (* 20 (demo-cell-v 0.92)))
(def stats-battery-soc 0.92) (def stats-battery-ah 20.0)
(def stats-kmh 0.0) (def stats-kw 0.0) (def stats-amps-now 0.0)
(def stats-duty 0.0) (def stats-km 0.0) (def stats-odom 1243.0)
(def stats-wh 0.0) (def stats-wh-chg 0.0)
(def stats-temp-esc 28.0) (def stats-temp-motor 30.0) (def stats-temp-battery 24.0)
(def stats-kmh-max 0.0) (def stats-kw-max 0.0) (def stats-amps-now-max 0.0)
(def stats-amps-max 0.0) (def stats-temp-esc-max 28.0)
(def stats-temp-motor-max 30.0) (def stats-temp-battery-max 24.0)
(def drive-mode 1) (def light-on false) (def highbeam-on false) ; 1 = neutral
(def indicate-l-on false) (def indicate-r-on false)
(def cruise-control-active false) (def cruise-control-speed 0.0)
(def stats-pas-rx true)
(def stats-pas-cadence 0.0) (def stats-pas-torque 0.0)
(def stats-pas-rider-w 0) (def stats-pas-assist-w 0)
(def stats-pas-output 0.0) (def stats-pas-flags 0)
(def kill-sw-active false) (def aux-on false) (def stats-fault-code 0)

; Controller settings, as if the mirror had arrived.
(def conf-count 13)
(looprange i 0 13 {
        (bufset-u8 conf-seen i 1)
        (bufset-f32 conf-vals (* i 4)
            (ix (list 2.0 0.35 22.0 25.0 250.0 1.0 1.0 4.0 18.0 0.30 0.25 1.5 70.0) i))
        (bufset-u8 conf-gated i (if (ix (conf-row i) 4) 1 0))
})

(defun lerp (a b f) (+ a (* (- b a) (if (< f 0.0) 0.0 (if (> f 1.0) 1.0 f)))))

; The ride, as phases over the frame index. Roughly 10 fps.
;
;   0- 30  pedalling away from a standstill, assist building
;  30- 60  up to speed, steady assist about twice the rider's effort
;  60- 80  into the speed taper: assist falls while the rider keeps working
;  80- 95  brake: assist cut at once, speed dropping
;  95-110  stopped, walk assist nudging along at a walking pace
; 110-125  rolling again, coasting with regen into the pack
; 125-135  the cooling fan comes on
; 135-142  the kill switch, which outranks everything else
; 142-160  the rolling chart, which is fed by the ride above
; 160-178  controller settings, with unsaved changes pending
; 178-246  pages: trip, session, battery, back to live
; 246-266  the cells page: one bar per cell, with a weak one
; 266-286  the quick shade, with the mode and cruise changing under it
; 286-296  back on a page, showing hazard and high beam taken from the request
;          rather than from a reported state -- the shade covers the strip, so
;          this cannot be shown while the shade is up
; 296-310  holding a live cell, then 310-316 the chart it opens
; 316-340  the Night and Light themes
; 340-356  a colour rule per live cell
(def demo-frames 356)

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
            ; Coasting downhill, not pedalling, pack taking current back.
            ((< f 125.0) {
                    (setq stats-pas-cadence 0.0)
                    (setq stats-pas-torque 0.0)
                    (setq stats-kmh 27.0)
                    (setq stats-pas-flags 0)
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

        ; Conditions the strip reports, in the order the slot ranks them. Each
        ; gets a window of its own so a still of it exists.
        (setq aux-on (and (> f 125.0) (< f 142.0)))
        ; Unsaved changes, so the strip shows it and the settings page is worth
        ; looking at. The kill switch window above is also what unlocks the
        ; gated rows, which is the point of showing them together.
        (setq conf-dirty (> f 160.0))
        (setq conf-now (if (< f 170.0) 0 8))
        (setq kill-sw-active (and (> f 135.0) (< f 142.0)))

        ; The rest of the vehicle, driven off speed and assist. Coasting with
        ; no pedalling puts current back into the pack, which is what the regen
        ; indicator reads.
        (setq stats-kw (if (and (> f 110.0) (< f 125.0))
                           -0.9
                           (/ (+ stats-pas-assist-w 40.0) 1000.0)))
        (setq stats-amps-now (/ (* stats-kw 1000.0) stats-vin))
        (setq stats-duty (/ stats-kmh 45.0))
        (setq stats-km (+ 0.0 (* f 0.006)))
        (setq stats-wh (* f 0.55))
        (setq stats-battery-soc (- 0.92 (* f 0.00035)))
        (setq bms-soc stats-battery-soc)
        (setq bms-load stats-amps-now)

        ; Pack voltage from the cell curve and the load, rather than a number
        ; drifting on its own, so it agrees with the cell voltages the battery
        ; page shows.
        (setq stats-vin (* config-battery-cells
                           (- (demo-cell-v stats-battery-soc)
                              (* 0.004 stats-amps-now))))
        (setq stats-temp-esc (+ 28.0 (* f 0.06)))
        (setq stats-temp-motor (+ 30.0 (* f 0.09)))
        (if (> stats-kmh stats-kmh-max) (setq stats-kmh-max stats-kmh))
        (if (> stats-kw stats-kw-max) (setq stats-kw-max stats-kw))
        (if (> stats-amps-now stats-amps-now-max)
            (setq stats-amps-now-max stats-amps-now))
        ; The controller reports its own peak separately from the one the dash
        ; tracks, and the live page's Peak Amps reads that one, so it sat at
        ; zero for the whole ride.
        (if (> stats-amps-now stats-amps-max)
            (setq stats-amps-max stats-amps-now))

        ; Some life in the top strip.
        (setq light-on (> f 40.0))
        (setq highbeam-on (and (> f 55.0) (< f 80.0)))
        (setq indicate-l-on (and (> f 84.0) (< f 96.0)))
        ; A drive mode, not neutral: index 1 is neutral, whose current scale is
        ; zero, so the bike could not have been accelerating in it. The demo
        ; showed neutral for the first three seconds of a ride.
        (setq drive-mode (cond ((< f 30.0) 2) ((< f 95.0) 4) (t 3)))
        (setq cruise-control-active (and (> f 45.0) (< f 60.0)))
        (setq cruise-control-speed 24.0)

        ; --- The parts that are about the display rather than the ride -------

        ; Holding a live cell fills its highlight and then opens the chart on
        ; that cell. Both the held region and the touch point are driven here,
        ; the way the input thread would, because there is no finger.
        (if (and (>= f 296.0) (< f 310.0)) {
                (setq touch-x (+ (live-cell-x 1) 10))
                (setq touch-y (+ (live-cell-y 1) 30))
                (setq btn-hold-region (touch-region touch-x touch-y))
                (setq btn-hold-progress (lerp 0.0 1.0 (/ (- f 296.0) 13.0)))
        }
        (if (< f 310.0) (setq btn-hold-region nil)))

        ; At the end of the hold the press fires, which is what the chart page
        ; after it is showing.
        (if (and (>= f 310.0) (< f 311.0)) {
                (setq btn-hold-region nil)
                (setq settings-chart-src (ix settings-slots 1))
        })

        ; Something happening under the shade, so its buttons are visibly
        ; reporting state rather than sitting still.
        (if (and (>= f 274.0) (< f 286.0)) (setq drive-mode 4))
        (if (and (>= f 278.0) (< f 286.0)) (setq cruise-control-active true))

        ; The signal request path: no bike-controls node reporting, so the
        ; strip shows what was asked for. Hazard lights both arrows. Shown on a
        ; page rather than under the shade, which covers the strip.
        ; Cleared outside the window rather than only before it: an else that
        ; also tested the frame left the request latched for the rest of the
        ; run, and the hazard arrows stayed up over every beat after it.
        (if (and (>= f 286.0) (< f 296.0)) {
                (setq sig-req (bitwise-or sig-hazard sig-beam))
                (defun sig-reported () false)
        } {
                (setq sig-req 0)
                (defun sig-reported () true)
        })

        ; Themes. Row 0 is the palette the dash shipped with, so the ride above
        ; ran on it; these are the two that change more than the accent.
        (if (and (>= f 316.0) (< f 328.0)) (demo-theme 3))
        (if (and (>= f 328.0) (< f 340.0)) (demo-theme 4))
        (if (>= f 340.0) (demo-theme 0))

        ; Colour rules, one per cell, with ranges the values actually land in.
        (if (and (>= f 340.0) (< f 341.0)) {
                (looprange c 0 4 {
                        (setix settings-slot-modes c (+ c 1))
                        (setix settings-slot-mins c 0.0)
                        (setix settings-slot-maxs c (ix '(40.0 80.0 100.0 50.0) c))
                })
                (setix settings-slots 3 4)
        })
})

; A theme change is a whole-screen repaint, since the palettes are baked into
; the buffers already on screen. Applied only on a change, or every frame of
; the beat would repaint and the incremental redraw being demonstrated would
; not be.
(def demo-theme-now 0)
(defun demo-theme (n)
    (if (!= n demo-theme-now) {
            (setq demo-theme-now n)
            (setq settings-theme n)
            (theme-apply-status)
            (setq color-bg (theme-bg))
            (setq color-accent (theme-accent))
            (setq color-text (theme-text))
            (setq settings-slot-cols (map (fn (c) (theme-text)) '(0 1 2 3)))
            (colors-build)
            (disp-clear color-bg)
            (setq view-force-static true)
            (view-static-frame)
            (setq last-page -1)
    }))

; Which page is on screen for a given frame. The PAS page carries the ride, then
; the others get a look in.
(defun demo-page (i)
    (cond
        ((< i 142) 4)       ; PAS, which is where the strip conditions play out
        ((< i 160) 5)       ; Chart, showing the ride that just happened
        ((< i 178) 6)       ; Controller settings
        ((< i 196) 1)       ; Trip
        ((< i 214) 2)       ; Session
        ((< i 232) 3)       ; Battery
        ((< i 246) 0)       ; Live
        ((< i 266) 7)       ; Cells
        ; The quick shade is one past the settings page, which is page-num.
        ((< i 286) (+ page-num 1))
        ((< i 296) 1)       ; Trip, so the strip is visible for the signals
        ((< i 310) 0)       ; Live, with a cell being held
        ((< i 316) 5)       ; Chart, now on the cell that was held
        (t 0)               ; Live: themes, then the colour rules
))

; The strip is stepped synchronously below rather than run as a thread: with
; the thread alongside this loop, whether a changed field had been painted
; before the frame was saved depended on how long the render took, and the
; frames -- and the stills cut from them -- were not reproducible.
(view-static-frame)

(def last-page -1)

(looprange i 0 demo-frames {
        (setq demo-frame i)
        (demo-state i)

        ; The chart is normally fed by the stats thread, which the harness does
        ; not run, so push a sample per frame here instead. The frame rate is
        ; the controller's send rate, which is what the sampler uses too.
        (chart-push (slot-value settings-chart-src))

        (var p (demo-page i))
        (setq page-now p)
        (var pg (ix pages p))

        ; Force a full redraw on a page change, incremental otherwise, which
        ; is exactly what the dash does -- including honouring view-force-pages,
        ; which view-static-frame raises after it has wiped the screen. Without
        ; that, leaving the quick shade or changing theme left the page with its
        ; labels erased and only the changed values redrawn.
        (var force view-force-pages)
        (setq view-force-pages false)
        (if (or force (!= p last-page)) (pg true) (pg false))
        (setq last-page p)

        ; One strip pass per frame, in step with the page, which is what makes
        ; the output the same on every run. Overlays cover the strip, so the
        ; pass is skipped and the repaint is left to the frame after.
        (if (overlay-showing)
            (setq view-force-static true)
            (view-static-step))

        (save-active-img (str-merge "out/BOARD_" (str-from-n i "%04d") ".png"))
})

(print (list 'BOARD 'frames demo-frames 'ok))
