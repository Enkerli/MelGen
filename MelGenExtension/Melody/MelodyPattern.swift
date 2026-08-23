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

/// One note of a pattern, positioned on the eighth-note grid and pitched
/// relative to the sounding chord.
struct PatternNote: Codable, Hashable, Sendable {
    var startEighth: Int
    var lengthEighths: Int
    /// Scale degree, 0-based: 0 is the root, 2 the third, 4 the fifth, 6 the
    /// seventh of a seven-note scale. Values beyond the scale wrap upward an
    /// octave, so 7 is the root again one octave higher.
    var degree: Int
    /// Extra octaves above (or below) the degree's natural placement.
    var octave: Int = 0
    /// Semitones off the scale, for chromatic approach notes. Usually 0.
    var alteration: Int = 0
    var velocity: Int = 90
    /// Eighths of silence after this note, as in the model's schema.
    var restAfterEighths: Int = 0
    /// How this note sat against the chord it was *derived* from, when it was
    /// derived from anything. Kept because it records what the note was for —
    /// a chromatic approach and a mis-snapped pitch look identical as numbers,
    /// and only the original harmony can tell them apart. Nil on a hand-written
    /// pattern, which has no original harmony to be relative to.
    var role: HarmonicRole?

    init(startEighth: Int,
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
    init(from decoder: any Decoder) throws {
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
struct PatternOrigin: Codable, Hashable, Sendable {
    /// The take this was derived from.
    var takeID: UUID?
    /// The progression it was played over, in leadsheet text.
    var progressionText: String
    /// The style brief or stored line that produced the take.
    var briefName: String
    /// Whether the take was composed by the model or fitted from a stored line.
    var source: TakeSource
    var derivedAt: Date

    init(takeID: UUID? = nil,
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

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        takeID = try container.decodeIfPresent(UUID.self, forKey: .takeID)
        progressionText = try container.decodeIfPresent(String.self, forKey: .progressionText) ?? ""
        briefName = try container.decodeIfPresent(String.self, forKey: .briefName) ?? ""
        source = try container.decodeIfPresent(TakeSource.self, forKey: .source) ?? .model
        derivedAt = try container.decodeIfPresent(Date.self, forKey: .derivedAt) ?? Date()
    }
}

/// A generic line: rhythm and contour, with no harmony of its own.
struct MelodyPattern: Codable, Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    /// How many bars before the pattern repeats.
    var bars: Int
    /// What it's for, shown in the interface.
    var summary: String
    var notes: [PatternNote]
    /// The take this was lifted from, if it was lifted from one.
    var origin: PatternOrigin?

    init(name: String, bars: Int, summary: String, notes: [PatternNote], origin: PatternOrigin? = nil) {
        self.name = name
        self.bars = bars
        self.summary = summary
        self.notes = notes
        self.origin = origin
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        bars = try container.decodeIfPresent(Int.self, forKey: .bars) ?? 2
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        notes = try container.decodeIfPresent([PatternNote].self, forKey: .notes) ?? []
        origin = try container.decodeIfPresent(PatternOrigin.self, forKey: .origin)
    }
}

enum MelodyPatterns {

    static let beatsPerBar: Double = 4
    /// Where the line sits when nothing else constrains it — around G4.
    static let registerCentre = 67

    /// Fits a pattern to a progression, repeating it as needed.
    ///
    /// Each repetition is re-pitched against whatever chord is sounding, so a
    /// two-bar cell over sixteen bars comes back eight times, recognisably the
    /// same figure and correct over every chord. That recurrence is the point:
    /// it's what makes a line sound composed rather than sampled.
    static func realize(_ pattern: MelodyPattern,
                        over progression: ChordProgression,
                        registerCentre centre: Int = registerCentre) -> [SequencedNote] {
        guard !pattern.notes.isEmpty, progression.totalBeats > 0, pattern.bars > 0 else { return [] }

        let patternBeats = Double(pattern.bars) * beatsPerBar
        let repetitions = max(1, Int(ceil(progression.totalBeats / patternBeats)))
        let ordered = pattern.notes.sorted { $0.startEighth < $1.startEighth }

        var placed: [SequencedNote] = []
        var previousPitch: Int?

        for repetition in 0..<repetitions {
            let offset = Double(repetition) * patternBeats
            for note in ordered {
                let startBeat = offset + Double(note.startEighth) / 2
                guard startBeat < progression.totalBeats - 0.001 else { continue }

                guard let pitch = pitch(for: note,
                                        at: startBeat,
                                        in: progression,
                                        near: previousPitch ?? centre) else { continue }
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

        return MelodyExpression.capDeadAir(
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
    static func fillHoles(in notes: [SequencedNote],
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

            let slice = MelodyChunker.slice(progression, from: start, to: hole.end)
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
    static func pitch(for note: PatternNote,
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
enum MelodyGeneratorSupport {
    /// Transposes by octaves until the pitch sits within an octave of its
    /// predecessor.
    static func fold(pitch: Int, near previous: Int) -> Int {
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
