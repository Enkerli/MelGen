# MelGen — Feature Roadmap

*Last updated: 2026-08-25, after the second design pass and a review of where the
next value is — see [Reviewed 2026-08-25](#reviewed-2026-08-25--where-the-next-value-actually-is).*

A consolidated inventory of planned work, backlog items and exploratory ideas.
Items are split between **this plug-in**, **shared suite infrastructure** (things
MelGen needs that belong in `music-suite` or a sibling), and **sibling projects**
that would share this codebase but have a distinct plug-in identity.

**On curation** (settled 2026-08-22): curation here is modelled on library
science rather than on rating. Two vocabularies, not one — facets that are
derived, fixed and structural, and tags that are typed, free and emergent, with
an explicit ratchet from the second to the first. Judgement is provisional and
happens in passes; nothing is ever removed from consideration, because a take
that was dull after one thing is the thing you needed after another. Direct
retrieval when you know what you want, serendipity when you don't. See
`MelodyCuration.swift` for the model and [TRAINING.md](TRAINING.md) for what gets
learned from the result.

**On overlap with the suite** (settled 2026-08-22): the fact that ProgGenie
generates progressions and MIDIcurator curates patterns is *not* a reason to
leave those out of MelGen. This project is built through a different system from
the suite, and the exploration — Foundation Models complemented by deterministic
processes, with generation, adaptation and curation in one environment — is the
point. Duplicated capability is an acceptable cost of that; "a sibling already
does this" is not an argument against planning a feature here. None of this is
meant to be a product.

---

## What landed on `curation-and-training`

Eighteen commits, 2026-08-22 to 2026-08-23, since merged. Everything below is
verified outside Xcode by `Scripts/verify.sh`, and has now been heard on device —
three sessions, 2026-08-23 to 2026-08-24. What that surfaced is in
[ISSUES.md](ISSUES.md).

| Area | Items |
|---|---|
| Curation | L1 (as dispositions and passes), L2, G5 |
| Re-harmonization | R1, R2, R3 |
| Templates | T1, T2, T5 (gestures as motif seeds) |
| Generation without the model | G10 (gesture phrases), G11 (mutate/score/morph), D2 |
| Learned material | S1, S2 (via capture), S3, and the two models the analysis staged |
| Polyphony | P1, P2, P3, P4 |
| Input | N5 (capture), and the melodic half of what N1 wanted |
| Progressions | B1, generated here rather than pasted |
| Shared formats | I3 (degree-relative, aligned with `@enkerli/accompaniment`), I1 (voicing layer, built here, not yet extracted) |

There are now **six sources of material**, and the interface labels every take
with which one produced it: the model, a stored line, a composed phrase, a draw
from your own slot statistics, a walk through your own chain, and a variant or
morph of something else — plus captured playing and comping, which are takes too.

The through-line is that all of them produce `MelodyPattern`s, so all of them are
realized, curated, learned from and mutated by the same machinery. Adding a
seventh source is a file, not a subsystem.

---

## Contents

1. [Where This Is Going](#where-this-is-going)
2. [Priorities](#priorities)
3. [Pending Fixes](#pending-fixes)
4. [Roadmap: This Plug-in](#roadmap-this-plug-in)
   - [Generation: Limits & Quality](#generation-limits--quality)
   - [Deterministic Lines](#deterministic-lines)
   - [Templates & Motifs](#templates--motifs)
   - [Rhythm & Duration](#rhythm--duration)
   - [Polyphony & Comping](#polyphony--comping)
   - [Learned Styles](#learned-styles)
   - [Pattern Library & Information Architecture](#pattern-library--information-architecture)
   - [Interchange: MIDI Files & Drag-and-Drop](#interchange-midi-files--drag-and-drop)
   - [Input Routing](#input-routing)
   - [Re-harmonization](#re-harmonization)
   - [Interface](#interface)
   - [Platform & Quality](#platform--quality)
5. [Shared Suite Infrastructure](#shared-suite-infrastructure)
6. [Sibling Projects](#sibling-projects)
7. [Open Questions](#open-questions)
8. [Effort Reference](#effort-reference)

---

## Where This Is Going

MelGen started as "generate a melody over these changes." The direction of travel
is a **generative pattern instrument**: you give it harmonic context, it proposes
material, you curate what it proposes, and it learns from what you keep.

Three axes separate out, and keeping them separate is what makes the thing
comprehensible:

| Axis | What it is | Where it lives now |
|---|---|---|
| **Harmonic context** | The progression the material is played against | Leadsheet text field, `ChordParser` |
| **Pattern** | The rhythmic/melodic figure, independent of harmony | A take's raw notes in `GenerationRecord` |
| **Realization** | How the pattern sounds — gate, accents, swing, register | `MelodyExpression`, applied live |

The interesting consequence: a pattern is *not* bound to the progression it was
generated over. That unlocks re-harmonization, a pattern library worth curating,
and interchange with MIDIcurator. Most of this roadmap follows from taking that
separation seriously.

---

## Priorities

*Reviewed 2026-08-22, after the first real session of playing the plug-in in AUM.*

The review changed the ordering. Most of what was written down was about *adding*
capability; playing it revealed that the existing capability isn't trustworthy
yet. A 16-bar progression — an ordinary jazz form — fails outright. Lines come out
wall-to-wall with notes and never breathe. Takes repeat themselves even at
temperature 0.89. Auto-regeneration silently can't keep up with its own setting.
None of those are missing features; they're the current feature not working.

So Wave 1 is "make what exists trustworthy", and it comes before everything else.

### Wave 1 — make the current thing trustworthy

| # | Item | Impact | Effort | Depends on | Why now |
|---|------|--------|--------|-----------|---------|
| G8 | Adapt stored lines (no model) | **Critical** | L | — | ✅ **done 2026-08-22** — instant lines, so playback no longer waits on a model that runs 4× slower than real time |
| G1 | Chunked generation (long progressions) | **Critical** | M–L | — | ✅ **done 2026-08-22** — 16 bars now generates as four phrases, and ProgGenie output works |
| G2 | Rests | **High** | S–M | — | ✅ **done 2026-08-22** — schema field, prompt requirement, and a guaranteed breath every two bars |
| G3 | Per-note gate | **High** | M | — | ✅ **done 2026-08-22** — derived per note from the next interval; the slider is now an amount over that shape |
| G5 | Variety scoring (pre-curation) | **High** | M | — | ✅ **done 2026-08-22** — `MelodyAnalysis` measures every take (interval and rhythmic variety, self-similarity, harmonic roles) and the score shows in the history. Annotate-only, per Open Question 6; reject-and-retry is deliberately not built |
| G4 | Measure generation time | Medium | S | — | ✅ **done 2026-08-22** — recorded per take, and compared against the actual loop duration |
| G6 | Buffer takes ahead | **High** | M | G1, G4 | ✅ **done 2026-08-22** — generates a loop ahead and swaps on the boundary |

**Wave 1 is complete**, and so is R1/R2 — the loop closes: a take you liked is
read back as scale degrees and joins the library, and the library conditions the
next generation. See [TRAINING.md](TRAINING.md) for what "conditions" can and
can't mean.

Heard on device twice, 2026-08-23 and 2026-08-24. What that produced is in
[ISSUES.md](ISSUES.md); `Scripts/analyse-history.sh` is how a session gets
measured rather than impressioned.

### Wave 2 — make it interactive

| # | Item | Impact | Effort | Depends on | Why |
|---|------|--------|--------|-----------|-----|
| U1 | Piano-roll display | **High** | L | — | ✅ **done 2026-08-23**, playhead added 2026-08-24. Detail row in [Interface](#interface) |
| N1 | Probe multi-cable input | Medium | S | — | An afternoon that decides the shape of all input routing |
| T1/T2 | Template selection, cycle vs randomize | Medium | S | — | ✅ **done 2026-08-22** — multi-select over the briefs, plus cycle / shuffle / lock for both briefs and stored lines. Shuffle is a shuffled cycle, so everything is heard once per round and no round opens with what the last one closed on |
| X1/X2 | MIDI export and drag-out | **High** | M | — | Nothing leaves the plug-in today except live MIDI. Independent of everything else |
| N4 | Chords in as harmonic context | **High** | L | N1 or N2, I6 | The richer ProgGenie link, and how MelGen stops being a text box |

### Wave 3 — make it a library and an instrument

Curation (L1–L3), re-harmonization (R1–R2) and comping (P1–P3) **all landed
early**, because the loop they close is the thing the project is for. What's left
in this wave: library search and filtering at scale (L3), the session/library
split done properly (L4, needing I5), chord information in exported MIDI (X3),
and — new, from the second device session — **taxicab voice leading** for comping
(P6), which landed 2026-08-24: over a ii–V–I–VI the comp now moves 20 semitones
where register-only leading moved 35, and the same measure smooths the seam where
a line crosses a chord change.

### Wave 4 — research

Trade fours (N6), and the parts of the learned-style series that aren't already
done. The analysis of what's reachable is in **[TRAINING.md](TRAINING.md)**, and
it shaped this wave: Foundation Models cannot be trained on device at all, its
adapter path is a developer artifact rather than a personal one, and everything
worth having in the near term is transparent statistics over the curated corpus.

S1 (learn from incoming MIDI) and S3 (style extraction) are done, and generating
from the learned distributions is done. What's left: S4 (storing the learned
models instead of recomputing them), S5 (style transfer), the in-app half of S2,
and N6. The 2026-08-24 session pointed at the same conclusion from the other
direction — mono patterns became more palatable through **mutation and morphing**,
which are Markov-ish and deterministic, so the refinement path runs through
M-series work rather than through the model.

**Reopened 2026-08-24 by a large MIDI collection.** TRAINING.md closed the
off-device question mostly on corpus size, and more material changes that
arithmetic and nothing else about the reasoning. So S6 (a corpus, and a number to
beat) and S7 (a trained model through Core ML) join this wave, with the gate
written into S7: it closes rather than continues if it can't beat the chain. The
analysis is **[COREML.md](COREML.md)**. The cheapest item in the family is
neither of them — it's pointing S2's new reader at the collection and letting the
models that already ship learn from it, which needs no tensor, no conversion and
no Xcode. Cheaper still since history import landed the same day: the corpus
exporter already builds `GenerationRecord`s, so having it write a history export
puts a found collection in front of the chain and the slot model through the file
picker, with no new Swift at all.

### Reviewed 2026-08-25 — where the next value actually is

*After the design pass merged and the icon landed, a pass over the whole list
asking one question: which item returns the most for what it costs.*

The answer isn't in-app MIDI import, and the reason is worth stating because the
opposite is the obvious guess. Reading a found collection into the plug-in
sounds like the big unlock — but the pipeline that does it **already exists on
the desktop side and is already tested**, and it solves the hard half that a
Swift SMF parser wouldn't: *where the harmony comes from*. A MIDI file is a
pattern with no chords under it, and a degree with no chord under it is just a
pitch. `midi_to_events.py` reads harmony from a sidecar, from markers, or from a
chord track, and says so plainly when there is none ([COREML.md](COREML.md) §5).
An in-app reader would have to answer that question a second time, worse.

So the CLI route wins, and it wins by more than convenience — the corpus
exporter compiles the **real** `Melody` sources, so there is exactly one
implementation of "which degree was that note", and it's the one the plug-in
runs.

**The four things worth doing, in order:**

| Order | Item | Effort | What it returns |
|---|---|---|---|
| 1 | **T3's chord-mode authoring gate** | Trivial | `authorRow` is gated on `state.mode == .line` (`MelGenExtensionMainView.swift:1179`), so a comping template can't be asked for at all — while the measured ceiling says chord mode has **eight slots free**. The cheapest real variety on the list, and it needs no corpus |
| 2 | **S6 step 2b — give the baseline its floors** | S | Nothing downstream means anything until this lands. As measured, `MelodyChain`'s held-out perplexity is *worse than uniform* and moves 15× on a `--smoothing` default nobody chose. Until the bar is best-of-three (chain, unigram, uniform), "beats the baseline" is a sentence a model that learned nothing can satisfy. While here: `verify.sh midi` prints SKIP and returns OK when `mido` is absent, so its 19 checks are conditional on a machine nobody verifies |
| 3 | **Have the exporter write a history export** | S | The move the user's own reading of this found, and the exporter is already 90% of the way: it builds `GenerationRecord`s on its way to tokens, and `MelGenState.importHistory` plus a file picker have shipped since 2026-08-24. Emitting the export format alongside `corpus.jsonl` puts a found MIDI collection in front of `MelodyChain` and `MelodyStyleModel` **with no new Swift at all** — no SMF parser, no in-app reader, no tensor. Then measure whether the chain actually gets better, which is the question TRAINING.md left open |
| 4 | **S4, reframed: a style is a file** | M | The one item this review changes the meaning of. `MelodyStyleModel` and `MelodyChain` are already `Codable` and already round-trip through JSON — so "a style file the CLI produces and MelGen loads" is *storage and a name*, not a format problem. That makes S4 the interchange point the whole corpus route needs, rather than the caching optimisation it's written as |

**And that reframing is what settles the Core ML question.** A style can be
either of two things through the same slot: distributions fitted on a desktop
over a corpus too big for an iPad, written out as the JSON the plug-in already
decodes — or, later, a trained model behind `MLModel`. The first needs no Core
ML, no conversion, no per-OS maintenance and no download; it is S4 plus a flag
on the exporter. The second only becomes necessary where the first genuinely
can't reach, and [COREML.md](COREML.md) §3 already names that place precisely:
**harmony conditioning**. An n-gram can't afford chord quality in its context —
every context becomes one seen once, and `trustThreshold` correctly refuses it.
That, and nothing else, is what an LSTM buys.

So the honest ordering is: build the slot (4), fill it the cheap way (3), and
let S7 compete for the same slot on the evidence — which is exactly the gate S7
already writes for itself, now with a bar that can actually fail a model.

**What this de-prioritises**, and why it isn't a loss:

- **S2's in-app half and X4** stay open but stop being the training story. Their
  remaining value is *re-harmonization ergonomics* — drop a file carrying chords
  and get pattern plus harmonic context in one gesture (R1) — which is a real
  feature and a different one. Sized and judged as that, X4 is an L that buys an
  interaction, not a corpus.
- **X1/X2 (MIDI out, drag-out)** are untouched by any of this and remain the
  highest-value item outside the corpus family: nothing leaves the plug-in today
  except live MIDI, and that is the wall between MelGen and everything else on
  the iPad.

### Deliberately deferred

- **D1 finer grid (16ths/triplets)** — large, touches the schema and every seed
  example, and makes the context problem *worse*: more notes per bar is more
  response tokens. Revisit after G1, which is what buys the headroom.
- **Q1 AU parameters for generation settings** — good for automation, but these
  settings aren't yet ones worth automating.
- **T3 per-template weighting** — selection plus lock (T1/T2) probably covers it.
- **P5 dual output** — decide after P1; two instances may be the cleaner answer.

---

## Pending Fixes

| # | Issue | Effort | Status |
|---|-------|--------|--------|
| F10 | **Long progressions fail** — a 16-bar form errored out instead of generating | M–L | ✅ fixed 2026-08-22 via G1. Diagnosed by measurement: the window is **4,096 tokens total** (instructions + prompt + output), and the response dominates because guided generation emits one object per note — so the budget is bounded by note count, not bars. The 16-bar ProgGenie form at the densest setting needed ~4,516 tokens in one request; chunked into four 4-bar requests the worst chunk is ~1,615, or 39% of the window. The progression always *parsed* fine; only generation failed |
| F12 | **Sliders didn't share a track column** — each row sized its track between its own captions, so equal values sat at different x (Gate 0.50 and Expression 0.50 thumbs 15pt apart) | Trivial | ✅ fixed 2026-08-22 — fixed-width captions (`MelGenMetrics.sliderCaptionWidth`) |
| F13 | **Header clipped against the top edge when dragged** — a page that fits still bounce-scrolled, cutting the appearance buttons in half | Trivial | ✅ fixed 2026-08-22 — `.scrollBounceBehavior(.basedOnSize)` |
| F14 | **Status message sat ~700pt from the button that produced it** — the only feedback Generate gives, and easy to miss entirely | Trivial | ✅ fixed 2026-08-22 — moved directly under the progression row |
| F15 | **"Still downloading" is a lie in the Simulator** — Foundation Models reports `.modelNotReady` there and never becomes ready | Trivial | ✅ fixed 2026-08-22 — `targetEnvironment(simulator)` branch says so plainly |
| F16 | **Host app title read "aumi MlGn Enke"** — three four-character codes run together | Trivial | ✅ fixed 2026-08-22 — separated with `·` |
| F17 | **Host app uses a deprecated AU accessor** | Trivial | Open — `AudioUnitHostModel.swift:108` uses `auAudioUnit`, deprecated in iOS 27 in favour of `withAUAudioUnit`. Template code, host app only, doesn't affect the plug-in |
| F18 | **Density asked for more notes than the bar has slots** — so rests were impossible no matter what the prompt said | Trivial | ✅ fixed 2026-08-22. A 4/4 bar has 8 eighth slots; the mapping ran 3→14 notes/bar, so the *default* of 0.5 asked for 8 (every slot) and anything above it asked for the impossible. Now 2→8, default 5. This, not the rest logic, is why G2 wasn't audible |
| F19 | **A take's notation showed neither rests nor note lengths** — "note@beat" pairs made a line with rests look identical to one without | S | ✅ fixed 2026-08-22 — `MelodyNotation` renders a bar-per-row grid, one column per eighth, with a symbol for a rest and one for a sustained note, plus a summary line carrying the rest count and the actual gate range |
| F12b | **A third-party model extension breaks generation** | — | ✅ **understood 2026-08-23, and the first diagnosis of it was wrong.** `SensitiveContentAnalysisML` error 15 was read as "the safety model's assets are missing" — an explanation taken from a search result and stated on a device that had been generating for several builds. Assets don't vanish. The actual cause was a third-party model extension enabled under Settings ▸ Apple Intelligence & Siri, redirecting requests away from the on-device model; disabling it restored generation. **The lesson is the useful part**: the plug-in already recorded the source of every take, so "has the model ever worked here" was a fact available to the diagnosis and wasn't used. It is now (`MelGenState.modelHasWorkedHere`), and the verdict branches on it. A diagnosis that contradicts the evidence is wrong however plausible it sounds. |
| F11 | **Generation errors are all reported the same way** | S | ✅ fixed 2026-08-23, after a device session where the model failed with `SensitiveContentAnalysisML error 15` and the interface said "Generation failed: the operation couldn't be completed". That error is Apple's content scanner falling over *underneath* the model — not a refusal and nothing to do with the progression, which is the opposite of what the message implied. Failures are now told apart, transient ones retry once quietly, and if it still fails a phrase is composed instead |
| F1 | **Slider end labels read as belonging to the next control** — they sat under the track, directly above the next row's name and value | Trivial | ✅ fixed 2026-08-22 — labels now flank the track inline (`LabelledSlider`) |
| F2 | **Gate length looked like a discrete control** — five text buckets on a continuous slider | Trivial | ✅ fixed 2026-08-22 — continuous 2-decimal read-out; genuinely discrete settings use `ChipPicker` instead |
| F3 | **Note duration and gate length were conflated** under one "Note length" control | S | ✅ fixed 2026-08-22 — "Note duration" (written rhythm, generation-time) vs "Gate length" (staccato–legato, live) |
| F4 | **Layout unverified on device** — Xcode can't host previews in a `com.apple.AudioUnit-UI` extension | S | ✅ checked in AUM 2026-08-22 at three window widths. Light theme, inline slider labels and collapsible groups all hold up; the two problems found became F8 and F9 |
| F8 | **Component identity collision** — loading **Progression Studio** in AUM launched MelGen | S | ✅ fixed 2026-08-22 — the Xcode template's default subtype was `Prst`, which is Progression Studio's `PLUGIN_CODE`. An AUv3 is identified by the (type, subtype, manufacturer) triple, so two components sharing one means the host resolves either name to whichever it indexed. MelGen is now `MlGn`; `Scripts/verify.sh identity` fails the build if the triple ever collides again or drifts from the host app's lookup |
| F9 | **Direction buttons stretched to fill** — a small arrow centred in a 400pt-wide button in a wide plug-in window | Trivial | ✅ fixed 2026-08-22 — direction group capped at 240pt, loop-count chips at 320pt |
| F5 | **Ping-pong repeats the pivot note** at each turnaround | S | Open — deliberate for now: shortening the reversed pass would break bar alignment. Revisit if it grates |
| F6 | **Auto-regeneration swaps mid-loop** — a take committed the moment the model returned | M | ✅ fixed 2026-08-22 via G6 — finished takes are held for the next loop boundary. No extra kernel buffer needed after all |
| F7 | **UI mirror can go stale** if the host restores session state while the editor is open | S | Open — refreshes on next `onAppear`; a state-generation counter on the audio unit would close it properly |

---

## Roadmap: This Plug-in

### Generation: Limits & Quality

The Wave 1 items. All of these came out of playing the plug-in rather than
reading the code.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| G1 | **Chunked generation** | M–L | ✅ done 2026-08-22. `MelodyChunker` splits a progression into 4-bar requests at bar lines, rebased to beat 0 so eighth indices stay small; a chord straddling a boundary appears in each chunk it sounds in, clipped. Each chunk gets a **fresh session** (Apple's guidance for data that won't fit) and is told the note the previous phrase ended on, so registers don't jump at the seams. Post-processing runs over the *assembled* line, not per chunk, because `fold` and `snap` work from the previous note — that's what makes the seams disappear. Kept free of any FoundationModels dependency so `Scripts/verify.sh chunking` can test it. Still to do: progressive playback of finished chunks, and sizing chunks from `tokenCount(for:)` at runtime rather than a fixed 4 bars |
| G2 | **Rests** | S–M | ✅ done 2026-08-22. Three layers, because prompting alone had already failed: `restAfterEighths` is now a **schema field** (a value the schema doesn't ask for is a value the model doesn't consider); the instructions state rests as a requirement with a target rather than a preference; and `MelodyExpression.ensureBreathing` guarantees it — any two-bar window with no gap of half a beat or more loses its least structurally important note, reusing the ranking density thinning already uses. Honouring a requested rest never costs more than half the note, so "four eighths of silence after this eighth note" reads as "end the phrase", not "delete the note" |
| G3 | **Per-note gate** | M | ✅ done 2026-08-22. Gate is derived per note from the move to the next one — a step connects (0.95 of the slot), a wide leap detaches (0.65), a repeated pitch breaks (0.55) — and the slider became an *amount* over that shape: 0.5 as derived, 0 clips, 1 pushes toward legato. Same structure as Expression. Two rules that make it musical rather than mechanical: a gap of half a beat or more is a **rest** and legato won't extend into it, and a repeated pitch never fills its slot whatever the setting — without a gap the second note-on lands as the first note-off does and most synths render one held note. Expression no longer touches duration at all; Gate owns it |
| G4 | **Measure generation time** | S | ✅ done 2026-08-22, **and the numbers change the plan — see G8**. Measured on an M1 iPad Pro at 5 notes/bar: **11.5s for 6 notes** (3 bars, one request) and **138.3s for 57 notes** (16 bars, four requests). That's ~1.9–2.4s *per note*, scaling with note count rather than request count. At 120bpm a 16-bar loop lasts 32s, so generation runs roughly 4× slower than real time — "a new take every loop" is arithmetically impossible for anything the model writes from scratch. Each take records wall-clock seconds and how many requests it needed, shown in the history row and in the status line. The kernel now publishes tempo and loop length too, so the status can compare the two directly — "took 4.2s over 4 phrases, loop is 8.0s", or "longer than the 8.0s loop, so takes arrive late" when it doesn't fit. That comparison is the whole point: "new take every loop" is only a promise we can keep if generation finishes inside a loop |
| G5 | **Variety scoring** | M | ✅ done 2026-08-22. `MelodyAnalysis` measures every take and the number reaches the history row and the take summary; `TakeFacets` turns the same measurements into filterable bands. Reject-and-retry deliberately not built — Open Question 6 resolved as "annotate always, never reject", because an ostinato is sometimes exactly what's wanted and the machine shouldn't be the one deciding. Original note: takes come out ostinato-like even at temperature 0.89, so temperature is not the variety lever we assumed. Score a take before it reaches the history: pitch-class and interval-class entropy, rhythmic distinctness, and self-similarity across bars (an autocorrelation over the note sequence catches literal repetition). Two uses — reject-and-retry below a floor, and show the score in the history so curation has something to sort by. Cheap to compute, deterministic, testable, and it belongs in `verify.sh` with hand-picked repetitive and varied fixtures. Note this is *pre*-curation and distinct from L1's keep/discard: the machine filters, then the human chooses. |
| G6 | **Buffer takes ahead** | M | ✅ done 2026-08-22. Auto-regeneration now generates the *next* take while the current one plays and holds it until the pass counter ticks, so the swap lands on a loop boundary instead of wherever the model happened to finish. A take asked for by hand still commits immediately — you pressed the button. This also closes F6: the deferred commit was what that needed, without the third sequence buffer I'd assumed. Still open: if generation is slower than a loop the take simply arrives a loop late, which the status line now says out loud rather than hiding |
| G7 | **Accept ProgGenie output directly** | S | ✅ works 2026-08-22, given G1. ProgGenie's `Cmaj7 \| Em7♭5 \| A7 \| …` parses as-is — format, spacing and `♭` spelling all fine — and the 16-bar form now generates as four phrases. That progression is a fixture in `Scripts/verify.sh chunking` so it stays true. Open question is whether it should stay a paste or become a route (N4/X4) |

### Deterministic Lines

| # | Item | Effort | Notes |
|---|------|--------|-------|
| G8 | **Adapt stored lines to new harmony, without the model** | L | ✅ first cut done 2026-08-22. `MelodyPattern` describes a line in **scale degrees** rather than pitches, so the same rhythm and contour comes out consonant over any chord — degrees 0/2/4/6 of a seven-note scale are its chord tones, which is why landing on those on strong beats fits whatever the harmony turns out to be. `MelodyPatterns.realize` tiles a pattern across a progression, re-pitching every repetition against the chord under it, and folds each note into register the same way the model path does. Six seed lines ship (long tones, guide tones, arch, running eighths, syncopated, call and response). "Fit a stored line" is instant; Auto now fits a line on the first loop and on any loop where the model hasn't finished, so the changes keep moving instead of the same take repeating for half a minute. `Scripts/verify.sh patterns` checks all 24 line×progression combinations for scale membership, monophony, register, leap width, recurrence and determinism. Still to do: derive patterns *from* takes (R1), user-authored lines, and weighting rather than a plain cycle |
| G10 | **Generate from the learned distributions** | M | ✅ **done 2026-08-23**, twice over: `MelodyStyleModel` (slot statistics, ported from `@enkerli/accompaniment`) and `MelodyChain` (variable-order, with backoff). Both are offered, because they learn different things from the same takes — slots have groove and no memory, the chain has phrases and only the groove its metric context carries. Original note: `StyleLearner` already measures onset, duration and interval distributions over curated takes; sampling *from* them produces a line that is new, is yours, and is instant. Today a stored line is either a hand-written seed (generic on purpose, therefore plain) or a specific past take (specific, therefore not new); this is the missing third thing. Needs a chord-conditioned degree histogram, which `LearnedStyle` doesn't have yet. Measured evidence: two thirds of everything played in the first real session came from a stored line rather than the model, and 60 distinct lines sat behind 98 takes |
| G11 | **Mutate, score, morph** | L | ✅ **done 2026-08-23**. Fourteen transforms, each moving one axis so a variant that works can be traced to what made it work; three scores kept separate rather than summed; a morph that aligns notes proportionally rather than by onset. Original note: Deterministic transforms over a pattern (displacement, degree and duration substitution, density adjustment, inversion, retrograde, ornament insertion, register displacement), scored against the learned style, presented as variants to audition — then an interpolation between two you like, where "finding the satisfying point" means marking a position on the morph slider, which lands back in curation as a take whose provenance names both parents. Curation applied to variants rather than takes. Needs G10 first, so mutations can be scored against something |
| G9 | **Report the cost of a generation before running it** | S | With ~2s per note measured, expected duration is predictable from bars × notes-per-bar. Say so before starting — "about 40s for 16 bars at 5 notes/bar" — rather than leaving a spinner running for two minutes. Also lets Auto refuse a configuration it can't sustain instead of quietly falling behind. |

### Templates & Motifs

The nine style briefs in `StyleBriefs.swift` currently rotate blindly. They want
to become first-class, selectable things.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| T1 | **Select which templates are in play** | S | ✅ done 2026-08-22. Multi-select over the brief list (`FlowChips`), stored per session; an empty selection means all of them, so a session saved before this existed behaves as it did. The set can never be emptied — an empty rotation has nothing to play. |
| T2 | **Cycle vs randomize** | S | ✅ done 2026-08-22. Cycle, shuffle or lock, for briefs *and* stored lines. Shuffle is a shuffled cycle rather than independent draws: everything is heard once per round, and the join between rounds is checked so a round never opens with what the last one closed on — independent draws repeat immediately about once every N picks, which reads as a bug whatever the maths says. Deterministic in all three modes, so reopening a session doesn't jump the queue. |
| T3 | **Per-template weighting** | M | Once selection exists, weights let a set lean toward one feel. Probably a later refinement — selection plus lock may be enough in practice. |
| T4 | **User-authored templates** | M | A template is just a name plus prompt text. Letting people write their own turns the brief list into a user-extensible resource; needs an editor and validation that the text doesn't fight the schema. |
| T5 | **Templates as motif seeds, not just prose** | L | ✅ **done 2026-08-23** as gestures. A `MelodyGesture` is a rhythm crossed with a contour and a role in a phrase, which is exactly the "3-note cell, sequenced through the changes" this asked for — and the phrase grammar sequences it. Original note: Today a brief is an instruction. A stronger form seeds an actual figure — "use this 3-note cell, sequence it through the changes" — which overlaps with the pattern library (P-series) and re-harmonization (R-series). Design these together. |

### Rhythm & Duration

**On live mutation** (added 2026-08-23): there are now two mutation systems and
they are deliberately different. `MelodyMutation` produces a *new take to judge*,
which is the right shape for curation. `MelodyLiveMutation` re-rolls probabilities
every pass and never writes back, which is the right shape for playing — the
hardware-sequencer control, where you steer by how much it drifts rather than by
choosing between candidates. Conflating them would make one of the two useless.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| D1 | **Finer grid — 16ths and triplets** | L | **Now the binding constraint**, and everything that would have to change is in one place at last: the grid constant in `MelodyStyleModel`, the eighth arithmetic in the pattern format, and `GestureRhythm`'s lengths. Gestures bought back most of what triplets would with dotted and 3+3+2 figures, but a swung triplet feel is still unrepresentable. Original note: The model writes to an eighth-note grid (`startEighth`, `lengthEighths`), so triplets are currently *unrepresentable*. This is why the Note duration control offers no triplet option. Moving to a 24-per-bar grid (divisible by 8 and 3) covers both; touches `MelodyIdeaNote`, the prompt's grid explanation, `PatternLibrary`'s text format and every seed example. Do it before promising triplet feels. |
| D2 | **Duration patterns beyond pairs** | M | ✅ **done 2026-08-23**. The gesture vocabulary has 3+3+2, dotted figures, ties over the bar line, uneven pairs and pushed anticipations — twelve rhythms, none of which reads as another played at a different speed. Original note: Long–short and short–long are pair figures. Real rhythmic identity often lives in longer cells (3+3+2). Express as a selectable cell that the model is asked to repeat and vary. Related: T5. |
| D3 | **Per-note gate** | M | Promoted to Wave 1 as **G3** — playing it confirmed a single number can't give staccato notes with legato transitions. |
| D4 | **Feel presets** | L | Raised 2026-08-22, and probably the right answer to "I'm unclear on the gate variability". Accents, swing, gate shape, gate *variability* and micro-timing are five knobs describing one thing: a feel. Named feels (straight, swung, laid back, pushed, clipped funk, rubato) would bundle them, with the individual sliders demoted to an advanced disclosure — you pick a feel and adjust, rather than assembling one from five numbers. Needs: a per-feel curve for each axis, a variability amount per axis (currently the gate shape's spread is fixed), and micro-timing beyond the current uniform jitter — probably per-metric-position offsets, which is also what a groove template is. Shareable with the rest of the suite. Do it *after* U1: choosing between feels you can't see is guesswork |

| D5 | **Note duration as a distribution that moves** | M | Raised 2026-08-22, restated 2026-08-24 with the actual complaint: "the results are fine, it's more about having a way to change them with time". The four palettes pick a *character* (even, long–short, short–long, mixed) and the model interprets it once per take. What's wanted is the distribution of note values as a thing in its own right — how much of each value, and how that mix drifts across a take or across successive takes. That is closer to `LiveMutation`'s model (applied over time, seeded, re-renderable) than to a palette, and probably belongs alongside drift rather than in the generation section. Note that the eighth grid (D1) caps what a distribution can contain. |

### Polyphony & Comping

The single biggest addition, and a genuine fork in the plug-in's identity.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| P1 | **Mode: melodic line vs polyphonic comping** | L | ✅ **done 2026-08-23**, and the model path added the same day: it chooses when chords land and which tones are in them, `CompingVoicer` does register, spacing and voice leading. A model asked for MIDI notes jumps register between chords, because keeping voicings near each other is arithmetic. **Corrected the same evening**: the first version handed the model the comping *figure's* description and asked it to reproduce that, which is a language model doing at two seconds a request what a four-line function does exactly — and why every take came out alike. A figure is a pattern for the deterministic path; a brief is a character for the model. See `CompingBriefs`. and cheaper than expected: the kernel was already polyphonic and the realization axis already per-note. The one real change was teaching `MelodyExpression` that a comping take must skip the passes that reason about "the next note". Original note: These must be explicit and visible, because the *receiving instrument* differs: a mono synth given comping chords plays whichever note wins its note-priority rule, which is not music. The mode changes the schema (chords not notes), the post-processing (no monophonic truncation; voice-leading applies between chord voicings instead of between notes) and the kernel's active-note budget. |
| P2 | **Voicing model** | L | ✅ **done 2026-08-23**. `ChordVoicing.swift`: shell, rootless A and B, drop 2, quartal and close, with tones classified by interval rather than by position in the dictionary's list — which is what makes them right on suspended, quartal and altered chords. Original note: Comping needs voicings, not pitch sets: register, spacing, inversion, which chord tones are omitted, and whether the bass is included. The suite's chord dictionary provides the pitch classes; voicing is the missing layer and is a good candidate for shared theory code. |
| P3 | **Voice-leading between voicings** | L | ✅ **done 2026-08-23**. The voicing moves as a *unit*: re-placing each voice independently finds lower total movement and destroys the voicing doing it, because internal spacing is what makes a rootless A one. Original note: The melodic version folds octaves to keep a line singable. The comping version needs the analogous constraint between successive voicings — minimize total movement, keep common tones. |
| P4 | **Rhythmic comping figures** | M | ✅ **done 2026-08-23**, and the guess was right — a comping figure is a rhythm plus a voicing policy, and the rhythms are the melodic side's `GestureRhythm` vocabulary, so both modes share one sense of time. Original note: Charleston, bossa, stabs, pad. Overlaps with the template system (T-series): a comping template is a rhythm plus a voicing policy. |
| P5 | **Split or dual output** | M | Line and comping in one instance, on separate MIDI channels or separate output ports, so one MelGen can feed a mono lead and a poly pad. Decide after P1: two instances may be the cleaner answer. |

| P6 | **Taxicab voice leading** | M | ✅ **done 2026-08-24**. Ported from `music-suite/packages/theory/src/voiceLeading.ts` — Tymoczko's dynamic-programming algorithm over cyclic rotations — and held to the same `vectors/voice-leading.json` the TypeScript, Lua and C++ implementations must reproduce, so `verify.sh comping` fails if MelGen and the suite ever disagree. The voicing *style* still decides which notes are in the chord; the leading decides where they sit. Three modes, exposed: off, register (P3's whole-voicing octave shift, which keeps the style's spacing) and smooth (each voice to its nearest target tone). Measured over Dm7–G7–Cmaj7–A7♭13: 37 semitones of movement off, 22 register, 7 smooth. Lines lead too, but the problem there is different — there's one voice, so nothing can be held, and what there is instead is a seam: the first note under each chord reaches for a chord tone within a tone. Notes that are *deliberately* off the chord are exempt (a chromatic alteration, or anything whose recorded `HarmonicRole` was colour or off-scale), which the extraction round trip caught — without the exemption a real take replayed over its own changes came back with a different note. Original note: P3 moves a voicing as a unit, which stops independent re-placement wrecking it but doesn't *minimise* anything. |

### Learned Styles

The main reason to be on Foundation Models at all, and closest in spirit to the
suite's **GloriArp** concept. Distinct from templates: a template is authored
instruction, a style is *induced from material*.

**Read [TRAINING.md](TRAINING.md) before planning any of these.** It settles what
Foundation Models can actually do (no on-device training; adapters are an
offline, version-locked, 160 MB developer artifact) and stages what's reachable
without it. The headline: the next item in this family is not S1 or S2 but
*generating from the learned distributions*, which needs neither a model nor a
capture path.

Training **off** the device and running the result through Core ML is the other
half, settled separately in **[COREML.md](COREML.md)** — same corpus, same
tokens, but the burden of proof sits on the model, because `MelodyChain` already
does that job instantly, inspectably and with nothing to download.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| S1 | **Learn from incoming MIDI** | XL | ✅ **done 2026-08-23**, and it turned out to be S, not XL — because the learned models were built so that adding material is `add(pattern)` and nothing else. A lock-free ring in the kernel, pairing that survives overlapping note-ons, segmentation on silence, and quantizing that records how far off the grid it was rather than absorbing it. Captured phrases are read against the progression that was on screen, so they're reusable over other changes rather than being a recording. |
| S2 | **Learn from a loaded MIDI file** | L | ✅ **done 2026-08-25**, both halves. The desktop half landed 2026-08-24 (`Scripts/training/midi_to_events.py`). The in-app half is now `StandardMIDIFile` (a format-0/1 SMF codec, metrical division, running status, note pairing that survives overlapping voices) and `MIDIFileImport` (the harmony tiers). It answers the question the Python answers, plus one the Python doesn't: a file written by the suite carries its whole leadsheet as an `MCURATOR:v1 PROG` text meta event, so a MIDIcurator or ProgGenie file arrives with its changes intact and the line reads straight through to degrees. Behind that: chord-symbol markers, then a chord track through the new `ChordDetection`, then nothing — and a file with nothing still imports and says what it can't do. The sidecar tier is desktop-only on purpose: a document picker hands over one file, not a directory. |
| S3 | **Style extraction** | XL | ✅ first cut done 2026-08-22. `StyleLearner.learn` measures the curated takes into `LearnedStyle` — density, rest share, register, step/skip/leap shares, direction changes, duration and onset histograms, harmonic role balance, and the tags — and renders it as prompt text shown in the interface in the words the model receives. The compression claim holds: 620 characters for 24 takes, against several hundred tokens for *one* quoted take. Still to do: a degree histogram conditioned on the chord (which is what generating from the style needs), per-facet styles, and a floor below which the description should say "not yet" rather than a confident number over three takes. |
| S4 | **Named, saved styles** | M | Half done: `MelodyStyleModel` and `MelodyChain` are both `Codable` and round-trip through JSON (tested), and the slot model accumulates so a style can grow across sessions. What's missing is storage and a name — they're currently recomputed from the kept takes on every draw, which is correct and wasteful. Depends on where the library lives (I5). **Reframed 2026-08-25**: because both types already round-trip through JSON, this is also the *interchange* point for a style fitted on a desktop over a corpus too big for an iPad — and the same slot a Core ML model would later compete for. That makes it the enabling item of the corpus route rather than a caching optimisation. |
| S5 | **Style transfer onto an existing pattern** | L | Partly done and partly still interesting. `MelodyTransforms.applyRhythm` transfers a *rhythm* onto existing pitch material, and the morph interpolates between two lines. What's missing is transferring a learned style's distributions onto a pattern — redraw this line's durations and placement from that style, keep its contour. Now a small piece of work on top of `PatternProfile`. |
| S6 | **A corpus, and a number to beat** | M | ✅ written 2026-08-24 and **compiled and run the same day** on merge — it works, and the first run found that the number it produces isn't yet a bar: `MelodyChain`'s held-out perplexity came out *worse than uniform over the vocabulary*, and moves 15× on the `--smoothing` default. So the baseline needs two floors (unigram from the train split, and uniform) before any figure from it is acted on, and the bar is the best of the three. Measurements in [COREML.md](COREML.md) §4. `Scripts/export-corpus.sh` compiles the real Melody sources rather than reimplementing them, turns exported histories and a MIDI collection into degree-relative patterns, tokenizes them as `ChainToken` keys unchanged, and reports what `MelodyChain` scores on held-out material. It deduplicates *and splits by line*, because 60 distinct lines behind 98 takes is otherwise the classic way to measure a model on its own training data. The baseline is the deliverable: it's what any later model has to beat, and it's worth having whether or not one is ever trained. |
| S7 | **A trained model, converted to Core ML** | L | Gated on S6, and the gate is the item. `train_lstm.py` trains a next-token LSTM over the same tokens, conditioned on chord quality, root motion and where the harmony changes — which is exactly what the chain can't afford, since adding harmony to an n-gram context turns every context into one seen once and `trustThreshold` then correctly refuses it. `export_coreml.py` converts it statefully (`ct.StateType`, not hand-carried `h`/`c` — the target is iOS 27), with the vocabulary embedded in the `.mlpackage` so weights and token dictionary can't be separated by a file copy. The device side is deliberately unwritten: it needs a real `.mlpackage` to compile against, and it's a seventh `MaterialSource` returning a `MelodyPattern`, a sampler with a temperature and a seed, and nothing on the audio thread. **If the LSTM doesn't beat S6's baseline this item closes rather than continues** — that would mean more material, not more epochs, and `MelodyChain` stays the answer. Blocked on S6 being able to state a real bar: `train_lstm.py` compares against `chainNLL` alone, so as written it would declare a model that learned only the token frequencies "worth converting". |

| T3 | **Authoring in chord mode, and the template ceiling** | S | Raised 2026-08-25 and **measured**, which changed what the item is. Sweeping 3,240 characters across the four axes and greedily accepting the most distinctive one available until nothing clears the bar: **line mode saturates at 13 templates (9 built in, 4 authorable) and chord mode at 14 (6 built in, 8 authorable)**. The squeeze is double, because the bar rises as templates are added — 0.036 → 0.055 → 0.080 over four acceptances in line mode. And 4 is a best case: it assumes a searcher hunting the most distinctive point, where a language model proposing in prose finds far fewer, which is why one was accepted and everything after it refused. Two consequences. Line-mode authoring is nearly out and should stop being presented as a repeatable action. And **chord mode has eight slots free with no way to reach them** — `authorRow` is gated on `state.mode == .line`, so a comping template can't be asked for at all, though the gate would accept one. The second is the cheapest real win on the list. See [DESIGN_BRIEF.md](DESIGN_BRIEF.md) §4 for what this implies about where variety actually comes from. |
| P7 | **Harmonic rhythm** | M | Raised 2026-08-24. Every generated progression is one chord per bar, so a form has no rhythmic shape of its own. Wanted: bars with two chords, and bars with three as a half plus two quarters. The parser already accepts multiple chords in a bar and shares the beats equally, so the representation is there — what's missing is the *generator* choosing to use it, and a way to say how often. |
| P8 | **Time signatures** | L | Raised 2026-08-24: "not all progressions are 4/4". Currently four beats a bar is assumed in the parser's default, the chunker, the notation grid, the metric weighting in expression, and the kernel's bar arithmetic. Doing this properly means a time signature on the progression and threading it through all five; doing it by halves means a plug-in that's subtly wrong in 3/4. Sized accordingly. |
| P9 | **Shuffle tonalities** | S | Raised 2026-08-24. The walk produces numerals and resolves them in one key. Shuffling the key between generations — or between passes of the same form — costs a transpose and gives a corpus of progressions that isn't all in C. |

### Pattern Library & Information Architecture

Take history is already 80% of a library; it lacks the curation affordances that
would make it one.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| L1 | ~~**Keep / discard / rate**~~ → **Dispositions and passes** | S | ✅ done 2026-08-22, in a different shape than planned. Rating was the wrong model: "good for now", "affords tweaks", "worth another try", "right elsewhere", "the rhythm works and the rest doesn't", "second pass", "skip for now" are seven different *next actions*, not seven points on one axis. So marks are unranked dispositions, each one keystroke; every mark records the pass it was made on and the take it was heard after; a take keeps all its marks rather than the latest, so a take skipped on pass 1 and kept on pass 3 preserves the disagreement instead of resolving it. The ring now drops only what you skipped or never heard. See `MelodyCuration.swift`. |
| L2 | **Name and tag takes** | S | ✅ mostly done 2026-08-22. Free-text tags with a `TagVocabulary` that counts usage, orders the suggestions by it, and reports which tags have been used often enough to be worth making structural — the folksonomy-to-controlled-vocabulary ratchet. Facets (density, placement, register, colour, motion) are the other half: derived, fixed, read-only, and how you find something on purpose. **Loose end:** `GenerationRecord.title` and `MelGenState.retitle` exist and nothing in the interface calls them, so takes can't be named yet. |
| L3 | **Search and filter** | M | By progression, tag, brief, note count, density. Matters once the library outgrows one screen. |
| L4 | **Library vs session split** | M | History is per-session (in the host's saved state); a library should outlive sessions and be shared across instances. Two stores with an explicit "promote to library" action. Note the App Group question in the shared-infrastructure section. |
| L5 | **Curate incoming patterns too** | L | Not just generated material — captured MIDI, imported files. At which point this is a pattern manager that happens to generate, and overlaps MIDIcurator by design. Decide the boundary (see Open Questions). |
| L7 | **Promote a tag to a facet** | M | The ratchet the vocabulary is built for: a tag used often enough stops being free text and becomes something structural you can filter by. `TagVocabulary.promotable` identifies candidates; nothing acts on them. Open Question 7 is what "acts on them" should mean. |
| L8 | **Serendipity, done honestly** | M | A "surprise me" that isn't random: weighted away from what you've heard recently and toward facet combinations under-represented in what you kept, with the disagreement between passes used as signal. "Here's one you skipped twice that fits these changes" is a better surprise than a random pick, and the data for it already exists. |
| L9 | **Curation of variants, not just takes** | M | The mutate/morph loop (G11) produces candidates by the dozen. They need the same dispositions and the same passes, and their provenance names parents rather than a progression. Mostly a question of whether variants share the history ring or get their own. |
| L6 | **Pattern preview without committing** | M | Audition a library pattern without replacing what's loaded. Needs a second sequence slot in the kernel, or an audition path that bypasses the main one. |

| L6 | **Setups: keep a set of settings** | M | ✅ **done 2026-08-24**, and named "setup" for the reason below. `MelGenSetup` captures the two dozen fields that decide what comes next and *nothing else* — no take, no mark, no tag, no progression text — which is what makes recalling one safe rather than destructive: the fields simply aren't in the type. Stored in `UserDefaults` rather than the host's session, because "the way I usually work" isn't a property of one project, and one can be marked the default, which a *new* audio unit starts from while a host restoring `fullState` assigns over it. The two examples below are shipped as one offered setup, `MelGenSetup.suggested` — offered rather than installed, since a preset written in on first launch is a setting nobody chose. Original note: two real examples rather than a hypothetical. **Progression:** 4 bars, surprise 0.96, bold freshness and reharm, 2-chord context, no modulation. **Performance:** chord mode, shuffle through templates, 6 notes/bar, high temperature, mixed note durations, 5% note-order drift, ≥30% accents, ≥30% slides, ~8% skip, ~10% octaves. Both are *found* settings — arrived at by playing — and there is currently no way to keep either, so each session rebuilds them from defaults. That makes presets worth more than several unbuilt features: they're the difference between a session starting where the last one ended and starting from scratch. Naming matters here; these are closer to "setups" than to synth patches, since they span three sections. |

### Interchange: MIDI Files & Drag-and-Drop

| # | Item | Effort | Notes |
|---|------|--------|-------|
| X1 | **Export the current take as a MIDI file** | M | ✅ **done 2026-08-25**. `MIDIExport.write` — format 0, the notes as you hear them (post-expression), tempo, and the changes. Written in the same file as the reader on purpose: export and import are one feature, and writing them apart is how an interchange format rots. The `midifile` suite asserts the round trip note for note, including a repeated pitch, which is where a note-off ordering bug shows up as one long note instead of two. |
| X2 | **Drag-and-drop out** | M | Drag a take (or library row) straight into a DAW track. On iOS this is `NSItemProvider` with a file promise; the interaction is the point — it's how this stops being a closed box. |
| X3 | **Chord information in exported MIDI** | M | Half done 2026-08-25, and the half that landed is the one that makes the suite link work. An exported take carries per-chord **markers** (which any DAW displays) and the suite's own **`MCURATOR:v1 PROG` payload** — the format `packages/midi/leadsheet-smf.ts` writes — so MelGen ↔ MIDIcurator ↔ ProgGenie is a real round trip and MelGen can read its own exports back with harmony intact. Deliberately *not* written: a track of block chords. The suite's exporter includes one because its files are progressions; MelGen's are lines, and a second track of comping nobody asked to hear is a surprise in someone else's session. What's still open is the original item: the **Apple Loops** chord format MIDIcurator reverse-engineered, which is a different format for a different consumer (Logic and GarageBand) and needs that code extracted somewhere shareable. |
| X4 | **Import MIDI, with chords if present** | L | ✅ **done 2026-08-25** with S2 — they were always one piece of work seen from two sides. A file carrying chord information gives pattern *and* harmonic context in one drop, which is what re-harmonization (R1) wanted: the changes load into the field and the line joins the stored lines as degrees, so it plays over anything. Note the 2026-08-25 review's caveat still holds — this is an *interaction*, not the training story. The corpus route runs through the desktop exporter. |
| X5 | **Drag-and-drop in** | M | Drop a MIDI file onto the plug-in window to load it as a pattern or a style source. |

### Input Routing

Right now MelGen has one MIDI input, and it does nothing with it but pass events
through. Several planned features need *different kinds* of input — a progression
here, a melody to learn from there — which raises the question of how they arrive.

**What the format actually allows.** More promising than expected: an AUv3
identifies MIDI input by **virtual cable**. `AUAudioUnit.virtualMIDICableCount`
declares up to 256 cables of input, and every event MelGen already receives
carries the cable number — `AUMIDIEventList.cable`, "the virtual cable number",
which `handleMIDIEventList` currently ignores. On the output side multiple
streams are unambiguously supported (`midiOutputNames` is an array, and each
output is a complete MIDI stream).

So the instinct about frameworks is right: JUCE flattens MIDI input into a single
buffer with no cable distinction, so the JUCE-based siblings can't express this
even though the format can. MelGen is raw AUv3 and can at least try.

**The unknowns**, in order of risk: the `virtualMIDICableCount` documentation
describes it for "a music device or effect", and MelGen is a MIDI processor
(`aumi`) — so whether it's honoured for our type needs testing, not assuming.
Then whether AUM (or any host) offers per-cable routing in its MIDI matrix. Both
are cheap to answer experimentally and worth answering before designing around
cables.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| N1 | **Probe multi-cable input** | S | Declare `virtualMIDICableCount = 2`, log the `cable` field of incoming events, and see what AUM offers in its routing matrix. An afternoon that decides the whole design. Do this first. |
| N2 | **Channel-based routing** | S | The fallback that works in every host today: chords on one MIDI channel, melody input on another, configurable. Less elegant than cables, but nothing needs to support anything. Worth building regardless as the fallback path when a host offers one cable. |
| N3 | **Note-range split** | S | Second fallback: below a split point is harmonic input, above it is melodic. Familiar from arpeggiators and hardware; no configuration for the person to get wrong. Weaker than N2 because it spends register. |
| N4 | **Chords in as harmonic context** | L | Play or route chords in and have them become the progression, instead of typing leadsheet text. Needs chord *detection* from simultaneous notes — which is exactly what `chordDetect.ts` does in music-suite, and it's already fingerprint-based, so a Swift port is generated-table work rather than new theory. Pairs with X4 (a MIDI file carrying chords) as the two ways context arrives. |
| N5 | **Melody in as training material** | XL | ✅ **done 2026-08-23** via S1. Still open: it currently listens to everything on the one input, so N2's channel split is what would let chords and melody arrive at once. |
| N6 | **Trade fours** | XL → **L** | The latency wall is gone. The capture path exists (N5), and `MelodyChain` walks a response in microseconds from a model of what was just played — so the answer can be instant and still be *about* the call. What's left is bar-accurate switching against the host transport and a mode that alternates listening and answering. This is now the most interesting item on the roadmap and no longer the most expensive. |
| N8 | **Markov mutation of an input phrase** | L | Partly answered from the other direction 2026-08-23: `MelodyLiveMutation` is the *live* half — probabilities re-rolled every pass (note order, accents, slides, skipped steps, octaves), after Ruismaker's Troublemaker, applied at render time so the take is never touched and seeded by (take, pass) so a good pass can be got back. What's still N8's own is mutating an *incoming* phrase rather than the loaded one, which needs the capture path pointed at a live buffer rather than at a review queue. Original note: Raised 2026-08-22, after Kai Aras's MIDIrack "Markov Mirror", which mutates incoming MIDI phrases rather than composing replies. That's the answer to N6's latency wall: mutation is deterministic and instant, so it can respond *this* bar. A hybrid looks right — mutate for the immediate answer, and let the model contribute new material in the background (same division of labour as G8). Worth studying what Markov Mirror actually does before designing: the interesting question is what the state is (interval? scale degree? interval plus metric position?) and how much it's allowed to drift before the answer stops relating to the call. |
| N7 | **Multiple MIDI outputs** | M | Cheap and well-supported — `midiOutputNames` already takes an array. Would let the line and the comping (P5) leave on separate ports rather than separate channels. |

### Re-harmonization

| # | Item | Effort | Notes |
|---|------|--------|-------|
| R1 | **Apply an existing pattern to a new progression** | L | ✅ **done 2026-08-22**. `MelodyPatterns.realize` fits a pattern to any progression; `extract` supplies the input R1 was missing. "Keep as a line" on a take does both, so the loop is closed end to end |
| R2 | **Degree-relative pattern representation** | M | ✅ **done 2026-08-22**. `MelodyPatterns.extract` inverts `realize` from the same interval table, which is what makes the round trip hold — checked by replaying rather than by comparing degree numbers, since a flattened seventh and a natural sixth can be the same pitch and reading one as the other is correct rather than a loss. The off-scale decision went the way the note predicted it might not: nothing is snapped. An off-scale note is stored as its nearest degree plus an `alteration`, and the `HarmonicRole` it had over its original harmony travels with it — a chromatic approach and a mis-snapped pitch are the same two numbers, and only the original harmony can tell them apart. Patterns also carry `PatternOrigin` (take, progression, brief, source), because a library without provenance is a pile of anonymous lines |
| R3 | **Fit report** | S | ✅ done 2026-08-22. `MelodyPatterns.fitReport` realizes a pattern over a progression and reports notes that fell outside the form, off-scale notes, landings on avoid notes, and whether the line tiles evenly. **Loose end:** computed and tested, not yet shown anywhere in the interface. |

### Interface

**Reviewed 2026-08-23, after the second device session.** The verdict was that
capability had outrun legibility: "harder to know what control does what". Three
causes, all fixed. Style briefs and comping figures did the same job from
opposite ends and had two rotations and two selection controls between them —
merged into one template list, with the mode choosing which half is in play.
"Slots" and "Chain" were named for their implementations — now "Groove" and
"Phrasing", which is what they give you. And generating a progression was three
screens below the field it fills in, under a heading that read as "edit
something" — now "New changes", directly under it.

The standing lesson: a new source of material is cheap, and a new *control* is
not. Six ways to make a take is only an improvement if the interface says what
each one is for.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| U1 | **Piano-roll display of the take** | L | ✅ **done 2026-08-23**. Chord regions behind the notes with each chord's scale shaded and its chord tones shaded harder, notes coloured by the same `MelodyAnalyser.role` that scores takes, velocity as a cap on the bar. Shows what the text grid can't: gate length below an eighth, and two voices at once. The grid stays behind a disclosure — it survives being copied into a note. Original note: The take summary is a text list of note names, so density, gate and contour have to be *understood* rather than seen — and gate length in particular is invisible as text. MIDIcurator and other parts of the suite already have a piano-roll idiom; reuse its visual language (and ideally its geometry code) rather than inventing a third one. Should show the chord regions behind the notes, since that's what makes a wrong note legible. Overlaps U2: the same view is where a playhead belongs. |
| U2 | **Playhead position in the UI** | M | The kernel already publishes a loop-pass counter; a within-loop phase readout would let the UI show where playback is, and make the auto-regeneration boundary visible. |
| U3 | **Chord progression editor beyond a text field** | L | Typing leadsheet text is fast for people who know the notation and opaque for everyone else. Chord chips with a picker, backed by the shared chord dictionary. |
| U4 | **Dynamic Type support** | M | Fonts are fixed point sizes. Should scale with the accessibility text size; the 44pt control heights already give room to grow. Audit with the Dynamic Type nutrition label. |
| U5 | **VoiceOver pass** | S | Labels and traits are in place on every control; needs an actual pass with VoiceOver on, particularly the slider values and history rows. |
| U7 | **App icon** | M | ✅ **done 2026-08-25**. `MelGen/MelGen.icon`, an Icon Composer document, drawn from the design pass: a voicing stacked at one x in ink, a line stepping up and to the right in short–long–short in the breath blue, both on the roll's eighth-note grid inside the 112pt inset. Two layer groups rather than six layers, so one specular runs across each gesture. Every fill carries a `dark` specialization in the plug-in's own dark tokens (`#e8e1d2` ink, `#6da3df` accent, `#1a1814` ground) — without those the system keeps the light fill and the ink stack disappears into the dark ground, which is what the `icon` verify suite now guards along with the geometry. `AppIcon.appiconset` is gone and `ASSETCATALOG_COMPILER_APPICON_NAME` names the icon; `actool` compiles it into `Assets.car` with `CFBundleIconName`. Renders checked at 512 and at 32 in light, dark and mono via `ictool --export-preview`. |
| U6 | **Reduce Motion / reduced transparency** | Trivial | No animation to speak of yet; check before adding any. |

| U8 | **Name the two control groups by when they take effect** | S | Raised 2026-08-24, and it's a naming problem the redesign got backwards. The first group (density, temperature, note duration) affects **the next take**; the second **re-renders what's playing now**. "Texture" landed on the wrong one — it reads as a description of sound, which is the second group's job — and the second group is collapsed by default when it's the more performative of the two and wants to be the more prominent. Candidate framing: **Next take** and **Now**, or **Compose** and **Perform**. Drift is the awkward case: it's applied at render time, which puts it in the second group, but it's a thing you set and leave, which behaves like the first. Deciding that is deciding what the groups mean. |
| U9 | **Stored lines aren't reachable from the mode that plays them** | S | Raised 2026-08-24: in "Play a stored line" mode the stored lines don't appear among the templates, so there's no way to choose which one. `MelGenTemplates.all(for:)` returns `line + TemplateStore.templates` for line mode and `chords` for comping — stored lines are a third list that the template picker never shows. Either they become templates (they already have names and summaries) or the picker grows a section for them. The first is less machinery and matches "everything downstream works on templates". |
| U10 | **Rate the take that just went by** | S | ✅ **done 2026-08-25**. Both halves. The first landed earlier that day — "new take every 2 loops" now buys the time it promised, because the drift re-rolls on the same cadence, so two laps really are the same performance twice (see [ISSUES.md](ISSUES.md) §3). The second is the rating strip from the design pass's handoff: **Yes / Maybe / No** on the take that is sounding, shortcuts to three of the seven dispositions and nothing new in storage — `TakeRating.of` returns nil for the other four rather than bucketing them. Beside it, an advance the listener *aims*: **Another like this** takes a variant of what is playing, **Something else** moves the rotation on, and each carries a subtitle computed before the tap, because an advance that can't say what it will do is a shuffle. `TakeAdvance` is free of any FoundationModels import by construction, so an advance can never wait on a model running at 1.8 seconds a note; when the model is the source it runs alongside and swaps in on a lap boundary. Touch gets a swipe on the roll (right Yes, left No, up Maybe, long press for the seven) and macOS gets `y`/`m`/`n` plus ↓/→ — space stays unbound, because hosts own it. `Affords tweaks` and `Worth another try` now set the aim rather than only being recorded. New `advance` verify suite, 39 checks. |

### Platform & Quality

| # | Item | Effort | Notes |
|---|------|--------|-------|
| Q1 | **Expose generation settings as AU parameters** | M | Temperature, density and gate are session state, not parameters, so hosts can't automate them. Gate and expression are realization-time and would be genuinely useful automated; temperature and density affect generation and are stranger to automate. Decide per control. |
| Q2 | **macOS AU and standalone** | M | The code is cross-platform already; needs a real pass on window sizing, pointer vs touch control heights (`MelGenMetrics`) and the host matrix. |
| Q3 | **Signing configuration out of the project file** | S | `DEVELOPMENT_TEAM` is committed in `project.pbxproj`. The suite's CMake plug-ins keep signing in a gitignored local file; the Xcode equivalent is a `signing.local.xcconfig` (already gitignored). |
| Q4 | **MIDI 1.0 input pass-through** | S | `handleMIDIEventList` forwards incoming MIDI only when the host provides the UMP event-list block; `AURenderEventMIDI` (byte-based) input isn't handled at all. Generation is unaffected. |
| Q7 | **Host app activates the audio session on the main thread** | S | Two runtime warnings, `SimplePlayEngine.swift:143-144`. `stateChangeQueue.sync` runs its block on the *calling* thread, so `setCategory` and `setActive` land on main, which is what the warnings are about. Template code, **host app only** — the plug-in never touches an audio session. Deliberately not fixed blind: activation has to happen before the engine starts, and dispatching it asynchronously risks silent playback on first press in the only device-side test rig there is. Fix properly by setting the category once at init and moving activation to an explicitly ordered async step. The `RBSAssertionErrorDomain` "self-assertion invalidated, reason 4" entries in the log are RunningBoard reclaiming a transient process assertion, which is normal around audio-session activation and app-extension lifecycle — not an error to chase unless audio actually stops. |
| Q6 | **Simulator is a usable verification host** | — | Found 2026-08-22. The bundled `MelGen` app target *is* an AUv3 host (`ContentView` embeds the extension through `AUViewControllerUI`), and it works in the Simulator: AU discovery succeeds, validation passes, and the plug-in UI renders. Good for layout, theming, transport and state; **useless for generation**, since Foundation Models reports `.modelNotReady` in the Simulator and never becomes ready. Also note XCUITest **can't** reach the plug-in UI this way: the extension renders out-of-process and appears in the accessibility hierarchy as a `RemotePlaceholder` with `isRemoteLeafPlaceholder: true`, so automation has to use screenshot-estimated coordinates. VoiceOver on device is unaffected. |
| Q5 | **Test the generator's post-processing** | M | `verify.sh` covers the chord dictionary, state, expression and kernel. `MelodyGenerator.sequence` / `fold` / `snap` are untested — they need a fixture of synthetic model output, since the model itself isn't reproducible. |

---

## Shared Suite Infrastructure

Things MelGen needs that shouldn't live only in MelGen.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| I1 | **Chord voicing layer in `packages/theory`** | L | Built in MelGen 2026-08-23 (`ChordVoicing.swift`), written to be portable and depending on nothing but the chord dictionary. Extracting it to the suite is now a copy rather than a design. See P2. The dictionary gives pitch classes; voicing (register, spacing, omissions, inversions) is missing and every comping-capable app in the suite will want it. |
| I2 | **Chord-in-MIDI encode/decode, extracted** | M | See X3. Currently inside MIDIcurator. Wants to be a small shared library — ideally with the format documented, since it's reverse-engineered. |
| I3 | **Degree-relative pattern format** | M | ✅ **converged 2026-08-23**. MelGen's slot model uses `@enkerli/accompaniment`'s own `degree:alteration:category` key, with `HarmonicRole` where the suite says category, so the two projects mean the same thing by a degree histogram. `PatternNote` carries degree, octave, alteration and role. What's left is agreeing the serialization, which is now a small conversation rather than a design. |
| I6 | **Chord detection in Swift** | M | ✅ **done 2026-08-25**. `ChordDetection`, ported from MIDIcurator by way of the suite's `chordDetect.ts`: twelve rotations, a decimal fingerprint per rotation, exact match preferred and a subset match behind it, ties broken by fewer extra notes then simpler quality then lower root. Checked against `packages/theory/vectors/chord-detection.json` — the reference implementation's own vectors, so it is a cross-language check rather than a restatement of the port — on root and quality for all 15 cases and on the bass for all 3 inversions. Two deliberate differences, both about staying consistent with *this* app: symbols are spelled the way `ChordParser` writes them (so a detected chord re-parses, and so it doesn't disagree with every other chord name on screen), and ties break by dictionary index rather than by a stable sort, because Swift's `sorted` isn't stable and a non-total comparator here is the same bug that once made `MelodyVariants.explore` reorder between runs. Reachable from the interface as well as from an import: **Read the changes** under Listen fills the progression from what you played, which is the direction "Learn from it" couldn't go — it needed harmony already typed, and what you just played *was* the harmony. One implementation (`ChordDetection.changes`) behind both, and it says **inferred** whenever nothing sounded together, because a melody always spells something and naming it silently is how a line becomes a progression nobody played. |
| I7 | **Piano-roll rendering, shared** | L | See U1. MIDIcurator has the idiom; a shared geometry/visual-language description (even just documented conventions plus a Swift and a web implementation) stops the suite growing three different piano rolls. |
| I4 | **Swift port of the theory package, generated** | M | `ChordDictionary+Generated.swift` proves the pattern works. `chordScale.ts` was hand-ported and can drift — `verify.sh chords` catches it, but generating both would be better. Any other Swift app in the suite needs the same. |
| I5 | **Shared pattern store** | L | See L4. An App Group container so plug-in and host app (and eventually siblings) see one library. Decide before building the library UI, because it changes where everything is read from. |

---

## Sibling Projects

| # | Project | Effort | Notes |
|---|---------|--------|-------|
| B1 | **Progression generator** | XL | ✅ **done 2026-08-23** — **now a MelGen panel, not a sibling**, as Open Question 3 decided; kept in this table for its history. Extended 2026-08-24 work is P7–P9 below. Original: inside MelGen as Open Question 3 decided, and **extended the same day** after it was judged too generic: its own Adventurousness rather than borrowing the melodic temperature, and a substitution pass — tritone subs, secondary dominants that resolve into whatever follows, relative swaps, borrowed-mode chords, extensions. Applied after the walk rather than folded into it, so the numerals still say what the corpus proposed and the substitution says what was done to it. ProgGenie's corpus transition tables, generated from music-suite rather than transcribed, walked at order two with a blended backoff to order one. Every emitted label is checked against MelGen's own dictionary before it's used, because the corpus vocabulary is larger than the dictionary's. Original note: Generate the changes, not the line. Overlaps **ProgGenie** deliberately: same corpus of leadsheets, but the model conditioned on that corpus rather than pure transition weights — so it can be asked for "a bridge that gets back to the tonic" instead of only sampling a Markov chain. |
| B2 | **Comping instrument** | XL | If P1's mode switch makes MelGen incoherent, comping becomes its own plug-in sharing the theory, library and realization code. Decide after P1's design, not before. |
| B3 | **Pattern librarian** | L | If L5 wins (curating incoming material as well as generated), the library outgrows a plug-in panel and wants to be an app — at which point it is either a MIDIcurator feature or its replacement. |

---

## Open Questions

1. **Name.** "MelGen" is short for melody generation. Once it comps
   polyphonically (P1), the name describes half the product. Renaming is cheap
   now (bundle ID `com.enkerli.MelGenExtension` is the ABI-stable part; the repo
   and folder are cosmetic) and gets more expensive once hosts have saved
   sessions referencing the component. Worth deciding before P1 ships, not after.
2. **MelGen vs MIDIcurator boundary.** ~~Worth deciding before building library
   UI in both.~~ **Settled 2026-08-22: build it here anyway.** Curation is part
   of the loop this project is exploring — the model proposes, measurement scores
   (G5), a person keeps — and that loop doesn't work if curation lives in another
   app. Sharing the pattern format (I3) and the chord-in-MIDI format (I2) is
   still worth doing where it's cheap, but as convergence, not as a constraint on
   what gets built.
3. **Progression generation: integrated or separate?** **Leaning integrated,
   as of 2026-08-22.** "Generate progressions, adapt patterns to them, curate the
   results, all in one environment" is the thing worth exploring, and splitting it
   across plug-ins is what would prevent that. Separate would still need MelGen to
   *receive* a progression (X4), which is worth having regardless. So: build it
   here, and treat the routing path as a bonus rather than a prerequisite.
4. **How much realization should be live vs baked?** Gate, expression and swing
   re-render instantly today, which is a nice property. Per-note gate (D3) and
   groove templates (D4) keep that. Learned realization (S5) probably can't.
5. **Where do styles live?** A style learned from your playing is more valuable
   and more personal than a generated take. Session state is the wrong home for
   it. Depends on I5.
6. **Should variety scoring reject, or just annotate?** (G5) **Settled
   2026-08-22: annotate, never reject.** An ostinato is sometimes exactly what's
   wanted, and a take that's dull after one thing is the thing you needed after
   another — which is the same argument the curation model is built on. A machine
   that quietly withholds candidates makes that impossible to discover. The
   scores annotate, the facets make them filterable, and the human decides.
7. **How do tags become facets?** The vocabulary counts what you type and can
   say which tags you've reached for often enough to be worth making structural
   (`TagVocabulary.promotable`). Nothing acts on that yet. The question is
   whether promotion should be a suggestion the person accepts, a fully automatic
   thing, or the output of grouping the corpus by similarity and asking what the
   groups have in common — which is where topic modelling belongs, per
   [TRAINING.md](TRAINING.md) §5.
8. **Is context worth modelling further than "heard after"?** Every mark records
   the take it followed, because judgement is comparative whether or not we admit
   it. But context is also time of day, what you were doing, how long you'd been
   listening, and what you'd just rejected — and the honest version might be that
   only the *disagreement between passes* is recoverable signal. Worth looking at
   once there are enough passes to look at.
9. **Where does an audition sit?** L6 asks for previewing a library pattern
   without committing. Curation makes that sharper: a sweep is exactly a sequence
   of auditions, and doing it by loading each take into the kernel means the
   sweep is destructive to whatever was playing. The morph slider (G11) has the
   same need.
10. **What defines a chunk boundary?** (G1) Fixed four-bar blocks are simple and
   predictable. Phrase or chord-group boundaries respect the music but are
   variable-length, which complicates the token budgeting that motivated
   chunking in the first place. Fixed bars first, with the seam-carrying context
   doing the musical work.

---

## Effort Reference

| Label | Approximate time |
|-------|-----------------|
| Trivial | < 1 hour |
| S — Small | 1–4 hours |
| M — Medium | half day – 1 day |
| L — Large | 2–4 days |
| XL — Extra large | 1–2 weeks |
| Epic | months |

Estimates assume a single developer familiar with the codebase. The XL items
here (S1, S3, P1, B1) are XL because of design uncertainty rather than volume of
code — expect the first attempt to be a prototype that reveals the real design.

---

*See also: [README.md](README.md) for what exists today · `Scripts/verify.sh` for
what's verified · the suite handoff at
<https://github.com/Enkerli/music-suite/blob/main/HANDOFF.md>.*
