#!/bin/bash
#
# Checks the parts of MelGen that the Xcode test targets can't reach: the DSP
# kernel (C++ inside the extension) and the Melody sources (extension-only
# target membership). Everything here runs outside Xcode with swiftc/clang++.
#
#   Scripts/verify.sh            # all checks
#   Scripts/verify.sh chords     # just one
#
# Checks:
#   chords  — MelGen's ported chord dictionary against Music Suite's TypeScript,
#             symbol by symbol (quality, scale, tensions, avoid notes)
#   state   — session state round-trip and the expression/swing pass
#   chunking — how a progression is split into model requests (context window)
#   patterns — stored generic lines fitted to real harmony, with no model
#   extraction — takes read back as degree-relative patterns, and the fit report
#   curation — dispositions, passes, facets and the review queue
#   phrases — gestures, the phrase grammar, and the lines it composes
#   stylemodel — slot statistics over kept takes, and sampling new lines from them
#   chain — the variable-order model: what follows what, with backoff
#   mutation — transforms, variant scoring, and the morph between two lines
#   retrieval — finding a line rather than making one, and being surprised on purpose
#   topics — grouping the library so the vocabulary can come from the material
#   steps — interval cells: Hanon's self-sequencing figures and Samchillian streams
#   capture — pairing, segmenting and quantizing what was played in
#   comping — the voicing layer, voice leading, and chords instead of a line
#   progression — generating the changes, ported from ProgGenie's corpus tables
#   analysis — take measurement (variety, harmonic roles) and the dead-air guard
#   kernel  — melody scheduling: forward/backward/ping-pong, host sync, loop counter
#   contrast — WCAG 2.1 AA on every theme token pairing the UI uses, both themes
#   identity — the audio component triple is unique across the suite and matches
#              the host app's lookup
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MELODY="$REPO/MelGenExtension/Melody"
DSP="$REPO/MelGenExtension/DSP"
PARAMS="$REPO/MelGenExtension/Parameters"
MUSIC_SUITE="${MUSIC_SUITE:-$REPO/../../music-suite}"
# Every Melody source except the one that needs FoundationModels. They are one
# interdependent set now — the pattern format knows about curation, curation
# knows about analysis — and keeping a hand-written list per suite meant every
# new file broke four of them for no reason anyone learned anything from.
melody_sources() {
    find "$MELODY" -name "*.swift" ! -name "MelodyGenerator.swift" | sort
}

# The Swift suites build unoptimized, and the reason is measured rather than
# assumed. With every suite compiling every Melody source, -O costs about 64
# seconds per suite and saves about 0.6 seconds of run time: a quarter of an hour
# of optimizer to save nine seconds. -Onone builds the same suite in 18 seconds.
# A test harness is a thing you run constantly, so it optimizes for the loop you
# are actually in.
SWIFT_OPT="-Onone"

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

which="${1:-all}"
status=0

run_chords() {
    echo "── chords ─────────────────────────────────────────"
    local dist="$MUSIC_SUITE/packages/theory/dist"
    if [ ! -d "$dist" ]; then
        echo "SKIP: music-suite not found at $MUSIC_SUITE (set MUSIC_SUITE=...)"
        return 0
    fi

    python3 "$REPO/Scripts/generate-chord-dictionary.py" --music-suite "$MUSIC_SUITE" --check || status=1

    MUSIC_SUITE_DIST="$dist" node "$REPO/Scripts/tests/chord-reference.mjs" > "$BUILD/reference.json" || {
        echo "FAIL: reference harness did not run"; status=1; return 0; }

    # Swift only allows top-level code in a file called main.swift.
    cp "$REPO/Scripts/tests/chord-swift-main.swift" "$BUILD/main.swift"
    swiftc -O "$MELODY/ChordDictionary.swift" "$MELODY/ChordDictionary+Generated.swift" \
        "$MELODY/ChordScale.swift" "$MELODY/ChordParser.swift" \
        "$BUILD/main.swift" -o "$BUILD/chords" || { status=1; return 0; }
    "$BUILD/chords" > "$BUILD/swift.json" || { status=1; return 0; }

    python3 - "$BUILD/reference.json" "$BUILD/swift.json" <<'PY' || status=1
import json, sys
ts = {r["symbol"]: r for r in json.load(open(sys.argv[1]))}
sw = {r["symbol"]: r for r in json.load(open(sys.argv[2]))}
fields = ["key", "rootPc", "tones", "scale", "scalePcs", "avoid", "tensions"]
diffs = 0
for symbol, expected in ts.items():
    actual = sw.get(symbol)
    if actual is None:
        print(f"MISSING {symbol}"); diffs += 1; continue
    if "error" in expected or "error" in actual:
        if expected.get("error") != actual.get("error"):
            print(f"ERRDIFF {symbol} ts={expected.get('error')} swift={actual.get('error')}")
            diffs += 1
        continue
    for field in fields:
        if expected[field] != actual[field]:
            print(f"DIFF {symbol:12} {field:9} ts={expected[field]} swift={actual[field]}")
            diffs += 1
print(f"{len(ts)} symbols compared, {diffs} differences")
sys.exit(1 if diffs else 0)
PY
}

run_state() {
    echo "── state ─────────────────────────────────────────"
    cp "$REPO/Scripts/tests/state-expression-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/state" || { status=1; return 0; }
    "$BUILD/state" || status=1
}

run_identity() {
    echo "── identity ───────────────────────────────────────"
    python3 "$REPO/Scripts/tests/component-identity.py" || status=1
}

