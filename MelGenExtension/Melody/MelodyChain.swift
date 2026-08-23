//
//  MelodyChain.swift
//  MelGenExtension
//
//  A variable-order model over what follows what.
//
//  The slot model in MelodyStyleModel.swift learns *where* this material puts
//  notes and knows nothing about order — each slot fires independently, so what
//  comes out has the corpus's groove and none of its phrases. That's the ceiling
//  of a marginal distribution, and no amount of more material raises it.
//
//  This is the other half: what tends to follow what. The state is deliberately
//  richer than "the last note", because pitch alone produces wandering:
//
//    · the last one or two events, each carrying **degree, alteration, length
//      and the rest after it** — so the model learns rhythm and pitch together,
//      which is the only way a phrase comes out with both;
//    · **where in the bar** we are, because bar-line behaviour and mid-bar
//      behaviour are different grammars and a model that conflates them writes
//      neither;
//    · **where in the phrase** we are, because phrases end, and "ends" was the
//      one thing prompting the language model never reliably produced.
//
//  With a personal corpus, backoff isn't an optimisation — it's the only reason
//  anything is produced at all. A few hundred transitions means most order-2
//  contexts are seen exactly once, and a context seen once has nothing to say
//  except "do what happened that time", which is quotation rather than
//  generation. So each level of the ladder has to have been observed more than
//  once before it's trusted; otherwise the model drops to a shorter context. That
//  single rule is what separates a model that composes from a model that replays
//  its corpus, and it's what the tests here check hardest.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

/// One event, as the chain sees it: what was played and how long it lasted,
/// with the silence after it. Pitch and rhythm in one token on purpose — a chain
/// over pitch alone learns melody without rhythm and has to have rhythm bolted
/// back on, which is how generated lines end up scanning like a list.
struct ChainToken: Hashable, Sendable {
    var degree: Int
    var alteration: Int
    var lengthEighths: Int
    var restAfterEighths: Int

    var key: String { "\(degree):\(alteration):\(lengthEighths):\(restAfterEighths)" }

    /// Total footprint on the grid — the note and its silence.
    var spanEighths: Int { max(1, lengthEighths) + max(0, restAfterEighths) }

    init(degree: Int, alteration: Int, lengthEighths: Int, restAfterEighths: Int) {
        self.degree = degree
        self.alteration = alteration
        self.lengthEighths = max(1, lengthEighths)
        self.restAfterEighths = max(0, min(8, restAfterEighths))
    }

    init?(key: String) {
        let parts = key.split(separator: ":")
        guard parts.count == 4,
              let degree = Int(parts[0]), let alteration = Int(parts[1]),
              let length = Int(parts[2]), let rest = Int(parts[3]) else { return nil }
        self.init(degree: degree, alteration: alteration, lengthEighths: length, restAfterEighths: rest)
    }

    init(_ note: PatternNote) {
        self.init(degree: note.degree,
                  alteration: note.alteration,
                  lengthEighths: note.lengthEighths,
                  restAfterEighths: note.restAfterEighths)
    }
}

/// Where in a phrase an event sits. Three positions, because that's what a
/// phrase has: it opens, it goes on, and it lands.
enum PhrasePosition: String, Codable, Hashable, Sendable, CaseIterable {
    case opening, middle, cadence

    static func at(eighth: Int, ofBars bars: Int) -> PhrasePosition {
        let total = max(1, bars * 8)
        let position = Double(eighth % max(1, min(total, 16))) / Double(max(1, min(total, 16)))
        switch position {
        case ..<0.25: return .opening
        case ..<0.75: return .middle
        default: return .cadence
        }
    }
}

/// Counts of what followed what, at several context lengths at once.
struct MelodyChain: Codable, Hashable, Sendable {
    static let schemaVersion = 1
    /// The longest history the model keeps. Two events is a figure; three is
    /// almost always a context seen exactly once.
    static let maxOrder = 2
    /// How often a context has to have been seen before it's trusted over a
    /// shorter one. Two, because a context seen once can only quote.
    static let trustThreshold = 2

    var version: Int = MelodyChain.schemaVersion
    var takes: Int = 0
    var bars: Int = 0
    /// context key → token key → count.
    var counts: [String: [String: Int]] = [:]
    /// What a line tends to start with, by metric position.
    var openings: [String: Int] = [:]

    var isEmpty: Bool { counts.isEmpty }
    var transitions: Int { counts.values.reduce(0) { $0 + $1.values.reduce(0, +) } }
    var contexts: Int { counts.count }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        takes = try container.decodeIfPresent(Int.self, forKey: .takes) ?? 0
        bars = try container.decodeIfPresent(Int.self, forKey: .bars) ?? 0
        counts = try container.decodeIfPresent([String: [String: Int]].self, forKey: .counts) ?? [:]
        openings = try container.decodeIfPresent([String: Int].self, forKey: .openings) ?? [:]
    }
}

// MARK: - Context keys

extension MelodyChain {

