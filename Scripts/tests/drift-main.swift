// Checks the live mutation layer.
//
// The shape is Troublemaker's: probabilities that re-roll every pass, each doing
// one thing you can hear in isolation. So each is checked in isolation, and the
// two things that make it MelGen's rather than a copy are checked hardest — that
// a chord drifts as a chord rather than losing a voice, and that a pass can be
// got back rather than being gone the moment the loop goes round.
import Foundation
import Carrier
import Theory

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let progression = try ChordProgression.parse("Dm7 | G7 | Cmaj7 | A7♭9")
let line = MelodyPatterns.realize(MelodyPhrases.compose(bars: 4, seed: 6), over: progression)
let comp = MelodyComping.comp(progression, figure: .pad)

func drift(_ settings: LiveMutation, _ notes: [SequencedNote] = line,
           polyphonic: Bool = false, seed: UInt64 = 7) -> [SequencedNote] {
    MelodyLiveMutations.apply(to: notes, settings: settings, lengthBeats: 16,
                              polyphonic: polyphonic, seed: seed)
}

// MARK: - Off is off

print("── nothing set changes nothing ────────────────────")

check("no probabilities means no drift", drift(LiveMutation()) == line)
check("and an inactive setting says so", !LiveMutation().isActive)
check("any probability makes it active", LiveMutation(skipSteps: 0.1).isActive)
check("its summary reads", LiveMutation(slides: 0.5).summary.contains("slides"))

// MARK: - One axis at a time

print()
print("── each axis, alone ───────────────────────────────")

let skipped = drift(LiveMutation(skipSteps: 0.5))
check("skip drops notes", skipped.count < line.count, "\(line.count) → \(skipped.count)")
check("and drops nothing else", Set(skipped.map(\.note)).isSubset(of: Set(line.map(\.note))))
check("everything skipped at 100%", drift(LiveMutation(skipSteps: 1)).isEmpty)
check("nothing skipped at 0%", drift(LiveMutation(skipSteps: 0)).count == line.count)

let reordered = drift(LiveMutation(noteOrder: 1))
check("note order keeps every onset exactly where it was",
      reordered.map(\.startBeat) == line.map(\.startBeat))
check("and keeps every length", reordered.map(\.durationBeats) == line.map(\.durationBeats))
check("but moves the pitches", reordered.map(\.note) != line.map(\.note))
check("without inventing any", Set(reordered.map(\.note)) == Set(line.map(\.note)))

let accented = drift(LiveMutation(accents: 1))
check("accents change velocities", accented.map(\.velocity) != line.map(\.velocity))
check("and nothing else", accented.map(\.note) == line.map(\.note)
      && accented.map(\.startBeat) == line.map(\.startBeat))
check("velocities stay legal", accented.allSatisfy { $0.velocity >= 1 && $0.velocity <= 127 })

let slid = drift(LiveMutation(slides: 1))
check("slides lengthen notes into the next",
      zip(slid, line).contains { $0.durationBeats > $1.durationBeats })
check("a slid note reaches the next onset",
      zip(slid, slid.dropFirst()).allSatisfy {
          $0.startBeat + $0.durationBeats >= $1.startBeat - 0.001
      })
check("and pitches are untouched", slid.map(\.note) == line.map(\.note))

let octaved = drift(LiveMutation(octaves: 1))
check("octaves move pitches by twelves",
      zip(octaved, line).allSatisfy { abs(Int($0.note) - Int($1.note)) % 12 == 0 })
check("and stay playable", octaved.allSatisfy { $0.note >= 36 && $0.note <= 96 })
check("onsets untouched", octaved.map(\.startBeat) == line.map(\.startBeat))

// MARK: - A chord drifts as a chord

print()
print("── a chord is one thing to decide about ───────────")

let compPolyphony = MelodyComping.maximumPolyphony(of: comp)
let driftedComp = drift(LiveMutation(accents: 0.5, skipSteps: 0.5, octaves: 0.4),
                        comp, polyphonic: true)
