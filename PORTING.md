# Porting the suite — what a second plug-in would be built on

*Written 2026-09-03. Answers `docs/JUCE_INDEPENDENCE.md` §3 Option 2 in the
music-suite monorepo, which priced a native AUv3 shell as "+3–4 weeks
foundation, then days per app" and then recommended not doing it yet. MelGen
has since built that shell for other reasons. This is what it costs to use it
twice — measured where it can be measured, and marked as an estimate where it
can't.*

Everything numeric below comes from `Scripts/verify.sh boundary`
(`Scripts/tests/foundation-boundary.py`) and from the two codegen drift checks,
both of which run against a sibling `music-suite` checkout. Re-run them rather
than trusting the numbers here; they were true on the day.

---

## 0. The honest framing, before anything else

**This is not "bypassing JUCE".** It is a second shell that covers a different
part of the matrix, and it loses things JUCE was carrying.

| | JUCE shell (the seven plugin repos) | This shell (MelGen) |
|---|---|---|
| Formats | AU, VST3, AUv3, CLAP, LV2, Standalone | **AUv3 only** |
| Platforms | macOS, Windows, Linux, iOS | **macOS + iOS** |
| UI | one WebView UI everywhere | SwiftUI, written once per plug-in |
| Binaries | AGPL-encumbered while JUCE is linked | Public Domain, all the way down |
| iPadOS | works, and is where JUCE earns its keep | native, no WebView, no bridge |
| Apple Intelligence / Core ML | not reachable | reachable |

`JUCE_INDEPENDENCE.md` §4 recommends CLAP+VST3+AU desktop shells with **JUCE
kept for AUv3 on iPadOS**. MelGen is a counterexample to the second half of
that sentence, not to the first. Option 1 (CLAP + `choc`) remains the desktop
answer; the two are complements. Anything ported into MelGen's shape gives up
Windows, Linux, VST3, CLAP and LV2, and a port is only worth making where that
trade is one you actually want — which, for the iPad-first tools, it is.

There is a second tax worth naming up front: this shell floors at Xcode 26+
(27 to open the project file, format 110) and iOS/macOS 26.0+. The suite's
webapps run in any browser from any year. Nothing about that changes.

---

## 1. What is measured, and what it says

`Scripts/verify.sh boundary` strips comments and string literals from all 78
Swift sources in the extension, finds all 232 top-level type declarations, and
calls it an edge whenever one file names a type another declares — 454
cross-file references. Layered as below, and today it reports:

```
      core      46 lines  (foundation)
    theory   3,432 lines  (foundation)
   carrier   3,708 lines  (foundation)
     shell     906 lines  (foundation)
        ui   2,532 lines  (foundation)
       app  15,183 lines  (MelGen)
            10,624 lines  foundation total (41%)

  PASS  no upward references beyond the 0 known seams
  PASS  the layer manifest matches the sources on disk
```

**Two thirds of MelGen is MelGen.** The other third is the thing a sibling
plug-in would stand on, and when this was first measured it was held together by
nineteen places where a lower layer reached up into the melody app. **All
nineteen are cut** (§3), and the foundation has grown from 32% to 41%, because
deciding a file is foundation moves its lines as well as closing its seams. That
is the answer to "could we port other plug-ins": the foundation names nothing
above itself, which is the property a separate module needs and the property
nothing but this check was ever going to establish.

All five layers are now separate targets of the `EnkerliSwift` package (§7
step 4), so *the compiler* refuses an upward reference before this check
runs. The check is still here, and the reasons are in its own docstring: the counts
above are its output, proposing a move is what it is best at — and it cannot be
replaced by the build for one case in particular. **Shell and UI are siblings, and a dependency graph expresses that by
omission.** Package.swift gives neither a dependency on the other; nothing but
this check notices if someone adds one.

Which matters because the check had that wrong itself. Its rank test failed only
on a *strictly* higher rank, so `ui → shell` passed silently for as long as it
existed — and it was passing over two real edges: `ParameterSlider` and
`MomentaryButton`, Xcode-template controls that bind to `ObservableAUParameter`.
The package build is what surfaced them, which is the argument for the package
made better than this document could make it in the abstract: **a check you wrote
shares your blind spot; a compiler does not.**

The check ships and runs in `verify.sh` because the layering is not enforced by
the compiler — one target, one module, every type visible to every file — so
without a check the seam closes again silently between commits. It fails on a
new upward edge, and equally on a seam that has been cut and left in the list,
because a work list that keeps finished items is a work list nobody reads.

