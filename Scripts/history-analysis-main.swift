// Reads exported take histories and reports what's in them.
//
// Everything about learning from curated material is easier to develop against
// exported sessions than against a device — but only if the analysis is the
// *same* analysis the plug-in runs, or it's measuring something else and saying
// it's the same. So this compiles the real Melody sources and calls
// StyleLearner, MelodyAnalyser and the rest directly.
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard !arguments.isEmpty else {
    print("usage: Scripts/analyse-history.sh <export.json | directory> …")
    exit(2)
}

func jsonFiles(at path: String) -> [URL] {
    let url = URL(fileURLWithPath: path)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return [] }
    guard isDirectory.boolValue else { return url.pathExtension == "json" ? [url] : [] }
    let contents = (try? FileManager.default.contentsOfDirectory(at: url,
                                                                includingPropertiesForKeys: nil)) ?? []
    return contents.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
}

let files = arguments.flatMap(jsonFiles(at:))
guard !files.isEmpty else {
    print("No .json exports found.")
    exit(1)
}

func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }
func fixed(_ value: Double, _ places: Int = 1) -> String {
    value.formatted(.number.precision(.fractionLength(places)))
}

/// Takes are deduplicated by id: consecutive exports of one session overlap
/// almost entirely, and counting the same take six times would skew every
/// distribution toward whatever was on screen longest.
var takesByID: [UUID: GenerationRecord] = [:]
var perFile: [(name: String, count: Int, new: Int)] = []

for file in files {
    guard let data = try? Data(contentsOf: file),
          let export = try? MelGenState.decodeHistoryExport(data) else {
        print("  skipped \(file.lastPathComponent) — not a MelGen history export")
        continue
    }
    var new = 0
    for take in export.takes where takesByID[take.id] == nil {
        takesByID[take.id] = take
        new += 1
    }
    perFile.append((file.lastPathComponent, export.takes.count, new))
}

let takes = takesByID.values.sorted { $0.date < $1.date }
guard !takes.isEmpty else {
    print("No takes found.")
    exit(1)
}

print("── files ──────────────────────────────────────────")
for entry in perFile {
    print("  \(entry.name)  \(entry.count) takes, \(entry.new) not seen before")
}
print("  \(takes.count) distinct takes in total")

// MARK: - What produced them

print()
print("── where takes came from ──────────────────────────")
var bySource: [TakeSource: Int] = [:]
var byBrief: [String: Int] = [:]
for take in takes {
    bySource[take.source, default: 0] += 1
    byBrief[take.briefName, default: 0] += 1
}
for (source, count) in bySource.sorted(by: { $0.value > $1.value }) {
    print("  \(source.label.padding(toLength: 8, withPad: " ", startingAt: 0)) \(count)")
}
print()
for (brief, count) in byBrief.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
    print("  \(brief.padding(toLength: 20, withPad: " ", startingAt: 0)) \(count)")
}

// MARK: - What generation cost

let modelTakes = takes.filter { $0.source == .model && $0.generationSeconds > 0 }
if !modelTakes.isEmpty {
    print()
    print("── what the model cost ────────────────────────────")
    let seconds = modelTakes.map(\.generationSeconds)
    let perNote = modelTakes.map { $0.generationSeconds / Double(max(1, $0.noteCount)) }
    print("  \(modelTakes.count) model takes, \(fixed(seconds.reduce(0,+)))s in total")
    print("  per take   min \(fixed(seconds.min() ?? 0))s  median \(fixed(median(seconds)))s  max \(fixed(seconds.max() ?? 0))s")
    print("  per note   min \(fixed(perNote.min() ?? 0, 2))s  median \(fixed(median(perNote), 2))s  max \(fixed(perNote.max() ?? 0, 2))s")
}

// MARK: - Repetition across takes

print()
print("── how much of this is the same line twice ────────")
var byFingerprint: [String: [GenerationRecord]] = [:]
for take in takes {
    let fingerprint = take.notes
        .sorted { $0.startBeat < $1.startBeat }
        .map { "\(Int($0.note)):\(Int($0.startBeat * 2))" }
        .joined(separator: ",")
    byFingerprint[fingerprint, default: []].append(take)
}
let duplicated = byFingerprint.values.filter { $0.count > 1 }.sorted { $0.count > $1.count }
print("  \(byFingerprint.count) distinct lines behind \(takes.count) takes")
for group in duplicated.prefix(5) {
    let take = group[0]
    print("  ×\(group.count)  \(take.source.label) · \(take.briefName) · \(take.noteCount) notes · \(take.progressionText.prefix(28))")
}
if duplicated.isEmpty { print("  no line appears twice") }

// MARK: - Facets

print()
print("── facets across the corpus ───────────────────────")
var densities: [String: Int] = [:]
var placements: [String: Int] = [:]
var motions: [String: Int] = [:]
var colours: [String: Int] = [:]
for take in takes {
    let facets = take.facets
    densities[facets.density.rawValue, default: 0] += 1
    placements[facets.placement.rawValue, default: 0] += 1
    motions[facets.motion.rawValue, default: 0] += 1
    colours[facets.colour.rawValue, default: 0] += 1
}
func show(_ title: String, _ counts: [String: Int]) {
    let line = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        .map { "\($0.key) \($0.value)" }
        .joined(separator: " · ")
    print("  \(title.padding(toLength: 10, withPad: " ", startingAt: 0)) \(line)")
}
show("density", densities)
show("placement", placements)
show("motion", motions)
show("colour", colours)

// MARK: - The style

print()
print("── the style these takes would teach ──────────────")
print("  (every take, as if all of it had been kept — the floor question in")
print("   TRAINING.md §5.2 is what this looks like at 3 takes versus 60)")
print()
let style = StyleLearner.learn(from: takes)
print("  " + style.summary)
print()
print(style.promptText.split(separator: "\n").map { "  " + $0 }.joined(separator: "\n"))

// If anything in the corpus was actually curated, say what changes.
let curated = takes.filter { take in
    guard let disposition = take.latestMark?.disposition else { return false }
    return disposition == .keep || disposition == .tweak || disposition == .partial
}
if !curated.isEmpty {
    print()
    print("── and from the \(curated.count) actually kept ────────────────")
    let curatedStyle = StyleLearner.learn(from: curated)
    print("  " + curatedStyle.summary)
    print()
    print(curatedStyle.promptText.split(separator: "\n").map { "  " + $0 }.joined(separator: "\n"))
} else {
    print()
    print("  Nothing in these exports carries a curation mark — they predate it.")
}

func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted.count.isMultiple(of: 2)
        ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        : sorted[sorted.count / 2]
}
