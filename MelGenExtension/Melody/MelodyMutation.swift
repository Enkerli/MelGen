//
//  MelodyMutation.swift
//  MelGenExtension
//
//  Transforms, scoring, and the morph between two lines.
//
//  This is curation pointed at variants rather than at takes, and it's the loop
//  worth building because the human stays in it: take a line, produce a dozen
//  mutations of it, score them against the material that's been kept, listen to
//  the survivors, then dial between two you like and mark the point where it
//  becomes the thing you wanted. The slider generates candidates; the
//  dispositions are the fitness function; the pass structure means the answer is
//  allowed to change next week.
//
//  Everything here is deterministic and free of any model. The transforms are the
//  suite's "stage 0" list from the GloriArp brief — displacement, substitution,
//  density adjustment, inversion, retrograde, ornament insertion, register
//  displacement — plus `applyRhythm`, ported from `@enkerli/accompaniment`'s
//  rhythm.ts: keep a line's pitch material and perform it on a different onset
//  grid. That one is the most direct answer to "there isn't enough variety in
//  rhythm" available anywhere in this codebase, because it decouples the two
//  axes completely.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

// MARK: - Rhythms to borrow

/// An onset grid to perform a line on, as a mask over equal steps.
///
/// The suite expresses these in UPI notation and generates them from Euclidean
/// and polygonal constructions; this carries the plain data those produce, plus
/// enough of a Euclidean generator to be useful without the notation.
struct RhythmSpec: Hashable, Sendable {
    /// One entry per step; true is an onset. Leftmost is step 0, as everywhere
    /// else in the suite.
    var steps: [Bool]
    /// Optional accents, aligned to `steps`.
    var accents: [Bool]
    var label: String

    init(steps: [Bool], accents: [Bool] = [], label: String) {
        self.steps = steps
        self.accents = accents
        self.label = label
    }

    var onsetCount: Int { steps.filter { $0 }.count }
    var onsetIndices: [Int] { steps.enumerated().compactMap { $1 ? $0 : nil } }

    /// Bjorklund's algorithm: `pulses` onsets spread as evenly as possible over
    /// `steps`. E(3,8) is the tresillo, E(5,8) the cinquillo, E(2,5) a limp —
    /// the whole family of rhythms that sound deliberate without being square.
    static func euclidean(pulses: Int, steps stepCount: Int, rotation: Int = 0) -> RhythmSpec {
        let stepCount = max(1, stepCount)
        let pulses = max(0, min(pulses, stepCount))
        var pattern = [Bool](repeating: false, count: stepCount)
        guard pulses > 0 else { return RhythmSpec(steps: pattern, label: "E(0,\(stepCount))") }

        // The Bresenham form: a step carries an onset when the running line
        // crosses an integer. Same family of rhythms Bjorklund's recursion
        // produces, in a tenth the code, and it puts an onset on step 0 — which
        // matters, because E(3,8) has to come out as the tresillo people mean
        // (x..x..x.) rather than a rotation of it that sounds like a mistake.
        for index in 0..<stepCount where (index * pulses) % stepCount < pulses {
            pattern[index] = true
        }
        if rotation != 0 {
            let shift = ((rotation % stepCount) + stepCount) % stepCount
            pattern = Array(pattern[shift...] + pattern[..<shift])
        }
        return RhythmSpec(steps: pattern,
                          label: rotation == 0 ? "E(\(pulses),\(stepCount))"
                                               : "E(\(pulses),\(stepCount),\(rotation))")
    }

    /// The ones worth reaching for, named.
    static let vocabulary: [RhythmSpec] = [
        .euclidean(pulses: 3, steps: 8),
        .euclidean(pulses: 5, steps: 8),
        .euclidean(pulses: 3, steps: 8, rotation: 2),
        .euclidean(pulses: 2, steps: 5),
        .euclidean(pulses: 5, steps: 16),
        .euclidean(pulses: 7, steps: 16),
        .euclidean(pulses: 4, steps: 9),
        .euclidean(pulses: 3, steps: 4)
    ]
}

// MARK: - Transforms

enum MelodyTransforms {

    /// Shifts every onset, wrapping inside the pattern's bars.
    ///
    /// The cheapest transform and often the most effective: the same figure an
    /// eighth later is a different musical idea, which is most of what
    /// syncopation is.
    static func displace(_ pattern: MelodyPattern, byEighths shift: Int) -> MelodyPattern {
        let span = max(1, pattern.bars * 8)
        var moved = pattern
        moved.notes = pattern.notes.map { note in
            var copy = note
            copy.startEighth = ((note.startEighth + shift) % span + span) % span
            return copy
        }
        moved.name = pattern.name + " ⟩\(shift)"
        return tidy(moved)
    }

