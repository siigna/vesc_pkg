; Copyright Benjamin Vedder
; Copyright 2026 Stephen Bouche
;
; Parts of this file were moved here from dash35b/lib/persistent-settings.lisp, dash35b/main.lisp, lib/persistent-settings.lisp;
; git blame -C records 36 lines as Benjamin Vedder's.
; SPDX-License-Identifier: GPL-3.0-or-later
; Runtime copies for the views. Before @const-start because they are mutated.
(def settings-units-metric config-metric-speeds)
(def settings-temps-metric config-metric-temps)
(def settings-batt-hot config-battery-hot)
(def settings-esc-hot config-esc-hot)
(def settings-motor-hot config-motor-hot)
(def settings-bl-bright bl-lvl-bright)
(def settings-bl-dim bl-lvl-dim)

; Drive modes the buttons cycle through.
(def drive-mode-num 5)

; Rotating pages in the button-0 cycle. Settings page sits at page-num.
(def settings-page-mask 0xF)
; How far a live cell's value moves towards the real one each redraw. 0 is off,
; which is the old behaviour of jumping straight to it.
; One btn-do-action id per quick shade button, 0 for an empty cell. Defaults
; to the controls a touch board otherwise cannot reach at all.
(def settings-shade (list 4 5 6 8 9 14))

(def settings-pin-code 0)
(def settings-pin-en false)

(def settings-smooth 0.0)

(def settings-chart-src 4)
(def settings-chart-secs 10)

(def settings-setting-mask 0xF)

; Short/long action id per button or touch region. See btn-do-action. Which
; input a given index means, and therefore what a sensible default is, depends
; on the board, so the defaults come from its config.lisp.
(def btn-actions-short config-btn-actions-short)
(def btn-actions-long config-btn-actions-long)

; 0 auto, 1 assume dash_esc, 2 assume stock.
(def settings-esc-mode 0)

(def settings-esc-id 0)

; Icons drawn. 0 signals 1 beam 2 kickstand 3 temp 4 fault 5 cruise.
(def settings-icon-mask 0x3F)

; Index into slot-catalog. Changing that order breaks saved settings.
(def settings-slots (list 2 6 7 15))

; Per slot: 0 a fixed colour, 1 a green to red ramp across the range below.
(def settings-slot-modes (list 0 0 0 0))

; Colour the battery bar by charge rather than the accent.
(def settings-batt-ramp false)

(def settings-splash true)
(def settings-slot-mins (list 0.0 0.0 0.0 0.0))
(def settings-slot-maxs (list 100.0 100.0 100.0 100.0))

; The worker repaints on this, so a redraw never blocks the data channel.
(def settings-redraw false)

; Built by settings-build.
(def setting-list-page1 nil)
(def setting-step-page1 nil)
(def setting-lim-page1 nil)
(def setting-label-page1 nil)
(def setting-fmt-page1 nil)

@const-start

