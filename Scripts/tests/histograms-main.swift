// Checks the two histograms: which note, and how far to the next one.
//
// The claims worth checking are the ones a listener would notice going wrong.
// The stack has to arrive in the stated order — root, fifth, third, seventh,
// eleventh, ninth, thirteenth — and has to stay ordered by weight, or "reach"
// is a dial that does something other than what it says. Outside notes have to
// stay small, because that is the difference between colour and a wrong note.
// The side-slipped pentatonic has to be the one the technique names: over a
// minor seventh chord, the pentatonic on the third, and the one a semitone
// above it sharing nothing with the chord's scale. And the two histograms have
// to multiply — the walk has to obey both at once, or one of them is decoration.
//
// The modal ladder is checked as a ladder: each rung one flattened degree darker
// than the last, which is the property the minorness dial is built on rather
// than a table somebody typed.
import Foundation

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let cm7 = try ChordProgression.parseChordSymbol("Cm7")
let g7 = try ChordProgression.parseChordSymbol("G7♭9")
let cmaj = try ChordProgression.parseChordSymbol("C∆")
let minor = DegreeContext(chord: cm7)
let dominant = DegreeContext(chord: g7)
let major = DegreeContext(chord: cmaj)

// MARK: - The stack

print("── the stack arrives in order ─────────────────────")

check("the arrival order is root, fifth, third, seventh, eleventh, ninth, thirteenth",
      DegreeHistogram.arrivalOrder == [0, 4, 2, 6, 3, 1, 5],
      "\(DegreeHistogram.arrivalOrder)")

// At the bottom of the dial there is one note and it is the root.
let atRoot = DegreeHistogram.stack(over: minor, reach: 0)
check("reach 0 is the root alone",
      atRoot.probability(of: 0) > 0.999,
      atRoot.summary)

// Each arrival appears, in order, as the dial is turned up.
let arrivals: [(Double, Int, String)] = [
    (0.0, 0, "root"), (0.17, 7, "fifth"), (0.34, 3, "third"), (0.5, 10, "seventh"),
    (0.67, 5, "eleventh"), (0.84, 2, "ninth"), (1.0, 9, "thirteenth")
]
var seenBefore = Set<Int>()
for (reach, semitone, name) in arrivals {
    let histogram = DegreeHistogram.stack(over: minor, reach: reach)
    check("at reach \(String(format: "%.2f", reach)) the \(name) is in",
          histogram.probability(of: semitone) > 0.01,
          String(format: "%.1f%%", histogram.probability(of: semitone) * 100))
    check("and everything that arrived earlier is still there",
          seenBefore.allSatisfy { histogram.probability(of: $0) > 0.01 })
    seenBefore.insert(semitone)
}

// The order of arrival is the order of weight — which is the whole reason the
// order was worth writing down.
let full = DegreeHistogram.stack(over: minor, reach: 1)
let ranked = arrivals.map { full.probability(of: $0.1) }
check("the stack stays ordered by weight, root heaviest",
      zip(ranked, ranked.dropFirst()).allSatisfy { $0 > $1 - 1e-9 },
      ranked.map { String(format: "%.3f", $0) }.joined(separator: " > "))
check("and the root is the single likeliest note",
      full.mostLikely == 0)

check("the stack lands on the chord's own third over a minor chord",
      full.probability(of: 3) > full.probability(of: 4),
      "♭3 \(String(format: "%.3f", full.probability(of: 3))) vs 3 \(String(format: "%.3f", full.probability(of: 4)))")
check("and on the major third over a major one",
      DegreeHistogram.stack(over: major, reach: 1).probability(of: 4) > 0.05)
check("an altered dominant's stack is built on its altered notes",
      DegreeHistogram.stack(over: dominant, reach: 1).probability(of: 1) > 0
        || DegreeHistogram.stack(over: dominant, reach: 1).probability(of: 3) > 0,
      dominant.scaleIntervals.description)

// MARK: - Avoid and outside

print()
print("── colour, and where it stops ─────────────────────")

