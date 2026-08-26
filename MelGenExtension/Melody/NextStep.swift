//
//  NextStep.swift
//  MelGenExtension
//
//  One line that says what to do now, and a control that goes there.
//
//  Written 2026-08-26, after a device session where the flow was still
//  described as inscrutable despite two design passes. The three places it
//  fails are worth naming, because they have one shape:
//
//  - **The setup drawer** sits above everything, collapsed, saying "none saved".
//    Nothing on screen says why you would want one, and the moment you would —
//    after half an hour of tuning — is exactly when you are not looking at a
//    collapsed row at the top.
//  - **"Your material"** is a drawer too, so the learned models are invisible
//    until you already know they exist. The readout is the feedback that tells
//    you whether keeping takes is *doing* anything.
//  - **Making and judging are on the same tab.** Decide holds the progression,
//    the source and the template, which are how options are *created* (ISSUES
//    §4.1). Moving them is a real design decision and this is not it.
//
//  The common shape is that the interface is arranged by *what things are* and a
//  session is lived in order of *when they matter*. Rearranging by time would
//  break the first arrangement without fixing the second — a control belongs to
//  one group and matters at several moments.
//
//  So: leave the arrangement alone and add the missing axis as one line. It is
//  deliberately not a tour, not a tooltip and not a checklist. Three rules:
//
//  1. **It is derived, never scripted.** Every step is a fact about the current
//     state. Nothing counts sessions, remembers what you were shown, or advances
//     because time passed — which is what makes it right after a reopened
//     session, and what keeps it from lying.
//  2. **It says why, not just what.** "Save this as a setup" is an instruction;
//     "you have changed nine settings since the last take you kept" is a reason.
//     The reason is the part that teaches.
//  3. **Silence is an answer.** When nothing is worth saying it says nothing.
//     A line that is always there is furniture, and furniture is not read.
//
//  Deliberately free of any FoundationModels dependency, and free of SwiftUI, so
//  the ladder is checked by `Scripts/verify.sh nextstep` rather than by eye.
//

import Foundation

/// Where a step points.
///
/// The view owns what "going there" means — which tab, which drawer — because
/// that is layout, and layout is the thing most likely to change. This names the
/// place, not the route, which is also what keeps this file compilable by
/// `verify.sh` without dragging SwiftUI in behind it.
enum StepDestination: String, Codable, Sendable, CaseIterable {
    case progression, source, rating, material, pass, setups, storedLines
}

/// What to do now, and why now.
struct NextStep: Hashable, Sendable {
    /// The action, in the imperative, matching the control it points at.
    let title: String
    /// The fact that makes it the next thing. Not encouragement.
    let reason: String
    let destination: StepDestination
}

/// Everything the ladder needs that doesn't live on `MelGenState`.
///
/// Passed in rather than read from `SetupStore` and `PatternStore` directly:
/// both are `UserDefaults`-backed statics, and a rung that reaches into one is a
/// rung that can't be tested without writing to the running user's defaults.
struct StepContext: Sendable {
    var source: MaterialSource
    var hasSavedSetup: Bool
    var hasStoredLineOfYourOwn: Bool
    var hasCapturedPlaying: Bool
    var modelIsAvailable: Bool

    init(source: MaterialSource,
         hasSavedSetup: Bool = false,
         hasStoredLineOfYourOwn: Bool = false,
         hasCapturedPlaying: Bool = false,
         modelIsAvailable: Bool = true) {
        self.source = source
        self.hasSavedSetup = hasSavedSetup
        self.hasStoredLineOfYourOwn = hasStoredLineOfYourOwn
        self.hasCapturedPlaying = hasCapturedPlaying
        self.modelIsAvailable = modelIsAvailable
    }
}

enum NextSteps {

    /// Takes before the learned models are worth a draw.
    ///
    /// Not a guess: below this the chain's own trust threshold refuses most
    /// contexts, so pointing someone at "your material" earlier would be
    /// pointing them at a source that answers with almost nothing.
    static let materialThreshold = 6

    /// Unanswered takes before a sweep is worth naming as a thing to do.
    static let sweepThreshold = 4

