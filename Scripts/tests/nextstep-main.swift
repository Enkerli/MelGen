// Checks the one line that says what to do now.
//
// A guidance line is worth exactly as much as its truthfulness, and the ways it
// stops being truthful are quiet: a rung fires when its precondition isn't met,
// two rungs both match and the order was never decided, or it keeps talking
// after there is nothing left to say. None of those look wrong on screen — they
// look like advice.
//
// So three claims. Every rung fires only in the state it describes. The ladder
// is total and ordered, so there is exactly one answer for any state. And it
// goes quiet, which is the property that keeps it from becoming furniture.
import Foundation
import Carrier
import Theory

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let changes = "E♭7 Gm9|D∆|A♭6"
let progression = try ChordProgression.parse(changes)

func take(_ index: Int) -> GenerationRecord {
    let pattern = MelodyPatterns.seed(at: index)
    let notes = MelodyPatterns.realize(pattern, over: progression)
    return GenerationRecord(
        progressionText: changes,
        temperature: 0.6,
        briefName: pattern.name,
        source: .pattern,
        analysis: MelodyAnalyser.analyse(notes, over: progression),
        lengthBeats: progression.totalBeats,
        notes: notes)
}

/// A session that has got past everything the ladder blocks on.
func settled(takes count: Int = 8, keeping kept: Int = 0) -> MelGenState {
    var state = MelGenState()
    state.progressionText = changes
    for index in 0..<count {
        let record = take(index)
        state.add(record)
        state.rate(record.id, index < kept ? .yes : .no)
    }
    state.currentTakeID = state.history.first?.id
    return state
}

let plain = StepContext(source: .composed)

// MARK: - Blocked before anything else

print("── the rungs nothing else can happen without ──────────")

var blank = MelGenState()
blank.progressionText = ""
check("no changes is the first thing said",
      NextSteps.step(for: blank, context: plain)?.destination == .progression)
check("and it says nothing can be made rather than scolding",
      NextSteps.step(for: blank, context: plain)?.reason.contains("nothing can be made") == true)

var broken = MelGenState()
broken.progressionText = "Hgw9 ||| ??"
check("a progression that doesn't parse is named as that, not as absent",
      NextSteps.step(for: broken, context: plain)?.reason.contains("doesn't parse") == true,
      NextSteps.step(for: broken, context: plain)?.reason ?? "nil")

var empty = MelGenState()
empty.progressionText = changes
check("changes but no takes points at the source",
      NextSteps.step(for: empty, context: plain)?.destination == .source)
check("and the reason is the source's own cost",
      NextSteps.step(for: empty, context: StepContext(source: .model))?
        .reason.contains("1.8 seconds") == true)
check("an instant source is not described as slow",
      NextSteps.step(for: empty, context: plain)?.reason.contains("instantly") == true)

// MARK: - The rung that fires most often

print("── something is sounding and nobody has said anything ─")

var unjudged = MelGenState()
unjudged.progressionText = changes
let first = take(1)
unjudged.add(first)
unjudged.currentTakeID = first.id
check("an unrated current take asks to be rated",
      NextSteps.step(for: unjudged, context: plain)?.destination == .rating)
check("and says No isn't destructive, because that is the thing people get wrong",
      NextSteps.step(for: unjudged, context: plain)?.reason.contains("not this pass") == true)

unjudged.rate(first.id, .maybe)
check("once it has an answer, the line moves on",
      NextSteps.step(for: unjudged, context: plain)?.destination != .rating)

// The same take on a *later* pass is unanswered again, because that is what a
// pass is. If this rung read the latest mark rather than this pass's, a second
// sweep would start with nothing to do.
unjudged.curationPass += 1
check("a new pass makes the same take unanswered again",
      NextSteps.step(for: unjudged, context: plain)?.destination == .rating)

// MARK: - The two drawers, which is what this exists for

print("── the drawers, pointed at when they matter ───────────")

