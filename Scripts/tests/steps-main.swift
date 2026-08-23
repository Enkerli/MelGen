// Checks lines described as moves rather than as positions.
//
// The central claim is small and checkable: a cycle of intervals whose sum isn't
// zero sequences itself. That is the whole mechanism behind Hanon's exercises,
// and here it should fall out of the representation with nothing transposing
// anything. The other claim is the Samchillian's — that the same figure over
// different harmony is the same *shape*, played on that harmony's notes.
import Foundation

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let cMajor = try ChordProgression.parse("Cmaj7 | Cmaj7 | Cmaj7 | Cmaj7")
let changes = try ChordProgression.parse("Dm7 | G7 | Cmaj7 | A7♭9")
let awkward = try ChordProgression.parse("Cdim7 | C7alt | Cquartal | C5")

// MARK: - Drift

print("── drift is the mechanism ─────────────────────────")

check("Hanon's first figure is +2 +1 +1 +1 −1 −1 −1 −1",
      StepCell.hanonRise.deltas == [2, 1, 1, 1, -1, -1, -1, -1],
      "\(StepCell.hanonRise.deltas)")
check("and its cycle sums to one step", StepCell.hanonRise.drift == 1)
check("which is what makes it sequence itself", StepCell.hanonRise.isSelfSequencing)
check("the inverted figure walks down", StepCell.hanonFall.drift == -1)
check("a turn goes nowhere", StepCell.turn.drift == 0 && !StepCell.turn.isSelfSequencing)
check("every cell says what its drift does", StepCell.all.allSatisfy { !$0.driftDescription.isEmpty })
check("the vocabulary has cells that climb, fall and stay",
      StepCell.all.contains { $0.drift > 0 } && StepCell.all.contains { $0.drift < 0 }
        && StepCell.all.contains { $0.drift == 0 })

// The claim, tested directly: the degrees climb by exactly the drift per cycle,
// and nothing anywhere transposes anything.
let hanon = MelodyStepPatterns.line(from: .hanonRise, bars: 8)
let degrees = hanon.notes.sorted { $0.startEighth < $1.startEighth }.map(\.degree)
check("Hanon's line is the figure repeated",
      Array(degrees.prefix(8)) == [0, 2, 3, 4, 5, 4, 3, 2], "\(Array(degrees.prefix(8)))")
check("and each repetition starts one step higher",
      degrees.count > 16 && degrees[8] == degrees[0] + 1 && degrees[16] == degrees[8] + 1,
      "\(degrees[0]) → \(degrees[8]) → \(degrees[16])")
check("a drift-zero cell doesn't move",
      Set(MelodyStepPatterns.line(from: .turn, bars: 8).notes.map(\.degree)).count <= 4,
      "\(Set(MelodyStepPatterns.line(from: .turn, bars: 8).notes.map(\.degree)).sorted())")

// MARK: - Walking

print()
print("── walking a cell ─────────────────────────────────")

for cell in StepCell.all {
    let pattern = MelodyStepPatterns.line(from: cell, bars: 4)
    let label = cell.name
    check("\(label) fills its bars", !pattern.notes.isEmpty && pattern.bars == 4)
    check("\(label) is monophonic before harmony",
          Set(pattern.notes.map(\.startEighth)).count == pattern.notes.count)
    check("\(label) stays inside its bars",
          pattern.notes.allSatisfy { $0.startEighth < 4 * 8 })
    check("\(label) is realized by stepping, not by folding",
          pattern.realization == .stepwise)
    check("\(label) is deterministic", MelodyStepPatterns.line(from: cell, bars: 4) == pattern)
}

// A self-sequencing cell must turn around rather than run off the instrument.
let long = MelodyStepPatterns.line(from: .hanonRise, bars: 32)
let realizedLong = MelodyPatterns.realize(long, over: cMajor)
check("a long climb turns around instead of running off the top",
      realizedLong.allSatisfy { $0.note >= 36 && $0.note <= 96 },
      "range \(realizedLong.map(\.note).min() ?? 0)–\(realizedLong.map(\.note).max() ?? 0)")
check("and it really did climb before turning",
      (long.notes.prefix(40).map(\.degree).max() ?? 0) > (long.notes.prefix(8).map(\.degree).max() ?? 0))

// MARK: - Stepwise realization

print()
print("── the Samchillian's arithmetic ───────────────────")

// The point of stepping: an interval stays an interval across a chord change.
let steppedOverChanges = MelodyPatterns.realize(hanon, over: changes)
check("a stepped line plays over changing harmony", !steppedOverChanges.isEmpty)
check("every note belongs to the chord under it",
      steppedOverChanges.allSatisfy { note in
          guard let chord = changes.chord(at: note.startBeat) else { return false }
          return chord.symbol.scalePitchClasses.contains(((Int(note.note) % 12) + 12) % 12)
      })
check("it stays in a playable register",
      steppedOverChanges.allSatisfy { $0.note >= 36 && $0.note <= 96 },
      "range \(steppedOverChanges.map(\.note).min() ?? 0)–\(steppedOverChanges.map(\.note).max() ?? 0)")
check("it climbs across the chord changes rather than restarting at each one",
      (steppedOverChanges.prefix(8).map(\.note).min() ?? 0)
        < (steppedOverChanges.dropFirst(16).prefix(8).map(\.note).min() ?? 0),
      "bar 1 from \(steppedOverChanges.prefix(8).map(\.note).min() ?? 0), "
      + "bar 3 from \(steppedOverChanges.dropFirst(16).prefix(8).map(\.note).min() ?? 0)")

