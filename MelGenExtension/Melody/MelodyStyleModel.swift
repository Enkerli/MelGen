//
//  MelodyStyleModel.swift
//  MelGenExtension
//
//  Statistics per grid slot, and a sampler that draws new lines from them.
//
//  Ported from `@enkerli/accompaniment`'s `StyleModel` in the suite, and the
//  design decisions are that package's rather than new ones — they were arrived
//  at over a much larger corpus than this project has, and reinventing them here
//  would have meant learning them again the slow way. What travels:
//
//  *Slots, not sequences.* A corpus of takes over a shared harmonic frame becomes
//  per-slot distributions: at this position in the bar, how often did a note
//  start, how loud, how long, how far off the grid line, and which scale degrees
//  showed up. Sampling draws each slot independently. That reproduces the
//  *habits* of the material — where it puts things — rather than replaying any
//  take in it.
//
//  *Counts and sums, never averages.* Every field accumulates, so adding one more
//  take is O(events) and nothing has to be recomputed. That is the co-learning
//  property: play continuously, feed takes in, the model keeps absorbing. It is
//  also what makes learning from incoming MIDI a matter of calling `add` rather
//  than of designing a second pipeline.
//
//  *`covered` as the denominator.* A slot's onset probability is `count /
//  covered`, where `covered` counts the takes long enough to have voted on that
//  slot. A two-bar take doesn't get an opinion about bar three.
//
//  *Degrees, keyed `degree:alteration:role`.* The suite's `degreeKey`, with
//  MelGen's `HarmonicRole` where it says `category`. Verbose on purpose: it's a
//  dictionary key that has to survive being read by a human in two years, and
//  every part of it is needed to place the note again. This is what lets a model
//  learned over one progression play over another — which is the whole reason the
//  pattern format is degree-relative.
//
//  One deliberate divergence. The suite samples absolute notes and re-infers
//  their chord relations afterwards, because its corpora are audio-derived loops
//  whose harmony has to be guessed. MelGen always knows the progression a take
//  was played over, so it stores and samples degrees directly and skips the
//  round trip.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

/// One grid position's distribution.
///
/// Everything here is a running total. Nothing is divided until it's asked for,
/// which is what makes a model something you can keep adding to for a year.
struct StyleSlot: Codable, Hashable, Sendable {
    /// Takes long enough to have voted on this slot — the onset denominator.
    var covered: Int = 0
    /// Onsets actually seen here.
    var count: Int = 0
    var velocitySum: Double = 0
    var velocitySquareSum: Double = 0
    /// Note lengths in eighths.
    var lengthSum: Double = 0
    var lengthSquareSum: Double = 0
    /// Silence asked for after a note here, in eighths.
    var restSum: Double = 0
    /// Micro-timing against the grid line, in eighths, signed. Always zero for
    /// material MelGen generated — it writes to the grid — and the reason the
    /// field exists anyway is that captured playing won't be.
    var deviationSum: Double = 0
    var deviationSquareSum: Double = 0
    /// Chord-relative vocabulary at this slot, keyed by `StyleSlot.degreeKey`.
    var degrees: [String: Int] = [:]

    var onsetProbability: Double {
        covered > 0 ? min(1, Double(count) / Double(covered)) : 0
    }

    var meanVelocity: Double { count > 0 ? velocitySum / Double(count) : 88 }
    var meanLength: Double { count > 0 ? max(1, lengthSum / Double(count)) : 1 }
    var meanRest: Double { count > 0 ? restSum / Double(count) : 0 }
    var meanDeviation: Double { count > 0 ? deviationSum / Double(count) : 0 }

    var velocitySpread: Double { spread(velocitySum, velocitySquareSum, count) }
    var lengthSpread: Double { spread(lengthSum, lengthSquareSum, count) }
    var deviationSpread: Double { spread(deviationSum, deviationSquareSum, count) }

    private func spread(_ sum: Double, _ squareSum: Double, _ count: Int) -> Double {
        guard count > 1 else { return 0 }
        let mean = sum / Double(count)
        return max(0, (squareSum / Double(count) - mean * mean).squareRoot())
    }

    /// `degree:alteration:role`. The suite's key, with MelGen's role vocabulary.
    static func degreeKey(degree: Int, alteration: Int, role: HarmonicRole?) -> String {
        "\(degree):\(alteration):\(role?.rawValue ?? "unclassified")"
    }

