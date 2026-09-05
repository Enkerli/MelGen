// Checks the transforms, the scoring and the morph.
//
// The loop this serves is curation pointed at variants: mutate a line a dozen
// ways, score them, listen to the survivors, then dial between two you like and
// mark the point where it becomes the thing you wanted. So what's asserted is
// that each transform moves one axis and leaves the others alone — a variant
// nobody can attribute to a cause teaches nothing — and that the morph really
// interpolates rather than crossfading.
import Foundation
import Carrier
import Theory

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let progression = try ChordProgression.parse("Dm7 | G7 | Cmaj7 | A7♭9")
let parent = MelodyPhrases.compose(bars: 4, seed: 11)
let mask = { (spec: RhythmSpec) in spec.steps.map { $0 ? "x" : "." }.joined() }

// MARK: - Euclidean rhythms

print("── rhythms to borrow ──────────────────────────────")

check("E(3,8) is the tresillo", mask(.euclidean(pulses: 3, steps: 8)) == "x..x..x.",
      mask(.euclidean(pulses: 3, steps: 8)))
check("E(2,5) is the limp", mask(.euclidean(pulses: 2, steps: 5)) == "x..x.",
      mask(.euclidean(pulses: 2, steps: 5)))
check("every Euclidean rhythm has the pulses it was asked for",
      (1...16).allSatisfy { pulses in
          (pulses...16).allSatisfy { steps in
              RhythmSpec.euclidean(pulses: pulses, steps: steps).onsetCount == pulses
          }
      })
check("a rotation is the same rhythm, moved",
      Set(RhythmSpec.euclidean(pulses: 3, steps: 8, rotation: 2).onsetIndices)
        != Set(RhythmSpec.euclidean(pulses: 3, steps: 8).onsetIndices)
      && RhythmSpec.euclidean(pulses: 3, steps: 8, rotation: 2).onsetCount == 3)
check("no pulses is silence, not a crash",
      RhythmSpec.euclidean(pulses: 0, steps: 8).onsetCount == 0)
check("more pulses than steps is clamped rather than looped forever",
      RhythmSpec.euclidean(pulses: 20, steps: 8).onsetCount == 8)

// MARK: - Transforms, one axis at a time

print()
print("── each transform moves one axis ──────────────────")

func degrees(_ pattern: MelodyPattern) -> [Int] {
    pattern.notes.sorted { $0.startEighth < $1.startEighth }.map(\.degree)
}
func onsets(_ pattern: MelodyPattern) -> [Int] {
    pattern.notes.map(\.startEighth).sorted()
}
func lengths(_ pattern: MelodyPattern) -> [Int] {
    pattern.notes.sorted { $0.startEighth < $1.startEighth }.map(\.lengthEighths)
}

let displaced = MelodyTransforms.displace(parent, byEighths: 2)
check("displacement moves the rhythm", onsets(displaced) != onsets(parent))
check("and keeps the pitches", Set(degrees(displaced)) == Set(degrees(parent)))
check("displacement wraps inside the bars",
      onsets(displaced).allSatisfy { $0 < parent.bars * 8 })
check("displacing by a whole cycle is the identity",
      onsets(MelodyTransforms.displace(parent, byEighths: parent.bars * 8)) == onsets(parent))

let inverted = MelodyTransforms.invert(parent)
check("inversion keeps the rhythm exactly", onsets(inverted) == onsets(parent))
check("and turns the shape over",
      zip(degrees(parent), degrees(inverted)).allSatisfy { a, b in
          a - degrees(parent)[0] == -(b - degrees(inverted)[0])
      })
check("inverting twice is the identity",
      degrees(MelodyTransforms.invert(inverted)) == degrees(parent))

let retrograded = MelodyTransforms.retrograde(parent)
check("retrograde keeps the rhythm", onsets(retrograded) == onsets(parent))
check("and reverses the pitch sequence", degrees(retrograded) == degrees(parent).reversed())

let redrawn = MelodyTransforms.substituteDurations(parent, amount: 1, seed: 3)
check("redrawing durations keeps the onsets", onsets(redrawn) == onsets(parent))
check("and keeps the pitches", degrees(redrawn) == degrees(parent))
check("and actually changes the lengths", lengths(redrawn) != lengths(parent))

let nudged = MelodyTransforms.substituteDegrees(parent, amount: 1, seed: 3)
check("nudging degrees keeps the rhythm", onsets(nudged) == onsets(parent))
check("and moves every pitch by a step",
      zip(degrees(parent), degrees(nudged)).allSatisfy { abs($0 - $1) == 1 })

let thinner = MelodyTransforms.adjustDensity(parent, to: 0.5, seed: 1)
let denser = MelodyTransforms.adjustDensity(parent, to: 2, seed: 1)
check("thinning removes notes", thinner.notes.count < parent.notes.count,
      "\(parent.notes.count) → \(thinner.notes.count)")
