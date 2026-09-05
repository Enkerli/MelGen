// Checks that curation behaves like curation rather than like a rating.
//
// Three claims, all falsifiable here. Nothing you marked is ever silently lost.
// A second pass really is a second pass — the same take can be answered
// differently later, and both answers survive. And the queue puts what you
// deferred ahead of what you skipped, because deferring is a promise and
// skipping isn't.
import Foundation
import Carrier
import Theory

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let progression = try ChordProgression.parse("E♭7 Gm9|D∆|A♭6")

func take(_ index: Int, source: TakeSource = .model) -> GenerationRecord {
    let notes = MelodyPatterns.realize(MelodyPatterns.seed(at: index), over: progression)
    return GenerationRecord(
        date: Date(timeIntervalSince1970: Double(1_000_000 + index * 60)),
        progressionText: progression.text,
        temperature: 0.6,
        briefName: MelodyPatterns.seed(at: index).name,
        source: source,
        analysis: MelodyAnalyser.analyse(notes, over: progression),
        lengthBeats: progression.totalBeats,
        notes: notes
    )
}

// MARK: - Nothing you marked is lost

print("── the ring keeps what you judged ─────────────────────")

var state = MelGenState()
var marked: [UUID] = []
for index in 0..<40 {
    let record = take(index)
    state.add(record)
    // Mark every fifth take as something that should survive.
    if index.isMultiple(of: 5) {
        state.mark(record.id, as: index.isMultiple(of: 10) ? .keep : .later)
        marked.append(record.id)
    } else if index.isMultiple(of: 3) {
        state.mark(record.id, as: .skip)
    }
}

check("the ring still bounds the unjudged",
      state.history.count <= MelGenState.historyCeiling,
      "\(state.history.count) takes held")
check("every take you marked survived 40 generations",
      marked.allSatisfy { id in state.history.contains { $0.id == id } },
      "\(marked.count) marked, \(marked.filter { id in state.history.contains { $0.id == id } }.count) present")
check("takes you skipped are eligible to be dropped",
      state.history.filter { $0.latestMark?.disposition == .skip }.count
        < state.history.filter { $0.latestMark?.disposition == .later }.count
        || state.history.count <= MelGenState.historyLimit,
      "\(state.history.filter { $0.latestMark?.disposition == .skip }.count) skipped still held")
check("a take set aside for later is not a take discarded",
      TakeDisposition.later.protectsFromEviction && !TakeDisposition.skip.protectsFromEviction)

// MARK: - A second pass is a second pass

print()
print("── judgement is provisional ───────────────────────────")

var second = MelGenState()
let first = take(1)
let other = take(2)
second.add(first)
second.add(other)

second.mark(first.id, as: .skip, now: Date(timeIntervalSince1970: 1))
check("a mark lands on the current pass",
      second.history.first(where: { $0.id == first.id })?.latestMark?.pass == 1)

// Same pass, changed your mind: that's a correction, not a second opinion.
second.mark(first.id, as: .later, now: Date(timeIntervalSince1970: 2))
check("re-marking on the same pass corrects rather than accumulates",
      second.history.first(where: { $0.id == first.id })?.marks.count == 1,
      "\(second.history.first(where: { $0.id == first.id })?.marks.count ?? -1) marks")

second.beginNextPass()
second.mark(first.id, as: .keep, now: Date(timeIntervalSince1970: 3))
let revisited = second.history.first(where: { $0.id == first.id })
check("a later pass keeps the earlier answer too", revisited?.marks.count == 2,
      "\(revisited?.marks.count ?? -1) marks across \(second.curationPass) passes")
check("the latest word wins", revisited?.latestMark?.disposition == .keep)
check("what was said on pass 1 is still readable",
      revisited?.mark(onPass: 1)?.disposition == .later)
check("the disagreement is recorded, not resolved",
      revisited?.mark(onPass: 1)?.disposition != revisited?.mark(onPass: 2)?.disposition)

// MARK: - Judgement is comparative

