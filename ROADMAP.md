# MelGen — Feature Roadmap

*Last updated: 2026-08-22*

A consolidated inventory of planned work, backlog items and exploratory ideas.
Items are split between **this plug-in**, **shared suite infrastructure** (things
MelGen needs that belong in `music-suite` or a sibling), and **sibling projects**
that would share this codebase but have a distinct plug-in identity.

---

## Contents

1. [Where This Is Going](#where-this-is-going)
2. [Pending Fixes](#pending-fixes)
3. [Roadmap: This Plug-in](#roadmap-this-plug-in)
   - [Templates & Motifs](#templates--motifs)
   - [Rhythm & Duration](#rhythm--duration)
   - [Polyphony & Comping](#polyphony--comping)
   - [Learned Styles](#learned-styles)
   - [Pattern Library & Information Architecture](#pattern-library--information-architecture)
   - [Interchange: MIDI Files & Drag-and-Drop](#interchange-midi-files--drag-and-drop)
   - [Re-harmonization](#re-harmonization)
   - [Interface](#interface)
   - [Platform & Quality](#platform--quality)
4. [Shared Suite Infrastructure](#shared-suite-infrastructure)
5. [Sibling Projects](#sibling-projects)
6. [Open Questions](#open-questions)
7. [Effort Reference](#effort-reference)

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

## Pending Fixes

| # | Issue | Effort | Status |
|---|-------|--------|--------|
| F1 | **Slider end labels read as belonging to the next control** — they sat under the track, directly above the next row's name and value | Trivial | ✅ fixed 2026-08-22 — labels now flank the track inline (`LabelledSlider`) |
| F2 | **Gate length looked like a discrete control** — five text buckets on a continuous slider | Trivial | ✅ fixed 2026-08-22 — continuous 2-decimal read-out; genuinely discrete settings use `ChipPicker` instead |
| F3 | **Note duration and gate length were conflated** under one "Note length" control | S | ✅ fixed 2026-08-22 — "Note duration" (written rhythm, generation-time) vs "Gate length" (staccato–legato, live) |
| F4 | **Layout unverified on device** — Xcode can't host previews in a `com.apple.AudioUnit-UI` extension, so nothing has been eyeballed at real plug-in window sizes | S | Open — needs a pass in AUM at a few window sizes; watch the transport row and chip pickers on iPhone widths |
| F5 | **Ping-pong repeats the pivot note** at each turnaround | S | Open — deliberate for now: shortening the reversed pass would break bar alignment. Revisit if it grates |
| F6 | **Auto-regeneration swaps mid-loop** — a take commits the moment the model returns | M | Open — needs a deferred commit that flips at the next loop point; the kernel's double buffer would need a third slot to stay allocation-free |
| F7 | **UI mirror can go stale** if the host restores session state while the editor is open | S | Open — refreshes on next `onAppear`; a state-generation counter on the audio unit would close it properly |

---

## Roadmap: This Plug-in

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
| D3 | **Per-note gate, not one global gate** | M | Gate is currently one number for the whole take. Accented notes wanting more length than passing notes is a realization decision that could be derived from metric weight, the way velocity accents already are. |
| D4 | **Groove templates** | M | Swing is a single number applied to offbeat eighths. A groove template (per-position timing and velocity offsets) generalizes it and would be shareable with the rest of the suite. |

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

### Re-harmonization

| # | Item | Effort | Notes |
|---|------|--------|-------|
| R1 | **Apply an existing pattern to a new progression** | L | The payoff of separating pattern from harmony. A pattern's *contour and rhythm* are kept while its pitches are remapped to the new chord-scales — the machinery already exists in `MelodyGenerator.snap` and `fold`, but it needs to work from scale degrees rather than absolute pitches, which means storing patterns degree-relative (or deriving degrees on import). |
| R2 | **Degree-relative pattern representation** | M | Prerequisite for R1. A pattern note becomes (scale degree, octave offset, chromatic alteration) against whatever chord is sounding. Also makes patterns transposable and comparable, which helps L3 and S3. |
| R3 | **Fit report** | S | Some patterns don't survive re-harmonization — a pattern built on a ♯11 over a progression with no altered chords. Say so rather than silently mangling it. |

### Interface

| # | Item | Effort | Notes |
|---|------|--------|-------|
| U1 | **Notation or piano-roll view of the take** | L | The take summary is a text list of note names. A minimal piano roll would make density, gate and contour legible at a glance — the controls currently have to be understood rather than seen. |
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
| Q5 | **Test the generator's post-processing** | M | `verify.sh` covers the chord dictionary, state, expression and kernel. `MelodyGenerator.sequence` / `fold` / `snap` are untested — they need a fixture of synthetic model output, since the model itself isn't reproducible. |

---

## Shared Suite Infrastructure

Things MelGen needs that shouldn't live only in MelGen.

| # | Item | Effort | Notes |
|---|------|--------|-------|
| I1 | **Chord voicing layer in `packages/theory`** | L | See P2. The dictionary gives pitch classes; voicing (register, spacing, omissions, inversions) is missing and every comping-capable app in the suite will want it. |
| I2 | **Chord-in-MIDI encode/decode, extracted** | M | See X3. Currently inside MIDIcurator. Wants to be a small shared library — ideally with the format documented, since it's reverse-engineered. |
| I3 | **Degree-relative pattern format** | M | See R2. If MelGen, MIDIcurator and GloriArp all describe patterns the same way, patterns move between them. This is the interchange format the suite doesn't have yet. |
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
