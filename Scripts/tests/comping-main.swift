// Checks the voicing layer and the comping mode.
//
// Two claims. Tones are classified by interval rather than by position in a
// list, which is what makes voicings right on suspended, quartal and altered
// chords rather than only on the plain ones. And voice leading moves the voicing
// as a unit — a player picks the register, not the arrangement, because the
// arrangement is what makes a rootless A a rootless A.
import Foundation
import Carrier
import Theory

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

func classes(_ pitches: [Int]) -> Set<Int> { Set(pitches.map { (($0 % 12) + 12) % 12 }) }
func names(_ pitches: [Int]) -> String {
    pitches.map { ChordProgression.noteName(forMIDINote: $0) }.joined(separator: " ")
}

// MARK: - Classifying tones

print("── tones, by interval rather than by position ─────")

let dm7 = try ChordProgression.parseChordSymbol("Dm7")
check("a minor third is found", ChordVoicings.third(of: dm7) == 3)
check("the fifth is found", ChordVoicings.fifth(of: dm7) == 7)
check("the seventh is found", ChordVoicings.seventh(of: dm7) == 10)

let sus = try ChordProgression.parseChordSymbol("C7sus4")
check("a suspended chord's fourth stands in for a third",
      ChordVoicings.third(of: sus) == 5 || ChordVoicings.third(of: sus) == 2,
      "\(ChordVoicings.third(of: sus).map(String.init) ?? "none")")

let altered = try ChordProgression.parseChordSymbol("G7alt")
check("an altered dominant still yields a third and a seventh",
      ChordVoicings.third(of: altered) != nil && ChordVoicings.seventh(of: altered) != nil)
check("and a colour note", ChordVoicings.colour(of: altered) != nil)

// MARK: - Voicings

print()
print("── laying chords out ──────────────────────────────")

for style in VoicingStyle.allCases {
    for symbol in ["Dm7", "G7", "Cmaj7", "A7♭9", "Cquartal", "C7sus4", "Cdim7", "B♭6"] {
        let chord = try ChordProgression.parseChordSymbol(symbol)
        let voicing = ChordVoicings.voice(chord, style: style)
        let label = "\(style.label) on \(symbol)"
        check("\(label) produces notes", voicing.pitches.count >= 2,
              "\(voicing.pitches.count): \(names(voicing.pitches))")
        check("\(label) stays in range",
              voicing.pitches.allSatisfy { ChordVoicings.range.contains($0) })
        check("\(label) doesn't double a pitch",
              Set(voicing.pitches).count == voicing.pitches.count)
        check("\(label) spans less than three octaves", voicing.span <= 36, "\(voicing.span)")
    }
}

// The drawn style is the only one that asks the chord what it can carry, so the
// checks on it are about *difference between chords* rather than about a recipe.
print()
print("── the voicing the chord chooses ──────────────────")

func drawn(_ symbol: String) -> [Int] {
    let chord = try! ChordProgression.parseChordSymbol(symbol)
    return ChordVoicings.drawnIntervals(of: chord, reach: 0.85).map { $0 % 12 }.sorted()
}

check("a major seventh takes the ninth, not the sharp eleventh",
      drawn("C∆").contains(2) && !drawn("C∆").contains(6),
      "\(drawn("C∆").map { IntervalNames.all[$0] })")
check("a minor seventh takes the eleventh, which nothing damps there",
      drawn("Dm7").contains(5),
      "\(drawn("Dm7").map { IntervalNames.all[$0] })")
check("neither of those is written down — the scale decides",
      drawn("C∆") != drawn("Cm7"))
check("an alteration the symbol names replaces the degree it alters",
      drawn("C7♯11").contains(6) && !drawn("C7♯11").contains(7),
      "\(drawn("C7♯11").map { IntervalNames.all[$0] })")
check("but a sharp eleventh that only came from the scale evicts nothing",
      drawn("C∆").contains(7))
check("no two tones a semitone apart, on any chord in the dictionary",
      ChordDictionary.allQualities.allSatisfy { quality in
          guard let chord = try? ChordProgression.parseChordSymbol(
              "C" + ChordDictionary.displaySuffix(forKey: quality.key)) else { return true }
          let tones = ChordVoicings.drawnIntervals(of: chord, reach: 0.85).map { $0 % 12 }
          return !tones.contains { left in
              tones.contains { right in
                  guard left != right else { return false }
                  let gap = abs(left - right)
                  return min(gap, 12 - gap) == 1
              }
          }
      })
