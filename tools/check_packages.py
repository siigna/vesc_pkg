#!/usr/bin/env python3
"""Checks every package's pkgdesc.qml against what vesc_tool requires of it.

    tools/check_packages.py            every package
    tools/check_packages.py garmr      one of them

Pure Python, no dependencies, nothing built. It cannot replace building a
package -- that needs vesc_tool for --buildPkgFromDesc and, for a Lua package,
vesc_express for luapack.py, so two other repositories and a Qt build. What it
can do is catch the mistakes that make a build fail or, worse, produce a
package that installs and does nothing: a missing name, a referenced file that
is neither present nor produced by the Makefile, or a raw .lua declared where
the Tool demands a .luapkg container.

That last one matters more than it looks. vesc_tool validates the container
header and refuses a bare script, because installing one would overwrite the
board's script slot with bytes no engine can run.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Properties naming a file the build consumes or produces.
FILE_PROPS = ("pkgLisp", "pkgLua", "pkgQml", "pkgOutput", "pkgDescriptionMd")


def prop(text, name):
    m = re.search(r"property\s+string\s+%s\s*:\s*\"([^\"]*)\"" % name, text)
    return m.group(1) if m else None


def made_by_makefile(pkgdir, target):
    """Whether the package's Makefile claims to produce this file.

    A build product need not exist in a clean checkout -- garmr.luapkg and
    garmr.vescpkg are both gitignored -- so the check is that something builds
    it, not that it is sitting there.
    """
    mk = os.path.join(pkgdir, "Makefile")

    if not os.path.exists(mk):
        return False

    text = open(mk, encoding="utf-8", errors="replace").read()
    base = os.path.basename(target)
    stem, ext = os.path.splitext(base)

    # An explicit rule, a variable holding the name, or a pattern rule for the
    # extension -- `%.luapkg:` covers garmr.luapkg without naming it.
    for pat in (r"^\s*%s\s*:" % re.escape(base),
                re.escape(base),
                r"^\s*%%%s\s*:" % re.escape(ext)):
        if re.search(pat, text, flags=re.M):
            return True

    return False


def check(name):
    pkgdir = os.path.join(ROOT, name)
    desc = os.path.join(pkgdir, "pkgdesc.qml")
    problems = []

    text = open(desc, encoding="utf-8", errors="replace").read()

    if not prop(text, "pkgName"):
        problems.append("no pkgName, so the Tool has nothing to list it under")

    # A description is either inline or a file; one of the two must be there.
    if not prop(text, "pkgDescriptionMd") and "pkgDescription" not in text:
        problems.append("no pkgDescription or pkgDescriptionMd")

    lua = prop(text, "pkgLua")

    if lua is not None and lua.endswith(".lua"):
        problems.append("pkgLua is %r, a raw script. vesc_tool validates the "
                        "container header and refuses one; it must be a "
                        ".luapkg built by vesc_express/tools/luapack.py" % lua)

    for p in FILE_PROPS:
        rel = prop(text, p)

        if not rel:
            continue

        if os.path.exists(os.path.join(pkgdir, rel)):
            continue

        if made_by_makefile(pkgdir, rel):
            continue

        problems.append("%s names %r, which is neither in the tree nor built "
                        "by the Makefile" % (p, rel))

    return problems


def main():
    wanted = sys.argv[1:]
    names = sorted(d for d in os.listdir(ROOT)
                   if os.path.exists(os.path.join(ROOT, d, "pkgdesc.qml")))

    if wanted:
        unknown = [w for w in wanted if w not in names]

        if unknown:
            sys.exit("no such package: %s" % ", ".join(unknown))

        names = wanted

    if not names:
        sys.exit("no packages found under %s" % ROOT)

    bad = 0

    for name in names:
        problems = check(name)

        if problems:
            bad += 1
            print("%s:" % name)

            for p in problems:
                print("  %s" % p)
        else:
            print("  ok  %s" % name)

    print("\n%d package(s), %d with problems" % (len(names), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
