//
//  MelGenSetup.swift
//  MelGenExtension
//
//  A named set of settings you can come back to, and one of them the way the
//  plug-in starts.
//
//  Why this is a type rather than "just save the state": a session is mostly
//  material — a history of takes, what was said about them, which one is playing.
//  A setup is none of that. It's the *dozen or so decisions* that shape what
//  comes next: four bars or eight, how far down the ranked list to reach, chord
//  mode, six notes a bar, a warm temperature, and how much the loop is allowed to
//  drift while it plays. Those are worth carrying between sessions; the takes
//  aren't, because they belong to the progression they were written over.
//
//  The split is also what makes recalling one safe. Applying a setup can't touch
//  a take, a mark, or a tag — the fields simply aren't in it — so it's a change
//  of intent rather than an edit to the record.
//
//  Stored outside the host's session, in the same place the authored templates
//  live, because "the way I usually work" isn't a property of one project.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

/// The settings that decide what comes next, under a name.
struct MelGenSetup: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var savedAt: Date = Date()

    // What kind of thing is being made.
    var mode: PlayMode
    var voiceLeading: VoiceLeadingMode
    var compingFigureName: String

    // How the changes are generated.
    var progressionBars: Int
    var progressionSurprise: Double
    var progressionFreshness: Freshness
    var progressionReharm: Reharm
    var progressionContext: Int
    var progressionModulation: Int
    var progressionKey: Int
    var progressionMode: ProgressionMode

    // How the line or comp is written.
    var temperature: Double
    var durationPalette: DurationPalette
    var expression: ExpressionSettings
    var liveMutation: LiveMutation

    // How the rotation behaves.
    var briefMode: SelectionMode
    var lockedBriefName: String?
    var selectedBriefNames: [String]
    var lineMode: SelectionMode
    var lockedLineName: String?
    var learnedDraw: LearnedDraw
    var autoRegenerate: Bool
    var regenerateEveryPasses: Int

    /// Captures the settings in force, leaving the material alone.
    init(name: String, capturing state: MelGenState, id: UUID = UUID(), savedAt: Date = Date()) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.savedAt = savedAt
        mode = state.mode
        voiceLeading = state.voiceLeading
        compingFigureName = state.compingFigureName
        progressionBars = state.progressionBars
        progressionSurprise = state.progressionSurprise
        progressionFreshness = state.progressionFreshness
        progressionReharm = state.progressionReharm
        progressionContext = state.progressionContext
        progressionModulation = state.progressionModulation
        progressionKey = state.progressionKey
        progressionMode = state.progressionMode
        temperature = state.temperature
        durationPalette = state.durationPalette
        expression = state.expression
        liveMutation = state.liveMutation
        briefMode = state.briefMode
        lockedBriefName = state.lockedBriefName
        selectedBriefNames = state.selectedBriefNames
        lineMode = state.lineMode
        lockedLineName = state.lockedLineName
        learnedDraw = state.learnedDraw
        autoRegenerate = state.autoRegenerate
        regenerateEveryPasses = state.regenerateEveryPasses
    }

    // Field by field, so a setup saved by an older build still loads instead of
    // the whole list failing to decode — which would lose every setup rather than
    // one field of one.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = MelGenState()
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date()
        mode = try container.decodeIfPresent(PlayMode.self, forKey: .mode) ?? fallback.mode
        voiceLeading = try container.decodeIfPresent(VoiceLeadingMode.self, forKey: .voiceLeading)
            ?? fallback.voiceLeading
        compingFigureName = try container.decodeIfPresent(String.self, forKey: .compingFigureName)
            ?? fallback.compingFigureName
        progressionBars = try container.decodeIfPresent(Int.self, forKey: .progressionBars)
            ?? fallback.progressionBars
        progressionSurprise = try container.decodeIfPresent(Double.self, forKey: .progressionSurprise)
            ?? fallback.progressionSurprise
        progressionFreshness = try container.decodeIfPresent(Freshness.self, forKey: .progressionFreshness)
            ?? fallback.progressionFreshness
        progressionReharm = try container.decodeIfPresent(Reharm.self, forKey: .progressionReharm)
            ?? fallback.progressionReharm
        progressionContext = try container.decodeIfPresent(Int.self, forKey: .progressionContext)
            ?? fallback.progressionContext
        progressionModulation = try container.decodeIfPresent(Int.self, forKey: .progressionModulation)
            ?? fallback.progressionModulation
        progressionKey = try container.decodeIfPresent(Int.self, forKey: .progressionKey)
            ?? fallback.progressionKey
        progressionMode = try container.decodeIfPresent(ProgressionMode.self, forKey: .progressionMode)
            ?? fallback.progressionMode
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
            ?? fallback.temperature
        durationPalette = try container.decodeIfPresent(DurationPalette.self, forKey: .durationPalette)
            ?? fallback.durationPalette
        expression = try container.decodeIfPresent(ExpressionSettings.self, forKey: .expression)
            ?? fallback.expression
        liveMutation = try container.decodeIfPresent(LiveMutation.self, forKey: .liveMutation)
            ?? fallback.liveMutation
        briefMode = try container.decodeIfPresent(SelectionMode.self, forKey: .briefMode)
            ?? fallback.briefMode
        lockedBriefName = try container.decodeIfPresent(String.self, forKey: .lockedBriefName)
        selectedBriefNames = try container.decodeIfPresent([String].self, forKey: .selectedBriefNames)
            ?? fallback.selectedBriefNames
        lineMode = try container.decodeIfPresent(SelectionMode.self, forKey: .lineMode)
            ?? fallback.lineMode
        lockedLineName = try container.decodeIfPresent(String.self, forKey: .lockedLineName)
        learnedDraw = try container.decodeIfPresent(LearnedDraw.self, forKey: .learnedDraw)
            ?? fallback.learnedDraw
        autoRegenerate = try container.decodeIfPresent(Bool.self, forKey: .autoRegenerate)
            ?? fallback.autoRegenerate
        regenerateEveryPasses = try container.decodeIfPresent(Int.self, forKey: .regenerateEveryPasses)
            ?? fallback.regenerateEveryPasses
    }

    /// A one-line description, so a list of setups is readable without opening them.
    var summary: String {
        var parts: [String] = [mode.label.lowercased()]
        parts.append("\(progressionBars) bars")
        parts.append(String(format: "surprise %.2f", progressionSurprise))
        parts.append(progressionFreshness.label.lowercased())
        parts.append(String(format: "temp %.2f", temperature))
        parts.append(String(format: "%.0f notes/bar", expression.density * 8))
        if liveMutation.isActive { parts.append("drifting") }
        if autoRegenerate {
            parts.append("auto every \(regenerateEveryPasses) pass\(regenerateEveryPasses == 1 ? "" : "es")")
        }
        return parts.joined(separator: " · ")
    }
}

