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
    static func compose(bars: Int = 4,
                        seed: UInt64,
                        style: LearnedStyle? = nil,
                        name: String? = nil) -> MelodyPattern {
        let phraseCount = max(1, Int(ceil(Double(max(1, bars)) / 2)))
        var rng = SplitMix64(seed: seed)
        var notes: [PatternNote] = []

        // The figure the whole line is about. Everything else refers to it.
        let callRhythm = pick(rhythms(for: .statement), style: style, using: &rng)
        let callContour = pick(contours(for: .statement), using: &rng)
        let call = MelodyGesture(rhythm: callRhythm, contour: callContour, role: .statement)

        var previousTailEighth = 0

        for phrase in 0..<phraseCount {
            let origin = phrase * eighthsPerPhrase
            let isLast = phrase == phraseCount - 1
            let plan = shape(at: phrase, of: phraseCount)

            // A pickup lives in the air at the end of the previous phrase, which
            // is the only place it can live: it has to arrive *before* the
            // downbeat it leads to.
            if phrase > 0, previousTailEighth <= origin - 2, rng.nextUnit() < 0.55 {
                let pickup = MelodyGesture(
                    rhythm: pick(rhythms(for: .pickup), style: style, using: &rng),
                    contour: .ascend,
                    role: .pickup,
                    anchor: -2
                )
                let start = origin - min(3, pickup.spanEighths)
                if start >= previousTailEighth {
                    notes.append(contentsOf: pickup.notes(startingAt: start, home: 6, velocity: 74))
                }
            }

            let (first, second) = gestures(for: plan,
                                           call: call,
                                           isLast: isLast,
                                           style: style,
                                           using: &rng)

            notes.append(contentsOf: first.notes(startingAt: origin,
                                                 home: home(for: first.role, plan: plan),
                                                 velocity: velocity(for: first.role)))

            // The second figure starts after the first has stopped sounding *and*
            // after whatever air the first asked for, pushed out to an even
            // eighth so the phrase keeps its footing. An extra beat of gap comes
            // up often enough that phrases don't all breathe in the same place.
            let firstEnd = origin + first.spanEighths
            var secondStart = firstEnd + (rng.nextUnit() < 0.4 ? 2 : 0)
            if !secondStart.isMultiple(of: 2) { secondStart += 1 }
            previousTailEighth = firstEnd

            // A phrase that is one figure and then silence is a phrase, and it's
            // the one shape a grammar of "always two figures" can never make.
            // Cadences always get their landing note.
            let saysMore = plan == .cadence || rng.nextUnit() < 0.78
            if saysMore, secondStart + second.spanEighths <= origin + eighthsPerPhrase + 2 {
                notes.append(contentsOf: second.notes(startingAt: secondStart,
                                                      home: home(for: second.role, plan: plan),
                                                      velocity: velocity(for: second.role)))
                previousTailEighth = secondStart + second.spanEighths

                // Room left over, now and then, for a parting fragment — the
                // thing a player adds because the bar isn't finished yet.
                let tailStart = previousTailEighth + 1
                if plan != .cadence, rng.nextUnit() < 0.3,
                   tailStart + 2 <= origin + eighthsPerPhrase {
                    let fragment = MelodyGesture(rhythm: .stab, contour: .held, role: .continuation,
                                                 anchor: rng.nextUnit() < 0.5 ? 2 : -2)
                    notes.append(contentsOf: fragment.notes(startingAt: tailStart,
                                                            home: 2, velocity: 78))
                    previousTailEighth = tailStart + fragment.spanEighths
                }
            }
        }

        let composed = tidy(notes, spanEighths: phraseCount * eighthsPerPhrase)
        return MelodyPattern(
            name: name ?? title(call: call, seed: seed),
            bars: phraseCount * 2,
            summary: summary(of: composed, call: call, bars: phraseCount * 2),
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

    static func shape(at index: Int, of count: Int) -> PhraseShape {
        if index == count - 1, count > 1 { return .cadence }
        switch index % 4 {
        case 0: return .call
        case 1: return .answer
        case 2: return .develop
        default: return .answer
        }
    }

    /// The two figures a phrase is built from.
    private static func gestures(for plan: PhraseShape,
                                 call: MelodyGesture,
                                 isLast: Bool,
                                 style: LearnedStyle?,
                                 using rng: inout SplitMix64) -> (MelodyGesture, MelodyGesture) {
        switch plan {
        case .call:
            let second = MelodyGesture(
                rhythm: pick(rhythms(for: .continuation), style: style, using: &rng),
                contour: pick(contours(for: .continuation), using: &rng),
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
                rhythm: pick(rhythms(for: .continuation), style: style, using: &rng),
                contour: .descend,
                role: .continuation,
                anchor: -2
            )
            return (answer, tail)

        case .develop:
            // Contrast is the job of this phrase. A develop that reuses the
            // call's rhythm makes the whole line one figure, which is exactly
            // the complaint gestures exist to answer.
            let contrasting = rhythms(for: .statement).filter { $0 != call.rhythm }
            let fresh = MelodyGesture(
                rhythm: pick(contrasting.isEmpty ? rhythms(for: .statement) : contrasting,
                             style: style, using: &rng),
                contour: call.contour,
                role: .statement,
                anchor: 2
            )
            let second = MelodyGesture(
                rhythm: call.rhythm,
                contour: pick(contours(for: .continuation), using: &rng),
                role: .continuation,
                anchor: 0
            )
            return (fresh, second)

        case .cadence:
            var closing = call.inverted
            closing.role = .answer
            closing.anchor = -1
            let landing = MelodyGesture(
                rhythm: pick(rhythms(for: .cadence), style: style, using: &rng),
                contour: .held,
                role: .cadence,
                anchor: 0
            )
            return (closing, landing)
        }
    }

    /// Which degree a figure is centred on, given its job.
    ///
    /// Degrees 0, 2, 4 and 6 are the chord tones of a seven-note scale, so
    /// centring a statement on the third and a cadence on the root is what makes
    /// the shape land right over whatever chord turns out to be underneath.
    private static func home(for role: GestureRole, plan: PhraseShape) -> Int {
        switch (role, plan) {
        case (.cadence, _): return 0
        case (.pickup, _): return 6
        case (.answer, _): return 2
        case (.statement, .develop): return 4
        case (.statement, _): return 2
        case (.continuation, .answer): return 0
        case (.continuation, _): return 4
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

    static func rhythms(for role: GestureRole) -> [GestureRhythm] {
        switch role {
        case .pickup:
            return [.stab, .reverseDotted, .even]
        case .statement:
            return [.dotted, .tresillo, .charleston, .twoPlusThree, .pushedPair, .tiedOverTheBar]
        case .continuation:
            return [.even, .runOfFour, .tripletFeel, .tresillo, .twoPlusThree]
        case .answer:
            return [.dotted, .reverseDotted, .tresillo, .pushedPair]
        case .cadence:
            return [.longWithAir, .tiedOverTheBar, .stab]
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

    private static func title(call: MelodyGesture, seed: UInt64) -> String {
        "\(call.rhythm.name) \(call.contour.label.lowercased()) \(seed % 1000)"
    }

    private static func summary(of notes: [PatternNote], call: MelodyGesture, bars: Int) -> String {
        let offbeats = notes.filter { !$0.startEighth.isMultiple(of: 2) }.count
        let lengths = Set(notes.map(\.lengthEighths)).sorted()
        var parts = ["\(notes.count) notes over \(bars) bars, built on a \(call.rhythm.name.lowercased()) figure"]
        if offbeats * 3 > notes.count { parts.append("syncopated") }
        parts.append("lengths " + lengths.map(String.init).joined(separator: "/"))
        return parts.joined(separator: ", ")
    }
}
