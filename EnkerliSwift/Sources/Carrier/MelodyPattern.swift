//
//  MelodyPattern.swift
//  MelGenExtension
//
//  Lines described relative to the harmony rather than tied to it, and the
//  deterministic machinery that fits them to a progression.
//
//  Measured generation time is roughly two seconds per note, which is about four
//  times slower than real time — so the model can never be the thing that feeds
//  continuous playback. Adapting an existing line to new harmony, on the other
//  hand, is arithmetic: instant, repeatable, and available the moment a
//  progression changes. That's what this is for. The model's job becomes growing
//  the library in the background; this is what plays while it works.
//
//  A pattern note names a *scale degree* of whatever chord is sounding, so the
//  same rhythmic and contour idea comes out consonant over any harmony. Degrees
//  0, 2, 4 and 6 of a seven-note scale are its chord tones, which is why a line
//  that lands on those on strong beats fits without needing to know the chord.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation
import Theory

/// One note of a pattern, positioned on the eighth-note grid and pitched
/// relative to the sounding chord.
public struct PatternNote: Codable, Hashable, Sendable {
    public var startEighth: Int
    public var lengthEighths: Int
    /// Scale degree, 0-based: 0 is the root, 2 the third, 4 the fifth, 6 the
    /// seventh of a seven-note scale. Values beyond the scale wrap upward an
    /// octave, so 7 is the root again one octave higher.
    public var degree: Int
    /// Extra octaves above (or below) the degree's natural placement.
    public var octave: Int = 0
    /// Semitones off the scale, for chromatic approach notes. Usually 0.
    public var alteration: Int = 0
    public var velocity: Int = 90
    /// Eighths of silence after this note, as in the model's schema.
    public var restAfterEighths: Int = 0
    /// How this note sat against the chord it was *derived* from, when it was
    /// derived from anything. Kept because it records what the note was for —
    /// a chromatic approach and a mis-snapped pitch look identical as numbers,
    /// and only the original harmony can tell them apart. Nil on a hand-written
    /// pattern, which has no original harmony to be relative to.
    public var role: HarmonicRole?

    /// Whether the seam leading is allowed to move this note.
    ///
    /// Only notes with no stated relationship to the harmony, and notes that
    /// *were* chord tones where they came from. A chromatic alteration and a
    /// recorded colour note are both deliberately off the chord: snapping them
    /// onto it is not smoothing, it's deleting the thing the note was for. The
    /// extraction round trip caught this — a real take replayed over its own
    /// changes came back with a different note, and a line written with a
    /// chromatic approach stopped reporting that it had one.
    public var isLeadable: Bool {
        guard alteration == 0 else { return false }
        switch role {
        case nil, .chordTone: return true
        case .colour, .avoid, .offScale: return false
        }
    }

    public init(startEighth: Int,
         lengthEighths: Int,
         degree: Int,
         octave: Int = 0,
         alteration: Int = 0,
         velocity: Int = 90,
         restAfterEighths: Int = 0,
         role: HarmonicRole? = nil) {
        self.startEighth = startEighth
        self.lengthEighths = lengthEighths
        self.degree = degree
        self.octave = octave
        self.alteration = alteration
        self.velocity = velocity
        self.restAfterEighths = restAfterEighths
        self.role = role
    }

    // Field by field, so a pattern stored by an older build still loads: the
    // synthesized decoder throws on a missing key even where a default exists,
    // and these are persisted now that patterns come from curation.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startEighth = try container.decodeIfPresent(Int.self, forKey: .startEighth) ?? 0
        lengthEighths = try container.decodeIfPresent(Int.self, forKey: .lengthEighths) ?? 1
        degree = try container.decodeIfPresent(Int.self, forKey: .degree) ?? 0
        octave = try container.decodeIfPresent(Int.self, forKey: .octave) ?? 0
        alteration = try container.decodeIfPresent(Int.self, forKey: .alteration) ?? 0
        velocity = try container.decodeIfPresent(Int.self, forKey: .velocity) ?? 90
        restAfterEighths = try container.decodeIfPresent(Int.self, forKey: .restAfterEighths) ?? 0
        role = try container.decodeIfPresent(HarmonicRole.self, forKey: .role)
    }
}

