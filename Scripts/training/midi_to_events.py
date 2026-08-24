#!/usr/bin/env python3
"""Reads a collection of MIDI files into the plain events MelGen already learns from.

This is the *front end* of the training pipeline and it deliberately knows no
music theory. It does one job — turn a file format into note-on/note-off events
positioned in beats — and hands everything musical to the Swift side, where
`MelodyCapture.learn(from:over:)` and `MelodyPatterns.extract` already live.

The reason is the one integration bug this pipeline can't afford. A degree is
only meaningful relative to a chord, and "which degree was that note" is
answered today by `MelodyPatternExtraction.swift`, which does not snap off-scale
notes and keeps the role a note had over its original harmony. Re-deriving that
in Python would produce a second answer to the same question, and the day the
two disagree is the day the iPad plays something the training data never said.
So: Python parses files, Swift decides what the notes *mean*.

That also means this script is ROADMAP S2's file reader ("the pipeline exists;
what's missing is only the file reader") rather than a training-only detour. It
is worth having whether or not a neural model ever ships.

    python3 Scripts/training/midi_to_events.py ~/MIDI --out corpus/events.jsonl

Output is JSON Lines, one object per source file:

    {"name": …, "beatsPerBar": 4.0, "endBeat": 32.0,
     "progression": "Gm7 | C7 | FMaj7 | %",   # leadsheet text, or null
     "progressionSource": "sidecar"|"marker"|"chordTrack"|"none",
     "melody":      [{"beat": 0.0, "note": 65, "velocity": 90, "isOn": true}, …],
     "chordEvents": [ … same shape … ],
     "warnings": [ … ]}

Chord alignment is looked for in three places, in descending order of how much
it can be trusted:

  1. a sidecar `<stem>.chords` file holding leadsheet text — unambiguous,
     because a human wrote it in the notation the parser already reads;
  2. marker / text meta events that look like chord symbols — common in files
     exported from notation software, and positioned, so they can be mapped
     onto bars;
  3. a chord track — real harmony, but as pitches rather than names, so the
     naming is left to Swift, which owns the chord dictionary.

A file with none of the three still yields events. It just can't contribute
degrees, only rhythm and contour, and the Swift stage is what decides what to do
about that.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path

try:
    import mido
except ImportError:  # pragma: no cover - environment guard
    sys.exit("mido is required: pip install -r Scripts/training/requirements.txt")

# Permissive on purpose. The authority on whether a symbol parses is
# `ChordProgression.parse` in Swift; this only has to separate "Gm7" from
# "Verse 1" so that a rehearsal mark doesn't get mapped onto a bar as harmony.
CHORD_TEXT = re.compile(r"^[A-G][#b♯♭]?[A-Za-z0-9°ø∆+\-#b()/♯♭]*$")

MELODY_NAMES = ("melody", "lead", "solo", "tune", "line", "theme")
CHORD_NAMES = ("chord", "comp", "harmon", "changes", "pad", "block", "voicing")
DRUM_CHANNEL = 9


def note_events(track, ticks_per_beat):
    """Absolute-beat note-on/note-off events for one track, drums excluded."""
    events = []
    ticks = 0
    for message in track:
        ticks += message.time
        if message.is_meta or message.type not in ("note_on", "note_off"):
            continue
        if getattr(message, "channel", 0) == DRUM_CHANNEL:
            continue
        # A note-on with velocity 0 is a note-off. Every MIDI reader has to know
        # this and every one that forgets produces notes that never end.
        is_on = message.type == "note_on" and message.velocity > 0
        events.append({
            "beat": round(ticks / ticks_per_beat, 6),
            "note": int(message.note),
            "velocity": int(message.velocity) if is_on else 0,
            "isOn": is_on,
        })
    return events


def overlap_share(events):
    """How often a note starts while another is still sounding: 0 is a line, 1 is a pad."""
    onsets = [e for e in events if e["isOn"]]
    if len(onsets) < 2:
        return 0.0
    held = 0
    sounding = 0
    # Note-offs settle before note-ons at the same beat — the order
    # `MelodyCapture.notes(from:)` uses in Swift. The other order makes a
    # perfectly monophonic line, whose notes end exactly where the next begins,
    # look like a pad and get filed as harmony.
    for event in sorted(events, key=lambda e: (e["beat"], 1 if e["isOn"] else 0)):
        if event["isOn"]:
            if sounding > 0:
                held += 1
            sounding += 1
        else:
            sounding = max(0, sounding - 1)
    return held / len(onsets)


def track_name(track):
    for message in track:
        if message.is_meta and message.type == "track_name":
            return message.name.strip().lower()
    return ""


def beats_per_bar(midi):
    for track in midi.tracks:
        for message in track:
            if message.is_meta and message.type == "time_signature":
                return message.numerator * 4.0 / message.denominator
    return 4.0


def markers(midi, ticks_per_beat):
    """Chord-looking marker and text meta events, in beats."""
    found = []
    for track in midi.tracks:
        ticks = 0
        for message in track:
            ticks += message.time
            if not message.is_meta or message.type not in ("marker", "text"):
                continue
            text = message.text.strip()
            if text and CHORD_TEXT.match(text):
                found.append((ticks / ticks_per_beat, text))
    return sorted(found)


def leadsheet(chords, bar_beats, total_beats, warnings):
    """Chord symbols positioned in beats, as the leadsheet text the parser reads.

    `ChordProgression.parse` splits a bar's beats *equally* between the chords
    written in it, so a bar holding two chords at unequal positions loses that
    unevenness here. That is a real loss and it is reported rather than hidden.
    """
    if not chords:
        return None
    last_chord_bar = int(max(beat for beat, _ in chords) // bar_beats)
    bar_count = max(1,
                    math.ceil(((total_beats or bar_beats) - 1e-6) / bar_beats),
                    last_chord_bar + 1)
    bars: list[list[str]] = [[] for _ in range(bar_count)]
    for beat, symbol in chords:
        index = int(beat // bar_beats)
        if 0 <= index < bar_count:
            bars[index].append((beat - index * bar_beats, symbol))

    text_bars = []
    for bar in bars:
        bar.sort()
        if len(bar) > 1:
            share = bar_beats / len(bar)
            expected = [i * share for i in range(len(bar))]
            if any(abs(a - b) > 0.05 for (a, _), b in zip(bar, expected)):
                warnings.append("a bar's chords are unevenly spaced; "
                                "the leadsheet format shares the bar equally")
        text_bars.append(" ".join(symbol for _, symbol in bar))

    # Trailing empty bars carry no information; interior ones mean "hold", which
    # is exactly what the parser does with an empty bar.
    while text_bars and not text_bars[-1]:
        text_bars.pop()
    if not any(text_bars):
        return None
    return " | ".join(text_bars)


def classify(midi, ticks_per_beat, melody_track, chord_track):
    """Split the tracks into one melody voice and one harmony voice."""
    tracks = []
    for index, track in enumerate(midi.tracks):
        events = note_events(track, ticks_per_beat)
        if not events:
            continue
        tracks.append({
            "index": index,
            "name": track_name(track),
            "events": events,
            "onsets": sum(1 for e in events if e["isOn"]),
            "overlap": overlap_share(events),
        })

    if not tracks:
        return None, None, []

    warnings = []
    melody = chord = None

    if melody_track is not None:
        melody = next((t for t in tracks if t["index"] == melody_track), None)
    if chord_track is not None:
        chord = next((t for t in tracks if t["index"] == chord_track), None)

    if melody is None:
        named = [t for t in tracks if any(n in t["name"] for n in MELODY_NAMES)]
        candidates = named or [t for t in tracks if t["overlap"] < 0.15 and t is not chord]
        melody = max(candidates, key=lambda t: t["onsets"], default=None)
    if chord is None:
        named = [t for t in tracks if any(n in t["name"] for n in CHORD_NAMES) and t is not melody]
        candidates = named or [t for t in tracks if t["overlap"] >= 0.15 and t is not melody]
        chord = max(candidates, key=lambda t: t["onsets"], default=None)

    used = {t["index"] for t in (melody, chord) if t}
    ignored = [t for t in tracks if t["index"] not in used and t["onsets"] > 4]
    if ignored:
        warnings.append("ignored %d other track(s) with notes: %s"
                        % (len(ignored), ", ".join(str(t["index"]) for t in ignored)))
    return melody, chord, warnings


def read_file(path: Path, melody_track=None, chord_track=None):
    try:
        midi = mido.MidiFile(path)
    except Exception as error:  # a corpus of found files always has a few
        return None, f"{path.name}: unreadable ({error})"

    ticks_per_beat = midi.ticks_per_beat or 480
    bar_beats = beats_per_bar(midi)
    melody, chord, warnings = classify(midi, ticks_per_beat, melody_track, chord_track)
    if melody is None and chord is None:
        return None, f"{path.name}: no note events"

    events = (melody["events"] if melody else []) + (chord["events"] if chord else [])
    end_beat = max((e["beat"] for e in events), default=0.0)

    progression = None
    source = "none"
    sidecar = path.with_suffix(".chords")
    if sidecar.exists():
        text = sidecar.read_text(encoding="utf-8").strip()
        if text:
            progression, source = text, "sidecar"
    if progression is None:
        found = [(beat, symbol) for beat, symbol in markers(midi, ticks_per_beat)]
        progression = leadsheet(found, bar_beats, end_beat, warnings)
        if progression:
            source = "marker"
    if progression is None and chord is not None:
        source = "chordTrack"

    return {
        "name": path.name,
        "beatsPerBar": bar_beats,
        "endBeat": round(end_beat, 6),
        "progression": progression,
        "progressionSource": source,
        "melody": melody["events"] if melody else [],
        "chordEvents": chord["events"] if chord else [],
        "warnings": warnings,
    }, None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="+", help="MIDI files or directories to read")
    parser.add_argument("--out", required=True, help="JSONL file to write")
    parser.add_argument("--melody-track", type=int, default=None,
                        help="force a track index as the melody voice")
    parser.add_argument("--chord-track", type=int, default=None,
                        help="force a track index as the harmony voice")
    parser.add_argument("--limit", type=int, default=None, help="stop after N files")
    args = parser.parse_args()

    files: list[Path] = []
    for entry in args.paths:
        path = Path(entry).expanduser()
        if path.is_dir():
            files.extend(sorted(p for p in path.rglob("*")
                                if p.suffix.lower() in (".mid", ".midi")))
        elif path.suffix.lower() in (".mid", ".midi"):
            files.append(path)
    if args.limit:
        files = files[:args.limit]
    if not files:
        print("No MIDI files found.", file=sys.stderr)
        return 1

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    by_source: dict[str, int] = {}
    written = skipped = 0

    with out.open("w", encoding="utf-8") as handle:
        for path in files:
            record, error = read_file(path, args.melody_track, args.chord_track)
            if error:
                print(f"  skipped {error}", file=sys.stderr)
                skipped += 1
                continue
            handle.write(json.dumps(record) + "\n")
            by_source[record["progressionSource"]] = by_source.get(record["progressionSource"], 0) + 1
            written += 1

    print(f"{written} files written to {out}, {skipped} skipped", file=sys.stderr)
    for source, count in sorted(by_source.items(), key=lambda item: -item[1]):
        print(f"  {source:<11} {count}", file=sys.stderr)
    if by_source.get("none"):
        print("  files with no harmony can teach rhythm and contour, not degrees",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