print()
print("── a judgement records what it was heard against ──────")

var heard = MelGenState()
let earlier = take(3)
let later = take(4)
heard.add(earlier)
heard.add(later)          // `later` is now current, `earlier` is previous
heard.mark(later.id, as: .skip)
check("marking what's playing records what it followed",
      heard.history.first(where: { $0.id == later.id })?.latestMark?.heardAfter == earlier.id,
      "heard after \(heard.history.first(where: { $0.id == later.id })?.latestMark?.heardAfter?.uuidString.prefix(8) ?? "nothing")")

// MARK: - The queue

print()
print("── the review queue ───────────────────────────────────")

var queued = MelGenState()
var byDisposition: [TakeDisposition: UUID] = [:]
for (index, disposition) in TakeDisposition.allCases.enumerated() {
    let record = take(index)
    queued.add(record)
    queued.mark(record.id, as: disposition)
    byDisposition[disposition] = record.id
}
let unheard = take(9)
queued.add(unheard)

queued.beginNextPass()
let order = queued.reviewQueue.map(\.id)
func position(_ id: UUID?) -> Int { order.firstIndex(of: id ?? UUID()) ?? Int.max }

check("what you deferred comes before what you skipped",
      position(byDisposition[.later]) < position(byDisposition[.skip]))
check("what you deferred comes before what you never heard",
      position(byDisposition[.later]) < position(unheard.id))
check("what you never heard comes before what you already kept",
      position(unheard.id) < position(byDisposition[.keep]))
check("what you skipped is last, but present",
      position(byDisposition[.skip]) == order.count - 1 && position(byDisposition[.skip]) != Int.max)

// Answering on this pass sinks a take to the bottom of it.
queued.mark(byDisposition[.later]!, as: .keep)
let after = queued.reviewQueue.map(\.id)
check("answering something this pass moves it out of the way",
      after.firstIndex(of: byDisposition[.later]!)! > after.firstIndex(of: unheard.id)!)
check("progress counts this pass only",
      queued.reviewProgress == (1, queued.history.count),
      "\(queued.reviewProgress.answered) of \(queued.reviewProgress.total)")

// MARK: - What gets learned from

print()
print("── what the library learns from ───────────────────────")

check("keep, tweak and partial are the material",
      Set(queued.curatedTakes.compactMap { $0.latestMark?.disposition })
        .isSubset(of: [.keep, .tweak, .partial]))
check("what you set aside is not training material",
      !queued.curatedTakes.contains { $0.latestMark?.disposition == .later
                                   || $0.latestMark?.disposition == .skip })

// MARK: - Facets and tags

print()
print("── the two vocabularies ───────────────────────────────")

let dense = take(3)   // running eighths
let sparse = take(0)  // long tones
check("a dense line and a sparse one land in different facets",
      dense.facets.density != sparse.facets.density,
      "\(dense.facets.density.rawValue) vs \(sparse.facets.density.rawValue)")
check("facets are derived, so they need no typing",
      !dense.facets.chips.isEmpty, dense.facets.chips.joined(separator: " · "))
check("facets are deterministic", dense.facets == take(3).facets)

var tagged = MelGenState()
let subject = take(2)
tagged.add(subject)
tagged.setTags(["  Bossa ", "bossa", "night"], for: subject.id)
check("tags normalize and de-duplicate",
      tagged.history[0].tags == ["bossa", "night"],
      "\(tagged.history[0].tags)")
check("the vocabulary counts what's actually used",
      tagged.tagVocabulary.counts["bossa"] == 1)

let another = take(4)
tagged.add(another)
tagged.setTags(["bossa", "wide"], for: another.id)
check("a tag you keep reaching for rises to the top",
      tagged.tagVocabulary.suggestions.first == "bossa",
      tagged.tagVocabulary.suggestions.joined(separator: ", "))
check("nothing is promotable yet at a threshold of four",
      tagged.tagVocabulary.promotable().isEmpty)

