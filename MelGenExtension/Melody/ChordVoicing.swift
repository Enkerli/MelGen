//
//  ChordVoicing.swift
//  MelGenExtension
//
//  The layer between a chord's pitch classes and something a keyboard would play.
//
//  The shared dictionary says which pitch classes a chord contains. That is not a
//  voicing, and the gap between the two is most of what makes comping sound like
//  comping: register, spacing, which tones are left out, which are doubled,
//  whether the bass is there at all, and — above everything — how one voicing
//  moves to the next.
//
//  Two decisions worth stating.
//
//  *Tones are classified by interval, not by position in a list.* It would be
//  shorter to say "the second entry is the third", and it would break on every
//  suspended, quartal and altered chord in the dictionary, which is a large
//  fraction of the interesting ones. Asking "which of these is three or four
//  semitones above the root" costs nothing and is right everywhere.
//
//  *Voice leading is the point, not a refinement.* A sequence of individually
//  good voicings played in sequence sounds like a chord chart being read aloud.
//  What makes it sound played is that the notes barely move — common tones held,
//  everything else going to its nearest neighbour — so the voicings here are
//  generated as a *sequence* by default and the single-chord call is the special
//  case rather than the other way round.
//
//  This is the layer ROADMAP I1 wants shared with the rest of the suite; it's
//  written to be portable and depends on nothing but the chord dictionary.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

/// How a chord is laid out under the hands.
enum VoicingStyle: String, Codable, CaseIterable, Sendable {
    /// Root, third, seventh. The smallest thing that states the chord, and what
    /// a guitarist plays behind a soloist.
    case shell
    /// Third, fifth, seventh, ninth — no root, because the bass has it. The
    /// standard left hand.
    case rootlessA
    /// Seventh, ninth, third, fifth: the same notes, the other inversion, so
    /// alternating A and B down a progression voice-leads itself.
    case rootlessB
    /// A close voicing with the second voice from the top dropped an octave.
    /// Opens the spacing without changing a note.
    case drop2
    /// Stacked fourths. Modal, deliberately vague about quality.
    case quartal
    /// Everything inside an octave. Dense, and right for a pad.
    case close

    var label: String {
        switch self {
        case .shell: return "Shell"
        case .rootlessA: return "Rootless A"
        case .rootlessB: return "Rootless B"
        case .drop2: return "Drop 2"
        case .quartal: return "Quartal"
        case .close: return "Close"
        }
    }

    var summary: String {
        switch self {
        case .shell: return "Root, third and seventh — states the chord and nothing else"
        case .rootlessA: return "Third, fifth, seventh, ninth — the standard left hand"
        case .rootlessB: return "The same notes inverted, so A and B alternate down a progression"
        case .drop2: return "Close voicing with the second voice dropped an octave"
        case .quartal: return "Stacked fourths — modal, and vague about quality on purpose"
        case .close: return "Everything inside an octave; dense, good for a pad"
        }
    }
}

/// One chord, laid out.
struct Voicing: Hashable, Sendable {
    var pitches: [Int]
    var style: VoicingStyle
    var symbolText: String
    /// The bass note, when it's included. Separate because it's usually played
    /// by something else.
    var bass: Int?

    var isEmpty: Bool { pitches.isEmpty }
    var span: Int { (pitches.max() ?? 0) - (pitches.min() ?? 0) }
}

enum ChordVoicings {

    /// Where the right hand sits by default — around middle C to the C above.
    static let defaultCentre = 62
    static let range = 40...88

    // MARK: - Classifying tones

    /// Which interval above the root each of a chord's pitch classes is.
    static func intervals(of symbol: ChordSymbol) -> [Int] {
        symbol.tonePitchClasses.map { (($0 - symbol.rootPitchClass) % 12 + 12) % 12 }
    }

    /// The chord's third, whatever kind it is — including a suspended fourth
    /// standing in for one, which is what makes this work on `sus` chords.
    static func third(of symbol: ChordSymbol) -> Int? {
        let intervals = intervals(of: symbol)
        return intervals.first { $0 == 3 || $0 == 4 }
            ?? intervals.first { $0 == 2 || $0 == 5 }
    }

    static func fifth(of symbol: ChordSymbol) -> Int? {
        intervals(of: symbol).first { (6...8).contains($0) }
    }

