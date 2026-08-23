//
//  MelodyPhrase.swift
//  MelGenExtension
//
//  The grammar that turns gestures into a line.
//
//  A phrase that opens, develops and lands sounds composed. Four statements in a
//  row sound like a list. That difference is not a matter of how many notes are
//  in each bar, which is the only lever the plug-in had until now — it's a matter
//  of a figure being *stated*, then *answered*, then *developed*, then *ended*.
//
//  So: a line is a sequence of two-bar phrases. The first states a figure. The
//  second answers it — same rhythm, contour inverted, landing lower, which is
//  what "answer" means in practice. The third develops it with a new rhythm over
//  a related shape. The last cadences: a long note and air. Longer forms cycle
//  that plan, and every phrase after the first may begin with a pickup borrowed
//  from the air at the end of the one before it.
//
//  The result is a `MelodyPattern` — degrees, not pitches — so all of it goes on
//  to be realized over harmony, extracted back, curated and learned from by the
//  machinery that already exists. The composer is a *source* of library material,
//  which is what the library was short of: the six hand-written seeds were
//  generic on purpose, and a corpus of 98 takes turned out to contain only 60
//  distinct lines because those six kept coming round.
//
//  Deterministic from a seed, so a line can be regenerated, compared and tested.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

enum MelodyPhrases {

    static let eighthsPerBar = 8
    static let eighthsPerPhrase = 16