check("and takes the weakest metric positions first",
      (thinner.notes.map { MelodyTransforms.metricWeight($0.startEighth) }.min() ?? 0)
        >= (parent.notes.map { MelodyTransforms.metricWeight($0.startEighth) }.min() ?? 0))
check("thickening adds them", denser.notes.count > parent.notes.count,
      "\(parent.notes.count) → \(denser.notes.count)")

let ornamented = MelodyTransforms.ornament(parent, amount: 1, seed: 2)
check("ornamenting adds approach notes", ornamented.notes.count >= parent.notes.count)
check("and they're chromatic", ornamented.notes.contains { $0.alteration != 0 })
check("ornaments don't displace what they ornament",
      Set(onsets(parent)).isSubset(of: Set(onsets(ornamented))))

let raised = MelodyTransforms.displaceRegister(parent, octaves: 1, fromEighth: 16)
check("register displacement leaves the first half alone",
      raised.notes.filter { $0.startEighth < 16 }.allSatisfy { $0.octave == 0 })
check("and lifts the second", raised.notes.filter { $0.startEighth >= 16 }.allSatisfy { $0.octave == 1 })

// MARK: - Rhythm replacement

print()
print("── performing a line on another rhythm ────────────")

let tresillo = RhythmSpec.euclidean(pulses: 3, steps: 8)
let onTresillo = MelodyTransforms.applyRhythm(parent, tresillo)
check("the line lands on the borrowed grid",
      onTresillo.notes.allSatisfy { tresillo.onsetIndices.contains($0.startEighth % 8) },
      "onsets \(Set(onTresillo.notes.map { $0.startEighth % 8 }).sorted())")
check("the cell tiles per bar rather than stretching over the form",
      onTresillo.notes.count >= 3 * parent.bars - 1,
      "\(onTresillo.notes.count) notes over \(parent.bars) bars")
check("the pitch material rides along in order",
      Array(Set(degrees(onTresillo))).allSatisfy { Set(degrees(parent)).contains($0) })
check("a rhythm with no onsets leaves the line alone",
      MelodyTransforms.applyRhythm(parent, RhythmSpec(steps: [false, false], label: "empty")) == parent)
check("stretching over the whole form is still available",
      MelodyTransforms.applyRhythm(parent, tresillo, overBars: parent.bars).notes.count == 3)

// MARK: - Everything stays playable

print()
print("── every transform leaves something playable ──────")

let allVariants = MelodyVariants.explore(parent, seed: 7, limit: 20)
check("exploring produces variants", allVariants.count >= 8, "\(allVariants.count)")
for variant in allVariants {
    let label = variant.transform
    check("\(label) is monophonic",
          Set(variant.pattern.notes.map(\.startEighth)).count == variant.pattern.notes.count)
    check("\(label) stays inside its bars",
          variant.pattern.notes.allSatisfy { $0.startEighth < variant.pattern.bars * 8 })
    check("\(label) has no zero-length notes",
          variant.pattern.notes.allSatisfy { $0.lengthEighths >= 1 })
    check("\(label) realizes over real changes",
          !MelodyPatterns.realize(variant.pattern, over: progression).isEmpty)
}

check("nothing offered is identical to its parent",
      allVariants.allSatisfy { $0.novelty > 0.05 })
check("every score is a proportion",
      allVariants.allSatisfy {
          (0...1).contains($0.novelty) && (0...1).contains($0.variety)
              && (0...1).contains($0.styleDistance)
      })
// Deterministic to the last bit, not merely in order. Summing entropies over a
// dictionary's iteration order gave answers differing in the final digits, which
// is invisible in a percentage and fatal in a list sorted by it.
check("exploring is deterministic",
      MelodyVariants.explore(parent, seed: 7, limit: 20) == allVariants)
check("and the scores are identical, not merely close",
      MelodyVariants.explore(parent, seed: 7, limit: 20).map(\.variety) == allVariants.map(\.variety))
check("variety is stable across repeated measurement",
      (1...5).allSatisfy { _ in MelodyVariants.variety(of: parent) == MelodyVariants.variety(of: parent) })

// Style distance has to mean something: a line measured against its own style
// is nearer than one measured against a style built from something else.
let ownTakes = [GenerationRecord(progressionText: progression.text, temperature: 0.6,
                                 briefName: parent.name, source: .composed,
                                 lengthBeats: 16,
                                 notes: MelodyPatterns.realize(parent, over: progression))]
