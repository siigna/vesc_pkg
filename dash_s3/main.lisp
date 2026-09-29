@const-start

; Waveshare ESP32-S3-Touch-LCD-4, 480x480. Board profile and bring-up; the
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
(import "font/roboto-bold-108-4c.bin" 'font-speed)
(import "font/roboto-bold-40-4c.bin" 'font-40)
(import "font/roboto-bold-24-4c.bin" 'font-24)
(import "font/roboto-bold-16-4c.bin" 'font-16)

; Views. These read the layout constants out of config.lisp, so they have to
; be loaded after it.
(import "../dash_common/views/view_static.lbm" 'code-view-static)
(read-eval-program code-view-static)

(import "../dash_common/views/view_pages.lbm" 'code-view-pages)
(read-eval-program code-view-pages)

@const-start

; disp-init comes from this board's hardware config and carries the 20-pin
; parallel RGB map, so the package holds no display pins.
(defun board-disp-init () {
        (disp-init)
        (ext-disp-orientation config-disp-rotation)
})

(defun board-touch-init () (apply touch-load-gt911 (touch-pins)))

; This panel has no backlight control, so this exists only because the shared
; settings layer calls it.
(defun bl-set (level) nil)

@const-end

(import "../dash_common/main_body.lisp" 'code-body)
(read-eval-program code-body)
