//
//  MelodyVariants.swift
//  MelGenExtension
//
//  Scoring the mutations, so a dozen of them is a shortlist rather than a pile.
//
//  Producing variants is easy; the hard part is that twelve of them is more than
//  anyone will audition, and picking which to offer is a judgement the machine
//  has to make before the human makes theirs. Three numbers, deliberately kept
//  separate rather than added into one:
//
//    · **novelty** — how far this is from the line it came from. A variant that
//      changed nothing is not a variant.
//    · **style distance** — how far its habits are from the material that's been
//      kept. Near is not automatically better: sometimes the point of a variant
//      is that it doesn't sound like everything else.
//    · **variety** — how much is going on inside it, measured the way takes are
//      already measured, so a variant and a take can be compared.
//
//  They're reported separately because collapsing them into one number decides in
//  advance what "good" means, and that decision belongs to whoever is listening.
//  The ordering offered is a default, not a verdict — the same stance the
//  curation model takes about everything else.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

/// The comparable measurements of a line, in degree space.
///
/// Computable from a pattern *and* from a `LearnedStyle`, which is what makes a
/// distance between the two meaningful: the same axes, measured the same way.
struct PatternProfile: Hashable, Sendable {
    var notesPerBar: Double = 0
    var offbeatShare: Double = 0
    var restShare: Double = 0
    var stepShare: Double = 0
    var skipShare: Double = 0
    var leapShare: Double = 0
    var meanLength: Double = 2

    static func of(_ pattern: MelodyPattern) -> PatternProfile {
        var profile = PatternProfile()
        let notes = pattern.notes.sorted { $0.startEighth < $1.startEighth }
        guard !notes.isEmpty else { return profile }

        let spanEighths = Double(max(1, pattern.bars * 8))
        profile.notesPerBar = Double(notes.count) / Double(max(1, pattern.bars))
        profile.offbeatShare = Double(notes.filter { !$0.startEighth.isMultiple(of: 2) }.count)
            / Double(notes.count)
        profile.meanLength = Double(notes.reduce(0) { $0 + $1.lengthEighths }) / Double(notes.count)

        let sounding = Double(notes.reduce(0) { $0 + $1.lengthEighths })
        profile.restShare = max(0, min(1, 1 - sounding / spanEighths))

        // Degrees, not semitones: one degree is a step, two is a skip, more is a
        // leap. Close enough to the semitone bands the style uses that the two
        // are comparable, and it doesn't need a chord to compute.
        let moves = zip(notes, notes.dropFirst()).map { abs($1.degree - $0.degree) }
        if !moves.isEmpty {
            profile.stepShare = Double(moves.filter { $0 <= 1 }.count) / Double(moves.count)
            profile.skipShare = Double(moves.filter { $0 == 2 }.count) / Double(moves.count)
            profile.leapShare = Double(moves.filter { $0 >= 3 }.count) / Double(moves.count)
        }
        return profile
    }

    static func of(_ style: LearnedStyle) -> PatternProfile {
        var profile = PatternProfile()
        profile.notesPerBar = style.notesPerBar
        profile.offbeatShare = style.offbeatShare
        profile.restShare = style.restShare
        profile.stepShare = style.stepShare
        profile.skipShare = style.skipShare
        profile.leapShare = style.leapShare
        profile.meanLength = style.commonDurations.isEmpty
            ? 2
            : Double(style.commonDurations.reduce(0, +)) / Double(style.commonDurations.count)
        return profile
    }

    /// Weighted L1, normalized to roughly 0...1. Rhythm counts double, because
    /// rhythm is what the ear identifies a line by.
    func distance(to other: PatternProfile) -> Double {
        let terms: [(Double, Double)] = [
            (abs(notesPerBar - other.notesPerBar) / 8, 1),
            (abs(offbeatShare - other.offbeatShare), 2),
            (abs(restShare - other.restShare), 1),
            (abs(stepShare - other.stepShare), 1),
            (abs(skipShare - other.skipShare), 0.5),
            (abs(leapShare - other.leapShare), 1),
            (abs(meanLength - other.meanLength) / 6, 2)
        ]
        let weight = terms.reduce(0) { $0 + $1.1 }
        let total = terms.reduce(0) { $0 + min(1, $1.0) * $1.1 }
        return weight > 0 ? total / weight : 0
    }
}