    /// Composes a new line.
    ///
    /// - Parameters:
    ///   - bars: how long, in bars. Rounded up to a whole number of two-bar
    ///     phrases, because the grammar's unit is the phrase.
    ///   - seed: everything random here comes from this, so the same seed is
    ///     always the same line.
    ///   - style: what the musician's kept material measures like. Used to
    ///     weight which rhythms come up — a corpus that syncopates gets
    ///     syncopated figures — and ignored when there isn't one yet.
    /// - Parameter preferring: rhythms the chosen template leans on. Not a
    ///   restriction — the grammar still needs a pickup where a pickup belongs —
    ///   but a heavy thumb on the scale, so "long tones" composes long tones
    ///   rather than only telling the model about them.
    /// - Parameter palette: the note-duration setting. It shaped generation and
    ///   did nothing to composed lines, which made it look broken from the one
    ///   source that answers instantly.
    static func compose(bars: Int = 4,
                        seed: UInt64,
                        style: LearnedStyle? = nil,
                        preferring preferred: [GestureRhythm] = [],
                        contours preferredContours: [GestureContour] = [],
                        density: Double? = nil,
                        restiness: Double? = nil,
                        architecture: LinePlan.Architecture? = nil,
                        palette: DurationPalette = .mixed,
                        name: String? = nil) -> MelodyPattern {
        let phraseCount = max(1, Int(ceil(Double(max(1, bars)) / 2)))
        var rng = SplitMix64(seed: seed)
        var notes: [PatternNote] = []

        // The line's own plan, drawn once. Without this, every composed line has
        // the same architecture — state, answer, develop, land, centred on the
        // third — and however varied the figures are the *lines* all sound like
        // one another. Which they did, and which is the complaint this answers.
        var plan = LinePlan(rng: &rng)
        // A template's character overrides the line's own draw where it has an
        // opinion. Without this, the plan was drawn freely every time and the
        // grammar drowned out the template — nine templates composed to within
        // 0.04 of each other on every measured axis, which is to say they were
        // one template with nine names.
        if let architecture { plan.architecture = architecture }
        if let restiness {
            plan.saysMoreChance = 1 - min(0.85, max(0.05, restiness))
            plan.fragmentChance = max(0, 0.45 - restiness * 0.5)
            plan.pickupChance = max(0.05, 0.6 - restiness * 0.5)
        }
        // Density is the axis the templates differ on most and the one the
        // grammar had no way to hear: a phrase is two figures whatever you asked
        // for. It becomes a thinning or a doubling at the end, using the same
        // metric ranking everything else uses to decide which note matters least.
        let targetDensity = density

        // The figure the whole line is about. Everything else refers to it.
        let callRhythm = pick(rhythms(for: .statement, preferring: preferred, palette: palette),
                              style: style, using: &rng)
        let callContour = pick(contours(for: .statement, preferring: preferredContours), using: &rng)
        let call = MelodyGesture(rhythm: callRhythm, contour: callContour, role: .statement)

        var previousTailEighth = 0

        for phrase in 0..<phraseCount {
            let origin = phrase * eighthsPerPhrase
            let isLast = phrase == phraseCount - 1
            let shape = plan.shape(at: phrase, of: phraseCount)

            // A pickup lives in the air at the end of the previous phrase, which
            // is the only place it can live: it has to arrive *before* the
            // downbeat it leads to.
            if phrase > 0, previousTailEighth <= origin - 2, rng.nextUnit() < plan.pickupChance {
                let pickup = MelodyGesture(
                    rhythm: pick(rhythms(for: .pickup, preferring: preferred, palette: palette),
                                 style: style, using: &rng),
                    contour: .ascend,
                    role: .pickup,
                    anchor: -2
                )
                let start = origin - min(3, pickup.spanEighths)
                if start >= previousTailEighth {
                    notes.append(contentsOf: pickup.notes(startingAt: start, home: 6, velocity: 74))
                }
            }

            let (first, second) = gestures(for: shape,
                                           call: call,
                                           isLast: isLast,
                                           style: style,
                                           preferring: preferred,
                                           contours: preferredContours,
                                           palette: palette,
                                           using: &rng)

            notes.append(contentsOf: first.notes(startingAt: origin,
                                                 home: plan.home(for: first.role, shape: shape),
                                                 velocity: velocity(for: first.role)))

            // The second figure starts after the first has stopped sounding *and*
            // after whatever air the first asked for. It's pushed out to an even
            // eighth so the phrase keeps its footing — unless the template's own
            // figures are offbeat ones, in which case forcing them onto the beat
            // is undoing the thing that makes them what they are. Derived from
            // the figures rather than declared, so a template can't claim to
            // syncopate while being made of downbeats.
            let firstEnd = origin + first.spanEighths
            var secondStart = firstEnd + (rng.nextUnit() < 0.4 ? 2 : 0)
            if !secondStart.isMultiple(of: 2), !leansOffbeat(preferred) { secondStart += 1 }
            previousTailEighth = firstEnd

            // A phrase that is one figure and then silence is a phrase, and it's
            // the one shape a grammar of "always two figures" can never make.
            // Cadences always get their landing note.
            // A phrase may say one thing and stop — that's phrasing. A phrase
            // that says one *short* thing and stops is a hole, and two of those
            // in a row is a line that has forgotten what it was doing.
            let leavesAHole = first.spanEighths < eighthsPerPhrase / 2
            let saysMore = shape == .cadence || leavesAHole
                || rng.nextUnit() < plan.saysMoreChance
            if saysMore, secondStart + second.spanEighths <= origin + eighthsPerPhrase + 2 {
                notes.append(contentsOf: second.notes(startingAt: secondStart,
                                                      home: plan.home(for: second.role, shape: shape),
                                                      velocity: velocity(for: second.role)))
                previousTailEighth = secondStart + second.spanEighths

                // Room left over, now and then, for a parting fragment — the
                // thing a player adds because the bar isn't finished yet.
                let tailStart = previousTailEighth + 1
                if shape != .cadence, rng.nextUnit() < plan.fragmentChance,
                   tailStart + 2 <= origin + eighthsPerPhrase {
                    let fragment = MelodyGesture(rhythm: .stab, contour: .held, role: .continuation,
                                                 anchor: rng.nextUnit() < 0.5 ? 2 : -2)
                    notes.append(contentsOf: fragment.notes(startingAt: tailStart,
                                                            home: 2, velocity: 78))
                    previousTailEighth = tailStart + fragment.spanEighths
                }
            }
        }

        var composed = tidy(notes, spanEighths: phraseCount * eighthsPerPhrase)
        if let targetDensity {
            composed = fit(composed,
                           toDensity: targetDensity,
                           bars: phraseCount * 2,
                           preferring: preferred,
                           rng: &rng)
        }
        return MelodyPattern(
            name: name ?? title(call: call, seed: seed),
            bars: phraseCount * 2,
            summary: summary(of: composed, call: call, bars: phraseCount * 2, plan: plan),
            notes: composed
        )
    }

    // MARK: - The plan

    /// What a phrase is doing in the line.
    enum PhraseShape {
        /// States the figure.
        case call
        /// Replies to it: same rhythm, shape inverted, landing lower.
        case answer
        /// Takes it somewhere: new rhythm, related shape.
        case develop
        /// Ends: a long note and air.
        case cadence
    }

