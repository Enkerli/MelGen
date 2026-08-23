//
//  TemplateCharacter.swift
//  MelGenExtension
//
//  A template as numbers, so one can be written rather than only chosen — and
//  refused when it isn't new.
//
//  The economics are the reason this exists. A take costs about 1.8 seconds a
//  note, every time, forever. A template costs one request *once*, and after that
//  the deterministic path composes from it instantly for as long as it's kept. If
//  the model is going to be asked for something, this is the thing to ask it for:
//  it's language and character, which is what it's good at, rather than
//  arithmetic and speed, which is what it isn't.
//
//  The part that makes it worth building rather than merely appealing is the
//  gate. A template can be composed from and *measured*, so one that turns out to
//  be an existing template under a new name can be rejected before it reaches the
//  rotation. That check was not buildable a day ago: the nine hand-written
//  templates were 0.04 apart from each other, so nothing could have failed it.
//  Now that they're 0.10 apart, "is this actually new" is a question with an
//  answer.
//
//  Deliberately free of any FoundationModels dependency: the schema lives in
//  MelodyModels, the request in MelodyGenerator, and everything that decides
//  whether an answer is any good lives here where it can be tested.
//

import Foundation

/// A template expressed as what it does rather than as which figures it uses.
///
/// Numbers rather than a list of figures, because a model asked for figures would
/// have to know the vocabulary and would get the names wrong; asked for "about
/// five notes a bar, mostly short, heavily syncopated" it is on ground it
/// understands, and matching that to figures is arithmetic this side can do.
struct TemplateCharacter: Codable, Hashable, Sendable {
    var name: String
    /// The instruction handed to the model when a line is generated from this.
    var brief: String
    /// Roughly how many notes a bar.
    var notesPerBar: Double
    /// 0 wall-to-wall, 1 mostly silence.
    var airiness: Double
    /// 0 everything on the beat, 1 everything off it.
    var offbeatness: Double
    /// Typical note length in eighths.
    var noteLength: Double
    /// One of the phrase architectures, by name; nil lets the line choose.
    var shape: String?

    init(name: String,
         brief: String,
         notesPerBar: Double,
         airiness: Double,
         offbeatness: Double,
         noteLength: Double,
         shape: String? = nil) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.brief = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notesPerBar = min(8, max(1, notesPerBar))
        self.airiness = min(1, max(0, airiness))
        self.offbeatness = min(1, max(0, offbeatness))
        self.noteLength = min(6, max(1, noteLength))
        self.shape = shape
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        brief = try container.decodeIfPresent(String.self, forKey: .brief) ?? ""
        notesPerBar = try container.decodeIfPresent(Double.self, forKey: .notesPerBar) ?? 4
        airiness = try container.decodeIfPresent(Double.self, forKey: .airiness) ?? 0.3
        offbeatness = try container.decodeIfPresent(Double.self, forKey: .offbeatness) ?? 0.3
        noteLength = try container.decodeIfPresent(Double.self, forKey: .noteLength) ?? 2
        shape = try container.decodeIfPresent(String.self, forKey: .shape)
    }
}

// MARK: - What a figure is like

extension GestureRhythm {

    /// The measured properties a character is matched against.
    var meanLength: Double {
        Double(lengths.reduce(0, +)) / Double(max(1, lengths.count))
    }

    var offbeatShare: Double {
        let onsets = positions
        guard !onsets.isEmpty else { return 0 }
        return Double(onsets.filter { !$0.isMultiple(of: 2) }.count) / Double(onsets.count)
    }

    /// Notes per bar this figure implies, from its own footprint.
    var impliedDensity: Double {
        Double(noteCount) / max(0.5, Double(spanEighths) / 8)
    }

    /// Share of the figure's footprint that is silence.
    var airShare: Double {
        let sounding = Double(lengths.reduce(0, +))
        let span = Double(max(1, spanEighths))
        return max(0, min(1, 1 - sounding / span))
    }
}

// MARK: - Numbers to figures

