// Checks learning from what was played in.
//
// The MIDI parsing isn't the hard part and isn't what's tested here — that lives
// in the kernel and needs a host. What's tested is the three things that are
// actually easy to get wrong: pairing note-ons with the right note-offs when a
// player overlaps them, splitting a stream into phrases the way the player heard
// themselves phrase it, and quantizing to the grid without silently absorbing
// how far off the grid it was.
import Foundation

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let progression = try ChordProgression.parse("Dm7 | G7 | Cmaj7 | A7♭9")

func on(_ note: UInt8, _ beat: Double, _ velocity: UInt8 = 90) -> CapturedMIDIEvent {
    CapturedMIDIEvent(beat: beat, note: note, velocity: velocity, isOn: true)
}
func off(_ note: UInt8, _ beat: Double) -> CapturedMIDIEvent {
    CapturedMIDIEvent(beat: beat, note: note, velocity: 0, isOn: false)
}

// MARK: - Pairing

print("── pairing ────────────────────────────────────────")

let simple = MelodyCapture.notes(from: [on(60, 0), off(60, 0.5), on(62, 1), off(62, 1.5)])
check("a note is its on and its off", simple.count == 2)
check("with the right length", simple.first?.durationBeats == 0.5)
check("and the on's velocity, not the off's", simple.first?.velocity == 90)

// Overlapping the same pitch is what a keyboard player does constantly.
let retriggered = MelodyCapture.notes(from: [on(60, 0), on(60, 0.5), off(60, 1), off(60, 1.5)])
check("a retriggered pitch gives two notes", retriggered.count == 2)
check("paired most-recent-first, so neither swallows the other",
      Set(retriggered.map(\.durationBeats)) == [0.5, 1.5],
      "\(retriggered.map(\.durationBeats))")

// Legato: the next note starts before the last one ends.
let overlapped = MelodyCapture.notes(from: [on(60, 0), on(64, 0.4), off(60, 0.6), off(64, 1)])
check("overlapping different pitches both survive", overlapped.count == 2)
check("and keep the overlap, because that's how it was played",
      (overlapped.first?.startBeat ?? 0) + (overlapped.first?.durationBeats ?? 0) > 0.4)

// A note still held when capture stops is the one you were holding when you
// decided you liked it.
let held = MelodyCapture.notes(from: [on(60, 0), on(67, 1)], endingAt: 3)
check("notes still held at the end are kept, not dropped", held.count == 2)
check("and closed at the end", held.map { $0.startBeat + $0.durationBeats }.max() == 3)

check("an off with no on is ignored rather than crashing",
      MelodyCapture.notes(from: [off(60, 1)]).isEmpty)
check("nothing played is no notes", MelodyCapture.notes(from: []).isEmpty)

// MARK: - Segmenting

print()
print("── segmenting at the silences ─────────────────────")

var stream: [CapturedMIDIEvent] = []
for beat in stride(from: 0.0, to: 3.0, by: 0.5) {
    stream.append(on(UInt8(60 + Int(beat * 2) % 5), beat))
    stream.append(off(UInt8(60 + Int(beat * 2) % 5), beat + 0.4))
}
// A gap of three beats, then another run.
for beat in stride(from: 6.0, to: 9.0, by: 0.5) {
    stream.append(on(UInt8(64 + Int(beat * 2) % 5), beat))
    stream.append(off(UInt8(64 + Int(beat * 2) % 5), beat + 0.4))
}

let phrases = MelodyCapture.phrases(from: MelodyCapture.notes(from: stream))
check("a gap splits a stream into phrases", phrases.count == 2, "\(phrases.count)")
check("each phrase is rebased to its own start",
      phrases.allSatisfy { $0.notes.first?.startBeat == 0 })
check("but remembers where it was played",
      phrases.count == 2 && phrases[1].startBeat >= 6)
check("a run with no gap in it is one phrase",
      MelodyCapture.phrases(from: MelodyCapture.notes(from: Array(stream.prefix(12)))).count == 1)
check("two notes aren't a phrase",
      MelodyCapture.phrases(from: MelodyCapture.notes(from: [on(60, 0), off(60, 0.5),
                                                             on(62, 0.5), off(62, 1)])).isEmpty)
check("every phrase reports its length", phrases.allSatisfy { $0.lengthBeats > 0 })

// MARK: - Quantizing

print()
print("── quantizing, but only just ──────────────────────")

