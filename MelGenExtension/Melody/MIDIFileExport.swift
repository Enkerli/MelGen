//
//  MIDIFileExport.swift
//  MelGenExtension
//
//  A take as a `.mid` — ROADMAP X1, with X3's chord information included
//  rather than deferred.
//
//  Export and import are one feature, not two, and writing them apart is how
//  interchange formats rot. Everything `MIDIFileImport` knows how to read is
//  written here: per-chord markers a DAW displays, and the same
//  `MCURATOR:v1 PROG` payload the suite's `leadsheet-smf.ts` writes, so a take
//  that leaves MelGen and comes back arrives with its changes intact — and so
//  does one that goes to MIDIcurator instead.
//
//  What is deliberately *not* written: a track of block chords. The suite's
//  exporter includes one because its files are progressions; MelGen's are
//  lines, and a second track of comping nobody asked to hear is a surprise in
//  someone else's session. The harmony rides as metadata, where it can be read
//  without being played.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

enum MIDIExport {

    /// Writes a take, with its changes carried as markers and as the payload.
    static func write(notes: [SequencedNote],
                      progressionText: String,
                      name: String,
                      beatsPerMinute: Double = 120) -> Data {
        let progression = try? ChordProgression.parse(progressionText)
        let markers = (progression?.chords ?? []).map {
            MIDIFileText(beat: $0.startBeat, text: $0.symbol.text, metaType: 0x06)
        }
        var payloads: [String] = []
        if !progressionText.isEmpty, let json = suitePayload(for: progressionText) {
            payloads.append(MIDIImport.progressionPrefix + json)
        }

        return StandardMIDIFile.write(notes: notes,
                                      markers: markers,
                                      textEvents: payloads,
                                      trackName: name,
                                      beatsPerMinute: beatsPerMinute,
                                      beatsPerBar: 4)
    }

    /// The leadsheet as the suite's `Progression`, JSON-encoded.
    ///
    /// Written from the *text* rather than from the parsed chords, so an
    /// unrecognised quality survives as `inputText` — which is the field the
    /// suite added for exactly this and the reason a round trip through a
    /// foreign app doesn't quietly normalize somebody's chord spelling.
    static func suitePayload(for progressionText: String) -> String? {
        var bars: [[String: Any]] = []
        for barText in progressionText.split(separator: "|", omittingEmptySubsequences: false) {
            let tokens = barText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                .filter { $0 != "%" }
            if tokens.isEmpty {
                bars.append(["chords": [], "repeat": true])
                continue
            }
            let chords: [[String: Any]] = tokens.map { token in
                var chord: [String: Any] = ["source": "absolute", "inputText": token]
                if let symbol = try? ChordProgression.parseChordSymbol(token),
                   let (_, rest) = ChordProgression.parseRoot(Substring(token)) {
                    var absolute: [String: Any] = [
                        "root": ChordProgression.flatNoteNames[symbol.rootPitchClass],
                        "suffix": String(rest).split(separator: "/").first.map(String.init) ?? "",
                    ]
                    if let bass = symbol.bassPitchClass {
                        absolute["bass"] = ChordProgression.flatNoteNames[bass]
                    }
                    chord["symbol"] = absolute
                }
                return chord
            }
            bars.append(["chords": chords])
        }
        while let last = bars.last, (last["repeat"] as? Bool) == true { bars.removeLast() }

        let progression: [String: Any] = [
            // MelGen's leadsheet is absolute throughout, so the key is only
            // here because the suite's type requires one. Nothing reads it back.
            "key": ["tonic": "C", "mode": "major"],
            "sections": [["bars": bars]],
        ]
        guard JSONSerialization.isValidJSONObject(progression),
              let data = try? JSONSerialization.data(withJSONObject: progression,
                                                     options: [.sortedKeys])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// A filename that says what the file is without needing the app open.
    static func fileName(for name: String, progressionText: String) -> String {
        let stem = name.isEmpty ? "MelGen take" : name
        let cleaned = stem.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
            .joined(separator: "-")
        return cleaned + ".mid"
    }
}
