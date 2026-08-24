# Local training in MelGen — what's actually available

*Written 2026-08-22. Companion to [ROADMAP.md](ROADMAP.md); the S-series items
there are the roadmap entries this document is the reasoning behind.*

*The scope here is what can be learned **on** an iPad. Training off-device and
running the result through Core ML is [COREML.md](COREML.md) — a separate
question, and one a large MIDI collection reopened after this was written.*

The question, sharpened: **MelGen should learn from the material its user keeps.
What can actually do that on an iPad, and in what order should it be built?**

Short version. Foundation Models cannot be trained on device, and its adapter
path is a real but heavy option that only pays off at a corpus size this project
won't reach for a long time. Almost everything worth having is available from
transparent statistics over a small curated corpus — which is also the thing that
runs instantly, works offline, is inspectable, and can be tested in `verify.sh`.
The model's job stays what measurement already said it should be: contributing
new material in the background at two seconds a note, while deterministic
machinery plays.

---

## 1. What Foundation Models can and can't do

**No on-device training, of any kind.** The framework exposes inference: a
session, instructions, a prompt, guided generation. There is no fine-tuning API,
no gradient anything, no way for a shipped app to update weights on a user's
device. That isn't a limitation to work around; it's the shape of the product.

**Adapters exist, and they are trained off-device.** Apple ships an Adapter
Training Toolkit: a Python CLI, run on an Apple-silicon Mac (32 GB+) or a Linux
GPU box, producing a **rank-32 LoRA adapter** of roughly **160 MB**, delivered to
the app through Background Assets and loaded with `SystemLanguageModel(adapter:)`.

Three consequences matter here:

| | |
|---|---|
| **It's a developer artifact, not a user one** | An adapter is trained by whoever builds the app, from a corpus they hold, and shipped to everyone. It cannot be "your model, learned from your playing" unless every user has a Mac and a Python toolchain. That is the opposite of what this feature is for. |
| **It's version-locked** | Each adapter is compatible with **one** system model version. Apple updates the base model; the adapter must be retrained. That is a permanent maintenance tax on a project with one developer, and it is paid in full every OS cycle whether or not anything about MelGen changed. |
| **160 MB, for a melody** | The download is larger than everything else MelGen ships, several times over, to bias the phrasing of a monophonic line. |

**So: adapters are out for personal style, and premature for house style.** They
would make sense for one thing only — teaching the base model the *output format*
so reliably that guided generation gets cheaper and faster. That's a real prize
(generation is currently ~2s/note, and the response dominates the 4,096-token
window) but it needs a corpus of thousands of format-correct examples, which is
exactly what curation will eventually produce. Revisit when the library has
four-figure counts in it, not before.

**What's left with FM is conditioning**, and there are only two levers:
quotation (few-shot examples) and description (measured statistics as prose).
Both are implemented — see `MelodyStyle.swift` — and the budget argument between
them is the interesting part: a full 57-note take quoted costs several hundred
tokens of a 4,096-token window shared with the response, while a description of
sixty takes costs about a hundred and doesn't grow with the corpus. Measured:
620 characters for 24 takes.

---

## 2. So what should "local training" mean here?

Everything real is on the deterministic side. The staging below is deliberately
the same shape as the suite's GloriArp brief — transforms, then distributions,
then variable-order models, then retrieval, then anything opaque — because that
brief is right about the sequencing: **each stage is useful on its own, and each
one produces the evaluation apparatus the next one needs.**

The through-line: MelGen already has a symbolic, harmony-relative representation
(`PatternNote`: degree, octave, alteration, role) and can convert in both
directions between it and real takes. That representation is what makes all of
this arithmetic rather than machine learning. Nothing below needs a tensor.

### Stage 0 — describe what's kept ✅ *done*

