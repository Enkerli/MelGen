#!/usr/bin/env python3
"""Checks MelGen.icon against the design pass and the Icon Composer rules.

The icon is the one asset nobody opens for months at a time, so the ways it
rots are quiet ones: a colour drifts away from the theme tokens the plug-in
actually paints with, a shape creeps outside the corner mask, or someone bakes
a shadow into the SVG and it fights the system's. None of that shows up in a
build — `actool` compiles a wrong icon just as happily as a right one.

Three things are checked here.

*Geometry* — the six bars, to the point. The design fixed them on the roll's
eighth-note grid inside a 800×800 content box inset 112 all round, which is
also what keeps the mark off the squircle's corners.

*Colour* — every fill is one of the theme tokens, and every layer carries both
a universal value and a `dark` specialization. Without the dark one the system
keeps the light fill and the ink stack vanishes into the dark ground; that is
the failure this file exists to catch, because it looks fine in Xcode's canvas.

*Cleanliness* — no strokes, shadows, gradients, filters or text in the
artwork. The system draws all of that as Liquid Glass, and a painted copy
double-draws.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
ICON = ROOT / "MelGen" / "MelGen.icon"
PBXPROJ = ROOT / "MelGen.xcodeproj" / "project.pbxproj"

CANVAS = 1024
INSET = 112

# The theme tokens, as MelGenTheme.swift paints them, in the form Icon
# Composer stores colours. Keyed by the name the design brief uses.
TOKENS = {
    "paper": "extended-srgb:0.98824,0.98431,0.96863,1.00000",   # #fcfbf7
    "ground-dark": "extended-srgb:0.10196,0.09412,0.07843,1.00000",  # #1a1814
    "ink": "extended-srgb:0.17647,0.16863,0.15294,1.00000",     # #2d2b27
    "ink-dark": "extended-srgb:0.90980,0.88235,0.82353,1.00000",  # #e8e1d2
    "accent": "extended-srgb:0.18431,0.40000,0.64706,1.00000",  # #2f66a5
    "accent-dark": "extended-srgb:0.42745,0.63922,0.87451,1.00000",  # #6da3df
}

# The mark, from the design pass: a voicing stacked at one x, and a line
# stepping up and to the right in short–long–short.
GEOMETRY = {
    "Voicing.svg": [(112, 462, 190, 100), (112, 622, 190, 100), (112, 782, 190, 100)],
    "Melody.svg": [(344, 622, 152, 100), (528, 462, 232, 100), (792, 302, 120, 100)],
}

CORNER_RADIUS = 30

# Anything here in the artwork fights the system's own rendering.
BAKED = re.compile(
    r"<(?:text|filter|linearGradient|radialGradient|feGaussianBlur|image)\b"
    r"|\bstroke\s*=|\bfilter\s*=|\bstyle\s*=",
    re.IGNORECASE)

RECT = re.compile(
    r'<rect\b[^>]*\bx="([-\d.]+)"[^>]*\by="([-\d.]+)"'
    r'[^>]*\bwidth="([-\d.]+)"[^>]*\bheight="([-\d.]+)"'
    r'[^>]*\brx="([-\d.]+)"')


def fail(problem: str, remedy: str) -> int:
    print(f"  FAIL  {problem}")
    print(f"        {remedy}")
    return 1


def check_artwork() -> int:
    """The six bars, where the design put them, drawn with nothing baked in."""
    failures = 0
    for name, expected in GEOMETRY.items():
        path = ICON / "Assets" / name
        if not path.exists():
            failures += fail(f"{name} is missing",
                             "the layer's artwork is what Icon Composer renders")
            continue
        source = path.read_text()

        if 'viewBox="0 0 1024 1024"' not in source:
            failures += fail(f"{name} is not on the 1024 canvas",
                             'every layer shares viewBox="0 0 1024 1024"')

        baked = BAKED.search(source)
        if baked:
            failures += fail(f"{name} bakes in {baked.group(0)!r}",
                             "the system draws shadow, highlight and material itself")

        drawn = [tuple(round(float(v)) for v in m.groups()[:4])
                 for m in RECT.finditer(source)]
        if drawn != expected:
            failures += fail(f"{name} geometry has drifted",
                             f"expected {expected}, found {drawn}")

        for match in RECT.finditer(source):
            if round(float(match.group(5))) != CORNER_RADIUS:
                failures += fail(f"{name} has a bar with a different corner",
                                 f"every bar is rx {CORNER_RADIUS}")
                break

        for x, y, w, h in drawn:
            if x < INSET or y < INSET or x + w > CANVAS - INSET or y + h > CANVAS - INSET:
                failures += fail(f"{name} leaves the {INSET}pt inset at {(x, y, w, h)}",
                                 "the corner mask crops what reaches the edge")
    return failures


def specialized(value: object, where: str) -> tuple[int, dict]:
    """A specialization list: one universal entry, then the dark override."""
    if not isinstance(value, list) or not value:
        return fail(f"{where} has no specializations",
                    "expected a list whose first entry carries no appearance"), {}
    found = {}
    failures = 0
    if "appearance" in value[0]:
        failures += fail(f"{where} has no universal value",
                         "the first entry is the default and names no appearance")
    else:
        found["universal"] = value[0].get("value")
    for entry in value[1:]:
        found[entry.get("appearance", "universal")] = entry.get("value")
    if "dark" not in found:
        failures += fail(f"{where} has no dark value",
                         "without it the system keeps the light fill in dark mode")
    return failures, found


def solid(value: object) -> str | None:
    return value.get("solid") if isinstance(value, dict) else None


def check_document() -> int:
    """The layer stack, and a token colour for each appearance."""
    manifest = ICON / "icon.json"
    if not manifest.exists():
        return fail("MelGen.icon/icon.json is missing",
                    "the icon is a folder holding icon.json and Assets/")
    document = json.loads(manifest.read_text())
    failures = 0

    count, background = specialized(document.get("fill-specializations"),
                                    "the background")
    failures += count
    if background:
        universal = background.get("universal")
        if not isinstance(universal, dict) or \
                universal.get("automatic-gradient") != TOKENS["paper"]:
            failures += fail("the light ground is not the paper token",
                             f"expected automatic-gradient {TOKENS['paper']}")
        if solid(background.get("dark")) != TOKENS["ground-dark"]:
            failures += fail("the dark ground is not the theme's own dark",
                             f"expected solid {TOKENS['ground-dark']}")

    groups = document.get("groups", [])
    names = [group.get("name") for group in groups]
    if names != ["Voicing", "Melody"]:
        failures += fail(f"the groups are {names}",
                         "two groups, Voicing under Melody — one specular per gesture")

    wanted = {"Voicing": ("ink", "ink-dark"), "Melody": ("accent", "accent-dark")}
    for group in groups:
        name = group.get("name")
        if group.get("lighting") != "combined":
            failures += fail(f"{name} lights its layers individually",
                             "combined keeps one highlight across the gesture")
        if len(group.get("layers", [])) != 1:
            failures += fail(f"{name} is not a single layer",
                             "six layers gives six highlights and the mark breaks up")
            continue
        layer = group["layers"][0]
        if layer.get("image-name") != f"{name}.svg":
            failures += fail(f"{name} does not draw {name}.svg",
                             f"found {layer.get('image-name')!r}")
        count, fills = specialized(layer.get("fill-specializations"),
                                   f"{name}'s fill")
        failures += count
        if not fills:
            continue
        light_token, dark_token = wanted[name]
        if solid(fills.get("universal")) != TOKENS[light_token]:
            failures += fail(f"{name}'s light fill is not the {light_token} token",
                             f"expected solid {TOKENS[light_token]}")
        if solid(fills.get("dark")) != TOKENS[dark_token]:
            failures += fail(f"{name}'s dark fill is not the {dark_token} token",
                             f"expected solid {TOKENS[dark_token]}")

    return failures


def check_project() -> int:
    """The icon has to be the one the app target actually ships."""
    failures = 0
    settings = PBXPROJ.read_text()
    if "ASSETCATALOG_COMPILER_APPICON_NAME = MelGen;" not in settings:
        failures += fail("the app target does not name MelGen as its icon",
                         "ASSETCATALOG_COMPILER_APPICON_NAME = MelGen")
    if (ROOT / "MelGen" / "Assets.xcassets" / "AppIcon.appiconset").exists():
        failures += fail("AppIcon.appiconset is still in the catalogue",
                         "the .icon replaces it; two icons is ambiguous to actool")
    return failures


def check() -> int:
    failures = check_artwork() + check_document() + check_project()
    bars = sum(len(rects) for rects in GEOMETRY.values())
    print(f"  {bars} bars, 2 layer groups and 6 fills checked against the design")
    if failures:
        print(f"icon: {failures} FAILURES")
        return 1
    print("icon: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(check())