    /// The one thing worth doing now, or nothing.
    ///
    /// First match wins, and the order is the argument: a rung is above another
    /// when the one below is *unreachable* until it is done, not when it seems
    /// more important. Everything is blocked on there being changes; nothing can
    /// be judged before something has been made.
    static func step(for state: MelGenState, context: StepContext) -> NextStep? {
        let hasChanges = (try? ChordProgression.parse(state.progressionText)) != nil

        // Nothing at all works without changes — every source plays against them.
        if !hasChanges {
            return NextStep(
                title: "Set the changes",
                reason: state.progressionText.isEmpty
                    ? "Every source plays against a progression, so nothing can be made yet."
                    : "Those changes don't parse, so nothing can be made against them.",
                destination: .progression)
        }

        if state.history.isEmpty {
            return NextStep(
                title: "Make the first take",
                reason: context.source == .model && context.modelIsAvailable
                    ? "The model takes about 1.8 seconds a note. Something instant plays "
                      + "meanwhile, so the bar is never empty."
                    : "\(context.source.name) answers instantly — nothing to wait for.",
                destination: .source)
        }

        // Something is sounding and nobody has said anything about it. This is
        // the rung that matters most often, and the one the interface used to
        // make hardest: judging was seven equal buttons behind a scan.
        if let take = state.currentTake, take.mark(onPass: state.curationPass) == nil {
            return NextStep(
                title: "Rate what you are hearing",
                reason: "Yes, Maybe or No — or swipe the roll. Nothing is discarded: "
                    + "No means not this pass.",
                destination: .rating)
        }

        let progress = state.reviewProgress
        let kept = state.curatedTakes.count

        // A backlog is the sweep not being done, which is blocking in the same
        // way an unrated current take is.
        if progress.total >= sweepThreshold, progress.total - progress.answered >= sweepThreshold {
            return NextStep(
                title: "Sweep the ones you haven't answered",
                reason: "\(progress.total - progress.answered) of \(progress.total) takes have "
                    + "no answer for pass \(state.curationPass).",
                destination: .pass)
        }

        // The three below are *missing capability* rather than missing work, and
        // they sit above "start the next pass" on purpose. Going round again is
        // always available; a diligent rater who is offered it every time never
        // finds out the other three exist. That ordering was wrong on the first
        // pass of this file and the suite caught it.

        // The drawer problem, first half. The learned models are the feedback
        // that says whether keeping takes is doing anything, and they are behind
        // a collapsed section nobody has been given a reason to open.
        if kept >= materialThreshold, context.source != .learned {
            return NextStep(
                title: "Draw from your own material",
                reason: "\(kept) kept takes is enough for the chain and the slot statistics "
                    + "to be worth a draw. Your material shows what they learned.",
                destination: .material)
        }

        // The drawer problem, second half — and the moment it matters. A setup
        // is worth saving once there is a session's worth of tuning behind it,
        // which is precisely when nobody is looking at a collapsed row above
        // everything else.
        if !context.hasSavedSetup, state.history.count >= materialThreshold {
            return NextStep(
                title: "Save this as a setup",
                reason: "\(state.history.count) takes in, the settings that got you here are "
                    + "worth a name — and one of them can be how a new instance starts.",
                destination: .setups)
        }

        // A kept take is a judgement; a stored line is material. The step
        // between them is one tap that nothing on screen asks for.
        if kept >= 1, !context.hasStoredLineOfYourOwn {
            return NextStep(
                title: "Keep one as a stored line",
                reason: "A kept take is still tied to these changes. As a line it is scale "
                    + "degrees, and plays over any others instantly.",
                destination: .storedLines)
        }

        // A sweep is finished. Saying so is the only thing that makes passes
        // legible as passes rather than as a counter that went up.
        if progress.total >= sweepThreshold, progress.answered == progress.total {
            return NextStep(
                title: "Start pass \(state.curationPass + 1)",
                reason: "Everything has an answer for pass \(state.curationPass). A second "
                    + "sweep reopens all of it, including what you skipped.",
                destination: .pass)
        }

        if context.hasCapturedPlaying {
            return NextStep(
                title: "Do something with what you played",
                reason: "There are captured notes sitting in Your material — learn from them, "
                    + "or read the changes off them.",
                destination: .material)
        }

        // Nothing to say. Furniture is not read.
        return nil
    }
}
