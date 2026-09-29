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
(setq settings-page-mask 0x3F)
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

(print (list 'BOARD 'pages (length pages) 'ok))