check("and never fewer than three voices",
      ChordDictionary.allQualities.allSatisfy { quality in
          guard let chord = try? ChordProgression.parseChordSymbol(
              "C" + ChordDictionary.displaySuffix(forKey: quality.key)) else { return true }
          return ChordVoicings.voice(chord, style: .drawn).pitches.count >= 3
      })
check("reaching further changes what comes in",
      ChordVoicings.drawnIntervals(of: dm7, reach: 0.3)
        != ChordVoicings.drawnIntervals(of: dm7, reach: 1))
check("it keeps the third and seventh whatever the weights say",
      {
          let tones = ChordVoicings.drawnIntervals(of: dm7, reach: 0).map { $0 % 12 }
          return tones.contains(3) && tones.contains(10)
      }(),
      "the two notes that name the chord")

print()
let shell = ChordVoicings.voice(dm7, style: .shell)
check("a shell is root, third and seventh",
      classes(shell.pitches) == [2, 5, 0], names(shell.pitches))

let rootless = ChordVoicings.voice(dm7, style: .rootlessA)
check("a rootless voicing leaves the root out",
      !classes(rootless.pitches).contains(dm7.rootPitchClass), names(rootless.pitches))
check("and keeps the third and seventh, which are what name the chord",
      classes(rootless.pitches).isSuperset(of: [5, 0]))

let withBass = ChordVoicings.voice(dm7, style: .rootlessA, includeBass: true)
check("a bass note is separate and low",
      (withBass.bass ?? 99) < (withBass.pitches.min() ?? 0),
      "bass \(withBass.bass.map { ChordProgression.noteName(forMIDINote: $0) } ?? "none")")

// Drop 2 opens the spacing without changing a note.
let close = ChordVoicings.voice(dm7, style: .close)
let drop2 = ChordVoicings.voice(dm7, style: .drop2)
check("drop 2 has the same notes as the close voicing",
      classes(drop2.pitches) == classes(close.pitches),
      "\(names(close.pitches)) → \(names(drop2.pitches))")
check("but wider", drop2.span > close.span, "\(close.span) → \(drop2.span)")

// MARK: - Voice leading

print()
print("── voice leading ──────────────────────────────────")

let iiVI = try ChordProgression.parse("Dm7 | G7 | Cmaj7 | Cmaj7")
let led = ChordVoicings.voiceLead(iiVI, style: .rootlessA)
check("every chord gets a voicing", led.count == iiVI.chords.count)
check("every voicing keeps its own pitch classes",
      zip(led, iiVI.chords).allSatisfy { voicing, placed in
          !voicing.pitches.isEmpty
              && classes(voicing.pitches).isSubset(of: Set(placed.symbol.scalePitchClasses))
      })

/// Distance each new note has to travel to the nearest note of the last chord.
func movement(_ a: Voicing, _ b: Voicing) -> Int {
    b.pitches.reduce(0) { total, pitch in
        total + (a.pitches.map { abs(pitch - $0) }.min() ?? 12)
    }
}
let ledMovement = zip(led, led.dropFirst()).map(movement)
let unled = iiVI.chords.map { ChordVoicings.voice($0.symbol, style: .rootlessA) }
let unledMovement = zip(unled, unled.dropFirst()).map(movement)
check("leading moves less than not leading",
      ledMovement.reduce(0, +) <= unledMovement.reduce(0, +),
      "\(ledMovement.reduce(0, +)) against \(unledMovement.reduce(0, +)) semitones")
check("no change moves more than a few semitones per voice",
      ledMovement.allSatisfy { $0 <= 12 }, "\(ledMovement)")

// The voicing must survive being led: a rootless A that comes back with its
// internal spacing rearranged is no longer a rootless A.
check("leading preserves the voicing's internal spacing",
      zip(led, unled).allSatisfy { after, before in
          let beforeGaps = zip(before.pitches, before.pitches.dropFirst()).map { $1 - $0 }
          let afterGaps = zip(after.pitches, after.pitches.dropFirst()).map { $1 - $0 }
          return beforeGaps == afterGaps
      })
check("a repeated chord doesn't move at all",
      led.count > 3 && led[2].pitches == led[3].pitches,
      "\(names(led[2].pitches)) then \(names(led[3].pitches))")

// MARK: - Comping

print()
print("── comping ────────────────────────────────────────")