Also verified, from a fresh clone, on a machine with no Xcode:

```
$ python3 Scripts/generate-chord-dictionary.py  --music-suite … --check   → up to date
$ python3 Scripts/generate-progression-tables.py --music-suite … --check  → up to date
```

That matters more than it looks. The suite's stated contract is *"test vectors
are the cross-language contract; any algorithm ported to Lua or C++ gets a JSON
vector file here first."* MelGen is the fourth language in that contract after
TypeScript, Lua and C++, and the machinery for keeping it honest already exists
and already runs. **A port to Swift is not a new kind of work for this suite.**
It is the work the suite was already set up to do.

---

## 2. The layers

| Layer | What it is | Lines | Is called |
|---|---|---:|---|
| **core** | Primitives with nothing musical in them. `SplitMix64` is the whole layer, and that is the right size for it — the moment a second thing lands here, check it is really a primitive and not a chord in disguise | 46 | `EnkerliSwift/Sources/Core` |
| **theory** | Chord dictionary (172 qualities, generated from `packages/theory`), chord-scale, parser, detector, diatonic harmony, taxicab voice leading, voicings, the degree histogram, the progression generator and its corpus tables | 3,432 | `Sources/Theory` — the Swift `@enkerli/theory` (+ `proggen`) |
| **carrier** | The interchange format and everything that handles it: `MelodyPattern` and its notes, `SequencedNote`, measurement, where material came from, the three tenses, curation (dispositions, passes, facets, tags), the pattern store, interval cells, SMF read/write | 3,708 | `Sources/Carrier` — no equivalent in the suite; invented here |
| **shell** | AU plumbing: parameter tree, `ObservableAUParameter`, the view-controller host, the 692-line C++ kernel (forward / backward / ping-pong, host sync, loop counter, lock-free capture ring) | 906 | `Sources/Shell` + `Sources/Kernel` — the Swift `enkerli-juce` |
| **ui** | Theme + its WCAG audit, piano roll, action badges, direction icon, curation view, the mini roll, the pinned verb bar. The two Xcode-template controls that bind to an AU parameter left for the shell, which is where the parameter is | 2,532 | `Sources/UI` — the Swift `@enkerli/ui` |
| **app** | MelGen | 15,183 | `MelGenExtension/` |

Two observations worth more than the table.

**The shell is the smallest layer.** 906 lines, against `enkerli-juce`'s 921
lines of C++/Obj-C for the JUCE equivalent. That is a near-exact match, and it
is the strongest single argument in this document: the amount of
platform-specific glue a plug-in needs is roughly a thousand lines *whichever
framework you pick*, so the framework is not where the cost lives.

It got *smaller* while the seams were being cut, which is the direction that
matters: `PluginAudioUnit` and `PluginViewController` are what is left after
MelGen's session and MelGen's root view were lifted out of them into
`MelGenExtension/AudioUnit/`. A sibling plug-in writes those two small
subclasses — three overrides and a state property — and inherits the rest.

**The carrier layer has no counterpart in music-suite.** Curation-as-passes,
dispositions that are not scores, facets derived from measurement, an emergent
tag vocabulary — none of that exists in the monorepo. It was invented here for
melody and it is not melody-specific. If anything in MelGen deserves to be
promoted *back* into the suite as a package, it is this, and that direction of
travel is worth keeping in view: porting is not only outward.

---

## 3. The seams — all nineteen cut

They were listed in `Scripts/tests/foundation-boundary.py`, each with a note on
how it gets cut, and that list was the work order rather than a copy of one. The
list is empty now; the check that reads it stays, because the layering is still
not enforced by the compiler and a new upward reference would otherwise land in
silence. Four are worth calling out here.

**`ProgressionGenerator` → `SplitMix64`** — ✅ *cut*. A seeded RNG that happened
to live in `MelodyExpression.swift`, reachable only because everything is one
module, and reached for by every generator here: phrases, comping, basslines,
retrieval, topics, pattern selection, and a progression generator that is
theory and has no business knowing a file about swing exists. It now lives in
`SeededRandom.swift` in a `core` layer below theory. Cheapest cut on the list
and the right one to make first, because it proves the audit finds real things
rather than modelling artefacts — and because the loop it demonstrates (cut,
re-run, watch the list shrink) is the whole method.

