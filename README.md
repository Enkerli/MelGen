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
| **Templates** | Twenty-three — nine line templates, six comping figures and eight bass figures. The mode chooses which set is in play; select any subset and cycle, shuffle or lock it |
| **Auto-regeneration** | A new take every 1/2/4/8 loops, swapped in on a loop boundary |
| **Take history** | 250 unjudged takes, and 1000 including judged ones, logged with their template, settings and measurements; tap to reload one. Exports as JSON and imports back, merged by take id |
| **What to do now** | One line above both tabs naming the next thing and why it's next, derived from the session's own state — and going quiet when nothing is outstanding |
| **Curation** | Yes / Maybe / No on what is sounding — or a swipe on the roll — with the seven (keep, tweak, try again, right elsewhere, partly, later, skip) one tap away, in passes, so the same take can be answered differently next time. A rating is a shortcut to three of the seven, never a score |
| **Variations** | Every variant, mutation, morph and drifted pass is judged in its own right, and says what its parent was called |
| **Facets and tags** | Density, placement, register, colour and motion are derived from measurement; tags are yours, and the vocabulary emerges from what you type |
| **Lines from takes** | Keep a take as a degree-relative line and it plays over any changes, instantly, with no model |
| **MIDI files, both ways** | Import a `.mid` as material and export a take as one. A file from MIDIcurator or ProgGenie carries its own leadsheet, so the line arrives as degrees; otherwise the chords are read from markers, then from a chord track, and the import says which |
| **Chord detection** | Names a chord from the notes sounding — 172 qualities by fingerprint, checked against the suite's own cross-language vectors |
| **Learned style** | What you kept, measured — as prompt text, as slot statistics, and as a chain of what follows what |
| **Composed phrases** | Gestures with rhythmic identity, composed by a phrase grammar into lines that state, answer and land |
| **Interval cells** | Hanon's self-sequencing figures and Samchillian-style interval streams, described as moves rather than positions |
| **Variants and morphs** | Fourteen transforms, scored against your material, and a dial between two lines you like |
| **Listening** | Play something in and it becomes library material, read against the changes on screen |
| **Comping** | Voicings under the changes, voice-led, in six figures |
| **Bass** | On-beat and off-beat figures played as two layers, balanced and selected on a pad, with a register range, a shift, eight seeds and a morph between them |
| **Degree histogram** | Which note, as weights over the twelve semitones above the chord's root. One `reach` dial walks the order an improviser arrives in — root, fifth, third, seventh, eleventh, ninth, thirteenth — and separate dials let the outside notes and a side-slipped pentatonic in. Comping draws on it too: the **Drawn** voicing asks each chord's own scale which colour it can carry, so a major seventh gets its ninth and a minor seventh gets its eleventh without either being written down |
| **Transition histogram** | How far to the next note, as weights over the interval. Multiplied by the degree histogram, so a line steps mostly by step *and* lands mostly on chord tones without either being a rule that overrides the other |
| **Modal vamps** | A key instead of a progression, written into the same field as `C(dorian)` and read by every mode. One ladder from brightest to darkest — Lydian, Ionian, Mixolydian, Dorian, Aeolian, Phrygian, Locrian — each rung one flattened degree below the last |
| **Drawn as you move it** | In Bass, every control draws a new part when you let go, and keeps it as a take. The one source fast enough to be played rather than asked for |
| **Voice leading** | Off, register, or smooth — minimal taxicab leading, ported from the suite's reference implementation and held to its shared vectors. In line mode it smooths the seam where a line crosses a chord change |
| **Progressions** | Generated here from corpus transition tables, rather than pasted in |
| **Setups** | Name the settings that decide what comes next and come back to them; mark one the default and new instances start there |
| **Session state** | Progression, settings and history are saved in the host's session |
| **Pattern library** | Save a take as a few-shot example that shapes later generations |
| **Two tabs** | **Play** makes material and performs it; **Decide** judges it and shows what's been learned |
| **Three modes** | **Line** writes a monophonic part, **Chords** comps under the changes, **Bass** draws a bass part in its own register. Explicit because the receiving instrument differs — a mono synth handed chords plays whichever note wins its note-priority rule, and a lead sound handed a bass part plays the right notes two octaves too low |
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
| `curation` | Dispositions, passes, eviction, facets, the tag vocabulary, the rotation, what gets learned, and that a rating stays a shortcut to three of the seven |
| `advance` | The aimed advance — it always answers, the two aims differ, and neither waits on the model |
| `phrases` | Gestures, the phrase grammar, and the lines it composes |
| `stylemodel` | Slot statistics over kept takes, and sampling new lines from them |
| `chain` | The variable-order model: what follows what, with backoff |
| `mutation` | Transforms, variant scoring, and the morph between two lines |
| `retrieval` | Finding a line rather than making one, and being surprised on purpose |
| `topics` | Grouping the library so the vocabulary can come from the material |
| `steps` | Interval cells: self-sequencing figures and interval streams |
| `histograms` | Which note and how far to the next one — the note stack in its stated order, the side slip, the modal ladder, and the two histograms multiplied |
| `bassline` | The bass mode: the two figure banks, the pad that balances and selects them, modal vamps as leadsheet text, and that the line stays in its range, stays one voice and states every chord |
| `capture` | Pairing, segmenting and quantizing what was played in |
| `comping` | The voicing layer, taxicab voice leading against the suite's shared vectors, and chords instead of a line |
| `progression` | Generating the changes, and a drift check on the corpus tables |
| `drift` | Live mutation: what the loop does as it plays, and that it never touches the take |
| `templates` | That the templates actually differ, and the gate that refuses one that doesn't |
| `analysis` | Take measurement — variety, harmonic roles — and the dead-air guard |
| `midi` | The MIDI front end of the training pipeline — files to plain events in beats, and where harmony was found |
| `midifile` | Reading and writing `.mid` — the codec round trip, the four harmony tiers, and chord detection against the suite's own vectors |
| `nextstep` | The line that says what to do now — every rung against the state it claims, and that it goes quiet |
| `docs` | These documents against the code they describe — suite lists, quoted constants, retired names, dead links |
| `terminology` | Every interface string against TERMINOLOGY.md — one word per concept |
| `icon` | `MelGen.icon` against the design pass — bar geometry, theme tokens, a dark value on every fill |
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

