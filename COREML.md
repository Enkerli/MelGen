# Training off-device, playing on device

*Written 2026-08-24. Companion to [TRAINING.md](TRAINING.md), which is about what
can be learned **on** an iPad. This is the other half: what can be trained on a
desktop, and what it takes to run the result inside the plug-in.*

The question this answers: **a model trained on a Mac or a Linux box, converted
to Core ML, embedded in the AUv3 — what does that actually look like in this
codebase, and how would we know it was worth doing?**

---

## 1. Six corrections, before anything is built

Generic advice about neural music models assumes a project that doesn't look
like this one. Every item below is somewhere MelGen's existing design makes the
usual answer wrong, and each one is cheaper to notice now than after the
tokenizer is written.

**Don't tokenize raw MIDI.** The standard recipe — `Note_On_60`,
`Time_Shift_100ms`, a vocabulary of absolute pitches and wall-clock deltas — is
for projects whose only representation is a MIDI file. MelGen's material is
already symbolic and already harmony-relative: a `PatternNote` is a *scale
degree* of whatever chord is sounding, plus a length in eighths. Tokenizing
absolute pitch would throw away the single property the whole project is built
on — that a pattern is not bound to the progression it was played over — and it
would need the model to relearn transposition and chord-fitting that
`MelodyPatterns.realize` already does exactly, for free, in arithmetic.

**The token dictionary already exists, and it ships.** `ChainToken.key` in
`MelodyChain.swift` is `degree:alteration:lengthEighths:restAfterEighths` — pitch
and rhythm in one token, deliberately, because a chain over pitch alone learns
melody without rhythm. Adopting it as the training vocabulary means the neural
model is a *drop-in alternative* to the chain rather than a parallel universe:
same tokens, same grid, same realization path, and therefore directly comparable
on the same held-out split. Inventing a second token format would forfeit the
only honest way to find out whether the new model is any good.

**Nothing runs on the audio thread.** The usual advice — pre-allocate every
`MLMultiArray`, force `.cpuOnly` to dodge Neural Engine wake-up latency, build
`MIDIPacketList`s in the render block — is aimed at a plug-in that generates
note-by-note inside `internalRenderBlock`. MelGen doesn't have that shape and
never did. Every material source produces a whole `MelodyPattern` off the audio
thread; the kernel schedules already-decided notes. Generation ahead of the beat
isn't a feature to add, it's how the thing already works (ROADMAP G6 buffers a
loop ahead). So Core ML inference sits exactly where the Foundation Models call
sits today, with a budget of *one loop* rather than one buffer — and the audio
thread is not in the conversation at all.

**Use Core ML states, not hand-carried hidden states.** Threading `h` and `c`
through Swift as `MLMultiArray` inputs and outputs is the pre-iOS-18 shape.
MelGen's deployment target is **iOS 27**. `ct.StateType` keeps the recurrent
state inside Core ML, which removes the per-step marshalling *and* makes "start
a new line" a matter of asking for a fresh `MLState` rather than remembering to
zero two tensors.

**An AUv3 is memory-constrained, which is an argument for a small model.**
Audio Unit extensions run under a much tighter memory limit than an app, and
they get killed rather than warned. A one-layer LSTM over a few thousand tokens
is a couple of megabytes in fp16 and untroubled by this. It is also the reason
the MusicGen / Stable Audio family is not on the table: those are audio models,
they are hundreds of megabytes to gigabytes, and MelGen generates *symbolic*
material that the host's own instrument plays.

**The model is a seventh source, not a new subsystem.** From
[HANDOFF.md](HANDOFF.md): everything produces `MelodyPattern`s, so everything is
realized, curated, mutated and learned from by the same machinery. The LSTM is a
`MaterialSource` case that returns a pattern. It does not replace the template
fitter, does not sit between the fitter and the output, and does not need any
awareness of realization, expression or MIDI. Which answers the handoff question
directly: **it receives the chords, and it emits a pattern** — everything after
that is the path every other source already takes.

---

## 2. The architecture, in one picture

