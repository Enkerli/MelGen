//
//  ChordScale.swift
//  MelGenExtension
//
//  Chord-scale relationships and avoid notes, ported from
//  music-suite/packages/theory/src/chordScale.ts.
//
//  Given a chord's root and the pitch classes it spans, pick the scale a
//  soloist draws on and split that scale into chord tones (stable), tensions
//  (colour) and avoid notes (a minor second above a chord tone, so a ♭9 clash).
//  The scale comes from a structural classifier over the chord's intervals
//  rather than a per-quality table, so it agrees with every one of the
//  dictionary's spelled qualities.
//

import Foundation

enum Scale: String, CaseIterable, Codable, Sendable {
    case ionian, dorian, phrygian, lydian, mixolydian, aeolian, locrian
    case melodicMinor, lydianDominant, mixolydianFlat13, altered, wholeTone
    case lydianAugmented, diminishedWholeHalf, diminishedHalfWhole

    /// Semitones from the scale root.
    var intervals: [Int] {
        switch self {
        case .ionian:              return [0, 2, 4, 5, 7, 9, 11]
        case .dorian:              return [0, 2, 3, 5, 7, 9, 10]
        case .phrygian:            return [0, 1, 3, 5, 7, 8, 10]
        case .lydian:              return [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian:          return [0, 2, 4, 5, 7, 9, 10]
        case .aeolian:             return [0, 2, 3, 5, 7, 8, 10]
        case .locrian:             return [0, 1, 3, 5, 6, 8, 10]
        case .melodicMinor:        return [0, 2, 3, 5, 7, 9, 11]
        case .lydianDominant:      return [0, 2, 4, 6, 7, 9, 10]
        case .mixolydianFlat13:    return [0, 2, 4, 5, 7, 8, 10]
        case .altered:             return [0, 1, 3, 4, 6, 8, 10]
        case .wholeTone:           return [0, 2, 4, 6, 8, 10]
        case .lydianAugmented:     return [0, 2, 4, 6, 8, 9, 11]
        case .diminishedWholeHalf: return [0, 2, 3, 5, 6, 8, 9, 11]
        case .diminishedHalfWhole: return [0, 1, 3, 4, 6, 7, 9, 10]
        }
    }

    var displayName: String {
        switch self {
        case .ionian:              return "Ionian"
        case .dorian:              return "Dorian"
        case .phrygian:            return "Phrygian"
        case .lydian:              return "Lydian"
        case .mixolydian:          return "Mixolydian"
        case .aeolian:             return "Aeolian"
        case .locrian:             return "Locrian"
        case .melodicMinor:        return "Melodic minor"
        case .lydianDominant:      return "Lydian dominant"
        case .mixolydianFlat13:    return "Mixolydian ♭13"
        case .altered:             return "Altered"
        case .wholeTone:           return "Whole tone"
        case .lydianAugmented:     return "Lydian augmented"
        case .diminishedWholeHalf: return "Diminished (whole-half)"
        case .diminishedHalfWhole: return "Diminished (half-whole)"
        }
    }
}

struct ChordScale: Sendable {
    let scale: Scale
    /// Absolute pitch classes of the scale.
    let scalePitchClasses: [Int]
    /// Absolute pitch classes that are chord tones (stable landing notes).
    let chordTones: [Int]
    /// Scale tones that colour without clashing — good extensions.
    let tensions: [Int]
    /// Scale tones a minor second above a chord tone: unstable as a held note.
    let avoid: [Int]

    var scaleName: String { scale.displayName }
}

enum ChordScales {

    /// The chord-scale for a chord, or nil for an empty pitch-class set.
    static func chordScale(rootPitchClass: Int, pitchClasses: [Int]) -> ChordScale? {
        guard !pitchClasses.isEmpty else { return nil }
        let root = pitchClass(rootPitchClass)
        let intervals = intervalsFromRoot(pitchClasses, root: root)
        let (primary, alternates) = pickScale(intervals: intervals)
        let chordSet = Set(pitchClasses.map(pitchClass))

        struct Candidate {
            let scale: Scale
            let scalePitchClasses: [Int]
            let avoid: [Int]
            let spansEveryChordTone: Bool
        }

        func score(_ scale: Scale) -> Candidate {
            let scalePcs = scale.intervals.map { (root + $0) % 12 }
            let scaleSet = Set(scalePcs)
            let avoid = scalePcs.filter { !chordSet.contains($0) && chordSet.contains(($0 + 11) % 12) }
            return Candidate(
                scale: scale,
                scalePitchClasses: scalePcs,
                avoid: avoid,
                spansEveryChordTone: chordSet.allSatisfy { scaleSet.contains($0) }
            )
        }

        let candidates = ([primary] + alternates).map(score)

        // Prefer the candidate with the fewest avoid notes that still spans every
        // chord tone — Lydian over Ionian for maj7, since its ♯11 replaces
        // Ionian's avoid 4th. Ties keep the quality-match priority, and a scale
        // missing a chord tone is never promoted over one that fits.
        let eligible = candidates.filter(\.spansEveryChordTone)
        let pool = eligible.isEmpty ? candidates : eligible
        var chosen = pool[0]
        for candidate in pool where candidate.avoid.count < chosen.avoid.count {
            chosen = candidate
        }

        let avoidSet = Set(chosen.avoid)
        return ChordScale(
            scale: chosen.scale,
            scalePitchClasses: chosen.scalePitchClasses,
            chordTones: chosen.scalePitchClasses.filter { chordSet.contains($0) },
            tensions: chosen.scalePitchClasses.filter { !chordSet.contains($0) && !avoidSet.contains($0) },
            avoid: chosen.avoid
        )
    }

