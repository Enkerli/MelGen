// Turns MelGen's material into a tokenized corpus for off-device training.
//
// This is the middle stage of the pipeline and the reason the pipeline has a
// middle stage at all. Python reads file formats; this decides what the notes
// *mean*; Python trains on the result. The rule that shape enforces:
//
//     There is exactly one implementation of "which degree was that note",
//     and it is `MelodyPatternExtraction.swift` — the one the plug-in runs.
//
// A second tokenizer written in Python would be a second answer to that
// question, and the day the two disagree is the day the iPad plays something
// the training data never said. So this compiles the real Melody sources and
// calls them, exactly as `Scripts/analyse-history.sh` does for measurement.
//
// It reads two things and treats them identically once they are patterns:
//
//   · exported take histories — what you have played and curated;
//   · `events.jsonl` from `Scripts/training/midi_to_events.py` — a collection
//     of MIDI files, with harmony where the files carried it.
//
// And it writes three:
//
//   · corpus.jsonl  — one line per pattern: the token sequence and, in
//                     parallel, the conditioning a neural model can afford and
//                     an n-gram cannot (chord quality, root motion, where the
//                     chord changes);
//   · vocab.json    — the token dictionary, which is the contract between the
//                     training script and the Swift that will run the model;
//   · baseline.json — what `MelodyChain` scores on the held-out split.
//
// The last one is the point of the whole exercise. A neural model here is only
// worth its download and its complexity if it beats the variable-order chain
// that already ships, on material the chain has not seen. That number is
// produced here, by the chain itself, so the comparison is against the real
// thing rather than against a reimplementation of it.

import Foundation

// MARK: - What the MIDI front end wrote

struct MIDIEvent: Codable {
    var beat: Double
    var note: Int
    var velocity: Int
    var isOn: Bool
}

struct MIDIFileRecord: Codable {
    var name: String
    var beatsPerBar: Double
    var endBeat: Double
    var progression: String?
    var progressionSource: String
    var melody: [MIDIEvent]
    var chordEvents: [MIDIEvent]
    var warnings: [String]
}

// MARK: - Naming a chord that arrived as pitches

/// The inverse of the chord dictionary: a set of sounding pitch classes back to
/// a symbol.
///
/// Needed because a chord track carries harmony as *pitches*, and everything
/// downstream — degrees, roles, scales — is defined against a *named* chord.
/// Kept here rather than in `Melody/` deliberately: it is corpus preparation,
/// not something the plug-in does, and `verify.sh` compiles every file in
/// `Melody/` into every suite.
enum ChordNaming {

    /// Flats, because this is a jazz dictionary and "E♭7" is how it is written.
    static let rootNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    /// Scores every root against every quality and takes the best fit.
    ///
    /// Scoring is deliberately blunt: a missing chord tone costs more than an
    /// extra sounding note, because a voicing that omits the fifth is ordinary
    /// and one that adds a note the quality doesn't have is a different chord.
    /// The bass gets a thumb on the scale for the root, and simpler qualities
    /// win ties, or every triad would be named as some thirteenth chord with
    /// four notes missing.
    static func name(pitchClasses: Set<Int>, bass: Int?) -> ChordSymbol? {
        guard pitchClasses.count >= 3 else { return nil }
        var best: (score: Double, symbol: ChordSymbol)?

        for root in 0..<12 {
            for quality in ChordDictionary.allQualities {
                let tones = Set(quality.pitchClasses.map { (root + $0) % 12 })
                let matched = tones.intersection(pitchClasses).count
                guard matched >= 3 else { continue }
                let missing = tones.subtracting(pitchClasses).count
                let extra = pitchClasses.subtracting(tones).count

                var score = Double(matched) - 2.0 * Double(missing) - 1.5 * Double(extra)
                score -= 0.05 * Double(tones.count)
                if let bass, bass % 12 == root { score += 0.75 }
                if best == nil || score > best!.score {
                    let suffix = ChordDictionary.displaySuffix(forKey: quality.key)
                    let symbol = ChordSymbol(rootPitchClass: root,
                                             quality: quality,
                                             bassPitchClass: nil,
                                             text: rootNames[root] + suffix)
                    best = (score, symbol)
                }
            }
        }
        return best?.symbol
    }

