//
//  Bassline.swift
//  MelGenExtension
//
//  Bass lines, drawn rather than written.
//
//  The shape of this is owed to Reason Studios' Bassline Generator, which does
//  something the rest of MelGen didn't: it separates *where the notes are* from
//  *which notes they are*, and gives you a continuous control over each. Its
//  on-beat and off-beat pattern banks, the pad that mixes between sources, a
//  single knob for how minor the result is, and a register range are all
//  reproduced here in MelGen's own terms. Nothing is ported — this is a
//  reimplementation of an idea, over a harmonic model that device doesn't have.
//
//  The one substantive difference is that the Bassline Generator works from a
//  key, and MelGen works from changes. Both are available: over a typed
//  progression each bar is read against whatever chord is sounding, and over a
//  key `DiatonicHarmony` supplies a single modal chord for the whole form, which
//  is the same machinery with one chord in it.
//
//  ## What this is made of
//
//  Three layers, and the interesting part is that none of them is new:
//
//  · **Rhythm** is a `BasslineFigure` — eight onset probabilities, lengths and
//    accents over a bar. Probabilities rather than a fixed mask, because that is
//    what makes mixing two figures mean something and what makes two bars of the
//    same figure differ.
//  · **Pitch** is `DegreeHistogram` and `TransitionHistogram`, multiplied by
//    `MelodicWalk`. The bass line's register, its preference for roots and
//    fifths, and its chromatic approaches are all settings on those two.
//  · **Mixing** is the diamond: four corner figures, a point inside, and a
//    weighted sum of their per-slot numbers.
//
//  ## Why this emits notes and not a pattern
//
//  Every other generator here produces a `MelodyPattern` — degrees, no register
//  — and lets `realize` place it. A bass line can't go through that gate without
//  losing the thing it is: folded realization keeps each note within an octave
//  of the last one, which is exactly the register decision the range control
//  exists to make, and stepwise realization can't carry a chromatic approach
//  without the alteration drifting through the "nearest scale member" step. So
//  the walk works in absolute pitch, inside a stated range, and the result is
//  read *back* into the pattern format by `MelodyPatterns.extract` — the same
//  route every take in this codebase already takes to become a stored line.
//  Nothing is lost: the material still ends up degree-relative, it just isn't
//  born that way.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

// MARK: - Figures

/// A rhythmic disposition for one bar, as probabilities rather than as a mask.
///
/// Eight slots, because the whole plug-in speaks eighths. Each slot carries how
/// likely a note is to start there, how long it would be, and how hard it is
/// struck — three vectors rather than one, because two figures can put notes in
/// the same places and still be nothing alike.
struct BasslineFigure: Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var summary: String
    /// Chance of an onset in each eighth of the bar, 0...1.
    var onsets: [Double]
    /// How long a note starting in each slot wants to be, in eighths.
    var lengths: [Double]
    /// Velocity offset for each slot, roughly −20...+20.
    var accents: [Double]
    /// How far up the note stack this figure leans, added to the reach dial.
    /// Negative keeps it on roots and fifths; positive lets colour in.
    var reachBias: Double
    /// How hard it insists on chord tones. 1 is neutral; above 1 anchors.
    var chordTonePull: Double

    init(_ name: String,
         _ summary: String,
         onsets: [Double],
         lengths: [Double],
         accents: [Double] = [],
         reachBias: Double = 0,
         chordTonePull: Double = 1) {
        self.name = name
        self.summary = summary
        self.onsets = BasslineFigure.eight(onsets, fill: 0)
        self.lengths = BasslineFigure.eight(lengths, fill: 2)
        self.accents = BasslineFigure.eight(accents, fill: 0)
        self.reachBias = reachBias
        self.chordTonePull = chordTonePull
    }

    /// Slots per bar. Eight, and named rather than written out, because the
    /// grid is a decision the whole codebase shares — see ROADMAP D1 on what
    /// changing it would take.
    static let slots = 8

    private static func eight(_ values: [Double], fill: Double) -> [Double] {
        guard !values.isEmpty else { return Array(repeating: fill, count: slots) }
        return (0..<slots).map { values[$0 % values.count] }
    }

    /// How much of the figure's weight falls off the beat.
    ///
    /// Measured rather than declared, so a figure can't claim to be syncopated
    /// and not be — which is the same gate `verify.sh templates` puts on a
    /// template that doesn't differ from the others.
    var offbeatShare: Double {
        let total = onsets.reduce(0, +)
        guard total > 0 else { return 0 }
        let off = onsets.enumerated().filter { $0.offset % 2 == 1 }.map(\.element).reduce(0, +)
        return off / total
    }
}

