# Copyright 2026 Stephen Bouche
# SPDX-License-Identifier: GPL-3.0-or-later
#
# One step, unlike the Lua sibling: vesc_tool walks lisp imports itself, so
# there is no container to pack first.
#
#   make           build the package
#   make test      the engage logic in the LispBM repl
#   make clean

VESC_TOOL ?= vesc_tool

all: garmr.vescpkg

garmr.vescpkg: garmr.lisp README.md pkgdesc.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml

test:
	@./test/run.sh

clean:
	rm -f garmr.vescpkg

.PHONY: all clean test