enum TemplateDerivation {

    /// The figures a character implies, nearest first.
    ///
    /// Distance over the four axes the character names, each normalized so none
    /// of them dominates by having a larger natural range. Three figures rather
    /// than one, because a template made of a single figure composes a line that
    /// repeats it — which is a different failure from the one this is fixing.
    static func rhythms(for character: TemplateCharacter, count: Int = 3) -> [GestureRhythm] {
        GestureRhythm.all
            .map { rhythm -> (GestureRhythm, Double) in
                let density = abs(rhythm.impliedDensity - character.notesPerBar) / 8
                let length = abs(rhythm.meanLength - character.noteLength) / 6
                let offbeat = abs(rhythm.offbeatShare - character.offbeatness)
                let air = abs(rhythm.airShare - character.airiness)
                return (rhythm, density + length + offbeat + air)
            }
            .sorted { ($0.1, $0.0.name) < ($1.1, $1.0.name) }
            .prefix(max(1, count))
            .map(\.0)
    }

    /// Contours, from the one thing about shape the character carries.
    ///
    /// A character that doesn't name a shape gets the contours that go with how
    /// busy it is: a sparse line wants shapes that hold and fall, a dense one
    /// wants shapes that go somewhere.
    static func contours(for character: TemplateCharacter) -> [GestureContour] {
        if let shape = character.shape?.lowercased() {
            let matched = GestureContour.allCases.filter {
                shape.contains($0.rawValue.lowercased())
                    || shape.contains($0.label.lowercased())
            }
            if !matched.isEmpty { return matched }
        }
        if character.notesPerBar < 2.5 { return [.held, .descend, .arch] }
        if character.notesPerBar > 5.5 { return [.ascend, .descend, .turn, .pendulum] }
        return [.arch, .turn, .leapFall, .valley]
    }

    static func architecture(for character: TemplateCharacter) -> MelodyPhrases.LinePlan.Architecture? {
        guard let shape = character.shape?.lowercased() else { return nil }
        for candidate in MelodyPhrases.LinePlan.Architecture.allCases
        where shape.contains(String(describing: candidate).lowercased()) {
            return candidate
        }
        if shape.contains("call") || shape.contains("answer") { return .callAnswer }
        if shape.contains("repeat") || shape.contains("aaba") { return .aaba }
        if shape.contains("pair") || shape.contains("question") { return .pairs }
        if shape.contains("through") || shape.contains("continuous") { return .through }
        return nil
    }

    /// The character as a template the rest of the plug-in can use.
    static func template(from character: TemplateCharacter) -> MelGenTemplate {
        MelGenTemplate(
            brief: StyleBrief(name: character.name, text: character.brief),
            gestureRhythms: rhythms(for: character),
            gestureContours: contours(for: character),
            density: character.notesPerBar,
            restiness: character.airiness,
            architecture: architecture(for: character)
        )
    }
}

// MARK: - Is it actually new?

/// What happened when an authored template met the ones that already exist.
struct TemplateVerdict: Sendable {
    var accepted: Bool
    var reason: String
    /// The existing template it's nearest to, and how near.
    var nearest: String?
    var distance: Double

    var summary: String {
        guard let nearest else { return reason }
        return reason + String(format: " (nearest: %@, %.2f away)", nearest, distance)
    }
}

enum TemplateGate {

    /// How different a new template has to be from every existing one.
    ///
    /// Set at roughly the median distance between the hand-written templates, so
    /// a new one has to be at least as distinct from its nearest neighbour as two
    /// existing templates typically are from each other. A lower bar would let
    /// through templates that are real but redundant; a higher one would reject
    /// legitimately narrow variations. This number is only meaningful because the
    /// existing templates were made to differ first — against a set that were
    /// 0.04 apart, no threshold would have meant anything.
    static let minimumDistance = 0.08

