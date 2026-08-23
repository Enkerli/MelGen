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

    // Rhythm. This is the whole point, so it's asserted hardest — but per line
    // the honest floor is two: a line built entirely on an uneven-pair figure has
    // exactly two note lengths and is not thereby monotonous. The corpus-wide
    // check below is where the vocabulary's width is actually asserted.
    let lengths = Set(pattern.notes.map(\.lengthEighths))
    check("\(label) uses more than one note length", lengths.count >= 2,
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

// And they have to differ in *architecture*, not only in which figure they're
// built on — two lines made of different cells but laid out identically sound
// like one another, which is what "it loops through the same" meant.
var architectures = Set<String>()
for seed in (1...24).map(UInt64.init) {
    let summary = MelodyPhrases.compose(bars: 8, seed: seed).summary
    for word in ["callAnswer", "aaba", "pairs", "through"] where summary.contains(word) {
        architectures.insert(word)
    }
}
check("and they differ in how they're laid out, not only in what they're made of",
      architectures.count >= 3, "\(architectures.sorted())")
check("the corpus of composed lines spans the rhythmic vocabulary",
      everyLength.count >= 5, "lengths \(everyLength.sorted())")

// The note-duration setting shaped the model's prompt and did nothing at all to
// a composed line, which made it look broken from the source that answers
// instantly.
for palette in DurationPalette.allCases {
    var lengths = Set<Int>()
    for seed in (1...12).map(UInt64.init) {
        lengths.formUnion(MelodyPhrases.compose(bars: 8, seed: seed, palette: palette)
            .notes.map(\.lengthEighths))
    }
    check("note duration \(palette.label) shapes a composed line", !lengths.isEmpty,
          "lengths \(lengths.sorted())")
}
var evenLengths = Set<Int>(), mixedLengths = Set<Int>()
for seed in (1...16).map(UInt64.init) {
    evenLengths.formUnion(MelodyPhrases.compose(bars: 8, seed: seed, palette: .even)
        .notes.map(\.lengthEighths))
    mixedLengths.formUnion(MelodyPhrases.compose(bars: 8, seed: seed, palette: .mixed)
        .notes.map(\.lengthEighths))
}
check("and Even is narrower than Mixed", evenLengths.count < mixedLengths.count,
      "\(evenLengths.sorted()) against \(mixedLengths.sorted())")

// A template has to shape a composed line too, or it's a prompt-only idea.
var longToneLengths = Set<Int>(), runningLengths = Set<Int>()
for seed in (1...16).map(UInt64.init) {
    longToneLengths.formUnion(
        MelodyPhrases.compose(bars: 8, seed: seed,
                              preferring: MelGenTemplates.line[0].gestureRhythms)
            .notes.map(\.lengthEighths))
    runningLengths.formUnion(
        MelodyPhrases.compose(bars: 8, seed: seed,
                              preferring: MelGenTemplates.line[1].gestureRhythms)
            .notes.map(\.lengthEighths))
}
check("a long-tone template composes longer notes than a running-eighths one",
      (longToneLengths.max() ?? 0) >= (runningLengths.max() ?? 0),
      "\(longToneLengths.sorted()) against \(runningLengths.sorted())")

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

// MARK: - Templates have to differ

print()
print("── nine templates, or one template with nine names ───")

/// A template's average measured profile over several seeds.
func profile(of template: MelGenTemplate) -> PatternProfile {
    var total = PatternProfile()
    var count = 0.0
    for seed in (1...8).map(UInt64.init) {
        let measured = PatternProfile.of(MelodyPhrases.compose(
            bars: 8, seed: seed,
            preferring: template.gestureRhythms,
            contours: template.gestureContours,
            density: template.density,
            restiness: template.restiness,
            architecture: template.architecture))
        total.notesPerBar += measured.notesPerBar
        total.offbeatShare += measured.offbeatShare
        total.restShare += measured.restShare
        total.stepShare += measured.stepShare
        total.skipShare += measured.skipShare
        total.leapShare += measured.leapShare
        total.meanLength += measured.meanLength
        count += 1
    }
    total.notesPerBar /= count; total.offbeatShare /= count; total.restShare /= count
    total.stepShare /= count; total.skipShare /= count; total.leapShare /= count
    total.meanLength /= count
    return total
}

let templateProfiles = MelGenTemplates.line.map { ($0.name, profile(of: $0)) }
var distances: [Double] = []
for i in templateProfiles.indices {
    for j in (i + 1)..<templateProfiles.count {
        distances.append(templateProfiles[i].1.distance(to: templateProfiles[j].1))
    }
}
let median = distances.sorted()[distances.count / 2]

// The number this guards. Measured at 0.04 median / 0.07 max before the template
// character reached the composer, which is to say the nine templates were one
// template with nine names — and no amount of authoring more of them would have
// helped until that was true.
check("templates are measurably different from one another", median >= 0.07,
      String(format: "median pair distance %.2f, max %.2f", median, distances.max() ?? 0))

// And they differ on the axes they claim to. A template is allowed to be similar
// to another; it is not allowed to be similar to *all* of them.
let densities = templateProfiles.map { $0.1.notesPerBar }
check("density actually spreads",
      (densities.max() ?? 0) - (densities.min() ?? 0) > 2.5,
      String(format: "%.1f to %.1f notes per bar", densities.min() ?? 0, densities.max() ?? 0))

let offbeats = templateProfiles.map { $0.1.offbeatShare }
check("so does syncopation",
      (offbeats.max() ?? 0) - (offbeats.min() ?? 0) > 0.2,
      "\(Int((offbeats.min() ?? 0) * 100))% to \(Int((offbeats.max() ?? 0) * 100))% offbeat")

// The named ones have to be what they're named.
func named(_ name: String) -> PatternProfile? {
    templateProfiles.first { $0.0 == name }?.1
}
check("Sparse is the sparsest",
      named("Sparse")?.notesPerBar == densities.min(),
      String(format: "%.1f/bar", named("Sparse")?.notesPerBar ?? 0))
check("Running eighths writes shorter notes than Long tones",
      (named("Running eighths")?.meanLength ?? 9) < (named("Long tones")?.meanLength ?? 0),
      String(format: "%.1f against %.1f eighths",
             named("Running eighths")?.meanLength ?? 0, named("Long tones")?.meanLength ?? 0))
check("Anticipation is among the most offbeat",
      (named("Anticipation")?.offbeatShare ?? 0) > (offbeats.reduce(0, +) / Double(offbeats.count)),
      "\(Int((named("Anticipation")?.offbeatShare ?? 0) * 100))% against an average of "
      + "\(Int(offbeats.reduce(0, +) / Double(offbeats.count) * 100))%")

// A template claiming to syncopate has to be made of figures that do.
check("syncopation is measured from the figures, not declared",
      MelodyPhrases.leansOffbeat([.charleston, .pushedPair])
        && !MelodyPhrases.leansOffbeat([.even, .steadyQuarters]))

print()
print(failures == 0 ? "phrases: all checks passed" : "phrases: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
