//
//  MelGenState.swift
//  MelGenExtension
//
//  Everything about a MelGen session that isn't an AU parameter: the
//  progression, the generation settings, and the log of takes the model has
//  produced. The audio unit owns one of these and saves it in its full state,
//  so a host session reopens with the same progression and the same melody
//  playing, and with the history intact.
//

import Foundation

/// Where a take's notes came from.
enum TakeSource: String, Codable, Sendable {
    /// Composed by the on-device model.
    case model
    /// A stored line fitted to this progression — instant, no model.
    case pattern
    /// Built here and now out of gestures, by the phrase grammar. Also instant,
    /// and unlike a stored line it has never existed before.
    case composed
    /// Drawn from the slot statistics of the takes you kept. Instant too, and the
    /// only one of the four that sounds like *your* material rather than like a
    /// vocabulary somebody wrote down.
    case sampled
    /// Walked through the variable-order model of what follows what in that same
    /// material. Also yours, and — unlike the slot draw — it has phrases, because
    /// it remembers what it just played.
    case chained
    /// A transform of another take, or a point on the morph between two of them.
    /// The only source whose provenance names a parent rather than a progression.
    case mutated
    /// Played in. The only source that didn't come from this plug-in at all.
    case captured
    /// Chords rather than a line.
    case comping

    var label: String {
        switch self {
        case .model: return "model"
        case .pattern: return "line"
        case .composed: return "phrase"
        case .sampled: return "learned"
        case .chained: return "chained"
        case .mutated: return "variant"
        case .captured: return "played"
        case .comping: return "comp"
        }
    }
}

/// One take. `notes` is the raw output, before expression is applied, so changing
/// the expression controls re-renders old takes too.
struct GenerationRecord: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var date: Date = Date()
    var progressionText: String
    var temperature: Double
    /// Name of the style brief that shaped this take, for the log.
    var briefName: String
    /// The density this take was asked for, so the density control knows how far
    /// it can thin the line without a new generation.
    var density: Double = 0.5
    /// The rhythmic palette this take was written with, for the log.
    var durationPalette: DurationPalette = .mixed
    /// Wall-clock seconds the model took. Recorded because "new take every loop"
    /// is only a promise we can keep if generation finishes inside a loop, and
    /// nobody knew whether it did.
    var generationSeconds: Double = 0
    /// How many model requests this take needed (one per 4-bar phrase).
    var requestCount: Int = 1
    var source: TakeSource = .model
    /// Measured after the notes were settled, so curation has something to sort
    /// by and non-chord tones are flagged for a human rather than judged here.
    var analysis: MelodyAnalysis?
    /// Every judgement ever made about this take, not just the latest one.
    /// A take skipped on the first pass and kept on the third isn't a
    /// correction — the disagreement is the most interesting thing in the record.
    var marks: [CurationMark] = []
    /// Free text, the emergent half of the vocabulary.
    var tags: [String] = []
    /// A name, when it has earned one.
    var title: String = ""
    var lengthBeats: Double
    var notes: [SequencedNote]

    var noteCount: Int { notes.count }

    /// The most recent judgement, whichever pass it was made on.
    var latestMark: CurationMark? {
        marks.max { ($0.pass, $0.date) < ($1.pass, $1.date) }
    }

    /// What was decided on a particular sweep, if anything was.
    func mark(onPass pass: Int) -> CurationMark? {
        marks.filter { $0.pass == pass }.max { $0.date < $1.date }
    }

    /// Whether the history ring is allowed to drop this.
    var survivesEviction: Bool {
        guard let latest = latestMark else { return false }
        return latest.disposition.protectsFromEviction
    }

    /// The structural facets, derived rather than typed.
    var facets: TakeFacets {
        TakeFacetting.facets(for: notes,
                             lengthBeats: lengthBeats,
                             analysis: analysis,
                             source: source)
    }

    /// What to call this in a list.
    var displayName: String {
        title.isEmpty ? "\(progressionText) · \(briefName)" : title
    }

    // Decoded field by field so a session saved by an older build still opens:
    // synthesized Codable throws on a missing key even when the property has a
    // default, which would silently wipe the history.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        progressionText = try container.decodeIfPresent(String.self, forKey: .progressionText) ?? ""
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.6
        briefName = try container.decodeIfPresent(String.self, forKey: .briefName) ?? ""
        density = try container.decodeIfPresent(Double.self, forKey: .density) ?? 0.5
        durationPalette = try container.decodeIfPresent(DurationPalette.self, forKey: .durationPalette) ?? .mixed
        generationSeconds = try container.decodeIfPresent(Double.self, forKey: .generationSeconds) ?? 0
        requestCount = try container.decodeIfPresent(Int.self, forKey: .requestCount) ?? 1
        source = try container.decodeIfPresent(TakeSource.self, forKey: .source) ?? .model
        analysis = try container.decodeIfPresent(MelodyAnalysis.self, forKey: .analysis)
        marks = try container.decodeIfPresent([CurationMark].self, forKey: .marks) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        lengthBeats = try container.decodeIfPresent(Double.self, forKey: .lengthBeats) ?? 0
        notes = try container.decodeIfPresent([SequencedNote].self, forKey: .notes) ?? []
    }

    init(id: UUID = UUID(),
         date: Date = Date(),
         progressionText: String,
         temperature: Double,
         briefName: String,
         density: Double = 0.5,
         durationPalette: DurationPalette = .mixed,
         generationSeconds: Double = 0,
         requestCount: Int = 1,
         source: TakeSource = .model,
         analysis: MelodyAnalysis? = nil,
         marks: [CurationMark] = [],
         tags: [String] = [],
         title: String = "",
         lengthBeats: Double,
         notes: [SequencedNote]) {
        self.id = id
        self.date = date
        self.progressionText = progressionText
        self.temperature = temperature
        self.briefName = briefName
        self.density = density
        self.durationPalette = durationPalette
        self.generationSeconds = generationSeconds
        self.requestCount = requestCount
        self.source = source
        self.analysis = analysis
        self.marks = marks
        self.tags = tags
        self.title = title
        self.lengthBeats = lengthBeats
        self.notes = notes
    }
}

