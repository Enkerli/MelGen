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
    /// A stored generic line fitted to this progression — instant, no model.
    case pattern

    var label: String {
        switch self {
        case .model: return "model"
        case .pattern: return "line"
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
    var lengthBeats: Double
    var notes: [SequencedNote]

    var noteCount: Int { notes.count }

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
    static let historyLimit = 24

    var progressionText: String = "E♭7 Gm9|D∆|A♭6"
    var temperature: Double = 0.6
    var durationPalette: DurationPalette = .mixed
    var expression = ExpressionSettings()

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

    /// Newest first. The take at `currentTakeID` is the one loaded in the kernel.
    var history: [GenerationRecord] = []
    var currentTakeID: UUID?

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        progressionText = try container.decodeIfPresent(String.self, forKey: .progressionText) ?? "E♭7 Gm9|D∆|A♭6"
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.6
        durationPalette = try container.decodeIfPresent(DurationPalette.self, forKey: .durationPalette) ?? .mixed
        expression = try container.decodeIfPresent(ExpressionSettings.self, forKey: .expression) ?? ExpressionSettings()
        showShape = try container.decodeIfPresent(Bool.self, forKey: .showShape) ?? true
        showFeel = try container.decodeIfPresent(Bool.self, forKey: .showFeel) ?? true
        showHistory = try container.decodeIfPresent(Bool.self, forKey: .showHistory) ?? false
        appearance = try container.decodeIfPresent(MelGenAppearance.self, forKey: .appearance) ?? .light
        autoRegenerate = try container.decodeIfPresent(Bool.self, forKey: .autoRegenerate) ?? false
        regenerateEveryPasses = try container.decodeIfPresent(Int.self, forKey: .regenerateEveryPasses) ?? 1
        briefCursor = try container.decodeIfPresent(Int.self, forKey: .briefCursor) ?? 0
        patternCursor = try container.decodeIfPresent(Int.self, forKey: .patternCursor) ?? 0
        history = try container.decodeIfPresent([GenerationRecord].self, forKey: .history) ?? []
        currentTakeID = try container.decodeIfPresent(UUID.self, forKey: .currentTakeID)
    }

    var currentTake: GenerationRecord? {
        guard let currentTakeID else { return history.first }
        return history.first { $0.id == currentTakeID } ?? history.first
    }

    /// The notes that should be playing, with expression applied.
    var renderedMelody: [SequencedNote] {
        guard let take = currentTake else { return [] }
        return MelodyExpression.apply(
            to: take.notes,
            settings: expression,
            generatedDensity: take.density,
            lengthBeats: take.lengthBeats,
            seed: take.id.uuidStableSeed
        )
    }

    mutating func add(_ record: GenerationRecord) {
        history.insert(record, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        currentTakeID = record.id
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