    // MARK: - Classifier

    /// Priority runs from the most specific quality (diminished, altered
    /// dominant) to the most generic (plain major / minor).
    private static func pickScale(intervals: [Int]) -> (Scale, [Scale]) {
        let present = Set(intervals)
        func has(_ interval: Int) -> Bool { present.contains(interval) }

        enum Third { case major, minor, suspended, none }
        let third: Third = has(4) ? .major : has(3) ? .minor : (has(2) || has(5)) ? .suspended : .none
        let perfectFifth = has(7)
        let augmentedFifth = has(8) && !has(7)
        let diminishedFifth = has(6) && !has(7)
        let majorSeventh = has(11)
        let flatSeventh = has(10)
        let diminishedSeventh = has(9) && !has(10) && !has(11)
        let flatNinth = has(1)
        let sharpNinth = has(3) && third == .major   // ♯9 only reads as such over a major 3rd
        let sharpEleventh = has(6) && perfectFifth   // distinct from a ♭5
        let flatThirteenth = has(8) && perfectFifth  // distinct from a ♯5

        if third == .minor && diminishedFifth && diminishedSeventh {
            return (.diminishedWholeHalf, [])
        }
        if third == .minor && diminishedFifth && flatSeventh {
            return (.locrian, [.dorian])
        }
        if third == .minor && majorSeventh {
            return (.melodicMinor, [])
        }
        if third == .minor {
            if has(8) && !has(9) { return (.aeolian, [.phrygian, .dorian]) }
            return (.dorian, [.aeolian])
        }

        if (third == .major || third == .suspended) && flatSeventh {
            if (flatNinth || sharpNinth) && (augmentedFifth || diminishedFifth || flatThirteenth) {
                return (.altered, [.diminishedHalfWhole])
            }
            if flatNinth || sharpNinth { return (.diminishedHalfWhole, [.altered]) }
            if sharpEleventh { return (.lydianDominant, [.mixolydian]) }
            if augmentedFifth { return (.wholeTone, [.altered]) }
            if flatThirteenth { return (.mixolydianFlat13, [.mixolydian]) }
            return (.mixolydian, [])
        }

        if third == .major {
            if augmentedFifth && majorSeventh { return (.lydianAugmented, [.lydian]) }
            if augmentedFifth { return (.wholeTone, []) }
            if sharpEleventh { return (.lydian, [.ionian]) }
            return (.ionian, [.lydian])
        }

        // Sus / quartal without a seventh, and anything unclassified — lean major.
        return (.ionian, [.mixolydian])
    }

    private static func intervalsFromRoot(_ pitchClasses: [Int], root: Int) -> [Int] {
        Array(Set(pitchClasses.map { (pitchClass($0) - root + 12) % 12 })).sorted()
    }

    static func pitchClass(_ value: Int) -> Int {
        ((value % 12) + 12) % 12
    }
}

// MARK: - How a note sits against the chord

/// How each note sits against the chord under it.
///
/// It lived in `MelodyAnalysis.swift`, which made it carrier — but it is a
/// question about a semitone and a chord's scale, and nothing else, so both
/// `DegreeContext.role(ofSemitone:)` and the pattern format were reaching up
/// for it from below. Moved here as part of PORTING.md's `ChordVoicing`
/// seam: the file it lived in was the accident, not the coupling.
enum HarmonicRole: String, Codable, Sendable {
    /// A tone of the chord itself.
    case chordTone
    /// In the scale, not in the chord — the colour notes.
    case colour
    /// A scale tone a semitone above a chord tone: unstable if landed on.
    case avoid
    /// Outside the chord's scale entirely — a chromatic approach, or a mistake.
    case offScale
}
