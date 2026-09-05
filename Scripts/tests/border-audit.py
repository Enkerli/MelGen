#!/usr/bin/env python3
"""Checks that a border identifies a control, and nothing else.

`MelGenTheme` says it outright: `borderStrong` is "≥3:1 — boundaries that
identify a control." A border on a *group* spends that signal on something you
cannot press, and once groups wear borders too a border no longer distinguishes
a control from a container. Groups separate by surface and space; the three
surfaces exist for exactly that.

Written because the rule turned out to be 97% true and 3% wrong, and the wrong
part was three days old: the `take` badge in `ActionBadge.swift` — a label
nobody can press — wore the 1.5pt `borderStrong` edge that means "control". A
rule that is nearly always kept is a rule nobody notices breaking, which is the
same shape as the "changes" drift in ISSUES §6.5 and the same remedy: check it.

How it decides. Every `strokeBorder(` in the interface is attributed to the
declaration that encloses it, and that declaration has to contain some evidence
of being interactive — a `Button`, a `TextField`, a gesture, a `contentShape`.
Canvas drawings are not caught here at all, because they stroke through a
`GraphicsContext` rather than through the view modifier; a line inside a drawing
is content, not a boundary.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
# The UI kit is the package's `UI` target now; what is left under
# MelGenExtension/UI is MelGen's own screen. Both are scanned, because the
# rule this checks is about what a person sees, not about which module
# drew it.
UI_DIRS = [ROOT / "MelGenExtension" / "UI",
           ROOT / "EnkerliSwift" / "Sources" / "UI"]

# What makes a declaration interactive. Deliberately generous: the rule is about
# borders on things that are plainly containers, and a false pass costs less
# than a false failure that trains people to widen the list.
INTERACTIVE = re.compile(
    r"\bButton\b|\bTextField\b|\bToggle\b|\bSlider\b|\bStepper\b|\bMenu\b"
    r"|onTapGesture|\.gesture\(|contentShape|DisclosureGroup|NavigationLink"
    r"|buttonStyle|isButton"
)

# Declarations whose border is information rather than a boundary. One entry,
# because the moment there are several the rule is wrong rather than the code.
#
# `rollKey` draws the piano roll's legend, and each swatch's outline carries the
# *dash pattern* that encodes a note's harmonic role — solid, hatched, dashed.
# That is what makes the key survive without colour, which is the only reason a
# key is worth having. Removing the outline there would delete the information
# the swatch exists to carry.
EXEMPT_DECLARATIONS = {"rollKey"}

# A declaration boundary: a struct, or a computed view / function returning one.
DECLARATION = re.compile(
    r"^\s*(?:@ViewBuilder\s+)?(?:private |fileprivate |public |)"
    r"(?:struct|var|func)\s+(\w+)"
)


def declarations(source: str):
    """Yields (name, start line, end line) for each view declaration."""
    lines = source.split("\n")
    found = []
    for index, line in enumerate(lines):
        match = DECLARATION.match(line)
        if not match:
            continue
        if not ("some View" in line or line.lstrip().startswith("struct")):
            continue
        found.append((match.group(1), index))
    for position, (name, start) in enumerate(found):
        end = found[position + 1][1] if position + 1 < len(found) else len(lines)
        yield name, start, end


def check() -> int:
    failures = 0
    checked = 0

    for path in sorted(p for d in UI_DIRS for p in d.glob("*.swift")):
        lines = path.read_text().split("\n")
        source = "\n".join(lines)
        for name, start, end in declarations(source):
            body = "\n".join(lines[start:end])
            borders = body.count("strokeBorder(")
            if not borders:
                continue
            checked += borders
            if name in EXEMPT_DECLARATIONS or INTERACTIVE.search(body):
                continue
            # Report the line, so the fix is one jump away.
            offset = next(i for i, line in enumerate(lines[start:end])
                          if "strokeBorder(" in line)
            failures += 1
            print(f"  FAIL  {path.name}:{start + offset + 1} — border on `{name}`, "
                  "which has nothing to press")
            print("        borderStrong identifies a control; a group separates "
                  "by surface and space")

    print(f"  {checked} borders checked, each attributed to what it encloses")
    if failures:
        print(f"borders: {failures} FAILURES")
        return 1
    print("borders: every border is on something interactive")
    return 0


if __name__ == "__main__":
    sys.exit(check())