    /// How a whole line is laid out, drawn once per line.
    ///
    /// Four architectures, a register the line is centred on, and how talkative
    /// it is. These are what actually differ between two lines that a listener
    /// would call different pieces, as against two lines built from different
    /// figures — which is the distinction the first version of this missed.
    struct LinePlan {
        enum Architecture: CaseIterable {
            /// State it, answer it, develop it, land. The default, and the one
            /// that reads most like a written phrase.
            case callAnswer
            /// AABA: say it twice, go somewhere else, come back.
            case aaba
            /// Question and answer in pairs, all the way down.
            case pairs
            /// Keep going somewhere new. Least architecture, most motion.
            case through
        }

        var architecture: Architecture
        /// Degrees added to every home, so one line sits on the third and
        /// another on the root without the grammar changing.
        var centre: Int
        var pickupChance: Double
        var saysMoreChance: Double
        var fragmentChance: Double

        init(rng: inout SplitMix64) {
            architecture = Architecture.allCases[Int(rng.next() % UInt64(Architecture.allCases.count))]
            centre = [0, 0, 2, -2, 4][Int(rng.next() % 5)]
            pickupChance = 0.25 + rng.nextUnit() * 0.5
            saysMoreChance = 0.6 + rng.nextUnit() * 0.35
            fragmentChance = rng.nextUnit() * 0.45
        }

        func shape(at index: Int, of count: Int) -> PhraseShape {
            if index == count - 1, count > 1 { return .cadence }
            switch architecture {
            case .callAnswer:
                switch index % 4 {
                case 0: return .call
                case 1: return .answer
                case 2: return .develop
                default: return .answer
                }
            case .aaba:
                switch index % 4 {
                case 0, 1: return .call
                case 2: return .develop
                default: return .call
                }
            case .pairs:
                return index.isMultiple(of: 2) ? .call : .answer
            case .through:
                return index.isMultiple(of: 3) ? .call : .develop
            }
        }

        /// Which degree a figure is centred on, given its job and this line's
        /// register.
        ///
        /// Degrees 0, 2, 4 and 6 are the chord tones of a seven-note scale, so
        /// centring a statement on the third and a cadence on the root is what
        /// makes the shape land right over whatever chord turns out to be
        /// underneath. The cadence is exempt from the line's centre: a phrase
        /// that lands somewhere other than home isn't a cadence.
        func home(for role: GestureRole, shape: PhraseShape) -> Int {
            if role == .cadence { return 0 }
            let base: Int
            switch (role, shape) {
            case (.pickup, _): base = 6
            case (.answer, _): base = 2
            case (.statement, .develop): base = 4
            case (.statement, _): base = 2
            case (.continuation, .answer): base = 0
            case (.continuation, _): base = 4
            case (.cadence, _): base = 0
            }
            return base + centre
        }
    }

    /// The two figures a phrase is built from.
    private static func gestures(for plan: PhraseShape,
                                 call: MelodyGesture,
                                 isLast: Bool,
                                 style: LearnedStyle?,
                                 preferring preferred: [GestureRhythm],
                                 contours preferredContours: [GestureContour],
                                 palette: DurationPalette,
                                 using rng: inout SplitMix64) -> (MelodyGesture, MelodyGesture) {
        switch plan {
        case .call:
            let second = MelodyGesture(
                rhythm: pick(rhythms(for: .continuation, preferring: preferred, palette: palette),
                             style: style, using: &rng),
                contour: pick(contours(for: .continuation, preferring: preferredContours), using: &rng),
                role: .continuation,
                anchor: 1
            )
            return (call, second)

        case .answer:
            // The answer *is* the call — same rhythm, so it's recognisably a
            // reply rather than a new idea — turned over and landing lower.
            var answer = call.inverted
            answer.role = .answer
            answer.anchor = -1
            let tail = MelodyGesture(
                rhythm: pick(rhythms(for: .continuation, preferring: preferred, palette: palette),
                             style: style, using: &rng),
                contour: .descend,
                role: .continuation,
                anchor: -2
            )
            return (answer, tail)

        case .develop:
            // Contrast is the job of this phrase. A develop that reuses the
            // call's rhythm makes the whole line one figure, which is exactly
            // the complaint gestures exist to answer.
            let available = rhythms(for: .statement, preferring: preferred, palette: palette)
            let contrasting = available.filter { $0 != call.rhythm }
            let fresh = MelodyGesture(
                rhythm: pick(contrasting.isEmpty ? available : contrasting,
                             style: style, using: &rng),
                contour: call.contour,
                role: .statement,
                anchor: 2
            )
            let second = MelodyGesture(
                rhythm: call.rhythm,
                contour: pick(contours(for: .continuation, preferring: preferredContours), using: &rng),
                role: .continuation,
                anchor: 0
            )
            return (fresh, second)

        case .cadence:
            var closing = call.inverted
            closing.role = .answer
            closing.anchor = -1
            let landing = MelodyGesture(
                rhythm: pick(rhythms(for: .cadence, preferring: preferred, palette: palette),
                             style: style, using: &rng),
                contour: .held,
                role: .cadence,
                anchor: 0
            )
            return (closing, landing)
        }
    }