    /// Nudges degrees to neighbours, leaving the rhythm exactly alone.
    ///
    /// - Parameter amount: 0 changes nothing, 1 moves every note.
    static func substituteDegrees(_ pattern: MelodyPattern,
                                  amount: Double,
                                  seed: UInt64) -> MelodyPattern {
        var rng = SplitMix64(seed: seed)
        var mutated = pattern
        mutated.notes = pattern.notes.map { note in
            var copy = note
            guard rng.nextUnit() < amount else { return copy }
            // A step, not a leap: a substitution that jumps is a different line
            // rather than a variation of this one.
            copy.degree += rng.nextUnit() < 0.5 ? -1 : 1
            return copy
        }
        mutated.name = pattern.name + " ~deg"
        return mutated
    }

    /// Redraws note lengths, leaving pitches and onsets alone.
    static func substituteDurations(_ pattern: MelodyPattern,
                                    amount: Double,
                                    seed: UInt64,
                                    palette: [Int] = [1, 2, 3, 4, 6]) -> MelodyPattern {
        var rng = SplitMix64(seed: seed)
        var mutated = pattern
        mutated.notes = pattern.notes.map { note in
            var copy = note
            guard rng.nextUnit() < amount, !palette.isEmpty else { return copy }
            copy.lengthEighths = palette[Int(rng.next() % UInt64(palette.count))]
            return copy
        }
        mutated.name = pattern.name + " ~dur"
        return tidy(mutated)
    }

    /// Thins or thickens, weakest metric positions first.
    ///
    /// The same ranking density thinning already uses, so a thinned variant and a
    /// thinned take lose the same notes — which is what makes the two comparable.
    static func adjustDensity(_ pattern: MelodyPattern, to target: Double, seed: UInt64) -> MelodyPattern {
        guard !pattern.notes.isEmpty else { return pattern }
        var mutated = pattern
        let wanted = max(1, Int((Double(pattern.notes.count) * max(0.2, min(2.5, target))).rounded()))

        if wanted < pattern.notes.count {
            // Weakest first: off-eighths before offbeats before downbeats.
            let ranked = pattern.notes.enumerated().sorted { left, right in
                metricWeight(left.element.startEighth) < metricWeight(right.element.startEighth)
            }
            let dropped = Set(ranked.prefix(pattern.notes.count - wanted).map(\.offset))
            mutated.notes = pattern.notes.enumerated()
                .filter { !dropped.contains($0.offset) }
                .map(\.element)
        } else if wanted > pattern.notes.count {
            var rng = SplitMix64(seed: seed)
            var added = pattern.notes
            let span = max(1, pattern.bars * 8)
            let taken = Set(pattern.notes.map(\.startEighth))
            let free = (0..<span).filter { !taken.contains($0) }
            for position in free.prefix(wanted - pattern.notes.count) {
                guard let neighbour = pattern.notes.min(by: {
                    abs($0.startEighth - position) < abs($1.startEighth - position)
                }) else { continue }
                var note = neighbour
                note.startEighth = position
                note.lengthEighths = 1
                note.restAfterEighths = 0
                note.degree += rng.nextUnit() < 0.5 ? -1 : 1
                added.append(note)
            }
            mutated.notes = added.sorted { $0.startEighth < $1.startEighth }
        }
        mutated.name = pattern.name + (wanted < pattern.notes.count ? " thinner" : " denser")
        return tidy(mutated)
    }

    /// Mirrors the shape around the first note. Rhythm untouched.
    static func invert(_ pattern: MelodyPattern) -> MelodyPattern {
        guard let first = pattern.notes.min(by: { $0.startEighth < $1.startEighth }) else { return pattern }
        var mutated = pattern
        mutated.notes = pattern.notes.map { note in
            var copy = note
            copy.degree = 2 * first.degree - note.degree
            copy.alteration = -note.alteration
            return copy
        }
        mutated.name = pattern.name + " inverted"
        return mutated
    }

    /// Plays the pitches backwards over the same rhythm.
    ///
    /// Not a time reversal — the rhythm stays put and only the pitch sequence
    /// turns round, which keeps the figure's groove and changes its argument.
    static func retrograde(_ pattern: MelodyPattern) -> MelodyPattern {
        let ordered = pattern.notes.sorted { $0.startEighth < $1.startEighth }
        guard ordered.count > 1 else { return pattern }
        var mutated = pattern
        mutated.notes = ordered.enumerated().map { index, note in
            var copy = note
            let source = ordered[ordered.count - 1 - index]
            copy.degree = source.degree
            copy.alteration = source.alteration
            copy.octave = source.octave
            return copy
        }
        mutated.name = pattern.name + " retrograde"
        return mutated
    }

