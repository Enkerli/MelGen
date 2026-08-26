//
//  MelodyCuration.swift
//  MelGenExtension
//
//  Curation, on the assumption that judgement is provisional.
//
//  The obvious design is a rating: thumbs up, thumbs down, five stars. It is
//  also wrong for this, in three ways.
//
//  *It ranks things that aren't comparable.* "Good for now", "there's a version
//  of this that works", "the rhythm is great and the rest is so-so" and "right
//  idea, wrong take" are not four points on one axis. They are four different
//  next actions. So a mark here is a **disposition**, not a score, and the
//  dispositions are deliberately unranked against each other.
//
//  *It pretends judgement is final.* It isn't. Hearing something right after
//  something else makes it dull; hearing it two days later makes it the thing
//  you needed. So every mark records the **pass** it was made on and the take it
//  was heard after, a take keeps all its marks rather than the latest one, and
//  nothing is ever removed from consideration — "skip" means "not this pass".
//  A take marked `pass` on the first sweep and `keep` on the third isn't a
//  correction. The disagreement is the most interesting thing in the record.
//
//  *It's the wrong vocabulary shape.* Two vocabularies are needed, not one.
//  Facets are structural, derived and fixed — density, register, syncopation,
//  chromaticism — and they're how you find something on purpose. Tags are typed,
//  free and emergent, and they're how a vocabulary you didn't know you needed
//  shows up. Neither substitutes for the other, and the interesting move is the
//  ratchet between them: a tag you keep reaching for is a facet waiting to be
//  named.
//
//  Deliberately free of any FoundationModels dependency: it's arithmetic and
//  bookkeeping.
//

import Foundation

// MARK: - Dispositions

/// What you want to happen to this take next.
///
/// Not a scale. Each case is a different next action, and none of them is
/// terminal — the whole point is that the same take gets asked again later, in
/// another context, and is allowed to answer differently.
enum TakeDisposition: String, Codable, CaseIterable, Sendable {
    /// Good for now. Not "good forever", and not a ranking against `tweak`.
    case keep
    /// There's a version of this that works. The material is right, the settings
    /// aren't.
    case tweak
    /// Right idea, wrong take — worth generating again from the same brief.
    case again
    /// Right thing, wrong moment. Belongs somewhere; not here.
    case context
    /// Part of it works. Which part is a separate question — see `TakeAspect`.
    case partial
    /// Set aside for a further pass, deliberately undecided.
    case later
    /// Skip — this pass. Still comes back around, just last.
    case skip

    /// The ones a fast sweep needs, in the order a sweep uses them.
    ///
    /// Seven equal buttons is the right *model* and the wrong *default*: it
    /// makes an ordinary yes/no/not-yet decision cost a scan of seven labels.
    /// These three answer most takes; the rest are there when one of them
    /// doesn't fit, behind a disclosure. Still not a scale — `keep` and `tweak`
    /// are different actions, not better and worse.
    static let primary: [TakeDisposition] = [.keep, .tweak, .skip]

    var isPrimary: Bool { Self.primary.contains(self) }

    /// A single key, so a sweep is a keystroke per take rather than a menu.
    var shortcut: Character {
        switch self {
        case .keep: return "k"
        case .tweak: return "t"
        case .again: return "a"
        case .context: return "c"
        case .partial: return "p"
        case .later: return "l"
        case .skip: return "s"
        }
    }

    var label: String {
        switch self {
        case .keep: return "Good for now"
        case .tweak: return "Affords tweaks"
        case .again: return "Worth another try"
        case .context: return "Right elsewhere"
        case .partial: return "Part of it works"
        case .later: return "Second pass"
        case .skip: return "Skip for now"
        }
    }

    /// Short enough for a chip.
    var chipLabel: String {
        switch self {
        case .keep: return "Keep"
        case .tweak: return "Tweak"
        case .again: return "Again"
        case .context: return "Elsewhere"
        case .partial: return "Partly"
        case .later: return "Later"
        case .skip: return "Skip"
        }
    }