    /// The ladder, longest first. Each rung drops the least load-bearing part of
    /// the context, in the order that costs the music least:
    ///
    /// 1. two events, the bar position and the phrase position;
    /// 2. the same without the phrase position;
    /// 3. one event and the bar position;
    /// 4. one event alone;
    /// 5. the bar position alone — the marginal, and always populated.
    ///
    /// Bar position outlives history on purpose. Knowing you're on beat one is
    /// worth more than knowing what happened two notes ago, and a model that
    /// forgets the metre first writes lines that don't scan.
    static func contextKeys(history: [ChainToken],
                            metricPosition: Int,
                            phrase: PhrasePosition) -> [String] {
        let metric = metricPosition % 8
        var keys: [String] = []
        if history.count >= 2 {
            let pair = "\(history[history.count - 2].key)>\(history[history.count - 1].key)"
            keys.append("2|\(pair)@\(metric)#\(phrase.rawValue)")
            keys.append("2|\(pair)@\(metric)")
        }
        if let last = history.last {
            keys.append("1|\(last.key)@\(metric)")
            keys.append("1|\(last.key)")
        }
        keys.append("0|@\(metric)")
        return keys
    }
}

// MARK: - Learning

extension MelodyChain {

    /// Folds a pattern in at every context length at once.
    ///
    /// Every event is counted under all five keys, not just the longest one —
    /// which is what makes the backoff ladder available at generation time
    /// without a second pass over the corpus.
    mutating func add(_ pattern: MelodyPattern) {
        let notes = pattern.notes.sorted { $0.startEighth < $1.startEighth }
        guard !notes.isEmpty else { return }

        takes += 1
        bars = max(bars, pattern.bars)

        if let first = notes.first {
            openings["\(first.startEighth % 8)|\(ChainToken(first).key)", default: 0] += 1
        }

        var history: [ChainToken] = []
        for note in notes {
            let token = ChainToken(note)
            let phrase = PhrasePosition.at(eighth: note.startEighth, ofBars: pattern.bars)
            for key in Self.contextKeys(history: history,
                                        metricPosition: note.startEighth,
                                        phrase: phrase) {
                counts[key, default: [:]][token.key, default: 0] += 1
            }
            history.append(token)
            if history.count > Self.maxOrder { history.removeFirst() }
        }
    }

    @discardableResult
    mutating func add(_ take: GenerationRecord) -> Bool {
        guard let progression = try? ChordProgression.parse(take.progressionText),
              let pattern = MelodyPatterns.extract(from: take.notes,
                                                   over: progression,
                                                   name: take.displayName,
                                                   lengthBeats: take.lengthBeats)
        else { return false }
        add(pattern)
        return true
    }

    static func learn(from takes: [GenerationRecord]) -> MelodyChain {
        var chain = MelodyChain()
        for take in takes { chain.add(take) }
        return chain
    }

    static func learn(from patterns: [MelodyPattern]) -> MelodyChain {
        var chain = MelodyChain()
        for pattern in patterns { chain.add(pattern) }
        return chain
    }
}

// MARK: - Generating

extension MelodyChain {

    /// Walks the chain to produce a new line.
    ///
    /// - Parameters:
    ///   - bars: how long.
    ///   - seed: everything random comes from here.
    ///   - temperature: 1 samples the counts as observed; below 1 sharpens
    ///     toward what the corpus does most; above 1 flattens toward what it did
    ///     rarely. The lever the model actually has, as against the language
    ///     model's, which measurement showed does almost nothing (ROADMAP G5).
    func generate(bars: Int = 4,
                  seed: UInt64,
                  temperature: Double = 1,
                  name: String? = nil) -> MelodyPattern? {
        guard !isEmpty else { return nil }
        var rng = SplitMix64(seed: seed &* 0x9E3779B97F4A7C15 &+ 0x1234_5678)

        let totalEighths = max(8, bars * 8)
        var notes: [PatternNote] = []
        var history: [ChainToken] = []
        var cursor = 0

        // Start from something the corpus actually started with, at the position
        // it started at — a line that begins mid-phrase sounds like a tape
        // spliced in.
        if let opening = pickOpening(&rng), let token = ChainToken(key: opening.token) {
            cursor = opening.metric
            notes.append(note(from: token, at: cursor))
            history.append(token)
            cursor += token.spanEighths
        }

        while cursor < totalEighths {
            let phrase = PhrasePosition.at(eighth: cursor, ofBars: bars)
            guard let token = next(after: history,
                                   metricPosition: cursor,
                                   phrase: phrase,
                                   temperature: temperature,
                                   rng: &rng) else { break }

            notes.append(note(from: token, at: cursor))
            history.append(token)
            if history.count > Self.maxOrder { history.removeFirst() }
            cursor += token.spanEighths
        }

        guard !notes.isEmpty else { return nil }

        // Clip the tail so the line ends inside its form.
        if var last = notes.last, last.startEighth + last.lengthEighths > totalEighths {
            last.lengthEighths = max(1, totalEighths - last.startEighth)
            notes[notes.count - 1] = last
        }
        notes = notes.filter { $0.startEighth < totalEighths }

        return MelodyPattern(
            name: name ?? "Chained \(seed % 1000)",
            bars: max(1, bars),
            summary: "walked from \(takes) take\(takes == 1 ? "" : "s"), "
                   + "\(notes.count) notes over \(bars) bars",
            notes: notes
        )
    }