`StyleLearner.learn` measures curated takes into distributions: density, rest
share, register, step/skip/leap shares, direction changes, duration and onset
histograms, chord-tone/colour/chromatic balance, plus the tags. Rendered as
prompt text and shown in the interface.

*What it buys:* the model writes more like your material, immediately, at ~100
tokens. *What it can't do:* it is advice, not control. The model may ignore it.

### Stage 1 — generate *from* the distributions

The same measurements, run backwards. Sample a line directly from the learned
onset, duration and degree distributions rather than describing them to a model:

- pick onsets from `onsetShares` until the bar hits the target density;
- pick a duration per onset from `durationShares` conditioned on the onset class;
- pick each degree from a chord-degree histogram, conditioned on the previous
  degree and on whether the beat is strong;
- honour the measured step/skip/leap mix as a rejection filter on candidates.

*Cost:* small — a day, in one file, testable end to end. *What it buys:* the
first line that is **yours** and **instant**. Right now a stored line is either
a hand-written seed (generic on purpose, therefore plain) or a specific past take
(specific, therefore not new). This produces new material with your statistics,
with no model and no wait. That is the biggest single gap in the current design.

*What it can't do:* nothing here has any memory beyond one note, so it produces
plausible texture and no phrases. Which is what Stage 2 is for.

### Stage 2 — a variable-order model over degrees

An n-gram over a state richer than pitch. The candidate state, in increasing
order of promise:

1. scale degree alone — too weak, produces wandering;
2. degree + metric position — knows that bar-line behaviour differs from
   mid-bar behaviour, which is most of what makes a line scan;
3. degree + metric position + phrase position (opening / middle / cadence) —
   knows that phrases end, which is the thing prompting has most struggled to
   get out of the model.

With backoff: try order 3, fall back to order 2, then to the Stage 1 marginals
when a context hasn't been seen. A personal corpus is small, so backoff isn't an
optimisation, it's the only way the thing produces anything at all.

*Cost:* medium — the model is a dictionary of counts and 200 lines of sampling.
*What it buys:* phrases rather than texture, and the "Markov mutation" answer to
trade-fours latency already noted as N8. *Risk:* over-fitting to a small corpus
produces literal quotation of your own takes, which is a musical problem, not a
statistical one. The fix is a temperature on the sampling and a self-similarity
check against the source material — and `MelodyAnalyser.selfSimilarity` already
exists to measure exactly that.

### Stage 3 — mutate, score, morph *(the one to build after Stage 1)*

This is the generation-and-analysis loop, and it is the most MelGen-shaped idea
in this document because it is curation applied to *variants* rather than to
takes.

Given a pattern, produce N mutations by composing the deterministic transforms:

| Transform | What it varies |
|---|---|
| Rhythmic displacement | Shift a phrase by an eighth |
| Degree substitution | Swap a degree for a neighbour, weighted by the learned degree histogram |
| Duration substitution | Redraw a note's length from the learned duration distribution |
| Density adjustment | Add or drop notes at the weakest metric positions (the ranking already used for thinning) |
| Contour inversion | Mirror the interval sequence around the phrase's first note |
| Retrograde of a cell | Reverse a two-bar cell, keeping the harmony fixed |
| Ornament insertion | Add a chromatic approach or an enclosure into a landing note |
| Register displacement | Move a phrase an octave and re-fold |

Score each mutation against the source and against the learned style —
`MelodyAnalysis` already gives variety and harmonic role counts; add a distance
between the mutation's distributions and the style's. Present the survivors as a
row of variants to audition.

Then the part the user actually asked for: **morph between two you like, and
find the satisfying point.** Two patterns in degree space can be interpolated
directly:

- *event-wise*, aligning notes by metric position and interpolating degree,
  duration and velocity — gives a continuous dial between two lines, with the
  caveat that patterns of different note counts need an alignment step (a
  Needleman–Wunsch over onsets, which is small and standard);
