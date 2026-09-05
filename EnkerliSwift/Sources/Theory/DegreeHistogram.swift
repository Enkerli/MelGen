//
//  DegreeHistogram.swift
//  MelGenExtension
//
//  Which note, as a distribution rather than as a rule.
//
//  Every generator in this codebase already answers "which note" somehow — the
//  seeds hard-code degrees, the phrase grammar picks contours, the slot model
//  reads a vocabulary off what was kept. What none of them had is a *shape you
//  can dial*: a set of weights over the twelve semitones above the sounding
//  chord's root, which any of them can draw from and all of them can be
//  described by.
//
//  Twelve chromatic buckets rather than seven scale degrees, and that choice is
//  the whole design. Scale degrees can't say "a semitone above the third", so a
//  histogram in degree space can only ever describe notes that belong — which
//  rules out exactly the material this was built for. In semitone space the
//  outside notes are ordinary entries with small weights, a pentatonic
//  transposed up a semitone is the same object shifted by one index, and
//  blending two ways of playing is vector arithmetic. `DegreePlacement` converts
//  a drawn semitone back into the `(degree, alteration, role)` the pattern
//  format speaks, so nothing downstream has to know this file exists.
//
//  ## The stack
//
//  The default shape isn't invented. It's a way of building a line that most
//  improvisers arrive at independently: start on the root, add the fifth, then
//  the third, then the seventh, then the eleventh, the ninth, and last the
//  thirteenth. Played slowly it's an exercise; played fast it's how a solo warms
//  up. What matters here is that the *order of arrival is itself a histogram* —
//  the notes you reach for first are the ones you play most — so a single
//  `reach` control walks that sequence and produces a distribution at every
//  point along it, rather than switching between seven presets.
//
//  ## Outside
//
//  `outside` puts a small, even weight on the five semitones the scale doesn't
//  contain. Small on purpose: an outside note at 30% is a wrong note, and at 3%
//  it's a colour. The transition weights in `TransitionHistogram` are what turn
//  a scattering of those into a chromatic run, because a run is a fact about
//  what follows what and not about what's likely on its own.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

/// The harmony a histogram is read against.
///
/// A `ChordSymbol` converts into one of these, and so does a bare key — which is
/// what lets the diatonic path use every generator here without inventing a
/// chord it doesn't have. Everything is stored as semitones above the root, so a
/// histogram built over one chord means the same thing over another.
public struct DegreeContext: Hashable, Sendable {
    public var rootPitchClass: Int
    /// Semitones above the root, sorted and unique. Seven for a mode, six for
    /// whole tone, eight for a diminished scale.
    public var scaleIntervals: [Int]
    /// Which of those are tones of the chord itself.
    public var chordIntervals: [Int]
    /// Scale tones a semitone above a chord tone — unstable as landing notes.
    public var avoidIntervals: [Int]

    public init(rootPitchClass: Int,
         scaleIntervals: [Int],
         chordIntervals: [Int],
         avoidIntervals: [Int] = []) {
        self.rootPitchClass = ChordScales.pitchClass(rootPitchClass)
        self.scaleIntervals = DegreeContext.normalize(scaleIntervals)
        self.chordIntervals = DegreeContext.normalize(chordIntervals)
        self.avoidIntervals = DegreeContext.normalize(avoidIntervals)
    }

    public init(chord: ChordSymbol) {
        let root = chord.rootPitchClass
        func relative(_ pitchClasses: [Int]) -> [Int] {
            pitchClasses.map { ChordScales.pitchClass($0 - root) }
        }
        self.init(rootPitchClass: root,
                  scaleIntervals: relative(chord.scalePitchClasses),
                  chordIntervals: relative(chord.tonePitchClasses),
                  avoidIntervals: relative(chord.avoidPitchClasses))
    }

    /// What a semitone above the root is, harmonically.
    public func role(ofSemitone semitone: Int) -> HarmonicRole {
        let interval = ChordScales.pitchClass(semitone)
        if chordIntervals.contains(interval) { return .chordTone }
        if avoidIntervals.contains(interval) { return .avoid }
        if scaleIntervals.contains(interval) { return .colour }
        return .offScale
    }

    private static func normalize(_ intervals: [Int]) -> [Int] {
        Array(Set(intervals.map(ChordScales.pitchClass))).sorted()
    }
}

/// Weights over the twelve semitones above a chord's root.
public struct DegreeHistogram: Codable, Hashable, Sendable {

    /// Twelve, always. A histogram of any other length is a different idea.
    public static let size = 12

    /// Index is semitones above the root. Never negative; not required to sum
    /// to anything, because normalizing on write means every blend has to
    /// renormalize and the arithmetic stops being associative.
    public var weights: [Double]

