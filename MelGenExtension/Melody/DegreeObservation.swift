//
//  DegreeObservation.swift
//  MelGenExtension
//
//  Counting what was actually played, as a degree histogram.
//
//  Split out of DegreeHistogram.swift, which was two things in one file: a
//  distribution over the twelve semitones above a chord's root, which is theory
//  and has no idea takes exist, and this — reading one off material that has
//  already been performed. The theory half is what `ChordVoicing` reaches for,
//  and it was reaching *up* only because of this half sharing its file. See
//  PORTING.md §3.
//

import Foundation

extension DegreeHistogram {

    /// Counts what a line actually played, against the harmony it played it over.
    ///
    /// Straight from pitches rather than through the pattern format, because the
    /// pitch and the chord are both already known and going via degrees would
    /// mean resolving an alteration back into a semitone that was right there to
    /// begin with.
    static func observed(in notes: [SequencedNote],
                         over progression: ChordProgression) -> DegreeHistogram {
        var histogram = DegreeHistogram()
        for note in notes {
            guard let placed = progression.chord(at: note.startBeat) else { continue }
            let semitone = ChordScales.pitchClass(Int(note.note) - placed.symbol.rootPitchClass)
            // Longer notes count for more: a held third says more about a style
            // than a passing one, and counting onsets alone says they're equal.
            histogram[semitone] += max(0.25, min(4, note.durationBeats))
        }
        return histogram
    }

    /// The same over a set of takes — the honest picture of what this material
    /// puts where, rather than what a dial was set to when it was made.
    static func observed(in takes: [GenerationRecord]) -> DegreeHistogram {
        var histogram = DegreeHistogram()
        for take in takes {
            guard let progression = try? ChordProgression.parse(take.progressionText) else { continue }
            let counted = observed(in: take.notes, over: progression)
            for index in 0..<size { histogram.weights[index] += counted.weights[index] }
        }
        return histogram
    }

    /// The prior, moved toward what was measured, with a floor under how much a
    /// thin corpus is allowed to say.
    ///
    /// Three takes is an anecdote. The weight given to the observation rises
    /// with how much of it there is and stops at `ceiling`, so a session with
    /// two lines in it still sounds like the dial rather than like those two
    /// lines — the same reasoning as the chain's trust threshold, arrived at for
    /// the same reason.
    func informed(by observed: DegreeHistogram,
                  observations: Int,
                  confidentAt: Int = 40,
                  ceiling: Double = 0.75) -> DegreeHistogram {
        guard !observed.isEmpty, observations > 0 else { return self }
        let trust = min(ceiling, Double(observations) / Double(max(1, confidentAt)) * ceiling)
        return blended(with: observed, trust)
    }
}

