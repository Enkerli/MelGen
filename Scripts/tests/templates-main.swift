// Checks writing a template, and — the part that matters — refusing one.
//
// The economics are why this exists: a take costs about 1.8 seconds a note every
// time, and a template costs one request once. The *gate* is why it's worth
// building rather than merely appealing, because without it authoring templates
// just produces more names for the same line. So most of this is the gate.
import Foundation

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

let existing = MelGenTemplates.line

// MARK: - Figures have measurable properties

print("── what a figure is like ──────────────────────────")

check("a long figure measures long", GestureRhythm.longWithAir.meanLength > 4,
      "\(GestureRhythm.longWithAir.meanLength)")
check("an even figure measures short", GestureRhythm.even.meanLength <= 1.5)
check("an offbeat figure measures offbeat", GestureRhythm.charleston.offbeatShare > 0.4,
      "\(GestureRhythm.charleston.offbeatShare)")
check("a downbeat figure doesn't", GestureRhythm.steadyQuarters.offbeatShare == 0)
check("a figure with air measures airy", GestureRhythm.stab.airShare > 0.5,
      "\(GestureRhythm.stab.airShare)")
check("a continuous one doesn't", GestureRhythm.tresillo.airShare < 0.3)
check("density is per bar, not per figure",
      GestureRhythm.even.impliedDensity > GestureRhythm.longWithAir.impliedDensity,
      "\(GestureRhythm.even.impliedDensity) against \(GestureRhythm.longWithAir.impliedDensity)")

// MARK: - Numbers to figures

print()
print("── a character becomes figures ────────────────────")

let sparse = TemplateCharacter(name: "Wide open", brief: "Play almost nothing and let it ring.",
                               notesPerBar: 1.5, airiness: 0.7, offbeatness: 0.1, noteLength: 5)
let busy = TemplateCharacter(name: "Chatter", brief: "Keep it moving and never stop for long.",
                             notesPerBar: 7, airiness: 0.05, offbeatness: 0.5, noteLength: 1)

let sparseFigures = TemplateDerivation.rhythms(for: sparse)
let busyFigures = TemplateDerivation.rhythms(for: busy)
check("a sparse character gets sparse figures",
      sparseFigures.map(\.meanLength).reduce(0, +) > busyFigures.map(\.meanLength).reduce(0, +),
      "\(sparseFigures.map(\.name)) against \(busyFigures.map(\.name))")
check("a busy character gets denser ones",
      busyFigures.map(\.impliedDensity).reduce(0, +) > sparseFigures.map(\.impliedDensity).reduce(0, +))
check("more than one figure, so the line doesn't just repeat one",
      sparseFigures.count >= 3 && busyFigures.count >= 3)
check("derivation is deterministic", TemplateDerivation.rhythms(for: sparse) == sparseFigures)

check("a named shape is honoured",
      TemplateDerivation.architecture(for: TemplateCharacter(
        name: "x", brief: "y", notesPerBar: 4, airiness: 0.3, offbeatness: 0.3,
        noteLength: 2, shape: "callAnswer")) == .callAnswer)
check("a shape described in words is understood too",
      TemplateDerivation.architecture(for: TemplateCharacter(
        name: "x", brief: "y", notesPerBar: 4, airiness: 0.3, offbeatness: 0.3,
        noteLength: 2, shape: "question and answer pairs")) == .pairs)
check("an unrecognised shape is left to the line rather than guessed",
      TemplateDerivation.architecture(for: TemplateCharacter(
        name: "x", brief: "y", notesPerBar: 4, airiness: 0.3, offbeatness: 0.3,
        noteLength: 2, shape: "banana")) == nil)

// And the whole thing has to compose.
for character in [sparse, busy] {
    let template = TemplateDerivation.template(from: character)
    let composed = MelodyPhrases.compose(bars: 8, seed: 3,
                                         preferring: template.gestureRhythms,
                                         contours: template.gestureContours,
                                         density: template.density,
                                         restiness: template.restiness,
                                         architecture: template.architecture)
    check("\(character.name) composes", !composed.notes.isEmpty, "\(composed.notes.count) notes")
    check("\(character.name) composes near the density it asked for",
          abs(Double(composed.notes.count) / 8 - character.notesPerBar) < 2.5,
          String(format: "asked %.1f, got %.1f", character.notesPerBar,
                 Double(composed.notes.count) / 8))
}

// MARK: - The gate

print()
print("── refusing a template ────────────────────────────")

// The failure the gate exists for: a new name for a line the rotation already
// composes. Built by copying an existing template's numbers exactly.
let copied = TemplateCharacter(
    name: "Not actually new",
    brief: "Long notes with plenty of air between them, letting each one settle.",
    notesPerBar: existing[0].density,
    airiness: existing[0].restiness,
    offbeatness: 0.3,
    noteLength: 5,
    shape: existing[0].architecture.map { String(describing: $0) })
let copiedVerdict = TemplateGate.judge(copied, against: existing)
check("a copy of an existing template is refused", !copiedVerdict.accepted,
      copiedVerdict.summary)
check("and it says which one it duplicates", copiedVerdict.nearest != nil)

// Something genuinely in a gap the nine leave — and finding one took a sweep,
// which is the finding. The obvious guess (very dense, very syncopated) is
// refused, because the composer tops out around six notes a bar and everything
// past that lands on "Running eighths". The gaps are at the *sparse* end.
let novel = TemplateCharacter(
    name: "One note a bar",
    brief: "A single note in each bar, square on the downbeat, and absolutely nothing else. "
         + "Let the harmony do the work.",
    notesPerBar: 1, airiness: 0.0, offbeatness: 0.0, noteLength: 3)
