//
//  ChordParser.swift
//  MelGenExtension
//
//  Parses chord progressions written in simple leadsheet format,
//  e.g. "E♭7 Gm9|D∆|A♭6" — bars separated by "|", chords by spaces.
//
//  Chord qualities come from the shared chord dictionary (ChordDictionary),
//  and each chord's scale, tensions and avoid notes from ChordScales, so MelGen
//  agrees with the rest of the suite on what a symbol means.
//

import Foundation

enum ChordParseError: LocalizedError, Equatable {
    case emptyInput
    case invalidRoot(String)
    case unknownQuality(chord: String, quality: String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "No chords found. Try something like “Dm7 G7|C∆”."
        case .invalidRoot(let token):
            return "“\(token)” doesn’t start with a valid root note (A–G with optional ♭/♯)."
        case .unknownQuality(let chord, let quality):
            return "Unrecognized chord quality “\(quality)” in “\(chord)”."
        }
    }
}

/// A parsed chord: its root, its dictionary quality, and the chord-scale
/// material a melody over it should draw on.
struct ChordSymbol: Hashable, Sendable {
    /// The chord as it should be displayed, e.g. "E♭7".
    let text: String
    /// Root pitch class, 0 = C.
    let rootPitchClass: Int
    let quality: ChordQuality
    /// Slash bass, when written (e.g. the G of "Dm7/G").
    let bassPitchClass: Int?

    /// Absolute pitch classes of the chord itself.
    let tonePitchClasses: [Int]
    /// Absolute pitch classes of the chosen scale.
    let scalePitchClasses: [Int]
    /// Scale tones that colour without clashing.
    let tensionPitchClasses: [Int]
    /// Scale tones a semitone above a chord tone — unstable as landing notes.
    let avoidPitchClasses: [Int]
    let scaleName: String

    init(rootPitchClass: Int, quality: ChordQuality, bassPitchClass: Int?, text: String) {
        self.text = text
        self.rootPitchClass = rootPitchClass
        self.quality = quality
        self.bassPitchClass = bassPitchClass

        let tones = quality.pitchClasses.map { (rootPitchClass + $0) % 12 }
        self.tonePitchClasses = tones

        let scale = ChordScales.chordScale(rootPitchClass: rootPitchClass, pitchClasses: tones)
        self.scalePitchClasses = scale?.scalePitchClasses ?? tones
        self.tensionPitchClasses = scale?.tensions ?? []
        self.avoidPitchClasses = scale?.avoid ?? []
        self.scaleName = scale?.scaleName ?? ""
    }

    /// A chord whose scale is stated rather than classified.
    ///
    /// Everywhere else the scale is derived from the notes, which is right: a
    /// symbol is what a player writes and the scale is what it implies. The
    /// modal path inverts that — the scale is the thing being chosen and the
    /// chord is whatever sits on top of it — and the classifier can't express
    /// the difference, because several modes share a tonic seventh chord and it
    /// resolves each of them to one answer. C Ionian and C Lydian are both maj7;
    /// C Dorian, C Aeolian and C Phrygian are all m7. Reaching those means
    /// saying which, so this initializer exists and is used by exactly one
    /// caller.
    init(rootPitchClass: Int,
         quality: ChordQuality,
         scale: Scale,
         bassPitchClass: Int? = nil,
         text: String) {
        self.text = text
        self.rootPitchClass = rootPitchClass
        self.quality = quality
        self.bassPitchClass = bassPitchClass

        let tones = quality.pitchClasses.map { (rootPitchClass + $0 % 12 + 12) % 12 }
        let scalePcs = scale.intervals.map { (rootPitchClass + $0) % 12 }
        let chordSet = Set(tones)
        let avoid = scalePcs.filter { !chordSet.contains($0) && chordSet.contains(($0 + 11) % 12) }
        let avoidSet = Set(avoid)

        self.tonePitchClasses = tones
        self.scalePitchClasses = scalePcs
        self.tensionPitchClasses = scalePcs.filter { !chordSet.contains($0) && !avoidSet.contains($0) }
        self.avoidPitchClasses = avoid
        self.scaleName = scale.displayName
    }
}

/// A chord positioned on the timeline of a progression, in quarter-note beats.
struct PlacedChord: Hashable, Sendable {
    var symbol: ChordSymbol
    var startBeat: Double
    var durationBeats: Double
}

