#!/usr/bin/env python3
"""Generates MelGen's Swift chord dictionary from Music Suite's TypeScript source.

The dictionary is owned by music-suite/packages/theory (itself ported from the
MIDIsplainer Chord-Dictionary branch). Rather than hand-transcribing 174 chord
qualities into Swift and letting the two drift, this reads the TypeScript and
emits the Swift table.

    python3 Scripts/generate-chord-dictionary.py [--music-suite PATH] [--check]

--check exits non-zero if the generated file is out of date, for CI.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MUSIC_SUITE = REPO_ROOT.parent.parent / "music-suite"
OUTPUT = REPO_ROOT / "MelGenExtension" / "Melody" / "ChordDictionary+Generated.swift"

# One dictionary entry per line in chords.ts, e.g.
#   { key: "maj7", fullName: "major seventh", displayName: "∆", pcs: [0,4,7,11], ... }
ENTRY_RE = re.compile(
    r'\{\s*key:\s*"(?P<key>[^"]*)",'
    r'\s*fullName:\s*"(?P<full>[^"]*)",'
    r'\s*displayName:\s*"(?P<display>[^"]*)",'
    r'\s*pcs:\s*\[(?P<pcs>[^\]]*)\],'
    r'.*?aliases:\s*\[(?P<aliases>[^\]]*)\]'
)

# The quoted-key form must allow an empty key: MANUAL_SUFFIX_KEYS maps "" to
# "maj", which is how a bare root like "C" resolves to a major triad.
RECORD_RE = re.compile(r'^\s*(?:"(?P<qkey>[^"]*)"|(?P<bkey>[A-Za-z_][\w]*)):\s*"(?P<value>[^"]*)",?\s*$')


def parse_qualities(chords_ts: Path) -> list[dict]:
    qualities: list[dict] = []
    for line in chords_ts.read_text(encoding="utf-8").splitlines():
        match = ENTRY_RE.search(line)
        if not match:
            continue
        pcs = [int(v) for v in match.group("pcs").replace(" ", "").split(",") if v != ""]
        aliases = json.loads("[" + match.group("aliases") + "]")
        qualities.append({
            "key": match.group("key"),
            "fullName": match.group("full"),
            "displayName": match.group("display"),
            "pcs": pcs,
            "aliases": aliases,
        })
    if not qualities:
        sys.exit(f"error: no chord qualities parsed from {chords_ts}")
    return qualities


def parse_string_record(source: str, name: str) -> dict[str, str]:
    """Pulls a `const NAME: Record<string, string> = { ... }` literal."""
    start = source.find(f"const {name}")
    if start < 0:
        sys.exit(f"error: {name} not found in chordSymbol.ts")
    open_brace = source.index("{", start)
    depth = 0
    for index in range(open_brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                body = source[open_brace + 1:index]
                break
    else:
        sys.exit(f"error: unterminated {name} literal")

    entries: dict[str, str] = {}
    for line in body.splitlines():
        line = line.split("//")[0]
        match = RECORD_RE.match(line)
        if match:
            key = match.group("qkey") if match.group("qkey") is not None else match.group("bkey")
            entries[key] = match.group("value")
    return entries


def swift_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def swift_string_list(values: list[str]) -> str:
    return "[" + ", ".join(swift_string(v) for v in values) + "]"


def render(qualities: list[dict], manual: dict[str, str], display: dict[str, str], source_note: str) -> str:
    lines = [
        "//",
        "//  ChordDictionary+Generated.swift",
        "//  MelGenExtension",
        "//",
        "//  GENERATED FILE — DO NOT EDIT BY HAND.",
        "//  Regenerate with: python3 Scripts/generate-chord-dictionary.py",
        f"//  Source: {source_note}",
        "//",
        "",
        "import Foundation",
        "",
        "extension ChordDictionary {",
        "",
        f"    /// Every chord quality in the dictionary ({len(qualities)} entries).",
        "    static let allQualities: [ChordQuality] = [",
    ]
    for quality in qualities:
        pcs = ", ".join(str(pc) for pc in quality["pcs"])
        lines.append(
            "        ChordQuality("
            f"key: {swift_string(quality['key'])}, "
            f"fullName: {swift_string(quality['fullName'])}, "
            f"displaySymbol: {swift_string(quality['displayName'])}, "
            f"pitchClasses: [{pcs}], "
            f"aliases: {swift_string_list(quality['aliases'])}),"
        )
    lines += [
        "    ]",
        "",
        "    /// Shorthand suffixes the alias table doesn't cover, mapped to quality keys.",
        "    static let manualSuffixKeys: [String: String] = [",
    ]
    for suffix in sorted(manual):
        lines.append(f"        {swift_string(suffix)}: {swift_string(manual[suffix])},")
    lines += [
        "    ]",
        "",
        "    /// Canonical compact suffix used when displaying a quality.",
        "    static let displaySuffixes: [String: String] = [",
    ]
    for key in sorted(display):
        lines.append(f"        {swift_string(key)}: {swift_string(display[key])},")
    lines += [
        "    ]",
        "}",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--music-suite", type=Path, default=DEFAULT_MUSIC_SUITE)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    theory = args.music_suite / "packages" / "theory" / "src"
    chords_ts = theory / "chords.ts"
    symbol_ts = theory / "chordSymbol.ts"
    for path in (chords_ts, symbol_ts):
        if not path.exists():
            sys.exit(f"error: {path} not found (pass --music-suite)")

    qualities = parse_qualities(chords_ts)
    symbol_source = symbol_ts.read_text(encoding="utf-8")
    manual = parse_string_record(symbol_source, "MANUAL_SUFFIX_KEYS")
    display = parse_string_record(symbol_source, "DISPLAY_SUFFIXES")

    known = {q["key"] for q in qualities}
    for suffix, key in sorted(manual.items()):
        if key not in known:
            print(f"warning: manual suffix {suffix!r} maps to unknown quality {key!r}", file=sys.stderr)

    rendered = render(qualities, manual, display, "music-suite/packages/theory/src/{chords,chordSymbol}.ts")

    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != rendered:
            sys.exit("error: ChordDictionary+Generated.swift is out of date")
        print("chord dictionary up to date")
        return

    OUTPUT.write_text(rendered, encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(REPO_ROOT)}: {len(qualities)} qualities, "
          f"{len(manual)} manual suffixes, {len(display)} display suffixes")


if __name__ == "__main__":
    main()
