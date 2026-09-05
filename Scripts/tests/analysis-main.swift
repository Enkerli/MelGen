// Checks take measurement (variety, harmonic roles) and the dead-air guard,
// including a replay of the real take whose two-bar hole the first version of
// the guard failed to touch.
import Foundation
import Carrier
import Theory

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

// MARK: - Dead air

// The exact shape from the exported history: a 4-beat note at beat 36, then
// nothing until beat 48. The first guard left this untouched, because the note
// had already reached its 4-beat hold cap and had no headroom.
let holed: [SequencedNote] = [
    SequencedNote(note: 60, velocity: 90, startBeat: 32, durationBeats: 2),
    SequencedNote(note: 64, velocity: 90, startBeat: 36, durationBeats: 4),
    SequencedNote(note: 67, velocity: 90, startBeat: 48, durationBeats: 2),
]
let capped = DeadAir.cap(holed, totalBeats: 64)
let heldNote = capped[1]
check("a note already at the old cap is now extended",
      heldNote.durationBeats > 4, "\(heldNote.durationBeats) beats")
// One note can't absorb eight beats on its own — extending it to the two-bar cap
// still leaves a bar. That residue is what hole-filling exists for, and the two
// run together in the real pipeline; see the combined check below.
let remainingGap = capped[2].startBeat - (heldNote.startBeat + heldNote.durationBeats)
check("extending alone leaves a residue, as documented",
      remainingGap > 2, "gap still \(remainingGap) after extending to the cap")
check("the extended note stays within two bars",
      heldNote.durationBeats <= 8 + 1e-9, "\(heldNote.durationBeats)")

// The contract, stated: every gap ends up at or under maxRest unless the note
// before it hit maxHold.
func honoursContract(_ notes: [SequencedNote], totalBeats: Double,
                     maxRest: Double = 2, maxHold: Double = 8) -> Bool {
    let out = DeadAir.cap(notes, totalBeats: totalBeats,
                          maxRest: maxRest, maxHold: maxHold)
    for (index, note) in out.enumerated() {
        let nextStart = index + 1 < out.count ? out[index + 1].startBeat : totalBeats
        let gap = nextStart - (note.startBeat + note.durationBeats)
        if gap > maxRest + 1e-9 && note.durationBeats < maxHold - 1e-9 { return false }
    }
    return true
}
check("contract holds for the reported case", honoursContract(holed, totalBeats: 64))
check("contract holds for a very long hole", honoursContract([
    SequencedNote(note: 60, velocity: 90, startBeat: 0, durationBeats: 0.5),
    SequencedNote(note: 62, velocity: 90, startBeat: 30, durationBeats: 0.5),
], totalBeats: 32))
check("contract holds for a line with no holes", honoursContract((0..<8).map {
    SequencedNote(note: 60, velocity: 90, startBeat: Double($0), durationBeats: 1)
}, totalBeats: 8))

// MARK: - Hole filling

let progression = try ChordProgression.parse(
    "F♯m7 | Am7 | F7 | Gmaj7 | G7alt | F♯mM7 | Dm7 | C♯m7 | "
    + "Dmaj7 | Gmaj7 | F♯m7 | D | G♯m7♭5 | C♯7♭9 | F♯m69 | F♯m7")
let sparse: [SequencedNote] = [
    SequencedNote(note: 66, velocity: 90, startBeat: 0, durationBeats: 1),
    SequencedNote(note: 69, velocity: 90, startBeat: 2, durationBeats: 1),
    // bars 2-13 empty
    SequencedNote(note: 71, velocity: 90, startBeat: 56, durationBeats: 1),
]
let patched = MelodyPatterns.fillHoles(in: sparse, over: progression,
                                       pattern: MelodyPatterns.arch)
check("a long hole is filled from the library", patched.count > sparse.count,
      "\(sparse.count) → \(patched.count) notes")
check("the model's own notes are kept",
      sparse.allSatisfy { original in patched.contains { $0.startBeat == original.startBeat } })
check("filling stays inside the progression",
      patched.allSatisfy { $0.startBeat + $0.durationBeats <= progression.totalBeats + 0.001 })
check("filled notes fit the harmony under them",
      patched.allSatisfy { note in
          guard let chord = progression.chord(at: note.startBeat) else { return false }
          let pc = ((Int(note.note) % 12) + 12) % 12
          return chord.symbol.scalePitchClasses.contains(pc)
              || chord.symbol.tonePitchClasses.contains(pc)
      })
// Covering the whole progression with one-beat gaps: phrasing, not holes.
let evenlySpaced = (0..<32).map {
    SequencedNote(note: 60, velocity: 90, startBeat: Double($0) * 2, durationBeats: 1)
}
check("a line with only phrasing rests is left alone",
      MelodyPatterns.fillHoles(in: evenlySpaced, over: progression,
                               pattern: MelodyPatterns.arch).count == evenlySpaced.count)

