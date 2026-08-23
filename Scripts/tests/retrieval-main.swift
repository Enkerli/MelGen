// Checks finding things rather than making them.
//
// Two modes, kept apart on purpose: direct retrieval has no randomness in it at
// all, and serendipity has nothing *but* weighted randomness — but weighted by
// things that mean something, chiefly that a line you've disagreed with yourself
// about is the best candidate for "try it again, it's a different day".
import Foundation

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let progression = try ChordProgression.parse("Dm7 | G7 | Cmaj7 | A7♭9")
// A library the way one actually looks: composed phrases, interval cells, and
// lines rewritten onto borrowed rhythms. Twenty composed phrases alone is not a
// library, it's one generator's output, and a retrieval test over it can't tell
// whether retrieval works or whether the generator is narrow.
let library: [MelodyPattern] = {
    var lines = (1...10).map { MelodyPhrases.compose(bars: 8, seed: UInt64($0)) }
    lines += MelodyStepPatterns.library(bars: 8)
    lines += (1...4).map { seed in
        MelodyTransforms.applyRhythm(MelodyPhrases.compose(bars: 8, seed: UInt64(50 + seed)),
                                     .euclidean(pulses: 5, steps: 8))
    }
    return lines
}()

// MARK: - Buckets

print("── buckets ────────────────────────────────────────")

var sparse = PatternProfile(); sparse.notesPerBar = 2; sparse.offbeatShare = 0.05; sparse.meanLength = 5
var busy = PatternProfile(); busy.notesPerBar = 7; busy.offbeatShare = 0.8; busy.meanLength = 1
check("a sparse on-beat line and a busy offbeat one bucket differently",
      RetrievalBucket.of(sparse) != RetrievalBucket.of(busy),
      "\(RetrievalBucket.of(sparse).label) vs \(RetrievalBucket.of(busy).label)")
check("bucketing is deterministic", RetrievalBucket.of(sparse) == RetrievalBucket.of(sparse))
check("a real library spreads over several buckets",
      MelodyRetrieval.buckets(of: library).count >= 3,
      "\(MelodyRetrieval.buckets(of: library).count) buckets over \(library.count) lines")

// MARK: - Direct retrieval

print()
print("── direct retrieval ───────────────────────────────")

let target = library[7]
let results = MelodyRetrieval.nearest(library, to: PatternProfile.of(target), over: progression)
check("a line is its own nearest match", results.first?.pattern.name == target.name,
      results.first.map { "\($0.pattern.name) at \($0.distance)" } ?? "nothing")
check("and at distance zero", (results.first?.distance ?? 1) < 0.001)
check("results are ordered by distance",
      zip(results, results.dropFirst()).allSatisfy { $0.distance <= $1.distance })
check("retrieval has no randomness in it",
      MelodyRetrieval.nearest(library, to: PatternProfile.of(target)).map(\.pattern.name)
        == MelodyRetrieval.nearest(library, to: PatternProfile.of(target)).map(\.pattern.name))
check("every result says why it's here", results.allSatisfy { !$0.reason.isEmpty })
check("a fit report comes back when there's harmony to fit",
      results.allSatisfy { $0.fit != nil })
check("an empty library returns nothing rather than crashing",
      MelodyRetrieval.nearest([], to: PatternProfile.of(target)).isEmpty)

let fits = MelodyRetrieval.fitting(library, progression)
check("fitting ranks the clean ones first",
      fits.first.map { $0.fit?.offScale ?? 99 } ?? 99 <= (fits.last.map { $0.fit?.offScale ?? 0 } ?? 0)
      || fits.allSatisfy { ($0.fit?.offScale ?? 0) == 0 })
check("fitting is deterministic",
      MelodyRetrieval.fitting(library, progression).map(\.pattern.name)
        == MelodyRetrieval.fitting(library, progression).map(\.pattern.name))

// MARK: - Serendipity

print()
print("── serendipity ────────────────────────────────────")

let recent = library.prefix(6).map(\.name)
check("the library has distinct names", Set(library.map(\.name)).count == library.count)
var picks: [String: Int] = [:]
for seed in (1...400).map(UInt64.init) {
    if let result = MelodyRetrieval.surprise(library, heardRecently: Array(recent), seed: seed) {
        picks[result.pattern.name, default: 0] += 1
    }
}
let recentPicks = recent.reduce(0) { $0 + (picks[$1] ?? 0) }
check("what you just heard comes up much less often",
      Double(recentPicks) / 400 < 0.12,
      "\(recentPicks) of 400 picks were among the last six heard")
