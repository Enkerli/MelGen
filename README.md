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
| **Note length** | Staccato through as-written to legato, applied live |
| **Expression & swing** | Metric accents, articulation, timing looseness, and swung eighths |
| **Style briefs** | Nine rotating rhythmic/contour briefs so successive takes actually differ |
| **Auto-regeneration** | A new take every 1/2/4/8 loops, swapped in on a loop boundary |
| **Take history** | The last 24 takes, logged with their brief and settings; tap to reload one |
| **Session state** | Progression, settings and history are saved in the host's session |
| **Pattern library** | Save a take as a few-shot example that shapes later generations |
| **Themes** | Light (default) and Dark, MelGen's own setting rather than the host's |

---

## Requirements

| Requirement | Version |
|---|---|
| Xcode | 26 or later |
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
| `chords` | Every chord symbol's quality, scale, tensions and avoid notes against Music Suite's TypeScript, plus a drift check on the generated dictionary |
| `state` | Session-state round-trip, and the expression / density / note-length passes |
| `contrast` | WCAG 2.1 AA on every theme token pairing the UI uses, both themes |
| `kernel` | Melody scheduling — direction, host sync, note-off discipline, loop counter |

The `chords` suite needs [music-suite](https://github.com/Enkerli/music-suite)
checked out alongside this repo (or `MUSIC_SUITE=/path/to/music-suite`).

---

## How it works

### Generation

The parsed progression becomes a harmonic plan — per chord, the beats it spans,
its scale, its chord tones, its colour notes and the notes to avoid landing on.
That plan, a rotating style brief and the pattern library's few-shot examples go
to the model, which returns notes on an eighth-note grid.

Post-processing then does what the model is bad at: notes are folded by octaves
to stay within an octave of their predecessor, out-of-scale pitches are moved to
the nearest tone that fits (chord tones on strong beats), and the line is made
strictly monophonic.

### Playback

Raw model notes are stored per take. What you hear is a deterministic render of
them through the density, note-length, expression and swing controls, so moving a
control re-renders the current take instantly instead of needing a new one.

The kernel loops the rendered take, one *pass* at a time. A reversed pass is a
true time-reversal — a note occupying beats `[s, e)` of a loop of length `L`
plays at `[L − e, L − s)` — so Backward reverses every pass and Ping-Pong
alternates. With host sync on, each buffer's beat window comes from the host's
playhead rather than an internal one.

### Chord dictionary

The dictionary is owned by
[music-suite](https://github.com/Enkerli/music-suite)'s `packages/theory`, itself
ported from the MIDIsplainer chord dictionary. MelGen generates its Swift copy
rather than transcribing it:

```bash
python3 Scripts/generate-chord-dictionary.py
```

Never hand-edit `MelGenExtension/Melody/ChordDictionary+Generated.swift`. Change
the vocabulary in music-suite and regenerate.

---

## License

[CC0 1.0 Universal](LICENSE) — public domain dedication, as with the rest of the
suite.

## Suite handoff

This repo is part of the Enkerli music suite. For the whole-suite picture — repo
map, conventions, build/validation ladders, and open queues — start at the suite
handoff:
<https://github.com/Enkerli/music-suite/blob/main/HANDOFF.md>.