- *distribution-wise*, interpolating the two learned styles and re-sampling —
  gives lines "between" two styles rather than between two lines. Coarser, but
  it doesn't need alignment and it generalizes across lengths.

Build event-wise first: a slider between two lines you chose is a control you can
understand, and "identify satisfying points" then means *marking a position on
that slider* — which lands straight back in the curation model as a take with
provenance naming both parents and the mix. The morph slider is a generator of
candidates; the disposition marks are the fitness function; the pass structure
means the answer is allowed to change. That's a closed loop with a human in it,
and it needs no model at all.

*Cost:* large, but it's the payoff item. Do it after Stage 1 so mutations can be
scored against a style rather than against nothing.

### Stage 4 — retrieval and recombination

Once the library has enough in it that you can't remember what's there, the
question changes from "generate something" to "find the thing I already have that
fits *this*". The facets are already the retrieval index; what's missing is a
similarity over the feature vector, and a splice that only cuts at phrase
boundaries. Provenance tracking is already in `PatternOrigin`.

*What it buys:* the recommendation half of the library-science framing, and
serendipity done honestly — "here's one you skipped twice that fits these
changes" is a better surprise than a random pick, and it uses the disagreement
between passes as signal rather than noise.

### Stage 5 — topic modelling, honestly

The user's instinct is right that this is the family of technique that fits, and
it's worth being precise about what it would do here.

