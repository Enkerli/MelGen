//
//  MelodyComping.swift
//  MelGenExtension
//
//  Chords instead of a line — and the reason it's a mode rather than a setting.
//
//  A mono synth handed comping chords plays whichever note wins its note-priority
//  rule, which is not music. The receiving instrument differs, so the mode has to
//  be explicit and visible: this is the one decision in the plug-in that changes
//  what you should plug it into.
//
//  What it needed turned out to be less than expected. The kernel is already
//  polyphonic — sixty-four active notes, and sequence entries are scheduled
//  independently, so two entries sharing a start beat simply both sound. Nothing
//  in the DSP changed. The realization axis is unchanged too: expression, swing
//  and gate all operate on `SequencedNote`s and don't care how many of them start
//  at once.
//
//  So a comping figure is exactly what ROADMAP P4 guessed it was: **a rhythm plus
//  a voicing policy**. The rhythms are the same `GestureRhythm` vocabulary the
//  melodic side uses — a charleston is a charleston whether it's one note or
//  four — which means the two modes share their sense of time rather than having
//  two unrelated ideas of it.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

/// A comping pattern: when to play, and what to play when you do.
struct CompingFigure: Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var summary: String
    /// When the chords land. Reused from the melodic vocabulary on purpose.
    var rhythm: GestureRhythm
    /// How the chords are laid out.
    var style: VoicingStyle
    /// Whether alternate chords swap to the other rootless inversion, which is
    /// how a left hand voice-leads down a ii–V–I without thinking about it.
    var alternatesInversion: Bool
    /// Whether to include a bass note.
    var includeBass: Bool
    /// How many of the figure's onsets get the full voicing; the rest get the
    /// top two voices only, which is what a player does on the weak hits.
    var fullVoicingShare: Double

    init(_ name: String,
         _ summary: String,
         rhythm: GestureRhythm,
         style: VoicingStyle = .rootlessA,
         alternatesInversion: Bool = true,
         includeBass: Bool = false,
         fullVoicingShare: Double = 0.6) {
        self.name = name
        self.summary = summary
        self.rhythm = rhythm
        self.style = style
        self.alternatesInversion = alternatesInversion
        self.includeBass = includeBass
        self.fullVoicingShare = fullVoicingShare
    }
}

extension CompingFigure {

    static let all: [CompingFigure] = [charleston, freddie, pad, stabs, bossa, tresilloComp]

    /// The downbeat and the and-of-two, and nothing else. The most-played comping
    /// figure in the idiom, and the one that leaves the most room.
    static let charleston = CompingFigure(
        "Charleston",
        "Beat one and the and of two — the classic, and mostly air",
        rhythm: .charleston,
        style: .rootlessA
    )

    /// Every offbeat, quietly. Named for the way Freddie Green's part functions
    /// rather than for what he actually played, which was four to the bar.
    static let freddie = CompingFigure(
        "Offbeat shells",
        "A shell on every offbeat, light and continuous",
        rhythm: .even,
        style: .shell,
        alternatesInversion: false,
        fullVoicingShare: 0.35
    )

    /// One voicing, held. What a synth pad wants and what a comping algorithm
    /// usually gets wrong by being busier than the music needs.
    static let pad = CompingFigure(
        "Pad",
        "One voicing per chord, held for as long as it lasts",
        rhythm: .longWithAir,
        style: .close,
        alternatesInversion: false,
        includeBass: true,
        fullVoicingShare: 1
    )

    /// Short, hard, off the beat.
    static let stabs = CompingFigure(
        "Stabs",
        "Short chords off the beat, with silence around them",
        rhythm: .pushedPair,
        style: .drop2,
        fullVoicingShare: 0.8
    )

    /// The bossa pattern: anticipations across the bar line.
    static let bossa = CompingFigure(
        "Bossa",
        "Anticipated, tied across the bar, never quite on the beat",
        rhythm: .tiedOverTheBar,
        style: .rootlessB,
        includeBass: true
    )

