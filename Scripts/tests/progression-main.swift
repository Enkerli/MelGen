// Checks generating the changes.
//
// Ported from ProgGenie, and the thing worth checking hardest is not that the
// walk works — it's that everything it emits is something the rest of this
// plug-in can actually play. The corpus vocabulary is larger than MelGen's chord
// dictionary, so a generator that trusted it would produce progressions that
// fail to parse, which is worse than producing none.
import Foundation
import Carrier
import Theory

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

// MARK: - Labels

print("── reading the corpus's labels ────────────────────")

check("a plain numeral splits", ProgressionGenerator.split("I")?.numeral == "I")
check("a numeral with a suffix splits",
      ProgressionGenerator.split("IIm7").map { ($0.numeral, $0.suffix) } ?? ("", "") == ("II", "m7"))
check("a flattened numeral keeps its accidental",
      ProgressionGenerator.split("♭VII7")?.numeral == "♭VII")
check("the longest numeral wins, or III reads as II",
      ProgressionGenerator.split("IIIm7")?.numeral == "III")
check("a sharpened numeral works too",
      ProgressionGenerator.split("♯IVm7b5").map { ($0.numeral, $0.suffix) } ?? ("", "") == ("♯IV", "m7b5"))
check("nonsense is rejected rather than guessed at", ProgressionGenerator.split("banana") == nil)

check("I is the tonic", ProgressionGenerator.semitones(for: "I") == 0)
check("V is a fifth up", ProgressionGenerator.semitones(for: "V") == 7)
check("♭VII is ten semitones", ProgressionGenerator.semitones(for: "♭VII") == 10)
check("♯IV is six", ProgressionGenerator.semitones(for: "♯IV") == 6)
check("♭II wraps rather than going negative", ProgressionGenerator.semitones(for: "♭II") == 1)

check("a label becomes leadsheet text", ProgressionGenerator.chordText(for: "IIm7", key: 0) == "Dm7")
check("in any key", ProgressionGenerator.chordText(for: "V7", key: 5) == "C7")
check("and only when this plug-in can read it",
      ProgressionGenerator.chordText(for: "IBass", key: 0) == nil
        || (try? ChordProgression.parseChordSymbol(
            ProgressionGenerator.chordText(for: "IBass", key: 0) ?? "!!")) != nil)

// MARK: - Tables

print()
print("── the tables ─────────────────────────────────────")

for mode in ProgressionMode.allCases {
    let bigrams = ProgressionGenerator.bigrams(mode)
    let trigrams = ProgressionGenerator.trigrams(mode)
    check("\(mode.rawValue) has first-order counts", bigrams.count > 100, "\(bigrams.count) contexts")
    check("\(mode.rawValue) has second-order counts", trigrams.count > 50, "\(trigrams.count) contexts")
    check("\(mode.rawValue) first-order rows are non-empty",
          bigrams.values.allSatisfy { !$0.isEmpty })
    check("\(mode.rawValue) counts are positive",
          bigrams.values.allSatisfy { $0.values.allSatisfy { $0 > 0 } })
    check("\(mode.rawValue) second-order contexts name two chords",
          trigrams.keys.allSatisfy { $0.contains(" → ") })

    // The honest number, reported rather than assumed.
    let coverage = ProgressionGenerator.coverage(mode: mode)
    check("\(mode.rawValue): most of the corpus vocabulary is spellable here",
          Double(coverage.spelled) / Double(coverage.total) > 0.9,
          "\(coverage.spelled) of \(coverage.total) labels")
}

// MARK: - Blending

print()
print("── the blend ──────────────────────────────────────")

let first = ["V7": 100, "IV": 50]
check("with no second order, the first order is untouched",
      ProgressionGenerator.blend(first: first, second: [:])["V7"] == 100)
check("with no first order, the second stands alone",
      ProgressionGenerator.blend(first: [:], second: ["I": 3])["I"] == 3)

// A second-order context seen twice barely shifts things; one seen fifty times
// dominates. That's the backoff, and it's the whole reason this is usable on a
// corpus with a long tail of contexts seen once.
let sparse = ProgressionGenerator.blend(first: first, second: ["IIIm7": 2])
let dense = ProgressionGenerator.blend(first: first, second: ["IIIm7": 200])
let sparseShare = (sparse["IIIm7"] ?? 0) / sparse.values.reduce(0, +)
let denseShare = (dense["IIIm7"] ?? 0) / dense.values.reduce(0, +)
check("a context seen twice barely shifts the result", sparseShare < 0.2,
      "\(Int(sparseShare * 100))% of the weight")
check("a context seen often dominates it", denseShare > 0.6,
      "\(Int(denseShare * 100))% of the weight")
check("the blend never invents negative weight",
      dense.values.allSatisfy { $0 >= 0 })

// MARK: - Generating

