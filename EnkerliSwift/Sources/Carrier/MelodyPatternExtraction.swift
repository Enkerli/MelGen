//
//  MelodyPatternExtraction.swift
//  MelGenExtension
//
//  The missing direction of the pattern format: takes back into patterns.
//
//  `MelodyPatterns.realize` turns scale degrees into pitches over whatever
//  harmony is sounding. This does the inverse — given a take's absolute pitches
//  and the progression it was played over, it works out which degree each note
//  was — and that inverse is what closes the loop the whole project is about.
//  Without it the library is a fixed set of hand-written lines and the model
//  produces one-offs; with it, a take you liked becomes a line you can play over
//  anything, and the model's job becomes growing the library.
//
//  The one real decision is what to do with a note that isn't in the chord's
//  scale at all. Snapping it away would make every extracted pattern
//  well-behaved and would also delete the chromatic approach notes that are most
//  of what makes a line sound played rather than assembled. So nothing is
//  snapped: an off-scale note is stored as its nearest degree plus an
//  `alteration`, and the role it had over its original harmony travels with it.
//  Preserve the uncertainty; don't invent certainty.
//
//  Deliberately free of any FoundationModels dependency: it's arithmetic.
//

import Foundation
import Theory

extension MelodyPatterns {

    /// Turns a take into a degree-relative pattern.
    ///
    /// - Parameters:
    ///   - notes: the take's notes, as generated — *not* the expression render,
    ///     since expression is realization and a pattern is not.
    ///   - progression: the harmony they were played over. Without it a pitch is
    ///     just a number.
    ///   - lengthBeats: the take's length, which sets how many bars the pattern
    ///     tiles at. Defaults to the progression's length.
    /// - Returns: nil when nothing could be placed against a chord.
    public static func extract(from notes: [SequencedNote],
                        over progression: ChordProgression,
                        name: String,
                        summary: String? = nil,
                        lengthBeats: Double? = nil,
                        origin: PatternOrigin? = nil) -> MelodyPattern? {
        guard !notes.isEmpty, progression.totalBeats > 0 else { return nil }
        let ordered = notes.sorted { $0.startBeat < $1.startBeat }

        var patternNotes: [PatternNote] = []
        for (index, note) in ordered.enumerated() {
            guard let relative = degree(of: Int(note.note), at: note.startBeat, in: progression) else { continue }

            let startEighth = Int((note.startBeat * 2).rounded())
            let lengthEighths = max(1, Int((note.durationBeats * 2).rounded()))

            // The silence after this note, in the schema's own terms. Measured
            // from the note's end rather than assumed, so phrasing survives the
            // conversion — a pattern with no rests in it plays as a wall.
            var restAfterEighths = 0
            if index + 1 < ordered.count {
                let gap = ordered[index + 1].startBeat - (note.startBeat + note.durationBeats)
                restAfterEighths = min(8, max(0, Int((gap * 2).rounded())))
            }

            patternNotes.append(PatternNote(
                startEighth: startEighth,
                lengthEighths: lengthEighths,
                degree: relative.degree,
                octave: relative.octave,
                alteration: relative.alteration,
                velocity: Int(note.velocity),
                restAfterEighths: restAfterEighths,
                role: MelodyAnalyser.role(of: note, in: progression)
            ))
        }
        guard !patternNotes.isEmpty else { return nil }

        let span = lengthBeats ?? progression.totalBeats
        let bars = max(1, Int(ceil(span / beatsPerBar - 0.001)))

        return MelodyPattern(
            name: name,
            bars: bars,
            summary: summary ?? describe(patternNotes, bars: bars),
            notes: patternNotes,
            origin: origin
        )
    }

    /// The inverse of `pitch(for:at:in:near:)`: which degree, octave and
    /// alteration name this pitch against the chord sounding at this beat.
    ///
    /// Built from exactly the same interval table as the forward direction, which
    /// is what makes the round trip hold: extract what realize wrote and the
    /// degrees come back unchanged.
    public static func degree(of pitch: Int,
                       at beat: Double,
                       in progression: ChordProgression) -> (degree: Int, octave: Int, alteration: Int)? {
        guard let placed = progression.chord(at: beat) else { return nil }
        let root = placed.symbol.rootPitchClass

        let intervals = placed.symbol.scalePitchClasses
            .map { (($0 - root) % 12 + 12) % 12 }
            .sorted()
        guard !intervals.isEmpty else { return nil }

        let relative = (((pitch - root) % 12) + 12) % 12

        // Nearest degree, preferring an exact match, then the smallest
        // alteration, then the lower degree so a passing tone reads as an
        // approach from below rather than an unresolved one from above.
        var best: (degree: Int, alteration: Int)?
        for (index, interval) in intervals.enumerated() {
            for alteration in [0, -1, 1, -2, 2] {
                guard (((interval + alteration) % 12) + 12) % 12 == relative else { continue }
                if let current = best, abs(current.alteration) <= abs(alteration) { continue }
                best = (index, alteration)
            }
        }
        guard let match = best else { return nil }

        // The reference pitch realize would produce for this degree with no
        // octave offset; whatever is left over is the octave.
        let base = 60 + root + intervals[match.degree] + match.alteration
        let offset = pitch - base
        // Always a whole number of octaves, because the pitch classes agree by
        // construction — but round rather than truncate so a negative offset
        // doesn't land a semitone out.
        let octave = Int((Double(offset) / 12).rounded())

        return (match.degree, octave, match.alteration)
    }

