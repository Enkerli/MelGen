//
//  MIDIFileImport.swift
//  MelGenExtension
//
//  What a `.mid` file *means* — the half `StandardMIDIFile` deliberately leaves
//  alone. ROADMAP S2's in-app reader and X4, and the reason MelGen and
//  MIDIcurator can now hand each other a file.
//
//  The whole difficulty is harmony. A pattern in this app is a run of scale
//  degrees relative to whatever chord is sounding, and that is what makes a
//  line reusable over other changes. A MIDI file is pitches. So the question
//  every import has to answer first is *where do the chords come from*, and the
//  answer has four tiers, in descending order of how much they can be trusted:
//
//  1. **An embedded progression.** A file written by the suite carries the
//     whole leadsheet as an `MCURATOR:v1 PROG` text meta event — the format
//     `packages/midi/leadsheet-smf.ts` writes, and the one MIDIcurator and
//     ProgGenie already speak. Lossless, because a machine wrote it for this.
//  2. **Chord-symbol markers.** Positioned text a human or an exporter left.
//     Common in files from notation software, and it is also the belt to tier
//     one's braces: the suite's exporter writes a marker per chord, so a
//     progression authored in Roman numerals still arrives as absolute symbols
//     here even when the payload can't be read as text.
//  3. **A chord track.** Real harmony, but as pitches, so it goes through
//     `ChordDetection`. Block voicings read correctly; an *arpeggiated* chord
//     track comes out as a run of wrong triads, which is why it is last and why
//     the import says so.
//  4. **Nothing.** The file still reads. It just can't contribute degrees —
//     only rhythm and contour — and that is stated rather than guessed at.
//
//  The tiers are the same ones `Scripts/training/midi_to_events.py` uses on the
//  desktop, minus its `<stem>.chords` sidecar (a document picker hands over one
//  file, not a directory) and plus tier one, which the Python doesn't read yet.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

/// Where the harmony came from, which is the fact that decides how much to
/// trust everything downstream.
enum HarmonySource: String, Codable, Sendable, CaseIterable {
    case embedded, marker, chordTrack, none

    var label: String {
        switch self {
        case .embedded: return "from the file's own leadsheet"
        case .marker: return "from chord markers"
        case .chordTrack: return "read off a chord track"
        case .none: return "no harmony in the file"
        }
    }

    /// Whether a degree read against this harmony is worth learning from.
    var isTrustworthy: Bool { self != .none }
}

/// One file, read.
struct MIDIFileImport: Sendable {
    var name: String
    /// Leadsheet text `ChordProgression.parse` accepts, when harmony was found.
    var progressionText: String?
    var harmonySource: HarmonySource
    /// The melodic line, as played, in beats from the start of the file.
    var melody: [SequencedNote]
    /// The line as degrees, when there was harmony to read it against.
    var pattern: MelodyPattern?
    var beatsPerBar: Double
    var beatsPerMinute: Double
    /// Everything the reader had to decide rather than know.
    var warnings: [String]

    var noteCount: Int { melody.count }

    var summary: String {
        var parts = ["\(melody.count) notes", harmonySource.label]
        if let text = progressionText, !text.isEmpty {
            parts.append(text.split(separator: "|").count == 1
                         ? text : "\(text.split(separator: "|").count) bars")
        }
        return parts.joined(separator: " · ")
    }
}

enum MIDIImport {

    /// Marker prefix for the embedded progression — the suite's MCURATOR family.
    static let progressionPrefix = "MCURATOR:v1 PROG "

    /// Names a track is likely to give itself.
    private static let melodyNames = ["melody", "lead", "solo", "tune", "line", "theme"]
    private static let chordNames = ["chord", "comp", "harmon", "changes", "pad", "block", "voicing"]

    // MARK: - The whole job

