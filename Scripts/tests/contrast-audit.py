#!/usr/bin/env python3
"""WCAG 2.1 contrast audit for MelGen's theme tokens.

Parses the hex values straight out of MelGenTheme.swift so the audit can't drift
from the code, then checks every foreground/surface pairing the UI actually uses,
on both themes. Mirrors music-suite/packages/ui/tools/contrast-audit.mjs.

Thresholds: text ≥4.5:1 (every label in this UI is below 18pt), and ≥3:1 for
boundaries that identify a control and for the accent as a UI component colour.
`textDisabled` is WCAG-exempt and only used for disabled controls.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

THEME = Path(__file__).resolve().parent.parent.parent / "MelGenExtension" / "UI" / "MelGenTheme.swift"

TEXT_MIN = 4.5
COMPONENT_MIN = 3.0

# (foreground token, surface token, threshold, what it's for)
CHECKS = [
    ("text", "background", TEXT_MIN, "primary text on paper"),
    ("text", "raised", TEXT_MIN, "primary text on a panel"),
    ("text", "sunken", TEXT_MIN, "primary text in a field"),
    ("textSecondary", "background", TEXT_MIN, "status text on paper"),
    ("textSecondary", "raised", TEXT_MIN, "take summary on a panel"),
    ("textMuted", "background", TEXT_MIN, "eyebrows and slider end labels"),
    ("textMuted", "raised", TEXT_MIN, "history subtitle on a panel"),
    ("textMuted", "sunken", TEXT_MIN, "history subtitle on the selected row"),
    ("accentText", "accent", TEXT_MIN, "Play / Generate button label"),
    ("borderStrong", "background", COMPONENT_MIN, "control outline on paper"),
    ("borderStrong", "raised", COMPONENT_MIN, "control outline on a panel"),
    ("accent", "background", COMPONENT_MIN, "selected control fill on paper"),
    ("accent", "raised", COMPONENT_MIN, "selected control fill on a panel"),
    ("accent", "sunken", COMPONENT_MIN, "selected row outline"),
    # The piano roll fills notes with these on the roll's own surface, so they
    # are UI component colours rather than text — 3:1, and against `sunken`
    # because that's what the roll is drawn on.
    ("warning", "sunken", COMPONENT_MIN, "avoid-note fill in the piano roll"),
    ("warning", "raised", COMPONENT_MIN, "avoid-note fill on a chord's lighter region"),
]


def parse_themes(source: str) -> dict[str, dict[str, tuple[int, int, int]]]:
    themes: dict[str, dict[str, tuple[int, int, int]]] = {}
    for theme_name in ("light", "dark"):
        match = re.search(
            rf"static let {theme_name} = MelGenTheme\((.*?)\n    \)", source, re.S
        )
        if not match:
            sys.exit(f"error: could not find the {theme_name} theme in {THEME.name}")
        tokens: dict[str, tuple[int, int, int]] = {}
        for token, hexvalue in re.findall(r"(\w+): Color\(hex: 0x([0-9a-fA-F]{6})\)", match.group(1)):
            value = int(hexvalue, 16)
            tokens[token] = ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
        themes[theme_name] = tokens
    return themes


def luminance(rgb: tuple[int, int, int]) -> float:
    channels = []
    for raw in rgb:
        c = raw / 255
        channels.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    r, g, b = channels
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    la, lb = luminance(a), luminance(b)
    lighter, darker = max(la, lb), min(la, lb)
    return (lighter + 0.05) / (darker + 0.05)


def main() -> None:
    themes = parse_themes(THEME.read_text(encoding="utf-8"))
    failures = 0

    for theme_name, tokens in themes.items():
        print(f"  {theme_name}:")
        for foreground, surface, threshold, purpose in CHECKS:
            if foreground not in tokens or surface not in tokens:
                print(f"    FAIL  missing token {foreground} or {surface}")
                failures += 1
                continue
            value = ratio(tokens[foreground], tokens[surface])
            ok = value >= threshold
            if not ok:
                failures += 1
            print(f"    {'PASS' if ok else 'FAIL'}  {value:5.2f}:1 "
                  f"(needs {threshold}) {foreground} on {surface} — {purpose}")

    print()
    if failures:
        print(f"contrast: {failures} FAILURES")
        sys.exit(1)
    print("contrast: all pairings meet WCAG 2.1 AA")


if __name__ == "__main__":
    main()
