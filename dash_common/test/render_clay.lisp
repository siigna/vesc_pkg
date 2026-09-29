; Renders the Clay screen description for one board profile, and checks two
; things that only show up as pixels:
;
;   - no text hangs off the bottom of the panel. Clay overflows rather than
;     shrinking content, so a layout that asks for more than the panel has
;     silently pushes the nav strip off the edge.
;   - drawing the screen a band at a time is byte-identical to drawing it in
;     one buffer. Band boundaries cut glyphs, and getting the baseline
;     rounding wrong there shifts them a row.
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
(import (str-merge C "views/view_static.lbm") 'c-static)
(import (str-merge C "views/clay_screen.lbm") 'c-cscreen)
(import (str-merge C "views/clay_draw.lbm") 'c-cdraw)

(read-eval-program c-config) (read-eval-program c-vehicle)
(read-eval-program c-colors) (read-eval-program c-user)
(read-eval-program c-persist) (read-eval-program c-stats)
(read-eval-program c-draw) (read-eval-program c-batt) (read-eval-program c-static)
(read-eval-program c-cscreen) (read-eval-program c-cdraw)

(import (str-merge B "font/F_SPEED") 'font-speed)
(import (str-merge B "font/F_BIG") 'font-40)
(import (str-merge B "font/F_MID") 'font-24)
(import (str-merge B "font/F_SMALL") 'font-16)
(setq clay-fonts (list font-16 font-24 font-40 font-speed))

(def screen (img-buffer 'rgb888 disp-w disp-h))
(set-active-img screen)
(display-to-img)
(settings-load) (settings-build) (colors-build) (settings-apply-units)
(clay-build-palette)

(def labels (list "Range" "Trip" "ODO" "Efficiency"
                  "Energy" "Regen" "Amp Hours" "Voltage"))
(def vals (list "63.6" "18.4" "1243" "12" "214" "12" "20.0" "58.7"))
(def desc (clay-screen (list true true true nil) "42" "km/h" "SPORT"
                       0.63 "63 %" labels vals "SET" "Page 1/4"))

(def fails 0)

; --- nothing off the bottom ---
(def cmds (clay-layout desc disp-w disp-h clay-fonts))
(def worst 0)
(loopforeach c cmds
    (if (and (eq (ix c 0) 'text) (> (+ (ix c 2) (ix c 4)) worst))
        (setq worst (+ (ix c 2) (ix c 4)))))
(if (> worst disp-h) {
        (print (list 'BOARD 'FAIL 'text-past-bottom worst 'panel disp-h))
        (setq fails (+ fails 1))
})

; --- banded == one buffer ---
(def dm-pool (dm-create (+ (/ (* disp-w disp-h) 2) 32768)))
(disp-clear 0)
(def fb (img-buffer dm-pool 'indexed16 disp-w disp-h))
(img-clear fb)
(clay-draw-into fb cmds)
(disp-render fb 0 0 clay-pal)
(save-active-img "out/BOARD_clay_full.png")

; A pool deliberately far too small for one full-screen buffer
(def dm-pool (dm-create (+ (* 3 (/ (* disp-w clay-band-h) 2)) 8192)))
(disp-clear 0)
(clay-draw-screen desc)
(save-active-img "out/BOARD_clay.png")

(print (list 'BOARD 'commands (length cmds) 'lowest-text worst
             'panel disp-h 'fails fails))
