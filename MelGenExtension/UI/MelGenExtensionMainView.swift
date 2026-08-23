//
//  MelGenExtensionMainView.swift
//  MelGenExtension
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

import SwiftUI
import UniformTypeIdentifiers

// No #Preview here: Xcode can't host previews inside a
// "com.apple.AudioUnit-UI" app extension, so the layout is checked in a host.

/// Wrapper so `fileExporter` can write already-encoded JSON straight out,
/// without a temp file or a share-sheet detour.
struct MelGenJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct MelGenExtensionMainView: View {
    var parameterTree: ObservableAUParameterGroup
    weak var audioUnit: MelGenExtensionAudioUnit?

    /// Mirror of the audio unit's session state. The audio unit owns the master
    /// copy so it survives this view and lands in the host's saved session.
    @State private var state = MelGenState()
    @State private var statusMessage: String?
    @State private var isGenerating = false
    @State private var savedExampleIDs: Set<UUID> = []

    /// A take generated ahead of time, waiting for a loop boundary to be swapped
    /// in. Deliberately not part of the saved session: it's in-flight work, and a
    /// reopened session should start from what was actually playing.
    @State private var pendingTake: GenerationRecord?
    @State private var pendingReadyPass: Int64 = 0

    @State private var isExporting = false
    @State private var exportDocument: MelGenJSONDocument?

    /// Whether the review sweep is unfolded. Not session state: it's about what
    /// you're doing right now, not what the document is.
    @State private var showCuration = false
    /// Same: which lines and briefs are in play is a session setting, but whether
    /// the drawer is open isn't.
    @State private var showRotation = false
    /// Redrawn when the library changes, since it lives outside the session state
    /// the rest of this view mirrors.
    @State private var libraryRevision = 0
    /// The store keeps hundreds of takes; the list shows a page of them. Bounding
    /// the store to what fits on screen was the actual mistake.
    @State private var historyRowLimit = 40
    /// The model diagnostic's results, when it has been run.
    @State private var probes: [MelodyGenerator.Probe] = []
    @State private var isProbing = false
    /// Whether the last thing that went wrong was the model, so the diagnostic
    /// appears when it's relevant and not before.
    @State private var lastFailureWasModel = false
    @State private var showRotationPicker = false
    @State private var showDrift = false

    /// Mutations of the current take, and the morph between it and one of them.
    /// Not session state: they're a working surface, regenerated on demand.
    @State private var variants: [MelodyVariant] = []
    @State private var variantParent: MelodyPattern?
    @State private var morphTarget: MelodyPattern?
    @State private var morphRhythm: Double = 0.5
    @State private var morphPitch: Double = 0.5
    @State private var showVariants = false

    /// What's been played in since capture was turned on, and whether it's on.
    /// Not session state: a recording buffer isn't a document.
    @State private var isListening = false
    @State private var capturedEvents: [CapturedMIDIEvent] = []
    @State private var showCapture = false
    @State private var showProgressionMaker = false
    /// The Roman numerals behind the current progression, when it was generated
    /// here. Worth showing: the numerals are what the corpus actually models, and
    /// the chord names are only one key's worth of them.
    @State private var generatedNumerals: String?

    /// Whatever appearance the host is offering, used only when the appearance
    /// setting is "Auto".
    @Environment(\.colorScheme) private var ambientScheme

    private var scheme: ColorScheme {
        switch state.appearance {
        case .light: return .light
        case .dark: return .dark
        case .system: return ambientScheme
        }
    }

    private var theme: MelGenTheme {
        MelGenTheme.resolved(for: scheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MelGenMetrics.space4) {
                header
                progressionSection

                // Directly under the control that produces it: at the bottom of
                // the view it sat hundreds of points from the Generate button and
                // went unread.
                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                modelDiagnostics

                nextTakeSection
                instantSection
                transportSection
                shapeSection
                lineLibrarySection
                feelSection
                driftSection

                if state.currentTake != nil {
                    currentTakeSection
                }

                captureSection
                curationSection
                if state.currentTake != nil {
                    variantsSection
                }
                historySection
            }
            .padding(MelGenMetrics.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Only scroll when there's something to scroll to. Left bouncing, a short
        // page still drags, and the header clips against the top edge mid-bounce.
        .scrollBounceBehavior(.basedOnSize)
        // The plug-in paints its own surface: left transparent, text contrast
        // would depend on the host's backdrop.
        .background(theme.background)
        .environment(\.colorScheme, scheme)
        .onAppear {
            if let audioUnit {
                state = audioUnit.state
            }
        }
        .task(id: state.autoRegenerate) {
            await runAutoRegeneration()
        }
        .task(id: isListening) {
            await collectPlaying()
        }
        // Drift runs on its own, not inside auto-regeneration: it's a property of
        // playing rather than of generating, and tying it to Auto meant it only
        // worked when something else was also happening.
        .task(id: state.liveMutation.isActive) {
            await runDrift()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("MelGen")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.text)

            Spacer(minLength: MelGenMetrics.space2)

            appearancePicker
        }
    }

    /// Labelled chips where there's room; icons alone in a narrow plug-in window,
    /// where the labels would otherwise push the title off screen. Both keep the
    /// same accessibility label.
    private var appearancePicker: some View {
        ViewThatFits(in: .horizontal) {
            appearanceChips(showLabels: true)
            appearanceChips(showLabels: false)
        }
    }