print()
print("── generating ─────────────────────────────────────")

var everyText = Set<String>()
for mode in ProgressionMode.allCases {
    for seed in (1...30).map(UInt64.init) {
        guard let generated = ProgressionGenerator.generate(bars: 8, key: 0, mode: mode, seed: seed) else {
            check("\(mode.rawValue) seed \(seed) generates", false)
            continue
        }
        everyText.insert(generated.text)
        let label = "\(mode.rawValue) seed \(seed)"

        check("\(label) has the bars asked for", generated.labels.count == 8,
              "\(generated.labels.count)")

        // The assertion that matters: everything it emits, this plug-in plays.
        guard let parsed = try? ChordProgression.parse(generated.text) else {
            check("\(label) parses", false, generated.text)
            continue
        }
        check("\(label) parses", parsed.chords.count == 8)
        check("\(label) is 32 beats", abs(parsed.totalBeats - 32) < 0.001)

        // Every chord has to be usable by the rest of the machinery, not just
        // parseable — a chord with no scale is a chord nothing can play over.
        check("\(label) gives every chord a scale",
              parsed.chords.allSatisfy { !$0.symbol.scalePitchClasses.isEmpty })

        check("\(label) starts on the tonic",
              ProgressionGenerator.split(generated.labels[0])?.numeral == "I")
        check("\(label) ends on the tonic",
              ProgressionGenerator.split(generated.labels[7])?.numeral == "I",
              generated.labels[7])
        check("\(label) is deterministic",
              ProgressionGenerator.generate(bars: 8, key: 0, mode: mode, seed: seed)?.text
                == generated.text)
    }
}

check("thirty seeds in two modes are not one progression",
      everyText.count > 30, "\(everyText.count) distinct")

// Keys.
for key in 0..<12 {
    guard let generated = ProgressionGenerator.generate(bars: 4, key: key, mode: .major, seed: 3) else {
        check("key \(key) generates", false)
        continue
    }
    check("key \(key) parses", (try? ChordProgression.parse(generated.text)) != nil, generated.text)
    check("key \(key) starts on its own tonic",
          (try? ChordProgression.parse(generated.text))?.chords.first?.symbol.rootPitchClass == key)
}

check("the same walk transposes rather than changing",
      ProgressionGenerator.generate(bars: 8, key: 0, mode: .major, seed: 11)?.labels
        == ProgressionGenerator.generate(bars: 8, key: 7, mode: .major, seed: 11)?.labels)

// Temperature.
func vocabulary(_ surprise: Double) -> Int {
    var labels = Set<String>()
    for seed in (1...25).map(UInt64.init) {
        labels.formUnion(ProgressionGenerator.generate(bars: 8, key: 0, mode: .major,
                                                       surprise: Surprise(surprise),
                                                       reharm: .none,
                                                       seed: seed)?.labels ?? [])
    }
    return labels.count
}
check("surprise widens the vocabulary", vocabulary(0.95) > vocabulary(0.0),
      "\(vocabulary(0.0)) at the top of the list, \(vocabulary(0.95)) further down")

check("without a cadence it may end anywhere",
      (1...20).contains { seed in
          ProgressionGenerator.generate(bars: 8, key: 0, mode: .major, cadence: false,
                                        seed: UInt64(seed))
              .flatMap { ProgressionGenerator.split($0.labels[7])?.numeral } != "I"
      })

// MARK: - The depth controls

print()
print("── surprise, freshness, context, reharm ───────────")

/// How often a cliché shows up across a run of progressions.
func clicheRate(_ freshness: Freshness) -> Double {
    var cliches = 0, moves = 0
    for seed in (1...40).map(UInt64.init) {
        guard let generated = ProgressionGenerator.generate(
            bars: 8, key: 0, mode: .major, surprise: Surprise(0.35),
            freshness: freshness, reharm: .none, seed: seed) else { continue }
        for (index, label) in generated.labels.enumerated() where index > 0 {
            moves += 1
            if label == generated.labels[index - 1] { cliches += 1 }
            else if index > 1 && label == generated.labels[index - 2] { cliches += 1 }
            else if ProgressionGenerator.split(generated.labels[index - 1])?.numeral == "V"
                && ProgressionGenerator.split(label)?.numeral == "I" { cliches += 1 }
        }
    }
    return moves > 0 ? Double(cliches) / Double(moves) : 0
}

let faithful = clicheRate(.faithful)
let fresh = clicheRate(.fresh)
let bold = clicheRate(.bold)
check("Fresh avoids more clichés than Faithful", fresh < faithful,
      "\(Int(faithful * 100))% → \(Int(fresh * 100))%")
check("and Bold avoids more than Fresh", bold < fresh,
      "\(Int(fresh * 100))% → \(Int(bold * 100))%")
check("but none of them bans them outright — a progression of only fresh moves "
      + "is its own kind of tiresome", bold > 0, "\(Int(bold * 100))% still")

