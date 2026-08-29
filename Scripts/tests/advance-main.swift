// Checks that an advance always answers, and answers what it promised.
//
// The whole feature is the aim. "Another like this" and "Something else" are
// only worth two buttons if they reliably differ, and the subtitle under each
// one is only worth printing if it is true before the tap. Both claims are
// falsifiable here.
//
// The other claim is the one that can't be tested by looking at a screen: an
// advance must never wait on the model. That is asserted structurally — the
// file must not be able to import FoundationModels — by the fact that this
// suite compiles `TakeAdvance.swift` without it and would fail to link if it
// reached for one.
import Foundation

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let progression = try ChordProgression.parse("E♭7 Gm9|D∆|A♭6")

func seeded(_ index: Int) -> GenerationRecord {
    let pattern = MelodyPatterns.seed(at: index)
    let notes = MelodyPatterns.realize(pattern, over: progression)
    return GenerationRecord(
        progressionText: progression.text,
        temperature: 0.6,
        briefName: pattern.name,
        source: .pattern,
        analysis: MelodyAnalyser.analyse(notes, over: progression),
        lengthBeats: progression.totalBeats,
        notes: notes
    )
}

func playing(_ mode: PlayMode = .line) -> MelGenState {
    var state = MelGenState()
    state.progressionText = progression.text
    state.mode = mode
    let record = seeded(1)
    state.add(record)
    state.currentTakeID = record.id
    return state
}

// MARK: - It always answers

print("── every mode and every source produces a take ────────")

for mode in PlayMode.allCases {
    for source in MaterialSource.all(for: mode) {
        for aim in AdvanceMode.allCases {
            let candidate = TakeAdvance.candidate(mode: aim,
                                                  state: playing(mode),
                                                  source: source,
                                                  progression: progression)
            check("\(mode) · \(source.rawValue) · \(aim.rawValue) answers",
                  candidate != nil && !(candidate?.notes.isEmpty ?? true),
                  "\(candidate?.notes.count ?? 0) notes")
        }
    }
}

print("── and answers from nothing, on the first take ────────")

var empty = MelGenState()
empty.progressionText = progression.text
for aim in AdvanceMode.allCases {
    let candidate = TakeAdvance.candidate(mode: aim, state: empty,
                                          source: .composed, progression: progression)
    check("\(aim.rawValue) answers with no current take",
          candidate != nil && !(candidate?.notes.isEmpty ?? true))
}

// MARK: - The two aims actually differ

print("── the aim is a promise, not a label ──────────────────")

let state = playing()
let sameAgain = TakeAdvance.candidate(mode: .anotherLikeThis, state: state,
                                      source: .composed, progression: progression)
let different = TakeAdvance.candidate(mode: .somethingElse, state: state,
                                      source: .composed, progression: progression)

check("another like this steps from the take that is sounding",
      sameAgain?.parentTakeID == state.currentTakeID,
      sameAgain?.derivation ?? "no derivation")
check("and says what was done to get there",
      !(sameAgain?.derivation.isEmpty ?? true))
check("something else does not claim a parent it didn't step from",
      different?.parentTakeID == nil)
check("another like this does not thin the bar into near-silence",
      (sameAgain?.notes.count ?? 0) >= (state.currentTake?.notes.count ?? 0) / 2,
      "\(state.currentTake?.notes.count ?? 0) notes → \(sameAgain?.notes.count ?? 0)")

var rotating = playing()
rotating.selectedBriefNames = MelGenTemplates.all(for: .line).prefix(3).map(\.name)
rotating.briefMode = .cycle
check("something else moves the rotation on",
      TakeAdvance.nextTemplate(after: rotating).name != rotating.nextTemplate.name,
      "\(rotating.nextTemplate.name) → \(TakeAdvance.nextTemplate(after: rotating).name)")
check("and the take it makes carries the template it promised",
      TakeAdvance.candidate(mode: .somethingElse, state: rotating,
                            source: .composed, progression: progression)?.briefName
        == TakeAdvance.nextTemplate(after: rotating).name)

var locked = playing()
locked.selectedBriefNames = MelGenTemplates.all(for: .line).prefix(3).map(\.name)
locked.briefMode = .lock
locked.lockedBriefName = locked.selectedBriefNames.first
check("a locked rotation stays locked, even under something else",
      TakeAdvance.nextTemplate(after: locked).name == locked.lockedBriefName)

// MARK: - The subtitle is true before the tap

print("── the subtitle, which is the whole feature ───────────")

check("another like this names the take it will vary",
      TakeAdvance.subtitle(mode: .anotherLikeThis, state: state, source: .composed)?
        .contains(state.currentTake?.briefName ?? "—") == true,
      TakeAdvance.subtitle(mode: .anotherLikeThis, state: state, source: .composed) ?? "nil")
check("something else names the template it will reach",
      TakeAdvance.subtitle(mode: .somethingElse, state: state, source: .composed)
        == "next: \(TakeAdvance.nextTemplate(after: state).name)")
check("with no take to vary, the button is disabled rather than vague",
      TakeAdvance.subtitle(mode: .anotherLikeThis, state: empty, source: .composed) == nil)
check("under Chords the subtitle says re-voiced, not varied",
      TakeAdvance.subtitle(mode: .anotherLikeThis, state: playing(.comping),
                           source: .comp)?.contains("re-voiced") == true)

// MARK: - The model is never what an advance waits on

print("── the model runs alongside, never in front ───────────")

check("no background request when the source is instant",
      MaterialSource.allCases.filter { $0.isInstant }.allSatisfy { source in
          AdvanceMode.allCases.allSatisfy {
              TakeAdvance.backgroundRequest(mode: $0, state: state, source: source) == nil
          }
      })
