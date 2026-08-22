# MelGen — Feature Roadmap

*Last updated: 2026-08-22*

A consolidated inventory of planned work, backlog items and exploratory ideas.
Items are split between **this plug-in**, **shared suite infrastructure** (things
MelGen needs that belong in `music-suite` or a sibling), and **sibling projects**
that would share this codebase but have a distinct plug-in identity.

---

## Contents

1. [Where This Is Going](#where-this-is-going)
2. [Priorities](#priorities)
3. [Pending Fixes](#pending-fixes)
4. [Roadmap: This Plug-in](#roadmap-this-plug-in)
   - [Generation: Limits & Quality](#generation-limits--quality)
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
| G1 | Chunked generation (long progressions) | **Critical** | M–L | — | ✅ **done 2026-08-22** — 16 bars now generates as four phrases, and ProgGenie output works |
| G2 | Rests | **High** | S–M | — | ✅ **done 2026-08-22** — schema field, prompt requirement, and a guaranteed breath every two bars |
| G3 | Per-note gate | **High** | M | — | ✅ **done 2026-08-22** — derived per note from the next interval; the slider is now an amount over that shape |
| G5 | Variety scoring (pre-curation) | **High** | M | — | Ostinato-ish takes at high temperature mean temperature isn't the variety lever we assumed. Turns 24 takes-to-audition into 24 takes-worth-keeping |
| G4 | Measure generation time | Medium | S | — | ✅ **done 2026-08-22** — recorded per take, and compared against the actual loop duration |
| G6 | Buffer takes ahead | **High** | M | G1, G4 | ✅ **done 2026-08-22** — generates a loop ahead and swaps on the boundary |

**Wave 1 is complete apart from G5 (variety scoring)**, which is independent of
everything else and is the last thing standing between "24 takes to audition"
and "24 takes worth keeping".

After that, Wave 2 opens with **U1 (piano roll)**. Its case keeps getting
stronger: G2's rests, G3's gate shaping and D4's feels are all things you
currently have to take on trust, and the text grid only shows them to the nearest
eighth.

Worth a listen before G5, though — the density fix (F18) is the first change that
should be plainly audible, and if the line still doesn't breathe then the model is
ignoring the notes-per-bar target and `ensureBreathing` needs to do more of the
work than it currently does.

### Wave 2 — make it interactive

| # | Item | Impact | Effort | Depends on | Why |
|---|------|--------|--------|-----------|-----|
| U1 | Piano-roll display | **High** | L | — | Now the top of Wave 2. The text grid (F19) made rests and note lengths readable, but sub-eighth gate shaping still isn't visible, and D4 (feels) can't be chosen without seeing what it does |
| N1 | Probe multi-cable input | Medium | S | — | An afternoon that decides the shape of all input routing |
| T1/T2 | Template selection, cycle vs randomize | Medium | S | — | Cheap, and pairs with G5: choosing templates is manual variety control where scoring is automatic |
| X1/X2 | MIDI export and drag-out | **High** | M | — | Nothing leaves the plug-in today except live MIDI. Independent of everything else |
| N4 | Chords in as harmonic context | **High** | L | N1 or N2, I6 | The richer ProgGenie link, and how MelGen stops being a text box |

### Wave 3 — make it a library and an instrument

Pattern library curation (L1–L3), polyphonic comping (P1–P3), re-harmonization
(R1–R2, needing the degree-relative format), chord information in exported MIDI
(X3). Comping is the largest single addition and wants the voicing layer (I1)
under it.

### Wave 4 — research

Learned styles (S1–S5) and trade fours (N6). Both are XL because of design
uncertainty rather than volume of code, and both need the capture path. Worth
prototyping only once Wave 1 means a single take is reliably good.

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
| F11 | **Generation errors are all reported the same way** | S | Open — `exceededContextWindowSize`, `rateLimited` and `guardrailViolation` all surface as "Generation failed: …". The context one especially deserves "that progression is too long, try 8 bars" |
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
| G4 | **Measure generation time** | S | ✅ done 2026-08-22. Each take records wall-clock seconds and how many requests it needed, shown in the history row and in the status line. The kernel now publishes tempo and loop length too, so the status can compare the two directly — "took 4.2s over 4 phrases, loop is 8.0s", or "longer than the 8.0s loop, so takes arrive late" when it doesn't fit. That comparison is the whole point: "new take every loop" is only a promise we can keep if generation finishes inside a loop |
| G5 | **Variety scoring** | M | Takes come out ostinato-like even at temperature 0.89, so temperature is not the variety lever we assumed. Score a take before it reaches the history: pitch-class and interval-class entropy, rhythmic distinctness, and self-similarity across bars (an autocorrelation over the note sequence catches literal repetition). Two uses — reject-and-retry below a floor, and show the score in the history so curation has something to sort by. Cheap to compute, deterministic, testable, and it belongs in `verify.sh` with hand-picked repetitive and varied fixtures. Note this is *pre*-curation and distinct from L1's keep/discard: the machine filters, then the human chooses. |
| G6 | **Buffer takes ahead** | M | ✅ done 2026-08-22. Auto-regeneration now generates the *next* take while the current one plays and holds it until the pass counter ticks, so the swap lands on a loop boundary instead of wherever the model happened to finish. A take asked for by hand still commits immediately — you pressed the button. This also closes F6: the deferred commit was what that needed, without the third sequence buffer I'd assumed. Still open: if generation is slower than a loop the take simply arrives a loop late, which the status line now says out loud rather than hiding |
| G7 | **Accept ProgGenie output directly** | S | ✅ works 2026-08-22, given G1. ProgGenie's `Cmaj7 \| Em7♭5 \| A7 \| …` parses as-is — format, spacing and `♭` spelling all fine — and the 16-bar form now generates as four phrases. That progression is a fixture in `Scripts/verify.sh chunking` so it stays true. Open question is whether it should stay a paste or become a route (N4/X4) |

### Templates & Motifs

The nine style briefs in `StyleBriefs.swift` currently rotate blindly. They want
to become first-class, selectable things.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| T1 | **Select which templates are in play** | S | Multi-select over the brief list; the rotation draws only from the selected set. Default all-on preserves today's behaviour. Stored per session. |
| T2 | **Cycle vs randomize** | S | Cycle (deterministic rotation, today's behaviour) or shuffle without immediate repeats. A "lock" that repeats one template lets you iterate on a single idea at varying temperature. |
| T3 | **Per-template weighting** | M | Once selection exists, weights let a set lean toward one feel. Probably a later refinement — selection plus lock may be enough in practice. |
| T4 | **User-authored templates** | M | A template is just a name plus prompt text. Letting people write their own turns the brief list into a user-extensible resource; needs an editor and validation that the text doesn't fight the schema. |
| T5 | **Templates as motif seeds, not just prose** | L | Today a brief is an instruction. A stronger form seeds an actual figure — "use this 3-note cell, sequence it through the changes" — which overlaps with the pattern library (P-series) and re-harmonization (R-series). Design these together. |

### Rhythm & Duration

| # | Item | Effort | Notes |
|---|------|--------|-------|
| D1 | **Finer grid — 16ths and triplets** | L | The model writes to an eighth-note grid (`startEighth`, `lengthEighths`), so triplets are currently *unrepresentable*. This is why the Note duration control offers no triplet option. Moving to a 24-per-bar grid (divisible by 8 and 3) covers both; touches `MelodyIdeaNote`, the prompt's grid explanation, `PatternLibrary`'s text format and every seed example. Do it before promising triplet feels. |
| D2 | **Duration patterns beyond pairs** | M | Long–short and short–long are pair figures. Real rhythmic identity often lives in longer cells (3+3+2). Express as a selectable cell that the model is asked to repeat and vary. Related: T5. |
| D3 | **Per-note gate** | M | Promoted to Wave 1 as **G3** — playing it confirmed a single number can't give staccato notes with legato transitions. |
| D4 | **Feel presets** | L | Raised 2026-08-22, and probably the right answer to "I'm unclear on the gate variability". Accents, swing, gate shape, gate *variability* and micro-timing are five knobs describing one thing: a feel. Named feels (straight, swung, laid back, pushed, clipped funk, rubato) would bundle them, with the individual sliders demoted to an advanced disclosure — you pick a feel and adjust, rather than assembling one from five numbers. Needs: a per-feel curve for each axis, a variability amount per axis (currently the gate shape's spread is fixed), and micro-timing beyond the current uniform jitter — probably per-metric-position offsets, which is also what a groove template is. Shareable with the rest of the suite. Do it *after* U1: choosing between feels you can't see is guesswork |

### Polyphony & Comping

The single biggest addition, and a genuine fork in the plug-in's identity.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| P1 | **Mode: melodic line vs polyphonic comping** | L | These must be explicit and visible, because the *receiving instrument* differs: a mono synth given comping chords plays whichever note wins its note-priority rule, which is not music. The mode changes the schema (chords not notes), the post-processing (no monophonic truncation; voice-leading applies between chord voicings instead of between notes) and the kernel's active-note budget. |
| P2 | **Voicing model** | L | Comping needs voicings, not pitch sets: register, spacing, inversion, which chord tones are omitted, and whether the bass is included. The suite's chord dictionary provides the pitch classes; voicing is the missing layer and is a good candidate for shared theory code. |
| P3 | **Voice-leading between voicings** | L | The melodic version folds octaves to keep a line singable. The comping version needs the analogous constraint between successive voicings — minimize total movement, keep common tones. |
| P4 | **Rhythmic comping figures** | M | Charleston, bossa, stabs, pad. Overlaps with the template system (T-series): a comping template is a rhythm plus a voicing policy. |
| P5 | **Split or dual output** | M | Line and comping in one instance, on separate MIDI channels or separate output ports, so one MelGen can feed a mono lead and a poly pad. Decide after P1: two instances may be the cleaner answer. |

### Learned Styles

The main reason to be on Foundation Models at all, and closest in spirit to the
suite's **GloriArp** concept. Distinct from templates: a template is authored
instruction, a style is *induced from material*.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| S1 | **Learn from incoming MIDI** | XL | Capture MIDI input, segment it into patterns, describe them in the prompt's example format so the model imitates. Few-shot conditioning, not fine-tuning — which is what makes it feasible on device. `PatternLibrary` already does a primitive version with saved takes. |
| S2 | **Learn from a loaded MIDI file** | L | Same pipeline, file source instead of live input. Cheaper than S1 (no real-time capture) so probably do it first. |
| S3 | **Style extraction** | XL | Turn captured material into a *described* style — register, interval distribution, rhythmic vocabulary, syncopation, articulation — rather than raw examples. Compresses better and generalizes across progressions. This is the interesting research bit. |
| S4 | **Named, saved styles** | M | Once extracted, a style is a savable, shareable object. Needs the library IA (P-series) underneath it. |
| S5 | **Style transfer onto an existing pattern** | L | Apply a learned style to a pattern already in the library — the realization axis, learned rather than dialled in. |

### Pattern Library & Information Architecture

Take history is already 80% of a library; it lacks the curation affordances that
would make it one.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| L1 | **Keep / discard / rate** | S | The history is currently a flat 24-item ring that silently drops the oldest. Keeping a take should protect it from eviction. Minimum viable curation. |
| L2 | **Name and tag takes** | S | Free-text name plus tags. Settings are already recorded per take (temperature, density, brief, palette); tags add the human judgement that settings can't capture. |
| L3 | **Search and filter** | M | By progression, tag, brief, note count, density. Matters once the library outgrows one screen. |
| L4 | **Library vs session split** | M | History is per-session (in the host's saved state); a library should outlive sessions and be shared across instances. Two stores with an explicit "promote to library" action. Note the App Group question in the shared-infrastructure section. |
| L5 | **Curate incoming patterns too** | L | Not just generated material — captured MIDI, imported files. At which point this is a pattern manager that happens to generate, and overlaps MIDIcurator by design. Decide the boundary (see Open Questions). |
| L6 | **Pattern preview without committing** | M | Audition a library pattern without replacing what's loaded. Needs a second sequence slot in the kernel, or an audition path that bypasses the main one. |

### Interchange: MIDI Files & Drag-and-Drop

| # | Item | Effort | Notes |
|---|------|--------|-------|
| X1 | **Export the current take as a MIDI file** | M | Standard MIDI File type 0, rendered notes (post-expression), with tempo. The unglamorous baseline everything else builds on. |
| X2 | **Drag-and-drop out** | M | Drag a take (or library row) straight into a DAW track. On iOS this is `NSItemProvider` with a file promise; the interaction is the point — it's how this stops being a closed box. |
| X3 | **Chord information in exported MIDI** | M | MIDIcurator has already reverse-engineered the Apple Loops chord format and built a system for embedding chord information in MIDI files. Reuse it rather than reinventing: MelGen knows the progression exactly, so its exports can be *the* well-formed example of the format. Needs that code extracted somewhere shareable. |
| X4 | **Import MIDI, with chords if present** | L | The inverse. A file carrying chord information gives both pattern and harmonic context in one drop — which is exactly what re-harmonization (R1) needs. Pairs with S2. |
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
| N5 | **Melody in as training material** | XL | The input side of S1/S2: captured phrases become style examples. Distinct from N4 in what it does with the notes, which is why they want separate routes. |
| N6 | **Trade fours** | XL | The interactive payoff, and a genuinely different mode: MelGen listens for N bars, then answers for N bars, alternating with the player. Needs the capture path (N5), bar-accurate switching against the host transport (the kernel's host-sync window already gives the timeline), and a response conditioned on what was just played rather than on a static prompt. Also needs a latency answer: the model takes seconds, so the answer has to be generated *during* the player's phrase, which constrains how late the conditioning can be sampled. |
| N7 | **Multiple MIDI outputs** | M | Cheap and well-supported — `midiOutputNames` already takes an array. Would let the line and the comping (P5) leave on separate ports rather than separate channels. |

### Re-harmonization

| # | Item | Effort | Notes |
|---|------|--------|-------|
| R1 | **Apply an existing pattern to a new progression** | L | The payoff of separating pattern from harmony. A pattern's *contour and rhythm* are kept while its pitches are remapped to the new chord-scales — the machinery already exists in `MelodyGenerator.snap` and `fold`, but it needs to work from scale degrees rather than absolute pitches, which means storing patterns degree-relative (or deriving degrees on import). |
| R2 | **Degree-relative pattern representation** | M | Prerequisite for R1. A pattern note becomes (scale degree, octave offset, chromatic alteration) against whatever chord is sounding. Also makes patterns transposable and comparable, which helps L3 and S3. |
| R3 | **Fit report** | S | Some patterns don't survive re-harmonization — a pattern built on a ♯11 over a progression with no altered chords. Say so rather than silently mangling it. |

### Interface

| # | Item | Effort | Notes |
|---|------|--------|-------|
| U1 | **Piano-roll display of the take** | L | The take summary is a text list of note names, so density, gate and contour have to be *understood* rather than seen — and gate length in particular is invisible as text. MIDIcurator and other parts of the suite already have a piano-roll idiom; reuse its visual language (and ideally its geometry code) rather than inventing a third one. Should show the chord regions behind the notes, since that's what makes a wrong note legible. Overlaps U2: the same view is where a playhead belongs. |
| U2 | **Playhead position in the UI** | M | The kernel already publishes a loop-pass counter; a within-loop phase readout would let the UI show where playback is, and make the auto-regeneration boundary visible. |
| U3 | **Chord progression editor beyond a text field** | L | Typing leadsheet text is fast for people who know the notation and opaque for everyone else. Chord chips with a picker, backed by the shared chord dictionary. |
| U4 | **Dynamic Type support** | M | Fonts are fixed point sizes. Should scale with the accessibility text size; the 44pt control heights already give room to grow. Audit with the Dynamic Type nutrition label. |
| U5 | **VoiceOver pass** | S | Labels and traits are in place on every control; needs an actual pass with VoiceOver on, particularly the slider values and history rows. |
| U6 | **Reduce Motion / reduced transparency** | Trivial | No animation to speak of yet; check before adding any. |

### Platform & Quality

| # | Item | Effort | Notes |
|---|------|--------|-------|
| Q1 | **Expose generation settings as AU parameters** | M | Temperature, density and gate are session state, not parameters, so hosts can't automate them. Gate and expression are realization-time and would be genuinely useful automated; temperature and density affect generation and are stranger to automate. Decide per control. |
| Q2 | **macOS AU and standalone** | M | The code is cross-platform already; needs a real pass on window sizing, pointer vs touch control heights (`MelGenMetrics`) and the host matrix. |
| Q3 | **Signing configuration out of the project file** | S | `DEVELOPMENT_TEAM` is committed in `project.pbxproj`. The suite's CMake plug-ins keep signing in a gitignored local file; the Xcode equivalent is a `signing.local.xcconfig` (already gitignored). |
| Q4 | **MIDI 1.0 input pass-through** | S | `handleMIDIEventList` forwards incoming MIDI only when the host provides the UMP event-list block; `AURenderEventMIDI` (byte-based) input isn't handled at all. Generation is unaffected. |
| Q6 | **Simulator is a usable verification host** | — | Found 2026-08-22. The bundled `MelGen` app target *is* an AUv3 host (`ContentView` embeds the extension through `AUViewControllerUI`), and it works in the Simulator: AU discovery succeeds, validation passes, and the plug-in UI renders. Good for layout, theming, transport and state; **useless for generation**, since Foundation Models reports `.modelNotReady` in the Simulator and never becomes ready. Also note XCUITest **can't** reach the plug-in UI this way: the extension renders out-of-process and appears in the accessibility hierarchy as a `RemotePlaceholder` with `isRemoteLeafPlaceholder: true`, so automation has to use screenshot-estimated coordinates. VoiceOver on device is unaffected. |
| Q5 | **Test the generator's post-processing** | M | `verify.sh` covers the chord dictionary, state, expression and kernel. `MelodyGenerator.sequence` / `fold` / `snap` are untested — they need a fixture of synthetic model output, since the model itself isn't reproducible. |

---

## Shared Suite Infrastructure

Things MelGen needs that shouldn't live only in MelGen.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| I1 | **Chord voicing layer in `packages/theory`** | L | See P2. The dictionary gives pitch classes; voicing (register, spacing, omissions, inversions) is missing and every comping-capable app in the suite will want it. |
| I2 | **Chord-in-MIDI encode/decode, extracted** | M | See X3. Currently inside MIDIcurator. Wants to be a small shared library — ideally with the format documented, since it's reverse-engineered. |
| I3 | **Degree-relative pattern format** | M | See R2. If MelGen, MIDIcurator and GloriArp all describe patterns the same way, patterns move between them. This is the interchange format the suite doesn't have yet. |
| I6 | **Chord detection in Swift** | M | See N4. `chordDetect.ts` is fingerprint-based against the same dictionary, so this is generated-table work plus the rotation search — and `packages/theory/vectors/chord-detection.json` already exists as a test fixture. Any suite app that wants to read chords off a keyboard needs it. |
| I7 | **Piano-roll rendering, shared** | L | See U1. MIDIcurator has the idiom; a shared geometry/visual-language description (even just documented conventions plus a Swift and a web implementation) stops the suite growing three different piano rolls. |
| I4 | **Swift port of the theory package, generated** | M | `ChordDictionary+Generated.swift` proves the pattern works. `chordScale.ts` was hand-ported and can drift — `verify.sh chords` catches it, but generating both would be better. Any other Swift app in the suite needs the same. |
| I5 | **Shared pattern store** | L | See L4. An App Group container so plug-in and host app (and eventually siblings) see one library. Decide before building the library UI, because it changes where everything is read from. |

---

## Sibling Projects

| # | Project | Effort | Notes |
|---|---------|--------|-------|
| B1 | **Progression generator** | XL | Generate the changes, not the line. An alternative to **ProgGenie**: same corpus of leadsheets, but the model conditioned on that corpus rather than pure transition weights — so it can be asked for "a bridge that gets back to the tonic" instead of only sampling a Markov chain. Open question below is whether this is a separate plug-in or a MelGen panel. |
| B2 | **Comping instrument** | XL | If P1's mode switch makes MelGen incoherent, comping becomes its own plug-in sharing the theory, library and realization code. Decide after P1's design, not before. |
| B3 | **Pattern librarian** | L | If L5 wins (curating incoming material as well as generated), the library outgrows a plug-in panel and wants to be an app — at which point it is either a MIDIcurator feature or its replacement. |

---

## Open Questions

1. **Name.** "MelGen" is short for melody generation. Once it comps
   polyphonically (P1), the name describes half the product. Renaming is cheap
   now (bundle ID `com.enkerli.MelGenExtension` is the ABI-stable part; the repo
   and folder are cosmetic) and gets more expensive once hosts have saved
   sessions referencing the component. Worth deciding before P1 ships, not after.
2. **MelGen vs MIDIcurator boundary.** L5 and B3 drift toward being MIDIcurator.
   Cleanest split is probably: MelGen *generates and realizes*, MIDIcurator
   *curates and analyses*, and they share the pattern format (I3) and the
   chord-in-MIDI format (I2). Worth deciding explicitly before building library
   UI in both.
3. **Progression generation: integrated or separate?** Integrated means one
   window from changes to line, and a plug-in that does two jobs. Separate means
   two plug-ins and a routing problem — MelGen would need to *receive* a
   progression, which is a MIDI-with-chords problem (X4), which it wants solved
   anyway.
4. **How much realization should be live vs baked?** Gate, expression and swing
   re-render instantly today, which is a nice property. Per-note gate (D3) and
   groove templates (D4) keep that. Learned realization (S5) probably can't.
5. **Where do styles live?** A style learned from your playing is more valuable
   and more personal than a generated take. Session state is the wrong home for
   it. Depends on I5.
6. **Should variety scoring reject, or just annotate?** (G5) Auto-rejecting below
   a floor means never seeing a dull take, but it also means the machine quietly
   deciding what's dull — and an ostinato is sometimes exactly what's wanted.
   Annotating and sorting keeps the judgement human but doesn't save any
   auditioning. Probably: annotate always, reject only when auto-regeneration is
   running unattended.
7. **What defines a chunk boundary?** (G1) Fixed four-bar blocks are simple and
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
