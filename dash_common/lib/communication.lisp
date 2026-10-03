; Copyright Benjamin Vedder
; Copyright 2026 Stephen Bouche
;
; Parts of this file were moved here from dash35b/lib/communication.lisp;
; git blame -C records 69 lines as Benjamin Vedder's.
; SPDX-License-Identifier: GPL-3.0-or-later
(def log-active false)
(def rx-cnt-can 0)
(def crusie-new-msg-rx false)

@const-start

(defun proc-sid (id data) {
        ; Any of these means dash_esc is alive, watched by standalone-thread
        (if (or (and (>= id 20) (<= id 27)) (= id 30) (= id 31))
            (setq dash-esc-last (systime))
        )

        (cond
            ((= id 20) {
                    ; Using SOC from BMS when available
                    (if (and (not battery-a-connected) (not battery-b-connected))
                        (def stats-battery-soc (/ (bufget-i16 data 0) 1000.0))
                    )
                    (def stats-duty (/ (bufget-i16 data 2) 1000.0))

                    ; Override speed if configured to use GPS speed
                    (if config-gnss-use-speed
                        (def stats-kmh (gnss-speed))
                        (def stats-kmh (/ (bufget-i16 data 4) 10.0))
                    )

                    (def stats-kw (/ (bufget-i16 data 6) 100.0))

                    (def stats-updated true)
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 21) {
                    (def stats-temp-battery (/ (bufget-i16 data 0) 10.0))
                    (def stats-temp-esc (/ (bufget-i16 data 2) 10.0))
                    (def stats-temp-motor (/ (bufget-i16 data 4) 10.0))
                    (def stats-angle-pitch (/ (bufget-i16 data 6) 100.0))
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 22) {
                    (def stats-wh (/ (bufget-u16 data 0) 10.0))
                    (def stats-wh-chg (/ (bufget-u16 data 2) 10.0))
                    (def stats-km (/ (bufget-u16 data 4) 10.0))
                    (def stats-fault-code (bufget-u16 data 6))
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 23) {
                    (def stats-amps-avg (bufget-u16 data 0))
                    (def stats-amps-max (bufget-u16 data 2))
                    (def stats-amps-now (bufget-i16 data 4))
                    ; Use Ah from BMS when available
                    (if (not battery-a-connected) {
                            (def stats-battery-ah (bufget-u16 data 6))
                    })
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 24) {
                    (def stats-vin (/ (bufget-u16 data 0) 10.0))
                    (def stats-odom (/ (bufget-u32 data 2) 10.0))
                    (def cruise-control-speed (/ (bufget-u16 data 6) 10.0))
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 30) {
                    (var indicate-l (= (bufget-u8 data 0) 1))
                    (var indicate-r (= (bufget-u8 data 1) 1))
                    (def indicate-ms (bufget-u16 data 2))
                    (def highbeam-on (= (bufget-u8 data 4) 1))

                    (if (not crusie-new-msg-rx)
                        (setq cruise-control-active (eq (bufget-u8 data 5) 1))
                    )

                    ; Track when indicators activate for animation
                    (if (or
                            (and indicate-l (not indicate-l-on))
                            (and indicate-r (not indicate-r-on))
                        )
                        (def indicator-timestamp (systime))
                    )

                    (def indicate-l-on indicate-l)
                    (def indicate-r-on indicate-r)

                    ; A bike-controls node is on the bus and reporting, so the
                    ; strip shows what the signals are doing rather than what
                    ; this display asked for.
                    (setq sig-rx-last (systime))

                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 31) {
                    (def kickstand-down (= (bufget-u8 data 0) 0)) ; NOTE: Inverted
                    ;(def drive-mode (match (bufget-u8 data 1)
                            ;(0 'neutral)
                            ;(1 'drive)
                            ;(2 'reverse)
                            ;(_ {
                                    ;(print "Error: Invalid drive mode")
                                    ;'neutral
                            ;})
                    ;))
                    (def performance-mode (match (bufget-u8 data 2)
                            (0 'eco)
                            (1 'normal)
                            (2 'sport)
                            (_ {
                                    (print "Error: Invalid performance mode")
                                    'eco
                            })
                    ))

                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 35) {
                    (def stats-battery-soc (/ (bufget-i16 data 0) 1000.0))
                    (def battery-a-charging (eq (bufget-u8 data 2) 1))
                    (def battery-a-chg-time (bufget-u16 data 3))
                    (def stats-battery-ah (/ (bufget-u16 data 5) 10.0))

                    (def battery-a-connected true) ; TODO: Allow for BMS A connected to timeout
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 36) {
                    (def battery-b-soc (/ (bufget-i16 data 0) 1000.0))
                    (def battery-b-charging (eq (bufget-u8 data 2) 1))
                    (def battery-b-chg-time (bufget-u16 data 3))

                    (def battery-b-connected true) ; TODO: Allow for BMS B connected to timeout
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ; Logging state from the controller. Announced on change, so the
            ; banner reflects what actually happened rather than what the
            ; button asked for.
            ((= id 25) {
                    (var log-new (= (bufget-u8 data 0) 1))
                    (if (not-eq log-new log-active)
                        (notify (if log-new "Log Started" "Log Stopped")))
                    (setq log-active log-new)

                    ; The controller owns the drive mode. Follow what it reports
                    ; unless this display has just asserted one itself, so two
                    ; displays can never show different modes or fight over it.
                    ; Out-of-range values are ignored rather than displayed.
                    (var mode-new (bufget-u8 data 1))
                    (if (and (> (secs-since mode-cmd-ts) 2.0)
                             (< mode-new drive-mode-num))
                        (setq drive-mode mode-new))

                    (setq service-mode (= (bufget-u8 data 2) 1))
                    (setq motor-bad (= (bufget-u8 data 3) 1))

                    ; Bytes 4 and 5 were spare. PAS status and output go here
                    ; rather than in a frame of their own, since one byte each
                    ; is all they need.
                    (def stats-pas-flags (bufget-u16 data 4))
                    (def stats-pas-output (/ (bufget-u8 data 6) 200.0))

                    ; Byte 7 carries conditions the display cannot derive.
                    (var st (bufget-u8 data 7))
                    (def kill-sw-active (!= 0 (bitwise-and st 1)))
                    (def aux-on (!= 0 (bitwise-and st 2)))
                    (def conf-dirty (!= 0 (bitwise-and st 4)))
                    ; The controller is holding a lock of its own. Reported so
                    ; a display can say why the bike will not move even when it
                    ; is not the display that set the code.
                    (def esc-pin-holding (!= 0 (bitwise-and st 8)))
            })
            ((= id 27) {
                    ; One controller setting per frame, cycled by the
                    ; controller, so the menu fills itself without asking.
                    (var i (bufget-u8 data 0))
                    (if (< i 16) {
                            (bufset-f32 conf-vals (* i 4) (bufget-f32 data 1))
                            (bufset-u8 conf-gated i (bufget-u8 data 5))
                            (bufset-u8 conf-seen i 1)
                            (def conf-count (bufget-u8 data 6))
                    })
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 26) {
                    (def stats-pas-cadence (/ (bufget-u16 data 0) 10.0))
                    (def stats-pas-torque (/ (bufget-u16 data 2) 10.0))
                    (def stats-pas-rider-w (bufget-u16 data 4))
                    (def stats-pas-assist-w (bufget-u16 data 6))
                    (def stats-pas-rx true)
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })


            ((= id 202) {
                    (setq cruise-control-active (= (bufget-u8 data 0) 1))
                    (setq crusie-new-msg-rx true)
            })

            ((= id 203) {
                    (setq temp-ambient (/ (bufget-i16 data 0) 10.0))
                    (setq temp-ambient-rx true)
            })

            ((= id 204) {
                    (setq date-time (map (fn (x) (bufget-u8 data x)) (range (buflen data))))
                    (setq date-time-rx true)
            })
        )

        (free data)
})

(defun event-handler ()
    (loopwhile t
        (recv
            ; Not the REPL, which drops commands sent within 0.5 s
            ((event-data-rx . (? data)) (trap (eval (read data))))
            ((event-can-sid . ((? id) . (? data))) (trap (proc-sid id data)))
            (_ nil)
)))

(defun comm-tx-thread () {
        ; Let the controller report the mode it is applying before announcing
        ; one. A display that restarts mid-ride would otherwise say it is in
        ; neutral before it has heard otherwise, dropping the rider out of gear.
        ; The controller allows five seconds of silence before it considers a
        ; display gone, so this is well inside that.
        (sleep 1.0)

        (loopwhile t {
                ; Byte 2 is the walk assist request. This frame goes out every
                ; 100 ms, well inside the half second the controller allows
                ; before it expires the request.
                ; Byte 3 is the signal request bitfield: hazard, left, right,
                ; high beam, horn. Sent whether or not anything on the bus acts
                ; on it, which costs one byte of a frame that was going out
                ; anyway. The horn bit is momentary, so it is computed here
                ; rather than latched.
                ; pin-drive-mode, not drive-mode: while the lock is up this
                ; asserts neutral, whose current scale is zero, and leaves the
                ; stored mode alone so unlocking restores it.
                (can-send-sid 201 (list (pin-drive-mode) (if light-on 1 0)
                        (if (walk-requested) 1 0) (sig-byte (horn-held))
                        0 0 0 0))

                (var buf (bufcreate 8))
                (bufset-i8 buf 0 (read-setting 'whl-active))
                (bufset-i16 buf 2 (* (read-setting 'whl-start) 10.0))
                (bufset-i16 buf 4 (* (read-setting 'whl-end) 10.0))
                (bufset-i16 buf 6 (* (read-setting 'whl-kd) 10000.0))
                (can-send-sid 202 buf)

                (sleep 0.1)
        })
})

; --- PIN lock, controller side ---------------------------------------------
;
; SID 205 command 3 sets whether the controller requires a code at every power
; up, and 4 releases the current one. The requirement is stored there and the
; release is not, so a power cycle comes back locked -- which is the whole
; point of holding it on the controller rather than only here.
;
; Sent three times, 60 ms apart. This is a single frame with no
; acknowledgement, and a lost unlock leaves a rider tapping a correct code at a
; bike that will not move.
(defun pin-cmd (cmd val) {
        (var buf (bufcreate 8))
        (bufset-u8 buf 0 cmd)
        (bufset-u8 buf 1 val)
        (looprange i 0 3 {
                (can-send-sid 205 buf)
                (sleep 0.06)
        })
})

(defun pin-lock-send () (pin-cmd 3 (if settings-pin-en 1 0)))
(defun pin-unlock-send () (pin-cmd 4 0))

; Send event
; ID 0: Toggle cruise control
; ID 1: Save data, power might turn off
(defun comm-send-event (event-id) {
        (var buf (bufcreate 2))
        (bufset-u8 buf 0 event-id)
        (can-send-sid 250 buf)
})
