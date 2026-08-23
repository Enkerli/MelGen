//
//  MelodyStepPattern.swift
//  MelGenExtension
//
//  Lines described as *moves* rather than as positions.
//
//  Everything else in this codebase is degree-relative: a note knows which step
//  of the sounding chord's scale it is. That already survives reharmonization.
//  But there's a level below it — describe a line as the sequence of *intervals
//  between* its notes and it survives something else: it can start anywhere, and
//  it doesn't need to know where it is at all.
//
//  Two traditions arrive at the same representation from opposite directions.
//
//  **Hanon.** *The Virtuoso Pianist* is built almost entirely on one device: a
//  short figure, repeated, each repetition starting one scale step higher. The
//  first exercise is C E F G A G F E, then D F G A B A G F, and so on up the
//  keyboard. Written as intervals between successive notes — including the step
//  from the end of one repetition into the start of the next — it is
//  `+2 +1 +1 +1 −1 −1 −1 −1`, and the sum of that cycle is **+1**.
//
//  That's the whole trick, and it falls out of this representation for free: *a
//  cycle of intervals whose sum isn't zero sequences itself.* Nothing has to
//  transpose anything. Play the loop and it climbs, because it ends one step
//  above where it began. A cycle summing to zero is an ornament that stays put;
//  one summing to −1 walks down. The `drift` property is that sum, and it is the
//  single most useful number about a cell.
//
//  **The Samchillian.** Leon Gruenbaum's Samchillian Tip Tip Tip Cheeepeeeee —
//  and the Misha, the Eventide module built from it with him — put this in the
//  performer's hands: the keys are intervals within the current scale, not
//  pitches, so the same fingering is the same *shape* in any key, and playing is
//  a matter of deciding where to go next rather than which note to hit. That is
//  precisely what a delta stream is, and it is why a vocabulary of cells here is
//  playable material rather than an exercise book: a Samchillian phrase and a
//  Hanon figure are the same kind of object.
//
//  What this buys MelGen specifically: contour that is genuinely independent of
//  register, of key, and of where the previous phrase left off — so a cell can be
//  dropped in anywhere, and a long line can be built by walking one rather than
//  by tiling a fixed shape. Tiling was what made the library repeat itself.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

/// A figure described as the moves between its notes.
struct StepCell: Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var summary: String
    /// Scale steps from each note to the next, cycled. The last entry is the
    /// step *into the next repetition*, which is what makes the cycle close.
    var deltas: [Int]
    /// Note lengths in eighths, cycled independently of the deltas — so a cell
    /// of eight moves and three lengths phases against itself, which is free
    /// variety and costs nothing.
    var lengths: [Int]

    /// How far one cycle moves. Non-zero means the figure sequences itself, which
    /// is the entire mechanism behind Hanon's exercises.
    var drift: Int { deltas.reduce(0, +) }

    var isSelfSequencing: Bool { drift != 0 }

    var driftDescription: String {
        switch drift {
        case 0: return "stays put"
        case 1: return "climbs a step each time round"
        case -1: return "falls a step each time round"
        case let value where value > 0: return "climbs \(value) steps each time round"
        default: return "falls \(-drift) steps each time round"
        }
    }

    init(_ name: String, _ summary: String, deltas: [Int], lengths: [Int] = [1]) {
        self.name = name
        self.summary = summary
        self.deltas = deltas
        self.lengths = lengths.isEmpty ? [1] : lengths
    }
}

extension StepCell {

    /// The vocabulary. Exercises and interval streams side by side on purpose:
    /// in this representation they are the same kind of thing, and the only
    /// difference is whether anyone meant them to be music.
    static let all: [StepCell] = [
        hanonRise, hanonFall, thirds, brokenTriads, sixths,
        turn, wideningZigzag, octaveCreep, samchillianDrift, descendingFours
    ]

    /// Hanon's first exercise, as intervals. `+2 +1 +1 +1 −1 −1 −1 −1`, drift +1
    /// — up through the scale one step per repetition, without anything ever
    /// transposing it.
    static let hanonRise = StepCell(
        "Hanon rise",
        "Up a third, walk up, walk back — and it climbs a step each time",
        deltas: [2, 1, 1, 1, -1, -1, -1, -1]
    )

    /// The same figure turned over: it walks the scale down.
    static let hanonFall = StepCell(
        "Hanon fall",
        "The rise inverted, so it descends a step per repetition",
        deltas: [-2, -1, -1, -1, 1, 1, 1, 1]
    )

    /// Running thirds. Two moves, drift +1: the shortest self-sequencing cell
    /// there is, and the one that most sounds like an exercise — which is why it
    /// wants a rhythm borrowed from somewhere else.
    static let thirds = StepCell(
        "Thirds",
        "Up a third, down a step, forever upward",
        deltas: [2, -1],
        lengths: [1, 1, 2]
    )

    /// Up the chord, back down past where it started.
    static let brokenTriads = StepCell(
        "Broken triads",
        "Arpeggio up, drop back, one step further on each time",
        deltas: [2, 2, -3],
        lengths: [1, 1, 2]
    )

    /// Sixths: a wide reach and a short recovery.
    static let sixths = StepCell(
        "Sixths",
        "A sixth up, a fifth back — wide, and still climbing",
        deltas: [5, -4],
        lengths: [2, 1]
    )

    /// Drift zero, so it goes nowhere. An ornament rather than a line, and the
    /// clearest demonstration that drift is the thing that makes a cell move.
    static let turn = StepCell(
        "Turn",
        "Above, home, below, home — an ornament that stays where it is",
        deltas: [1, -1, -1, 1],
        lengths: [1, 1, 1, 2]
    )