    /// 3+3+2 as a comping figure rather than a melodic one.
    static let tresilloComp = CompingFigure(
        "Tresillo",
        "Three, three, two — the cell, played as chords",
        rhythm: .tresillo,
        style: .quartal,
        alternatesInversion: false,
        fullVoicingShare: 0.5
    )
}

enum MelodyComping {

    static let beatsPerBar: Double = 4

    /// Comps a progression.
    ///
    /// The voicings are led through the whole progression first and *then*
    /// rhythmicized, rather than being chosen chord by chord as the rhythm asks
    /// for them. That ordering is the difference between a comp that moves and
    /// one that jumps: voice leading is a property of the sequence, so it has to
    /// be decided over the sequence.
    /// - Parameter leading: how each voicing relates to the one before it.
    ///   Smooth by default, because the complaint that a comp sounds like "the
    ///   same voicing over and over" is exactly what register-only leading
    ///   produces: every chord is one shape transposed, so the top voice tracks
    ///   the root and nothing is heard to move.
    static func comp(_ progression: ChordProgression,
                     figure: CompingFigure = .charleston,
                     centre: Int = ChordVoicings.defaultCentre,
                     seed: UInt64 = 0x60D,
                     gate: Double = 0.9,
                     leading: VoiceLeadingMode = .smooth) -> [SequencedNote] {
        guard progression.totalBeats > 0, !progression.chords.isEmpty else { return [] }
        var rng = SplitMix64(seed: seed)

        // Alternating the rootless inversion is what voice-leads a ii–V–I; doing
        // it before the lead pass means the lead pass has less work to do and the
        // result keeps the idiom's shape.
        var voicings: [Voicing] = []
        var previous: [Int]?
        for (index, placed) in progression.chords.enumerated() {
            let style: VoicingStyle
            if figure.alternatesInversion, figure.style == .rootlessA || figure.style == .rootlessB {
                style = index.isMultiple(of: 2) ? .rootlessA : .rootlessB
            } else {
                style = figure.style
            }
            var voicing = ChordVoicings.voice(placed.symbol,
                                              style: style,
                                              centre: centre,
                                              includeBass: figure.includeBass)
            voicing.pitches = ChordVoicings.lead(from: previous, to: voicing.pitches,
                                                 centre: centre, mode: leading)
            previous = voicing.pitches
            voicings.append(voicing)
        }

        var notes: [SequencedNote] = []
        let totalEighths = Int((progression.totalBeats * 2).rounded())
        let cycle = max(1, figure.rhythm.spanEighths)

        var onset = 0
        var hit = 0
        while onset < totalEighths {
            for (index, position) in figure.rhythm.positions.enumerated() {
                let eighth = onset + position
                guard eighth < totalEighths else { continue }
                let beat = Double(eighth) / 2

                guard let chordIndex = progression.chords.firstIndex(where: {
                    beat >= $0.startBeat - 0.001 && beat < $0.startBeat + $0.durationBeats - 0.001
                }) else { continue }
                let voicing = voicings[chordIndex]
                guard !voicing.isEmpty else { continue }

                // Weak hits get the top of the voicing only — which is what a
                // player does, and what stops a comp sounding like a sequencer
                // playing the same block over and over.
                let full = rng.nextUnit() < figure.fullVoicingShare
                var pitches = full ? voicing.pitches : Array(voicing.pitches.suffix(2))
                if full, let bass = voicing.bass { pitches.append(bass) }

                // A chord never sounds past its own chord's end: holding a ii
                // voicing into the V is the one thing that makes a comp sound
                // wrong rather than merely dull.
                let chordEnd = progression.chords[chordIndex].startBeat
                    + progression.chords[chordIndex].durationBeats
                let written = Double(max(1, figure.rhythm.lengths[index])) / 2
                let duration = max(0.25, min(written * gate, chordEnd - beat))

                let velocity = figure.rhythm.accents.contains(index) ? 96 : 78
                for pitch in pitches where (0...127).contains(pitch) {
                    notes.append(SequencedNote(note: UInt8(pitch),
                                               velocity: UInt8(max(1, min(127, velocity))),
                                               startBeat: beat,
                                               durationBeats: duration))
                }
                hit += 1
            }
            onset += cycle
        }

        return notes.sorted { ($0.startBeat, $0.note) < ($1.startBeat, $1.note) }
    }

