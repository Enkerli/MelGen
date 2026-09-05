//
//  MelodyLiveMutation.swift
//  MelGenExtension
//
//  The loop changing while it plays.
//
//  Everything else here mutates a take and gives you a *new* take to judge. That
//  is the curation loop and it is the right shape for deciding what to keep. It
//  is the wrong shape for playing: on hardware sequencers the interesting control
//  is a set of probabilities that re-roll every pass, so the part drifts under
//  your hands and you steer it by adjusting how much it drifts rather than by
//  choosing between candidates.
//
//  Ruismaker's Troublemaker is the clearest version of this — probabilities for
//  note order, accents, slides and skipped steps — and the shape is worth taking
//  literally rather than reinvented, because it has been played enough to have
//  settled. Four axes, each a probability, each re-rolled per pass, each doing
//  one thing you can hear in isolation.
//
//  Two decisions that are MelGen's rather than Troublemaker's. Mutation happens
//  at *render* time, downstream of the take and upstream of the kernel, so what
//  it changes is never written back — the take you kept stays the take you kept
//  and the drift is a performance of it. And it is seeded by (take, pass), so a
//  loop that sounded good can be got back by knowing which pass it was, rather
//  than being gone the moment it went round again.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation
import Carrier
import Core

/// How much the loop is allowed to drift as it plays.
struct LiveMutation: Codable, Hashable, Sendable {
    /// Chance that a note swaps its pitch with another note in the same bar.
    /// Rhythm untouched — the figure stays, the tune moves.
    var noteOrder: Double = 0
    /// Chance that a note's accent is added or taken away.
    var accents: Double = 0
    /// Chance that a note runs into the next one instead of stopping — a slide
    /// in the 303 sense, which here is a gate that doesn't close.
    var slides: Double = 0
    /// Chance that a note is simply not played this time round.
    var skipSteps: Double = 0
    /// Chance that a note jumps an octave. Not one of Troublemaker's four; added
    /// because a melodic part has a register axis a bassline mostly doesn't, and
    /// it's the one that most changes a line's character per pass.
    var octaves: Double = 0

    var isActive: Bool {
        noteOrder > 0 || accents > 0 || slides > 0 || skipSteps > 0 || octaves > 0
    }

    /// One line for a collapsed header.
    var summary: String {
        guard isActive else { return "off" }
        var parts: [String] = []
        if noteOrder > 0 { parts.append("order \(percent(noteOrder))") }
        if accents > 0 { parts.append("accents \(percent(accents))") }
        if slides > 0 { parts.append("slides \(percent(slides))") }
        if skipSteps > 0 { parts.append("skip \(percent(skipSteps))") }
        if octaves > 0 { parts.append("octaves \(percent(octaves))") }
        return parts.joined(separator: " · ")
    }

    private func percent(_ value: Double) -> String { "\(Int(value * 100))%" }

    init(noteOrder: Double = 0, accents: Double = 0, slides: Double = 0,
         skipSteps: Double = 0, octaves: Double = 0) {
        self.noteOrder = noteOrder
        self.accents = accents
        self.slides = slides
        self.skipSteps = skipSteps
        self.octaves = octaves
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noteOrder = try container.decodeIfPresent(Double.self, forKey: .noteOrder) ?? 0
        accents = try container.decodeIfPresent(Double.self, forKey: .accents) ?? 0
        slides = try container.decodeIfPresent(Double.self, forKey: .slides) ?? 0
        skipSteps = try container.decodeIfPresent(Double.self, forKey: .skipSteps) ?? 0
        octaves = try container.decodeIfPresent(Double.self, forKey: .octaves) ?? 0
    }
}

enum MelodyLiveMutations {

    /// Applies one pass's worth of drift.
    ///
    /// - Parameters:
    ///   - polyphonic: a comping take's simultaneous notes are one chord, so they
    ///     are skipped, accented and slid *together*. Rolling the dice per note
    ///     inside a voicing produces a chord with one note missing, which is a
    ///     different chord rather than a variation.
    ///   - seed: (take, pass). The same pass of the same take always drifts the
    ///     same way, so a loop that sounded good is findable again.
    static func apply(to notes: [SequencedNote],
                      settings: LiveMutation,
                      lengthBeats: Double,
                      polyphonic: Bool,
                      seed: UInt64) -> [SequencedNote] {
        guard settings.isActive, !notes.isEmpty else { return notes }
        var rng = SplitMix64(seed: seed)
        var result = notes.sorted { ($0.startBeat, $0.note) < ($1.startBeat, $1.note) }

        // Groups: one per note when melodic, one per simultaneity when not.
        let groups = polyphonic ? simultaneities(in: result) : result.indices.map { [$0] }

        // Order. Pitches move between onsets; the rhythm stays exactly where it
        // was, which is what makes this a variation of the figure rather than a
        // different figure.
        if settings.noteOrder > 0, groups.count > 1 {
            for index in groups.indices.dropLast() {
                guard rng.nextUnit() < settings.noteOrder else { continue }
                let partner = index + 1 + Int(rng.next() % UInt64(groups.count - index - 1))
                swapPitches(&result, groups[index], groups[partner])
            }
        }

        for group in groups {
            let skip = rng.nextUnit() < settings.skipSteps
            let accent = rng.nextUnit() < settings.accents
            let slide = rng.nextUnit() < settings.slides
            let octave = rng.nextUnit() < settings.octaves
            let direction = rng.nextUnit() < 0.5 ? -12 : 12

            for index in group {
                if skip {
                    // Marked rather than removed, so the indices the other rolls
                    // work from stay valid; cleared at the end.
                    result[index].velocity = 0
                    continue
                }
                if accent {
                    result[index].velocity = UInt8(clamping: Int(result[index].velocity) +
                                                   (result[index].velocity > 90 ? -22 : 24))
                }
                if octave {
                    let moved = Int(result[index].note) + direction
                    if (36...96).contains(moved) { result[index].note = UInt8(moved) }
                }
                if slide {
                    // Runs into whatever comes next rather than stopping. The
                    // gate doesn't close, which is what a slide is.
                    let nextStart = result
                        .filter { $0.startBeat > result[index].startBeat + 0.001 }
                        .map(\.startBeat).min() ?? lengthBeats
                    result[index].durationBeats = max(result[index].durationBeats,
                                                      nextStart - result[index].startBeat)
                }
            }
        }

        return result.filter { $0.velocity > 0 }
    }

    /// Indices grouped by start beat — a chord is one thing to decide about.
    private static func simultaneities(in notes: [SequencedNote]) -> [[Int]] {
        var groups: [[Int]] = []
        for index in notes.indices {
            if let last = groups.last, let first = last.first,
               abs(notes[first].startBeat - notes[index].startBeat) < 0.001 {
                groups[groups.count - 1].append(index)
            } else {
                groups.append([index])
            }
        }
        return groups
    }

    /// Swaps the pitches of two groups, keeping each group's own shape.
    ///
    /// Two chords of different sizes swap what they can and leave the rest, which
    /// is the only thing that doesn't either drop a voice or invent one.
    private static func swapPitches(_ notes: inout [SequencedNote], _ a: [Int], _ b: [Int]) {
        for (left, right) in zip(a, b) {
            let pitch = notes[left].note
            notes[left].note = notes[right].note
            notes[right].note = pitch
        }
    }
}
