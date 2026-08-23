//
//  MelodyGesture.swift
//  MelGenExtension
//
//  Phrases made of gestures, because variety isn't a number of notes.
//
//  Everything in the plug-in that tried to make lines more interesting had been
//  reaching for the same lever: more notes, fewer notes, a different density
//  target. That lever was never the problem. A line of five notes per bar and a
//  line of three notes per bar are equally dull if every note is an eighth, every
//  phrase is four bars, and every four bars is the same four bars.
//
//  What's missing is *gesture*: the small shaped figures a player actually
//  thinks in. A pickup into a downbeat. A dotted quarter answered by an eighth. A
//  3+3+2 cell. A held note with air after it. A run that turns around. An
//  enclosure into a landing note. Those have rhythmic identity, they have
//  contour, and — this is the part that matters — they have a *role in a phrase*:
//  some open, some continue, some answer, some end.
//
//  So a gesture here is a **rhythm crossed with a contour**, not a fixed list of
//  notes. Twelve rhythms and ten contours is a hundred and twenty figures out of
//  twenty-two declarations, and the phrase grammar in MelodyPhrase.swift composes
//  them into lines that state something, develop it and land.
//
//  Two deliberate constraints. Everything is on the eighth-note grid, because
//  that's what the schema and the kernel speak (ROADMAP D1 is the finer grid);
//  the dotted and 3+3+2 figures are what buys back most of what triplets would.
//  And a gesture produces `PatternNote`s — degrees, not pitches — so everything
//  downstream is unchanged: gestures compose into patterns, patterns realize onto
//  harmony, takes extract back into patterns. Gestures are a *generator of
//  patterns*, not a second runtime format.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

// MARK: - Rhythm

/// The rhythmic half of a gesture: what lengths, in what order, with what
/// silence after.
///
/// Lengths are in eighths and lie end to end unless `onsets` says otherwise —
/// which is how syncopation gets in, since a figure that starts on an odd eighth
/// and ties across the beat can't be described by durations alone.
struct GestureRhythm: Hashable, Sendable {
    var name: String
    /// Note lengths in eighths, in order.
    var lengths: [Int]
    /// Explicit onsets in eighths from the gesture's start. Nil lays the notes
    /// end to end.
    var onsets: [Int]?
    /// Silence after the last note, in eighths. This is where phrasing lives:
    /// a figure with no air after it runs into the next one and the line
    /// becomes a wall.
    var trailingRest: Int
    /// Indices that carry the figure's weight.
    var accents: [Int]

    init(_ name: String,
         lengths: [Int],
         onsets: [Int]? = nil,
         trailingRest: Int = 0,
         accents: [Int] = [0]) {
        self.name = name
        self.lengths = lengths
        self.onsets = onsets
        self.trailingRest = trailingRest
        self.accents = accents
    }

    var noteCount: Int { lengths.count }

    /// Where each note starts, in eighths from the gesture's start.
    var positions: [Int] {
        if let onsets, onsets.count == lengths.count { return onsets }
        var cursor = 0
        return lengths.map { length in
            defer { cursor += length }
            return cursor
        }
    }

    /// The whole gesture's footprint, silence included.
    var spanEighths: Int {
        let positions = positions
        let end = zip(positions, lengths).map(+).max() ?? 0
        return end + trailingRest
    }
}

extension GestureRhythm {

    /// The vocabulary. Chosen so that no two of them read as the same figure
    /// played at a different speed — which is the trap a list of "one note, two
    /// notes, three notes" falls into.
    static let all: [GestureRhythm] = [
        even, dotted, reverseDotted, tresillo, charleston, longWithAir,
        pushedPair, runOfFour, tiedOverTheBar, twoPlusThree, tripletFeel, stab
    ]

    /// Steady eighths. The baseline, and the one everything else is *not*.
    static let even = GestureRhythm("Even", lengths: [1, 1, 1, 1], trailingRest: 2, accents: [0, 2])

    /// Dotted quarter then eighth. The loping figure, and the single cheapest
    /// way to stop a line sounding metronomic.
    static let dotted = GestureRhythm("Dotted", lengths: [3, 1], trailingRest: 2, accents: [0])

    /// Its reverse: a short pickup leaning into a long note.
    static let reverseDotted = GestureRhythm("Lean-in", lengths: [1, 3], trailingRest: 2, accents: [1])