    static func seventh(of symbol: ChordSymbol) -> Int? {
        intervals(of: symbol).first { $0 == 10 || $0 == 11 } ?? intervals(of: symbol).first { $0 == 9 }
    }

    /// The most characteristic colour note the chord offers, as an interval.
    static func colour(of symbol: ChordSymbol) -> Int? {
        let tensions = symbol.tensionPitchClasses.map { (($0 - symbol.rootPitchClass) % 12 + 12) % 12 }
        // A ninth first, then anything else the chord offers: the ninth is the
        // one that reads as colour rather than as a wrong note.
        return tensions.first { $0 == 1 || $0 == 2 || $0 == 3 }
            ?? tensions.first { $0 == 9 || $0 == 8 }
            ?? tensions.first
    }

    // MARK: - One chord

    /// Lays a chord out in the given style, near a register centre.
    ///
    /// Falls back rather than failing: a chord with no seventh can't be voiced
    /// rootless, and returning nothing would leave a hole in the comp, so it
    /// takes the nearest style that works. Music, not an assertion failure.
    static func voice(_ symbol: ChordSymbol,
                      style: VoicingStyle = .rootlessA,
                      centre: Int = defaultCentre,
                      includeBass: Bool = false) -> Voicing {
        let root = symbol.rootPitchClass
        let third = third(of: symbol)
        let fifth = fifth(of: symbol)
        let seventh = seventh(of: symbol)
        let colour = colour(of: symbol)

        var intervals: [Int]
        switch style {
        case .shell:
            intervals = [0, third, seventh].compactMap { $0 }
        case .rootlessA:
            intervals = [third, fifth, seventh, colour.map { $0 + 12 }].compactMap { $0 }
            if intervals.count < 3 { intervals = [0, third, fifth, seventh].compactMap { $0 } }
        case .rootlessB:
            intervals = [seventh, colour.map { $0 + 12 }, third.map { $0 + 12 }, fifth.map { $0 + 12 }]
                .compactMap { $0 }
            if intervals.count < 3 { intervals = [0, third, fifth, seventh].compactMap { $0 } }
        case .close:
            intervals = [0, third, fifth, seventh].compactMap { $0 }
        case .drop2:
            var close = [0, third, fifth, seventh].compactMap { $0 }.sorted()
            if close.count >= 3 {
                // Drop the second voice from the top an octave. The whole
                // technique, in one line.
                close[close.count - 2] -= 12
            }
            intervals = close
        case .quartal:
            // *Scale* fourths, not perfect ones. Stacking three perfect fourths
            // from the third of a minor seventh chord walks straight out of the
            // key — F B♭ E♭ A♭ over Dm7 — which is a different chord rather than
            // a voicing of this one. Stepping three scale degrees at a time keeps
            // the ambiguity that makes quartal harmony worth having and keeps it
            // inside the mode.
            let scale = symbol.scalePitchClasses
                .map { (($0 - root) % 12 + 12) % 12 }
                .sorted()
            if scale.count >= 4 {
                let start = scale.firstIndex(of: third ?? scale[0]) ?? 0
                intervals = (0..<4).map { step -> Int in
                    let position = start + step * 3
                    return scale[position % scale.count] + 12 * (position / scale.count)
                }
            } else {
                intervals = [0, third, fifth, seventh].compactMap { $0 }
            }
        }

        guard !intervals.isEmpty else {
            return Voicing(pitches: [], style: style, symbolText: symbol.text, bass: nil)
        }

        // Place the stack so its *centre of gravity* sits near the register
        // centre. Anchoring on the lowest note instead puts a wide quartal
        // stack an octave too high, because the thing that has to be in the
        // right place is the voicing, not its bottom note.
        let raw = intervals.map { root + $0 }
        let mean = raw.reduce(0, +) / max(1, raw.count)
        var octave = 0
        while mean + 12 * octave + 60 < centre - 6 { octave += 1 }
        while mean + 12 * octave + 60 > centre + 6 { octave -= 1 }

        let pitches = raw
            .map { $0 + 60 + 12 * octave }
            .map { min(max($0, range.lowerBound), range.upperBound) }
            .sorted()

        var bass: Int?
        if includeBass {
            let bassClass = symbol.bassPitchClass ?? root
            var note = bassClass + 36
            while note < (pitches.min() ?? 60) - 24 { note += 12 }
            bass = min(max(note, range.lowerBound), range.upperBound)
        }

        return Voicing(pitches: Array(Set(pitches)).sorted(),
                       style: style,
                       symbolText: symbol.text,
                       bass: bass)
    }

