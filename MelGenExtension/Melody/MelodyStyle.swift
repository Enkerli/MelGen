//
//  MelodyStyle.swift
//  MelGenExtension
//
//  What the takes you kept have in common, described rather than quoted.
//
//  There are two ways to make the model write more like the material you like.
//  Quote it — paste takes into the instructions as few-shot examples — or
//  describe it: measure the material and tell the model what the measurements
//  say. Both are "learning" only in the loose, few-shot sense; neither trains
//  anything. But they fail in different directions, and the difference is
//  budget.
//
//  The context window is 4,096 tokens for instructions, prompt and response
//  together (see ROADMAP F10), and the response is already the expensive part —
//  guided generation emits an object per note. A single 57-note take quoted in
//  full costs several hundred tokens of that, and three of them crowd out the
//  line you asked for. A description of *sixty* takes costs about a hundred
//  tokens and doesn't grow. So: quote a little, describe a lot.
//
//  Describing also generalizes in a way quoting doesn't. An example says "over
//  these changes, these pitches". A distribution says "you land on chord tones
//  three times in five, you move by step two times in three, a third of your
//  onsets are off the beat" — which is true of your playing rather than of one
//  progression, and survives being pointed at changes you've never played.
//
//  This is the transparent, arithmetic end of the GloriArp "staged learning"
//  idea: empirical distributions over a small curated corpus, exportable and
//  inspectable, before anything opaque is considered. See TRAINING.md for where
//  it could go from here.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

/// Distributions measured over a set of takes.
///
/// Every field is a share of something countable, so two styles can be compared,
/// a style can be exported, and nothing here requires trusting a black box.
struct LearnedStyle: Codable, Hashable, Sendable {
    var takeCount: Int = 0
    var noteCount: Int = 0

    /// Notes per bar, averaged across the takes.
    var notesPerBar: Double = 0
    /// Share of eighth-note slots with nothing sounding.
    var restShare: Double = 0

    /// Where the line sits, in MIDI note numbers.
    var registerLow: Int = 60
    var registerHigh: Int = 72
    var registerCentre: Int = 66

    /// Share of moves that are a step (1–2 semitones), a skip (3–4), or a leap (5+).
    var stepShare: Double = 0
    var skipShare: Double = 0
    var leapShare: Double = 0
    /// How often the line changes direction, per move.
    var directionChangeRate: Double = 0
    /// Share of moves that go up rather than down or stay.
    var risingShare: Double = 0

    /// Note lengths in eighths, as shares. Keyed by length.
    var durationShares: [Int: Double] = [:]
    /// Onsets by position within the bar, 0–7 eighths.
    var onsetShares: [Int: Double] = [:]
    /// Share of onsets that fall on an odd eighth.
    var offbeatShare: Double = 0

    /// How the material sits on the harmony, as shares of all notes.
    var chordToneShare: Double = 0
    var colourShare: Double = 0
    var avoidShare: Double = 0
    var offScaleShare: Double = 0

    /// The tags on the material this was learned from, most used first — the
    /// folksonomy carried into the prompt, since what you called it is evidence
    /// about what you meant.
    var tags: [String] = []

    var isEmpty: Bool { takeCount == 0 || noteCount < 8 }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        takeCount = try container.decodeIfPresent(Int.self, forKey: .takeCount) ?? 0
        noteCount = try container.decodeIfPresent(Int.self, forKey: .noteCount) ?? 0
        notesPerBar = try container.decodeIfPresent(Double.self, forKey: .notesPerBar) ?? 0
        restShare = try container.decodeIfPresent(Double.self, forKey: .restShare) ?? 0
        registerLow = try container.decodeIfPresent(Int.self, forKey: .registerLow) ?? 60
        registerHigh = try container.decodeIfPresent(Int.self, forKey: .registerHigh) ?? 72
        registerCentre = try container.decodeIfPresent(Int.self, forKey: .registerCentre) ?? 66
        stepShare = try container.decodeIfPresent(Double.self, forKey: .stepShare) ?? 0
        skipShare = try container.decodeIfPresent(Double.self, forKey: .skipShare) ?? 0
        leapShare = try container.decodeIfPresent(Double.self, forKey: .leapShare) ?? 0
        directionChangeRate = try container.decodeIfPresent(Double.self, forKey: .directionChangeRate) ?? 0
        risingShare = try container.decodeIfPresent(Double.self, forKey: .risingShare) ?? 0
        durationShares = try container.decodeIfPresent([Int: Double].self, forKey: .durationShares) ?? [:]
        onsetShares = try container.decodeIfPresent([Int: Double].self, forKey: .onsetShares) ?? [:]
        offbeatShare = try container.decodeIfPresent(Double.self, forKey: .offbeatShare) ?? 0
        chordToneShare = try container.decodeIfPresent(Double.self, forKey: .chordToneShare) ?? 0
        colourShare = try container.decodeIfPresent(Double.self, forKey: .colourShare) ?? 0
        avoidShare = try container.decodeIfPresent(Double.self, forKey: .avoidShare) ?? 0
        offScaleShare = try container.decodeIfPresent(Double.self, forKey: .offScaleShare) ?? 0
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

extension LearnedStyle {