extension BasslineFigure {

    /// The on-beat bank: figures whose weight is on the beats.
    static let onBeatBank: [BasslineFigure] = [downbeats, halfNotes, walking, pedal]

    /// The off-beat bank: figures whose weight is between them.
    static let offBeatBank: [BasslineFigure] = [ands, charleston, tresillo, pushed]

    /// Quarter notes. The plainest bass line there is, and the one everything
    /// else is heard against.
    static let downbeats = BasslineFigure(
        "Downbeats",
        "A note on every beat",
        onsets: [1, 0, 0.95, 0, 1, 0, 0.9, 0],
        lengths: [2, 2, 2, 2, 2, 2, 2, 2],
        accents: [8, 0, -4, 0, 4, 0, -4, 0]
    )

    /// Two in a bar. Room around every note, so the harmony does the work.
    static let halfNotes = BasslineFigure(
        "Half notes",
        "Two in the bar, held",
        onsets: [1, 0, 0, 0, 0.9, 0, 0, 0.15],
        lengths: [4, 4, 4, 4, 4, 4, 4, 2],
        accents: [8, 0, 0, 0, 2, 0, 0, -6],
        reachBias: -0.15,
        chordTonePull: 1.6
    )

    /// Four on the beat and a lead-in to the next bar. Walking, in the sense
    /// the phrase is normally used: the interest is in where the notes go rather
    /// than in when they land.
    static let walking = BasslineFigure(
        "Walking",
        "On every beat, with a lead-in to the next bar",
        onsets: [1, 0, 0.95, 0, 0.95, 0, 0.95, 0.35],
        lengths: [2, 2, 2, 2, 2, 2, 2, 1],
        accents: [6, 0, -2, 0, 2, 0, -2, -4],
        reachBias: 0.2
    )

    /// One note, held. The floor of the whole diamond, and the thing a range
    /// control is easiest to hear on.
    static let pedal = BasslineFigure(
        "Pedal",
        "One note under the whole bar",
        onsets: [1, 0, 0, 0, 0, 0, 0, 0],
        lengths: [8, 8, 8, 8, 8, 8, 8, 8],
        accents: [6, 0, 0, 0, 0, 0, 0, 0],
        reachBias: -0.45,
        chordTonePull: 2.4
    )

    /// Every off-beat eighth. The most purely syncopated thing available and,
    /// alone, more of an axis end than a bass line.
    static let ands = BasslineFigure(
        "Ands",
        "Only between the beats",
        onsets: [0, 1, 0, 0.9, 0, 1, 0, 0.9],
        lengths: [1, 1, 1, 1, 1, 1, 1, 1],
        accents: [0, 4, 0, -2, 0, 4, 0, -2],
        reachBias: 0.1
    )

    /// The Charleston: the downbeat and the and of two. Half a century of bass
    /// lines start here.
    static let charleston = BasslineFigure(
        "Charleston",
        "The downbeat, and the push after beat two",
        onsets: [0.95, 0, 0, 0.9, 0, 0.2, 0, 0.3],
        lengths: [3, 2, 2, 3, 2, 2, 2, 2],
        accents: [8, 0, 0, 6, 0, -4, 0, -2],
        chordTonePull: 1.4
    )