let changes = try ChordProgression.parse("Dm7 | G7 | Cmaj7 | A7♭9")
for figure in CompingFigure.all {
    let notes = MelodyComping.comp(changes, figure: figure)
    let label = figure.name
    check("\(label) comps", !notes.isEmpty, "\(notes.count) notes")
    check("\(label) is polyphonic", MelodyComping.maximumPolyphony(of: notes) >= 2,
          "up to \(MelodyComping.maximumPolyphony(of: notes)) voices")
    check("\(label) stays inside what the kernel can hold",
          MelodyComping.maximumPolyphony(of: notes) <= 8)
    check("\(label) stays inside the form",
          notes.allSatisfy { $0.startBeat + $0.durationBeats <= changes.totalBeats + 0.01 })
    check("\(label) is playable", notes.allSatisfy { $0.note >= 24 && $0.note <= 108 })
    check("\(label) is deterministic", MelodyComping.comp(changes, figure: figure) == notes)

    // The one thing that makes a comp sound wrong rather than dull.
    check("\(label) never holds a voicing into the next chord",
          notes.allSatisfy { note in
              guard let chord = changes.chords.first(where: {
                  note.startBeat >= $0.startBeat - 0.001
                      && note.startBeat < $0.startBeat + $0.durationBeats - 0.001
              }) else { return true }
              return note.startBeat + note.durationBeats <= chord.startBeat + chord.durationBeats + 0.01
          })

    // Every sounding note has to belong to the chord under it.
    check("\(label) plays the chord that's sounding",
          notes.allSatisfy { note in
              guard let chord = changes.chord(at: note.startBeat) else { return false }
              return chord.symbol.scalePitchClasses.contains(((Int(note.note) % 12) + 12) % 12)
          })
}

// MARK: - Realization keeps the chords

print()
print("── realization keeps the chords ───────────────────")

let comp = MelodyComping.comp(changes, figure: .pad)
let rendered = MelodyExpression.apply(to: comp,
                                      settings: ExpressionSettings(amount: 0.8, swing: 0.5,
                                                                   noteLength: 0.5, density: 0.3),
                                      generatedDensity: 0.5,
                                      lengthBeats: changes.totalBeats,
                                      seed: 42,
                                      polyphonic: true)
check("expression keeps every voice", rendered.count == comp.count,
      "\(comp.count) → \(rendered.count)")
check("and the chords are still chords",
      MelodyComping.maximumPolyphony(of: rendered) >= MelodyComping.maximumPolyphony(of: comp) - 1,
      "\(MelodyComping.maximumPolyphony(of: comp)) → \(MelodyComping.maximumPolyphony(of: rendered))")

// The monophonic path would have destroyed it, which is why the flag exists.
let asLine = MelodyExpression.apply(to: comp,
                                    settings: ExpressionSettings(amount: 0.8, swing: 0.5,
                                                                 noteLength: 0.5, density: 0.3),
                                    generatedDensity: 0.5,
                                    lengthBeats: changes.totalBeats,
                                    seed: 42,
                                    polyphonic: false)
check("treating a comp as a line would have thinned it away",
      asLine.count < rendered.count, "\(asLine.count) against \(rendered.count) notes")

// A comp is a take like any other, so it has to survive the whole session path.
var state = MelGenState()
state.mode = .comping
state.add(GenerationRecord(progressionText: changes.text, temperature: 0.6,
                           briefName: "Pad", source: .comping,
                           lengthBeats: changes.totalBeats, notes: comp))
check("a comping take renders polyphonically from the session",
      MelodyComping.maximumPolyphony(of: state.renderedMelody) >= 3,
      "up to \(MelodyComping.maximumPolyphony(of: state.renderedMelody)) voices")
// The polyphony decision is the take's, not the mode's, so a line loaded while
// the mode says Chords still renders as a line. Checked as that property rather
// than by counting the modes, which is what this used to do and which said
// nothing about rendering — it also broke the day a third mode was added, which
// is a test failing for the one reason it should never fail.
var lineState = MelGenState()
lineState.mode = .comping
lineState.add(GenerationRecord(progressionText: changes.text, temperature: 0.6,
                               briefName: "Long tones", source: .pattern,
                               lengthBeats: changes.totalBeats,
                               notes: MelodyPatterns.realize(MelodyPatterns.longTones,
                                                             over: changes)))
check("and a line take still renders as a line",
      MelodyComping.maximumPolyphony(of: lineState.renderedMelody) == 1,
      "up to \(MelodyComping.maximumPolyphony(of: lineState.renderedMelody)) voices")
check("every mode says which it is and whether it can stack notes",
      PlayMode.allCases.allSatisfy { !$0.label.isEmpty && !$0.explanation.isEmpty }
        && PlayMode.allCases.filter(\.isPolyphonic) == [.comping],
      "\(PlayMode.allCases.map(\.label))")

// MARK: - Varying a comp

print()
print("── varying a comp, as a comp ──────────────────────")

