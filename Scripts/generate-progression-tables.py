#!/usr/bin/env python3
"""Generates MelGen's Swift copy of ProgGenie's corpus transition tables.

The tables are counts over Roman-numeral labels — "I" → {"V7": 607, "IV": 591, …}
— learned from a leadsheet corpus, plus a trigram layer keyed "A → B". They are
generated rather than transcribed for the same reason the chord dictionary is
(ROADMAP I4): a hand-copied table drifts, and nobody notices until the music is
wrong in a way that looks like a bug in something else.

    python3 Scripts/generate-progression-tables.py            # write
    python3 Scripts/generate-progression-tables.py --check    # fail on drift

The full corpus is ~360KB of JSON. Only the top transitions per context are
carried: the tail is a long list of things seen once, which contributes almost
nothing to the sound and a great deal to the binary. --top controls it.
"""

import argparse
import json
import os
import sys

HEADER = '''//
//  ProgressionTables+Generated.swift
//  MelGenExtension
//
//  GENERATED — do not edit. Run Scripts/generate-progression-tables.py.
//
//  Corpus transition counts over Roman-numeral labels, from ProgGenie
//  (music-suite/packages/proggen). First order — what follows "IIm7" — and
//  second order, keyed "IIm7 → V7", so the generator can blend the two and back
//  off to the first when a context is sparse. The same shape as the melodic
//  chain in MelodyChain.swift, which is not a coincidence: it's the same problem
//  one level up.
//
//  Encoded as strings rather than as dictionary literals because a Swift
//  dictionary literal of this size takes the type checker minutes and the
//  binary a great deal of space. Parsed once, lazily.
//

import Foundation

enum ProgressionTables {

    /// context;next:count,next:count|context;… — parsed on first use.
'''


def encode(table, top):
    parts = []
    for context, row in sorted(table.items()):
        entries = sorted(row.items(), key=lambda kv: (-kv[1], kv[0]))[:top]
        if not entries:
            continue
        body = ",".join(f"{label}:{count}" for label, count in entries)
        parts.append(f"{context};{body}")
    return "|".join(parts)


def swift_string(name, value):
    # Chunked so no single literal is enormous; Swift concatenates at compile
    # time and the type checker copes with a few dozen pieces.
    chunk = 900
    pieces = [value[i:i + chunk] for i in range(0, len(value), chunk)]
    joined = "\n        + ".join(
        '"' + piece.replace("\\", "\\\\").replace('"', '\\"') + '"' for piece in pieces
    )
    return f"    static let {name} =\n        {joined}\n"


def build(source, top):
    transitions = json.load(open(os.path.join(source, "transitions.json")))
    trigrams = json.load(open(os.path.join(source, "trigrams.json")))

    out = [HEADER]
    for mode in ("major", "minor"):
        out.append(swift_string(f"{mode}Bigrams", encode(transitions.get(mode, {}), top)))
        out.append("\n")
        out.append(swift_string(f"{mode}Trigrams", encode(trigrams.get(mode, {}), top)))
        out.append("\n")
    out.append("}\n")
    return "".join(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--music-suite", default=None)
    parser.add_argument("--top", type=int, default=14)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    suite = args.music_suite or os.environ.get("MUSIC_SUITE") or os.path.join(repo, "..", "..", "music-suite")
    source = os.path.join(suite, "packages", "proggen", "src", "data")
    if not os.path.isdir(source):
        print(f"SKIP: proggen data not found at {source}")
        return 0

    generated = build(source, args.top)
    target = os.path.join(repo, "MelGenExtension", "Melody", "ProgressionTables+Generated.swift")

    if args.check:
        if not os.path.exists(target):
            print("FAIL: generated tables missing")
            return 1
        current = open(target).read()
        if current != generated:
            print("FAIL: progression tables have drifted from music-suite — regenerate")
            return 1
        print("progression tables up to date")
        return 0

    open(target, "w").write(generated)
    print(f"wrote {target} ({len(generated)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
