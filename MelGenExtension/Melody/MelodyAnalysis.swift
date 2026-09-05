//
//  MelodyAnalysis.swift
//  MelGenExtension
//
//  Measures a take, so curation has something to sort by.
//
//  Two questions, both asked of every take:
//
//  *How varied is it?* Temperature turned out not to be the variety lever — takes
//  come out ostinato-like even near 1.0 — so variety has to be measured rather
//  than dialled. Interval variety, rhythmic variety and self-similarity across
//  bars catch the three ways a line repeats itself.
//
//  *How does it sit on the harmony?* Every note is classified against the chord
//  under it: chord tone, colour tone, avoid note, or off-scale. Non-chord tones
//  aren't errors — they're most of what makes a line interesting — but they are
//  the thing worth *flagging for a human to judge*, which is what curation is.
//
//  Deliberately free of any FoundationModels dependency: it's arithmetic.
//

import Foundation

struct MelodyAnalysis: Codable, Hashable, Sendable {
    // Variety, each 0...1.
    /// Spread of interval sizes. 0 is one interval repeated.
    var intervalVariety: Double = 0
    /// Spread of note lengths. 0 is every note the same length.
    var rhythmicVariety: Double = 0
    /// How much bar N resembles bar N-1. High means ostinato.
    var selfSimilarity: Double = 0

    // Harmony, as counts.
    var chordTones: Int = 0
    var colourTones: Int = 0
    var avoidNotes: Int = 0
    var offScaleNotes: Int = 0

    /// One number for sorting a library by. Variety, penalised for repetition.
    var varietyScore: Double {
        let varied = (intervalVariety + rhythmicVariety) / 2
        return max(0, min(1, varied * (1 - selfSimilarity * 0.7)))
    }

    /// Notes worth a human's attention: off-scale, or landing on an avoid note.
    var notesToReview: Int { offScaleNotes + avoidNotes }

    var summary: String {
        let score = Int((varietyScore * 100).rounded())
        var text = "variety \(score)%"
        if selfSimilarity > 0.6 { text += " · repetitive" }
        text += " · \(chordTones)/\(colourTones)/\(avoidNotes)/\(offScaleNotes) chord/colour/avoid/off"
        return text
    }
}

enum MelodyAnalyser {

    static func analyse(_ notes: [SequencedNote],
                        over progression: ChordProgression,
                        beatsPerBar: Double = 4) -> MelodyAnalysis {
        guard notes.count > 1 else { return MelodyAnalysis() }
        let ordered = notes.sorted { $0.startBeat < $1.startBeat }

        var analysis = MelodyAnalysis()
        analysis.intervalVariety = intervalVariety(ordered)
        analysis.rhythmicVariety = rhythmicVariety(ordered)
        analysis.selfSimilarity = selfSimilarity(ordered, beatsPerBar: beatsPerBar)

        for note in ordered {
            switch role(of: note, in: progression) {
            case .chordTone: analysis.chordTones += 1
            case .colour: analysis.colourTones += 1
            case .avoid: analysis.avoidNotes += 1
            case .offScale: analysis.offScaleNotes += 1
            }
        }
        return analysis
    }

    /// Where a single note sits against the chord sounding under it.
    static func role(of note: SequencedNote, in progression: ChordProgression) -> HarmonicRole {
        guard let placed = progression.chord(at: note.startBeat) else { return .offScale }
        let pitchClass = ((Int(note.note) % 12) + 12) % 12

        if placed.symbol.tonePitchClasses.contains(pitchClass) { return .chordTone }
        if placed.symbol.avoidPitchClasses.contains(pitchClass) { return .avoid }
        if placed.symbol.scalePitchClasses.contains(pitchClass) { return .colour }
        return .offScale
    }

    // MARK: - Variety

    /// Normalized spread of the intervals between consecutive notes. A line that
    /// only ever steps up a tone scores near 0; one that mixes steps, leaps and
    /// directions scores high.
    private static func intervalVariety(_ notes: [SequencedNote]) -> Double {
        let intervals = zip(notes, notes.dropFirst()).map { Int($1.note) - Int($0.note) }
        guard intervals.count > 1 else { return 0 }
        return normalizedEntropy(of: intervals.map { max(-12, min(12, $0)) })
    }

    /// Same, over note lengths quantized to eighths.
    private static func rhythmicVariety(_ notes: [SequencedNote]) -> Double {
        let lengths = notes.map { max(1, Int(($0.durationBeats * 2).rounded())) }
        guard lengths.count > 1 else { return 0 }
        return normalizedEntropy(of: lengths)
    }

    /// How strongly each bar repeats the one before it, by pitch-class content
    /// and onset positions. This is what catches an ostinato that the interval
    /// and rhythm measures alone would call varied.
    private static func selfSimilarity(_ notes: [SequencedNote], beatsPerBar: Double) -> Double {
        let lastBeat = notes.map { $0.startBeat }.max() ?? 0
        let barCount = max(1, Int(ceil((lastBeat + 0.001) / beatsPerBar)))
        guard barCount > 1 else { return 0 }

        func fingerprint(_ bar: Int) -> Set<String> {
            let start = Double(bar) * beatsPerBar
            return Set(notes.filter { $0.startBeat >= start && $0.startBeat < start + beatsPerBar }
                .map { note in
                    let offset = Int(((note.startBeat - start) * 2).rounded())
                    let pitchClass = ((Int(note.note) % 12) + 12) % 12
                    return "\(offset):\(pitchClass)"
                })
        }

        var scores: [Double] = []
        for bar in 1..<barCount {
            let previous = fingerprint(bar - 1)
            let current = fingerprint(bar)
            guard !previous.isEmpty || !current.isEmpty else { continue }
            let union = previous.union(current).count
            guard union > 0 else { continue }
            scores.append(Double(previous.intersection(current).count) / Double(union))
        }
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Double(scores.count)
    }

    /// Shannon entropy of a value distribution, scaled to 0...1 against the
    /// entropy of the same number of distinct values spread evenly.
    private static func normalizedEntropy<Value: Hashable>(of values: [Value]) -> Double {
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
        let entropy = counts.values.sorted().reduce(0.0) { partial, count in
            let probability = Double(count) / total
            return partial - probability * log2(probability)
        }
        // The most a sample of this size can score, so short takes aren't
        // penalised for having fewer notes than possible values.
        let ceiling = log2(min(total, Double(counts.count) * 2))
        guard ceiling > 0 else { return 0 }
        return max(0, min(1, entropy / ceiling))
    }
}