    private static func velocity(for role: GestureRole) -> Int {
        switch role {
        case .pickup: return 74
        case .statement: return 96
        case .continuation: return 84
        case .answer: return 90
        case .cadence: return 92
        }
    }

    // MARK: - Vocabulary by role

    /// The rhythms a role may use, narrowed by what the template leans on and by
    /// the note-duration setting.
    ///
    /// Narrowed, never emptied: a template that prefers long tones still needs
    /// *something* for a pickup, and a grammar that can't find a figure for a
    /// role stops being a grammar. Where the preference and the role don't
    /// overlap, the role wins and the preference is simply not expressible there.
    static func rhythms(for role: GestureRole,
                        preferring preferred: [GestureRhythm],
                        palette: DurationPalette) -> [GestureRhythm] {
        let base = rhythms(for: role)
        var pool = base

        if !preferred.isEmpty {
            let overlap = base.filter { preferred.contains($0) }
            if !overlap.isEmpty {
                // Heavily weighted rather than merely nudged. The first version
                // put the preferred figures in the pool twice against a base of
                // nine, which worked out at about a third of draws — far too
                // gentle to be audible, and the measured result was nine
                // templates that composed identically. Six copies against the
                // base puts them at roughly four draws in five, and the rest of
                // the vocabulary is still reachable.
                pool = Array(repeating: overlap, count: 6).flatMap { $0 } + base
            }
        }

        let byPalette = pool.filter { fits($0, palette) }
        return byPalette.isEmpty ? pool : byPalette
    }

    /// Whether a template's figures live off the beat.
    ///
    /// Measured from the figures' own onsets. A template that says it syncopates
    /// and is made of downbeat figures is not syncopating, and taking its word
    /// for it is how nine templates came to compose alike.
    static func leansOffbeat(_ rhythms: [GestureRhythm]) -> Bool {
        guard !rhythms.isEmpty else { return false }
        let onsets = rhythms.flatMap { $0.positions }
        guard !onsets.isEmpty else { return false }
        return Double(onsets.filter { !$0.isMultiple(of: 2) }.count) / Double(onsets.count) > 0.3
    }

    /// Whether a figure belongs to a note-duration setting.
    ///
    /// This is what makes the Note duration control mean something on every
    /// source rather than only on the model's prompt — it was one of four
    /// settings that silently did nothing to a composed line.
    static func fits(_ rhythm: GestureRhythm, _ palette: DurationPalette) -> Bool {
        let lengths = rhythm.lengths
        switch palette {
        case .even:
            // Uniform *and* short. A figure of one six-eighth note is uniform and
            // is not what anyone means by "even" — the brief says steady eighths
            // or steady quarters, so that's what this admits. Without the length
            // bound, Even and Mixed produced the same spread of note lengths
            // across a line, which is a setting that does nothing.
            return Set(lengths).count == 1 && (lengths.first ?? 9) <= 2
        case .longShort:
            // The figure's *own* shape, not merely a descent somewhere in it:
            // nearly every figure contains a longer note followed by a shorter
            // one somewhere, so that test admitted everything.
            guard let first = lengths.first, lengths.count > 1 else { return false }
            return first > lengths[1]
        case .shortLong:
            guard let first = lengths.first, lengths.count > 1 else { return false }
            return first < lengths[1]
        case .mixed:
            // Everything except a *multi-note* figure whose notes are all the
            // same length. A single-note figure — a held tone, a stab — has no
            // mix to have and excluding it took every long note out of the
            // default palette, which is the opposite of mixed.
            return lengths.count == 1 || Set(lengths).count > 1
        }
    }

