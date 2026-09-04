//
//  DeadAir.swift
//  MelGenExtension
//
//  A bar of silence in the middle of a chorus, and what to do about it.
//
//  This lived inside MelodyExpression, next to swing and metric accent, because
//  the expression pass was where it was first needed. It does not belong there:
//  expression is how a take is *performed* and this is a repair to what the
//  take *is*, applied during realization, before any of that. Two callers make
//  the point — the model generator patches what it can't absorb from the stored
//  library, and MelodyPatterns.realize runs it on every pattern it fits.
//
//  Moved out as one of PORTING.md's five MelodyPattern seams: the pattern format
//  is the carrier layer, so everything realization reaches for has to be at or
//  below it, and a sibling plug-in that never generates a note still wants this
//  the moment it fits stored material to changes.
//
//  Nothing here knows about melody, chords, or MelGen. It takes notes and beats.
//

import Foundation

/// Caps dead air.
enum DeadAir {

    /// A gap of a beat or two is a breath; eight beats is the line having stopped.
    /// The excess is absorbed by *extending the note before it*, which is what a
    /// phrase ending actually sounds like — a long note, then a breath — rather
    /// than a clipped note followed by nothing.
    ///
    /// `maxHold` is two bars, not one. The first version capped it at one bar,
    /// which meant a note that was *already* a bar long had no headroom at all
    /// and an eight-beat hole after it survived untouched — the guard did nothing
    /// in exactly the case it existed for. A note held across two bars is
    /// ordinary; a bar of silence in the middle of a chorus is not.
    ///
    /// Contract: afterwards, every gap is at most `maxRest` *unless* the note
    /// before it has reached `maxHold`, in which case there was more hole than
    /// one note could absorb. That residue means the model under-produced for
    /// that stretch, which `MelodyGenerator` patches from the stored library
    /// rather than leaving as silence.
    static func cap(_ notes: [SequencedNote],
                    totalBeats: Double,
                    maxRest: Double = 2,
                    maxHold: Double = 8) -> [SequencedNote] {
        guard !notes.isEmpty, totalBeats > 0 else { return notes }

        return notes.enumerated().map { index, note in
            var note = note
            let nextStart = index + 1 < notes.count ? notes[index + 1].startBeat : totalBeats
            let gap = nextStart - (note.startBeat + note.durationBeats)
            guard gap > maxRest else { return note }

            let wanted = gap - maxRest
            let headroom = max(0, maxHold - note.durationBeats)
            note.durationBeats += min(wanted, headroom)
            return note
        }
    }
}