    public init(weights: [Double] = Array(repeating: 0, count: DegreeHistogram.size)) {
        var padded = weights.map { max(0, $0) }
        if padded.count < Self.size {
            padded += Array(repeating: 0, count: Self.size - padded.count)
        }
        self.weights = Array(padded.prefix(Self.size))
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(weights: try container.decodeIfPresent([Double].self, forKey: .weights) ?? [])
    }

    public var total: Double { weights.reduce(0, +) }
    public var isEmpty: Bool { total <= 0 }

    public subscript(semitone: Int) -> Double {
        get { weights[ChordScales.pitchClass(semitone)] }
        set { weights[ChordScales.pitchClass(semitone)] = max(0, newValue) }
    }
}

// MARK: - Building one

extension DegreeHistogram {

    /// The order an improviser reaches for the notes in, as scale-degree indices.
    ///
    /// Root, fifth, third, seventh, eleventh, ninth, thirteenth — degrees 0, 4,
    /// 2, 6, 3, 1, 5 of a seven-note scale. Indices rather than intervals, so
    /// the same order means the right thing over a minor chord, an altered
    /// dominant, or anything else whose scale has seven notes in it. Scales that
    /// don't (whole tone has six, diminished has eight) wrap, which is the only
    /// answer available and is a good one: the fifth of a whole-tone scale is
    /// still the note four steps up.
    public static let arrivalOrder = [0, 4, 2, 6, 3, 1, 5]

    /// How much less each successive arrival is worth. 0.72 puts the thirteenth
    /// at about a seventh of the root, which is roughly the ratio a transcribed
    /// solo shows and is far enough down that the colour notes stay colour.
    public static let arrivalDecay = 0.72

    /// The stack, as a distribution.
    ///
    /// - Parameters:
    ///   - reach: how far up the stack this line has got. 0 is the root alone; 1
    ///     is everything through the thirteenth. Fractional values are the point
    ///     — each arrival ramps in over its own unit of the dial, so the shape
    ///     changes continuously rather than in seven jumps.
    ///   - outside: weight given to the semitones the scale doesn't contain,
    ///     as a fraction of the mean scale weight. Small numbers only.
    ///   - avoidDamping: what fraction of its weight an avoid note keeps.
    public static func stack(over context: DegreeContext,
                      reach: Double = 0.55,
                      outside: Double = 0,
                      avoidDamping: Double = 0.45,
                      decay: Double = arrivalDecay) -> DegreeHistogram {
        let scale = context.scaleIntervals
        guard !scale.isEmpty else { return DegreeHistogram() }

        let reach = max(0, min(1, reach))
        // Position 1 at reach 0 so the root is always present: a histogram that
        // is entirely zero isn't the bottom of the dial, it's a broken generator.
        let position = reach * Double(arrivalOrder.count - 1) + 1

        var histogram = DegreeHistogram()
        for (rank, degreeIndex) in arrivalOrder.enumerated() {
            let gate = max(0, min(1, position - Double(rank)))
            guard gate > 0 else { continue }
            let interval = scale[((degreeIndex % scale.count) + scale.count) % scale.count]
            histogram[interval] += gate * pow(decay, Double(rank))
        }

        if avoidDamping < 1 {
            histogram = histogram.damping(context.avoidIntervals, to: avoidDamping)
        }
        if outside > 0 {
            histogram = histogram.opening(to: context, by: outside)
        }
        return histogram
    }

    /// Even weight on a set of semitones above the root.
    public static func at(_ semitones: [Int], weight: Double = 1) -> DegreeHistogram {
        var histogram = DegreeHistogram()
        for semitone in semitones { histogram[semitone] += weight }
        return histogram
    }

    /// Even weight on every scale tone — the plainest thing there is, and the
    /// right floor to blend a shaped histogram against when it gets too narrow.
    public static func scaleTones(of context: DegreeContext, weight: Double = 1) -> DegreeHistogram {
        at(context.scaleIntervals, weight: weight)
    }

    /// The major pentatonic rooted `semitone` above the chord root.
    ///
    /// Two of these do most of the work of playing out. On a minor seventh
    /// chord, the pentatonic on the third is entirely inside the harmony — over
    /// Cm7 it is E♭ F G B♭ C, which is five of the seven notes anyone would have
    /// played anyway. The one a semitone above it shares *nothing* with the
    /// chord's scale, and still lands, which is the observation `sideSlip` is
    /// built on.
    public static func majorPentatonic(on semitone: Int, weight: Double = 1) -> DegreeHistogram {
        at([0, 2, 4, 7, 9].map { semitone + $0 }, weight: weight)
    }

