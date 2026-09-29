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

; --- Board profile ------------------------------------------------------
; The panel, and the four layout numbers that differ between panels. Every
; other band in view_static is derived by stacking from these.
(def disp-w 800)
(def disp-h 480)
(def strip-h 58)        ; status strip along the top
(def speed-h 145)       ; big speed readout
(def page-h 120)        ; swappable page area
(def page-cols 4)       ; label/value columns; 8 cells, so 4 cols = 2 rows
(def page-row-h 44)     ; must fit the font the page grid draws with

; Image buffers are full-width strips, and this panel is 800 wide, so the
; pool has to be bigger than the square board's: the speed strip alone is
; 800 * 190 / 4 = 38 kB.
(def config-dm-pool 262144)

; The panel is 480x800 native, so landscape needs a rotation. 1 and 3 are the
; two landscape orientations; which one is upright depends on the case.
;
; This is a software transpose in disp_st7701.c, which costs two allocations
; and a CPU rotate per rendered image. It is why the dash redraws only the
; fields that changed rather than whole frames.
(def config-disp-rotation 1)

; Action id per touch region, short and long press. See btn-do-action, and the
; region map in lib/input.lisp: region 0 is the left of the nav strip, 1 and 2
; are the left and right halves of the screen above it, and 3 is the centre of
; the strip. Chosen so the on-screen hints in view_static match.
(def config-btn-actions-short (list 3 2 1 6))
(def config-btn-actions-long (list 0 0 0 8))

; (swap-xy mirror-x mirror-y), each 0 or 1. Start at (0 0 0) and try
; combinations until a tap lands where you put your finger. Must be changed to
; match config-disp-rotation, and this board needs a rotation, so expect to
; set swap-xy here.
(def config-touch-transforms '(0 0 0))

; Backlight, 0..1. This board has real PWM control, so unlike the square one
; the dim level is genuinely dimmer rather than just "on".
(def bl-lvl-bright 1.0)
(def bl-lvl-dim 0.25)

; Display: reset pin and DSI lane rate, handed straight to disp-load-st7701.
; Touch: GT911 on I2C. No INT is broken out to the P4 on this board.
;
; TODO: verify every pin below against the board before flashing. They are
; taken from the board documentation, not from hardware.
(def config-disp-rst 27)
(def config-disp-lane-mbps 500)
(def config-touch-sda 7)
(def config-touch-scl 8)
(def config-touch-rst 23)
(def config-touch-int -1)

; Backlight pin. Active-LOW on this board, so bl-set inverts the duty.
(def config-bl-pin 26)
(def config-bl-freq 5000)

; Default light state
(def light-on-default false)

; Light-on means high beam, low beam otherwise
(def light-on-is-highbeam false)

; Shown under the speed. Index is the drive mode, so this must be at least
; drive-mode-num long.
(def drive-mode-names '("NEUTRAL" "ECO" "NORMAL" "SPORT" "REVERSE"))
