# Copyright 2026 Stephen Bouche
# SPDX-License-Identifier: GPL-3.0-or-later
# The Lua dash, as an installable VESC package.
#
# Two steps rather than one, because the Lua side has its own packer. The
# container is built by vesc_express/tools/luapack.py, which walks require()
# the way vesc_tool walks lisp imports and emits the same container format
# with the language flag set; vesc_tool then embeds it verbatim via pkgLua.
#
# Walking the imports in vesc_tool instead would mean a second implementation
# of Lua module resolution that could disagree with the one the packer uses.
#
#   make                 build the package
#   make upload          build and push it over serial, without VESC Tool
#   make clean
#
# VE points at the vesc_express checkout the packer and the fonts come from.

VESC_TOOL ?= vesc_tool
VE ?= ../../vesc_express
LUAPACK = $(VE)/tools/luapack.py
SCRIPT = $(VE)/tools/vesc_script.py
PORT ?= /dev/ttyACM1

# The fonts are dash_p4's: prepared glyph tables, identical for both engines,
# and duplicating 200 KB of them to own a copy would be worse than sharing.
FONTS = ../dash_p4/font

VERSION = $(shell cat version)

LIB = $(wildcard ../dash_common_lua/lib/*.lua)

all: dash_p4_lua.vescpkg

dash_p4_lua.vescpkg: dash_p4_lua.luapkg README-gen.md ui.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml \
		--testPkgDesc 'custom:ws p4 touch lcd 4.3'

dash_p4_lua.luapkg: main.lua config.lua version.lua $(LIB)
	python3 $(LUAPACK) \
		--import-root . --import-root ../dash_common_lua \
		--asset font120=$(FONTS)/roboto-bold-120-4c.bin \
		--asset font40=$(FONTS)/roboto-bold-40-4c.bin \
		--asset font24=$(FONTS)/roboto-bold-24-4c.bin \
		--asset font18=$(FONTS)/roboto-bold-18-4c.bin \
		-o $@ main.lua

# Straight to the board, for the loop this was developed in: VESC Tool is not
# always available with its firmware resources, and this needs no package.
upload: dash_p4_lua.luapkg
	python3 $(SCRIPT) $(PORT) upload dash_p4_lua.luapkg

# The package, installed the way a user would install it. Needs a vesc_tool
# built from this fork: --installPkg and pkgLua are both new.
#
# XDG_DATA_HOME is redirected because a VESC Tool that has run before leaves a
# downloaded res_config.rcc in the real one, and that resource shadows the
# built-in config -- the tool then reports no supported firmwares and refuses
# to connect. Pointing it at an empty directory is the whole workaround.
install: dash_p4_lua.vescpkg
	mkdir -p $(CURDIR)/.vt-home
	XDG_DATA_HOME=$(CURDIR)/.vt-home QT_QPA_PLATFORM=offscreen \
		$(VESC_TOOL) --offscreen --vescPort $(PORT) \
		--installPkg dash_p4_lua.vescpkg

version.lua: version.lua.in version
	sed "s/{{VERSION}}/$(VERSION)/g" $< > $@

ui.qml: ui.qml.in version
	sed "s/{{VERSION}}/$(VERSION)/g" $< > $@

README-gen.md: README.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "" >> $@
	echo "- Version: $(VERSION)" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@

# Everything the suites cover, in the order a failure is cheapest to read.
test:
	cd ../dash_common_lua && ./test/run.sh
	cd ../dash_common_lua && ./test/cfg/run.sh
	cd ../dash_common_lua && ./test/render/run_e2e.sh

clean:
	rm -f dash_p4_lua.vescpkg dash_p4_lua.luapkg README-gen.md ui.qml version.lua
	rm -rf .vt-home

.PHONY: all clean test upload install
