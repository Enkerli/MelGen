//
//  MelodyTopics.swift
//  MelGenExtension
//
//  Grouping the library, so the vocabulary can come from the material.
//
//  This is the stage where topic modelling belongs, and what it's for here is
//  *not* generation. It's naming. The curation model has two vocabularies —
//  derived facets and typed tags — and an explicit ratchet between them: a tag
//  you keep reaching for is a facet waiting to be named. What's been missing is
//  the other direction, where the material itself proposes a grouping nobody had
//  thought to name.
//
//  On method, this deliberately starts at the bottom of the ladder TRAINING.md
//  §5 lays out. Topic modelling wants a term–document matrix; the documents are
//  patterns and the terms have to be something a line has many of, with a heavy
//  tail — **degree bigrams**, **rhythm cells**, **onset masks**. Those are real
//  vocabularies with real Zipfian distributions. But LDA over a few dozen
//  documents produces confident nonsense, and a personal library is a few dozen
//  documents for a long time. So: TF-IDF over those terms, cosine similarity,
//  and k-means with deterministic seeding — the most defensible thing at this
//  corpus size, and the thing whose failure mode is "the groups are arbitrary"
//  rather than "the groups look meaningful and aren't".
//
//  Every grouping is reported with a confidence derived from how much material
//  is behind it and how cohesive the groups actually are, because a topic model
//  over thirty lines that doesn't say how little it knows is worse than no topic
//  model at all.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation
import Carrier
import Core

/// A group the material fell into, with the evidence for it.
struct MelodyTopic: Sendable, Identifiable {
    var id: Int
    /// Names of the patterns in this group.
    var members: [String]
    /// The terms that distinguish this group from the rest, most telling first.
    var distinctiveTerms: [String]
    /// A name proposed from those terms. A suggestion for a human to accept,
    /// reject or rename — never applied on its own.
    var suggestedName: String
    /// How tightly the group holds together, 0...1.
    var cohesion: Double

    var summary: String {
        "\(members.count) line\(members.count == 1 ? "" : "s") · \(Int(cohesion * 100))% cohesive"
    }
}

/// What a grouping is worth, given how much went into it.
struct TopicConfidence: Sendable {
    var documents: Int
    var terms: Int
    var groups: Int
    var meanCohesion: Double

    /// Honest, and deliberately harsh below about forty documents.
    ///
    /// The failure this guards against is a grouping that looks meaningful over
    /// thirty lines and isn't. Saying "provisional" is cheap; discovering three
    /// months later that a facet was named after noise is not.
    var verdict: String {
        if documents < 12 { return "Far too little material — this is noise with labels on it." }
        if documents < 40 { return "Provisional. Enough to look at, not enough to name anything after." }
        if meanCohesion < 0.25 { return "The groups aren't holding together; the library may not divide this way." }
        if documents < 120 { return "Worth reading. Treat a name as a hypothesis." }
        return "Solid enough to name something after."
    }

    var isWorthShowing: Bool { documents >= 12 }
}

enum MelodyTopics {

    // MARK: - Terms

    /// The vocabulary a line is described in.
    ///
    /// Three kinds, because a line is at least three things at once and a
    /// grouping over any one of them alone misses what the others say:
    ///
    ///   · `d:a>b` — a degree bigram, which carries contour;
    ///   · `r:2-1-3` — a bar's sequence of note lengths, which carries rhythm;
    ///   · `o:x..x..x.` — a bar's onset mask, which carries placement.
    static func terms(of pattern: MelodyPattern) -> [String: Int] {
        var counts: [String: Int] = [:]
        let notes = pattern.notes.sorted { $0.startEighth < $1.startEighth }
        guard !notes.isEmpty else { return counts }

        for (previous, next) in zip(notes, notes.dropFirst()) {
            let step = next.degree - previous.degree
            counts["d:\(clamp(step))", default: 0] += 1
        }

        for bar in 0..<max(1, pattern.bars) {
            let start = bar * 8
            let inBar = notes.filter { $0.startEighth >= start && $0.startEighth < start + 8 }
            guard !inBar.isEmpty else { continue }

            let cell = inBar.map { String($0.lengthEighths) }.joined(separator: "-")
            counts["r:\(cell)", default: 0] += 1

            var mask = Array(repeating: ".", count: 8)
            for note in inBar { mask[note.startEighth - start] = "x" }
            counts["o:\(mask.joined())", default: 0] += 1
        }
        return counts
    }

