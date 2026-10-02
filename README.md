# ESCargot Packages

Packages for the package store in VESC® Tool. A fork of the VESC® Packages
repository, with a touch dashboard and a logger added.

**Not affiliated with, endorsed by, or certified by Mr. Benjamin Vedder.**
VESC® is his registered trademark; see [TRADEMARKS.md](TRADEMARKS.md).

## What this fork adds

| package | what it is |
|---|---|
| `dash_p4` / `dash_s3` | a touch dashboard in LispBM, for 800x480 and 480x480 panels |
| `dash_p4_lua` | the same dashboard in Lua, at parity with the lisp one |
| `dash_common` / `dash_common_lua` | the shared libraries both dashboards are built from |
| `dash_esc` | the controller-side half: a custom SID protocol feeding the dash |
| `vesclog` | a logger |

The two dashboards are held at parity deliberately. Thirty golden images are
rendered on a host for both panel profiles and compared pixel by pixel, and
the configuration packet the Lua dash sends is diffed field by field against
the lisp dash's as an oracle — 61 fields, byte-identical across two settings
states. The point is that porting a dashboard between script engines is
verifiable rather than hopeful.

### Tests

All host-side, no board required:

```bash
cd dash_common_lua/test && ./run.sh            # 19 suites
cd dash_common_lua/test/render && ./run.sh     # golden images, both panels
cd dash_common_lua/test/cfg && ./run.sh        # the config-packet oracle
cd dash_common/test && ./run.sh                # the lisp dashboard
```

The render harness needs only `lua5_4` and `python3`; the lisp one drives the
LispBM REPL. Neither needs a display.

## Upstream

`upstream` points at `vedderb/vesc_pkg` over HTTPS and is pull-only; its push
URL is deliberately set to `no-push`. Changes go to `origin`.

## What a package is

A package consists of:

* A description, which can include formatted text and images.
* An optional LispBM script with optional includes.
	- The includes can also contain one or more compiled C libraries.
* An optional QML file.
* Or, in this fork, a Lua script in place of the LispBM one.

Packages are pulled and updated from VESC® Tool on demand, so their
development does not have to be synchronised with the tool's. There is no need
for users to update the tool or the firmware — they refresh the package store
and reinstall.

## Package Types

There are two types of packages:

* Applications
* Libraries

At the moment they are implemented in the same way, the only difference is the naming and how you are supposed to use them. If you create a package or library you should make that clear in your description.

### Applications

Application packages are intended to be installed and used either without configuration, or with a configuration GUI that they provide. That GUI can either be a QML-file or a custom configuration page in VESC® Tool.

### Libraries

Library packages are intended to be building blocks to be used from LisbBM-scripts. All libraries in this repository can be imported in LispBM-scripts without the need for installation.

To declare a package as a library it should be placed in a directory that starts with the name **lib_**. That is enough to tell VESC® Tool to list it under libraries and to disable the install button when it is selected.

Libraries work by providing one or more files that can be imported in LispBM-scripts. These files can be anything, but are typically either LispBM-scripts or compiled native code that can be loaded after importing it. To make these files available they need a LispBM-script that imports all files meant to be provided in the package. Other LispBM-scripts can then import the files imported in the package.

**Example**

The WS2812-library wants to provide the file **c_lib/ws2812/ws2812.bin**. Therefore it contains a lisp-script with the line

```clj
(import "c_lib/ws2812/ws2812.bin" 'ws2812)
```

which means that it imports that file under the label ws2812. Once the package is made this file is included in the package and thus available to other lisp-scripts that want to use it.

Other lisp-scripts can then import that file by addressing the label ws2812 in that package:

```clj
(import "pkg::ws2812@://vesc_packages/lib_ws2812/ws2812.vescpkg" 'ws2812)
```

Here the syntax means

**pkg::** - Import a file from a package  
**ws2812** - The label in that package is ws2812  
**@://vesc_packages/lib_ws2812/ws2812.vescpkg** - The path of that package

The **@**-sign is followed by a path to a package which can be any path on the local file system. The packages in this git-repository can be accessed from the base path **://vesc_packages/** (because they are loaded as a Qt resource there), which is what we have done here.

Once the file is imported in your lisp-script you can use it as usual, e.g. in this case by loading it as a native library:

```clj
(load-native-lib ws2812) ; Loading this library provides some extensions to control ws2812 addressable LEDs
```

**Note**

VESC® Tool does not automatically refresh the packages, it uses the ones that are downloaded and cached from the archive the last time. To update the archive you can use the **Update Archive**-button from the packages-page in VESC® Tool.

## How to include your package

To include your package in VESC® Tool you can make a pull request to this repository. Your pull request should include:

* A description of what your package does.
* Instructions on how to use it.
* If it contains compiled C libraries their source code must be included in the pull request under the GPL license (see the examples).

## Building

To build all packages in the repository, run (in the root directory):
```sh
make
```

If you make changes to the source files, it is important to run `make clean`, as `make` doesn't detect changes in files to regenerate them:
```sh
make clean
make
```

If you don't have `vesc_tool` in your path, you can specify the `vesc_tool` to use:
```sh
make clean
make VESC_TOOL=/path/to/vesc_tool
```

### Native libraries for VESC® Express boards

The build rules for VESC® Express native libraries (see `c_libs/examples/express_extension`) use [RVfplib](https://github.com/pulp-platform/RVfplib) for soft-float support on the RISC-V targets. It is included as a git submodule, so it has to be initialized before building:
```sh
git submodule update --init
```

### Notes

* Make sure that you build a package file (\*.vescpkg) in the main directory of your package (e.g. euc/euc.vescpkg)
* Make sure to add your package to res_all.qrc in the root of the repository.
* Make sure all temporary files generated by your Makefiles are properly cleaned in the `clean` targets, otherwise you risk hard-to-debug failures of building from stale generated files.
* Test your .vescpkg-file before making a pull request!
