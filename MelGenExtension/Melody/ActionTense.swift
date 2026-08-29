//
//  ActionTense.swift
//  MelGenExtension
//
//  What happens when you press it, of three, and there is no fourth.
//
//  The design pass before this one split controls by *when they take effect* —
//  now, or next take. That was half a grammar, and the missing half is the one
//  the brief was actually about: **making a take is not "next", it is its own
//  act**, with its own cost, its own gesture, and — until this change — no
//  manual control anywhere in the interface. Auto pressed a button that did not
//  exist.
//
//  So every action answers exactly one of three questions:
//
//  · **now** — changes what you are hearing. Free, reversible, audible this lap.
//  · **take** — makes something judgeable. Costs between nothing and two
//    minutes, arrives on a lap boundary, enters the history, can be rated.
//  · **aims** — changes what the next one will be like. Silent until a verb.
//
//  The test, for any control: press it with the transport running and say what
//  happened. *The sound changed* → `now`. *Something arrived that I could rate*
//  → `take`. *Nothing, yet* → `aims`.
//
//  This is a type rather than a convention because the previous pass stated the
//  same distinction as a convention in a comment, and a convention that isn't
//  checkable is one that comes back. ISSUES §6.5 — "changes" retired in a commit
//  message, never written down, back in a dozen strings five days later — is the
//  same lesson arriving from a different direction, and the reason
//  `verify.sh terminology` now scans these labels.
//
//  Deliberately free of SwiftUI, so `verify.sh` can reach it, and of any
//  FoundationModels dependency.
//

import Foundation

/// One of the three tenses every control has exactly one of.
enum ActionTense: String, Codable, CaseIterable, Sendable {
    /// Free, reversible, heard this lap or the next. Never stored, never judged.
    case now
    /// Costs something between nothing and two minutes, arrives on a lap
    /// boundary, enters the history, can be rated.
    case take
    /// Silent until a verb. The setup.
    case aims

    /// The badge text. Uppercased at the point of display, not here — a raw
    /// value that shouts is one that reads badly everywhere except the badge.
    var label: String { rawValue }

    /// Whether the badge is filled.
    ///
    /// Only `now` is. Filled has meant "it happens now" since the 2026-08-23
    /// redesign, and this finishes applying that rule to *settings*, which it
    /// never reached — which is most of why density and gate length looked
    /// identical while behaving nothing alike.
    var isFilled: Bool { self == .now }

    /// One sentence, for a hint or a caption.
    var explanation: String {
        switch self {
        case .now: return "Changes what you are hearing. Free, and nothing is stored."
        case .take: return "Makes something you can rate. It arrives on a lap boundary."
        case .aims: return "Changes what the next one will be like. Silent until a verb."
        }
    }
}

/// The primitive manual gestures. Three, and everything Auto does it does by
/// pressing one of them — which is the whole reason they have to exist first.
///
/// Two of the three had no manual control before this. `nextTake` existed but
/// was labelled by its source ("Draw a bass line", "Comp the progression"), so
/// it read as a feature rather than as the thing Auto presses; `rollAgain` did
/// not exist at all, which meant the one action that changes what you hear for
/// free could only be waited for.
enum Verb: String, Codable, CaseIterable, Sendable {
    /// Re-roll the drift. Free, and the counterpart that was missing.
    case rollAgain
    /// Make a take, aimed by `AdvanceMode`.
    case nextTake
    /// Generate a progression.
    ///
    /// A verb rather than an aim because it *replaces* what everything else is
    /// played against — the only setting that does. Every other aim shapes the
    /// next take; this one changes the ground it stands on.
    case newProgression

    var tense: ActionTense { self == .rollAgain ? .now : .take }

    var label: String {
        switch self {
        case .rollAgain: return "Roll again"
        case .nextTake: return "Next take"
        // "New changes" is the retired noun, quoted in TERMINOLOGY.md as the
        // counterexample it was retired for. `verify.sh terminology` fires on
        // it, which is exactly why this says progression.
        case .newProgression: return "New progression"
        }
    }

    /// What it does, in the words the grammar uses.
    var explanation: String {
        switch self {
        case .rollAgain: return "Re-rolls the drift. Free, and it never touches the take."
        case .nextTake: return "Makes a take, aimed the way the switch beside it says."
        case .newProgression: return "Replaces the progression everything is played against."
        }
    }

    var symbolName: String {
        switch self {
        case .rollAgain: return "dice"
        case .nextTake: return "arrow.forward"
        case .newProgression: return "arrow.triangle.branch"
        }
    }
}

