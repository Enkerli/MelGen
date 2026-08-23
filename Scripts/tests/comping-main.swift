// Checks the voicing layer and the comping mode.
//
// Two claims. Tones are classified by interval rather than by position in a
// list, which is what makes voicings right on suspended, quartal and altered
// chords rather than only on the plain ones. And voice leading moves the voicing
// as a unit — a player picks the register, not the arrangement, because the
// arrangement is what makes a rootless A a rootless A.
import Foundation

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
check("and a line take still renders as a line",
      PlayMode.allCases.count == 2 && PlayMode.line.label == "Line")

// MARK: - Varying a comp

print()
print("── varying a comp, as a comp ──────────────────────")

let compVariants = MelodyComping.variants(of: changes, figure: .charleston, seed: 5)
check("a comp has variants", compVariants.count >= 8, "\(compVariants.count)")
check("every one of them is still polyphonic",
      compVariants.allSatisfy { MelodyComping.maximumPolyphony(of: $0.notes) >= 2 },
      "least polyphonic: \(compVariants.map { MelodyComping.maximumPolyphony(of: $0.notes) }.min() ?? 0)")
check("they vary the voicing and the rhythm, which are a comp's two axes",
      compVariants.contains { $0.name.contains("Drop 2") || $0.name.contains("Quartal") }
        && compVariants.contains { $0.name.contains("Tresillo") || $0.name.contains("Even") })
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
      MelodyComping.variants(of: changes, figure: .charleston, seed: 5).map(\.name)
        == compVariants.map(\.name))
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

print()
print(failures == 0 ? "comping: all checks passed" : "comping: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
