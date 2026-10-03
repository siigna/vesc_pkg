// Copyright 2026 Stephen Bouche
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick 2.15

Item {
    property string pkgName: "Garmr (prototype)"
    property string pkgDescriptionMd: "README.md"

    // Lisp needs no container: vesc_tool walks the imports itself. The Lua
    // sibling in garmr_lua has to ship a .luapkg instead, which is the one
    // real difference between the two packages.
    property string pkgLisp: "garmr.lisp"

    property string pkgOutput: "garmr.vescpkg"

    // Needs the pedal-assist walk keepalive and app-pas-get-flags, so this is
    // an ESCargot build only. On firmware without them the script would load
    // and then fail on the first call.
    function isCompatible (fwRxParams) {
        var fwName = fwRxParams.fwName
        return fwRxParams.hwTypeStr() === "VESC" &&
               fwName.indexOf("ESCargot") !== -1
    }
}
