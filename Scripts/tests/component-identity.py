#!/usr/bin/env python3
"""Checks MelGen's audio component identity.

An AUv3 is identified by the (type, subtype, manufacturer) triple, not by its
name or bundle ID. Two components sharing a triple means the host resolves
*either* name to whichever one it indexed — which is how loading Progression
Studio in AUM launched MelGen: the Xcode template's default subtype was "Prst",
Progression Studio's code.

Checks:
  1. The extension's Info.plist and the host app's lookup agree on the triple.
  2. The subtype doesn't collide with any sibling plug-in's PLUGIN_CODE.
  3. The bundle identifier doesn't collide either — a different failure with a
     worse symptom, since the plug-in then does not appear at all.
  4. The display name follows the "Manufacturer: Product" convention hosts
     expect, so AUM shows "MelGen" rather than a target name.

Siblings are found two ways, because there are two kinds: the JUCE plug-ins
declare PLUGIN_CODE in CMakeLists.txt, and a Swift AUv3 declares its triple in
the extension's Info.plist and has no CMakeLists at all.
"""

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
INFO_PLIST = REPO / "MelGenExtension" / "Info.plist"
PROJECT = REPO / "MelGen.xcodeproj" / "project.pbxproj"
HOST_MODEL = REPO / "MelGen" / "Model" / "AudioUnitHostModel.swift"
# Sibling plug-ins live alongside the MelGen checkout.
SIBLING_ROOT = REPO.parent.parent

failures = 0


def fail(message: str) -> None:
    global failures
    failures += 1
    print(f"  FAIL  {message}")


def ok(message: str) -> None:
    print(f"  PASS  {message}")