    static func parseDegreeKey(_ key: String) -> (degree: Int, alteration: Int, role: HarmonicRole?)? {
        let parts = key.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let degree = Int(parts[0]), let alteration = Int(parts[1]) else { return nil }
        return (degree, alteration, HarmonicRole(rawValue: String(parts[2])))
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        covered = try container.decodeIfPresent(Int.self, forKey: .covered) ?? 0
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        velocitySum = try container.decodeIfPresent(Double.self, forKey: .velocitySum) ?? 0
        velocitySquareSum = try container.decodeIfPresent(Double.self, forKey: .velocitySquareSum) ?? 0
        lengthSum = try container.decodeIfPresent(Double.self, forKey: .lengthSum) ?? 0
        lengthSquareSum = try container.decodeIfPresent(Double.self, forKey: .lengthSquareSum) ?? 0
        restSum = try container.decodeIfPresent(Double.self, forKey: .restSum) ?? 0
        deviationSum = try container.decodeIfPresent(Double.self, forKey: .deviationSum) ?? 0
        deviationSquareSum = try container.decodeIfPresent(Double.self, forKey: .deviationSquareSum) ?? 0
        degrees = try container.decodeIfPresent([String: Int].self, forKey: .degrees) ?? [:]
    }
}

/// A style, as slot statistics over a shared grid.
struct MelodyStyleModel: Codable, Hashable, Sendable {
    static let schemaVersion = 1

    var version: Int = MelodyStyleModel.schemaVersion
    var id: String
    /// Grid slots per beat. 2 is the eighth-note grid the whole plug-in speaks;
    /// a finer grid (ROADMAP D1) would raise it and nothing else here changes.
    var grid: Int = 2
    var beatsPerBar: Int = 4
    /// Bars covered — the longest take folded in.
    var bars: Int = 0
    /// How many takes are behind these numbers.
    var takes: Int = 0
    var slots: [StyleSlot] = []
    /// The tags on the material, most used first.
    var tags: [String] = []

    var slotsPerBar: Int { beatsPerBar * grid }
    var isEmpty: Bool { takes == 0 || slots.allSatisfy { $0.count == 0 } }
    /// Onsets behind the whole model — the honest measure of how much it knows.
    var observations: Int { slots.reduce(0) { $0 + $1.count } }