let novelVerdict = TemplateGate.judge(novel, against: existing)
check("something in a gap the others leave is accepted", novelVerdict.accepted,
      novelVerdict.summary)

// The obvious guess, refused — worth asserting, because it's why the gate is
// here rather than being a formality.
let obvious = TemplateCharacter(
    name: "Faster and stranger",
    brief: "As many notes as will fit, and none of them where you expect them.",
    notesPerBar: 8, airiness: 0.0, offbeatness: 1.0, noteLength: 1)
check("asking for more of what a template already does is refused",
      !TemplateGate.judge(obvious, against: existing).accepted,
      TemplateGate.judge(obvious, against: existing).summary)

check("an unnamed template is refused",
      !TemplateGate.judge(TemplateCharacter(name: "", brief: "something long enough to count here",
                                            notesPerBar: 3, airiness: 0.3, offbeatness: 0.3,
                                            noteLength: 2),
                          against: existing).accepted)
check("a template with no real brief is refused",
      !TemplateGate.judge(TemplateCharacter(name: "Terse", brief: "Play it.",
                                            notesPerBar: 3, airiness: 0.3, offbeatness: 0.3,
                                            noteLength: 2),
                          against: existing).accepted)
check("a name already taken is refused",
      !TemplateGate.judge(TemplateCharacter(name: existing[0].name,
                                            brief: "Something entirely different from that one.",
                                            notesPerBar: 8, airiness: 0.9, offbeatness: 0.9,
                                            noteLength: 1),
                          against: existing).accepted)
check("with nothing to compare against, anything reasonable passes",
      TemplateGate.judge(novel, against: []).accepted)

// The threshold has to be meaningful against the set it guards: a bar that every
// existing template would fail is not a bar, it's a wall.
let selfJudgements = existing.map { template -> Bool in
    let others = existing.filter { $0.name != template.name }
    let asCharacter = TemplateCharacter(
        name: template.name + " (again)",
        brief: template.summary.isEmpty ? "A way of playing worth having around." : template.summary,
        notesPerBar: template.density,
        airiness: template.restiness,
        offbeatness: 0.3,
        noteLength: 2,
        shape: template.architecture.map { String(describing: $0) })
    return TemplateGate.judge(asCharacter, against: others).accepted
}
check("the threshold isn't a wall — some existing templates would clear it against the rest",
      selfJudgements.contains(true),
      "\(selfJudgements.filter { $0 }.count) of \(selfJudgements.count) clear it")

// How much room is there at all? This is the number that says what template
// authoring is worth: a sweep of the character space, asking how much of it
// lands somewhere the nine don't already cover.
//
// It is *small*, and knowing that is the point. Authoring templates is a finite
// win — a handful of genuinely new ones and then the gate starts refusing
// everything, which is exactly what it should do. A generator that always says
// yes would just be producing new names for the same nine lines.
var landedSomewhereNew = 0
var swept = 0
for density in stride(from: 1.0, through: 8.0, by: 1.0) {
    for air in stride(from: 0.0, through: 0.8, by: 0.4) {
        for offbeat in stride(from: 0.0, through: 1.0, by: 0.5) {
            let probe = TemplateCharacter(name: "probe",
                                          brief: String(repeating: "x", count: 30),
                                          notesPerBar: density, airiness: air,
                                          offbeatness: offbeat, noteLength: 2)
            swept += 1
            if TemplateGate.judge(probe, against: existing).accepted { landedSomewhereNew += 1 }
        }
    }
}
let coverage = Double(landedSomewhereNew) / Double(swept)
check("the nine already cover most of the reachable space",
      coverage < 0.4,
      "\(landedSomewhereNew) of \(swept) probe characters land somewhere new "
      + "(\(Int(coverage * 100))%)")
check("but not all of it — there is room for a few more",
      landedSomewhereNew > 0, "\(landedSomewhereNew) gaps")

check("judging is deterministic",
      TemplateGate.judge(novel, against: existing).accepted
        == TemplateGate.judge(novel, against: existing).accepted)
check("profiling a template is deterministic",
      TemplateGate.profile(of: existing[0]) == TemplateGate.profile(of: existing[0]))

// MARK: - Keeping them

print()
print("── storing them ───────────────────────────────────")

TemplateStore.remove(named: novel.name)
let before = TemplateStore.characters.count
TemplateStore.add(novel)
check("an accepted template is stored", TemplateStore.characters.count == before + 1)
check("and comes back as a usable template",
      TemplateStore.templates.contains { $0.name == novel.name })
check("and joins the line rotation",
      MelGenTemplates.all(for: .line).contains { $0.name == novel.name })
check("but not the chord one",
      !MelGenTemplates.all(for: .comping).contains { $0.name == novel.name })
TemplateStore.add(novel)
check("adding it twice doesn't duplicate it", TemplateStore.characters.count == before + 1)
TemplateStore.remove(named: novel.name)
check("and it can be removed", TemplateStore.characters.count == before)

// Stored as numbers, so a change to the figure vocabulary improves old templates
// rather than stranding them.
let encoded = try JSONEncoder().encode(novel)
let decoded = try JSONDecoder().decode(TemplateCharacter.self, from: encoded)
check("a character round-trips", decoded == novel)
check("and re-derives the same figures",
      TemplateDerivation.rhythms(for: decoded) == TemplateDerivation.rhythms(for: novel))

print()
print(failures == 0 ? "templates: all checks passed" : "templates: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
