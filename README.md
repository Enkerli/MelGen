# MelGen

**MelGen** is an iOS/macOS AUv3 MIDI plug-in that composes melodic lines over a
chord progression using Apple's on-device Foundation Models, then loops them as
MIDI for whatever instrument you point it at. Type a leadsheet progression, hit
Generate, and the line plays back forwards, backwards or ping-pong, free-running
or locked to the host's playhead.

---

## Features

| Feature | Details |
|---|---|
| **On-device generation** | Foundation Models composes the line locally — no network, no account |
| **Leadsheet input** | `E♭7 Gm9\|D∆\|A♭6` — bars separated by `\|`, chords share a bar's beats |
| **Shared chord dictionary** | 172 qualities from the suite's chord dictionary, including slash chords, altered dominants and quartal voicings |
| **Chord-scale awareness** | Each chord's scale, colour notes and avoid notes are derived structurally and given to the model |
| **Transport** | Play/Stop, Forward / Backward / Ping-Pong, and host sync that follows the DAW's playhead, tempo map and locates |
| **Temperature** | 0–1 sampling control, from the safest line to the most adventurous |
| **Density** | Sparse to dense, targeted at generation time and thinned live (which is how rests appear) |
| **Note duration** | The written rhythm — even, long–short, short–long or mixed |
| **Gate length** | How much of each note's slot sounds: staccato through as-written to legato, applied live |
| **Expression & swing** | Metric accents, articulation, timing looseness, and swung eighths |
| **Templates** | Fifteen — nine line templates and six comping figures. The mode chooses which half is in play; select any subset and cycle, shuffle or lock it |
| **Auto-regeneration** | A new take every 1/2/4/8 loops, swapped in on a loop boundary |
| **Take history** | 250 unjudged takes, and 1000 including judged ones, logged with their template, settings and measurements; tap to reload one |
| **Curation** | One tap per take — keep, tweak, try again, right elsewhere, partly, later, skip — in passes, so the same take can be answered differently next time |
| **Facets and tags** | Density, placement, register, colour and motion are derived from measurement; tags are yours, and the vocabulary emerges from what you type |
| **Lines from takes** | Keep a take as a degree-relative line and it plays over any changes, instantly, with no model |
| **Learned style** | What you kept, measured — as prompt text, as slot statistics, and as a chain of what follows what |
| **Composed phrases** | Gestures with rhythmic identity, composed by a phrase grammar into lines that state, answer and land |
| **Interval cells** | Hanon's self-sequencing figures and Samchillian-style interval streams, described as moves rather than positions |
| **Variants and morphs** | Fourteen transforms, scored against your material, and a dial between two lines you like |
| **Listening** | Play something in and it becomes library material, read against the changes on screen |
| **Comping** | Voicings under the changes, voice-led, in six figures |
| **Progressions** | Generated here from corpus transition tables, rather than pasted in |
| **Session state** | Progression, settings and history are saved in the host's session |
| **Pattern library** | Save a take as a few-shot example that shapes later generations |
| **Two tabs** | **Play** makes material and performs it; **Decide** judges it and shows what's been learned |
| **Two modes** | **Line** writes a monophonic part, **Chords** comps under the changes. Explicit because the receiving instrument differs — a mono synth handed chords plays whichever note wins its note-priority rule |
| **Themes** | Light (default) and Dark, MelGen's own setting rather than the host's |

---

## Requirements

| Requirement | Version |
|---|---|
| Xcode | 26 or later — **27 to open the project file**, which is format 110 |
| iOS / macOS deployment target | 26.0+ |
| Apple Intelligence | Enabled, with a supported system language |

The plug-in is a **MIDI processor** AUv3 (`aumi` type). It produces MIDI output
only — no audio I/O — and advertises a MIDI output port, so hosts route it into
an instrument.

---

## Building

```bash
git clone https://github.com/Enkerli/MelGen.git
cd MelGen
open MelGen.xcodeproj
```

The **MelGen** scheme builds a standalone host app that loads the extension for
quick testing. The **MelGenExtension** scheme builds the app extension that
hosts deploy.

Set your own `DEVELOPMENT_TEAM` in the target's signing settings before building
to a device.

---

## Verifying

Xcode's test targets can't reach the DSP kernel (C++ inside the extension) or the
`Melody` sources (extension-only target membership), so those are checked outside
Xcode:

```bash
Scripts/verify.sh            # all suites
Scripts/verify.sh chords     # one suite
```