    /// The two or three note lengths that account for most of the material.
    var commonDurations: [Int] {
        durationShares.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(3)
            .filter { $0.value >= 0.1 }
            .map(\.key)
    }

    /// A line for the interface: what this style is, in one glance.
    var summary: String {
        guard !isEmpty else { return "Not enough kept material to describe a style yet." }
        return "\(takeCount) takes · \(notesPerBar.formatted(.number.precision(.fractionLength(1))))/bar · "
             + "\(percent(stepShare)) stepwise · \(percent(offbeatShare)) offbeat · "
             + "\(percent(chordToneShare)) chord tones"
    }

    /// The same measurements as instruction text.
    ///
    /// Written as description rather than as numbers wherever a number wouldn't
    /// mean anything to a language model — "mostly stepwise" lands where "0.68"
    /// doesn't — but the shares are kept where they're the actual instruction,
    /// because a model given "about a third" writes a third and a model given
    /// "some" writes anything.
    var promptText: String {
        guard !isEmpty else { return "" }

        var lines = ["Your own voice, measured from \(takeCount) take\(takeCount == 1 ? "" : "s") "
                     + "this musician kept. Write like this material, not like a generic melody:"]

        lines.append("- Density: about \(notesPerBar.formatted(.number.precision(.fractionLength(1)))) "
                     + "notes per bar, with roughly \(percent(restShare)) of the bar silent.")

        let motion: String
        if stepShare > 0.6 {
            motion = "overwhelmingly stepwise"
        } else if stepShare > 0.45 {
            motion = "mostly stepwise"
        } else if leapShare > 0.35 {
            motion = "leap-driven"
        } else {
            motion = "a mix of steps and skips"
        }
        lines.append("- Motion: \(motion) — \(percent(stepShare)) steps of a tone or less, "
                     + "\(percent(skipShare)) skips of a third, \(percent(leapShare)) leaps of a fourth "
                     + "or wider. The direction changes on \(percent(directionChangeRate)) of moves.")

        lines.append("- Register: centred around \(ChordProgression.noteName(forMIDINote: registerCentre)), "
                     + "between \(ChordProgression.noteName(forMIDINote: registerLow)) and "
                     + "\(ChordProgression.noteName(forMIDINote: registerHigh)).")

        if !commonDurations.isEmpty {
            let lengths = commonDurations
                .map { "\($0) eighth\($0 == 1 ? "" : "s")" }
                .joined(separator: ", ")
            lines.append("- Rhythm: note lengths are mostly \(lengths). "
                         + "\(percent(offbeatShare)) of onsets fall off the beat.")
        }

        lines.append("- Harmony: \(percent(chordToneShare)) chord tones, \(percent(colourShare)) colour "
                     + "notes, \(percent(offScaleShare)) chromatic. Match that balance — a line that is "
                     + "all chord tones is an exercise.")

        if !tags.isEmpty {
            lines.append("- The musician files this material under: \(tags.prefix(6).joined(separator: ", ")).")
        }

        return lines.joined(separator: "\n")
    }

    private func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}

// MARK: - Learning

enum StyleLearner {

    static let beatsPerBar: Double = 4