    private func appearanceChips(showLabels: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(MelGenAppearance.allCases, id: \.self) { option in
                let isSelected = state.appearance == option
                Button {
                    commit(reloadKernel: false) { $0.appearance = option }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: option.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                        if showLabels {
                            Text(option.label)
                                .font(.system(size: 12, weight: .medium))
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, showLabels ? MelGenMetrics.space2 : 10)
                    .frame(height: MelGenMetrics.smallControlHeight)
                    .foregroundStyle(isSelected ? theme.accentText : theme.textSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? theme.accent : theme.raised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? theme.accent : theme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.label) appearance")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    // MARK: - Progression

    /// The changes, and where they come from.
    ///
    /// Generating a progression sits directly under the field it fills in,
    /// because that is what it does. It used to be a collapsed section called
    /// "Make changes" three screens further down, which is both the wrong place
    /// and a name that reads as "edit something".
    private var progressionSection: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            Eyebrow(text: "Progression", theme: theme)

            TextField("E♭7 Gm9|D∆|A♭6", text: binding(\.progressionText, reloadKernel: false))
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(theme.text)
                .textFieldStyle(.plain)
                .padding(.horizontal, MelGenMetrics.space3)
                .frame(height: MelGenMetrics.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .fill(theme.sunken)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .strokeBorder(theme.borderStrong, lineWidth: 1.5)
                )
                .onSubmit { nextTake() }
                .accessibilityLabel("Chord progression")

            HStack(spacing: MelGenMetrics.space2) {
                Button {
                    makeChanges()
                } label: {
                    findLabel("Generate a progression", systemImage: "arrow.triangle.branch")
                }
                .buttonStyle(.plain)

                Button {
                    showProgressionMaker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showProgressionMaker ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(ChordProgression.flatNoteNames[state.progressionKey]) "
                             + "\(state.progressionMode.rawValue) · \(state.progressionBars) bars")
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, MelGenMetrics.space2)
                    .frame(height: MelGenMetrics.controlHeight)
                    .foregroundStyle(theme.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Progression settings")
            }

            if showProgressionMaker {
                progressionSettings
            }

            if let generatedNumerals {
                Text(generatedNumerals)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var progressionSettings: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            HStack(spacing: MelGenMetrics.space2) {
                ChipPicker(options: ProgressionMode.allCases.map { ($0, $0.label) },
                           selection: binding(\.progressionMode, reloadKernel: false),
                           theme: theme)
                    .frame(maxWidth: 160)
                ChipPicker(options: [(4, "4"), (8, "8"), (12, "12"), (16, "16")],
                           selection: binding(\.progressionBars, reloadKernel: false),
                           theme: theme)
                    .frame(maxWidth: 180)
            }

            FlowChips(items: ChordProgression.flatNoteNames,
                      isSelected: { $0 == ChordProgression.flatNoteNames[state.progressionKey] },
                      theme: theme) { name in
                guard let index = ChordProgression.flatNoteNames.firstIndex(of: name) else { return }
                commit(reloadKernel: false) { $0.progressionKey = index }
            }

            LabelledSlider(title: "Surprise",
                           lowLabel: "the usual",
                           highLabel: "further down",
                           value: binding(\.progressionSurprise, reloadKernel: false),
                           theme: theme)

            labelledRow("Freshness") {
                ChipPicker(options: Freshness.allCases.map { ($0, $0.label) },
                           selection: binding(\.progressionFreshness, reloadKernel: false),
                           theme: theme)
            }

            labelledRow("Context") {
                ChipPicker(options: [(1, "1 chord"), (2, "2 chords")],
                           selection: binding(\.progressionContext, reloadKernel: false),
                           theme: theme)
            }

            labelledRow("Reharm") {
                ChipPicker(options: Reharm.allCases.map { ($0, $0.label) },
                           selection: binding(\.progressionReharm, reloadKernel: false),
                           theme: theme)
            }

            labelledRow("Modulate") {
                ChipPicker(options: [(0, "Never"), (4, "4 bars"), (8, "8 bars")],
                           selection: binding(\.progressionModulation, reloadKernel: false),
                           theme: theme)
            }

            Text("Surprise reaches further down each transition's list rather than "
                 + "flattening it. Freshness discounts the moves everyone makes — "
                 + "repeats, quick returns, rote V→I. Context is how much history the "
                 + "walk leans on. Reharm rewrites chords afterwards: subtle keeps the "
                 + "route and changes how you get there, bold changes the colour too.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Diagnosing the model

    /// Offered only once the model has actually failed, and then insistently.
    ///
    /// "The model doesn't work any more" is a claim about a path with four
    /// independent parts, and which part broke can't be read off an error
    /// message. This asks the model four progressively larger questions and says
    /// which it can answer, so the answer is evidence rather than a guess.
    @ViewBuilder
    private var modelDiagnostics: some View {
        if lastFailureWasModel || !probes.isEmpty {
            VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
                Button {
                    runDiagnostics()
                } label: {
                    findLabel(isProbing ? "Testing…" : "Test the model",
                              systemImage: "stethoscope",
                              detail: "four questions, smallest first")
                }
                .buttonStyle(.plain)
                .disabled(isProbing)

                if !probes.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(probes.enumerated()), id: \.offset) { _, probe in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: probe.succeeded ? "checkmark.circle" : "xmark.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(probe.succeeded ? theme.accent : theme.warning)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(probe.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(theme.text)
                                    Text(probe.detail)
                                        .font(.system(size: 10))
                                        .foregroundStyle(theme.textMuted)
                                    if !probe.succeeded {
                                        Text(probe.message)
                                            .font(.system(size: 10))
                                            .foregroundStyle(theme.textMuted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }

                        Text(MelodyGenerator.verdict(for: probes))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    .padding(MelGenMetrics.space2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .fill(theme.raised)
                    )
                }
            }
        }
    }

    private func runDiagnostics() {
        isProbing = true
        probes = []
        Task {
            let progression = try? ChordProgression.parse(liveState.progressionText)
            probes = await MelodyGenerator.diagnose(progression: progression)
            isProbing = false
        }
    }

    /// A label and a control on one line, which the settings needed and the
    /// chip pickers didn't provide — a row of unlabelled chips says nothing about
    /// what it's a row of.
    private func labelledRow<Content: View>(_ title: String,
                                            @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: MelGenMetrics.space2) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.text)
                .frame(width: 80, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    // MARK: - The next take

    /// One control for "what comes next", whichever kind of thing that is.
    ///
    /// Line or chords is the first decision because it changes every one below
    /// it, so it comes first. The templates under it are whichever set matches —
    /// style briefs for a line, comping figures for chords — through one
    /// rotation rather than two.
    private var nextTakeSection: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            Eyebrow(text: "Next take", theme: theme)

            HStack(spacing: MelGenMetrics.space2) {
                ChipPicker(options: PlayMode.allCases.map { ($0, $0.label) },
                           selection: binding(\.mode, reloadKernel: false),
                           theme: theme)
                    .frame(maxWidth: 200)
                Text(state.mode.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: MelGenMetrics.space2) {
                Button {
                    nextTake()
                } label: {
                    HStack(spacing: 6) {
                        if isGenerating {
                            ProgressView().controlSize(.small).tint(theme.accentText)
                        } else {
                            Image(systemName: state.mode == .line ? "wand.and.stars" : "pianokeys")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(isGenerating ? "Working" : (state.mode == .line ? "Generate" : "Comp"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, MelGenMetrics.space3)
                    .frame(height: MelGenMetrics.controlHeight)
                    .foregroundStyle(nextTakeEnabled ? theme.accentText : theme.textDisabled)
                    .background(
                        RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .fill(nextTakeEnabled ? theme.accent : theme.sunken)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!nextTakeEnabled)

                Text(state.nextTemplate.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Spacer(minLength: 0)

                ChipPicker(options: SelectionMode.allCases.map { ($0, $0.label) },
                           selection: binding(\.briefMode, reloadKernel: false),
                           theme: theme)
                    .frame(maxWidth: 200)
            }

            // Tapping a template *uses* it. That was the question the last
            // session ended on — "how do I select a specific template?" — and the
            // answer was "switch to Lock, then tap", which is not an answer. A
            // list of things you can pick from should pick one when you pick one.
            FlowChips(items: MelGenTemplates.all(for: state.mode).map(\.name),
                      isSelected: { $0 == state.nextTemplate.name },
                      isPinned: { state.briefMode == .lock && state.lockedBriefName == $0 },
                      theme: theme) { name in
                useTemplate(name)
            }

            Text(state.briefMode == .lock
                 ? "Pinned. Cycle or Shuffle to move on."
                 : "Tap one to use it next. Cycle and Shuffle move through whichever are in the rotation.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)

            Text(state.nextTemplate.summary)
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showRotationPicker.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showRotationPicker ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(state.selectedBriefNames.isEmpty
                         ? "All \(MelGenTemplates.all(for: state.mode).count) in the rotation"
                         : "\(state.selectedBriefNames.count) in the rotation")
                        .font(.system(size: 11))
                }
                .foregroundStyle(theme.textMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Curating the rotation is a different job from choosing what's next,
            // and doing both with one control is what made neither discoverable.
            if showRotationPicker {
                FlowChips(items: MelGenTemplates.all(for: state.mode).map(\.name),
                          isSelected: { name in
                              state.selectedBriefNames.isEmpty
                                  || state.selectedBriefNames.contains(name)
                          },
                          theme: theme) { name in
                    toggleTemplate(name)
                }
                Text("Which templates Cycle and Shuffle draw from.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }
        }
    }

    /// A draw from the musician's own material, with the choice of which model.
    @ViewBuilder
    private var sampleStyleButton: some View {
        let kept = state.curatedTakes.count
        let ready = kept >= 3
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: MelGenMetrics.space2) {
                Button {
                    sampleLearnedStyle()
                } label: {
                    findLabel("Draw from your style", systemImage: "waveform.path.ecg",
                              detail: ready ? "from \(kept) kept" : "keep three takes first")
                }
                .buttonStyle(.plain)
                .disabled(!ready || state.progressionText.isEmpty)

                ChipPicker(options: LearnedDraw.allCases.map { ($0, $0.label) },
                           selection: binding(\.learnedDraw, reloadKernel: false),
                           theme: theme)
                    .frame(maxWidth: 200)
            }
            Text(state.learnedDraw.explanation)
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Lays voicings under the progression and plays them.
    ///
    /// No model involved, and none wanted: comping is a voicing policy and a
    /// rhythm, both of which are decisions rather than guesses.
    private func compChanges() {
        let current = liveState
        guard let progression = try? ChordProgression.parse(current.progressionText) else {
            statusMessage = "That progression doesn't parse."
            return
        }
        let template = current.nextTemplate
        let figure = template.figure ?? CompingFigure.charleston
        let notes = MelodyComping.comp(progression,
                                       figure: figure,
                                       seed: UInt64(bitPattern: Int64(current.briefCursor &* 2_246_822_519)))
        guard !notes.isEmpty else {
            statusMessage = "Nothing to comp — check the progression."
            return
        }

        let record = GenerationRecord(
            progressionText: current.progressionText,
            temperature: current.temperature,
            briefName: "\(figure.name) · \(figure.style.label)",
            density: current.expression.density,
            durationPalette: current.durationPalette,
            source: .comping,
            analysis: MelodyAnalyser.analyse(notes, over: progression),
            lengthBeats: progression.totalBeats,
            notes: notes
        )
        commit {
            $0.add(record)
            $0.briefCursor += 1
        }
        statusMessage = "\(figure.name): \(notes.count) notes, up to "
            + "\(MelodyComping.maximumPolyphony(of: notes)) voices. \(figure.summary)."
    }

    private var nextTakeEnabled: Bool {
        guard !state.progressionText.isEmpty, !isGenerating else { return false }
        // Comping needs no model, so it's available whatever the model is doing.
        return state.mode == .comping || generateEnabled
    }

    /// Makes a template the next one, whatever mode the rotation is in.
    ///
    /// Pins it, because "use this one" and "keep using this one" are the same
    /// wish nine times in ten, and Cycle or Shuffle un-pins it again. Tapping the
    /// pinned one lets go.
    private func useTemplate(_ name: String) {
        commit(reloadKernel: false) { state in
            if state.briefMode == .lock, state.lockedBriefName == name {
                state.lockedBriefName = nil
                state.briefMode = .cycle
                return
            }
            state.lockedBriefName = name
            state.briefMode = .lock
            // Anything you pick has to be in the rotation, or letting go of the
            // pin would skip straight past it.
            if !state.selectedBriefNames.isEmpty, !state.selectedBriefNames.contains(name) {
                state.selectedBriefNames.append(name)
            }
        }
    }

    private func toggleTemplate(_ name: String) {
        let available = MelGenTemplates.all(for: liveState.mode).map(\.name)
        commit(reloadKernel: false) { state in
            if state.briefMode == .lock {
                state.lockedBriefName = state.lockedBriefName == name ? nil : name
                return
            }
            var selection = state.selectedBriefNames.isEmpty
                ? available
                : state.selectedBriefNames.filter { available.contains($0) }
            if selection.isEmpty { selection = available }
            if let index = selection.firstIndex(of: name) {
                // Never empty the set: an empty rotation has nothing to play.
                if selection.count > 1 { selection.remove(at: index) }
            } else {
                selection.append(name)
            }
            state.selectedBriefNames = selection.count == available.count ? [] : selection
        }
    }

    /// The one "what comes next" action, which does whichever thing the mode says.
    private func nextTake() {
        if liveState.mode == .comping {
            compChanges()
        } else {
            generate()
        }
    }

    // MARK: - Instant sources

    /// Everything that answers immediately, gathered and labelled as such.
    ///
    /// They were spread down the view as differently-shaped buttons with no
    /// indication that they had anything in common. What they have in common is
    /// the only thing worth knowing about them: none of them waits for a model.
    private var instantSection: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            Eyebrow(text: "Instant · no model", theme: theme)

            HStack(spacing: MelGenMetrics.space2) {
                Button { adaptStoredLine() } label: {
                    findLabel("Stored line", systemImage: "bolt.fill",
                              detail: state.nextLine(from: PatternStore.library).name)
                }
                .buttonStyle(.plain)
                .disabled(state.progressionText.isEmpty)

                Button { composeLine() } label: {
                    findLabel("Compose", systemImage: "wand.and.stars", detail: "new every time")
                }
                .buttonStyle(.plain)
                .disabled(state.progressionText.isEmpty)
            }

            HStack(spacing: MelGenMetrics.space2) {
                Button { playBestFittingLine() } label: {
                    findLabel("Fits these changes", systemImage: "target")
                }
                .buttonStyle(.plain)
                .disabled(state.progressionText.isEmpty)

                Button { surpriseMe() } label: {
                    findLabel("Surprise me", systemImage: "dice")
                }
                .buttonStyle(.plain)
                .disabled(state.progressionText.isEmpty)
            }

            sampleStyleButton
        }
    }

    private var generateEnabled: Bool {
        !isGenerating && !state.progressionText.isEmpty
    }

    // MARK: - Generating the changes

    private func makeChanges() {
        let current = liveState
        let seed = UInt64(bitPattern: Int64(current.progressionCursor &* 6_364_136_223 &+ 17))
        guard let generated = ProgressionGenerator.generate(
            bars: current.progressionBars,
            key: current.progressionKey,
            mode: current.progressionMode,
            surprise: Surprise(current.progressionSurprise),
            freshness: current.progressionFreshness,
            contextDepth: current.progressionContext,
            reharm: current.progressionReharm,
            modulateEvery: current.progressionModulation,
            seed: seed
        ) else {
            statusMessage = "Couldn't generate changes — the corpus tables are missing."
            return
        }

        commit(reloadKernel: false) {
            $0.progressionText = generated.text
            $0.progressionCursor += 1
        }
        generatedNumerals = generated.labels.joined(separator: "  ")
        statusMessage = "\(generated.summary). Generate or fit a line over it."
    }

    // MARK: - Transport

    private var transportSection: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            HStack {
                Eyebrow(text: "Transport", theme: theme)
                Spacer(minLength: 0)
                Text(directionName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textMuted)
            }

            HStack(spacing: MelGenMetrics.space2) {
                playButton

                HStack(spacing: 4) {
                    DirectionButton(direction: .backward, label: "Backward",
                                    isSelected: direction == MelGenPlaybackDirection.backward.rawValue,
                                    theme: theme) {
                        setDirection(.backward)
                    }
                    DirectionButton(direction: .pingPong, label: "Ping-pong",
                                    isSelected: direction == MelGenPlaybackDirection.pingPong.rawValue,
                                    theme: theme) {
                        setDirection(.pingPong)
                    }
                    DirectionButton(direction: .forward, label: "Forward",
                                    isSelected: direction == MelGenPlaybackDirection.forward.rawValue,
                                    theme: theme) {
                        setDirection(.forward)
                    }
                }
                // Capped: a small arrow centred in a 400pt button looks broken in
                // a wide plug-in window.
                .frame(maxWidth: 240)

                Spacer(minLength: 0)
            }

            HStack(spacing: MelGenMetrics.space2) {
                ToggleChip(title: "Host sync", systemImage: "metronome",
                           isOn: hostSyncBinding, theme: theme)
                ToggleChip(title: "Auto", systemImage: "arrow.trianglehead.2.clockwise",
                           isOn: binding(\.autoRegenerate, reloadKernel: false), theme: theme)
                Spacer(minLength: 0)
            }

            // Sits with Auto, which is the only thing it affects.
            if state.autoRegenerate {
                HStack(spacing: MelGenMetrics.space2) {
                    Text("New take every")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text)
                    ChipPicker(
                        options: [(1, "loop"), (2, "2 loops"), (4, "4 loops"), (8, "8 loops")],
                        selection: binding(\.regenerateEveryPasses, reloadKernel: false),
                        theme: theme
                    )
                    .frame(maxWidth: 320)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var playButton: some View {
        let isPlaying = playParameter.boolValue
        return Button {
            playParameter.boolValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(isPlaying ? "Stop" : "Play")
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, MelGenMetrics.space4)
            .frame(height: MelGenMetrics.controlHeight)
            .foregroundStyle(theme.accentText)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(theme.accent)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Stop" : "Play")
    }

    private var directionName: String {
        switch direction {
        case MelGenPlaybackDirection.backward.rawValue: return "Backward"
        case MelGenPlaybackDirection.pingPong.rawValue: return "Ping-pong"
        default: return "Forward"
        }
    }

    // MARK: - Shape (applies to the next take)

    /// Controls the model acts on. Grouped separately from Feel because these
    /// only take effect when something is generated, and that distinction is the
    /// one thing worth knowing before touching a control here.
    private var shapeSection: some View {
        CollapsibleSection(title: "Shape · next take",
                           summary: shapeSummary,
                           isExpanded: binding(\.showShape, reloadKernel: false),
                           theme: theme) {
            VStack(alignment: .leading, spacing: MelGenMetrics.space3) {
                LabelledSlider(title: "Density", lowLabel: "sparse", highLabel: "dense",
                               value: binding(\.expression.density), theme: theme,
                               format: { "\(MelodyExpression.notesPerBar(forDensity: $0))/bar" })

                LabelledSlider(title: "Temperature", lowLabel: "expected", highLabel: "surprising",
                               value: binding(\.temperature, reloadKernel: false), theme: theme)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Note duration")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.text)
                    ChipPicker(
                        options: DurationPalette.allCases.map { ($0, $0.label) },
                        selection: binding(\.durationPalette, reloadKernel: false),
                        theme: theme
                    )
                    Text("The written rhythm. Gate length, under Feel, is separate.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                }
            }
        }
    }

    private var shapeSummary: String {
        "\(MelodyExpression.notesPerBar(forDensity: state.expression.density))/bar · "
        + state.durationPalette.label.lowercased()
    }

    // MARK: - Feel (applies to the take already loaded)

    /// Controls that re-render the current take immediately, since they are
    /// post-processing over its stored notes rather than part of generation.
    private var feelSection: some View {
        CollapsibleSection(title: "Feel · live",
                           summary: feelSummary,
                           isExpanded: binding(\.showFeel, reloadKernel: false),
                           theme: theme) {
            VStack(alignment: .leading, spacing: MelGenMetrics.space3) {
                // The three sliders own three separate things, which isn't
                // obvious from their names alone.
                Text("Three separate things: Gate is note length, Expression is "
                     + "velocity and timing, Swing shifts offbeats.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 2) {
                    LabelledSlider(title: "Gate length", lowLabel: "staccato", highLabel: "legato",
                                   value: binding(\.expression.noteLength), theme: theme)
                    Text("Shaped per note: steps connect, leaps and repeats detach. "
                         + "Rests are never filled in. See the gate range under Current take.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabelledSlider(title: "Expression", lowLabel: "flat", highLabel: "shaped",
                               value: binding(\.expression.amount), theme: theme)

                LabelledSlider(title: "Swing", lowLabel: "straight", highLabel: "swung",
                               value: binding(\.expression.swing), theme: theme)
            }
        }
    }

    private var feelSummary: String {
        let gate = state.expression.noteLength
        let name = gate < 0.45 ? "staccato" : (gate > 0.55 ? "legato" : "as written")
        return "gate \(name) · swing \(state.expression.swing.formatted(.number.precision(.fractionLength(2))))"
    }

    // MARK: - Drift

    /// Probabilities that re-roll every pass, so the loop moves while it plays.
    ///
    /// The rest of the plug-in gives you a new take to judge, which is the right
    /// shape for deciding what to keep and the wrong one for playing. This is the
    /// hardware-sequencer control: you steer by how much it drifts rather than by
    /// choosing between candidates. Nothing here is written back to the take.
    private var driftSection: some View {
        CollapsibleSection(title: "Drift · live",
                           summary: state.liveMutation.summary,
                           isExpanded: $showDrift,
                           theme: theme) {
            VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
                LabelledSlider(title: "Note order", lowLabel: "fixed", highLabel: "shuffled",
                               value: binding(\.liveMutation.noteOrder), theme: theme,
                               format: { "\(Int($0 * 100))%" })
                LabelledSlider(title: "Accents", lowLabel: "as played", highLabel: "moving",
                               value: binding(\.liveMutation.accents), theme: theme,
                               format: { "\(Int($0 * 100))%" })
                LabelledSlider(title: "Slides", lowLabel: "none", highLabel: "everywhere",
                               value: binding(\.liveMutation.slides), theme: theme,
                               format: { "\(Int($0 * 100))%" })
                LabelledSlider(title: "Skip", lowLabel: "every note", highLabel: "sparse",
                               value: binding(\.liveMutation.skipSteps), theme: theme,
                               format: { "\(Int($0 * 100))%" })
                LabelledSlider(title: "Octaves", lowLabel: "in place", highLabel: "leaping",
                               value: binding(\.liveMutation.octaves), theme: theme,
                               format: { "\(Int($0 * 100))%" })

                Text("Re-rolled every time the loop comes round, and seeded by which pass "
                     + "it is — so a pass that sounded good can be got back rather than "
                     + "being gone. Pass \(state.mutationPass).")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: MelGenMetrics.space2) {
                    Button {
                        commit { $0.mutationPass -= 1 }
                    } label: {
                        findLabel("Previous pass", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.plain)
                    .disabled(!state.liveMutation.isActive)

                    Button {
                        keepThisPass()
                    } label: {
                        findLabel("Keep this pass", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.plain)
                    .disabled(!state.liveMutation.isActive)
                }
            }
        }
    }

    /// Re-rolls the drift on every loop boundary.
    ///
    /// A quarter of a second is far shorter than any loop and costs nothing; the
    /// alternative is a callback from the render thread, which would mean the
    /// audio thread waiting on the interface.
    private func runDrift() async {
        guard state.liveMutation.isActive else { return }
        var lastPass = audioUnit?.currentPass ?? 0
        while !Task.isCancelled, liveState.liveMutation.isActive {
            try? await Task.sleep(for: .milliseconds(250))
            guard let pass = audioUnit?.currentPass, pass != lastPass else { continue }
            lastPass = pass
            commit { $0.mutationPass += 1 }
        }
    }

    /// Freezes the drifted loop as a take of its own.
    ///
    /// The drift is a performance and doesn't touch the take, which is right
    /// until the moment a pass comes out better than what it was performing.
    private func keepThisPass() {
        let current = liveState
        guard let take = current.currentTake else { return }
        let notes = current.renderedMelody
        guard !notes.isEmpty else { return }

        let record = GenerationRecord(
            progressionText: take.progressionText,
            temperature: take.temperature,
            briefName: "\(take.briefName) · pass \(current.mutationPass)",
            density: take.density,
            durationPalette: take.durationPalette,
            source: take.source,
            analysis: (try? ChordProgression.parse(take.progressionText))
                .map { MelodyAnalyser.analyse(notes, over: $0) },
            lengthBeats: take.lengthBeats,
            notes: notes
        )
        commit { $0.add(record) }
        statusMessage = "Pass \(current.mutationPass) kept as a take of its own."
    }

    // MARK: - Current take

    private var currentTakeSection: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            Eyebrow(text: "Current take", theme: theme)

            VStack(alignment: .leading, spacing: 4) {
                // The roll first, because it shows what the grid can't: gate
                // length below an eighth, and two voices at once.
                PianoRoll(notes: state.renderedMelody,
                          progression: try? ChordProgression.parse(state.progressionText),
                          lengthBeats: state.currentTake?.lengthBeats ?? 0,
                          theme: theme)

                Text(takeSummary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.textMuted)

                if let analysis = state.currentTake?.analysis {
                    Text(analysis.summary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MelGenMetrics.space2)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(theme.raised)
            )

            if let take = state.currentTake {
                curationControls(for: take)
            }

            if let take = state.currentTake {
                let saved = savedExampleIDs.contains(take.id)
                Button {
                    PatternLibrary.addUserExample(progression: take.progressionText, notes: take.notes)
                    savedExampleIDs.insert(take.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: saved ? "checkmark" : "square.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                        Text(saved ? "Saved as example" : "Save as example")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, MelGenMetrics.space3)
                    .frame(height: MelGenMetrics.controlHeight)
                    .foregroundStyle(saved ? theme.textMuted : theme.text)
                    .background(
                        RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .fill(theme.raised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .strokeBorder(theme.borderStrong, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(saved)
            }
        }
    }

    // MARK: - Curation

    /// One tap per take, while you're listening to it.
    ///
    /// This is the whole interaction: hear it, say what you want to happen to it,
    /// move on. Everything else in the section exists so that saying it once
    /// doesn't have to be the last word.
    @ViewBuilder
    private func curationControls(for take: GenerationRecord) -> some View {
        let mark = take.mark(onPass: state.curationPass)

        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            HStack(spacing: MelGenMetrics.space2) {
                Eyebrow(text: "Pass \(state.curationPass)", theme: theme)
                FacetChips(facets: take.facets, theme: theme)
                Spacer(minLength: 0)
            }

            DispositionBar(current: mark?.disposition, theme: theme) { disposition in
                commit(reloadKernel: false) { state in
                    if let disposition {
                        state.mark(take.id, as: disposition, aspects: mark?.aspects ?? [])
                    } else {
                        state.unmark(take.id)
                    }
                }
                statusMessage = disposition.map { "\($0.label) — pass \(state.curationPass)." }
            }

            // Only asked when it's the question: "part of it works" is the one
            // disposition that's incomplete on its own.
            if mark?.disposition == .partial {
                AspectPicker(selected: mark?.aspects ?? [], theme: theme) { aspect in
                    var aspects = mark?.aspects ?? []
                    if let index = aspects.firstIndex(of: aspect) {
                        aspects.remove(at: index)
                    } else {
                        aspects.append(aspect)
                    }
                    commit(reloadKernel: false) { state in
                        state.mark(take.id, as: .partial, aspects: aspects)
                    }
                }
            }

            TagField(tags: take.tags,
                     suggestions: state.tagVocabulary.suggestions,
                     theme: theme) { tags in
                commit(reloadKernel: false) { $0.setTags(tags, for: take.id) }
            }

            keepAsLineButton(for: take)
        }
    }

    /// The payoff of the whole loop: a take you liked becomes a line you can
    /// play over anything, instantly, with no model involved.
    private func keepAsLineButton(for take: GenerationRecord) -> some View {
        Button {
            keepAsLine(take)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 13, weight: .semibold))
                Text("Keep as a line")
                    .font(.system(size: 13, weight: .medium))
                Text("plays over any changes")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }
            .padding(.horizontal, MelGenMetrics.space3)
            .frame(height: MelGenMetrics.controlHeight)
            .foregroundStyle(theme.text)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(theme.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .strokeBorder(theme.borderStrong, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Reads this take back as scale degrees and adds it to the line library")
    }

    /// Reads a take back as degrees and stores it (ROADMAP R1/R2).
    private func keepAsLine(_ take: GenerationRecord) {
        let progression: ChordProgression
        do {
            progression = try ChordProgression.parse(take.progressionText)
        } catch {
            statusMessage = "Can't read that take's progression back: \(error.localizedDescription)"
            return
        }

        let name = take.title.isEmpty ? "\(take.briefName) line" : take.title
        guard let pattern = MelodyPatterns.extract(
            from: take.notes,
            over: progression,
            name: name,
            lengthBeats: take.lengthBeats,
            origin: PatternOrigin(takeID: take.id,
                                  progressionText: take.progressionText,
                                  briefName: take.briefName,
                                  source: take.source)
        ) else {
            statusMessage = "Nothing in that take could be placed against a chord."
            return
        }

        let stored = PatternStore.add(pattern)
        libraryRevision += 1
        statusMessage = "Kept as \"\(stored.name)\" — \(stored.summary). It's in the rotation now."
    }

    // MARK: - Listening

    /// Learning from what's played in, rather than only from what's generated.
    ///
    /// The two learned models were written so that adding material is `add` and
    /// nothing else, which is why this is a section rather than a subsystem: get
    /// the notes off the wire, split them at the silences, read them back as
    /// degrees against the progression that was on screen, and hand them to the
    /// same two methods the kept takes go to.
    private var captureSection: some View {
        CollapsibleSection(title: "Listen",
                           summary: isListening
                               ? "listening · \(capturedEvents.filter(\.isOn).count) notes"
                               : (capturedEvents.isEmpty ? "off" : "\(capturedEvents.filter(\.isOn).count) notes held"),
                           isExpanded: $showCapture,
                           theme: theme) {
            VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
                ToggleChip(title: isListening ? "Listening" : "Listen to what I play",
                           systemImage: isListening ? "waveform.circle.fill" : "waveform.circle",
                           isOn: Binding(get: { isListening },
                                         set: { isListening = $0 }),
                           theme: theme)

                Text("MIDI coming in still passes through untouched. This only "
                     + "watches it — and only while it's on.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if !capturedEvents.isEmpty {
                    capturedReadout
                }
            }
        }
    }

    @ViewBuilder
    private var capturedReadout: some View {
        let sounded = MelodyCapture.notes(from: capturedEvents)
        let phrases = MelodyCapture.phrases(from: sounded)

        VStack(alignment: .leading, spacing: 4) {
            Text("\(sounded.count) notes · \(phrases.count) phrase\(phrases.count == 1 ? "" : "s")")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.textSecondary)

            ForEach(phrases) { phrase in
                Text("· \(phrase.summary)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.textMuted)
            }

            HStack(spacing: MelGenMetrics.space2) {
                Button {
                    learnFromPlaying()
                } label: {
                    findLabel("Learn from it", systemImage: "brain")
                }
                .buttonStyle(.plain)
                .disabled(phrases.isEmpty)

                Button {
                    capturedEvents = []
                    statusMessage = "Cleared what was played in."
                } label: {
                    findLabel("Clear", systemImage: "trash")
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Polls the kernel's capture ring while listening is on.
    ///
    /// A quarter of a second is far longer than the ring needs and far shorter
    /// than a phrase, which is the whole requirement: the render thread never
    /// waits for this, and nothing gets lost between polls unless someone plays
    /// a thousand events in 250ms.
    private func collectPlaying() async {
        guard isListening else { return }
        audioUnit?.isCapturing = true
        defer { audioUnit?.isCapturing = false }

        while !Task.isCancelled, isListening {
            try? await Task.sleep(for: .milliseconds(250))
            let fresh = audioUnit?.drainCapturedEvents() ?? []
            if !fresh.isEmpty { capturedEvents.append(contentsOf: fresh) }
        }
    }

    /// Turns what was played into library material and into both learned models.
    private func learnFromPlaying() {
        let current = liveState
        guard let progression = try? ChordProgression.parse(current.progressionText) else {
            statusMessage = "Set a progression first — a played phrase needs harmony to be read against."
            return
        }

        let patterns = MelodyCapture.learn(from: capturedEvents, over: progression)
        guard !patterns.isEmpty else {
            statusMessage = "Nothing long enough to be a phrase yet — play a few more notes."
            return
        }

        for pattern in patterns { PatternStore.add(pattern) }
        libraryRevision += 1

        // The first phrase is loaded so it can be heard and judged like anything
        // else, which is what puts captured material into the same curation loop
        // as everything the plug-in made itself.
        if let first = patterns.first {
            play(first,
                 describedAs: "\(patterns.count) phrase\(patterns.count == 1 ? "" : "s") learned from your playing",
                 source: .captured)
        }
        capturedEvents = []
    }

    // MARK: - Variants

    /// Curation pointed at variants rather than at takes.
    ///
    /// Take a line, produce a dozen mutations of it, score them against what's
    /// been kept, hear the survivors — then dial between two you like and mark
    /// the point where it becomes the thing you wanted. The slider generates
    /// candidates, the dispositions are the fitness function, and the pass
    /// structure means the answer is allowed to change next week.
    private var variantsSection: some View {
        CollapsibleSection(title: "Variants · from the current take",
                           summary: variants.isEmpty ? "not explored" : "\(variants.count) offered",
                           isExpanded: $showVariants,
                           theme: theme) {
            VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
                Button {
                    exploreVariants()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.hexagongrid")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Explore variants")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, MelGenMetrics.space3)
                    .frame(height: MelGenMetrics.controlHeight)
                    .foregroundStyle(theme.text)
                    .background(
                        RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .fill(theme.raised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .strokeBorder(theme.borderStrong, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)

                if variants.isEmpty {
                    Text("One transform each: rhythm, pitch, density and register move "
                         + "separately, so a variant that works can be traced to the thing "
                         + "that made it work.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 3) {
                        ForEach(variants.prefix(8)) { variant in
                            VariantRow(variant: variant, theme: theme) {
                                play(variant)
                            } onMorphTarget: {
                                // Only a line has a degree-relative form to morph
                                // through; a comp's variants are the morph.
                                if let pattern = variant.material.patternIfLine {
                                    morphTarget = pattern
                                    morphRhythm = 0.5
                                    morphPitch = 0.5
                                }
                            }
                        }
                    }
                    morphControl
                }
            }
        }
    }

    @ViewBuilder
    private var morphControl: some View {
        if let parent = variantParent, let target = morphTarget {
            let morphed = MelodyMorph.between(parent, target,
                                              rhythmMix: morphRhythm, pitchMix: morphPitch)
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Morph", theme: theme)
                Text("\(parent.name)  →  \(target.name)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)

                // Two axes, because "keep this rhythm and take those pitches" is
                // the instruction anyone actually has, and one slider hides it.
                LabelledSlider(title: "Rhythm", lowLabel: "this", highLabel: "that",
                               value: $morphRhythm, theme: theme,
                               format: { "\(Int($0 * 100))%" })
                LabelledSlider(title: "Pitch", lowLabel: "this", highLabel: "that",
                               value: $morphPitch, theme: theme,
                               format: { "\(Int($0 * 100))%" })

                // Seen before it's heard: the whole difficulty with a morph is
                // that the interesting point is somewhere in the middle and
                // there's no way to find it by pressing a button repeatedly.
                if let changes = try? ChordProgression.parse(state.progressionText) {
                    PianoRoll(notes: MelodyPatterns.realize(morphed, over: changes),
                              progression: changes,
                              lengthBeats: Double(morphed.bars) * 4,
                              theme: theme,
                              height: 110)
                }

                Text(morphed.summary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.textMuted)

                HStack(spacing: MelGenMetrics.space2) {
                    Button {
                        play(morphed, describedAs: "morph, rhythm \(Int(morphRhythm * 100))% "
                             + "pitch \(Int(morphPitch * 100))%")
                    } label: {
                        findLabel("Hear this point", systemImage: "play.circle")
                    }
                    .buttonStyle(.plain)

                    Button {
                        swap(&variantParent, &morphTarget)
                    } label: {
                        findLabel("Swap ends", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Varies the current take, in whichever way its kind of take can be varied.
    private func exploreVariants() {
        let current = liveState
        guard let take = current.currentTake,
              let progression = try? ChordProgression.parse(take.progressionText) else {
            statusMessage = "Nothing to vary — load a take first."
            return
        }

        // A comp varies as a comp. Reading it back through degree extraction —
        // which is monophonic by construction — was turning every chord into a
        // single note before the first transform ran.
        if take.source == .comping {
            let figure = CompingFigure.named(
                take.briefName.components(separatedBy: " · ").first ?? "")
            let voiced = MelodyComping.variants(of: progression,
                                                figure: figure,
                                                seed: take.id.uuidStableSeed)
            let parentKeys = Set(take.notes.map { "\($0.note):\($0.startBeat)" })
            variantParent = nil
            morphTarget = nil
            variants = voiced.map { entry in
                let keys = Set(entry.notes.map { "\($0.note):\($0.startBeat)" })
                let union = parentKeys.union(keys).count
                return MelodyVariant(
                    voiced: entry.notes,
                    name: entry.name,
                    summary: entry.summary,
                    transform: entry.name,
                    novelty: union > 0 ? 1 - Double(parentKeys.intersection(keys).count) / Double(union) : 0,
                    variety: min(1, Double(MelodyComping.maximumPolyphony(of: entry.notes)) / 5)
                )
            }
            statusMessage = "\(variants.count) ways to comp these changes."
            return
        }

        guard let pattern = MelodyPatterns.extract(from: take.notes,
                                                   over: progression,
                                                   name: take.displayName,
                                                   lengthBeats: take.lengthBeats)
        else {
            statusMessage = "That take couldn't be read back as a pattern."
            return
        }

        let style = StyleLearner.learn(from: current.curatedTakes)
        variantParent = pattern
        variants = MelodyVariants.explore(pattern,
                                          seed: take.id.uuidStableSeed,
                                          style: style.isEmpty ? nil : style)
        morphTarget = variants.first?.pattern
        statusMessage = "\(variants.count) variants of \(pattern.name)."
    }

    /// Plays a variant, whichever kind it is.
    private func play(_ variant: MelodyVariant) {
        switch variant.material {
        case .line(let pattern):
            play(pattern, describedAs: variant.transform)
        case .voiced(let notes, let summary):
            playVoiced(notes, named: variant.name, describedAs: summary)
        }
    }

    /// Commits already-realized polyphonic notes as a take.
    private func playVoiced(_ notes: [SequencedNote], named name: String, describedAs detail: String) {
        let current = liveState
        guard let progression = try? ChordProgression.parse(current.progressionText),
              !notes.isEmpty else { return }
        let record = GenerationRecord(
            progressionText: current.progressionText,
            temperature: current.temperature,
            briefName: name,
            density: current.expression.density,
            durationPalette: current.durationPalette,
            source: .comping,
            analysis: MelodyAnalyser.analyse(notes, over: progression),
            lengthBeats: progression.totalBeats,
            notes: notes
        )
        commit { $0.add(record) }
        statusMessage = "\(name) — \(detail)."
    }

    /// Commits a pattern as a take so it can be heard and judged like any other.
    private func play(_ pattern: MelodyPattern,
                      describedAs description: String,
                      source: TakeSource = .mutated) {
        let current = liveState
        guard let progression = try? ChordProgression.parse(current.progressionText) else { return }
        let notes = MelodyPatterns.realize(pattern, over: progression)
        guard !notes.isEmpty else {
            statusMessage = "That variant didn't fit this progression."
            return
        }

        let record = GenerationRecord(
            progressionText: current.progressionText,
            temperature: current.temperature,
            briefName: pattern.name,
            density: current.expression.density,
            durationPalette: current.durationPalette,
            source: source,
            analysis: MelodyAnalyser.analyse(notes, over: progression),
            lengthBeats: progression.totalBeats,
            notes: notes
        )
        commit { $0.add(record) }
        statusMessage = "\(description) — judge it like anything else."
    }

    // MARK: - Rotation

    private func findLabel(_ title: String,
                          systemImage: String,
                          detail: String? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, MelGenMetrics.space3)
        .frame(maxWidth: .infinity)
        .frame(height: MelGenMetrics.controlHeight)
        .foregroundStyle(theme.text)
        .background(
            RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                .fill(theme.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                .strokeBorder(theme.borderStrong, lineWidth: 1.5)
        )
    }

    /// Everything the library can offer: the stored lines, plus what's been kept.
    private func searchableLines() -> [MelodyPattern] {
        var lines = PatternStore.library
        for take in liveState.curatedTakes {
            guard let progression = try? ChordProgression.parse(take.progressionText),
                  let pattern = MelodyPatterns.extract(from: take.notes,
                                                       over: progression,
                                                       name: take.displayName,
                                                       lengthBeats: take.lengthBeats)
            else { continue }
            lines.append(pattern)
        }
        return lines
    }

    private func playBestFittingLine() {
        guard let progression = try? ChordProgression.parse(liveState.progressionText) else {
            statusMessage = "That progression doesn't parse."
            return
        }
        guard let best = MelodyRetrieval.fitting(searchableLines(), progression).first else {
            statusMessage = "Nothing in the library to search."
            return
        }
        play(best.pattern, describedAs: "\(best.pattern.name) — \(best.reason)")
    }

    private func surpriseMe() {
        let current = liveState
        guard let progression = try? ChordProgression.parse(current.progressionText) else {
            statusMessage = "That progression doesn't parse."
            return
        }
        let contested = Set(current.contestedTakes.map(\.displayName))
        let recent = current.recentlyHeard().map(\.displayName)
        let keptPatterns = current.curatedTakes.compactMap { take -> MelodyPattern? in
            guard let progression = try? ChordProgression.parse(take.progressionText) else { return nil }
            return MelodyPatterns.extract(from: take.notes, over: progression,
                                          name: take.displayName, lengthBeats: take.lengthBeats)
        }

        guard let surprise = MelodyRetrieval.surprise(
            searchableLines(),
            heardRecently: recent,
            keptBuckets: MelodyRetrieval.buckets(of: keptPatterns),
            contested: contested,
            seed: UInt64(bitPattern: Int64(current.patternCursor &* 7919)) ^ 0xA5A5,
            over: progression
        ) else {
            statusMessage = "Nothing in the library to be surprised by yet."
            return
        }
        commit(reloadKernel: false) { $0.patternCursor += 1 }
        play(surprise.pattern, describedAs: "\(surprise.pattern.name) — \(surprise.reason)")
    }

    private var lineSelection: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            HStack {
                Text("Stored lines")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text)
                Spacer(minLength: MelGenMetrics.space2)
                ChipPicker(options: SelectionMode.allCases.map { ($0, $0.label) },
                           selection: binding(\.lineMode, reloadKernel: false),
                           theme: theme)
                    .frame(maxWidth: 220)
            }

            VStack(spacing: 4) {
                ForEach(PatternStore.library) { pattern in
                    lineRow(pattern)
                }
            }

            if PatternStore.isEmpty {
                Text("The six built-in lines are generic on purpose — the property that "
                     + "makes them fit anything is the one that makes them plain. Keep a take "
                     + "you liked as a line and it joins them here.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The stored lines, with their own rotation mode.
    ///
    /// Separate from the template rotation on purpose: a template is what the
    /// *next take* is like, and a stored line is a specific piece of material.
    /// Merging those two was the thing that made the old Rotation section
    /// unreadable — two lists, two modes, one heading.
    private var lineLibrarySection: some View {
        CollapsibleSection(title: "Stored lines",
                           summary: "\(PatternStore.library.count) · \(state.lineMode.label.lowercased())",
                           isExpanded: $showRotation,
                           theme: theme) {
            VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
                ChipPicker(options: SelectionMode.allCases.map { ($0, $0.label) },
                           selection: binding(\.lineMode, reloadKernel: false),
                           theme: theme)
                    .frame(maxWidth: 240)

                VStack(spacing: 4) {
                    ForEach(PatternStore.library) { pattern in
                        lineRow(pattern)
                    }
                }

                if PatternStore.isEmpty {
                    Text("The built-in lines are generic on purpose — the property that "
                         + "makes them fit anything is the one that makes them plain. Keep a take "
                         + "you liked as a line and it joins them here.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .id(libraryRevision)
        }
    }

    private func lineRow(_ pattern: MelodyPattern) -> some View {
        let isPinned = state.lineMode == .lock && state.lockedLineName == pattern.name
        let isMine = pattern.origin != nil
        return HStack(spacing: MelGenMetrics.space2) {
            Button {
                commit(reloadKernel: false) { state in
                    state.lineMode = .lock
                    state.lockedLineName = isPinned ? nil : pattern.name
                    if isPinned { state.lineMode = .cycle }
                }
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isPinned ? theme.accent : theme.textMuted)
                    .frame(width: 24, height: MelGenMetrics.smallControlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPinned ? "Unpin \(pattern.name)" : "Pin \(pattern.name)")

            VStack(alignment: .leading, spacing: 1) {
                Text(pattern.name)
                    .font(.system(size: 12, weight: isPinned ? .semibold : .regular))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(pattern.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isMine {
                Button {
                    PatternStore.remove(named: pattern.name)
                    libraryRevision += 1
                    statusMessage = "Removed \"\(pattern.name)\" from the line library."
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                        .frame(width: 24, height: MelGenMetrics.smallControlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(pattern.name)")
            } else {
                Text("built in")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .padding(.horizontal, MelGenMetrics.space2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isPinned ? theme.sunken : theme.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isPinned ? theme.accent : theme.border, lineWidth: isPinned ? 1.5 : 1)
        )
    }

    /// The sweep: what's left to hear on this pass, and the way to start another.
    private var curationSection: some View {
        let progress = state.reviewProgress
        return CollapsibleSection(
            title: "Review (pass \(state.curationPass))",
            summary: "\(progress.answered)/\(progress.total) this pass",
            isExpanded: $showCuration,
            theme: theme
        ) {
            if state.history.isEmpty {
                Text("Generate a few takes, then sweep through them here.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textMuted)
            } else {
                VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
                    Text("Deferred first, then what you haven't heard, then what you skipped — "
                         + "because a second sweep over the discards is where the surprises are.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 4) {
                        ForEach(state.reviewQueue.prefix(12)) { take in
                            ReviewRow(take: take,
                                      isCurrent: take.id == state.currentTake?.id,
                                      currentPass: state.curationPass,
                                      theme: theme) {
                                commit { $0.select(take.id) }
                            }
                        }
                    }

                    learnedStyleReadout
                    nextPassButton
                }
            }
        }
    }

    /// What the model has been told about your material, in the words it's told.
    ///
    /// Shown rather than hidden because a prompt you can't read is a system you
    /// can't reason about — and because seeing "68% stepwise" is itself a piece
    /// of feedback about what you've been keeping.
    @ViewBuilder
    private var learnedStyleReadout: some View {
        let style = StyleLearner.learn(from: state.curatedTakes)
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "Learned from what you kept", theme: theme)
            Text(style.summary)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !style.isEmpty {
                Text(style.promptText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                // Where the material puts its notes, bar by bar. A groove looks
                // like a groove here; a smear looks like a smear, which is the
                // honest signal that there isn't enough material yet.
                let model = MelodyStyleModel.learn(from: state.curatedTakes)
                if !model.isEmpty {
                    Text(model.summary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                    ForEach(Array(model.onsetMap().prefix(8).enumerated()), id: \.offset) { _, row in
                        Text(row)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.textMuted)
                    }
                }
                let grouping = MelodyTopics.group(state.curatedTakes.compactMap { take in
                    guard let progression = try? ChordProgression.parse(take.progressionText) else { return nil }
                    return MelodyPatterns.extract(from: take.notes, over: progression,
                                                  name: take.displayName, lengthBeats: take.lengthBeats)
                })
                if grouping.confidence.isWorthShowing {
                    Text("Groups the material falls into — \(grouping.confidence.verdict)")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(grouping.topics) { topic in
                        Text("· \(topic.suggestedName) — \(topic.summary)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.textMuted)
                    }
                }

                let chain = MelodyChain.learn(from: state.curatedTakes)
                if !chain.isEmpty {
                    Text(chain.summary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                    // The number that says whether there's enough material for
                    // the long context to mean anything. Low is not a bug.
                    Text("order-2 usable: \(Int(chain.trustedShare * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MelGenMetrics.space2)
        .background(
            RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                .fill(theme.raised)
        )
    }

    private var nextPassButton: some View {
        Button {
            commit(reloadKernel: false) { $0.beginNextPass() }
            statusMessage = "Pass \(state.curationPass). Everything is up for review again — "
                          + "including what you skipped."
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                Text("Start pass \(state.curationPass + 1)")
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, MelGenMetrics.space3)
            .frame(height: MelGenMetrics.controlHeight)
            .foregroundStyle(theme.text)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(theme.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .strokeBorder(theme.borderStrong, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Reopens every take for review, including the ones you skipped")
    }

    // MARK: - History

    private var historySection: some View {
        CollapsibleSection(title: "History (\(state.history.count))",
                           isExpanded: binding(\.showHistory, reloadKernel: false),
                           theme: theme) {
            if state.history.isEmpty {
                Text("Takes you generate are logged here.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textMuted)
            } else {
                VStack(spacing: 4) {
                    ForEach(state.history.prefix(historyRowLimit)) { take in
                        historyRow(take)
                    }
                }
                if state.history.count > historyRowLimit {
                    Button {
                        historyRowLimit += 40
                    } label: {
                        Text("Show 40 more of \(state.history.count - historyRowLimit) older takes")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.accent)
                            .frame(height: MelGenMetrics.smallControlHeight)
                    }
                    .buttonStyle(.plain)
                }
                exportButton
            }
        }
    }

    private func historyRow(_ take: GenerationRecord) -> some View {
        let isCurrent = take.id == state.currentTake?.id
        return Button {
            commit { $0.select(take.id) }
        } label: {
            HStack(spacing: MelGenMetrics.space2) {
                Image(systemName: isCurrent ? "speaker.wave.2.fill" : "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCurrent ? theme.accent : theme.textMuted)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(take.displayName)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(historyDetail(take))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                    FacetChips(facets: take.facets, theme: theme)
                }

                Spacer(minLength: 0)

                if let mark = take.latestMark {
                    Image(systemName: mark.disposition.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mark.pass == state.curationPass ? theme.accent : theme.textMuted)
                        .accessibilityLabel(mark.disposition.label)
                }
            }
            .padding(.horizontal, MelGenMetrics.space2)
            .frame(minHeight: MelGenMetrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(isCurrent ? theme.sunken : theme.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .strokeBorder(isCurrent ? theme.accent : theme.border, lineWidth: isCurrent ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(take.progressionText), \(take.briefName), \(take.noteCount) notes")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    /// Writes the history out as JSON — every take with the settings it was
    /// generated from and how long it took, so a run of takes can be read and
    /// analysed outside the plug-in.
    private var exportButton: some View {
        Button {
            do {
                exportDocument = try MelGenJSONDocument(data: state.historyExportData())
                isExporting = true
            } catch {
                statusMessage = "Couldn't prepare the export: \(error.localizedDescription)"
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                Text("Export history")
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, MelGenMetrics.space3)
            .frame(height: MelGenMetrics.controlHeight)
            .foregroundStyle(theme.text)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(theme.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .strokeBorder(theme.borderStrong, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: state.historyExportFilename()
        ) { result in
            switch result {
            case .success(let url):
                statusMessage = "Exported \(state.history.count) takes to \(url.lastPathComponent)."
            case .failure(let error):
                statusMessage = "Export failed: \(error.localizedDescription)"
            }
            exportDocument = nil
        }
    }

    /// Time, note count, temperature — and how long the model took, so a run of
    /// takes shows whether generation is keeping up.
    private func historyDetail(_ take: GenerationRecord) -> String {
        var parts = [
            take.date.formatted(date: .omitted, time: .shortened),
            take.source.label,
            "\(take.noteCount) notes"
        ]
        if take.source == .model {
            parts.append("temp \(take.temperature.formatted(.number.precision(.fractionLength(2))))")
        }
        if take.generationSeconds > 0 {
            parts.append("\(take.generationSeconds.formatted(.number.precision(.fractionLength(1))))s")
        }
        if let analysis = take.analysis {
            parts.append("variety \(Int((analysis.varietyScore * 100).rounded()))%")
            if analysis.notesToReview > 0 {
                parts.append("⚑\(analysis.notesToReview)")
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - State plumbing

    /// Mutates the session state and pushes it to the audio unit, which reloads
    /// the kernel's sequence unless told otherwise.
    ///
    /// The mutation is applied to the audio unit's copy rather than this view's
    /// `state`, because a long-running task (auto-regeneration) captures the view
    /// struct as it was when the task started. Reading through the audio unit
    /// means a take that finishes generating can't write back a progression the
    /// user has since edited.
    private func commit(reloadKernel: Bool = true, _ mutate: (inout MelGenState) -> Void) {
        var updated = liveState
        mutate(&updated)
        state = updated
        audioUnit?.update(state: updated, reloadKernel: reloadKernel)
    }

    /// The authoritative state, as opposed to this view's display mirror.
    private var liveState: MelGenState {
        audioUnit?.state ?? state
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MelGenState, Value>,
                                reloadKernel: Bool = true) -> Binding<Value> {
        Binding(
            get: { state[keyPath: keyPath] },
            set: { newValue in
                commit(reloadKernel: reloadKernel) { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private var playParameter: ObservableAUParameter {
        parameterTree.global.playMelody
    }

    private var direction: Int32 {
        let param: ObservableAUParameter = parameterTree.global.playbackDirection
        return Int32(param.value.rounded())
    }

    private func setDirection(_ direction: MelGenPlaybackDirection) {
        let param: ObservableAUParameter = parameterTree.global.playbackDirection
        param.value = AUValue(direction.rawValue)
    }

    private var hostSyncBinding: Binding<Bool> {
        let param: ObservableAUParameter = parameterTree.global.hostSync
        return Binding(
            get: { param.boolValue },
            set: { param.boolValue = $0 }
        )
    }

    private var takeSummary: String {
        MelodyNotation.summary(for: state.renderedMelody,
                               lengthBeats: state.currentTake?.lengthBeats ?? 0)
    }

    // MARK: - Adapting a stored line

    /// Fits the next stored generic line to the current progression and plays it.
    ///
    /// No model, so it's instant. This is what makes the plug-in usable while
    /// generation — measured at roughly four times slower than real time — catches
    /// up in the background.
    @discardableResult
    private func adaptStoredLine(commitNow: Bool = true) -> GenerationRecord? {
        let current = liveState

        let progression: ChordProgression
        do {
            progression = try ChordProgression.parse(current.progressionText)
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }

        let pattern = current.nextLine(from: PatternStore.library)
        let notes = MelodyPatterns.realize(pattern, over: progression)
        guard !notes.isEmpty else {
            statusMessage = "That line didn't fit this progression."
            return nil
        }

        let record = GenerationRecord(
            progressionText: current.progressionText,
            temperature: current.temperature,
            briefName: pattern.name,
            density: current.expression.density,
            durationPalette: current.durationPalette,
            source: .pattern,
            analysis: MelodyAnalyser.analyse(notes, over: progression),
            lengthBeats: progression.totalBeats,
            notes: notes
        )

        if commitNow {
            commit {
                $0.add(record)
                $0.patternCursor += 1
            }
            statusMessage = "\(pattern.name) — \(pattern.summary.lowercased()), fitted to \(current.progressionText)."
        } else {
            commit(reloadKernel: false) { $0.patternCursor += 1 }
        }
        return record
    }

    /// Composes a brand-new line out of gestures and plays it.
    ///
    /// The third source, alongside the model and the stored library, and the one
    /// that fixes what the other two couldn't: a stored line is generic or it is
    /// a specific past take, and the model takes two seconds a note. This is new
    /// material, shaped into phrases, instantly.
    @discardableResult
    private func composeLine(commitNow: Bool = true) -> GenerationRecord? {
        let current = liveState

        let progression: ChordProgression
        do {
            progression = try ChordProgression.parse(current.progressionText)
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }

        // Seeded from the cursor so the same session replays the same lines, and
        // from the progression so the same cursor over different changes isn't
        // the same idea twice.
        let seed = UInt64(bitPattern: Int64(current.patternCursor &* 2_654_435_761))
            ^ UInt64(truncatingIfNeeded: abs(current.progressionText.hashValue))
        let style = StyleLearner.learn(from: current.curatedTakes)
        let bars = max(2, Int(ceil(progression.totalBeats / 4)))
        let template = current.nextTemplate
        let pattern = MelodyPhrases.compose(bars: min(bars, 8),
                                            seed: seed,
                                            style: style.isEmpty ? nil : style,
                                            // A template shapes every source, not
                                            // only the one that talks to a model.
                                            preferring: template.gestureRhythms,
                                            palette: current.durationPalette)

        let notes = MelodyPatterns.realize(pattern, over: progression)
        guard !notes.isEmpty else {
            statusMessage = "That phrase didn't fit this progression."
            return nil
        }

        let record = GenerationRecord(
            progressionText: current.progressionText,
            temperature: current.temperature,
            briefName: pattern.name,
            density: current.expression.density,
            durationPalette: current.durationPalette,
            source: .composed,
            analysis: MelodyAnalyser.analyse(notes, over: progression),
            lengthBeats: progression.totalBeats,
            notes: notes
        )

        if commitNow {
            commit {
                $0.add(record)
                $0.patternCursor += 1
            }
            statusMessage = "\(template.name): \(pattern.summary)."
        } else {
            commit(reloadKernel: false) { $0.patternCursor += 1 }
        }
        return record
    }

    /// Draws a line from the slot statistics of the takes that were kept.
    ///
    /// The other three sources are, in order, somebody else's vocabulary (the
    /// seeds), a grammar (gestures) and a language model. This one is the
    /// musician's own habits, played back as new material.
    @discardableResult
    private func sampleLearnedStyle(commitNow: Bool = true) -> GenerationRecord? {
        let current = liveState

        let progression: ChordProgression
        do {
            progression = try ChordProgression.parse(current.progressionText)
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }

        let seed = UInt64(bitPattern: Int64(current.patternCursor &* 40_503))
            ^ UInt64(truncatingIfNeeded: abs(current.progressionText.hashValue))
        let bars = max(2, min(8, Int(ceil(progression.totalBeats / 4))))

        let pattern: MelodyPattern?
        let learnedFrom: Int
        switch current.learnedDraw {
        case .slots:
            let model = MelodyStyleModel.learn(from: current.curatedTakes)
            learnedFrom = model.takes
            pattern = model.isEmpty ? nil : model.sample(seed: seed, pass: current.patternCursor % 4)
        case .chain:
            let chain = MelodyChain.learn(from: current.curatedTakes)
            learnedFrom = chain.takes
            pattern = chain.isEmpty ? nil : chain.generate(bars: bars, seed: seed,
                                                           temperature: 0.6 + current.temperature)
        }

        guard let pattern else {
            statusMessage = learnedFrom == 0
                ? "Nothing kept yet — mark a few takes and this learns from them."
                : "The \(current.learnedDraw.label.lowercased()) model didn't draw anything — it needs more material."
            return nil
        }

        let notes = MelodyPatterns.realize(pattern, over: progression)
        guard !notes.isEmpty else {
            statusMessage = "That draw didn't fit this progression."
            return nil
        }

        let record = GenerationRecord(
            progressionText: current.progressionText,
            temperature: current.temperature,
            briefName: pattern.name,
            density: current.expression.density,
            durationPalette: current.durationPalette,
            source: current.learnedDraw == .slots ? .sampled : .chained,
            analysis: MelodyAnalyser.analyse(notes, over: progression),
            lengthBeats: progression.totalBeats,
            notes: notes
        )

        if commitNow {
            commit {
                $0.add(record)
                $0.patternCursor += 1
            }
            statusMessage = "Drawn from your own \(learnedFrom) kept takes — \(pattern.summary)."
        } else {
            commit(reloadKernel: false) { $0.patternCursor += 1 }
        }
        return record
    }

    // MARK: - Generation

    /// Polls the kernel's loop counter, generates the *next* take while the
    /// current one plays, and swaps it in on a loop boundary.
    ///
    /// Generation takes seconds, so committing the moment the model returns lands
    /// the change somewhere in the middle of a bar — and "new take every loop"
    /// silently became "every loop generation could keep up with". Holding the
    /// finished take until the pass counter ticks fixes both: the swap is musical,
    /// and the work happens during the loop before the one it plays in.
    private func runAutoRegeneration() async {
        guard state.autoRegenerate else { return }

        // Nothing to loop yet: put music under the changes within a beat, rather
        // than half a minute of silence while the model thinks.
        if liveState.currentTake == nil {
            composeLine()
        }
        var lastStartedPass = audioUnit?.currentPass ?? 0
        var lastFilledPass = audioUnit?.currentPass ?? 0

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            let current = liveState
            guard current.autoRegenerate else { return }
            guard let pass = audioUnit?.currentPass else { continue }

            let due = pass >= lastStartedPass + Int64(max(1, current.regenerateEveryPasses))

            // A model take finished during the last loop: it wins, so swap it in
            // now the loop has come round.
            if let ready = pendingTake, pass > pendingReadyPass {
                pendingTake = nil
                commit {
                    $0.add(ready)
                    $0.briefCursor += 1
                }
                statusMessage = "\(ready.briefName): \(ready.noteCount) notes"
                    + timingNote(for: ready)
                lastFilledPass = pass
            } else if due, pass > lastFilledPass {
                // Nothing from the model yet. Rather than repeat the same take
                // until it arrives, put a new line under the changes — instant,
                // and it keeps them moving while the model works. Alternating
                // between a fresh phrase and a stored one is what stops an
                // unattended session settling into either the same six lines or
                // the same one grammar.
                let filler = liveState.patternCursor.isMultiple(of: 2)
                    ? composeLine(commitNow: false)
                    : adaptStoredLine(commitNow: false)
                if let filler {
                    commit { $0.add(filler) }
                    statusMessage = "\(filler.briefName) (\(filler.source.label)) — model still working…"
                }
                lastFilledPass = pass
            }

            if due, !isGenerating, pendingTake == nil {
                lastStartedPass = pass
                generate(auto: true, holdForLoopPoint: true)
            }
        }
    }

    /// Says whether generation actually fits inside a loop, which is the only
    /// thing that makes "every loop" honest.
    private func timingNote(for take: GenerationRecord) -> String {
        guard take.generationSeconds > 0 else { return "" }
        let seconds = take.generationSeconds.formatted(.number.precision(.fractionLength(1)))
        let requests = take.requestCount > 1 ? " over \(take.requestCount) phrases" : ""
        guard let loop = audioUnit?.loopDuration, loop > 0 else {
            return " · took \(seconds)s\(requests)"
        }
        let fits = take.generationSeconds <= loop
        let loopText = loop.formatted(.number.precision(.fractionLength(1)))
        return fits
            ? " · took \(seconds)s\(requests), loop is \(loopText)s"
            : " · took \(seconds)s\(requests) — longer than the \(loopText)s loop, so takes arrive late"
    }

    /// - Parameter holdForLoopPoint: keep the finished take aside instead of
    ///   committing it, so the auto loop can swap it in on a boundary. A take you
    ///   asked for by hand is always committed immediately — you pressed the
    ///   button, you want to hear it.
    private func generate(auto: Bool = false, holdForLoopPoint: Bool = false) {
        guard !isGenerating else { return }
        let current = liveState

        // A manual Generate supersedes anything queued up.
        if !holdForLoopPoint {
            pendingTake = nil
        }

        let progression: ChordProgression
        do {
            progression = try ChordProgression.parse(current.progressionText)
        } catch {
            statusMessage = error.localizedDescription
            if auto {
                // Don't spin on a progression that can't parse.
                commit(reloadKernel: false) { $0.autoRegenerate = false }
            }
            return
        }

        guard #available(iOS 26.0, macOS 26.0, *) else {
            statusMessage = "Melody generation requires iOS/macOS 26 with Apple Intelligence."
            return
        }

        if case .unavailable(let reason) = MelodyGenerator.availability {
            statusMessage = reason
            if auto {
                commit(reloadKernel: false) { $0.autoRegenerate = false }
            }
            return
        }

        let template = current.nextTemplate
        let brief = template.brief ?? StyleBriefs.brief(at: current.briefCursor)
        let temperature = current.temperature
        let density = current.expression.density
        let durationPalette = current.durationPalette
        let progressionText = current.progressionText

        // What you kept, measured, and a couple of short quotes of it. Both are
        // computed here rather than inside the generator so this stays the only
        // place that knows what "curated" means.
        let curated = current.curatedTakes
        let style = StyleLearner.learn(from: curated)
        let examples = curated.isEmpty
            ? PatternLibrary.allExamples
            : PatternLibrary.examples(from: curated) + PatternLibrary.userExamples

        // A long progression is generated a phrase at a time, so say how many —
        // otherwise it just looks like it's hung.
        let phrases = MelodyChunker.chunks(for: progression).count
        let voice = style.isEmpty ? "" : " · in your voice, from \(style.takeCount) kept"
        statusMessage = phrases > 1
            ? "Generating \(brief.name.lowercased()) take over \(progressionText) — \(phrases) phrases\(voice)…"
            : "Generating \(brief.name.lowercased()) take over \(progressionText)\(voice)…"
        isGenerating = true

        Task {
            let startedAt = Date()
            do {
                let notes = try await MelodyGenerator.generate(
                    for: progression,
                    temperature: temperature,
                    brief: brief,
                    density: density,
                    durationPalette: durationPalette,
                    style: style.isEmpty ? nil : style,
                    examples: examples
                )
                if notes.isEmpty {
                    statusMessage = "The model returned no notes — try again."
                } else {
                    let record = GenerationRecord(
                        progressionText: progressionText,
                        temperature: temperature,
                        briefName: brief.name,
                        density: density,
                        durationPalette: durationPalette,
                        generationSeconds: Date().timeIntervalSince(startedAt),
                        requestCount: phrases,
                        analysis: MelodyAnalyser.analyse(notes, over: progression),
                        lengthBeats: progression.totalBeats,
                        notes: notes
                    )
                    if holdForLoopPoint {
                        pendingTake = record
                        pendingReadyPass = audioUnit?.currentPass ?? 0
                        statusMessage = "Next take ready\(timingNote(for: record)) — swapping at the loop point."
                    } else {
                        commit {
                            $0.add(record)
                            $0.briefCursor += 1
                        }
                        statusMessage = "\(brief.name): \(notes.count) notes over \(progressionText)"
                            + timingNote(for: record)
                    }
                }
            } catch {
                let failure = MelodyGenerator.describe(error)

                // One quiet retry when the failure was in the machinery rather
                // than in what was asked for. The model's safety layer fails
                // spuriously often enough that making a person press the button
                // twice is just making them do the retry by hand.
                if failure.isTransient, !auto {
                    do {
                        let notes = try await MelodyGenerator.generate(
                            for: progression,
                            temperature: temperature,
                            brief: brief,
                            density: density,
                            durationPalette: durationPalette,
                            style: style.isEmpty ? nil : style,
                            examples: examples
                        )
                        if !notes.isEmpty {
                            let record = GenerationRecord(
                                progressionText: progressionText,
                                temperature: temperature,
                                briefName: brief.name,
                                density: density,
                                durationPalette: durationPalette,
                                generationSeconds: Date().timeIntervalSince(startedAt),
                                requestCount: phrases,
                                source: .model,
                                analysis: MelodyAnalyser.analyse(notes, over: progression),
                                lengthBeats: progression.totalBeats,
                                notes: notes
                            )
                            commit {
                                $0.add(record)
                                $0.briefCursor += 1
                            }
                            statusMessage = "\(brief.name): \(notes.count) notes "
                                + "(the first attempt hit \(failure.message.prefix(40))…)"
                            isGenerating = false
                            return
                        }
                    } catch {
                        // Fall through to the fallback below.
                    }
                }

                // Still nothing from the model. Rather than leaving silence,
                // compose a phrase: the whole point of having sources that need
                // no model is that the model failing is an inconvenience rather
                // than a dead end.
                lastFailureWasModel = true
                if composeLine() != nil {
                    statusMessage = failure.message + " Composed a phrase instead."
                } else {
                    statusMessage = failure.message
                }
            }
            isGenerating = false
        }
    }
}