/// Which rhythmic values the model should write.
///
/// This is *note duration* — the written rhythm — as distinct from gate length,
/// which is how much of a note's slot is actually sounded. The two interact (a
/// long–short figure played staccato reads differently from the same figure
/// played legato) but they are separate decisions, and only this one requires a
/// new take.
///
/// Every option here is representable on the eighth-note grid the model writes
/// to. Triplets are not, and need a finer grid first — see ROADMAP.md.
enum DurationPalette: String, Codable, CaseIterable, Sendable {
    case even, longShort, shortLong, mixed

    var label: String {
        switch self {
        case .even: return "Even"
        case .longShort: return "Long–short"
        case .shortLong: return "Short–long"
        case .mixed: return "Mixed"
        }
    }

    var promptText: String {
        switch self {
        case .even:
            return "Rhythm values: keep to even values — steady eighths, or steady quarters. "
                 + "No dotted figures."
        case .longShort:
            return "Rhythm values: favour long–short pairs — three eighths then one, or a dotted "
                 + "quarter then an eighth. Let the figure recur so it reads as a groove."
        case .shortLong:
            return "Rhythm values: favour short–long pairs — a single eighth pickup into a note "
                 + "of three or more eighths, so phrases lean forward into their long notes."
        case .mixed:
            return "Rhythm values: mix freely — 1, 2, 3, 4 and 6 eighths — and don't repeat the "
                 + "same figure twice in a row."
        }
    }
}

/// How a take is rendered into the notes that actually play.
struct ExpressionSettings: Codable, Hashable, Sendable {
    /// 0 = play the model's velocities on a strict grid; 1 = strong metric
    /// accents, varied articulation and loose timing.
    var amount: Double = 0.5
    /// 0 = straight eighths; 1 = fully swung (offbeat lands two thirds through).
    var swing: Double = 0
    /// Gate length: 0 = clipped staccato, 0.5 = as written, 1 = legato (each note
    /// runs into the next). How much of a note's slot sounds, not what the
    /// written rhythm is — see `DurationPalette` for that.
    var noteLength: Double = 0.5
    /// How busy the line is. Above the take's own density this asks the *next*
    /// take for more notes; below it, notes are dropped from this take now,
    /// weakest metric positions first, which is how rests get added.
    var density: Double = 0.5

