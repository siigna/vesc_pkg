// Log analysis for the VESC Tool mobile UI.
//
// The desktop UI has a full log analysis page (pages/pageloganalysis.cpp) but it
// is built on Qt Widgets, so it is unreachable in the QML mobile build. This
// ships the same idea as a VESC package: VESC Tool pulls the QML off the device
// and instantiates it as a tab, so it works with the stock app.
//
// Logs are read straight off the device over whatever transport is already
// connected (BLE/USB/WiFi) using Commands::fileBlockList / fileBlockRead, both
// of which are already Q_INVOKABLE.

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.3
import Vedder.vesc.utility 1.0
import Vedder.vesc.commands 1.0

Item {
    id: root
    anchors.fill: parent

    property Commands mCommands: VescIf.commands()

    // Follow the app theme instead of assuming a dark one
    readonly property string bgColor:   Utility.getAppHexColor("normalBackground")
    readonly property string gridColor: Utility.getAppHexColor("lightestBackground")

    // The page sits on whatever is behind it, so paint our own base
    Rectangle {
        anchors.fill: parent
        color: bgColor
        z: -1
    }

    // Emitted whenever the viewport or cursor moves; every chart listens.
    signal repaintCharts()

    // ── Loaded log ───────────────────────────────────────────────────────────
    property var  logData: ({})      // key -> array of numbers (NaN for gaps)
    property var  logMeta: ({})      // key -> { name, unit, precision }
    property string timeKey: ""
    property var  activePanels: []   // [{ title, keys: [...] }]
    property int  sampleCount: 0

    property real viewT0: 0
    property real viewT1: 0
    property int  cursorIdx: -1

    property string loadedName: ""
    property string browsePath: "/"
    property bool   busy: false
    property string status: ""
    property string armedName: ""

    readonly property var colors: [
        "#58a6ff", "#f78166", "#56d364", "#d2a8ff",
        "#ffa657", "#79c0ff", "#ff7b72", "#a5f3fc"
    ]

    // Panel groupings. Keys absent from the log are dropped, and so are
    // channels that never read anything but zero (an unconnected sensor).
    readonly property var panelDefs: [
        { title: "Speed",         keys: ["kmh_vesc", "gnss_h_vel"] },
        { title: "Motor",         keys: ["RPM", "Duty"] },
        { title: "Current",       keys: ["Current", "Current In"] },
        { title: "Voltage",       keys: ["Input Voltage"] },
        { title: "Temperature",   keys: ["Temp Fet", "Temp Motor", "Temp Batt"] },
        { title: "Battery",       keys: ["Batt", "cnt_wh", "cnt_ah"] },
        { title: "Trip",          keys: ["trip_vesc", "trip_vesc_abs"] },
        { title: "Elevation",     keys: ["gnss_alt"] },
        { title: "IMU",           keys: ["roll", "pitch", "yaw"] },
        { title: "FOC Currents",  keys: ["iq", "id", "iq-set", "id-set"] },
        { title: "FOC Voltages",  keys: ["vq", "vd"] },
        { title: "Aux",           keys: ["ADC1", "ADC2", "Power Factor", "fault"] }
    ]

    // ── Helpers ──────────────────────────────────────────────────────────────

    // fileBlockRead hands QML a QByteArray, which arrives as an ArrayBuffer.
    // Everything below works on the bytes directly: converting half a megabyte
    // to a JS string and then split()/parseFloat-ing it takes minutes in the
    // QML engine, which is indistinguishable from a hang on a phone.
    property string convertNote: ""

    function asBytes(b) {
        convertNote = ""
        if (typeof b === "string") {
            // Some builds hand over a string; re-encode so one path follows
            var u = new Uint8Array(b.length)
            for (var i = 0; i < b.length; i++) {
                u[i] = b.charCodeAt(i) & 0xff
            }
            convertNote = "string " + b.length + "B"
            return u
        }
        try {
            var v = new Uint8Array(b)
            convertNote = "bytes " + v.length + "B"
            return v
        } catch (e) {
            convertNote = "not a byte array: " + e
            return null
        }
    }

    // Decimal parse straight out of the byte range, avoiding a substring and a
    // parseFloat per field. The logs hold plain decimals, no exponents.
    function numAt(u8, a, b) {
        if (a >= b) {
            return NaN
        }
        var i = a, neg = false
        if (u8[i] === 45) { neg = true; i++ }
        else if (u8[i] === 43) { i++ }

        var val = 0, seen = false, c
        while (i < b) {
            c = u8[i]
            if (c < 48 || c > 57) break
            val = val * 10 + (c - 48)
            seen = true
            i++
        }
        if (i < b && u8[i] === 46) {
            i++
            var scale = 0.1
            while (i < b) {
                c = u8[i]
                if (c < 48 || c > 57) break
                val += (c - 48) * scale
                scale *= 0.1
                seen = true
                i++
            }
        }
        if (!seen) {
            return NaN
        }
        return neg ? -val : val
    }

    function bytesToStr(u8, a, b) {
        var out = ""
        for (var i = a; i < b; i++) {
            out += String.fromCharCode(u8[i])
        }
        return out
    }

    // BleUartDummy (builds without bluetooth) has no isConnected(), and the
    // port name is a translated string, so try the direct call first.
    function connectionKind() {
        try {
            var ble = VescIf.bleDevice()
            if (ble && ble.isConnected && ble.isConnected()) {
                return "ble"
            }
        } catch (e) {
        }

        var n = VescIf.getConnectedPortName()
        if (n.indexOf("BLE") >= 0) return "ble"
        if (n.indexOf("TCP") >= 0 || n.indexOf("UDP") >= 0) return "net"
        if (n.indexOf("serial") >= 0) return "usb"
        if (n.indexOf("CAN") >= 0) return "can"
        return "other"
    }

    // Most rows are sparse (the device writes a field only when it updates),
    // so read the most recent value at or before the cursor.
    function valueAt(key, idx) {
        var arr = logData[key]
        if (!arr || idx < 0) {
            return NaN
        }
        var lo = Math.max(0, idx - 2000)
        for (var i = Math.min(idx, arr.length - 1); i >= lo; i--) {
            if (isFinite(arr[i])) {
                return arr[i]
            }
        }
        return NaN
    }

    function hasSignal(arr) {
        if (!arr) {
            return false
        }
        var seen = false, mn = Infinity, mx = -Infinity
        for (var i = 0; i < arr.length; i++) {
            var v = arr[i]
            if (!isFinite(v)) {
                continue
            }
            seen = true
            if (v < mn) mn = v
            if (v > mx) mx = v
        }
        return seen && !(mn === 0 && mx === 0)
    }

    function firstFinite(arr) {
        for (var i = 0; i < arr.length; i++) {
            if (isFinite(arr[i])) return arr[i]
        }
        return NaN
    }

    function lastFinite(arr) {
        for (var i = arr.length - 1; i >= 0; i--) {
            if (isFinite(arr[i])) return arr[i]
        }
        return NaN
    }

    function loBound(arr, val) {
        var lo = 0, hi = arr.length
        while (lo < hi) {
            var m = (lo + hi) >> 1
            if (arr[m] < val) lo = m + 1; else hi = m
        }
        return lo
    }

    function fmtDur(s) {
        if (!isFinite(s)) return "-"
        var h = Math.floor(s / 3600)
        var m = Math.floor((s % 3600) / 60)
        var sec = Math.floor(s % 60)
        if (h > 0) return h + "h " + m + "m"
        if (m > 0) return m + "m " + sec + "s"
        return s.toFixed(1) + "s"
    }

    function fmtSize(b) {
        if (b > 1048576) return (b / 1048576).toFixed(1) + " MB"
        if (b > 1024) return Math.round(b / 1024) + " KB"
        return b + " B"
    }

    // ── VESC CSV parsing ─────────────────────────────────────────────────────
    // Header row is ';'-separated fields of key:name:unit:precision:rel:isTime.
    // Every following row is data. The first one is often sparse (only the
    // timestamp is populated) but in a log that stopped immediately it is the
    // only row there is, so it must not be skipped.
    property string parseError: ""

    // Single pass over the bytes: locate each row, then each ';' field within
    // it, and parse the number in place. No intermediate strings, no splits.
    function parseLog(raw) {
        parseError = ""

        var u8 = asBytes(raw)
        if (!u8 || u8.length === 0) {
            parseError = "nothing was read from the device"
            return false
        }

        // Header is the first line and is small, so a string is fine here
        var hdrEnd = 0
        while (hdrEnd < u8.length && u8[hdrEnd] !== 10) {
            hdrEnd++
        }
        if (hdrEnd >= u8.length) {
            parseError = "file has no data rows"
            return false
        }
        var hdrStr = bytesToStr(u8, 0, hdrEnd).replace("\r", "")

        var keys = [], meta = {}, tKey = ""
        var parts = hdrStr.split(";")
        for (var i = 0; i < parts.length; i++) {
            var c = parts[i].split(":")
            if (!c[0]) {
                continue
            }
            keys.push(c[0])
            meta[c[0]] = {
                name: c[1] ? c[1] : c[0],
                unit: c[2] ? c[2] : "",
                precision: parseInt(c[3]) || 2
            }
            // Logs carry two timestamp fields: t_day on every row, and
            // t_day_pos only when there is a GNSS fix. Take the first.
            if (c[5] === "1" && tKey === "") {
                tKey = c[0]
            }
        }
        if (keys.length === 0) {
            parseError = "header has no fields - not a VESC log"
            return false
        }
        if (tKey === "") {
            parseError = "header has no timestamp field - not a VESC log"
            return false
        }

        var nf = keys.length
        var ti = keys.indexOf(tKey)

        // Rough row estimate so the arrays rarely need to grow
        var cols = []
        for (i = 0; i < nf; i++) {
            cols.push([])
        }

        var pos = hdrEnd + 1
        var n = u8.length
        var rows = 0

        while (pos < n) {
            // Row extent
            var eol = pos
            while (eol < n && u8[eol] !== 10) {
                eol++
            }
            var rowEnd = eol
            if (rowEnd > pos && u8[rowEnd - 1] === 13) {
                rowEnd--
            }

            if (rowEnd > pos) {
                // Walk the fields of this row
                var f = 0, fs = pos, k
                for (k = pos; k <= rowEnd; k++) {
                    if (k === rowEnd || u8[k] === 59) {
                        if (f < nf) {
                            cols[f].push(numAt(u8, fs, k))
                        }
                        f++
                        fs = k + 1
                    }
                }
                // Short rows happen when the log is cut off mid-write
                for (; f < nf; f++) {
                    cols[f].push(NaN)
                }
                rows++
            }
            pos = eol + 1
        }

        if (rows === 0) {
            parseError = "file has no data rows"
            return false
        }

        // Only rows carrying a timestamp are usable on a time axis
        var tcol = cols[ti]
        var keep = []
        for (i = 0; i < tcol.length; i++) {
            if (isFinite(tcol[i])) {
                keep.push(i)
            }
        }
        if (keep.length < 2) {
            parseError = "only " + keep.length + " timestamped sample" +
                         (keep.length === 1 ? "" : "s") +
                         " - the log stopped before recording anything"
            return false
        }

        var data = {}
        var compact = keep.length !== tcol.length
        for (var ci = 0; ci < nf; ci++) {
            if (!compact) {
                data[keys[ci]] = cols[ci]
            } else {
                var a = new Array(keep.length)
                for (i = 0; i < keep.length; i++) {
                    a[i] = cols[ci][keep[i]]
                }
                data[keys[ci]] = a
            }
        }

        cleanGps(data, tKey)

        logData = data
        logMeta = meta
        timeKey = tKey
        sampleCount = keep.length

        // Keep only panels with at least one channel carrying real data
        var ap = []
        for (i = 0; i < panelDefs.length; i++) {
            var def = panelDefs[i]
            var use = []
            for (k = 0; k < def.keys.length; k++) {
                var key = def.keys[k]
                if (data.hasOwnProperty(key) && hasSignal(data[key])) {
                    use.push(key)
                }
            }
            if (use.length > 0) {
                ap.push({ title: def.title, keys: use })
            }
        }
        activePanels = ap

        var t = data[tKey]
        viewT0 = t[0]
        viewT1 = t[t.length - 1]
        cursorIdx = -1
        return true
    }

    // These logs contain occasional single-character corruption (a negative
    // h_acc, a dropped digit in a longitude) which passes every accuracy check.
    // Drop samples the receiver flagged, plus physically impossible jumps.
    function cleanGps(data, tKey) {
        var t = data[tKey]
        var targets = ["gnss_h_vel", "gnss_lat", "gnss_lon", "gnss_alt"].filter(function (k) {
            return data.hasOwnProperty(k)
        })
        if (targets.length === 0) {
            return
        }

        // A missing h_acc is not evidence of a bad fix: fields are only written
        // when they update, so many rows carry a value with no accuracy beside it.
        if (data.hasOwnProperty("gnss_h_acc")) {
            var hacc = data["gnss_h_acc"]
            for (var i = 0; i < hacc.length; i++) {
                var a = hacc[i]
                if (isFinite(a) && (a <= 0 || a > 100)) {
                    for (var k = 0; k < targets.length; k++) {
                        data[targets[k]][i] = NaN
                    }
                }
            }
        }

        // Over 15 m/s^2 since the last valid fix is receiver noise
        if (data.hasOwnProperty("gnss_h_vel")) {
            var v = data["gnss_h_vel"]
            var prev = -1
            for (i = 0; i < v.length; i++) {
                if (!isFinite(v[i])) {
                    continue
                }
                if (prev >= 0) {
                    var dt = t[i] - t[prev]
                    if (dt > 0 && Math.abs(v[i] - v[prev]) / 3.6 / dt > 15) {
                        v[i] = NaN
                        continue
                    }
                }
                prev = i
            }
        }
    }

    // ── Summary statistics over the visible range ────────────────────────────
    function statsRows() {
        if (!timeKey || !logData[timeKey]) {
            return []
        }
        var t = logData[timeKey]
        var iA = loBound(t, viewT0)
        var iB = Math.min(loBound(t, viewT1), t.length - 1)
        if (iB < iA) iB = iA

        var rows = [["Duration", fmtDur(t[iB] - t[iA])]]

        var spanOf = function (key) {
            var d = logData[key]
            if (!d) return NaN
            var f = NaN, l = NaN
            for (var i = iA; i <= iB; i++) {
                if (isFinite(d[i])) {
                    if (!isFinite(f)) f = d[i]
                    l = d[i]
                }
            }
            return Math.abs(l - f)
        }

        var distKey = ["trip_vesc_abs", "trip_vesc"].filter(function (k) {
            return logData.hasOwnProperty(k)
        })[0]

        var dist = NaN
        if (distKey) {
            dist = spanOf(distKey)
            rows.push(["Distance", isFinite(dist)
                ? (dist >= 1000 ? (dist / 1000).toFixed(2) + " km" : Math.round(dist) + " m")
                : "-"])
        }

        var spdKey = ["gnss_h_vel", "kmh_vesc"].filter(function (k) {
            return logData.hasOwnProperty(k) && hasSignal(logData[k])
        })[0]
        if (spdKey) {
            var mx = 0
            for (var i = iA; i <= iB; i++) {
                var v = logData[spdKey][i]
                if (isFinite(v) && v > mx) mx = v
            }
            rows.push(["Top speed", mx.toFixed(1) + " km/h"])
        }

        if (logData.hasOwnProperty("cnt_wh")) {
            var wh = spanOf("cnt_wh")
            rows.push(["Energy", isFinite(wh) ? wh.toFixed(1) + " Wh" : "-"])
            if (isFinite(dist) && dist > 100 && isFinite(wh) && wh > 0) {
                rows.push(["Efficiency", (wh / (dist / 1000)).toFixed(1) + " Wh/km"])
            }
        }

        rows.push(["Samples", (iB - iA + 1) + ""])
        return rows
    }

    // ── Viewport ─────────────────────────────────────────────────────────────
    function clampView(t0, t1) {
        var t = logData[timeKey]
        var tMin = t[0], tMax = t[t.length - 1]
        var span = Math.max(t1 - t0, (tMax - tMin) * 0.0005)
        var a = t0, b = t0 + span
        if (a < tMin) { a = tMin; b = tMin + span }
        if (b > tMax) { b = tMax; a = tMax - span }
        viewT0 = a
        viewT1 = b
        repaintCharts()
    }

    function zoomAt(factor, frac) {
        var pivot = viewT0 + frac * (viewT1 - viewT0)
        var span = (viewT1 - viewT0) * factor
        clampView(pivot - frac * span, pivot + (1 - frac) * span)
    }

    function resetView() {
        var t = logData[timeKey]
        cursorIdx = -1
        clampView(t[0], t[t.length - 1])
    }

    function setCursorFrac(frac) {
        var t = logData[timeKey]
        var tv = viewT0 + Math.max(0, Math.min(1, frac)) * (viewT1 - viewT0)
        cursorIdx = Math.max(0, Math.min(loBound(t, tv), t.length - 1))
        repaintCharts()
    }

    // ── Device file browsing ─────────────────────────────────────────────────
    function refreshList() {
        busy = true
        status = "Listing " + browsePath + " ..."
        // fileBlockList blocks on a QEventLoop, so let the UI paint first
        Qt.callLater(function () {
            var entries = mCommands.fileBlockList(browsePath)
            fileModel.clear()

            if (browsePath !== "/") {
                fileModel.append({ fName: "..", fIsDir: true, fSize: 0 })
            }
            for (var i = 0; i < entries.length; i++) {
                var e = entries[i]
                fileModel.append({ fName: e.name, fIsDir: e.isDir, fSize: e.size })
            }
            busy = false
            status = entries.length + " entries"
        })
    }

    function joinPath(dir, name) {
        if (dir === "/") return "/" + name
        return dir + "/" + name
    }

    function parentPath(dir) {
        var i = dir.lastIndexOf("/")
        if (i <= 0) return "/"
        return dir.substring(0, i)
    }

    // Non-printable bytes make a useless diagnostic; show them as dots.
    function snippet(text, n) {
        var out = ""
        for (var i = 0; i < Math.min(n, text.length); i++) {
            var c = text.charCodeAt(i)
            out += (c >= 32 && c < 127) ? text.charAt(i) : "."
        }
        return out
    }

    function openEntry(name, isDir, size) {
        if (isDir) {
            browsePath = (name === "..") ? parentPath(browsePath) : joinPath(browsePath, name)
            refreshList()
            return
        }

        busy = true
        status = "Reading " + name + " ..."
        var t0 = new Date().getTime()

        Qt.callLater(function () {
            var raw = mCommands.fileBlockRead(joinPath(browsePath, name))
            var readSecs = (new Date().getTime() - t0) / 1000
            var t1 = new Date().getTime()
            var ok = parseLog(raw)
            var parseSecs = (new Date().getTime() - t1) / 1000
            busy = false

            if (!ok) {
                status = parseError + "\n" + convertNote +
                         (size > 0 ? ", expected " + size + "B" : "")
                return
            }

            loadedName = name
            var rate = readSecs > 0 ? (size / readSecs) : 0
            status = "Read " + fmtSize(size) + " in " + readSecs.toFixed(0) + "s" +
                     (rate > 0 ? " (" + fmtSize(rate) + "/s)" : "") +
                     ", parsed " + sampleCount + " samples in " + parseSecs.toFixed(1) + "s"
            repaintCharts()
        })
    }

    Component.onCompleted: {
        // Logs live under log_can on the SD card / internal storage
        browsePath = "/log_can"
        if (VescIf.isPortConnected()) {
            refreshList()
        } else {
            status = "Not connected"
        }
    }

    ListModel { id: fileModel }

    // ── Browser ──────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 5
        visible: loadedName === ""
        spacing: 4

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                color: Utility.getAppHexColor("lightText")
                font.pointSize: 11
                elide: Text.ElideMiddle
                text: browsePath
            }

            Button {
                text: "Refresh"
                enabled: !busy
                onClicked: refreshList()
            }
        }

        // Bluetooth moves a few kB/s on this protocol; a megabyte log is
        // genuinely unusable over it, so say so up front.
        Rectangle {
            Layout.fillWidth: true
            visible: connectionKind() === "ble"
            color: Utility.getAppHexColor("lightestBackground")
            radius: 4
            implicitHeight: bleWarn.implicitHeight + 12

            Text {
                id: bleWarn
                anchors.fill: parent
                anchors.margins: 6
                wrapMode: Text.WordWrap
                color: Utility.getAppHexColor("orange")
                font.pointSize: 9
                text: "Connected over Bluetooth. Log transfer is very slow — " +
                      "connect over WiFi or USB for anything above a few hundred kB."
            }
        }

        Text {
            Layout.fillWidth: true
            visible: status !== ""
            wrapMode: Text.WordWrap
            color: Utility.getAppHexColor("disabledText")
            font.pointSize: 9
            text: status
        }

        ListView {
            id: fileList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: fileModel
            spacing: 1

            delegate: Rectangle {
                width: fileList.width
                height: 44
                color: Utility.getAppHexColor("lightBackground")

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10

                    Text {
                        Layout.fillWidth: true
                        color: Utility.getAppHexColor("lightText")
                        font.pointSize: 11
                        elide: Text.ElideMiddle
                        text: (fIsDir ? "[ " + fName + " ]" : fName)
                    }

                    Text {
                        color: armedName === fName
                               ? Utility.getAppHexColor("orange")
                               : Utility.getAppHexColor("disabledText")
                        font.pointSize: 9
                        text: {
                            if (fIsDir) return ""
                            if (armedName === fName) return "tap again — " + fmtSize(fSize) + " over BLE"
                            return fmtSize(fSize)
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !busy
                    onClicked: {
                        // Large reads over BLE take minutes; make it deliberate
                        if (!fIsDir && connectionKind() === "ble" && fSize > 102400
                                && armedName !== fName) {
                            armedName = fName
                            return
                        }
                        armedName = ""
                        openEntry(fName, fIsDir, fSize)
                    }
                }
            }
        }
    }

    // ── Analysis ─────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 5
        visible: loadedName !== ""
        spacing: 4

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                color: Utility.getAppHexColor("lightText")
                font.pointSize: 11
                font.bold: true
                elide: Text.ElideMiddle
                text: loadedName
            }

            Button {
                text: "Reset"
                onClicked: resetView()
            }

            Button {
                text: "Close"
                onClicked: {
                    loadedName = ""
                    refreshList()
                }
            }
        }

        // Statistics, recomputed for whatever range is on screen
        Flow {
            Layout.fillWidth: true
            spacing: 10

            Repeater {
                model: loadedName !== "" ? statsRows() : []

                Row {
                    spacing: 4
                    Text {
                        color: Utility.getAppHexColor("disabledText")
                        font.pointSize: 9
                        text: modelData[0] + ":"
                    }
                    Text {
                        color: Utility.getAppHexColor("lightText")
                        font.pointSize: 9
                        font.bold: true
                        text: modelData[1]
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            color: Utility.getAppHexColor("disabledText")
            font.pointSize: 8
            text: "Drag to move the cursor and pan · pinch to zoom"
        }

        // Pinch zooms the shared x-range; a one-finger drag pans and scrubs.
        PinchArea {
            Layout.fillWidth: true
            Layout.fillHeight: true

            property real pinchStartSpan: 0
            property real pinchFrac: 0.5

            onPinchStarted: {
                pinchStartSpan = viewT1 - viewT0
                pinchFrac = Math.max(0, Math.min(1, pinch.startCenter.x / width))
            }
            onPinchUpdated: {
                if (pinch.scale > 0.05) {
                    var pivot = viewT0 + pinchFrac * (viewT1 - viewT0)
                    var span = pinchStartSpan / pinch.scale
                    clampView(pivot - pinchFrac * span, pivot + (1 - pinchFrac) * span)
                }
            }

            Flickable {
                id: chartScroll
                anchors.fill: parent
                contentWidth: width
                contentHeight: chartCol.height
                clip: true
                // Horizontal drags belong to the charts, vertical to the list
                flickableDirection: Flickable.VerticalFlick

                Column {
                    id: chartCol
                    width: chartScroll.width
                    spacing: 6

                    Repeater {
                        model: activePanels

                        Item {
                            width: chartCol.width
                            height: 150

                            property var panelKeys: modelData.keys

                            Column {
                                anchors.fill: parent
                                spacing: 2

                                // Title plus a live value per series
                                Flow {
                                    width: parent.width
                                    spacing: 8

                                    Text {
                                        color: Utility.getAppHexColor("disabledText")
                                        font.pointSize: 8
                                        font.bold: true
                                        text: modelData.title.toUpperCase()
                                    }

                                    Repeater {
                                        model: panelKeys

                                        Row {
                                            spacing: 3

                                            Rectangle {
                                                width: 8; height: 8; radius: 4
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: colors[index % colors.length]
                                            }
                                            Text {
                                                color: Utility.getAppHexColor("disabledText")
                                                font.pointSize: 8
                                                text: logMeta[modelData] ? logMeta[modelData].name : modelData
                                            }
                                            Text {
                                                color: Utility.getAppHexColor("lightText")
                                                font.pointSize: 8
                                                font.bold: true
                                                text: {
                                                    if (cursorIdx < 0 || !logData[modelData]) {
                                                        return ""
                                                    }
                                                    var v = valueAt(modelData, cursorIdx)
                                                    if (!isFinite(v)) {
                                                        return "-"
                                                    }
                                                    var m = logMeta[modelData]
                                                    return v.toFixed(Math.min(m.precision, 2)) +
                                                           (m.unit ? " " + m.unit : "")
                                                }
                                            }
                                        }
                                    }
                                }

                                Canvas {
                                    id: cv
                                    width: parent.width
                                    height: parent.height - 22
                                    antialiasing: true

                                    readonly property int axisW: 54

                                    Connections {
                                        target: root
                                        function onRepaintCharts() { cv.requestPaint() }
                                    }

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()

                                        ctx.fillStyle = bgColor
                                        ctx.fillRect(0, 0, width, height)

                                        if (!timeKey || !logData[timeKey]) {
                                            return
                                        }

                                        var t = logData[timeKey]
                                        var cw = width - axisW
                                        var iA = loBound(t, viewT0)
                                        var iB = Math.min(loBound(t, viewT1), t.length - 1)

                                        // Gridlines
                                        ctx.strokeStyle = gridColor
                                        ctx.lineWidth = 1
                                        for (var g = 1; g < 4; g++) {
                                            var gy = (g / 4) * height
                                            ctx.beginPath()
                                            ctx.moveTo(axisW, gy)
                                            ctx.lineTo(width, gy)
                                            ctx.stroke()
                                        }

                                        for (var si = 0; si < panelKeys.length; si++) {
                                            var key = panelKeys[si]
                                            var arr = logData[key]
                                            if (!arr) {
                                                continue
                                            }

                                            // Autoscale to the visible window
                                            var mn = Infinity, mx = -Infinity
                                            for (var i = iA; i <= iB; i++) {
                                                var v = arr[i]
                                                if (isFinite(v)) {
                                                    if (v < mn) mn = v
                                                    if (v > mx) mx = v
                                                }
                                            }
                                            if (!isFinite(mn)) {
                                                continue
                                            }
                                            if (mn === mx) { mn -= 1; mx += 1 }
                                            var pad = (mx - mn) * 0.07
                                            mn -= pad; mx += pad

                                            // GNSS updates slower than the log rate; hold the
                                            // last reading so the trace stays continuous.
                                            var hold = key.indexOf("gnss_") === 0
                                            var lastV = NaN
                                            var down = false

                                            ctx.beginPath()
                                            ctx.strokeStyle = colors[si % colors.length]
                                            ctx.lineWidth = 1.5

                                            for (i = iA; i <= iB; i++) {
                                                var val = arr[i]
                                                if (isFinite(val)) {
                                                    lastV = val
                                                } else if (hold && isFinite(lastV)) {
                                                    val = lastV
                                                }
                                                if (!isFinite(val)) {
                                                    down = false
                                                    continue
                                                }
                                                var px = axisW + ((t[i] - viewT0) / (viewT1 - viewT0)) * cw
                                                var py = height - ((val - mn) / (mx - mn)) * (height - 2) - 1
                                                if (down) {
                                                    ctx.lineTo(px, py)
                                                } else {
                                                    ctx.moveTo(px, py)
                                                }
                                                down = true
                                            }
                                            ctx.stroke()

                                            // Range labels for the first two series only,
                                            // otherwise they collide
                                            if (si < 2) {
                                                var prec = Math.min(logMeta[key].precision, 2)
                                                ctx.fillStyle = colors[si % colors.length]
                                                ctx.font = "9px sans-serif"
                                                ctx.textAlign = si === 0 ? "right" : "left"
                                                var lx = si === 0 ? axisW - 3 : axisW + 3
                                                ctx.textBaseline = "top"
                                                ctx.fillText(mx.toFixed(prec), lx, 2)
                                                ctx.textBaseline = "bottom"
                                                ctx.fillText(mn.toFixed(prec), lx, height - 2)
                                            }
                                        }

                                        // Cursor
                                        if (cursorIdx >= 0) {
                                            var cx = axisW + ((t[cursorIdx] - viewT0) / (viewT1 - viewT0)) * cw
                                            if (cx >= axisW && cx <= width) {
                                                ctx.strokeStyle = Utility.getAppHexColor("lightText")
                                                ctx.lineWidth = 1
                                                ctx.beginPath()
                                                ctx.moveTo(cx, 0)
                                                ctx.lineTo(cx, height)
                                                ctx.stroke()
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        preventStealing: true

                                        property real lastX: 0

                                        onPressed: {
                                            lastX = mouseX
                                            setCursorFrac((mouseX - cv.axisW) / (width - cv.axisW))
                                        }
                                        onPositionChanged: {
                                            var dx = mouseX - lastX
                                            lastX = mouseX
                                            var dt = -(dx / (width - cv.axisW)) * (viewT1 - viewT0)
                                            clampView(viewT0 + dt, viewT1 + dt)
                                            setCursorFrac((mouseX - cv.axisW) / (width - cv.axisW))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Busy overlay: fileBlockList/fileBlockRead block, so make that visible
    Rectangle {
        anchors.fill: parent
        visible: busy
        color: "#a0000000"    // QML hex is #AARRGGBB

        ProgressBar {
            anchors.centerIn: parent
            width: parent.width * 0.6
            indeterminate: true
        }
    }
}
