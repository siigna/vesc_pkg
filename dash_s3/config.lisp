; Copyright 2026 Stephen Bouche
; SPDX-License-Identifier: GPL-3.0-or-later
@const-start

(def config-metric-speeds true)
(def config-metric-temps true)

(def config-gnss-use-speed false) ; Prefer GPS speed over ESC speed
(def config-code-server true) ; Enable remote code execution

; Show the touch regions over the running dash for this long, once, a moment
; after it comes up. Zero is off. Every label is read back out of
; touch-region, so what it draws is the map that is really in force.
(def config-region-overlay-s 5.0)
(def config-region-overlay-delay-s 1.0)

(def config-battery-hot 55.0) ; Displays warning indicator, Degrees C
(def config-esc-hot 80.0) ; Degrees C
(def config-motor-hot 80.0) ; Displays warning indicator, Degrees C

; Current limits for animation above speed dial
(def config-curr-accel 80.0)
(def config-curr-brake 60.0)

; --- Board profile ------------------------------------------------------
; The panel, and the four layout numbers that differ between panels. Every
; other band in view_static is derived by stacking from these.
(def disp-w 480)
(def disp-h 480)
(def strip-h 54)        ; status strip along the top
(def speed-h 130)       ; big speed readout
(def page-h 144)        ; swappable page area
(def page-cols 2)       ; label/value columns; 8 cells, so 2 cols = 4 rows
(def page-row-h 36)     ; must fit the font the page grid draws with

; Image buffers are full-width strips, so this scales with the panel.
(def config-dm-pool 131072)

; Display rotation, 0-3. The panel is square, so any of the four is usable and
; which one is "up" depends on how the board sits in its case.
(def config-disp-rotation 0)

; Action id per touch region, short and long press. See btn-do-action, and the
; region map in lib/input.lisp: region 0 is the left of the nav strip, 1 and 2
; are the left and right halves of the screen above it, and 3 is the centre of
; the strip. Chosen so the on-screen hints in view_static match.
(def config-btn-actions-short (list 3 2 1 6))
; Region 1 is the left half of the screen; holding it clears the session.
(def config-btn-actions-long (list 0 12 0 8))

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
; Index for index what dash_esc applies in its drive-mode match, and what
; dash16 labels R N 1 2 3. The list used to read
; ("NEUTRAL" "ECO" "NORMAL" "SPORT" "REVERSE"), which labelled index 0 as
; neutral when the controller treats 0 as reverse, and index 4 as reverse when
; the controller treats it as the fastest drive mode.
(def drive-mode-names '("REVERSE" "NEUTRAL" "ECO" "NORMAL" "SPORT"))

; --- Battery model ------------------------------------------------------
; Used for the state-of-charge estimates in lib/battery.lisp. The defaults
; are placeholders: set the cell count and capacity to match your pack before
; pointing config-soc-source at anything but 'esc, because the model is only
; as good as these.

; Cells in series, and the pack's rated capacity in amp hours.
(def config-battery-cells 12)
(def config-battery-ah 20.0)

; Fraction of the rated capacity to treat as usable, so 0% on the gauge is
; the reserve you chose rather than cell damage.
(def config-battery-usable 0.85)

; Per-cell voltages at equally spaced states of charge: first entry empty,
; last full, the rest dividing the range evenly. Points are crowded between
; 3.6 and 3.9 V because that is where a lithium curve is flattest and a
; sparse table reads nearly full for most of a ride. Editing these is how you
; change chemistry.
(def config-discharge-ticks
    (list 3.30 3.60 3.68 3.73 3.77 3.81 3.85 3.90 4.00 4.20))

; How much the voltage estimate counts against the amp-hour one. 1.0 is
; voltage only, which sags under load; 0.0 is counting only, which drifts.
(def config-soc-voltage-weight 0.4)

; Which estimate the dash shows and uses for range:
;   'esc      what the controller reports (the default, and what it did before)
;   'voltage  from the discharge curve alone
;   'coulomb  from amp hours alone
;   'model    the two blended by config-soc-voltage-weight
;
; The live page can show all three at once, so you can watch them disagree on
; a real ride before trusting one.
(def config-soc-source 'esc)