tagged.setTags([], for: another.id)
check("retagging forgets the tags it replaced",
      tagged.tagVocabulary.counts["wide"] == nil && tagged.tagVocabulary.counts["bossa"] == 1)

// MARK: - The rotation

print()
print("── choosing what comes next ───────────────────────────")

check("cycle goes in order",
      (0..<9).map { Rotation.index(cursor: $0, count: 4, mode: .cycle) } == [0, 1, 2, 3, 0, 1, 2, 3, 0])

for count in 3...9 {
    let picks = (0..<(count * 12)).map { Rotation.index(cursor: $0, count: count, mode: .shuffle) }
    let rounds = stride(from: 0, to: picks.count, by: count).map { Array(picks[$0..<($0 + count)]) }
    check("shuffle of \(count) hears everything once per round",
          rounds.allSatisfy { Set($0).count == count })
    check("shuffle of \(count) never repeats back to back",
          zip(picks, picks.dropFirst()).allSatisfy { $0 != $1 })
}

check("shuffle is deterministic",
      (0..<40).map { Rotation.index(cursor: $0, count: 6, mode: .shuffle) }
        == (0..<40).map { Rotation.index(cursor: $0, count: 6, mode: .shuffle) })

check("a locked brief is the only brief",
      (0..<5).allSatisfy {
          StyleBriefs.brief(at: $0, selected: [], mode: .lock, locked: "Sparse").name == "Sparse"
      })
check("an empty selection means all of them",
      Set((0..<StyleBriefs.all.count).map { StyleBriefs.brief(at: $0, selected: [], mode: .cycle).name })
        == Set(StyleBriefs.all.map(\.name)))
let pair = ["Sparse", "Syncopated"]
check("a selection restricts the rotation to it",
      Set((0..<8).map { StyleBriefs.brief(at: $0, selected: pair, mode: .cycle).name }) == Set(pair))
check("a selection naming nothing real falls back to everything rather than crashing",
      !StyleBriefs.brief(at: 0, selected: ["nonexistent"], mode: .cycle).name.isEmpty)
check("an empty library falls back to the seeds",
      MelodyPatterns.line(at: 0, from: []).name == MelodyPatterns.seeds[0].name)
check("a locked line is the only line",
      MelodyPatterns.line(at: 3, from: MelodyPatterns.seeds, mode: .lock, locked: "Arch").name == "Arch")

// MARK: - Learning from it

print()
print("── what gets learned from what you kept ───────────────")

var learning = MelGenState()
for index in 0..<6 {
    let record = take(index)
    learning.add(record)
    learning.mark(record.id, as: index < 3 ? .keep : .skip)
    if index < 3 { learning.setTags(["bossa"], for: record.id) }
}

let learned = StyleLearner.learn(from: learning.curatedTakes)
check("a style is learned only from the curated takes", learned.takeCount == 3,
      "\(learned.takeCount) takes")
check("it measures density", learned.notesPerBar > 0,
      "\(learned.notesPerBar.formatted(.number.precision(.fractionLength(1))))/bar")
check("the motion shares are a distribution",
      abs(learned.stepShare + learned.skipShare + learned.leapShare - 1) < 0.001,
      "\(learned.stepShare) + \(learned.skipShare) + \(learned.leapShare)")
check("the harmonic shares are a distribution",
      abs(learned.chordToneShare + learned.colourShare
          + learned.avoidShare + learned.offScaleShare - 1) < 0.001)
check("register is ordered", learned.registerLow <= learned.registerCentre
      && learned.registerCentre <= learned.registerHigh,
      "\(learned.registerLow)–\(learned.registerCentre)–\(learned.registerHigh)")
check("it carries the tags you used", learned.tags == ["bossa"], "\(learned.tags)")
check("it is deterministic", learned == StyleLearner.learn(from: learning.curatedTakes))
check("nothing kept means no style to describe",
      StyleLearner.learn(from: []).isEmpty && StyleLearner.learn(from: []).promptText.isEmpty)