    /// Slips a chromatic approach in front of the notes that get landed on.
    ///
    /// Only where there's room — an ornament that displaces the note it
    /// ornaments isn't one.
    static func ornament(_ pattern: MelodyPattern, amount: Double, seed: UInt64) -> MelodyPattern {
        var rng = SplitMix64(seed: seed)
        let ordered = pattern.notes.sorted { $0.startEighth < $1.startEighth }
        var result: [PatternNote] = []

        for (index, note) in ordered.enumerated() {
            let previousEnd = index > 0
                ? ordered[index - 1].startEighth + ordered[index - 1].lengthEighths
                : 0
            let room = note.startEighth - previousEnd
            // A landing note is one on a strong beat with air in front of it.
            if room >= 1, note.startEighth.isMultiple(of: 2), rng.nextUnit() < amount {
                var approach = note
                approach.startEighth = note.startEighth - 1
                approach.lengthEighths = 1
                approach.restAfterEighths = 0
                approach.alteration = -1
                approach.velocity = max(40, note.velocity - 14)
                result.append(approach)
            }
            result.append(note)
        }

        var mutated = pattern
        mutated.notes = result
        mutated.name = pattern.name + " ornamented"
        return tidy(mutated)
    }

    /// Moves a stretch of the line into another octave.
    static func displaceRegister(_ pattern: MelodyPattern,
                                 octaves: Int,
                                 fromEighth: Int = 0) -> MelodyPattern {
        var mutated = pattern
        mutated.notes = pattern.notes.map { note in
            var copy = note
            if note.startEighth >= fromEighth { copy.octave += octaves }
            return copy
        }
        mutated.name = pattern.name + (octaves > 0 ? " up an octave" : " down an octave")
        return mutated
    }

    /// Performs a line's pitch material on a different onset grid.
    ///
    /// Ported from `@enkerli/accompaniment`'s rhythm.ts, and the most complete
    /// separation of the two axes available: contour and harmonic function ride
    /// along, rhythm is replaced wholesale. The pattern spans the phrase, so
    /// E(3,8) over a 4/4 bar lands on the half-beat grid and a 9-step figure
    /// lands as a 9-grid over the same bar.
    ///
    /// - Parameter overBars: how many bars the rhythm spans before it repeats.
    ///   The suite's version stretches a pattern across the whole phrase, which
    ///   is right when a phrase is a bar; over a four-bar line it turns E(3,8)
    ///   into three notes in four bars, which is not what anyone means by
    ///   "play it on a tresillo". One bar by default, so the cell tiles.
    static func applyRhythm(_ pattern: MelodyPattern,
                            _ rhythm: RhythmSpec,
                            overBars: Int = 1) -> MelodyPattern {
        let onsetsPerCycle = rhythm.onsetIndices
        guard !onsetsPerCycle.isEmpty else { return pattern }
        let material = pattern.notes.sorted { $0.startEighth < $1.startEighth }
        guard !material.isEmpty else { return pattern }

        let spanEighths = max(1, pattern.bars * 8)
        let cycleEighths = max(1, min(spanEighths, overBars * 8))
        let eighthsPerStep = Double(cycleEighths) / Double(max(1, rhythm.steps.count))
        let cycles = max(1, Int(ceil(Double(spanEighths) / Double(cycleEighths))))

        var onsets: [(step: Int, eighth: Int)] = []
        for cycle in 0..<cycles {
            for step in onsetsPerCycle {
                let eighth = cycle * cycleEighths + Int((Double(step) * eighthsPerStep).rounded())
                if eighth < spanEighths { onsets.append((step, eighth)) }
            }
        }
        guard !onsets.isEmpty else { return pattern }

        var notes: [PatternNote] = []
        for (index, onset) in onsets.enumerated() {
            let source = material[index % material.count]
            let step = onset.step
            let start = onset.eighth
            let nextStart = index + 1 < onsets.count ? onsets[index + 1].eighth : spanEighths

            var note = source
            note.startEighth = start
            // Legato to the next onset, which is the tied feel the suite's
            // version produces; gate length shortens it again at render time.
            note.lengthEighths = max(1, nextStart - start)
            note.restAfterEighths = 0
            if rhythm.accents.indices.contains(step), rhythm.accents[step] {
                note.velocity = min(120, note.velocity + 18)
            }
            notes.append(note)
        }

        var mutated = pattern
        mutated.notes = notes
        mutated.name = "\(pattern.name) on \(rhythm.label)"
        mutated.summary = "\(pattern.summary), performed on \(rhythm.label)"
        return tidy(mutated)
    }

    // MARK: - Helpers

    /// Downbeats outrank beats, beats outrank offbeats. The ranking every part of
    /// the plug-in uses when it has to decide which note matters least.
    static func metricWeight(_ eighth: Int) -> Int {
        if eighth % 8 == 0 { return 3 }
        if eighth % 4 == 0 { return 2 }
        if eighth % 2 == 0 { return 1 }
        return 0
    }

