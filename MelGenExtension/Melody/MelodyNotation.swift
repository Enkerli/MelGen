//
//  MelodyNotation.swift
//  MelGenExtension
//
//  Renders a take as text you can read.
//
//  The old summary was a run of "note@beat" pairs, which showed neither how long
//  a note lasts nor where the silence is — so a line with rests in it looked
//  exactly like a line without. Here a rest gets a symbol of its own, on a grid
//  where one column is one eighth note, so phrasing is visible at a glance.
//
//  This is a stand-in for a real piano roll (ROADMAP U1), and it can't show
//  everything: gate differences smaller than an eighth don't survive the grid.
//  The summary line carries those as numbers instead.
//

import Foundation
import Carrier
import Theory

enum MelodyNotation {

    static let onsetColumnWidth = 4
    /// A note continuing through this eighth.
    static let sustain = "‑"
    /// Silence.
    static let rest = "·"

    /// One row per bar: the bar number, then one column per eighth showing a note
    /// name where a note starts, a sustain mark where one continues, and a rest
    /// mark where nothing sounds.
    static func bars(for notes: [SequencedNote],
                     lengthBeats: Double,
                     beatsPerBar: Double = 4,
                     maxBars: Int = 16) -> [String] {
        guard !notes.isEmpty, lengthBeats > 0 else { return [] }

        let eighthsPerBar = Int((beatsPerBar * 2).rounded())
        let totalEighths = max(eighthsPerBar, Int((lengthBeats * 2).rounded()))
        let barCount = min(maxBars, Int(ceil(Double(totalEighths) / Double(eighthsPerBar))))

        // Which note starts in each eighth, and which eighths it holds through.
        var onset: [Int: SequencedNote] = [:]
        var held = Set<Int>()
        for note in notes {
            let start = Int((note.startBeat * 2).rounded())
            let eighths = max(1, Int((note.durationBeats * 2).rounded()))
            onset[start] = note
            for offset in 1..<max(1, eighths) where eighths > 1 {
                held.insert(start + offset)
            }
        }

        return (0..<barCount).map { bar in
            let columns = (0..<eighthsPerBar).map { column -> String in
                let eighth = bar * eighthsPerBar + column
                guard eighth < totalEighths else { return pad("") }
                if let note = onset[eighth] {
                    return pad(ChordProgression.noteName(forMIDINote: Int(note.note)))
                }
                return pad(held.contains(eighth) ? sustain : rest)
            }
            return String(format: "%2d ", bar + 1) + columns.joined()
        }
    }

    /// Counts and ranges the grid can't show: how many phrase rests there are,
    /// and how widely gate length actually varies across the take.
    static func summary(for notes: [SequencedNote],
                        lengthBeats: Double,
                        restThreshold: Double = MelodyExpression.restThreshold) -> String {
        guard !notes.isEmpty else { return "No notes yet." }

        var rests = 0
        var gates: [Double] = []
        for (index, note) in notes.enumerated() {
            let slot: Double
            if index + 1 < notes.count {
                slot = notes[index + 1].startBeat - note.startBeat
                let gap = notes[index + 1].startBeat - (note.startBeat + note.durationBeats)
                if gap >= restThreshold - 0.001 { rests += 1 }
            } else {
                slot = max(note.durationBeats, lengthBeats - note.startBeat)
            }
            if slot > 0 {
                gates.append(min(note.durationBeats / slot, 1))
            }
        }

        let low = Int(((gates.min() ?? 0) * 100).rounded())
        let high = Int(((gates.max() ?? 0) * 100).rounded())
        let restText = rests == 1 ? "1 rest" : "\(rests) rests"
        return "\(notes.count) notes · \(restText) · gate \(low)–\(high)%"
    }

    private static func pad(_ text: String) -> String {
        // Note names are 2–4 characters ("C3", "E♭3"), so a fixed column keeps
        // the grid aligned in a monospaced font.
        let padding = max(0, onsetColumnWidth - text.count)
        return text + String(repeating: " ", count: padding)
    }
}