let ownStyle = StyleLearner.learn(from: ownTakes)
let ownProfile = PatternProfile.of(parent)
check("a line is nearer its own style than a contrived opposite",
      ownProfile.distance(to: PatternProfile.of(ownStyle)) < ownProfile.distance(to: {
          var far = PatternProfile()
          far.notesPerBar = 8; far.offbeatShare = 1; far.restShare = 0
          far.stepShare = 0; far.leapShare = 1; far.meanLength = 1
          return far
      }()),
      "\(ownProfile.distance(to: PatternProfile.of(ownStyle)))")

// MARK: - Morphing

print()
print("── the morph ──────────────────────────────────────")

let other = MelodyPhrases.compose(bars: 4, seed: 19)
check("mix 0 is the first line", degrees(MelodyMorph.between(parent, other, mix: 0)) == degrees(parent))
check("mix 1 is the second", degrees(MelodyMorph.between(parent, other, mix: 1)) == degrees(other))
check("the morph is deterministic",
      MelodyMorph.between(parent, other, mix: 0.5) == MelodyMorph.between(parent, other, mix: 0.5))

// The note count has to travel between the two, or it's a crossfade.
let counts = stride(from: 0.0, through: 1.0, by: 0.25)
    .map { MelodyMorph.between(parent, other, mix: $0).notes.count }
check("the note count travels from one to the other",
      counts.first == parent.notes.count && counts.last == other.notes.count,
      "\(counts)")

// And the middle has to actually be in the middle rather than one end.
let middle = MelodyMorph.between(parent, other, mix: 0.5)
check("the middle is neither parent",
      degrees(middle) != degrees(parent) && degrees(middle) != degrees(other))
check("every morph stays playable",
      stride(from: 0.0, through: 1.0, by: 0.1).allSatisfy { mix in
          let morphed = MelodyMorph.between(parent, other, mix: mix)
          return Set(morphed.notes.map(\.startEighth)).count == morphed.notes.count
              && morphed.notes.allSatisfy { $0.lengthEighths >= 1 }
              && !MelodyPatterns.realize(morphed, over: progression).isEmpty
      })
check("morphing with an empty line gives back the other one",
      MelodyMorph.between(parent, MelodyPattern(name: "e", bars: 4, summary: "", notes: []), mix: 0.5)
        == parent)

// The two axes, which are what a morph is actually for.
print()
print("── rhythm and pitch, separately ───────────────────")

let keepRhythm = MelodyMorph.between(parent, other, rhythmMix: 0, pitchMix: 1)
check("keeping this rhythm keeps its onsets",
      onsets(keepRhythm) == onsets(parent), "\(onsets(keepRhythm)) vs \(onsets(parent))")
check("and takes the other line's degrees",
      degrees(keepRhythm) != degrees(parent))

let keepPitch = MelodyMorph.between(parent, other, rhythmMix: 1, pitchMix: 0)
check("keeping this pitch takes its degrees and nothing else's",
      Set(degrees(keepPitch)).isSubset(of: Set(degrees(parent))),
      "\(Set(degrees(keepPitch)).sorted()) from \(Set(degrees(parent)).sorted())")
check("and takes the other line's rhythm", onsets(keepPitch) == onsets(other),
      "\(onsets(keepPitch)) vs \(onsets(other))")
// The note count follows the rhythm, because a rhythm is how many notes there
// are as much as where they fall.
check("the note count follows the rhythm axis",
      keepPitch.notes.count == other.notes.count && keepRhythm.notes.count == parent.notes.count,
      "\(keepPitch.notes.count) vs \(other.notes.count), "
      + "\(keepRhythm.notes.count) vs \(parent.notes.count)")

check("both axes at zero is the first line",
      degrees(MelodyMorph.between(parent, other, rhythmMix: 0, pitchMix: 0)) == degrees(parent))
check("both at one is the second",
      degrees(MelodyMorph.between(parent, other, rhythmMix: 1, pitchMix: 1)) == degrees(other))
check("the one-slider version still means both at once",
      MelodyMorph.between(parent, other, mix: 0.4)
        == MelodyMorph.between(parent, other, rhythmMix: 0.4, pitchMix: 0.4))
check("every combination stays playable",
      stride(from: 0.0, through: 1.0, by: 0.25).allSatisfy { r in
          stride(from: 0.0, through: 1.0, by: 0.25).allSatisfy { p in
              let morphed = MelodyMorph.between(parent, other, rhythmMix: r, pitchMix: p)
              return Set(morphed.notes.map(\.startEighth)).count == morphed.notes.count
                  && !MelodyPatterns.realize(morphed, over: progression).isEmpty
          }
      })
check("the summary says what each axis did",
      MelodyMorph.between(parent, other, rhythmMix: 0.25, pitchMix: 0.75).summary.contains("rhythm 25%")
        && MelodyMorph.between(parent, other, rhythmMix: 0.25, pitchMix: 0.75).summary.contains("pitch 75%"))

print()
print(failures == 0 ? "mutation: all checks passed" : "mutation: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