    /// 3+3+2 — the cell the roadmap has wanted since D2. It's the rhythm that
    /// most reliably makes an eighth-grid line stop sounding like an eighth grid.
    static let tresillo = GestureRhythm("Tresillo", lengths: [3, 3, 2], trailingRest: 2, accents: [0, 1])

    /// The downbeat and the and-of-two, with the rest of the bar empty. Almost
    /// all air, and it swings by itself.
    static let charleston = GestureRhythm("Charleston", lengths: [1, 3], onsets: [0, 3],
                                          trailingRest: 2, accents: [0, 1])

    /// One long note and a bar's worth of nothing. The figure a line needs after
    /// it has said something.
    static let longWithAir = GestureRhythm("Long tone", lengths: [6], trailingRest: 4, accents: [0])

    /// Two notes arriving an eighth early, tied over the beat — the anticipation
    /// the style briefs kept asking the model for and never getting.
    static let pushedPair = GestureRhythm("Pushed", lengths: [3, 2], onsets: [1, 4],
                                          trailingRest: 1, accents: [0])

    /// A burst that starts on the and of one and lands long. Distinct from
    /// `even` by where it *begins*, which is the whole difference between a
    /// stream of eighths and a flourish.
    static let runOfFour = GestureRhythm("Burst", lengths: [1, 1, 1, 3], onsets: [1, 2, 3, 4],
                                         trailingRest: 3, accents: [0, 3])

    /// A note that starts before the bar line and holds through it. The only
    /// figure here that makes the bar line audible by crossing it.
    static let tiedOverTheBar = GestureRhythm("Tied over", lengths: [1, 5], onsets: [0, 1],
                                              trailingRest: 2, accents: [1])

    /// 2+3, an uneven pair that lands off where you expect it to.
    static let twoPlusThree = GestureRhythm("Uneven pair", lengths: [2, 3], trailingRest: 3, accents: [0])

    /// The nearest an eighth grid gets to a triplet: three notes over four
    /// eighths, unevenly. Not a triplet; honest about not being one.
    static let tripletFeel = GestureRhythm("Loping three", lengths: [2, 1, 1], onsets: [0, 2, 3],
                                           trailingRest: 4, accents: [0])

    /// One short note, then silence. Punctuation.
    static let stab = GestureRhythm("Stab", lengths: [1], trailingRest: 3, accents: [0])
}

// MARK: - Contour

/// The pitch half of a gesture, in scale degrees relative to wherever the
/// gesture starts. Independent of the rhythm on purpose: the same shape played
/// as even eighths and as a 3+3+2 are two different musical ideas, and a
/// vocabulary that couples them can only hold as many ideas as it has entries.
enum GestureContour: String, CaseIterable, Sendable {
    case ascend, descend, arch, valley, turn, leapFall, fallLeap, pendulum, held, enclose

    var label: String {
        switch self {
        case .ascend: return "Rising"
        case .descend: return "Falling"
        case .arch: return "Arch"
        case .valley: return "Valley"
        case .turn: return "Turn"
        case .leapFall: return "Leap and fall"
        case .fallLeap: return "Fall and leap"
        case .pendulum: return "Pendulum"
        case .held: return "Held"
        case .enclose: return "Enclosure"
        }
    }

    /// Degree offsets from the gesture's anchor, one per note.
    ///
    /// Offsets are in scale steps, so 2 is a third and 4 is a fifth — which is
    /// what makes a contour sound like the same shape over any chord.
    func offsets(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        switch self {
        case .ascend:
            return (0..<count).map { $0 }
        case .descend:
            return (0..<count).map { -$0 }
        case .arch:
            let peak = count / 2
            return (0..<count).map { $0 <= peak ? $0 : 2 * peak - $0 }
        case .valley:
            let trough = count / 2
            return (0..<count).map { $0 <= trough ? -$0 : $0 - 2 * trough }
        case .turn:
            // Above, home, below, home — the ornament, cycling for longer figures.
            let cycle = [0, 1, 0, -1]
            return (0..<count).map { cycle[$0 % cycle.count] }
        case .leapFall:
            // Up a fifth, then walk back down. Resolve a leap by step in the
            // opposite direction, which is the one voice-leading rule the model
            // breaks most often.
            guard count > 1 else { return [0] }
            return [0] + (1..<count).map { 4 - ($0 - 1) }
        case .fallLeap:
            guard count > 2 else { return (0..<count).map { -$0 } }
            return (0..<(count - 1)).map { -$0 } + [3]
        case .pendulum:
            // Home, away, home, further away — the shape that develops without
            // going anywhere, which is most of what a vamp wants.
            return (0..<count).map { $0.isMultiple(of: 2) ? 0 : ($0 / 2) + 1 }
        case .held:
            return Array(repeating: 0, count: count)
        case .enclose:
            // Approach the target from above and below before landing on it.
            guard count > 2 else { return Array(repeating: 0, count: count) }
            var offsets = Array(repeating: 0, count: count)
            offsets[count - 3] = 1
            offsets[count - 2] = 0      // carries a semitone alteration; see `alterations`
            offsets[count - 1] = 0
            return offsets
        }
    }