    var symbolName: String {
        switch self {
        case .keep: return "checkmark.circle"
        case .tweak: return "slider.horizontal.3"
        case .again: return "arrow.clockwise"
        case .context: return "arrow.turn.up.right"
        case .partial: return "circle.lefthalf.filled"
        case .later: return "clock"
        case .skip: return "arrow.right.to.line"
        }
    }

    /// Whether a take carrying this mark survives the history ring.
    ///
    /// Everything except a plain skip does. The asymmetry is deliberate: it costs
    /// almost nothing to keep a take around, and there is no way to get one back
    /// once the ring has dropped it.
    var protectsFromEviction: Bool { self != .skip }

    /// Where this sits in the next pass's queue. Lower is sooner.
    ///
    /// The order is the argument: things you explicitly deferred come first,
    /// because deferring is a promise to come back. Then what you haven't heard.
    /// Then what you skipped — last, but present, because a second pass over the
    /// discards is where the surprises are.
    var reviewPriority: Int {
        switch self {
        case .later: return 0
        case .again: return 1
        case .context: return 2
        case .partial: return 3
        case .tweak: return 5
        case .keep: return 6
        case .skip: return 7
        }
    }

    /// The priority of a take nobody has marked yet — between "deferred" and
    /// "already settled".
    static let unmarkedPriority = 4
}

// MARK: - The coarse layer

/// The coarse answer most takes get, as a shortcut to three of the seven.
///
/// Not a scale and not a score: the three cases are the three dispositions a
/// sweep reaches for, named the way a listener names them. The seven stay
/// reachable, and a mark made from one of the other four is displayed as
/// itself — never bucketed into a rating it didn't come from.
///
/// This exists only at the point of *input*. Nothing downstream knows about it:
/// a rating writes exactly the mark its disposition writes, so eviction, the
/// review queue and everything learned from the record are untouched.
enum TakeRating: String, Codable, CaseIterable, Sendable {
    case no, maybe, yes

    var disposition: TakeDisposition {
        switch self {
        case .yes: return .keep
        case .maybe: return .later
        case .no: return .skip
        }
    }

    var label: String {
        switch self {
        case .yes: return "Yes"
        case .maybe: return "Maybe"
        case .no: return "No"
        }
    }

    /// What the rating actually does to the take, for the accessibility value —
    /// "Yes" alone doesn't say that nothing is being discarded.
    var consequence: String {
        switch self {
        case .yes: return "keeps this take for now"
        case .maybe: return "sets this take aside for a further pass"
        case .no: return "skips this take for this pass — it comes back last"
        }
    }

    /// The single key, macOS only, alongside the seven that already have one.
    var shortcut: Character {
        switch self {
        case .yes: return "y"
        case .maybe: return "m"
        case .no: return "n"
        }
    }

    var symbolName: String { disposition.symbolName }

    /// Which rating a disposition reads back as, if any.
    ///
    /// The other four are deliberately nil: `tweak`, `again`, `context` and
    /// `partial` are not coarser versions of anything, and showing them as one
    /// of these three would be the collapse this design refuses.
    static func of(_ disposition: TakeDisposition) -> TakeRating? {
        switch disposition {
        case .keep: return .yes
        case .later: return .maybe
        case .skip: return .no
        default: return nil
        }
    }
}

/// Which way the listener is aiming the next take.
///
/// The aim is the feature. An advance that can't say what it will do is a
/// shuffle with extra steps, which is what the sweep had before.
enum AdvanceMode: String, Codable, CaseIterable, Sendable {
    /// Same setup, rolled again — a variant of the current take when there is
    /// one, otherwise the same source and template with a fresh seed.
    case anotherLikeThis
    /// Advance the setup: the rotation moves on, so the next take is a
    /// different template.
    case somethingElse

    var label: String {
        self == .anotherLikeThis ? "Another like this" : "Something else"
    }

    var symbolName: String {
        self == .anotherLikeThis ? "arrow.trianglehead.2.clockwise" : "arrow.turn.up.right"
    }