| Suite | Checks |
|---|---|
| `identity` | The audio component triple is unique across the suite and matches the host app's lookup |
| `chords` | Every chord symbol's quality, scale, tensions and avoid notes against Music Suite's TypeScript, plus a drift check on the generated dictionary |
| `chunking` | How a progression is split into model requests, so a 16-bar form fits the context window |
| `patterns` | Stored generic lines fitted to real harmony, with no model |
| `state` | Session-state round-trip, and the expression / density / note-length passes |
| `extraction` | Takes read back as degree-relative lines, round-tripped by replaying, plus the fit report |
| `curation` | Dispositions, passes, eviction, facets, the tag vocabulary, the rotation, and what gets learned |
| `phrases` | Gestures, the phrase grammar, and the lines it composes |
| `stylemodel` | Slot statistics over kept takes, and sampling new lines from them |
| `chain` | The variable-order model: what follows what, with backoff |
| `mutation` | Transforms, variant scoring, and the morph between two lines |
| `retrieval` | Finding a line rather than making one, and being surprised on purpose |
| `topics` | Grouping the library so the vocabulary can come from the material |
| `steps` | Interval cells: self-sequencing figures and interval streams |
| `capture` | Pairing, segmenting and quantizing what was played in |
| `comping` | The voicing layer, voice leading, and chords instead of a line |
| `progression` | Generating the changes, and a drift check on the corpus tables |
| `drift` | Live mutation: what the loop does as it plays, and that it never touches the take |
| `templates` | That the templates actually differ, and the gate that refuses one that doesn't |
| `analysis` | Take measurement — variety, harmonic roles — and the dead-air guard |
| `midi` | The MIDI front end of the training pipeline — files to plain events in beats, and where harmony was found |
| `docs` | These documents against the code they describe — suite lists, quoted constants, retired names, dead links |
| `contrast` | WCAG 2.1 AA on every theme token pairing the UI uses, both themes |
| `kernel` | Melody scheduling — direction, host sync, note-off discipline, loop counter |