    /// Three, three, two. The other half of the world's bass lines.
    static let tresillo = BasslineFigure(
        "Tresillo",
        "Three, three, two across the bar",
        onsets: [1, 0, 0, 0.95, 0, 0, 0.9, 0.1],
        lengths: [3, 2, 2, 3, 2, 2, 2, 2],
        accents: [8, 0, 0, 2, 0, 0, 4, -6]
    )

    /// Anticipations: everything arrives an eighth early.
    static let pushed = BasslineFigure(
        "Pushed",
        "Every landing arrives an eighth early",
        onsets: [0.25, 0.85, 0, 0.5, 0.2, 0.85, 0, 0.6],
        lengths: [1, 3, 2, 2, 1, 3, 2, 2],
        accents: [-4, 8, 0, 0, -4, 6, 0, 2],
        reachBias: 0.15
    )

    static func named(_ name: String, in bank: [BasslineFigure]) -> BasslineFigure {
        bank.first { $0.name == name } ?? bank[0]
    }

    /// Every figure either bank holds, for a picker that wants one list.
    static var all: [BasslineFigure] { onBeatBank + offBeatBank }
}

// MARK: - The diamond

/// Which corner of the diamond a figure sits at.
enum BasslineCorner: String, CaseIterable, Codable, Sendable {
    case onBeat, offBeat, anchored, running

    var label: String {
        switch self {
        case .onBeat: return "On the beat"
        case .offBeat: return "Off the beat"
        case .anchored: return "Anchored"
        case .running: return "Running"
        }
    }
}

/// Four figures, a point between them, and the figure that point names.
///
/// Two axes, because that is what a bass line has two of. North and south are
/// the on-beat and off-beat banks — the distinction the Bassline Generator makes
/// and the one that turned out to be worth copying, because it is the axis a
/// bass part is actually described along. East and west are how much of it there
/// is: a pedal at one end, eighths at the other. The centre is an even blend of
/// all four, which is a real place rather than a default, and the reason the
/// control is a pad rather than two sliders is that the interesting settings are
/// the ones between corners.
struct BasslineDiamond: Codable, Hashable, Sendable {
    /// −1 anchored, +1 running.
    var x: Double = 0
    /// −1 off the beat, +1 on it.
    var y: Double = 0.5
    /// Which figure from the on-beat bank sits north.
    var onBeatName: String = BasslineFigure.downbeats.name
    /// Which figure from the off-beat bank sits south.
    var offBeatName: String = BasslineFigure.tresillo.name

