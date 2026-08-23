// Checks the direction that closes the loop: takes back into patterns.
//
// The claim is that `extract` inverts `realize` — that if a line was written in
// scale degrees, played against harmony and then read back, the degrees come
// home unchanged. That's what makes a take you liked reusable over anything, so
// that's what this tries to falsify. Then the same machinery is pointed at a
// real take off a device, because a round trip through our own arithmetic is
// only half a proof.
import Foundation

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let progressionTexts = [
    "E♭7 Gm9|D∆|A♭6",
    "Cmaj7 | E7 | Am7 | A♭7 | G | D7♯5 | Dm7 | D♭7 | C6 | F | C | B♭ | F | C | D7 | G7",
    "F♯m7 | Am7 | F7 | Gmaj7 | G7alt | F♯mM7 | Dm7 | C♯m7",
    "Cdim7 | C7alt | Cquartal | C5"
]

// MARK: - Round trip

print("── round trip: realize, then read the degrees back ─────")

var roundTrips = 0
for text in progressionTexts {
    let progression = try ChordProgression.parse(text)
    for pattern in MelodyPatterns.seeds {
        let realized = MelodyPatterns.realize(pattern, over: progression)
        guard !realized.isEmpty else {
            check("\(pattern.name) over \(text.prefix(14))… realizes", false)
            continue
        }
        guard let recovered = MelodyPatterns.extract(from: realized,
                                                     over: progression,
                                                     name: "\(pattern.name) (recovered)") else {
            check("\(pattern.name) over \(text.prefix(14))… extracts", false)
            continue
        }
        roundTrips += 1

        let label = "\(pattern.name) over \(text.prefix(14))…"
        check("\(label) recovers one pattern note per played note",
              recovered.notes.count == realized.count,
              "\(recovered.notes.count) of \(realized.count)")

        // The invariant worth asserting is not that the degree *numbers* match —
        // a flattened seventh and a natural sixth can be the same pitch, and
        // reading one as the other is correct, not a loss. It's that playing the
        // recovered pattern back over the same changes gives the same line.
        let replayed = MelodyPatterns.realize(recovered, over: progression)
        check("\(label) replays at the same moments",
              replayed.map(\.startBeat) == realized.map(\.startBeat),
              replayed.count == realized.count ? "" : "\(replayed.count) vs \(realized.count) notes")
        check("\(label) replays the same pitch classes",
              replayed.map { Int($0.note) % 12 } == realized.map { Int($0.note) % 12 })

        // Rhythm has to survive too, or a pattern is only half recovered — but
        // only the part of it that ever got played: a four-bar cell over a
        // three-bar form loses its last bar to the end of the progression, which
        // is the tiling working, not the extraction failing.
        let patternEighths = pattern.bars * 8
        let totalEighths = Int((progression.totalBeats * 2).rounded())
        let sourceOnsets = Set(pattern.notes
            .map { $0.startEighth % patternEighths }
            .filter { onset in
                stride(from: 0, to: totalEighths, by: patternEighths).contains { $0 + onset < totalEighths }
            })
        let recoveredOnsets = Set(recovered.notes.map { $0.startEighth % patternEighths })
        check("\(label) recovers the rhythm", recoveredOnsets == sourceOnsets,
              recoveredOnsets == sourceOnsets ? "" : "\(recoveredOnsets.sorted()) vs \(sourceOnsets.sorted())")
    }
}

// MARK: - A real take, off a device

print()
print("── a real take: F♯/E♭ session, 2026-08-22 ──────────────")

// "Running eighths", model take, E♭7 Gm9|D∆|A♭6, 12 beats — from an exported
// history. Real model output, including the repeated pitch and the octave leap
// at the start that post-processing left alone.
let realTake = [
    SequencedNote(note: 49, velocity: 60, startBeat: 0, durationBeats: 0.5),
    SequencedNote(note: 55, velocity: 60, startBeat: 2, durationBeats: 0.5),
    SequencedNote(note: 57, velocity: 60, startBeat: 3, durationBeats: 0.5),
    SequencedNote(note: 59, velocity: 60, startBeat: 4, durationBeats: 0.5),
    SequencedNote(note: 61, velocity: 60, startBeat: 5, durationBeats: 0.5),
    SequencedNote(note: 61, velocity: 60, startBeat: 6, durationBeats: 0.5),
    SequencedNote(note: 62, velocity: 60, startBeat: 7, durationBeats: 0.5),
    SequencedNote(note: 63, velocity: 60, startBeat: 8, durationBeats: 2)
]

