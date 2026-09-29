import QtQuick 2.15

Item {
    property string pkgName: "Dash P4"
    property string pkgDescriptionMd: "README_Disp-gen.md"
    property string pkgLisp: "main.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "dash_p4.vescpkg"

    // This function should return true when this package is compatible
    // with the connected vesc-based device
    function isCompatible (fwRxParams) {
        var hwName = fwRxParams.hw.toLowerCase();

        // vesc, vesc bms or custom module
        var hwType = fwRxParams.hwTypeStr().toLowerCase();

        // The classic VESC BMS does not support packages at all
        if (hwType == "vesc bms") {
            return false
        }

        if (hwType != "custom module") {
            return false
        }

        // The display pins come from the hardware config, so this needs a
        // firmware built for a board that provides disp-init for a 480x480
        // ST7701 over RGB.
        return hwName == "ws p4 touch lcd 4.3"
    }
}
