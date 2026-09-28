@const-start

(def config-metric-speeds true)
(def config-metric-temps true)

(def config-gnss-use-speed false) ; Prefer GPS speed over ESC speed
(def config-code-server true) ; Enable remote code execution

(def config-battery-hot 55.0) ; Displays warning indicator, Degrees C
(def config-esc-hot 80.0) ; Degrees C
(def config-motor-hot 80.0) ; Displays warning indicator, Degrees C

; Current limits for animation above speed dial
(def config-curr-accel 80.0)
(def config-curr-brake 60.0)

; Display rotation, 0-3. The panel is square, so any of the four is usable and
; which one is "up" depends on how the board sits in its case.
(def config-disp-rotation 0)

; (swap-xy mirror-x mirror-y), each 0 or 1. Start at (0 0 0) and try
; combinations until a tap lands where you put your finger. Must be changed to
; match config-disp-rotation.
(def config-touch-transforms '(0 0 0))

; This panel has no backlight control, only the two levels the shared settings
; layer insists on. Both are "on".
(def bl-lvl-bright 1)
(def bl-lvl-dim 1)

; Default light state
(def light-on-default false)

; Light-on means high beam, low beam otherwise
(def light-on-is-highbeam false)

; Shown under the speed. Index is the drive mode, so this must be at least
; drive-mode-num long.
(def drive-mode-names '("NEUTRAL" "ECO" "NORMAL" "SPORT" "REVERSE"))