    /// Groups a chord track's note-ons into simultaneities and names each one.
    ///
    /// Onsets within a sixteenth of each other are one chord: a block voicing
    /// played by a human is never perfectly simultaneous. An *arpeggiated*
    /// chord track defeats this and will come out as a run of wrong triads —
    /// which is why the caller reports how many chords it named and over what.
    static func progression(from events: [MIDIEvent],
                            endBeat: Double,
                            beatsPerBar: Double) -> ChordProgression? {
        let onsets = events.filter { $0.isOn }.sorted { $0.beat < $1.beat }
        guard !onsets.isEmpty else { return nil }

        var clusters: [(beat: Double, pitches: [Int])] = []
        for onset in onsets {
            if var last = clusters.last, onset.beat - last.beat <= 0.25 {
                last.pitches.append(onset.note)
                clusters[clusters.count - 1] = last
            } else {
                clusters.append((onset.beat, [onset.note]))
            }
        }

        var placed: [PlacedChord] = []
        for (index, cluster) in clusters.enumerated() {
            let end = index + 1 < clusters.count ? clusters[index + 1].beat : max(endBeat, cluster.beat + beatsPerBar)
            let duration = max(0.25, end - cluster.beat)
            guard let symbol = name(pitchClasses: Set(cluster.pitches.map { $0 % 12 }),
                                    bass: cluster.pitches.min().map { $0 % 12 })
            else { continue }
            // A repeat of the chord already sounding is the same chord held.
            if var last = placed.last, last.symbol.text == symbol.text,
               abs(last.startBeat + last.durationBeats - cluster.beat) < 0.01 {
                last.durationBeats += duration
                placed[placed.count - 1] = last
            } else {
                placed.append(PlacedChord(symbol: symbol, startBeat: cluster.beat, durationBeats: duration))
            }
        }

        guard !placed.isEmpty else { return nil }
        let total = max(endBeat, placed.last!.startBeat + placed.last!.durationBeats)
        let text = placed.map { $0.symbol.text }.joined(separator: " | ")
        return ChordProgression(text: text, chords: placed, totalBeats: total)
    }
}

// MARK: - What gets written

/// One pattern, tokenized, with the conditioning a model can read.
///
/// Parallel arrays rather than an array of objects: every one of these is a
/// tensor column on the other side of the pipeline, and writing them the way
/// they will be read saves the training script a transposition it would
/// otherwise get wrong once.
struct CorpusItem: Codable {
    var name: String
    var bars: Int
    var split: String
    var provenance: String
    var progression: String
    /// `degree:alteration:lengthEighths:restAfterEighths`, as `ChainToken.key`.
    var tokens: [String]
    /// Where in the bar each event starts, 0–7.
    var metric: [Int]
    var phrase: [String]
    /// Dictionary key of the chord sounding at each event.
    var quality: [String]
    /// Semitones from this chord's root to the next chord's, folded to −6…5.
    /// Zero where the chord doesn't change again. The single most useful thing
    /// a melody model can know that a per-note model can't see.
    var rootMotion: [Int]
    /// Eighths until the harmony changes, clamped to 16.
    var eighthsToChange: [Int]
    var role: [String]
}

struct BaselineReport: Codable {
    var trainPatterns: Int
    var validationPatterns: Int
    var validationEvents: Int
    var vocabulary: Int
    /// Mean negative log-likelihood per event, natural log. Lower is better.
    var chainNLL: Double
    var chainPerplexity: Double
    var chainTop1: Double
    var smoothing: Double
    var note: String
}

// MARK: - Helpers

/// FNV-1a, because `Hasher` is salted per process and a split has to be the
/// same split tomorrow and on another machine.
func stableHash(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return hash
}

func signature(of pattern: MelodyPattern) -> String {
    pattern.notes
        .sorted { $0.startEighth < $1.startEighth }
        .map { "\($0.startEighth):\(ChainToken($0).key)" }
        .joined(separator: ",")
}

