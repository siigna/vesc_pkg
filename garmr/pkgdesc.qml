// Copyright 2026 Stephen Bouche
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick 2.15

Item {
    property string pkgName: "Garmr (prototype)"
    property string pkgDescriptionMd: "README.md"

    // Built by vesc_express/tools/luapack.py, not the .lua source: vesc_tool
    // checks the container header and refuses a raw script, because
    // installing one would erase the board's script slot and leave it holding
    // bytes no engine can run.
    property string pkgLua: "garmr.luapkg"

    property string pkgOutput: "garmr.vescpkg"

    // Needs the pedal-assist walk keepalive and the Lua PAS bindings, so this
    // is an ESCargot build only. On firmware without them the script would
    // load and then fail on the first call.
    function isCompatible (fwRxParams) {
        var fwName = fwRxParams.fwName
        return fwRxParams.hwTypeStr() === "VESC" &&
               fwName.indexOf("ESCargot") !== -1
    }
}
