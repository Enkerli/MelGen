#!/usr/bin/env python3
"""Checks the MIDI front end of the training pipeline.

Everything here builds its own MIDI files with mido and reads them back, so the
suite needs no corpus and asserts against material whose correct answer is known
by construction. What it is guarding is narrow and worth stating: this stage
must produce *plain events in beats* and must not start deciding what notes
mean. Every check below is either "the file was read correctly" or "harmony was
located where the file put it".
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "training"))

try:
    import mido
except ImportError:
    print("  SKIP  mido not installed (pip install -r Scripts/training/requirements.txt)")
    sys.exit(0)

import midi_to_events as ingest

TPB = 480
failures: list[str] = []
checks = 0


def check(label: str, ok: bool, detail: str = "") -> None:
    global checks
    checks += 1
    print(f"  {'PASS' if ok else 'FAIL'}  {label}{' — ' + detail if detail else ''}")
    if not ok:
        failures.append(label)


def track(name, notes, channel=0, meta=None):
    """A track from (start_beat, length_beats, pitch, velocity) tuples."""
    events = []
    for start, length, pitch, velocity in notes:
        events.append((start, "note_on", pitch, velocity))
        events.append((start + length, "note_off", pitch, 0))
    for beat, text in (meta or []):
        events.append((beat, "marker", text, 0))

    events.sort(key=lambda e: (e[0], 0 if e[1] == "note_off" else 1))
    out = mido.MidiTrack()
    out.append(mido.MetaMessage("track_name", name=name, time=0))
    ticks = 0
    for beat, kind, value, velocity in events:
        at = int(round(beat * TPB))
        delta, ticks = at - ticks, at
        if kind == "marker":
            out.append(mido.MetaMessage("marker", text=value, time=delta))
        else:
            out.append(mido.Message(kind, note=value, velocity=velocity,
                                    channel=channel, time=delta))
    return out


def write(path, tracks, numerator=None):
    midi = mido.MidiFile(ticks_per_beat=TPB)
    if numerator:
        head = mido.MidiTrack()
        head.append(mido.MetaMessage("time_signature", numerator=numerator,
                                     denominator=4, time=0))
        midi.tracks.append(head)
    for item in tracks:
        midi.tracks.append(item)
    midi.save(path)
    return Path(path)


SCALE = [(i * 0.5, 0.5, 60 + i, 90) for i in range(8)]
TRIADS = [(0, 4, p, 70) for p in (60, 64, 67)] + [(4, 4, p, 70) for p in (62, 65, 69)]


def main() -> None:
    with tempfile.TemporaryDirectory() as directory:
        home = Path(directory)

        # 1. A plain monophonic file: events in beats, note-offs paired.
        path = write(home / "line.mid", [track("Melody", SCALE)])
        record, error = ingest.read_file(path)
        check("a monophonic file reads", record is not None and error is None, error or "")
        if record:
            check("every note-on is present",
                  sum(1 for e in record["melody"] if e["isOn"]) == 8,
                  f"{sum(1 for e in record['melody'] if e['isOn'])} onsets")
            check("note-offs are paired with their ons",
                  sum(1 for e in record["melody"] if not e["isOn"]) == 8)
            check("time is in beats, not ticks",
                  [e["beat"] for e in record["melody"] if e["isOn"]][:3] == [0.0, 0.5, 1.0])
            check("a file with no harmony says so",
                  record["progressionSource"] == "none" and record["progression"] is None)

        # 2. A note-on with velocity 0 is a note-off. Files in the wild are full
        #    of these, and a reader that misses it produces notes that never end.
        running = mido.MidiTrack()
        running.append(mido.MetaMessage("track_name", name="Melody", time=0))
        running.append(mido.Message("note_on", note=60, velocity=90, time=0))
        running.append(mido.Message("note_on", note=60, velocity=0, time=TPB))
        path = write(home / "running.mid", [running])
        record, _ = ingest.read_file(path)
        check("note-on velocity 0 is read as a note-off",
              record is not None
              and sum(1 for e in record["melody"] if e["isOn"]) == 1
              and sum(1 for e in record["melody"] if not e["isOn"]) == 1)

        # 3. Markers become leadsheet text, mapped onto bars.
        path = write(home / "marked.mid",
                     [track("Melody", SCALE, meta=[(0, "Cmaj7"), (4, "Am7")])])
        record, _ = ingest.read_file(path)
        check("chord markers are found", record["progressionSource"] == "marker")
        check("markers map onto bars", record["progression"] == "Cmaj7 | Am7",
              repr(record["progression"]))

        # 4. A marker that isn't a chord is not harmony.
        path = write(home / "rehearsal.mid",
                     [track("Melody", SCALE, meta=[(0, "Verse 1"), (4, "Solo")])])
        record, _ = ingest.read_file(path)
        check("rehearsal marks are not read as chords",
              record["progressionSource"] == "none", repr(record["progression"]))

        # 5. Two chords in one bar, unevenly placed: allowed, and reported,
        #    because the leadsheet format will share the bar equally.
        path = write(home / "uneven.mid",
                     [track("Melody", SCALE, meta=[(0, "Cmaj7"), (3, "Am7")])])
        record, _ = ingest.read_file(path)
        check("uneven chords in a bar are reported, not silently flattened",
              any("unevenly spaced" in w for w in record["warnings"]),
              "; ".join(record["warnings"]) or "no warning")

        # 6. A sidecar outranks markers: a human wrote it in the parser's notation.
        path = write(home / "sided.mid",
                     [track("Melody", SCALE, meta=[(0, "Cmaj7")])])
        path.with_suffix(".chords").write_text("Dm7 | G7", encoding="utf-8")
        record, _ = ingest.read_file(path)
        check("a sidecar outranks markers",
              record["progressionSource"] == "sidecar" and record["progression"] == "Dm7 | G7")

        # 7. Melody and chords in one file are separated by polyphony.
        path = write(home / "both.mid",
                     [track("Untitled A", SCALE), track("Untitled B", TRIADS)])
        record, _ = ingest.read_file(path)
        check("the monophonic track is the melody",
              sum(1 for e in record["melody"] if e["isOn"]) == 8)
        check("the polyphonic track is the harmony",
              sum(1 for e in record["chordEvents"] if e["isOn"]) == 6)
        check("a chord track with no names is left for Swift to name",
              record["progressionSource"] == "chordTrack" and record["progression"] is None)

        # 8. Track names win over the polyphony heuristic.
        path = write(home / "named.mid",
                     [track("Comping", SCALE), track("Lead", TRIADS)])
        record, _ = ingest.read_file(path)
        check("track names outrank the polyphony guess",
              sum(1 for e in record["melody"] if e["isOn"]) == 6
              and sum(1 for e in record["chordEvents"] if e["isOn"]) == 8)

        # 9. Drums are never material.
        path = write(home / "drums.mid",
                     [track("Melody", SCALE), track("Kit", SCALE, channel=9)])
        record, _ = ingest.read_file(path)
        check("channel 10 is excluded",
              sum(1 for e in record["melody"] + record["chordEvents"] if e["isOn"]) == 8)

        # 10. A time signature that isn't 4/4 changes where bar lines fall.
        path = write(home / "waltz.mid",
                     [track("Melody", SCALE, meta=[(0, "Cmaj7"), (3, "Am7")])],
                     numerator=3)
        record, _ = ingest.read_file(path)
        check("the time signature sets the bar length", record["beatsPerBar"] == 3.0)
        check("bars follow the time signature", record["progression"] == "Cmaj7 | Am7",
              repr(record["progression"]))

        # 11. An unreadable file is skipped, not fatal: a found corpus has some.
        broken = home / "broken.mid"
        broken.write_bytes(b"not a midi file")
        record, error = ingest.read_file(broken)
        check("an unreadable file is reported and skipped",
              record is None and error is not None)

    print()
    print(f"  {checks - len(failures)}/{checks} checks passed")
    if failures:
        print("  failed: " + ", ".join(failures))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
