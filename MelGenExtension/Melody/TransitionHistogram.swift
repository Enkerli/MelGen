//
//  TransitionHistogram.swift
//  MelGenExtension
//
//  How far the next note is, as a distribution.
//
//  `DegreeHistogram` answers "which note" and has no idea what came before it.
//  That is a marginal, and a line drawn from a marginal alone wanders: every
//  note is individually plausible and no two of them are related. This is the
//  other half of the pair — weights over the *interval* to the next note, from a
//  twelfth down to a twelfth up.
//
//  The two are multiplied rather than chosen between, and that is the whole
//  mechanism. For each candidate pitch within reach, the transition weight says
//  how likely a move of that size is and the degree weight says how likely that
//  landing note is over the chord now sounding; the product is sampled. So a
//  line steps mostly by step *and* mostly onto chord tones, without either
//  constraint being a rule that overrides the other, and the same code produces
//  a walking bass, an arpeggiated figure and a chromatic run depending only on
//  which two histograms went in.
//
//  ## Why not the chain
//
//  `MelodyChain` already models what follows what, and it is the better model
//  where it applies: it learns real order from real material, with rhythm in the
//  token. It has one requirement this doesn't — material. A chain over three
//  takes can only quote them, which is the reason its trust threshold exists.
//  This is the prior that works at zero takes: shaped by hand, dialled rather
//  than trained, and able to be *informed* by observation as observation arrives.
//  They meet in the middle rather than competing.
//
//  ## Runs
//
//  A chromatic run is not a sequence of individually unlikely notes. It is one
//  decision to move by semitone and then several decisions to keep doing what
//  was just done, which is why `momentum` is a parameter of the walk rather than
//  a shape in the histogram. Repeating the previous interval exactly is boosted
//  hardest, then any move in the same direction — the same reason a run of
//  descending semitones lands and a scattering of them doesn't.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation
import Carrier
import Theory

/// Weights over the interval to the next note, in semitones.
struct TransitionHistogram: Codable, Hashable, Sendable {

    /// How far either way the histogram reaches. An octave, because a move
    /// wider than that in a single step is a register change rather than a
    /// melodic interval, and the walk handles those by folding into range.
    static let span = 12
    static let size = span * 2 + 1

    /// Index `interval + span`, so index 12 is staying put.
    var weights: [Double]

    init(weights: [Double] = Array(repeating: 0, count: TransitionHistogram.size)) {
        var padded = weights.map { max(0, $0) }
        if padded.count < Self.size {
            padded += Array(repeating: 0, count: Self.size - padded.count)
        }
        self.weights = Array(padded.prefix(Self.size))
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(weights: try container.decodeIfPresent([Double].self, forKey: .weights) ?? [])
    }

    var total: Double { weights.reduce(0, +) }
    var isEmpty: Bool { total <= 0 }

    /// Out-of-reach intervals read as zero rather than trapping, because the
    /// walk offers candidates and asks about all of them.
    subscript(interval: Int) -> Double {
        get {
            let index = interval + Self.span
            return weights.indices.contains(index) ? weights[index] : 0
        }
        set {
            let index = interval + Self.span
            guard weights.indices.contains(index) else { return }
            weights[index] = max(0, newValue)
        }
    }

    /// Every interval the histogram can describe, in order.
    static var intervals: [Int] { Array(-span...span) }
}

// MARK: - Building one

extension TransitionHistogram {

    /// Steps, with a tail.
    ///
    /// An exponential falloff in interval size: the commonest shape in
    /// transcribed melody and the one that makes a line singable. `leapiness`
    /// stretches the falloff — 0 is almost entirely semitones and tones, 1 puts
    /// real weight on sixths and sevenths.
    ///
    /// - Parameter repeats: how much weight staying on the same note gets.
    ///   Separately controlled because zero is a legitimate setting (a bass line
    ///   that repeats a note is pumping, not walking) and an exponential would
    ///   otherwise make it the single most likely move by a wide margin.
    static func stepwise(leapiness: Double = 0.35, repeats: Double = 0.1) -> TransitionHistogram {
        let scale = 1.1 + max(0, min(1, leapiness)) * 3.6
        var histogram = TransitionHistogram()
        for interval in intervals {
            histogram[interval] = interval == 0
                ? max(0, repeats)
                : exp(-Double(abs(interval)) / scale)
        }
        return histogram
    }