run_chunking() {
    echo "── chunking ───────────────────────────────────────"
    cp "$REPO/Scripts/tests/chunking-main.swift" "$BUILD/main.swift"
    swiftc -O "$MELODY/ChordDictionary.swift" "$MELODY/ChordDictionary+Generated.swift" \
        "$MELODY/ChordScale.swift" "$MELODY/ChordParser.swift" "$MELODY/MelodyChunker.swift" \
        "$BUILD/main.swift" -o "$BUILD/chunking" || { status=1; return 0; }
    "$BUILD/chunking" || status=1
}

run_patterns() {
    echo "── patterns ──────────────────────────────────────"
    cp "$REPO/Scripts/tests/patterns-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/patterns" || { status=1; return 0; }
    "$BUILD/patterns" || status=1
}

run_extraction() {
    echo "── extraction ────────────────────────────────────"
    cp "$REPO/Scripts/tests/extraction-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/extraction" || { status=1; return 0; }
    "$BUILD/extraction" || status=1
}

run_curation() {
    echo "── curation ──────────────────────────────────────"
    cp "$REPO/Scripts/tests/curation-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/curation" || { status=1; return 0; }
    "$BUILD/curation" || status=1
}

run_phrases() {
    echo "── phrases ───────────────────────────────────────"
    cp "$REPO/Scripts/tests/phrases-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/phrases" || { status=1; return 0; }
    "$BUILD/phrases" || status=1
}

run_stylemodel() {
    echo "── stylemodel ────────────────────────────────────"
    cp "$REPO/Scripts/tests/stylemodel-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/stylemodel" || { status=1; return 0; }
    "$BUILD/stylemodel" || status=1
}

run_chain() {
    echo "── chain ─────────────────────────────────────────"
    cp "$REPO/Scripts/tests/chain-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/chain" || { status=1; return 0; }
    "$BUILD/chain" || status=1
}

run_mutation() {
    echo "── mutation ──────────────────────────────────────"
    cp "$REPO/Scripts/tests/mutation-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/mutation" || { status=1; return 0; }
    "$BUILD/mutation" || status=1
}

run_retrieval() {
    echo "── retrieval ─────────────────────────────────────"
    cp "$REPO/Scripts/tests/retrieval-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/retrieval" || { status=1; return 0; }
    "$BUILD/retrieval" || status=1
}

run_topics() {
    echo "── topics ────────────────────────────────────────"
    cp "$REPO/Scripts/tests/topics-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/topics" || { status=1; return 0; }
    "$BUILD/topics" || status=1
}

run_steps() {
    echo "── steps ─────────────────────────────────────────"
    cp "$REPO/Scripts/tests/steps-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/steps" || { status=1; return 0; }
    "$BUILD/steps" || status=1
}

run_capture() {
    echo "── capture ───────────────────────────────────────"
    cp "$REPO/Scripts/tests/capture-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/capture" || { status=1; return 0; }
    "$BUILD/capture" || status=1
}

run_comping() {
    echo "── comping ───────────────────────────────────────"
    cp "$REPO/Scripts/tests/comping-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/comping" || { status=1; return 0; }
    "$BUILD/comping" || status=1
}

run_progression() {
    echo "── progression ───────────────────────────────────"
    python3 "$REPO/Scripts/generate-progression-tables.py" --music-suite "$MUSIC_SUITE" --check || status=1
    cp "$REPO/Scripts/tests/progression-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/progression" || { status=1; return 0; }
    "$BUILD/progression" || status=1
}

run_analysis() {
    echo "── analysis ──────────────────────────────────────"
    cp "$REPO/Scripts/tests/analysis-main.swift" "$BUILD/main.swift"
    # shellcheck disable=SC2046
    swiftc $SWIFT_OPT $(melody_sources) "$BUILD/main.swift" -o "$BUILD/analysis" || { status=1; return 0; }
    "$BUILD/analysis" || status=1
}

run_contrast() {
    echo "── contrast ───────────────────────────────────────"
    python3 "$REPO/Scripts/tests/contrast-audit.py" || status=1
}

run_kernel() {
    echo "── kernel ─────────────────────────────────────────"
    clang++ -std=gnu++17 -fobjc-arc -x objective-c++ \
        "$REPO/Scripts/tests/kernel-scheduling.mm" -I"$DSP" -I"$PARAMS" \
        -framework Foundation -framework AudioToolbox -framework CoreMIDI \
        -o "$BUILD/kernel" || { status=1; return 0; }
    "$BUILD/kernel" || status=1
}

case "$which" in
    all)      run_identity; run_chords; run_state; run_chunking; run_patterns; run_extraction; run_curation; run_phrases; run_stylemodel; run_chain; run_mutation; run_retrieval; run_topics; run_steps; run_capture; run_comping; run_progression; run_analysis; run_contrast; run_kernel ;;
    chords)   run_chords ;;
    state)    run_state ;;
    chunking) run_chunking ;;
    patterns) run_patterns ;;
    extraction) run_extraction ;;
    curation) run_curation ;;
    phrases)  run_phrases ;;
    stylemodel) run_stylemodel ;;
    chain)    run_chain ;;
    mutation) run_mutation ;;
    retrieval) run_retrieval ;;
    topics)   run_topics ;;
    steps)    run_steps ;;
    capture)  run_capture ;;
    comping)  run_comping ;;
    progression) run_progression ;;
    analysis) run_analysis ;;
    contrast) run_contrast ;;
    identity) run_identity ;;
    kernel)   run_kernel ;;
    *) echo "usage: Scripts/verify.sh [all|identity|chords|state|chunking|patterns|extraction|curation|phrases|stylemodel|chain|mutation|retrieval|topics|steps|capture|comping|progression|analysis|contrast|kernel]"; exit 2 ;;
esac

echo
if [ "$status" -eq 0 ]; then echo "verify: OK"; else echo "verify: FAILURES"; fi
exit "$status"
