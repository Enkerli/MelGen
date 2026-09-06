# Working on MelGen

*For any agent picking this up — the one embedded in Xcode included. Short on
purpose. The long documents are listed at the bottom; this is the part you need
before touching anything.*

---

## The one thing that surprises everybody

**Xcode's test targets cannot reach most of this codebase.** The DSP kernel is
C++ inside the extension; every source under `MelGenExtension/Melody/` has
extension-only target membership; and the four foundation layers are targets of
the `EnkerliSwift` package next door. `MelGenTests` sees none of it. So a green
test action in Xcode tells you almost nothing.

The real check is a shell script:

```bash
Scripts/verify.sh            # all 34 suites
Scripts/verify.sh chords     # just one
```

It builds the `EnkerliSwift` package with `swift build`, compiles the app's
Melody sources against it with `swiftc` outside Xcode, runs the C++ kernel under
`clang++`, and audits the docs, the icon and the theme contrast with Python.
**If you can run a terminal, run this before and after every change.**
If you cannot (Xcode's built-in assistant can't), say so plainly and ask for it
to be run rather than reporting a change as verified — building the two schemes
is necessary and is not sufficient.

**Nothing runs without the foundation checked out beside this repo.** It is its
own repository now — the four lower layers plus the AU shell live there, and this
repo is one plug-in standing on them:

```bash
git clone https://github.com/Enkerli/enkerli-swift ../../enkerli-swift
```

`verify.sh` and the Xcode project both look in `$REPO/../../enkerli-swift`;
override with `ENKERLI_SWIFT=...`. Without it every Swift suite fails with that
line printed, deliberately — a suite that quietly passed against a stale in-repo
copy of the foundation would be worse than one that refuses.

Two more suites need a `music-suite` checkout, because they check this port
against the TypeScript it was ported from:

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
| `MelGenExtension` | the plug-in: MelGen itself, plus the AU shell |
| `MelGen` | a host app that loads the extension, for quick testing |
| `EnkerliSwift` | a local Swift package — `Core`, `Theory`, `Carrier`, `UI`. The third of the codebase a sibling plug-in stands on ([PORTING.md](PORTING.md)) |

**Which half a file belongs in is a real decision, and the compiler enforces it
now.** A package target may not name anything above it, so a new type that
belongs to melody goes in `MelGenExtension/`, and one that any plug-in in the
suite could use goes in the matching `EnkerliSwift/Sources/` target. If you are
unsure, put it in the app: moving it down later is a `git mv` plus a `public`
sweep, and moving it up is a compile error you will find immediately.

Everything in the package is `public` because it had to be, not because it was
designed as API — see PORTING.md §7 step 4. Do not read a `public` there as a
promise.

The Xcode project uses **synchronized folder groups**, so a new file in
`MelGenExtension/` joins the target automatically — a new *directory* too, which
is how `AudioUnit/` arrived — no `pbxproj` edit, and no forgetting one either.
A new file in `EnkerliSwift/Sources/` joins its target the same way, because
that is how SwiftPM works. Check membership only if a build complains about a
symbol you can see on disk.

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

**The layering is compiled, and also checked.** See below.

---

## The layering, and how to change it

Seven stacked layers, and nothing may point upward:

```
core → theory → carrier → auhost → shell / instrument / ui → app
```

Everything below `app` is the ~13,000 lines a sibling plug-in stands on
([PORTING.md](PORTING.md)). **Every one of the nineteen upward references is
cut**, `SEAMS` in `Scripts/tests/foundation-boundary.py` is empty, and all of
them are package targets — so an upward reference is a build error, not a
report.

`shell`, `instrument` and `ui` share a rank because none is above the others: a
MIDI processor's audio unit, a synth's, and a UI kit that must not know about
either. `auhost` sits below all three because both kinds of audio unit need the
same lifecycle around them, which is what the suite's one `aumu` plug-in
([SwiftVane](https://github.com/Enkerli/SwiftVane)) made necessary.

`verify.sh boundary` still runs, and it is worth knowing what is left of its
job, because two of these are things the build cannot do:

- **The shell is not a package target yet** (Package.swift says why), so
  shell → app is only checked there.
- **Shell and UI are siblings, and Package.swift says so by omission** — neither
  depends on the other. Add a dependency and the build goes green; only this
  notices. It got that wrong itself until the package was built, which is how
  two AU-bound controls sat in the UI kit unremarked.
- **The counts.** PORTING.md §1's percentage is this script's output.
- **Proposing a move.** Edit the layer manifest, run it, and it says what a
  reclassification would cost before a file is touched. Three of the last four
  cuts were decided that way.

Moving a file down into the foundation is a loop:

1. `git mv` it into the right `EnkerliSwift/Sources/` target — usually that is
   the whole change. Fifteen of the nineteen cuts were moves or
   reclassifications, not couplings that had to be broken. Suspect that first.
2. Mark what it exposes `public`, and write out the memberwise initializer if it
   is a struct the app constructs — Swift synthesizes one and keeps it internal.
3. `swift build --package-path EnkerliSwift`, then `Scripts/verify.sh`.
4. Update the counts in `PORTING.md` §1 and §2. `verify.sh docs` will not catch
   a stale number there, so it is on you.

Adding a *new* upward reference is not forbidden — it is forbidden silently. Add
it to `SEAMS` with how it would be cut, or move the code so it isn't one.

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