    init(x: Double = 0,
         y: Double = 0.5,
         onBeatName: String = BasslineFigure.downbeats.name,
         offBeatName: String = BasslineFigure.tresillo.name) {
        self.onBeatName = onBeatName
        self.offBeatName = offBeatName
        self.setPoint(x: x, y: y)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: try container.decodeIfPresent(Double.self, forKey: .x) ?? 0,
                  y: try container.decodeIfPresent(Double.self, forKey: .y) ?? 0.5,
                  onBeatName: try container.decodeIfPresent(String.self, forKey: .onBeatName)
                      ?? BasslineFigure.downbeats.name,
                  offBeatName: try container.decodeIfPresent(String.self, forKey: .offBeatName)
                      ?? BasslineFigure.tresillo.name)
    }

    /// Moves the point, clamped onto the diamond.
    ///
    /// A square would let both axes run to their extremes at once, which is a
    /// corner that means "entirely on the beat and entirely running" — two
    /// different figures claiming the whole mix. `|x| + |y| ≤ 1` is what makes
    /// the four weights a partition instead of a contradiction, and it is why
    /// the shape is a diamond rather than a pad.
    mutating func setPoint(x: Double, y: Double) {
        let x = max(-1, min(1, x))
        let y = max(-1, min(1, y))
        let magnitude = abs(x) + abs(y)
        if magnitude > 1 {
            self.x = x / magnitude
            self.y = y / magnitude
        } else {
            self.x = x
            self.y = y
        }
    }

    /// The figure at each corner.
    func figure(at corner: BasslineCorner) -> BasslineFigure {
        switch corner {
        case .onBeat: return BasslineFigure.named(onBeatName, in: BasslineFigure.onBeatBank)
        case .offBeat: return BasslineFigure.named(offBeatName, in: BasslineFigure.offBeatBank)
        case .anchored: return .pedal
        case .running: return .ands
        }
    }

    /// How much of each corner the current point asks for.
    ///
    /// Whatever the point doesn't spend on a direction is spread evenly over all
    /// four, so the centre is every corner at a quarter and the weights always
    /// sum to one.
    var weights: [BasslineCorner: Double] {
        let spare = max(0, 1 - abs(x) - abs(y)) / 4
        return [
            .onBeat: max(0, y) + spare,
            .offBeat: max(0, -y) + spare,
            .running: max(0, x) + spare,
            .anchored: max(0, -x) + spare
        ]
    }

    /// The mixed figure this point names.
    ///
    /// Per-slot arithmetic on all three vectors at once. Onsets and accents are
    /// plain weighted sums; lengths are weighted by *onset* share rather than by
    /// corner weight, because a corner that isn't going to put a note there has
    /// no business having an opinion about how long it is — which is what stopped
    /// the pedal's eight-eighth notes stretching every mix that included it.
    func mixed() -> BasslineFigure {
        let weights = self.weights
        var onsets = Array(repeating: 0.0, count: BasslineFigure.slots)
        var lengths = Array(repeating: 0.0, count: BasslineFigure.slots)
        var accents = Array(repeating: 0.0, count: BasslineFigure.slots)
        var lengthShare = Array(repeating: 0.0, count: BasslineFigure.slots)
        var reachBias = 0.0
        var chordTonePull = 0.0
        var names: [String] = []

        for corner in BasslineCorner.allCases {
            let weight = weights[corner] ?? 0
            guard weight > 0 else { continue }
            let figure = figure(at: corner)
            if weight > 0.2 { names.append(figure.name) }
            reachBias += figure.reachBias * weight
            chordTonePull += figure.chordTonePull * weight
            for slot in 0..<BasslineFigure.slots {
                let contribution = figure.onsets[slot] * weight
                onsets[slot] += contribution
                accents[slot] += figure.accents[slot] * weight
                lengths[slot] += figure.lengths[slot] * contribution
                lengthShare[slot] += contribution
            }
        }

        for slot in 0..<BasslineFigure.slots {
            lengths[slot] = lengthShare[slot] > 0 ? lengths[slot] / lengthShare[slot] : 2
        }

        return BasslineFigure(
            names.isEmpty ? "Mixed" : names.joined(separator: " + "),
            "mixed at \(Int((x * 100).rounded()))% running, \(Int((y * 100).rounded()))% on the beat",
            onsets: onsets,
            lengths: lengths,
            accents: accents,
            reachBias: reachBias,
            chordTonePull: max(0.2, chordTonePull)
        )
    }
}

// MARK: - Settings

/// Everything that decides what the next bass line is like.
struct BasslineSettings: Codable, Hashable, Sendable {

    /// Where the notes go.
    var diamond = BasslineDiamond()

    /// Whether the harmony is the typed changes or a key.
    ///
    /// Both, rather than one: the Bassline Generator's model is a key, MelGen's
    /// is a progression, and a bass part wants whichever the rest of the track
    /// has. Over changes the histograms are rebuilt per chord; over a key they
    /// are built once.
    var overKey: Bool = false
    /// Tonic pitch class, when the harmony is a key.
    var key: Int = 0
    /// How far down the modal brightness ladder the key sits. See
    /// `DiatonicHarmony` — 0 is Lydian, 0.5 Dorian, 1 Locrian.
    var minorness: Double = 0.5
    /// How long the form is, when the harmony is a key rather than changes.
    var bars: Int = 4

