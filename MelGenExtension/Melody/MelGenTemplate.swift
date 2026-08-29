//
//  MelGenTemplate.swift
//  MelGenExtension
//
//  One idea of "what the next take is like", whether it's a line or chords.
//
//  Style briefs and comping figures grew up separately and did the same job from
//  opposite ends: a brief tells the model what kind of line to write, a figure
//  tells the voicing layer what kind of comp to play. Having two of them meant
//  two rotations, two selection controls, two things to explain, and no way to
//  say "give me the next take" without first saying which kind of thing a take
//  is this time.
//
//  So there is one template list, and the mode chooses which half of it is in
//  play. Everything downstream — the rotation, cycle/shuffle/lock, which
//  templates are selected, what the history row says — works on templates rather
//  than on briefs, and stops caring whether a take is monophonic.
//
//  The asymmetry that remains is honest rather than accidental: a line template
//  can be handed to the model *or* realized deterministically, and a chord
//  template is deterministic today because the model has never been asked for a
//  voicing. That's a gap in one direction, not a difference in kind.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

/// A template: the character of the next take.
struct MelGenTemplate: Hashable, Sendable, Identifiable {
    var id: String { "\(mode.rawValue):\(name)" }
    var name: String
    var summary: String
    var mode: PlayMode

    /// For a line: the instruction handed to the model.
    var brief: StyleBrief?
    /// For a line: the gesture rhythms this template leans on when the line is
    /// composed rather than generated, so a template means the same thing on
    /// both paths instead of only shaping the prompt.
    var gestureRhythms: [GestureRhythm]
    /// The contours it leans on. Rhythm alone turned out not to be enough to
    /// tell two templates apart — see `character`.
    var gestureContours: [GestureContour]
    /// Notes per bar it implies, and how much air it wants.
    var density: Double
    var restiness: Double
    /// How it prefers a line to be laid out.
    var architecture: MelodyPhrases.LinePlan.Architecture?
    /// For chords: the comping figure.
    var figure: CompingFigure?
    /// For bass: the rhythmic figure, and which of the pad's two banks it
    /// belongs to — which is what choosing it actually does.
    var basslineFigure: BasslineFigure?

    init(brief: StyleBrief,
         gestureRhythms: [GestureRhythm] = [],
         gestureContours: [GestureContour] = [],
         density: Double = 4,
         restiness: Double = 0.3,
         architecture: MelodyPhrases.LinePlan.Architecture? = nil) {
        self.name = brief.name
        self.summary = brief.text
        self.mode = .line
        self.brief = brief
        self.gestureRhythms = gestureRhythms
        self.gestureContours = gestureContours
        self.density = density
        self.restiness = restiness
        self.architecture = architecture
        self.figure = nil
        self.basslineFigure = nil
    }

    init(figure: CompingFigure) {
        self.name = figure.name
        self.summary = figure.summary
        self.mode = .comping
        // A chord template carries both: the figure for the deterministic path,
        // where the point is getting exactly the rhythm you asked for, and a
        // brief for the model, where the point is getting something you didn't
        // specify. They are not two descriptions of one thing.
        self.brief = StyleBrief(name: figure.name, text: CompingBriefs.brief(for: figure.name))
        self.gestureRhythms = [figure.rhythm]
        self.gestureContours = []
        self.density = 3
        self.restiness = 0.5
        self.architecture = nil
        self.figure = figure
        self.basslineFigure = nil
    }

    /// A bass figure, as a template.
    ///
    /// The rotation, the selection control and the history row all work on
    /// templates, so a mode that had none of them would have to grow its own
    /// copies of three things that already exist. What a bass template means is
    /// narrower than what a line template means, and honestly so: choosing one
    /// moves the pad to where that figure sits in its own bank's ordering.
    /// It carries no brief, because the model is not the thing drawing this.
    init(basslineFigure: BasslineFigure) {
        self.name = basslineFigure.name
        self.summary = basslineFigure.summary
        self.mode = .bass
        self.brief = nil
        self.gestureRhythms = []
        self.gestureContours = []
        self.density = basslineFigure.onsets.reduce(0, +)
        self.restiness = 1 - min(1, basslineFigure.onsets.reduce(0, +) / Double(BasslineFigure.slots))
        self.architecture = nil
        self.figure = nil
        self.basslineFigure = basslineFigure
    }
}

enum MelGenTemplates {

    /// Every template, both kinds.
    static let all: [MelGenTemplate] = line + chords

