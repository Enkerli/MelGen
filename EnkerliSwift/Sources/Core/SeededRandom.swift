//
//  SeededRandom.swift
//  MelGenExtension
//
//  The one primitive with no music in it.
//
//  SplitMix64 lived in MelodyExpression.swift because that is where it was
//  first needed. Every generator here reaches for it — phrases, comping,
//  basslines, retrieval, topics, pattern selection, and the progression
//  generator, which is theory and has no business knowing that a file about
//  swing and metric accent exists.
//
//  Moved out as the first cut in PORTING.md's seam list: a sibling plug-in
//  wants reproducible-by-seed generation and wants none of the melody app, and
//  this is what "shared foundation" means at its smallest. Checked by
//  Scripts/verify.sh boundary.
//
//  The algorithm is Steele, Lea and Flood's SplittableRandom mixer. It is here
//  rather than Swift's own RandomNumberGenerator conformance for one reason:
//  the same seed has to give the same take on every machine and every OS
//  version, and the standard library promises nothing of the kind.
//

import Foundation

/// Small deterministic generator, so a take always renders the same way.
public struct SplitMix64 {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// A value in 0..<1.
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
