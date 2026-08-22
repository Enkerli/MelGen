//
//  StyleBriefs.swift
//  MelGenExtension
//
//  Rotating rhythmic and contour briefs. Asking the model for "a melody" over
//  the same changes at the same temperature tends to produce the same shape
//  every time; handing each take a different brief is what makes a run of
//  auto-generated takes actually differ from one another. The brief's name is
//  recorded with the take so the log says what produced it.
//

import Foundation

struct StyleBrief: Sendable, Hashable {
    let name: String
    let text: String
}

enum StyleBriefs {

    static let all: [StyleBrief] = [
        StyleBrief(
            name: "Long tones",
            text: "Rhythm for this take: mostly long notes — half notes and longer, four to six notes per bar at most. Let notes tie across bar lines, and use a short two-note pickup into a new chord."
        ),
        StyleBrief(
            name: "Running eighths",
            text: "Rhythm for this take: a near-continuous stream of eighth notes, broken by one long note (four eighths or more) at the end of each two-bar phrase. Keep the direction changing so it doesn't read as a scale exercise."
        ),
        StyleBrief(
            name: "Syncopated",
            text: "Rhythm for this take: syncopate hard. Start most phrases on an odd eighth, hold notes across the beat, and place the strongest note of each bar off the beat rather than on it."
        ),
        StyleBrief(
            name: "Sparse",
            text: "Rhythm for this take: sparse and patient — three to five notes per bar with real rests between them. Every note should feel chosen; end phrases on a long note and leave a bar of space somewhere."
        ),
        StyleBrief(
            name: "Call and response",
            text: "Shape for this take: a two-bar call, then a two-bar answer that echoes its rhythm but resolves differently. Rest for at least two eighths between the two."
        ),
        StyleBrief(
            name: "Repeated motif",
            text: "Shape for this take: invent a short cell of three or four notes in the first bar, then repeat its rhythm over each following chord, moving the pitches to fit the new harmony. Vary it slightly the last time."
        ),
        StyleBrief(
            name: "Rising arc",
            text: "Shape for this take: start low in the range and climb steadily to a peak around three quarters of the way through, then fall back by step. Mix note lengths so the climb isn't mechanical."
        ),
        StyleBrief(
            name: "Anticipation",
            text: "Feel for this take: arrive early. Land the new chord's tone an eighth before the chord actually changes and hold it through, so the line pulls against the harmony."
        ),
        StyleBrief(
            name: "Dotted swing",
            text: "Rhythm for this take: lean on dotted figures — a note of three eighths followed by one of one eighth, and its reverse. Keep it loping rather than even."
        ),
    ]

    /// The brief for a rotating cursor, so successive takes differ.
    static func brief(at cursor: Int) -> StyleBrief {
        let index = ((cursor % all.count) + all.count) % all.count
        return all[index]
    }
}
