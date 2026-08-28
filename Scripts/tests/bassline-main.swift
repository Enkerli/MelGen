// Checks the bass mode: the figures, the diamond that mixes them, and the line
// that comes out.
//
// Three claims, and each of them is a thing a listener would notice going wrong.
//
// *The banks are what they say.* An on-beat figure whose weight is off the beat
// is a mislabelled figure, and the diamond's whole vertical axis is that label.
// So the split is measured rather than asserted — the same gate `templates`
// puts on a template that doesn't differ from the others.
//
// *The diamond is a partition.* Four weights summing to one, whatever the point
// is, with the corners reachable and the centre an even blend. If the weights
// don't sum the mix isn't a mix, and moving the puck changes the amount of
// material rather than its character.
//
// *The line stays inside its range, stays one voice, and states the harmony.*
// The range is most of what makes a bass part a bass part, one voice is what a
// bass is, and a chord change with no note under it leaves the harmony unstated
// — which no amount of right notes afterwards recovers.
import Foundation

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
      BasslineFigure.pedal.onsets.reduce(0, +)
        == BasslineFigure.all.map { $0.onsets.reduce(0, +) }.min())

// MARK: - The diamond

print()
print("── the diamond ────────────────────────────────────")

for (x, y) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0),
               (0.7, 0.7), (-0.9, -0.9), (0.3, -0.4), (5.0, -5.0)] {
    let diamond = BasslineDiamond(x: x, y: y)
    let total = diamond.weights.values.reduce(0, +)
    check("(\(x), \(y)) stays on the diamond and its weights sum to one",
          abs(diamond.x) + abs(diamond.y) <= 1 + 1e-9 && abs(total - 1) < 1e-9,
          String(format: "→ (%.2f, %.2f), sum %.4f", diamond.x, diamond.y, total))
}

let centre = BasslineDiamond(x: 0, y: 0)
check("the centre is every corner at a quarter",
      BasslineCorner.allCases.allSatisfy { abs((centre.weights[$0] ?? 0) - 0.25) < 1e-9 })
let north = BasslineDiamond(x: 0, y: 1)
check("a corner is that corner and nothing else",
      abs((north.weights[.onBeat] ?? 0) - 1) < 1e-9
        && (north.weights[.offBeat] ?? 1) < 1e-9)

check("the mixed figure at a corner is that corner's figure",
      north.mixed().onsets.elementsEqual(north.figure(at: .onBeat).onsets) { abs($0 - $1) < 1e-9 })
check("mixing produces something between its corners",
      {
          let between = BasslineDiamond(x: 0, y: 0.4).mixed()
          let on = BasslineFigure.downbeats
          let off = BasslineFigure.tresillo
          // Slot 3 is an onset for the tresillo and silence for the downbeats,
          // so a mix that includes any of the off-beat corner has to put some
          // weight there and less than the tresillo alone does.
          return between.onsets[3] > 0 && between.onsets[3] < off.onsets[3]
            && on.onsets[3] == 0
      }())
check("a length comes from the corners that actually play that slot",
      {
          // The pedal asks for eight eighths but only ever plays slot 0. Mixed
          // with a figure that plays throughout, it must not stretch the notes
          // it was never going to sound.
          let mix = BasslineDiamond(x: -0.5, y: 0.5, onBeatName: "Downbeats",
                                    offBeatName: "Ands").mixed()
          return mix.lengths[2] < 4 && mix.lengths[0] > 2
      }(),
      "pedal only votes on the slots it plays")
check("moving the point changes the figure",
      BasslineDiamond(x: 0, y: 1).mixed().onsets != BasslineDiamond(x: 0, y: -1).mixed().onsets)
check("the mixed figure says what went into it",
      !BasslineDiamond(x: 0, y: 0.5).mixed().name.isEmpty)

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
print("── over a key rather than changes ─────────────────")

var overKey = BasslineSettings()
overKey.overKey = true
overKey.key = 4
overKey.minorness = 0.5
overKey.bars = 4
overKey.outside = 0
let keyed = BasslineGenerator.line(overKey, over: changes, seed: 33)
let vamp = BasslineGenerator.progression(for: overKey, changes: changes)
check("the key wins over whatever is typed",
      vamp?.chords.count == 1 && vamp?.chords.first?.symbol.rootPitchClass == 4,
      vamp?.text ?? "nothing")
check("and the form is as long as the bars asked for",
      vamp?.totalBeats == 16)
check("the line stays in the mode",
      !keyed.isEmpty && keyed.allSatisfy {
          Set(DiatonicHarmony.mode(forMinorness: 0.5).intervals.map { (4 + $0) % 12 })
              .contains(ChordScales.pitchClass(Int($0.note)))
      },
      "E Dorian, \(keyed.count) notes")

var brighter = overKey
brighter.minorness = 0
var darker = overKey
darker.minorness = 1
check("minorness changes which notes are available",
      Set(BasslineGenerator.line(brighter, over: nil, seed: 33).map { ChordScales.pitchClass(Int($0.note)) })
        != Set(BasslineGenerator.line(darker, over: nil, seed: 33).map { ChordScales.pitchClass(Int($0.note)) }))
check("with no changes at all a key still plays",
      !BasslineGenerator.line(overKey, over: nil, seed: 1).isEmpty)

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
check("choosing one puts it on the diamond, at its own bank's corner",
      {
          let settings = BasslineSettings()
          let onBeat = settings.placing(.walking)
          let offBeat = settings.placing(.charleston)
          return onBeat.diamond.onBeatName == "Walking" && onBeat.diamond.y > 0
            && offBeat.diamond.offBeatName == "Charleston" && offBeat.diamond.y < 0
      }())
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
state.bassline.diamond.setPoint(x: -0.3, y: 0.6)
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