let parentComp = MelodyComping.comp(changes, figure: .charleston, seed: 5)
let compVariants = MelodyComping.variants(of: changes, figure: .charleston,
                                          parent: parentComp, seed: 5)
check("a comp has variants", compVariants.count >= 8, "\(compVariants.count)")
check("every one of them is still polyphonic",
      compVariants.allSatisfy { MelodyComping.maximumPolyphony(of: $0.notes) >= 2 },
      "least polyphonic: \(compVariants.map { MelodyComping.maximumPolyphony(of: $0.notes) }.min() ?? 0)")
// The property, not two hard-coded names: the list has to cover both of a
// comp's axes. Asserting particular variants made the test fail whenever the
// ordering changed, which said nothing about whether the coverage was there.
let variesVoicing = compVariants.contains { variant in
    VoicingStyle.allCases.contains {
        $0 != CompingFigure.charleston.style && variant.name.hasSuffix($0.label)
    }
}
let variesRhythm = compVariants.contains { variant in
    GestureRhythm.all.contains {
        $0 != CompingFigure.charleston.rhythm && variant.name.hasPrefix($0.name)
    }
}
check("they vary the voicing and the rhythm, which are a comp's two axes",
      variesVoicing && variesRhythm,
      "voicing \(variesVoicing), rhythm \(variesRhythm)")
check("and every axis is represented before any is doubled",
      Set(compVariants.prefix(6).map { $0.name.components(separatedBy: " ").first ?? "" }).count >= 3,
      compVariants.prefix(6).map(\.name).joined(separator: ", "))
check("they include a register move", compVariants.contains { $0.name.contains("octave") })
check("none of them is the original", compVariants.allSatisfy {
    $0.notes != MelodyComping.comp(changes, figure: .charleston, seed: 5)
})
check("every one plays the chord that's sounding",
      compVariants.allSatisfy { variant in
          variant.notes.allSatisfy { note in
              guard let chord = changes.chord(at: note.startBeat) else { return false }
              return chord.symbol.scalePitchClasses.contains(((Int(note.note) % 12) + 12) % 12)
          }
      })
check("varying a comp is deterministic",
      MelodyComping.variants(of: changes, figure: .charleston,
                             parent: parentComp, seed: 5).map(\.name)
        == compVariants.map(\.name))

// The one that matters: a variant of *this take* has to keep this take's
// rhythm. Without it, exploring a model-generated comp threw the model's
// material away and offered deterministic comps instead — polyphonic, so it
// didn't look like a bug, and not variants of anything.
let keepsRhythm = compVariants.filter { $0.name.hasPrefix("This comp · ") }
check("some variants keep the parent's own rhythm", !keepsRhythm.isEmpty,
      "\(keepsRhythm.count) of \(compVariants.count)")
check("and keep it exactly",
      keepsRhythm.allSatisfy { variant in
          Set(variant.notes.map { ($0.startBeat * 100).rounded() })
              == Set(parentComp.map { ($0.startBeat * 100).rounded() })
      })
check("while changing what's played at each hit",
      keepsRhythm.allSatisfy { $0.notes.map(\.note) != parentComp.map(\.note) })
check("re-voicing keeps a comp polyphonic",
      keepsRhythm.allSatisfy { MelodyComping.maximumPolyphony(of: $0.notes) >= 2 })
check("and every re-voiced note still belongs to its chord",
      keepsRhythm.allSatisfy { variant in
          variant.notes.allSatisfy { note in
              guard let chord = changes.chord(at: note.startBeat) else { return false }
              return chord.symbol.scalePitchClasses.contains(((Int(note.note) % 12) + 12) % 12)
          }
      })

// Displacement keeps the chords and moves them.
let shifted = compVariants.filter { $0.name.contains("shifted") }
check("some variants move the parent's hits", !shifted.isEmpty)
check("and nothing sounds past its own chord",
      shifted.allSatisfy { variant in
          variant.notes.allSatisfy { note in
              guard let chord = changes.chord(at: note.startBeat) else { return false }
              return note.startBeat + note.durationBeats
                  <= chord.startBeat + chord.durationBeats + 0.01
          }
      })

// With no parent it falls back to the figure, which is what a fresh comp wants.
check("with no parent it still offers something",
      !MelodyComping.variants(of: changes, figure: .charleston, seed: 5).isEmpty)
check("names are distinct", Set(compVariants.map(\.name)).count == compVariants.count)

// The bug this exists to prevent, stated precisely. Extraction itself keeps
// every note — it's the *transforms* and realization that assume one note per
// onset, so a comp routed through the melodic variant path survives being read
// and is flattened the moment anything is done to it.
let flattened = MelodyPatterns.extract(from: comp, over: changes, name: "flattened")
check("extraction keeps every note of a comp", flattened?.notes.count == comp.count,
      "\(flattened?.notes.count ?? 0) from \(comp.count)")
