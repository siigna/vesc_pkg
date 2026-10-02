# Copyright 2026 Stephen Bouche
# SPDX-License-Identifier: GPL-3.0-or-later
VESC_TOOL ?= vesc_tool

all: dash_s3.vescpkg

dash_s3.vescpkg: README_Disp-gen.md ui.qml version.lisp
	$(VESC_TOOL) --reduceLisp --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:test' --testPkgDesc 'custom:ws s3 touch lcd 4' --testPkgDesc 'vesc:test'

VERSION=`cat version`

README_Disp-gen.md: README_Disp.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@

ui.qml: ui.qml.in
	cat ui.qml.in | sed "s/{{VERSION}}/${VERSION}/g" > ui.qml

version.lisp: version.lisp.in version
	cat version.lisp.in | sed "s/{{VERSION}}/${VERSION}/g" > version.lisp

clean:
	rm -f dash_s3.vescpkg
	rm -f README_Disp-gen.md
	rm -f ui.qml
	rm -f version.lisp

.PHONY: all clean
