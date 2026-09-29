
; ID 20
(def stats-battery-soc 0)
(def stats-duty 0)
(def stats-kmh 0)
(def stats-kw 0)
; ID 21
(def stats-temp-battery 0)
(def stats-temp-esc 0)
(def stats-temp-motor 0)
(def stats-angle-pitch 0)
; ID22
(def stats-wh 0)
(def stats-wh-chg 0)
(def stats-km 0)
(def stats-fault-code 0)
; ID23
(def stats-amps-avg 0)
(def stats-amps-max 0)
(def stats-amps-now 0)
(def stats-battery-ah 0)
; ID24
(def stats-vin 0)
(def stats-odom 0.0)

; Computed Statistics (resettable)
(def stats-reset-now nil)
(def stats-kmh-max 0)
(def stats-kw-max 0)
(def stats-temp-battery-max 0)
(def stats-temp-esc-max 0)
(def stats-temp-motor-max 0)
(def stats-amps-now-max 0)
(def stats-amps-now-min 0)
(def stats-fault-codes-observed (list))

; Lowest pack voltage seen this session. Maxima say how hard you pushed;
; the voltage floor says whether the pack could take it, which is the cheapest
; sag and pack-health indicator there is -- it tells you if you are getting
; near the controller's cutoff before it cuts.
;
; Starts at nil rather than 0 so the first reading sets it instead of the
; minimum being stuck at zero forever.
(def stats-vin-min nil)

; Computed Statistics (non-resettable)
(def stats-active-timer 0)
(def stats-active-timestamp nil)

; Wall-clock time since the session started, against stats-active-timer's
; moving time. Shown side by side, the gap between them is time spent
; stopped, which is what a rider actually wants to know.
(def stats-elapsed-timer 0)
(def stats-elapsed-timestamp nil)

@const-start

(defun stats-reset-max () {
        (def stats-reset-now true)
})

(defunret list-find (haystack needle) {
        (var i 0)
        (loopwhile (< i (length haystack)) {
                (if (eq needle (ix haystack i)) (return i))
                (setq i (+ i 1))
        })
        (return nil)
})

(defun stats-thread () {
        (loopwhile t {
                (sleep 0.05)
                (if stats-reset-now {
                        (def stats-kmh-max 0)
                        (def stats-kw-max 0)
                        (def stats-temp-battery-max 0)
                        (def stats-temp-esc-max 0)
                        (def stats-temp-motor-max 0)
                        (def stats-amps-now-max 0)
                        (def stats-amps-now-min 0)
                        (def stats-vin-min nil)
                        (def stats-active-timer 0)
                        (def stats-active-timestamp nil)
                        (def stats-elapsed-timer 0)
                        (def stats-elapsed-timestamp nil)
                        (def stats-reset-now nil)
                })

                ; Max Speed
                (if (> stats-kmh stats-kmh-max) (def stats-kmh-max stats-kmh))

                ; Max KW
                (if (> stats-kw stats-kw-max) (def stats-kw-max stats-kw))

                ; Max Temps
                (if (> stats-temp-battery stats-temp-battery-max) (setq stats-temp-battery-max stats-temp-battery))
                (if (> stats-temp-esc stats-temp-esc-max) (setq stats-temp-esc-max stats-temp-esc))
                (if (> stats-temp-motor stats-temp-motor-max) (def stats-temp-motor-max stats-temp-motor))

                ; Max Amps Observed
                (if (< stats-amps-now-max stats-amps-now) (def stats-amps-now-max stats-amps-now))

                ; Min Amps Observed (Max Regen Amps)
                (if (> stats-amps-now-min stats-amps-now) (def stats-amps-now-min stats-amps-now))

                ; Fault Codes
                (if (> stats-fault-code 0) {
                        ; Check if fault-code is already in list
                        (if (not (list-find stats-fault-codes-observed stats-fault-code)) {
                                (setq stats-fault-codes-observed (append stats-fault-codes-observed (list stats-fault-code)))
                        })
                })

                ; Minimum pack voltage. Ignore zero, which is what the
                ; fields read before the first frame arrives.
                (if (> stats-vin 0.0)
                    (if (or (not stats-vin-min) (< stats-vin stats-vin-min))
                        (def stats-vin-min stats-vin)))

                ; Elapsed timer runs from the first frame onward, whether or
                ; not the vehicle is moving.
                (if (not stats-elapsed-timestamp) (def stats-elapsed-timestamp (systime)))

                ; Usage Timer - Start
                (if (and (> stats-kmh 0.0) (not stats-active-timestamp)) (def stats-active-timestamp (systime)))

                ; Usage Timer - End
                (if (and (= stats-kmh 0.0) (not-eq stats-active-timestamp nil)) {
                        (var millis-active (- (systime) stats-active-timestamp))
                        (setq stats-active-timer (+ stats-active-timer millis-active))
                        (def stats-active-timestamp nil)
                })
        })
})

