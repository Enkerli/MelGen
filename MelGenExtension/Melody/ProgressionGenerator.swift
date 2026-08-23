//
//  ProgressionGenerator.swift
//  MelGenExtension
//
//  Generating the changes, not just the line.
//
//  Ported from ProgGenie (music-suite/packages/proggen), tables and all. The
//  method is a variable-order walk over corpus transition counts between
//  Roman-numeral labels: what follows "IIm7", blended with what follows
//  "IIm7 → V7", backing off to the first order when the second is sparse.
//
//  That is the same machinery as MelodyChain.swift one level up, and the
//  resemblance is worth noticing rather than tidying away: a progression is a
//  sequence of symbols with strong local dependencies and weak long ones, and so
//  is a melody. Both want order-2 where the corpus supports it and order-1
//  everywhere else; both are ruined by trusting a context seen once.
//
//  What this is *for* here is the thing the whole project is exploring: generate
//  the changes, adapt patterns to them, curate the results, without leaving the
//  environment. Until now a progression arrived by being typed or pasted, which
//  meant every experiment started with a trip to another application.
//
//  Realization goes through MelGen's own chord dictionary rather than a second
//  copy of the theory: a label becomes a numeral and a suffix, the numeral
//  becomes a pitch class in the chosen key, and the pair becomes leadsheet text
//  that `ChordProgression.parse` reads back. Anything the dictionary can't parse
//  is skipped rather than emitted, so a generated progression is always one the
//  rest of the plug-in can actually play.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

/// Major or minor, which is which corpus table gets walked.
enum ProgressionMode: String, Codable, CaseIterable, Sendable {
    case major, minor

    var label: String { self == .major ? "Major" : "Minor" }
}

/// One generated progression, with what produced it.
struct GeneratedProgression: Sendable {
    /// The Roman-numeral labels, in order — the corpus's own vocabulary.
    var labels: [String]
    /// Leadsheet text, one chord per bar, ready for `ChordProgression.parse`.
    var text: String
    var key: Int
    var mode: ProgressionMode
    var seed: UInt64

    var summary: String {
        "\(labels.count) bars in \(ChordProgression.flatNoteNames[key]) \(mode.rawValue) · "
            + labels.joined(separator: " ")
    }
}

enum ProgressionGenerator {

    /// How much a second-order context is allowed to say, at most. The rest is
    /// the first order, which is always populated.
    static let trigramStrength = 0.75
    /// The backoff constant: a second-order context needs to have been seen
    /// about this many times before it dominates. Sparse contexts fall back
    /// toward the first order rather than quoting the one time they were seen —
    /// the same rule, and the same reason, as the melodic chain's trust
    /// threshold.
    static let backoffConstant = 8.0

    // MARK: - Tables

    private static let cache = TableCache()

    /// Parses "context;next:count,…|context;…" into a dictionary. Done once.
    static func parse(_ encoded: String) -> [String: [String: Int]] {
        var table: [String: [String: Int]] = [:]
        for group in encoded.split(separator: "|") {
            let halves = group.split(separator: ";", maxSplits: 1)
            guard halves.count == 2 else { continue }
            var row: [String: Int] = [:]
            for entry in halves[1].split(separator: ",") {
                guard let colon = entry.lastIndex(of: ":"),
                      let count = Int(entry[entry.index(after: colon)...]) else { continue }
                row[String(entry[..<colon])] = count
            }
            if !row.isEmpty { table[String(halves[0])] = row }
        }
        return table
    }

    static func bigrams(_ mode: ProgressionMode) -> [String: [String: Int]] {
        cache.bigrams(mode)
    }

    static func trigrams(_ mode: ProgressionMode) -> [String: [String: Int]] {
        cache.trigrams(mode)
    }

    /// Lazily parsed, once per mode. The tables are a hundred kilobytes of
    /// string; parsing them on every generate would be visible.
    private final class TableCache: @unchecked Sendable {
        private var parsedBigrams: [ProgressionMode: [String: [String: Int]]] = [:]
        private var parsedTrigrams: [ProgressionMode: [String: [String: Int]]] = [:]
        private let lock = NSLock()

        func bigrams(_ mode: ProgressionMode) -> [String: [String: Int]] {
            lock.lock(); defer { lock.unlock() }
            if let cached = parsedBigrams[mode] { return cached }
            let parsed = ProgressionGenerator.parse(
                mode == .major ? ProgressionTables.majorBigrams : ProgressionTables.minorBigrams)
            parsedBigrams[mode] = parsed
            return parsed
        }

        func trigrams(_ mode: ProgressionMode) -> [String: [String: Int]] {
            lock.lock(); defer { lock.unlock() }
            if let cached = parsedTrigrams[mode] { return cached }
            let parsed = ProgressionGenerator.parse(
                mode == .major ? ProgressionTables.majorTrigrams : ProgressionTables.minorTrigrams)
            parsedTrigrams[mode] = parsed
            return parsed
        }
    }