### Seven sources, one loop

A take can come from any of seven places, and everything downstream treats them
alike — the same measurement, the same curation, the same performance controls:

| Source | Cost | What it is |
|---|---|---|
| **The model** | ~1.8s per note | Foundation Models writes the line, or chooses when a comp lands |
| **Composed** | Instant | A phrase grammar assembles gestures into lines that state, answer and land |
| **Stored line** | Instant | A degree-relative line from the library, fitted to whatever changes are loaded |
| **Your material** | Instant | Drawn from slot statistics and a variable-order chain over what you kept |
| **What you play** | Instant | Your own playing, captured and read against the changes |
| **Comp** | Instant | Voicings under the changes, voice-led, in six figures |
| **Bassline** | Instant | A degree histogram and a transition histogram, drawn through a rhythmic figure, inside a stated register |

Which of the seven are offered depends on the mode: Chords narrows it to the
three that can produce a voicing and Bass to the three that can put a part in the
right register, because offering the others would be offering something the mode
can't deliver. Material also arrives from outside — a MIDI
file, or a take kept as a line — and once it is a `MelodyPattern` nothing
downstream can tell where it came from.

The model is the slowest by a wide margin — measured at roughly four times
slower than real time — so it is never what feeds continuous playback. It adds
new material; the deterministic sources keep the changes moving meanwhile.

### The loop

```
        make ──▶ hear ──▶ judge ──▶ keep ──▶ learn ──▶ make
```

Judging is one tap — or one swipe on the roll. Most takes get one of three coarse
answers, Yes, Maybe and No, which are shortcuts to three of a vocabulary of seven
next actions: keep, tweak, again, elsewhere, partly, later, skip. None of the
seven is terminal, so the same take can be answered differently on a later pass,
and a rating is never stored as a number — it *is* one of the seven, chosen for
you. What survives feeds two learned
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

### Bass, and the two histograms

The newest half of the plug-in, and the least discoverable: **Bass** is a mode
chip beside Line and Chords, and everything below is behind it.

