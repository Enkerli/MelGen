// Checks the slot-statistics style model, ported from @enkerli/accompaniment.
//
// The claims: it accumulates (so a year of playing is O(events), not a rebuild),
// its onset probabilities have the right denominator (a two-bar take doesn't
// vote on bar three), it samples something new rather than replaying a take, and
// what it samples puts notes where the corpus puts them.
import Foundation
import Carrier
import Theory

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let progression = try ChordProgression.parse("Dm7 | G7 | Cmaj7 | A7♭9 | Dm7 | G7 | Cmaj7 | Cmaj7")

func corpus(_ count: Int, bars: Int = 8) -> [MelodyPattern] {
    (1...count).map { MelodyPhrases.compose(bars: bars, seed: UInt64($0)) }
}

// MARK: - The key

print("── the degree key ─────────────────────────────────")

let key = StyleSlot.degreeKey(degree: 2, alteration: -1, role: .colour)
check("a degree key reads as one", key == "2:-1:colour", key)
let parsed = StyleSlot.parseDegreeKey(key)
check("and parses back", parsed?.degree == 2 && parsed?.alteration == -1 && parsed?.role == .colour)
check("an unclassified key survives the round trip",
      StyleSlot.parseDegreeKey(StyleSlot.degreeKey(degree: 0, alteration: 0, role: nil))?.role == nil)
check("a negative degree survives too",
      StyleSlot.parseDegreeKey("-3:1:chordTone")?.degree == -3)

// MARK: - Accumulating

print()
print("── accumulating ───────────────────────────────────")

var model = MelodyStyleModel(id: "test")
for pattern in corpus(12) { model.add(pattern) }

check("it counts its takes", model.takes == 12)
check("it covers the bars it was given", model.bars == 8, "\(model.bars) bars")
check("it has a slot per eighth", model.slots.count == 8 * 8, "\(model.slots.count) slots")
check("it saw real material", model.observations > 100, "\(model.observations) onsets")
check("something was played at most positions",
      model.slots.filter { $0.count > 0 }.count > model.slots.count / 3,
      "\(model.slots.filter { $0.count > 0 }.count) of \(model.slots.count)")
check("every slot's onset probability is a probability",
      model.slots.allSatisfy { (0...1).contains($0.onsetProbability) })

// Order must not matter: statistics, not a sequence.
var forwards = MelodyStyleModel(id: "f")
var backwards = MelodyStyleModel(id: "b")
for pattern in corpus(8) { forwards.add(pattern) }
for pattern in corpus(8).reversed() { backwards.add(pattern) }
check("the order takes arrive in doesn't change the model",
      forwards.slots == backwards.slots)

// Adding one more take is exactly adding one more take.
var incremental = forwards
incremental.add(MelodyPhrases.compose(bars: 8, seed: 9))
var batch = MelodyStyleModel(id: "f")
for pattern in corpus(9) { batch.add(pattern) }
check("adding a take to a model equals learning the corpus with it in",
      incremental.slots == batch.slots && incremental.takes == batch.takes)

// `covered` is the denominator that makes short takes honest.
var mixed = MelodyStyleModel(id: "mixed")
mixed.add(MelodyPhrases.compose(bars: 2, seed: 3))
mixed.add(MelodyPhrases.compose(bars: 8, seed: 4))
check("a short take doesn't vote on bars it never reached",
      mixed.slots[0].covered == 2 && mixed.slots[mixed.slots.count - 1].covered == 1,
      "bar 1 covered \(mixed.slots[0].covered), last slot covered \(mixed.slots[mixed.slots.count - 1].covered)")

// MARK: - Sampling

print()
print("── sampling ───────────────────────────────────────")

guard let drawn = model.sample(seed: 42) else {
    print("  FAIL  the model samples")
    exit(1)
}
check("the model samples", !drawn.notes.isEmpty, "\(drawn.notes.count) notes")
check("sampling is deterministic", model.sample(seed: 42) == drawn)
check("a different pass is a different line", model.sample(seed: 42, pass: 1) != drawn)
check("what it draws is monophonic before harmony",
      Set(drawn.notes.map(\.startEighth)).count == drawn.notes.count)
check("it stays inside the model's bars",
      drawn.notes.allSatisfy { $0.startEighth < model.bars * 8 })

// The point of a model is that it doesn't replay the corpus.
let corpusFingerprints = Set(corpus(12).map { pattern in
    pattern.notes.map { "\($0.startEighth):\($0.degree):\($0.alteration)" }.joined(separator: ",")
})
var drawnFingerprints = Set<String>()
for seed in (1...40).map(UInt64.init) {
    guard let sample = model.sample(seed: seed) else { continue }
    drawnFingerprints.insert(sample.notes.map { "\($0.startEighth):\($0.degree):\($0.alteration)" }
        .joined(separator: ","))
}
check("forty draws are forty lines", drawnFingerprints.count == 40, "\(drawnFingerprints.count)")
check("none of them is a take from the corpus",
      drawnFingerprints.isDisjoint(with: corpusFingerprints))