    /// How far up the note stack the line reaches: root, fifth, third, seventh,
    /// eleventh, ninth, thirteenth. See `DegreeHistogram.stack(over:reach:)`.
    var reach: Double = 0.3
    /// How much weight the notes outside the scale get.
    var outside: Double = 0.04
    /// How much of the pitch material comes from the side-slipped pentatonic.
    /// See `DegreeHistogram.sideSlip(over:slip:)`.
    var sideSlip: Double = 0
    /// How much the transitions like semitones — and, with `momentum`, how
    /// readily a chromatic approach becomes a run.
    var chromaticism: Double = 0.15
    /// How much a move that continues the last one is favoured.
    var momentum: Double = 0.5
    /// How much the line leaps rather than steps.
    var leapiness: Double = 0.35

    /// The register the line is kept in, as MIDI note numbers.
    var lowNote: Int = 28
    var highNote: Int = 52

    /// Scales every onset probability. 1 plays the figure as written.
    var density: Double = 1

    /// Which of the eight seeds is in play.
    ///
    /// Eight, the way a step sequencer has eight memories — except that nothing
    /// is stored, because a draw *is* its seed. They cost nothing to have and
    /// every one of them can be got back exactly.
    ///
    /// Called a seed rather than a variant on purpose: TERMINOLOGY.md already
    /// spends the word "variant" on a named transform of a take, offered with
    /// its scores, and these are not that. They are eight draws of one setting.
    var seedIndex: Int = 0
    /// A dial from this seed's draw into the next one's.
    ///
    /// The Bassline Generator switches between its variations; this morphs
    /// through them, which is Troublemaker's model and the better one for a
    /// part that has to develop rather than just change. Note by note, so a
    /// half-morph is a line that is genuinely half of each rather than a
    /// crossfade between two of them.
    var morph: Double = 0

    static let seedCount = 8

    var range: ClosedRange<Int> {
        let low = min(lowNote, highNote)
        let high = max(lowNote, highNote)
        return low...max(low + 11, high)
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        diamond = try container.decodeIfPresent(BasslineDiamond.self, forKey: .diamond) ?? BasslineDiamond()
        overKey = try container.decodeIfPresent(Bool.self, forKey: .overKey) ?? false
        key = try container.decodeIfPresent(Int.self, forKey: .key) ?? 0
        minorness = try container.decodeIfPresent(Double.self, forKey: .minorness) ?? 0.5
        bars = try container.decodeIfPresent(Int.self, forKey: .bars) ?? 4
        reach = try container.decodeIfPresent(Double.self, forKey: .reach) ?? 0.3
        outside = try container.decodeIfPresent(Double.self, forKey: .outside) ?? 0.04
        sideSlip = try container.decodeIfPresent(Double.self, forKey: .sideSlip) ?? 0
        chromaticism = try container.decodeIfPresent(Double.self, forKey: .chromaticism) ?? 0.15
        momentum = try container.decodeIfPresent(Double.self, forKey: .momentum) ?? 0.5
        leapiness = try container.decodeIfPresent(Double.self, forKey: .leapiness) ?? 0.35
        lowNote = try container.decodeIfPresent(Int.self, forKey: .lowNote) ?? 28
        highNote = try container.decodeIfPresent(Int.self, forKey: .highNote) ?? 52
        density = try container.decodeIfPresent(Double.self, forKey: .density) ?? 1
        seedIndex = try container.decodeIfPresent(Int.self, forKey: .seedIndex) ?? 0
        morph = try container.decodeIfPresent(Double.self, forKey: .morph) ?? 0
    }

    /// What the settings say, in one line, for the history row and the button.
    var summary: String {
        let harmony = overKey
            ? "\(ChordProgression.flatNoteNames[ChordScales.pitchClass(key)]) \(DiatonicHarmony.label(forMinorness: minorness).lowercased())"
            : "the changes"
        return "\(diamond.mixed().name.lowercased()) over \(harmony), "
             + "\(ChordProgression.noteName(forMIDINote: range.lowerBound))–"
             + "\(ChordProgression.noteName(forMIDINote: range.upperBound))"
    }
}