#### Which note: the degree histogram

A weight for each of the twelve semitones above the sounding chord's root.
Chromatic buckets rather than scale degrees, because degree space cannot say
"a semitone above the third" — and that is exactly the material the histogram
was built for. A drawn semitone becomes the `(degree, alteration, role)` the
pattern format speaks on the way out, so nothing downstream has to know.

| Control | What it does |
|---|---|
| **Reach** | How far up the note stack the line goes: root, fifth, third, seventh, eleventh, ninth, thirteenth. That is the order an improviser arrives in, and the order of arrival *is* the histogram — what you reach for first is what you play most. One continuous dial, not seven presets: at 0 it is the root alone, at 1 everything through the thirteenth, and the weights stay in arrival order all the way up |
| **Outside** | Weight on the notes the scale doesn't contain. Small, always — at three per cent an outside note is colour and at thirty it is a wrong note. Left slightly on by default, which is where the chromatic approaches come from |
| **Side-slip** | The pentatonic on the third of the chord, and the one a semitone above it. Over Cm7 that is E♭ F G B♭ C, then E F♯ G♯ B C♯ — which shares no note with the chord's scale and lands anyway. The dial is how much of the second one you get |

The **avoid** notes the chord dictionary already derives are damped rather than
removed, so a colour note the harmony can't carry gets quieter instead of
disappearing.

#### How far: the transition histogram

A weight for each interval to the next note, from a twelfth down to a twelfth up.
It is **multiplied** by the degree histogram rather than chosen between: for
every candidate pitch in range, how likely a move of that size is times how
likely that landing note is over the chord now sounding. So a line steps mostly
by step *and* lands mostly on chord tones, with neither being a rule that
overrides the other.

| Control | What it does |
|---|---|
| **Chromatic** | How much the transitions like semitones |
| **Runs** | How much a move that continues the last one is favoured. This is what turns a chromatic approach into a run: a run is one decision to move by semitone and several to keep doing it, so it belongs here rather than in the note weights |
| **Leaps** | How wide the line reaches. Blended with an arpeggiating shape, because roots to fifths to octaves is how a bass moves and an exponential over interval size alone never produces it |

Both histograms can also be **learned** from what you kept — `observed(in:)`
counts what a set of takes actually played against the harmony it played it over
— and blended with the dialled shape, with the weight given to the observation
rising as there is more of it.

#### The figure pad

Bass plays two layers at once, merged into one monophonic line: an **on-beat**
figure and an **off-beat** one. A figure is eight onset chances, lengths and
accents over a bar — probabilities rather than a fixed mask, which is what makes
mixing two of them mean something and what makes two bars of one differ.

- **Left to right is the balance.** All the way left you hear only the on-beat
  layer; all the way right only the off-beat one; in the middle both at full.
  This is the syncopation axis — moving right is the part getting pushed off the
  beat without a single figure changing.
- **Up and down is which figures.** One position walking both banks at once,
  each ordered sparse to busy by its own measured onset weight. Between two
  entries the figures blend, so the axis is continuous rather than four steps.

The region is a square and every corner is reachable, including the one a
diamond would forbid: the busiest on-beat figure with the off-beat layer
silent, which is a straight walking bass and about the most ordinary bass part
there is.

**Shift** moves the whole figure along the bar and wraps it. It is the cheapest
variation available — an on-beat figure shifted by one eighth *is* an off-beat
figure, and not one note changed.

**Range** is register: where the part sits, as two note numbers. (Distinct from
Reach, which is how far up the chord it goes, and from Leaps, which is how wide
each move is.)

**Seed** is one of eight draws of the same settings — nothing is stored behind
them, because a draw *is* its seed, so all eight are always there and every one
can be got back exactly. **Morph** dials from this seed's draw into the next
one's, note by note, rather than switching at the boundary.

#### It draws as you move it

Bass is the first thing here fast enough to be *played* rather than asked for: a
draw is arithmetic over two histograms, so the part can be different before the
finger lifts. So every control in the section draws a new one **when you let go**
— not on every frame of a drag, which would make a hundred parts nobody can hear,
and not only when you press Draw, which is how a control stops teaching what it
does.