// MARK: - What the machine presses

/// How often the machine presses each verb, in laps. Zero is off.
///
/// This is the whole of Auto. It replaces `autoRegenerate: Bool` plus
/// `regenerateEveryPasses: Int`, which between them could express one of the
/// three verbs at one interval — and which is why Auto read as weather rather
/// than as a machine pressing buttons you could also press yourself.
///
/// It is only writable because the manual verbs exist. A list of what is being
/// pressed for you is unreadable when the things being pressed have no names.
struct AutoVerbs: Codable, Hashable, Sendable {
    var rollAgainEveryLaps: Int = 0
    var nextTakeEveryLaps: Int = 0
    var newProgressionEveryLaps: Int = 0

    var isActive: Bool {
        Verb.allCases.contains { interval(for: $0) > 0 }
    }

    func interval(for verb: Verb) -> Int {
        switch verb {
        case .rollAgain: return rollAgainEveryLaps
        case .nextTake: return nextTakeEveryLaps
        case .newProgression: return newProgressionEveryLaps
        }
    }

    mutating func setInterval(_ laps: Int, for verb: Verb) {
        let laps = max(0, laps)
        switch verb {
        case .rollAgain: rollAgainEveryLaps = laps
        case .nextTake: nextTakeEveryLaps = laps
        case .newProgression: newProgressionEveryLaps = laps
        }
    }

    init(rollAgainEveryLaps: Int = 0,
         nextTakeEveryLaps: Int = 0,
         newProgressionEveryLaps: Int = 0) {
        self.rollAgainEveryLaps = max(0, rollAgainEveryLaps)
        self.nextTakeEveryLaps = max(0, nextTakeEveryLaps)
        self.newProgressionEveryLaps = max(0, newProgressionEveryLaps)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rollAgainEveryLaps: try container.decodeIfPresent(Int.self, forKey: .rollAgainEveryLaps) ?? 0,
            nextTakeEveryLaps: try container.decodeIfPresent(Int.self, forKey: .nextTakeEveryLaps) ?? 0,
            newProgressionEveryLaps: try container.decodeIfPresent(Int.self, forKey: .newProgressionEveryLaps) ?? 0)
    }

    /// What it does, in one phrase, zeros omitted.
    var summary: String {
        let parts = Verb.allCases
            .filter { interval(for: $0) > 0 }
            .map { "\($0.label.lowercased()) \(interval(for: $0))" }
        return parts.isEmpty ? "off" : parts.joined(separator: ", ")
    }
}

extension AutoVerbs {

    /// The keys this shape has ever been written under.
    ///
    /// The two legacy ones are not properties any more, so they are not in the
    /// synthesized `CodingKeys` of anything — which is exactly why the migration
    /// needs its own container rather than a default on a field that no longer
    /// exists.
    private enum MigrationKeys: String, CodingKey {
        case autoVerbs
        case autoRegenerate
        case regenerateEveryPasses
    }

    /// Reads the new shape, or migrates the two fields it replaced.
    ///
    /// Lossless, and it has to be: three saved setups exist on the user's device
    /// and a session that decodes with Auto silently off is a session that
    /// stopped doing what it was doing. `autoRegenerate == true` becomes
    /// `nextTakeEveryLaps`; false becomes zero.
    ///
    /// `rollAgainEveryLaps` migrates to **1** whenever there is a legacy shape at
    /// all, because the drift used to re-roll on its own and this is the setting
    /// that now says so. Anyone who had drift running keeps hearing it; anyone
    /// who had it at zero hears nothing either way, since a roll of a drift that
    /// does nothing does nothing.
    static func decode(from decoder: any Decoder) -> AutoVerbs {
        guard let container = try? decoder.container(keyedBy: MigrationKeys.self) else {
            return AutoVerbs()
        }
        if let current = try? container.decodeIfPresent(AutoVerbs.self, forKey: .autoVerbs) {
            return current
        }
        // `decode` rather than `decodeIfPresent`, so an absent key is nil and a
        // present one is a value — which is the difference between a session
        // written before this shape existed and one written after it.
        let wasOn = try? container.decode(Bool.self, forKey: .autoRegenerate)
        let interval = try? container.decode(Int.self, forKey: .regenerateEveryPasses)
        guard wasOn != nil || interval != nil else { return AutoVerbs() }
        return AutoVerbs(rollAgainEveryLaps: 1,
                         nextTakeEveryLaps: (wasOn ?? false) ? max(1, interval ?? 1) : 0)
    }
}