extension BasslineSettings {

    /// The same settings with a figure moved onto the diamond.
    ///
    /// Which corner it lands at is a property of the figure rather than a choice
    /// — that is what the two banks *are* — so selecting a bass template is one
    /// tap and never asks a follow-up question. Selecting one also pulls the
    /// point toward that corner, because putting a figure on a diamond that is
    /// nowhere near it changes nothing audible and reads as the control being
    /// broken.
    func placing(_ figure: BasslineFigure) -> BasslineSettings {
        var copy = self
        if BasslineFigure.onBeatBank.contains(where: { $0.name == figure.name }) {
            copy.diamond.onBeatName = figure.name
            copy.diamond.setPoint(x: diamond.x, y: max(diamond.y, 0.4))
        } else {
            copy.diamond.offBeatName = figure.name
            copy.diamond.setPoint(x: diamond.x, y: min(diamond.y, -0.4))
        }
        return copy
    }

    /// The figure currently doing most of the work, for a subtitle.
    var leadingFigure: BasslineFigure {
        diamond.figure(at: diamond.y < 0 ? .offBeat : .onBeat)
    }
}

// MARK: - Generating

enum BasslineGenerator {

    /// The harmony a set of settings describes: the typed changes, or the key.
    static func progression(for settings: BasslineSettings,
                            changes: ChordProgression?) -> ChordProgression? {
        if settings.overKey || changes == nil {
            return DiatonicHarmony.progression(key: settings.key,
                                               minorness: settings.minorness,
                                               bars: max(1, settings.bars))
        }
        return changes
    }

    /// The pitch material for a chord, under these settings.
    ///
    /// Three histograms blended: the stack, the side-slipped pentatonic, and —
    /// when the harmony is a key rather than a chord — the modal blend across
    /// whichever two rungs the minorness falls between. Built per chord, which
    /// is what a progression buys over a key and what makes the same settings
    /// sound different over `Dm7 G7` than over one modal vamp.
    static func degrees(for settings: BasslineSettings,
                        context: DegreeContext,
                        figure: BasslineFigure) -> DegreeHistogram {
        let reach = max(0, min(1, settings.reach + figure.reachBias))
        var histogram = settings.overKey
            ? DiatonicHarmony.degrees(key: settings.key,
                                      minorness: settings.minorness,
                                      reach: reach)
            : DegreeHistogram.stack(over: context, reach: reach)

        if settings.sideSlip > 0 {
            histogram = histogram.blended(
                with: DegreeHistogram.sideSlip(over: context, slip: 0.5),
                min(1, settings.sideSlip))
        }
        if settings.outside > 0 {
            histogram = histogram.opening(to: context, by: settings.outside)
        }
        if figure.chordTonePull != 1 {
            histogram = histogram.emphasising(chordTonesOf: context, by: figure.chordTonePull)
        }
        return histogram
    }

    /// How the line moves, under these settings.
    static func transitions(for settings: BasslineSettings) -> TransitionHistogram {
        let steps = TransitionHistogram.stepwise(leapiness: settings.leapiness, repeats: 0.12)
        // The arpeggio weights are what stop a bass line being a scale: roots to
        // fifths to octaves is how the instrument moves, and an exponential over
        // interval size on its own never produces it.
        let arpeggios = TransitionHistogram.arpeggiating(reach: settings.leapiness)
        var histogram = TransitionHistogram.mix([(steps, 0.55), (arpeggios, 0.45)])
        if settings.chromaticism > 0 {
            histogram = histogram.blended(with: TransitionHistogram.chromatic(),
                                          min(0.6, settings.chromaticism))
        }
        return histogram
    }