check("a comp still has chords in it after drifting",
      MelodyComping.maximumPolyphony(of: driftedComp) >= compPolyphony - 1,
      "\(compPolyphony) → \(MelodyComping.maximumPolyphony(of: driftedComp))")

// The failure this guards against: rolling per note inside a voicing gives a
// chord with one note missing, which is a different chord rather than a
// variation of this one.
func voicingSizes(_ notes: [SequencedNote]) -> [Double: Int] {
    var sizes: [Double: Int] = [:]
    for note in notes { sizes[(note.startBeat * 100).rounded() / 100, default: 0] += 1 }
    return sizes
}
let originalSizes = Set(voicingSizes(comp).values)
let driftedSizes = Set(voicingSizes(driftedComp).values)
check("no voicing came back with a voice missing",
      driftedSizes.isSubset(of: originalSizes),
      "\(driftedSizes.sorted()) against \(originalSizes.sorted())")

// Treated as a line, it would.
let asLine = drift(LiveMutation(skipSteps: 0.5), comp, polyphonic: false)
check("treating a comp as a line would have taken voices out of chords",
      !Set(voicingSizes(asLine).values).isSubset(of: originalSizes)
        || asLine.count == comp.count,
      "\(Set(voicingSizes(asLine).values).sorted())")

// MARK: - A pass can be got back

print()
print("── the same pass drifts the same way ──────────────")

let settings = LiveMutation(noteOrder: 0.4, accents: 0.4, slides: 0.3, skipSteps: 0.3, octaves: 0.2)
check("one seed always drifts the same way",
      drift(settings, seed: 42) == drift(settings, seed: 42))
check("a different pass is a different drift",
      drift(settings, seed: 42) != drift(settings, seed: 43))
check("going back a pass returns the earlier drift",
      drift(settings, seed: 41) == drift(settings, seed: 41))

var distinct = Set<String>()
for pass in (1...40).map(UInt64.init) {
    distinct.insert(drift(settings, seed: pass).map { "\($0.note):\($0.startBeat)" }
        .joined(separator: ","))
}
check("forty passes are forty different loops", distinct.count >= 35, "\(distinct.count)")

// MARK: - Through the session

print()
print("── through the session's own render ───────────────")

var state = MelGenState()
state.progressionText = progression.text
state.add(GenerationRecord(progressionText: progression.text, temperature: 0.6,
                           briefName: "test", source: .composed,
                           lengthBeats: 16, notes: line))
let undrifted = state.renderedMelody
state.liveMutation = LiveMutation(accents: 0.5, skipSteps: 0.4)
let drifted = state.renderedMelody
check("drift reaches the rendered melody", drifted != undrifted,
      "\(undrifted.count) → \(drifted.count) notes")

state.mutationPass += 1
check("and advancing the pass changes it again", state.renderedMelody != drifted)
state.mutationPass -= 1
check("and going back restores it", state.renderedMelody == drifted)

// Expression runs before drift, so a slide isn't gated shut again.
var slideState = MelGenState()
slideState.progressionText = progression.text
slideState.expression = ExpressionSettings(amount: 0.5, swing: 0, noteLength: 0.1, density: 0.5)
slideState.add(GenerationRecord(progressionText: progression.text, temperature: 0.6,
                                briefName: "test", source: .composed,
                                lengthBeats: 16, notes: line))
let staccato = slideState.renderedMelody
slideState.liveMutation = LiveMutation(slides: 1)
let slidThrough = slideState.renderedMelody
check("a slide survives a staccato gate setting",
      zip(slidThrough, staccato).contains { $0.durationBeats > $1.durationBeats + 0.01 },
      "longest \(slidThrough.map(\.durationBeats).max() ?? 0) against "
      + "\(staccato.map(\.durationBeats).max() ?? 0)")

print()
print(failures == 0 ? "drift: all checks passed" : "drift: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