extension MelGenSetup {

    /// The setup to offer when there aren't any yet.
    ///
    /// Not a "factory default" in the preset sense — the plain defaults on
    /// `MelGenState` are that. This is a working setup, written down from how the
    /// plug-in is actually used: four bars, surprise almost all the way up, bold
    /// on both the corpus and the substitutions, two chords of context, no
    /// modulation, chords rather than a line, templates shuffled, six notes a
    /// bar, a warm temperature, mixed note values, and enough drift that no two
    /// passes are identical.
    ///
    /// Offering it means the first thing anyone sees is a setup that produces
    /// something, rather than an empty list and a note explaining what setups are.
    static var suggested: MelGenSetup {
        var state = MelGenState()
        state.mode = .comping
        state.voiceLeading = .smooth
        state.progressionBars = 4
        state.progressionSurprise = 0.96
        state.progressionFreshness = .bold
        state.progressionReharm = .bold
        state.progressionContext = 2
        state.progressionModulation = 0
        state.temperature = 0.9
        state.durationPalette = .mixed
        // Density is a fraction of the eight-eighth bar, so six notes a bar.
        state.expression.density = 6.0 / 8
        state.briefMode = .shuffle
        state.liveMutation = LiveMutation(noteOrder: 0.05, accents: 0.3, slides: 0.3,
                                          skipSteps: 0.08, octaves: 0.1)
        state.autoRegenerate = true
        state.regenerateEveryPasses = 2
        return MelGenSetup(name: "Bold 4-bar comp", capturing: state)
    }
}

