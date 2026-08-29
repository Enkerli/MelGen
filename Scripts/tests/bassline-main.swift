// Checks the bass mode: the figures, the pad that mixes them, and the line that
// comes out.
//
// Three claims, and each of them is a thing a listener would notice going wrong.
//
// *The banks are what they say.* An on-beat figure whose weight is off the beat
// is a mislabelled figure, and the pad's whole horizontal axis is that label.
// So the split is measured rather than asserted — the same gate `templates`
// puts on a template that doesn't differ from the others.
//
// *The pad's two axes mean two things, independently.* Left to right is the
// balance between the two layers and up and down is which pair of figures, and
// neither constrains the other — which is why the region is a square. It was a
// diamond while four corner figures were being mixed barycentrically; with two
// independent axes that constraint only removed settings, and the one it
// removed first was a straight walking bass with no syncopation in it.
//
// *The line stays inside its range, stays one voice, and states the harmony.*
// The range is most of what makes a bass part a bass part, one voice is what a
// bass is, and a chord change with no note under it leaves the harmony unstated
// — which no amount of right notes afterwards recovers.
import Foundation

extension Sequence where Element == Double {
    /// Every neighbouring pair, for checking that a sweep is monotonic.
    func adjacentPairs() -> [(Double, Double)] {
        let values = Array(self)
        return zip(values, values.dropFirst()).map { ($0, $1) }
    }
}

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let changes = try ChordProgression.parse("Dm7 G7|C∆|Am7 D7|G∆")
let modal = try ChordProgression.parse("Cm7|Cm7|Cm7|Cm7")

// MARK: - Figures

print("── the two banks ──────────────────────────────────")

check("there are two banks and they don't overlap",
      Set(BasslineFigure.onBeatBank.map(\.name))
        .isDisjoint(with: Set(BasslineFigure.offBeatBank.map(\.name))))
check("every figure is named and described",
      BasslineFigure.all.allSatisfy { !$0.name.isEmpty && !$0.summary.isEmpty })
check("every figure covers exactly one bar of eighths",
      BasslineFigure.all.allSatisfy {
          $0.onsets.count == BasslineFigure.slots
            && $0.lengths.count == BasslineFigure.slots
            && $0.accents.count == BasslineFigure.slots
      })
check("every figure puts a note somewhere",
      BasslineFigure.all.allSatisfy { $0.onsets.reduce(0, +) > 0 })

for figure in BasslineFigure.onBeatBank {
    check("\(figure.name) is on the beat",
          figure.offbeatShare < 0.35,
          String(format: "%.0f%% off the beat", figure.offbeatShare * 100))
}
for figure in BasslineFigure.offBeatBank {
    check("\(figure.name) is off it",
          figure.offbeatShare > 0.35,
          String(format: "%.0f%% off the beat", figure.offbeatShare * 100))
}

check("no two figures are the same figure",
      Set(BasslineFigure.all.map { $0.onsets.map { String(format: "%.2f", $0) }.joined() }).count
        == BasslineFigure.all.count)
check("the pedal is the sparsest thing in either bank",
      BasslineFigure.pedal.weight == BasslineFigure.all.map(\.weight).min())
check("no two figures in a bank weigh the same, so the ordering is total",
      Set(BasslineFigure.onBeatBank.map(\.weight)).count == BasslineFigure.onBeatBank.count
        && Set(BasslineFigure.offBeatBank.map(\.weight)).count == BasslineFigure.offBeatBank.count,
      "\(BasslineFigure.all.map { String(format: "%.2f", $0.weight) })")

