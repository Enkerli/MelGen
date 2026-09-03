#!/usr/bin/env python3
"""Checks the seam a second plug-in would have to cut along.

PORTING.md argues that MelGen is really four layers stacked — an AU shell, a
theory layer, a carrier layer and a UI kit, with the melody app on top — and
that a sibling plug-in (ProgGenie first) reuses the bottom four. That argument
is worth exactly as much as it is checkable, so this checks it.

The method is a crude but honest one: strip comments and string literals from
every Swift source in the extension, find every top-level type declaration, and
call it an edge whenever one file names a type another file declares. Layer the
files, then look for edges that point *upward* — a theory file reaching into the
melody app, a UI component that only works because a bass figure exists.

Every upward edge is a cut the extraction has to make. They are listed below,
with a note on how each one gets cut, so the file doubles as the work list. The
check fails when a NEW one appears — which is the point: the layering is not
enforced by the compiler today (one target, one module), so without this the
seam silently closes again between commits.

It also fails when a listed seam has been cut, because a work list that keeps
finished items is a work list nobody reads.

    python3 Scripts/tests/foundation-boundary.py
    python3 Scripts/tests/foundation-boundary.py --graph   # every edge, layered

What this deliberately does NOT do: resolve scope. A local type shadowing a
top-level one, or a name used only inside a comment-free string, will read as an
edge. It over-reports rather than under-reports, which is the right direction
for a boundary check — a false edge costs a glance, a missed one costs the port.
"""

from __future__ import annotations

import argparse
import collections
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
EXTENSION = REPO / "MelGenExtension"

# ── The layers ──────────────────────────────────────────────────────────────
#
# Order matters: a file may name types from its own layer and any layer below,
# never above. The names are the ones PORTING.md uses.

CORE = "core"          # primitives with no music in them at all
THEORY = "theory"      # chords, scales, voice leading, progressions — the suite's own
CARRIER = "carrier"    # what a take is made of, and how it is stored, judged, exported
SHELL = "shell"        # AU plumbing: parameters, the C++ kernel, the view controller
UIKIT = "ui"           # controls and views that know nothing about melody
APP = "app"            # MelGen itself

# Rank, not order: the shell and the UI kit are siblings. Both sit on the
# carrier — the kernel is handed SequencedNotes and the piano roll draws them —
# and neither may reach for the other. An edge is upward when the target's rank
# is strictly higher than the source's, so shell → carrier is fine and
# shell → ui is not.
RANK = {CORE: 0, THEORY: 1, CARRIER: 2, SHELL: 3, UIKIT: 3, APP: 4}
ORDER = [CORE, THEORY, CARRIER, SHELL, UIKIT, APP]

# Nothing may be below theory except things with no music in them. The seeded
# RNG is the whole layer today, and that is the right size for it: the moment a
# second thing lands here, check it is really a primitive and not a chord in
# disguise.
CORE_FILES = {
    "SeededRandom.swift",
}

THEORY_FILES = {
    "ChordDictionary.swift",
    "ChordDictionary+Generated.swift",
    "ChordScale.swift",
    "ChordParser.swift",
    "ChordDetection.swift",
    "DiatonicHarmony.swift",
    "VoiceLeading.swift",
    "ChordVoicing.swift",
    "ProgressionGenerator.swift",
    "ProgressionTables+Generated.swift",
}

CARRIER_FILES = {
    "MelodyPattern.swift",      # THE interchange format: a degree-relative line
    "MelodyModels.swift",       # SequencedNote — what the kernel and the MIDI files speak
    "MelodyAnalysis.swift",     # measurement, which curation needs and melody doesn't own
    "MaterialSource.swift",     # where material comes from, and what a take came from
    "ActionTense.swift",        # now / take / aims — the interaction grammar, not the music
    "MelodyCuration.swift",     # dispositions, passes, facets, the tag vocabulary
    "DeadAir.swift",            # a realization repair, not an expression setting
    "PatternStore.swift",
    "StandardMIDIFile.swift",
    "MIDIFileImport.swift",
    "MIDIFileExport.swift",
}