; Persistent settings
; Format: (label . (offset type))
(def eeprom-addrs '(
    (ver-code  . (0 i))
    (pf1-speed . (1 f))
    (pf1-brake . (2 f))
    (pf1-accel . (3 f))
    (pf2-speed . (4 f))
    (pf2-brake . (5 f))
    (pf2-accel . (6 f))
    (pf3-speed . (7 f))
    (pf3-brake . (8 f))
    (pf3-accel . (9 f))
    (pf-active . (10 i))

    (whl-active . (11 i))
    (whl-start . (12 f))
    (whl-end . (13 f))
    (whl-kd . (14 f))

    (units-metric . (15 i))
    (temps-metric . (16 i))
    (batt-hot . (17 f))
    (esc-hot . (18 f))
    (motor-hot . (19 f))
    (bl-bright . (20 i))
    (bl-dim . (21 i))

    (drive-modes . (22 i))
    (page-mask . (23 i))
    (setting-mask . (24 i))

    (btn0-short . (25 i))
    (btn1-short . (26 i))
    (btn2-short . (27 i))
    (btn3-short . (28 i))
    (btn0-long . (29 i))
    (btn1-long . (30 i))
    (btn2-long . (31 i))
    (btn3-long . (32 i))

    (esc-mode . (33 i))
    (esc-id . (34 i))

    (icon-mask . (52 i))

    (col-accent . (55 i))
    (col-text . (56 i))

    (slot-0 . (57 i))
    (slot-1 . (58 i))
    (slot-2 . (59 i))
    (slot-3 . (60 i))

    (slot-col-0 . (61 i))
    (slot-col-1 . (62 i))
    (slot-col-2 . (63 i))
    (slot-col-3 . (64 i))
    (slot-mode-0 . (65 i))
    (slot-mode-1 . (66 i))
    (slot-mode-2 . (67 i))
    (slot-mode-3 . (68 i))
    (slot-min-0 . (69 f))
    (slot-min-1 . (70 f))
    (slot-min-2 . (71 f))
    (slot-min-3 . (72 f))
    (slot-max-0 . (73 f))
    (slot-max-1 . (74 f))
    (slot-max-2 . (75 f))
    (slot-max-3 . (76 f))

    (batt-ramp . (77 i))
    (splash-en . (78 i))
    (chart-src . (79 i))
    (chart-secs . (80 i))
    (theme . (81 i))
    (col-bg . (82 i))
    (smooth . (83 f))
    (shade-0 . (84 i))
    (shade-1 . (85 i))
    (shade-2 . (86 i))
    (shade-3 . (87 i))
    (shade-4 . (88 i))
    (shade-5 . (89 i))

    ; A plain four digit number. Anything on the bus can read it; see the note
    ; on the PIN lock in vehicle-state.lisp for what this is and is not.
    (pin-code . (90 i))
    ; i, not b, like every other flag here: setting-flag compares the value
    ; against 1, and a b cell reads back as a boolean, which makes that a type
    ; error rather than false.
    (pin-en . (91 i))
))

(defun print-settings ()
    (loopforeach it eeprom-addrs
        (print (list (first it) (read-setting (first it))))
))

; Settings version
(def settings-version 54i32)