// A bank is walked by density, and the walk is continuous: between two entries
// the figures blend, which is what makes the pad's vertical a control rather
// than four chips.
for bank in [BasslineFigure.onBeatBank, BasslineFigure.offBeatBank] {
    let sparsest = BasslineFigure.inBank(bank, at: 0)
    let busiest = BasslineFigure.inBank(bank, at: 1)
    check("a bank runs from its sparsest figure to its busiest",
          sparsest.weight == bank.map(\.weight).min()
            && busiest.weight == bank.map(\.weight).max(),
          "\(sparsest.name) → \(busiest.name)")
    check("and never gets sparser on the way up",
          stride(from: 0.0, through: 1.0, by: 0.05)
            .map { BasslineFigure.inBank(bank, at: $0).weight }
            .adjacentPairs().allSatisfy { $0 <= $1 + 1e-9 })
    check("a position between two entries is between them",
          {
              let ordered = bank.sorted { ($0.weight, $0.name) < ($1.weight, $1.name) }
              let step = 1 / Double(ordered.count - 1)
              let between = BasslineFigure.inBank(bank, at: step / 2)
              return between.weight > ordered[0].weight
                  && between.weight < ordered[1].weight
          }())
}

// Shift is the cheapest variation the device has, and the claim is exact: the
// same notes, moved and wrapped.
let shifted = BasslineFigure.downbeats.shifted(by: 1)
check("a shift moves every onset along by one and wraps",
      shifted.onsets == [0] + BasslineFigure.downbeats.onsets.dropLast(),
      "\(shifted.onsets.map { String(format: "%.2f", $0) })")
check("and a shift of a whole bar changes nothing",
      BasslineFigure.downbeats.shifted(by: BasslineFigure.slots).onsets
        == BasslineFigure.downbeats.onsets)
check("shifting an on-beat figure by one makes an off-beat one",
      BasslineFigure.downbeats.offbeatShare < 0.35
        && BasslineFigure.downbeats.shifted(by: 1).offbeatShare > 0.65,
      String(format: "%.0f%% → %.0f%% off the beat",
             BasslineFigure.downbeats.offbeatShare * 100,
             BasslineFigure.downbeats.shifted(by: 1).offbeatShare * 100))

// MARK: - The pad

print()
print("── the pad ────────────────────────────────────────")

for (x, y) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0),
               (0.7, 0.7), (-0.9, -0.9), (0.3, -0.4), (5.0, -5.0)] {
    let pad = BasslinePad(x: x, y: y)
    check("(\(x), \(y)) is clamped per axis, so every corner is reachable",
          (-1...1).contains(pad.x) && (-1...1).contains(pad.y)
            && (abs(x) <= 1 ? pad.x == x : abs(pad.x) == 1)
            && (abs(y) <= 1 ? pad.y == y : abs(pad.y) == 1),
          String(format: "→ (%.2f, %.2f)", pad.x, pad.y))
}

// The corner the diamond used to forbid, and the reason it stopped being one: a
// straight quarter-note walking bass with nothing off the beat in it.
let corner = BasslinePad(x: -1, y: 1)
check("the busiest on-beat figure can be heard with no off-beat layer at all",
      corner.offBeatLevel == 0 && corner.selection == 1
        && corner.mixed().offbeatShare < 0.35,
      "\(corner.readout), "
      + String(format: "%.0f%% off the beat", corner.mixed().offbeatShare * 100))

// West to east is the balance, and it reaches both ends at every height.
for y in [-0.8, -0.4, 0.0, 0.4, 0.8] {
    let west = BasslinePad(x: -1, y: y)
    let east = BasslinePad(x: 1, y: y)
    check(String(format: "at height %.1f the west edge is the on-beat layer alone", y),
          west.balance <= -0.999 && west.offBeatLevel == 0 && west.onBeatLevel == 1,
          String(format: "balance %.2f", west.balance))
    check(String(format: "at height %.1f the east edge is the off-beat layer alone", y),
          east.balance >= 0.999 && east.onBeatLevel == 0 && east.offBeatLevel == 1)
}

let centre = BasslinePad(x: 0, y: 0)
check("the middle is both layers at full, not each at half",
      centre.balance == 0 && centre.onBeatLevel == 1 && centre.offBeatLevel == 1)