let home = try ChordProgression.parse("E♭7 Gm9|D∆|A♭6")
guard let lifted = MelodyPatterns.extract(from: realTake,
                                          over: home,
                                          name: "Lifted",
                                          lengthBeats: 12,
                                          origin: PatternOrigin(progressionText: home.text,
                                                                briefName: "Running eighths",
                                                                source: .model)) else {
    print("  FAIL  a real take extracts")
    exit(1)
}

check("a real take extracts", lifted.notes.count == realTake.count,
      "\(lifted.notes.count) of \(realTake.count) notes")
check("it spans the bars it was played over", lifted.bars == 3, "\(lifted.bars) bars")
check("it keeps the rests it was played with",
      lifted.notes.first?.restAfterEighths == 3,
      "first note followed by \(lifted.notes.first?.restAfterEighths ?? -1) eighths of silence")
check("it records what each note was over its own harmony",
      lifted.notes.allSatisfy { $0.role != nil })
check("it carries its provenance", lifted.origin?.progressionText == home.text)
check("it describes itself", !lifted.summary.isEmpty, lifted.summary)

// Played back over its own harmony it has to be recognisably the same line.
let athome = MelodyPatterns.realize(lifted, over: home)
let originalClasses = realTake.map { Int($0.note) % 12 }
let replayedClasses = athome.prefix(realTake.count).map { Int($0.note) % 12 }
check("replayed over its own changes it keeps its pitch classes",
      originalClasses == Array(replayedClasses),
      "\(originalClasses) vs \(Array(replayedClasses))")

// And over changes it never saw it has to still be music.
for text in progressionTexts.dropFirst() {
    let elsewhere = try ChordProgression.parse(text)
    let moved = MelodyPatterns.realize(lifted, over: elsewhere)
    let label = "moved to \(text.prefix(14))…"
    check("\(label) produces notes", !moved.isEmpty, "\(moved.count) notes")
    check("\(label) stays monophonic",
          zip(moved, moved.dropFirst()).allSatisfy {
              $0.startBeat + $0.durationBeats <= $1.startBeat + 1e-9
          })
    check("\(label) stays in a singable register",
          moved.allSatisfy { $0.note >= 36 && $0.note <= 96 },
          "range \(moved.map(\.note).min() ?? 0)–\(moved.map(\.note).max() ?? 0)")
    check("\(label) is deterministic",
          moved == MelodyPatterns.realize(lifted, over: elsewhere))

    let report = MelodyPatterns.fitReport(for: lifted, over: elsewhere)
    print("        fit: \(report.summary)")
}

// MARK: - Fit report

print()
print("── fit report ─────────────────────────────────────────")

let clean = MelodyPatterns.fitReport(for: MelodyPatterns.guideTones, over: home)
check("a diatonic line over a 3-bar form reports no off-scale notes",
      clean.offScale == 0, clean.summary)

let awkward = try ChordProgression.parse("Cdim7 | C7alt | Cquartal | C5")
let chromatic = MelodyPatterns.fitReport(for: MelodyPatterns.arch, over: awkward)
check("a line with a chromatic approach says so somewhere",
      chromatic.offScale > 0 || chromatic.onAvoidNotes > 0 || !chromatic.isClean,
      chromatic.summary)

let uneven = MelodyPatterns.fitReport(for: MelodyPatterns.arch, over: home)
check("a 4-bar line over a 3-bar form reports that it doesn't tile",
      !uneven.tilesEvenly, uneven.summary)

print()
print("  \(roundTrips) round trips")
print(failures == 0 ? "extraction: all checks passed" : "extraction: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