/// Where a pattern came from, when it came from somewhere.
///
/// A hand-written seed has no provenance; one derived from a take has all of it,
/// and losing that is how a library becomes a pile of anonymous lines.
public struct PatternOrigin: Codable, Hashable, Sendable {
    /// The take this was derived from.
    public var takeID: UUID?
    /// The progression it was played over, in leadsheet text.
    public var progressionText: String
    /// The style brief or stored line that produced the take.
    public var briefName: String
    /// Whether the take was composed by the model or fitted from a stored line.
    public var source: TakeSource
    public var derivedAt: Date

    public init(takeID: UUID? = nil,
         progressionText: String,
         briefName: String = "",
         source: TakeSource = .model,
         derivedAt: Date = Date()) {
        self.takeID = takeID
        self.progressionText = progressionText
        self.briefName = briefName
        self.source = source
        self.derivedAt = derivedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        takeID = try container.decodeIfPresent(UUID.self, forKey: .takeID)
        progressionText = try container.decodeIfPresent(String.self, forKey: .progressionText) ?? ""
        briefName = try container.decodeIfPresent(String.self, forKey: .briefName) ?? ""
        source = try container.decodeIfPresent(TakeSource.self, forKey: .source) ?? .model
        derivedAt = try container.decodeIfPresent(Date.self, forKey: .derivedAt) ?? Date()
    }
}

/// How a pattern's degrees become pitches.
///
/// Two modes, because the pattern format turned out to describe two different
/// kinds of thing.
public enum PatternRealization: String, Codable, Hashable, Sendable {
    /// Each note is placed at its degree's own pitch, then folded by octaves to
    /// sit next to its predecessor. Right for almost everything: folding is what
    /// keeps a line singable and what stops the model's register jumps.
    case folded
    /// Each note is placed by *moving* from the previous one by the number of
    /// scale steps between their degrees, through whatever scale is sounding.
    ///
    /// This is the Samchillian's model, and the only correct way to realize a
    /// figure whose content is its intervals. Folding would destroy it twice
    /// over: a deliberate octave leap is exactly what folding removes, and a
    /// degree re-anchored against a new chord's root loses the *move* that the
    /// figure was made of. Stepping through the sounding scale keeps both — a
    /// leap stays a leap, and it lands on a note that belongs to the new chord.
    case stepwise
}

/// A generic line: rhythm and contour, with no harmony of its own.
public struct MelodyPattern: Codable, Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    /// How many bars before the pattern repeats.
    public var bars: Int
    /// What it's for, shown in the interface.
    public var summary: String
    public var notes: [PatternNote]
    /// The take this was lifted from, if it was lifted from one.
    public var origin: PatternOrigin?
    /// How this pattern becomes pitches.
    public var realization: PatternRealization = .folded

    public init(name: String,
         bars: Int,
         summary: String,
         notes: [PatternNote],
         origin: PatternOrigin? = nil,
         realization: PatternRealization = .folded) {
        self.name = name
        self.bars = bars
        self.summary = summary
        self.notes = notes
        self.origin = origin
        self.realization = realization
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        bars = try container.decodeIfPresent(Int.self, forKey: .bars) ?? 2
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        notes = try container.decodeIfPresent([PatternNote].self, forKey: .notes) ?? []
        origin = try container.decodeIfPresent(PatternOrigin.self, forKey: .origin)
        realization = try container.decodeIfPresent(PatternRealization.self, forKey: .realization) ?? .folded
    }
}

public enum MelodyPatterns {

    public static let beatsPerBar: Double = 4
    /// Where the line sits when nothing else constrains it — around G4.
    public static let registerCentre = 67
    /// Where a stepwise line is kept. Three octaves: wide enough that a
    /// deliberate octave leap has headroom on both sides of it, narrow enough
    /// that an accumulating drift is caught before it leaves the instrument.
    public static let registerBand = 48...84