**`MelodyPattern` and its namespace** — ✅ *cut, and it took five with it, then
a sixth*. Five seams were the carrier reaching for the pattern format, and one
decision closed all of them: **a degree-relative line with lengths and rests is
the interchange format**, not a MelGen internal. It is already what MIDI import,
the pattern store and the corpus exporter all speak, and it is the thing a
sibling plug-in would hand this one.

Ruling it foundation forced three of its own reaches downward, and each turned
out to be a thing in the wrong place rather than a coupling to break:

- **`TakeSource`** lived in `MelGenState.swift`, which made it session state. It
  isn't: it is stamped into `PatternOrigin`, so it travels inside every exported
  pattern and every `.mid` this plug-in writes. It moves beside `MaterialSource`
  — the same question, asked after the fact — which also cut the separate
  `MelodyCuration → TakeSource` seam that had been listed with the wrong remedy
  ("pass a String tag"). Two subsystems reaching up for the same type was the
  evidence that the type, not the reaching, was misplaced.
- **`capDeadAir`** sat inside `MelodyExpression`, next to swing and metric
  accent. Expression is how a take is *performed*; this is a repair to what the
  take *is*, applied during realization, before any of that. It moves to
  `DeadAir.cap` and knows nothing about melody, chords or MelGen — it takes
  notes and beats.
- **`MelodyChunker.slice`** was never chunking. It clips a progression to a beat
  window and rebases it, using only theory types, and it happened to live in the
  file that first needed it. It becomes `ChordProgression.slice(from:to:)`,
  where a reader would look for it.

That is the pattern worth naming, and it held all the way to the end: **an
upward reference is usually a file in the wrong place, not a dependency that has
to be broken.** Three of these four cuts were moves, and none changed a line of
logic. Of the nineteen, fifteen were moves or reclassifications.

**`ChordVoicing` → `DegreeHistogram`** — ✅ *cut, and the remedy written here
was wrong.* This was called the only seam that was a design decision rather than
a tidy-up: the Drawn voicing asks the *learned* degree histogram which colour
this chord can carry, so invert it and have the caller pass weights in. Reading
the call site said otherwise. `drawnIntervals` only ever calls
`DegreeHistogram.stack(over:reach:)`, which is built from the chord's own scale
with its avoid notes damped — derived, not learned — and no caller has ever
passed it a histogram read off takes. Nothing was reaching up into learned
state; two things were sharing a file.

So the cut was the ordinary one after all. `DegreeHistogram.swift` split three
ways: the distribution and its arithmetic stayed and became theory,
`DegreeObservation.swift` took the two `observed(in:)` overloads that read a
histogram off material somebody played, and `DegreePlacement.swift` took the
conversion back into the pattern format. `HarmonicRole` went down to
`ChordScale.swift` at the same time — it is a question about a semitone and a
chord's scale and had no business being in `MelodyAnalysis.swift`. That is +566
lines of theory and one fewer design decision than this document expected.

**The three shell seams** were the ones the prediction got right, and the shape
was almost the predicted one. §3 said "three of these become one generic
parameter and one protocol." A generic parameter is not available: the principal
class is looked up by name out of `Info.plist` through the ObjC runtime, and a
generic Swift class has no ObjC name and cannot override the `@objc` members
`AUViewController` declares. A base class with three overrides is what survives
that constraint. `PluginViewController` and `PluginAudioUnit` are the shell;
`AudioUnitViewController` (which keeps its name, because `Info.plist` names it)
and `MelGenExtensionAudioUnit` are MelGen's, and live in
`MelGenExtension/AudioUnit/`. The session state, the setup store and the root
view all moved up with them.

---

## 4. Separate plug-ins, not modes

The instinct is right, and there are three reasons beyond "MelGen is already
overloaded" — though it is, and that alone would do.

**The AU identity is per product, and the suite already treats it that way.**
A component is its `(type, subtype, manufacturer)` triple, not its name.
`Scripts/tests/component-identity.py` exists in this repo because the Xcode
template's default subtype was `Prst` — Progression Studio's code — and loading
ProgGenie in AUM launched MelGen instead. The codes are already allocated
across the suite (`Mcur`, `Prst`, `Pqf1`, `RPEd`, `VAne`, `Wksp`, `Dqau`) and
they are forever. A mode inside MelGen has no identity; a plug-in does, and the
host's routing, per-instance state and session recall all hang off it.