The `chords` suite needs [music-suite](https://github.com/Enkerli/music-suite)
checked out alongside this repo (or `MUSIC_SUITE=/path/to/music-suite`).

### Checking the interface

The **MelGen** app target is itself an AUv3 host — it loads the extension and
embeds the plug-in's own view — so running that scheme on a Simulator is enough
to check layout, theming, transport and session state without a third-party host.

Two caveats. Foundation Models is **not available in the Simulator** (it reports
`.modelNotReady` and never becomes ready), so generation only works on a device.
And Xcode can't host SwiftUI previews inside a `com.apple.AudioUnit-UI`
extension, nor can XCUITest reach the plug-in's controls — the extension renders
out-of-process and shows up as a `RemotePlaceholder` in the accessibility
hierarchy. VoiceOver on a device is unaffected.

---

## How it works

### Six sources, one loop

A take can come from any of six places, and everything downstream treats them
alike — the same measurement, the same curation, the same performance controls:

| Source | Cost | What it is |
|---|---|---|
| **The model** | ~1.8s per note | Foundation Models writes the line, or chooses when a comp lands |
| **Composed phrases** | Instant | A phrase grammar assembles gestures into lines that state, answer and land |
| **Stored lines** | Instant | A degree-relative line from the library, fitted to whatever changes are loaded |
| **Your own style** | Instant | Drawn from slot statistics and a variable-order chain over what you kept |
| **Interval cells** | Instant | Self-sequencing figures described as moves rather than positions |
| **Comping** | Instant | Voicings under the changes, voice-led, in six figures |

The model is the slowest by a wide margin — measured at roughly four times
slower than real time — so it is never what feeds continuous playback. It adds
new material; the deterministic sources keep the changes moving meanwhile.

### The loop

```
        make ──▶ hear ──▶ judge ──▶ keep ──▶ learn ──▶ make
```

Judging is one tap per take from a vocabulary of seven next actions — keep,
tweak, again, elsewhere, partly, later, skip — none of them terminal, so the same
take can be answered differently on a later pass. What survives feeds two learned
models: slot statistics over kept takes, and a variable-order chain of what
follows what. Both are transparent statistics rather than anything trained; see
[TRAINING.md](TRAINING.md) for why that boundary is where it is.

### Generation

The parsed progression becomes a harmonic plan — per chord, the beats it spans,
its scale, its chord tones, its colour notes and the notes to avoid landing on.
That plan, the current template and the library's few-shot examples go to the
model, which returns notes on an eighth-note grid. A form longer than four bars
is generated a phrase at a time, in a fresh session per phrase, because the
context window covers instructions, prompt and response together.

Post-processing then does what the model is bad at: notes are folded by octaves
to stay within an octave of their predecessor, out-of-scale pitches are moved to
the nearest tone that fits, holes left by an under-producing phrase are patched
from the stored library, and the line is made strictly monophonic.

### Playback

Raw notes are stored per take. What you hear is a deterministic render of them
through density, gate length, expression, swing and live drift, so moving a
control re-renders the current take instantly instead of needing a new one.

The kernel loops the rendered take, one *pass* at a time. A reversed pass is a
true time-reversal — a note occupying beats `[s, e)` of a loop of length `L`
plays at `[L − e, L − s)` — so Backward reverses every pass and Ping-Pong
alternates. With host sync on, each buffer's beat window comes from the host's
playhead rather than an internal one. The kernel publishes its position, which is
what the piano roll's playhead follows.

### Chord dictionary

The dictionary is owned by
[music-suite](https://github.com/Enkerli/music-suite)'s `packages/theory`, itself
ported from the MIDIsplainer chord dictionary. MelGen generates its Swift copy
rather than transcribing it:

```bash
python3 Scripts/generate-chord-dictionary.py
```

The same applies to the progression corpus, ported from
[ProgGenie](https://github.com/Enkerli/music-suite)'s `packages/proggen`:

```bash
python3 Scripts/generate-progression-tables.py
```

Never hand-edit `MelGenExtension/Melody/ChordDictionary+Generated.swift`. Change
the vocabulary in music-suite and regenerate.

### Training pipeline

Off-device work, and none of it ships. Three stages, split by what each side is
actually good at — the reasoning is in [COREML.md](COREML.md), and the short
version is that there is exactly one implementation of "which degree was that
note" and it is the one the plug-in runs.

```bash
pip install -r Scripts/training/requirements.txt

# 1. Python reads file formats, and nothing else.
python3 Scripts/training/midi_to_events.py ~/MIDI --out corpus/events.jsonl

# 2. Swift decides what the notes mean, and reports the number to beat.
Scripts/export-corpus.sh ~/exports --events corpus/events.jsonl --out corpus

# 3. Python trains, and says whether the result earned its place.
python3 Scripts/training/train_lstm.py --corpus corpus
python3 Scripts/training/export_coreml.py --corpus corpus
```

Stage 2 prints what `MelodyChain` — the variable-order model that already ships —
scores on held-out material. A neural model that doesn't beat it is not worth its
download, and stage 3 says so rather than reporting its own loss in isolation.

`Scripts/analyse-history.sh` is the measurement counterpart: what a session's
exports contain, rather than what can be trained from them.

```bash
Scripts/analyse-history.sh ~/Library/Mobile\ Documents/com~apple~CloudDocs
```

---

## Documentation

Six documents, each with one job. Kept apart so that a finding lands in exactly
one of them:

| Document | What belongs in it | What doesn't |
|---|---|---|
| [README.md](README.md) | What exists and how to build, verify and use it | Anything not built yet |
| [ROADMAP.md](ROADMAP.md) | What to build next, with effort, impact and dependencies | Bugs in what exists |
| [ISSUES.md](ISSUES.md) | What's wrong now, and what was measured rather than guessed | Feature requests |
| [TRAINING.md](TRAINING.md) | What "learning from your material" can and can't mean on device | Anything not about learning |
| [HANDOFF.md](HANDOFF.md) | Current state, open risks, and where to pick up | Durable design rationale — that goes in the code |
| [COREML.md](COREML.md) | Training off-device and running the result on the iPad | On-device learning — that's TRAINING.md |

### Hygiene

Four rules, each written because it was broken:

1. **A summary that restates a table is a summary that will contradict it.** The
   ROADMAP's wave summaries claimed items were open that their own detail rows
   marked done. Say it once, in the detail row, and let the summary link.
2. **A number in prose is a number that will drift.** "The last 24 takes" outlived
   the constant by an order of magnitude. Prefer naming the constant
   (`MelGenState.historyLimit`) over quoting its value.
3. **Renaming a concept in code renames it in the docs, in the same commit.**
   Briefs became templates in the code and stayed briefs in the README.
4. **Lists that mirror something enumerable get checked, not eyeballed.** The
   verify table drifted six suites behind `verify.sh`; `Scripts/verify.sh docs`
   now fails when it does.

Design rationale lives in the code, next to what it explains — these documents
say what the state *is*, not why each decision was made.

---

## Roadmap

See [ROADMAP.md](ROADMAP.md) for planned work. The near list: harmonic rhythm and
time signatures, presets, taxicab voice leading for comping, and note-duration
distributions that change over time. [TRAINING.md](TRAINING.md) works out what
"learning from your material" can actually mean on device, and what it can't.

---

## License

[CC0 1.0 Universal](LICENSE) — public domain dedication, as with the rest of the
suite.

## Suite handoff

This repo is part of the Enkerli music suite. For the whole-suite picture — repo
map, conventions, build/validation ladders, and open queues — start at the suite
handoff:
<https://github.com/Enkerli/music-suite/blob/main/HANDOFF.md>.