check("so the middle is busier than either edge",
      centre.mixed().weight > BasslinePad(x: -1, y: 0).mixed().weight
        && centre.mixed().weight > BasslinePad(x: 1, y: 0).mixed().weight,
      String(format: "%.2f vs %.2f / %.2f", centre.mixed().weight,
             BasslinePad(x: -1, y: 0).mixed().weight,
             BasslinePad(x: 1, y: 0).mixed().weight))

// South to north is which figures, sparsest at the bottom.
check("the south vertex is the sparsest pair and the north the busiest",
      BasslinePad(x: 0, y: -1).selection == 0
        && BasslinePad(x: 0, y: 1).selection == 1)
check("and moving north never makes the figure sparser",
      stride(from: -1.0, through: 1.0, by: 0.1)
        .map { BasslinePad(x: 0, y: $0).mixed().weight }
        .adjacentPairs().allSatisfy { $0 <= $1 + 1e-9 })
check("the two axes are independent — moving north doesn't move the balance",
      stride(from: -1.0, through: 1.0, by: 0.25)
        .allSatisfy { BasslinePad(x: -0.5, y: $0).balance == -0.5 })
check("and moving east doesn't change which figures are named",
      stride(from: -1.0, through: 1.0, by: 0.25)
        .allSatisfy { BasslinePad(x: $0, y: 0.3).onBeatFigure.name
                        == BasslinePad(x: 0, y: 0.3).onBeatFigure.name })

check("only the on-beat layer means an on-beat figure",
      BasslinePad(x: -1, y: 0).mixed().offbeatShare < 0.35,
      String(format: "%.0f%% off the beat", BasslinePad(x: -1, y: 0).mixed().offbeatShare * 100))
check("only the off-beat layer means an off-beat one",
      BasslinePad(x: 1, y: 0).mixed().offbeatShare > 0.5,
      String(format: "%.0f%% off the beat", BasslinePad(x: 1, y: 0).mixed().offbeatShare * 100))
check("moving east is the part getting pushed off the beat",
      stride(from: -1.0, through: 1.0, by: 0.25)
        .map { BasslinePad(x: $0, y: 0).mixed().offbeatShare }
        .adjacentPairs().allSatisfy { $0 <= $1 + 1e-9 },
      stride(from: -1.0, through: 1.0, by: 0.5)
        .map { String(format: "%.2f", BasslinePad(x: $0, y: 0).mixed().offbeatShare) }
        .joined(separator: " → "))

check("a length comes from the layers that actually play that slot",
      {
          // The pedal asks for eight eighths but only ever plays slot 0. Mixed
          // with a figure that plays throughout, it must not stretch the notes
          // it was never going to sound.
          let mix = BasslinePad(x: 0, y: -1).mixed()
          return mix.lengths[1] < 6 && mix.lengths[0] > 2
      }(),
      "the pedal only votes on the slot it plays")
check("the pad says what it currently names",
      !centre.name.isEmpty && !centre.readout.isEmpty && centre.name.contains("+"),
      centre.readout)

// MARK: - Drawing a line

print()
print("── the line ───────────────────────────────────────")

var settings = BasslineSettings()
let line = BasslineGenerator.line(settings, over: changes, seed: 7)
check("a default draw produces notes", !line.isEmpty, "\(line.count) notes")
check("the same seed produces the same line",
      BasslineGenerator.line(settings, over: changes, seed: 7) == line)
check("a different seed produces a different one",
      BasslineGenerator.line(settings, over: changes, seed: 8) != line)

// The property the live redraw rests on: at one seed, moving one control
// changes the line *because of that control*. If the seed moved too, every
// release would be a different line and there would be nothing to hear.
var nudged = settings
nudged.reach = min(1, settings.reach + 0.4)
let after = BasslineGenerator.line(nudged, over: changes, seed: 7)
check("at one seed, one control moved gives a related line rather than a new one",
      after != line
        && Set(after.map(\.startBeat)) == Set(line.map(\.startBeat)),
      "\(line.count) notes → \(after.count), same onsets")
