#!/usr/bin/env python3
"""Checks the interface against TERMINOLOGY.md.

One word per concept, one concept per word. The reason this is a test rather
than a convention is in the design brief: three of one week's bugs were the
take/pass/loop confusion arriving as code, including a mark keyed on the drift
counter showing up on a different take. A vocabulary nothing enforces goes back
to meaning three things within a month.

Only *user-facing strings* are checked. Identifiers are exempt and named as
outstanding renames in TERMINOLOGY.md — `mutationPass`, `curationPass`,
`selectedBriefNames` — because renaming stored properties changes what a saved
session decodes, which is a separate job with a migration attached.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
UI = ROOT / "MelGenExtension" / "UI"

# Identifiers that legitimately contain a retired word. Exempt by exact match
# inside an interpolation, not by substring anywhere.
EXEMPT_IDENTIFIERS = {
    "mutationPass", "curationPass", "regenerateEveryPasses", "currentPass",
    "selectedBriefNames", "briefCursor", "briefMode", "lockedBriefName",
    "briefName", "onPass", "reviewProgress",
}

# (pattern, what's wrong, what to use). Patterns run over string literals only.
RULES = [
    (r"\bvariation\b",
     '"variation" is retired',
     'a candidate transform is a "variant"; a kept one is a take with a parent'),
    (r"\bTexture\b",
     '"Texture" is retired',
     'use "Next take" and "Now playing" — the real difference is when they apply'),
    (r"\bpass(es)?\b(?![^\"]*curation)",
     '"pass" outside curation',
     'a traversal of the loop is a "lap"; a drift re-roll is a "roll"'),
]

# "pass" is allowed only where a reader can tell *which* pass is meant. That is
# the editorial rule the whole vocabulary rests on: if the sentence doesn't
# disambiguate, neither will whoever reads the code next, which is how a mark
# ended up keyed on the drift counter.
CURATION_CONTEXT = re.compile(
    r"curation|\bmark\b|\bmarks\b|judged|judge|sweep|Review|this pass|passes through",
    re.IGNORECASE)


def string_literals(source: str):
    """Yields (line number, literal) for every Swift string literal."""
    for number, line in enumerate(source.splitlines(), 1):
        # Skip comment-only lines: comments may use any word, and several
        # deliberately explain the retired ones.
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("///"):
            continue
        for literal in re.findall(r'"((?:[^"\\]|\\.)*)"', line):
            yield number, literal


def check() -> int:
    failures = 0
    checked = 0

    for path in sorted(UI.glob("*.swift")):
        source = path.read_text()
        for number, literal in string_literals(source):
            checked += 1
            if CURATION_CONTEXT.search(literal):
                continue
            # Strip interpolated identifiers before matching: `\(mutationPass)`
            # is an identifier, not a word shown to anyone.
            visible = re.sub(r"\\\([^)]*\)", " ", literal)
            for pattern, problem, remedy in RULES:
                if not re.search(pattern, visible, re.IGNORECASE):
                    continue
                # A rule may still be satisfied by an exempt identifier that the
                # interpolation-stripping missed.
                if any(name.lower() in literal.lower() for name in EXEMPT_IDENTIFIERS):
                    if not re.search(pattern, visible, re.IGNORECASE):
                        continue
                print(f"  FAIL  {path.name}:{number} — {problem}")
                print(f"        {literal[:96]}")
                print(f"        {remedy}")
                failures += 1

    print(f"  {checked} interface strings checked against TERMINOLOGY.md")
    if failures:
        print(f"terminology: {failures} FAILURES")
        return 1
    print("terminology: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(check())