```
DESKTOP                                            iPad
────────────────────────────────────────────────   ──────────────────────────

 MIDI collection          exported take histories
        │                          │
        ▼                          │
 midi_to_events.py                 │              ┌───────────────────────┐
 (mido; file formats only)         │              │  progression on screen│
        │                          │              └───────────┬───────────┘
        │  events.jsonl            │                          │
        ▼                          ▼                          ▼
 ┌──────────────────────────────────────┐          ┌──────────────────────┐
 │  export-corpus.sh  (Swift)           │          │ MelGenLSTM.mlpackage │
 │  compiles the REAL Melody sources    │          │  · one step per call │
 │   · ChordDictionary → name chords    │──────────▶  · state in MLState  │
 │   · MelodyPatterns.extract → degrees │  vocab   │  · logits out        │
 │   · ChainToken → tokens              │  travels └──────────┬───────────┘
 │   · MelodyChain → the number to beat │  inside             │ sampled with
 └──────────────────┬───────────────────┘  the model          │ temperature
                    │                                         ▼
     corpus.jsonl · vocab.json · baseline.json         MelodyPattern
                    │                                         │
                    ▼                                         ▼
             train_lstm.py ─── beats baseline? ───▶  the same loop as every
                    │           no → stop                other source:
                    ▼                                  realize · hear · curate
             export_coreml.py                                 │
                                                              └──▶ learned from
```

The split between the two languages is the load-bearing decision, and it is not
about preference:

> **Python parses file formats. Swift decides what notes mean. There is exactly
> one implementation of "which degree was that note", and it is the one the
> plug-in runs.**

`MelodyPatternExtraction.swift` does something subtle that no reimplementation
would reproduce by accident: it *never snaps*. An off-scale note becomes its
nearest degree plus an alteration and keeps the role it had over its original
harmony, because a chromatic approach and a mis-snapped pitch are the same two
numbers and only the original harmony can tell them apart. A Python tokenizer
using `pretty_midi` and a scale lookup would quietly produce a second answer,
and the day the two disagree is the day the iPad plays something the training
data never said. So the corpus exporter compiles the real sources, exactly as
`Scripts/analyse-history.sh` already does for measurement.

---

## 3. The schema, pinned

### The token

`ChainToken.key`, unchanged from what ships:

```
degree : alteration : lengthEighths : restAfterEighths
```

| Field | Range | Why it's in the token |
|---|---|---|
| `degree` | 0-based scale degree, wraps by octave | The whole point: relative to the sounding chord, so a line fits any harmony |
| `alteration` | semitones off the scale, usually 0 | Chromatic approach notes survive; nothing is snapped |
| `lengthEighths` | ≥ 1 | Pitch and rhythm in one token, or the model learns melody without rhythm |
| `restAfterEighths` | 0–8 | Phrases end. This is the field that lets a line breathe |

Reserved indices `0 <pad>`, `1 <bos>`, `2 <eos>`; real tokens from 3, in
descending frequency so an index is stable and meaningful.

The grid is eighths, and that is a real ceiling — a swung triplet feel is
unrepresentable (ROADMAP D1). The model inherits the limitation rather than
introducing it, and the two places the grid lives are already known.

### The conditioning

This is where a neural model earns its keep, and it is the only argument for one
that survives contact with this codebase. `MelodyChain` conditions on the last
one or two events, the bar position, and the phrase position — and it *cannot
afford harmony*. Adding chord quality to an n-gram context multiplies the state
space by a hundred and turns every context into one seen exactly once, which the
chain's own trust threshold then correctly refuses to use. Backoff isn't an
optimisation there, it's the only reason anything is produced at all.

An LSTM conditions on all of it for the price of a wider input vector:

| Input | Size | Known when? |
|---|---|---|
| previous token | vocabulary | emitted |
| bar position | 8 | from the cursor |
| phrase position | 3 | from the cursor |
| chord quality | dictionary keys seen | **from the progression** |
| root motion to the next chord, folded to −6…5 | 12 | **from the progression** |
| eighths until the harmony changes | 0–16 | **from the progression** |