if let flattened {
    let transformed = MelodyTransforms.displace(flattened, byEighths: 1)
    check("but a transform flattens it, because a pattern is one note per onset",
          transformed.notes.count < flattened.notes.count,
          "\(transformed.notes.count) from \(flattened.notes.count)")
    // Realization doesn't drop them — it collapses them. `monophonic` clips each
    // note to the next one's start, and inside a chord that distance is zero, so
    // every voice but the last becomes a 0.05-beat sliver. Audibly the same as
    // losing them, and harder to notice in a note count.
    let realized = MelodyPatterns.realize(flattened, over: changes)
    let slivers = realized.filter { $0.durationBeats <= 0.06 }.count
    check("and realizing it collapses the voices to slivers",
          slivers > realized.count / 2,
          "\(slivers) of \(realized.count) notes are 0.05 beats long")
}

// And the variant material distinguishes the two kinds so the wrong transforms
// can't be applied.
let lineVariant = MelodyVariant(pattern: MelodyPhrases.compose(bars: 4, seed: 1),
                                transform: "t", novelty: 0.5, styleDistance: 0, variety: 0.5)
let compVariant = MelodyVariant(voiced: comp, name: "c", summary: "s", transform: "t",
                                novelty: 0.5, variety: 0.5)
check("a line variant carries a pattern", lineVariant.material.patternIfLine != nil)
check("a comp variant does not", compVariant.material.patternIfLine == nil)

// MARK: - Voicing what a model chose

print()
print("── the half the model doesn't do ──────────────────")

// The model gives when and which tones; everything else is arithmetic. These are
// the shapes it would plausibly return, including the ones it would get wrong.
let modelHits: [CompingVoicer.Hit] = [
    (startEighth: 0, lengthEighths: 3, degrees: [2, 4, 6], velocity: 90),
    (startEighth: 3, lengthEighths: 2, degrees: [6, 1, 2], velocity: 78),
    (startEighth: 8, lengthEighths: 4, degrees: [2, 6, 5], velocity: 96),
    (startEighth: 16, lengthEighths: 6, degrees: [0, 2, 4, 6], velocity: 88),
    (startEighth: 24, lengthEighths: 4, degrees: [2, 4, 6, 1], velocity: 84)
]
let voiced = CompingVoicer.voice(modelHits, over: changes)

check("chosen degrees become a voiced part", !voiced.isEmpty, "\(voiced.count) notes")
check("and it's polyphonic", MelodyComping.maximumPolyphony(of: voiced) >= 3,
      "up to \(MelodyComping.maximumPolyphony(of: voiced)) voices")
check("every note belongs to the chord it's under",
      voiced.allSatisfy { note in
          guard let chord = changes.chord(at: note.startBeat) else { return false }
          return chord.symbol.scalePitchClasses.contains(((Int(note.note) % 12) + 12) % 12)
      })
check("nothing sounds into the next chord",
      voiced.allSatisfy { note in
          guard let chord = changes.chords.first(where: {
              note.startBeat >= $0.startBeat - 0.001
                  && note.startBeat < $0.startBeat + $0.durationBeats - 0.001
          }) else { return true }
          return note.startBeat + note.durationBeats <= chord.startBeat + chord.durationBeats + 0.01
      })
check("it lands in a playable register",
      voiced.allSatisfy { $0.note >= 36 && $0.note <= 96 },
      "range \(voiced.map(\.note).min() ?? 0)–\(voiced.map(\.note).max() ?? 0)")
check("voicing is deterministic", CompingVoicer.voice(modelHits, over: changes) == voiced)

// The whole reason this isn't the model's job: successive voicings have to stay
// near each other, and nothing in a language model is keeping them there.
func chordAt(_ beat: Double, _ notes: [SequencedNote]) -> [Int] {
    notes.filter { abs($0.startBeat - beat) < 0.001 }.map { Int($0.note) }.sorted()
}
let successive = [0.0, 1.5, 4.0, 8.0, 12.0].map { chordAt($0, voiced) }.filter { !$0.isEmpty }
let jumps = zip(successive, successive.dropFirst()).map { before, after in
    after.reduce(0) { total, pitch in
        total + (before.map { abs(pitch - $0) }.min() ?? 12)
    }
}
check("successive voicings stay near each other",
      jumps.allSatisfy { $0 <= 14 }, "movement per change: \(jumps)")

