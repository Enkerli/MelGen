//
//  TakeAdvance.swift
//  MelGenExtension
//
//  The next take, aimed, and never waiting on a model.
//
//  The hard constraint is measured, not assumed: the model runs at about 1.8
//  seconds a note, roughly four times slower than real time. So an advance can
//  never be what a listener waits on, and this file is deliberately free of any
//  FoundationModels dependency — if it can import FoundationModels, that
//  constraint has been broken. A model request is a separate `Task` that swaps
//  in on a lap boundary through the path auto-regeneration already uses.
//
//  The other half is the aim. An advance that can't say what it will do is a
//  shuffle, and a shuffle is what the sweep already had. `anotherLikeThis`
//  prefers a *variant* of what is sounding — fourteen transforms scored against
//  the musician's own material is the closest thing to "the same idea again"
//  that exists here, and unlike the model it is instant. `somethingElse` moves
//  the rotation on, which is the only honest way to promise a different
//  template.
//

import Foundation
import Carrier
import Theory

enum TakeAdvance {

    // MARK: - The candidate

    /// The next take, now.
    ///
    /// Never slower than the deterministic sources it draws on, and non-nil for
    /// every mode and every source whenever the progression parses — which is
    /// what makes it safe to call on the tap rather than after it.
    static func candidate(mode: AdvanceMode,
                          state: MelGenState,
                          source: MaterialSource,
                          progression: ChordProgression) -> GenerationRecord? {
        guard progression.totalBeats > 0 else { return nil }
        switch mode {
        case .sameChanged: return sameChanged(state: state, source: source, over: progression)
        case .anotherLikeThis: return again(state: state, source: source, over: progression)
        case .somethingElse: return elsewhere(state: state, source: source, over: progression)
        }
    }

    /// The same setup at the same seed, so the only difference is whatever the
    /// caller just changed.
    ///
    /// Bass had this and it was written as plumbing — a control release redraws
    /// with the seed held, Draw advances it — which made it look like a rule
    /// about Bass. It is a third aim, it applies to every source whose draw is
    /// deterministic, and giving it a name is what makes a continuous control
    /// teachable rather than mysterious.
    ///
    /// Falls through to `anotherLikeThis` when there is no seed to hold: a take
    /// made before takes recorded one, or no current take at all. Falling
    /// through rather than returning nil, because a verb that sometimes does
    /// nothing is worse than one that sometimes does slightly more.
    private static func sameChanged(state: MelGenState,
                                    source: MaterialSource,
                                    over progression: ChordProgression) -> GenerationRecord? {
        guard let held = state.currentTake?.seed, held != 0 else {
            return again(state: state, source: source, over: progression)
        }
        if state.mode == .bass {
            return bassline(state: state, over: progression,
                            seed: held, settings: state.bassline)
        }
        return rolled(state: state, source: source, template: state.nextTemplate,
                      over: progression, seed: held)
    }