    private func note(from token: ChainToken, at eighth: Int) -> PatternNote {
        PatternNote(startEighth: eighth,
                    lengthEighths: token.lengthEighths,
                    degree: token.degree,
                    octave: 0,
                    alteration: token.alteration,
                    velocity: 88,
                    restAfterEighths: token.restAfterEighths,
                    role: nil)
    }

    /// The backoff itself: take the longest context that has been seen often
    /// enough to be worth trusting.
    private func next(after history: [ChainToken],
                      metricPosition: Int,
                      phrase: PhrasePosition,
                      temperature: Double,
                      rng: inout SplitMix64) -> ChainToken? {
        let keys = Self.contextKeys(history: history,
                                    metricPosition: metricPosition,
                                    phrase: phrase)

        // Fixed draw, taken before the search, so which rung of the ladder a
        // model happens to land on doesn't change its random stream. Two models
        // sampled at one seed stay comparable.
        let draw = rng.nextUnit()

        for key in keys {
            guard let distribution = counts[key] else { continue }
            let total = distribution.values.reduce(0, +)
            // A context seen once can only quote what happened that time. Drop
            // to a shorter one and let the model actually choose.
            guard total >= Self.trustThreshold || key.hasPrefix("0|") else { continue }
            if let picked = pick(from: distribution, draw: draw, temperature: temperature) {
                return ChainToken(key: picked)
            }
        }

        // Nothing at any length: fall back to the whole corpus's vocabulary,
        // which is the marginal and is never empty when the model isn't.
        var everything: [String: Int] = [:]
        for (key, distribution) in counts where key.hasPrefix("0|") {
            for (token, count) in distribution { everything[token, default: 0] += count }
        }
        return pick(from: everything, draw: draw, temperature: temperature).flatMap(ChainToken.init(key:))
    }

    private func pickOpening(_ rng: inout SplitMix64) -> (metric: Int, token: String)? {
        guard !openings.isEmpty else { return nil }
        let draw = rng.nextUnit()
        guard let key = pick(from: openings, draw: draw, temperature: 1) else { return nil }
        let parts = key.split(separator: "|", maxSplits: 1)
        guard parts.count == 2, let metric = Int(parts[0]) else { return nil }
        return (metric, String(parts[1]))
    }

    /// Weighted pick, in a stable key order, with temperature.
    private func pick(from histogram: [String: Int],
                      draw: Double,
                      temperature: Double) -> String? {
        guard !histogram.isEmpty else { return nil }
        let entries = histogram.sorted { $0.key < $1.key }
        let exponent = 1 / max(0.05, temperature)
        let weights = entries.map { pow(Double($0.value), exponent) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return entries.first?.key }

        var remaining = draw * total
        for (index, weight) in weights.enumerated() {
            remaining -= weight
            if remaining <= 0 { return entries[index].key }
        }
        return entries.last?.key
    }
}

// MARK: - Reading it

extension MelodyChain {

    var summary: String {
        guard !isEmpty else { return "No chain yet — keep some takes first." }
        let trusted = counts.values.filter { $0.values.reduce(0, +) >= Self.trustThreshold }.count
        return "\(takes) takes · \(transitions) transitions · \(contexts) contexts "
             + "(\(trusted) seen more than once)"
    }

    /// How much of the model is actually usable at full length — the honest
    /// measure of whether there's enough material for order 2 to mean anything.
    var trustedShare: Double {
        let long = counts.filter { $0.key.hasPrefix("2|") }
        guard !long.isEmpty else { return 0 }
        let trusted = long.values.filter { $0.values.reduce(0, +) >= Self.trustThreshold }.count
        return Double(trusted) / Double(long.count)
    }
}

/// Which model a draw from your own material comes out of.
///
/// Two models, learned from the same takes, that know different things. The slot
/// model knows *where* this material puts notes and nothing about order, so it
/// has the groove and no phrases. The chain knows what follows what, so it has
/// phrases and only as much groove as the metric position in its context carries.
/// Neither is the better one; they're different instruments, and which one is
/// wanted is a musical decision rather than something to pick automatically.
enum LearnedDraw: String, Codable, CaseIterable, Sendable {
    case slots, chain

    var label: String {
        switch self {
        case .slots: return "Slots"
        case .chain: return "Chain"
        }
    }

    var explanation: String {
        switch self {
        case .slots: return "Where your material puts notes. Groove, no memory."
        case .chain: return "What follows what in it. Phrases, less groove."
        }
    }
}
