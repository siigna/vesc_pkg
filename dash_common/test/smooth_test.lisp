; Unit tests for smooth-step, the exponential approach behind the optional
; value smoothing on the live page. Pure arithmetic, so no display needed.
;
; Two properties matter and neither is obvious from the formula. It has to
; converge in a bounded number of refreshes, because a value that crawls
; forever means the last digit of a number never settles; and it must never
; overshoot, because a number that goes past its value and comes back reads as
; a glitch rather than as motion.
(import "stubs.lisp" 'code-stubs)
(read-eval-program code-stubs)

(import "build/common/smooth_fn.lisp" 'c-smooth)
(read-eval-program c-smooth)

(def checks 0)
(def fails 0)
(defun is (what got want) {
        (setq checks (+ checks 1))
        (if (not (eq got want)) {
                (setq fails (+ fails 1))
                (print (list 'FAIL what 'got got 'want want))
        })
})
(defun near (what got want tol) {
        (setq checks (+ checks 1))
        (if (> (abs (- got want)) tol) {
                (setq fails (+ fails 1))
                (print (list 'FAIL what 'got got 'want want))
        })
})

; Nothing shown yet: snap, whatever k says.
(is 'first-frame (smooth-step nil 42.0 0.3 0.0 100.0) 42.0)

; Off, and the two degenerate gains. k of 1 or more would overshoot or
; oscillate, so both are treated as off rather than clamped.
(is 'k-zero (smooth-step 0.0 42.0 0.0 0.0 100.0) 42.0)
(is 'k-one (smooth-step 0.0 42.0 1.0 0.0 100.0) 42.0)
(is 'k-over (smooth-step 0.0 42.0 1.4 0.0 100.0) 42.0)

; One step of a third of the way.
(near 'one-step (smooth-step 0.0 30.0 (/ 1.0 3.0) 0.0 100.0) 10.0 0.001)

; Already there.
(is 'settled (smooth-step 42.0 42.0 0.3 0.0 100.0) 42.0)

; Converges, and exactly, within a bounded number of refreshes. At 20 Hz the
; live page gets 40 of these in two seconds, so the bound is what says the
; number settles rather than drifting for the rest of the ride.
(defun steps-to (from to k lo hi) {
        (var sv from)
        (var n 0)
        (loopwhile (and (not (= sv to)) (< n 200)) {
                (setq sv (smooth-step sv to k lo hi))
                (setq n (+ n 1))
        })
        n
})
(is 'converges (< (steps-to 0.0 100.0 0.3 0.0 100.0) 30) t)
(is 'converges-down (< (steps-to 100.0 0.0 0.3 0.0 100.0) 30) t)
(is 'converges-slow-gain (< (steps-to 0.0 100.0 0.1 0.0 100.0) 90) t)
(is 'converges-negative (< (steps-to 0.0 -50.0 0.3 -100.0 100.0) 40) t)

; Never past the target, from either side, on the way in.
(defun overshoots (from to k lo hi) {
        (var sv from)
        (var bad nil)
        (looprange i 0 200 {
                (setq sv (smooth-step sv to k lo hi))
                (if (if (> to from) (> sv to) (< sv to)) (setq bad t))
        })
        bad
})
(is 'no-overshoot-up (overshoots 0.0 100.0 0.3 0.0 100.0) nil)
(is 'no-overshoot-down (overshoots 100.0 0.0 0.3 0.0 100.0) nil)
(is 'no-overshoot-high-gain (overshoots 0.0 100.0 0.9 0.0 100.0) nil)

; The snap threshold scales with the range, so a wide one settles at a coarser
; absolute distance. A cell with no range set gets the 0.05 floor instead,
; which is what keeps a small reading from snapping a visible distance.
(is 'snap-wide (smooth-step 9999.0 10000.0 0.3 0.0 10000.0) 10000.0)
(is 'snap-floor-holds (= (smooth-step 0.9 1.0 0.3 0.0 0.0) 1.0) nil)
(is 'snap-floor-snaps (smooth-step 0.99 1.0 0.3 0.0 0.0) 1.0)

; An unset range is lo = hi, which must not divide or produce a negative
; threshold that snaps nothing.
(near 'zero-range (smooth-step 0.0 10.0 0.5 0.0 0.0) 5.0 0.001)
(near 'inverted-range (smooth-step 0.0 10.0 0.5 100.0 0.0) 5.0 0.001)

(print (list 'smooth checks 'checks fails 'fails))