func foldedMotion(_ semitones: Int) -> Int {
    var value = ((semitones % 12) + 12) % 12
    if value >= 6 { value -= 12 }
    return value
}

func jsonFiles(at path: String) -> [URL] {
    let url = URL(fileURLWithPath: path)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return [] }
    guard isDirectory.boolValue else { return [url] }
    let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
    return contents.filter { $0.pathExtension == "json" || $0.pathExtension == "jsonl" }
        .sorted { $0.path < $1.path }
}

// MARK: - Reading material in

/// A pattern and the harmony it was played over, which is the pair everything
/// downstream needs. A pattern alone can't say what a degree meant.
struct Sourced {
    var pattern: MelodyPattern
    var progression: ChordProgression
    var provenance: String
}

func patterns(fromHistory url: URL, keptOnly: Bool, into result: inout [UUID: GenerationRecord]) -> Bool {
    guard let data = try? Data(contentsOf: url),
          let export = try? MelGenState.decodeHistoryExport(data) else { return false }
    for take in export.takes {
        // Deduplicated by id: consecutive exports of one session overlap almost
        // entirely, and counting a take six times would weight it six times.
        if result[take.id] != nil { continue }
        if keptOnly {
            let kept: Set<TakeDisposition> = [.keep, .tweak, .partial, .context]
            guard let mark = take.latestMark, kept.contains(mark.disposition) else { continue }
        }
        result[take.id] = take
    }
    return true
}

func sourced(fromMIDI record: MIDIFileRecord) -> (items: [Sourced], reason: String?) {
    let progression: ChordProgression?
    switch record.progressionSource {
    case "sidecar", "marker":
        progression = record.progression.flatMap { try? ChordProgression.parse($0, beatsPerBar: record.beatsPerBar) }
    case "chordTrack":
        progression = ChordNaming.progression(from: record.chordEvents,
                                              endBeat: record.endBeat,
                                              beatsPerBar: record.beatsPerBar)
    default:
        progression = nil
    }

    // A file with no harmony still has rhythm and contour in it, and none of
    // that is expressible in this corpus: every token is a *degree*, and a
    // degree with no chord under it is a pitch with a story attached. Counted
    // and reported rather than guessed at.
    guard let progression else { return ([], "no harmony") }
    guard !record.melody.isEmpty else { return ([], "no melody track") }

    let events = record.melody.map {
        CapturedMIDIEvent(beat: $0.beat, note: UInt8(clamping: $0.note),
                          velocity: UInt8(clamping: $0.velocity), isOn: $0.isOn)
    }
    let sounded = MelodyCapture.notes(from: events, endingAt: record.endBeat)
    let phrases = MelodyCapture.phrases(from: sounded)
    guard !phrases.isEmpty else { return ([], "no phrase survived segmentation") }

    let stem = (record.name as NSString).deletingPathExtension
    var items: [Sourced] = []
    for (index, phrase) in phrases.enumerated() {
        guard let pattern = MelodyCapture.pattern(from: phrase,
                                                  over: progression,
                                                  name: "\(stem) \(index + 1)",
                                                  at: phrase.startBeat)
        else { continue }
        items.append(Sourced(pattern: pattern, progression: progression, provenance: "midi"))
    }
    return (items, items.isEmpty ? "no phrase could be placed against the harmony" : nil)
}

// MARK: - Tokenizing

