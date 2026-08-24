#!/usr/bin/env python3
"""Checks the documentation against the code it describes.

Only claims that are mechanically checkable live here — lists that mirror
something enumerable, and numbers that quote a constant. Everything else in the
docs is prose and stays a human's job.

Written after an audit found the README six verify suites behind, quoting a
history limit an order of magnitude stale, and using a name the code had
renamed. Each check below is one of those failures, turned into something that
can't happen twice.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
failures: list[str] = []
checks = 0


def check(label: str, ok: bool, detail: str = "") -> None:
    global checks
    checks += 1
    print(f"  {'PASS' if ok else 'FAIL'}  {label}{' — ' + detail if detail else ''}")
    if not ok:
        failures.append(label)


def read(name: str) -> str:
    return (REPO / name).read_text(encoding="utf-8")


def main() -> None:
    readme = read("README.md")
    verify = read("Scripts/verify.sh")

    # 1. Every suite verify.sh defines is documented, and nothing else is.
    defined = set(re.findall(r"^run_([a-z]+)\(\)", verify, re.M))
    documented = set(re.findall(r"^\| `([a-z]+)` \|", readme, re.M))
    check("every verify suite is in the README table",
          defined <= documented,
          f"undocumented: {', '.join(sorted(defined - documented)) or 'none'}")
    check("the README documents no suite that doesn't exist",
          documented <= defined,
          f"phantom: {', '.join(sorted(documented - defined)) or 'none'}")

    # 2. Numbers that quote a constant.
    state = read("MelGenExtension/Melody/MelGenState.swift")
    limit = re.search(r"historyLimit = (\d+)", state)
    ceiling = re.search(r"historyCeiling = (\d+)", state)
    if limit and ceiling:
        check("the README's history limits match the code",
              limit.group(1) in readme and ceiling.group(1) in readme,
              f"code says {limit.group(1)} / {ceiling.group(1)}")
    else:
        check("history limits are findable in the code", False)

    # 3. Template counts, which are two lists the README totals.
    templates = read("MelGenExtension/Melody/MelGenTemplate.swift")
    comping = read("MelGenExtension/Melody/MelodyComping.swift")
    line_count = len(re.findall(r"MelGenTemplate\(brief:", templates))
    figures = re.search(r"static let all: \[CompingFigure\] = \[([^\]]*)\]", comping)
    figure_count = len([f for f in figures.group(1).split(",") if f.strip()]) if figures else 0
    total = line_count + figure_count
    check("the README's template count matches the code",
          str(total) in readme or _spelled(total) in readme.lower(),
          f"{line_count} line + {figure_count} chord = {total}")

    # 4. A concept renamed in code is renamed in the docs. "Style brief" is the
    #    old name for what the code now calls a template.
    check("the README doesn't use the retired name for templates",
          "style brief" not in readme.lower(),
          "code calls these templates")

    # 5. Scripts exist and are mentioned somewhere.
    for script in sorted((REPO / "Scripts").glob("*.py")) + sorted((REPO / "Scripts").glob("*.sh")):
        name = script.name
        mentioned = any(name in read(doc.name) for doc in REPO.glob("*.md"))
        check(f"{name} is documented", mentioned)

    # 6. Docs referenced by other docs exist.
    for doc in REPO.glob("*.md"):
        for link in re.findall(r"\]\((([A-Z][A-Za-z]*\.md))\)", doc.read_text(encoding="utf-8")):
            target = link[0]
            check(f"{doc.name} → {target} resolves", (REPO / target).exists())

    print()
    if failures:
        print(f"docs: {len(failures)} of {checks} checks FAILED")
        sys.exit(1)
    print(f"docs: {checks} checks passed")


def _spelled(number: int) -> str:
    words = {9: "nine", 6: "six", 14: "fourteen", 15: "fifteen", 16: "sixteen", 22: "twenty-two"}
    return words.get(number, str(number))


if __name__ == "__main__":
    main()