    // MARK: - Labels

    /// Splits "♭VII7" into its numeral and its suffix.
    static func split(_ label: String) -> (numeral: String, suffix: String)? {
        var index = label.startIndex
        var accidentals = ""
        while index < label.endIndex, "♭♯b#𝄪𝄫".contains(label[index]) {
            accidentals.append(label[index])
            index = label.index(after: index)
        }
        // Longest numeral first, or "III" reads as "II" and leaves an "I" behind.
        for numeral in ["VII", "VI", "IV", "V", "III", "II", "I"] where label[index...].hasPrefix(numeral) {
            let after = label.index(index, offsetBy: numeral.count)
            return (accidentals + numeral, String(label[after...]))
        }
        return nil
    }

    /// Semitones above the tonic for a numeral, accidentals included.
    static func semitones(for numeral: String) -> Int? {
        var offset = 0
        var rest = Substring(numeral)
        while let first = rest.first, "♭♯b#𝄪𝄫".contains(first) {
            switch first {
            case "♭", "b": offset -= 1
            case "♯", "#": offset += 1
            case "𝄪": offset += 2
            case "𝄫": offset -= 2
            default: break
            }
            rest = rest.dropFirst()
        }
        let degrees = ["I": 0, "II": 2, "III": 4, "IV": 5, "V": 7, "VI": 9, "VII": 11]
        guard let base = degrees[String(rest)] else { return nil }
        return ((base + offset) % 12 + 12) % 12
    }

    /// A label as leadsheet text in a key, or nil when this plug-in's dictionary
    /// can't read the result.
    ///
    /// Checking rather than trusting: the corpus vocabulary is larger than the
    /// dictionary's, and emitting a chord the parser then rejects would turn a
    /// generated progression into an error message.
    static func chordText(for label: String, key: Int) -> String? {
        guard let parts = split(label),
              let offset = semitones(for: parts.numeral) else { return nil }
        let root = (key + offset) % 12
        let text = ChordProgression.flatNoteNames[root] + parts.suffix
        guard (try? ChordProgression.parseChordSymbol(text)) != nil else { return nil }
        return text
    }

    // MARK: - Generating

    /// Walks the corpus tables into a progression.
    ///
    /// - Parameters:
    ///   - bars: how many chords. One per bar, which is what the corpus counted.
    ///   - temperature: 1 samples the counts as they are; below 1 sharpens toward
    ///     what the corpus does most, above 1 flattens toward what it did rarely.
    ///   - cadence: end on the tonic. On by default — a generated progression
    ///     that stops mid-phrase is a fragment, and this is meant to be looped.
    /// - Parameter substitution: how often a chord in the walk is rewritten by a
    ///   substitution. 0 leaves the corpus walk alone.
    ///
    ///   The walk on its own produces what the corpus does *most*, which is what
    ///   a transition count is for and also why it comes out sounding like the
    ///   most ordinary version of itself. Substitutions are the other half of
    ///   how anybody writes changes: the moves are conventional and then you
    ///   replace some of them. Applying them afterwards rather than folding them
    ///   into the walk keeps both legible — the numerals say what the corpus
    ///   proposed and the reharmonization says what was done to it.
    static func generate(bars: Int = 8,
                         key: Int = 0,
                         mode: ProgressionMode = .major,
                         temperature: Double = 1,
                         substitution: Double = 0,
                         cadence: Bool = true,
                         seed: UInt64) -> GeneratedProgression? {
        let first = bigrams(mode)
        let second = trigrams(mode)
        guard !first.isEmpty else { return nil }

        var rng = SplitMix64(seed: seed &* 0x2545F4914F6CDD1D &+ 0x9E37)
        let bars = max(2, bars)

        // Start on the tonic — a corpus walk that starts anywhere starts nowhere —
        // and on the *right* tonic: "I" in a minor corpus is a major chord, and
        // opening a minor progression on it says the piece is in the other mode.
        var labels = [tonic(for: mode, in: first)]
        while labels.count < bars {
            let previous = labels[labels.count - 1]
            let context = labels.count >= 2
                ? "\(labels[labels.count - 2]) → \(previous)"
                : nil

            let blended = blend(first: first[previous] ?? [:],
                                second: context.flatMap { second[$0] } ?? [:])
            guard !blended.isEmpty else { break }

            // The last chord goes home if anything in reach does — and to a
            // tonic that sounds like an ending. "Idim7" has the right numeral
            // and is not a cadence.
            if cadence, labels.count == bars - 1 {
                let tonics = blended.keys.filter { split($0)?.numeral == "I" }
                let reachable = tonics.min { cadenceRank($0, mode) < cadenceRank($1, mode) }
                if let reachable, cadenceRank(reachable, mode) < Int.max {
                    labels.append(reachable)
                } else {
                    // Nothing at home is in reach from here. The corpus not
                    // having seen this particular approach to the tonic is not a
                    // reason to end somewhere else when the caller asked to end
                    // at home — every progression that resolves has a first time
                    // somewhere, and a loop that never comes home is a fragment.
                    labels.append(tonic(for: mode, in: first))
                }
                continue
            }

            guard let next = pick(blended, draw: rng.nextUnit(), temperature: temperature) else { break }
            labels.append(next)
        }

        if substitution > 0 {
            labels = substitute(labels, amount: substitution, mode: mode, rng: &rng)
        }

        // Drop anything the dictionary can't spell rather than emitting it.
        let playable = labels.compactMap { label -> (String, String)? in
            chordText(for: label, key: key).map { (label, $0) }
        }
        guard playable.count >= 2 else { return nil }

        return GeneratedProgression(labels: playable.map(\.0),
                                    text: playable.map(\.1).joined(separator: "|"),
                                    key: key,
                                    mode: mode,
                                    seed: seed)
    }