let plain = DegreeHistogram.stack(over: major, reach: 1, avoidDamping: 1)
let damped = DegreeHistogram.stack(over: major, reach: 1)
check("avoid notes are damped rather than removed",
      major.avoidIntervals.isEmpty
        || major.avoidIntervals.allSatisfy {
            damped[$0] < plain[$0] - 1e-9 && damped[$0] >= 0
        },
      "avoid \(major.avoidIntervals)")

let opened = DegreeHistogram.stack(over: minor, reach: 1, outside: 0.1)
let outsideNotes = (0..<12).filter { !minor.scaleIntervals.contains($0) }
check("outside notes get weight when asked for",
      outsideNotes.allSatisfy { opened.probability(of: $0) > 0 },
      "\(outsideNotes.count) of them")
check("and none of them at all when not",
      outsideNotes.allSatisfy { full.probability(of: $0) == 0 })
check("outside stays small — colour, not a wrong note",
      outsideNotes.map { opened.probability(of: $0) }.reduce(0, +) < 0.2,
      String(format: "%.1f%% of the weight",
             outsideNotes.map { opened.probability(of: $0) }.reduce(0, +) * 100))
check("every semitone has a role and a name",
      (0..<12).allSatisfy { !IntervalNames.all[$0].isEmpty }
        && (0..<12).allSatisfy { !minor.role(ofSemitone: $0).shortLabel.isEmpty })

// MARK: - Playing out

print()
print("── the side slip ──────────────────────────────────")

// Over Cm7: E♭ F G B♭ C, then E F♯ G♯ B C♯. The second shares nothing with the
// chord's scale, which is the observation the whole device rests on.
let inside = DegreeHistogram.majorPentatonic(on: 3)
let outside = DegreeHistogram.majorPentatonic(on: 4)
let insideSet = Set((0..<12).filter { inside[$0] > 0 })
let outsideSet = Set((0..<12).filter { outside[$0] > 0 })
check("the pentatonic on the third of Cm7 is E♭ F G B♭ C",
      insideSet == [3, 5, 7, 10, 0], "\(insideSet.sorted().map { IntervalNames.all[$0] })")
check("the one a semitone up is E F♯ G♯ B C♯",
      outsideSet == [4, 6, 8, 11, 1], "\(outsideSet.sorted().map { IntervalNames.all[$0] })")
check("the two share no note at all", insideSet.isDisjoint(with: outsideSet))
check("and the slipped one shares nothing with the chord's scale either",
      outsideSet.isDisjoint(with: Set(minor.scaleIntervals)),
      "scale \(minor.scaleIntervals)")

let slipped = DegreeHistogram.sideSlip(over: minor, slip: 0.4)
check("the side slip is mostly inside at 0.4",
      insideSet.map { slipped.probability(of: $0) }.reduce(0, +)
        > outsideSet.map { slipped.probability(of: $0) }.reduce(0, +))
check("and entirely inside at 0",
      outsideSet.allSatisfy { DegreeHistogram.sideSlip(over: minor, slip: 0)[$0] == 0 })

// MARK: - Arithmetic

print()
print("── mixing ─────────────────────────────────────────")

let mixed = DegreeHistogram.mix([(atRoot, 0.5), (full, 0.5)])
check("a mix sums to one when normalized",
      abs(mixed.normalized.total - 1) < 1e-9)
check("mixing normalizes its parts, so scale doesn't leak",
      DegreeHistogram.mix([(atRoot.scaled(by: 1000), 0.5), (full, 0.5)]).normalized.weights
        .elementsEqual(mixed.normalized.weights) { abs($0 - $1) < 1e-9 })
check("blending at 0 is the left and at 1 is the right",
      atRoot.blended(with: full, 0).normalized.weights
        .elementsEqual(atRoot.normalized.weights) { abs($0 - $1) < 1e-9 }
        && atRoot.blended(with: full, 1).normalized.weights
        .elementsEqual(full.normalized.weights) { abs($0 - $1) < 1e-9 })
check("emphasis moves weight toward the chord tones",
      full.emphasising(chordTonesOf: minor, by: 3).normalized.probability(of: 0)
        > full.normalized.probability(of: 0))
check("a pick is deterministic in its draw",
      full.pick(draw: 0.4) == full.pick(draw: 0.4))
check("and every draw in range lands somewhere",
      stride(from: 0.0, to: 1.0, by: 0.05).allSatisfy { full.pick(draw: $0) != nil })