def main() -> None:
    with INFO_PLIST.open("rb") as handle:
        info = plistlib.load(handle)
    try:
        component = info["NSExtension"]["NSExtensionAttributes"]["AudioComponents"][0]
    except (KeyError, IndexError):
        sys.exit("error: no AudioComponents entry in Info.plist")

    au_type = component.get("type", "")
    subtype = component.get("subtype", "")
    manufacturer = component.get("manufacturer", "")
    name = component.get("name", "")
    print(f"  identity: {au_type}/{subtype}/{manufacturer} — {name!r}")

    for label, value in (("type", au_type), ("subtype", subtype), ("manufacturer", manufacturer)):
        if len(value) != 4:
            fail(f"{label} must be exactly four characters, got {value!r}")

    # 1. The host app looks the extension up by the same triple.
    source = HOST_MODEL.read_text(encoding="utf-8")
    match = re.search(
        r'init\(type: String = "(\w{4})",\s*subType: String = "(\w{4})",\s*'
        r'manufacturer: String = "(\w{4})"\)',
        source,
    )
    if not match:
        fail(f"couldn't find the component triple in {HOST_MODEL.name}")
    else:
        host_triple = match.groups()
        if host_triple == (au_type, subtype, manufacturer):
            ok(f"host app looks up the same triple ({'/'.join(host_triple)})")
        else:
            fail(f"host app looks up {'/'.join(host_triple)}, Info.plist declares "
                 f"{au_type}/{subtype}/{manufacturer} — the host app won't find the extension")

    # 2. No sibling plug-in claims this subtype.
    #
    # Two kinds of sibling now. The JUCE plug-ins declare their code in
    # CMakeLists.txt; a Swift AUv3 has an Info.plist and no CMakeLists at all,
    # which PORTING.md §9 called out as the point where this check would quietly
    # stop checking — "the second Swift AUv3 is the point at which that lookup
    # needs to learn about Info.plist siblings too". This is that.
    #
    # The Info.plist search goes two levels deep because a Swift plug-in's
    # extension plist is at <repo>/<Target>Extension/Info.plist rather than at
    # the repo root, and it skips this repo's own so MelGen does not collide with
    # itself.
    siblings: dict[str, list[str]] = {}
    for cmake in sorted(SIBLING_ROOT.glob("*/CMakeLists.txt")):
        text = cmake.read_text(encoding="utf-8", errors="replace")
        for code in re.findall(r"PLUGIN_CODE\s+([A-Za-z0-9]{4})", text):
            siblings.setdefault(code, []).append(cmake.parent.name)

    for plist in sorted(SIBLING_ROOT.glob("*/*/Info.plist")) + sorted(SIBLING_ROOT.glob("*/*/*/Info.plist")):
        if plist == INFO_PLIST:
            continue
        try:
            with plist.open("rb") as handle:
                other = plistlib.load(handle)
            component = other["NSExtension"]["NSExtensionAttributes"]["AudioComponents"][0]
            code = component["subtype"]
        except (KeyError, IndexError, ValueError, OSError):
            continue
        label = plist.relative_to(SIBLING_ROOT).parts[0]
        if label not in siblings.setdefault(code, []):
            siblings[code].append(label)

    if not siblings:
        print(f"  SKIP  no sibling plug-ins found next to the checkout ({SIBLING_ROOT})")
    elif subtype in siblings:
        fail(f"subtype {subtype!r} collides with {', '.join(siblings[subtype])} — "
             f"hosts will confuse the two plug-ins")
    else:
        ok(f"subtype {subtype!r} is unique across {len(siblings)} sibling codes "
           f"({', '.join(sorted(siblings))})")

    # 3. Hosts show the part after "Manufacturer: ", so it should read as the
    #    product name rather than a build target.
    if ": " not in name:
        fail(f"name {name!r} should be \"Manufacturer: Product\"")
    else:
        product = name.split(": ", 1)[1]
        if "Extension" in product:
            fail(f"name {name!r} exposes the target name — hosts will display "
                 f"{product!r} rather than the product name")
        else:
            ok(f"display name reads {product!r}")


    # 4. No sibling plug-in claims this bundle identifier.
    #
    # The triple is not the only forever identifier, and this check learned that
    # the hard way: the Swift Serpe was built with `com.enkerli.Serpe` while the
    # JUCE one ships `com.enkerli.serpe`, and the Swift plug-in **did not appear
    # in AUM at all**. Same story waiting for PitchFold, whose JUCE CMakeLists
    # sets `com.enkerli.PitchFold` and carries its own warning: "installed
    # devices have it".
    #
    # A colliding subtype makes a host load the wrong plug-in, which is bad and
    # visible. A colliding bundle ID makes a plug-in silently not exist, which
    # is worse, because there is nothing to notice. Both are forever.
    bundle_ids: dict[str, list[str]] = {}
    for cmake in sorted(SIBLING_ROOT.glob("*/CMakeLists.txt")):
        text = cmake.read_text(encoding="utf-8", errors="replace")
        for bundle in re.findall(r'BUNDLE_ID\s+"([^"]+)"', text):
            bundle_ids.setdefault(bundle.lower(), []).append(cmake.parent.name)

    for project in sorted(SIBLING_ROOT.glob("*/*.xcodeproj/project.pbxproj")):
        repo = project.relative_to(SIBLING_ROOT).parts[0]
        if repo == REPO.name:
            continue
        text = project.read_text(encoding="utf-8", errors="replace")
        for bundle in set(re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;\s]+)", text)):
            if bundle.endswith("Tests") or bundle.endswith("UITests"):
                continue
            bundle_ids.setdefault(bundle.lower(), []).append(repo)

    ours = set()
    text = PROJECT.read_text(encoding="utf-8", errors="replace") if PROJECT.exists() else ""
    for bundle in set(re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;\s]+)", text)):
        if not (bundle.endswith("Tests") or bundle.endswith("UITests")):
            ours.add(bundle)

    if not ours:
        fail(f"no PRODUCT_BUNDLE_IDENTIFIER found in {PROJECT.name}")
    for bundle in sorted(ours):
        clash = bundle_ids.get(bundle.lower())
        if clash:
            fail(f"bundle id {bundle!r} collides with {', '.join(sorted(set(clash)))} — "
                 f"the plug-in will not register, and will simply not appear in a host. "
                 f"Case does not save you: the comparison here is lowercased "
                 f"because macOS's is.")
        else:
            ok(f"bundle id {bundle!r} is unique across the siblings")

    print()
    if failures:
        print(f"identity: {failures} FAILURES")
        sys.exit(1)
    print("identity: component identity is unique and consistent")


if __name__ == "__main__":
    main()
