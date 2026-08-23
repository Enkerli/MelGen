#!/bin/bash
#
# Reads exported take histories and reports what's in them: where takes came
# from, what generation cost, how much of the corpus is the same line twice, the
# facet spread, and the style the material would teach.
#
#   Scripts/analyse-history.sh ~/Library/Mobile\ Documents/com~apple~CloudDocs
#   Scripts/analyse-history.sh export-a.json export-b.json
#
# Compiles the real Melody sources rather than reimplementing the measurements,
# so what this prints is what the plug-in would compute.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MELODY="$REPO/MelGenExtension/Melody"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

if [ "$#" -eq 0 ]; then
    echo "usage: Scripts/analyse-history.sh <export.json | directory> …"
    exit 2
fi

cp "$REPO/Scripts/history-analysis-main.swift" "$BUILD/main.swift"
# shellcheck disable=SC2046
swiftc -O $(find "$MELODY" -name "*.swift" ! -name "MelodyGenerator.swift" | sort) \
    "$BUILD/main.swift" -o "$BUILD/analyse" || exit 1

"$BUILD/analyse" "$@"