    /// Sorts, de-collides and clips lengths. Every transform runs through it,
    /// because a transform that leaves two notes on one eighth has produced
    /// something the rest of the plug-in can't play.
    static func tidy(_ pattern: MelodyPattern) -> MelodyPattern {
        var result = pattern
        let span = max(1, pattern.bars * 8)
        let ordered = pattern.notes
            .filter { $0.startEighth >= 0 && $0.startEighth < span }
            .sorted { ($0.startEighth, $0.degree) < ($1.startEighth, $1.degree) }

        var deduplicated: [PatternNote] = []
        for note in ordered where deduplicated.last?.startEighth != note.startEighth {
            deduplicated.append(note)
        }
        for index in deduplicated.indices.dropLast() {
            let slot = deduplicated[index + 1].startEighth - deduplicated[index].startEighth
            var length = min(deduplicated[index].lengthEighths, slot)
            let requested = deduplicated[index].restAfterEighths
            if requested > 0 {
                length = min(length, max(slot - requested, (slot + 1) / 2))
            }
            deduplicated[index].lengthEighths = max(1, length)
        }
        if var last = deduplicated.last {
            last.lengthEighths = max(1, min(last.lengthEighths, span - last.startEighth))
            deduplicated[deduplicated.count - 1] = last
        }
        result.notes = deduplicated
        return result
    }
}

// MARK: - Morphing

enum MelodyMorph {

    /// Dials between two lines.
    ///
    /// Notes are aligned proportionally rather than by onset, because two lines
    /// worth morphing between rarely have their notes in the same places — and an
    /// alignment that only matches exact coincidences produces a crossfade rather
    /// than a morph. The output has a note count between the two, and each of its
    /// notes is a blend of the corresponding note in each parent.
    ///
    /// - Parameter mix: 0 is entirely `from`, 1 is entirely `to`.
    static func between(_ from: MelodyPattern,
                        _ to: MelodyPattern,
                        mix: Double,
                        name: String? = nil) -> MelodyPattern {
        let mix = max(0, min(1, mix))
        let left = from.notes.sorted { $0.startEighth < $1.startEighth }
        let right = to.notes.sorted { $0.startEighth < $1.startEighth }
        guard !left.isEmpty else { return to }
        guard !right.isEmpty else { return from }

        let bars = Int((Double(from.bars) * (1 - mix) + Double(to.bars) * mix).rounded())
        let span = max(1, bars * 8)
        let count = max(1, Int((Double(left.count) * (1 - mix) + Double(right.count) * mix).rounded()))

        var notes: [PatternNote] = []
        for index in 0..<count {
            let position = count > 1 ? Double(index) / Double(count - 1) : 0
            let a = left[min(left.count - 1, Int((position * Double(left.count - 1)).rounded()))]
            let b = right[min(right.count - 1, Int((position * Double(right.count - 1)).rounded()))]

            // Onsets scale into the blended span before they're blended, or a
            // four-bar line morphing into an eight-bar one bunches up at the top.
            let aStart = Double(a.startEighth) / Double(max(1, from.bars * 8)) * Double(span)
            let bStart = Double(b.startEighth) / Double(max(1, to.bars * 8)) * Double(span)

            notes.append(PatternNote(
                startEighth: Int((aStart * (1 - mix) + bStart * mix).rounded()),
                lengthEighths: max(1, Int((Double(a.lengthEighths) * (1 - mix)
                                           + Double(b.lengthEighths) * mix).rounded())),
                degree: Int((Double(a.degree) * (1 - mix) + Double(b.degree) * mix).rounded()),
                octave: Int((Double(a.octave) * (1 - mix) + Double(b.octave) * mix).rounded()),
                // Alteration doesn't interpolate — half a semitone isn't a note.
                // It follows whichever parent the mix is nearer.
                alteration: mix < 0.5 ? a.alteration : b.alteration,
                velocity: Int((Double(a.velocity) * (1 - mix) + Double(b.velocity) * mix).rounded()),
                restAfterEighths: Int((Double(a.restAfterEighths) * (1 - mix)
                                       + Double(b.restAfterEighths) * mix).rounded()),
                role: mix < 0.5 ? a.role : b.role
            ))
        }

        var morphed = MelodyPattern(
            name: name ?? "\(from.name) → \(to.name) @\(Int(mix * 100))%",
            bars: max(1, bars),
            summary: "\(Int((1 - mix) * 100))% \(from.name), \(Int(mix * 100))% \(to.name)",
            notes: notes,
            origin: from.origin
        )
        morphed = MelodyTransforms.tidy(morphed)
        return morphed
    }
}
