# Branch handoff — `curation-and-training`

*2026-08-23. For whoever picks this up next, including the agent embedded in
Xcode. Written while moving fast on purpose: what landed, what's loose, and what
is definitely not proven.*

Eighteen commits. Everything is verified outside Xcode and compiles in the
extension target. **None of it has run on a device**, which is the single largest
open risk and the first thing to do next.

---

## The shape of it

The branch turns MelGen from "a model writes a line" into a loop with six sources
of material, one curation model over all of them, and two learned models fed by
what survives curation.

```
        ┌─ the model (~2s/note)
        ├─ stored lines (seeds + interval cells)
        ├─ composed phrases (gestures + a phrase grammar)   ─┐
        ├─ slot statistics of what you kept                  ├─ all produce
        ├─ a chain walk over what you kept                   │  MelodyPattern
        ├─ variants and morphs of any of the above          ─┘
        ├─ what you played in
        └─ comping (chords rather than a line)
                    │
                    ▼
            realized over harmony  ──►  heard  ──►  judged (disposition, this pass)
                    ▲                                        │
                    └──────── learned from ◄─────────────────┘
                                (keep / tweak / partly)
```

The through-line: **everything produces `MelodyPattern`s** — degrees, not
pitches — so everything is realized, curated, mutated and learned from by the
same machinery. A seventh source would be a file, not a subsystem.

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

---

## Build and verify

**The Xcode 26.6 command-line tools cannot open this project** — it's project
file format 110. Use the beta toolchain:

```bash
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project MelGen.xcodeproj -scheme MelGenExtension -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

`Scripts/verify.sh` is unaffected and now runs fifteen suites, compiling every
Melody source each time:

```bash
Scripts/verify.sh
```

New suites on this branch: `extraction`, `curation`, `phrases`, `stylemodel`,
`chain`, `mutation`, `retrieval`, `topics`, `steps`, `capture`, `comping`,
`progression`. The last one also fails if the generated ProgGenie tables have
drifted from music-suite.

Not part of `verify.sh`, because it needs data rather than fixtures:

```bash
Scripts/analyse-history.sh ~/Library/Mobile\ Documents/com~apple~CloudDocs
```

---

## Loose ends

Ordered by how likely they are to bite.

1. **Heard once, on 2026-08-23, and it moved a lot.** What came back: comping is
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

1. **Hear it.** A device session that exercises the whole loop: generate changes,
   compose a phrase over them, mark a few takes, draw from the learned models,
   comp the same changes, play something in and learn from it. Then
   `analyse-history.sh` over the export.
2. **Store the learned models** (S4). Fixes loose end 2 and makes styles savable
   in one piece of work.
3. **Trade fours** (N6). It was XL because the model couldn't answer in four
   bars. The chain answers in microseconds and is *about* what it just heard, so
   what's left is bar-accurate switching — the most interesting item on the
   roadmap and no longer the most expensive.