    /// How many voices sound at once, at most. The kernel allows sixty-four; a
    /// comp that needs more than a handful is a comp that has gone wrong.
    static func maximumPolyphony(of notes: [SequencedNote]) -> Int {
        var maximum = 0
        for note in notes {
            let sounding = notes.filter {
                $0.startBeat <= note.startBeat + 1e-9
                    && $0.startBeat + $0.durationBeats > note.startBeat + 1e-9
            }.count
            maximum = max(maximum, sounding)
        }
        return maximum
    }
}

/// What the plug-in is producing.
///
/// A mode rather than a setting, and visible rather than inferred, because it
/// decides what the output should be plugged into. Everything downstream of a
/// take — expression, swing, gate, the kernel — is indifferent to it, which is
/// why the fork lives here and not in five places.
enum PlayMode: String, Codable, CaseIterable, Sendable {
    case line, comping, bass

    var label: String {
        switch self {
        case .line: return "Line"
        case .comping: return "Chords"
        case .bass: return "Bass"
        }
    }

    var explanation: String {
        switch self {
        case .line: return "A monophonic line — point it at a lead sound."
        case .comping: return "Voicings under the changes — point it at something polyphonic."
        case .bass: return "A bass part in its own register — point it at a bass sound."
        }
    }

    /// Whether this mode can put two notes on at once.
    ///
    /// Asked as a question about the mode rather than compared against `.comping`
    /// in a dozen places, because adding a third mode turned every one of those
    /// comparisons into a decision about a case that didn't exist when it was
    /// written. Bass is monophonic for the same reason a line is: one voice.
    var isPolyphonic: Bool { self == .comping }
}

extension CompingFigure {
    static func named(_ name: String) -> CompingFigure {
        all.first { $0.name == name } ?? .charleston
    }

    /// The same figure with a different voicing under it, or the same voicing
    /// with a different figure over it. The two axes a comp actually has.
    func with(style: VoicingStyle) -> CompingFigure {
        var copy = self
        copy.style = style
        // Alternation off when a style is chosen deliberately. `comp` overrides
        // the style per chord when it's on, so a figure asked for rootless B came
        // back playing the same A/B alternation as one asked for rootless A —
        // the choice made no audible difference at all.
        copy.alternatesInversion = false
        return copy
    }

    func with(rhythm: GestureRhythm) -> CompingFigure {
        var copy = self
        copy.rhythm = rhythm
        return copy
    }
}

extension MelodyComping {

