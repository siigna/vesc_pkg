; Copyright 2026 Stephen Bouche
; SPDX-License-Identifier: GPL-3.0-or-later
; State of charge from the pack itself, rather than taking the controller's
; word for it.
;
; The idea and the shape of the voltage table are from DAVEga
; (github.com/janpom/davega, GPLv3). Reimplemented, not copied.
;
; Two estimates, each wrong in its own direction:
;
;   voltage   tracks the pack directly and needs no calibration, but sags
;             under load, so it reads low under throttle and jumps back when
;             you coast.
;   coulomb   integrates amp hours out of the pack, so it is steady under
;             load, but it drifts: it only knows what it has counted since
;             something last told it where full was.
;
; Blending them with a fixed weight gives a figure that neither sags nor
; drifts much. config-soc-voltage-weight is the knob: 1.0 is voltage only,
; 0.0 is coulomb only.
;
; None of this replaces the controller's own figure unless you ask for it.
; config-soc-source selects, and the default is the controller, because the
; model is only as good as the pack capacity and cell count you configured
; and those default to placeholders. All three are on the live page, so you
; can watch them disagree before trusting one.

@const-start

; --- voltage -> state of charge ---
;
; config-discharge-ticks holds per-cell voltages at equally spaced states of
; charge: the first entry is empty, the last is full, and the rest divide the
; range evenly. So a ten-entry table means 0%, 11.1%, 22.2% and so on, and
; configuring a different chemistry is editing voltages rather than pairs.
;
; Points are worth crowding where the curve is flat -- most of a lithium
; pack's discharge sits between 3.6 and 3.9 V per cell, and a table that
; ignores that reads nearly full for most of a ride.
(defun batt-voltage-soc (v) {
        (var ticks config-discharge-ticks)
        (var n (length ticks))
        (var cells config-battery-cells)
        (if (or (< n 2) (< cells 1) (<= v 0.0))
            0.0
            {
                (var vc (/ v (to-float cells)))
                (if (<= vc (ix ticks 0))
                    0.0
                    (if (>= vc (ix ticks (- n 1)))
                        1.0
                        {
                            ; Find the interval this voltage falls in and
                            ; interpolate within it.
                            (var i 1)
                            (var res 1.0)
                            (loopwhile (< i n) {
                                    (var hi (ix ticks i))
                                    (if (< vc hi) {
                                            (var lo (ix ticks (- i 1)))
                                            (var span (- hi lo))
                                            (var frac (if (> span 0.0)
                                                          (/ (- vc lo) span) 0.0))
                                            (setq res (/ (+ (- i 1) frac)
                                                         (to-float (- n 1))))
                                            (setq i n)
                                    }
                                    (setq i (+ i 1)))
                            })
                            res
                        }))
            })
})

; --- amp hours -> state of charge ---
;
; Against the usable capacity rather than the rated one, so 0% is the reserve
; you decided on and not cell damage. A pack run to its real floor every ride
; does not last.
(defun batt-usable-ah ()
    (* config-battery-ah config-battery-usable))

(defun batt-coulomb-soc (ah-spent) {
        (var cap (batt-usable-ah))
        (if (<= cap 0.0) 0.0 (clamp01 (- 1.0 (/ ah-spent cap))))
})

; --- the blend ---
;
; Clamped, because two independently derived fractions can land outside 0..1
; between them -- a voltage above the top tick, or a counter that was
; re-anchored while the pack was resting. Anything downstream that scales a
; bar by this would index off the end of its palette.
(defun batt-model-soc ()
    (clamp01 (+ (* config-soc-voltage-weight (batt-voltage-soc stats-vin))
                (* (- 1.0 config-soc-voltage-weight)
                   (batt-coulomb-soc stats-battery-ah)))))

; What the rest of the dash should use. 'esc trusts the controller, 'voltage
; and 'coulomb take one estimate alone, 'model blends them.
(defun batt-soc ()
    (cond
        ((eq config-soc-source 'voltage) (batt-voltage-soc stats-vin))
        ((eq config-soc-source 'coulomb) (batt-coulomb-soc stats-battery-ah))
        ((eq config-soc-source 'model) (batt-model-soc))
        (t stats-battery-soc)))

@const-end
