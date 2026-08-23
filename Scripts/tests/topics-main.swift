// Checks the grouping — and, mostly, checks that it admits what it doesn't know.
//
// The failure this guards against isn't a bad grouping. It's a grouping that
// looks meaningful over thirty lines and isn't, gets named, and becomes a facet
// three months later. So the assertions are: it finds a division that really is
// there, it's deterministic, and it says "provisional" until there's enough
// material to say anything else.
import Foundation

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("  \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { failures += 1 }
}

// MARK: - Terms

print("── the vocabulary a line is described in ──────────")

let line = MelodyPhrases.compose(bars: 4, seed: 5)
let terms = MelodyTopics.terms(of: line)
check("a line has terms", !terms.isEmpty, "\(terms.count) distinct")
check("all three kinds are present",
      terms.keys.contains { $0.hasPrefix("d:") }
      && terms.keys.contains { $0.hasPrefix("r:") }
      && terms.keys.contains { $0.hasPrefix("o:") })
check("onset masks are one bar wide",
      terms.keys.filter { $0.hasPrefix("o:") }.allSatisfy { $0.count == 10 },
      "\(terms.keys.filter { $0.hasPrefix("o:") }.first ?? "none")")
check("big leaps are clamped rather than sprawling the vocabulary",
      terms.keys.filter { $0.hasPrefix("d:") }.allSatisfy {
          ["d:same", "d:+1", "d:+2", "d:+3", "d:+4", "d:-1", "d:-2", "d:-3", "d:-4"].contains($0)
      })
check("an empty line has no terms",
      MelodyTopics.terms(of: MelodyPattern(name: "e", bars: 4, summary: "", notes: [])).isEmpty)
check("terms are deterministic", MelodyTopics.terms(of: line) == terms)

// MARK: - It finds a division that's really there

print()
print("── grouping ───────────────────────────────────────")

// Two deliberately different halves: free-composed lines, and the same kind of
// line forced onto a tresillo. A grouping worth anything separates them.
var mixed = (1...14).map { MelodyPhrases.compose(bars: 4, seed: UInt64($0)) }
let tresilloNames = Set((1...14).map { seed -> String in
    let pattern = MelodyTransforms.applyRhythm(
        MelodyPhrases.compose(bars: 4, seed: UInt64(100 + seed)),
        .euclidean(pulses: 3, steps: 8))
    mixed.append(pattern)
    return pattern.name
})

let (topics, confidence) = MelodyTopics.group(mixed, into: 3)
check("it produces groups", !topics.isEmpty, "\(topics.count)")
check("every line lands in exactly one group",
      topics.reduce(0) { $0 + $1.members.count } == mixed.count,
      "\(topics.reduce(0) { $0 + $1.members.count }) of \(mixed.count)")
check("grouping is deterministic",
      MelodyTopics.group(mixed, into: 3).topics.map(\.members) == topics.map(\.members))

// The tresillo half should mostly end up together — that's the whole test.
let purest = topics.max { left, right in
    let leftShare = Double(left.members.filter { tresilloNames.contains($0) }.count) / Double(left.members.count)
    let rightShare = Double(right.members.filter { tresilloNames.contains($0) }.count) / Double(right.members.count)
    return leftShare < rightShare
}
let share = purest.map {
    Double($0.members.filter { tresilloNames.contains($0) }.count) / Double($0.members.count)
} ?? 0
check("a real division in the material is found",
      share > 0.75, "the purest group is \(Int(share * 100))% tresillo lines")
check("and it's described by the thing that makes it one",
      purest?.distinctiveTerms.contains { $0.contains("3-3-2") || $0.contains("x..x..x.") } ?? false,
      purest?.distinctiveTerms.joined(separator: " ") ?? "")
check("groups report how tightly they hold together",
      topics.allSatisfy { (0...1).contains($0.cohesion) })
check("every group gets a proposed name", topics.allSatisfy { !$0.suggestedName.isEmpty })

// MARK: - Honesty about how little it knows

print()
print("── what it admits ─────────────────────────────────")

let tiny = MelodyTopics.group(Array(mixed.prefix(6)), into: 3)
check("six lines is called noise", tiny.confidence.verdict.lowercased().contains("noise"),
      tiny.confidence.verdict)
check("and isn't worth showing", !tiny.confidence.isWorthShowing)
check("twenty-eight lines is called provisional",
      confidence.verdict.lowercased().contains("provisional"), confidence.verdict)
check("nothing under about forty lines claims to be nameable",
      !confidence.verdict.lowercased().contains("solid"))
check("too few lines to group at all returns nothing rather than inventing groups",
      MelodyTopics.group(Array(mixed.prefix(3)), into: 3).topics.isEmpty)
check("asking a small library for many groups gets fewer, not invented ones",
      MelodyTopics.group(Array(mixed.prefix(8)), into: 8).topics.count <= 3,
      "\(MelodyTopics.group(Array(mixed.prefix(8)), into: 8).topics.count) groups from 8 lines")

// MARK: - Naming

print()
print("── proposed names ─────────────────────────────────")

check("a busy offbeat group is named for it",
      MelodyTopics.name(from: ["o:xxxxxxxx", "d:+1"]).contains("busy"))
check("a sparse on-beat group is named for that",
      MelodyTopics.name(from: ["o:x.......", "d:+1"]).contains("sparse"))
check("a repeated-note group says so",
      MelodyTopics.name(from: ["d:same"]).contains("repeating"))
check("a leaping group says so", MelodyTopics.name(from: ["d:+4"]).contains("leaping"))
check("a loping group says so", MelodyTopics.name(from: ["r:3-3-2"]).contains("loping"))
check("nothing recognisable gets an honest non-name",
      MelodyTopics.name(from: []) == "unnamed group")
check("a name is stable", MelodyTopics.name(from: ["o:x.x.x.x.", "r:2-2", "d:+1"])
        == MelodyTopics.name(from: ["o:x.x.x.x.", "r:2-2", "d:+1"]))

print()
print(failures == 0 ? "topics: all checks passed" : "topics: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
