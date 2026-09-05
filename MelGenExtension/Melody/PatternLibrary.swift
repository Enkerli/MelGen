//
//  PatternLibrary.swift
//  MelGenExtension
//
//  A library of MIDI melody patterns mapped to chord progressions. The model
//  "learns" from these at prompt time: every example is embedded in the
//  session instructions as few-shot training material. Ships with seed
//  examples; user-saved patterns persist in UserDefaults.
//

import Foundation
import Carrier

struct PatternExample: Codable, Hashable {
    /// Leadsheet progression the pattern was played over, e.g. "Dm7 G7|C∆".
    var progression: String
    /// Melody as space-separated "midiNote@startEighth:lengthEighths" tokens.
    var pattern: String
}

enum PatternLibrary {
    private static let defaultsKey = "MelGen.userPatternExamples"

    /// Built-in examples so generation works well out of the box.
    static let seedExamples: [PatternExample] = [
        PatternExample(
            progression: "Dm7 G7|C∆",
            pattern: "62@0:1 65@1:1 69@2:1 72@3:1 71@4:1 67@5:1 65@6:1 62@7:1 64@8:6 60@14:2"
        ),
        PatternExample(
            progression: "Cm7 F7|B♭∆",
            pattern: "60@0:1 63@1:1 67@2:1 70@3:1 69@4:1 65@5:1 63@6:1 60@7:1 62@8:6 58@14:2"
        ),
        PatternExample(
            progression: "C∆|Am7|F∆|G7",
            pattern: "64@0:3 67@3:1 64@4:2 62@6:2 60@8:4 57@12:4 57@16:2 60@18:2 65@20:4 62@24:2 59@26:2 62@28:4"
        )
    ]

    static var userExamples: [PatternExample] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let examples = try? JSONDecoder().decode([PatternExample].self, from: data) else {
            return []
        }
        return examples
    }

    static var allExamples: [PatternExample] {
        seedExamples + userExamples
    }

    static func addUserExample(progression: String, notes: [SequencedNote]) {
        var examples = userExamples
        let example = PatternExample(progression: progression, pattern: pattern(from: notes))
        guard !examples.contains(example) else { return }
        examples.append(example)
        if let data = try? JSONEncoder().encode(examples) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    /// Renders a note sequence in the library's compact text format
    /// (one eighth note = half a beat).
    static func pattern(from notes: [SequencedNote]) -> String {
        notes.map { note in
            let start = Int((note.startBeat * 2).rounded())
            let length = max(1, Int((note.durationBeats * 2).rounded()))
            return "\(note.note)@\(start):\(length)"
        }
        .joined(separator: " ")
    }
}