    /// The moves inside a chord: thirds, fourths, fifths, sixths and the octave.
    ///
    /// What a bass line does when it isn't walking, and what an arpeggiated
    /// figure is made of. Sizes rather than degrees, because the degree
    /// histogram decides what the landing note has to be and this only has an
    /// opinion about how far away it is.
    static func arpeggiating(reach: Double = 0.5) -> TransitionHistogram {
        var histogram = TransitionHistogram()
        for interval in intervals {
            let size = abs(interval)
            switch size {
            case 3, 4: histogram[interval] = 1
            case 5, 7: histogram[interval] = 0.85
            case 8, 9: histogram[interval] = 0.4 + reach * 0.5
            case 12: histogram[interval] = 0.25 + reach * 0.6
            case 1, 2: histogram[interval] = 0.2
            default: histogram[interval] = 0
            }
        }
        return histogram
    }

    /// Semitones, and almost nothing else.
    static func chromatic(strictness: Double = 0.8) -> TransitionHistogram {
        let strictness = max(0, min(1, strictness))
        var histogram = TransitionHistogram()
        for interval in intervals {
            switch abs(interval) {
            case 1: histogram[interval] = 1
            case 2: histogram[interval] = 1 - strictness * 0.7
            case 0: histogram[interval] = 0
            default: histogram[interval] = (1 - strictness) * 0.15
            }
        }
        return histogram
    }

    /// Even weight on every move, staying put included. The floor to blend
    /// against when a shaped histogram has painted itself into a corner.
    static func flat(includingRepeats: Bool = false) -> TransitionHistogram {
        var histogram = TransitionHistogram()
        for interval in intervals {
            histogram[interval] = (interval == 0 && !includingRepeats) ? 0 : 1
        }
        return histogram
    }

    /// Leans the whole histogram one way.
    ///
    /// - Parameter rise: 1 only ever goes up, −1 only ever down, 0 is even. A
    ///   line that leans has direction without having a contour written into it,
    ///   which is what lets a bass figure descend across a chorus while every
    ///   individual move is still drawn rather than scripted.
    func leaning(_ rise: Double) -> TransitionHistogram {
        let rise = max(-1, min(1, rise))
        var copy = self
        for interval in Self.intervals where interval != 0 {
            copy[interval] = self[interval] * (interval > 0 ? 1 + rise : 1 - rise)
        }
        return copy
    }
}

// MARK: - Arithmetic

extension TransitionHistogram {

    var normalized: TransitionHistogram {
        let total = self.total
        guard total > 0 else { return self }
        return TransitionHistogram(weights: weights.map { $0 / total })
    }

    /// A weighted sum, each part normalized first — the same contract as
    /// `DegreeHistogram.mix`, and for the same reason.
    static func mix(_ parts: [(TransitionHistogram, Double)]) -> TransitionHistogram {
        var result = TransitionHistogram()
        for (histogram, weight) in parts where weight > 0 {
            let normalized = histogram.normalized
            for index in 0..<size { result.weights[index] += normalized.weights[index] * weight }
        }
        return result
    }

    func blended(with other: TransitionHistogram, _ t: Double) -> TransitionHistogram {
        let t = max(0, min(1, t))
        return TransitionHistogram.mix([(self, 1 - t), (other, t)])
    }

    func probability(of interval: Int) -> Double {
        let total = self.total
        guard total > 0 else { return 0 }
        return self[interval] / total
    }
}

// MARK: - Learning one