    private static func clamp(_ step: Int) -> String {
        if step == 0 { return "same" }
        let capped = max(-4, min(4, step))
        return capped > 0 ? "+\(capped)" : "\(capped)"
    }

    // MARK: - Grouping

    /// Groups the library by what its lines are made of.
    ///
    /// - Parameter groups: how many to look for. Kept small on purpose — asking a
    ///   thirty-line library for eight topics is asking it to invent seven.
    static func group(_ patterns: [MelodyPattern],
                      into groups: Int = 3,
                      seed: UInt64 = 0x5EED)
        -> (topics: [MelodyTopic], confidence: TopicConfidence) {

        let documents = patterns.filter { !$0.notes.isEmpty }
        let groups = max(2, min(groups, max(2, documents.count / 4)))
        guard documents.count >= 4 else {
            return ([], TopicConfidence(documents: documents.count, terms: 0,
                                        groups: 0, meanCohesion: 0))
        }

        // TF-IDF, so a term every line has says nothing and a term a few lines
        // share says a lot — which is the whole basis of the grouping.
        let bags = documents.map(terms(of:))
        var documentFrequency: [String: Int] = [:]
        for bag in bags {
            for term in bag.keys { documentFrequency[term, default: 0] += 1 }
        }
        let vocabulary = documentFrequency.keys.sorted()
        let total = Double(documents.count)

        let vectors: [[Double]] = bags.map { bag in
            let length = Double(bag.values.reduce(0, +))
            let raw = vocabulary.map { term -> Double in
                guard let count = bag[term], length > 0 else { return 0 }
                let frequency = Double(count) / length
                let inverse = log(total / Double(max(1, documentFrequency[term] ?? 1)))
                return frequency * inverse
            }
            let norm = raw.reduce(0) { $0 + $1 * $1 }.squareRoot()
            return norm > 0 ? raw.map { $0 / norm } : raw
        }

        let assignment = kMeans(vectors, groups: groups, seed: seed)

        var topics: [MelodyTopic] = []
        var cohesions: [Double] = []
        for group in 0..<groups {
            let indices = assignment.enumerated().compactMap { $1 == group ? $0 : nil }
            guard !indices.isEmpty else { continue }

            // Distinctive means "more common here than everywhere", not "common
            // here" — otherwise every group is described by the same terms.
            var inside: [String: Double] = [:]
            for index in indices {
                let bag = bags[index]
                let length = Double(max(1, bag.values.reduce(0, +)))
                for (term, count) in bag { inside[term, default: 0] += Double(count) / length }
            }
            let distinctive = inside
                .map { term, weight -> (String, Double) in
                    let global = Double(documentFrequency[term] ?? 1) / total
                    return (term, weight / Double(indices.count) / max(0.05, global))
                }
                .sorted { ($0.1, $1.0) > ($1.1, $0.0) }
                .prefix(5)
                .map(\.0)

            let cohesion = meanSimilarity(indices.map { vectors[$0] })
            cohesions.append(cohesion)

            topics.append(MelodyTopic(
                id: group,
                members: indices.map { documents[$0].name },
                distinctiveTerms: distinctive,
                suggestedName: name(from: distinctive),
                cohesion: cohesion
            ))
        }

        topics.sort { $0.members.count > $1.members.count }
        let confidence = TopicConfidence(
            documents: documents.count,
            terms: vocabulary.count,
            groups: topics.count,
            meanCohesion: cohesions.isEmpty ? 0 : cohesions.reduce(0, +) / Double(cohesions.count)
        )
        return (topics, confidence)
    }