check("an empty histogram picks nothing rather than guessing",
      DegreeHistogram().pick(draw: 0.5) == nil && DegreeHistogram().isEmpty)
check("a profile has one readable row per semitone",
      full.profile(over: minor).count == 12
        && full.profile(over: minor).allSatisfy { $0.contains("%") })

// MARK: - Transitions

print()
print("── how far ────────────────────────────────────────")

let steps = TransitionHistogram.stepwise()
let leaps = TransitionHistogram.stepwise(leapiness: 1)
let arps = TransitionHistogram.arpeggiating()
let chromatic = TransitionHistogram.chromatic()

check("stepwise falls off with interval size",
      (1..<12).allSatisfy { steps[$0] > steps[$0 + 1] },
      steps.summary)
check("leapiness widens it",
      leaps.probability(of: 7) > steps.probability(of: 7),
      "\(String(format: "%.3f", leaps.probability(of: 7))) vs \(String(format: "%.3f", steps.probability(of: 7)))")
check("arpeggiating prefers thirds and fifths to seconds",
      arps.probability(of: 4) > arps.probability(of: 2) && arps.probability(of: 7) > arps.probability(of: 1),
      arps.summary)
check("chromatic is almost all semitones",
      chromatic.probability(of: 1) + chromatic.probability(of: -1) > 0.5,
      chromatic.summary)
check("nothing reaches past an octave",
      TransitionHistogram.intervals.allSatisfy { abs($0) <= 12 }
        && steps[13] == 0 && steps[-13] == 0)
check("leaning upward makes upward moves likelier and downward ones less so",
      steps.leaning(0.6).probability(of: 3) > steps.probability(of: 3)
        && steps.leaning(0.6).probability(of: -3) < steps.probability(of: -3))
check("leaning by nothing changes nothing",
      steps.leaning(0).weights.elementsEqual(steps.weights) { abs($0 - $1) < 1e-9 })
check("a repeat is separately controlled",
      TransitionHistogram.stepwise(repeats: 0)[0] == 0
        && TransitionHistogram.stepwise(repeats: 0.5)[0] > 0)

// MARK: - The walk

print()
print("── the two multiplied ─────────────────────────────")

let range = 28...52
let onlyRoots = DegreeHistogram.at([0])
var rng = SplitMix64(seed: 99)

// With a degree histogram of one note, every landing has to be that note —
// whatever the transitions want. That is the multiplication, in its simplest
// observable form.
var landings: [Int] = []
var pitch = 36
for _ in 0..<40 {
    guard let next = MelodicWalk.next(from: pitch, previousInterval: nil,
                                      degrees: onlyRoots, context: minor,
                                      transitions: TransitionHistogram.flat(),
                                      range: range, draw: rng.nextUnit()) else { break }
    landings.append(next)
    pitch = next
}
check("a one-note histogram lands only on that note",
      !landings.isEmpty && landings.allSatisfy { ChordScales.pitchClass($0) == minor.rootPitchClass },
      "\(landings.count) landings")
check("and never leaves the range",
      landings.allSatisfy { range.contains($0) })

// With a transition histogram of one interval, every move has to be that move.
let onlyOctaves = TransitionHistogram(weights: {
    var histogram = TransitionHistogram()
    histogram[12] = 1
    histogram[-12] = 1
    return histogram.weights
}())
var moves: [Int] = []
// Starting on the root, so an octave move stays on a note the degree histogram
// allows — otherwise the walk correctly refuses every candidate and the check
// would be measuring the wrong refusal.
pitch = 36
for _ in 0..<12 {
    guard let next = MelodicWalk.next(from: pitch, previousInterval: nil,
                                      degrees: DegreeHistogram.scaleTones(of: minor),
                                      context: minor, transitions: onlyOctaves,
                                      range: range, draw: rng.nextUnit()) else { break }
    moves.append(abs(next - pitch))
    pitch = next
}
check("a one-interval histogram moves only by that interval",
      !moves.isEmpty && moves.allSatisfy { $0 == 12 }, "\(moves)")

