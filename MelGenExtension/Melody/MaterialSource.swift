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
    func verb(mode: PlayMode) -> String {
        switch self {
        case .model:
            switch mode {
            case .comping: return "Generate a comp"
            case .bass: return "Generate a bass part"
            case .line: return "Generate a line"
            }
        case .stored: return "Play a stored line"
        case .composed: return "Compose a phrase"
        case .learned: return "Draw from your style"
        case .played: return "Learn what I play"
        case .comp: return "Comp these changes"
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

    /// Which sources can produce what this mode asks for.
    ///
    /// A melodic source under Chords would be offering something the mode can't
    /// deliver — the whole reason the mode exists is that the receiving
    /// instrument differs.
    static func all(for mode: PlayMode) -> [MaterialSource] {
        switch mode {
        case .comping: return [.comp, .model, .learned]
        // Bass narrows harder than Chords does, and for the same reason. The
        // bassline draw is the only source that knows about a register, and a
        // register is most of what makes a bass part one: the melodic sources
        // would hand back a line in the wrong octave with the right notes in it,
        // which is a lead part played low rather than a bass part. What survives
        // alongside it is your own material, which carries whatever register it
        // was played in, and the model, which is told where to write.
        case .bass: return [.bassline, .learned, .model]
        case .line: return [.model, .stored, .composed, .learned, .played]
        }
    }

    static func first(for mode: PlayMode) -> MaterialSource {
        all(for: mode).first ?? .composed
    }
}
