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
#endif
