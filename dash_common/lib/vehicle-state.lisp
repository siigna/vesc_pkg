
(def indicate-l-on nil)
(def indicate-r-on nil)
(def indicate-ms 0)
(def indicator-timestamp 0)
(def highbeam-on false)

(def kickstand-down false)

; --- Signal requests --------------------------------------------------------
;
; What this display is asking for on the bike's own outputs, as a bitfield in
; byte 3 of SID 201. Nothing in the VESC ecosystem drives these today: a
; controller has exactly two script-drivable outputs, set-aux ports 1 and 2,
; and dash_esc uses those for the lights. This is for a second node on the bus
; that owns the switch gear and has GPIO to spare -- an rmcore, whose shipped
; demo already reads the light bit out of the same frame.
;
; So the frame goes out whether or not anything listens, which costs one byte
; of a frame that was already being sent every 100 ms, and the requests do
; nothing at all until something acts on them.
;
; Not persisted. An indicator that came back on after a power cycle would be
; both surprising and, on a road bike, worse than that.
(def sig-hazard 1)
(def sig-left 2)
(def sig-right 4)
(def sig-beam 8)
(def sig-horn 16)

(def sig-req 0)

; The horn is momentary, and a tap cannot hold anything. A press on the quick
; shade blips it for this long; a held button asserts it for as long as it is
; held, which is what the request byte carries either way.
(def sig-horn-blip-s 0.6)

; systime of the last blip. Measured with secs-since rather than compared
; against a deadline, so nothing here assumes what a systime tick is worth. A
; zero start is simply a blip that finished long ago.
(def sig-horn-ts 0)

; systime of the last SID 30, which is the frame a bike-controls node sends to
; report what the signals are actually doing. While that is recent the reported
; state is what gets displayed and the request is only a request. With no such
; node on the bus the display falls back to showing what it asked for, which is
; the only feedback there is.
(def sig-rx-last 0)
(def sig-rx-timeout 2.0)

(defun sig-reported () (< (secs-since sig-rx-last) sig-rx-timeout))

(defun sig-on (bit) (!= 0 (bitwise-and sig-req bit)))

; Hazard outranks the indicators, and the two indicators cancel each other:
; asking for both is the hazard, and a bike that lit one while the other was on
; would be lying about which way it was going.
(defun sig-toggle (bit) {
        (if (sig-on bit)
            (setq sig-req (bitwise-and sig-req (bitwise-xor bit 0xFF)))
            {
                (if (= bit sig-left)
                    (setq sig-req (bitwise-and sig-req (bitwise-xor sig-right 0xFF))))
                (if (= bit sig-right)
                    (setq sig-req (bitwise-and sig-req (bitwise-xor sig-left 0xFF))))
                (setq sig-req (bitwise-or sig-req bit))
            })
})

(defun sig-horn-blip () (setq sig-horn-ts (systime)))

(defun sig-horn-blipping () (< (secs-since sig-horn-ts) sig-horn-blip-s))

; The byte on the wire. The horn is the one bit that is not latched: it is set
; while a bound button is held or a blip is still running.
(defun sig-byte (held) {
        (var v (bitwise-and sig-req (bitwise-xor sig-horn 0xFF)))
        (if (or held (sig-horn-blipping))
            (bitwise-or v sig-horn)
            v)
})

; What the status strip should show. The reported state when a bike-controls
; node is on the bus, otherwise what this display asked for -- so the
; indicators mean something on a bike where the display is the only thing
; asking. Hazard lights both sides, which is what hazard is.
(defun sig-l-shown ()
    (if (sig-reported) indicate-l-on (or (sig-on sig-left) (sig-on sig-hazard))))

(defun sig-r-shown ()
    (if (sig-reported) indicate-r-on (or (sig-on sig-right) (sig-on sig-hazard))))

(defun sig-beam-shown ()
    (if (sig-reported) highbeam-on (sig-on sig-beam)))

; --- end signal requests ----------------------------------------------------
; test/run.sh extracts everything between the two markers for signal_test, so
; nothing below here can be moved above them.
(def drive-mode 1)

; systime of the last mode this display asserted itself. While that is recent
; the controller's reported mode is not followed, so a button press, the
; kickstand or charging cannot be undone by the controller echoing back a mode
; it has not been told about yet.
(def mode-cmd-ts 0)

; The controller has suspended its drive profile for servicing
(def service-mode false)

; The controller's stored motor parameters cannot describe a real motor
(def motor-bad false)

(defun mode-set (m) {
        (setq drive-mode m)
        (setq mode-cmd-ts (systime))
})
(def performance-mode 'eco) ; 'eco 'normal 'sport UNUSED!

(def cruise-control-active false)
(def cruise-control-speed 0.0)

(def battery-a-charging false)
(def battery-a-chg-time 0)
(def battery-a-connected false) ; Has received msg from BMS A

(def battery-b-soc 0.0)
(def battery-b-charging false)
(def battery-b-chg-time 0)
(def battery-b-connected false) ; Has received msg from BMS B

(def page-now 0)
(def page-num 3)

(def setting-now 0)
(def setting-num 0)

; setting-list-page1 etc are built by settings-build.

(def light-on light-on-default)
(def backlight-dim false)

; For changes per-field detection cannot see, e.g. a unit label swap.
(def view-force-static false)
(def view-force-pages false)

(def temp-ambient 0.0)
(def temp-ambient-rx false)

(def date-time nil)
(def date-time-rx false)
