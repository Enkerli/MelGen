//
//  DegreePlacement.swift
//  MelGenExtension
//
//  Back into the pattern format.
//
//  Split out of DegreeHistogram.swift for the reason above it in
//  DegreeObservation.swift: this names `PatternNote`, so it belongs beside the
//  interchange format rather than inside the theory that decides a semitone.
//

import Foundation

/// Turning a drawn semitone into a note the rest of the codebase understands.
///
/// The pattern format is `(degree, alteration)` — which step of the sounding
/// scale, and how far off it. That is the right format for material that has to
/// survive being replayed over other changes, and the wrong one for deciding
/// what to play, because it can't express "a semitone above the third" without
/// first knowing which step to call it. So the decision happens in semitones and
/// lands here.
enum DegreePlacement {

    /// The nearest scale step to a semitone, and the alteration that gets there.
    ///
    /// Nearest by signed distance rather than by rounding down, because a note
    /// one semitone *below* a step is an approach to that step and calling it a
    /// sharpened version of the step underneath loses what it was for — the same
    /// argument `PatternNote.isLeadable` is built on.
    static func place(semitone: Int, in context: DegreeContext) -> (degree: Int, alteration: Int) {
        let scale = context.scaleIntervals
        guard !scale.isEmpty else { return (0, ChordScales.pitchClass(semitone)) }
        let target = ChordScales.pitchClass(semitone)

        // Candidates include the octave above the first step, so a semitone just
        // under the root reads as the root flattened rather than as the seventh
        // sharpened halfway across the scale.
        var candidates: [(degree: Int, alteration: Int)] = []
        for (index, interval) in scale.enumerated() {
            candidates.append((index, target - interval))
        }
        candidates.append((scale.count, target - (scale[0] + 12)))

        return candidates.min {
            (abs($0.alteration), $0.degree) < (abs($1.alteration), $1.degree)
        } ?? (0, 0)
    }

    /// A pattern note for a drawn semitone, with the role it actually has.
    ///
    /// Carrying the role matters downstream: a note recorded as `colour` or
    /// `offScale` is exempt from the seam leading, which is what stops a
    /// deliberate outside note being quietly snapped onto the chord at the next
    /// bar line.
    static func note(semitone: Int,
                     in context: DegreeContext,
                     startEighth: Int,
                     lengthEighths: Int,
                     velocity: Int = 88,
                     octave: Int = 0,
                     restAfterEighths: Int = 0) -> PatternNote {
        let placed = place(semitone: semitone, in: context)
        return PatternNote(startEighth: startEighth,
                           lengthEighths: max(1, lengthEighths),
                           degree: placed.degree,
                           octave: octave,
                           alteration: placed.alteration,
                           velocity: min(127, max(1, velocity)),
                           restAfterEighths: max(0, restAfterEighths),
                           role: context.role(ofSemitone: semitone))
    }
}

