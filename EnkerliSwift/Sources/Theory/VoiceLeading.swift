//
//  VoiceLeading.swift
//  MelGenExtension
//
//  Minimal voice leading between pitch-class sets, under the L1 ("taxicab") norm.
//
//  A port of the suite's reference implementation
//  (`music-suite/packages/theory/src/voiceLeading.ts`), which implements the
//  dynamic-programming algorithm from the supplement to Dmitri Tymoczko, "The
//  Geometry of Musical Chords" (Science, 2006): the two chords are treated as
//  cyclic sequences, and for a fixed initial pair the matrix entry e[i][j] adds
//  the interval-class distance to the cheapest of its three predecessors.
//  Minimising over rotations of one chord gives the global minimum. Voices may
//  double, which is what makes a leading between chords of different size
//  well-defined at all.
//
//  Ported rather than shared because the suite is TypeScript and this is an
//  audio unit. What keeps the two honest is `Scripts/verify.sh voiceleading`,
//  which runs this against the same `vectors/voice-leading.json` the Lua and C++
//  ports are held to — so a divergence is a test failure rather than a thing
//  someone notices in a chord chart years later.
//
//  Why this exists when `ChordVoicing.lead` already claimed to voice-lead: that
//  one moves a whole voicing by octaves, preserving the style's internal
//  spacing. It keeps a rootless A recognisably a rootless A, and it means every
//  chord in a progression is the *same shape* transposed — which is audibly
//  "the chords are all in the same voicing", because the top voice tracks the
//  root. Taxicab leading answers the other question: not "where does this
//  voicing sit" but "which notes does each voice go to". The two are both worth
//  having, which is why they're both here and the choice is exposed.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

/// How one chord's voicing is chosen given the one before it.
public enum VoiceLeadingMode: String, Codable, CaseIterable, Sendable {
    /// Every chord in its own home register. No relation between neighbours —
    /// useful as a reference for hearing what the other two do.
    case none
    /// The whole voicing shifted by octaves to the register that moves least.
    /// Keeps the voicing style's internal spacing exactly.
    case register
    /// Each voice to its nearest tone of the next chord. Smoothest, and it
    /// reshapes the voicing to get there — which is what a player does.
    case smooth

    public var label: String {
        switch self {
        case .none: return "Off"
        case .register: return "Register"
        case .smooth: return "Smooth"
        }
    }

    public var summary: String {
        switch self {
        case .none: return "Every chord in its home position — no smoothing"
        case .register: return "The voicing keeps its shape and moves octaves"
        case .smooth: return "Each voice to its nearest note — taxicab leading"
        }
    }
}

/// One minimal leading: how far every voice moved in total, and one mapping
/// that achieves it.
public struct VoiceLeadingResult: Hashable, Sendable {
    /// Sum of the interval classes moved by every voice. Symmetric in its
    /// arguments, and zero exactly when the two sets are equal.
    public var size: Int
    /// One minimal mapping, as (from, to) pitch-class pairs. A pitch class may
    /// appear more than once on either side: that's a doubling, and it's what
    /// lets four voices lead to a triad.
    public var mapping: [(from: Int, to: Int)]

    public static func == (lhs: VoiceLeadingResult, rhs: VoiceLeadingResult) -> Bool {
        lhs.size == rhs.size && lhs.mapping.map { [$0.from, $0.to] } == rhs.mapping.map { [$0.from, $0.to] }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(size)
        for pair in mapping { hasher.combine(pair.from); hasher.combine(pair.to) }
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(size: Int,
                mapping: [(from: Int, to: Int)]) {
        self.size = size
        self.mapping = mapping
    }
}

public enum VoiceLeading {

    /// Distance between two pitch classes the short way round the circle.
    public static func intervalClass(_ a: Int, _ b: Int) -> Int {
        let difference = abs(mod12(a) - mod12(b))
        return min(difference, 12 - difference)
    }

    public static func mod12(_ value: Int) -> Int { ((value % 12) + 12) % 12 }

    /// The distinct pitch classes of a collection, in order.
    public static func pitchClassSet<S: Sequence>(_ values: S) -> [Int] where S.Element == Int {
        var seen = Set<Int>()
        var result: [Int] = []
        for value in values {
            let pc = mod12(value)
            if seen.insert(pc).inserted { result.append(pc) }
        }
        return result.sorted()
    }

    /// The cheapest way to get from one pitch-class set to another.
    ///
    /// Order and duplicates in the inputs don't matter; both are reduced to sets
    /// first, which is what makes the result a property of the two chords rather
    /// than of how they were written down.
    public static func minimal<S: Sequence, T: Sequence>(from: S, to: T) -> VoiceLeadingResult
    where S.Element == Int, T.Element == Int {
        let a = pitchClassSet(from)
        let b = pitchClassSet(to)
        guard !a.isEmpty, !b.isEmpty else { return VoiceLeadingResult(size: 0, mapping: []) }

        var best: VoiceLeadingResult?
        // The algorithm fixes which pair of notes starts the leading, so every
        // rotation of one chord has to be tried; the minimum over rotations is
        // the minimum overall.
        for rotation in 0..<b.count {
            let rotated = Array(b[rotation...] + b[..<rotation])
            let candidate = solve(a, rotated)
            if best == nil || candidate.size < best!.size { best = candidate }
        }

        var result = best ?? VoiceLeadingResult(size: 0, mapping: [])
        result.mapping.sort { ($0.from, $0.to) < ($1.from, $1.to) }
        return result
    }