let material = settled(takes: 10, keeping: NextSteps.materialThreshold)
check("enough kept takes points at Your material",
      NextSteps.step(for: material, context: plain)?.destination == .material,
      NextSteps.step(for: material, context: plain)?.title ?? "nil")
check("and the reason is the count, not encouragement",
      NextSteps.step(for: material, context: plain)?
        .reason.contains("\(NextSteps.materialThreshold) kept takes") == true)
check("it stops once you are already drawing from it",
      NextSteps.step(for: material, context: StepContext(source: .learned))?
        .destination != .material)

let thin = settled(takes: 10, keeping: NextSteps.materialThreshold - 1)
check("below the threshold it doesn't point at a source that would answer with nothing",
      NextSteps.step(for: thin, context: plain)?.destination != .material)

let tuned = settled(takes: NextSteps.materialThreshold, keeping: 1)
check("a session's worth of takes with no setup saved points at setups",
      NextSteps.step(for: tuned, context: StepContext(source: .composed,
                                                      hasStoredLineOfYourOwn: true))?
        .destination == .setups,
      NextSteps.step(for: tuned, context: StepContext(source: .composed,
                                                      hasStoredLineOfYourOwn: true))?.title ?? "nil")
check("and never once one is saved",
      NextSteps.step(for: tuned, context: StepContext(source: .composed,
                                                      hasSavedSetup: true,
                                                      hasStoredLineOfYourOwn: true))?
        .destination != .setups)

// MARK: - Passes, and the step from a judgement to material

print("── the sweep, and what a kept take is still missing ───")

var swept = settled(takes: NextSteps.sweepThreshold + 2, keeping: 1)
// Already in Bass, so the capability rung above this one is satisfied. The
// capability rungs sit above "start the next pass" on purpose and each of them
// extinguishes itself once taken; a fixture that hasn't taken them is testing
// the wrong rung rather than finding a bug.
swept.mode = .bass
check("a finished sweep offers the next pass",
      NextSteps.step(for: swept, context: StepContext(source: .composed,
                                                      hasSavedSetup: true,
                                                      hasStoredLineOfYourOwn: true))?
        .destination == .pass)
check("and names the pass it would start",
      NextSteps.step(for: swept, context: StepContext(source: .composed,
                                                      hasSavedSetup: true,
                                                      hasStoredLineOfYourOwn: true))?
        .title == "Start pass \(swept.curationPass + 1)")

var backlog = MelGenState()
backlog.progressionText = changes
for index in 0..<(NextSteps.sweepThreshold + 4) { backlog.add(take(index)) }
// The current take answered, the rest not: the rating rung is satisfied and the
// backlog rung is what should speak.
if let current = backlog.history.first {
    backlog.currentTakeID = current.id
    backlog.rate(current.id, .yes)
}
check("a backlog of unanswered takes is named as a backlog",
      NextSteps.step(for: backlog, context: plain)?.destination == .pass,
      NextSteps.step(for: backlog, context: plain)?.title ?? "nil")

// MARK: - The newest drawer

print()
print("── a mode nothing points at ───────────────────────────")

let unexplored = settled(takes: NextSteps.materialThreshold, keeping: 1)
check("a session that has never made a bass part is told there is one",
      NextSteps.step(for: unexplored,
                     context: StepContext(source: .learned, hasSavedSetup: true,
                                          hasStoredLineOfYourOwn: true))?
        .destination == .bass,
      NextSteps.step(for: unexplored,
                     context: StepContext(source: .learned, hasSavedSetup: true,
                                          hasStoredLineOfYourOwn: true))?.title ?? "nil")
check("and it says what is behind the mode rather than repeating its name",
      NextSteps.step(for: unexplored,
                     context: StepContext(source: .learned, hasSavedSetup: true,
                                          hasStoredLineOfYourOwn: true))?
        .reason.contains("pad") == true)