extension MelGenState {

    /// Takes on a setup's settings, leaving the material untouched.
    ///
    /// Everything a setup doesn't name is left exactly as it was: the
    /// progression text, the history, the marks, which take is playing. That's
    /// the point of the type — recalling a setup is a statement about what comes
    /// next, not an edit to what already happened.
    mutating func apply(_ setup: MelGenSetup) {
        mode = setup.mode
        voiceLeading = setup.voiceLeading
        compingFigureName = setup.compingFigureName
        progressionBars = setup.progressionBars
        progressionSurprise = setup.progressionSurprise
        progressionFreshness = setup.progressionFreshness
        progressionReharm = setup.progressionReharm
        progressionContext = setup.progressionContext
        progressionModulation = setup.progressionModulation
        progressionKey = setup.progressionKey
        progressionMode = setup.progressionMode
        temperature = setup.temperature
        durationPalette = setup.durationPalette
        expression = setup.expression
        liveMutation = setup.liveMutation
        briefMode = setup.briefMode
        lockedBriefName = setup.lockedBriefName
        selectedBriefNames = setup.selectedBriefNames
        lineMode = setup.lineMode
        lockedLineName = setup.lockedLineName
        learnedDraw = setup.learnedDraw
        autoRegenerate = setup.autoRegenerate
        regenerateEveryPasses = setup.regenerateEveryPasses
    }

    /// Whether the settings in force still match a setup, so the interface can
    /// say "Bold 4-bar comp" rather than "Bold 4-bar comp (edited)" wrongly.
    func matches(_ setup: MelGenSetup) -> Bool {
        MelGenSetup(name: setup.name, capturing: self, id: setup.id, savedAt: setup.savedAt) == setup
    }
}

/// Where setups live: outside any one host session, next to the authored
/// templates, because "the way I usually work" isn't a property of one project.
enum SetupStore {
    private static let setupsKey = "MelGen.setups"
    private static let defaultKey = "MelGen.defaultSetup"

    static var all: [MelGenSetup] {
        guard let data = UserDefaults.standard.data(forKey: setupsKey),
              let stored = try? JSONDecoder().decode([MelGenSetup].self, from: data) else {
            return []
        }
        return stored
    }

    /// Which setup a new instance starts from, if any.
    ///
    /// Stored as an id rather than a name so renaming a setup doesn't quietly
    /// stop it being the default.
    static var defaultSetupID: UUID? {
        get {
            guard let text = UserDefaults.standard.string(forKey: defaultKey) else { return nil }
            return UUID(uuidString: text)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: defaultKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultKey)
            }
        }
    }

    static var defaultSetup: MelGenSetup? {
        guard let defaultSetupID else { return nil }
        return all.first { $0.id == defaultSetupID }
    }

    /// Saves a setup, replacing one of the same name.
    ///
    /// By name rather than adding another, because "save" on a setup you already
    /// have means update it — a list with four "Bold 4-bar" entries is how a
    /// preset system becomes useless.
    static func save(_ setup: MelGenSetup) {
        var stored = all
        if let index = stored.firstIndex(where: {
            $0.name.lowercased() == setup.name.lowercased()
        }) {
            // The id survives, so a setup that was the default stays the default
            // after being re-saved.
            var replacement = setup
            replacement.id = stored[index].id
            stored[index] = replacement
        } else {
            stored.append(setup)
        }
        write(stored)
    }

    static func remove(id: UUID) {
        write(all.filter { $0.id != id })
        if defaultSetupID == id { defaultSetupID = nil }
    }

    static func makeDefault(id: UUID?) {
        defaultSetupID = id
    }

    private static func write(_ setups: [MelGenSetup]) {
        guard let data = try? JSONEncoder().encode(setups) else { return }
        UserDefaults.standard.set(data, forKey: setupsKey)
    }
}