    /// k-means over cosine distance, seeded deterministically.
    ///
    /// k-means++ seeding from a fixed stream rather than random restarts: the
    /// same library must give the same grouping, or nobody can act on it.
    private static func kMeans(_ vectors: [[Double]], groups: Int, seed: UInt64) -> [Int] {
        guard !vectors.isEmpty, let width = vectors.first?.count, width > 0 else {
            return Array(repeating: 0, count: vectors.count)
        }
        var rng = SplitMix64(seed: seed)

        var centres: [[Double]] = [vectors[Int(rng.next() % UInt64(vectors.count))]]
        while centres.count < groups {
            let distances = vectors.map { vector in
                centres.map { 1 - dot(vector, $0) }.min() ?? 0
            }
            let total = distances.reduce(0, +)
            guard total > 0 else { break }
            var draw = rng.nextUnit() * total
            var chosen = vectors.count - 1
            for (index, distance) in distances.enumerated() {
                draw -= distance
                if draw <= 0 { chosen = index; break }
            }
            centres.append(vectors[chosen])
        }
        while centres.count < groups { centres.append(vectors[centres.count % vectors.count]) }

        var assignment = Array(repeating: 0, count: vectors.count)
        for _ in 0..<24 {
            var changed = false
            for (index, vector) in vectors.enumerated() {
                var best = 0
                var bestScore = -Double.infinity
                for (group, centre) in centres.enumerated() {
                    let score = dot(vector, centre)
                    if score > bestScore { bestScore = score; best = group }
                }
                if assignment[index] != best { assignment[index] = best; changed = true }
            }

            for group in centres.indices {
                let members = assignment.enumerated().compactMap { $1 == group ? vectors[$0] : nil }
                guard !members.isEmpty else { continue }
                var centre = Array(repeating: 0.0, count: width)
                for member in members {
                    for index in 0..<width { centre[index] += member[index] }
                }
                let norm = centre.reduce(0) { $0 + $1 * $1 }.squareRoot()
                centres[group] = norm > 0 ? centre.map { $0 / norm } : centre
            }
            if !changed { break }
        }
        return assignment
    }

    private static func dot(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private static func meanSimilarity(_ vectors: [[Double]]) -> Double {
        guard vectors.count > 1 else { return 1 }
        var total = 0.0
        var pairs = 0
        for i in 0..<vectors.count {
            for j in (i + 1)..<vectors.count {
                total += dot(vectors[i], vectors[j])
                pairs += 1
            }
        }
        return pairs > 0 ? max(0, min(1, total / Double(pairs))) : 0
    }

    // MARK: - Naming

    /// Proposes a name from the terms that distinguish a group.
    ///
    /// A suggestion, never an assertion: the whole design of the two-vocabulary
    /// model is that the human names things and the machine notices patterns.
    /// This is the noticing, phrased so a person can say yes or no to it.
    static func name(from terms: [String]) -> String {
        var words: [String] = []

        let onsets = terms.filter { $0.hasPrefix("o:") }.map { String($0.dropFirst(2)) }
        if let mask = onsets.first {
            let positions = mask.enumerated().compactMap { $1 == "x" ? $0 : nil }
            let offbeat = positions.filter { !$0.isMultiple(of: 2) }.count
            if positions.count <= 2 { words.append("sparse") }
            else if positions.count >= 6 { words.append("busy") }
            if offbeat * 2 >= positions.count, !positions.isEmpty { words.append("offbeat") }
            else if offbeat == 0, !positions.isEmpty { words.append("on-beat") }
        }

        let cells = terms.filter { $0.hasPrefix("r:") }.map { String($0.dropFirst(2)) }
        if let cell = cells.first {
            let lengths = cell.split(separator: "-").compactMap { Int($0) }
            if lengths.allSatisfy({ $0 == lengths.first }) , lengths.count > 1 { words.append("even") }
            else if lengths.contains(where: { $0 >= 4 }) { words.append("long-held") }
            else if lengths == [3, 3, 2] || lengths == [3, 2] { words.append("loping") }
        }

        let steps = terms.filter { $0.hasPrefix("d:") }.map { String($0.dropFirst(2)) }
        if steps.contains("same") { words.append("repeating") }
        if steps.contains(where: { ["+3", "+4", "-3", "-4"].contains($0) }) { words.append("leaping") }
        else if steps.contains(where: { ["+1", "-1"].contains($0) }) { words.append("stepwise") }

        guard !words.isEmpty else { return "unnamed group" }
        return Array(Set(words)).sorted().joined(separator: ", ")
    }
}