extension TransitionHistogram {

    /// Counts the moves a line actually made.
    ///
    /// No harmony needed, which is the one respect in which this is easier to
    /// learn than a degree histogram: an interval is a fact about two notes and
    /// nothing else. Moves wider than the span are dropped rather than clamped —
    /// a fourteenth is a register change and counting it as an octave would put
    /// weight where none belongs.
    static func observed(in notes: [SequencedNote]) -> TransitionHistogram {
        let ordered = notes.sorted { $0.startBeat < $1.startBeat }
        var histogram = TransitionHistogram()
        for (previous, next) in zip(ordered, ordered.dropFirst()) {
            let interval = Int(next.note) - Int(previous.note)
            guard abs(interval) <= span else { continue }
            histogram[interval] += 1
        }
        return histogram
    }

    static func observed(in takes: [GenerationRecord]) -> TransitionHistogram {
        var histogram = TransitionHistogram()
        for take in takes {
            let counted = observed(in: take.notes)
            for index in 0..<size { histogram.weights[index] += counted.weights[index] }
        }
        return histogram
    }

    /// The prior, moved toward what was measured, with the same floor under a
    /// thin corpus as `DegreeHistogram.informed(by:observations:)`.
    func informed(by observed: TransitionHistogram,
                  observations: Int,
                  confidentAt: Int = 60,
                  ceiling: Double = 0.75) -> TransitionHistogram {
        guard !observed.isEmpty, observations > 0 else { return self }
        let trust = min(ceiling, Double(observations) / Double(max(1, confidentAt)) * ceiling)
        return blended(with: observed, trust)
    }
}

// MARK: - Reading one

extension TransitionHistogram {

    /// One row per interval, drawn as a bar either side of centre.
    func profile(width: Int = 20) -> [String] {
        let peak = weights.max() ?? 0
        guard peak > 0 else { return ["empty"] }
        return Self.intervals.compactMap { interval in
            let share = self[interval] / peak
            guard share > 0 else { return nil }
            let filled = max(1, Int((share * Double(width)).rounded()))
            let label = interval == 0 ? "  0" : String(format: "%+3d", interval)
            let percent = String(format: "%5.1f%%", probability(of: interval) * 100)
            return "\(label) \(String(repeating: "█", count: filled)) \(percent)"
        }
    }

    var summary: String {
        guard !isEmpty else { return "no weight anywhere" }
        let steps = Self.intervals.filter { (1...2).contains(abs($0)) }
            .map { probability(of: $0) }.reduce(0, +)
        let leaps = Self.intervals.filter { abs($0) >= 5 }
            .map { probability(of: $0) }.reduce(0, +)
        let up = Self.intervals.filter { $0 > 0 }.map { probability(of: $0) }.reduce(0, +)
        return "\(Int((steps * 100).rounded()))% by step · "
             + "\(Int((leaps * 100).rounded()))% leaps · "
             + "\(Int((up * 100).rounded()))% upward"
    }

    /// How well a set of voice movements matches this histogram, as a mean
    /// probability. Higher is more like the material.
    ///
    /// Comping's own leading is settled — taxicab, held to the suite's shared
    /// vectors, and not something to make probabilistic. But *choosing between*
    /// voicings that all lead well is an open question, and "which of these
    /// moves the way my material moves" is an answer this can give. Exposed and
    /// deliberately not wired in: the voicing layer picks by policy today, and
    /// replacing a settled rule with a distribution is a decision to make on
    /// purpose rather than as a side effect of this file existing.
    func agreement(with movements: [Int]) -> Double {
        guard !movements.isEmpty, !isEmpty else { return 0 }
        return movements.map { probability(of: $0) }.reduce(0, +) / Double(movements.count)
    }
}

// MARK: - The walk

/// Drawing a line from the two histograms at once.
///
/// The only place either histogram turns into pitches, and the reason both of
/// them are worth having: neither is a generator on its own.
enum MelodicWalk {

