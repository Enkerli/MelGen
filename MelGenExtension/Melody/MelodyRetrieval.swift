//
//  MelodyRetrieval.swift
//  MelGenExtension
//
//  Finding the thing you already have.
//
//  Once a library outgrows what anyone can remember, the question stops being
//  "generate something" and becomes "which of the things I already have fits
//  *this*". That's a different problem and it wants different machinery:
//  similarity over the measurements, a fit check against the harmony in front of
//  you, and — separately — a way of being surprised on purpose.
//
//  The two modes are kept apart deliberately, because they answer to different
//  needs and blending them serves neither. **Direct retrieval** is for when you
//  know what you want: nearest by profile, filtered by fit, ordered by distance,
//  no randomness anywhere. **Serendipity** is for when you don't: weighted away
//  from what you've heard lately and toward the corners of the library you've
//  been ignoring, using the one signal a curation model has that a rating
//  doesn't — that a take marked "skip" on one pass and "keep" on another is
//  material whose value depends on context, which makes it exactly the thing
//  worth putting in front of someone again.
//
//  Recombination splices at bar lines only. A splice mid-figure produces
//  something that sounds like an edit, and the whole point of keeping provenance
//  is that you can hear where a line came from.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation
import Carrier
import Core
import Theory

/// A coarse bucket for a line, used to notice which corners of the library are
/// under-explored. Three axes at three or four levels each is small enough that
/// a personal library actually populates it.
struct RetrievalBucket: Hashable, Sendable {
    enum Density: String, Sendable { case sparse, medium, busy }
    enum Placement: String, Sendable { case onBeat, mixed, offBeat }
    enum Length: String, Sendable { case short, medium, long }

    var density: Density
    var placement: Placement
    var length: Length

    var label: String { "\(density.rawValue)/\(placement.rawValue)/\(length.rawValue)" }

    static func of(_ profile: PatternProfile) -> RetrievalBucket {
        let density: Density = profile.notesPerBar < 3 ? .sparse
                             : (profile.notesPerBar < 6 ? .medium : .busy)
        let placement: Placement = profile.offbeatShare < 0.15 ? .onBeat
                                 : (profile.offbeatShare < 0.45 ? .mixed : .offBeat)
        let length: Length = profile.meanLength < 1.75 ? .short
                           : (profile.meanLength < 3.5 ? .medium : .long)
        return RetrievalBucket(density: density, placement: placement, length: length)
    }

    static func of(_ pattern: MelodyPattern) -> RetrievalBucket {
        of(PatternProfile.of(pattern))
    }
}

/// One result, with the reason it's here.
struct RetrievalResult: Sendable, Identifiable {
    var id: String { pattern.name }
    var pattern: MelodyPattern
    /// 0 is an exact match for what was asked for.
    var distance: Double
    /// How it survives the harmony in front of you, when there is one.
    var fit: PatternFitReport?
    /// Why this one came back, in words.
    var reason: String
}

enum MelodyRetrieval {

    // MARK: - Direct

    /// Nearest by profile. No randomness: asked the same question twice, this
    /// gives the same answer, which is the whole point of the direct mode.
    static func nearest(_ candidates: [MelodyPattern],
                        to profile: PatternProfile,
                        over progression: ChordProgression? = nil,
                        limit: Int = 8) -> [RetrievalResult] {
        candidates
            .filter { !$0.notes.isEmpty }
            .map { pattern in
                let distance = PatternProfile.of(pattern).distance(to: profile)
                return RetrievalResult(
                    pattern: pattern,
                    distance: distance,
                    fit: progression.map { MelodyPatterns.fitReport(for: pattern, over: $0) },
                    reason: distance < 0.15 ? "very like it" : (distance < 0.35 ? "like it" : "loosely like it")
                )
            }
            // Stable order: distance, then name, so equal distances don't shuffle
            // between calls.
            .sorted { ($0.distance, $0.pattern.name) < ($1.distance, $1.pattern.name) }
            .prefix(limit)
            .map { $0 }
    }

