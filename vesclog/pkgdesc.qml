import QtQuick 2.15

Item {
    property string pkgName: "Log Analysis"
    property string pkgDescriptionMd: "README.md"

    // QML-only package. NOTE: an empty pkgLisp is not neutral — CodeLoader::
    // installVescPackage() calls lispErase() when a package carries no lisp,
    // so installing this REMOVES any LispBM script already on the device.
    // A device holds one package at a time; installing replaces both slots.
    property string pkgLisp: ""
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "vesclog.vescpkg"

    // This function should return true when this package is compatible
    // with the connected vesc-based device
    function isCompatible (fwRxParams) {
        var hwType = fwRxParams.hwTypeStr().toLowerCase()

        // The log files live on the logging device, so this is aimed at
        // custom modules (VESC Express and friends). The classic VESC BMS
        // does not support packages at all.
        if (hwType == "vesc bms") {
            return false
        }

        return hwType == "custom module"
    }
}
