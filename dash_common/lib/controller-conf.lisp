; Copyright 2026 Stephen Bouche
; SPDX-License-Identifier: GPL-3.0-or-later
; Controller settings the dash may change.
;
; Separate from the display settings in persistent-settings.lisp: these live on
; the controller, are mirrored in over CAN, and are changed by sending a frame
; back rather than by writing eeprom here.
;
; In a library rather than main_body because views/view_pages.lbm renders them,
; and the off-target render harness loads the libraries and the views without
; main_body.

; The ids, limits and step come from this table; the controller has its own copy
; of the ids and enforces its own limits, because a display is on a bus anyone
; can put a frame on. So this table is for presentation, not for safety.
;
; Order must match the controller's, since the id is what goes over CAN.
;
;   (id label format step gated)
(def conf-menu '(
        (0  "Assist Gain"   "%.2f"   0.1   false)
        (1  "PAS Current"   "%.2f"   0.01  false)
        (2  "Taper Start"   "%.1f"   0.5   false)
        (3  "Taper End"     "%.1f"   0.5   false)
        (4  "Power Cap"     "%.0f"   10.0  false)
        (5  "Regen Scale"   "%.2f"   0.05  false)
        (6  "Accel Scale"   "%.2f"   0.05  false)
        (7  "PAS Mode"      "%.0f"   1.0   true)
        (8  "Magnets"       "%.0f"   1.0   true)
        (9  "Start Thresh"  "%.2f"   0.05  true)
        (10 "Stop Thresh"   "%.2f"   0.05  true)
        (11 "Torque Zero"   "%.3f"   0.01  true)
        (12 "Torque Nm/V"   "%.1f"   1.0   true)
))

(def conf-now 0)

(defun conf-menu-len () (length conf-menu))
(defun conf-row (i) (ix conf-menu i))

; What the controller last reported for a row, or nil until it has.
(defun conf-value (i)
    (let ((id (ix (conf-row i) 0)))
        (if (= 1 (bufget-u8 conf-seen id))
            (bufget-f32 conf-vals (* id 4))
            nil)))

; A gated row is only accepted by the controller while the kill switch holds the
; motor, so the dash says so rather than letting the press be silently refused.
(defun conf-blocked (i)
    (and (ix (conf-row i) 4) (not kill-sw-active)))

(defun conf-send (cmd id val) {
        (var b (bufcreate 8))
        (bufset-u8 b 0 cmd)
        (bufset-u8 b 1 id)
        (bufset-f32 b 2 val)
        (can-send-sid 205 b)
        (free b)
})