check("and the notes it changed are the ones the control is about",
      zip(line, after).contains { $0.note != $1.note })

check("every note is inside the range",
      line.allSatisfy { settings.range.contains(Int($0.note)) },
      "\(settings.range) — lowest \(line.map(\.note).min() ?? 0), highest \(line.map(\.note).max() ?? 0)")
check("the line is one voice",
      zip(line, line.dropFirst()).allSatisfy {
          $0.startBeat + $0.durationBeats <= $1.startBeat + 1e-9
      })
check("it is in time order and inside the form",
      zip(line, line.dropFirst()).allSatisfy { $0.startBeat <= $1.startBeat }
        && line.allSatisfy { $0.startBeat + $0.durationBeats <= changes.totalBeats + 1e-6 })
check("every note has a length worth sounding",
      line.allSatisfy { $0.durationBeats >= 0.1 })

// The claim about seams: every chord change gets a note at or just after it.
var missedSeams: [String] = []
for chord in changes.chords {
    let underIt = line.contains {
        $0.startBeat >= chord.startBeat - 1e-9 && $0.startBeat < chord.startBeat + 0.5
    }
    if !underIt { missedSeams.append(chord.symbol.text) }
}
check("every chord change gets a note under it",
      missedSeams.isEmpty, missedSeams.joined(separator: ", "))

// And usually names it. The bass is whoever is lowest, so arriving on the third
// of every chord leaves the harmony ambiguous even though every note belonged.
// A majority rather than a rule: reaching the new chord by its fifth is
// idiomatic and the histogram only makes the root the likeliest arrival.
var roots = 0
var arrivals = 0
for chord in changes.chords {
    guard let arrival = line.first(where: {
        $0.startBeat >= chord.startBeat - 1e-9 && $0.startBeat < chord.startBeat + 0.5
    }) else { continue }
    arrivals += 1
    if ChordScales.pitchClass(Int(arrival.note)) == chord.symbol.rootPitchClass { roots += 1 }
}
check("and most changes are arrived at on the root",
      Double(roots) / Double(max(1, arrivals)) >= 0.5,
      "\(roots) of \(arrivals)")

// And the notes it does land on are mostly the chord's own.
var chordTones = 0
for note in line {
    guard let placed = changes.chord(at: note.startBeat) else { continue }
    let semitone = ChordScales.pitchClass(Int(note.note) - placed.symbol.rootPitchClass)
    if DegreeContext(chord: placed.symbol).role(ofSemitone: semitone) == .chordTone { chordTones += 1 }
}
check("most of the line is chord tones at the default reach",
      Double(chordTones) / Double(max(1, line.count)) > 0.55,
      "\(chordTones) of \(line.count)")

// MARK: - The dials

print()
print("── the dials do what they say ─────────────────────")

// One dial at a time. The defaults leave a little outside weight on, which is
// deliberate — it is what makes a chromatic approach to the root happen on its
// own — but it means a check about *reach* has to turn it off, or it is a check
// about two dials at once and can only ever be flaky.
var narrow = BasslineSettings()
narrow.reach = 0
narrow.outside = 0
let narrowLine = BasslineGenerator.line(narrow, over: modal, seed: 3)
check("reach 0 plays the root and nothing else",
      Set(narrowLine.map { ChordScales.pitchClass(Int($0.note)) }) == [0],
      "\(Set(narrowLine.map { ChordScales.pitchClass(Int($0.note)) }).sorted())")

var wide = BasslineSettings()
wide.reach = 1
wide.outside = 0
let wideLine = BasslineGenerator.line(wide, over: modal, seed: 3)
check("reach 1 plays most of the scale",
      Set(wideLine.map { ChordScales.pitchClass(Int($0.note)) }).count >= 4,
      "\(Set(wideLine.map { ChordScales.pitchClass(Int($0.note)) }).sorted().count) pitch classes")

