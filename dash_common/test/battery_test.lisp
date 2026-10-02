; Copyright 2026 Stephen Bouche
; SPDX-License-Identifier: GPL-3.0-or-later
; Unit tests for lib/battery.lisp. Pure arithmetic, so no display needed.
(import "stubs.lisp" 'code-stubs)
(read-eval-program code-stubs)
(import "build/common/lib/draw-utils.lisp" 'c-draw)
(read-eval-program c-draw)
(import "build/common/lib/battery.lisp" 'c-batt)
(read-eval-program c-batt)

; The configuration the tests assume, rather than whichever board's
(def config-battery-cells 12)
(def config-battery-ah 20.0)
(def config-battery-usable 0.85)
(def config-discharge-ticks
    (list 3.30 3.60 3.68 3.73 3.77 3.81 3.85 3.90 4.00 4.20))
(def config-soc-voltage-weight 0.4)
(def config-soc-source 'esc)
(def stats-vin 0.0)
(def stats-battery-ah 0.0)
(def stats-battery-soc 0.5)

(def checks 0)
(def fails 0)
(defun near (what got want) {
        (setq checks (+ checks 1))
        (if (> (abs (- got want)) 0.001) {
                (setq fails (+ fails 1))
                (print (list 'FAIL what 'got got 'want want))
        })
})

; --- voltage curve ---
; Ten ticks, so the states of charge they mark are i/9.
(near "empty tick"        (batt-voltage-soc (* 12 3.30)) 0.0)
(near "full tick"         (batt-voltage-soc (* 12 4.20)) 1.0)
(near "below empty"       (batt-voltage-soc (* 12 3.00)) 0.0)
(near "above full"        (batt-voltage-soc (* 12 4.35)) 1.0)
(near "tick 1"            (batt-voltage-soc (* 12 3.60)) (/ 1.0 9.0))
(near "tick 7"            (batt-voltage-soc (* 12 3.90)) (/ 7.0 9.0))
(near "tick 8"            (batt-voltage-soc (* 12 4.00)) (/ 8.0 9.0))
; Halfway between tick 1 and tick 2, whose states of charge are 1/9 and 2/9
(near "interpolated"      (batt-voltage-soc (* 12 3.64)) (/ 1.5 9.0))
; A quarter of the way from tick 4 (3.77) to tick 5 (3.81)
(near "interpolated high" (batt-voltage-soc (* 12 3.78)) (/ 4.25 9.0))
(near "zero volts"        (batt-voltage-soc 0.0) 0.0)
(near "negative volts"    (batt-voltage-soc -5.0) 0.0)

; Cell count must scale it: the same per-cell voltage on a 6S pack
(def config-battery-cells 6)
(near "6S at tick 7"      (batt-voltage-soc (* 6 3.90)) (/ 7.0 9.0))
(def config-battery-cells 12)

; A table too short to interpolate must not divide by zero
(def config-discharge-ticks (list 3.5))
(near "one-entry table"   (batt-voltage-soc (* 12 3.8)) 0.0)
(def config-discharge-ticks
    (list 3.30 3.60 3.68 3.73 3.77 3.81 3.85 3.90 4.00 4.20))

; --- coulomb ---
; Usable capacity is 20 * 0.85 = 17 Ah, so that is what 0% means.
(near "nothing spent"     (batt-coulomb-soc 0.0) 1.0)
(near "half spent"        (batt-coulomb-soc 8.5) 0.5)
(near "usable exhausted"  (batt-coulomb-soc 17.0) 0.0)
(near "past usable"       (batt-coulomb-soc 20.0) 0.0)
(near "regen past full"   (batt-coulomb-soc -2.0) 1.0)
(near "usable ah"         (batt-usable-ah) 17.0)

; --- the blend, and that it is clamped ---
(setq stats-vin (* 12 3.90))      ; voltage says 7/9
(setq stats-battery-ah 8.5)       ; counting says 0.5
(near "blend 0.4/0.6"
      (batt-model-soc)
      (+ (* 0.4 (/ 7.0 9.0)) (* 0.6 0.5)))

(setq config-soc-voltage-weight 1.0)
(near "weight 1 is voltage only" (batt-model-soc) (/ 7.0 9.0))
(setq config-soc-voltage-weight 0.0)
(near "weight 0 is counting only" (batt-model-soc) 0.5)
(setq config-soc-voltage-weight 0.4)

; Both estimates at their extremes must still land inside 0..1, because a bar
; scaled by this would index off the end of its palette.
(setq stats-vin (* 12 4.35))
(setq stats-battery-ah -5.0)
(near "clamped high" (batt-model-soc) 1.0)
(setq stats-vin 0.0)
(setq stats-battery-ah 99.0)
(near "clamped low" (batt-model-soc) 0.0)

; --- source selection ---
(setq stats-vin (* 12 3.90))
(setq stats-battery-ah 8.5)
(setq stats-battery-soc 0.25)
(def config-soc-source 'esc)
(near "source esc"     (batt-soc) 0.25)
(def config-soc-source 'voltage)
(near "source voltage" (batt-soc) (/ 7.0 9.0))
(def config-soc-source 'coulomb)
(near "source coulomb" (batt-soc) 0.5)
(def config-soc-source 'model)
(near "source model"   (batt-soc) (+ (* 0.4 (/ 7.0 9.0)) (* 0.6 0.5)))
(def config-soc-source 'nonsense)
(near "unknown source falls back to esc" (batt-soc) 0.25)

(print (list 'battery checks 'checks fails 'fails))
