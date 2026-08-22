import Foundation

func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("\(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}
var failures = 0

// A four-bar take: eighths on and off the beat, mixed lengths.
let raw: [SequencedNote] = [
    SequencedNote(note: 60, velocity: 90, startBeat: 0.0, durationBeats: 0.5),
    SequencedNote(note: 62, velocity: 90, startBeat: 0.5, durationBeats: 0.5),
    SequencedNote(note: 64, velocity: 90, startBeat: 1.0, durationBeats: 1.0),
    SequencedNote(note: 65, velocity: 90, startBeat: 2.0, durationBeats: 0.5),
    SequencedNote(note: 67, velocity: 90, startBeat: 2.5, durationBeats: 1.5),
    SequencedNote(note: 69, velocity: 90, startBeat: 7.5, durationBeats: 1.0),
]

var state = MelGenState()
state.add(GenerationRecord(
    progressionText: "Dm7 G7|C∆",
    temperature: 0.7,
    briefName: "Syncopated",
    lengthBeats: 8,
    notes: raw
))

// 1. Full-state round trip.
let encoded = try JSONEncoder().encode(state)
let decoded = try JSONDecoder().decode(MelGenState.self, from: encoded)
check("state round-trips through JSON",
      decoded.progressionText == state.progressionText
      && decoded.history.count == 1
      && decoded.currentTakeID == state.currentTakeID
      && decoded.currentTake?.notes == raw
      && decoded.expression == state.expression,
      "\(encoded.count) bytes")

// 2. Neutral settings leave the grid alone.
state.expression = ExpressionSettings(amount: 0, swing: 0)
let neutral = state.renderedMelody
check("expression 0 keeps note starts on the grid",
      zip(neutral, raw).allSatisfy { abs($0.startBeat - $1.startBeat) < 1e-9 })
check("expression 0 keeps the model's velocities",
      neutral.allSatisfy { $0.velocity == 90 })

// 3. Swing pushes offbeat eighths by up to a sixth of a beat, on-beats stay put.
state.expression = ExpressionSettings(amount: 0, swing: 1)
let swung = state.renderedMelody
let offbeatShifts = zip(swung, raw)
    .filter { Int(($1.startBeat * 2).rounded()) % 2 != 0 }
    .map { $0.0.startBeat - $0.1.startBeat }
let onbeatShifts = zip(swung, raw)
    .filter { Int(($1.startBeat * 2).rounded()) % 2 == 0 }
    .map { $0.0.startBeat - $0.1.startBeat }
check("swing delays offbeat eighths by 1/6 beat",
      offbeatShifts.allSatisfy { abs($0 - 1.0 / 6.0) < 1e-9 },
      "shifts \(offbeatShifts.map { ($0 * 1000).rounded() / 1000 })")
check("swing leaves on-beat notes alone",
      onbeatShifts.allSatisfy { abs($0) < 1e-9 })

// 4. Full expression: still monophonic, inside the loop, legal velocities.
state.expression = ExpressionSettings(amount: 1, swing: 0.6)
let shaped = state.renderedMelody
check("stays inside the loop",
      shaped.allSatisfy { $0.startBeat >= 0 && $0.startBeat + $0.durationBeats <= 8 + 1e-9 })
check("stays monophonic",
      zip(shaped, shaped.dropFirst()).allSatisfy {
          $0.startBeat + $0.durationBeats <= $1.startBeat + 1e-9
      })
check("velocities stay in MIDI range",
      shaped.allSatisfy { $0.velocity <= 127 })
check("every note keeps a positive length", shaped.allSatisfy { $0.durationBeats > 0 })
check("note count preserved", shaped.count == raw.count, "\(shaped.count) of \(raw.count)")

// 5. Accents: the downbeat should end up louder than the offbeat after it.
let downbeat = shaped.first { abs($0.startBeat) < 0.2 }?.velocity ?? 0
let offbeat = shaped.first { $0.startBeat > 0.4 && $0.startBeat < 0.8 }?.velocity ?? 0
check("downbeat is accented above the following offbeat", downbeat > offbeat,
      "downbeat \(downbeat) vs offbeat \(offbeat)")

// 6. Rendering is deterministic across runs (same take, same seed).
check("rendering is deterministic", state.renderedMelody == shaped)

// 7. History is capped and newest-first.
var big = MelGenState()
for index in 0..<(MelGenState.historyLimit + 6) {
    big.add(GenerationRecord(progressionText: "C∆", temperature: 0.5,
                             briefName: "Take \(index)", lengthBeats: 4, notes: raw))
}
check("history capped at the limit", big.history.count == MelGenState.historyLimit,
      "\(big.history.count)")
check("newest take is first and current",
      big.history.first?.briefName == "Take \(MelGenState.historyLimit + 5)"
      && big.currentTake?.id == big.history.first?.id)

// 8. Density thins the line — this is how rests get added — and never drops the
// note the line starts on.
state.expression = ExpressionSettings(amount: 0, swing: 0, noteLength: 0.5, density: 0.5)
let atGeneratedDensity = state.renderedMelody
check("density at the take's own value keeps every note",
      atGeneratedDensity.count == raw.count, "\(atGeneratedDensity.count) of \(raw.count)")

state.expression = ExpressionSettings(amount: 0, swing: 0, noteLength: 0.5, density: 0.1)
let thinned = state.renderedMelody
check("lowering density drops notes", thinned.count < raw.count,
      "\(thinned.count) of \(raw.count)")
check("thinning keeps the first note", thinned.first?.startBeat == raw.first?.startBeat)
check("thinning keeps the downbeats",
      thinned.contains { abs($0.startBeat - 0.0) < 1e-9 }
      && thinned.contains { abs($0.startBeat - 2.0) < 1e-9 })

// 9. Gate length (G3): shaped per note, and rests survive legato (G2).
state.expression = ExpressionSettings(amount: 0, swing: 0, noteLength: 0, density: 0.5)
let staccato = state.renderedMelody
check("staccato shortens every note",
      zip(staccato, raw).allSatisfy { $0.durationBeats < $1.durationBeats })

state.expression = ExpressionSettings(amount: 0, swing: 0, noteLength: 1, density: 0.5)
let legato = state.renderedMelody
check("legato never overlaps the next note",
      zip(legato, legato.dropFirst()).allSatisfy {
          $0.startBeat + $0.durationBeats <= $1.startBeat + 1e-9
      })
// The raw take runs notes back to back through beat 4, then rests until 7.5.
let articulationGaps = zip(legato, legato.dropFirst())
    .filter { $1.startBeat - ($0.startBeat + $0.durationBeats) < MelodyExpression.restThreshold }
check("legato closes articulation-sized gaps",
      articulationGaps.allSatisfy {
          abs($1.startBeat - ($0.startBeat + $0.durationBeats)) < 1e-9
      },
      "\(articulationGaps.count) connected")
// Note 4 (start 2.5, written 1.5, ends 4.0) is followed by a rest until 7.5.
if let beforeRest = legato.first(where: { abs($0.startBeat - 2.5) < 0.01 }) {
    check("legato does not swallow a rest",
          beforeRest.durationBeats <= 1.5 + 1e-9,
          "held \(beforeRest.durationBeats) of the 5.0 beats available")
} else {
    check("legato does not swallow a rest", false, "note not found")
}

// Gate is derived from what happens next: a step connects, a wide leap detaches,
// and a repeated pitch must break or you can't hear two notes.
let shapeProbe: [SequencedNote] = [
    SequencedNote(note: 60, velocity: 90, startBeat: 0.0, durationBeats: 0.5),   // step up
    SequencedNote(note: 62, velocity: 90, startBeat: 0.5, durationBeats: 0.5),   // wide leap
    SequencedNote(note: 74, velocity: 90, startBeat: 1.0, durationBeats: 0.5),   // repeat
    SequencedNote(note: 74, velocity: 90, startBeat: 1.5, durationBeats: 0.5),
    SequencedNote(note: 72, velocity: 90, startBeat: 2.0, durationBeats: 0.5),
]
var probeState = MelGenState()
probeState.add(GenerationRecord(progressionText: "C∆", temperature: 0.5,
                                briefName: "probe", lengthBeats: 4, notes: shapeProbe))
probeState.expression = ExpressionSettings(amount: 0, swing: 0, noteLength: 0.5, density: 0.5)
let shaped2 = probeState.renderedMelody
if shaped2.count >= 4 {
    check("a step is held longer than a wide leap",
          shaped2[0].durationBeats > shaped2[1].durationBeats,
          "step \(shaped2[0].durationBeats) vs leap \(shaped2[1].durationBeats)")
    check("a repeated pitch gets the shortest gate",
          shaped2[2].durationBeats < shaped2[0].durationBeats,
          "repeat \(shaped2[2].durationBeats) vs step \(shaped2[0].durationBeats)")
    check("even at full legato a repeated pitch still breaks", {
        probeState.expression = ExpressionSettings(amount: 0, swing: 0, noteLength: 1, density: 0.5)
        let full = probeState.renderedMelody
        return full.count > 3 && full[2].durationBeats < 0.5 - 1e-9
    }())
} else {
    check("gate shape probe produced notes", false, "\(shaped2.count) notes")
}

// 9b. The breathing guarantee (G2): a wall of notes gains a rest.
let wall = (0..<16).map {
    SequencedNote(note: UInt8(60 + $0 % 5), velocity: 90,
                  startBeat: Double($0) * 0.5, durationBeats: 0.5)
}
let breathing = MelodyExpression.ensureBreathing(wall, totalBeats: 8)
check("a wall-to-wall line gains a rest", breathing.count < wall.count,
      "\(breathing.count) of \(wall.count) notes kept")
let breathingGaps = zip(breathing, breathing.dropFirst()).map {
    $1.startBeat - ($0.startBeat + $0.durationBeats)
}
check("the gap it opens is audible",
      (breathingGaps.max() ?? 0) >= 0.5 - 1e-9,
      "largest gap \(breathingGaps.max() ?? 0)")
check("breathing keeps the first note",
      breathing.first?.startBeat == wall.first?.startBeat)
check("a line that already breathes is left alone",
      MelodyExpression.ensureBreathing(raw, totalBeats: 8).count == raw.count)

// 10. Appearance defaults to light and survives the round trip.
check("appearance defaults to light", MelGenState().appearance == .light)
var themed = MelGenState()
themed.appearance = .dark
let themedDecoded = try JSONDecoder().decode(
    MelGenState.self, from: try JSONEncoder().encode(themed))
check("appearance round-trips", themedDecoded.appearance == .dark)

// 11. State saved by an older build still opens (new keys absent).
let legacyJSON = #"{"progressionText":"Dm7|G7","temperature":0.4,"history":[]}"#
if let legacy = try? JSONDecoder().decode(MelGenState.self, from: Data(legacyJSON.utf8)) {
    check("older saved state still decodes",
          legacy.progressionText == "Dm7|G7"
          && legacy.appearance == .light
          && legacy.expression.noteLength == 0.5,
          "defaults filled in")
} else {
    check("older saved state still decodes", false, "threw")
}

// 12. Note duration is a separate axis from gate length, and round-trips.
check("duration palette defaults to mixed", MelGenState().durationPalette == .mixed)
var withPalette = MelGenState()
withPalette.durationPalette = .longShort
let paletteDecoded = try JSONDecoder().decode(
    MelGenState.self, from: try JSONEncoder().encode(withPalette))
check("duration palette round-trips", paletteDecoded.durationPalette == .longShort)
check("every duration palette has a prompt and a label",
      DurationPalette.allCases.allSatisfy { !$0.promptText.isEmpty && !$0.label.isEmpty },
      "\(DurationPalette.allCases.count) options")
check("gate length is independent of the duration palette",
      MelGenState().expression.noteLength == 0.5)

// 13. Section fold state persists.
var folded = MelGenState()
folded.showFeel = false
folded.showHistory = true
let foldedDecoded = try JSONDecoder().decode(
    MelGenState.self, from: try JSONEncoder().encode(folded))
check("section fold state round-trips",
      foldedDecoded.showFeel == false && foldedDecoded.showHistory == true
      && foldedDecoded.showShape == true)

// 14. Style briefs rotate and wrap.
let names = (0..<(StyleBriefs.all.count + 2)).map { StyleBriefs.brief(at: $0).name }
check("briefs rotate without repeating early",
      Set(names.prefix(StyleBriefs.all.count)).count == StyleBriefs.all.count)
check("brief cursor wraps", names[StyleBriefs.all.count] == names[0])

print(failures == 0 ? "\nall checks passed" : "\n\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