Topic modelling wants a term–document matrix. The documents are patterns or
takes. The terms have to be something a musical line has many of, with a heavy
tail: **degree bigrams** (`0→2`, `4→3`, `6→5`), **rhythm cells** (the sequence of
durations within a bar), or **onset patterns** (the bar's onset bitmask). Those
are real vocabularies with real Zipfian distributions, and factorising that
matrix gives latent components that are, plausibly, the things a musician would
call feels.

Two honest caveats:

- **Corpus size.** LDA on a few dozen documents produces confident nonsense.
  NMF on a term–document matrix of a few hundred short documents is more
  defensible, and simple co-occurrence clustering over bigrams is more defensible
  still. Start at the bottom of that ladder.
- **What it's *for*.** The interesting output isn't generation — it's
  **vocabulary**. A latent component that keeps grouping the same twelve patterns
  is a facet nobody has named yet, and the folksonomy already tracks which tags
  you reach for. The ratchet from tags to facets is the place topic modelling
  belongs: propose the grouping, let the human name it. That is a
  library-science use of the technique, not a generative one, and it's the one
  that pays at this corpus size.

### Stage 6 — an adapter, eventually, for the format

Covered above. The only defensible use is making guided generation cheap and
reliable, not making it personal. Preconditions: a four-figure corpus of
format-correct examples, and a decision to accept the retrain-per-OS tax.

An adapter is not the only off-device path, and it is the expensive one: it
retrains per OS release and weighs 160 MB to bias a monophonic line. A small
model trained on the same corpus and converted to Core ML has neither problem —
a couple of megabytes, no version lock, and it runs where the deterministic
machinery already runs. What it *does* have is the burden of proof, because
`MelodyChain` already does this job instantly and inspectably. That argument,
the pipeline, and the gate the model has to pass are in [COREML.md](COREML.md).

---

## 3. What the code needs that it doesn't have

In dependency order, and small enough to be real:

1. **A degree histogram conditioned on the chord**, in `LearnedStyle`. Present
   as roles (chord tone / colour / avoid / off-scale) but not yet as degrees,
   which is what Stage 1 samples from. Half a day.
2. **A style-distance function** — how far one take is from a learned style, as
   one number. Needed by Stage 3's scoring and by "is this take like my
   material?" in the interface. Reuses everything in `MelodyStyle.swift`.
3. **Transform primitives**, as pure functions over `MelodyPattern`, each
   independently testable. Stage 3 is nothing but compositions of these.
4. **An onset alignment** between two patterns, for the morph.
5. **A corpus that isn't in a plug-in.** Everything above is easier to develop
   against exported histories than against a device. The export already carries
   notes, settings, timings and analysis; what's missing is a script that reads a
   directory of them and reports distributions, so a change to the learner can be
   evaluated against real sessions rather than against fixtures.

Item 5 first, probably. It's the cheapest, and every other item is easier to
believe once its effect on real material can be seen.

---

## 3b. What the first corpus already says

`Scripts/analyse-history.sh` compiles the real Melody sources and reports over a
directory of exported histories, so what it prints is what the plug-in would
compute. Run over the nine exports from 2026-08-22 — 98 distinct takes, the first
real session — it says four things worth acting on:

**The library repeats itself, and now there's a number for it.** 60 distinct
lines behind 98 takes. The top five duplicates are all stored lines, each played
five to seven times over the same progression: the six seeds cycling. That is the
"not amazingly interesting" complaint, measured. Stage 1 is the fix, and this is
the measurement that will say whether it worked.

**Generation cost is confirmed and stable.** 33 model takes, 28 minutes of
wall-clock between them: median **1.82s per note**, range 1.25–2.86. The earlier
~2s/note estimate holds across briefs and progressions, so the four-times-slower-
than-real-time arithmetic isn't an artifact of one bad run.

**The material is very inside.** 89 of 98 takes have *no* off-scale note at all,
and the aggregate is 71% chord tones / 25% colour / 2% chromatic. Some of that is
`snap` doing its job. But it means a learned style built from this corpus will
teach the model to be *more* inside than it already is, which is the opposite of
what the takes need. Worth watching once real curation marks exist — and an
argument for the floor question below.

**Two thirds of what's played is a stored line, not a model take.** 65 of 98.
The deterministic path is already the main path, which is the strongest argument
in this document for investing in Stage 1 rather than in anything involving the
model.

---

## 4. Cost and order

| Stage | Effort | Needs | Payoff |
|---|---|---|---|
| 0 — describe | S | ✅ done | Model writes more like you |
| — offline corpus harness | S | exports | Every later stage becomes measurable |
| 1 — generate from distributions | M | degree histogram | **New lines that are yours, instantly** |
| 3 — mutate / score / morph | L | Stage 1, transforms | The loop the user described |
| 2 — variable-order model | L | Stage 1 | Phrases, and instant call-and-response (N8) |
| 4 — retrieval | M | a full library | Recommendation and honest serendipity |
| 5 — topic modelling | L | hundreds of patterns | Names for facets nobody named |
| 6 — adapter | XL | thousands of examples, a Mac, per-OS retraining | Cheaper guided generation |

The ordering claim: **Stage 1 before Stage 3 before Stage 2.** Stage 1 is the
smallest thing that makes the library stop being either generic or repetitive.
Stage 3 is where a human is in the loop, which is what this project is about.
Stage 2 is the most technically interesting and the least urgent, because a
Markov model with nothing to be scored against is just another generator.

---

## 5. Open questions

1. **Does the learned style actually change what the model writes?** Untested —
   it can only be tested on a device, by generating with and without it over the
   same changes and comparing the measurements. This is the first thing to check
   on the next device session, and the export makes it a real experiment rather
   than an impression.
2. **How much material before a style means anything?** Three kept takes produce
   a confident-looking description of very little. The interface currently shows
   it regardless. There is probably a floor below which the style should say "not
   yet" rather than a number — and finding that floor is an empirical question
   the corpus harness can answer.
3. **Should generated-from-style lines be marked as such?** They'd be a third
   `TakeSource` alongside `model` and `pattern`. Almost certainly yes: curating
   material the machine derived from your own curation is exactly the kind of
   feedback loop that needs to stay legible.
4. **Whose statistics?** A style learned across every progression you've played
   averages over genuinely different musical situations. Per-facet styles ("what
   I keep over minor changes") are more useful and need more material. The facets
   are already there to slice by.