UIKIT_FILES = {
    "MelGenTheme.swift",
    "PianoRoll.swift",
    "ParameterSlider.swift",
    "MomentaryButton.swift",
    "ActionBadge.swift",
    "DirectionIcon.swift",
    "MelGenPanelParts.swift",
    "CurationView.swift",
    "RateAndAdvance.swift",
}

# ── The seams ───────────────────────────────────────────────────────────────
#
# Every upward edge that exists today, keyed (file, symbol it reaches for), with
# how it gets cut. Cutting one means deleting its line here. Adding one without
# a line here fails the check.

SEAMS: dict[tuple[str, str], str] = {
    # ── The shell's hooks into the app ──────────────────────────────────────
    # Expected, and the shape enkerli-juce uses for its archetype functions:
    # a foundation that is generic over the app it hosts. Three of these become
    # one generic parameter and one protocol.
    ("AudioUnitViewController.swift", "MelGenExtensionMainView"):
        "the root view — becomes a generic parameter",
    ("MelGenExtensionAudioUnit.swift", "MelGenState"):
        "session state — becomes a Codable the app supplies",
    ("MelGenExtensionAudioUnit.swift", "SetupStore"):
        "named setups — same treatment as MelGenState",
    ("MelGenExtensionAudioUnit.swift", "CapturedMIDIEvent"):
        "the capture ring's event type. The ring is foundation (it is in the "
        "C++ kernel); what an event means is not. Move the struct down.",

    # ── Theory reaching upward ──────────────────────────────────────────────
    ("ChordDetection.swift", "SequencedNote"):
        "detection takes the carrier's note type. Harmless as a rank, listed "
        "because theory should take [Int] pitch classes and let the caller "
        "unwrap — that is what makes it portable to a plug-in with no notes.",
    ("ChordVoicing.swift", "DegreeHistogram"):
        "REAL coupling: the Drawn voicing asks the learned histogram which "
        "colour this chord can carry. Invert it — the caller passes weights "
        "in, theory never reaches up for them.",
    ("ChordVoicing.swift", "DegreeContext"):
        "the same call, its argument type. Closes with the one above.",

    # ── The carrier reaching upward ─────────────────────────────────────────
    # What is left after MelodyPattern was ruled the interchange format, which
    # closed five of these and, by moving TakeSource down with it, a sixth.
    ("PatternStore.swift", "MelodyStepPatterns"):
        "interval cells — melody-specific. The store should be generic over "
        "what it stores rather than naming both kinds.",
    ("MaterialSource.swift", "PlayMode"):
        "line / chords / bass. A MelGen distinction; the source list should "
        "be filtered by a predicate the app supplies.",

    # ── The UI kit reaching upward ──────────────────────────────────────────
    ("CurationView.swift", "GenerationRecord"):
        "the take record. The view wants four fields of it — take a small "
        "view-model struct instead.",
    ("CurationView.swift", "MelodyVariant"):
        "variant naming — pass strings, not the variant type",
    ("MelGenPanelParts.swift", "NextStep"):
        "'what to do now' — the panel should take a String",
}

# Files that are melody-specific by construction and are NOT proposed for the
# foundation, listed so their absence reads as a decision rather than an
# oversight. FigurePad draws bass figures; the main view is the app.
NOT_FOUNDATION = {
    "FigurePad.swift": "draws bass seeds — a MelGen control, not a suite one",
    "MelGenExtensionMainView.swift": "the app",
    "MelGenState.swift": "enumerates every MelGen subsystem",
    "MelGenSetup.swift": "the same, saved",
}

DECLARATION = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:public |internal |private |fileprivate |open |final |indirect )*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Z]\w*)",
    re.M,
)
BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)
LINE_COMMENT = re.compile(r"//.*")
STRING_LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')
CAPITALIZED = re.compile(r"\b[A-Z]\w*\b")

failures = 0


def fail(message: str) -> None:
    global failures
    failures += 1
    print(f"  FAIL  {message}")


def ok(message: str) -> None:
    print(f"  PASS  {message}")


def layer_of(path: Path) -> str:
    parts = path.parts
    if "Common" in parts or "DSP" in parts or "Parameters" in parts:
        return SHELL
    if path.name in CORE_FILES:
        return CORE
    if path.name in THEORY_FILES:
        return THEORY
    if path.name in CARRIER_FILES:
        return CARRIER
    if path.name in UIKIT_FILES:
        return UIKIT
    return APP