func tokenize(_ item: Sourced, split: String) -> CorpusItem? {
    let notes = item.pattern.notes.sorted { $0.startEighth < $1.startEighth }
    guard notes.count >= 2 else { return nil }
    let progression = item.progression
    let chords = progression.chords

    var corpus = CorpusItem(name: item.pattern.name,
                            bars: max(1, item.pattern.bars),
                            split: split,
                            provenance: item.provenance,
                            progression: progression.text,
                            tokens: [], metric: [], phrase: [], quality: [],
                            rootMotion: [], eighthsToChange: [], role: [])

    for note in notes {
        let beat = Double(note.startEighth) / 2
        corpus.tokens.append(ChainToken(note).key)
        corpus.metric.append(note.startEighth % 8)
        corpus.phrase.append(PhrasePosition.at(eighth: note.startEighth,
                                               ofBars: corpus.bars).rawValue)

        guard let current = progression.chord(at: beat) else {
            corpus.quality.append("")
            corpus.rootMotion.append(0)
            corpus.eighthsToChange.append(16)
            corpus.role.append(note.role?.rawValue ?? "unclassified")
            continue
        }
        corpus.quality.append(current.symbol.quality.key)

        let next = chords.first { $0.startBeat > current.startBeat }
        corpus.rootMotion.append(next.map {
            foldedMotion($0.symbol.rootPitchClass - current.symbol.rootPitchClass)
        } ?? 0)
        let changeBeat = next?.startBeat ?? progression.totalBeats
        corpus.eighthsToChange.append(min(16, max(0, Int(((changeBeat - beat) * 2).rounded()))))
        corpus.role.append(note.role?.rawValue ?? "unclassified")
    }
    return corpus
}

// MARK: - The baseline the neural model has to beat

/// Held-out likelihood under `MelodyChain`, using the chain's own backoff rule.
///
/// Mirrors `MelodyChain.next(after:…)`: walk the ladder, take the first rung
/// seen at least `trustThreshold` times, and read the distribution there. The
/// one addition is add-k smoothing, because a held-out event the chain has
/// never seen has probability zero and an infinite loss, which measures nothing
/// except that the corpus is finite.
func evaluate(chain: MelodyChain, on items: [CorpusItem], vocabulary: Int, k: Double) -> (nll: Double, top1: Double, events: Int) {
    var total = 0.0
    var correct = 0
    var count = 0

    for item in items {
        var history: [ChainToken] = []
        for (index, key) in item.tokens.enumerated() {
            guard let token = ChainToken(key: key) else { continue }
            let phrase = PhrasePosition(rawValue: item.phrase[index]) ?? .middle
            let keys = MelodyChain.contextKeys(history: history,
                                               metricPosition: item.metric[index],
                                               phrase: phrase)
            var distribution: [String: Int] = [:]
            for candidate in keys {
                guard let found = chain.counts[candidate] else { continue }
                let sum = found.values.reduce(0, +)
                guard sum >= MelodyChain.trustThreshold || candidate.hasPrefix("0|") else { continue }
                distribution = found
                break
            }

            let observed = Double(distribution[token.key] ?? 0)
            let sum = Double(distribution.values.reduce(0, +))
            let probability = (observed + k) / (sum + k * Double(max(1, vocabulary)))
            total += -log(probability)
            if let best = distribution.max(by: { $0.value < $1.value })?.key, best == token.key {
                correct += 1
            }
            count += 1

            history.append(token)
            if history.count > MelodyChain.maxOrder { history.removeFirst() }
        }
    }

    guard count > 0 else { return (0, 0, 0) }
    return (total / Double(count), Double(correct) / Double(count), count)
}

// MARK: - Driver

var historyPaths: [String] = []
var eventPaths: [String] = []
var outputPath = "corpus"
var keptOnly = true
var validationFraction = 0.15
var smoothing = 0.1

let arguments = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "--events":
        index += 1
        if index < arguments.count { eventPaths.append(arguments[index]) }
    case "--out":
        index += 1
        if index < arguments.count { outputPath = arguments[index] }
    case "--validation":
        index += 1
        if index < arguments.count { validationFraction = Double(arguments[index]) ?? 0.15 }
    case "--smoothing":
        index += 1
        if index < arguments.count { smoothing = Double(arguments[index]) ?? 0.1 }
    case "--all-takes":
        keptOnly = false
    case "--help", "-h":
        print("""
        usage: Scripts/export-corpus.sh [history.json | directory …] [options]

          --events <events.jsonl>   output of Scripts/training/midi_to_events.py (repeatable)
          --out <directory>         where to write the corpus (default: corpus)
          --all-takes               include takes you didn't keep (default: kept only)
          --validation <fraction>   held-out share, split by line (default: 0.15)
          --smoothing <k>           add-k smoothing for the baseline (default: 0.1)
        """)
        exit(0)
    default:
        historyPaths.append(argument)
    }
    index += 1
}

