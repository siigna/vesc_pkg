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

(print (list 'hit checks 'checks fails 'fails))