    /// The next pitch, or nil if nothing in range has any weight.
    ///
    /// - Parameters:
    ///   - pitch: where the line is now, as a MIDI note.
    ///   - previousInterval: the move that got here, for momentum. Nil at the
    ///     start of a line and after a rest long enough to break the thread.
    ///   - degrees: which notes, relative to `context`'s root.
    ///   - context: the harmony sounding at the moment being drawn.
    ///   - transitions: how far.
    ///   - momentum: how much a move that continues what just happened is
    ///     favoured. 0 draws every move independently; at 1 a run, once started,
    ///     is hard to stop. Half is where a chromatic approach reliably becomes
    ///     two or three notes rather than one.
    ///   - range: the register the line is kept in.
    ///   - draw: one value in 0..<1. One draw per note, so the stream stays
    ///     aligned whatever the histograms contain.
    static func next(from pitch: Int,
                     previousInterval: Int?,
                     degrees: DegreeHistogram,
                     context: DegreeContext,
                     transitions: TransitionHistogram,
                     momentum: Double = 0.5,
                     range: ClosedRange<Int>,
                     draw: Double) -> Int? {
        let momentum = max(0, min(1, momentum))
        var candidates: [(pitch: Int, weight: Double)] = []
        var total = 0.0

        for interval in TransitionHistogram.intervals {
            let candidate = pitch + interval
            guard range.contains(candidate) else { continue }
            let move = transitions[interval]
            guard move > 0 else { continue }

            let semitone = ChordScales.pitchClass(candidate - context.rootPitchClass)
            let landing = degrees[semitone]
            guard landing > 0 else { continue }

            // Momentum: the same interval again hardest, then anything the same
            // way. Multiplicative so it shapes what's already possible rather
            // than resurrecting a move both histograms said no to.
            var weight = move * landing
            if let previousInterval, previousInterval != 0, interval != 0 {
                if interval == previousInterval {
                    weight *= 1 + momentum * 3
                } else if (interval > 0) == (previousInterval > 0) {
                    weight *= 1 + momentum
                }
            }

            candidates.append((candidate, weight))
            total += weight
        }

        guard total > 0 else { return nil }
        var remaining = max(0, min(1, draw)) * total
        for candidate in candidates {
            remaining -= candidate.weight
            if remaining <= 0 { return candidate.pitch }
        }
        return candidates.last?.pitch
    }

    /// Where to start, when there is no previous note.
    ///
    /// Drawn from the degree histogram alone — there is no interval yet — and
    /// placed in the octave of `range` nearest `near`, so a bass line starts low
    /// and a melody starts where the last phrase left off rather than wherever
    /// the arithmetic happened to land.
    static func start(degrees: DegreeHistogram,
                      context: DegreeContext,
                      range: ClosedRange<Int>,
                      near: Int,
                      draw: Double) -> Int? {
        guard let semitone = degrees.pick(draw: draw) ?? degrees.mostLikely else { return nil }
        let target = ChordScales.pitchClass(context.rootPitchClass + semitone)

        let candidates = stride(from: range.lowerBound, through: range.upperBound, by: 1)
            .filter { ChordScales.pitchClass($0) == target }
        guard !candidates.isEmpty else { return nil }
        return candidates.min { abs($0 - near) < abs($1 - near) }
    }

    /// Folds a pitch into a range by octaves, keeping its pitch class.
    ///
    /// The one correction that never changes what note is being played — which
    /// is why every register control in this codebase is an octave shift and
    /// none of them is a clamp.
    static func fold(_ pitch: Int, into range: ClosedRange<Int>) -> Int {
        guard range.upperBound - range.lowerBound >= 11 else {
            return min(max(pitch, range.lowerBound), range.upperBound)
        }
        var folded = pitch
        while folded > range.upperBound { folded -= 12 }
        while folded < range.lowerBound { folded += 12 }
        return folded
    }
}