    /// One bass line.
    ///
    /// - Parameters:
    ///   - changes: the typed progression, or nil to work from the key alone.
    ///   - seed: everything random comes from here, so a line can be got back.
    static func line(_ settings: BasslineSettings,
                     over changes: ChordProgression?,
                     seed: UInt64) -> [SequencedNote] {
        guard let progression = progression(for: settings, changes: changes),
              progression.totalBeats > 0 else { return [] }

        let first = draw(settings, over: progression, seed: seed, index: settings.seedIndex)
        guard settings.morph > 0.001 else { return first }

        let next = draw(settings, over: progression, seed: seed,
                        index: settings.seedIndex + 1)
        return morph(first, into: next, mix: settings.morph,
                     range: settings.range, totalBeats: progression.totalBeats)
    }

    /// One seed's draw, without the morph.
    private static func draw(_ settings: BasslineSettings,
                             over progression: ChordProgression,
                             seed: UInt64,
                             index: Int) -> [SequencedNote] {
        let figure = settings.diamond.mixed()
        let transitions = transitions(for: settings)
        let range = settings.range
        let bars = Int(ceil(progression.totalBeats / MelodyPatterns.beatsPerBar))

        var rng = SplitMix64(seed: seed
            &* 0x9E3779B97F4A7C15
            &+ UInt64(bitPattern: Int64(index % BasslineSettings.seedCount &+ 1) &* 0x2545_F491))
        var notes: [SequencedNote] = []
        var pitch: Int?
        var previousInterval: Int?
        var previousChordStart: Double?

        for bar in 0..<max(1, bars) {
            for slot in 0..<BasslineFigure.slots {
                // A fixed draw budget per slot whether or not it fires, so two
                // settings sampled at one seed stay comparable — the aligned
                // streams discipline the slot model and the chain both keep.
                let onsetDraw = rng.nextUnit()
                let pitchDraw = rng.nextUnit()
                let lengthDraw = rng.nextUnit()

                let startBeat = Double(bar) * MelodyPatterns.beatsPerBar + Double(slot) / 2
                guard startBeat < progression.totalBeats - 0.001 else { continue }
                guard let placed = progression.chord(at: startBeat) else { continue }

                let chance = min(1, figure.onsets[slot] * max(0, settings.density))
                let isSeam = placed.startBeat != previousChordStart
                // A chord change always gets a note. Not a preference: a bass
                // line that misses the downbeat of a new chord leaves the
                // harmony unstated, and no amount of the right notes afterwards
                // recovers it.
                guard onsetDraw < chance || (isSeam && startBeat >= placed.startBeat - 0.001
                                             && startBeat < placed.startBeat + 0.5) else { continue }

                let context = DegreeContext(chord: placed.symbol)
                var histogram = degrees(for: settings, context: context, figure: figure)
                // Strong slots want the chord itself; the ones in between are
                // where the passing material belongs. One histogram, leaned two
                // ways, rather than two histograms to keep in step.
                if slot % 2 == 0 {
                    histogram = histogram.emphasising(chordTonesOf: context,
                                                      by: isSeam ? 3 : 1.6)
                }
                // And at a change, the root above the other chord tones. This is
                // the one thing a bass part does that a line doesn't: the chord
                // is named by whoever is lowest, and a bass that arrives on the
                // third of every chord has left the harmony ambiguous even
                // though every note it played belonged. Not forced — a walking
                // line that reaches the new chord by its fifth is idiomatic and
                // this only makes the root the likeliest arrival, not the only
                // one.
                if isSeam {
                    histogram = histogram.boosting([0], by: 2.2)
                }

                let next: Int?
                if let pitch {
                    next = MelodicWalk.next(from: pitch,
                                            previousInterval: previousInterval,
                                            degrees: histogram,
                                            context: context,
                                            transitions: transitions,
                                            momentum: settings.momentum,
                                            range: range,
                                            draw: pitchDraw)
                } else {
                    // Start low in the range: a bass line that opens in its top
                    // octave has nowhere to go but up.
                    next = MelodicWalk.start(degrees: histogram,
                                             context: context,
                                             range: range,
                                             near: range.lowerBound + 3,
                                             draw: pitchDraw)
                }
                guard let landed = next else { continue }

                previousInterval = pitch.map { landed - $0 }
                pitch = landed
                previousChordStart = placed.startBeat

                // Length varies around what the figure asks for, then is clipped
                // to the form. Clipping to the *next note* happens once at the
                // end, because what the next note is isn't known yet.
                let wanted = figure.lengths[slot] * (0.75 + lengthDraw * 0.5)
                let lengthBeats = max(0.25, wanted / 2)
                let velocity = min(120, max(30, 88 + Int(figure.accents[slot].rounded())))

                notes.append(SequencedNote(
                    note: UInt8(clamping: landed),
                    velocity: UInt8(clamping: velocity),
                    startBeat: startBeat,
                    durationBeats: min(lengthBeats, progression.totalBeats - startBeat)
                ))
            }
        }

        return monophonic(notes)
    }

