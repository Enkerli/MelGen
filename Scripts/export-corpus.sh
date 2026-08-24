#!/bin/bash
#
# Turns MelGen's material into a tokenized corpus for off-device training, and
# reports what the shipping variable-order chain scores on the held-out half.
#
#   Scripts/export-corpus.sh ~/Library/Mobile\ Documents/com~apple~CloudDocs
#   Scripts/export-corpus.sh --events corpus/events.jsonl --out corpus
#   Scripts/export-corpus.sh history/ --events corpus/events.jsonl --all-takes
#
# Compiles the real Melody sources rather than reimplementing extraction, so the
# degrees in the corpus are the degrees the plug-in would compute. That is the
# whole reason this stage is Swift and not Python — see COREML.md.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MELODY="$REPO/MelGenExtension/Melody"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

if [ "$#" -eq 0 ]; then
    echo "usage: Scripts/export-corpus.sh [history.json | directory …] [--events events.jsonl] [--out dir]"
    exit 2
fi

cp "$REPO/Scripts/corpus-export-main.swift" "$BUILD/main.swift"
# shellcheck disable=SC2046
swiftc -O $(find "$MELODY" -name "*.swift" ! -name "MelodyGenerator.swift" | sort) \
    "$BUILD/main.swift" -o "$BUILD/export" || exit 1

"$BUILD/export" "$@"
