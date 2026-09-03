#!/usr/bin/env python3
"""Diffs MelGen's progression port against ProgGenie's own answers.

Run by `Scripts/verify.sh proggen`, which produces both files first:
`proggen-reference.mjs` (ProgGenie, in JS) and `proggen-swift-main.swift`
(MelGen, in Swift), over the same labels in the same three keys.

    python3 Scripts/tests/proggen-diff.py reference.json swift.json

What is compared, and what deliberately isn't, is the whole design of the check
— see PORTING.md §7. Briefly:

  compared    how a corpus label splits (numeral, suffix); where the numeral
              lands in semitones above the tonic, which each side derives
              independently; whether the label is playable; and for a playable
              one, the root pitch class and the quality key
  not         the spelling. ProgGenie writes the ♯IV of B major as E♯m7b5,
              MelGen writes Fm7b5, because MelGen's leadsheet has to be one its
              own parser reads back. Same chord, different orthography, and
              insisting on orthography would be inventing a contract nobody
              agreed to
  not         the sampling. Surprise is not temperature, Freshness has no
              ProgGenie equivalent, and MelGen's Reharm is an explicit
              superset. Those differ on purpose and a vector that pinned them
              would be pinning the wrong thing
"""

from __future__ import annotations

import json
import sys

diffs = 0


def differ(label: str, field: str, expected: object, actual: object) -> None:
    global diffs
    print(f"  DIFF {label!r:14} {field:22} proggen={expected!r} melgen={actual!r}")
    diffs += 1


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: proggen-diff.py <reference.json> <swift.json>")

    with open(sys.argv[1], encoding="utf-8") as handle:
        reference = {row["label"]: row for row in json.load(handle)}
    with open(sys.argv[2], encoding="utf-8") as handle:
        swift = {row["label"]: row for row in json.load(handle)}

    global diffs
    for label, expected in reference.items():
        actual = swift.get(label)
        if actual is None:
            print(f"  MISSING {label!r}")
            diffs += 1
            continue

        # How a corpus label is read. No room to differ: the tables are shared,
        # so a label MelGen splits differently is a label it walks differently.
        for field in ("numeral", "suffix"):
            if expected[field] != actual[field]:
                differ(label, field, expected[field], actual[field])

        for key, want in expected["realized"].items():
            got = actual["realized"].get(key)
            if (want is None) != (got is None):
                differ(label, f"realized[{key}]", want, got)
                continue
            if want is None:
                continue

            # Where the numeral lands, derived independently on each side —
            # ProgGenie by spelling the degree and subtracting the tonic,
            # MelGen straight from the numeral's accidentals. Agreement here is
            # the actual port check.
            if want["semitonesAboveTonic"] != got["semitonesAboveTonic"]:
                differ(label, f"{key}:semitones",
                       want["semitonesAboveTonic"], got["semitonesAboveTonic"])

            # Whether MelGen will emit it at all. A contract rather than a
            # match: ProgGenie names anything, MelGen refuses what its own
            # dictionary cannot play, because a generated progression that
            # fails to parse is worse than no progression.
            if want["playable"] != got["playable"]:
                differ(label, f"{key}:playable", want["playable"], got["playable"])
            if not (want["playable"] and got["playable"]):
                continue

            if want["rootPc"] != got["rootPc"]:
                differ(label, f"{key}:rootPc", want["rootPc"], got["rootPc"])
            if want["qualityKey"] != got["qualityKey"]:
                differ(label, f"{key}:quality", want["qualityKey"], got["qualityKey"])

    keys = len(next(iter(reference.values()))["realized"]) if reference else 0
    print(f"  {len(reference)} labels compared in {keys} keys, {diffs} differences")
    sys.exit(1 if diffs else 0)


if __name__ == "__main__":
    main()
