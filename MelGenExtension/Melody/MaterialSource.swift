//
//  MaterialSource.swift
//  MelGenExtension
//
//  The six ways to get material, as one list with the two facts that matter.
//
//  From the redesign's second rule: *cost is the axis*. Thirteen buttons had
//  accumulated across three sections, organised by the order they were built in,
//  and what a person actually chooses between is where the material comes from
//  and whether it answers now or in about half a minute. Neither was written
//  anywhere. Both are properties of the source, so they live on it.
//
//  The list is filtered by mode rather than duplicated, which is the fourth
//  rule: choosing Chords has to change what the sources *are*, not just what one
//  button does. Three of the six can produce a voicing; the rest are melodic by
//  construction, and offering them under Chords would be offering something the
//  mode can't deliver.
//
//  That filter used to live here, as `all(for: PlayMode)`, which made a carrier
//  type name a MelGen mode — PORTING.md's `MaterialSource → PlayMode` seam. It
//  is now `PlayMode.sources`, beside the mode it is about. A sibling plug-in
//  gets the list and supplies its own answer to "which of these can I use",
//  which is the only part that was ever MelGen's.
//

import Foundation

/// Where a take's material comes from.
enum MaterialSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case model, stored, composed, learned, played, comp, bassline

    var id: String { rawValue }

    var name: String {
        switch self {
        case .model: return "Model"
        case .stored: return "Stored line"
        case .composed: return "Composed"
        case .learned: return "Your material"
        case .played: return "What you play"
        case .comp: return "Comp"
        case .bassline: return "Bassline"
        }
    }

    /// Whose vocabulary this is. The thing that actually distinguishes them, and
    /// the thing none of the old buttons said.
    var provenance: String {
        switch self {
        case .model: return "a language model"
        case .stored: return "somebody else's"
        case .composed: return "a phrase grammar"
        case .learned: return "takes you kept"
        case .played: return "your own playing"
        case .comp: return "a voicing policy"
        case .bassline: return "two histograms and a figure"
        }
    }

    /// What it costs to ask. Measured, not estimated: the model runs at about
    /// 1.8 seconds a note across every session that has been exported.
    var cost: String {
        self == .model ? "~1.8s a note" : "instant"
    }

    var isInstant: Bool { self != .model }

    /// What the button will do, named as the action rather than as the feature.
    ///
    /// Only the model's verb depends on what the plug-in is producing, and what
    /// it is producing is a MelGen distinction — so the caller names the
    /// material and the carrier never learns that `PlayMode` exists. The naming
    /// of the object lives beside the mode, in `PlayMode.material`.
    func verb(generating material: String) -> String {
        switch self {
        case .model: return "Generate \(material)"
        case .stored: return "Play a stored line"
        case .composed: return "Compose a phrase"
        case .learned: return "Draw from your style"
        case .played: return "Learn what I play"
        case .comp: return "Comp the progression"
        case .bassline: return "Draw a bass line"
        }
    }

    var symbolName: String {
        switch self {
        case .model: return "wand.and.stars"
        case .stored: return "bolt.fill"
        case .composed: return "circle.hexagongrid"
        case .learned: return "waveform.path.ecg"
        case .played: return "waveform.circle"
        case .comp: return "pianokeys"
        case .bassline: return "waveform.path"
        }
    }
}

/// Where a take's notes came from — the same question `MaterialSource` answers
/// for a button, answered after the fact for a take that already exists.
///
/// It lived in MelGenState.swift, which made it session state. It isn't: it is
/// stamped into `PatternOrigin`, so it travels inside every pattern this
/// plug-in exports and every `.mid` it writes. That makes it part of the
/// interchange format rather than part of one plug-in's session, and it is why
/// both the pattern format and curation were reaching up into the session to
/// read it. Moved here as part of PORTING.md's carrier layer.
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
    /// A bass part, drawn from a degree histogram and a transition histogram
    /// through a rhythmic figure. Instant, and the only source that decides a
    /// register rather than inheriting one.
    case bassline

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
        case .bassline: return "bass"
        }
    }
}