    static func rhythms(for role: GestureRole) -> [GestureRhythm] {
        switch role {
        case .pickup:
            return [.stab, .reverseDotted, .even]
        case .statement:
            return [.dotted, .tresillo, .charleston, .twoPlusThree, .pushedPair,
                    .tiedOverTheBar, .even, .steadyQuarters, .halfAndAir]
        case .continuation:
            return [.even, .steadyQuarters, .runOfFour, .tripletFeel, .tresillo, .twoPlusThree]
        case .answer:
            return [.dotted, .reverseDotted, .tresillo, .pushedPair]
        case .cadence:
            return [.longWithAir, .tiedOverTheBar, .stab, .halfAndAir]
        }
    }

    static func contours(for role: GestureRole) -> [GestureContour] {
        switch role {
        case .pickup: return [.ascend, .enclose]
        case .statement: return [.arch, .leapFall, .turn, .pendulum, .ascend]
        case .continuation: return [.descend, .valley, .turn, .enclose, .pendulum]
        case .answer: return [.descend, .valley, .fallLeap]
        case .cadence: return [.held, .descend]
        }
    }

    // MARK: - Choosing

    private static func pick<Element>(_ options: [Element], using rng: inout SplitMix64) -> Element {
        options[Int(rng.next() % UInt64(max(1, options.count)))]
    }

    /// Narrows a role's contours by what the template leans on, the same way
    /// rhythms are narrowed — and never to nothing, because a role that can't
    /// find a shape isn't a role.
    static func contours(for role: GestureRole,
                         preferring preferred: [GestureContour]) -> [GestureContour] {
        let base = contours(for: role)
        guard !preferred.isEmpty else { return base }
        let overlap = base.filter { preferred.contains($0) }
        return overlap.isEmpty ? base : overlap
    }

    /// Picks a rhythm, leaning toward the kind of figure the musician's kept
    /// material actually contains.
    ///
    /// Not a hard filter: a style that has never syncopated shouldn't be
    /// *prevented* from syncopating, or the library can only ever narrow. The
    /// weighting is gentle enough to be a lean and not a rule.
    private static func pick(_ options: [GestureRhythm],
                             style: LearnedStyle?,
                             using rng: inout SplitMix64) -> GestureRhythm {
        guard let style, !style.isEmpty, options.count > 1 else {
            return pick(options, using: &rng)
        }

        let weights = options.map { rhythm -> Double in
            let offbeats = rhythm.positions.filter { !$0.isMultiple(of: 2) }.count
            let offbeatShare = Double(offbeats) / Double(max(1, rhythm.noteCount))
            let averageLength = Double(rhythm.lengths.reduce(0, +)) / Double(max(1, rhythm.noteCount))

            // How close is this figure to the material, on the two axes the
            // material is actually measured on?
            let styleLength = style.commonDurations.isEmpty
                ? 2.0
                : Double(style.commonDurations.reduce(0, +)) / Double(style.commonDurations.count)
            let rhythmFit = 1 - min(1, abs(averageLength - styleLength) / 4)
            let syncopationFit = 1 - min(1, abs(offbeatShare - style.offbeatShare))
            return 0.35 + 0.65 * (rhythmFit + syncopationFit) / 2
        }

        let total = weights.reduce(0, +)
        var draw = rng.nextUnit() * total
        for (index, weight) in weights.enumerated() {
            draw -= weight
            if draw <= 0 { return options[index] }
        }
        return options[options.count - 1]
    }

    // MARK: - Finishing

    /// Sorts, de-overlaps and clips. Gestures are placed independently and can
    /// collide at the seams; a pattern has to be monophonic before anything else
    /// touches it.
    private static func tidy(_ notes: [PatternNote], spanEighths: Int) -> [PatternNote] {
        var ordered = notes
            .filter { $0.startEighth >= 0 && $0.startEighth < spanEighths }
            .sorted { ($0.startEighth, $0.degree) < ($1.startEighth, $1.degree) }

        // One note per onset: two gestures landing on the same eighth is a
        // collision, not a chord.
        var deduplicated: [PatternNote] = []
        for note in ordered where deduplicated.last?.startEighth != note.startEighth {
            deduplicated.append(note)
        }
        ordered = deduplicated

        for index in ordered.indices.dropLast() {
            let slot = ordered[index + 1].startEighth - ordered[index].startEighth
            let requested = ordered[index].restAfterEighths
            var length = min(ordered[index].lengthEighths, slot)
            if requested > 0 {
                length = min(length, max(slot - requested, (slot + 1) / 2))
            }
            ordered[index].lengthEighths = max(1, length)
        }
        if var last = ordered.last {
            last.lengthEighths = max(1, min(last.lengthEighths, spanEighths - last.startEighth))
            ordered[ordered.count - 1] = last
        }
        return ordered
    }

