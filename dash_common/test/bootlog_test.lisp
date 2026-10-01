; Unit tests for boot-log-touch-line in lib/boot-log.lisp.
;
; The point is not the formatting for its own sake: the Lua dash reports the
; same three numbers in the same words, so a reading from either board says
; the same thing, and these literals are what hold the two together. The Lua
; side asserts the identical strings in test/boot_log_test.lua.
;
; Three numbers because there are three ways touch can be useless on a board
; where it is the sole input, and they need different fixes: the bus not
; answering, the panel answering but never reporting a finger, and a finger
; reported while the regions or the dispatch are wrong.
(import "stubs.lisp" 'code-stubs)
(read-eval-program code-stubs)

; The dash's own counters, which the line reports alongside the firmware's.
(def touch-reads 12)
(def touch-fires 5)

; Extracted from the real lib/boot-log.lisp by run.sh rather than copied, so
; the test cannot drift from what ships. Copying it by hand is exactly how a
; test ends up agreeing with itself.
(import "build/common/bootlog_fn.lisp" 'c-bl)
(read-eval-program c-bl)

(def checks 0)
(def fails 0)
(defun is-str (what got want) {
        (setq checks (+ checks 1))
        (if (not (eq got want)) {
                (setq fails (+ fails 1))
                (print (list 'FAIL what 'got got 'want want))
        })
})

; A healthy bus. The counters are what separate "nobody has touched it" from
; "it is not reporting".
(defun touch-stats () (list 4321 0 0))
(is-str 'healthy (boot-log-touch-line)
    "touch: bus ok (4321), 12 fingers, 5 actions")

; A bus that has started failing. The error count and the last error are what
; say a controller fell off rather than a finger being absent.
(defun touch-stats () (list 100 7 -1))
(is-str 'failing (boot-log-touch-line)
    "touch: 100 ok, 7 FAILED, last err -1, 12 fingers")

; No binding at all, which is a firmware without the counters rather than a
; panel without a finger. Said rather than guessed at.
(defun touch-stats () (raise 'no-such-extension))
(is-str 'no-binding (boot-log-touch-line) "touch: no stats binding")

(print (list 'bootlog checks 'checks fails 'fails))
(if (> fails 0) (exit-error 1))