**Hosts instance plug-ins, not modes.** Two Serpe instances feeding two drum
kits, or a Serpe and a MelGen on different tracks, is a thing a DAW does for
free and a mode switch cannot do at all. Every mode added to MelGen is a
feature that can only exist once per session.

**MelGen's own mode axis is already carrying weight.** Line / Chords / Bass
exists because *the receiving instrument differs* — a mono synth handed chords
plays whichever note wins its note-priority rule. That is a good reason for a
mode and it does not generalise to "and also rhythm generation".

The cost of separate plug-ins is exactly §2 and §3: without an extracted
foundation, three plug-ins means three chord dictionaries drifting apart. The
suite has already lived that (§9). **The foundation is the price of the plural,
and it is why the boundary check comes before the second plug-in rather than
after it.**

---

## 5. Rhythm, UPI, and which vectors

The intuition — *there is a rhythmic component in melodic and harmonic patterns,
and it uses the vectors* — is half true, and the half that isn't is the useful
part.

**Where the suite's rhythm authority actually sits.** Not in `@enkerli/upi`. It
is in `packages/theory/src/rhythm.ts`, held by `packages/theory/vectors/rhythm.json`
— seven groups of cases (euclidean, complement, Barlow tables, syncopation,
transforms, codecs, codec batch), described in the file as *"ported from Serpe
(rhythm_pattern_explorer)… verified by differential testing against the
original WebApp JS (all E(k,n) for n≤24 with offsets, Barlow tables,
transforms)"*. That is the densest cross-language contract in the monorepo
after the chord dictionary. `@enkerli/upi` is the layer *above* it — notation
(`parseUPI`), generators, transforms, polyrhythm, progressive patterns — about
2,600 lines of engine JS held by exactly one small vector file (`poly.json`,
3.5 KB).

So Serpe's engine is already split, and the split is favourable: **the
algorithms are vector-covered theory; the notation is not.**

**MelGen uses none of it, and could not.** There is no Euclid, no Barlow, no
indispensability, no onset mask anywhere in this repo. MelGen's rhythm is
*durations on an eighth grid* — `lengthEighths` and `restAfterEighths`, carried
inside the token itself (`ChainToken.key`, deliberately, because a chain over
pitch alone learns melody without rhythm). A UPI pattern is *a mask of onsets*,
leftmost = LSB. These are two different objects. A mask has no durations; a
MelGen line has nothing to say about which of sixteen slots are struck.

**The bridge between them already exists in the suite, and nobody has used it
here.** `packages/accompaniment/src/rhythm.ts::applyRhythm` takes a phrase's
pitch material and performs it on a different onset grid: `ticksPerStep =
lengthTicks / steps.length`, onset *k* takes its pitch from source event *k*
(cycling), durations legato-to-next-onset, accents boost velocity, and a
chromatic approach's target re-points to the next onset because "resolves to
whatever comes next" is what the approach *means* independently of grid. That
is precisely the operation MelGen would want, written down, deterministic, and
already reasoned about.

### What that implies for the work

1. **Port `theory/rhythm.ts` into the foundation's theory layer, held to
   `vectors/rhythm.json`.** Same method as the chord dictionary: generate or
   hand-port, then check against the suite's own cases. This is shared code in
   the strict sense — one implementation, four languages, one vector file.
2. **Port `applyRhythm` into the carrier layer.** It is the thing that lets
   MelGen gain rhythm replacement *without becoming Serpe*: a line you kept,
   performed on a tresillo, is a MelGen feature that costs one function.
3. **Leave UPI notation to Serpe.** The parser is where Serpe's identity lives,
   it has almost no vector coverage, and MelGen has no use for a notation
   language. Swift Serpe can then go somewhere new at the notation and
   interaction level — which is the point of porting rather than transcribing —
   while still being provably the same engine underneath.
4. **Write UPI vectors first, in the monorepo.** One thin file is not enough to
   hold a port honest. This is a prerequisite for Swift Serpe and it pays off
   for the Lua/PdLua branch at the same time.

One convention is non-negotiable and easy to get wrong in a language with no
prior art here: **first step = leftmost bit = LSB**, and hex/octal digit
strings are little-endian, so tresillo `10010010` reads `0x94`. It is stated in
`CONVENTIONS.md`, it is in the vectors, and it is the single thing a Swift port
would silently invert.

---

## 6. Where each plug-in sits

