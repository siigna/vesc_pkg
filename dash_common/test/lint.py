#!/usr/bin/env python3
# Copyright 2026 Stephen Bouche
# SPDX-License-Identifier: GPL-3.0-or-later
"""A linter for the dash's LispBM sources.

LispBM has no static checking of its own: a file loads, and an undefined symbol
or a misplaced `return` becomes a runtime error the first time that branch is
taken. On a display that means a thread dies mid-ride, and the branch that
takes it may be the one that only runs when something has gone wrong.

Every check here exists because the mistake it catches was actually made in
this package, and in each case the render tests did not catch it: they exercise
the drawing, not the paths that only run on a real vehicle.

  ./lint.py <package dir> [...]

Exits non-zero on any finding.
"""
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

def strip_comments(text):
    """Remove `;` comments, leaving string literals alone."""
    out = []
    for line in text.splitlines():
        in_str = False
        esc = False
        cut = len(line)
        for i, ch in enumerate(line):
            if esc:
                esc = False
                continue
            if ch == "\\":
                esc = True
            elif ch == '"':
                in_str = not in_str
            elif ch == ";" and not in_str:
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def top_forms(text):
    """Yield (start_line, source) for each top-level parenthesised form."""
    depth = 0
    start = None
    start_line = 0
    line = 1
    in_str = False
    esc = False
    for i, ch in enumerate(text):
        if ch == "\n":
            line += 1
        if esc:
            esc = False
            continue
        if ch == "\\":
            esc = True
            continue
        if ch == '"':
            in_str = not in_str
            continue
        if in_str:
            continue
        if ch == "(":
            if depth == 0:
                start = i
                start_line = line
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0 and start is not None:
                yield start_line, text[start:i + 1]
                start = None
            if depth < 0:
                depth = 0
    if depth > 0 and start is not None:
        yield start_line, text[start:]


DEFUN = re.compile(r"^\(\s*(defun|defunret)\s+([^\s()]+)")
DEF = re.compile(r"^\(\s*(def)\s+([^\s()]+)")

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def check_return_needs_defunret(path, text, findings):
    """`return` only exists inside `defunret`.

    In a plain `defun` it is an unbound variable, and the error is raised when
    that branch first runs rather than when the file is loaded. This is exactly
    how the PIN keypad shipped: every key press during a lockout would have
    thrown instead of being ignored.
    """
    for line_no, form in top_forms(text):
        m = DEFUN.match(form)
        if not m or m.group(1) == "defunret":
            continue
        if re.search(r"\(\s*return\b", form):
            findings.append(
                f"{path}:{line_no}: `return` inside (defun {m.group(2)} ...) -- "
                f"needs defunret, or it throws variable_not_bound when reached"
            )


def check_paren_balance(path, text, findings):
    """Unbalanced parens, reported per top-level form rather than per file."""
    depth = 0
    in_str = False
    esc = False
    for ch in text:
        if esc:
            esc = False
            continue
        if ch == "\\":
            esc = True
        elif ch == '"':
            in_str = not in_str
        elif not in_str and ch == "(":
            depth += 1
        elif not in_str and ch == ")":
            depth -= 1
    if depth != 0:
        findings.append(
            f"{path}: parens unbalanced by {depth:+d} "
            f"({'unclosed' if depth > 0 else 'extra closing'})"
        )


def collect_defined(text):
    """Every name this file binds at the top level, plus function parameters."""
    names = set()
    for _, form in top_forms(text):
        m = DEFUN.match(form) or DEF.match(form)
        if m:
            names.add(m.group(2))
    return names


def check_string_equality(path, text, findings):
    """`=` on strings is a type error, not false.

    A string is a byte array, and `=` rejects one. The quick shade shipped with
    `(!= sub "")`, which took the page down the first time a button had no
    state line to draw.
    """
    for line_no, line in enumerate(strip_comments(text).splitlines(), 1):
        for m in re.finditer(r"\(\s*(!?=)\s+[^()]*?\"", line):
            findings.append(
                f"{path}:{line_no}: `{m.group(1)}` applied to a string literal -- "
                f"use eq; = on a byte array is a type error"
            )