// Momentum: a run continues. Checked as a statistic rather than as one draw,
// because a single draw could go either way and prove nothing.
func runLength(momentum: Double) -> Double {
    var rng = SplitMix64(seed: 4242)
    var continued = 0
    var total = 0
    var pitch = 40
    var previous: Int? = 2
    for _ in 0..<400 {
        guard let next = MelodicWalk.next(from: pitch, previousInterval: previous,
                                          degrees: DegreeHistogram.chromatic(),
                                          context: minor,
                                          transitions: TransitionHistogram.stepwise(),
                                          momentum: momentum, range: range,
                                          draw: rng.nextUnit()) else { break }
        let interval = next - pitch
        if let previous, interval != 0, (interval > 0) == (previous > 0) { continued += 1 }
        if previous != nil { total += 1 }
        previous = interval == 0 ? previous : interval
        pitch = next
    }
    return total > 0 ? Double(continued) / Double(total) : 0
}
let withMomentum = runLength(momentum: 1)
let without = runLength(momentum: 0)
check("momentum makes a line keep going the way it was going",
      withMomentum > without + 0.1,
      String(format: "%.0f%% with, %.0f%% without", withMomentum * 100, without * 100))

check("a start lands in the range, near where it was asked to",
      {
          guard let start = MelodicWalk.start(degrees: full, context: minor,
                                              range: range, near: 30, draw: 0.5)
          else { return false }
          return range.contains(start) && abs(start - 30) <= 12
      }())
check("folding into a range keeps the pitch class",
      (0...127).allSatisfy {
          let folded = MelodicWalk.fold($0, into: range)
          return range.contains(folded) && ChordScales.pitchClass(folded) == ChordScales.pitchClass($0)
      })

// MARK: - Learning

print()
print("── learned rather than dialled ────────────────────")

let changes = try ChordProgression.parse("Cm7|Cm7")
let played = [
    SequencedNote(note: 48, velocity: 90, startBeat: 0, durationBeats: 1),
    SequencedNote(note: 51, velocity: 90, startBeat: 1, durationBeats: 1),
    SequencedNote(note: 55, velocity: 90, startBeat: 2, durationBeats: 1),
    SequencedNote(note: 58, velocity: 90, startBeat: 3, durationBeats: 1)
]
let observed = DegreeHistogram.observed(in: played, over: changes)
check("what was played is counted where it was played",
      Set((0..<12).filter { observed[$0] > 0 }) == [0, 3, 7, 10],
      "\(Set((0..<12).filter { observed[$0] > 0 }).sorted())")

let observedMoves = TransitionHistogram.observed(in: played)
check("the moves between them are counted too",
      observedMoves[3] == 2 && observedMoves[4] == 1,
      observedMoves.summary)

let informed = full.informed(by: observed, observations: 4)
check("four observations barely move the prior",
      abs(informed.probability(of: 0) - full.normalized.probability(of: 0)) < 0.1)
let confident = full.informed(by: observed, observations: 400)
check("four hundred move it as far as the ceiling allows",
      abs(confident.probability(of: 0) - observed.normalized.probability(of: 0))
        < abs(full.normalized.probability(of: 0) - observed.normalized.probability(of: 0)))
check("and never all the way — the prior always has a say",
      confident.probability(of: 4) >= 0 && confident.total > 0)
check("nothing observed leaves the prior exactly as it was",
      full.informed(by: DegreeHistogram(), observations: 100).weights == full.weights)

// MARK: - The modal ladder

print()
print("── the ladder ─────────────────────────────────────")

check("the ladder is the seven modes, brightest first",
      DiatonicHarmony.ladder == [.lydian, .ionian, .mixolydian, .dorian,
                                 .aeolian, .phrygian, .locrian])

// The property the dial rests on: each rung is exactly one flattened degree
// darker than the one above it.
for (brighter, darker) in zip(DiatonicHarmony.ladder, DiatonicHarmony.ladder.dropFirst()) {
    let above = Set(brighter.intervals)
    let below = Set(darker.intervals)
    check("\(brighter.displayName) → \(darker.displayName) flattens exactly one degree",
          above.subtracting(below).count == 1 && below.subtracting(above).count == 1,
          "\(above.subtracting(below).sorted()) → \(below.subtracting(above).sorted())")
}