// And the failure modes a model actually produces.
check("a hit with one tone is skipped rather than played as a single note",
      CompingVoicer.pitches(for: [2], of: try ChordProgression.parseChordSymbol("Dm7")) == nil)
check("duplicate degrees collapse rather than doubling",
      (CompingVoicer.pitches(for: [2, 2, 6], of: try ChordProgression.parseChordSymbol("Dm7"))?.count ?? 0) == 2)
check("a degree past the scale wraps an octave up",
      (CompingVoicer.pitches(for: [0, 7], of: try ChordProgression.parseChordSymbol("Dm7"))?
        .max() ?? 0)
        - (CompingVoicer.pitches(for: [0, 7], of: try ChordProgression.parseChordSymbol("Dm7"))?
        .min() ?? 0) == 12)
check("hits past the end of the form are dropped",
      CompingVoicer.voice([(startEighth: 900, lengthEighths: 2, degrees: [2, 6], velocity: 90)],
                          over: changes).isEmpty)
check("a negative onset is dropped rather than wrapped",
      CompingVoicer.voice([(startEighth: -4, lengthEighths: 2, degrees: [2, 6], velocity: 90)],
                          over: changes).isEmpty)

// MARK: - What the model is told

print()
print("── a brief is not a figure ────────────────────────")

// The distinction the first version collapsed. A figure is a pattern and belongs
// to the deterministic path; a brief is a character and belongs to the model.
// If a brief can be executed rather than interpreted, it's a figure wearing the
// wrong hat.
for figure in CompingFigure.all {
    let brief = CompingBriefs.brief(for: figure.name)
    check("\(figure.name) has a brief", !brief.isEmpty)
    check("\(figure.name)'s brief doesn't name beats",
          !brief.contains("beat one") && !brief.contains("and of two")
            && !brief.lowercased().contains("eighth"),
          brief.prefix(48) + "…")
    check("\(figure.name)'s brief differs from its figure's summary",
          brief != figure.summary)
}
check("an unknown template still gets a brief",
      !CompingBriefs.brief(for: "nothing").isEmpty)
check("the briefs are distinct",
      Set(CompingFigure.all.map { CompingBriefs.brief(for: $0.name) }).count
        == CompingFigure.all.count)

// And the rotation, which is the other half of why every take came out alike.
check("there are several angles", CompingBriefs.angles.count >= 5)
check("they're distinct", Set(CompingBriefs.angles).count == CompingBriefs.angles.count)
check("the rotation wraps",
      CompingBriefs.angle(at: 0) == CompingBriefs.angle(at: CompingBriefs.angles.count))
check("and handles a negative cursor", !CompingBriefs.angle(at: -3).isEmpty)
check("successive takes get different nudges",
      CompingBriefs.angle(at: 0) != CompingBriefs.angle(at: 1))

// A chord template carries both objects, because they do different jobs.
let chordTemplate = MelGenTemplates.chords.first { $0.name == CompingFigure.pad.name }
check("a chord template has a figure for the deterministic path",
      chordTemplate?.figure != nil)
check("and a brief for the model", chordTemplate?.brief != nil)
check("and they say different things",
      chordTemplate?.brief?.text != chordTemplate?.figure?.summary)

// MARK: - Harmonising a mono line (mode-aware realize)

// Every deterministic source makes a monophonic pattern, so chord mode has to
// put voicings under one. Each hit is a simultaneity of *one* note, which is why
// re-voicing without a voice count returns a line unchanged.
let monoLine: [SequencedNote] = [
    SequencedNote(note: 66, velocity: 90, startBeat: 0, durationBeats: 1),
    SequencedNote(note: 69, velocity: 88, startBeat: 1, durationBeats: 1),
    SequencedNote(note: 71, velocity: 92, startBeat: 2, durationBeats: 2),
]
let harmonyChanges = try ChordProgression.parse("F♯m7 | Bm7")
let lineKeptMono = MelodyComping.revoice(monoLine, over: harmonyChanges, as: .rootlessA)
check("re-voicing a mono line without a voice count leaves it mono",
      MelodyComping.maximumPolyphony(of: lineKeptMono) == 1,
      "\(MelodyComping.maximumPolyphony(of: lineKeptMono)) voices")

let lineAsChords = MelodyComping.revoice(monoLine, over: harmonyChanges, as: .rootlessA, voices: 3)
check("asking for three voices harmonises it",
      MelodyComping.maximumPolyphony(of: lineAsChords) == 3,
      "\(MelodyComping.maximumPolyphony(of: lineAsChords)) voices")
check("harmonising keeps the line's rhythm",
      Set(lineAsChords.map(\.startBeat)) == Set(monoLine.map(\.startBeat)),
      "\(Set(lineAsChords.map(\.startBeat)).sorted())")