| Plugin | Engine | UI | Verdict |
|---|---|---|---|
| **ProgGenie** (`aumi Prst`) | `packages/proggen`, ~1.1k JS; MelGen already ships its tables | 2.7k JS, 1.8k of it one JSX file | **Pathfinder** — §7 |
| **Serpe** (`aumi RPEd`) | rhythm algorithms already vector-covered in `theory`; notation in `upi` | 2.7k JS | Second. Vectors first |
| **PitchFold** (`aumi Pqf1`) | 4,024 LOC C++ quantizer, largely theory MelGen has | 3.1k JS | Third, and the smallest total surface |
| **MIDIcurator** (`aumi Mcur`) | thin (1,090 LOC shell) | **14.6k JS — the product** | Engine cheap, UI is the plug-in. Wrong shape for a SwiftUI rewrite; best Core ML story (§8) |
| **DrawnQurve** (`aumi Dqau`) | 25.2k LOC, JUCE-7 native UI + engine | mid-migration | Wait for its WebUI migration, as the suite already says |
| **Vane** (`aumu VAne`) | 11.9k synth DSP, already proven shell-free as WASM | 1.2k | Different animal — an instrument with a real audio render. Breaks the invariant in §8 |
| **Suite Workspace** (`aumi Wksp`) | — | 4.6k | Container; no |

---

## 7. ProgGenie as pathfinder

`JUCE_INDEPENDENCE.md` picks ProgGenie as the pathfinder for Option 1 —
"smallest shell, device-verified webapp, low blast radius". It is the right
choice here too, for a reason that looks at first like a disqualification.

**MelGen already contains ProgGenie's engine, and a superset of it.**
`ProgressionGenerator.swift` (672 lines) walks the same corpus transition
tables, blends first and second order with the same backoff logic, and realizes
labels through MelGen's own chord dictionary. It replaces ProgGenie's
temperature with **Surprise** — which walks down the ranked list rather than
flattening the distribution, on the argument that a leadsheet corpus has a long
tail of things seen once and flattening reaches the tail before it reaches the
interesting middle — and adds **Freshness** and a **Reharm** that is explicitly
a superset of ProgGenie's ("with only tritone and backdoor, Subtle is a no-op
on any progression whose middle is minor sevenths, which is most of them, and a
control that does nothing most of the time reads as broken").

So the pathfinder is not building a product MelGen lacks. **It is proving that
the third of MelGen in §2 can be stood on twice**, on the app where the engine
is already written and therefore cannot hide a failure to share. If ProgGenie
ends up with its own copy of the chord dictionary, the extraction failed, and
that is worth finding out on the cheapest app rather than the fifth one.

### The product delta, for when it becomes a real plug-in

Two things ProgGenie has that MelGen does not:

- **Per-transition curation.** `packages/proggen/src/curation.js` keeps a map of
  multipliers per `from → to` transition, clamped to [1/16, 16], nudged by
  emphasizing a single change or rating a whole progression, persisted, and
  exportable as a shareable JSON profile. MelGen curates *takes*; it has no
  notion of "this change sounds good" as a durable, portable weight. This is
  the most interesting thing in ProgGenie and it has no equivalent here.
- **Corpus browsing** — seeing what the statistics actually say, rather than
  only hearing their output.

### The divergence that has to be resolved first

`packages/proggen` has **no `vectors/` directory**. Neither does `@enkerli/upi`
beyond `poly.json`. So MelGen's progression generator is checked against its own
expectations (`Scripts/tests/progression-main.swift`) and against the *tables*
(the codegen `--check`), but nothing checks that Swift and JS agree on
behaviour. They already deliberately don't, on Surprise and Reharm — which is
fine, and is exactly why the boundary between "shared, vector-held" and
"divergent on purpose" needs writing down before there are two consumers.

The shareable, deterministic part is narrower than the whole engine and should
be the vector's scope:

- label splitting (`IIm7` → `II` + `m7`, `♭VII7`, `♯IVm7b5`, longest-numeral-wins)
- numeral → semitones (`♭II` wraps rather than going negative)
- label + key → spelled chord symbol, and which labels are *refused*
- the tables themselves (already checked)

Sampling — Surprise, Freshness, Reharm, the backoff blend — is where the two
implementations are allowed to differ, and saying so in the vector file is the
point of writing it.

### Order of work

Steps 1–3 run anywhere. Step 4 on needs a Mac with Xcode 27.