check("no background request for another like this — a variant already answers it",
      TakeAdvance.backgroundRequest(mode: .anotherLikeThis, state: state, source: .model) == nil)
check("something else on the model asks for one alongside",
      TakeAdvance.backgroundRequest(mode: .somethingElse, state: state, source: .model) == .model)
check("and still hands back a take that did not wait for it",
      TakeAdvance.candidate(mode: .somethingElse, state: state,
                            source: .model, progression: progression)?.source != .model)

// MARK: - The third aim

print()
print("── same, changed: the seed is held ────────────────────")

// The property the aim exists for: at a held seed, the only difference is
// whatever the caller just changed. Bass had this and it was written as
// plumbing; it is a third aim and it applies to every source whose draw is
// deterministic — ROADMAP H14, answered.
var held = playing()
if var take = held.currentTake {
    take.seed = 0xA11CE
    held.history[0] = take
    held.currentTakeID = take.id
}
let atHeldSeed = TakeAdvance.candidate(mode: .sameChanged, state: held,
                                       source: .composed, progression: progression)
check("it answers", atHeldSeed != nil && !(atHeldSeed?.notes.isEmpty ?? true))
check("at the seed the current take was drawn at",
      atHeldSeed?.seed == held.currentTake?.seed,
      "\(atHeldSeed?.seed ?? 0) vs \(held.currentTake?.seed ?? 0)")
let atHeldSeedAgain = TakeAdvance.candidate(mode: .sameChanged, state: held,
                                            source: .composed, progression: progression)
check("and it is repeatable, because a held seed is the whole point",
      atHeldSeedAgain?.notes == atHeldSeed?.notes)
check("the setup travels with it untouched",
      atHeldSeed?.progressionText == held.progressionText)
check("and so does the rest of it",
      atHeldSeed?.temperature == held.temperature
        && atHeldSeed?.durationPalette == held.durationPalette)

// One thing changed, and it is the thing that differs.
var nudged = held
nudged.durationPalette = nudged.durationPalette == .even ? .mixed : .even
let afterNudge = TakeAdvance.candidate(mode: .sameChanged, state: nudged,
                                       source: .composed, progression: progression)
check("changing one aim changes the take at the same seed",
      afterNudge?.seed == atHeldSeed?.seed && afterNudge?.notes != atHeldSeed?.notes)

// No seed to hold: fall through rather than refuse. A verb that sometimes does
// nothing is worse than one that sometimes does slightly more.
var seedless = playing()
if var take = seedless.currentTake {
    take.seed = 0
    seedless.history[0] = take
    seedless.currentTakeID = take.id
}
check("with no seed to hold it falls through to another like this, rather than nil",
      TakeAdvance.candidate(mode: .sameChanged, state: seedless,
                            source: .composed, progression: progression) != nil)
var noTakeYet = playing()
noTakeYet.history = []
noTakeYet.currentTakeID = nil
check("and with no take at all it still answers",
      TakeAdvance.candidate(mode: .sameChanged, state: noTakeYet,
                            source: .composed, progression: progression) != nil)

// The one place the grammar softens, and it says so rather than pretending.
check("on an instant source the promise is exact",
      AdvanceMode.sameChanged.promise(for: .composed) == "seed held")
check("on the model it is honest instead",
      AdvanceMode.sameChanged.promise(for: .model) == "asked again")
check("and only the model carries the caveat, in a sentence",
      AdvanceMode.sameChanged.caveat(for: .model)?.contains("similar") == true
        && AdvanceMode.sameChanged.caveat(for: .composed) == nil)
check("the other two aims make no promise at all, on any source",
      MaterialSource.allCases.allSatisfy { source in
          AdvanceMode.anotherLikeThis.promise(for: source).isEmpty
            && AdvanceMode.somethingElse.promise(for: source).isEmpty
            && AdvanceMode.anotherLikeThis.caveat(for: source) == nil
      })
check("three aims, narrowest first, and the order is the argument",
      AdvanceMode.allCases == [.sameChanged, .anotherLikeThis, .somethingElse])
check("each says what it will do before it does it",
      AdvanceMode.allCases.allSatisfy {
          TakeAdvance.subtitle(mode: $0, state: held, source: .composed) != nil
      })

// MARK: - An advance is not a roll

print("── drift is untouched ─────────────────────────────────")

var drifting = playing()
drifting.liveMutation.noteOrder = 0.4
drifting.mutationPass = 7
let before = drifting.liveMutation
_ = TakeAdvance.candidate(mode: .anotherLikeThis, state: drifting,
                          source: .composed, progression: progression)
_ = TakeAdvance.candidate(mode: .somethingElse, state: drifting,
                          source: .composed, progression: progression)
check("an advance does not re-roll the drift dice",
      drifting.mutationPass == 7)
check("an advance does not change what drift is doing",
      drifting.liveMutation == before)

// MARK: - The aim survives a reopened session

print("── the aim is session state ───────────────────────────")

var aimed = playing()
aimed.advanceMode = .somethingElse
let encoded = try JSONEncoder().encode(aimed)
let decoded = try JSONDecoder().decode(MelGenState.self, from: encoded)
check("the aim round-trips", decoded.advanceMode == .somethingElse)
check("and the history came with it", decoded.history.count == aimed.history.count)

var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
legacy.removeValue(forKey: "advanceMode")
let older = try JSONDecoder().decode(
    MelGenState.self,
    from: JSONSerialization.data(withJSONObject: legacy))
check("a session saved before the aim existed decodes with the default",
      older.advanceMode == .anotherLikeThis)
check("and does not lose its history on the way",
      older.history.count == aimed.history.count)

print()
print(failures == 0 ? "advance: all checks passed" : "advance: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