    /// Measures a set of takes into a style.
    ///
    /// Takes whose progression won't parse are skipped rather than guessed at:
    /// the harmonic shares are the most useful part and a wrong progression
    /// poisons them.
    static func learn(from takes: [GenerationRecord]) -> LearnedStyle {
        var style = LearnedStyle()
        guard !takes.isEmpty else { return style }

        var totalNotes = 0
        var totalBars = 0.0
        var soundingEighths = 0.0
        var totalEighths = 0.0

        var moves = 0
        var steps = 0, skips = 0, leaps = 0, rising = 0, directionChanges = 0
        var durationCounts: [Int: Int] = [:]
        var onsetCounts: [Int: Int] = [:]
        var offbeats = 0
        var roles: [HarmonicRole: Int] = [:]
        var pitches: [Int] = []
        var tagCounts: [String: Int] = [:]

        for take in takes {
            let notes = take.notes.sorted { $0.startBeat < $1.startBeat }
            guard notes.count > 1, take.lengthBeats > 0 else { continue }

            style.takeCount += 1
            totalNotes += notes.count
            totalBars += take.lengthBeats / beatsPerBar
            totalEighths += take.lengthBeats * 2
            soundingEighths += notes.reduce(0) { $0 + $1.durationBeats * 2 }

            for tag in take.tags { tagCounts[tag, default: 0] += 1 }

            var previousDirection = 0
            for (index, note) in notes.enumerated() {
                pitches.append(Int(note.note))

                let eighth = Int((note.startBeat * 2).rounded())
                onsetCounts[((eighth % 8) + 8) % 8, default: 0] += 1
                if !eighth.isMultiple(of: 2) { offbeats += 1 }

                durationCounts[max(1, Int((note.durationBeats * 2).rounded())), default: 0] += 1

                if index + 1 < notes.count {
                    let interval = Int(notes[index + 1].note) - Int(note.note)
                    moves += 1
                    switch abs(interval) {
                    case 0...2: steps += 1
                    case 3...4: skips += 1
                    default: leaps += 1
                    }
                    if interval > 0 { rising += 1 }
                    let direction = interval == 0 ? previousDirection : (interval > 0 ? 1 : -1)
                    if direction != 0, previousDirection != 0, direction != previousDirection {
                        directionChanges += 1
                    }
                    previousDirection = direction
                }
            }

            // Harmonic shares need the changes the take was played over. A take
            // whose progression won't parse contributes its rhythm and contour
            // and abstains from the harmony, rather than being dropped whole.
            if let progression = try? ChordProgression.parse(take.progressionText) {
                for note in notes {
                    roles[MelodyAnalyser.role(of: note, in: progression), default: 0] += 1
                }
            }
        }

        guard style.takeCount > 0, totalNotes > 0 else { return LearnedStyle() }

        style.noteCount = totalNotes
        style.notesPerBar = totalBars > 0 ? Double(totalNotes) / totalBars : 0
        style.restShare = totalEighths > 0
            ? max(0, min(1, 1 - soundingEighths / totalEighths))
            : 0

        let sorted = pitches.sorted()
        style.registerLow = sorted[sorted.count / 10]
        style.registerHigh = sorted[max(0, sorted.count - 1 - sorted.count / 10)]
        style.registerCentre = sorted[sorted.count / 2]

        if moves > 0 {
            style.stepShare = Double(steps) / Double(moves)
            style.skipShare = Double(skips) / Double(moves)
            style.leapShare = Double(leaps) / Double(moves)
            style.risingShare = Double(rising) / Double(moves)
            style.directionChangeRate = Double(directionChanges) / Double(moves)
        }

        style.durationShares = shares(durationCounts)
        style.onsetShares = shares(onsetCounts)
        style.offbeatShare = Double(offbeats) / Double(totalNotes)

        let roleTotal = roles.values.reduce(0, +)
        if roleTotal > 0 {
            style.chordToneShare = Double(roles[.chordTone] ?? 0) / Double(roleTotal)
            style.colourShare = Double(roles[.colour] ?? 0) / Double(roleTotal)
            style.avoidShare = Double(roles[.avoid] ?? 0) / Double(roleTotal)
            style.offScaleShare = Double(roles[.offScale] ?? 0) / Double(roleTotal)
        }

        style.tags = tagCounts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        return style
    }

    private static func shares(_ counts: [Int: Int]) -> [Int: Double] {
        let total = Double(counts.values.reduce(0, +))
        guard total > 0 else { return [:] }
        return counts.mapValues { Double($0) / total }
    }
}

// MARK: - Quoting

extension PatternLibrary {

    /// A few short excerpts of curated material, for the instructions.
    ///
    /// Capped and excerpted on purpose. The window is 4,096 tokens for
    /// everything, and a full 57-note take quoted verbatim eats a chunk of it
    /// that the response needs — so this quotes the *opening* of a small number
    /// of takes and lets `LearnedStyle` carry the rest, which it does at a
    /// hundredth the cost.
    static func examples(from takes: [GenerationRecord],
                         limit: Int = 3,
                         bars: Int = 2) -> [PatternExample] {
        let cutoff = Double(bars) * 4
        return takes.prefix(limit).compactMap { take in
            let excerpt = take.notes
                .filter { $0.startBeat < cutoff }
                .sorted { $0.startBeat < $1.startBeat }
            guard excerpt.count >= 3 else { return nil }
            return PatternExample(progression: take.progressionText,
                                  pattern: pattern(from: excerpt))
        }
    }
}
