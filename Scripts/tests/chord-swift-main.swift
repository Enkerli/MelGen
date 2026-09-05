// Runs the same symbols through MelGen's Swift port and prints the reference
// fields as JSON, for diffing against the TypeScript output.
import Foundation
import Theory

let symbols = [
    "C", "Cmaj7", "C∆", "CM7", "Cmaj9", "C6", "C69", "Cadd9", "Cadd11",
    "Cm", "Cmin", "C-", "Cm7", "Cmin7", "C-7", "Cm9", "Cm11", "Cm6", "CmM7", "CminMaj7",
    "C7", "C9", "C11", "C13", "C7sus4", "C7sus", "C9sus4", "C7b9", "C7#9", "C7#11",
    "C7b5", "C7#5", "C7b13", "C9b13", "C7alt", "Calt7",
    "Cdim", "Cdim7", "Co7", "Cm7b5", "Cø", "Ch7", "C+", "Caug", "CaugMaj7",
    "Csus2", "Csus4", "Csus", "C5", "Cquartal",
    "Cmaj13", "C∆9", "Cmaj#4", "CM7#11", "C69#11", "CM13#11",
    "Ebm7", "E♭m7", "F#7b9", "Bb∆", "A♭6", "Gm9", "D∆", "Dm7/G", "Cmaj7/E", "Bbmaj7/D",
    "Fmi7", "Fmin9", "Cm7add11", "C7add13", "Cphryg", "Csusb9",
]

var rows: [[String: Any]] = []
for symbol in symbols {
    do {
        let parsed = try ChordProgression.parseChordSymbol(symbol)
        rows.append([
            "symbol": symbol,
            "key": parsed.quality.key,
            "rootPc": parsed.rootPitchClass,
            "tones": Array(Set(parsed.tonePitchClasses)).sorted(),
            "scale": String(describing: Scale.allCases.first { $0.displayName == parsed.scaleName }
                            ?? .ionian),
            "scalePcs": parsed.scalePitchClasses.sorted(),
            "avoid": parsed.avoidPitchClasses.sorted(),
            "tensions": parsed.tensionPitchClasses.sorted(),
        ])
    } catch let error as ChordParseError {
        switch error {
        case .invalidRoot: rows.append(["symbol": symbol, "error": "unparsed"])
        case .unknownQuality: rows.append(["symbol": symbol, "error": "unknownQuality"])
        case .emptyInput: rows.append(["symbol": symbol, "error": "empty"])
        }
    }
}

let data = try JSONSerialization.data(withJSONObject: rows)
print(String(data: data, encoding: .utf8)!)