(defun read-setting (name)
    (let (
            (addr (first (assoc eeprom-addrs name)))
            (type (second (assoc eeprom-addrs name)))
        )
        (cond
            ((eq type 'i) (eeprom-read-i addr))
            ((eq type 'f) (eeprom-read-f addr))
            ((eq type 'b) (!= (eeprom-read-i addr) 0))
)))

(defun write-setting (name val)
    (let (
            (addr (first (assoc eeprom-addrs name)))
            (type (second (assoc eeprom-addrs name)))
        )
        (cond
            ((eq type 'i) (eeprom-store-i addr val))
            ((eq type 'f) (eeprom-store-f addr val))
            ((eq type 'b) (eeprom-store-i addr (if val 1 0)))
)))

; (name label format step min max). Page fits six rows.
(def setting-catalog '(
        (whl-active   "Wheelie EN"  "%d"       1     0    1)
        (whl-start    "Angle Start" "%.1f deg" 0.5   0.0  55.0)
        (whl-end      "Angle End"   "%.1f deg" 0.5   0.0  55.0)
        (whl-kd       "Damping"     "%.3f"     0.001 0.0  0.2)
        (bl-bright    "BL Bright"   "%d"       1     1    1)
        (bl-dim       "BL Dim"      "%d"       1     0    1)
        (batt-hot     "Batt Warn"   "%.0f C"   1.0   0.0  200.0)
        (esc-hot      "ESC Warn"    "%.0f C"   1.0   0.0  200.0)
        (motor-hot    "Motor Warn"  "%.0f C"   1.0   0.0  200.0)
        (units-metric "Metric Spd"  "%d"       1     0    1)
        (temps-metric "Metric Tmp"  "%d"       1     0    1)
        ; Bit 11. A bare index rather than a name because the settings page
        ; formats numbers, and here that is tolerable: the whole screen
        ; recolours as the number changes, so the value names itself.
        (theme        "Theme"       "%d"       1     0    4)
        ; Bit 12.
        (smooth       "Smoothing"   "%.1f"     0.1   0.0  0.9)
))

(def setting-catalog-max 6)

; An unwritten cell reads -1, which as a float is NaN, so test that first.
;
; nil is tested before that, and not for tidiness: read-setting returns nil for
; a name that is not in eeprom-addrs, and on real hardware for a slot that has
; never been written -- where the test stub hands back 0 instead. Comparing nil
; with = is a type error, which took settings-load down with it and left the
; dash dead before it drew anything. A missing setting has to degrade to its
; default, not stop the display coming up.
(defun setting-clamp (v lo hi dflt)
    (if (eq v nil) dflt
    (if (not (= v v)) dflt
        (if (< v lo) dflt
            (if (> v hi) dflt v)))))

; A never written cell reads nil, and comparing that to a number throws.
(defun setting-flag (name dflt)
    (let ((v (read-setting name)))
        (cond
            ((eq v nil) dflt)
            ((= v 1) true)
            ((= v 0) false)
            (t dflt)
)))

; Backlight floor is 1: zero is a black screen that looks like a crash.
(defun settings-load () {
        (setq settings-units-metric (setting-flag 'units-metric config-metric-speeds))
        (setq settings-temps-metric (setting-flag 'temps-metric config-metric-temps))
        (setq settings-batt-hot (setting-clamp (read-setting 'batt-hot) 0.0 200.0 config-battery-hot))
        (setq settings-esc-hot (setting-clamp (read-setting 'esc-hot) 0.0 200.0 config-esc-hot))
        (setq settings-motor-hot (setting-clamp (read-setting 'motor-hot) 0.0 200.0 config-motor-hot))
        (setq settings-bl-bright (setting-clamp (read-setting 'bl-bright) 1 1 bl-lvl-bright))
        (setq settings-bl-dim (setting-clamp (read-setting 'bl-dim) 0 1 bl-lvl-dim))
        ; view_static labels only 0-4, dash_esc matches only 0-4.
        (setq drive-mode-num (setting-clamp (read-setting 'drive-modes) 1 5 5))
        ; The PAS page is bit 4 and is off in the default mask, since most
        ; vehicles have no pedals. Raise the upper bound when pages are added or
        ; the new page cannot be enabled at all.
        (setq settings-page-mask (setting-clamp (read-setting 'page-mask) 1 0x1FF 0xF))
        ; One bit per setting-catalog row. Raise the bound when the catalog
        ; grows, or the new row cannot be enabled at all.
        (setq settings-setting-mask (setting-clamp (read-setting 'setting-mask) 0 0x1FFF 0xF))

        ; The upper bound is the highest action id in btn-do-action. Raise it
        ; when an action is added, or the new id clamps to 0 and the binding
        ; quietly vanishes.
        ; Upper bound is the last action in btn-do-action. Raise it when actions
        ; are added, or the new one cannot be selected at all.
        (setq btn-actions-short (map (fn (n) (setting-clamp (read-setting n) 0 21 0))
                '(btn0-short btn1-short btn2-short btn3-short)))
        (setq btn-actions-long (map (fn (n) (setting-clamp (read-setting n) 0 21 0))
                '(btn0-long btn1-long btn2-long btn3-long)))

        (setq settings-esc-mode (setting-clamp (read-setting 'esc-mode) 0 2 0))
        (setq settings-esc-id (setting-clamp (read-setting 'esc-id) 0 253 0))
        (setq settings-icon-mask (setting-clamp (read-setting 'icon-mask) 0 0x3F 0x3F))
        (setq settings-batt-ramp (setting-flag 'batt-ramp false))
        (setq settings-splash (setting-flag 'splash-en true))
        ; The theme first: it supplies the defaults the three colour settings
        ; fall back to, so it has to be known before they are read. An
        ; out-of-range index falls back to row 0 in theme-row rather than here,
        ; since the catalog length lives with the catalog.
        (setq settings-theme (setting-clamp (read-setting 'theme) 0 15 0))
        (theme-apply-status)
        (setq color-bg (setting-clamp (read-setting 'col-bg) 0 0xFFFFFF (theme-bg)))
        (setq color-accent (setting-clamp (read-setting 'col-accent) 0 0xFFFFFF (theme-accent)))
        (setq color-text (setting-clamp (read-setting 'col-text) 0 0xFFFFFF (theme-text)))
        ; Upper bound is the last index of slot-catalog. Raise it when the
        ; catalog grows, or the new sources cannot be selected at all.
        ; Which slot-catalog source the rolling chart plots, and over how long.
        ; Reusing the catalog means the chart gets its label, unit and
        ; formatting for free and can plot anything a live cell can.
        (setq settings-chart-src (setting-clamp (read-setting 'chart-src) 0 29 4))
        (setq settings-chart-secs (setting-clamp (read-setting 'chart-secs) 5 10 10))

        ; Off by default: it raises the redraw rate while a value moves, and
        ; the S3 is the board with the least headroom for that.
        (setq settings-smooth (setting-clamp (read-setting 'smooth) 0.0 0.9 0.0))

        ; Same bound as the button actions, for the same reason: an id past the
        ; end of btn-do-action clamps to 0 and the cell quietly goes blank.
        (setq settings-shade (map (fn (n) (setting-clamp (read-setting n) 0 21 0))
                '(shade-0 shade-1 shade-2 shade-3 shade-4 shade-5)))

        (setq settings-pin-code (setting-clamp (read-setting 'pin-code) 0 9999 0))
        (setq settings-pin-en (setting-flag 'pin-en false))

        (setq settings-slots (map (fn (n) (setting-clamp (read-setting n) 0 29 0))
                '(slot-0 slot-1 slot-2 slot-3)))
        ; Same fallback as the three main colours: an unpicked cell takes the
        ; theme's text colour, so a live cell is not left white on a pale
        ; background.
        (setq settings-slot-cols (map (fn (n) (setting-clamp (read-setting n) 0 0xFFFFFF (theme-text)))
                '(slot-col-0 slot-col-1 slot-col-2 slot-col-3)))
        ; 0 fixed, 1 ramp, 2 heat, 3 low-warn, 4 sign. See slot-colors. Raise
        ; the bound when a rule is added, or it clamps to fixed and the choice
        ; quietly vanishes.
        (setq settings-slot-modes (map (fn (n) (setting-clamp (read-setting n) 0 4 0))
                '(slot-mode-0 slot-mode-1 slot-mode-2 slot-mode-3)))
        (setq settings-slot-mins (map (fn (n) (setting-clamp (read-setting n) -1000.0 10000.0 0.0))
                '(slot-min-0 slot-min-1 slot-min-2 slot-min-3)))
        (setq settings-slot-maxs (map (fn (n) (setting-clamp (read-setting n) -1000.0 10000.0 100.0))
                '(slot-max-0 slot-max-1 slot-max-2 slot-max-3)))

        ; Neutral, not 0. Index 0 is reverse in the order dash_esc applies, so
        ; a stored mode past the end of a shortened list used to drop the bike
        ; into reverse.
        (if (>= drive-mode drive-mode-num) (mode-set 1))
})

; Rows from the mask, capped so none draw off the page.
(defun settings-build () {
        (var names nil)
        (var steps nil)
        (var lims nil)
        (var labels nil)
        (var fmts nil)
        (var shown 0)

        (looprange i 0 (length setting-catalog) {
                (var row (ix setting-catalog i))
                (if (and (!= 0 (bitwise-and settings-setting-mask (shl 1 i)))
                         (< shown setting-catalog-max)) {
                        (setq names (cons (ix row 0) names))
                        (setq labels (cons (ix row 1) labels))
                        (setq fmts (cons (ix row 2) fmts))
                        (setq steps (cons (ix row 3) steps))
                        (setq lims (cons (list (ix row 4) (ix row 5)) lims))
                        (setq shown (+ shown 1))
                })
        })

        (setq setting-list-page1 (reverse names))
        (setq setting-label-page1 (reverse labels))
        (setq setting-fmt-page1 (reverse fmts))
        (setq setting-step-page1 (reverse steps))
        (setq setting-lim-page1 (reverse lims))
        (setq setting-num shown)
        (if (>= setting-now shown) (setq setting-now 0))
})

; Views read the pairs, not the flags.
(defun settings-apply-units () {
        (setq view-force-static true)
        (setq view-force-pages true)
        (if settings-units-metric
            (def settings-units-speeds '(kmh . "km/h"))
            (def settings-units-speeds '(mph . "MPH"))
        )
        (if settings-temps-metric
            (def settings-units-temps '(celsius . "C"))
            (def settings-units-temps '(fahrenheit . "F"))
        )
})

; True when an icon should be drawn.
(defun icon-on (n)
    (!= 0 (bitwise-and settings-icon-mask (shl 1 n))))

; Wipe every stored setting and reload. The page calls this.
(defun settings-reset () {
        (restore-settings)
        (settings-load)
        (settings-build)
        (settings-apply-units)
        (settings-apply-pages)
        (setq settings-redraw true)
        (send-cfg)
})

; Reload now so a read back is current, but leave the repaint to the worker.
(defun settings-set (name val) {
        (write-setting name val)
        (settings-load)
        (settings-build)
        (settings-apply-units)
        (settings-apply-pages)
        (setq settings-redraw true)
})

; Everything on screen is now the wrong colour, so redraw the lot.
(defun settings-apply-visual () {
        (setq settings-redraw false)
        (colors-build)
        (disp-clear color-bg)
        (setq view-force-static true)
        (setq view-force-pages true)
        (bl-set (if backlight-dim settings-bl-dim settings-bl-bright))
})

; Preview without storing, for the slider.
(defun bl-preview (v) (bl-set (setting-clamp v 0 1 settings-bl-bright)))

; One framed packet, not seven prints, and no 0.5 s REPL limit.
(defun send-cfg ()
    (send-data (str-merge
            "cfg "
            (str-from-n (if settings-units-metric 1 0) "%d ")
            (str-from-n (if settings-temps-metric 1 0) "%d ")
            (str-from-n settings-batt-hot "%.1f ")
            (str-from-n settings-esc-hot "%.1f ")
            (str-from-n settings-motor-hot "%.1f ")
            (str-from-n settings-bl-bright "%d ")
            (str-from-n settings-bl-dim "%d ")
            (str-from-n drive-mode-num "%d ")
            (str-from-n settings-page-mask "%d ")
            (str-from-n settings-setting-mask "%d ")
            (str-from-n (ix btn-actions-short 0) "%d ")
            (str-from-n (ix btn-actions-short 1) "%d ")
            (str-from-n (ix btn-actions-short 2) "%d ")
            (str-from-n (ix btn-actions-short 3) "%d ")
            (str-from-n (ix btn-actions-long 0) "%d ")
            (str-from-n (ix btn-actions-long 1) "%d ")
            (str-from-n (ix btn-actions-long 2) "%d ")
            (str-from-n (ix btn-actions-long 3) "%d ")
            (str-from-n settings-esc-mode "%d ")
            (str-from-n settings-esc-id "%d ")
            (str-from-n (if standalone-active 1 0) "%d ")
            (str-from-n standalone-esc-id "%d ")
            (str-from-n settings-icon-mask "%d ")
            ; The stored values rather than the resolved ones, so the pickers
            ; can show "Theme" for a colour nobody has overridden. An unwritten
            ; cell reads -1, which is exactly that state.
            (str-from-n (read-setting 'col-accent) "%d ")
            (str-from-n (read-setting 'col-text) "%d ")
            (str-from-n (ix settings-slots 0) "%d ")
            (str-from-n (ix settings-slots 1) "%d ")
            (str-from-n (ix settings-slots 2) "%d ")
            (str-from-n (ix settings-slots 3) "%d ")
            (str-from-n (ix settings-slot-cols 0) "%d ")
            (str-from-n (ix settings-slot-cols 1) "%d ")
            (str-from-n (ix settings-slot-cols 2) "%d ")
            (str-from-n (ix settings-slot-cols 3) "%d ")
            (str-from-n (ix settings-slot-modes 0) "%d ")
            (str-from-n (ix settings-slot-modes 1) "%d ")
            (str-from-n (ix settings-slot-modes 2) "%d ")
            (str-from-n (ix settings-slot-modes 3) "%d ")
            (str-from-n (ix settings-slot-mins 0) "%.0f ")
            (str-from-n (ix settings-slot-mins 1) "%.0f ")
            (str-from-n (ix settings-slot-mins 2) "%.0f ")
            (str-from-n (ix settings-slot-mins 3) "%.0f ")
            (str-from-n (ix settings-slot-maxs 0) "%.0f ")
            (str-from-n (ix settings-slot-maxs 1) "%.0f ")
            (str-from-n (ix settings-slot-maxs 2) "%.0f ")
            (str-from-n (ix settings-slot-maxs 3) "%.0f ")
            (str-from-n (if settings-batt-ramp 1 0) "%d ")
            (str-from-n (if settings-splash 1 0) "%d ")
            ; Positional and append-only, so new fields go on the end.
            (str-from-n settings-theme "%d ")
            (str-from-n (read-setting 'col-bg) "%d ")
            (str-from-n settings-chart-src "%d ")
            (str-from-n settings-chart-secs "%d ")
            (str-from-n settings-smooth "%.2f ")
            (str-from-n (ix settings-shade 0) "%d ")
            (str-from-n (ix settings-shade 1) "%d ")
            (str-from-n (ix settings-shade 2) "%d ")
            (str-from-n (ix settings-shade 3) "%d ")
            (str-from-n (ix settings-shade 4) "%d ")
            (str-from-n (ix settings-shade 5) "%d ")
            (str-from-n settings-pin-code "%d ")
            (if settings-pin-en "1" "0")
)))

(defun restore-settings ()
    (progn
        (write-setting 'pf1-speed 39.3)
        (write-setting 'pf1-brake 1.0)
        (write-setting 'pf1-accel 1.0)
        (write-setting 'pf2-speed 18.8)
        (write-setting 'pf2-brake 0.4)
        (write-setting 'pf2-accel 0.6)
        (write-setting 'pf3-speed 11.2)
        (write-setting 'pf3-brake 0.2)
        (write-setting 'pf3-accel 0.4)
        (write-setting 'pf-active 0)

        (write-setting 'whl-active 0)
        (write-setting 'whl-start 20)
        (write-setting 'whl-end 43)
        (write-setting 'whl-kd 0.005)

        (write-setting 'units-metric (if config-metric-speeds 1 0))
        (write-setting 'temps-metric (if config-metric-temps 1 0))
        (write-setting 'batt-hot config-battery-hot)
        (write-setting 'esc-hot config-esc-hot)
        (write-setting 'motor-hot config-motor-hot)
        (write-setting 'bl-bright bl-lvl-bright)
        (write-setting 'bl-dim bl-lvl-dim)

        (write-setting 'drive-modes 5)
        (write-setting 'page-mask 0xF)
        (write-setting 'setting-mask 0xF)

        ; From the board's config, not hardcoded: which input index 0 to 3
        ; means differs per board, so only the board knows a sensible default.
        (write-setting 'btn0-short (ix config-btn-actions-short 0))
        (write-setting 'btn1-short (ix config-btn-actions-short 1))
        (write-setting 'btn2-short (ix config-btn-actions-short 2))
        (write-setting 'btn3-short (ix config-btn-actions-short 3))
        (write-setting 'btn0-long (ix config-btn-actions-long 0))
        (write-setting 'btn1-long (ix config-btn-actions-long 1))
        (write-setting 'btn2-long (ix config-btn-actions-long 2))
        (write-setting 'btn3-long (ix config-btn-actions-long 3))

        (write-setting 'esc-mode 0)
        (write-setting 'esc-id 0)

        (write-setting 'icon-mask 0x3F)
        (write-setting 'batt-ramp 0)
        (write-setting 'splash-en 1)

        (write-setting 'theme 0)
        (write-setting 'smooth 0.0)

        (looprange i 0 6
            (write-setting (ix '(shade-0 shade-1 shade-2 shade-3 shade-4 shade-5) i)
                (ix '(4 5 6 8 9 14) i)))

        (write-setting 'pin-code 0)
        (write-setting 'pin-en 0)

        ; Added to eeprom-addrs and to settings-load when the chart page was
        ; written, and missed here. An unwritten slot reads nil on hardware, so
        ; the clamp above threw and took the whole of settings-load with it.
        (write-setting 'chart-src 4)
        (write-setting 'chart-secs 10)

        ; -1 is "no colour picked", which is what makes the three fall back to
        ; whatever the theme says. Writing an actual colour here would pin them
        ; and every later theme change would only move the status colours.
        (write-setting 'col-bg -1)
        (write-setting 'col-accent -1)
        (write-setting 'col-text -1)

        (write-setting 'slot-0 2)
        (write-setting 'slot-1 6)
        (write-setting 'slot-2 7)
        (write-setting 'slot-3 15)

        (looprange i 0 4 {
                (write-setting (ix '(slot-col-0 slot-col-1 slot-col-2 slot-col-3) i) -1)
                (write-setting (ix '(slot-mode-0 slot-mode-1 slot-mode-2 slot-mode-3) i) 0)
                (write-setting (ix '(slot-min-0 slot-min-1 slot-min-2 slot-min-3) i) 0.0)
                (write-setting (ix '(slot-max-0 slot-max-1 slot-max-2 slot-max-3) i) 100.0)
        })

        (write-setting 'ver-code settings-version)
        (print "Settings Restored!")
))

; Restore settings if version number does not match
; as that probably means something else is in eeprom
(if (not-eq (read-setting 'ver-code) settings-version) (restore-settings))