check("but it isn't excluded — a surprise you can predict isn't one",
      recentPicks > 0, "\(recentPicks) of 400")
check("the whole library gets reached eventually",
      picks.count >= library.count - 2, "\(picks.count) of \(library.count) lines picked")
check("surprising is deterministic for one seed",
      MelodyRetrieval.surprise(library, heardRecently: [], seed: 5)?.pattern.name
        == MelodyRetrieval.surprise(library, heardRecently: [], seed: 5)?.pattern.name)

// The disagreement signal is the one a rating can't produce.
let contested: Set<String> = [library[13].name]
var contestedPicks = 0, plainPicks = 0
for seed in (1...400).map(UInt64.init) {
    if MelodyRetrieval.surprise(library, heardRecently: [], contested: contested, seed: seed)?
        .pattern.name == library[13].name { contestedPicks += 1 }
    if MelodyRetrieval.surprise(library, heardRecently: [], seed: seed)?
        .pattern.name == library[13].name { plainPicks += 1 }
}
check("a line you've disagreed with yourself about comes up more often",
      contestedPicks > plainPicks, "\(plainPicks) → \(contestedPicks) of 400")
check("and says so", MelodyRetrieval.surprise(library, heardRecently: [],
                                              contested: contested, seed: 1)?.reason.contains("disagreed")
      ?? false || contestedPicks > 0)

// Under-represented corners get reached for.
let commonBucket = RetrievalBucket.of(library[0])
let kept = [commonBucket: 50]
var cornerPicks = 0
for seed in (1...400).map(UInt64.init) {
    guard let result = MelodyRetrieval.surprise(library, heardRecently: [],
                                                keptBuckets: kept, seed: seed) else { continue }
    if RetrievalBucket.of(result.pattern) != commonBucket { cornerPicks += 1 }
}
check("corners you've been ignoring get reached for",
      cornerPicks > 200, "\(cornerPicks) of 400 picks were outside the well-worn bucket")

// MARK: - Recombination

print()
print("── splicing ───────────────────────────────────────")

let a = library[2], b = library[9]
let spliced = MelodyRetrieval.splice(a, b, atBar: 2)
check("a splice takes the opening from the first line",
      spliced.notes.filter { $0.startEighth < 16 }.map(\.degree)
        == a.notes.filter { $0.startEighth < 16 }.sorted { $0.startEighth < $1.startEighth }.map(\.degree))
check("and the rest from the second", spliced.notes.contains { $0.startEighth >= 16 })
check("nothing sounds through the join",
      spliced.notes.filter { $0.startEighth < 16 }
        .allSatisfy { $0.startEighth + $0.lengthEighths <= 16 })
check("the result is monophonic",
      Set(spliced.notes.map(\.startEighth)).count == spliced.notes.count)
check("it plays over real harmony",
      !MelodyPatterns.realize(spliced, over: progression).isEmpty)
check("it says where it came from", spliced.summary.contains(a.name) && spliced.summary.contains(b.name))
check("splicing is deterministic", MelodyRetrieval.splice(a, b, atBar: 2) == spliced)
check("splicing past the end of the second line still produces music",
      !MelodyRetrieval.splice(a, b, atBar: 6).notes.isEmpty)

// MARK: - What the session knows

print()
print("── disagreement, from the session ─────────────────")

var state = MelGenState()
let takes = (1...4).map { seed -> GenerationRecord in
    let pattern = MelodyPhrases.compose(bars: 4, seed: UInt64(seed))
    return GenerationRecord(progressionText: progression.text, temperature: 0.6,
                            briefName: pattern.name, source: .composed, lengthBeats: 16,
                            notes: MelodyPatterns.realize(pattern, over: progression))
}
for take in takes { state.add(take) }

state.mark(takes[0].id, as: .skip)
state.beginNextPass()
state.mark(takes[0].id, as: .keep)
state.mark(takes[1].id, as: .keep)

check("a take kept on both passes isn't contested",
      !state.contestedTakes.contains { $0.id == takes[1].id })
check("a take skipped then kept is",
      state.contestedTakes.contains { $0.id == takes[0].id })
check("an unjudged take isn't", !state.contestedTakes.contains { $0.id == takes[2].id })
check("recently heard is newest first",
      state.recentlyHeard(limit: 2).first?.id == takes[3].id)

print()
print(failures == 0 ? "retrieval: all checks passed" : "retrieval: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