    static func read(_ data: Data, name: String) throws -> MIDIFileImport {
        let file = try StandardMIDIFile.read(data)
        var warnings: [String] = []

        let playable = file.tracks.filter { !$0.isDrums && !$0.notes.isEmpty }
        if playable.count < file.tracks.filter({ !$0.notes.isEmpty }).count {
            warnings.append("A drum track was left out — it has no degrees to give.")
        }

        let chordTrack = pickChordTrack(from: playable)
        let melodyTrack = pickMelodyTrack(from: playable, excluding: chordTrack)

        let harmony = readHarmony(file: file, chordTrack: chordTrack, warnings: &warnings)

        let melodyNotes = (melodyTrack?.notes ?? []).map {
            SequencedNote(note: UInt8(clamping: $0.pitch),
                          velocity: UInt8(clamping: $0.velocity),
                          startBeat: $0.startBeat,
                          durationBeats: $0.durationBeats)
        }
        if melodyNotes.isEmpty {
            warnings.append("No melodic track was found — every track was drums, harmony, or empty.")
        }

        var pattern: MelodyPattern?
        if let text = harmony.text,
           let progression = try? ChordProgression.parse(text, beatsPerBar: file.beatsPerBar),
           !melodyNotes.isEmpty {
            pattern = MelodyPatterns.extract(
                from: melodyNotes,
                over: progression,
                name: patternName(from: name),
                lengthBeats: max(progression.totalBeats, file.endBeat),
                origin: PatternOrigin(progressionText: text,
                                      briefName: patternName(from: name),
                                      source: .captured))
            if pattern == nil {
                warnings.append("The line wouldn't read as degrees against those changes.")
            }
        } else if harmony.text == nil && !melodyNotes.isEmpty {
            warnings.append("Without harmony this file can teach rhythm and contour, "
                            + "but not a single degree.")
        }

        return MIDIFileImport(name: name,
                              progressionText: harmony.text,
                              harmonySource: harmony.source,
                              melody: melodyNotes,
                              pattern: pattern,
                              beatsPerBar: file.beatsPerBar,
                              beatsPerMinute: file.beatsPerMinute,
                              warnings: warnings)
    }

    // MARK: - Where the chords come from

    private static func readHarmony(file: StandardMIDIFile,
                                    chordTrack: MIDIFileTrack?,
                                    warnings: inout [String]) -> (text: String?, source: HarmonySource) {
        if let embedded = embeddedProgression(in: file.texts) {
            return (embedded, .embedded)
        }
        if let markers = markerProgression(in: file.texts,
                                           beatsPerBar: file.beatsPerBar,
                                           endBeat: file.endBeat) {
            return (markers, .marker)
        }
        if let track = chordTrack,
           let detected = detectedProgression(from: track,
                                              beatsPerBar: file.beatsPerBar,
                                              endBeat: file.endBeat,
                                              warnings: &warnings) {
            return (detected, .chordTrack)
        }
        return (nil, .none)
    }

    /// Tier one: the leadsheet the file carries about itself.
    ///
    /// Only the absolute view is read. A chord authored as a Roman numeral has
    /// to be realized against the key to become a symbol, and the same exporter
    /// writes a marker per chord carrying exactly that realization — so the
    /// answer to a degree-only payload is tier two, not a second realizer here
    /// that could disagree with the suite's.
    static func embeddedProgression(in texts: [MIDIFileText]) -> String? {
        for event in texts where event.text.hasPrefix(progressionPrefix) {
            let json = String(event.text.dropFirst(progressionPrefix.count))
            guard let data = json.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(SuiteProgression.self, from: data)
            else { continue }
            let text = payload.leadsheetText
            if !text.isEmpty, (try? ChordProgression.parse(text)) != nil { return text }
        }
        return nil
    }

    /// Tier two: positioned chord symbols, mapped onto bars.
    ///
    /// Two chords landing in one bar share it equally, which is what MelGen's
    /// own leadsheet format can express. Uneven placement is flattened, and the
    /// caller is told so by the source rather than by silence.
    static func markerProgression(in texts: [MIDIFileText],
                                  beatsPerBar: Double,
                                  endBeat: Double) -> String? {
        let symbols = texts.filter { $0.metaType == 0x01 || $0.metaType == 0x06 }
            .compactMap { event -> (bar: Int, text: String)? in
                let trimmed = event.text.trimmingCharacters(in: .whitespaces)
                guard looksLikeChord(trimmed) else { return nil }
                return (Int(event.beat / max(1, beatsPerBar)), trimmed)
            }
        guard !symbols.isEmpty else { return nil }

        let lastBar = max(symbols.map(\.bar).max() ?? 0,
                          Int(ceil(endBeat / max(1, beatsPerBar))) - 1)
        var bars: [String] = []
        for bar in 0...max(0, lastBar) {
            let inBar = symbols.filter { $0.bar == bar }.map(\.text)
            // An empty bar holds the previous chord, which is what the parser
            // does with it and what a marker's absence actually means.
            bars.append(inBar.joined(separator: " "))
        }
        while bars.last?.isEmpty == true { bars.removeLast() }
        guard bars.contains(where: { !$0.isEmpty }) else { return nil }
        let text = bars.joined(separator: "|")
        return (try? ChordProgression.parse(text)) != nil ? text : nil
    }