    init(amount: Double = 0.5, swing: Double = 0, noteLength: Double = 0.5, density: Double = 0.5) {
        self.amount = amount
        self.swing = swing
        self.noteLength = noteLength
        self.density = density
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try container.decodeIfPresent(Double.self, forKey: .amount) ?? 0.5
        swing = try container.decodeIfPresent(Double.self, forKey: .swing) ?? 0
        noteLength = try container.decodeIfPresent(Double.self, forKey: .noteLength) ?? 0.5
        density = try container.decodeIfPresent(Double.self, forKey: .density) ?? 0.5
    }
}

/// Which appearance the plug-in window uses, independent of the host.
enum MelGenAppearance: String, Codable, CaseIterable, Sendable {
    case light, dark, system

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "Auto"
        }
    }

    var symbolName: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

struct MelGenState: Codable, Sendable {
    /// How many unjudged takes the ring holds before it starts dropping them.
    ///
    /// Was 24, which came from "a history is a scrollable list" and made sense
    /// when a take was a log entry. It isn't one any more — it's curation
    /// material, and a sweep over a second pass needs the first pass still to be
    /// there. A take is a few kilobytes of JSON in the host's saved state; two
    /// hundred of them is about a megabyte, which is nothing next to the audio
    /// in the same project. The list is what needed bounding, not the store, so
    /// the interface pages instead.
    static let historyLimit = 250
    /// And the hard ceiling, past which even judged takes go. Far above the ring
    /// because keeping a take costs a few kilobytes and losing one you marked is
    /// unrecoverable.
    static let historyCeiling = 1000

    var progressionText: String = "E♭7 Gm9|D∆|A♭6"
    var temperature: Double = 0.6
    var durationPalette: DurationPalette = .mixed
    var expression = ExpressionSettings()
    /// How much the loop drifts as it plays. Applied at render time, so it never
    /// touches the take.
    var liveMutation = LiveMutation()
    /// Which pass the drift is on. Bumped by the transport loop, and part of the
    /// seed, so a pass that sounded good can be got back.
    var mutationPass: Int = 0

    /// Line or chords.
    ///
    /// Explicit and visible because the *receiving instrument* differs: a mono
    /// synth handed comping chords plays whichever note wins its note-priority
    /// rule, which is not music. This is the one setting in the plug-in that
    /// changes what you should plug it into.
    var mode: PlayMode = .line
    /// Which comping figure is in play, by name.
    var compingFigureName: String = CompingFigure.charleston.name

    /// Settings for generating the changes themselves.
    var progressionKey: Int = 0
    var progressionMode: ProgressionMode = .major
    var progressionBars: Int = 8
    /// Bumped per generation so the same settings give a new progression.
    var progressionCursor: Int = 0
    /// How far down each transition's ranked list to reach.
    var progressionSurprise: Double = 0.35
    /// How hard to avoid the moves everyone makes.
    var progressionFreshness: Freshness = .fresh
    /// 1 chord or 2 — the plain first-order walk, or the longer context that
    /// produces phrasing.
    var progressionContext: Int = 2
    /// Which substitutions are in play, and how often.
    var progressionReharm: Reharm = .subtle
    /// Change key every N bars. 0 for none.
    var progressionModulation: Int = 0

    /// Which groups of the interface are unfolded.
    var showShape: Bool = true
    var showFeel: Bool = true
    var showHistory: Bool = false

    /// Light by default: the suite designs for paper first, and a plug-in window
    /// shouldn't be at the mercy of whatever the host is set to.
    var appearance: MelGenAppearance = .light

    /// Regenerate on its own while playing, giving a new take every few passes.
    var autoRegenerate: Bool = false
    var regenerateEveryPasses: Int = 1

    /// Rotates through the style briefs so successive takes differ.
    var briefCursor: Int = 0
    /// Rotates through the stored generic lines, for the same reason.
    var patternCursor: Int = 0

    /// Which briefs are in play. Empty means all of them, so a session saved
    /// before selection existed behaves exactly as it did.
    var selectedBriefNames: [String] = []
    var briefMode: SelectionMode = .cycle
    /// The brief the rotation is pinned to, in lock mode.
    var lockedBriefName: String?

    var lineMode: SelectionMode = .cycle
    /// The stored line the rotation is pinned to, in lock mode.
    var lockedLineName: String?

    /// Which model a draw from your own material comes out of. They learn
    /// different things from the same takes and sound different because of it,
    /// so this is a choice rather than something to pick automatically.
    var learnedDraw: LearnedDraw = .chain