    /// Measures a template by composing from it several times.
    ///
    /// Several seeds, because one composition is one draw and a template is a
    /// distribution. Averaging is what makes the comparison about the template
    /// rather than about the line it happened to produce.
    static func profile(of template: MelGenTemplate, seeds: Int = 8) -> PatternProfile {
        var total = PatternProfile()
        var count = 0.0
        for seed in (1...max(1, seeds)).map(UInt64.init) {
            let measured = PatternProfile.of(MelodyPhrases.compose(
                bars: 8,
                seed: seed,
                preferring: template.gestureRhythms,
                contours: template.gestureContours,
                density: template.density,
                restiness: template.restiness,
                architecture: template.architecture))
            total.notesPerBar += measured.notesPerBar
            total.offbeatShare += measured.offbeatShare
            total.restShare += measured.restShare
            total.stepShare += measured.stepShare
            total.skipShare += measured.skipShare
            total.leapShare += measured.leapShare
            total.meanLength += measured.meanLength
            count += 1
        }
        guard count > 0 else { return total }
        total.notesPerBar /= count
        total.offbeatShare /= count
        total.restShare /= count
        total.stepShare /= count
        total.skipShare /= count
        total.leapShare /= count
        total.meanLength /= count
        return total
    }

    /// Whether an authored template earns a place.
    ///
    /// Three ways to fail, in the order they're worth checking: it has no brief
    /// (nothing to hand the model), it reuses a name (the library is keyed by
    /// name), or — the one this is really for — it composes to within a hair of
    /// something already in the rotation, which makes it a rename rather than a
    /// template.
    static func judge(_ character: TemplateCharacter,
                      against existing: [MelGenTemplate]) -> TemplateVerdict {
        guard !character.name.isEmpty else {
            return TemplateVerdict(accepted: false, reason: "It has no name.",
                                   nearest: nil, distance: 0)
        }
        guard character.brief.count >= 20 else {
            return TemplateVerdict(accepted: false,
                                   reason: "Its brief is too short to tell the model anything.",
                                   nearest: nil, distance: 0)
        }
        guard !existing.contains(where: { $0.name.lowercased() == character.name.lowercased() }) else {
            return TemplateVerdict(accepted: false,
                                   reason: "There's already a template called that.",
                                   nearest: character.name, distance: 0)
        }

        let candidate = profile(of: TemplateDerivation.template(from: character))
        var nearest: (name: String, distance: Double)?
        for template in existing {
            let distance = candidate.distance(to: profile(of: template))
            if nearest == nil || distance < nearest!.distance {
                nearest = (template.name, distance)
            }
        }

        guard let nearest else {
            return TemplateVerdict(accepted: true, reason: "Nothing to compare it against.",
                                   nearest: nil, distance: 0)
        }
        guard nearest.distance >= minimumDistance else {
            return TemplateVerdict(
                accepted: false,
                reason: "It composes to almost the same thing as one you already have.",
                nearest: nearest.name,
                distance: nearest.distance)
        }
        return TemplateVerdict(accepted: true,
                               reason: "New — it composes to something the rotation doesn't have.",
                               nearest: nearest.name,
                               distance: nearest.distance)
    }
}

// MARK: - Keeping them

enum TemplateStore {
    private static let defaultsKey = "MelGen.authoredTemplates"

    /// Stored as characters rather than as templates: the numbers are the durable
    /// thing, and the figures are re-derived on load, so a change to the gesture
    /// vocabulary improves old templates instead of stranding them.
    static var characters: [TemplateCharacter] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode([TemplateCharacter].self, from: data) else {
            return []
        }
        return stored
    }

    static var templates: [MelGenTemplate] {
        characters.map(TemplateDerivation.template(from:))
    }

    static func add(_ character: TemplateCharacter) {
        var stored = characters
        guard !stored.contains(where: { $0.name.lowercased() == character.name.lowercased() }) else {
            return
        }
        stored.append(character)
        write(stored)
    }

    static func remove(named name: String) {
        write(characters.filter { $0.name != name })
    }

    private static func write(_ characters: [TemplateCharacter]) {
        guard let data = try? JSONEncoder().encode(characters) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