var low = BasslineSettings()
low.lowNote = 24
low.highNote = 40
let lowLine = BasslineGenerator.line(low, over: changes, seed: 11)
check("a range control moves the whole line",
      !lowLine.isEmpty && lowLine.allSatisfy { (24...40).contains(Int($0.note)) },
      "\(lowLine.map(\.note).min() ?? 0)–\(lowLine.map(\.note).max() ?? 0)")
check("a range narrower than an octave is widened rather than refused",
      { var tight = BasslineSettings(); tight.lowNote = 40; tight.highNote = 42
        return tight.range.count >= 12 && !BasslineGenerator.line(tight, over: changes, seed: 1).isEmpty }())
check("a range given backwards is read the right way round",
      { var flipped = BasslineSettings(); flipped.lowNote = 52; flipped.highNote = 28
        return flipped.range.lowerBound == 28 }())

var moved = BasslineSettings()
moved.shift = 3
check("shifting moves the line without changing how many notes are in it",
      {
          let plain = BasslineGenerator.line(BasslineSettings(), over: modal, seed: 5)
          let shifted = BasslineGenerator.line(moved, over: modal, seed: 5)
          return !shifted.isEmpty && shifted.map(\.startBeat) != plain.map(\.startBeat)
      }())

var sparse = BasslineSettings()
sparse.density = 0.3
check("density thins the line",
      BasslineGenerator.line(sparse, over: changes, seed: 5).count
        < BasslineGenerator.line(BasslineSettings(), over: changes, seed: 5).count)

var outside = BasslineSettings()
outside.reach = 1
outside.outside = 0.6
let outsideLine = BasslineGenerator.line(outside, over: modal, seed: 17)
let insideOnly = BasslineGenerator.line(wide, over: modal, seed: 17)
func offScaleShare(_ notes: [SequencedNote], over progression: ChordProgression) -> Double {
    guard !notes.isEmpty else { return 0 }
    var off = 0
    for note in notes {
        guard let placed = progression.chord(at: note.startBeat) else { continue }
        let semitone = ChordScales.pitchClass(Int(note.note) - placed.symbol.rootPitchClass)
        if DegreeContext(chord: placed.symbol).role(ofSemitone: semitone) == .offScale { off += 1 }
    }
    return Double(off) / Double(notes.count)
}
check("outside lets notes off the scale in",
      offScaleShare(outsideLine, over: modal) > offScaleShare(insideOnly, over: modal),
      String(format: "%.0f%% vs %.0f%%",
             offScaleShare(outsideLine, over: modal) * 100,
             offScaleShare(insideOnly, over: modal) * 100))
check("and at zero there are none at all",
      offScaleShare(insideOnly, over: modal) == 0)
check("the default leaves a little of it on, which is where a chromatic "
      + "approach comes from",
      BasslineSettings().outside > 0 && BasslineSettings().outside < 0.1,
      String(format: "%.2f", BasslineSettings().outside))

// MARK: - Variants and the morph

print()
print("── the eight seeds, and the dial between them ─────")

var draws: [[SequencedNote]] = []
for index in 0..<BasslineSettings.seedCount {
    var settings = BasslineSettings()
    settings.seedIndex = index
    draws.append(BasslineGenerator.line(settings, over: changes, seed: 21))
}
check("all eight seeds produce a line", draws.allSatisfy { !$0.isEmpty })
check("and no two of them are the same line",
      Set(draws.map { $0.map { "\($0.note)@\($0.startBeat)" }.joined() }).count
        == BasslineSettings.seedCount)

var morphed = BasslineSettings()
morphed.seedIndex = 0
let atZero = BasslineGenerator.line(morphed, over: changes, seed: 21)
morphed.morph = 1
let atOne = BasslineGenerator.line(morphed, over: changes, seed: 21)
morphed.morph = 0.5
let halfway = BasslineGenerator.line(morphed, over: changes, seed: 21)