check("harmonising keeps the line's note lengths",
      lineAsChords.allSatisfy { voiced in
          monoLine.contains { abs($0.startBeat - voiced.startBeat) < 1e-9
                              && abs($0.durationBeats - voiced.durationBeats) < 1e-9 }
      })
check("every harmonised note fits the chord under it",
      lineAsChords.allSatisfy { note in
          guard let chord = harmonyChanges.chord(at: note.startBeat) else { return false }
          let pc = ((Int(note.note) % 12) + 12) % 12
          return chord.symbol.scalePitchClasses.contains(pc)
              || chord.symbol.tonePitchClasses.contains(pc)
      })

// MARK: - Taxicab voice leading, against the suite's shared vectors

// The one place MelGen and the suite must agree note for note. The vectors are
// the same file the TypeScript, Lua and C++ implementations are held to, so a
// divergence here is a divergence between plug-ins rather than a local bug.
print()
print("── taxicab leading, against the suite's vectors ────")

struct VectorFile: Decodable {
    struct Case: Decodable {
        let name: String
        let from: [Int]
        let to: [Int]
        let size: Int
    }
    let cases: [Case]
}

if let path = ProcessInfo.processInfo.environment["VOICE_LEADING_VECTORS"],
   let data = FileManager.default.contents(atPath: path),
   let vectors = try? JSONDecoder().decode(VectorFile.self, from: data) {
    for vector in vectors.cases {
        let size = VoiceLeading.size(from: vector.from, to: vector.to)
        check("\(vector.name)", size == vector.size, "got \(size), expected \(vector.size)")
        // The suite documents the measure as symmetric, so the port has to be.
        check("\(vector.name), the other way round",
              VoiceLeading.size(from: vector.to, to: vector.from) == vector.size)
    }
    check("the vectors were found", !vectors.cases.isEmpty, "\(vectors.cases.count) cases")
} else {
    check("the suite's voice-leading vectors are readable", false,
          ProcessInfo.processInfo.environment["VOICE_LEADING_VECTORS"] ?? "VOICE_LEADING_VECTORS unset")
}

// MARK: - Leading actual notes rather than pitch classes

print()
print("── leading notes ──────────────────────────────────")

let cmaj: [Int] = [60, 64, 67]
let smoothToF = VoiceLeading.led(from: cmaj, to: [5, 9, 0], range: ChordVoicings.range)
check("a leading covers every tone of the target chord",
      classes(smoothToF) == Set([5, 9, 0]), names(smoothToF))
check("no voice moves more than a tritone",
      smoothToF.allSatisfy { note in cmaj.contains { abs($0 - note) <= 6 } },
      names(smoothToF))
check("the common tone doesn't move at all", smoothToF.contains(60), names(smoothToF))
check("taxicab leading moves less than transposing the chord",
      VoiceLeading.movement(from: cmaj, to: smoothToF)
          <= VoiceLeading.movement(from: cmaj, to: cmaj.map { $0 + 5 }),
      "\(VoiceLeading.movement(from: cmaj, to: smoothToF)) vs \(VoiceLeading.movement(from: cmaj, to: cmaj.map { $0 + 5 }))")

let smoothToBigger = VoiceLeading.led(from: cmaj, to: [2, 5, 9, 0], range: ChordVoicings.range)
check("leading to a bigger chord still states all of it",
      classes(smoothToBigger) == Set([2, 5, 9, 0]), names(smoothToBigger))
check("and doesn't double anything",
      Set(smoothToBigger).count == smoothToBigger.count, names(smoothToBigger))

// MARK: - Smooth mode moves less than register mode, over a real progression

// The complaint this answers: with register leading every chord is the same
// shape transposed, so the top voice tracks the root and it sounds like one
// voicing being moved around. Smooth leading has to actually move less.
let smoothChanges = try ChordProgression.parse("Dm7 | G7 | Cmaj7 | A7♭13")
var totals: [VoiceLeadingMode: Int] = [:]
for mode in VoiceLeadingMode.allCases {
    let voicings = ChordVoicings.voiceLead(smoothChanges, style: .rootlessA, leading: mode)
    var total = 0
    for (previous, next) in zip(voicings, voicings.dropFirst()) {
        total += VoiceLeading.movement(from: previous.pitches, to: next.pitches)
    }
    totals[mode] = total
    check("\(mode.label) voices every chord",
          voicings.count == smoothChanges.chords.count && voicings.allSatisfy { !$0.isEmpty })
    check("\(mode.label) states each chord correctly",
          zip(voicings, smoothChanges.chords).allSatisfy { voicing, placed in
              classes(voicing.pitches).isSubset(of: Set(placed.symbol.scalePitchClasses.map {
                  (($0 % 12) + 12) % 12
              }))
          })
}
check("smooth leading moves less than register leading",
      (totals[.smooth] ?? .max) < (totals[.register] ?? 0),
      "smooth \(totals[.smooth] ?? -1) vs register \(totals[.register] ?? -1)")
