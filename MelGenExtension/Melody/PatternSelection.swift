//
//  PatternSelection.swift
//  MelGenExtension
//
//  How the next brief, and the next line, get chosen.
//
//  Both rotations used to be a bare cursor modulo the count, which is the right
//  default and the wrong only option: it makes a run of takes predictable, and it
//  gives you no way to iterate on one idea. Three modes cover it — cycle for
//  coverage, shuffle for surprise, lock for working on a single thing at varying
//  settings — over a set you choose, because half the variety problem is that the
//  rotation includes things you didn't want.
//
//  Shuffle is a shuffled *cycle* rather than independent draws: each round is a
//  permutation of the whole set, so everything is heard once before anything is
//  heard twice, and the seam between rounds is checked so a round never opens
//  with what the last one closed on. Independent draws would repeat immediately
//  about once every N picks, which reads as a bug whatever the maths says.
//

import Foundation
import Carrier
import Core

enum SelectionMode: String, Codable, CaseIterable, Sendable {
    /// In order. Predictable, and covers everything.
    case cycle
    /// A different order every round, without immediate repeats.
    case shuffle
    /// One thing, over and over, so you can vary everything else around it.
    case lock

    var label: String {
        switch self {
        case .cycle: return "Cycle"
        case .shuffle: return "Shuffle"
        case .lock: return "Lock"
        }
    }
}

enum Rotation {

    /// Which element of a set of `count` comes up at this point in the rotation.
    ///
    /// Deterministic in every mode, including shuffle — the same cursor gives the
    /// same answer, so a session reopens where it left off rather than jumping.
    static func index(cursor: Int, count: Int, mode: SelectionMode, seed: UInt64 = 0x9E3779B9) -> Int {
        guard count > 0 else { return 0 }
        guard count > 1 else { return 0 }
        let position = ((cursor % count) + count) % count

        switch mode {
        case .cycle, .lock:
            return position
        case .shuffle:
            let round = Int(floor(Double(cursor) / Double(count)))
            return permutation(round: round, count: count, seed: seed)[position]
        }
    }

    /// A shuffled ordering of `0..<count` for one round, with the join to the
    /// previous round fixed up so nothing repeats across it.
    static func permutation(round: Int, count: Int, seed: UInt64) -> [Int] {
        var order = rawPermutation(round: round, count: count, seed: seed)
        guard count > 2, round > 0 else { return order }

        // Don't open a round with what closed the last one. Compared against the
        // previous round's *raw* ordering rather than its fixed-up one, which is
        // the same thing everywhere except its first two positions — and those
        // aren't its last.
        let previous = rawPermutation(round: round - 1, count: count, seed: seed)
        if order[0] == previous[count - 1] {
            order.swapAt(0, 1)
        }
        return order
    }

    private static func rawPermutation(round: Int, count: Int, seed: UInt64) -> [Int] {
        var order = Array(0..<count)
        var rng = SplitMix64(seed: seed &+ UInt64(bitPattern: Int64(round)) &* 0x2545F4914F6CDD1D)
        // Fisher–Yates, so every ordering is equally likely.
        for index in stride(from: count - 1, to: 0, by: -1) {
            let swap = Int(rng.next() % UInt64(index + 1))
            order.swapAt(index, swap)
        }
        return order
    }
}

// MARK: - Applying it

extension MelodyPatterns {

    /// The line for this point in the rotation, from whichever set is in play.
    static func line(at cursor: Int,
                     from library: [MelodyPattern],
                     mode: SelectionMode = .cycle,
                     locked: String? = nil) -> MelodyPattern {
        let pool = library.isEmpty ? seeds : library
        if mode == .lock, let locked, let pinned = pool.first(where: { $0.name == locked }) {
            return pinned
        }
        return pool[Rotation.index(cursor: cursor, count: pool.count, mode: mode)]
    }
}

extension StyleBriefs {

    /// The brief for this point in the rotation, from the selected set.
    ///
    /// An empty selection means everything, so a session saved before selection
    /// existed behaves exactly as it did.
    static func brief(at cursor: Int,
                      selected names: [String],
                      mode: SelectionMode = .cycle,
                      locked: String? = nil) -> StyleBrief {
        let chosen = names.isEmpty ? all : all.filter { names.contains($0.name) }
        let pool = chosen.isEmpty ? all : chosen
        if mode == .lock, let locked, let pinned = pool.first(where: { $0.name == locked }) {
            return pinned
        }
        return pool[Rotation.index(cursor: cursor, count: pool.count, mode: mode)]
    }
}