    /// Inside, then a semitone up: the side-slip.
    ///
    /// - Parameter slip: how much of the weight goes to the outside pentatonic.
    ///   0 is the inside one alone. Half is where it stops sounding like a
    ///   wrong turn and starts sounding like a decision.
    public static func sideSlip(over context: DegreeContext,
                         slip: Double = 0.35) -> DegreeHistogram {
        // From the third of the chord, which is what makes the inside
        // pentatonic land on the chord's own colour rather than on its root.
        let scale = context.scaleIntervals
        let third = scale.isEmpty ? 3 : scale[min(2, scale.count - 1)]
        let slip = max(0, min(1, slip))
        return mix([(majorPentatonic(on: third), 1 - slip),
                    (majorPentatonic(on: third + 1), slip)])
    }

    /// All twelve, evenly. On its own this is noise; multiplied by a transition
    /// histogram that likes semitones, it's a chromatic run.
    public static func chromatic(weight: Double = 1) -> DegreeHistogram {
        DegreeHistogram(weights: Array(repeating: weight, count: size))
    }
}

// MARK: - Arithmetic

extension DegreeHistogram {

    /// Sums to one, or comes back empty. The only place division happens.
    public var normalized: DegreeHistogram {
        let total = self.total
        guard total > 0 else { return self }
        return DegreeHistogram(weights: weights.map { $0 / total })
    }

    public func scaled(by factor: Double) -> DegreeHistogram {
        DegreeHistogram(weights: weights.map { $0 * factor })
    }

    /// A weighted sum, each part normalized first.
    ///
    /// Normalizing the parts is what makes the mix mean what it says: two
    /// histograms with wildly different totals blended 50/50 would otherwise be
    /// whichever one happened to be written with bigger numbers.
    public static func mix(_ parts: [(DegreeHistogram, Double)]) -> DegreeHistogram {
        var result = DegreeHistogram()
        for (histogram, weight) in parts where weight > 0 {
            let normalized = histogram.normalized
            for index in 0..<size { result.weights[index] += normalized.weights[index] * weight }
        }
        return result
    }

    /// `t` of 0 is all self, 1 is all other.
    public func blended(with other: DegreeHistogram, _ t: Double) -> DegreeHistogram {
        let t = max(0, min(1, t))
        return DegreeHistogram.mix([(self, 1 - t), (other, t)])
    }

    /// Multiplies the named semitones by a factor. Under 1 damps, over 1 boosts.
    public func damping(_ semitones: [Int], to factor: Double) -> DegreeHistogram {
        var copy = self
        for semitone in semitones { copy[semitone] = copy[semitone] * max(0, factor) }
        return copy
    }

    public func boosting(_ semitones: [Int], by factor: Double) -> DegreeHistogram {
        damping(semitones, to: factor)
    }

    /// Lets the outside notes in, at a fraction of what's already there.
    ///
    /// Relative to the mean rather than to a constant, so it means the same
    /// thing whatever scale the histogram was built over and whether it has been
    /// normalized yet.
    public func opening(to context: DegreeContext, by amount: Double) -> DegreeHistogram {
        guard amount > 0 else { return self }
        let inside = context.scaleIntervals
        let insideWeight = inside.map { self[$0] }.reduce(0, +)
        guard insideWeight > 0, inside.count < Self.size else { return self }
        let mean = insideWeight / Double(inside.count)
        var copy = self
        for semitone in 0..<Self.size where !inside.contains(semitone) {
            copy[semitone] += mean * amount
        }
        return copy
    }

    /// Leans on the chord tones, or away from them.
    ///
    /// What a strong beat wants. A line that lands on the third on beat one and
    /// wanders in between is the same histogram twice with this applied
    /// differently, which is cheaper and more musical than keeping two.
    public func emphasising(chordTonesOf context: DegreeContext, by factor: Double) -> DegreeHistogram {
        boosting(context.chordIntervals, by: factor)
    }
}

// MARK: - Drawing from one

extension DegreeHistogram {

    /// The semitone a draw in 0..<1 lands on, or nil if there is no weight.
    ///
    /// Deterministic given the draw, and iterated in index order, so two
    /// histograms sampled at one seed are comparable — the aligned-streams
    /// discipline the rest of the codebase keeps.
    public func pick(draw: Double) -> Int? {
        let total = self.total
        guard total > 0 else { return nil }
        var remaining = max(0, min(1, draw)) * total
        for index in 0..<Self.size {
            remaining -= weights[index]
            if remaining <= 0 { return index }
        }
        return weights.lastIndex { $0 > 0 }
    }

