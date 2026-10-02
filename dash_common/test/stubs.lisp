; Copyright 2026 Stephen Bouche
; SPDX-License-Identifier: GPL-3.0-or-later
; Stubs for the VESC-specific extensions the LispBM repl does not have, so the
; dash_s3 views can be rendered offline to a PNG.

(defun color-mix (a b f) {
        (var ar (bitwise-and (shr a 16) 0xFF))
        (var ag (bitwise-and (shr a 8) 0xFF))
        (var ab (bitwise-and a 0xFF))
        (var br (bitwise-and (shr b 16) 0xFF))
        (var bg (bitwise-and (shr b 8) 0xFF))
        (var bb (bitwise-and b 0xFF))
        (+ (shl (to-i (+ ar (* f (- br ar)))) 16)
           (shl (to-i (+ ag (* f (- bg ag)))) 8)
              (to-i (+ ab (* f (- bb ab)))))
})

(defun color-make (r g b)
    (+ (shl (to-i (* r 255)) 16) (shl (to-i (* g 255)) 8) (to-i (* b 255))))

(defun set-print-prefix (p) nil)
(defun conf-get (k) 0)
(defun conf-set (k v) nil)
(defun conf-store () nil)
(defun reboot () nil)
(defun can-send-sid (id data) nil)
(defun can-list-devs () nil)
(defun canget-current () 0.0)
(defun gnss-speed () 0.0)
(defun event-enable (e) nil)
(defun gpio-configure (p m) nil)
(defun gpio-read (p) 1)
(defun get-adc (c) 0.0)
(defun pwm-start (a b c d) nil)
(defun pwm-set-duty (a b) nil)
(defun set-io (a b) nil)
(defun sysinfo (x) 0)
(defun start-code-server () nil)
(defun get-bms-val (k) (if (rest-args) 0.0 0.0))
(defun rcode-run (a b c) nil)
(defun rcode-run-noret (a b) nil)
; A real store, not a stub that returns 0: the settings layer writes defaults
; and reads them straight back, and zeroes come out as an all-black palette.
(def eeprom-mem (mkarray 128))
(def eeprom-isf (mkarray 128))
(defun eeprom-store-i (a v) { (setix eeprom-mem a (to-i v)) (setix eeprom-isf a nil) t })
(defun eeprom-store-f (a v) { (setix eeprom-mem a (to-float v)) (setix eeprom-isf a t) t })
(defun eeprom-read-i (a) (let ((v (ix eeprom-mem a))) (if (eq v nil) 0 (to-i v))))
(defun eeprom-read-f (a) (let ((v (ix eeprom-mem a))) (if (eq v nil) 0.0 (to-float v))))

; Display: the repl renders into whatever set-active-img points at
(defun disp-init () t)
(defun touch-pins () '(15 7 -1 16 480 480))
(defun touch-load-gt911 (a b c d e f) t)
(defun touch-apply-transforms (a b c) t)
(defun touch-read () nil)