    /// A one-line description of what an extracted pattern actually is, so a
    /// library row says something before anyone has named it.
    public static func describe(_ notes: [PatternNote], bars: Int) -> String {
        guard !notes.isEmpty else { return "Empty" }
        let perBar = Double(notes.count) / Double(max(1, bars))
        let density: String
        switch perBar {
        case ..<2.5: density = "sparse"
        case ..<5: density = "steady"
        case ..<7: density = "busy"
        default: density = "dense"
        }

        let offbeats = notes.filter { !$0.startEighth.isMultiple(of: 2) }.count
        let syncopated = Double(offbeats) / Double(notes.count) > 0.35
        let chromatic = notes.contains { $0.alteration != 0 }

        var parts = ["\(density), \(notes.count) notes over \(bars) bar\(bars == 1 ? "" : "s")"]
        if syncopated { parts.append("syncopated") }
        if chromatic { parts.append("with chromatic approaches") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Fit report

/// What happened when a pattern met a progression it wasn't written over.
///
/// Some patterns don't survive re-harmonization — a line leaning on a ♯11 over
/// changes with no altered chords comes out as something else. Saying so is
/// cheaper than letting someone wonder why a line they liked sounds wrong here.
public struct PatternFitReport: Sendable, Hashable {
    public var patternName: String
    public var progressionText: String
    /// Notes the pattern asked for.
    public var requested: Int
    /// Notes that actually landed inside the progression.
    public var placed: Int
    /// Of those, how many came out off the sounding chord's scale.
    public var offScale: Int
    /// And how many landed on a note the chord says not to land on.
    public var onAvoidNotes: Int
    /// Whether the pattern tiles the progression evenly, or gets cut off.
    public var tilesEvenly: Bool

    public var isClean: Bool { placed == requested && offScale == 0 && onAvoidNotes == 0 && tilesEvenly }

    public var summary: String {
        if isClean { return "Fits: all \(placed) notes land in the scale, and the line tiles evenly." }
        var parts: [String] = []
        if placed < requested { parts.append("\(requested - placed) note\(requested - placed == 1 ? "" : "s") fell outside the form") }
        if offScale > 0 { parts.append("\(offScale) off-scale") }
        if onAvoidNotes > 0 { parts.append("\(onAvoidNotes) on avoid notes") }
        if !tilesEvenly { parts.append("doesn't tile evenly — the last repetition is cut short") }
        return parts.isEmpty ? "Fits." : parts.joined(separator: ", ") + "."
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(patternName: String,
                progressionText: String,
                requested: Int,
                placed: Int,
                offScale: Int,
                onAvoidNotes: Int,
                tilesEvenly: Bool) {
        self.patternName = patternName
        self.progressionText = progressionText
        self.requested = requested
        self.placed = placed
        self.offScale = offScale
        self.onAvoidNotes = onAvoidNotes
        self.tilesEvenly = tilesEvenly
    }
}

extension MelodyPatterns {

    /// Fits a pattern to a progression and reports what it cost.
    public static func fitReport(for pattern: MelodyPattern,
                          over progression: ChordProgression) -> PatternFitReport {
        let placed = realize(pattern, over: progression)
        let analysis = MelodyAnalyser.analyse(placed, over: progression)

        let patternBeats = Double(max(1, pattern.bars)) * beatsPerBar
        let repetitions = max(1, Int(ceil(progression.totalBeats / patternBeats)))

        return PatternFitReport(
            patternName: pattern.name,
            progressionText: progression.text,
            requested: pattern.notes.count * repetitions,
            placed: placed.count,
            offScale: analysis.offScaleNotes,
            onAvoidNotes: analysis.avoidNotes,
            tilesEvenly: abs(progression.totalBeats.truncatingRemainder(dividingBy: patternBeats)) < 0.001
        )
    }
}
