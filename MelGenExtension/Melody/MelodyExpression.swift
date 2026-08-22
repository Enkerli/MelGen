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

            // Note that Expression deliberately doesn't touch duration. Gate owns
            // it: shortening here as well would double-count, and it would also
            // widen the gaps that `applyGate` reads to tell a rest from
            // articulation space, inventing rests that were never written.
            shaped.append(SequencedNote(
                note: note.note,
                velocity: velocity(for: note, at: start, index: index, amount: amount, random: &random),
                startBeat: start,
                durationBeats: max(duration, 0.05)
            ))
        }

        return clean(applyGate(to: shaped, setting: settings.noteLength),
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

    /// Higher is more structurally important, so less droppable. Shared by
    /// density thinning and the breathing guarantee, so both agree about which
    /// note matters least. The tiers match
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

    /// A gap of at least this much is a rest — part of the phrasing — rather than
    /// articulation space between two notes of the same phrase.
    static let restThreshold: Double = 0.5

    /// Gate length, shaped per note.
    ///
    /// A single number can't give staccato notes *and* legato transitions, which
    /// is the combination that makes a line sound played rather than stepped. So
    /// each note gets a target gate from what happens next — stepwise motion
    /// connects, leaps detach, a repeated pitch must detach or you can't hear two
    /// notes — and the control becomes an *amount* applied to that shape: 0.5
    /// takes the shape as derived, 0 clips everything, 1 pushes toward full
    /// legato. Same structure as Expression, which shapes velocity the same way.
    ///
    /// Rests are protected. Extending into a real rest would undo the phrasing
    /// the model was asked for, so a note followed by one keeps its written
    /// length as the ceiling; only notes separated by articulation-sized gaps
    /// can reach the next note.
    private static func applyGate(to notes: [SequencedNote], setting: Double) -> [SequencedNote] {
        let amount = min(max(setting, 0), 1)

        return notes.enumerated().map { index, note in
            var note = note
            let written = note.durationBeats

            let available: Double
            let target: Double
            if index + 1 < notes.count {
                let next = notes[index + 1]
                let slot = next.startBeat - note.startBeat
                let gap = next.startBeat - (note.startBeat + written)
                // A real rest caps the note at its written length; otherwise the
                // note may reach all the way to the next one.
                available = gap >= restThreshold - 0.001 ? min(written, slot) : slot
                target = gapTarget(from: Int(note.note), to: Int(next.note))
            } else {
                available = written
                target = 0.85
            }

            // 0.5 uses the derived target; below scales it down toward a clip,
            // above pushes it up toward filling the space.
            var ratio: Double = amount < 0.5
                ? target * (0.25 + (amount / 0.5) * 0.75)
                : target + (1 - target) * ((amount - 0.5) / 0.5)

            // A repeated pitch never fills its slot, whatever the setting asks
            // for: without a gap the second note-on lands the instant the first
            // note-off does, and most synths render that as one held note rather
            // than two. Legato between two of the same note isn't legato, it's a
            // missing note.
            if index + 1 < notes.count, notes[index + 1].note == note.note {
                ratio = min(ratio, 0.85)
            }

            note.durationBeats = max(available * ratio, 0.05)
            return note
        }
    }

    /// How much of its slot a note should sound, given the move to the next one.
    private static func gapTarget(from pitch: Int, to nextPitch: Int) -> Double {
        let interval = abs(nextPitch - pitch)
        switch interval {
        case 0:      return 0.55   // repeated pitch: needs a clear break
        case 1...2:  return 0.95   // step: connect
        case 3...4:  return 0.85
        case 5...7:  return 0.75
        default:     return 0.65   // wide leap: detach
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
    /// Guarantees the line comes up for air.
    ///
    /// Asking for rests in the prompt and in the schema both help, but neither is
    /// a guarantee, and a wall of notes is the single thing that makes a
    /// generated line sound machine-made. So every two bars that contains no gap
    /// worth hearing gets one, by dropping its least structurally important note
    /// — the same ranking density thinning uses.
    static func ensureBreathing(_ notes: [SequencedNote],
                                totalBeats: Double,
                                windowBeats: Double = 8,
                                minimumRest: Double = 0.5) -> [SequencedNote] {
        guard notes.count > 2, totalBeats > 0 else { return notes }

        var kept = notes
        var windowStart = 0.0
        while windowStart < totalBeats - 0.001 {
            let windowEnd = min(windowStart + windowBeats, totalBeats)
            let indices = kept.indices.filter {
                kept[$0].startBeat >= windowStart - 0.001 && kept[$0].startBeat < windowEnd - 0.001
            }
            // One note in a window is already mostly silence.
            guard indices.count > 2 else {
                windowStart = windowEnd
                continue
            }

            let breathes = indices.contains { index in
                let note = kept[index]
                let nextStart = index + 1 < kept.count ? kept[index + 1].startBeat : windowEnd
                return nextStart - (note.startBeat + note.durationBeats) >= minimumRest - 0.001
            }
            if !breathes, let weakest = indices.dropFirst().min(by: {
                let left = metricWeight(kept[$0])
                let right = metricWeight(kept[$1])
                return left == right ? kept[$0].durationBeats < kept[$1].durationBeats : left < right
            }) {
                kept.remove(at: weakest)
                // Re-examine this window: removing a note may not have been enough.
                continue
            }
            windowStart = windowEnd
        }
        return kept
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
