# Branch handoff — `curation-and-training`

*2026-08-22. For whoever picks this up next, including the agent embedded in
Xcode. Written while moving fast on purpose: what landed, what's loose, and what
is definitely not proven.*

The branch adds the curate → keep → learn loop. Six commits, all verified
outside Xcode, all compiling in the real target. **None of it has run on a
device.**

---

## What landed

| Commit | What it does |
|---|---|
| `Read a take back as a line…` | R1/R2. `MelodyPatterns.extract` inverts `realize`: a take plus its progression becomes a degree-relative pattern that plays over any changes. Plus `fitReport` (R3) and `PatternOrigin` provenance |
| `Curate in passes, not verdicts` | The curation model. Seven unranked dispositions, marks stamped with the pass and with what the take was heard after, facets derived from measurement, an emergent tag vocabulary, a review queue, and eviction that protects anything you marked |
| `Say what to do with a take…` | The curation interface: disposition bar, aspect picker, facet chips, tag field, review sweep, "start pass N+1" |
| `Keep a take as a line…` | `PatternStore` (a library outside the session), "Keep as a line", and rotation selection — cycle / shuffle / lock over a set you choose (T1/T2) |
| `Describe what you kept…` | `StyleLearner` measures curated takes into `LearnedStyle`; it conditions generation as prompt text and is shown in the interface in the words the model receives (S3, first cut) |
| `Work out what local training could mean` | [TRAINING.md](TRAINING.md) and `Scripts/analyse-history.sh` |

---

## Build and verify — read this first

**The Xcode 26.6 command-line tools cannot open this project.** It's in project
file format 110. Use the beta toolchain:

```bash
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project MelGen.xcodeproj -scheme MelGenExtension -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

`Scripts/verify.sh` is unaffected — it drives `swiftc` directly and now compiles
**every** Melody source rather than a per-suite list. New suites this branch:
`extraction` and `curation`. Everything passes.

```bash
Scripts/verify.sh
```

New, and not part of `verify.sh` because it needs data rather than fixtures:

```bash
Scripts/analyse-history.sh ~/Library/Mobile\ Documents/com~apple~CloudDocs
```

It compiles the real Melody sources over a directory of exported histories, so
its numbers are the plug-in's numbers.

---

## Loose ends — deliberate, and worth closing

Ordered by how likely they are to bite.

1. **Nothing has been heard.** The whole loop is unverified by ear. In
   particular: does a take marked `keep` actually change what the model writes
   next? The measurement exists (`analyse-history.sh`), the experiment doesn't.
2. **Two buttons that overlap.** "Save as example" (old, `PatternLibrary`,
   absolute-pitch text for the prompt) and "Keep as a line" (new, `PatternStore`,
   degree-relative, plays back) sit next to each other and do different things
   with the same intent behind them. The old one is probably subsumed now that
   curated takes are quoted automatically — but deleting it needs a device
   session to be sure the prompt doesn't get worse.
3. **Takes can't be named.** `GenerationRecord.title`, `displayName` and
   `MelGenState.retitle` all exist; no interface calls `retitle`. A one-line text
   field in the curation controls closes it.
4. **`partial` aspects are recorded and unused.** Marking "the rhythm works" is
   stored and does nothing. The point of the fixed vocabulary was that these are
   actionable — "keep the rhythm, re-derive the pitches" is a real transform, and
   it's the natural first entry in G11's transform list.
5. **The fit report isn't shown.** `MelodyPatterns.fitReport` is computed and
   tested and appears nowhere. Obvious home: next to "Keep as a line", and in the
   line rows when the current progression differs from the line's origin.
6. **`previousTakeID` is encoded but not decoded.** Intentional — it describes a
   listening session, not a document — but it's an inconsistency someone will
   trip over. Either give `MelGenState` an explicit `CodingKeys` that omits it,
   or decode it and stop pretending.
7. **The library is `UserDefaults`, not an App Group.** `PatternStore` is on the
   right side of the session/library line but in the wrong container: the host
   app and the plug-in don't see the same library. That's ROADMAP I5/L4, and it
   should be decided before any more library UI is built.
8. **`PatternStore` has no export or import.** History exports carry marks and
   tags (they're on `GenerationRecord`), but the derived lines can't leave.
9. **Keyboard shortcuts are macOS/Catalyst only.** `DispositionBar` guards
   `.keyboardShortcut` behind `#if os(macOS) || targetEnvironment(macCatalyst)`.
   Whether an iPad with a hardware keyboard picks them up inside an AUv3 view is
   untested — that's why the guard is there rather than an unconditional call.
10. **The style floor.** Three kept takes produce a confident-looking description
    of nearly nothing, and the interface shows it anyway. TRAINING.md §5.2.

---

## Things that will surprise you

- **`extract` never snaps.** An off-scale note becomes its nearest degree plus an
  `alteration`, and keeps the `HarmonicRole` it had over its original harmony.
  This is deliberate and is the single most consequential decision on the branch:
  a chromatic approach worth keeping and a mis-snapped pitch are the same two
  numbers, and only the original harmony can tell them apart.
- **The round trip is not tested by comparing degrees.** It's tested by
  replaying. A flattened seventh and a natural sixth can be the same pitch, and
  reading one as the other is correct rather than a loss, so degree equality is
  the wrong invariant. `Scripts/tests/extraction-main.swift` says so at the
  assertion.
- **Shuffle is a shuffled cycle**, not independent draws, and the join between
  rounds is fixed up. Independent draws repeat immediately about once every N
  picks, which reads as a bug whatever the maths says.
- **The history ring grew a second bound.** `historyLimit` (24) is when unjudged
  takes start being dropped; `historyCeiling` (128) is when marked ones do. A
  marked take survives 40 generations — that's a test.
- **`verify.sh` compiles all of `Melody/`.** If you add a file that needs
  `FoundationModels`, exclude it in `melody_sources()` the way
  `MelodyGenerator.swift` is, or every suite stops building.

---

## What to do next

From [TRAINING.md](TRAINING.md) §4, and the ordering claim is argued there:

1. **Hear it.** A device session with the loop: generate, mark, keep as a line,
   generate again, and check with `analyse-history.sh` whether the second batch
   moved toward the first.
2. **G10 — generate from the learned distributions.** Needs a chord-conditioned
   degree histogram in `LearnedStyle`. This is the item that makes the library
   stop being either generic or repetitive, and the corpus already says why: 60
   distinct lines behind 98 takes, two thirds of them stored rather than
   generated.
3. **G11 — mutate, score, morph.** The loop with a human in it.

Not next: anything involving adapters, and anything involving capturing MIDI
input. TRAINING.md §1 says why the first is a dead end for personal style, and
§4 says the second is downstream of work that hasn't been done.