guard !historyPaths.isEmpty || !eventPaths.isEmpty else {
    print("usage: Scripts/export-corpus.sh [history.json | directory …] [--events events.jsonl]")
    exit(2)
}

// 1. Everything becomes a pattern with the harmony it was played over.

var items: [Sourced] = []
var takesByID: [UUID: GenerationRecord] = [:]

for path in historyPaths {
    for url in jsonFiles(at: path) where url.pathExtension == "json" {
        if !patterns(fromHistory: url, keptOnly: keptOnly, into: &takesByID) {
            print("  skipped \(url.lastPathComponent) — not a MelGen history export")
        }
    }
}

for take in takesByID.values.sorted(by: { $0.date < $1.date }) {
    guard let progression = try? ChordProgression.parse(take.progressionText),
          let pattern = MelodyPatterns.extract(from: take.notes,
                                               over: progression,
                                               name: take.displayName,
                                               lengthBeats: take.lengthBeats)
    else { continue }
    items.append(Sourced(pattern: pattern, progression: progression, provenance: "take"))
}

var midiFiles = 0
var midiRejections: [String: Int] = [:]
for path in eventPaths {
    guard let text = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
        print("  could not read \(path)")
        continue
    }
    for line in text.split(separator: "\n") {
        guard let data = line.data(using: .utf8),
              let record = try? JSONDecoder().decode(MIDIFileRecord.self, from: data) else { continue }
        midiFiles += 1
        let (produced, reason) = sourced(fromMIDI: record)
        if let reason { midiRejections[reason, default: 0] += 1 }
        items.append(contentsOf: produced)
    }
}

guard !items.isEmpty else {
    print("No patterns could be built. Nothing to train on.")
    exit(1)
}

// 2. The same line twice is one line.
//
// The first exported session held 60 distinct lines behind 98 takes, and the
// duplicates were the six stored seeds cycling. Left in, they would be counted
// six times over *and* land on both sides of the split, which is the classic
// way to measure a model on its own training data and call it generalization.

var seen: Set<String> = []
var unique: [Sourced] = []
var duplicates = 0
for item in items {
    let key = signature(of: item.pattern)
    if seen.insert(key).inserted { unique.append(item) } else { duplicates += 1 }
}

// 3. Split by line, deterministically, so the split is the same tomorrow.

var trainItems: [CorpusItem] = []
var validationItems: [CorpusItem] = []
let threshold = UInt64(max(0, min(1, validationFraction)) * 10_000)
for item in unique {
    let isValidation = stableHash(signature(of: item.pattern)) % 10_000 < threshold
    guard let tokenized = tokenize(item, split: isValidation ? "validation" : "train") else { continue }
    if isValidation { validationItems.append(tokenized) } else { trainItems.append(tokenized) }
}

guard !trainItems.isEmpty else {
    print("Everything landed in the validation split. Lower --validation.")
    exit(1)
}

// 4. The vocabulary, which is the contract with the other side of the pipeline.

var tokenCounts: [String: Int] = [:]
var qualitySet: Set<String> = []
var roleSet: Set<String> = []
for item in trainItems + validationItems {
    for token in item.tokens { tokenCounts[token, default: 0] += 1 }
    for quality in item.quality where !quality.isEmpty { qualitySet.insert(quality) }
    for role in item.role { roleSet.insert(role) }
}

// Frequency order, ties broken by key so the file is byte-identical between
// runs over the same corpus — a vocabulary that reshuffles silently is a
// vocabulary that will one day be paired with the wrong weights.
let ordered = tokenCounts.sorted {
    $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
}.map { $0.key }
let specials = ["<pad>", "<bos>", "<eos>"]
var tokenIndex: [String: Int] = [:]
for (offset, key) in specials.enumerated() { tokenIndex[key] = offset }
for (offset, key) in ordered.enumerated() { tokenIndex[key] = offset + specials.count }