    // MARK: - A sequence

    /// Voices a whole progression, keeping the movement between chords small.
    ///
    /// This is the part that makes it sound played. Each voicing after the first
    /// keeps its pitch classes but chooses octaves that put every voice as close
    /// as possible to the voice it's replacing — common tones end up not moving
    /// at all, which is what a player does without thinking about it.
    /// - Parameter leading: which of the two kinds of leading to apply. See
    ///   `VoiceLeadingMode`; `register` keeps the style's shape and moves the
    ///   whole voicing, `smooth` sends each voice to its nearest target tone.
    static func voiceLead(_ progression: ChordProgression,
                          style: VoicingStyle = .rootlessA,
                          centre: Int = defaultCentre,
                          includeBass: Bool = false,
                          leading: VoiceLeadingMode = .register) -> [Voicing] {
        var previous: [Int]?
        return progression.chords.map { placed in
            var voicing = voice(placed.symbol, style: style, centre: centre, includeBass: includeBass)
            voicing.pitches = lead(from: previous, to: voicing.pitches, centre: centre, mode: leading)
            previous = voicing.pitches
            return voicing
        }
    }

    /// Applies whichever kind of leading was asked for.
    ///
    /// The style still decides *which* notes are in the chord — a rootless
    /// voicing has no root whichever way it is led, a quartal one is still
    /// fourths. What the leading decides is where those notes sit. Keeping that
    /// division is what lets the two modes be a choice rather than two
    /// half-finished voicers.
    static func lead(from previous: [Int]?,
                     to target: [Int],
                     centre: Int,
                     mode: VoiceLeadingMode) -> [Int] {
        guard let previous, !previous.isEmpty, !target.isEmpty else { return target }
        switch mode {
        case .none:
            return target
        case .register:
            return lead(from: previous, to: target, centre: centre)
        case .smooth:
            let led = VoiceLeading.led(from: previous,
                                       to: target.map { (($0 % 12) + 12) % 12 },
                                       range: range)
            // A leading that lost a voice is worse than no leading: a comp that
            // thins itself chord by chord ends up as a two-note part.
            return led.count >= min(target.count, 3) ? led : lead(from: previous, to: target, centre: centre)
        }
    }

    /// Puts a voicing in the register that moves least from the one before it.
    ///
    /// The whole voicing shifts by octaves as a unit rather than each voice being
    /// re-placed independently. That's deliberate, and it took a probe to see
    /// why: re-placing voices individually finds a lower total movement and
    /// destroys the voicing while doing it, because the thing that makes a
    /// rootless A a rootless A is its internal spacing. A player picks the
    /// register, not the arrangement — the arrangement was decided when they
    /// chose the voicing.
    ///
    /// Cost is the distance from each new note to the nearest note of the
    /// previous chord, so a held common tone costs nothing, which is exactly the
    /// property worth optimising for.
    static func lead(from previous: [Int], to target: [Int], centre: Int) -> [Int] {
        guard !previous.isEmpty, !target.isEmpty else { return target }

        func cost(_ shift: Int) -> Int {
            target.reduce(0) { total, pitch in
                let moved = pitch + shift
                guard range.contains(moved) else { return total + 96 }
                let nearest = previous.map { abs(moved - $0) }.min() ?? 12
                return total + nearest
            }
        }

        let shifts = [-24, -12, 0, 12, 24]
        let best = shifts.min { left, right in
            let leftCost = cost(left), rightCost = cost(right)
            if leftCost != rightCost { return leftCost < rightCost }
            // Tie: stay nearer the register centre rather than drifting.
            let leftCentre = abs((target.map { $0 + left }.reduce(0, +) / target.count) - centre)
            let rightCentre = abs((target.map { $0 + right }.reduce(0, +) / target.count) - centre)
            return leftCentre < rightCentre
        } ?? 0

        return target.map { min(max($0 + best, range.lowerBound), range.upperBound) }.sorted()
    }
}