1. **Cut the cheap seams.** ✅ *started* — `SplitMix64` moved out of
   `MelodyExpression.swift` into `SeededRandom.swift`, which is now a `core`
   layer below theory: primitives with no music in them. The seam list went
   from 19 to 18 and `verify.sh boundary` still passes, which is the loop
   working. Then `MelodyPattern` was ruled the interchange format, which closed
   five more and dragged `TakeSource`, `capDeadAir` and `slice` into the places
   they belonged — 19 → 12, and the foundation grew to 35%.

   Then two view seams, on the pattern §3 names: a view that reaches up for a
   type it only reads strings and numbers out of does not need the type.
   `NextStepRow` takes a title and a reason instead of a `NextStep`, and
   `VariantRow` takes a name and three scores instead of a `MelodyVariant`.
   Both are pure — the call site now does the unwrapping the row used to do,
   and nothing else changed. 12 → 10.

   `MiniRoll` was also classified in the same pass, as `ui` rather than the
   `app` it had been defaulting to. It only names `SequencedNote`,
   `ChordProgression`, `MelGenTheme`, `MelodyAnalyser` and `MelGenMetrics`, all
   foundation, so it passes clean and a sibling plug-in inherits a
   glance-at-the-take drawing beside the reading one. It reached this state by
   landing on `layout-pass` while the boundary check was being written on
   another branch, which is worth knowing about the check: it verifies that the
   manifest names files that exist, **not** that every file is named, so a new
   UI file still defaults to `app` in silence.

   ✅ **Finished 2026-09-05: 10 → 0.** `MaterialSource` stopped naming
   `PlayMode` (the mode now answers "which sources can produce what I am
   producing", which is the only part that was ever MelGen's);
   `MelodyStepPattern.swift` and `DegreeHistogram.swift` were reclassified after
   the trial showed neither introduced a new upward reference;
   `DegreeHistogram.swift` split three ways and `HarmonicRole` moved down to
   `ChordScale.swift`; `ReviewRow` took four values instead of a
   `GenerationRecord`; `CapturedMIDIEvent` moved down beside `SequencedNote`,
   which is what the shell's capture ring actually needs; `ChordDetection` took
   a three-field `SoundingNote` instead of the carrier's note type; and the AU
   class and the view controller each split into a shell base and a MelGen
   subclass (§3). Foundation 35% → 38%, `verify.sh` green with nothing skipped,
   and all four Xcode builds — extension on iOS Simulator, host app on macOS and
   generic iOS, Debug and Release — succeed.

   Two things are worth keeping from the pass. The `ChordVoicing` remedy written
   in §3 was wrong and reading the call site was what showed it (§3 again). And
   the check earns its keep in an unglamorous way: three times, a reclassification
   was *proposed* by editing the manifest and running it, which reported exactly
   which new upward references the proposal would create before any code moved.
2. **Hold the port to ProgGenie's own answers.** ✅ *run, and they agree* —
   `verify.sh proggen` compares the deterministic half: how a corpus label
   splits, where its numeral lands in semitones, and what MelGen refuses to
   play. `Scripts/tests/proggen-reference.mjs` runs against the real
   `@enkerli/proggen`; `Scripts/tests/proggen-diff.py` states in code what is
   compared and what is allowed to differ.

   First run on a Mac, 2026-09-04: the Swift emitter compiled unchanged, and the
   comparison reports **44 labels in 3 keys, 0 differences**. The first real
   differences were supposed to be the point, so a zero needed justifying rather
   than celebrating. Two things justify it. The check is not thin — 132 realized
   cells, 120 playable, all twelve semitone classes and twelve distinct quality
   keys. And it is not inert: a planted wrong `rootPc`, `semitonesAboveTonic`,
   `qualityKey` or `playable` flag, and a dropped label, each produce exactly
   one named `DIFF`, while a spelling-only change produces none — which is the
   single divergence it exists to tolerate. `IBass` and `VIII` come back
   unplayable on both sides, as §7 says they should.

   **Next:** promote the case list into `packages/proggen/vectors/` in the
   monorepo, the way `gen-rhythm-codecs.mjs` and `gen-accompaniment-vectors.mjs`
   already do, so the Lua and C++ consumers inherit it. The agreement is
   currently a fact about two checkouts on one machine; a vector file is what
   makes it a contract.
3. **Decide what the foundation is called and where it lives** — ✅ *decided
   2026-09-05*. A local Swift package in this repo first, extracted to its own
   GitHub repo once it has stopped moving and before the first sibling plug-in
   needs it — the ordinary answer this step already named, chosen because the
   plug-ins are going into separate repos and a package that is already a
   package moves cleanly. The targets are named after their music-suite
   counterparts where they have one (§2's right-hand column).
4. **Move the foundation into a Swift package target**, MelGen depending on it,
   no behaviour change. ✅ *Done 2026-09-05.* `EnkerliSwift` has `Core`,
   `Theory`, `Carrier`, `UI` and `Shell` as separate targets, plus `Kernel` for
   the C++ the shell talks to. MelGen's extension links all six, `verify.sh` is
   green with nothing skipped, and every Xcode build passes. The suites build the package once and compile the app sources
   against the built modules, which is also the configuration the plug-in ships
   in — before this, every suite compiled foundation and app as one module and
   could not have caught a missing `public`.

   **What the split cost, since §0 promises measurement rather than estimate.**
   Two mechanical passes over 10,694 lines: `public` on everything a single
   module never made anyone mark, and the memberwise initializers Swift
   synthesizes but keeps internal. The second is the one that bites — a public
   struct's free memberwise init is *internal*, so splitting the module silently
   removes every `SequencedNote(note:velocity:startBeat:durationBeats:)` call
   site in the app. Fifty-five of them were written out. Four rules had to be
   rediscovered by breaking a call site each: `@Binding` takes a `Binding<T>` and
   assigns through the underscore, `@ViewBuilder` survives onto the parameter, a
   non-optional closure parameter is `@escaping` and an optional one already is,
   and **a `var` of optional type defaults to nil with no `=` written** — which
   is the easiest to forget and the hardest to spot.

   The `public` sweep is deliberately over-broad and worth saying so plainly:
   every symbol it marked was already visible to every file in the extension, so
   nothing was widened that was not already open — but the code has never
   recorded which of those were API and which were helpers nobody meant to
   expose, and no compiler can tell them apart. Narrowing it is a separate pass
   with no automated help.

   **What the split found**, which is the part worth the trouble: two seams the
   boundary check was blind to. `PatternStore` and `MIDIFileImport` were calling
   `MelodyPatterns.seeds` and `MelodyPatterns.extract`, both declared in
   extensions in the app — and the check ignores extensions on purpose ("an
   extension in the app on a foundation type is not the app owning it"), which is
   right for ownership and wrong for compilation. Both files were carrier and
   moved. And `ui → shell` (§1).

   **The shell was the interesting one**, and all three of the things that made
   it look hard turned out to be small.

   The header-only C++ kernel is its own target, `Kernel`, with one `.mm` file
   whose whole job is to give SwiftPM something to compile and to fail the build
   if either header stops parsing. It has to be Objective-C++ rather than C++:
   `NS_ENUM` and `AudioToolbox/AUParameters.h` do not compile as plain C++, which
   is a two-minute discovery and an hour if you go looking in the wrong place.
   `Shell` depends on it with `.interoperabilityMode(.Cxx)` and imports it as a
   module, which is what replaces the bridging header — SwiftPM has no equivalent
   and does not need one.

   And the third was a naming problem all along.
   `MelGenExtensionParameterAddresses.h` made the kernel look as though it
   depended on the melody app; the addresses in it are `playMelody`,
   `playbackDirection` and `hostSync`, which are the parameters *a loop player*
   has. It is `PluginParameterAddresses.h` now, and nothing about the rename
   changed a line of logic. This was the one seam the boundary check could never
   have found, because everything under the extension's `Common/`, `DSP/` and
   `Parameters/` was classified shell by its directory rather than by what it
   named — the same class of blind spot as the `ui → shell` bug above, and found
   the same way: by trying to build the thing separately.

   What is left in the extension is MelGen: its session, its root view, its three
   overrides on `PluginViewController`, and its own parameter tree. That is the
   file list a sibling plug-in writes.
5. **Build ProgGenie as a second AUv3** on that package: new triple (`aumi
   Prst`, checked by `component-identity.py` — which cannot see a Swift sibling
   yet, §9), progression generation, playback through the same kernel,
   per-transition curation as the new work.
6. **Report back into `JUCE_INDEPENDENCE.md`** with what it actually cost, so
   §3's estimates stop being estimates.

Steps 1 and 2 de-risk everything after them, and neither needs a Mac — which is
why they are the two that are done.

### What the vector already found, before Swift ran

Writing the reference harness surfaced two divergences that were real and
undocumented:

- **`IBass` is a label ProgGenie will name and MelGen will refuse.** ProgGenie
  realizes it to the symbol `CBass` with a null quality; MelGen returns
  nothing, because a generated progression has to be one the rest of the
  plug-in can actually play. Both behaviours are right. Neither was written
  down, and `progression-main.swift` asserted MelGen's half without ever
  mentioning that the other side disagreed. It is now a contract in the vector
  rather than an accident in two codebases.
- **The two implementations spell differently on purpose.** ProgGenie writes
  the ♯IV of B major as `E♯m7b5`; MelGen writes `Fm7b5`, because
  `chordText(for:key:)` builds from `flatNoteNames` and then insists its own
  parser can read the result back. So the check compares pitch class and
  quality key, never orthography — a vector that demanded the same string would
  have been inventing a contract nobody agreed to, and would have failed on
  every sharp key.

---

## 8. Core ML, narrowly

Being accurate about the current state: **there is no Core ML in this
codebase.** `import CoreML` appears in no Swift file, there is no `.mlpackage`,
and `Scripts/training/export_coreml.py` has no consumer. `COREML.md` §4
documents, to its credit, that its own gate is broken — on a 32-take export the
`MelodyChain` baseline measured *worse than guessing uniformly* (perplexity
109.0 at the default smoothing, 32.0 for uniform), so "beats the baseline" is
currently satisfiable by a model that learned nothing. The stated fix — compare
against the best of chain, unigram and uniform — has not landed.

So Core ML is not a reason to port. It is a capability some ports would unlock:

- **MIDIcurator — the strongest case, and it isn't generative.** Curation over
  a collection is embedding, nearest-neighbour and classification: what the
  Neural Engine is actually good at, with no baseline-gate problem because the
  alternative is hand-written similarity heuristics rather than a well-tuned
  Markov chain. The plug-in with the worst UI-port story has the best Core ML
  story, which is worth sitting with.
- **Serpe** — a model over step patterns conditioned on UPI's own analysis
  features (evenness, balance, syncopation, Barlow indispensability) is
  plausible, and those weights make unusually good conditioning. The same gate
  applies: it has to beat Euclid + Barlow + rotation, which are strong,
  instant and inspectable.
- **PitchFold, ProgGenie, Vane** — no. A quantizer is a lookup, a Markov chain
  is a Markov chain, and a synth voice is DSP.

The real Core ML argument is architectural rather than per-app. MelGen's
invariant is that **nothing runs on the audio thread**: every source produces a
whole pattern off-thread and the kernel schedules already-decided notes, so
inference has a budget of one loop rather than one buffer. Any plug-in built on
this foundation inherits that for free. Vane is the one candidate that breaks
it, and that is the deeper reason Vane is last rather than its line count.

---

## 9. What this actually risks

**Divergence, not effort.** `packages/accompaniment` is GloriArp's engine —
canonical accompaniment phrases plus a deterministic bass adapter, "headless by
construction", with eight vector files including walking bass, two-feel, bossa
and funk-ghost. MelGen has `Bassline.swift` (822 lines) and
`MelodyComping.swift` (494 lines), and `verify.sh` references no accompaniment
vector at all. **There are already two bass-and-comping engines in this suite
that have never been made to agree.** That is the failure mode a porting
programme multiplies, and the suite's own rule is the fix: vectors first, in the
monorepo, then the implementation held to them. Applied *before* the next port,
not after — otherwise "port" quietly means "reimplement".

**Three chord dictionaries.** There are already TypeScript, Lua and C++ ports
plus this one. Every new Swift plug-in that does not share the foundation makes
it five. The boundary check exists to make that visible while it is still one.

**The identity registry is a shared, unversioned resource.** Plugin codes are
forever, `component-identity.py` reads sibling `CMakeLists.txt` files to find
them, and a Swift plug-in has no `CMakeLists.txt`. The second Swift AUv3 is the
point at which that lookup needs to learn about `Info.plist` siblings too, or
the check quietly stops checking.

**The Apple-only tax, again.** Everything in §0. It is the right trade for the
iPad-first tools and the wrong one for anything that has to run on the miniPC
or in a browser, and no amount of shared foundation changes that.