// The same shape in any key — the property the instrument is built on.
func shape(_ progression: ChordProgression) -> [Int] {
    let notes = MelodyPatterns.realize(hanon, over: progression)
    return zip(notes, notes.dropFirst()).prefix(7).map { Int($1.note) - Int($0.note) }
}
check("the same figure over one chord is the same shape whatever the chord",
      shape(try ChordProgression.parse("Cmaj7 | Cmaj7 | Cmaj7 | Cmaj7")).map { $0 > 0 ? 1 : -1 }
        == shape(try ChordProgression.parse("F♯maj7 | F♯maj7 | F♯maj7 | F♯maj7")).map { $0 > 0 ? 1 : -1 },
      "the contour survives transposition")

// A wide cell has to keep its width; that's what stepwise realization is for.
let octaves = MelodyPatterns.realize(MelodyStepPatterns.line(from: .octaveCreep, bars: 4),
                                     over: cMajor)
let widest = zip(octaves, octaves.dropFirst()).map { abs(Int($1.note) - Int($0.note)) }.max() ?? 0
check("an octave leap survives realization", widest >= 12, "widest leap \(widest) semitones")

// What folding actually costs is direction, not width — a clean octave survives
// it, but a degree re-anchored against a new chord's root doesn't have to move
// the way the figure said. So the checkable claim is that a stepped line goes
// where its deltas said and a folded one is free not to.
func directionsMatch(_ pattern: MelodyPattern, over progression: ChordProgression) -> Double {
    let notes = MelodyPatterns.realize(pattern, over: progression)
    let intended = zip(pattern.notes.sorted { $0.startEighth < $1.startEighth },
                       pattern.notes.sorted { $0.startEighth < $1.startEighth }.dropFirst())
        .map { $1.degree - $0.degree }
    let actual = zip(notes, notes.dropFirst()).map { Int($1.note) - Int($0.note) }
    let pairs = zip(intended, actual).filter { $0.0 != 0 }
    guard !pairs.isEmpty else { return 1 }
    let agreeing = pairs.filter { ($0.0 > 0) == ($0.1 > 0) }.count
    return Double(agreeing) / Double(pairs.count)
}

var foldedVersion = MelodyStepPatterns.line(from: .hanonRise, bars: 8)
let steppedVersion = foldedVersion
foldedVersion.realization = .folded
let steppedAgreement = directionsMatch(steppedVersion, over: changes)
let foldedAgreement = directionsMatch(foldedVersion, over: changes)
check("a stepped line moves the way its intervals said, over changing harmony",
      steppedAgreement > 0.95, "\(Int(steppedAgreement * 100))% of moves agree")
check("and folding is free not to, which is why the mode exists",
      foldedAgreement < steppedAgreement,
      "folded \(Int(foldedAgreement * 100))%, stepped \(Int(steppedAgreement * 100))%")

// MARK: - Reading a line back as moves

print()
print("── reading a line back as moves ───────────────────")

let composed = MelodyPhrases.compose(bars: 4, seed: 9)
guard let lifted = MelodyStepPatterns.cell(from: composed, named: "lifted") else {
    print("  FAIL  a composed line reads back as a cell")
    exit(1)
}
check("a composed line reads back as a cell", lifted.deltas.count == composed.notes.count,
      "\(lifted.deltas.count) moves from \(composed.notes.count) notes")
check("the cycle closes, so repeating it is continuous", lifted.drift == 0,
      "drift \(lifted.drift)")
check("its lengths come from the line", lifted.lengths.count == composed.notes.count)
check("a single note has no moves in it",
      MelodyStepPatterns.cell(from: MelodyPattern(name: "one", bars: 1, summary: "",
                                                  notes: [PatternNote(startEighth: 0,
                                                                      lengthEighths: 1,
                                                                      degree: 0)]),
                              named: "x") == nil)

// MARK: - In the library

print()
print("── in the library ─────────────────────────────────")

let library = MelodyStepPatterns.library()
check("every cell becomes a playable line", library.count == StepCell.all.count)
check("their names are distinct", Set(library.map(\.name)).count == library.count)
for pattern in library {
    for progression in [cMajor, changes, awkward] {
        let notes = MelodyPatterns.realize(pattern, over: progression)
        check("\(pattern.name) over \(progression.text.prefix(10))… plays", !notes.isEmpty)
        check("\(pattern.name) over \(progression.text.prefix(10))… stays monophonic",
              zip(notes, notes.dropFirst()).allSatisfy {
                  $0.startBeat + $0.durationBeats <= $1.startBeat + 1e-9
              })
        check("\(pattern.name) over \(progression.text.prefix(10))… stays playable",
              notes.allSatisfy { $0.note >= 36 && $0.note <= 96 })
    }
}

// And they have to survive the round trip like anything else in the library.
for pattern in library.prefix(4) {
    let notes = MelodyPatterns.realize(pattern, over: changes)
    check("\(pattern.name) reads back as a pattern",
          MelodyPatterns.extract(from: notes, over: changes, name: "back") != nil)
}

print()
print(failures == 0 ? "steps: all checks passed" : "steps: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
