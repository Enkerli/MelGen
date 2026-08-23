//
//  CompingBriefs.swift
//  MelGenExtension
//
//  What to tell the model about a comp, as against what to tell the voicing layer.
//
//  The first version of model comping handed the model a comping figure's own
//  description — "beat one and the and of two" — and asked it to produce that.
//  Which is using a language model, at two seconds a request, to do something a
//  four-line function already does exactly and instantly. It also explains why
//  successive takes came out the same: they were all reproductions of one
//  pattern.
//
//  A figure and a brief are different objects and the confusion was mine. A
//  **figure** is a pattern: it belongs to the deterministic path, where the point
//  is that you get precisely the rhythm you asked for. A **brief** is a
//  character: it belongs to the model, where the point is that you get something
//  you didn't specify. Handing the model the figure collapses the second into the
//  first and pays two seconds a note for the privilege.
//
//  So these describe how a comp should *feel* and deliberately never say where
//  the chords go. The rotating angle underneath does the rest of the work of
//  making two takes differ, the same way style briefs do for lines.
//

import Foundation

enum CompingBriefs {

    /// The character of a comp, by the template it belongs to.
    ///
    /// Keyed by figure name so the two stay paired, and written so that no
    /// sentence in any of them could be followed by a machine. If a brief can be
    /// executed rather than interpreted, it belongs in `CompingFigure` instead.
    static func brief(for figureName: String) -> String {
        switch figureName {
        case CompingFigure.charleston.name:
            return "Play very little. Most of each bar should be empty, and what you do play "
                 + "should arrive somewhere you don't expect it — early rather than late, and "
                 + "almost never on the first beat of a bar you've already established."
        case CompingFigure.freddie.name:
            return "Keep it moving and keep it out of the way: small chords, close together, "
                 + "none of them heavy. Think of a hand that never stops but never insists."
        case CompingFigure.pad.name:
            return "One chord per change, and let it lie there. Say the harmony and nothing "
                 + "else. Where a chord lasts a long time, that's the point rather than a gap "
                 + "to fill."
        case CompingFigure.stabs.name:
            return "Short and hard, with silence around each one. The silence is the part that "
                 + "makes it work, so err on the side of too few."
        case CompingFigure.bossa.name:
            return "Everything arrives before you expect it and holds through the moment it was "
                 + "expected. Nothing should land squarely on a bar line."
        case CompingFigure.tresilloComp.name:
            return "An uneven cell that doesn't line up with the beats and doesn't reset at the "
                 + "bar line. Repeat it enough to be recognisable and vary it enough not to tick."
        default:
            return "Comp behind a soloist: mostly space, off the beat more often than on it, "
                 + "and never the same bar twice."
        }
    }

    /// A rotating nudge, so two takes of the same template differ.
    ///
    /// The melodic side gets this from its style briefs rotating; comping had
    /// nothing equivalent, which is the other half of why every model comp came
    /// out alike. Each of these changes one thing about the *texture* rather than
    /// the pattern, so they compose with any brief above.
    static let angles: [String] = [
        "This take: three voices, no more. Spare rather than rich.",
        "This take: reach for the ninth and the thirteenth. Colour over correctness.",
        "This take: put a chord where the bar line is about to be, and hold it across.",
        "This take: let one chord ring far longer than the others, and play less around it.",
        "This take: two hits in some bars and none at all in others.",
        "This take: change which tones you use every time the chord changes, even where the "
            + "chord doesn't.",
        "This take: start each phrase off the beat and end it on one."
    ]

    static func angle(at cursor: Int) -> String {
        angles[((cursor % angles.count) + angles.count) % angles.count]
    }
}
