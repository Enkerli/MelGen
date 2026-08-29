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
MELODY = ROOT / "MelGenExtension" / "Melody"

# Melody files whose strings reach the screen. The whole folder would sweep in
# the prose handed to the model and the fingerprints a parser matches on, which
# are not interface text and would have to be exempted one by one; these are the
# files that carry labels, verbs, explanations and status sentences. Named
# rather than globbed so that adding one is a decision.
MELODY_SURFACES = [
    "ActionTense.swift",        # the three badges and the three verb buttons
    "MelodyCuration.swift",     # the three aims, and the promise each makes
    "MaterialSource.swift",     # the source rows and the primary action's verb
    "NextStep.swift",           # the one line that says what to do now
    "MelodyComping.swift",      # PlayMode's labels and explanations
    "Bassline.swift",           # the figure names and the settings summary
    "MelodyChain.swift",        # LearnedDraw's labels
    "MelGenState.swift",        # the palette and appearance labels
]

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
    # The harmony is a *progression*. "Changes" is what a musician says to
    # another musician who already knows; on screen it only parses if you have
    # already read it as a progression, which was settled in the second device
    # session and then drifted back into a dozen strings because nothing
    # checked. The verb is untouched — "re-roll changes what you are hearing" is
    # ordinary English — so the pattern only fires on a determiner or a
    # preposition, which is what makes "changes" a noun.
    (r"\b(the|these|those|its|their|our|any|no|new|own|with|from|over|against|under|of)"
     r"\s+changes\b",
     '"changes" as a noun',
     'the harmony is a "progression"'),
]

# "pass" is allowed only where a reader can tell *which* pass is meant. That is
# the editorial rule the whole vocabulary rests on: if the sentence doesn't
# disambiguate, neither will whoever reads the code next, which is how a mark
# ended up keyed on the drift counter.
CURATION_CONTEXT = re.compile(
    r"curation|\bmark\b|\bmarks\b|judged|judge|sweep|Review|passes through"
    # A pass with an ordinal or a determiner in front of it is a sweep being
    # counted, and a lap is never spoken about that way — nobody says "a further
    # pass" about a loop traversal. Bare "pass" and "passes" stay caught, which
    # is where the take/pass/loop confusion actually lived.
    r"|\b(this|that|the same|a further|another|the next|the first|the second"
    r"|the third|second|third|later) pass\b"
    r"|\bpass \d",
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


# Literals that look like interface text and are not. One entry, because the
# moment there are many the scope is wrong rather than the exemptions.
EXEMPT_LITERALS = {
    "changes",   # MIDIFileImport's list of names a chord track might give itself
}


def check() -> int:
    failures = 0
    checked = 0

    surfaces = sorted(UI.glob("*.swift")) + [MELODY / name for name in MELODY_SURFACES]
    for path in surfaces:
        source = path.read_text()
        for number, literal in string_literals(source):
            checked += 1
            if literal in EXEMPT_LITERALS:
                continue
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