    /// Brings a composed line to about the density its template asked for.
    ///
    /// Thinning takes the weakest metric positions first, which is the ranking
    /// the whole plug-in shares; thickening inserts notes between existing ones
    /// rather than at random positions, so the added notes are passing tones
    /// through the shape that's already there rather than a second line laid over
    /// it.
    static func fit(_ notes: [PatternNote],
                    toDensity target: Double,
                    bars: Int,
                    preferring preferred: [GestureRhythm],
                    rng: inout SplitMix64) -> [PatternNote] {
        guard !notes.isEmpty, bars > 0 else { return notes }
        let wanted = max(2, Int((target * Double(bars)).rounded()))
        let ordered = notes.sorted { $0.startEighth < $1.startEighth }

        if wanted < ordered.count {
            let ranked = ordered.indices.sorted {
                MelodyTransforms.metricWeight(ordered[$0].startEighth)
                    < MelodyTransforms.metricWeight(ordered[$1].startEighth)
            }
            // Never the first note or the last: the line still has to start where
            // it started and land where it landed.
            let droppable = ranked.filter { $0 != 0 && $0 != ordered.count - 1 }
            let dropped = Set(droppable.prefix(ordered.count - wanted))
            return ordered.indices.filter { !dropped.contains($0) }.map { ordered[$0] }
        }

        guard wanted > ordered.count else { return ordered }

        // A dense target can't be reached by filling gaps alone: once the notes
        // are packed there are no gaps left, and the line tops out well short of
        // what was asked for. So a template asking for a great deal more than it
        // got shortens what's there first — which is not a compromise. "Running
        // eighths" means short notes; a version of it made of half notes with
        // extra notes squeezed between them would be the wrong line.
        var result = ordered
        if Double(wanted) > Double(ordered.count) * 1.4 {
            for index in result.indices {
                result[index].lengthEighths = min(result[index].lengthEighths, 2)
            }
        }
        var attempts = 0
        while result.count < wanted, attempts < wanted * 3 {
            attempts += 1
            // The widest gap, so the line fills in where it is emptiest.
            var widest = 0
            var widestGap = 0
            for index in result.indices.dropLast() {
                let gap = result[index + 1].startEighth
                    - (result[index].startEighth + result[index].lengthEighths)
                if gap > widestGap { widestGap = gap; widest = index }
            }
            guard widestGap >= 1 else { break }

            let anchor = result[widest]
            let next = result[widest + 1]
            var inserted = anchor
            inserted.startEighth = anchor.startEighth + anchor.lengthEighths
                + max(0, (widestGap - 1) / 2)
            inserted.lengthEighths = 1
            inserted.restAfterEighths = 0
            // Between the two it sits between, so it passes rather than repeats.
            inserted.degree = (anchor.degree + next.degree) / 2
            if inserted.degree == anchor.degree {
                inserted.degree += next.degree > anchor.degree ? 1 : -1
            }
            inserted.velocity = max(40, anchor.velocity - 10)
            result.insert(inserted, at: widest + 1)
        }
        return result
    }

    private static func title(call: MelodyGesture, seed: UInt64) -> String {
        "\(call.rhythm.name) \(call.contour.label.lowercased()) \(seed % 1000)"
    }

    private static func summary(of notes: [PatternNote], call: MelodyGesture,
                                bars: Int, plan: LinePlan) -> String {
        let offbeats = notes.filter { !$0.startEighth.isMultiple(of: 2) }.count
        let lengths = Set(notes.map(\.lengthEighths)).sorted()
        var parts = ["\(notes.count) notes over \(bars) bars, "
                     + "\(String(describing: plan.architecture)) on a \(call.rhythm.name.lowercased()) figure"]
        if offbeats * 3 > notes.count { parts.append("syncopated") }
        parts.append("lengths " + lengths.map(String.init).joined(separator: "/"))
        return parts.joined(separator: ", ")
    }
}