    // MARK: - Substitutions

    /// One way of rewriting a chord, and when it applies.
    enum Substitution: String, CaseIterable, Sendable {
        /// A dominant replaced by the dominant a tritone away: V7 becomes ♭II7.
        /// The most recognisable reharmonization there is, and it works because
        /// the two chords share their third and seventh.
        case tritone
        /// The dominant of whatever comes next, inserted in place of what was
        /// there. Turns a walk into a chain of resolutions.
        case secondaryDominant
        /// A major chord for its relative minor or the reverse — same key, a
        /// different colour under the same melody.
        case relative
        /// The chord borrowed from the parallel mode: IV becomes IVm, or a minor
        /// chord brightens. The move that makes an ordinary progression sound
        /// like it was written by someone.
        case borrowed
        /// A seventh chord gains its extensions.
        case extended

        var label: String {
            switch self {
            case .tritone: return "tritone sub"
            case .secondaryDominant: return "secondary dominant"
            case .relative: return "relative swap"
            case .borrowed: return "borrowed"
            case .extended: return "extended"
            }
        }
    }

    /// Rewrites some of the walk.
    ///
    /// Never the first or last chord: those are the tonic, and a progression
    /// whose home has been substituted has lost the thing the substitutions are
    /// heard against.
    static func substitute(_ labels: [String],
                           amount: Double,
                           mode: ProgressionMode,
                           rng: inout SplitMix64) -> [String] {
        guard labels.count > 2 else { return labels }
        var result = labels

        for index in 1..<(labels.count - 1) {
            guard rng.nextUnit() < amount else { continue }
            guard let parts = split(result[index]) else { continue }
            let next = split(result[index + 1])

            var options: [Substitution] = [.extended]
            if parts.suffix.hasPrefix("7") || parts.suffix.isEmpty {
                options.append(.borrowed)
            }
            if isDominant(parts.suffix) { options.append(.tritone) }
            if let next, semitones(for: next.numeral) != nil { options.append(.secondaryDominant) }
            if parts.suffix.isEmpty || parts.suffix.hasPrefix("maj") || parts.suffix.hasPrefix("m") {
                options.append(.relative)
            }

            let choice = options[Int(rng.next() % UInt64(options.count))]
            if let rewritten = apply(choice, to: parts, before: next, mode: mode),
               chordText(for: rewritten, key: 0) != nil {
                result[index] = rewritten
            }
        }
        return result
    }

    static func isDominant(_ suffix: String) -> Bool {
        guard suffix.hasPrefix("7") || suffix.hasPrefix("9") || suffix.hasPrefix("13") else { return false }
        return !suffix.hasPrefix("7sus") || suffix.hasPrefix("7sus4")
    }

    /// Applies one substitution to one chord, or gives up.
    static func apply(_ substitution: Substitution,
                      to parts: (numeral: String, suffix: String),
                      before next: (numeral: String, suffix: String)?,
                      mode: ProgressionMode) -> String? {
        guard let degree = semitones(for: parts.numeral) else { return nil }

        switch substitution {
        case .tritone:
            return numeral(for: (degree + 6) % 12) + (parts.suffix.isEmpty ? "7" : parts.suffix)

        case .secondaryDominant:
            // The dominant *of* what comes next, so the substitution earns its
            // place by resolving rather than by being unexpected.
            guard let next, let target = semitones(for: next.numeral) else { return nil }
            let fifth = (target + 7) % 12
            guard fifth != degree else { return nil }
            return numeral(for: fifth) + "7"

        case .relative:
            let isMinor = parts.suffix.hasPrefix("m") && !parts.suffix.hasPrefix("maj")
            let moved = isMinor ? (degree + 3) % 12 : (degree + 9) % 12
            let suffix = isMinor
                ? (parts.suffix.hasPrefix("m7") ? "maj7" : "")
                : (parts.suffix.contains("7") ? "m7" : "m")
            return numeral(for: moved) + suffix

        case .borrowed:
            // Toward the parallel mode: a major chord darkens, a minor one
            // brightens.
            if parts.suffix.hasPrefix("m") && !parts.suffix.hasPrefix("maj") {
                return parts.numeral + (parts.suffix.hasPrefix("m7") ? "7" : "")
            }
            return parts.numeral + (parts.suffix.contains("7") ? "m7" : "m")

        case .extended:
            let extensions = mode == .major
                ? ["maj9", "6", "9", "13", "maj7"]
                : ["m9", "m11", "m6", "7b9", "7alt"]
            let base = parts.suffix.isEmpty ? "" : parts.suffix
            _ = base
            return parts.numeral + extensions[abs(degree) % extensions.count]
        }
    }