    /// Keeps the line strictly monophonic: a bass part is one voice.
    private static func monophonic(_ notes: [SequencedNote]) -> [SequencedNote] {
        var ordered = notes.sorted { $0.startBeat < $1.startBeat }
        for index in ordered.indices.dropLast() {
            let gap = ordered[index + 1].startBeat - ordered[index].startBeat
            ordered[index].durationBeats = max(0.1, min(ordered[index].durationBeats, gap))
        }
        return ordered
    }

    /// Dials from one seed's draw into the next, note by note.
    ///
    /// Aligned proportionally rather than by onset, the same way
    /// `MelodyMutations.between` aligns two patterns — two lines worth morphing
    /// between rarely put their notes in the same places, and an alignment that
    /// only matches exact coincidences produces a crossfade. Done here rather
    /// than by reusing that function because a bass line's whole point is the
    /// register it sits in, and the pattern format doesn't carry one.
    static func morph(_ from: [SequencedNote],
                      into to: [SequencedNote],
                      mix: Double,
                      range: ClosedRange<Int>,
                      totalBeats: Double) -> [SequencedNote] {
        let mix = max(0, min(1, mix))
        guard !from.isEmpty else { return to }
        guard !to.isEmpty else { return from }

        let count = max(1, Int((Double(from.count) * (1 - mix) + Double(to.count) * mix).rounded()))
        var morphed: [SequencedNote] = []

        for index in 0..<count {
            let position = count == 1 ? 0 : Double(index) / Double(count - 1)
            let left = from[min(from.count - 1, Int((position * Double(from.count - 1)).rounded()))]
            let right = to[min(to.count - 1, Int((position * Double(to.count - 1)).rounded()))]

            let start = left.startBeat * (1 - mix) + right.startBeat * mix
            let duration = left.durationBeats * (1 - mix) + right.durationBeats * mix
            let pitch = Double(left.note) * (1 - mix) + Double(right.note) * mix
            let velocity = Double(left.velocity) * (1 - mix) + Double(right.velocity) * mix

            morphed.append(SequencedNote(
                note: UInt8(clamping: MelodicWalk.fold(Int(pitch.rounded()), into: range)),
                velocity: UInt8(clamping: Int(velocity.rounded())),
                startBeat: min(start, max(0, totalBeats - 0.25)),
                durationBeats: max(0.1, duration)
            ))
        }

        // The blend can put two notes on one grid position; a bass part is one
        // voice, so the later one wins and the earlier is dropped rather than
        // being shortened to nothing.
        var deduplicated: [SequencedNote] = []
        for note in morphed.sorted(by: { $0.startBeat < $1.startBeat }) {
            if let last = deduplicated.last, abs(last.startBeat - note.startBeat) < 0.12 {
                deduplicated[deduplicated.count - 1] = note
            } else {
                deduplicated.append(note)
            }
        }
        return monophonic(deduplicated)
    }
}