    init(id: String, grid: Int = 2, beatsPerBar: Int = 4) {
        self.id = id
        self.grid = grid
        self.beatsPerBar = beatsPerBar
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "style"
        grid = try container.decodeIfPresent(Int.self, forKey: .grid) ?? 2
        beatsPerBar = try container.decodeIfPresent(Int.self, forKey: .beatsPerBar) ?? 4
        bars = try container.decodeIfPresent(Int.self, forKey: .bars) ?? 0
        takes = try container.decodeIfPresent(Int.self, forKey: .takes) ?? 0
        slots = try container.decodeIfPresent([StyleSlot].self, forKey: .slots) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

// MARK: - Accumulating

extension MelodyStyleModel {

    /// Folds one pattern into the statistics.
    ///
    /// A take longer than the model extends it; a shorter one only votes on the
    /// slots it covers. O(notes), and nothing is recomputed — which is what makes
    /// "keep playing, keep feeding it in" a real workflow rather than a rebuild.
    mutating func add(_ pattern: MelodyPattern) {
        let patternSlots = max(1, pattern.bars * slotsPerBar)
        while slots.count < patternSlots { slots.append(StyleSlot()) }
        bars = max(bars, pattern.bars)
        takes += 1

        for index in 0..<min(patternSlots, slots.count) {
            slots[index].covered += 1
        }

        for note in pattern.notes {
            // The pattern grid is eighths; the model's may be finer.
            let slotIndex = (note.startEighth * grid) / 2
            guard slotIndex >= 0, slotIndex < slots.count else { continue }
            let deviation = Double(note.startEighth * grid) / 2 - Double(slotIndex)

            slots[slotIndex].count += 1
            slots[slotIndex].velocitySum += Double(note.velocity)
            slots[slotIndex].velocitySquareSum += Double(note.velocity * note.velocity)
            slots[slotIndex].lengthSum += Double(note.lengthEighths)
            slots[slotIndex].lengthSquareSum += Double(note.lengthEighths * note.lengthEighths)
            slots[slotIndex].restSum += Double(note.restAfterEighths)
            slots[slotIndex].deviationSum += deviation
            slots[slotIndex].deviationSquareSum += deviation * deviation

            let key = StyleSlot.degreeKey(degree: note.degree,
                                          alteration: note.alteration,
                                          role: note.role)
            slots[slotIndex].degrees[key, default: 0] += 1
        }
    }

    /// Folds in a take, reading it back to degrees first.
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

    /// Builds a model over a set of takes.
    static func learn(from takes: [GenerationRecord], id: String = "kept") -> MelodyStyleModel {
        var model = MelodyStyleModel(id: id)
        var tagCounts: [String: Int] = [:]
        for take in takes where model.add(take) {
            for tag in take.tags { tagCounts[tag, default: 0] += 1 }
        }
        model.tags = tagCounts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        return model
    }
}

// MARK: - Sampling

extension MelodyStyleModel {

    /// Draws a new line from the statistics.
    ///
    /// Each slot fires independently at its own observed probability, then picks
    /// a degree from the vocabulary seen there. What comes out has never been
    /// played and puts its notes where this material puts them.
    ///
    /// - Parameters:
    ///   - seed: everything random comes from here, so a line can be got back.
    ///   - pass: a second line from the same seed. The suite's `(seed, pass)`
    ///     convention, kept so the two projects mean the same thing by it.
    ///   - density: scales every onset probability. 1 is as observed.
    ///   - humanize: scales the spread on velocity and micro-timing. 0 plays the
    ///     means exactly, which is a useful thing to be able to hear.
    ///   - avoidRepeats: skips a degree identical to the one just drawn when the
    ///     slot's vocabulary offers anything else. This is the smallest possible
    ///     amount of memory, and it's here because a slot model has none at all:
    ///     each draw is independent, so the same degree comes up twice in a row
    ///     about as often as chance says it should, and a repeated pitch is the
    ///     single thing that most makes a sampled line sound broken rather than
    ///     new. Real memory — a state that knows what preceded it — is the
    ///     variable-order model in MelodyChain.swift; this is a stopgap and is
    ///     labelled as one.
    func sample(seed: UInt64,
                pass: Int = 0,
                density: Double = 1,
                humanize: Double = 1,
                avoidRepeats: Bool = true,
                name: String? = nil) -> MelodyPattern? {
        guard !isEmpty else { return nil }
        var rng = SplitMix64(seed: seed &* 2_654_435_761 ^ UInt64(bitPattern: Int64(pass &+ 1) &* 40_503))
        var notes: [PatternNote] = []

        for (index, slot) in slots.enumerated() {
            // A fixed draw budget per slot, whether or not it fires. The suite
            // calls this the aligned-streams discipline: it means a model's draw
            // sequence doesn't depend on what its own corpus happened to contain,
            // so two models sampled at one seed stay comparable.
            let onsetDraw = rng.nextUnit()
            let degreeDraw = rng.nextUnit()
            let velocityDraw = gaussian(&rng)
            let deviationDraw = gaussian(&rng)

            guard slot.covered > 0, slot.count > 0 else { continue }
            guard onsetDraw < min(1, slot.onsetProbability * density) else { continue }

            var vocabulary = slot.degrees
            if avoidRepeats, let last = notes.last, vocabulary.count > 1 {
                // By degree and alteration, not by the whole key: the same note
                // recorded once as a chord tone and once as a colour note is
                // still the same note, and dropping only the exact key would let
                // it repeat under a different label.
                let filtered = vocabulary.filter { entry in
                    guard let parsed = StyleSlot.parseDegreeKey(entry.key) else { return true }
                    return !(parsed.degree == last.degree && parsed.alteration == last.alteration)
                }
                if !filtered.isEmpty { vocabulary = filtered }
            }
            guard let picked = pick(from: vocabulary, draw: degreeDraw),
                  let parsed = StyleSlot.parseDegreeKey(picked) else { continue }

            let velocity = Int((slot.meanVelocity + velocityDraw * slot.velocitySpread * humanize)
                .rounded())
            let deviation = slot.meanDeviation + deviationDraw * slot.deviationSpread * humanize
            let startEighth = max(0, Int((Double(index * 2) / Double(grid) + deviation).rounded()))

            notes.append(PatternNote(
                startEighth: startEighth,
                lengthEighths: max(1, Int(slot.meanLength.rounded())),
                degree: parsed.degree,
                octave: 0,
                alteration: parsed.alteration,
                velocity: min(120, max(40, velocity)),
                restAfterEighths: min(8, max(0, Int(slot.meanRest.rounded()))),
                role: parsed.role
            ))
        }

        // A silent take is not a take: fall back to the slot this material plays
        // most often, so an under-dense draw still says something.
        if notes.isEmpty {
            guard let best = slots.enumerated()
                .filter({ $0.element.count > 0 })
                .max(by: { $0.element.onsetProbability < $1.element.onsetProbability }),
                  let picked = best.element.degrees.max(by: { $0.value < $1.value })?.key,
                  let parsed = StyleSlot.parseDegreeKey(picked)
            else { return nil }
            notes.append(PatternNote(
                startEighth: (best.offset * 2) / grid,
                lengthEighths: max(1, Int(best.element.meanLength.rounded())),
                degree: parsed.degree,
                alteration: parsed.alteration,
                velocity: Int(best.element.meanVelocity.rounded()),
                role: parsed.role
            ))
        }

        // One note per onset, and lengths clipped to the next one. A slot model
        // has no idea what its neighbours drew.
        notes.sort { $0.startEighth < $1.startEighth }
        var tidied: [PatternNote] = []
        for note in notes where tidied.last?.startEighth != note.startEighth {
            tidied.append(note)
        }
        for index in tidied.indices.dropLast() {
            let slot = tidied[index + 1].startEighth - tidied[index].startEighth
            var length = min(tidied[index].lengthEighths, slot)
            let requested = tidied[index].restAfterEighths
            if requested > 0 {
                length = min(length, max(slot - requested, (slot + 1) / 2))
            }
            tidied[index].lengthEighths = max(1, length)
        }

        let modelBars = max(1, bars)
        return MelodyPattern(
            name: name ?? "Learned \(seed % 1000)-\(pass)",
            bars: modelBars,
            summary: "sampled from \(takes) kept take\(takes == 1 ? "" : "s"), "
                   + "\(tidied.count) notes over \(modelBars) bars",
            notes: tidied
        )
    }

    /// Weighted pick from a histogram, in a stable key order — dictionary order
    /// is not a reproducibility guarantee and an explicit sort is.
    private func pick(from histogram: [String: Int], draw: Double) -> String? {
        guard !histogram.isEmpty else { return nil }
        let entries = histogram.sorted { $0.key < $1.key }
        let total = entries.reduce(0) { $0 + $1.value }
        guard total > 0 else { return nil }
        var remaining = draw * Double(total)
        for entry in entries {
            remaining -= Double(entry.value)
            if remaining <= 0 { return entry.key }
        }
        return entries.last?.key
    }

    /// Box–Muller, so velocity and timing spread the way the corpus did rather
    /// than uniformly.
    private func gaussian(_ rng: inout SplitMix64) -> Double {
        let u1 = max(1e-9, rng.nextUnit())
        let u2 = rng.nextUnit()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

// MARK: - Reading it

extension MelodyStyleModel {

    /// What the model knows, in one line.
    var summary: String {
        guard !isEmpty else { return "No model yet — keep some takes first." }
        let played = slots.filter { $0.count > 0 }.count
        return "\(takes) takes · \(observations) onsets · \(played)/\(slots.count) slots played · \(bars) bars"
    }

    /// Which slots this material actually leans on, as a readable row per bar.
    /// Useful for seeing that a model has a groove rather than a smear.
    func onsetMap() -> [String] {
        guard !slots.isEmpty else { return [] }
        return stride(from: 0, to: slots.count, by: slotsPerBar).map { start in
            let end = min(start + slotsPerBar, slots.count)
            let row = slots[start..<end].map { slot -> String in
                switch slot.onsetProbability {
                case 0: return "·"
                case ..<0.25: return "▁"
                case ..<0.5: return "▃"
                case ..<0.75: return "▅"
                default: return "█"
                }
            }
            return "\(start / slotsPerBar + 1) " + row.joined(separator: " ")
        }
    }
}
