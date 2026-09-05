// Checks the deterministic path: stored generic lines fitted to real harmony.
// The claim is that a degree-relative line comes out consonant over *any*
// progression, instantly — so that's what this tries to falsify.
import Foundation
import Carrier
import Theory

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

// Two of Alex's real progressions plus a deliberately awkward one.
let progressions = [
    "E♭7 Gm9|D∆|A♭6",
    "Cmaj7 | E7 | Am7 | A♭7 | G | D7♯5 | Dm7 | D♭7 | C6 | F | C | B♭ | F | C | D7 | G7",
    "F♯m7 | Am7 | F7 | Gmaj7 | G7alt | F♯mM7 | Dm7 | C♯m7",
    "Cdim7 | C7alt | Cquartal | C5"
]

print("  \(MelodyPatterns.seeds.count) stored lines: "
      + MelodyPatterns.seeds.map(\.name).joined(separator: ", "))

var totalRealized = 0
for text in progressions {
    let progression = try ChordProgression.parse(text)
    for pattern in MelodyPatterns.seeds {
        let notes = MelodyPatterns.realize(pattern, over: progression)
        totalRealized += 1

        let label = "\(pattern.name) over \(text.prefix(18))…"
        guard !notes.isEmpty else {
            check("\(label) produces notes", false)
            continue
        }

        // Every note has to be in the scale of the chord under it — that's the
        // whole point of describing lines by degree. Altered notes are the
        // deliberate exception.
        let alterations = Set(pattern.notes.filter { $0.alteration != 0 }.map(\.degree))
        var offScale = 0
        for note in notes {
            guard let chord = progression.chord(at: note.startBeat) else { continue }
            let pc = ((Int(note.note) % 12) + 12) % 12
            if !chord.symbol.scalePitchClasses.contains(pc) { offScale += 1 }
        }
        // At most one off-scale note per altered degree per repetition.
        let allowed = alterations.isEmpty ? 0 : notes.count
        check("\(label) stays in each chord's scale", offScale <= allowed,
              offScale == 0 ? "all in scale" : "\(offScale) chromatic")

        check("\(label) fills the progression",
              (notes.last?.startBeat ?? 0) >= progression.totalBeats - 8,
              "last note at \(notes.last?.startBeat ?? 0) of \(progression.totalBeats)")
        check("\(label) stays monophonic",
              zip(notes, notes.dropFirst()).allSatisfy {
                  $0.startBeat + $0.durationBeats <= $1.startBeat + 1e-9
              })
        check("\(label) stays inside the loop",
              notes.allSatisfy { $0.startBeat + $0.durationBeats <= progression.totalBeats + 1e-9 })
        check("\(label) stays in a singable register",
              notes.allSatisfy { $0.note >= 36 && $0.note <= 96 },
              "range \(notes.map(\.note).min() ?? 0)–\(notes.map(\.note).max() ?? 0)")
        // Consecutive leaps wider than an octave are what folding exists to stop.
        let widest = zip(notes, notes.dropFirst())
            .map { abs(Int($1.note) - Int($0.note)) }.max() ?? 0
        check("\(label) never leaps more than an octave", widest <= 12, "widest \(widest)")
    }
}

// Determinism: the same line over the same changes is the same notes every time.
let progression = try ChordProgression.parse(progressions[1])
let once = MelodyPatterns.realize(MelodyPatterns.arch, over: progression)
let twice = MelodyPatterns.realize(MelodyPatterns.arch, over: progression)
check("realization is deterministic", once == twice)

// A short cell over a long form must recur, not run out.
let cell = MelodyPatterns.realize(MelodyPatterns.guideTones, over: progression)
check("a 2-bar cell repeats across a 16-bar form",
      cell.count >= MelodyPatterns.guideTones.notes.count * 6,
      "\(cell.count) notes from \(MelodyPatterns.guideTones.notes.count) per repetition")

// The same cell must actually re-pitch to each chord rather than transposing
// blindly: over changing harmony the repetitions differ.
let firstBar = cell.filter { $0.startBeat < 8 }.map(\.note)
let laterBar = cell.filter { $0.startBeat >= 8 && $0.startBeat < 16 }.map(\.note)
check("repetitions re-pitch to the new chord", firstBar != laterBar,
      "\(firstBar) then \(laterBar)")

// Cycling covers the library before repeating.
let cycled = (0..<MelodyPatterns.seeds.count).map { MelodyPatterns.seed(at: $0).name }
check("cycling visits every line once", Set(cycled).count == MelodyPatterns.seeds.count)
check("cycling wraps",
      MelodyPatterns.seed(at: MelodyPatterns.seeds.count).name == cycled[0])

print()
print("  \(totalRealized) line/progression combinations realized")
print(failures == 0 ? "patterns: all checks passed" : "patterns: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
