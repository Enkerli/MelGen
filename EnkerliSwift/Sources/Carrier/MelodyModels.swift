//
//  MelodyModels.swift
//  MelGenExtension
//
//  Data types for generated melodies: the concrete sequence handed to the DSP
//  kernel, and the @Generable schema the on-device model fills in.
//

import Foundation

/// A concrete, timed note ready to hand to the DSP kernel.
public struct SequencedNote: Hashable, Codable, Sendable {
    /// MIDI note number, 0–127.
    public var note: UInt8
    /// MIDI velocity, 0–127.
    public var velocity: UInt8
    /// Start position in quarter-note beats from the beginning of the progression.
    public var startBeat: Double
    public var durationBeats: Double

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(note: UInt8,
                velocity: UInt8,
                startBeat: Double,
                durationBeats: Double) {
        self.note = note
        self.velocity = velocity
        self.startBeat = startBeat
        self.durationBeats = durationBeats
    }
}

#if canImport(FoundationModels)
import FoundationModels
import Theory

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A monophonic melody over a chord progression, on an eighth-note grid")
public struct MelodyIdea {
    @Guide(description: "Melody notes in chronological order. Two eighths per beat, eight eighths per 4/4 bar. Phrases are separated by rests, not run together.")
    public var notes: [MelodyIdeaNote]

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(notes: [MelodyIdeaNote]) {
        self.notes = notes
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A single melody note on the eighth-note grid, and the silence that follows it")
public struct MelodyIdeaNote {
    @Guide(description: "MIDI note number", .range(48...84))
    public var midiNote: Int

    @Guide(description: "Start position, in eighth notes from the beginning of the progression", .range(0...255))
    public var startEighth: Int

    @Guide(description: "Duration in eighth notes", .range(1...16))
    public var lengthEighths: Int

    @Guide(description: "MIDI velocity", .range(40...120))
    public var velocity: Int

    /// Rests are a field rather than something inferred from the gaps between
    /// notes, because a value the schema doesn't ask for is a value the model
    /// doesn't consider — asking for phrasing in prose produced lines with no
    /// silence in them at all.
    @Guide(description: "Eighths of silence after this note before the next one. 0 to run straight on, 2 or more to end a phrase. Most notes are 0; use a real rest every bar or two.", .range(0...8))
    public var restAfterEighths: Int

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(midiNote: Int,
                startEighth: Int,
                lengthEighths: Int,
                velocity: Int,
                restAfterEighths: Int) {
        self.midiNote = midiNote
        self.startEighth = startEighth
        self.lengthEighths = lengthEighths
        self.velocity = velocity
        self.restAfterEighths = restAfterEighths
    }
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
public struct CompingIdea {
    @Guide(description: "The chords, in chronological order. Two eighths per beat, eight per 4/4 bar. Leave space: a comp that plays on every beat is not comping.")
    public var hits: [CompingHit]

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(hits: [CompingHit]) {
        self.hits = hits
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "One chord in a comping part, and which of its tones to sound")
public struct CompingHit {
    @Guide(description: "Start position, in eighth notes from the beginning of the progression", .range(0...255))
    public var startEighth: Int

    @Guide(description: "How long the chord sounds, in eighth notes", .range(1...16))
    public var lengthEighths: Int

    /// Degrees rather than pitches: the chord under this hit decides what they
    /// mean, which is what lets one comping idea be played over other changes.
    @Guide(description: "Which tones of the sounding chord to play, as degrees: 0 root, 1 ninth, 2 third, 3 eleventh, 4 fifth, 5 thirteenth, 6 seventh. Pick three or four. Leaving out the root is normal — the bass has it.", .count(2...5))
    public var degrees: [Int]

    @Guide(description: "How hard the chord is struck", .range(40...120))
    public var velocity: Int

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(startEighth: Int,
                lengthEighths: Int,
                degrees: [Int],
                velocity: Int) {
        self.startEighth = startEighth
        self.lengthEighths = lengthEighths
        self.degrees = degrees
        self.velocity = velocity
    }
}

/// A template, asked for as character rather than as figures.
///
/// The one thing worth spending a model request on. A take costs about 1.8
/// seconds a note every time; a template costs one request once and the
/// deterministic path composes from it instantly for as long as it's kept. And
/// it's the request the model is actually suited to: naming a character and
/// describing it, rather than doing arithmetic slowly.
///
/// Numbers rather than a list of gesture figures, deliberately. Asked for figures
/// the model would have to know a vocabulary it has never seen and would invent
/// names; asked for "about five notes a bar, mostly short, heavily syncopated"
/// it is on ground it understands, and matching that to figures is arithmetic
/// this side does exactly.
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A named style for a melodic line: what it's called, how it should be played, and what it measures like")
public struct AuthoredTemplateIdea {
    @Guide(description: "A short name, two or three words. Evocative rather than technical — the name of a way of playing, not a description of a rhythm.")
    public var name: String

    @Guide(description: "One or two sentences telling a composer how to play this way. Say what to do, not what it measures like. No numbers.")
    public var brief: String

    @Guide(description: "Roughly how many notes per bar this way of playing uses", .range(1...8))
    public var notesPerBar: Int

    @Guide(description: "How much silence it leaves, 0 for wall-to-wall and 100 for mostly space", .range(0...100))
    public var airiness: Int

    @Guide(description: "How much of it falls off the beat, 0 for square and 100 for nothing on a beat", .range(0...100))
    public var offbeatness: Int

    @Guide(description: "Typical note length in eighth notes, 1 for short and 6 for long", .range(1...6))
    public var noteLength: Int

    @Guide(description: "How its phrases are laid out. One of: callAnswer, aaba, pairs, through.")
    public var shape: String

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(name: String,
                brief: String,
                notesPerBar: Int,
                airiness: Int,
                offbeatness: Int,
                noteLength: Int,
                shape: String) {
        self.name = name
        self.brief = brief
        self.notesPerBar = notesPerBar
        self.airiness = airiness
        self.offbeatness = offbeatness
        self.noteLength = noteLength
        self.shape = shape
    }
}
#endif

// MARK: - What came off the wire

/// One note-on or note-off, as the render thread saw it.
///
/// Here rather than in `MelodyCapture.swift`, where it started, because the
/// capture ring that fills it is in the C++ kernel — so the AU shell has to name
/// this type, and the shell may not reach up into the app. What an event *means*
/// is the app's business; what one *is* is the same for any plug-in with a
/// lock-free ring under it. PORTING.md's `MelGenExtensionAudioUnit →
/// CapturedMIDIEvent` seam.
public struct CapturedMIDIEvent: Hashable, Sendable {
    /// Timeline position in beats.
    public var beat: Double
    public var note: UInt8
    public var velocity: UInt8
    public var isOn: Bool

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(beat: Double,
                note: UInt8,
                velocity: UInt8,
                isOn: Bool) {
        self.beat = beat
        self.note = note
        self.velocity = velocity
        self.isOn = isOn
    }
}

extension SequencedNote {
    /// The three fields chord detection needs, and nothing else.
    ///
    /// The conversion lives here rather than in `ChordDetection` because the
    /// direction matters: theory may not name a carrier type, and carrier may
    /// name a theory one. PORTING.md's last listed seam, cut this way round.
    public var sounding: SoundingNote {
        SoundingNote(startBeat: startBeat, durationBeats: durationBeats, pitch: Int(note))
    }
}