    /// Newest first. The take at `currentTakeID` is the one loaded in the kernel.
    var history: [GenerationRecord] = []
    var currentTakeID: UUID?
    /// The take that was playing before this one, so a judgement can record what
    /// it was heard against — "dull after that, perfect after this" is a fact
    /// about the pair. Not restored when a session reopens: it describes a
    /// listening session, not a document.
    var previousTakeID: UUID?

    /// Which curation sweep we're on. Marks are stamped with it, so the same take
    /// judged twice keeps both answers rather than overwriting the first.
    var curationPass: Int = 1
    /// The tags actually in use, so the interface can offer the vocabulary that
    /// emerged rather than one somebody guessed at.
    var tagVocabulary = TagVocabulary()

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        progressionText = try container.decodeIfPresent(String.self, forKey: .progressionText) ?? "E♭7 Gm9|D∆|A♭6"
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.6
        durationPalette = try container.decodeIfPresent(DurationPalette.self, forKey: .durationPalette) ?? .mixed
        expression = try container.decodeIfPresent(ExpressionSettings.self, forKey: .expression) ?? ExpressionSettings()
        liveMutation = try container.decodeIfPresent(LiveMutation.self, forKey: .liveMutation) ?? LiveMutation()
        mutationPass = try container.decodeIfPresent(Int.self, forKey: .mutationPass) ?? 0
        mode = try container.decodeIfPresent(PlayMode.self, forKey: .mode) ?? .line
        progressionKey = try container.decodeIfPresent(Int.self, forKey: .progressionKey) ?? 0
        progressionMode = try container.decodeIfPresent(ProgressionMode.self, forKey: .progressionMode) ?? .major
        progressionBars = try container.decodeIfPresent(Int.self, forKey: .progressionBars) ?? 8
        progressionCursor = try container.decodeIfPresent(Int.self, forKey: .progressionCursor) ?? 0
        progressionSurprise = try container.decodeIfPresent(Double.self, forKey: .progressionSurprise) ?? 0.35
        progressionFreshness = try container.decodeIfPresent(Freshness.self, forKey: .progressionFreshness) ?? .fresh
        progressionContext = try container.decodeIfPresent(Int.self, forKey: .progressionContext) ?? 2
        progressionReharm = try container.decodeIfPresent(Reharm.self, forKey: .progressionReharm) ?? .subtle
        progressionModulation = try container.decodeIfPresent(Int.self, forKey: .progressionModulation) ?? 0
        compingFigureName = try container.decodeIfPresent(String.self, forKey: .compingFigureName)
            ?? CompingFigure.charleston.name
        showShape = try container.decodeIfPresent(Bool.self, forKey: .showShape) ?? true
        showFeel = try container.decodeIfPresent(Bool.self, forKey: .showFeel) ?? true
        showHistory = try container.decodeIfPresent(Bool.self, forKey: .showHistory) ?? false
        appearance = try container.decodeIfPresent(MelGenAppearance.self, forKey: .appearance) ?? .light
        autoRegenerate = try container.decodeIfPresent(Bool.self, forKey: .autoRegenerate) ?? false
        regenerateEveryPasses = try container.decodeIfPresent(Int.self, forKey: .regenerateEveryPasses) ?? 1
        briefCursor = try container.decodeIfPresent(Int.self, forKey: .briefCursor) ?? 0
        patternCursor = try container.decodeIfPresent(Int.self, forKey: .patternCursor) ?? 0
        selectedBriefNames = try container.decodeIfPresent([String].self, forKey: .selectedBriefNames) ?? []
        briefMode = try container.decodeIfPresent(SelectionMode.self, forKey: .briefMode) ?? .cycle
        lockedBriefName = try container.decodeIfPresent(String.self, forKey: .lockedBriefName)
        lineMode = try container.decodeIfPresent(SelectionMode.self, forKey: .lineMode) ?? .cycle
        lockedLineName = try container.decodeIfPresent(String.self, forKey: .lockedLineName)
        learnedDraw = try container.decodeIfPresent(LearnedDraw.self, forKey: .learnedDraw) ?? .chain
        history = try container.decodeIfPresent([GenerationRecord].self, forKey: .history) ?? []
        currentTakeID = try container.decodeIfPresent(UUID.self, forKey: .currentTakeID)
        curationPass = try container.decodeIfPresent(Int.self, forKey: .curationPass) ?? 1
        tagVocabulary = try container.decodeIfPresent(TagVocabulary.self, forKey: .tagVocabulary) ?? TagVocabulary()
    }

    var currentTake: GenerationRecord? {
        guard let currentTakeID else { return history.first }
        return history.first { $0.id == currentTakeID } ?? history.first
    }

    /// The notes that should be playing, with expression applied.
    var renderedMelody: [SequencedNote] {
        guard let take = currentTake else { return [] }
        let polyphonic = take.source == .comping

        // Expression first, drift second — and getting this the wrong way round
        // is a real bug rather than a preference. Expression's gate pass clips
        // every note to the next one's start, which is exactly what a slide must
        // not be; drifting first meant every slide was closed again before it
        // reached the kernel. Expression is the realization of the take, and the
        // drift is a performance of that realization, so it goes last.
        let rendered = MelodyExpression.apply(
            to: take.notes,
            settings: expression,
            generatedDensity: take.density,
            lengthBeats: take.lengthBeats,
            seed: take.id.uuidStableSeed,
            // Judged by the take, not by the mode: a comping take stays
            // polyphonic when the mode is switched back, and a line stays a line.
            polyphonic: polyphonic
        )

        guard liveMutation.isActive else { return rendered }
        return MelodyLiveMutations.apply(
            to: rendered,
            settings: liveMutation,
            lengthBeats: take.lengthBeats,
            polyphonic: polyphonic,
            seed: take.id.uuidStableSeed &+ UInt64(bitPattern: Int64(mutationPass &* 0x9E3779B9))
        )
    }

    mutating func add(_ record: GenerationRecord) {
        history.insert(record, at: 0)
        evict()
        previousTakeID = currentTakeID
        currentTakeID = record.id
    }

    /// Drops the oldest take the ring is allowed to drop.
    ///
    /// "Allowed" is the whole rule: anything you marked survives, including
    /// things you set aside for a later pass, because setting something aside is
    /// a promise to come back to it and a ring that quietly ate it would break
    /// that promise. Only a plain skip, or a take nobody has heard yet, is
    /// eligible — and past the ceiling, everything is, oldest first.
    private mutating func evict() {
        while history.count > Self.historyLimit {
            guard let index = history.lastIndex(where: { !$0.survivesEviction && $0.id != currentTakeID })
            else { break }
            history.remove(at: index)
        }
        while history.count > Self.historyCeiling {
            guard let index = history.lastIndex(where: { $0.id != currentTakeID }) else { break }
            history.remove(at: index)
        }
    }
}

