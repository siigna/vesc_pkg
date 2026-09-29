; Rebuilt at runtime from the theme and the colour settings
(def color-bg 0x000000)
(def color-accent 0x00C8FF)
(def color-text 0xfbfcfc)

; The three status colours. Held here rather than written as literals at each
; use so a theme can move them: a yellow warning is unreadable on a light
; background, and a night theme wants all three dimmed rather than only the
; accent.
(def color-ok 0x00C321)
(def color-warn 0xFFD400)
(def color-crit 0xFF3030)

(def settings-slot-cols (list 0xfbfcfc 0xfbfcfc 0xfbfcfc 0xfbfcfc))

(def colors-theme-2 nil)
(def colors-speed nil)
(def colors-charging nil)
(def colors-vesc nil)
(def colors-red-icon nil)
(def colors-green-icon nil)
(def colors-blue-icon nil)
(def colors-hidden nil)
(def colors-dim-icon nil)
(def colors-white-icon nil)
(def colors-purple-icon nil)
(def colors-text-aa nil)
(def colors-slots nil)
(def colors-warn nil)
(def colors-crit nil)
(def colors-ok nil)
(def colors-ok-2 nil)
(def colors-warn-2 nil)
(def colors-crit-2 nil)
(def colors-text-sel-aa nil)
(def colors-white-aa nil)

@const-start

(defun colors-make-aa (color1 color2 num) {
        (var colors (range num))

        (looprange i 0 num {
                (setix colors i (color-mix color1 color2 (/ (to-float i) (- num 1))))
        })

        colors
})

; Towards the background rather than towards black, so this still darkens on a
; dark theme and lightens on a light one. Identical on the default theme, whose
; background is black.
(defun colors-shade (c f) (color-mix color-bg c f))

; A text ramp faded towards the background by f, where f is how far through a
; long press the finger is. At 0 it is the normal text ramp; at 1 the value
; has gone, which is what the press is about to do to it. The value being
; destroyed is its own progress bar.
(defun colors-fade-aa (f)
    (colors-make-aa color-bg (color-mix color-text color-bg (clamp01 f)) 4))

; (name bg accent text ok warn crit).
;
; Row 0 is the palette the dash shipped with, value for value, so the default
; look does not move. Index order is stored in eeprom, so only append.
;
; Night is for riding after dark: every colour is pulled down and towards red,
; which is what keeps a bright panel from destroying dark adaptation. Light is
; the only row with a pale background, and its status colours are darkened
; rather than reused -- the default yellow and green have almost no contrast
; against white.
(def theme-catalog (list
    (list "Dark"  0x000000 0x00C8FF 0xfbfcfc 0x00C321 0xFFD400 0xFF3030)
    (list "Amber" 0x000000 0xFFA000 0xfbfcfc 0x00C321 0xFFD400 0xFF3030)
    (list "Green" 0x000000 0x00E05A 0xfbfcfc 0x00C321 0xFFD400 0xFF3030)
    (list "Night" 0x000000 0xC03030 0xB07070 0x2E7D32 0xA06000 0xC01010)
    (list "Light" 0xFBFCFC 0x0067A8 0x101010 0x0A7A1C 0x9A6A00 0xC01010)
))

(def settings-theme 0)

(defun theme-row (i) (ix theme-catalog (if (< i (length theme-catalog)) i 0)))

; Theme colours, as the defaults the individual colour settings fall back to.
; A colour the rider has actually picked in VESC Tool keeps winning, because an
; unwritten eeprom cell reads -1 and setting-clamp hands back the default for
; anything below zero. That is also why resetting settings writes -1 into those
; cells rather than a colour.
(defun theme-bg () (ix (theme-row settings-theme) 1))
(defun theme-accent () (ix (theme-row settings-theme) 2))
(defun theme-text () (ix (theme-row settings-theme) 3))

; The status colours come from the theme only. Overriding them one by one is
; three more eeprom cells and a picker each, for a choice that has to stay
; legible against the background to mean anything.
(defun theme-apply-status () {
        (var row (theme-row settings-theme))
        (setq color-ok (ix row 4))
        (setq color-warn (ix row 5))
        (setq color-crit (ix row 6))
})

(defun colors-build () {
        (setq colors-theme-2 (colors-make-aa color-bg color-accent 2))
        (setq colors-speed
            (list color-bg (colors-shade color-accent 0.55) color-accent color-text))
        (setq colors-charging
            (list color-bg 0x00C321 color-accent color-text))

        (setq colors-vesc (colors-make-aa color-bg 0xF05A22 4))
        (setq colors-red-icon (colors-make-aa color-bg color-crit 4))
        (setq colors-green-icon (colors-make-aa color-bg color-ok 4))
        (setq colors-blue-icon (colors-make-aa color-bg 0x1d00e8 4))

        ; Erases an icon's footprint. Skipping the draw would leave it on screen.
        (setq colors-hidden (colors-make-aa color-bg color-bg 4))

        (setq colors-dim-icon (colors-make-aa color-bg (color-mix color-bg color-text 0.25) 4))
        (setq colors-white-icon (colors-make-aa color-bg color-text 4))
        (setq colors-purple-icon (colors-make-aa color-bg 0x9f20f1 4))

        (setq colors-text-aa (colors-make-aa color-bg color-text 4))

        (setq colors-ok (colors-make-aa color-bg color-ok 4))
        (setq colors-warn (colors-make-aa color-bg color-warn 4))
        (setq colors-crit (colors-make-aa color-bg color-crit 4))

        ; Battery bar segments are indexed2
        (setq colors-ok-2 (colors-make-aa color-bg color-ok 2))
        (setq colors-warn-2 (colors-make-aa color-bg color-warn 2))
        (setq colors-crit-2 (colors-make-aa color-bg color-crit 2))
        (setq colors-slots (map (fn (c) (colors-make-aa color-bg c 4)) settings-slot-cols))
        (setq colors-text-sel-aa (colors-make-aa color-bg 0x00FF00 4))
        (setq colors-white-aa (colors-make-aa color-bg color-text 4))
})

(if (eq (car (trap (colors-build))) 'exit-error)
    (print "colors-build failed"))

@const-end
