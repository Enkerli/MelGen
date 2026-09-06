# Handoff — current state

*Updated 2026-09-05. For whoever picks this up next, including the agent embedded
in Xcode. Written while moving fast on purpose: what landed, what's loose, and
what is definitely not proven.*

**On `foundation-package` (2026-09-05) — the seam list is empty.** All nineteen
upward references PORTING.md found are cut; the foundation is 9,596 lines, 38%
of the extension, and names nothing above itself. `verify.sh` is green with
nothing skipped and all four Xcode builds succeed. Detail in
[PORTING.md](PORTING.md) §1 and §3; the short version is that fifteen of the
nineteen were files in the wrong place, including the one §3 had singled out as
the only real design decision — `ChordVoicing → DegreeHistogram` turned out to
be two things sharing a file, and reading the call site is what showed it.

The shell now splits into a base and a subclass: `PluginAudioUnit` and
`PluginViewController` are the ~874 lines any AUv3 in this suite needs,
`MelGenExtension/AudioUnit/` holds MelGen's session and its three overrides. A
sibling plug-in writes those two small files. This is the shape §3 predicted as
"one generic parameter and one protocol"; a generic parameter turned out to be
unavailable, because `Info.plist` names the principal class and the ObjC runtime
looks it up by name.

**And the foundation is a package now** — PORTING.md §7 step 4, done.
`EnkerliSwift/` has `Core`, `Theory`, `Carrier`, `UI` and `Shell` as targets,
plus `Kernel` for the C++; the extension links all six; `verify.sh` builds the package once and compiles the app against
the built modules, which is what the plug-in actually ships as and what no suite
was testing before. 10,694 lines, 41% of the extension. All four Xcode builds
pass and all 34 suites are green with nothing skipped.

Three things about it are worth carrying forward rather than rediscovering.

**The `public` sweep is over-broad, deliberately.** Every symbol it marked was
already visible to every file in the extension — one target, one module — so
nothing was widened that was not already open. But the code has never recorded
which of those were API and which were helpers nobody meant to expose, and no
compiler can tell them apart. Narrowing it is a separate pass with no automated
help, and until it happens a `public` in the package is not a promise.

**Fifty-five memberwise initializers had to be written out**, because a public
struct's synthesized one is internal. Four rules were rediscovered one broken
call site at a time; the one to remember is that **a `var` of optional type gets
an implicit `= nil` in the synthesized init** and nothing tells you when you drop
it.

**The split found two seams the boundary check is blind to, and one bug in it.**
`MelodyPatterns.seeds` and `MelodyPatterns.extract` were declared in extensions
in the app and called from carrier — the check ignores extensions on purpose,
which is right for ownership and wrong for compilation. And its rank test only
failed on a strictly higher rank, so `ui → shell` had been passing silently over
two real edges. Both fixed; the second is the argument for the package made
better than PORTING.md could make it in the abstract, because **a check you wrote
shares your blind spot and a compiler does not.**

**The shell went in too, and all three things that made it look hard were
small.** The kernel is its own target with one `.mm` compile unit — Objective-C++
rather than C++, because `NS_ENUM` and `AudioToolbox/AUParameters.h` do not
compile as plain C++. `Shell` imports it as a module, which is what replaces the
bridging header. And `MelGenExtensionParameterAddresses.h` was a naming problem
all along: `playMelody`, `playbackDirection` and `hostSync` are the parameters a
loop player has, not anything about melody, so it is
`PluginParameterAddresses.h` now and no logic changed.

**What is left in `MelGenExtension/` is MelGen.** Its session, its root view, its
three overrides on `PluginViewController`, and its own parameter tree.