    /// A variant of what is sounding, or the same setup rolled again.
    private static func again(state: MelGenState,
                              source: MaterialSource,
                              over progression: ChordProgression) -> GenerationRecord? {
        // Bass takes never go through the variant path, and the reason is the
        // register. `explore` works on extracted patterns, and an extracted
        // pattern has no octave in it — realizing one back fold by fold puts the
        // line wherever the folding lands rather than inside the range that was
        // set. Redrawing the same settings at a new seed is the honest reading
        // of "another like this" here anyway: the figure and the histograms are
        // the idea, and a draw from them is a take of it.
        if state.mode == .bass {
            return bassline(state: state, over: progression,
                            seed: seed(state, salt: 0x5EED_A11E), settings: state.bassline)
        }

        guard let take = state.currentTake,
              let parent = MelodyPatterns.extract(from: take.notes,
                                                  over: progression,
                                                  name: take.briefName),
              !parent.notes.isEmpty
        else {
            return rolled(state: state, source: source,
                          template: state.nextTemplate, over: progression)
        }

        let style = StyleLearner.learn(from: state.curatedTakes)
        let variants = MelodyVariants.explore(parent,
                                              seed: seed(state, salt: 0x5EED_A11E),
                                              style: style.isEmpty ? nil : style)
        // The nearest one that is still a step: high novelty is "something
        // else" wearing this button's label. And a variant that empties the bar
        // isn't "like this" either, however novel — thinning is one of the
        // fourteen and it can halve a sparse parent into near-silence.
        let floor = max(1, parent.notes.count / 2)
        guard let chosen = variants
            .filter({ $0.novelty > 0.05 && $0.pattern.notes.count >= floor })
            .min(by: { abs($0.novelty - 0.3) < abs($1.novelty - 0.3) })
        else {
            return rolled(state: state, source: source,
                          template: state.nextTemplate, over: progression)
        }

        let notes = realize(chosen.pattern, over: progression, mode: state.mode,
                            leading: state.voiceLeading)
        guard !notes.isEmpty else {
            return rolled(state: state, source: source,
                          template: state.nextTemplate, over: progression)
        }

        var record = record(notes: notes, over: progression, state: state,
                            briefName: take.briefName,
                            seed: seed(state, salt: 0x5EED_A11E), source: .mutated)
        record.parentTakeID = take.id
        record.derivation = chosen.transform
        return record
    }

    /// The rotation moves on, and the take is made from whatever answers now.
    private static func elsewhere(state: MelGenState,
                                  source: MaterialSource,
                                  over progression: ChordProgression) -> GenerationRecord? {
        let template = nextTemplate(after: state)
        return rolled(state: state, source: source, template: template, over: progression)
    }

    /// The same shape both branches fall back to: compose against a template.
    ///
    /// Composing is the fallback rather than the stored lines because it always
    /// answers — a stored line can fail to fit, and a fallback that can fail is
    /// not a fallback.
    private static func rolled(state: MelGenState,
                               source: MaterialSource,
                               template: MelGenTemplate,
                               over progression: ChordProgression,
                               seed rolledSeed: UInt64? = nil) -> GenerationRecord? {
        // In Bass the rotation names a figure, so moving it on means putting a
        // different figure on the pad — which is exactly what "something
        // else" should mean in a mode whose character lives there.
        if state.mode == .bass {
            let settings = template.basslineFigure.map(state.bassline.placing) ?? state.bassline
            return bassline(state: state, over: progression,
                            seed: seed(state, salt: 0xBA55), settings: settings)
        }

        let style = StyleLearner.learn(from: state.curatedTakes)
        let bars = max(2, Int(ceil(progression.totalBeats / 4)))
        let composeSeed = rolledSeed ?? seed(state, salt: 0xC0FFEE)
        let pattern = MelodyPhrases.compose(bars: min(bars, 8),
                                            seed: composeSeed,
                                            style: style.isEmpty ? nil : style,
                                            preferring: template.gestureRhythms,
                                            contours: template.gestureContours,
                                            density: template.density,
                                            restiness: template.restiness,
                                            architecture: template.architecture,
                                            palette: state.durationPalette)
        let notes = realize(pattern, over: progression, mode: state.mode,
                            leading: state.voiceLeading)
        guard !notes.isEmpty else { return nil }
        return record(notes: notes, over: progression, state: state,
                      briefName: template.name, seed: composeSeed,
                      // A composed take under Chords is a comp, and the log
                      // should not call a voiced draw a line.
                      source: state.mode == .comping ? .comping : .composed)
    }

    /// A bass line under the settings given, as a take.
    private static func bassline(state: MelGenState,
                                 over progression: ChordProgression,
                                 seed: UInt64,
                                 settings: BasslineSettings) -> GenerationRecord? {
        let notes = BasslineGenerator.line(settings, over: progression, seed: seed)
        guard !notes.isEmpty else { return nil }
        return record(notes: notes, over: progression, state: state,
                      briefName: settings.leadingFigure.name, seed: seed, source: .bassline)
    }

    // MARK: - What the button says before it is tapped