// MARK: - Curation

extension MelGenState {

    /// Records a judgement about a take, on the current pass.
    ///
    /// Appends rather than replaces: a take judged on pass 1 and again on pass 3
    /// keeps both answers. Re-marking on the *same* pass does replace, because
    /// that's a correction rather than a second opinion.
    mutating func mark(_ takeID: UUID,
                       as disposition: TakeDisposition,
                       aspects: [TakeAspect] = [],
                       note: String = "",
                       now: Date = Date()) {
        guard let index = history.firstIndex(where: { $0.id == takeID }) else { return }
        history[index].marks.removeAll { $0.pass == curationPass }
        history[index].marks.append(CurationMark(
            disposition: disposition,
            pass: curationPass,
            date: now,
            aspects: aspects,
            heardAfter: takeID == currentTakeID ? previousTakeID : currentTakeID,
            note: note
        ))
    }

    /// Takes back what was said about a take on this pass, leaving earlier passes
    /// alone. Un-judging is a normal thing to want.
    mutating func unmark(_ takeID: UUID) {
        guard let index = history.firstIndex(where: { $0.id == takeID }) else { return }
        history[index].marks.removeAll { $0.pass == curationPass }
    }

    /// The brief for the next take, honouring the selection and the mode.
    var nextBrief: StyleBrief {
        StyleBriefs.brief(at: briefCursor,
                          selected: selectedBriefNames,
                          mode: briefMode,
                          locked: lockedBriefName)
    }

    /// The stored line for the next instant take, from whichever library is in play.
    func nextLine(from library: [MelodyPattern]) -> MelodyPattern {
        MelodyPatterns.line(at: patternCursor,
                            from: library,
                            mode: lineMode,
                            locked: lockedLineName)
    }

    /// Loads a take, remembering what it displaced.
    mutating func select(_ takeID: UUID) {
        guard takeID != currentTakeID else { return }
        previousTakeID = currentTakeID
        currentTakeID = takeID
    }