    /// The numeral for a number of semitones above the tonic, spelled the way the
    /// corpus spells it.
    static func numeral(for semitones: Int) -> String {
        let table = ["I", "♭II", "II", "♭III", "III", "IV", "♯IV", "V", "♭VI", "VI", "♭VII", "VII"]
        return table[((semitones % 12) + 12) % 12]
    }

    /// Which tonic a mode opens on, preferring what the corpus actually contains.
    static func tonic(for mode: ProgressionMode, in table: [String: [String: Int]]) -> String {
        let candidates = mode == .major
            ? ["I", "Imaj7", "I6", "Imaj9"]
            : ["Im7", "Im", "Im6", "ImMaj7", "I"]
        return candidates.first { table[$0] != nil } ?? candidates[0]
    }

    /// How much a tonic chord sounds like an ending, in this mode. Lower is more
    /// final; `Int.max` means "has the numeral but isn't a cadence".
    ///
    /// Mode-dependent, because ending a major progression on a minor tonic is
    /// not a cadence, it's a modal interchange — a fine thing to pass through and
    /// a strange thing to stop on.
    static func cadenceRank(_ label: String, _ mode: ProgressionMode) -> Int {
        let endings = mode == .major
            ? ["I", "Imaj7", "I6", "I69", "Imaj9", "I5", "Im7", "Im"]
            : ["Im7", "Im", "Im6", "Im9", "ImMaj7", "I5", "I", "Imaj7"]
        return endings.firstIndex(of: label) ?? Int.max
    }

    /// Interpolates the second-order distribution into the first, in count space
    /// so temperature still means the same thing afterwards.
    ///
    /// λ = strength · total₂ / (total₂ + K): a second-order context seen twice
    /// barely shifts the result, one seen fifty times dominates it. That is the
    /// backoff, expressed as a blend rather than as a branch — which is what
    /// keeps it smooth as a corpus grows.
    static func blend(first: [String: Int], second: [String: Int]) -> [String: Double] {
        let firstTotal = Double(first.values.reduce(0, +))
        let secondTotal = Double(second.values.reduce(0, +))
        guard firstTotal > 0 else {
            return second.mapValues(Double.init)
        }
        guard secondTotal > 0 else {
            return first.mapValues(Double.init)
        }

        let lambda = trigramStrength * secondTotal / (secondTotal + backoffConstant)
        var blended: [String: Double] = [:]
        for (label, count) in first {
            blended[label] = (1 - lambda) * Double(count)
        }
        for (label, count) in second {
            blended[label, default: 0] += lambda * firstTotal * (Double(count) / secondTotal)
        }
        return blended
    }

    /// Weighted pick in a stable key order, with temperature.
    static func pick(_ distribution: [String: Double],
                     draw: Double,
                     temperature: Double) -> String? {
        guard !distribution.isEmpty else { return nil }
        let entries = distribution.sorted { $0.key < $1.key }
        let exponent = 1 / max(0.05, temperature)
        let weights = entries.map { pow(max(0, $0.value), exponent) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return entries.first?.key }

        var remaining = draw * total
        for (index, weight) in weights.enumerated() {
            remaining -= weight
            if remaining <= 0 { return entries[index].key }
        }
        return entries.last?.key
    }

    /// How much of the corpus this plug-in can actually spell.
    ///
    /// Worth knowing and worth reporting: the corpus vocabulary is larger than
    /// the dictionary's, and the honest number is more useful than the assumption
    /// that they match.
    static func coverage(mode: ProgressionMode, key: Int = 0) -> (spelled: Int, total: Int) {
        var labels = Set<String>()
        for (context, row) in bigrams(mode) {
            labels.insert(context)
            labels.formUnion(row.keys)
        }
        let spelled = labels.filter { chordText(for: $0, key: key) != nil }.count
        return (spelled, labels.count)
    }
}
