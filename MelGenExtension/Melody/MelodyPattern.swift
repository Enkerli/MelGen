//
//  MelodyPattern.swift
//  MelGenExtension
//
//  Lines described relative to the harmony rather than tied to it, and the
//  deterministic machinery that fits them to a progression.
//
//  Measured generation time is roughly two seconds per note, which is about four
//  times slower than real time — so the model can never be the thing that feeds
//  continuous playback. Adapting an existing line to new harmony, on the other
//  hand, is arithmetic: instant, repeatable, and available the moment a
//  progression changes. That's what this is for. The model's job becomes growing
//  the library in the background; this is what plays while it works.
//
//  A pattern note names a *scale degree* of whatever chord is sounding, so the
//  same rhythmic and contour idea comes out consonant over any harmony. Degrees
//  0, 2, 4 and 6 of a seven-note scale are its chord tones, which is why a line
//  that lands on those on strong beats fits without needing to know the chord.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

/// One note of a pattern, positioned on the eighth-note grid and pitched
/// relative to the sounding chord.
struct PatternNote: Codable, Hashable, Sendable {
    var startEighth: Int
    var lengthEighths: Int
    /// Scale degree, 0-based: 0 is the root, 2 the third, 4 the fifth, 6 the
    /// seventh of a seven-note scale. Values beyond the scale wrap upward an
    /// octave, so 7 is the root again one octave higher.
    var degree: Int
    /// Extra octaves above (or below) the degree's natural placement.
    var octave: Int = 0
    /// Semitones off the scale, for chromatic approach notes. Usually 0.
    var alteration: Int = 0
    var velocity: Int = 90
    /// Eighths of silence after this note, as in the model's schema.
    var restAfterEighths: Int = 0
}

/// A generic line: rhythm and contour, with no harmony of its own.
struct MelodyPattern: Codable, Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    /// How many bars before the pattern repeats.
    var bars: Int
    /// What it's for, shown in the interface.
    var summary: String
    var notes: [PatternNote]
}

enum MelodyPatterns {

    static let beatsPerBar: Double = 4
    /// Where the line sits when nothing else constrains it — around G4.
    static let registerCentre = 67

    /// Fits a pattern to a progression, repeating it as needed.
    ///
    /// Each repetition is re-pitched against whatever chord is sounding, so a
    /// two-bar cell over sixteen bars comes back eight times, recognisably the
    /// same figure and correct over every chord. That recurrence is the point:
    /// it's what makes a line sound composed rather than sampled.
    static func realize(_ pattern: MelodyPattern,
                        over progression: ChordProgression,
                        registerCentre centre: Int = registerCentre) -> [SequencedNote] {
        guard !pattern.notes.isEmpty, progression.totalBeats > 0, pattern.bars > 0 else { return [] }

        let patternBeats = Double(pattern.bars) * beatsPerBar
        let repetitions = max(1, Int(ceil(progression.totalBeats / patternBeats)))
        let ordered = pattern.notes.sorted { $0.startEighth < $1.startEighth }

        var placed: [SequencedNote] = []
        var previousPitch: Int?

        for repetition in 0..<repetitions {
            let offset = Double(repetition) * patternBeats
            for note in ordered {
                let startBeat = offset + Double(note.startEighth) / 2
                guard startBeat < progression.totalBeats - 0.001 else { continue }

                guard let pitch = pitch(for: note,
                                        at: startBeat,
                                        in: progression,
                                        near: previousPitch ?? centre) else { continue }
                previousPitch = pitch

                let maxLength = (progression.totalBeats - startBeat) * 2
                let lengthEighths = min(Double(max(1, note.lengthEighths)), maxLength)
                placed.append(SequencedNote(
                    note: UInt8(clamping: pitch),
                    velocity: UInt8(clamping: note.velocity),
                    startBeat: startBeat,
                    durationBeats: lengthEighths / 2
                ))
            }
        }

        return MelodyExpression.capDeadAir(
            monophonic(placed, honouringRestsFrom: ordered, repetitions: repetitions),
            totalBeats: progression.totalBeats
        )
    }

    /// Turns a degree into a MIDI note against the chord sounding at `beat`.
    static func pitch(for note: PatternNote,
                      at beat: Double,
                      in progression: ChordProgression,
                      near previous: Int) -> Int? {
        guard let placed = progression.chord(at: beat) else { return nil }
        let root = placed.symbol.rootPitchClass

        // Ascending intervals from the root, so a degree can carry octaves.
        let intervals = placed.symbol.scalePitchClasses
            .map { (($0 - root) % 12 + 12) % 12 }
            .sorted()
        guard !intervals.isEmpty else { return nil }

        let size = intervals.count
        let index = ((note.degree % size) + size) % size
        let octaveCarry = Int(floor(Double(note.degree) / Double(size)))

        // Root in octave 4 is the reference, then fold toward the previous note so
        // the line keeps its register across chords and keys.
        let base = 60 + root + intervals[index] + 12 * (octaveCarry + note.octave) + note.alteration
        let folded = MelodyGeneratorSupport.fold(pitch: base, near: previous)
        return (0...127).contains(folded) ? folded : base.clamped(to: 0...127)
    }

    /// Keeps the line strictly monophonic and honours each pattern note's rest.
    private static func monophonic(_ notes: [SequencedNote],
                                   honouringRestsFrom pattern: [PatternNote],
                                   repetitions: Int) -> [SequencedNote] {
        guard notes.count > 1 else { return notes }
        // The rests line up with the notes one-for-one, in order.
        let rests = (0..<repetitions).flatMap { _ in pattern.map(\.restAfterEighths) }

        var result = notes
        for index in result.indices.dropLast() {
            let slot = result[index + 1].startBeat - result[index].startBeat
            var duration = min(result[index].durationBeats, slot)
            let requested = Double(min(max(rests.indices.contains(index) ? rests[index] : 0, 0), 8)) / 2
            if requested > 0 {
                duration = min(duration, max(slot - requested, slot / 2))
            }
            result[index].durationBeats = max(duration, 0.05)
        }
        return result
    }
}

/// Shared with the model path so an adapted line and a generated one are folded
/// into register by exactly the same rule.
enum MelodyGeneratorSupport {
    /// Transposes by octaves until the pitch sits within an octave of its
    /// predecessor.
    static func fold(pitch: Int, near previous: Int) -> Int {
        var folded = pitch
        while folded - previous > 12, folded - 12 >= 0 { folded -= 12 }
        while previous - folded > 12, folded + 12 <= 127 { folded += 12 }
        return folded
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        // Qualified, because inside an Int extension `min` and `max` resolve to
        // Int.min and Int.max rather than the global functions.
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
