; Copyright Benjamin Vedder
; Copyright 2026 Stephen Bouche
;
; Parts of this file were moved here from dash35b/lib/statistics.lisp;
; git blame -C records 3 lines as Benjamin Vedder's.
; SPDX-License-Identifier: GPL-3.0-or-later
; Unit tests for live-cell-hit, the coordinate-to-cell map behind the long
; press that sends a live cell to the chart page. Pure arithmetic, so no
; display and no board package needed.
;
; The strong property is the round trip: the forward geometry that draws a cell
; (live-cell-x / live-cell-y) and the inverse that hits it come from the same
; three numbers, so every cell the view draws must map back to itself. Both are
; extracted from the real view_pages by run.sh, which is what keeps this from
; drifting from what ships, and the block is re-evaluated per board profile
; because every derived constant in it is computed at load.
(import "stubs.lisp" 'code-stubs)
(read-eval-program code-stubs)

(import "build/common/live_geom.lisp" 'c-geom)
(import "build/common/shade_geom.lisp" 'c-shade)

; list-find lives in statistics.lisp, which this test does not load: it wants
; the two geometry blocks and nothing else.
(defunret list-find (haystack needle) {
        (var i 0)
        (loopwhile (< i (length haystack)) {
                (if (eq needle (ix haystack i)) (return i))
                (setq i (+ i 1))
        })
        (return nil)
})

(def checks 0)
(def fails 0)
(defun is (what got want) {
        (setq checks (+ checks 1))
        (if (not (eq got want)) {
                (setq fails (+ fails 1))
                (print (list 'FAIL what 'got got 'want want))
        })
})

; The page band, which normally comes from the board config and view_static.
(def page-x 0)
(def page-y 100)
(def page-h 144)
(def page-w 480)
(def page-cols 2)

(defun profile (w cols) {
        (setq page-w w)
        (setq page-cols cols)
        (read-eval-program c-geom)
})

(defun check-profile (name) {
        ; Every cell centre hits its own cell.
        (looprange i 0 4 {
                (var cx (+ (live-cell-x i) (/ (- live-cell-w 16) 2)))
                (var cy (+ (live-cell-y i) (/ live-cell-h 2)))
                (is (list name 'centre i) (live-cell-hit cx cy) i)
        })

        ; Corners of the grid.
        (is (list name 'top-left) (live-cell-hit page-x page-y) 0)
        (is (list name 'last-px)
            (live-cell-hit (- (+ page-x (* live-cols live-cell-w)) 1)
                           (- (+ page-y (* live-rows live-cell-h)) 1))
            (- 4 1))

        ; Outside, on all four sides. Left and above matter most: integer
        ; division truncates towards zero, so without the explicit edge tests
        ; both would land in cell 0.
        (is (list name 'left-of) (live-cell-hit (- page-x 1) page-y) nil)
        (is (list name 'above) (live-cell-hit page-x (- page-y 1)) nil)
        (is (list name 'right-of)
            (live-cell-hit (+ page-x (* live-cols live-cell-w)) page-y) nil)
        (is (list name 'below)
            (live-cell-hit page-x (+ page-y (* live-rows live-cell-h))) nil)

        ; The nav strip sits 4 px past the last row, so a press there is below
        ; the grid and must not chart anything.
        (is (list name 'nav-strip)
            (live-cell-hit page-x (+ page-y page-h 6)) nil)

        ; No coordinate inside the band may map outside 0..3. Sampled on a
        ; coprime stride rather than every pixel, which keeps the sweep off the
        ; column boundaries it would otherwise line up with.
        (var y page-y)
        (loopwhile (< y (+ page-y page-h)) {
                (var x page-x)
                (loopwhile (< x (+ page-x page-w)) {
                        (var c (live-cell-hit x y))
                        (if (and c (or (< c 0) (> c 3)))
                            (is (list name 'in-range x y) c 'zero-to-three))
                        (setq x (+ x 7))
                })
                (setq y (+ y 11))
        })
})

; 480x480 panel: 2 columns, so 2x2.
(profile 480 2)
(is 's3-cols live-cols 2)
(is 's3-rows live-rows 2)
(check-profile 's3)

; 800x480 panel: 4 columns in one row. A 2x2 would overflow the nav strip on
; the shorter page area a wide panel leaves.
(profile 800 4)
(is 'p4-cols live-cols 4)
(is 'p4-rows live-rows 1)
(check-profile 'p4)

; A profile nothing ships, to show the map follows the constants rather than
; either shipped grid.
(profile 600 2)
(check-profile 'odd)

; --- Quick shade grid -----------------------------------------------------
;
; Same property, over the whole panel above the nav strip rather than over the
; page area. Six buttons where the touch layer reports two regions, so a press
; is resolved by position and the map has to be right for every pixel of it.
(defun shade-profile (w navy) {
        (setq disp-w w)
        (setq nav-y navy)
        (read-eval-program c-shade)
})

(defun check-shade (name) {
        (looprange i 0 (* shade-cols shade-rows) {
                (var cx (+ (shade-cell-x i) (/ shade-cell-w 2)))
                (var cy (+ (shade-cell-y i) (/ shade-cell-h 2)))
                (is (list name 'centre i) (shade-cell-hit cx cy) i)
        })
        (is (list name 'origin) (shade-cell-hit 0 0) 0)
        (is (list name 'last-px)
            (shade-cell-hit (- (* shade-cols shade-cell-w) 1)
                            (- (* shade-rows shade-cell-h) 1))
            (- (* shade-cols shade-rows) 1))
        (is (list name 'left-of) (shade-cell-hit -1 0) nil)
        (is (list name 'above) (shade-cell-hit 0 -1) nil)
        (is (list name 'right-of) (shade-cell-hit (* shade-cols shade-cell-w) 0) nil)
        ; The nav strip is below the last row, and a press there has to fall
        ; through to the region actions or there is no way off the shade.
        (is (list name 'nav-strip) (shade-cell-hit 0 nav-y) nil)

        ; Nothing in the grid may map outside 0..5, and every button has to be
        ; reachable: a column of zero width would pass the centre test above
        ; while being untappable.
        (var seen nil)
        (var y 0)
        (loopwhile (< y (* shade-rows shade-cell-h)) {
                (var x 0)
                (loopwhile (< x (* shade-cols shade-cell-w)) {
                        (var c (shade-cell-hit x y))
                        (if (and c (or (< c 0) (>= c (* shade-cols shade-rows))))
                            (is (list name 'in-range x y) c 'zero-to-five))
                        (if (and c (not (list-find seen c))) (setq seen (cons c seen)))
                        (setq x (+ x 5))
                })
                (setq y (+ y 7))
        })
        (is (list name 'all-reachable) (length seen) (* shade-cols shade-rows))
})

(def disp-w 480)
(def nav-y 450)
(shade-profile 480 450)
(check-shade 's3)
(shade-profile 800 430)
(check-shade 'p4)

(print (list 'hit checks 'checks fails 'fails))