/// What a variant is made of.
///
/// Two cases, because a take is one of two things and pretending otherwise cost
/// a real bug: variants of a comping take were being read back through
/// `MelodyPatterns.extract`, which is monophonic by construction — one note per
/// onset — so every chord came out as a single note and the whole point of the
/// comp was gone before the first transform ran.
///
/// A monophonic take varies in degree space, where the transforms live. A
/// polyphonic one varies as *already-realized notes*, because its content is
/// voicings and a voicing has no degree-relative representation in this format.
/// The two need different transforms, and saying so in the type is what stops
/// the wrong ones being applied.
enum VariantMaterial: Hashable, Sendable {
    case line(MelodyPattern)
    case voiced(notes: [SequencedNote], summary: String)

    var patternIfLine: MelodyPattern? {
        if case .line(let pattern) = self { return pattern }
        return nil
    }

    var summary: String {
        switch self {
        case .line(let pattern): return pattern.summary
        case .voiced(_, let summary): return summary
        }
    }
}

/// One mutation, with the three numbers that decide whether it's worth hearing.
struct MelodyVariant: Hashable, Sendable, Identifiable {
    var id: String { "\(transform)·\(name)" }
    var name: String
    var material: VariantMaterial
    /// The monophonic pattern, when there is one. Nil for a comping variant.
    var pattern: MelodyPattern {
        material.patternIfLine
            ?? MelodyPattern(name: name, bars: 1, summary: material.summary, notes: [])
    }
    /// What was done to get here.
    var transform: String
    /// 0 identical to the parent, 1 nothing in common.
    var novelty: Double
    /// 0 exactly the kept material's habits, 1 nothing like them.
    var styleDistance: Double
    /// How much is going on inside it, on the same scale takes are scored on.
    var variety: Double

    var summary: String {
        "\(transform) · \(Int(novelty * 100))% new · \(Int(variety * 100))% varied"
            + (styleDistance > 0 ? " · \(Int(styleDistance * 100))% from your style" : "")
    }

    init(pattern: MelodyPattern, transform: String,
         novelty: Double, styleDistance: Double, variety: Double) {
        self.name = pattern.name
        self.material = .line(pattern)
        self.transform = transform
        self.novelty = novelty
        self.styleDistance = styleDistance
        self.variety = variety
    }

    init(voiced notes: [SequencedNote], name: String, summary: String, transform: String,
         novelty: Double, variety: Double) {
        self.name = name
        self.material = .voiced(notes: notes, summary: summary)
        self.transform = transform
        self.novelty = novelty
        self.styleDistance = 0
        self.variety = variety
    }
}

enum MelodyVariants {

