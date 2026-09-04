// Runs the same labels through MelGen's Swift port of ProgGenie and prints the
// comparable fields as JSON, for diffing against proggen-reference.mjs.
//
// Every call here is a shape Scripts/tests/progression-main.swift already
// exercises, deliberately: this file exists to be compared, not to discover
// API. See PORTING.md §7 for what is compared and what is allowed to differ.
import Foundation

let labels = [
    "I", "Im7", "IM7", "I6", "I7",
    "IIm7", "II7", "IIm7b5", "IIø",
    "IIIm7", "III7", "IIIm7b5",
    "IV", "IVM7", "IVm7", "IV7", "IVm6",
    "V", "V7", "V7b9", "V7#5", "V7alt", "Vm7", "Vsus4",
    "VIm7", "VI7", "VIm7b5",
    "VIIm7b5", "VIIo7", "VII7",
    "♭II7", "♭IIM7", "♭IIIM7", "♭VIM7", "♭VII7", "♭VIIM7", "♭VIm7",
    "♯IVm7b5", "♯IVo7", "♯Vo7",
    "IBass", "banana", "", "VIII",
]

let keys: [(name: String, pc: Int)] = [("C", 0), ("F", 5), ("B", 11)]

var rows: [[String: Any]] = []
for label in labels {
    var row: [String: Any] = ["label": label]
    let parts = ProgressionGenerator.split(label)
    row["numeral"] = parts?.numeral ?? NSNull()
    row["suffix"] = parts?.suffix ?? NSNull()

    var realized: [String: Any] = [:]
    for key in keys {
        guard let parts,
              let offset = ProgressionGenerator.semitones(for: parts.numeral) else {
            realized[key.name] = NSNull()
            continue
        }
        // What the plug-in would actually put in the leadsheet field. nil means
        // MelGen refuses the label — which is a contract, not a failure: the
        // generator only emits changes the rest of the plug-in can play.
        guard let text = ProgressionGenerator.chordText(for: label, key: key.pc),
              let parsed = try? ChordProgression.parseChordSymbol(text) else {
            realized[key.name] = [
                "semitonesAboveTonic": ((offset % 12) + 12) % 12,
                "playable": false,
            ]
            continue
        }
        realized[key.name] = [
            "semitonesAboveTonic": ((offset % 12) + 12) % 12,
            "playable": true,
            "text": text,
            "rootPc": parsed.rootPitchClass,
            "qualityKey": parsed.quality.key,
        ]
    }
    row["realized"] = realized
    rows.append(row)
}

let data = try JSONSerialization.data(withJSONObject: rows)
print(String(data: data, encoding: .utf8)!)
