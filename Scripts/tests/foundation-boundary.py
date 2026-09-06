#!/usr/bin/env python3
"""Checks the seam a second plug-in is built on.

PORTING.md argues that MelGen is really four layers stacked — an AU shell, a
theory layer, a carrier layer and a UI kit, with the melody app on top — and
that a sibling plug-in (ProgGenie first) reuses the bottom four. That argument
is worth exactly as much as it is checkable, so this checks it.

Four of the five layers are now separate targets of the `EnkerliSwift` package,
which means the compiler refuses an upward reference before this script ever
runs. That does not make the script redundant, and it is worth being clear about
what is left of its job:

  - **The shell is not a package target yet** (see Package.swift for the three
    reasons), so shell → app is still only checked here.
  - **The compiler cannot see a sibling violation.** UI and Shell are siblings
    by rank, and Package.swift expresses that by giving neither a dependency on
    the other — but the moment someone adds one, the build goes green. This
    checks that they stay siblings. It got that wrong itself until the package
    was built: the rank test only failed on a *strictly* higher rank, so a
    `ui → shell` edge passed silently, and two Xcode-template controls had been
    binding to `ObservableAUParameter` the whole time.
  - **The counts.** PORTING.md §1's percentage is this script's output.
  - **Proposing a move.** Editing the manifest and running it says what a
    reclassification would cost before a file is touched — which is how three of
    the last four cuts were decided.

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
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
EXTENSION = REPO / "MelGenExtension"
# A sibling checkout, the way enkerli-juce is (PORTING.md §7 step 3). Override
# with ENKERLI_SWIFT=... ; without it there is nothing to check the layering of.
PACKAGE = Path(os.environ.get("ENKERLI_SWIFT",
                              REPO.parent.parent / "enkerli-swift")) / "Sources"
# The package's own directory names are the layer names, so a file's target is
# its layer and there is nothing to keep in step by hand.
PACKAGE_LAYERS = {"Core": "core", "Theory": "theory", "Carrier": "carrier",
                  "AUHost": "auhost",
                  "Shell": "shell", "Kernel": "shell", "UI": "ui",
                  "Instrument": "instrument", "AudioKernel": "instrument"}

# ── The layers ──────────────────────────────────────────────────────────────
#
# Order matters: a file may name types from its own layer and any layer below,
# never above. The names are the ones PORTING.md uses.

CORE = "core"          # primitives with no music in them at all
THEORY = "theory"      # chords, scales, voice leading, progressions — the suite's own
CARRIER = "carrier"    # what a take is made of, and how it is stored, judged, exported
AUHOST = "auhost"      # AU plumbing with no music and no MIDI in it: the observable
                       # parameter tree, the spec DSL, the view-controller lifecycle
SHELL = "shell"        # a MIDI processor's half of an audio unit: the C++ kernel,
                       # the note map, the curve lanes
INSTRUMENT = "instrument"  # an instrument's half: the audio render path and the
                       # C++ voice. A sibling of the shell, never a layer of it
UIKIT = "ui"           # controls and views that know nothing about melody
APP = "app"            # MelGen itself

# Rank, not order: the shell and the UI kit are siblings. Both sit on the
# carrier — the kernel is handed SequencedNotes and the piano roll draws them —
# and neither may reach for the other. An edge is upward when the target's rank
# is strictly higher than the source's, so shell → carrier is fine and
# shell → ui is not.
#
# `auhost` was inserted below both when the synth arrived. A synth's audio unit
# cannot subclass the MIDI processor's, and needed the lifecycle around it — so
# the lifecycle, the observable parameter tree and the spec DSL went one layer
# down, where an instrument can reach them without the MIDI kernel.
RANK = {CORE: 0, THEORY: 1, CARRIER: 2, AUHOST: 3,
        SHELL: 4, UIKIT: 4, INSTRUMENT: 4, APP: 5}
ORDER = [CORE, THEORY, CARRIER, AUHOST, SHELL, INSTRUMENT, UIKIT, APP]

# Downward by rank and still forbidden.
#
# `ui → auhost` is the edge this exists for. The UI kit is controls that know
# nothing about melody *and nothing about audio units*: a slider bound to an
# `AUParameter` is not a control a plug-in without AU parameters can use, which
# is exactly how two Xcode-template controls sat in the UI kit unremarked until
# the package was built. Those two are in `auhost` now, which is where they
# belong — and rank alone would happily let them be reached for again from `ui`,
# because `auhost` is genuinely below it.
# `shell` and `instrument` are already caught by sharing a rank — an edge
# between two different layers of equal rank is a violation, which is how the
# shell/UI sibling rule works and why the synth needed no new machinery.
FORBIDDEN: set[tuple[str, str]] = {(UIKIT, AUHOST)}

# The four foundation layers below the app are the `EnkerliSwift` package's
# targets now, and `layer_of` reads a package source's layer off its directory —
# so there is no list here to keep in step with them, and no way for a new file
# in `Sources/Theory/` to default to `app` in silence the way `MiniRoll` once did.
#
# What is left in the extension is the shell (`Common/`, `DSP/`, `Parameters/`,
# by directory) and MelGen itself.

# ── The seams ───────────────────────────────────────────────────────────────
#
# Every upward edge that exists today, keyed (file, symbol it reaches for), with
# how it gets cut. Cutting one means deleting its line here. Adding one without
# a line here fails the check.

SEAMS: dict[tuple[str, str], str] = {
    # ── Theory reaching upward ──────────────────────────────────────────────

    # ── The carrier reaching upward ─────────────────────────────────────────
    # What is left after MelodyPattern was ruled the interchange format, which
    # closed five of these and, by moving TakeSource down with it, a sixth.

    # ── The UI kit reaching upward ──────────────────────────────────────────
}

# Files that are melody-specific by construction and are NOT proposed for the
# foundation, listed so their absence reads as a decision rather than an
# oversight. FigurePad draws bass figures; the main view is the app.
NOT_FOUNDATION = {
    "FigurePad.swift": "draws bass seeds — a MelGen control, not a suite one",
    "AudioUnitViewController.swift":
        "MelGen's three overrides on PluginViewController. Info.plist names this "
        "class, so it keeps the name and the shell took the other one",
    "MelGenExtensionAudioUnit.swift":
        "MelGen's session half of PluginAudioUnit — the state, and what the "
        "kernel plays out of it",
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
    # A package source is whatever target it is in. Nothing to keep in step.
    for directory, layer in PACKAGE_LAYERS.items():
        if directory in parts and "Sources" in parts:
            return layer
    if "Common" in parts or "DSP" in parts or "Parameters" in parts:
        return SHELL
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
               for p in sorted(list(EXTENSION.rglob("*.swift")) + list(PACKAGE.rglob("*.swift")))}
    if not sources:
        sys.exit(f"error: no Swift sources under {EXTENSION} or {PACKAGE}")
    if not PACKAGE.is_dir():
        sys.exit(f"error: no foundation package at {PACKAGE.parent} — clone "
                 f"https://github.com/Enkerli/enkerli-swift beside this checkout, "
                 f"or set ENKERLI_SWIFT")

    # Where each type is declared. Extensions are not declarations, which is
    # deliberate — an extension in the app on a foundation type is not the app
    # owning it.
    #
    # *Every* declarer is recorded, not the first one, because the regex matches
    # nested types too and two of those can share a simple name:
    # `TakeFacets.Density` in the carrier and `MelodyIdea.Density` in the app are
    # different types spelled the same. Keeping only the first made the answer
    # depend on which directory sorted earlier, which is a fine thing to discover
    # by moving the foundation into a sibling checkout and watching two seams
    # appear out of nowhere, and a terrible thing to leave in a check.
    declared_in: dict[str, list[Path]] = {}
    for path, text in sources.items():
        for name in DECLARATION.findall(text):
            declared_in.setdefault(name, []).append(path)

    lines = collections.Counter()
    for path in sources:
        lines[layer_of(path)] += len(path.read_text(encoding="utf-8").splitlines())

    edges: list[tuple[Path, Path, str]] = []
    for path, text in sources.items():
        for name in sorted(set(CAPITALIZED.findall(text))):
            homes = declared_in.get(name, [])
            if path in homes:
                # This file declares it. `TakeFacets.Density` naming `Density`
                # is not a reference to `MelodyIdea.Density` in the app, however
                # the two sort.
                continue
            if not homes:
                continue
            # A name declared in more than one place is an edge to the *lowest*
            # of them: if any file at or below this layer declares it, naming it
            # is not a reach upward, whichever one the compiler actually resolves.
            edges.append((path, min(homes, key=lambda h: RANK[layer_of(h)]), name))

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

    # 1. No new upward edges — and no sideways ones between the two siblings.
    #
    # Equal rank is only allowed within a layer. Shell and UI share rank 3
    # because neither is above the other, which is not the same as them being
    # free to name each other: the kernel is handed notes and the piano roll
    # draws them, and a control that binds to an AU parameter is not a control a
    # plug-in without AU parameters can use. Comparing ranks alone missed that
    # for as long as this script existed.
    def is_upward(source: Path, target: Path) -> bool:
        a, b = layer_of(source), layer_of(target)
        if (a, b) in FORBIDDEN:
            return True
        return RANK[b] > RANK[a] or (RANK[b] == RANK[a] and a != b)

    upward = [(s, t, n) for s, t, n in edges if is_upward(s, t)]
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
    for group, label in ((set(NOT_FOUNDATION), "not-foundation"),):
        missing = sorted(group - names)
        if missing:
            fail(f"{label} manifest names files that don't exist: {', '.join(missing)}")

    # 3b. …and knows about every target on disk.
    #
    # The hole this closes: `AudioKernel` and `Instrument` were added to the
    # package and this script counted neither, because `layer_of` reads a
    # directory name out of PACKAGE_LAYERS and quietly returns `app` for anything
    # it does not recognise. The counts stayed plausible and the layering went
    # unchecked — which is the same failure mode as `MiniRoll` defaulting to
    # `app` in silence, the one the package targets were supposed to have made
    # impossible.
    if PACKAGE.is_dir():
        on_disk = {d.name for d in PACKAGE.iterdir() if d.is_dir()}
        unlisted = sorted(on_disk - set(PACKAGE_LAYERS))
        if unlisted:
            fail("package targets with no layer: " + ", ".join(unlisted)
                 + " — add them to PACKAGE_LAYERS with a rank, or this script "
                   "counts them as app and checks nothing about them")
    if failures == 0:
        ok("the layer manifest matches the sources on disk")

    print()
    if failures:
        print(f"foundation-boundary: {failures} failure(s)")
        sys.exit(1)
    print("foundation-boundary: OK")


if __name__ == "__main__":
    main()
