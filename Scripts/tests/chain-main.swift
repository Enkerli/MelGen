// Checks the variable-order chain.
//
// The claim that matters: with a personal corpus, backoff is the only reason
// anything is produced at all. A few hundred transitions means most order-2
// contexts are seen exactly once, and a context seen once can only quote. So
// what's asserted hardest here is that the model does *not* replay its corpus —
// and that the honest measure of how much order-2 it can actually use is
// reported rather than hidden.
import Foundation
import Carrier
import Theory

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let progression = try ChordProgression.parse("Dm7 | G7 | Cmaj7 | A7♭9 | Dm7 | G7 | Cmaj7 | Cmaj7")
let corpus = (1...16).map { MelodyPhrases.compose(bars: 8, seed: UInt64($0)) }
let chain = MelodyChain.learn(from: corpus)

// MARK: - Tokens

print("── tokens ─────────────────────────────────────────")

let token = ChainToken(degree: 4, alteration: -1, lengthEighths: 3, restAfterEighths: 2)
check("a token reads as one", token.key == "4:-1:3:2", token.key)
check("and parses back", ChainToken(key: token.key) == token)
check("a token's span is its note plus its silence", token.spanEighths == 5)
check("pitch and rhythm are one token",
      ChainToken(degree: 0, alteration: 0, lengthEighths: 1, restAfterEighths: 0)
        != ChainToken(degree: 0, alteration: 0, lengthEighths: 4, restAfterEighths: 0))
check("a garbled key is rejected rather than guessed at", ChainToken(key: "nonsense") == nil)

// MARK: - The context ladder

print()
print("── the backoff ladder ─────────────────────────────")

let history = [ChainToken(degree: 0, alteration: 0, lengthEighths: 2, restAfterEighths: 0),
               ChainToken(degree: 2, alteration: 0, lengthEighths: 1, restAfterEighths: 0)]
let keys = MelodyChain.contextKeys(history: history, metricPosition: 4, phrase: .middle)
check("the ladder has five rungs at full history", keys.count == 5, "\(keys.count)")
check("it goes longest first", keys[0].hasPrefix("2|") && keys[keys.count - 1].hasPrefix("0|"))
check("bar position outlives history",
      keys.filter { $0.contains("@4") }.count > keys.filter { $0.contains("#") }.count,
      "\(keys.filter { $0.contains("@4") }.count) rungs keep the metre, "
      + "\(keys.filter { $0.contains("#") }.count) keep the phrase position")
check("a shorter history gives a shorter ladder",
      MelodyChain.contextKeys(history: [], metricPosition: 0, phrase: .opening).count == 1)

// MARK: - Learning

print()
print("── learning ───────────────────────────────────────")

check("it counts its takes", chain.takes == 16)
check("it saw real material", chain.transitions > 500, chain.summary)
check("every event is counted at every context length",
      chain.counts.keys.contains { $0.hasPrefix("2|") }
      && chain.counts.keys.contains { $0.hasPrefix("1|") }
      && chain.counts.keys.contains { $0.hasPrefix("0|") })
check("it knows how lines start", !chain.openings.isEmpty, "\(chain.openings.count) openings")

// The honest number: how much order-2 is worth anything at this corpus size.
check("it reports how much of its longest context it can trust",
      chain.trustedShare > 0 && chain.trustedShare < 1,
      "\(Int(chain.trustedShare * 100))% of order-2 contexts seen more than once")

var empty = MelodyChain()
check("an empty chain generates nothing rather than crashing",
      empty.generate(bars: 4, seed: 1) == nil)
check("a take whose progression won't parse is skipped",
      !empty.add(GenerationRecord(progressionText: "!!!", temperature: 0.5,
                                  briefName: "", lengthBeats: 4, notes: [])))

// MARK: - Generating

print()
print("── generating ─────────────────────────────────────")

guard let walked = chain.generate(bars: 8, seed: 3) else {
    print("  FAIL  the chain generates")
    exit(1)
}
check("the chain generates", walked.notes.count > 4, "\(walked.notes.count) notes")
check("generation is deterministic", chain.generate(bars: 8, seed: 3) == walked)
check("a different seed is a different line", chain.generate(bars: 8, seed: 4) != walked)
check("it stays inside its bars", walked.notes.allSatisfy { $0.startEighth < 8 * 8 })
check("it is monophonic before harmony",
      zip(walked.notes, walked.notes.dropFirst()).allSatisfy {
          $0.startEighth + $0.lengthEighths <= $1.startEighth
      })

// This is the one that matters. A chain over a small corpus that trusts
// singleton contexts reproduces takes verbatim; this must not.
let corpusFingerprints = Set(corpus.map { pattern in
    pattern.notes.map { ChainToken($0).key }.joined(separator: ",")
})
var generated = Set<String>()
for seed in (1...50).map(UInt64.init) {
    guard let line = chain.generate(bars: 8, seed: seed) else { continue }
    generated.insert(line.notes.map { ChainToken($0).key }.joined(separator: ","))
}
check("fifty walks are fifty lines", generated.count == 50, "\(generated.count)")
check("none of them is a take from the corpus",
      generated.isDisjoint(with: corpusFingerprints))

// And it has to keep the rhythmic variety that the corpus had — the whole
// reason pitch and rhythm are one token.
var lengths = Set<Int>()
var rests = 0, notes = 0
for seed in (1...20).map(UInt64.init) {
    guard let line = chain.generate(bars: 8, seed: seed) else { continue }
    lengths.formUnion(line.notes.map(\.lengthEighths))
    rests += line.notes.filter { $0.restAfterEighths > 0 }.count
    notes += line.notes.count
}
check("walked lines keep a range of note lengths", lengths.count >= 4, "lengths \(lengths.sorted())")
check("walked lines breathe", rests * 4 > notes,
      "\(rests) of \(notes) notes are followed by silence")

// Temperature is the lever the language model didn't turn out to have.
func spread(temperature: Double) -> Int {
    var tokens = Set<String>()
    for seed in (1...20).map(UInt64.init) {
        guard let line = chain.generate(bars: 8, seed: seed, temperature: temperature) else { continue }
        tokens.formUnion(line.notes.map { ChainToken($0).key })
    }
    return tokens.count
}
let cold = spread(temperature: 0.3)
let hot = spread(temperature: 2.5)
check("temperature widens the vocabulary", hot > cold, "\(cold) tokens cold, \(hot) hot")

// MARK: - Over real harmony

print()
print("── over real changes ──────────────────────────────")

for seed in (1...8).map(UInt64.init) {
    guard let pattern = chain.generate(bars: 8, seed: seed) else { continue }
    let realized = MelodyPatterns.realize(pattern, over: progression)
    check("walk \(seed) plays", !realized.isEmpty)
    check("walk \(seed) stays monophonic",
          zip(realized, realized.dropFirst()).allSatisfy {
              $0.startBeat + $0.durationBeats <= $1.startBeat + 1e-9
          })
    check("walk \(seed) stays in a singable register",
          realized.allSatisfy { $0.note >= 36 && $0.note <= 96 })
    check("walk \(seed) never leaps more than an octave",
          (zip(realized, realized.dropFirst()).map { abs(Int($1.note) - Int($0.note)) }.max() ?? 0) <= 12)
}

let encoded = try JSONEncoder().encode(chain)
let decoded = try JSONDecoder().decode(MelodyChain.self, from: encoded)
check("a chain round-trips through JSON", decoded == chain, "\(encoded.count) bytes")
check("and walks identically afterwards", decoded.generate(bars: 8, seed: 3) == walked)

print()
print(failures == 0 ? "chain: all checks passed" : "chain: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