    mutating func setTags(_ tags: [String], for takeID: UUID) {
        guard let index = history.firstIndex(where: { $0.id == takeID }) else { return }
        let normalized = tags
            .map(TagVocabulary.normalize)
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let unique = normalized.filter { seen.insert($0).inserted }
        tagVocabulary.forget(history[index].tags)
        tagVocabulary.record(unique)
        history[index].tags = unique
    }

    mutating func retitle(_ takeID: UUID, to title: String) {
        guard let index = history.firstIndex(where: { $0.id == takeID }) else { return }
        history[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Opens the next sweep. Everything becomes reviewable again — that's the
    /// point of a pass rather than a verdict.
    mutating func beginNextPass() {
        curationPass += 1
    }

    /// What's up for review, in the order it's worth hearing.
    ///
    /// Things you explicitly deferred come first, because deferring is a promise.
    /// Then what you haven't heard. Then, last but present, what you skipped —
    /// a second pass over the discards is where the surprises are. Anything
    /// already answered *on this pass* sinks to the bottom.
    var reviewQueue: [GenerationRecord] {
        history
            .map { take -> (take: GenerationRecord, answered: Bool, priority: Int, date: Date) in
                let thisPass = take.mark(onPass: curationPass)
                let priority = take.latestMark?.disposition.reviewPriority
                    ?? TakeDisposition.unmarkedPriority
                return (take, thisPass != nil, priority, take.date)
            }
            .sorted { left, right in
                if left.answered != right.answered { return !left.answered }
                if left.priority != right.priority { return left.priority < right.priority }
                return left.date > right.date
            }
            .map(\.take)
    }

    /// How much of this pass is done, for a progress read-out that means something.
    var reviewProgress: (answered: Int, total: Int) {
        let answered = history.filter { $0.mark(onPass: curationPass) != nil }.count
        return (answered, history.count)
    }

    /// Every take carrying a given disposition as its latest word.
    func takes(dispositioned disposition: TakeDisposition) -> [GenerationRecord] {
        history.filter { $0.latestMark?.disposition == disposition }
    }

    /// The material worth learning from: what you kept, plus what you said had a
    /// version that works. Deliberately not everything marked — a library that
    /// includes what you set aside teaches the model to write what you set aside.
    var curatedTakes: [GenerationRecord] {
        history.filter { take in
            guard let disposition = take.latestMark?.disposition else { return false }
            return disposition == .keep || disposition == .tweak || disposition == .partial
        }
    }
}

/// The take history in a form that can leave the plug-in.
///
/// Carries the settings each take was generated with *and* how long it took, so
/// a run of takes is a usable record of how the model behaves — which is the
/// only way to reason about generation time without guessing.
struct MelGenHistoryExport: Codable, Sendable {
    var exportedAt: Date
    var takeCount: Int
    /// The realization settings in force at export, since the stored notes are
    /// pre-expression and won't sound like what was heard without them.
    var expressionAtExport: ExpressionSettings
    var takes: [GenerationRecord]
}

extension MelGenState {
    func historyExport() -> MelGenHistoryExport {
        MelGenHistoryExport(
            exportedAt: Date(),
            takeCount: history.count,
            expressionAtExport: expression,
            takes: history
        )
    }

    func historyExportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(historyExport())
    }

    /// The counterpart to `historyExportData()`. Paired with it deliberately: the
    /// export writes ISO-8601 dates so the file is readable by anything, and a
    /// default `JSONDecoder` would fail on it — that shouldn't be something the
    /// next reader has to rediscover.
    static func decodeHistoryExport(_ data: Data) throws -> MelGenHistoryExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MelGenHistoryExport.self, from: data)
    }

    /// A filename that sorts, reads well in Files, and — because exporting twice
    /// in a day is normal — doesn't collide with the last one.
    func historyExportFilename(now: Date = Date()) -> String {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = .current
        stamp.dateFormat = "yyyy-MM-dd-HHmmss"
        return "MelGen-history-\(stamp.string(from: now)).json"
    }
}

extension UUID {
    /// A stable seed, so a take's expression renders identically every session
    /// (UUID's own hashValue is salted per process).
    var uuidStableSeed: UInt64 {
        withUnsafeBytes(of: uuid) { bytes in
            var seed: UInt64 = 0xcbf29ce484222325
            for byte in bytes {
                seed = (seed ^ UInt64(byte)) &* 0x100000001b3
            }
            return seed
        }
    }
}
