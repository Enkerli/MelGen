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

// 11b. Density must not ask for more notes than an eighth-note bar has slots.
// Asking for 9-14 notes in an 8-slot bar is what made rests impossible.
let perBar = [0.0, 0.25, 0.5, 0.75, 1.0].map { MelodyExpression.notesPerBar(forDensity: $0) }
check("density never exceeds the 8 eighths in a bar", perBar.allSatisfy { $0 <= 8 },
      "\(perBar)")
check("the default density leaves room for rests",
      MelodyExpression.notesPerBar(forDensity: 0.5) <= 6,
      "\(MelodyExpression.notesPerBar(forDensity: 0.5)) notes in an 8-slot bar")
check("density still spans a useful range", perBar.first! < perBar.last!, "\(perBar)")

// 11c. Notation: rests and note lengths have to be readable.
let notated: [SequencedNote] = [
    SequencedNote(note: 60, velocity: 90, startBeat: 0.0, durationBeats: 1.0),  // 2 eighths
    SequencedNote(note: 64, velocity: 90, startBeat: 1.0, durationBeats: 0.5),
    // beat 1.5-3.0 is silent: a phrase rest
    SequencedNote(note: 67, velocity: 90, startBeat: 3.0, durationBeats: 1.0),
]
let rows = MelodyNotation.bars(for: notated, lengthBeats: 4)
check("notation renders one row per bar", rows.count == 1, "\(rows.count) rows")
if let row = rows.first {
    check("a rest gets its own symbol", row.contains(MelodyNotation.rest), row)
    check("a held note shows a sustain mark", row.contains(MelodyNotation.sustain), row)
    check("note names appear at their onsets",
          row.contains("C4") && row.contains("E4") && row.contains("G4"), row)
}
let notationSummary = MelodyNotation.summary(for: notated, lengthBeats: 4)
check("summary counts the rests", notationSummary.contains("1 rest"), notationSummary)
check("summary reports a gate range", notationSummary.contains("gate"), notationSummary)
check("empty take reads as empty",
      MelodyNotation.summary(for: [], lengthBeats: 4) == "No notes yet.")

// 11d. Generation timing is recorded on the take (G4) and survives saving.
var timed = MelGenState()
timed.add(GenerationRecord(progressionText: "Dm7|G7", temperature: 0.5,
                           briefName: "Sparse", generationSeconds: 4.25, requestCount: 4,
                           lengthBeats: 8, notes: raw))
let timedDecoded = try JSONDecoder().decode(
    MelGenState.self, from: try JSONEncoder().encode(timed))
check("generation timing round-trips",
      timedDecoded.currentTake?.generationSeconds == 4.25
      && timedDecoded.currentTake?.requestCount == 4)
check("takes from before timing existed read as unmeasured", {
    let legacyTake = #"{"progressionText":"C","temperature":0.5,"history":[{"progressionText":"C∆","temperature":0.5,"briefName":"x","lengthBeats":4,"notes":[]}]}"#
    let decoded = try? JSONDecoder().decode(MelGenState.self, from: Data(legacyTake.utf8))
    return decoded?.history.first?.generationSeconds == 0
        && decoded?.history.first?.requestCount == 1
}())

// 11e. Dead air is capped: a breath, not the line stopping.
let sparse: [SequencedNote] = [
    SequencedNote(note: 60, velocity: 90, startBeat: 0.0, durationBeats: 0.5),
    // six beats of nothing
    SequencedNote(note: 64, velocity: 90, startBeat: 6.5, durationBeats: 0.5),
]
let capped = MelodyExpression.capDeadAir(sparse, totalBeats: 8)
check("a six-beat gap is trimmed", capped[0].durationBeats > sparse[0].durationBeats,
      "\(sparse[0].durationBeats) → \(capped[0].durationBeats)")
let cappedGap = capped[1].startBeat - (capped[0].startBeat + capped[0].durationBeats)
check("what's left is still a real rest", cappedGap >= 1.0 - 1e-9, "gap \(cappedGap)")
check("the excess became a held note, not a drone",
      capped[0].durationBeats <= 4.0 + 1e-9, "\(capped[0].durationBeats) beats")
check("onsets are never moved", zip(capped, sparse).allSatisfy { $0.startBeat == $1.startBeat })
// The first four notes are back-to-back, so nothing to absorb. The fifth ends at
// beat 4 with the next at 7.5 — 3.5 beats of silence, which is dead air by design.
check("ordinary gaps are left alone",
      MelodyExpression.capDeadAir(raw, totalBeats: 8).prefix(4).map(\.durationBeats)
        == raw.prefix(4).map(\.durationBeats))

// 11f. The history export carries the settings and the timing.
var exportable = MelGenState()
exportable.add(GenerationRecord(progressionText: "Dm7|G7", temperature: 0.7,
                                briefName: "Sparse", generationSeconds: 11.5, requestCount: 1,
                                lengthBeats: 12, notes: raw))
let exported = try exportable.historyExportData()
let reread = try MelGenState.decodeHistoryExport(exported)
check("export round-trips the takes", reread.takes.count == 1 && reread.takeCount == 1)
check("export keeps the timing", reread.takes.first?.generationSeconds == 11.5)
check("export keeps the settings it was rendered with",
      reread.expressionAtExport == exportable.expression)
check("export filename is dated and sortable",
      exportable.historyExportFilename().hasPrefix("MelGen-history-")
      && exportable.historyExportFilename().hasSuffix(".json"),
      exportable.historyExportFilename())
// Exporting twice in a day is normal, so the name carries the time too.
let earlier = exportable.historyExportFilename(now: Date(timeIntervalSince1970: 1_700_000_000))
let later = exportable.historyExportFilename(now: Date(timeIntervalSince1970: 1_700_000_007))
check("two exports the same day don't collide", earlier != later, "\(earlier) vs \(later)")

// A take's source is recorded, so the log distinguishes an adapted line from a
// generated one.
var mixed = MelGenState()
mixed.add(GenerationRecord(progressionText: "C∆", temperature: 0.5, briefName: "Arch",
                           source: .pattern, lengthBeats: 4, notes: raw))
let mixedDecoded = try JSONDecoder().decode(MelGenState.self, from: try JSONEncoder().encode(mixed))
check("take source round-trips", mixedDecoded.currentTake?.source == .pattern)
check("takes from before sources existed read as model-generated", {
    let old = #"{"progressionText":"C","temperature":0.5,"history":[{"progressionText":"C","temperature":0.5,"briefName":"x","lengthBeats":4,"notes":[]}]}"#
    return (try? JSONDecoder().decode(MelGenState.self, from: Data(old.utf8)))?
        .history.first?.source == .model
}())

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