Each of those releases is a **take**, judged and kept like any other. Something
you have just found and cannot keep is something you have to find twice; the
history ring drops the unjudged ones, which is what it is for.

#### A key is a progression with one chord in it

There is no switch. A modal vamp is written into the progression field as
`C(dorian)` — which every mode reads, the piano roll already draws, and you can
edit by hand afterwards like any other progression. Under **Progression →
settings** there is a key, a mode and a **Write it into the progression**
button that fills the field for you; `D(dorian)|||` is four bars of D Dorian,
because an empty bar holds the previous chord.

The parentheses are required: the chord dictionary already spells two triads
`major` and `minor`, so a bare `Cminor` stays the triad it always was. This is
also the only way to reach Ionian, Aeolian and Phrygian, because several modes
share a tonic seventh chord and the chord-scale classifier can only give one
answer for all of them.

The modes run along one ladder, brightest to darkest:

```
Lydian ──♯4→4── Ionian ──7→♭7── Mixolydian ──3→♭3── Dorian
       ──6→♭6── Aeolian ──2→♭2── Phrygian ──5→♭5── Locrian
```

Each rung flattens exactly one degree, which is checked rather than tabulated —
and which turns out to be exactly what the Bassline Generator's own Minorness
control does, in the same order, arrived at from the opposite direction.

#### Comping draws on it too

The **Drawn** voicing style takes its tones from a degree histogram over each
chord's own scale rather than from a recipe in intervals. So a major seventh
gets its ninth and a minor seventh gets its eleventh — a major seventh's scale
is Lydian, its eleventh sits a semitone under the fifth, and the no-cluster rule
drops it in favour of the ninth. On a minor seventh nothing damps the eleventh
and it comes in. Neither is written down anywhere; both fall out of the scale
the dictionary already derives.

Two rules the histogram can't supply: no two tones a semitone apart, and an
alteration the symbol names replaces the degree it alters — voicing a `7♯11`
with its natural fifth and without the alteration voices a different chord.

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

Eight documents, each with one job. Kept apart so that a finding lands in exactly
one of them:

| Document | What belongs in it | What doesn't |
|---|---|---|
| [README.md](README.md) | What exists and how to build, verify and use it | Anything not built yet |
| [ROADMAP.md](ROADMAP.md) | What to build next, with effort, impact and dependencies | Bugs in what exists |
| [ISSUES.md](ISSUES.md) | What's wrong now, and what was measured rather than guessed | Feature requests |
| [TRAINING.md](TRAINING.md) | What "learning from your material" can and can't mean on device | Anything not about learning |
| [HANDOFF.md](HANDOFF.md) | Current state, open risks, and where to pick up | Durable design rationale — that goes in the code |
| [COREML.md](COREML.md) | Training off-device and running the result on the iPad | On-device learning — that's TRAINING.md |
| [DESIGN_BRIEF.md](DESIGN_BRIEF.md) | The experience: vocabulary, playflows, what's being asked of a design pass | Implementation, and anything already settled |
| [TESTING.md](TESTING.md) | What `verify.sh` can't answer, and the device sessions that can | Anything a suite could check instead |
| [TERMINOLOGY.md](TERMINOLOGY.md) | One word per concept, and the retired ones | Anything not a naming decision |

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

See [ROADMAP.md](ROADMAP.md) for planned work. The near list, after the
2026-08-25 review: authoring a comping template (the gate would accept eight more
and the control is closed to it), giving the corpus baseline its floors, and
having the corpus exporter write a history export so a found MIDI collection
reaches the models that already ship. Then harmonic rhythm, time signatures and
shuffled tonalities. [TRAINING.md](TRAINING.md) works out what "learning from
your material" can actually mean on device, and what it can't;
[COREML.md](COREML.md) is the off-device half.

---

## License

[CC0 1.0 Universal](LICENSE) — public domain dedication, as with the rest of the
suite.

## Suite handoff

This repo is part of the Enkerli music suite. For the whole-suite picture — repo
map, conventions, build/validation ladders, and open queues — start at the suite
handoff:
<https://github.com/Enkerli/music-suite/blob/main/HANDOFF.md>.