check("morph 0 is this seed's draw", atZero == draws[0])
check("morph 1 is the next seed's material",
      atOne.count == draws[1].count,
      "\(atOne.count) vs \(draws[1].count)")
check("halfway is neither of them", halfway != atZero && halfway != atOne)
check("and is still one voice inside the range",
      !halfway.isEmpty
        && halfway.allSatisfy { morphed.range.contains(Int($0.note)) }
        && zip(halfway, halfway.dropFirst()).allSatisfy {
            $0.startBeat + $0.durationBeats <= $1.startBeat + 1e-9
        })
check("the morph never puts two notes on one grid position",
      zip(halfway, halfway.dropFirst()).allSatisfy { $1.startBeat - $0.startBeat > 0.11 })

// MARK: - Over a key

print()
print("── a key, as a progression with one chord in it ───")

// There is no "over a key" path any more. A vamp is leadsheet text, so the same
// generator reads it and the same field holds it — which is the whole claim
// worth checking.
let vampText = DiatonicHarmony.vamp(key: 4, scale: .dorian, bars: 4)
check("a vamp is written as one chord held for the bars asked for",
      vampText == "E(dorian)|||", vampText)
guard let vamp = try? ChordProgression.parse(vampText) else {
    check("a written vamp parses", false)
    fatalError("a written vamp must parse")
}
check("and parses back to one chord over the whole form",
      vamp.chords.count == 1 && vamp.totalBeats == 16
        && vamp.chords[0].symbol.rootPitchClass == 4,
      vamp.text)
check("in the mode it names",
      vamp.chords[0].symbol.scaleName == "Dorian")

var overVamp = BasslineSettings()
overVamp.outside = 0
let keyed = BasslineGenerator.line(overVamp, over: vamp, seed: 33)
check("a bass part over it stays in the mode",
      !keyed.isEmpty && keyed.allSatisfy {
          Set(Scale.dorian.intervals.map { (4 + $0) % 12 })
              .contains(ChordScales.pitchClass(Int($0.note)))
      },
      "E Dorian, \(keyed.count) notes")
check("and a different mode gives different notes for the same settings",
      Set(keyed.map { ChordScales.pitchClass(Int($0.note)) })
        != Set(BasslineGenerator.line(
            overVamp,
            over: try? ChordProgression.parse(DiatonicHarmony.vamp(key: 4, scale: .lydian, bars: 4)),
            seed: 33).map { ChordScales.pitchClass(Int($0.note)) }))
check("every rung of the ladder writes something that parses back to itself",
      DiatonicHarmony.ladder.allSatisfy { scale in
          let text = DiatonicHarmony.vamp(key: 7, scale: scale, bars: 2)
          guard let parsed = try? ChordProgression.parse(text) else { return false }
          return parsed.chords.count == 1 && parsed.totalBeats == 8
            && parsed.chords[0].symbol.scaleName == scale.displayName
      })
check("with no progression at all nothing is drawn, rather than something invented",
      BasslineGenerator.line(overVamp, over: nil, seed: 1).isEmpty)

// A take carries the harmony it was drawn over, whatever that harmony was, so
// nothing upstream has to be edited for it to be replayed or coloured correctly.
var vampState = MelGenState()
vampState.mode = .bass
vampState.progressionText = vampText
if let take = TakeAdvance.candidate(mode: .anotherLikeThis, state: vampState,
                                    source: .bassline, progression: vamp) {
    check("a take over a vamp records the vamp it was drawn against",
          take.progressionText == vampText, take.progressionText)
    check("so replaying it means replaying it over the same harmony",
          (try? ChordProgression.parse(take.progressionText))?.chords.first?.symbol.scaleName
            == "Dorian")
} else {
    check("a take over a vamp is produced at all", false)
}

// MARK: - Fitting in

print()
print("── it is a take like any other ────────────────────")

