// Checks the MIDI file codec, the harmony tiers, and chord detection.
//
// Three claims.
//
// *A file written here reads back here.* The codec is the one place in this
// app where a one-byte mistake turns into music nobody wrote — a controller
// event skipped by the wrong length decodes the rest of the track as noise —
// so the round trip is asserted note for note rather than in aggregate.
//
// *The harmony tiers are ordered, and each one works alone.* A file carrying
// the suite's leadsheet payload must use it; one carrying only markers must
// fall to them; one carrying only a chord track must read it; and one carrying
// nothing must still import, and say so, rather than inventing changes.
//
// *Detection agrees with the suite.* The vectors are the reference
// implementation's own, so this is a cross-language check rather than a
// restatement of the port. Root and quality are compared, not the printed
// symbol: MelGen spells chords the way `ChordParser` writes them, and matching
// the suite's display strings would mean disagreeing with every other chord
// name in the app.
import Foundation
import Carrier
import Theory

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

// MARK: - The codec round-trips

print("── a file written here reads back here ────────────────")

let line = [
    SequencedNote(note: 60, velocity: 90, startBeat: 0, durationBeats: 0.5),
    SequencedNote(note: 63, velocity: 80, startBeat: 0.5, durationBeats: 0.5),
    SequencedNote(note: 67, velocity: 100, startBeat: 1, durationBeats: 1),
    SequencedNote(note: 70, velocity: 70, startBeat: 2.5, durationBeats: 1.5),
    // The same pitch twice in a row, which is where a note-off ordering bug
    // shows up as one long note instead of two.
    SequencedNote(note: 70, velocity: 70, startBeat: 4, durationBeats: 1),
]

let written = MIDIExport.write(notes: line,
                               progressionText: "Cm7|F7|B♭∆|%",
                               name: "Round trip",
                               beatsPerMinute: 96)
let readBack = try StandardMIDIFile.read(written)

check("the header says what was written",
      readBack.format == 0 && readBack.ticksPerBeat == 480)
check("the tempo survived", abs(readBack.beatsPerMinute - 96) < 0.5,
      "\(readBack.beatsPerMinute)")
check("every note came back", readBack.allNotes.count == line.count,
      "\(readBack.allNotes.count) of \(line.count)")

let pairs = zip(readBack.allNotes.sorted { $0.startBeat < $1.startBeat },
                line.sorted { $0.startBeat < $1.startBeat })
check("pitches, positions and lengths are unchanged",
      pairs.allSatisfy { file, original in
          file.pitch == Int(original.note)
              && abs(file.startBeat - original.startBeat) < 0.001
              && abs(file.durationBeats - original.durationBeats) < 0.001
      })
check("a repeated pitch stays two notes",
      readBack.allNotes.filter { $0.pitch == 70 }.count == 2)
check("the track name came back", readBack.tracks.first?.name == "Round trip")

// MARK: - Tier one: the file's own leadsheet

print("── the harmony tiers, in order ────────────────────────")

let roundTripped = try MIDIImport.read(written, name: "Round trip.mid")
check("a file we wrote reads its own leadsheet back",
      roundTripped.harmonySource == .embedded,
      roundTripped.harmonySource.rawValue)
check("and the changes are the changes",
      roundTripped.progressionText == "Cm7|F7|B♭∆",
      roundTripped.progressionText ?? "nil")
check("which still parses", (try? ChordProgression.parse(roundTripped.progressionText ?? "")) != nil)
check("the line reads as degrees against them", roundTripped.pattern != nil)

// The payload the suite writes, verbatim in shape: this is the format
// `packages/midi/leadsheet-smf.ts` emits, so a MIDIcurator file lands here.
let suiteJSON = """
{"key":{"tonic":"F","mode":"major"},"sections":[{"bars":[\
{"chords":[{"source":"absolute","symbol":{"root":"G","suffix":"m7"}}]},\
{"chords":[{"source":"absolute","symbol":{"root":"C","suffix":"7"}}]},\
{"chords":[{"source":"absolute","symbol":{"root":"F","suffix":"∆"}}]},\
{"chords":[],"repeat":true}]}]}
"""
let foreign = StandardMIDIFile.write(
    notes: line,
    markers: [],
    textEvents: [MIDIImport.progressionPrefix + suiteJSON],
    trackName: "From the suite")
let fromSuite = try MIDIImport.read(foreign, name: "suite.mid")
check("a suite-written payload is read as the leadsheet",
      fromSuite.harmonySource == .embedded && fromSuite.progressionText == "Gm7|C7|F∆",
      fromSuite.progressionText ?? "nil")

let verbatim = """
{"key":{"tonic":"C","mode":"major"},"sections":[{"bars":[\
{"chords":[{"source":"absolute","inputText":"D-7","symbol":{"root":"D","suffix":"m7"}}]},\
{"chords":[{"source":"absolute","inputText":"G7","symbol":{"root":"G","suffix":"7"}}]}]}]}
"""
let kept = StandardMIDIFile.write(notes: line, textEvents: [MIDIImport.progressionPrefix + verbatim])
check("the author's own spelling wins over the derived symbol",
      try MIDIImport.read(kept, name: "verbatim.mid").progressionText == "D-7|G7")