// Density scales what comes out, which is the control that makes it playable.
let sparse = model.sample(seed: 7, density: 0.35)?.notes.count ?? 0
let asObserved = model.sample(seed: 7, density: 1)?.notes.count ?? 0
let dense = model.sample(seed: 7, density: 2)?.notes.count ?? 0
check("density thins and thickens the draw", sparse < asObserved && asObserved <= dense,
      "\(sparse) / \(asObserved) / \(dense) notes")

// Humanize 0 must be exactly the means — the useful thing to be able to hear.
let flat = model.sample(seed: 7, humanize: 0)
check("humanize 0 plays the means",
      flat?.notes.allSatisfy { $0.velocity >= 40 && $0.velocity <= 120 } ?? false)

// A slot model has no memory, which is why it needs the one-note lookback.
var repeatsWith = 0, repeatsWithout = 0
for seed in (1...30).map(UInt64.init) {
    if let on = model.sample(seed: seed, avoidRepeats: true) {
        repeatsWith += zip(on.notes, on.notes.dropFirst())
            .filter { $0.degree == $1.degree && $0.alteration == $1.alteration }.count
    }
    if let off = model.sample(seed: seed, avoidRepeats: false) {
        repeatsWithout += zip(off.notes, off.notes.dropFirst())
            .filter { $0.degree == $1.degree && $0.alteration == $1.alteration }.count
    }
}
// Not to zero, and it shouldn't be: a slot that has only ever seen one degree
// has nothing else to offer, and inventing an alternative would be the model
// making something up rather than reporting what it saw.
check("the one-note lookback cuts repeated degrees to a fraction",
      repeatsWithout > 0 && repeatsWith * 2 < repeatsWithout,
      "\(repeatsWith) with the lookback, \(repeatsWithout) without")

// MARK: - Where it puts things

print()
print("── it plays where the corpus plays ────────────────")

// A corpus that only ever plays on the beat must not produce offbeat draws.
var onBeatOnly = MelodyStyleModel(id: "onbeat")
for seed in 1...8 {
    var notes: [PatternNote] = []
    for eighth in stride(from: 0, to: 32, by: 4) {
        notes.append(PatternNote(startEighth: eighth, lengthEighths: 2,
                                 degree: (seed + eighth / 4) % 7, velocity: 90))
    }
    onBeatOnly.add(MelodyPattern(name: "s\(seed)", bars: 4, summary: "", notes: notes))
}
var offbeatDraws = 0
for seed in (1...30).map(UInt64.init) {
    offbeatDraws += onBeatOnly.sample(seed: seed)?.notes
        .filter { !$0.startEighth.isMultiple(of: 2) }.count ?? 0
}
check("a corpus that never plays offbeat never draws offbeat", offbeatDraws == 0,
      "\(offbeatDraws) offbeat notes in 30 draws")

check("the onset map has a row per bar", model.onsetMap().count == model.bars)
check("and shows something", model.onsetMap().contains { $0.contains("█") || $0.contains("▅") })

// MARK: - Round trip and realization

print()
print("── over real harmony ──────────────────────────────")

for seed in (1...8).map(UInt64.init) {
    guard let pattern = model.sample(seed: seed) else { continue }
    let notes = MelodyPatterns.realize(pattern, over: progression)
    check("draw \(seed) plays", !notes.isEmpty)
    check("draw \(seed) stays monophonic",
          zip(notes, notes.dropFirst()).allSatisfy {
              $0.startBeat + $0.durationBeats <= $1.startBeat + 1e-9
          })
    check("draw \(seed) stays in a singable register",
          notes.allSatisfy { $0.note >= 36 && $0.note <= 96 })
}

// A model has to survive being written down and read back, or it can't outlive
// a session — which is the only reason to accumulate rather than recompute.
let encoded = try JSONEncoder().encode(model)
let decoded = try JSONDecoder().decode(MelodyStyleModel.self, from: encoded)
check("a model round-trips through JSON", decoded == model,
      "\(encoded.count) bytes for \(model.takes) takes")
check("and samples identically after the round trip",
      decoded.sample(seed: 42) == model.sample(seed: 42))

// Learning from takes rather than patterns is the path the plug-in uses.
let takes = (1...6).map { seed -> GenerationRecord in
    let pattern = MelodyPhrases.compose(bars: 8, seed: UInt64(seed))
    let notes = MelodyPatterns.realize(pattern, over: progression)
    return GenerationRecord(progressionText: progression.text, temperature: 0.6,
                            briefName: pattern.name, source: .composed,
                            tags: ["probe"],
                            lengthBeats: progression.totalBeats, notes: notes)
}
let fromTakes = MelodyStyleModel.learn(from: takes)
check("a model can be learned straight from takes", fromTakes.takes == 6, fromTakes.summary)
check("and carries the tags they were filed under", fromTakes.tags == ["probe"])
var unparseable = MelodyStyleModel(id: "x")
check("a take whose progression won't parse is skipped, not guessed at",
      !unparseable.add(GenerationRecord(progressionText: "!!!", temperature: 0.5,
                                        briefName: "", lengthBeats: 4, notes: [])))

print()
print(failures == 0 ? "stylemodel: all checks passed" : "stylemodel: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