check("Bass is a mode, and a monophonic one",
      PlayMode.allCases.contains(.bass) && !PlayMode.bass.isPolyphonic
        && PlayMode.bass.label == "Bass")
check("its sources are the ones that can produce a bass part",
      MaterialSource.all(for: .bass) == [.bassline, .learned, .model],
      "\(MaterialSource.all(for: .bass).map(\.name))")
check("the bassline source is instant and says whose vocabulary it is",
      MaterialSource.bassline.isInstant && !MaterialSource.bassline.provenance.isEmpty
        && MaterialSource.bassline.verb(mode: .bass) == "Draw a bass line")
check("its templates are the figures",
      MelGenTemplates.all(for: .bass).count == BasslineFigure.all.count
        && MelGenTemplates.all(for: .bass).allSatisfy { $0.basslineFigure != nil })
check("choosing one moves the pad to where that figure lives, and leans its way",
      {
          let settings = BasslineSettings()
          let onBeat = settings.placing(.walking)
          let offBeat = settings.placing(.charleston)
          return onBeat.pad.onBeatFigure.name == "Walking" && onBeat.pad.balance < 0
            && offBeat.pad.offBeatFigure.name == "Charleston" && offBeat.pad.balance > 0
      }(),
      "\(BasslineSettings().placing(.walking).pad.onBeatFigure.name) / "
      + "\(BasslineSettings().placing(.charleston).pad.offBeatFigure.name)")
check("every figure in either bank can be reached from the pad",
      BasslineFigure.all.allSatisfy { figure in
          guard let selection = BasslinePad.selection(of: figure) else { return false }
          let pad = BasslinePad(x: 0, y: selection * 2 - 1)
          return pad.onBeatFigure.name == figure.name || pad.offBeatFigure.name == figure.name
      })
check("a take drawn this way analyses like any other",
      {
          let analysis = MelodyAnalyser.analyse(line, over: changes)
          return analysis.chordTones + analysis.colourTones
              + analysis.avoidNotes + analysis.offScaleNotes == line.count
      }(),
      MelodyAnalyser.analyse(line, over: changes).summary)
check("and reads back as a stored line",
      MelodyPatterns.extract(from: line, over: changes, name: "bass") != nil)

// The settings are part of a session and part of a setup, so they have to
// survive both round trips — and an older session has to still open.
let encoded = try JSONEncoder().encode(settings)
check("the settings round-trip through JSON",
      (try? JSONDecoder().decode(BasslineSettings.self, from: encoded)) == settings)
check("and a session saved before they existed still decodes",
      (try? JSONDecoder().decode(BasslineSettings.self, from: Data("{}".utf8)))
        == BasslineSettings())

var state = MelGenState()
state.mode = .bass
state.bassline.reach = 0.8
state.bassline.pad.setPoint(x: -0.3, y: 0.6)
let setup = MelGenSetup(name: "Bass", capturing: state)
var restored = MelGenState()
restored.apply(setup)
check("a setup carries the bass settings",
      restored.bassline == state.bassline && restored.mode == .bass)
check("and a saved state does too",
      {
          guard let data = try? JSONEncoder().encode(state),
                let back = try? JSONDecoder().decode(MelGenState.self, from: data)
          else { return false }
          return back.bassline == state.bassline
      }())

// The advance has to answer in Bass too, and without waiting on anything.
for aim in AdvanceMode.allCases {
    let candidate = TakeAdvance.candidate(mode: aim, state: state,
                                          source: .bassline, progression: changes)
    check("\(aim) answers in Bass",
          candidate != nil && !(candidate?.notes.isEmpty ?? true))
    check("\(aim) says what it will do before it does it",
          TakeAdvance.subtitle(mode: aim, state: state, source: .bassline) != nil)
    check("\(aim) produces a take labelled as a bass part",
          candidate?.source == .bassline, candidate?.source.label ?? "nothing")
}

print()
print(failures == 0 ? "bassline: all checks passed" : "bassline: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