// MARK: - Tier two: markers

let markered = StandardMIDIFile.write(
    notes: line,
    markers: [MIDIFileText(beat: 0, text: "Dm7", metaType: 0x06),
              MIDIFileText(beat: 4, text: "G7", metaType: 0x06),
              MIDIFileText(beat: 8, text: "C∆", metaType: 0x06),
              // A rehearsal mark, which must not be read as harmony.
              MIDIFileText(beat: 8, text: "Verse 1", metaType: 0x06)],
    trackName: "Markers")
let fromMarkers = try MIDIImport.read(markered, name: "markers.mid")
check("markers are the second tier",
      fromMarkers.harmonySource == .marker, fromMarkers.harmonySource.rawValue)
check("and they map onto bars",
      fromMarkers.progressionText == "Dm7|G7|C∆", fromMarkers.progressionText ?? "nil")
check("a rehearsal mark isn't harmony",
      !MIDIImport.looksLikeChord("Verse 1") && MIDIImport.looksLikeChord("Dm7"))

// MARK: - Tier three: a chord track

// Block voicings on their own track, one a bar, plus a line to read against.
var chordTrackFile: [SequencedNote] = []
let voicings: [(beat: Double, pitches: [Int])] = [
    (0, [62, 65, 69, 72]),   // Dm7
    (4, [67, 71, 74, 77]),   // G7
    (8, [60, 64, 67, 71]),   // C∆
]
for voicing in voicings {
    for pitch in voicing.pitches {
        chordTrackFile.append(SequencedNote(note: UInt8(pitch), velocity: 80,
                                            startBeat: voicing.beat, durationBeats: 4))
    }
}
let chordOnly = StandardMIDIFile.write(notes: chordTrackFile, trackName: "Chords")
let fromChords = try MIDIImport.read(chordOnly, name: "chords.mid")
check("a chord track is the third tier",
      fromChords.harmonySource == .chordTrack, fromChords.harmonySource.rawValue)
// "Cmaj7", not "C∆": a detected chord is spelled the way `ChordParser` writes
// one, which is the whole point of not copying the suite's display strings.
check("and it names what was voiced",
      fromChords.progressionText == "Dm7|G7|Cmaj7", fromChords.progressionText ?? "nil")

// MARK: - Tier four: nothing

let bare = StandardMIDIFile.write(notes: line, trackName: "Just a tune")
let fromNothing = try MIDIImport.read(bare, name: "bare.mid")
check("a file with no harmony still imports",
      fromNothing.harmonySource == .none && !fromNothing.melody.isEmpty)
check("and says what it can't do rather than guessing",
      fromNothing.progressionText == nil
        && fromNothing.warnings.contains { $0.contains("degree") },
      fromNothing.warnings.joined(separator: " / "))

// MARK: - Detection

print("── naming a chord from the notes ──────────────────────")

check("a major triad", ChordDetection.detect(pitchClasses: [0, 4, 7])?.quality.key == "maj")
check("a minor seventh", ChordDetection.detect(pitchClasses: [2, 5, 9, 0])?.quality.key == "min7")
check("a dominant seventh, rooted correctly",
      ChordDetection.detect(pitchClasses: [7, 11, 2, 5]).map {
          ($0.rootPitchClass, $0.quality.key)
      }.map { $0 == 7 && $1 == "7" } == true)
check("one note is not a chord", ChordDetection.detect(pitchClasses: [4]) == nil)
check("register makes a slash chord",
      ChordDetection.detect(pitches: [57, 62, 65, 69])?.bassPitchClass == 9)
check("and pitch classes alone never do",
      ChordDetection.detect(pitchClasses: [2, 5, 9, 0])?.bassPitchClass == nil)
check("an extra note is reported rather than hidden",
      ChordDetection.detect(pitchClasses: [0, 4, 7, 11, 2])?.extras.isEmpty == false
        || ChordDetection.detect(pitchClasses: [0, 4, 7, 11, 2])?.quality.key == "maj9")
check("every detected symbol re-parses as itself",
      (0..<12).allSatisfy { root in
          guard let detected = ChordDetection.detect(pitchClasses: [root, root + 4, root + 7, root + 10])
          else { return false }
          guard let parsed = try? ChordProgression.parseChordSymbol(detected.symbol) else { return false }
          return parsed.rootPitchClass == detected.rootPitchClass
              && parsed.quality.key == detected.quality.key
      })
check("detection is deterministic across runs",
      (0..<50).allSatisfy { _ in
          ChordDetection.detect(pitchClasses: [0, 3, 6, 10])?.quality.key
              == ChordDetection.detect(pitchClasses: [0, 3, 6, 10])?.quality.key
      })

// MARK: - The suite's own vectors, when they're here

