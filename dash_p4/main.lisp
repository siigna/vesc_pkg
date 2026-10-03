; Copyright Benjamin Vedder
; Copyright 2026 Stephen Bouche
;
; Parts of this file were moved here from main.lisp;
; git blame -C records 4 lines as Benjamin Vedder's.
; SPDX-License-Identifier: GPL-3.0-or-later
@const-start

; Waveshare ESP32-P4-WIFI6-Touch-LCD-4.3, 800x480. Board profile and bring-up; the
; dash itself is ../dash_common.
;
; Every import in the package has to be here: vesc_tool packs imports by
; scanning this file only, so an import inside an imported file would never
; reach the device.

(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)

(import "version.lisp" 'code-version)
(read-eval-program code-version)

(import "config.lisp" 'code-config)
(read-eval-program code-config)

; Shared lib
(import "../dash_common/lib/vehicle-state.lisp" 'code-vehicle-state)
(read-eval-program code-vehicle-state)

(import "../dash_common/lib/colors.lisp" 'code-colors)
(read-eval-program code-colors)

(import "../dash_common/lib/user-settings.lisp" 'code-user-settings)
(read-eval-program code-user-settings)

(import "../dash_common/lib/persistent-settings.lisp" 'code-persistent-settings)
(read-eval-program code-persistent-settings)

(import "../dash_common/lib/statistics.lisp" 'code-statistics)
(read-eval-program code-statistics)

; The board's own log, which the log page draws. Loaded before the views,
; which call into it.
(import "../dash_common/lib/boot-log.lisp" 'code-boot-log)
(read-eval-program code-boot-log)

(import "../dash_common/lib/draw-utils.lisp" 'code-draw-utils)
(read-eval-program code-draw-utils)

(import "../dash_common/lib/battery.lisp" 'code-battery)
(read-eval-program code-battery)

(import "../dash_common/lib/controller-conf.lisp" 'code-controller-conf)
(import "../dash_common/lib/communication.lisp" 'code-communication)
(read-eval-program code-controller-conf)
(read-eval-program code-communication)

(import "../dash_common/lib/standalone.lisp" 'code-standalone)
(read-eval-program code-standalone)

; Touch regions stand in for buttons on this board, so input is board-local
(import "lib/input.lisp" 'code-input)
(read-eval-program code-input)

; Fonts, pre-rendered by font/generate_fonts. Preparing them on the device
; would mean shipping Roboto-Bold.ttf, which is larger than the fonts and the
; whole source put together. The two big ones carry only the glyphs they can
; draw, plus a "D" that ttf-txt-center measures to find the baseline.
(import "font/roboto-bold-120-4c.bin" 'font-speed)
(import "font/roboto-bold-40-4c.bin" 'font-40)
(import "font/roboto-bold-24-4c.bin" 'font-24)
(import "font/roboto-bold-18-4c.bin" 'font-16)

; Views. These read the layout constants out of config.lisp, so they have to
; be loaded after it.
(import "../dash_common/views/view_static.lbm" 'code-view-static)
(read-eval-program code-view-static)

(import "../dash_common/views/view_pages.lbm" 'code-view-pages)
(read-eval-program code-view-pages)

@const-start

; This panel is already supported upstream, so unlike the S3 board there is no
; board-specific disp-init to call: disp-load-st7701 takes the two numbers it
; needs. They live in config.lisp rather than here.
;
; The panel is 480x800 native, so the rotation is what makes it landscape, and
; it has to be applied before touch is loaded because touch is told the
; rotated size.
(defun board-disp-init () {
        (disp-load-st7701 config-disp-rst config-disp-lane-mbps)
        (ext-disp-orientation config-disp-rotation)
})

(defun board-touch-init ()
    (touch-load-gt911 config-touch-sda config-touch-scl
                      config-touch-rst config-touch-int
                      disp-w disp-h))

; Real PWM backlight. The pin is active-LOW, so the duty is inverted; the
; firmware parks it off in hw_init so nothing shows before the first draw.
(defun bl-set (level)
    (pwm-start config-bl-freq (- 1.0 (clamp01 level)) 0 config-bl-pin))

@const-end

(import "../dash_common/main_body.lisp" 'code-body)
(read-eval-program code-body)