    /// The most likely note, for when something has to be certain — a fallback
    /// after a draw that found nothing, or the first note of a line.
    public var mostLikely: Int? {
        guard total > 0 else { return nil }
        return (0..<Self.size).max { weights[$0] < weights[$1] }
    }

    /// The chance of drawing a given semitone.
    public func probability(of semitone: Int) -> Double {
        let total = self.total
        guard total > 0 else { return 0 }
        return self[semitone] / total
    }
}

// MARK: - Reading one

extension DegreeHistogram {

    /// One row per semitone, named against a chord and drawn as a bar.
    ///
    /// The stated reason this project keeps statistics rather than training
    /// anything is that you can look at them. A histogram nobody can read is a
    /// weight vector with better manners, so this is part of the type rather
    /// than a debugging convenience.
    public func profile(over context: DegreeContext, width: Int = 24) -> [String] {
        let peak = weights.max() ?? 0
        guard peak > 0 else { return ["empty"] }
        return (0..<Self.size).map { semitone in
            let share = weights[semitone] / peak
            let filled = Int((share * Double(width)).rounded())
            let name = IntervalNames.all[semitone].padding(toLength: 4, withPad: " ", startingAt: 0)
            let bar = String(repeating: "█", count: filled)
                    + String(repeating: "·", count: max(0, width - filled))
            let percent = String(format: "%5.1f%%", probability(of: semitone) * 100)
            return "\(name) \(bar) \(percent)  \(context.role(ofSemitone: semitone).shortLabel)"
        }
    }

    public var summary: String {
        guard !isEmpty else { return "no weight anywhere" }
        let ranked = (0..<Self.size)
            .sorted { weights[$0] > weights[$1] }
            .prefix(4)
            .filter { weights[$0] > 0 }
            .map { "\(IntervalNames.all[$0]) \(Int((probability(of: $0) * 100).rounded()))%" }
        return ranked.joined(separator: " · ")
    }
}

extension HarmonicRole {
    /// A word narrow enough to sit in a column.
    public var shortLabel: String {
        switch self {
        case .chordTone: return "chord"
        case .colour: return "colour"
        case .avoid: return "avoid"
        case .offScale: return "outside"
        }
    }
}

/// Interval names, so a histogram can be read rather than decoded.
///
/// One spelling per semitone, chosen for the position it usually occupies in a
/// chord rather than for correctness in every key — a histogram is read to see
/// where the weight is, and "♯11" says that faster than "♭5" does.
public enum IntervalNames {
    public static let all = ["1", "♭9", "9", "♭3", "3", "11", "♯11", "5", "♭13", "13", "♭7", "7"]

    public static func name(of semitone: Int) -> String { all[ChordScales.pitchClass(semitone)] }
}

// MARK: - A key, as a histogram

extension DiatonicHarmony {

    /// The harmonic context for a key, as the histograms read it.
    ///
    /// Here rather than in DiatonicHarmony.swift so that file stays free of
    /// everything below the theory layer — `ChordParser` calls into it to read a
    /// modal token, and a parser that transitively needed the pattern format
    /// would be a parser the theory suites couldn't compile on their own.
    public static func context(key: Int, minorness: Double) -> DegreeContext {
        DegreeContext(chord: symbol(root: key, scale: mode(forMinorness: minorness)))
    }

    /// The degree histogram for a fractional minorness.
    ///
    /// Both neighbouring modes' stacks, blended: between two rungs the flattened
    /// degree and the natural one both carry weight, in proportion, and the line
    /// audibly sits between the two modes rather than in one of them.
    ///
    /// **Nothing calls this today**, and that is a decision rather than an
    /// oversight. The mode a key is in is now written into the progression as
    /// `C(dorian)`, and text can only name one mode — so the dial that used to
    /// be continuous rounds to a rung. What is lost is the in-between, and it is
    /// worth having back as a *darkness* control that leans the histogram over
    /// any progression rather than only over a modal one: see ROADMAP H13. Kept
    /// and tested meanwhile, because deleting it would mean deriving the ladder
    /// blend a second time when that lands.
    public static func degrees(key: Int,
                        minorness: Double,
                        reach: Double,
                        outside: Double = 0) -> DegreeHistogram {
        let (brighter, darker, t) = neighbours(forMinorness: minorness)
        func stack(_ scale: Scale) -> DegreeHistogram {
            DegreeHistogram.stack(over: DegreeContext(chord: symbol(root: key, scale: scale)),
                                  reach: reach)
        }
        let blended = brighter == darker
            ? stack(brighter)
            : DegreeHistogram.mix([(stack(brighter), 1 - t), (stack(darker), t)])

        guard outside > 0 else { return blended }
        return blended.opening(to: context(key: key, minorness: minorness), by: outside)
    }
}