if let path = ProcessInfo.processInfo.environment["CHORD_VECTORS"],
   let data = FileManager.default.contents(atPath: path) {
    struct Vectors: Decodable {
        struct Match: Decodable {
            var root: Int
            var qualityKey: String
            var symbol: String
            var bassPc: Int?
        }
        struct Case: Decodable { var name: String; var pcs: [Int]; var match: Match? }
        /// The slash cases carry MIDI pitches rather than pitch classes,
        /// because which note is *underneath* is the whole point of them.
        struct SlashCase: Decodable { var name: String; var pitches: [Int]; var match: Match }
        var dictionarySize: Int
        var cases: [Case]
        var slashCases: [SlashCase]
    }
    let vectors = try JSONDecoder().decode(Vectors.self, from: data)
    check("the dictionary is the same size on both sides",
          vectors.dictionarySize == ChordDictionary.allQualities.count,
          "suite \(vectors.dictionarySize), MelGen \(ChordDictionary.allQualities.count)")

    var agreed = 0
    var disagreed: [String] = []
    for testCase in vectors.cases {
        let detected = ChordDetection.detect(pitchClasses: testCase.pcs)
        guard let expected = testCase.match else {
            if detected == nil { agreed += 1 } else { disagreed.append("\(testCase.name): expected none") }
            continue
        }
        if detected?.rootPitchClass == expected.root && detected?.quality.key == expected.qualityKey {
            agreed += 1
        } else {
            disagreed.append("\(testCase.name): suite \(expected.root)/\(expected.qualityKey), "
                             + "MelGen \(detected.map { "\($0.rootPitchClass)/\($0.quality.key)" } ?? "none")")
        }
    }
    check("every vector agrees on root and quality",
          disagreed.isEmpty,
          disagreed.isEmpty ? "\(agreed) cases" : disagreed.prefix(4).joined(separator: "; "))

    var slashDisagreed: [String] = []
    for testCase in vectors.slashCases {
        let detected = ChordDetection.detect(pitches: testCase.pitches)
        let agrees = detected?.rootPitchClass == testCase.match.root
            && detected?.quality.key == testCase.match.qualityKey
            && detected?.bassPitchClass == testCase.match.bassPc
        if !agrees {
            slashDisagreed.append("\(testCase.name): MelGen "
                + (detected.map { "\($0.rootPitchClass)/\($0.quality.key) bass \($0.bassPitchClass.map(String.init) ?? "none")" } ?? "none"))
        }
    }
    check("and every inversion finds the same bass",
          slashDisagreed.isEmpty,
          slashDisagreed.isEmpty ? "\(vectors.slashCases.count) cases"
                                 : slashDisagreed.joined(separator: "; "))
} else {
    print("  SKIP  suite chord-detection vectors (set CHORD_VECTORS=…/chord-detection.json)")
}

// MARK: - The same reading, pointed at playing

print("── changes read off notes, not off a file ─────────────")

var played: [SequencedNote] = []
for voicing in voicings {
    for pitch in voicing.pitches {
        played.append(SequencedNote(note: UInt8(pitch), velocity: 80,
                                    startBeat: voicing.beat, durationBeats: 4))
    }
}
let readLive = ChordDetection.changes(in: played.map(\.sounding))
check("playing the changes in reads them back",
      readLive?.text == "Dm7|G7|Cmaj7", readLive?.text ?? "nil")
check("and every bar was nameable",
      readLive?.namedBars == readLive?.totalBars && readLive?.namedBars == 3)
check("block voicings don't read as arpeggiated",
      readLive?.looksArpeggiated == false)
check("an import and live playing agree, because it is one implementation",
      readLive?.text == fromChords.progressionText)

// The same notes, one at a time: still a chord track by pitch content, and
// still a guess by construction — the import and this both have to say so.
var rolled: [SequencedNote] = []
for voicing in voicings {
    for (index, pitch) in voicing.pitches.enumerated() {
        rolled.append(SequencedNote(note: UInt8(pitch), velocity: 80,
                                    startBeat: voicing.beat + Double(index) * 0.5,
                                    durationBeats: 0.5))
    }
}
check("an arpeggio is read, and flagged as a guess",
      ChordDetection.changes(in: rolled.map(\.sounding))?.looksArpeggiated == true)
// A melody will always spell *something* — four notes in a bar are four pitch
// classes and the dictionary has 172 entries. The answer isn't to refuse it,
// it's to never present it as read rather than inferred.
check("a single line still names something, and is never presented as read",
      ChordDetection.changes(in: line.map(\.sounding)).map { !$0.text.isEmpty && $0.looksArpeggiated } == true,
      ChordDetection.changes(in: line.map(\.sounding))?.text ?? "nil")
check("which means only real voicings are confident",
      ChordDetection.changes(in: line.map(\.sounding))?.isConfident == false
        && readLive?.isConfident == true)

print()
print(failures == 0 ? "midifile: all checks passed" : "midifile: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
