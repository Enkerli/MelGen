//
//  MelodyModels.swift
//  MelGenExtension
//
//  Data types for generated melodies: the concrete sequence handed to the DSP
//  kernel, and the @Generable schema the on-device model fills in.
//

import Foundation

/// A concrete, timed note ready to hand to the DSP kernel.
struct SequencedNote: Hashable, Codable, Sendable {
    /// MIDI note number, 0–127.
    var note: UInt8
    /// MIDI velocity, 0–127.
    var velocity: UInt8
    /// Start position in quarter-note beats from the beginning of the progression.
    var startBeat: Double
    var durationBeats: Double
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A monophonic melody over a chord progression, on an eighth-note grid")
struct MelodyIdea {
    @Guide(description: "Melody notes in chronological order. Two eighths per beat, eight eighths per 4/4 bar. Phrases are separated by rests, not run together.")
    var notes: [MelodyIdeaNote]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A single melody note on the eighth-note grid, and the silence that follows it")
struct MelodyIdeaNote {
    @Guide(description: "MIDI note number", .range(48...84))
    var midiNote: Int

    @Guide(description: "Start position, in eighth notes from the beginning of the progression", .range(0...255))
    var startEighth: Int

    @Guide(description: "Duration in eighth notes", .range(1...16))
    var lengthEighths: Int

    @Guide(description: "MIDI velocity", .range(40...120))
    var velocity: Int

    /// Rests are a field rather than something inferred from the gaps between
    /// notes, because a value the schema doesn't ask for is a value the model
    /// doesn't consider — asking for phrasing in prose produced lines with no
    /// silence in them at all.
    @Guide(description: "Eighths of silence after this note before the next one. 0 to run straight on, 2 or more to end a phrase. Most notes are 0; use a real rest every bar or two.", .range(0...8))
    var restAfterEighths: Int
}

/// Comping, asked for as *choices* rather than as pitches.
///
/// The model is good at deciding and poor at arithmetic, and a voicing is almost
/// entirely arithmetic: register, spacing, which octave each voice lands in,
/// how it moves from the last one. Asking for MIDI notes would be asking it to
/// do the part it's worst at and would throw away the voicing layer that already
/// exists.
///
/// So it chooses the two things that are choices — when the chords land, and
/// which tones are in them — and `ChordVoicings` does the rest, including the
/// voice leading. The same division of labour as the melodic path, where the
/// model writes the line and post-processing folds and snaps it.
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A comping part: chords under a progression, on an eighth-note grid")
struct CompingIdea {
    @Guide(description: "The chords, in chronological order. Two eighths per beat, eight per 4/4 bar. Leave space: a comp that plays on every beat is not comping.")
    var hits: [CompingHit]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "One chord in a comping part, and which of its tones to sound")
struct CompingHit {
    @Guide(description: "Start position, in eighth notes from the beginning of the progression", .range(0...255))
    var startEighth: Int

    @Guide(description: "How long the chord sounds, in eighth notes", .range(1...16))
    var lengthEighths: Int

    /// Degrees rather than pitches: the chord under this hit decides what they
    /// mean, which is what lets one comping idea be played over other changes.
    @Guide(description: "Which tones of the sounding chord to play, as degrees: 0 root, 1 ninth, 2 third, 3 eleventh, 4 fifth, 5 thirteenth, 6 seventh. Pick three or four. Leaving out the root is normal — the bass has it.", .count(2...5))
    var degrees: [Int]

    @Guide(description: "How hard the chord is struck", .range(40...120))
    var velocity: Int
}
#endif