    /// The two dispositions that are the same wish as "another like this", said
    /// in the seven's own words. Answering either sets the aim without
    /// advancing — saying something specific is not sweeping.
    static func aimed(by disposition: TakeDisposition) -> AdvanceMode? {
        switch disposition {
        case .tweak, .again: return .anotherLikeThis
        default: return nil
        }
    }
}

/// Which part of a take a `partial` mark is about.
///
/// A small controlled vocabulary rather than free text, because these are the
/// aspects the code can actually *act* on: keeping a rhythm and re-deriving the
/// pitches is a transform we can perform, and "cool rhythm, rest is so-so" is
/// the instruction for it.
enum TakeAspect: String, Codable, CaseIterable, Sendable {
    case rhythm, contour, harmony, register, feel, ending

    var label: String {
        switch self {
        case .rhythm: return "Rhythm"
        case .contour: return "Contour"
        case .harmony: return "Harmony"
        case .register: return "Register"
        case .feel: return "Feel"
        case .ending: return "Ending"
        }
    }
}

/// One judgement, made at one moment, in one context.
struct CurationMark: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var disposition: TakeDisposition
    /// Which sweep this was made on. Marks from different passes coexist.
    var pass: Int
    var date: Date = Date()
    /// For `partial`: the parts that work. Empty otherwise.
    var aspects: [TakeAspect] = []
    /// The take that was playing immediately before this one, when there was
    /// one. Judgement is comparative whether or not we admit it, so record what
    /// it was compared against.
    var heardAfter: UUID?
    /// Anything the vocabulary doesn't cover.
    var note: String = ""

    init(disposition: TakeDisposition,
         pass: Int,
         date: Date = Date(),
         aspects: [TakeAspect] = [],
         heardAfter: UUID? = nil,
         note: String = "") {
        self.disposition = disposition
        self.pass = pass
        self.date = date
        self.aspects = aspects
        self.heardAfter = heardAfter
        self.note = note
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        disposition = try container.decodeIfPresent(TakeDisposition.self, forKey: .disposition) ?? .later
        pass = try container.decodeIfPresent(Int.self, forKey: .pass) ?? 1
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        aspects = try container.decodeIfPresent([TakeAspect].self, forKey: .aspects) ?? []
        heardAfter = try container.decodeIfPresent(UUID.self, forKey: .heardAfter)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

// MARK: - Facets

/// The structural half of the vocabulary: derived, fixed, and never typed.
///
/// Every value here is computed from the take and its measurement, so filtering
/// by them costs nothing and can't go stale. This is what "give me the direct
/// result" looks like — sparse, offbeat, chromatic, over these changes.
struct TakeFacets: Codable, Hashable, Sendable {
    enum Density: String, Codable, CaseIterable, Sendable {
        case sparse, steady, busy, dense
    }
    enum Placement: String, Codable, CaseIterable, Sendable {
        case onBeat, mixed, offBeat
    }
    enum Register: String, Codable, CaseIterable, Sendable {
        case low, middle, high, wide
    }
    enum Colour: String, Codable, CaseIterable, Sendable {
        case diatonic, touched, chromatic
    }
    enum Motion: String, Codable, CaseIterable, Sendable {
        case ostinato, repetitive, varied, restless
    }

    var density: Density
    var placement: Placement
    var register: Register
    var colour: Colour
    var motion: Motion
    var bars: Int
    var source: TakeSource

    /// The chips a library row shows, in the order they're worth reading.
    ///
    /// Source comes first and is never elided. Whether a line was composed by
    /// the model or fitted from the library is the single most useful thing to
    /// know about it — it says what it cost, how it got here, and what changing
    /// a setting will do to it — and it was briefly missing from these rows,
    /// which made the whole history unreadable at a glance.
    var chips: [String] {
        [source.label,
         density.rawValue,
         placement == .mixed ? "" : placement.rawValue.lowercasedWords,
         colour == .diatonic ? "" : colour.rawValue,
         motion.rawValue,
         register == .middle ? "" : register.rawValue]
            .filter { !$0.isEmpty }
    }
}

private extension String {
    /// "onBeat" reads badly as a chip; "on-beat" doesn't.
    var lowercasedWords: String {
        var result = ""
        for character in self {
            if character.isUppercase {
                result += "-" + character.lowercased()
            } else {
                result.append(character)
            }
        }
        return result
    }
}

enum TakeFacetting {

    static func facets(for notes: [SequencedNote],
                       lengthBeats: Double,
                       analysis: MelodyAnalysis?,
                       source: TakeSource,
                       beatsPerBar: Double = 4) -> TakeFacets {
        let bars = max(1, Int(ceil(lengthBeats / beatsPerBar - 0.001)))
        let perBar = Double(notes.count) / Double(bars)

        let density: TakeFacets.Density
        switch perBar {
        case ..<2.5: density = .sparse
        case ..<5: density = .steady
        case ..<7: density = .busy
        default: density = .dense
        }

        let offbeats = notes.filter { note in
            let eighth = Int((note.startBeat * 2).rounded())
            return !eighth.isMultiple(of: 2)
        }.count
        let offbeatShare = notes.isEmpty ? 0 : Double(offbeats) / Double(notes.count)
        let placement: TakeFacets.Placement
        switch offbeatShare {
        case ..<0.15: placement = .onBeat
        case ..<0.45: placement = .mixed
        default: placement = .offBeat
        }

        let pitches = notes.map { Int($0.note) }
        let low = pitches.min() ?? 60
        let high = pitches.max() ?? 60
        let centre = pitches.isEmpty ? 60 : pitches.reduce(0, +) / pitches.count
        let register: TakeFacets.Register
        if high - low > 19 {
            register = .wide
        } else if centre < 57 {
            register = .low
        } else if centre > 72 {
            register = .high
        } else {
            register = .middle
        }

        let offScale = analysis?.offScaleNotes ?? 0
        let colour: TakeFacets.Colour
        switch offScale {
        case 0: colour = .diatonic
        case 1...2: colour = .touched
        default: colour = .chromatic
        }

        let variety = analysis?.varietyScore ?? 0.5
        let motion: TakeFacets.Motion
        switch variety {
        case ..<0.25: motion = .ostinato
        case ..<0.45: motion = .repetitive
        case ..<0.75: motion = .varied
        default: motion = .restless
        }

        return TakeFacets(density: density,
                          placement: placement,
                          register: register,
                          colour: colour,
                          motion: motion,
                          bars: bars,
                          source: source)
    }
}

// MARK: - The emergent half

/// The tags actually in use, with how often — so the interface can offer the
/// vocabulary you have rather than one somebody guessed at.
///
/// This is the folksonomy side, and the ratchet is the point: a tag you keep
/// reaching for is a facet waiting to be named. `promotable` says which ones
/// have earned it.
struct TagVocabulary: Codable, Hashable, Sendable {
    private(set) var counts: [String: Int] = [:]

    init(counts: [String: Int] = [:]) {
        self.counts = counts
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        counts = try container.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
    }

    /// Free text, normalized just enough that "Bossa" and "bossa " are one tag.
    static func normalize(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    mutating func record(_ tags: [String]) {
        for tag in tags.map(Self.normalize) where !tag.isEmpty {
            counts[tag, default: 0] += 1
        }
    }

    mutating func forget(_ tags: [String]) {
        for tag in tags.map(Self.normalize) where !tag.isEmpty {
            guard let count = counts[tag] else { continue }
            if count <= 1 { counts.removeValue(forKey: tag) } else { counts[tag] = count - 1 }
        }
    }

    /// Most used first, then alphabetical so the order is stable to look at.
    var suggestions: [String] {
        counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    /// Tags used often enough to be worth turning into something structural.
    func promotable(threshold: Int = 4) -> [String] {
        suggestions.filter { (counts[$0] ?? 0) >= threshold }
    }
}