    /// Fits a pattern to a progression, repeating it as needed.
    ///
    /// Each repetition is re-pitched against whatever chord is sounding, so a
    /// two-bar cell over sixteen bars comes back eight times, recognisably the
    /// same figure and correct over every chord. That recurrence is the point:
    /// it's what makes a line sound composed rather than sampled.
    /// - Parameter leading: whether to reach for the chord at a change. Voice
    ///   leading in a line is about the seams — see `ledToChord`, and
    ///   `PatternNote.isLeadable` for which notes are exempt from it.
    public static func realize(_ pattern: MelodyPattern,
                        over progression: ChordProgression,
                        registerCentre centre: Int = registerCentre,
                        leading: VoiceLeadingMode = .smooth) -> [SequencedNote] {
        guard !pattern.notes.isEmpty, progression.totalBeats > 0, pattern.bars > 0 else { return [] }

        let patternBeats = Double(pattern.bars) * beatsPerBar
        let repetitions = max(1, Int(ceil(progression.totalBeats / patternBeats)))
        let ordered = pattern.notes.sorted { $0.startEighth < $1.startEighth }

        var placed: [SequencedNote] = []
        var previousPitch: Int?
        var previousNote: PatternNote?
        // Which chord the last note belonged to, so the first note under a new
        // one can be recognised as the seam.
        var previousChordStart: Double?

        for repetition in 0..<repetitions {
            let offset = Double(repetition) * patternBeats
            for note in ordered {
                let startBeat = offset + Double(note.startEighth) / 2
                guard startBeat < progression.totalBeats - 0.001 else { continue }

                let resolved: Int?
                switch pattern.realization {
                case .folded:
                    resolved = pitch(for: note,
                                     at: startBeat,
                                     in: progression,
                                     near: previousPitch ?? centre)
                case .stepwise:
                    resolved = steppedPitch(to: note,
                                            from: previousNote,
                                            at: previousPitch ?? centre,
                                            beat: startBeat,
                                            in: progression)
                }
                guard var pitch = resolved else { continue }

                // The seam: the first note under a chord is the one a player
                // places deliberately.
                //
                // The very first note has nothing to lead *from*, but landing on
                // the chord is right regardless, so it uses itself as the
                // reference and only the chord-tone correction applies.
                let chordStart = progression.chord(at: startBeat)?.startBeat
                if leading == .smooth, chordStart != previousChordStart, note.isLeadable {
                    pitch = ledToChord(pitch, at: startBeat, in: progression,
                                       from: previousPitch ?? pitch)
                }
                previousChordStart = chordStart

                previousNote = note
                previousPitch = pitch

                let maxLength = (progression.totalBeats - startBeat) * 2
                let lengthEighths = min(Double(max(1, note.lengthEighths)), maxLength)
                placed.append(SequencedNote(
                    note: UInt8(clamping: pitch),
                    velocity: UInt8(clamping: note.velocity),
                    startBeat: startBeat,
                    durationBeats: lengthEighths / 2
                ))
            }
        }

        return DeadAir.cap(
            monophonic(placed, honouringRestsFrom: ordered, repetitions: repetitions),
            totalBeats: progression.totalBeats
        )
    }

