//
//  PatternSeeds.swift
//  MelGenExtension
//
//  The starting library of generic lines.
//
//  Each is written in scale degrees, so it fits any progression: degrees 0, 2, 4
//  and 6 are the chord tones of a seven-note scale, so landing on those on strong
//  beats is consonant whatever the chord turns out to be. Odd degrees are the
//  passing tones between them, and `alteration` buys a chromatic approach where a
//  line wants one.
//
//  These are meant to be *usable defaults*, not the whole vocabulary — the model
//  grows the library over time (ROADMAP G8/R1). They're hand-written because the
//  point is that something good is available instantly, with no model and no wait.
//

import Foundation

extension MelodyPatterns {

    static let seeds: [MelodyPattern] = [
        longTones,
        guideTones,
        arch,
        runningEighths,
        syncopatedCell,
        callAndResponse
    ]

    /// One note per bar on chord tones, held. The most harmonically transparent
    /// thing available: it states the changes and nothing else.
    static let longTones = MelodyPattern(
        name: "Long tones",
        bars: 2,
        summary: "One held chord tone per bar",
        notes: [
            PatternNote(startEighth: 0, lengthEighths: 6, degree: 2, velocity: 96, restAfterEighths: 2),
            PatternNote(startEighth: 8, lengthEighths: 6, degree: 4, velocity: 88, restAfterEighths: 2)
        ]
    )

    /// The third and seventh — the notes that actually spell a chord's quality.
    /// Comping vocabulary, and it voice-leads itself as the harmony moves.
    static let guideTones = MelodyPattern(
        name: "Guide tones",
        bars: 2,
        summary: "Third and seventh, the notes that name the chord",
        notes: [
            PatternNote(startEighth: 0, lengthEighths: 3, degree: 2, velocity: 98),
            PatternNote(startEighth: 4, lengthEighths: 4, degree: 6, velocity: 86, restAfterEighths: 2),
            PatternNote(startEighth: 10, lengthEighths: 2, degree: 4, velocity: 82),
            PatternNote(startEighth: 12, lengthEighths: 3, degree: 2, velocity: 90, restAfterEighths: 2)
        ]
    )

    /// Up through the chord and back down, with a chromatic approach into the
    /// peak. Four bars so the shape has room to be a shape.
    static let arch = MelodyPattern(
        name: "Arch",
        bars: 4,
        summary: "Climbs the chord and falls back by step",
        notes: [
            PatternNote(startEighth: 0, lengthEighths: 2, degree: 0, velocity: 92),
            PatternNote(startEighth: 2, lengthEighths: 2, degree: 2, velocity: 84),
            PatternNote(startEighth: 4, lengthEighths: 2, degree: 4, velocity: 88),
            PatternNote(startEighth: 6, lengthEighths: 2, degree: 5, velocity: 80),
            PatternNote(startEighth: 8, lengthEighths: 1, degree: 6, alteration: -1, velocity: 78),
            PatternNote(startEighth: 9, lengthEighths: 5, degree: 7, velocity: 100, restAfterEighths: 2),
            PatternNote(startEighth: 16, lengthEighths: 2, degree: 6, velocity: 88),
            PatternNote(startEighth: 18, lengthEighths: 2, degree: 4, velocity: 84),
            PatternNote(startEighth: 20, lengthEighths: 2, degree: 2, velocity: 86),
            PatternNote(startEighth: 22, lengthEighths: 6, degree: 0, velocity: 94, restAfterEighths: 4)
        ]
    )

    /// A stream of eighths that turns around instead of running up a scale.
    /// Dense, so the density control has something to thin.
    static let runningEighths = MelodyPattern(
        name: "Running eighths",
        bars: 2,
        summary: "Continuous eighths that change direction",
        notes: [
            PatternNote(startEighth: 0, lengthEighths: 1, degree: 0, velocity: 94),
            PatternNote(startEighth: 1, lengthEighths: 1, degree: 1, velocity: 78),
            PatternNote(startEighth: 2, lengthEighths: 1, degree: 2, velocity: 88),
            PatternNote(startEighth: 3, lengthEighths: 1, degree: 3, velocity: 76),
            PatternNote(startEighth: 4, lengthEighths: 1, degree: 4, velocity: 90),
            PatternNote(startEighth: 5, lengthEighths: 1, degree: 3, velocity: 76),
            PatternNote(startEighth: 6, lengthEighths: 1, degree: 2, velocity: 84),
            PatternNote(startEighth: 7, lengthEighths: 1, degree: 1, velocity: 74, restAfterEighths: 0),
            PatternNote(startEighth: 8, lengthEighths: 1, degree: 2, velocity: 92),
            PatternNote(startEighth: 9, lengthEighths: 1, degree: 4, velocity: 78),
            PatternNote(startEighth: 10, lengthEighths: 1, degree: 6, velocity: 86),
            PatternNote(startEighth: 11, lengthEighths: 1, degree: 4, velocity: 76),
            PatternNote(startEighth: 12, lengthEighths: 4, degree: 2, velocity: 96, restAfterEighths: 2)
        ]
    )

    /// Everything lands off the beat except the resolution.
    static let syncopatedCell = MelodyPattern(
        name: "Syncopated",
        bars: 2,
        summary: "Offbeat cell resolving on the bar",
        notes: [
            PatternNote(startEighth: 1, lengthEighths: 2, degree: 4, velocity: 92),
            PatternNote(startEighth: 3, lengthEighths: 1, degree: 2, velocity: 80),
            PatternNote(startEighth: 5, lengthEighths: 3, degree: 6, velocity: 88, restAfterEighths: 2),
            PatternNote(startEighth: 11, lengthEighths: 2, degree: 4, velocity: 84),
            PatternNote(startEighth: 13, lengthEighths: 1, degree: 1, alteration: 1, velocity: 76),
            PatternNote(startEighth: 14, lengthEighths: 2, degree: 0, velocity: 98, restAfterEighths: 2)
        ]
    )

    /// A two-bar call, a breath, then an answer that mirrors its rhythm and
    /// resolves downward.
    static let callAndResponse = MelodyPattern(
        name: "Call and response",
        bars: 4,
        summary: "Two-bar call, then an answer that resolves",
        notes: [
            PatternNote(startEighth: 0, lengthEighths: 2, degree: 4, velocity: 96),
            PatternNote(startEighth: 2, lengthEighths: 1, degree: 5, velocity: 78),
            PatternNote(startEighth: 3, lengthEighths: 3, degree: 6, velocity: 90),
            PatternNote(startEighth: 8, lengthEighths: 4, degree: 4, velocity: 88, restAfterEighths: 4),
            PatternNote(startEighth: 16, lengthEighths: 2, degree: 2, velocity: 94),
            PatternNote(startEighth: 18, lengthEighths: 1, degree: 1, velocity: 76),
            PatternNote(startEighth: 19, lengthEighths: 3, degree: 0, velocity: 88),
            PatternNote(startEighth: 24, lengthEighths: 6, degree: 0, octave: -1, velocity: 92, restAfterEighths: 2)
        ]
    )

    /// The pattern for a rotating cursor, so cycling doesn't repeat immediately.
    static func seed(at cursor: Int) -> MelodyPattern {
        let index = ((cursor % seeds.count) + seeds.count) % seeds.count
        return seeds[index]
    }
}
