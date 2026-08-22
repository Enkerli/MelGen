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
#   kernel  — melody scheduling: forward/backward/ping-pong, host sync, loop counter
#   contrast — WCAG 2.1 AA on every theme token pairing the UI uses, both themes
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MELODY="$REPO/MelGenExtension/Melody"
DSP="$REPO/MelGenExtension/DSP"
PARAMS="$REPO/MelGenExtension/Parameters"
MUSIC_SUITE="${MUSIC_SUITE:-$REPO/../../music-suite}"
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
    echo "── state ──────────────────────────────────────────"
    cp "$REPO/Scripts/tests/state-expression-main.swift" "$BUILD/main.swift"
    swiftc -O "$MELODY/MelodyModels.swift" "$MELODY/MelGenState.swift" \
        "$MELODY/MelodyExpression.swift" "$MELODY/StyleBriefs.swift" \
        "$BUILD/main.swift" -o "$BUILD/state" || { status=1; return 0; }
    "$BUILD/state" || status=1
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
    all)      run_chords; run_state; run_contrast; run_kernel ;;
    chords)   run_chords ;;
    state)    run_state ;;
    contrast) run_contrast ;;
    kernel)   run_kernel ;;
    *) echo "usage: Scripts/verify.sh [all|chords|state|contrast|kernel]"; exit 2 ;;
esac

echo
if [ "$status" -eq 0 ]; then echo "verify: OK"; else echo "verify: FAILURES"; fi
exit "$status"