    /// Variants of a comp, as comps.
    ///
    /// A comping take has two axes and they are not the ones a line has: which
    /// rhythm the chords land on, and how the chords are laid out. So the
    /// variants are the cross of those, plus the transforms that make sense on
    /// whole chords — displacing the figure, thinning it, moving the register.
    /// Nothing here goes through degree extraction, which is what flattened
    /// comping variants to single notes.
    /// - Parameter parent: the take being varied. Its *rhythm* is what makes a
    ///   variant a variant of it, so the re-voicings keep it and only change how
    ///   the chords are laid out. Without this, exploring a model-generated comp
    ///   threw the model's material away and offered twelve deterministic comps
    ///   instead — polyphonic, so it didn't look like a bug, and not variants of
    ///   anything.
    static func variants(of progression: ChordProgression,
                         figure: CompingFigure,
                         parent: [SequencedNote] = [],
                         seed: UInt64,
                         limit: Int = 12,
                         leading: VoiceLeadingMode = .smooth) -> [(name: String, summary: String, notes: [SequencedNote])] {
        // Axis-tagged at construction. The first version worked the axis out by
        // reading the name back, and two different kinds of variant happened to
        // end with the same word — so a whole axis was silently classified as
        // another and never appeared. Deriving structure from a string you just
        // built is a way of forgetting what you knew.
        enum Axis: Int, CaseIterable { case revoiced, displaced, register, style, rhythm, density }
        var results: [(axis: Axis, name: String, summary: String, notes: [SequencedNote])] = []

        // Re-voicing the parent: same hits, same lengths, different chords under
        // them. This is the variant that keeps what you were listening to.
        if !parent.isEmpty {
            for style in VoicingStyle.allCases where style != figure.style {
                let revoiced = revoice(parent, over: progression, as: style, leading: leading)
                guard !revoiced.isEmpty, revoiced != parent else { continue }
                results.append((.revoiced, "This comp · \(style.label)",
                                "the rhythm you have, laid out as \(style.label.lowercased())",
                                revoiced))
            }
            for shift in [1, -2] {
                let displaced = displace(parent, byEighths: shift, over: progression)
                guard !displaced.isEmpty else { continue }
                // Re-voiced after moving, not before. A hit displaced across a
                // chord change carries the *old* chord's notes otherwise, which
                // is a wrong chord rather than a variation — and the kind of
                // wrong that a polyphony count doesn't notice.
                let corrected = revoice(displaced, over: progression, as: figure.style, leading: leading)
                guard !corrected.isEmpty else { continue }
                results.append((.displaced, "This comp, shifted \(shift > 0 ? "+" : "")\(shift)",
                                "the same figure, landing elsewhere", corrected))
            }
        }

        // Register first among the figure-derived ones: an octave is the most
        // audible change available and it was being ranked below six voicing
        // styles, so it never survived the limit.
        for (octaves, label) in [(-1, "an octave down"), (1, "an octave up")] {
            let notes = parent.isEmpty
                ? comp(progression, figure: figure,
                       centre: ChordVoicings.defaultCentre + 12 * octaves, seed: seed,
                       leading: leading)
                : revoice(parent, over: progression, as: figure.style,
                          centre: ChordVoicings.defaultCentre + 12 * octaves,
                          leading: leading)
            guard !notes.isEmpty else { continue }
            results.append((.register, "\(figure.name) \(label)", "the same comp, \(label)", notes))
        }

        // Same rhythm, every other way of laying the chords out.
        for style in VoicingStyle.allCases where style != figure.style {
            let varied = figure.with(style: style)
            let notes = comp(progression, figure: varied, seed: seed, leading: leading)
            guard !notes.isEmpty else { continue }
            results.append((.style, "\(figure.name) · \(style.label)", style.summary, notes))
        }

        // Same voicing, every other figure's rhythm.
        for other in CompingFigure.all where other.rhythm != figure.rhythm {
            let varied = figure.with(rhythm: other.rhythm)
            let notes = comp(progression, figure: varied, seed: seed, leading: leading)
            guard !notes.isEmpty else { continue }
            results.append((.rhythm, "\(other.rhythm.name) · \(figure.style.label)",
                            "\(figure.style.label) voicings on \(other.name)'s rhythm", notes))
        }

        // Sparser and denser, by how often a hit gets the whole voicing.
        for (share, label) in [(0.15, "sparser"), (1.0, "every hit full")] {
            var varied = figure
            varied.fullVoicingShare = share
            let notes = comp(progression, figure: varied, seed: seed, leading: leading)
            guard !notes.isEmpty else { continue }
            results.append((.density, "\(figure.name), \(label)",
                            share < 0.5 ? "mostly the top two voices" : "the full voicing every time",
                            notes))
        }

        // Round-robin across the axes rather than in the order they were
        // generated. Taking the first twelve gave every slot to whichever axis
        // happened to be produced first, so a whole kind of variant — a
        // different rhythm entirely, a different register — could be absent
        // without anything looking wrong. One from each axis in turn guarantees
        // all of them are represented before any is doubled.
        var ordered: [(String, String, [SequencedNote])] = []
        var cursor = 0
        while ordered.count < results.count {
            var addedAny = false
            for axis in Axis.allCases {
                let inAxis = results.filter { $0.axis == axis }
                guard cursor < inAxis.count else { continue }
                ordered.append((inAxis[cursor].name, inAxis[cursor].summary, inAxis[cursor].notes))
                addedAny = true
            }
            if !addedAny { break }
            cursor += 1
        }
        return Array(ordered.prefix(limit))
    }