struct ChordProgression: Sendable {
    let text: String
    let chords: [PlacedChord]
    let totalBeats: Double

    /// The chord sounding at a given beat position.
    func chord(at beat: Double) -> PlacedChord? {
        chords.last { beat >= $0.startBeat } ?? chords.first
    }

    /// Parses leadsheet text. Bars are separated by "|", chords within a bar by
    /// whitespace and share the bar's beats equally. An empty bar (or "%")
    /// extends the previous chord by one bar.
    static func parse(_ input: String, beatsPerBar: Double = 4) throws -> ChordProgression {
        let barTexts = input.split(separator: "|", omittingEmptySubsequences: false)
        var placed: [PlacedChord] = []
        var beatCursor = 0.0

        for barText in barTexts {
            let tokens = barText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                .filter { $0 != "%" }
            if tokens.isEmpty {
                // Empty bar: hold the previous chord for another bar.
                if !placed.isEmpty {
                    placed[placed.count - 1].durationBeats += beatsPerBar
                    beatCursor += beatsPerBar
                }
                continue
            }
            let share = beatsPerBar / Double(tokens.count)
            for token in tokens {
                let symbol = try parseChordSymbol(token)
                placed.append(PlacedChord(symbol: symbol, startBeat: beatCursor, durationBeats: share))
                beatCursor += share
            }
        }

        guard !placed.isEmpty else { throw ChordParseError.emptyInput }
        return ChordProgression(text: input, chords: placed, totalBeats: beatCursor)
    }

    static func parseChordSymbol(_ token: String) throws -> ChordSymbol {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard let (root, afterRoot) = parseRoot(Substring(trimmed)) else {
            throw ChordParseError.invalidRoot(token)
        }

        // Slash bass: split on the last "/" whose remainder reads as a note.
        var rest = afterRoot
        var bass: Int?
        if let slash = rest.lastIndex(of: "/") {
            let candidate = rest[rest.index(after: slash)...]
            if let (bassPitch, remainder) = parseRoot(candidate), remainder.isEmpty {
                bass = bassPitch
                rest = rest[..<slash]
            }
        }

        let suffix = String(rest)

        // A modal token — "C(dorian)" — names the scale instead of implying one.
        // The parentheses are what keep it out of the dictionary's way: "Cminor"
        // is a triad somebody wrote, and only "C(minor)" is a mode.
        if bass == nil, let modal = DiatonicHarmony.symbol(root: root, suffix: suffix) {
            return modal
        }

        guard let quality = ChordDictionary.quality(forSuffix: suffix) else {
            throw ChordParseError.unknownQuality(chord: token, quality: suffix)
        }

        var display = flatNoteNames[root] + ChordDictionary.displaySuffix(forKey: quality.key)
        if let bass { display += "/" + flatNoteNames[bass] }

        return ChordSymbol(
            rootPitchClass: root,
            quality: quality,
            bassPitchClass: bass,
            text: display
        )
    }

    /// Reads a note name off the front of `text`, returning its pitch class and
    /// whatever follows. Accepts single and double accidentals in ASCII or Unicode.
    static func parseRoot(_ text: Substring) -> (pitchClass: Int, rest: Substring)? {
        guard let letter = text.first,
              let base = naturalPitchClasses[Character(letter.uppercased())] else {
            return nil
        }
        var rest = text.dropFirst()

        let doubles: [(String, Int)] = [("##", 2), ("♯♯", 2), ("𝄪", 2), ("bb", -2), ("♭♭", -2), ("𝄫", -2)]
        let singles: [(String, Int)] = [("#", 1), ("♯", 1), ("b", -1), ("♭", -1)]
        for (mark, shift) in doubles + singles where rest.hasPrefix(mark) {
            rest = rest.dropFirst(mark.count)
            return (((base + shift) % 12 + 12) % 12, rest)
        }
        return (base, rest)
    }

    static let naturalPitchClasses: [Character: Int] = [
        "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11
    ]

    static let flatNoteNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    /// Human-readable name for a MIDI note number, e.g. 63 → "E♭4".
    static func noteName(forMIDINote note: Int) -> String {
        flatNoteNames[((note % 12) + 12) % 12] + String(note / 12 - 1)
    }
}
