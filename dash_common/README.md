# dash_common

Shared source for the touch dash packages. Not a package itself: there is no
`pkgdesc.qml` and it produces no `.vescpkg`.

Currently used by `dash_s3` (Waveshare ESP32-S3-Touch-LCD-4, 480x480) and
`dash_p4` (Waveshare ESP32-P4-WIFI6-Touch-LCD-4.3, 800x480). The `lib/` files
here are the same ones `dash_vdisp` and `dash35b` carry their own copies of,
so those two could move onto this tree without changes; `dash16` has diverged
too far to be worth folding in.

## Layout

    lib/        the shared library: vehicle state, colours, statistics,
                communication, standalone fallback, settings. Board-agnostic.
    views/      view_static (the always-on bands) and view_pages (the
                swappable lower area). Sized from the board profile.
    main_body   everything in a dash's main.lisp that is not board-specific.

## What a board package provides

`config.lisp`, the board profile:

| | meaning |
|---|---|
| `disp-w` `disp-h` | panel size, after any rotation |
| `strip-h` `speed-h` `page-h` | band heights; every other band is derived by stacking from these in `views/view_static.lbm` |
| `page-cols` `page-row-h` | the label/value grid. Pages supply eight cells, so the rows follow from the column count: 2 columns means 4 rows, 4 means 2 |
| `config-dm-pool` | display memory. Image buffers are full-width strips, so this scales with the panel |
| `config-disp-rotation` | passed to `ext-disp-orientation` |
| `config-touch-transforms` | `(swap-xy mirror-x mirror-y)` |
| `config-btn-actions-short` / `-long` | action id per button or touch region |

Plus `lib/input.lisp` (buttons and touch regions differ per board), the
fonts, and three functions: `board-disp-init`, `board-touch-init`, `bl-set`.

## Importing

**Every `import` has to be in the board's `main.lisp`.** vesc_tool packs
imports by scanning the top-level lisp file only, with no recursion
(`codeloader.cpp`, `lispPackImports`), so an import inside an imported file
never reaches the device. That is why `main_body.lisp` contains none, and why
each board's `main.lisp` lists the whole shared tree explicitly with `../`
paths — which resolve, because imports are looked up relative to the main
file's directory.

## Testing

Layouts render to PNG on a workstation with no hardware. See the harness notes
in `dash_s3/README_Disp.md`.