    /// Semitone alterations, where the contour means a chromatic note rather than
    /// a scale one. Everything is 0 except the note an enclosure approaches from
    /// underneath, which is a semitone below its target rather than a scale step
    /// below — that's what makes it an enclosure and not a turn.
    func alterations(count: Int) -> [Int] {
        var alterations = Array(repeating: 0, count: max(0, count))
        if self == .enclose, count > 2 {
            alterations[count - 2] = -1
        }
        return alterations
    }

    /// Where the shape leaves the line, in degrees from where it started. The
    /// phrase grammar uses this to decide where the next gesture begins.
    func endOffset(count: Int) -> Int {
        offsets(count: count).last ?? 0
    }
}

// MARK: - Role

/// What a gesture is doing in its phrase.
///
/// The grammar in MelodyPhrase.swift is built on this: a phrase that opens,
/// develops and lands sounds composed, and a phrase that is four statements in a
/// row sounds like a list. Roles are what make that difference expressible.
enum GestureRole: String, CaseIterable, Sendable {
    /// Leads into a downbeat from before it.
    case pickup
    /// Opens the phrase, on or near the downbeat.
    case statement
    /// Carries it forward.
    case continuation
    /// Replies to the statement — same rhythm, different outcome.
    case answer
    /// Ends it, with air after.
    case cadence

    var label: String {
        switch self {
        case .pickup: return "Pickup"
        case .statement: return "Statement"
        case .continuation: return "Continuation"
        case .answer: return "Answer"
        case .cadence: return "Cadence"
        }
    }
}

// MARK: - A gesture

/// One figure: a rhythm, a shape, and a job.
struct MelodyGesture: Hashable, Sendable {
    var rhythm: GestureRhythm
    var contour: GestureContour
    var role: GestureRole
    /// Where the shape sits relative to the phrase's home degree.
    var anchor: Int = 0

    var name: String { "\(rhythm.name) \(contour.label.lowercased())" }
    var spanEighths: Int { rhythm.spanEighths }

    /// Instantiates the figure as pattern notes, starting at `startEighth`.
    ///
    /// - Parameter home: the degree the phrase is centred on. Contour offsets are
    ///   relative to it, so the same gesture at a different home is the same
    ///   figure transposed within the scale — which is exactly what sequencing a
    ///   motif through the changes means.
    func notes(startingAt startEighth: Int, home: Int, velocity: Int = 88) -> [PatternNote] {
        let count = rhythm.noteCount
        let offsets = contour.offsets(count: count)
        let alterations = contour.alterations(count: count)
        let positions = rhythm.positions

        return (0..<count).map { index in
            let isAccented = rhythm.accents.contains(index)
            // The last note of the gesture carries its trailing rest, which is
            // how phrasing survives into the pattern format.
            let isLast = index == count - 1
            return PatternNote(
                startEighth: startEighth + positions[index],
                lengthEighths: max(1, rhythm.lengths[index]),
                degree: home + anchor + offsets[index],
                octave: 0,
                alteration: alterations[index],
                velocity: min(120, max(40, velocity + (isAccented ? 12 : -6))),
                restAfterEighths: isLast ? rhythm.trailingRest : 0,
                role: nil
            )
        }
    }

    /// The same figure with its shape turned upside down — the classic way to
    /// answer a call without changing what it is.
    var inverted: MelodyGesture {
        var copy = self
        switch contour {
        case .ascend: copy.contour = .descend
        case .descend: copy.contour = .ascend
        case .arch: copy.contour = .valley
        case .valley: copy.contour = .arch
        case .leapFall: copy.contour = .fallLeap
        case .fallLeap: copy.contour = .leapFall
        default: break
        }
        return copy
    }
}
