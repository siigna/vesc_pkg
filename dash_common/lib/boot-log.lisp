; The board's own log, for the pages to draw.
;
; The counterpart of dash_common_lua/lib/boot_log.lua, which came first: this
; is the Lua dash's feature brought back so both dashes have it.
;
; commands_printf sends a COMM_PRINT packet out whichever port last spoke to
; the board, so every line produced during bring-up -- which panel came up,
; whether touch answered, whether the radio attached -- went nowhere. On a
; board with the console off it could not go anywhere at all. The firmware
; keeps the last lines in a ring now; this reads them.

; Lines the dash adds itself, oldest first. Kept separately from the
; firmware's ring so a step can be recorded before anything is listening, and
; so they survive the ring wrapping during a noisy radio attach.
(def boot-log-own nil)
(def boot-log-own-max 16)

; How many of the firmware's lines to ask for.
(def boot-log-max 48)

@const-start

; Record a bring-up step. Also printed, so it reaches a listening tool and the
; firmware ring, where it interleaves with the ESP-IDF lines in the right
; order.
(defun boot-log-step (txt) {
        (var line (str-merge "[" (str-from-n (/ (systime) 1000.0) "%7.3f") "] " txt))

        (setq boot-log-own (append boot-log-own (list line)))
        (if (> (length boot-log-own) boot-log-own-max)
            (setq boot-log-own (cdr boot-log-own)))

        (print txt)
        line
})

; Whether touch is answering, as a line rather than a number: the tallies on
; their own need explaining every time they are read.
;
; A panel that has stopped answering shows a climbing error count against a
; frozen ok count, which is the difference between a wedged I2C bus and a
; rider who has not touched the screen. Nothing else on the dash tells those
; apart.
(defun boot-log-touch-line () {
        (var st (match (trap (touch-stats))
                ((exit-ok (? v)) v)
                (_ nil)
        ))

        (if (eq st nil) "touch: no stats binding" {
                (var ok (ix st 0))
                (var err (ix st 1))
                (var last (ix st 2))

                (if (= err 0)
                    (str-merge "touch: bus ok (" (str-from-n ok "%d") ")")
                    (str-merge "touch: " (str-from-n ok "%d") " ok, "
                               (str-from-n err "%d") " FAILED, last err "
                               (str-from-n last "%d")))
        })
})

; Everything to show, oldest first: the firmware's ring, which starts earlier,
; then the dash's own steps, then the live line.
;
; A dropped count is said rather than hidden. A log that silently loses its
; beginning is worse than one that admits it.
(defun boot-log-lines () {
        (var ring (match (trap (log-lines boot-log-max))
                ((exit-ok (? v)) v)
                (_ nil)
        ))

        (var dropped (match (trap (log-dropped))
                ((exit-ok (? v)) v)
                (_ 0)
        ))

        (var out ring)

        (if (> dropped 0)
            (setq out (cons (str-merge "... " (str-from-n dropped "%d")
                                       " earlier lines dropped") out)))

        (append (append out boot-log-own) (list (boot-log-touch-line)))
})

@const-end