; Both timers accumulate only when their interval closes, so a live reader has
; to add the interval still in progress or the number sits still while you
; ride.
(defun stats-moving-secs ()
    (/ (+ stats-active-timer
          (if stats-active-timestamp (- (systime) stats-active-timestamp) 0))
       1000.0))

(defun stats-elapsed-secs ()
    (/ (+ stats-elapsed-timer
          (if stats-elapsed-timestamp (- (systime) stats-elapsed-timestamp) 0))
       1000.0))

; Average over moving time, not elapsed: an average that counts time at the
; lights tells you about the lights.
(defun stats-avg-kmh () {
        (var t (stats-moving-secs))
        (if (> t 1.0) (/ stats-km (/ t 3600.0)) 0.0)
})

; Live page sources, (label unit). Stored by index, so only append.
(def slot-catalog '(
        ("Speed"      "")
        ("Battery"    "%")
        ("Motor Amps" "A")
        ("Batt Amps"  "A")
        ("Power"      "kW")
        ("Voltage"    "V")
        ("Motor Temp" "")
        ("ESC Temp"   "")
        ("Pack Temp"  "")
        ("Duty"       "%")
        ("Trip"       "")
        ("Odometer"   "")
        ("Energy"     "Wh")
        ("Regen"      "Wh")
        ("Amp Hours"  "Ah")
        ("Peak Amps"  "A")
        ("Top Speed"  "")
        ("Pitch"      "deg")
        ("Min Pack"   "V")
        ("Avg Speed"  "")
        ("Moving"     "")
        ("Elapsed"    "")
        ("SOC Volts"  "%")
        ("SOC Count"  "%")
        ("SOC Model"  "%")
))

(defun slot-value (i)
    (cond
        ((= i 0) (u-speed stats-kmh))
        ((= i 1) (* 100.0 stats-battery-soc))
        ((= i 2) stats-amps-now)
        ((= i 3) (if (= stats-vin 0) 0.0 (/ (* stats-kw 1000.0) stats-vin)))
        ((= i 4) stats-kw)
        ((= i 5) stats-vin)
        ((= i 6) (u-temp stats-temp-motor))
        ((= i 7) (u-temp stats-temp-esc))
        ((= i 8) (u-temp stats-temp-battery))
        ((= i 9) (* stats-duty 100.0))
        ((= i 10) (u-dist stats-km))
        ((= i 11) (u-dist stats-odom))
        ((= i 12) stats-wh)
        ((= i 13) stats-wh-chg)
        ((= i 14) stats-battery-ah)
        ((= i 15) stats-amps-max)
        ((= i 16) (u-speed stats-kmh-max))
        ((= i 17) stats-angle-pitch)
        ((= i 18) (if stats-vin-min stats-vin-min 0.0))
        ((= i 19) (u-speed (stats-avg-kmh)))
        ((= i 20) (stats-moving-secs))
        ((= i 21) (stats-elapsed-secs))
        ; The three state-of-charge estimates, so they can be compared before
        ; config-soc-source is pointed at one of them.
        ((= i 22) (* 100.0 (batt-voltage-soc stats-vin)))
        ((= i 23) (* 100.0 (batt-coulomb-soc stats-battery-ah)))
        (t (* 100.0 (batt-model-soc)))
))

; Units that follow the unit setting rather than being fixed.
(defun slot-unit (i)
    (cond
        ((or (= i 0) (= i 16) (= i 19)) (u-speed-str))
        ((or (= i 6) (= i 7) (= i 8)) (u-temp-str))
        ((or (= i 10) (= i 11)) (u-dist-str))
        (t (ix (ix slot-catalog i) 1))
))

(defun slot-label (i) (ix (ix slot-catalog i) 0))

; The two timers are drawn as h:mm:ss rather than a number of seconds.
(defun slot-is-time (i) (or (= i 20) (= i 21)))

; m:ss under an hour, h:mm over it. Full h:mm:ss does not fit the value
; column -- the grid sizes it for a number, and seven characters overflow.
(defun slot-time-str (secs) {
        (var s (to-i secs))
        (if (< s 3600)
            (str-merge (str-from-n (/ s 60) "%d:") (str-from-n (mod s 60) "%02d"))
            (str-merge (str-from-n (/ s 3600) "%d:")
                       (str-from-n (mod (/ s 60) 60) "%02d")))
})

; One decimal for the small numbers, none for the ones that get large.
(defun slot-fmt (i)
    (if (or (= i 1) (= i 5) (= i 9) (= i 12) (= i 13) (= i 15)
            (= i 2) (= i 3) (= i 6) (= i 7) (= i 8)
            (= i 22) (= i 23) (= i 24))
        "%.0f" "%.1f"))
