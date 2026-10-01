import QtQuick 2.15

Item {
    property string pkgName: "Dash P4 (Lua)"
    property string pkgDescriptionMd: "README-gen.md"

    // A prebuilt container from vesc_express/tools/luapack.py, not a source
    // file: the packer walks the require() tree and emits the same container
    // format vesc_tool's lispPackImports does, with the language flag set.
    // The Makefile builds it.
    property string pkgLua: "dash_p4_lua.luapkg"

    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "dash_p4_lua.vescpkg"

    // True when this package is compatible with the connected device.
    function isCompatible (fwRxParams) {
        var hwName = fwRxParams.hw.toLowerCase();
        var hwType = fwRxParams.hwTypeStr().toLowerCase();

        // The classic VESC BMS does not support packages at all.
        if (hwType == "vesc bms") {
            return false
        }

        if (hwType != "custom module") {
            return false
        }

        // The panel pins come from the hardware config, so this needs a
        // firmware built for this board -- and, unlike the lisp package, one
        // built with -DSCRIPT_ENGINE=lua. There is nothing in the version
        // reply that says which engine is running, so that cannot be checked
        // here: a lisp firmware will accept this package and then fail to run
        // it, reporting a container it does not understand.
        //
        // Worth a capability bit in COMM_FW_VERSION eventually. Only one
        // hardware capability reaches the host today.
        return hwName == "ws p4 touch lcd 4.3"
    }
}