    /// The line templates: the style briefs, each paired with the gesture
    /// rhythms that mean the same thing the brief's prose does.
    ///
    /// Pairing them is what stops a template being a prompt-only idea. "Long
    /// tones" asked the model for long notes and did nothing at all when the
    /// line was composed instead; now it biases the gesture vocabulary toward
    /// the figures that *are* long tones, so choosing a template shapes every
    /// source rather than only the slowest one.
    static let line: [MelGenTemplate] = [
        // Long tones: few notes, long ones, lots of air, and a shape that goes
        // somewhere slowly.
        MelGenTemplate(brief: StyleBriefs.all[0],
                       gestureRhythms: [.longWithAir, .halfAndAir, .tiedOverTheBar],
                       gestureContours: [.held, .ascend, .arch],
                       density: 2, restiness: 0.55, architecture: .aaba),
        // Running eighths: many notes, short ones, almost no air.
        MelGenTemplate(brief: StyleBriefs.all[1],
                       gestureRhythms: [.even, .runOfFour, .tresillo],
                       gestureContours: [.ascend, .descend, .turn, .pendulum],
                       density: 7, restiness: 0.1, architecture: .through),
        // Syncopated: offbeat figures, middling density.
        MelGenTemplate(brief: StyleBriefs.all[2],
                       gestureRhythms: [.charleston, .pushedPair, .tresillo, .twoPlusThree],
                       gestureContours: [.leapFall, .turn, .pendulum],
                       density: 4, restiness: 0.35, architecture: .pairs),
        // Sparse: the fewest notes of any of them, and the most silence.
        MelGenTemplate(brief: StyleBriefs.all[3],
                       gestureRhythms: [.longWithAir, .stab, .halfAndAir],
                       gestureContours: [.held, .descend],
                       density: 1.5, restiness: 0.65, architecture: .pairs),
        // Call and response: two-bar units that answer each other.
        MelGenTemplate(brief: StyleBriefs.all[4],
                       gestureRhythms: [.dotted, .reverseDotted, .twoPlusThree],
                       gestureContours: [.arch, .valley, .fallLeap],
                       density: 3.5, restiness: 0.4, architecture: .callAnswer),
        // Repeated motif: one cell, over and over, barely varied.
        MelGenTemplate(brief: StyleBriefs.all[5],
                       gestureRhythms: [.tresillo, .twoPlusThree, .tripletFeel],
                       gestureContours: [.pendulum, .turn],
                       density: 5, restiness: 0.25, architecture: .aaba),
        // Rising arc: one long climb.
        MelGenTemplate(brief: StyleBriefs.all[6],
                       gestureRhythms: [.even, .steadyQuarters, .reverseDotted],
                       gestureContours: [.ascend, .arch],
                       density: 5, restiness: 0.2, architecture: .through),
        // Anticipation: everything arrives early and holds.
        MelGenTemplate(brief: StyleBriefs.all[7],
                       gestureRhythms: [.pushedPair, .tiedOverTheBar, .charleston],
                       gestureContours: [.leapFall, .enclose, .held],
                       density: 3, restiness: 0.45, architecture: .pairs),
        // Dotted swing: loping pairs.
        MelGenTemplate(brief: StyleBriefs.all[8],
                       gestureRhythms: [.dotted, .tripletFeel, .reverseDotted],
                       gestureContours: [.valley, .turn, .descend],
                       density: 4.5, restiness: 0.3, architecture: .callAnswer)
    ]

    static let chords: [MelGenTemplate] = CompingFigure.all.map(MelGenTemplate.init(figure:))

    /// The bass templates: the two figure banks, on-beat first.
    static let bass: [MelGenTemplate] = BasslineFigure.all.map(MelGenTemplate.init(basslineFigure:))

    static func all(for mode: PlayMode) -> [MelGenTemplate] {
        switch mode {
        case .line: return line + TemplateStore.templates
        case .comping: return chords
        case .bass: return bass
        }
    }

    static func named(_ name: String, mode: PlayMode) -> MelGenTemplate? {
        all(for: mode).first { $0.name == name }
    }

    /// The template for this point in the rotation, honouring the selection and
    /// the mode. The same shape as the line rotation, because it is the same
    /// rotation — that was the point of merging them.
    static func template(at cursor: Int,
                         mode: PlayMode,
                         selected names: [String],
                         selectionMode: SelectionMode = .cycle,
                         locked: String? = nil) -> MelGenTemplate {
        let available = all(for: mode)
        let chosen = names.isEmpty ? available : available.filter { names.contains($0.name) }
        let pool = chosen.isEmpty ? available : chosen
        if selectionMode == .lock, let locked, let pinned = pool.first(where: { $0.name == locked }) {
            return pinned
        }
        return pool[Rotation.index(cursor: cursor, count: pool.count, mode: selectionMode)]
    }
}

extension MelGenState {

    /// The template the next take will be built from.
    var nextTemplate: MelGenTemplate {
        MelGenTemplates.template(at: briefCursor,
                                 mode: mode,
                                 selected: selectedBriefNames,
                                 selectionMode: briefMode,
                                 locked: lockedBriefName)
    }
}