    /// Keeps a comp's rhythm and re-lays its chords.
    ///
    /// Each simultaneity is read back as degrees of the chord under it, then
    /// voiced afresh in the requested style and led from the one before. The
    /// hits, their lengths and their velocities are untouched, which is what
    /// makes the result recognisably the same part played differently.
    /// - Parameter voices: how many voices to put under each hit. Nil keeps as
    ///   many as the parent had there, which is what re-voicing a comp wants.
    ///   A number is what *harmonising a line* wants: every hit in a monophonic
    ///   part is a simultaneity of one, so without this a line comes back a line.
    /// - Parameter leading: how each hit's voicing relates to the hit before
    ///   it. Re-voicing is where leading is most audible, because the rhythm is
    ///   held fixed and the movement is the only thing that changed.
    static func revoice(_ notes: [SequencedNote],
                        over progression: ChordProgression,
                        as style: VoicingStyle,
                        centre: Int = ChordVoicings.defaultCentre,
                        voices: Int? = nil,
                        leading: VoiceLeadingMode = .smooth) -> [SequencedNote] {
        let groups = simultaneities(in: notes.sorted { ($0.startBeat, $0.note) < ($1.startBeat, $1.note) })
        var result: [SequencedNote] = []
        var previous: [Int]?

        for group in groups {
            guard let first = group.first,
                  let placed = progression.chord(at: first.startBeat) else { continue }
            var voicing = ChordVoicings.voice(placed.symbol, style: style, centre: centre)
            guard !voicing.pitches.isEmpty else { continue }
            voicing.pitches = ChordVoicings.lead(from: previous, to: voicing.pitches,
                                                 centre: centre, mode: leading)
            previous = voicing.pitches

            // As many voices as the parent had at this hit, so a comp that
            // thinned to two voices on the weak hits still does — unless a count
            // was asked for, which is how a mono line becomes chords.
            let wanted = max(1, min(voices ?? group.count, voicing.pitches.count))
            for pitch in voicing.pitches.suffix(wanted) where (24...108).contains(pitch) {
                result.append(SequencedNote(note: UInt8(pitch),
                                            velocity: first.velocity,
                                            startBeat: first.startBeat,
                                            durationBeats: first.durationBeats))
            }
        }
        return result.sorted { ($0.startBeat, $0.note) < ($1.startBeat, $1.note) }
    }

    /// Moves a comp's hits without changing what's in them, clipping anything
    /// that would sound past its own chord.
    static func displace(_ notes: [SequencedNote],
                         byEighths shift: Int,
                         over progression: ChordProgression) -> [SequencedNote] {
        let offset = Double(shift) / 2
        return notes.compactMap { note in
            var moved = note
            moved.startBeat = note.startBeat + offset
            guard moved.startBeat >= 0, moved.startBeat < progression.totalBeats else { return nil }
            guard let chord = progression.chord(at: moved.startBeat) else { return nil }
            let end = chord.startBeat + chord.durationBeats
            moved.durationBeats = max(0.25, min(moved.durationBeats, end - moved.startBeat))
            return moved
        }.sorted { ($0.startBeat, $0.note) < ($1.startBeat, $1.note) }
    }

    /// Notes grouped by start beat — one chord is one thing.
    static func simultaneities(in notes: [SequencedNote]) -> [[SequencedNote]] {
        var groups: [[SequencedNote]] = []
        for note in notes {
            if let last = groups.last, let first = last.first,
               abs(first.startBeat - note.startBeat) < 0.001 {
                groups[groups.count - 1].append(note)
            } else {
                groups.append([note])
            }
        }
        return groups
    }
}