    /// Tier three: harmony as pitches, named by the dictionary.
    ///
    /// The reading itself is `ChordDetection.changes`, shared with "what did I
    /// just play" — an imported chord track and a captured comp are the same
    /// question, and two implementations of it would drift apart.
    static func detectedProgression(from track: MIDIFileTrack,
                                    beatsPerBar: Double,
                                    endBeat: Double,
                                    warnings: inout [String]) -> String? {
        let notes = track.notes.map {
            SequencedNote(note: UInt8(clamping: $0.pitch),
                          velocity: UInt8(clamping: $0.velocity),
                          startBeat: $0.startBeat,
                          durationBeats: $0.durationBeats)
        }
        guard let read = ChordDetection.changes(in: notes,
                                                beatsPerBar: beatsPerBar,
                                                endBeat: endBeat) else { return nil }
        if read.namedBars < read.totalBars {
            warnings.append("\(read.totalBars - read.namedBars) of \(read.totalBars) bars had no "
                            + "nameable chord and hold the one before.")
        }
        if read.looksArpeggiated {
            warnings.append("The chord track looks arpeggiated rather than blocked, so these "
                            + "names are a guess — one chord a bar read off a moving line.")
        }
        return read.text
    }

    // MARK: - Choosing tracks

    static func pickChordTrack(from tracks: [MIDIFileTrack]) -> MIDIFileTrack? {
        if let named = tracks.first(where: { matches($0.name, chordNames) }) { return named }
        // Otherwise the most polyphonic one, and only if it really is: a track
        // that never plays two notes at once isn't a chord track however it is
        // named.
        let scored = tracks.map { ($0, polyphony(of: $0)) }.filter { $0.1 >= 2.0 }
        return scored.max { $0.1 < $1.1 }?.0
    }

    static func pickMelodyTrack(from tracks: [MIDIFileTrack],
                                excluding chords: MIDIFileTrack?) -> MIDIFileTrack? {
        let available = tracks.filter { $0 != chords }
        if let named = available.first(where: { matches($0.name, melodyNames) }) { return named }
        // The most monophonic track with the most notes: a melody is the part
        // that plays one thing at a time and keeps doing it.
        return available.min {
            (polyphony(of: $0), -$0.notes.count) < (polyphony(of: $1), -$1.notes.count)
        } ?? tracks.first { $0 != chords }
    }

    /// Average notes sounding at each onset. 1 is a line; 3 is a voicing.
    static func polyphony(of track: MIDIFileTrack) -> Double {
        guard !track.notes.isEmpty else { return 0 }
        let starts = Set(track.notes.map { ($0.startBeat * 48).rounded() })
        return Double(track.notes.count) / Double(max(1, starts.count))
    }

    private static func matches(_ name: String, _ words: [String]) -> Bool {
        let lowered = name.lowercased()
        return words.contains { lowered.contains($0) }
    }

    /// Permissive on purpose. The authority on whether a symbol parses is
    /// `ChordProgression.parse`; this only has to keep "Verse 1" from being
    /// mapped onto a bar as harmony.
    static func looksLikeChord(_ text: String) -> Bool {
        guard let first = text.first, "ABCDEFG".contains(first), text.count <= 12 else {
            return false
        }
        return (try? ChordProgression.parseChordSymbol(text)) != nil
    }

    private static func patternName(from fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        return stem.isEmpty ? "Imported" : stem
    }
}

// MARK: - The suite's leadsheet payload

/// Just enough of `@enkerli/theory`'s `Progression` to read one back.
///
/// Decoded rather than shared because the suite is TypeScript: this is the wire
/// format, and the fields not named here (`key`, `meta`, section keys) are the
/// ones MelGen's flat leadsheet text has nowhere to put.
struct SuiteProgression: Decodable, Sendable {
    struct Symbol: Decodable, Sendable {
        var root: String
        var suffix: String
        var bass: String?
    }

    struct Chord: Decodable, Sendable {
        var symbol: Symbol?
        var inputText: String?
    }

    struct Bar: Decodable, Sendable {
        var chords: [Chord]?
        var `repeat`: Bool?
    }

    struct Section: Decodable, Sendable {
        var bars: [Bar]
    }

    var sections: [Section]

    /// The progression as leadsheet text MelGen's parser reads.
    ///
    /// `inputText` wins where it exists — it is the verbatim token the author
    /// typed, kept by the suite precisely so an unrecognised quality survives a
    /// round trip. Sections are concatenated: MelGen's format has no way to say
    /// "A section", and dropping the labels loses less than dropping the bars.
    var leadsheetText: String {
        var bars: [String] = []
        for section in sections {
            for bar in section.bars {
                if bar.repeat == true {
                    bars.append("")
                    continue
                }
                let tokens = (bar.chords ?? []).compactMap { chord -> String? in
                    if let text = chord.inputText, !text.isEmpty { return text }
                    guard let symbol = chord.symbol else { return nil }
                    let slash = symbol.bass.map { "/" + $0 } ?? ""
                    return symbol.root + symbol.suffix + slash
                }
                bars.append(tokens.joined(separator: " "))
            }
        }
        while bars.last?.isEmpty == true { bars.removeLast() }
        return bars.joined(separator: "|")
    }
}
