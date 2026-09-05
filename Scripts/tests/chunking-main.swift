// Checks how a progression is split into model requests. The 16-bar case is the
// real ProgGenie progression that used to fail outright.
import Foundation
import Theory

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let shortText = "E♭7 Gm9|D∆|A♭6"
let progGenieText = "Cmaj7 | Em7♭5 | A7 | D7 | Ddim | Dm7 | G7 | Gm7 "
    + "| A7 | D7 | Edim7 | Am7 | Dm7 | G7 | Dm7 | G7"

let short = try ChordProgression.parse(shortText)
let long = try ChordProgression.parse(progGenieText)

// The premise: the long progression parses. Only generation used to fail.
check("ProgGenie progression parses", long.chords.count == 16,
      "\(long.chords.count) chords, \(long.totalBeats) beats")

// Short progressions stay a single request — no behaviour change there.
let shortChunks = MelodyChunker.chunks(for: short)
check("3-bar progression stays one request", shortChunks.count == 1,
      "\(shortChunks.count) chunk(s)")
check("single chunk keeps the whole progression",
      shortChunks[0].beats == short.totalBeats
      && shortChunks[0].progression.chords.count == short.chords.count)

// 16 bars becomes four 4-bar requests.
let chunks = MelodyChunker.chunks(for: long)
check("16 bars splits into 4 requests", chunks.count == 4, "\(chunks.count) chunks")
check("every chunk is at most 4 bars",
      chunks.allSatisfy { $0.beats <= 16.0 + 1e-9 },
      "sizes \(chunks.map(\.beats))")

// Coverage: the chunks must tile the progression exactly, with no gap or overlap.
var cursor = 0.0
var contiguous = true
for chunk in chunks {
    if abs(chunk.startBeat - cursor) > 1e-9 { contiguous = false }
    cursor += chunk.beats
}
check("chunks tile the progression with no gaps or overlaps", contiguous)
check("chunks cover the whole progression", abs(cursor - long.totalBeats) < 1e-9,
      "covered \(cursor) of \(long.totalBeats)")

// Each chunk is rebased to start at beat 0, so eighth indices stay small.
check("each chunk is rebased to zero",
      chunks.allSatisfy { ($0.progression.chords.first?.startBeat ?? 0) < 1e-9 })
check("chunk eighth offsets step by 32", chunks.map(\.startEighth) == [0, 32, 64, 96],
      "\(chunks.map(\.startEighth))")
check("bar ranges are reported 1-based",
      chunks.map(\.bars) == [1...4, 5...8, 9...12, 13...16],
      "\(chunks.map { "\($0.bars.lowerBound)-\($0.bars.upperBound)" })")

// No chunk may be harmonically empty, or the model gets no plan for those bars.
check("every chunk carries harmony", chunks.allSatisfy { !$0.progression.chords.isEmpty },
      "counts \(chunks.map(\.progression.chords.count))")

// Every chord must survive into some chunk.
let placedTotal = chunks.reduce(0) { $0 + $1.progression.chords.count }
check("all 16 chords appear across the chunks", placedTotal == 16, "\(placedTotal)")

// A chord straddling a boundary appears in every chunk it sounds in, clipped.
// "Cmaj7||Dm7|" is two bars of Cmaj7 then two of Dm7 (an empty bar extends the
// previous chord); split one bar at a time, each chord shows up twice.
let straddle = try ChordProgression.parse("Cmaj7||Dm7|")
let straddleChunks = MelodyChunker.chunks(for: straddle, barsPerRequest: 1)
check("a chord spanning a boundary appears in each chunk it sounds in",
      straddleChunks.map { $0.progression.chords.map(\.symbol.text).joined(separator: "+") }
        == ["Cmaj7", "Cmaj7", "Dm7", "Dm7"],
      "\(straddleChunks.map { $0.progression.chords.map(\.symbol.text).joined(separator: "+") })")
check("each clipped piece is one bar long",
      straddleChunks.allSatisfy { $0.progression.chords.allSatisfy { $0.durationBeats == 4 } })
check("clipped chords never exceed their chunk",
      straddleChunks.allSatisfy { chunk in
          chunk.progression.chords.allSatisfy {
              $0.startBeat + $0.durationBeats <= chunk.beats + 1e-9
          }
      })

// A single very long progression must not blow up into absurd request counts.
let epic = try ChordProgression.parse(Array(repeating: "C∆", count: 64).joined(separator: "|"))
let epicChunks = MelodyChunker.chunks(for: epic)
check("64 bars splits into 16 requests", epicChunks.count == 16, "\(epicChunks.count)")

print()
print(failures == 0 ? "chunking: all checks passed" : "chunking: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