// Surprise is not temperature: it walks down the ranked list rather than
// flattening, so the second and third choices open before the tail does.
let ranked = ProgressionGenerator.rank(["a": 100, "b": 50, "c": 10, "d": 1],
                                       surprise: Surprise(0.6))
check("surprise keeps the ranking", (ranked["a"] ?? 0) >= (ranked["d"] ?? 0))
check("and narrows the gap", (ranked["b"] ?? 0) / (ranked["a"] ?? 1)
        > 50.0 / 100.0, "b/a went from 0.5 to \(((ranked["b"] ?? 0) / (ranked["a"] ?? 1)))")
check("surprise at zero changes nothing",
      ProgressionGenerator.rank(["a": 100, "b": 50], surprise: Surprise(0)) == ["a": 100, "b": 50])

// Context depth has to change the walk, or exposing it is theatre.
var depthOne = Set<String>(), depthTwo = Set<String>()
for seed in (1...25).map(UInt64.init) {
    depthOne.insert(ProgressionGenerator.generate(bars: 8, key: 0, mode: .major,
                                                  contextDepth: 1, reharm: .none,
                                                  seed: seed)?.text ?? "")
    depthTwo.insert(ProgressionGenerator.generate(bars: 8, key: 0, mode: .major,
                                                  contextDepth: 2, reharm: .none,
                                                  seed: seed)?.text ?? "")
}
check("one chord of context and two give different walks", depthOne != depthTwo)

// Reharm, at both settings, has to actually rewrite something.
func reharmRate(_ reharm: Reharm) -> Int {
    var changed = 0
    for seed in (1...40).map(UInt64.init) {
        let plain = ProgressionGenerator.generate(bars: 8, key: 0, mode: .major,
                                                  reharm: .none, seed: seed)?.labels
        let rewritten = ProgressionGenerator.generate(bars: 8, key: 0, mode: .major,
                                                      reharm: reharm, seed: seed)?.labels
        if plain != rewritten { changed += 1 }
    }
    return changed
}
check("Subtle rewrites something — a control that does nothing reads as broken",
      reharmRate(.subtle) > 5, "\(reharmRate(.subtle)) of 40 progressions changed")
check("and Bold rewrites more", reharmRate(.bold) > reharmRate(.subtle),
      "\(reharmRate(.subtle)) → \(reharmRate(.bold)) of 40")
check("None rewrites nothing", reharmRate(.none) == 0)

// The backdoor dominant, which is the one ProgGenie names alongside the tritone.
check("a backdoor dominant is ♭VII7",
      ProgressionGenerator.apply(.backdoor, to: ("V", "7"), before: ("I", ""), mode: .major)
        == "♭VII7")
check("a tritone sub is a tritone away",
      ProgressionGenerator.apply(.tritone, to: ("V", "7"), before: nil, mode: .major) == "♭II7")

// Modulation moves the key and keeps everything playable.
guard let modulated = ProgressionGenerator.generate(bars: 8, key: 0, mode: .major,
                                                    reharm: .none, modulateEvery: 4, seed: 8),
      let parsedModulated = try? ChordProgression.parse(modulated.text) else {
    print("  FAIL  modulation generates")
    exit(1)
}
check("modulation still parses", parsedModulated.chords.count == 8)
check("and it actually leaves the key",
      Set(parsedModulated.chords.suffix(3).map { $0.symbol.rootPitchClass })
        != Set(parsedModulated.chords.prefix(3).map { $0.symbol.rootPitchClass }))
check("not modulating leaves the key alone",
      ProgressionGenerator.generate(bars: 8, key: 0, mode: .major,
                                    reharm: .none, modulateEvery: 0, seed: 8)?.text
        != modulated.text)

// MARK: - Playing over them

print()
print("── and the rest of the plug-in plays over them ────")

for seed in (1...12).map(UInt64.init) {
    guard let generated = ProgressionGenerator.generate(bars: 8, key: 0, mode: .major, seed: seed),
          let progression = try? ChordProgression.parse(generated.text) else { continue }

    let composed = MelodyPhrases.compose(bars: 8, seed: seed)
    let line = MelodyPatterns.realize(composed, over: progression)
    check("a composed phrase plays over generated changes \(seed)", !line.isEmpty)
    check("and stays monophonic",
          zip(line, line.dropFirst()).allSatisfy {
              $0.startBeat + $0.durationBeats <= $1.startBeat + 1e-9
          })

    let comp = MelodyComping.comp(progression, figure: .charleston)
    check("and they can be comped \(seed)", !comp.isEmpty)

    check("and a take over them reads back as a pattern",
          MelodyPatterns.extract(from: line, over: progression, name: "x") != nil)
}

print()
print(failures == 0 ? "progression: all checks passed" : "progression: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
