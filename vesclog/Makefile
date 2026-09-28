VESC_TOOL ?= vesc_tool

all: vesclog.vescpkg

vesclog.vescpkg: ui.qml pkgdesc.qml README.md
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml

clean:
	rm -f vesclog.vescpkg

.PHONY: all clean
