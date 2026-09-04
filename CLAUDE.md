# Working on MelGen

*For any agent picking this up — the one embedded in Xcode included. Short on
purpose. The long documents are listed at the bottom; this is the part you need
before touching anything.*

---

## The one thing that surprises everybody

**Xcode's test targets cannot reach most of this codebase.** The DSP kernel is
C++ inside the extension, and every source under `MelGenExtension/Melody/` has
extension-only target membership. `MelGenTests` sees neither. So a green test
action in Xcode tells you almost nothing.

The real check is a shell script:

```bash
Scripts/verify.sh            # all 33 suites
Scripts/verify.sh chords     # just one
```

It compiles the Melody sources with `swiftc` outside Xcode, runs the C++ kernel
under `clang++`, and audits the docs, the icon and the theme contrast with
Python. **If you can run a terminal, run this before and after every change.**
If you cannot (Xcode's built-in assistant can't), say so plainly and ask for it
to be run rather than reporting a change as verified — building the two schemes
is necessary and is not sufficient.

Two suites need a `music-suite` checkout, because they check this port against
the TypeScript it was ported from:

```bash
git clone https://github.com/Enkerli/music-suite ../../music-suite
cd ../../music-suite && npm install     # builds packages/theory/dist
```

`verify.sh` looks in `$REPO/../../music-suite` by default; override with
`MUSIC_SUITE=...`. Without it, `chords` and `proggen` print SKIP and pass — so
a green run on a machine without it is a weaker green than it looks.

---

## What this is

An iOS/macOS **AUv3 MIDI processor** (`aumi`) that composes lines, comps and
basslines over a chord progression and loops them as MIDI. Two targets:

| Target | What it is |
|---|---|
| `MelGenExtension` | the plug-in. Everything real lives here |
| `MelGen` | a host app that loads the extension, for quick testing |

The Xcode project uses **synchronized folder groups**, so a new file in
`MelGenExtension/Melody/` joins the target automatically — no `pbxproj` edit,
and no forgetting one either. Check membership only if a build complains about
a symbol you can see on disk.

Requires Xcode 26+ (**27 to open the project**, format 110) and iOS/macOS 26.0+.

---

## Rules that are not negotiable

**Never hand-edit a generated file.** `ChordDictionary+Generated.swift` and
`ProgressionTables+Generated.swift` are emitted from music-suite by
`Scripts/generate-chord-dictionary.py` and
`Scripts/generate-progression-tables.py`. Both take `--check`, both run in
`verify.sh`, and both will catch you. If the dictionary is wrong, it is wrong in
`packages/theory` and the fix belongs there.

**Nothing generates on the audio thread.** Every material source produces a
whole `MelodyPattern` off-thread; the C++ kernel schedules already-decided
notes. This is load-bearing — it is what makes Foundation Models and, later,
Core ML usable at all. Do not move generation into the render block.

**One word per concept.** `TERMINOLOGY.md` is enforced against every interface
string by `verify.sh terminology`. If you need a new word, add it there first
and say why.

**The layering is checked.** See below.

---

## The layering, and how to change it

`verify.sh boundary` (`Scripts/tests/foundation-boundary.py`) treats this repo
as five stacked layers and fails on any reference that points upward:

```
core → theory → carrier → shell / ui → app
```

The bottom four are the ~8,600 lines a sibling plug-in would stand on
([PORTING.md](PORTING.md)). Twelve upward references remain; each is listed in
`SEAMS` at the top of that script with a note on how it gets cut, so **the
script is the work list**.

Cutting one is a loop, and doing it in this order matters:

1. Make the change — usually a **move**, not a rewrite. Three of the four cuts
   made so far were files sitting in the wrong place, not couplings that had to
   be broken. Suspect that first.
2. Delete its entry from `SEAMS`.
3. `Scripts/verify.sh boundary`. It fails if you left a cut seam in the list,
   and it fails if you introduced a new upward reference.
4. Update the counts in `PORTING.md` §1 and §3. `verify.sh docs` will not catch
   a stale number there, so it is on you.

Adding a *new* upward reference is not forbidden — it is forbidden silently.
Add it to `SEAMS` with how it would be cut, or move the code so it isn't one.

---

## Where the documents are

| | |
|---|---|
| [HANDOFF.md](HANDOFF.md) | **start here** — current state, what is loose, what is not proven |
| [README.md](README.md) | features, building, the verify-suite table |
| [PORTING.md](PORTING.md) | the layers, the seams, and what a second plug-in would cost |
| [ROADMAP.md](ROADMAP.md) | what is planned, with why-not for the things not done |
| [ISSUES.md](ISSUES.md) | known problems, including ones observed and not yet reproduced |
| [TESTING.md](TESTING.md) | what `verify.sh` cannot answer, and how to answer it on a device |
| [TERMINOLOGY.md](TERMINOLOGY.md) | one word per concept, enforced |
| [TRAINING.md](TRAINING.md) / [COREML.md](COREML.md) | on-device learning, and training off-device |
| [DESIGN_BRIEF.md](DESIGN_BRIEF.md) | why the interface is shaped the way it is |

---

## House style

The prose in this repo — comments, commit messages, documents — explains *why*,
records what was measured, and says plainly what is not known. A comment that
restates the code is noise; a comment naming the bug that made the code look
like that is the reason the file is readable a month later. Match it. When you
are unsure whether something works, write that down instead of rounding up.