The asymmetry matters and is not a leak: at step *t* the model predicts the
token at *t* given the conditioning **of step *t* itself**. On device the
progression is already on screen, so the harmony and the metre of the slot about
to be filled are known before anything is generated. What isn't known is the
note. The cursor is causal too — it advances by the previous token's own span —
so nothing here requires seeing the future.

### The contract between the two sides

The vocabulary is written to `vocab.json` **and** embedded in the `.mlpackage`
as `melgen.tokens` metadata, with a SHA-256 digest checked at conversion time.
Weights paired with the wrong dictionary don't crash; they index the wrong notes
with total confidence, which is the worst failure this pipeline can have. So the
dictionary travels inside the model, and the Swift side refuses a model whose
`melgen.schemaVersion` it doesn't recognise.

---

## 4. The gate

`Scripts/export-corpus.sh` trains `MelodyChain` on the train split and reports
its held-out per-event loss, perplexity and top-1 accuracy. That is the number a
neural model has to beat, produced by the shipping model itself rather than by a
reimplementation of it.

If the LSTM doesn't beat it, the answer is **not** "train longer". It is that the
corpus doesn't support a neural model, and `MelodyChain` — instant, inspectable,
no download, no conversion step, no per-OS maintenance — stays the answer.
`train_lstm.py` prints that verdict rather than reporting its own loss in
isolation, because a loss curve with nothing to compare against is the easiest
way to talk yourself into shipping something worse.

Three things the split does on purpose:

- **Deduplicate by line.** The first exported session held 60 distinct lines
  behind 98 takes, and the duplicates were the six stored seeds cycling.
- **Split by line, not by take**, so the same line can't be on both sides. That
  is otherwise the classic way to measure a model on its own training data.
- **Hash stably** (FNV-1a, not `Hasher`, which is salted per process), so the
  split is the same split tomorrow and on another machine.

Two honest warnings the exporter prints:

- A vocabulary large against the corpus means most tokens are seen once or
  twice. That's a corpus problem no architecture fixes.
- Files with no harmony contribute nothing here. Every token is a degree, and a
  degree with no chord under it is a pitch with a story attached. They're
  counted and reported, never guessed at.

---

## 5. What the MIDI collection changes

[TRAINING.md](TRAINING.md) argued against anything with a tensor in it, and the
argument was mostly about corpus size: a personal library of a few dozen curated
takes produces confident nonsense from any model with real capacity, and the
failure mode isn't bad music but *your own material played back at you*, which
is worse because it looks like success.

A large MIDI collection changes that arithmetic and nothing else about the
reasoning. It does not make an LSTM better than the chain — the gate still
decides that — but it makes the question worth asking, which at four dozen takes
it wasn't.

It also means the front end is worth building **whether or not any neural model
ever ships**. `midi_to_events.py` is ROADMAP **S2**'s file reader ("the pipeline
exists; what's missing is only the file reader"), and reading a collection into
`MelodyCapture.learn(from:over:)` feeds the slot model and the chain — both of
which already ship — on day one. **X4** (import MIDI with chords if present) is
the same work seen from the plug-in side.

Where harmony comes from, in descending order of trust:

| Source | How | What it costs |
|---|---|---|
| `<stem>.chords` sidecar | leadsheet text a human wrote | nothing; it's the notation the parser already reads |
| marker / text meta events | positioned, mapped onto bars | a bar's chords share it equally, so uneven placement is flattened — and reported |
| a chord track | pitches named against `ChordDictionary` by best fit | block voicings are fine; an *arpeggiated* chord track will come out as a run of wrong triads |
| nothing | — | the file teaches rhythm and contour, neither of which this corpus can express |

---

## 6. The device side, when the gate is passed

Not written yet, deliberately: it needs a real `.mlpackage` to compile against,
and writing it before the gate is passed is building on an assumption. The shape
it should take, so it isn't rediscovered:

**One step per call, whole patterns per generation.** Ask for a fresh `MLState`,
walk the cursor across the form, and at each slot feed the last token plus the
conditioning read from the progression. Out comes a distribution; sample it;
advance the cursor by the token's span. Stop at `<eos>` or the end of the form.
The result is a `MelodyPattern`, and the rest of the app already knows what to do
with one.

**Sample, don't argmax.** Temperature and top-k belong in Swift, next to the
seed that makes a take reproducible — `MelodyChain.generate` already takes a
seed and a temperature, and its fixed-draw-before-the-search trick (so which
rung of the backoff ladder is used doesn't change the random stream) is the
convention to match. Greedy decoding produces the same line every time and is
the fastest way to make a model sound robotic.

**Compute units: measure, don't guess.** `.all` is the right default. The
folklore about forcing `.cpuOnly` is about audio-thread wake-up latency, which
this design doesn't have. If first-inference latency shows up at all it belongs
in the loop-ahead budget, and it is measurable the same way generation cost
already is (ROADMAP G4 records seconds per take, which is how "~1.8s a note" is
a measurement rather than an impression).

**A trap worth writing down.** `Scripts/verify.sh` compiles *every* file in
`MelGenExtension/Melody/` into every suite. A new source that imports Core ML
must be excluded in `melody_sources()` the way `MelodyGenerator.swift` is for
Foundation Models — otherwise all twenty-odd suites stop building at once, for a
reason whose error message won't mention Core ML.

**Where the model lives.** Bundled in the extension is the simple answer and the
right first one. A model the *user* trained is a different question — it wants
`MLModel.compileModel(at:)` at runtime and a container both the app and the
extension can see, which is the same App Group decision the library is already
waiting on (ROADMAP I5/L4). Don't solve it twice; solve it there.

---

## 7. Order of work

| # | Step | Effort | Gate |
|---|---|---|---|
| 1 | Read the MIDI collection into events | ✅ built, tested | `Scripts/verify.sh midi` |
| 2 | Corpus exporter: patterns, tokens, vocabulary, baseline | ✅ written, **never compiled** | first run on a Mac |
| 3 | Point it at the real collection; read what it prints | S | is there a corpus at all? |
| 4 | Feed the collection to the models that already ship | S | does the chain get better? **This is the cheapest win here** |
| 5 | Train the LSTM | M | does it beat the baseline? |
| 6 | Convert to Core ML | S | does the digest match? |
| 7 | The Swift runtime: sampler, cursor, seventh source | M | does it sound like anything? |

Step 4 is the one to be greedy about. It needs no tensor, no conversion and no
Xcode work — the collection becomes patterns, the patterns feed
`MelodyStyleModel` and `MelodyChain`, and both of those already play. If that
alone fixes the "not amazingly interesting" complaint that
[TRAINING.md](TRAINING.md) measured — 60 distinct lines behind 98 takes — then
steps 5–7 are a research project rather than a fix, and can be judged as one.

---

## 8. Open questions

1. **Does a found MIDI collection teach the right thing?** A corpus of other
   people's playing is not the same as a corpus of what *you kept*, and MelGen's
   whole curation model is built on the second. The likely answer is two models,
   or one model and a style-conditioned adapter — but the first honest step is
   measuring whether they're even different, which the corpus exporter can do by
   running the baseline over each separately.
2. **Is the eighth-note grid what makes the material sound quantized?** If a
   found collection is full of swing and the grid flattens it, the corpus will
   teach flatness convincingly. `StyleSlot` already records micro-timing
   deviation rather than absorbing it; nothing in the token format does.
3. **How much of the win, if there is one, is the harmony conditioning?**
   Trainable directly: the same model with the chord inputs zeroed. If that
   ablation barely moves, the LSTM isn't buying what this document claims it is,
   and the chain should be extended with a coarse chord bucket instead.
4. **What does a take generated this way get marked as?** The same question
   TRAINING.md asks about style-generated lines: it needs to be a distinct
   `TakeSource`, or the curation record stops being able to say where its own
   material came from.