    /// The subtitle, derivable without producing the take.
    ///
    /// The subtitles are the whole feature: they are what makes an aimed advance
    /// different from a shuffle. Nil means the button should be disabled — a
    /// vague subtitle is worse than a missing one, because it promises an aim
    /// that isn't there.
    static func subtitle(mode: AdvanceMode,
                         state: MelGenState,
                         source: MaterialSource) -> String? {
        switch mode {
        case .sameChanged:
            // Says the promise rather than the outcome, because the outcome is
            // "whatever you just changed" and naming that would be guessing at
            // which control the hand was on.
            let promise = mode.promise(for: source)
            if state.mode == .bass { return "\(state.bassline.leadingFigure.name) · \(promise)" }
            guard let take = state.currentTake else { return nil }
            let name = take.title.isEmpty ? take.briefName : take.title
            guard !name.isEmpty else { return nil }
            return "\(name) · \(promise)"
        case .anotherLikeThis:
            if state.mode == .bass { return "\(state.bassline.leadingFigure.name) · redrawn" }
            guard let take = state.currentTake else { return nil }
            let name = take.title.isEmpty ? take.briefName : take.title
            guard !name.isEmpty else { return nil }
            return state.mode == .comping ? "\(name) · re-voiced" : "\(name) · varied"
        case .somethingElse:
            let name = nextTemplate(after: state).name
            guard !name.isEmpty else { return nil }
            return "next: \(name)"
        }
    }

    /// Whether a model request should be started alongside this advance, and for
    /// what.
    ///
    /// Nil when the model isn't the chosen source, or when the aim is "another
    /// like this" — a variant of what is sounding is already the answer to that
    /// question, and asking a model for one would be paying 1.8 seconds a note
    /// for a worse version of something instant.
    static func backgroundRequest(mode: AdvanceMode,
                                  state: MelGenState,
                                  source: MaterialSource) -> MaterialSource? {
        guard source == .model, mode == .somethingElse else { return nil }
        return .model
    }

    // MARK: - Shared

    /// The template the rotation reaches next, which is what makes
    /// `somethingElse` a promise rather than a hope.
    static func nextTemplate(after state: MelGenState) -> MelGenTemplate {
        MelGenTemplates.template(at: state.briefCursor + 1,
                                 mode: state.mode,
                                 selected: state.selectedBriefNames,
                                 selectionMode: state.briefMode,
                                 locked: state.lockedBriefName)
    }

    private static func realize(_ pattern: MelodyPattern,
                                over progression: ChordProgression,
                                mode: PlayMode,
                                leading: VoiceLeadingMode) -> [SequencedNote] {
        let notes = MelodyPatterns.realize(pattern, over: progression, leading: leading)
        guard mode == .comping, !notes.isEmpty else { return notes }
        let voiced = MelodyComping.revoice(notes, over: progression, as: .rootlessA,
                                           voices: 3, leading: leading)
        return voiced.isEmpty ? notes : voiced
    }

    private static func record(notes: [SequencedNote],
                               over progression: ChordProgression,
                               state: MelGenState,
                               briefName: String,
                               seed: UInt64,
                               source: TakeSource) -> GenerationRecord {
        GenerationRecord(
            progressionText: state.progressionText,
            temperature: state.temperature,
            briefName: briefName,
            density: state.expression.density,
            durationPalette: state.durationPalette,
            seed: seed,
            source: source,
            analysis: MelodyAnalyser.analyse(notes, over: progression),
            lengthBeats: progression.totalBeats,
            notes: notes
        )
    }

    /// Seeded from the cursors and the changes, so a session replays and the
    /// same cursor over different changes isn't the same idea twice.
    private static func seed(_ state: MelGenState, salt: UInt64) -> UInt64 {
        UInt64(bitPattern: Int64(state.patternCursor &* 2_654_435_761))
            ^ UInt64(truncatingIfNeeded: abs(state.progressionText.hashValue))
            ^ UInt64(bitPattern: Int64(state.briefCursor &* 40_503))
            ^ salt
    }
}