// Deliberately loose playing — and *unevenly* loose, because a phrase that is
// uniformly late is not loose at all: rebasing to its own first note absorbs a
// shared offset, which is correct. Only the spread around the grid is looseness.
let loose = MelodyCapture.phrases(from: MelodyCapture.notes(from: [
    on(60, 0.07), off(60, 0.44),
    on(62, 0.61), off(62, 0.94),
    on(64, 0.93), off(64, 1.44),
    on(65, 1.62), off(65, 1.96)
]))
check("a loose phrase is still a phrase", loose.count == 1)
guard let looseFirst = loose.first else { print("  FAIL  no phrase"); exit(1) }
check("and it says it was played loosely", looseFirst.meanDeviation > 0.05,
      "mean deviation \(String(format: "%.3f", looseFirst.meanDeviation)) eighths")

let snapped = MelodyCapture.quantize(looseFirst)
check("quantizing puts everything on the grid",
      snapped.allSatisfy { abs($0.startBeat * 2 - ($0.startBeat * 2).rounded()) < 1e-9 },
      "\(snapped.map(\.startBeat))")
check("without losing notes", snapped.count == looseFirst.notes.count)
check("and the looseness is recorded rather than absorbed", looseFirst.meanDeviation > 0)

// Two fingers on one eighth is a chord, and this path is melodic.
let doubled = CapturedPhrase(notes: [
    SequencedNote(note: 60, velocity: 90, startBeat: 0, durationBeats: 0.5),
    SequencedNote(note: 67, velocity: 90, startBeat: 0.02, durationBeats: 0.5),
    SequencedNote(note: 64, velocity: 90, startBeat: 1, durationBeats: 0.5)
], startBeat: 0, meanDeviation: 0)
let single = MelodyCapture.quantize(doubled)
check("simultaneous notes become one", single.count == 2, "\(single.count)")
check("and the top one wins, which is what a listener hears",
      single.first?.note == 67)

// MARK: - Reading it back as degrees

print()
print("── against the harmony that was sounding ──────────")

guard let pattern = MelodyCapture.pattern(from: looseFirst, over: progression, name: "played") else {
    print("  FAIL  a captured phrase reads back as a pattern")
    exit(1)
}
check("a captured phrase reads back as a pattern", pattern.notes.count >= 3)
check("it carries where it came from", pattern.origin?.source == .captured)
check("and which changes it was played over",
      pattern.origin?.progressionText == progression.text)
check("it plays back over the same changes",
      !MelodyPatterns.realize(pattern, over: progression).isEmpty)
check("and over changes it never met",
      !MelodyPatterns.realize(pattern, over: try ChordProgression.parse("E♭7 Gm9|D∆|A♭6")).isEmpty)

// A phrase played in the second half of the form must be read against the
// chords that were actually sounding there, not against the first bar.
let late = CapturedPhrase(notes: [
    SequencedNote(note: 60, velocity: 90, startBeat: 0, durationBeats: 0.5),
    SequencedNote(note: 64, velocity: 90, startBeat: 0.5, durationBeats: 0.5),
    SequencedNote(note: 67, velocity: 90, startBeat: 1, durationBeats: 0.5)
], startBeat: 8, meanDeviation: 0)
let earlyPattern = MelodyCapture.pattern(from: CapturedPhrase(notes: late.notes, startBeat: 0,
                                                              meanDeviation: 0),
                                         over: progression, name: "early")
let latePattern = MelodyCapture.pattern(from: late, over: progression, name: "late")
check("the same notes played later read as different degrees",
      earlyPattern?.notes.map(\.degree) != latePattern?.notes.map(\.degree),
      "\(earlyPattern?.notes.map(\.degree) ?? []) vs \(latePattern?.notes.map(\.degree) ?? [])")

// MARK: - Into the models

print()
print("── straight into both learned models ──────────────")

let learned = MelodyCapture.learn(from: stream, over: progression)
check("playing produces patterns", !learned.isEmpty, "\(learned.count)")
check("named in order", learned.first?.name == "Played 1")

var model = MelodyStyleModel(id: "played")
for pattern in learned { model.add(pattern) }
check("the slot model takes them with no special case", model.takes == learned.count)
check("and has something to sample", !model.isEmpty)

var chain = MelodyChain()
for pattern in learned { chain.add(pattern) }
check("so does the chain", chain.takes == learned.count)
check("and it walks", chain.generate(bars: 4, seed: 1) != nil)

check("learning is deterministic",
      MelodyCapture.learn(from: stream, over: progression).map(\.notes) == learned.map(\.notes))

print()
print(failures == 0 ? "capture: all checks passed" : "capture: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