**Four plug-ins now stand on it**, and the fourth —
[SwiftPitchFold](https://github.com/Enkerli/SwiftPitchFold), `aumi PtFd` — is
the first that is not a generator. It folds incoming notes into a pitch-class
set, which inverts the dataflow the other three share and made the shared kernel
grow a transform path. PORTING.md §8's invariant survives intact because of
where the line falls: **the decision is off-thread, only the lookup is on it.** A
128-byte note map is computed in Swift at leisure; the render thread reads one
byte per note-on. There is no quantizer in that repo — sets are `Theory`, the
map is `Shell`, the rewrite is the kernel.

**Two things it cost that are worth carrying.** A `NoteMap` change while a note
is held has to end that note on the mapping it *started* with, or it stays
sounding in somebody else's synth after this plug-in is removed from the chain;
the kernel harness plants all three shapes of that bug. And a Swift port of
`packages/theory/src/pcs.ts` found the C major scale's bitmask written as 2773
in four separate files' prose, always with correct code beside it — see
CONVENTIONS.md, which now names the trap.

**And two plug-ins were renamed, because a four-character code is not the only
forever identifier.** SwiftSerpe was `com.enkerli.Serpe` against the JUCE build's
`com.enkerli.serpe` and did not appear in AUM at all — absent rather than
misrouted. SwiftPitchFold was heading for the same wall. `component-identity.py`
checks bundle ids now, lowercased.

**Three plug-ins before that**, and the third is the one that tested the
layering rather than just using it. [Serpe](https://github.com/Enkerli/Serpe) —
`aumi Srpe` — is UPI notation in Swift, and building it meant *splitting* an
engine rather than porting one: the rhythm algorithms (Björklund, Barlow, the
codecs) went into `enkerli-swift`'s Theory target held to the suite's own
vectors, and the notation stayed in the plug-in because it is a grammar and
nobody else wants it. `Scripts/verify.sh upi` reports 59 of 59 notation cases
passing with none unported.

Two things came out of that worth carrying:

- **The vectors were written first, and they earned it.** `packages/upi` had
  3.5 KB of coverage against 2,600 lines of engine; it now has 100 cases in
  seven groups. Writing them found two undocumented behaviours in the
  JavaScript, and the Swift port then found four bugs in itself against them on
  its first run. PORTING.md §5 said to do this before the port; it was right for
  a reason it did not state, which is that the vectors improve the thing they
  are written about.
- **A rhythm plug-in can voice a chord**, because it shares a package with a
  melody plug-in. Three cases in a switch, and no rhythm tool that did not share
  a foundation would have them. That is the clearest single example of what the
  layering was for.

**And the second plug-in writes exactly that file list.**
[ProgGenie](https://github.com/Enkerli/ProgGenie) is `aumi PgGn`, it generates
chord progressions off the corpus tables, plays them through the same kernel, and
**contains no theory at all** — no chord dictionary, no pattern format, no UI
kit, no shell. Six files, about 770 lines against the package's 10,624, of which
the two AU subclasses are 120. That is PORTING.md §7 step 5, and the thing it was
for: "if ProgGenie ends up with its own copy of the chord dictionary, the
extraction failed."

Its triple is `PgGn` rather than the `Prst` §6 first assigned, because `Prst`
belongs to the JUCE Progression Studio and its AUv3 build — the exact collision
`component-identity.py` exists to prevent, which is also why that check learned
to read Swift siblings before any of this. It reads MelGen's `Info.plist` from
ProgGenie's checkout and vice versa.

**What is not done**, in ProgGenie and here:

- **Nothing has been heard on a device**, in either plug-in. ProgGenie builds and
  its suites pass; MelGen's bass mode has never been heard at all, and design
  pass 3's L4 question still needs a session at AUM's half height.
- **ProgGenie's curation steers by rejection sampling** — twelve candidates, keep
  the one the profile likes. Approximate, and written down as approximate.
  Weighting the distribution directly would mean the shared generator learning
  that anyone keeps opinions, which is a change to foundation and wants more
  thought.
- **`JUCE_INDEPENDENCE.md` has not been written back to** (§7 step 6). It belongs
  in the monorepo. PORTING.md §7 now carries the measured numbers it needs, and
  §5 carries what a *split* costs as opposed to a port, which is the case that
  document did not price at all.
- **Serpe has four named gaps**, all in its README: progressive notation (the
  monorepo has vectors for all four forms and the plug-in has nowhere to put a
  trigger index), `R(k,n)` refused on purpose because `Math.random` has no
  cross-language contract, poly lanes whose vectors have existed since before
  the port, and an analysis readout that is one line where the monorepo has six
  vector-covered measures.
- **The `public` sweep has not been narrowed**, and the UI kit still carries
  MelGen's name in its types (`MelGenTheme`, `MelGenMetrics`) from inside a
  package two plug-ins use. Honest about where it came from; worth renaming when
  a third makes it actively wrong rather than merely historical.

The `curation-and-training` branch this document started as a handoff for is
merged, and so is the redesign that followed it, the UX-and-playflow pass, and
the MIDI interchange work. **Every branch is now merged into `main`** —
`layout-pass` was the last one holding work, and it landed 2026-09-05.
Everything is verified outside Xcode by `Scripts/verify.sh` — **34 suites** —
and compiles in both targets.

**On `layout-pass` (design pass 3, merged 2026-09-05).** Two of its three
prescriptions, in the order the pass itself demands. `MiniRoll` — 44pt, chord
ticks, notes as marks with register as height, the playhead, flagged notes in
`warning` — is the object the pinned verbs act on, and the swipe went with it,
because you rate what you can see. The full roll became a sheet, which returned
170pt of permanent screen and is the first thing any of the three design passes
has actually removed. The border rule turned out 97% true and its one violation
was three days old and in `ActionBadge`, so it is checked now by `verify.sh
borders` rather than remembered. Detail in [ISSUES.md](ISSUES.md) §6.7.

**L4 is open on purpose, not abandoned** — the choice between the console, the
instrument and three cards is the pass's own third step, and the pass says to
judge it on device after the first two exist, "otherwise all three are being
compared through the same fog." Both prerequisites now exist. This is the one
piece of unfinished business the merge inherits, and it needs a session at
AUM's half height rather than a commit.

One thing the merge surfaced, because the two branches never saw each other:
**`MiniRoll.swift` is classified as `app` by default, and it does not have to
be.** It is in neither `UIKIT_FILES` nor `NOT_FOUNDATION` in
`Scripts/tests/foundation-boundary.py`, and that dict exists precisely so an
absence "reads as a decision rather than an oversight" — this one is an
oversight. Proposing it as `ui` was tried and passes with no new upward
reference, which would move 165 lines into the foundation (ui 2,019 → 2,184,
total 8,580 → 8,745). Its sibling `PianoRoll` is already foundation. Left
undecided deliberately, because whether a glance-at-the-take drawing belongs in
a shared UI kit is a question about the second plug-in, not about this merge.
Note also that the check does not catch this class of gap: it verifies the
manifest names files that exist, not that every file is named.

**On `music-suite-plugin-porting` (2026-09-04) — it compiles, and all four
predictions about where it would break were wrong.** Seven declarations moved
between files on a Linux box with no `swiftc`, so "compiles" was a claim nobody
had earned. It is earned now, on a Mac with Xcode 27 beta:

- `Scripts/verify.sh` passes **every suite with nothing skipped** — 33 at the
  time, 34 now that `borders` has landed with `layout-pass`. That last part
  is the load-bearing half — this document has always warned that a green run
  with skips is a weaker green than it looks, and the earlier Linux run skipped
  `midi` for a missing `mido` while `chords` and `proggen` had no music-suite to
  compare against. All three ran here.
- Both schemes build across four destination and configuration pairs: iOS
  Simulator in Debug and in Release, macOS, and generic iOS. All four targets
  compile, the two test targets included (`build-for-testing`). macOS matters
  because §0 of PORTING.md claims this shell covers macOS as well as iOS and
  nothing had ever built it there.

[§0 of What to do next](#what-to-do-next) named four places it expected to
break: target membership for the two new files, the seven `DeadAir.cap` call
sites, the new `ChordProgression` extension in the one suite that compiles files
by name rather than by glob, and `TakeSource` having left the session. None of
them broke. The instruction that came with those predictions — treat a clean run
as a prediction being wrong, not as nothing having been at risk — is the part
worth keeping. What was wrong was the estimate of risk, and for a reason that
generalises: synchronized folder groups really do pick up new files, and a
single-module target really does make a cross-file move a non-event. Four
predictions about a pure move are four predictions that the build system might
not behave as documented. It behaved as documented.

What the branch is *for* is [PORTING.md](PORTING.md): whether a second AUv3 —
ProgGenie first — could stand on this codebase without JUCE, answered with a
measurement rather than an estimate. About a third of the extension is
foundation a sibling plug-in would share, and `verify.sh boundary` now enforces
the layering the compiler can't (one target, one module, every type visible to
every file). Nineteen upward references were found; seven are cut and the
remaining twelve are listed in `Scripts/tests/foundation-boundary.py` with how
each one goes, so that script is the work list.

The moves, all pure — no logic changed:

| Was | Is now | Why |
|---|---|---|
| `SplitMix64` in `MelodyExpression.swift` | `SeededRandom.swift` | every generator reaches for it, including one that is theory |
| `TakeSource` in `MelGenState.swift` | `MaterialSource.swift` | it is stamped into `PatternOrigin`, so it travels in every exported pattern — interchange, not session state |
| `MelodyExpression.capDeadAir` | `DeadAir.cap` | a repair to what a take *is*, not how it is performed |
| `MelodyChunker.slice` | `ChordProgression.slice(from:to:)` | it was never chunking — it clips a progression |

`MelodyPattern` is now formally the interchange format, which is what closed
five of the seven seams. Also new: `verify.sh proggen`, which holds the
progression port to ProgGenie's own answers — the first cross-language check
`packages/proggen` has ever had, and it found two divergences before any Swift
ran (see PORTING.md §7).

**`proggen`'s first run against Swift reports 44 labels in 3 keys, 0
differences**, which was the outcome §1 said to expect *least*. A check that
passes on its first run is indistinguishable from a check that does nothing, so
this one was made to fail on purpose before the zero was believed: planting a
wrong `rootPc`, `semitonesAboveTonic`, `qualityKey`, `playable` flag and a
dropped label each produce exactly one named `DIFF`, and a spelling-only change
produces none, which is the one thing it is designed to tolerate. It is also not
a thin check — 132 realized cells, 120 of them playable, spanning all twelve
semitone classes and twelve distinct quality keys. The two known divergences
behave as written down: `IBass` and `VIII` come back unplayable on both sides.
`verify.sh boundary` was given the same treatment, because the 35% figure is
PORTING.md's load-bearing claim: one planted upward reference from `core` to
`MelGenState` fails it with the file, the type and the remedy named.

So the Swift and JS readings of a corpus label agree exactly, and that is now a
measured fact rather than a hope. The port's remaining risk is not in the
deterministic half.

**On `bassline-and-histograms` (2026-08-28)**, the newest work and the one thing
here that has *not* been heard on device: a third mode, a seventh source, and the
two distributions the roadmap had been naming as missing since G10. Detail is in
[ROADMAP.md](ROADMAP.md#what-landed-on-bassline-and-histograms). The short
version: `DegreeHistogram` says which note as weights over the twelve semitones
above the chord's root, `TransitionHistogram` says how far to the next one, and
`MelodicWalk` multiplies them; `BasslineGenerator` plays an on-beat and an
off-beat figure at once, balanced and selected on a pad, inside a stated
register; `DiatonicHarmony` turns a key and a minorness into a one-chord
progression so nothing downstream has to know the difference. Comping draws on
the histograms too, through the `drawn` voicing style. Two new suites,
`histograms` and `bassline`, and both build targets compile.

The pad was a diamond first and is a square now — see [the manual pass in
ROADMAP.md](ROADMAP.md#what-landed-on-bassline-and-histograms) for what changed
and why. The one open risk this leaves is the usual one: **none of it has been
heard on device.** `README.md` has a section explaining the mode, and the
next-step line offers it once a session has six takes and no bass part in it,
which is the only thing on screen that says the mode exists.

**Since 2026-08-25**, five things landed that this document did not previously
mention. Detail is in [ROADMAP.md](ROADMAP.md); the short version:

- **The app icon** is an Icon Composer document, `MelGen/MelGen.icon`. Every fill
  carries a `dark` specialization; without one the system keeps the light fill
  and the ink stack vanishes into the dark ground, which *looks correct in every
  editor* because editors show you the light artwork. `verify.sh icon` guards it.
- **Rating and an aimed advance** (U10). Yes/Maybe/No are shortcuts to three of
  the seven dispositions and never reach storage as anything else; "another like
  this" and "something else" each carry a subtitle computed *before* the tap.
  `TakeAdvance` cannot import FoundationModels by construction, which is how the
  1.8s-a-note constraint is enforced rather than remembered.
- **MIDI in and out**, with harmony, in four tiers — the top one being the
  suite's own `MCURATOR:v1 PROG` payload, so MelGen ↔ MIDIcurator ↔ ProgGenie is
  a real round trip. Plus `ChordDetection`, the MIDIcurator port (I6).
- **"Your material"** groups listening, the stored lines and the learned readout
  on one surface in flow order.
- **A next-step line** (U11) above both tabs, which is the first answer to the
  flow still reading as inscrutable. See [ISSUES.md](ISSUES.md) §4.1–4.2.

**It has been heard on device several times, 2026-08-23 to 2026-08-26**, which
retired the largest open risk this document used to name. What those sessions
surfaced lives in [ISSUES.md](ISSUES.md); the two that mattered most — takes
losing their first notes, and a rating that followed what was playing rather than
what was rated — are fixed, and §3 there says how. The first was a phase bug in
`commitSequence` rather than any of the three places §4 pointed at; the second
turned into the parentage model, which is the more interesting outcome.

---

## The shape of it

The branch turns MelGen from "a model writes a line" into a loop with seven
sources of material, one curation model over all of them, and two learned models fed by
what survives curation.

```
        ┌─ the model (~2s/note)
        ├─ stored lines (seeds + interval cells)
        ├─ composed phrases (gestures + a phrase grammar)   ─┐
        ├─ slot statistics of what you kept                  ├─ all produce
        ├─ a chain walk over what you kept                   │  MelodyPattern
        ├─ variants and morphs of any of the above          ─┘
        ├─ what you played in
        ├─ comping (chords rather than a line)
        └─ a bass line (two histograms through a figure) ── emits notes, read
                                                            back as a pattern
                    │
                    ▼
            realized over harmony  ──►  heard  ──►  judged (disposition, this pass)
                    ▲                                        │
                    └──────── learned from ◄─────────────────┘
                                (keep / tweak / partly)
```

The through-line: **everything ends up a `MelodyPattern`** — degrees, not
pitches — so everything is realized, curated, mutated and learned from by the
same machinery. The bass line is the one source that doesn't *start* there, and
the reason is written next to it: a register is the whole point of a bass part
and the pattern format deliberately doesn't carry one, so the walk happens in
absolute pitch and `MelodyPatterns.extract` reads it back. An eighth source
would be a file, not a subsystem.

---

## What landed, in order

| Commit | What it does |
|---|---|
| Read a take back as a line | R1/R2 — `extract` inverts `realize`; off-scale notes are kept as alterations with their original role, never snapped |
| Curate in passes, not verdicts | Seven unranked dispositions, marks stamped with their pass and with what the take was heard after, derived facets and an emergent tag vocabulary |
| Say what to do with a take | The curation surface |
| Keep a take as a line | `PatternStore`, plus cycle/shuffle/lock over a chosen set (T1/T2) |
| Describe what you kept | `LearnedStyle` — measurements as prompt text (S3) |
| Work out what local training could mean | [TRAINING.md](TRAINING.md) and `Scripts/analyse-history.sh` |
| Compose phrases out of gestures | Twelve rhythms × ten contours × five phrase roles, and the grammar that composes them |
| Learn slot statistics | Ported from `@enkerli/accompaniment` — per-slot distributions, accumulable, sampled |
| Learn what follows what | Variable-order chain with backoff; reports how much order-2 it can actually trust |
| Mutate, score and morph | Fourteen transforms, three separate scores, proportional-alignment morph |
| Find a line, be surprised by one | Retrieval and serendipity, plus topic grouping that proposes facet names |
| Describe lines as moves | Hanon's self-sequencing cells and the Samchillian's interval streams, with a second realization mode for them |
| Learn from what's played in | Lock-free capture ring, pairing, segmenting, quantizing |
| Comp the changes | Voicing layer, voice leading, comping figures, polyphonic mode |
| Generate the changes too | ProgGenie's corpus tables, generated from music-suite |
| Prepare the off-device path | Desktop-only: a tested MIDI reader, a corpus exporter that compiles the real Melody sources, and a training/conversion pair. Nothing ships. [COREML.md](COREML.md) — and §4 there records that the gate the whole document rests on doesn't yet gate |
| Lead the voices | Minimal L1 (taxicab) leading ported from the suite's reference implementation and held to its shared vectors; three modes, and a seam pass for lines |
| Judge a variation as one | Takes carry the take they were made from and what was done to get there, so a variant, mutation, morph or drifted pass is judged in its own right with its parent's mark for context |
| Keep a setup | `MelGenSetup` — the settings that decide what comes next, and none of the material; one can be the default a new instance starts from |
| Draw a bass line | `DegreeHistogram` and `TransitionHistogram`, multiplied by `MelodicWalk` and drawn through a figure mixed on a diamond; a key as an alternative to changes, with minorness as one dial across the modal brightness ladder |
| Keep what the gate refused | Every proposed template is logged with the bar it was held to; the bar is now derived from the existing set's own spacing rather than from a mis-taken constant |

---

## Build and verify

**The Xcode 26.6 command-line tools cannot open this project** — it's project
file format 110. Use the beta toolchain:

```bash
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project MelGen.xcodeproj -scheme MelGenExtension -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

`Scripts/verify.sh` is unaffected and now runs every suite in the README's table,
compiling every Melody source each time:

```bash
Scripts/verify.sh
```

New suites on this branch: `extraction`, `curation`, `phrases`, `stylemodel`,
`chain`, `mutation`, `retrieval`, `topics`, `steps`, `capture`, `comping`,
`progression`. The last one also fails if the generated ProgGenie tables have
drifted from music-suite. Added on `bassline-and-histograms`: `histograms` and
`bassline`. Added on `music-suite-plugin-porting`: `boundary` (the layering,
pure Python — runs anywhere) and `proggen` (the progression port against
ProgGenie's own answers).

`chords` and `proggen` both need a **built** music-suite beside this checkout,
and both print SKIP and pass without one — so a green run on a machine that
lacks it is a weaker green than it looks:

```bash
git clone https://github.com/Enkerli/music-suite ../../music-suite
cd ../../music-suite && npm install     # builds packages/theory/dist
```

`midi` is the third suite that skips rather than fails, and it needs `mido`
rather than music-suite. Homebrew's Python refuses to install into itself, so a
throwaway virtualenv is the shortest path to a run with no skips in it:

```bash
python3 -m venv /tmp/melgen-venv
/tmp/melgen-venv/bin/pip install -r Scripts/training/requirements.txt
PATH=/tmp/melgen-venv/bin:$PATH Scripts/verify.sh    # 34 suites, 0 skipped
```

**Count the skips, not just the exit code.** Three of the 34 suites pass while
doing nothing if their dependency is absent, so `verify: OK` on a bare machine
is a green that covers 31 suites and says so nowhere. `grep -c SKIP` is the
difference between the two greens.

Not part of `verify.sh`, because it needs data rather than fixtures:

```bash
Scripts/analyse-history.sh ~/Library/Mobile\ Documents/com~apple~CloudDocs
```

---

## Loose ends

Ordered by how likely they are to bite.

1. **Heard three times, 2026-08-23 to 2026-08-24, and it moved a lot each time.**
   From the first: comping is
   the best recent addition; phrasing improved but has room; the model failed
   with a content-scanner error and said nothing useful about it; the interface
   had outrun legibility. All of that is addressed. What is *still* unheard: the
   two-axis morph, the piano roll, the substitutions, and whether the composed
   lines' new architectures actually read as different pieces rather than
   different figures.
2. **The learned models are recomputed on every draw.** `MelodyStyleModel.learn`
   and `MelodyChain.learn` run over the whole kept history each time a button is
   pressed, and again for each interface refresh that shows their summary. That
   is O(takes × notes) on the main thread. It is fine at fifty takes and will not
   be at five hundred. They accumulate by design — storing them (S4) fixes this
   and is the same work as making styles savable.
3. **The model works. A third-party Apple Intelligence extension was breaking
   it**, and the first diagnosis of that was wrong — see F12b in the roadmap for
   the mistake and what it cost. The diagnostic now uses
   `MelGenState.modelHasWorkedHere` rather than reasoning from the error alone.
   What remains unverified on hardware is *most of the model path on this
   branch*: the learned-style conditioning, the retry, the fallback, and model
   comping in its corrected form. Lines generate; nothing else about the model
   has been heard.
4. **Two buttons that overlap.** "Save as example" (old, absolute-pitch text for
   the prompt) and "Keep as a line" (degree-relative, plays back) do different
   things with the same intent. The old one is probably subsumed now that curated
   takes are quoted automatically — but deleting it wants a device session first.
5. **Takes still can't be named.** `retitle` exists and nothing calls it.
6. **`partial` aspects are still recorded and unused.** Marking "the rhythm
   works" should now be a one-line call into `MelodyTransforms` — keep the
   rhythm, redraw the degrees. The vocabulary was chosen for this and the
   machinery now exists.
7. **The fit report still isn't shown.** Computed, tested, invisible.
8. **Capture listens to everything on the one input.** N2's channel split is what
   would let chords and melody arrive at the same time.
9. **The library is `UserDefaults`, not an App Group.** Right side of the
   session/library line, wrong container (I5/L4). Decide before more library UI.
10. **`PatternStore` has no export or import**, and neither do the learned models.
11. **The eighth-note grid is now the binding constraint.** Gestures buy back
    most of what triplets would with dotted and 3+3+2 figures, but a swung
    triplet feel is still unrepresentable (D1). Everything that would have to
    change is now in one place — the grid constant in `MelodyStyleModel`, the
    eighth arithmetic in the pattern format — which it wasn't before.
12. **`previousTakeID` is encoded but not decoded.** Deliberate, inconsistent.

---

## Things that will surprise you

- **`extract` never snaps.** An off-scale note becomes its nearest degree plus an
  alteration and keeps the role it had over its original harmony. A chromatic
  approach and a mis-snapped pitch are the same two numbers, and only the
  original harmony can tell them apart.
- **A cycle of intervals whose sum isn't zero sequences itself.** That's the
  whole of Hanon, and it falls out of the step-cell representation with nothing
  transposing anything. `drift` is that sum.
- **There are two realization modes.** `.folded` places degrees and folds them
  into register; `.stepwise` walks N scale steps from the previous pitch. Interval
  cells need the second, because folding is exactly the operation that removes an
  octave leap.
- **Backoff isn't an optimisation, it's the whole thing.** In both the melodic
  chain and the progression walk, a context seen once can only quote. The rule
  that a context must be seen more than once before it's trusted is what
  separates a model that composes from one that replays its corpus.
- **The comping path skips most of `MelodyExpression`.** Thinning would take two
  voices out of a four-note chord and the gate reads a gap that is zero inside a
  chord. `polyphonic: true` is judged from the take's source, not the mode, so a
  comping take stays polyphonic when the mode is switched back.
- **`verify.sh` compiles all of `Melody/`.** A new file needing
  `FoundationModels` must be excluded in `melody_sources()` the way
  `MelodyGenerator.swift` is, or every suite stops building.
- **Several tests were wrong before the code was.** The one-note lookback can't
  remove every repeat (a slot with one degree has nothing else to offer); folding
  doesn't remove a *clean* octave, it removes *direction* across a chord change;
  a uniformly-late phrase isn't loose, because rebasing absorbs a shared offset.
  Each of those assertions was rewritten to claim the true thing.

---

## What to do next

0. ~~**Compile the porting branch, before anything else.**~~ ✅ **Done
   2026-09-04, clean.** Kept here as the record, because what it gated is now
   open and because the four predictions it made are more useful wrong than they
   would have been right.

   ```bash
   PATH=/tmp/melgen-venv/bin:$PATH Scripts/verify.sh   # 34 suites, 0 skipped

   /Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
     -project MelGen.xcodeproj -scheme MelGenExtension \
     -destination 'generic/platform=iOS Simulator' -configuration Debug \
     build CODE_SIGNING_ALLOWED=NO
   ```

   Both schemes were then built on macOS, on generic iOS, and in Release, and
   the test targets compiled via `build-for-testing` — eight builds, no errors.
   `verify.sh` compiles the Melody sources on their own and says nothing about
   target membership or the SwiftUI layer, which is why the xcodebuild half is
   not optional.

   **Where it was predicted to break, and didn't.** All four held:

   - **Two new files** (`SeededRandom.swift`, `DeadAir.swift`) in
     `MelGenExtension/Melody/` joined the extension target on their own, which
     is what synchronized folder groups are for. Nothing to look at.
   - **`DeadAir.cap`** resolves at all seven call sites, two in sources and five
     in `Scripts/tests/`.
   - **`ChordProgression.slice(from:to:)`** is fine in `verify.sh chords`, the
     suite that compiles five files by name rather than by glob.
   - **`TakeSource`**'s move to `MaterialSource.swift` was correctly called the
     safest of the four.

   The lesson is about what a pure move inside a single-module target can
   actually cost, which is nearly nothing, and it is worth spending on the next
   seam rather than re-deriving. The one prediction still unfalsified is the
   opposite kind: none of this says the branch *behaves*, only that it builds.

1. ~~**Run `Scripts/verify.sh proggen` and read the differences.**~~ ✅ **Done
   2026-09-04: 44 labels, 3 keys, 0 differences** — the outcome this item
   thought least likely. The zero was not taken on trust; the harness was made
   to fail on planted divergences in every field it claims to compare, and to
   stay silent on a spelling-only change. Detail in the lead section above.

   **What is left of this item** is the half that was always going to outlive
   it: promote the case list into `packages/proggen/vectors/` in the monorepo,
   the way `gen-rhythm-codecs.mjs` and `gen-accompaniment-vectors.mjs` already
   do, so the Lua and C++ consumers inherit a contract that currently lives only
   in this repo. Two things found while writing the harness need writing down
   there rather than only in a comment: that ProgGenie names `IBass` and
   `VIII` while MelGen refuses both, and that the two spell the ♯IV of B major
   differently on purpose.

2. **Run [TESTING.md](TESTING.md).** Five scenarios, about forty minutes, and
   three of them are about things no suite can reach: whether the next-step line
   is read or scrolled past, whether the two drawers make sense once you are sent
   to them, and whether a MIDI round trip survives another application. Predict
   before you look — that is the whole method, and every finding in ISSUES that
   mattered came from a contradicted expectation.
3. **Chord-mode authoring** (T3). One line: `authorRow` is gated on
   `state.mode == .line` while the measured ceiling says chord mode has eight
   template slots free. Cheapest real variety on the list.
4. **Give the corpus baseline its floors** (S6 step 2b). Until then "beats the
   baseline" is a sentence a model that learned nothing can satisfy — the chain's
   held-out perplexity measured *worse than uniform*. Nothing downstream in the
   S6/S7 family means anything until this lands.
5. **Store the learned models** (S4). Fixes loose end 2, and the 2026-08-25
   review reframed it as the bigger item: because both types already round-trip
   through JSON, S4 is also the *interchange* slot for a style fitted off-device
   — and the same slot a Core ML model would compete for. See
   [COREML.md](COREML.md).
6. **Trade fours** (N6). It was XL because the model couldn't answer in four
   bars. The chain answers in microseconds and is *about* what it just heard, so
   what's left is bar-accurate switching — the most interesting item on the
   roadmap and no longer the most expensive.
