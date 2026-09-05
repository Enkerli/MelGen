//
//  CompingVoicer.swift
//  MelGenExtension
//
//  Turning chosen chord tones into a voiced, voice-led part.
//
//  This is the half of model-generated comping that isn't a choice. The model
//  decides when a chord lands and which of its tones are in it — both genuine
//  decisions, and both things a language model is good at. Register, spacing and
//  how each voicing moves to the next are arithmetic, and asking a model for
//  arithmetic gets voicings that jump an octave between chords because nothing
//  was keeping them near each other.
//
//  Kept out of MelodyGenerator so it can be tested without FoundationModels: the
//  input is a plain tuple, which is the whole of what the schema carries.
//

import Foundation
import Carrier
import Theory

enum CompingVoicer {

    /// One chord as the model describes it.
    typealias Hit = (startEighth: Int, lengthEighths: Int, degrees: [Int], velocity: Int)

    /// Voices a set of hits over a progression, leading each into the next.
    static func voice(_ hits: [Hit],
                      over progression: ChordProgression,
                      centre: Int = ChordVoicings.defaultCentre) -> [SequencedNote] {
        let ordered = hits
            .filter { $0.startEighth >= 0 && Double($0.startEighth) / 2 < progression.totalBeats }
            .sorted { $0.startEighth < $1.startEighth }

        var notes: [SequencedNote] = []
        var previous: [Int]?

        for hit in ordered {
            let beat = Double(hit.startEighth) / 2
            guard let placed = progression.chord(at: beat) else { continue }
            guard let pitches = pitches(for: hit.degrees, of: placed.symbol) else { continue }

            var voiced = pitches
            if let previous {
                voiced = ChordVoicings.lead(from: previous, to: voiced, centre: centre)
            } else {
                // No predecessor: centre it, in whole octaves so the spacing the
                // degrees implied is exactly preserved.
                let mean = voiced.reduce(0, +) / voiced.count
                let shift = 12 * Int((Double(centre - mean) / 12).rounded())
                voiced = voiced.map { $0 + shift }
            }
            previous = voiced

            // Never into the next chord: holding a ii voicing through the V is
            // the one thing that makes a comp sound wrong rather than dull.
            let chordEnd = placed.startBeat + placed.durationBeats
            let duration = max(0.25, min(Double(max(1, hit.lengthEighths)) / 2, chordEnd - beat))

            for pitch in voiced where (24...108).contains(pitch) {
                notes.append(SequencedNote(note: UInt8(pitch),
                                           velocity: UInt8(clamping: max(1, hit.velocity)),
                                           startBeat: beat,
                                           durationBeats: duration))
            }
        }

        return notes.sorted { ($0.startBeat, $0.note) < ($1.startBeat, $1.note) }
    }

    /// Degrees of the sounding chord's scale to pitches, an octave apart where
    /// the degree asks for it.
    ///
    /// Nil rather than a single note when fewer than two distinct pitches come
    /// out: a comp hit with one note in it is not a chord, and emitting it would
    /// be a worse answer than skipping the hit.
    static func pitches(for degrees: [Int], of symbol: ChordSymbol) -> [Int]? {
        let root = symbol.rootPitchClass
        let intervals = symbol.scalePitchClasses
            .map { (($0 - root) % 12 + 12) % 12 }
            .sorted()
        guard !intervals.isEmpty else { return nil }

        let size = intervals.count
        var pitches: Set<Int> = []
        for degree in degrees {
            let index = ((degree % size) + size) % size
            let carry = Int(floor(Double(degree) / Double(size)))
            pitches.insert(60 + root + intervals[index] + 12 * carry)
        }
        guard pitches.count >= 2 else { return nil }
        return pitches.sorted()
    }
}