var explored = unexplored
explored.mode = .bass
check("never once you are in it",
      NextSteps.step(for: explored,
                     context: StepContext(source: .learned, hasSavedSetup: true,
                                          hasStoredLineOfYourOwn: true))?
        .destination != .bass)

var drawn = unexplored
if var first = drawn.history.first {
    first.source = .bassline
    drawn.history[0] = first
}
check("nor once a bass part has been made, whatever mode you are in now",
      NextSteps.step(for: drawn,
                     context: StepContext(source: .learned, hasSavedSetup: true,
                                          hasStoredLineOfYourOwn: true))?
        .destination != .bass)

let kept = settled(takes: 6, keeping: 2)
check("a kept take that isn't a line yet says why a line is different",
      NextSteps.step(for: kept, context: StepContext(source: .composed, hasSavedSetup: true))?
        .destination == .storedLines,
      NextSteps.step(for: kept, context: StepContext(source: .composed, hasSavedSetup: true))?
        .reason ?? "nil")

// MARK: - It goes quiet

print("── silence is an answer ───────────────────────────────")

var done = settled(takes: 3, keeping: 1)
done.curationPass = 1
let settledContext = StepContext(source: .learned,
                                 hasSavedSetup: true,
                                 hasStoredLineOfYourOwn: true,
                                 hasCapturedPlaying: false)
check("a session with nothing outstanding says nothing",
      NextSteps.step(for: done, context: settledContext) == nil,
      NextSteps.step(for: done, context: settledContext)?.title ?? "silent")
check("except that captured notes left sitting are still worth a word",
      NextSteps.step(for: done, context: StepContext(source: .learned,
                                                     hasSavedSetup: true,
                                                     hasStoredLineOfYourOwn: true,
                                                     hasCapturedPlaying: true))?
        .destination == .material)

// MARK: - Total and ordered

print("── one answer, whatever the state ─────────────────────")

var everyStepIsReachable: Set<StepDestination> = []
var deterministic = true
// Includes the states that block, not only the settled ones — a sweep that
// only visits tidy sessions can't tell you the early rungs are reachable.
for takes in [0, 1, 3, 6, 12] {
    for keptCount in [0, 1, 6] where keptCount <= takes {
        for source in MaterialSource.allCases {
            for saved in [false, true] {
                for line in [false, true] {
                    for captured in [false, true] {
                    // Mode is part of the state the ladder reads now, so a sweep
                    // that only visits Line can't reach the rungs below the one
                    // that offers Bass.
                    for mode in PlayMode.allCases {
                        var state = settled(takes: takes, keeping: keptCount)
                        state.mode = mode
                        let context = StepContext(source: source,
                                                  hasSavedSetup: saved,
                                                  hasStoredLineOfYourOwn: line,
                                                  hasCapturedPlaying: captured)
                        let once = NextSteps.step(for: state, context: context)
                        let twice = NextSteps.step(for: state, context: context)
                        if once != twice { deterministic = false }
                        if let once { everyStepIsReachable.insert(once.destination) }
                    }
                    }
                }
            }
        }
    }
}
check("the same state always gives the same answer", deterministic)
everyStepIsReachable.formUnion(
    [NextSteps.step(for: blank, context: plain),
     NextSteps.step(for: broken, context: plain),
     NextSteps.step(for: unjudged, context: plain)].compactMap { $0?.destination })
check("every destination is reachable from some real state",
      Set(StepDestination.allCases).subtracting(everyStepIsReachable).isEmpty,
      "never reached: " + Set(StepDestination.allCases).subtracting(everyStepIsReachable)
        .map(\.rawValue).sorted().joined(separator: ", "))
check("no step is ever both untitled and shown",
      NextSteps.step(for: settled(), context: plain).map {
          !$0.title.isEmpty && !$0.reason.isEmpty
      } ?? true)

print()
print(failures == 0 ? "nextstep: all checks passed" : "nextstep: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