let totalEvents = tokenCounts.values.reduce(0, +)
var running = 0
var typesFor95 = 0
for key in ordered {
    running += tokenCounts[key] ?? 0
    typesFor95 += 1
    if Double(running) >= 0.95 * Double(totalEvents) { break }
}

let vocabulary: [String: Any] = [
    "schemaVersion": 1,
    "tokenKeyFormat": "degree:alteration:lengthEighths:restAfterEighths",
    "eighthsPerBar": 8,
    "maxOrderOfBaseline": MelodyChain.maxOrder,
    "specials": Dictionary(uniqueKeysWithValues: specials.enumerated().map { ($1, $0) }),
    "tokens": tokenIndex,
    "counts": tokenCounts,
    "qualities": Dictionary(uniqueKeysWithValues: qualitySet.sorted().enumerated().map { ($1, $0) }),
    "roles": Dictionary(uniqueKeysWithValues: roleSet.sorted().enumerated().map { ($1, $0) }),
    "phrases": PhrasePosition.allCases.map { $0.rawValue },
    "metricPositions": 8,
]

// 5. What the chain scores on material it has not seen.

// Trained on the train split by the same rule that made the split, rather
// than by matching names back up: two lines are allowed to share a name.
let chain = MelodyChain.learn(from: unique.filter {
    stableHash(signature(of: $0.pattern)) % 10_000 >= threshold
}.map { $0.pattern })
if validationItems.isEmpty {
    print("  ⚠︎ nothing was held out, so there is no number to beat.")
    print("    Raise --validation, or find more distinct lines.")
}
let scored = evaluate(chain: chain, on: validationItems, vocabulary: tokenIndex.count, k: smoothing)

let report = BaselineReport(
    trainPatterns: trainItems.count,
    validationPatterns: validationItems.count,
    validationEvents: scored.events,
    vocabulary: tokenIndex.count,
    chainNLL: scored.nll,
    chainPerplexity: exp(scored.nll),
    chainTop1: scored.top1,
    smoothing: smoothing,
    note: "MelodyChain with backoff, trained on the train split only. "
        + "A neural model is worth its download only if it beats this."
)

// 6. Write.

let outputDirectory = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

var corpusLines: [String] = []
for item in trainItems + validationItems {
    guard let data = try? encoder.encode(item),
          let line = String(data: data, encoding: .utf8) else { continue }
    corpusLines.append(line)
}
try? corpusLines.joined(separator: "\n").write(to: outputDirectory.appendingPathComponent("corpus.jsonl"),
                                               atomically: true, encoding: .utf8)

if let data = try? JSONSerialization.data(withJSONObject: vocabulary,
                                          options: [.prettyPrinted, .sortedKeys]) {
    try? data.write(to: outputDirectory.appendingPathComponent("vocab.json"))
}

encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
if let data = try? encoder.encode(report) {
    try? data.write(to: outputDirectory.appendingPathComponent("baseline.json"))
}

// 7. Say what happened.

print("── material ───────────────────────────────────────")
print("  \(takesByID.count) takes from exported history")
print("  \(midiFiles) MIDI files read")
for (reason, count) in midiRejections.sorted(by: { $0.value > $1.value }) {
    print("    \(count) contributed nothing — \(reason)")
}
print("  \(items.count) patterns, \(duplicates) of them the same line twice")
print()
print("── corpus ─────────────────────────────────────────")
print("  \(trainItems.count) train / \(validationItems.count) held out, split by line")
print("  \(totalEvents) events, \(tokenIndex.count) token types")
print("  \(typesFor95) types cover 95% of events")
if tokenIndex.count > totalEvents / 4 {
    print("  ⚠︎ the vocabulary is large against the corpus — most tokens are seen")
    print("    once or twice, which is a corpus problem no architecture fixes")
}
print()
print("── the number to beat ─────────────────────────────")
print("  MelodyChain on held-out material:")
print("    per-event loss   \(String(format: "%.4f", report.chainNLL)) nats")
print("    perplexity       \(String(format: "%.1f", report.chainPerplexity))")
print("    top-1 accuracy   \(String(format: "%.1f", report.chainTop1 * 100))%")
print()
print("  Written to \(outputDirectory.path)/")