    /// Intervals that widen as it goes, then close again. Drift zero, and still
    /// nothing like the turn — which is the point: drift is only one axis.
    static let wideningZigzag = StepCell(
        "Widening zigzag",
        "Alternating up and down, reaching further each time and back",
        deltas: [1, -2, 3, -4, 5, -4, 3, -2],
        lengths: [1, 1, 2]
    )

    /// Octave leaps that creep. In a seven-note scale, seven steps is the octave.
    static let octaveCreep = StepCell(
        "Octave creep",
        "Leap an octave, fall back, and gain a step",
        deltas: [7, -7, 1],
        lengths: [2, 1, 1]
    )

    /// A Samchillian-shaped stream: no exercise logic, just a sequence of moves
    /// a player might make, with a drift that carries it somewhere.
    static let samchillianDrift = StepCell(
        "Interval stream",
        "Steps and a reach, drifting upward the way a played line does",
        deltas: [1, 1, -2, 3, -1, -1],
        lengths: [1, 2, 1, 1, 3]
    )

    /// Descending runs that recover upward. Drift +1, so the line rises overall
    /// while every figure in it falls — a contradiction worth having.
    static let descendingFours = StepCell(
        "Descending fours",
        "Four steps down, a fourth up: falling figures on a rising line",
        deltas: [-1, -1, -1, 4],
        lengths: [1, 1, 1, 2]
    )
}

// MARK: - Walking a cell

enum MelodyStepPatterns {

    /// How far a line may wander before it turns around, in scale degrees either
    /// side of where it started. Eleven is about a twelfth and a half, which is
    /// what keeps a self-sequencing cell inside a singable range instead of
    /// running off the top of the keyboard the way Hanon happily does.
    static let defaultSpan = 11

    /// Walks a cell into a line.
    ///
    /// A self-sequencing cell would climb forever, so the walk reflects: when the
    /// next move would take it past the span, the direction flips and the figure
    /// comes back down. That turnaround is what a Hanon exercise does at the top
    /// of the keyboard, and it's what stops this needing a range check anywhere
    /// downstream.
    ///
    /// - Parameters:
    ///   - startDegree: where to begin, in scale degrees.
    ///   - span: how far either side of the start it may wander before turning.
    static func line(from cell: StepCell,
                     bars: Int = 4,
                     startDegree: Int = 0,
                     span: Int? = nil,
                     velocity: Int = 88,
                     name: String? = nil) -> MelodyPattern {
        // A cell needs room proportional to what it reaches for: too tight and a
        // figure that leaps an octave turns around before it has climbed
        // anywhere, which is the difference between "octave creep" and "octave
        // oscillate". Measured from the widest move in the cell rather than
        // guessed at, with a floor of a few steps above the reach itself.
        let reach = cell.deltas.map(abs).max() ?? 1
        let span = span ?? max(reach + 3, defaultSpan - reach)
        let totalEighths = max(8, bars * 8)
        var notes: [PatternNote] = []

        var degree = startDegree
        var cursor = 0
        var direction = 1
        var index = 0

        while cursor < totalEighths {
            let length = cell.lengths[index % cell.lengths.count]
            notes.append(PatternNote(
                startEighth: cursor,
                lengthEighths: max(1, length),
                degree: degree,
                octave: 0,
                alteration: 0,
                // Lean on the first note of each cycle, so the figure's shape is
                // audible rather than just present.
                velocity: min(120, max(40, velocity + (index % cell.deltas.count == 0 ? 10 : -4))),
                restAfterEighths: 0,
                role: nil
            ))

            let delta = cell.deltas[index % cell.deltas.count] * direction
            let next = degree + delta
            // Turn around rather than run off the end.
            if next > startDegree + span || next < startDegree - span {
                direction *= -1
                degree -= delta
            } else {
                degree = next
            }

            cursor += max(1, length)
            index += 1
        }

        // Clip the last note to the form.
        if var last = notes.last, last.startEighth + last.lengthEighths > totalEighths {
            last.lengthEighths = max(1, totalEighths - last.startEighth)
            notes[notes.count - 1] = last
        }

        return MelodyPattern(
            name: name ?? cell.name,
            bars: max(1, bars),
            summary: "\(cell.summary) · \(cell.driftDescription)",
            notes: notes.filter { $0.startEighth < totalEighths },
            // A cell *is* its intervals, so it's realized by stepping through the
            // sounding scale rather than by placing degrees and folding.
            realization: .stepwise
        )
    }

    /// Reads a line back as the moves between its notes.
    ///
    /// The inverse, and the thing that makes this a format rather than a
    /// generator: any pattern — composed, sampled, kept from a take — can be
    /// described as a stream of intervals and then played from anywhere. This is
    /// the Samchillian's view of a melody, applied to material that arrived some
    /// other way.
    static func cell(from pattern: MelodyPattern, named name: String) -> StepCell? {
        let notes = pattern.notes.sorted { $0.startEighth < $1.startEighth }
        guard notes.count > 1 else { return nil }

        var deltas = zip(notes, notes.dropFirst()).map { $1.degree - $0.degree }
        // Close the cycle: the move from the last note back into the first, so
        // repeating the cell is continuous rather than jumping.
        deltas.append(notes[0].degree - notes[notes.count - 1].degree)

        return StepCell(name,
                        "lifted from \(pattern.name)",
                        deltas: deltas,
                        lengths: notes.map(\.lengthEighths))
    }

    /// The whole vocabulary as playable lines, for the library.
    static func library(bars: Int = 4) -> [MelodyPattern] {
        StepCell.all.map { line(from: $0, bars: bars) }
    }
}
