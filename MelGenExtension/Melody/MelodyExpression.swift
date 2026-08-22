//
//  MelodyExpression.swift
//  MelGenExtension
//
//  Turns a take's raw notes into the notes that actually play: metric accents,
//  varied articulation, swing and a little timing looseness.
//
//  The model is good at pitches and poor at feel — it tends to return a flat
//  velocity and every note the same length. This pass supplies the feel, and
//  because it's deterministic post-processing rather than part of generation,
//  moving the controls re-renders the current take instantly instead of
//  needing a new one.
//

import Foundation

enum MelodyExpression {

    /// Applies `settings` to raw model notes. Deterministic for a given seed.
    ///
    /// - Parameter generatedDensity: the density the take was generated at. The
    ///   density control can thin below it but can't invent notes above it.
    static func apply(to notes: [SequencedNote],
                      settings: ExpressionSettings,
                      generatedDensity: Double,
                      lengthBeats: Double,
                      seed: UInt64) -> [SequencedNote] {
        guard !notes.isEmpty else { return [] }

        let amount = min(max(settings.amount, 0), 1)
        let swing = min(max(settings.swing, 0), 1)
        var random = SplitMix64(seed: seed)

        let sorted = thin(notes.sorted { $0.startBeat < $1.startBeat },
                          to: settings.density,
                          generatedDensity: generatedDensity)

        var shaped: [SequencedNote] = []
        shaped.reserveCapacity(sorted.count)

        for (index, note) in sorted.enumerated() {
            var start = note.startBeat
            var duration = note.durationBeats

            // Swing: an offbeat eighth lands two thirds of the way through the
            // beat instead of half, so delay it by up to a sixth of a beat.
            let eighth = (start * 2).rounded()
            let isOffbeatEighth = Int(eighth) % 2 != 0
            if isOffbeatEighth {
                let push = swing / 6.0
                start += push
                duration = max(duration - push, 0.05)
            }

            // Timing looseness: a few milliseconds either side at full amount.
            let jitter = (random.nextUnit() - 0.5) * 0.02 * amount
            start = max(0, start + jitter)

            // Articulation: short notes get more air than long ones, so the
            // line breathes instead of running together.
            let gapFraction = duration <= 0.5 ? 0.22 : (duration <= 1.0 ? 0.12 : 0.05)
            duration *= 1 - gapFraction * amount

            shaped.append(SequencedNote(
                note: note.note,
                velocity: velocity(for: note, at: start, index: index, amount: amount, random: &random),
                startBeat: start,
                durationBeats: max(duration, 0.05)
            ))
        }

        return clean(applyNoteLength(to: shaped, noteLength: settings.noteLength),
                     lengthBeats: lengthBeats)
    }

    /// Drops notes to bring a take down to the requested density, which is how
    /// rests appear. Weakest positions go first — offbeats before beats,
    /// shortest before longest — and the first note is always kept so the line
    /// still starts where it did.
    private static func thin(_ notes: [SequencedNote],
                             to density: Double,
                             generatedDensity: Double) -> [SequencedNote] {
        let requested = min(max(density, 0), 1)
        guard notes.count > 1, generatedDensity > 0, requested < generatedDensity else {
            return notes
        }

        // Keep the same proportion of notes as the density shortfall, never
        // going below a quarter of the line.
        let keepRatio = max(requested / generatedDensity, 0.25)
        let keepCount = max(1, Int((Double(notes.count) * keepRatio).rounded()))
        guard keepCount < notes.count else { return notes }

        let ranked = notes.indices.dropFirst().sorted { left, right in
            let weightLeft = metricWeight(notes[left])
            let weightRight = metricWeight(notes[right])
            if weightLeft != weightRight { return weightLeft < weightRight }
            return notes[left].durationBeats < notes[right].durationBeats
        }
        let dropped = Set(ranked.prefix(notes.count - keepCount))
        return notes.indices.filter { !dropped.contains($0) }.map { notes[$0] }
    }

    /// Higher is more structurally important, so less droppable. The tiers match
    /// the accent hierarchy in `velocity(for:...)`: the downbeat carries the bar,
    /// beat 3 is the secondary strong beat, then the remaining beats, then
    /// offbeats. Without the separate beat-3 tier, thinning drops the middle of
    /// the bar before a weaker beat that merely happens to be longer.
    private static func metricWeight(_ note: SequencedNote) -> Int {
        let positionInBar = note.startBeat.truncatingRemainder(dividingBy: 4)
        if positionInBar < 0.05 { return 4 }                                  // downbeat
        if abs(positionInBar - 2) < 0.05 { return 3 }                         // beat 3
        if abs(positionInBar.rounded() - positionInBar) < 0.05 { return 2 }   // beat 2 or 4
        return 1                                                              // offbeat
    }

    /// Staccato below the midpoint, as written at it, legato above: at 1 each
    /// note runs right up to the next one.
    private static func applyNoteLength(to notes: [SequencedNote], noteLength: Double) -> [SequencedNote] {
        let setting = min(max(noteLength, 0), 1)
        guard abs(setting - 0.5) > 0.001 else { return notes }

        return notes.enumerated().map { index, note in
            var note = note
            if setting < 0.5 {
                // 0 → a quarter of the written length, 0.5 → unchanged.
                let scale = 0.25 + (setting / 0.5) * 0.75
                note.durationBeats = max(note.durationBeats * scale, 0.05)
            } else if index + 1 < notes.count {
                let gap = notes[index + 1].startBeat - note.startBeat
                if gap > note.durationBeats {
                    let reach = (setting - 0.5) / 0.5
                    note.durationBeats += (gap - note.durationBeats) * reach
                }
            }
            return note
        }
    }

    /// Metric accent plus a little variation: downbeats loudest, offbeats
    /// softest, long notes leaned into.
    private static func velocity(for note: SequencedNote,
                                 at start: Double,
                                 index: Int,
                                 amount: Double,
                                 random: inout SplitMix64) -> UInt8 {
        let base = Double(note.velocity)

        let positionInBar = start.truncatingRemainder(dividingBy: 4)
        let isDownbeat = positionInBar < 0.05
        let isOnBeat = abs(positionInBar.rounded() - positionInBar) < 0.05
        let accent: Double
        if isDownbeat {
            accent = 14
        } else if isOnBeat {
            accent = positionInBar == 2 ? 7 : 2   // beat 3 is the secondary strong beat
        } else {
            accent = -9
        }

        let lengthBonus = note.durationBeats >= 1.5 ? 5.0 : 0
        let variation = (random.nextUnit() - 0.5) * 12

        let shaped = base + (accent + lengthBonus + variation) * amount
        return UInt8(clamping: Int(shaped.rounded()))
    }

    /// Keeps the line monophonic and inside the loop after notes have moved.
    private static func clean(_ notes: [SequencedNote], lengthBeats: Double) -> [SequencedNote] {
        var result: [SequencedNote] = []
        result.reserveCapacity(notes.count)

        for (index, note) in notes.enumerated() {
            var note = note
            if index + 1 < notes.count {
                let room = notes[index + 1].startBeat - note.startBeat
                if room > 0 {
                    note.durationBeats = min(note.durationBeats, room)
                }
            }
            if lengthBeats > 0 {
                guard note.startBeat < lengthBeats else { continue }
                note.durationBeats = min(note.durationBeats, lengthBeats - note.startBeat)
            }
            guard note.durationBeats > 0 else { continue }
            result.append(note)
        }
        return result
    }
}

/// Small deterministic generator, so a take always renders the same way.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// A value in 0..<1.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