check("register leading moves less than none",
      (totals[.register] ?? .max) <= (totals[VoiceLeadingMode.none] ?? 0),
      "register \(totals[.register] ?? -1) vs none \(totals[VoiceLeadingMode.none] ?? -1)")

// A comp asked for smooth leading has to actually be smoother, end to end.
var compMovement: [VoiceLeadingMode: Int] = [:]
for mode in VoiceLeadingMode.allCases {
    let notes = MelodyComping.comp(smoothChanges, figure: .pad, leading: mode)
    let groups = MelodyComping.simultaneities(in: notes)
    var total = 0
    for (previous, next) in zip(groups, groups.dropFirst()) {
        total += VoiceLeading.movement(from: previous.map { Int($0.note) },
                                       to: next.map { Int($0.note) })
    }
    compMovement[mode] = total
    check("a \(mode.label) comp produces chords",
          MelodyComping.maximumPolyphony(of: notes) >= 3,
          "\(MelodyComping.maximumPolyphony(of: notes)) voices")
}
check("a smooth comp moves less than a register comp",
      (compMovement[.smooth] ?? .max) < (compMovement[.register] ?? 0),
      "smooth \(compMovement[.smooth] ?? -1) vs register \(compMovement[.register] ?? -1)")

// MARK: - Lines lead too

// In line mode voice leading is about the seams: a note landing on a chord
// change should reach for the near chord tone rather than leaping because its
// degree happens to point somewhere else.
print()
print("── leading a line across the changes ──────────────")

let leaps = try ChordProgression.parse("Cmaj7 | F♯maj7")
let sawtooth = MelodyPattern(
    name: "seam test", bars: 1,
    summary: "one note per beat, on a degree that isn't a chord tone",
    notes: (0..<8).map { PatternNote(startEighth: $0 * 2, lengthEighths: 2, degree: 5, velocity: 90) })
let plainLine = MelodyPatterns.realize(sawtooth, over: leaps, leading: VoiceLeadingMode.none)
let ledLine = MelodyPatterns.realize(sawtooth, over: leaps, leading: .smooth)
func biggestLeap(_ notes: [SequencedNote]) -> Int {
    zip(notes, notes.dropFirst()).map { abs(Int($1.note) - Int($0.note)) }.max() ?? 0
}
check("leading a line keeps every note", ledLine.count == plainLine.count,
      "\(ledLine.count) vs \(plainLine.count)")
check("leading a line keeps its rhythm",
      Set(ledLine.map(\.startBeat)) == Set(plainLine.map(\.startBeat)))
check("the seam at the chord change is no wider than it was",
      biggestLeap(ledLine) <= biggestLeap(plainLine),
      "\(biggestLeap(ledLine)) vs \(biggestLeap(plainLine)) semitones")
// The point of leading a line: the note that lands on the change is on the
// chord, rather than beside it by an accident of degree arithmetic.
func onChordAtChanges(_ notes: [SequencedNote]) -> Int {
    var count = 0
    var lastChordStart: Double?
    for note in notes.sorted(by: { $0.startBeat < $1.startBeat }) {
        guard let chord = leaps.chord(at: note.startBeat) else { continue }
        defer { lastChordStart = chord.startBeat }
        guard chord.startBeat != lastChordStart else { continue }
        let pc = ((Int(note.note) % 12) + 12) % 12
        if chord.symbol.tonePitchClasses.map({ (($0 % 12) + 12) % 12 }).contains(pc) { count += 1 }
    }
    return count
}
check("leading a line lands on the chord at every change",
      onChordAtChanges(ledLine) == leaps.chords.count
          && onChordAtChanges(plainLine) < leaps.chords.count,
      "\(onChordAtChanges(ledLine)) vs \(onChordAtChanges(plainLine)) of \(leaps.chords.count) changes")

check("every note of a led line still belongs to its chord",
      ledLine.allSatisfy { note in
          guard let chord = leaps.chord(at: note.startBeat) else { return false }
          let pc = ((Int(note.note) % 12) + 12) % 12
          return chord.symbol.scalePitchClasses.contains(pc)
      })

print()
print(failures == 0 ? "comping: all checks passed" : "comping: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