    /// Produces and scores a spread of mutations.
    ///
    /// The transform list is fixed and covers the axes independently — one moves
    /// rhythm only, one moves pitch only, one moves density only — so a variant
    /// that works can be traced to the thing that made it work. Random
    /// combinations would sometimes sound better and would teach nothing.
    static func explore(_ pattern: MelodyPattern,
                        seed: UInt64,
                        style: LearnedStyle? = nil,
                        limit: Int = 12) -> [MelodyVariant] {
        var rng = SplitMix64(seed: seed)
        let target = style.map(PatternProfile.of)

        var candidates: [(String, MelodyPattern)] = [
            ("displaced", MelodyTransforms.displace(pattern, byEighths: 1)),
            ("displaced back", MelodyTransforms.displace(pattern, byEighths: -2)),
            ("inverted", MelodyTransforms.invert(pattern)),
            ("retrograde", MelodyTransforms.retrograde(pattern)),
            ("thinner", MelodyTransforms.adjustDensity(pattern, to: 0.6, seed: rng.next())),
            ("denser", MelodyTransforms.adjustDensity(pattern, to: 1.5, seed: rng.next())),
            ("ornamented", MelodyTransforms.ornament(pattern, amount: 0.5, seed: rng.next())),
            ("degrees nudged", MelodyTransforms.substituteDegrees(pattern, amount: 0.35, seed: rng.next())),
            ("durations redrawn", MelodyTransforms.substituteDurations(pattern, amount: 0.4, seed: rng.next())),
            ("up an octave", MelodyTransforms.displaceRegister(pattern, octaves: 1, fromEighth: 8))
        ]

        // Rhythm replacement gets several entries because it's the transform that
        // moves the axis the material is shortest on.
        for spec in RhythmSpec.vocabulary.prefix(4) {
            candidates.append(("on \(spec.label)", MelodyTransforms.applyRhythm(pattern, spec)))
        }

        let parentKeys = Set(pattern.notes.map { "\($0.startEighth):\($0.degree):\($0.alteration):\($0.lengthEighths)" })

        return candidates
            .filter { !$0.1.notes.isEmpty }
            .map { transform, candidate in
                let keys = Set(candidate.notes.map {
                    "\($0.startEighth):\($0.degree):\($0.alteration):\($0.lengthEighths)"
                })
                let shared = parentKeys.intersection(keys).count
                let union = parentKeys.union(keys).count
                let novelty = union > 0 ? 1 - Double(shared) / Double(union) : 0

                let profile = PatternProfile.of(candidate)
                return MelodyVariant(
                    pattern: candidate,
                    transform: transform,
                    novelty: novelty,
                    styleDistance: target.map { profile.distance(to: $0) } ?? 0,
                    variety: variety(of: candidate)
                )
            }
            // A variant that changed nothing isn't one. Everything else is
            // offered, ordered by how much it moved — not by how "good" it is,
            // which isn't a judgement this can make.
            .filter { $0.novelty > 0.05 }
            .sorted { left, right in
                if abs(left.novelty - right.novelty) > 0.02 { return left.novelty > right.novelty }
                if abs(left.variety - right.variety) > 0.001 { return left.variety > right.variety }
                // A total order, or the list a person is choosing from can come
                // back in a different sequence each time they look at it. Swift's
                // sort isn't stable, so ties have to be broken explicitly rather
                // than left to whatever the algorithm does.
                return left.transform < right.transform
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Variety in degree space, on the same 0...1 scale takes are scored on.
    ///
    /// A local version rather than `MelodyAnalyser`'s, because that one needs a
    /// progression and a variant hasn't met one yet.
    static func variety(of pattern: MelodyPattern) -> Double {
        let notes = pattern.notes.sorted { $0.startEighth < $1.startEighth }
        guard notes.count > 2 else { return 0 }

        let intervals = zip(notes, notes.dropFirst()).map { $1.degree - $0.degree }
        let lengths = notes.map(\.lengthEighths)
        let onsets = notes.map { $0.startEighth % 8 }

        let spread = (entropy(intervals) + entropy(lengths) + entropy(onsets)) / 3

        // Penalise a line that repeats itself bar for bar, the way take scoring
        // does — an ostinato reads as varied on the marginals and isn't.
        var fingerprints: [Set<String>] = []
        for bar in 0..<max(1, pattern.bars) {
            let start = bar * 8
            fingerprints.append(Set(notes
                .filter { $0.startEighth >= start && $0.startEighth < start + 8 }
                .map { "\($0.startEighth - start):\($0.degree)" }))
        }
        var similarity = 0.0
        var comparisons = 0
        for index in 1..<max(1, fingerprints.count) {
            let previous = fingerprints[index - 1], current = fingerprints[index]
            let union = previous.union(current).count
            guard union > 0 else { continue }
            similarity += Double(previous.intersection(current).count) / Double(union)
            comparisons += 1
        }
        let selfSimilarity = comparisons > 0 ? similarity / Double(comparisons) : 0
        return max(0, min(1, spread * (1 - selfSimilarity * 0.7)))
    }

    private static func entropy<Value: Hashable>(_ values: [Value]) -> Double {
        guard values.count > 1 else { return 0 }
        var counts: [Value: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        guard counts.count > 1 else { return 0 }
        let total = Double(values.count)
        // Summed in a fixed order. Reducing over a dictionary's values sums in
        // whatever order that dictionary iterates, which Swift does not promise
        // is the same twice — and floating-point addition is not associative, so
        // the same counts produced answers differing in the last bits. Harmless
        // in a displayed percentage; not harmless in a list that is sorted by it
        // and expected to come back the same, which is how this was found.
        let measured = counts.values.sorted().reduce(0.0) { partial, count in
            let probability = Double(count) / total
            return partial - probability * log2(probability)
        }
        let ceiling = log2(min(total, Double(counts.count) * 2))
        return ceiling > 0 ? max(0, min(1, measured / ceiling)) : 0
    }
}