    /// Just the size, for ranking candidates.
    public static func size<S: Sequence, T: Sequence>(from: S, to: T) -> Int
    where S.Element == Int, T.Element == Int {
        minimal(from: from, to: to).size
    }

    private static func solve(_ a: [Int], _ b: [Int]) -> VoiceLeadingResult {
        // Both cyclic sequences are extended by repeating their first element,
        // so a path from one corner of the matrix to the other wraps around.
        let ax = a + [a[0]]
        let bx = b + [b[0]]
        let m = ax.count
        let n = bx.count

        var e = [[Int]](repeating: [Int](repeating: Int.max, count: n), count: m)
        for i in 0..<m {
            for j in 0..<n {
                let d = intervalClass(ax[i], bx[j])
                if i == 0 && j == 0 { e[i][j] = d; continue }
                let up = i > 0 ? e[i - 1][j] : Int.max
                let left = j > 0 ? e[i][j - 1] : Int.max
                let diagonal = (i > 0 && j > 0) ? e[i - 1][j - 1] : Int.max
                e[i][j] = d + Swift.min(up, left, diagonal)
            }
        }

        // Trace one cheapest path back. The first and last entries are the same
        // pair counted twice, so the duplicate is dropped and its cost removed.
        var pairs: [(from: Int, to: Int)] = []
        var i = m - 1
        var j = n - 1
        while i > 0 || j > 0 {
            pairs.append((ax[i], bx[j]))
            let up = i > 0 ? e[i - 1][j] : Int.max
            let left = j > 0 ? e[i][j - 1] : Int.max
            let diagonal = (i > 0 && j > 0) ? e[i - 1][j - 1] : Int.max
            let best = Swift.min(up, left, diagonal)
            if best == diagonal { i -= 1; j -= 1 }
            else if best == up { i -= 1 }
            else { j -= 1 }
        }
        pairs.append((ax[0], bx[0]))
        pairs.reverse()
        pairs.removeLast()

        return VoiceLeadingResult(size: e[m - 1][n - 1] - intervalClass(ax[0], bx[0]),
                                  mapping: pairs)
    }

    // MARK: - From pitch classes to actual notes

    /// The voicing of `targetClasses` that each voice of `from` reaches by
    /// moving as little as possible.
    ///
    /// The minimal mapping says which pitch class each voice goes to; this puts
    /// that decision in a register, by moving each voice to its target by at
    /// most six semitones in either direction. A common tone therefore doesn't
    /// move at all, which is the property worth having.
    ///
    /// Surplus voices are dropped rather than doubled — a doubling in a comp
    /// reads as a thicker chord, not as smoother leading — and any target tone
    /// no voice reached is placed near the middle of the result so the chord is
    /// complete.
    public static func led(from previous: [Int], to targetClasses: [Int], range: ClosedRange<Int>) -> [Int] {
        let targets = pitchClassSet(targetClasses)
        guard !targets.isEmpty else { return [] }
        guard !previous.isEmpty else { return targets.map { 60 + $0 } }

        let mapping = minimal(from: previous, to: targets).mapping

        // Which actual notes sound each of the previous chord's pitch classes.
        // The lowest is used, so voices are consumed from the bottom up and a
        // doubled pitch class doesn't send two voices to the same place.
        var sources: [Int: [Int]] = [:]
        for note in previous.sorted() { sources[mod12(note), default: []].append(note) }

        var notes: [Int] = []
        var placed = Set<Int>()
        for pair in mapping {
            guard !placed.contains(pair.to) else { continue }
            placed.insert(pair.to)
            let source = sources[pair.from]?.first ?? (60 + pair.from)
            var note = source + shortestStep(from: source, to: pair.to)
            while notes.contains(note) { note += 12 }
            notes.append(note)
        }

        // Anything the mapping didn't cover: put it where the rest of the chord
        // already is, rather than in some default octave of its own.
        let centre = notes.isEmpty ? 60 : notes.reduce(0, +) / notes.count
        for target in targets where !placed.contains(target) {
            placed.insert(target)
            var note = centre + shortestStep(from: centre, to: target)
            while notes.contains(note) { note += 12 }
            notes.append(note)
        }

        return notes
            .map { Swift.min(Swift.max($0, range.lowerBound), range.upperBound) }
            .sorted()
    }

    /// How far to move from a note to reach a pitch class, the short way: in
    /// (-6, +6]. This is what makes a held common tone cost zero.
    public static func shortestStep(from note: Int, to pitchClass: Int) -> Int {
        (((mod12(pitchClass) - mod12(note)) % 12) + 18) % 12 - 6
    }

    /// Total movement from one set of notes to another, each target counted to
    /// its nearest source. Used to rank candidate voicings.
    public static func movement(from previous: [Int], to notes: [Int]) -> Int {
        guard !previous.isEmpty else { return 0 }
        return notes.reduce(0) { total, note in
            total + (previous.map { abs($0 - note) }.min() ?? 0)
        }
    }
}