def strip(source: str) -> str:
    """Comments and string literals out, so a name in prose isn't an edge."""
    source = BLOCK_COMMENT.sub(" ", source)
    source = LINE_COMMENT.sub(" ", source)
    return STRING_LITERAL.sub('""', source)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--graph", action="store_true",
                        help="print every cross-file edge, grouped by layer")
    args = parser.parse_args()

    sources = {p: strip(p.read_text(encoding="utf-8"))
               for p in sorted(EXTENSION.rglob("*.swift"))}
    if not sources:
        sys.exit(f"error: no Swift sources under {EXTENSION}")

    # Where each top-level type is declared. First declaration wins; extensions
    # are not declarations, which is deliberate — an extension in the app on a
    # foundation type is not the app owning it.
    declared_in: dict[str, Path] = {}
    for path, text in sources.items():
        for name in DECLARATION.findall(text):
            declared_in.setdefault(name, path)

    lines = collections.Counter()
    for path in sources:
        lines[layer_of(path)] += len(path.read_text(encoding="utf-8").splitlines())

    edges: list[tuple[Path, Path, str]] = []
    for path, text in sources.items():
        for name in sorted(set(CAPITALIZED.findall(text))):
            home = declared_in.get(name)
            if home is not None and home != path:
                edges.append((path, home, name))

    print(f"  {len(sources)} sources, {len(declared_in)} top-level types, "
          f"{len(edges)} cross-file references")
    print()
    for layer in ORDER:
        label = "foundation" if layer != APP else "MelGen"
        print(f"  {layer:>8}  {lines[layer]:>6,} lines  ({label})")
    foundation = sum(lines[l] for l in ORDER if l != APP)
    share = 100 * foundation / max(1, sum(lines.values()))
    print(f"  {'':>8}  {foundation:>6,} lines  foundation total ({share:.0f}%)")
    print()

    if args.graph:
        for source, target, name in sorted(
                edges, key=lambda e: (e[0].name, e[1].name, e[2])):
            print(f"  {layer_of(source):>8} {source.name} → "
                  f"{layer_of(target):>8} {target.name}  ({name})")
        print()

    # 1. No new upward edges.
    upward = [(s, t, n) for s, t, n in edges
              if RANK[layer_of(t)] > RANK[layer_of(s)]]
    seen: set[tuple[str, str]] = set()
    unlisted: list[tuple[Path, Path, str]] = []
    for source, target, name in upward:
        key = (source.name, name)
        seen.add(key)
        if key not in SEAMS:
            unlisted.append((source, target, name))

    if unlisted:
        for source, target, name in sorted(unlisted, key=lambda e: e[0].name):
            fail(f"new upward reference: [{layer_of(source)}] {source.name} → "
                 f"[{layer_of(target)}] {name} ({target.name}) — cut it, or add "
                 f"it to SEAMS with how it gets cut")
    else:
        ok(f"no upward references beyond the {len(SEAMS)} known seams")

    # 2. No stale entries: a cut seam leaves the list.
    stale = sorted(set(SEAMS) - seen)
    for path_name, symbol in stale:
        fail(f"seam already cut, remove it from SEAMS: {path_name} → {symbol}")
    if not stale and SEAMS:
        ok(f"every listed seam is still real ({len(SEAMS)} to cut)")

    # 3. The layer manifest names files that exist.
    names = {p.name for p in sources}
    for group, label in ((CORE_FILES, "core"), (THEORY_FILES, "theory"), (CARRIER_FILES, "carrier"),
                         (UIKIT_FILES, "ui"), (set(NOT_FOUNDATION), "not-foundation")):
        missing = sorted(group - names)
        if missing:
            fail(f"{label} manifest names files that don't exist: {', '.join(missing)}")
    if failures == 0:
        ok("the layer manifest matches the sources on disk")

    print()
    if failures:
        print(f"foundation-boundary: {failures} failure(s)")
        sys.exit(1)
    print("foundation-boundary: OK")


if __name__ == "__main__":
    main()