// The whole reason to describe rather than quote is that description doesn't
// grow with the corpus. Check that it actually doesn't.
var wide = MelGenState()
for index in 0..<24 {
    let record = take(index)
    wide.add(record)
    wide.mark(record.id, as: .keep)
}
let manyTakes = StyleLearner.learn(from: wide.curatedTakes)
check("a description of 20-odd takes still fits in a prompt",
      manyTakes.promptText.count < 1200,
      "\(manyTakes.promptText.count) characters from \(manyTakes.takeCount) takes")
check("quoting is capped and excerpted",
      PatternLibrary.examples(from: wide.curatedTakes).count <= 3
      && PatternLibrary.examples(from: wide.curatedTakes).allSatisfy { $0.pattern.count < 400 })

print()
print(learned.promptText.split(separator: "\n").map { "        " + $0 }.joined(separator: "\n"))


// MARK: - The coarse layer never reaches storage

// The rating strip exists at the point of input and nowhere else. If any of
// these fail, three of the seven have quietly become a scale.

print("── a rating is a shortcut, not a scale ────────────────")

var rated = MelGenState()
let rateMe = take(70)
rated.add(rateMe)

for rating in TakeRating.allCases {
    var one = MelGenState()
    let record = take(71)
    one.add(record)
    let written = one.rate(record.id, rating)
    let marks = one.history.first { $0.id == record.id }?.marks ?? []
    check("\(rating.label) writes exactly one mark",
          marks.count == 1, "\(marks.count) written")
    check("\(rating.label) writes \(rating.disposition.rawValue)",
          written == rating.disposition && marks.first?.disposition == rating.disposition)
    check("\(rating.label) is stamped with the current pass",
          marks.first?.pass == one.curationPass)
}

check("the three round-trip through TakeRating.of",
      TakeRating.allCases.allSatisfy { TakeRating.of($0.disposition) == $0 })
check("the other four are not coarser versions of anything",
      [TakeDisposition.tweak, .again, .context, .partial]
        .allSatisfy { TakeRating.of($0) == nil })

rated.rate(rateMe.id, .no)
rated.rate(rateMe.id, .yes)
check("rating twice on one pass replaces",
      rated.history.first { $0.id == rateMe.id }?.marks.count == 1)
check("the replacement is the second answer",
      rated.history.first { $0.id == rateMe.id }?.latestMark?.disposition == .keep)

rated.curationPass += 1
rated.rate(rateMe.id, .maybe)
check("rating on a later pass appends rather than replaces",
      rated.history.first { $0.id == rateMe.id }?.marks.count == 2)
check("both answers survive, disagreement included",
      Set((rated.history.first { $0.id == rateMe.id }?.marks ?? []).map(\.disposition))
        == [.keep, .later])

var skipped = MelGenState()
let skipMe = take(72)
skipped.add(skipMe)
skipped.rate(skipMe.id, .no)
check("No is not destructive — the take is still in the queue",
      skipped.reviewQueue.contains { $0.id == skipMe.id })
check("No puts it last rather than out",
      TakeDisposition.skip.reviewPriority
        > TakeDisposition.allCases.filter { $0 != .skip }.map(\.reviewPriority).max()!)

// MARK: - Two of the seven set the aim

print("── the two that are a request to re-roll ──────────────")

for disposition in TakeDisposition.allCases {
    var aiming = MelGenState()
    let record = take(73)
    aiming.add(record)
    aiming.advanceMode = .somethingElse
    aiming.judge(record.id, as: disposition)
    let expected: AdvanceMode = (disposition == .tweak || disposition == .again)
        ? .anotherLikeThis : .somethingElse
    check("\(disposition.label) leaves the aim at \(expected.label)",
          aiming.advanceMode == expected)
    check("\(disposition.label) still records its own mark",
          aiming.history.first { $0.id == record.id }?.latestMark?.disposition == disposition)
}

print()
print(failures == 0 ? "curation: all checks passed" : "curation: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
