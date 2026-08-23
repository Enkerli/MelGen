// Checks that composed phrases are phrases.
//
// The complaint this answers is that variety was being sought in the wrong
// place: a line of five notes a bar and a line of three notes a bar are equally
// dull if every note is an eighth and every two bars are the same two bars. So
// what's asserted here is *gesture* — that note lengths differ, that onsets
// aren't all on the beat, that phrases breathe, that a line contains more than
// one figure, and that two seeds are two ideas rather than one idea twice.
import Foundation

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let progressions = [
    "Dm7 | G7 | Cmaj7 | A7♭9 | Dm7 | G7 | Cmaj7 | Cmaj7",
    "E♭7 Gm9|D∆|A♭6",
    "Cdim7 | C7alt | Cquartal | C5"
]

// MARK: - The vocabulary itself

print("── the gesture vocabulary ─────────────────────────")

check("no two rhythms are the same figure",
      Set(GestureRhythm.all.map { "\($0.positions)|\($0.lengths)" }).count == GestureRhythm.all.count)
check("the rhythms cover a real range of note lengths",
      Set(GestureRhythm.all.flatMap(\.lengths)).count >= 4,
      "lengths \(Set(GestureRhythm.all.flatMap(\.lengths)).sorted())")
check("some rhythms start off the beat",
      GestureRhythm.all.contains { $0.positions.contains { !$0.isMultiple(of: 2) } })
check("most rhythms leave air after them",
      GestureRhythm.all.filter { $0.trailingRest > 0 }.count * 2 >= GestureRhythm.all.count,
      "\(GestureRhythm.all.filter { $0.trailingRest > 0 }.count) of \(GestureRhythm.all.count)")

for contour in GestureContour.allCases {
    let offsets = contour.offsets(count: 4)
    check("\(contour.label) gives one offset per note", offsets.count == 4)
    check("\(contour.label) stays inside a reasonable span",
          (offsets.max() ?? 0) - (offsets.min() ?? 0) <= 8,
          "\(offsets)")
}
check("only an enclosure asks for a chromatic note",
      GestureContour.allCases.filter { $0.alterations(count: 4).contains { $0 != 0 } } == [.enclose])
check("inverting a shape turns it over",
      MelodyGesture(rhythm: .dotted, contour: .ascend, role: .statement).inverted.contour == .descend)

// MARK: - Composed lines

print()
print("── composed lines ─────────────────────────────────")

var everyLength = Set<Int>()
var everyFigure = Set<String>()

for seed in (1...24).map(UInt64.init) {
    let pattern = MelodyPhrases.compose(bars: 8, seed: seed)
    let label = "seed \(seed)"
    everyLength.formUnion(pattern.notes.map(\.lengthEighths))
    everyFigure.insert(pattern.name)

    guard !pattern.notes.isEmpty else {
        check("\(label) composes something", false)
        continue
    }

    // Rhythm. This is the whole point, so it's asserted hardest.
    let lengths = Set(pattern.notes.map(\.lengthEighths))
    check("\(label) uses more than one note length", lengths.count >= 3,
          "lengths \(lengths.sorted())")

    let onsets = pattern.notes.map(\.startEighth)
    check("\(label) doesn't put everything on the beat",
          onsets.contains { !$0.isMultiple(of: 2) })

    // Breath. A phrase that never stops isn't a phrase.
    let rests = pattern.notes.filter { $0.restAfterEighths > 0 }.count
    check("\(label) breathes", rests >= 2, "\(rests) figures end with air")

    // Structure.
    check("\(label) is monophonic before it meets any harmony",
          Set(onsets).count == onsets.count)
    check("\(label) stays inside its bars",
          onsets.allSatisfy { $0 < pattern.bars * 8 })
    check("\(label) is deterministic",
          MelodyPhrases.compose(bars: 8, seed: seed) == pattern)
}

check("different seeds are different ideas, not one idea twice",
      everyFigure.count >= 8, "\(everyFigure.count) distinct figures across 24 seeds")
check("the corpus of composed lines spans the rhythmic vocabulary",
      everyLength.count >= 4, "lengths \(everyLength.sorted())")

// The failure that started all this: 98 takes containing 60 distinct lines.
var realizedLines = Set<String>()
let jazz = try ChordProgression.parse(progressions[0])
for seed in (1...40).map(UInt64.init) {
    let notes = MelodyPatterns.realize(MelodyPhrases.compose(bars: 8, seed: seed), over: jazz)
    realizedLines.insert(notes.map { "\($0.note):\(Int($0.startBeat * 2))" }.joined(separator: ","))
}
check("forty composed lines are forty lines", realizedLines.count == 40,
      "\(realizedLines.count) distinct")

// MARK: - Over real harmony

print()
print("── composed lines over real changes ───────────────")

for text in progressions {
    let progression = try ChordProgression.parse(text)
    for seed in (1...6).map(UInt64.init) {
        let pattern = MelodyPhrases.compose(bars: 8, seed: seed)
        let notes = MelodyPatterns.realize(pattern, over: progression)
        let label = "seed \(seed) over \(text.prefix(12))…"

        check("\(label) plays", !notes.isEmpty)
        check("\(label) stays monophonic",
              zip(notes, notes.dropFirst()).allSatisfy {
                  $0.startBeat + $0.durationBeats <= $1.startBeat + 1e-9
              })
        check("\(label) stays in a singable register",
              notes.allSatisfy { $0.note >= 36 && $0.note <= 96 })
        check("\(label) never leaps more than an octave",
              (zip(notes, notes.dropFirst()).map { abs(Int($1.note) - Int($0.note)) }.max() ?? 0) <= 12)

        // A composed line has to survive the round trip like any other, or it
        // can't be curated and kept.
        check("\(label) reads back as a pattern",
              MelodyPatterns.extract(from: notes, over: progression, name: "x") != nil)
    }
}

// MARK: - Style leaning

print()
print("── leaning on the learned style ───────────────────")

// A style is a lean, not a rule: a corpus that never syncopated must not make
// syncopation impossible, or the library can only ever narrow.
var straight = LearnedStyle()
straight.takeCount = 12
straight.noteCount = 200
straight.offbeatShare = 0
straight.durationShares = [2: 0.9, 4: 0.1]

var offbeat = straight
offbeat.offbeatShare = 0.9

func offbeatRate(style: LearnedStyle) -> Double {
    var offbeats = 0, total = 0
    for seed in (1...40).map(UInt64.init) {
        let pattern = MelodyPhrases.compose(bars: 8, seed: seed, style: style)
        offbeats += pattern.notes.filter { !$0.startEighth.isMultiple(of: 2) }.count
        total += pattern.notes.count
    }
    return Double(offbeats) / Double(max(1, total))
}

let straightRate = offbeatRate(style: straight)
let offbeatRateValue = offbeatRate(style: offbeat)
check("a syncopated style composes more offbeats than a straight one",
      offbeatRateValue > straightRate,
      "\(Int(straightRate * 100))% vs \(Int(offbeatRateValue * 100))%")
check("but a straight style doesn't forbid syncopation",
      straightRate > 0.02, "\(Int(straightRate * 100))% still offbeat")

print()
print(failures == 0 ? "phrases: all checks passed" : "phrases: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