    /// The lines that survive this progression cleanly, best first.
    ///
    /// "Clean" is the fit report's own judgement — everything lands in the
    /// scale, nothing falls outside the form, and the line tiles evenly.
    static func fitting(_ candidates: [MelodyPattern],
                        _ progression: ChordProgression,
                        limit: Int = 8) -> [RetrievalResult] {
        candidates
            .filter { !$0.notes.isEmpty }
            .map { pattern in
                let report = MelodyPatterns.fitReport(for: pattern, over: progression)
                // Cost, not a score: notes lost, notes outside the scale, notes
                // on avoid tones, and a penalty for not tiling.
                let lost = Double(max(0, report.requested - report.placed)) / Double(max(1, report.requested))
                let wrong = Double(report.offScale + report.onAvoidNotes) / Double(max(1, report.placed))
                let cost = lost + wrong + (report.tilesEvenly ? 0 : 0.15)
                return RetrievalResult(pattern: pattern,
                                       distance: cost,
                                       fit: report,
                                       reason: report.isClean ? "fits cleanly" : report.summary)
            }
            .sorted { ($0.distance, $0.pattern.name) < ($1.distance, $1.pattern.name) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Serendipity

    /// A deliberate surprise.
    ///
    /// Weighted three ways, and none of them is "at random": away from what's
    /// been heard lately, toward buckets the kept material under-represents, and
    /// toward lines whose curation history *disagrees with itself*. That last
    /// one is the signal a disposition model has and a rating doesn't — a line
    /// skipped on one pass and kept on another is material whose worth depends
    /// on context, which makes it the best possible candidate for "try this now,
    /// it's a different day".
    static func surprise(_ candidates: [MelodyPattern],
                         heardRecently recent: [String],
                         keptBuckets: [RetrievalBucket: Int] = [:],
                         contested: Set<String> = [],
                         seed: UInt64,
                         over progression: ChordProgression? = nil) -> RetrievalResult? {
        let pool = candidates.filter { !$0.notes.isEmpty }
        guard !pool.isEmpty else { return nil }
        let recentSet = Set(recent)
        let keptTotal = max(1, keptBuckets.values.reduce(0, +))

        var rng = SplitMix64(seed: seed)
        var weights: [Double] = []
        var reasons: [String] = []

        for pattern in pool {
            var weight = 1.0
            var reason = "worth another listen"

            if recentSet.contains(pattern.name) {
                weight *= 0.15
            }

            // Under-represented corners get more weight, so the library's edges
            // get heard rather than only its centre of mass.
            let bucket = RetrievalBucket.of(pattern)
            let share = Double(keptBuckets[bucket] ?? 0) / Double(keptTotal)
            if share < 0.1 {
                weight *= 2.2
                reason = "a corner of the library you've been ignoring — \(bucket.label)"
            }

            if contested.contains(pattern.name) {
                weight *= 2.8
                reason = "you've disagreed with yourself about this one"
            }

            weights.append(weight)
            reasons.append(reason)
        }

        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }
        var draw = rng.nextUnit() * total
        var index = weights.count - 1
        for (candidate, weight) in weights.enumerated() {
            draw -= weight
            if draw <= 0 { index = candidate; break }
        }

        let pattern = pool[index]
        return RetrievalResult(
            pattern: pattern,
            distance: 0,
            fit: progression.map { MelodyPatterns.fitReport(for: pattern, over: $0) },
            reason: reasons[index]
        )
    }

    /// Which buckets the kept material covers, for the weighting above.
    static func buckets(of patterns: [MelodyPattern]) -> [RetrievalBucket: Int] {
        var counts: [RetrievalBucket: Int] = [:]
        for pattern in patterns { counts[RetrievalBucket.of(pattern), default: 0] += 1 }
        return counts
    }

    // MARK: - Recombination

    /// Joins the opening of one line to the continuation of another.
    ///
    /// At a bar line only. A splice mid-figure sounds like an edit, and the
    /// point of keeping provenance is being able to hear where a line came from
    /// rather than being unable to tell.
    static func splice(_ opening: MelodyPattern,
                       _ continuation: MelodyPattern,
                       atBar bar: Int) -> MelodyPattern {
        let bar = max(1, bar)
        let cut = bar * 8
        let bars = max(bar + 1, max(opening.bars, continuation.bars))
        let span = bars * 8

        var notes = opening.notes.filter { $0.startEighth < cut }
        // Don't let the last note of the opening run through the join.
        if let last = notes.indices.max() {
            notes[last].lengthEighths = max(1, min(notes[last].lengthEighths, cut - notes[last].startEighth))
        }

        // The continuation is taken from the same position in its own form, so a
        // second phrase stays a second phrase rather than becoming a first one.
        for note in continuation.notes where note.startEighth >= cut && note.startEighth < span {
            notes.append(note)
        }
        // Nothing to take from there: wrap the continuation round instead of
        // leaving silence.
        if !notes.contains(where: { $0.startEighth >= cut }) {
            let continuationSpan = max(1, continuation.bars * 8)
            for note in continuation.notes {
                var shifted = note
                shifted.startEighth = cut + (note.startEighth % continuationSpan)
                if shifted.startEighth < span { notes.append(shifted) }
            }
        }

        var spliced = MelodyPattern(
            name: "\(opening.name) ▸ \(continuation.name)",
            bars: bars,
            summary: "\(bar) bar\(bar == 1 ? "" : "s") of \(opening.name), then \(continuation.name)",
            notes: notes,
            origin: opening.origin
        )
        spliced = MelodyTransforms.tidy(spliced)
        return spliced
    }
}

// MARK: - What the session knows

extension MelGenState {

    /// Lines whose curation history disagrees with itself — kept on one pass and
    /// set aside on another. The most interesting rows in the library, and the
    /// ones serendipity should reach for first.
    var contestedTakes: [GenerationRecord] {
        history.filter { take in
            let dispositions = Set(take.marks.map(\.disposition))
            guard dispositions.count > 1 else { return false }
            let positive: Set<TakeDisposition> = [.keep, .tweak, .partial]
            let negative: Set<TakeDisposition> = [.skip, .later, .again]
            return !dispositions.isDisjoint(with: positive) && !dispositions.isDisjoint(with: negative)
        }
    }

    /// The takes most recently loaded, newest first — what "heard lately" means.
    func recentlyHeard(limit: Int = 6) -> [GenerationRecord] {
        Array(history.prefix(limit))
    }
}