def check_setting_flag_type(path, text, findings):
    """A flag read with setting-flag must be stored as `i`, not `b`.

    setting-flag compares the value against 1. A `b` cell reads back as a
    boolean, and comparing that to a number throws. pin-en shipped this way and
    took settings-load down on the first load.
    """
    addrs = {}
    for m in re.finditer(r"\(([\w\-]+)\s*\.\s*\(\s*(\d+)\s+([ifb])\s*\)\)", text):
        addrs[m.group(1)] = m.group(3)
    for line_no, line in enumerate(strip_comments(text).splitlines(), 1):
        for m in re.finditer(r"\(setting-flag\s+'([\w\-]+)", line):
            name = m.group(1)
            if addrs.get(name) == "b":
                findings.append(
                    f"{path}:{line_no}: setting-flag on '{name}', which is stored "
                    f"as b -- it must be i, or the comparison against 1 throws"
                )


def _balanced(text, start, open_ch="(", close_ch=")"):
    """The source of the form beginning at start, to its matching close."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == open_ch:
            depth += 1
        elif text[i] == close_ch:
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    return text[start:]


def check_settings_restored(path, text, findings):
    """Every setting read at load must be written by restore-settings.

    An eeprom slot that has never been written reads nil on hardware, where the
    test stub hands back 0 -- so a setting added to settings-load and forgotten
    in restore-settings works in the renders and throws on a real board. That
    took the dash down before its first draw once already: setting-clamp
    compares with `=`, and `=` on nil is a type error rather than false.

    Checked statically because the goldens structurally cannot see it.
    """
    if "eeprom-addrs" not in text:
        return

    clean = strip_comments(text)

    declared = set(re.findall(
        r"\(([\w\-]+)\s*\.\s*\(\s*\d+\s+[ifb]\s*\)\)",
        _balanced(clean, clean.index("(def eeprom-addrs"))))

    def names_in(defun, pattern):
        try:
            i = clean.index(defun)
        except ValueError:
            return set()
        body = _balanced(clean, i)
        found = set(re.findall(pattern, body))
        # names passed as a quoted list to ix, which is how the repeated
        # per-slot and per-button settings are written
        for group in re.findall(r"ix '\(([^)]*)\)", body):
            found |= set(group.split())
        return found

    read = names_in("(defun settings-load",
                    r"\((?:read-setting|setting-flag)\s+'([\w\-]+)")
    written = names_in("(defun restore-settings",
                       r"\(write-setting\s+'([\w\-]+)")

    for name in sorted(read - written):
        findings.append(
            f"{path}: '{name}' is read by settings-load but never written by "
            f"restore-settings -- it reads nil on hardware and throws")

    for name in sorted(read - declared):
        findings.append(
            f"{path}: '{name}' is read by settings-load but is not in "
            f"eeprom-addrs -- read-setting returns nil for it")


CHECKS = (
    check_paren_balance,
    check_return_needs_defunret,
    check_string_equality,
    check_setting_flag_type,
    check_settings_restored,
)


def check_unbound(pkg, files, findings):
    """Symbols referenced by a package but bound nowhere in it.

    Crude on purpose: it only reports a name that looks like a definition this
    package should own -- one that is referenced in a call position and is not
    bound anywhere in the package, not a builtin, and not a local. That is the
    class of mistake that shipped twice in one session (`shade-showing` from a
    view, `light-on-default` from a library), both of which loaded fine and
    threw later.
    """
    defined = set()
    for f in files:
        defined |= collect_defined(strip_comments(f.read_text()))

    # Names bound by the board package, the repl, or a let/var, which this
    # crude pass cannot see. Extended rather than guessed at: anything listed
    # here is a name a reader can check by hand.
    known = set(BUILTINS)

    for f in files:
        text = strip_comments(f.read_text())
        locals_here = set(re.findall(r"\(\s*(?:var|let)\s*\(?\s*\(?([\w\-]+)", text))
        locals_here |= set(re.findall(r"\(\s*(?:defun|defunret)\s+[\w\-]+\s*\(([^)]*)\)", text)
                           and sum((p.split() for p in re.findall(
                               r"\(\s*(?:defun|defunret)\s+[\w\-]+\s*\(([^)]*)\)", text)), []))
        locals_here |= set(re.findall(r"\(\s*looprange\s+([\w\-]+)", text))
        locals_here |= set(re.findall(r"\(\s*loopforeach\s+([\w\-]+)", text))
        locals_here |= set(re.findall(r"\(\s*let\s*\(\s*\(([\w\-]+)", text))
        for m in re.finditer(r"\(\s*([a-z][\w\-]{2,})\s", text):
            name = m.group(1)
            if name in defined or name in known or name in locals_here:
                continue
            line_no = text[:m.start()].count("\n") + 1
            findings.append(
                f"{f.relative_to(pkg.parent)}:{line_no}: `{name}` is called but "
                f"bound nowhere in this package"
            )


# LispBM builtins and the names a board package or the repl provides. Not
# exhaustive; a name missing from here shows up as a false positive, which is
# why check_unbound is opt-in behind --unbound.
BUILTINS = set("""
def defun defunret defmacro lambda let var setq setix progn if cond match
loopwhile loopforeach looprange loopwhile-thd atomic recv recv-to spawn wait
trap exit-ok exit-error return eq not-eq and or not car cdr cons list append
reverse length ix map zipwith filter foldl range str-merge str-from-n str-split
str-len str-cmp to-i to-float round abs mod sqrt pow sin cos atan2 min max
bitwise-and bitwise-or bitwise-xor shl shr systime secs-since sleep print
bufcreate bufset-u8 bufset-i8 bufset-u16 bufset-i16 bufset-u32 bufset-i32
bufset-f32 bufget-u8 bufget-i8 bufget-u16 bufget-i16 bufget-u32 bufget-i32
bufget-f32 buflen bufclear array-create mkarray eeprom-store-i eeprom-store-f
eeprom-read-i eeprom-read-f img-buffer img-clear img-line img-rectangle img-arc
img-circle img-circle-sector img-blit img-dims img-setpix disp-init disp-clear
disp-render disp-load-st7701 ttf-prepare ttf-text ttf-text-dims ttf-glyph-dims
color-make color-mix colors-make-aa can-send-sid can-send-eid send-data
event-register-handler event-enable gpio-configure gpio-write gpio-read
get-adc get-bms-val set-bms-val conf-get conf-set conf-store get-speed
touch-read touch-load-gt911 touch-pins rgbled-init rgbled-buffer rgbled-color
rgbled-update dm-create set-active-img display-to-img save-active-img
img-buffer-from-bin image-save read-eval-program import gnss-speed
set-print-prefix reboot sysinfo select-motor get-selected-motor apply
first second rest-args assoc setassoc number? eval read clamp clamp01 fmax
fabs list-find str-to-i str-to-f ext-disp-orientation
""".split())


def main(argv):
    want_unbound = "--unbound" in argv
    dirs = [a for a in argv[1:] if not a.startswith("--")]
    if not dirs:
        print(__doc__)
        return 2

    findings = []
    for d in dirs:
        pkg = Path(d)
        files = sorted(list(pkg.rglob("*.lisp")) + list(pkg.rglob("*.lbm")))
        files = [f for f in files if "/build/" not in str(f) and "/test/" not in str(f)]
        if not files:
            print(f"no lisp sources under {d}")
            return 2
        for f in files:
            text = f.read_text()
            rel = f.relative_to(pkg.parent)
            for check in CHECKS:
                check(rel, text, findings)
        if want_unbound:
            check_unbound(pkg, files, findings)

    for line in sorted(set(findings)):
        print(line)

    n = len(set(findings))
    print(f"\n{n} finding{'' if n == 1 else 's'}")
    return 1 if n else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