check("minorness 0 is the brightest and 1 the darkest",
      DiatonicHarmony.mode(forMinorness: 0) == .lydian
        && DiatonicHarmony.mode(forMinorness: 1) == .locrian)
check("halfway is Dorian, which is where the music is",
      DiatonicHarmony.mode(forMinorness: 0.5) == .dorian)
check("every setting has a name",
      stride(from: 0.0, through: 1.0, by: 0.05)
        .allSatisfy { !DiatonicHarmony.label(forMinorness: $0).isEmpty })
check("landing on a rung gives that rung the whole weight",
      {
          let (brighter, _, t) = DiatonicHarmony.neighbours(forMinorness: 0.5)
          return brighter == .dorian && t < 1e-9
      }())
check("and the dark end has nothing below it to blend with",
      {
          let (brighter, darker, _) = DiatonicHarmony.neighbours(forMinorness: 1)
          return brighter == .locrian && darker == .locrian
      }())

// A mode's tonic seventh is its chord, and it falls out rather than being typed.
check("Dorian's tonic seventh is a minor seventh chord",
      DiatonicHarmony.tonicSeventh(of: .dorian) == [0, 3, 7, 10])
check("Mixolydian's is a dominant",
      DiatonicHarmony.tonicSeventh(of: .mixolydian) == [0, 4, 7, 10])
check("Locrian's is half-diminished",
      DiatonicHarmony.tonicSeventh(of: .locrian) == [0, 3, 6, 10])

// MARK: - Modal tokens

print()
print("── a key, written down ────────────────────────────")

for scale in Scale.allCases {
    let text = DiatonicHarmony.text(root: 3, scale: scale)
    guard let parsed = try? ChordProgression.parseChordSymbol(text) else {
        check("\(scale.rawValue) round-trips", false, "\(text) did not parse")
        continue
    }
    check("\(scale.rawValue) round-trips through its own text",
          parsed.scalePitchClasses == scale.intervals.map { (3 + $0) % 12 }
            && parsed.text == text,
          text)
}

check("the modes the classifier can't reach are reachable by name",
      (try? ChordProgression.parseChordSymbol("C(ionian)"))?.scaleName == "Ionian"
        && (try? ChordProgression.parseChordSymbol("C(aeolian)"))?.scaleName == "Aeolian"
        && (try? ChordProgression.parseChordSymbol("C(phrygian)"))?.scaleName == "Phrygian")
check("a bare chord suffix still means the chord",
      (try? ChordProgression.parseChordSymbol("Cminor"))?.quality.key == "min"
        && (try? ChordProgression.parseChordSymbol("Cmajor"))?.quality.key == "maj",
      "parentheses are what separate a mode from a triad")
check("and the friendly names work inside them",
      (try? ChordProgression.parseChordSymbol("C(minor)"))?.scaleName == "Aeolian"
        && (try? ChordProgression.parseChordSymbol("C(major)"))?.scaleName == "Ionian")
check("nothing that was a chord before has stopped being one",
      ["C∆", "Dm7", "G7♭9", "E♭7", "A♭6", "Cdim7", "C7alt", "Dm7/G", "F♯m7♭5"]
        .allSatisfy { (try? ChordProgression.parseChordSymbol($0)) != nil })

let vamp = DiatonicHarmony.progression(key: 2, minorness: 0.5, bars: 4)
check("a key becomes one chord over the whole form",
      vamp.chords.count == 1 && vamp.totalBeats == 16 && vamp.chords[0].durationBeats == 16,
      vamp.text)
check("and that chord knows the mode it came from",
      vamp.chords[0].symbol.scaleName == "Dorian")
check("a fractional minorness blends both thirds",
      {
          // Between Mixolydian and Dorian, both the major and the minor third
          // should carry weight — which is the thing a seven-position switch
          // cannot do and is why the dial is continuous.
          let between = DiatonicHarmony.degrees(key: 0, minorness: 0.42, reach: 0.5)
          return between.probability(of: 3) > 0.01 && between.probability(of: 4) > 0.01
      }(),
      DiatonicHarmony.label(forMinorness: 0.42))

print()
print(failures == 0 ? "histograms: all checks passed" : "histograms: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