// The combination, in the order the generator runs them: the reported hole is
// filled, and nothing is left that reads as the line having stopped.
let pipeline = DeadAir.cap(
    MelodyExpression.ensureBreathing(
        MelodyPatterns.fillHoles(in: holed, over: progression, pattern: MelodyPatterns.arch),
        totalBeats: 64),
    totalBeats: 64)
var worstGap = 0.0
for (index, note) in pipeline.enumerated() {
    let nextStart = index + 1 < pipeline.count ? pipeline[index + 1].startBeat : 64
    worstGap = max(worstGap, nextStart - (note.startBeat + note.durationBeats))
}
check("the reported two-bar hole is gone once holes are filled",
      worstGap <= 2 + 1e-9, "worst gap now \(worstGap)")
check("filling kept the model's notes", pipeline.count > holed.count,
      "\(holed.count) → \(pipeline.count)")

// MARK: - Variety

let ostinato = (0..<16).map {
    SequencedNote(note: UInt8(60 + ($0 % 2) * 2), velocity: 90,
                  startBeat: Double($0) * 0.5, durationBeats: 0.5)
}
let varied: [SequencedNote] = [
    SequencedNote(note: 60, velocity: 90, startBeat: 0.0, durationBeats: 1.5),
    SequencedNote(note: 67, velocity: 90, startBeat: 1.5, durationBeats: 0.5),
    SequencedNote(note: 65, velocity: 90, startBeat: 2.5, durationBeats: 1.0),
    SequencedNote(note: 62, velocity: 90, startBeat: 4.0, durationBeats: 2.0),
    SequencedNote(note: 71, velocity: 90, startBeat: 6.5, durationBeats: 0.5),
    SequencedNote(note: 69, velocity: 90, startBeat: 7.0, durationBeats: 1.0),
]
let flat = MelodyAnalyser.analyse(ostinato, over: progression)
let rich = MelodyAnalyser.analyse(varied, over: progression)
check("an ostinato scores low", flat.varietyScore < 0.4,
      "\(Int(flat.varietyScore * 100))%")
check("a varied line scores higher than an ostinato",
      rich.varietyScore > flat.varietyScore,
      "\(Int(rich.varietyScore * 100))% vs \(Int(flat.varietyScore * 100))%")
check("an ostinato is detected as self-similar", flat.selfSimilarity > 0.5,
      "\(Int(flat.selfSimilarity * 100))%")
check("scores stay in range",
      (0...1).contains(flat.varietyScore) && (0...1).contains(rich.varietyScore))
check("a single note doesn't crash or score",
      MelodyAnalyser.analyse([ostinato[0]], over: progression).varietyScore == 0)

// MARK: - Harmonic roles

// F♯m7 over bar 1: F♯ A C♯ E are chord tones, dorian adds G♯ B D♯.
let roleProbe = try ChordProgression.parse("F♯m7")
func role(_ midi: UInt8) -> HarmonicRole {
    MelodyAnalyser.role(of: SequencedNote(note: midi, velocity: 90, startBeat: 0, durationBeats: 1),
                        in: roleProbe)
}
check("a chord tone is recognised", role(66) == .chordTone, "F♯ → \(role(66))")
check("the seventh is a chord tone", role(76) == .chordTone, "E → \(role(76))")
check("a scale tone that isn't in the chord is colour or avoid",
      [.colour, .avoid].contains(role(68)), "G♯ → \(role(68))")
check("a note outside the scale is flagged off-scale",
      role(67) == .offScale, "G → \(role(67))")

let counted = MelodyAnalyser.analyse(varied, over: progression)
check("every note is classified exactly once",
      counted.chordTones + counted.colourTones + counted.avoidNotes + counted.offScaleNotes
        == varied.count,
      "\(counted.chordTones)/\(counted.colourTones)/\(counted.avoidNotes)/\(counted.offScaleNotes)")
check("notes worth reviewing are counted",
      counted.notesToReview == counted.avoidNotes + counted.offScaleNotes)
check("the summary is readable", counted.summary.contains("variety"), counted.summary)

print()
// Measuring a take twice has to give the same number to the last bit: the
// history is sorted by these, and a score that wobbles in its final digits
// reorders a list for no reason anybody can see.
let stableProgression = try ChordProgression.parse("Dm7 | G7 | Cmaj7 | A7♭9")
let stableNotes = MelodyPatterns.realize(MelodyPhrases.compose(bars: 4, seed: 3),
                                         over: stableProgression)
let firstPass = MelodyAnalyser.analyse(stableNotes, over: stableProgression)
check("a take measures the same way twice",
      (1...5).allSatisfy { _ in
          MelodyAnalyser.analyse(stableNotes, over: stableProgression) == firstPass
      })

print(failures == 0 ? "analysis: all checks passed" : "analysis: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
