# Copyright 2026 Stephen Bouche
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Two steps, like the other Lua packages here: the Lua side has its own
# packer, which walks require() the way vesc_tool walks lisp imports and
# writes the same container with the language flag set. vesc_tool then embeds
# the container verbatim through pkgLua.
#
#   make           build the package
#   make clean
#
# VE points at the vesc_express checkout the packer comes from.

VESC_TOOL ?= vesc_tool
VE ?= ../../vesc_express
LUAPACK = $(VE)/tools/luapack.py

all: garmr.vescpkg

garmr.vescpkg: garmr.luapkg README.md pkgdesc.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml

garmr.luapkg: garmr.lua
	python3 $(LUAPACK) garmr.lua -o $@

clean:
	rm -f garmr.vescpkg garmr.luapkg

.PHONY: all clean