    /// Fills stretches a generated line left empty.
    ///
    /// A chunk that under-produces leaves bars of silence, and no amount of
    /// extending the previous note fixes a two-bar hole. Since fitting a stored
    /// line to arbitrary harmony is instant and already correct, the library is
    /// the natural patch: the take keeps the model's material everywhere the
    /// model actually wrote something, and borrows for the rest.
    ///
    /// - Parameter minimumHole: only stretches at least this long are filled;
    ///   anything shorter is phrasing.
    public static func fillHoles(in notes: [SequencedNote],
                          over progression: ChordProgression,
                          pattern: MelodyPattern,
                          minimumHole: Double = 8) -> [SequencedNote] {
        guard progression.totalBeats > 0 else { return notes }

        // Where the line is silent for long enough to be a hole rather than a rest.
        var holes: [(start: Double, end: Double)] = []
        var cursor = 0.0
        for note in notes.sorted(by: { $0.startBeat < $1.startBeat }) {
            if note.startBeat - cursor >= minimumHole - 0.001 {
                holes.append((cursor, note.startBeat))
            }
            cursor = max(cursor, note.startBeat + note.durationBeats)
        }
        if progression.totalBeats - cursor >= minimumHole - 0.001 {
            holes.append((cursor, progression.totalBeats))
        }
        guard !holes.isEmpty else { return notes }

        var filled = notes
        for hole in holes {
            // Start on a bar line so the borrowed material lands in time.
            let start = (hole.start / beatsPerBar).rounded(.up) * beatsPerBar
            guard hole.end - start >= beatsPerBar else { continue }

            let slice = progression.slice(from: start, to: hole.end)
            for note in realize(pattern, over: slice) {
                var shifted = note
                shifted.startBeat += start
                guard shifted.startBeat + shifted.durationBeats <= hole.end + 0.001 else { continue }
                filled.append(shifted)
            }
        }
        return filled.sorted { $0.startBeat < $1.startBeat }
    }

    /// Turns a degree into a MIDI note against the chord sounding at `beat`.
    public static func pitch(for note: PatternNote,
                      at beat: Double,
                      in progression: ChordProgression,
                      near previous: Int) -> Int? {
        guard let placed = progression.chord(at: beat) else { return nil }
        let root = placed.symbol.rootPitchClass

        // Ascending intervals from the root, so a degree can carry octaves.
        let intervals = placed.symbol.scalePitchClasses
            .map { (($0 - root) % 12 + 12) % 12 }
            .sorted()
        guard !intervals.isEmpty else { return nil }

        let size = intervals.count
        let index = ((note.degree % size) + size) % size
        let octaveCarry = Int(floor(Double(note.degree) / Double(size)))

        // Root in octave 4 is the reference, then fold toward the previous note so
        // the line keeps its register across chords and keys.
        let base = 60 + root + intervals[index] + 12 * (octaveCarry + note.octave) + note.alteration
        let folded = MelodyGeneratorSupport.fold(pitch: base, near: previous)
        return (0...127).contains(folded) ? folded : base.clamped(to: 0...127)
    }

    /// Moves `steps` scale degrees from a pitch, through the scale sounding at
    /// this beat.
    ///
    /// The Samchillian's arithmetic: you don't say which note, you say how far,
    /// and the scale decides what that lands on. Which means the same figure over
    /// a different chord is the same *shape*, played on that chord's notes — and
    /// an octave leap survives, because seven steps of a seven-note scale is an
    /// octave by construction rather than by luck.
    public static func steppedPitch(to note: PatternNote,
                             from previous: PatternNote?,
                             at previousPitch: Int,
                             beat: Double,
                             in progression: ChordProgression) -> Int? {
        guard let placed = progression.chord(at: beat) else { return nil }
        let scale = placed.symbol.scalePitchClasses.map { (($0 % 12) + 12) % 12 }.sorted()
        guard !scale.isEmpty else { return nil }

        // No predecessor: place the first note the ordinary way.
        guard let previous else {
            return pitch(for: note, at: beat, in: progression, near: previousPitch)
        }
        let steps = note.degree - previous.degree
        let size = scale.count

        // Where the previous pitch sits in this scale — nearest member, since the
        // last note may have been placed against a different chord entirely.
        let previousClass = ((previousPitch % 12) + 12) % 12
        let nearest = scale.enumerated().min {
            let left = min(abs($0.element - previousClass), 12 - abs($0.element - previousClass))
            let right = min(abs($1.element - previousClass), 12 - abs($1.element - previousClass))
            return left < right
        }?.offset ?? 0

        let target = nearest + steps
        let index = ((target % size) + size) % size
        let octaves = Int(floor(Double(target) / Double(size)))
        let anchorOctave = (previousPitch - scale[nearest]) / 12

        var pitch = scale[index] + 12 * (anchorOctave + octaves + note.octave) + note.alteration

        // Stepping from the last note means pitch accumulates: a cell that drifts
        // upward drifts upward *forever*, and the degree-space turnaround can't
        // see it because the degrees stayed put. So the register is corrected in
        // whole octaves, which is the one correction that keeps both the scale
        // degree and the interval class — and is what a player does when a
        // sequence runs off the end of the instrument.
        while pitch > registerBand.upperBound { pitch -= 12 }
        while pitch < registerBand.lowerBound { pitch += 12 }
        return pitch.clamped(to: 36...96)
    }

    /// Reaches for the chord at a change.
    ///
    /// Voice leading in a line isn't the same problem as in a comp: there is one
    /// voice, so nothing can be held. What there is instead is a seam. Inside a
    /// chord a degree means what the pattern says it means, and the pattern's
    /// shape is the whole point of it. At a change the same degree points at a
    /// different pitch class, and whether that lands on the new chord or beside
    /// it is an accident of arithmetic rather than a musical decision.
    ///
    /// So only the first note under each chord is touched, and only when it
    /// isn't already a chord tone: it moves to the nearest one within `reach`,
    /// preferring the direction that keeps the interval from the previous note
    /// smaller. A note further than `reach` from any chord tone is left alone —
    /// it's a colour note the pattern asked for, not a mistake.
    public static func ledToChord(_ pitch: Int,
                           at beat: Double,
                           in progression: ChordProgression,
                           from previous: Int,
                           reach: Int = 2) -> Int {
        guard let placed = progression.chord(at: beat) else { return pitch }
        let tones = Set(placed.symbol.tonePitchClasses.map { (($0 % 12) + 12) % 12 })
        guard !tones.isEmpty else { return pitch }
        let pitchClass = ((pitch % 12) + 12) % 12
        if tones.contains(pitchClass) { return pitch }

        let candidates = (-reach...reach)
            .map { pitch + $0 }
            .filter { tones.contains((($0 % 12) + 12) % 12) }
        guard !candidates.isEmpty else { return pitch }

        // Nearest chord tone, and among equals the one that makes the step from
        // the previous note smaller — which is the leading, rather than just the
        // correction.
        return candidates.min {
            let left = (abs($0 - pitch), abs($0 - previous))
            let right = (abs($1 - pitch), abs($1 - previous))
            return left < right
        } ?? pitch
    }

    /// Keeps the line strictly monophonic and honours each pattern note's rest.
    private static func monophonic(_ notes: [SequencedNote],
                                   honouringRestsFrom pattern: [PatternNote],
                                   repetitions: Int) -> [SequencedNote] {
        guard notes.count > 1 else { return notes }
        // The rests line up with the notes one-for-one, in order.
        let rests = (0..<repetitions).flatMap { _ in pattern.map(\.restAfterEighths) }

        var result = notes
        for index in result.indices.dropLast() {
            let slot = result[index + 1].startBeat - result[index].startBeat
            var duration = min(result[index].durationBeats, slot)
            let requested = Double(min(max(rests.indices.contains(index) ? rests[index] : 0, 0), 8)) / 2
            if requested > 0 {
                duration = min(duration, max(slot - requested, slot / 2))
            }
            result[index].durationBeats = max(duration, 0.05)
        }
        return result
    }
}

/// Shared with the model path so an adapted line and a generated one are folded
/// into register by exactly the same rule.
public enum MelodyGeneratorSupport {
    /// Transposes by octaves until the pitch sits within an octave of its
    /// predecessor.
    public static func fold(pitch: Int, near previous: Int) -> Int {
        var folded = pitch
        while folded - previous > 12, folded - 12 >= 0 { folded -= 12 }
        while previous - folded > 12, folded + 12 <= 127 { folded += 12 }
        return folded
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        // Qualified, because inside an Int extension `min` and `max` resolve to
        // Int.min and Int.max rather than the global functions.
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
