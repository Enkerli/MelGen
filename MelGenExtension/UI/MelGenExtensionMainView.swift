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
    /// Which aim produced the held take, so the rotation is only advanced by the
    /// branch that promised to advance it.
    @State private var pendingAim: AdvanceMode?

    /// One candidate held per aim, refilled after every rating and every
    /// advance. Working state, not a document — for the same reason
    /// `pendingTake` isn't one: a reopened session should start from what was
    /// actually playing, not from something nobody heard.
    ///
    /// Never more than one per branch. Both branches are deterministic and cheap
    /// to refill, and a deep buffer is a buffer that goes stale silently when the
    /// setup changes under it.
    @State private var buffered: [AdvanceMode: GenerationRecord] = [:]
    /// The four that aren't ratings, opened from "more".
    @State private var showAllDispositions = false
    /// What a swipe just moved off, so Back can reselect it.
    @State private var ratedTakeID: UUID?

    @State private var isExporting = false
    @State private var exportDocument: MelGenJSONDocument?
    @State private var isImporting = false
    @State private var showRefusedTemplates = false
    /// Which pass of which take was answered, and how. Not in `MelGenState`: it's
    /// about the performance happening now, not about the session.
    @State private var driftPassMark: (takeID: UUID, pass: Int, disposition: TakeDisposition)?
    @State private var showSetups = false
    @State private var setupRevision = 0
    @State private var setupName = ""

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
    /// Set when a failure says the framework itself is down. Once it is, the
    /// plug-in stops asking: retrying a missing safety model produces the same
    /// answer every time, three seconds later, and the deterministic sources are
    /// right there. Cleared by the banner's "Try again".
    ///
    /// The four-probe diagnostic that used to sit alongside this is gone: it
    /// existed to find out *which* part of the framework was broken, and that
    /// question has been answered. The banner stays because it still does
    /// something the answer doesn't — it stops the plug-in spending three seconds
    /// per take rediscovering that the model is unavailable.
    @State private var modelIsDown = false
    /// Where the loop is, polled while the transport runs. Nil when stopped,
    /// which is what makes the playhead disappear rather than freeze.
    @State private var playheadBeat: Double?
    @State private var showRotationPicker = false
    @State private var showDrift = true
    /// Which loop is showing. Not session state: it's about what you're doing
    /// right now, not what the document is.
    @State private var panelTab: PanelTab = .play
    @State private var source: MaterialSource = .composed
    @State private var showTemplates = false
    @State private var showTexture = false
    @State private var showPlayMore = false
    @State private var showDecideMore = false
    @State private var showNoteTable = false
    /// The last template the model wrote, and what the gate made of it.
    @State private var authored: TemplateCharacter?
    @State private var authoredVerdict: TemplateVerdict?
    @State private var isAuthoring = false

    /// Mutations of the current take, and the morph between it and one of them.
    /// Not session state: they're a working surface, regenerated on demand.
    @State private var variants: [MelodyVariant] = []
    /// What's been said about each variant on screen, keyed by variant.
    ///
    /// Not part of the session state: a variant is a candidate, and the durable
    /// record of a judgement is the take that judging one creates. This is only
    /// so the row can show a tick rather than forgetting the moment it redraws.
    @State private var variantMarks: [MelodyVariant.ID: TakeDisposition] = [:]
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

                // The status message is the take's caption now, not a floating
                // line — except while the model is down, where it's about the
                // whole panel rather than about a take.
                if modelIsDown { modelDownBanner }

                switch panelTab {
                case .play: playTab
                case .decide: decideTab
                }
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
        .task(id: playParameter.boolValue) {
            await followPlayhead()
        }
        .task(id: isListening) {
            await collectPlaying()
        }
        .task(id: pendingTake?.id) {
            await runPendingSwap()
        }
        // Both branches are refilled whenever what they would produce changes:
        // the take they'd vary, the source and template they'd draw from, or the
        // changes they'd play over. A buffer nobody refreshes is a buffer that
        // promises last minute's take.
        .task(id: advanceRefillKey) {
            refillAdvances()
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
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            HStack(alignment: .firstTextBaseline) {
                Text("MelGen")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.text)

                Spacer(minLength: MelGenMetrics.space2)

                appearancePicker
            }

            // Rule one: two loops, two tabs. Playing and judging were
            // interleaved down one column of sixteen sections.
            PanelTabBar(tab: $panelTab,
                        waiting: state.reviewProgress.total - state.reviewProgress.answered,
                        theme: theme)
        }
    }

    // MARK: - Play

    /// Acts on what is sounding.
    ///
    /// The tabs were right and their criterion wasn't: "playing versus judging"
    /// fails immediately, because judging happens on both and should. The
    /// criterion that holds is *what the control acts on* — the thing that is
    /// sounding, or the thing that comes next. The test for belonging here is
    /// that touching it changes the sound before the lap ends.
    ///
    /// Curation is here too, and it is a different kind of curation: reflex.
    /// One gesture, no comparison, no list — you are answering the thing in
    /// your ears. The comparative sweep is on Decide.
    private var playTab: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space4) {
            transportStrip

            if state.currentTake != nil {
                currentTakeSection
            }

            advanceRow
            autoRow
            nowPlayingGroup
            driftSection
        }
    }

    /// Acts on what comes next, and on the record.
    ///
    /// The test for belonging: touching it changes nothing until you ask for a
    /// take. That is why the progression is here — it is the most consequential
    /// setting in the app and it does nothing on its own.
    private var decideTab: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space4) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            setupRow
            progressionSection
            nextTakeSection
            nextTakeSettings

            curationSection

            if state.currentTake != nil {
                variantsSection
            }

            historySection

            MoreRow(summary: "More: stored lines (\(PatternStore.library.count)) · "
                           + "listen to what I play · write a template · export",
                    isExpanded: $showDecideMore,
                    theme: theme)
            if showDecideMore {
                VStack(alignment: .leading, spacing: MelGenMetrics.space3) {
                    lineLibrarySection
                    captureSection
                    authorRow
                    HStack(spacing: MelGenMetrics.space2) {
                        exportButton
                        importButton
                    }
                }
            }
        }
    }

    // MARK: - Setups

    /// Named settings you can come back to, and one of them the way a new
    /// instance starts.
    ///
    /// Above everything because it's the decision that precedes the others: a
    /// setup is what four bars, surprise 0.96, chord mode and six notes a bar
    /// amount to together, and re-dialling those one control at a time every
    /// session is the work this removes. It carries no material — no take, no
    /// mark, no progression text — so recalling one can't damage a session.
    @ViewBuilder
    private var setupRow: some View {
        let setups = SetupStore.all
        let matching = setups.first { state.matches($0) }
        VStack(alignment: .leading, spacing: 4) {
            Button {
                showSetups.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showSetups ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                    Text("Setup · " + (matching?.name ?? (setups.isEmpty ? "none saved" : "unsaved")))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if let matching, matching.id == SetupStore.defaultSetupID {
                        Text("· default")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textMuted)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.textSecondary)
                .frame(height: MelGenMetrics.smallControlHeight)
            }
            .buttonStyle(.plain)

            if showSetups {
                VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
                    ForEach(setups) { setup in
                        setupCard(setup, isCurrent: setup.id == matching?.id)
                    }

                    // Offered rather than installed: an empty list with an
                    // explanation of what setups are teaches nothing, and a
                    // preset written in on first launch would be a setting
                    // nobody chose.
                    if setups.isEmpty {
                        Button {
                            let suggested = MelGenSetup.suggested
                            SetupStore.save(suggested)
                            SetupStore.makeDefault(id: SetupStore.all.first { $0.name == suggested.name }?.id)
                            commit { $0.apply(suggested) }
                            setupRevision += 1
                            statusMessage = "\(suggested.name) saved and made the default."
                        } label: {
                            findLabel("Start from \(MelGenSetup.suggested.name)",
                                      systemImage: "sparkles",
                                      detail: MelGenSetup.suggested.summary)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: MelGenMetrics.space2) {
                        TextField("Name these settings", text: $setupName)
                            .font(.system(size: 13))
                            .textFieldStyle(.plain)
                            .padding(.horizontal, MelGenMetrics.space2)
                            .frame(height: MelGenMetrics.controlHeight)
                            .background(
                                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                                    .fill(theme.sunken)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                                    .strokeBorder(theme.border, lineWidth: 1)
                            )
                        Button {
                            saveSetup()
                        } label: {
                            findLabel("Save setup", systemImage: "square.and.arrow.down.on.square")
                        }
                        .buttonStyle(.plain)
                        .disabled(setupName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .id(setupRevision)
            }
        }
    }

    private func setupCard(_ setup: MelGenSetup, isCurrent: Bool) -> some View {
        let isDefault = setup.id == SetupStore.defaultSetupID
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(setup.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                if isDefault {
                    Text("default")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.accentText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.accent))
                }
                Spacer(minLength: 0)
            }
            Text(setup.summary)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: MelGenMetrics.space3) {
                Button {
                    commit { $0.apply(setup) }
                    setupRevision += 1
                    statusMessage = "\(setup.name) — \(setup.summary)."
                } label: {
                    Text(isCurrent ? "In use" : "Use")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isCurrent ? theme.textMuted : theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(isCurrent)
                Button {
                    SetupStore.makeDefault(id: isDefault ? nil : setup.id)
                    setupRevision += 1
                    statusMessage = isDefault
                        ? "\(setup.name) is no longer the default."
                        : "New instances will start from \(setup.name)."
                } label: {
                    Text(isDefault ? "Not the default" : "Make default")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
                Button {
                    SetupStore.remove(id: setup.id)
                    setupRevision += 1
                } label: {
                    Text("Delete")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .padding(MelGenMetrics.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                .fill(isCurrent ? theme.sunken : theme.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                .strokeBorder(isCurrent ? theme.accent : theme.border, lineWidth: isCurrent ? 1.5 : 1)
        )
    }

    private func saveSetup() {
        let name = setupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let existing = SetupStore.all.contains { $0.name.lowercased() == name.lowercased() }
        SetupStore.save(MelGenSetup(name: name, capturing: liveState))
        setupName = ""
        setupRevision += 1
        statusMessage = existing ? "\(name) updated." : "\(name) saved."
    }

    // MARK: - Decide

    // MARK: - The manual gestures

    /// The two things you do to what is sounding, as first-class controls.
    ///
    /// Auto has existed for a while and its manual counterpart never did, which
    /// is what made the automatic version feel like weather rather than an
    /// instrument. There *was* a way to make a take by hand — the primary action
    /// on the other tab — but it is labelled by source ("Generate a line",
    /// "Comp"), so it doesn't read as the thing Auto does. And there was no way
    /// at all to re-roll the drift: only "previous" and "keep", so the one
    /// control that changes what you hear without costing a generation could
    /// only be waited for.
    ///
    /// They sit side by side and they are not peers, so they don't look like
    /// peers: one costs about 1.8 seconds a note and the other costs nothing,
    /// and each says so.
    private var advanceRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: MelGenMetrics.space2) {
                PrimaryAction(title: "Advance",
                              subtitle: advanceSubtitle,
                              systemImage: "forward.end.fill",
                              isWorking: isGenerating,
                              isEnabled: !state.progressionText.isEmpty,
                              theme: theme) {
                    advance()
                }

                Button {
                    rerollDrift()
                } label: {
                    findLabel("Re-roll", systemImage: "dice",
                              detail: state.liveMutation.isActive
                                  ? "roll \(state.mutationPass + 1)"
                                  : "drift is off")
                }
                .buttonStyle(.plain)
                .disabled(!state.liveMutation.isActive)
            }

            Text(advanceExplanation)
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What Advance will actually do, named before it does it.
    private var advanceSubtitle: String {
        let template = state.nextTemplate.name
        if source == .model && !modelIsDown {
            return "\(template) · something plays while the model works"
        }
        return "\(template) · \(source.name.lowercased()) · instant"
    }

    private var advanceExplanation: String {
        source == .model && !modelIsDown
            ? "The model takes about 1.8 seconds a note, so Advance fills the bar "
              + "immediately and swaps the model's take in on a lap boundary when it arrives."
            : "Re-roll changes what you are hearing without making a take. Advance makes one."
    }

    /// Next take, by whatever route is quickest — the gesture, not the source.
    ///
    /// The rule from journey one: asking must produce something within a lap. So
    /// when the chosen source is the model, this starts the generation *and*
    /// composes something to be going on with, rather than leaving a bar of
    /// silence while the model thinks for half a minute.
    private func advance() {
        if source == .model, !modelIsDown {
            composeLine()
            nextTake()
            return
        }
        run(source)
    }

    /// One draw of drift's dice, on demand rather than on the next lap.
    private func rerollDrift() {
        guard liveState.liveMutation.isActive else { return }
        commit { $0.mutationPass += 1 }
        statusMessage = "Roll \(liveState.mutationPass)."
    }

    // MARK: - Now playing, and next take

    /// Controls that re-render what is sounding.
    ///
    /// "Texture" is retired. It was one heading over two groups whose real
    /// difference is *when* they apply, and putting them together meant density
    /// and gate length looked identical while behaving nothing alike. They are
    /// now on the two different tabs, under the two different names, because the
    /// difference is which half of the interface they belong to.
    private var nowPlayingGroup: some View {
        WhenGroup(legend: "Now playing", theme: theme) {
            VStack(alignment: .leading, spacing: MelGenMetrics.space3) {
                LabelledSlider(title: "Expression", lowLabel: "even", highLabel: "shaped",
                               value: binding(\.expression.amount), theme: theme)
                LabelledSlider(title: "Gate length", lowLabel: "staccato",
                               highLabel: "legato",
                               value: binding(\.expression.noteLength), theme: theme)
                LabelledSlider(title: "Swing", lowLabel: "straight", highLabel: "swung",
                               value: binding(\.expression.swing), theme: theme)
            }
        }
    }

    /// Controls that change nothing until you ask for a take.
    private var nextTakeSettings: some View {
        WhenGroup(legend: "Next take", theme: theme) {
            VStack(alignment: .leading, spacing: MelGenMetrics.space3) {
                LabelledSlider(title: "Density", lowLabel: "sparse", highLabel: "dense",
                               value: binding(\.expression.density), theme: theme,
                               format: { "\(MelodyExpression.notesPerBar(forDensity: $0))/bar" })
                LabelledSlider(title: "Temperature", lowLabel: "expected",
                               highLabel: "surprising",
                               value: binding(\.temperature, reloadKernel: false), theme: theme)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note duration")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.text)
                    ChipPicker(options: DurationPalette.allCases.map { ($0, $0.label) },
                               selection: binding(\.durationPalette, reloadKernel: false),
                               theme: theme)
                }
            }
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


    /// Says once, quietly, what would otherwise be said after every attempt.
    private var modelDownBanner: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Foundation Models isn't available on this device")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.text)
                Text(state.modelHasWorkedHere
                     ? "It has worked here before, so something changed — a third-party model "
                       + "extension under Settings ▸ Apple Intelligence & Siri is the usual "
                       + "culprit. Everything that doesn't need a model still works meanwhile."
                     : "Everything that doesn't need a model still works — composing, stored "
                       + "lines, comping, drawing from your own material, and the whole "
                       + "curation loop.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                modelIsDown = false
                statusMessage = "Trying the model again."
            } label: {
                Text("Try again")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(MelGenMetrics.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                .fill(theme.raised)
        )
    }

    /// How much the chain can be trusted, in words.
    private func chainConfidence(_ share: Double) -> String {
        let howOften: String
        switch share {
        case ..<0.1: howOften = "almost never"
        case ..<0.3: howOften = "about a fifth of the time"
        case ..<0.45: howOften = "about a third of the time"
        case ..<0.6: howOften = "about half the time"
        case ..<0.8: howOften = "most of the time"
        default: howOften = "nearly always"
        }
        return "It can predict two notes ahead \(howOften) — "
             + (share < 0.3 ? "not enough material yet." : "enough to be worth drawing from.")
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
                           selection: modeBinding,
                           theme: theme)
                    .frame(maxWidth: 200)
                Text(state.mode.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Voice leading sits with the mode rather than with the expression
            // controls, because it's a harmonic decision and it applies to both
            // modes: how one chord reaches the next, and how a line crosses a
            // change.
            HStack(spacing: MelGenMetrics.space2) {
                ChipPicker(options: VoiceLeadingMode.allCases.map { ($0, $0.label) },
                           selection: Binding(
                               get: { state.voiceLeading },
                               set: { mode in commit(reloadKernel: false) { $0.voiceLeading = mode } }),
                           theme: theme)
                    .frame(maxWidth: 240)
                Text("Voice leading — \(state.voiceLeading.summary.lowercased())")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Rule three: one filled action, and it always names what it will do.
            PrimaryAction(title: source.verb(mode: state.mode),
                          subtitle: actionSubtitle,
                          systemImage: source.symbolName,
                          isWorking: isGenerating,
                          isEnabled: sourceIsAvailable(source),
                          theme: theme) {
                run(source)
            }

            // Rule two: cost is the axis. Every source says whose vocabulary it
            // is and whether it answers now or in about 1.8 seconds a note.
            VStack(alignment: .leading, spacing: 4) {
                Text("Where the material comes from")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                VStack(spacing: 4) {
                    ForEach(MaterialSource.all(for: state.mode)) { candidate in
                        SourceRow(source: candidate,
                                  isSelected: candidate == source,
                                  isAvailable: sourceIsAvailable(candidate),
                                  theme: theme) {
                            source = candidate
                        }
                    }
                }
            }

            templateRow
        }
    }

    /// What the action will produce, under its own name.
    private var actionSubtitle: String {
        switch source {
        case .model, .composed:
            return "\(state.nextTemplate.name)\(modelIsDown && source == .model ? " · model unavailable" : "")"
        case .stored:
            return state.nextLine(from: PatternStore.library).name
        case .learned:
            return "\(state.learnedDraw.label.lowercased()) · \(state.curatedTakes.count) kept"
        case .played:
            return isListening ? "listening" : "listening is off"
        case .comp:
            return state.nextTemplate.name
        }
    }

    private func sourceIsAvailable(_ candidate: MaterialSource) -> Bool {
        guard !state.progressionText.isEmpty else { return false }
        switch candidate {
        case .learned: return state.curatedTakes.count >= 3
        default: return true
        }
    }

    /// Runs whichever source is chosen. The one place that knows the mapping.
    private func run(_ candidate: MaterialSource) {
        switch candidate {
        case .model:
            // With the framework down this composes, and the button already
            // says so rather than promising something it can't do.
            if modelIsDown { composeLine() } else { nextTake() }
        case .stored: adaptStoredLine()
        case .composed: composeLine()
        case .learned: sampleLearnedStyle()
        case .played: isListening.toggle()
        case .comp: compChanges()
        }
    }

    /// Switching mode switches the source with it, since half of them can't
    /// produce what the other mode asks for.
    private var modeBinding: Binding<PlayMode> {
        Binding(
            get: { state.mode },
            set: { newMode in
                commit(reloadKernel: false) { $0.mode = newMode }
                if !MaterialSource.all(for: newMode).contains(source) {
                    source = MaterialSource.first(for: newMode)
                }
            }
        )
    }

    /// The template, behind a one-line disclosure — set once a session rather
    /// than once a take.
    private var templateRow: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            Button {
                showTemplates.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showTemplates ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                    Text("Template · \(state.nextTemplate.name) · "
                         + (state.briefMode == .lock
                            ? "pinned"
                            : "\(state.briefMode.label.lowercased()) through "
                              + "\(MelGenTemplates.all(for: state.mode).count)"))
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.textSecondary)
                .frame(minHeight: MelGenMetrics.controlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showTemplates {
                FlowChips(items: MelGenTemplates.all(for: state.mode).map(\.name),
                          isSelected: { $0 == state.nextTemplate.name },
                          isPinned: { state.briefMode == .lock && state.lockedBriefName == $0 },
                          theme: theme) { name in
                    useTemplate(name)
                }

                HStack(spacing: MelGenMetrics.space2) {
                    ChipPicker(options: SelectionMode.allCases.map { ($0, $0.label) },
                               selection: binding(\.briefMode, reloadKernel: false),
                               theme: theme)
                        .frame(maxWidth: 220)
                    Spacer(minLength: 0)
                }

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
                    .frame(minHeight: MelGenMetrics.smallControlHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showRotationPicker {
                    FlowChips(items: MelGenTemplates.all(for: state.mode).map(\.name),
                              isSelected: { name in
                                  state.selectedBriefNames.isEmpty
                                      || state.selectedBriefNames.contains(name)
                              },
                              theme: theme) { name in
                        toggleTemplate(name)
                    }
                }
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

    /// Comps once with every figure, so the six can be compared by ear rather
    /// than by cycling through them one press at a time.
    private func compEveryFigure() {
        let current = liveState
        guard let progression = try? ChordProgression.parse(current.progressionText) else {
            statusMessage = "That progression doesn't parse."
            return
        }
        var added = 0
        for (index, figure) in CompingFigure.all.enumerated() {
            let notes = MelodyComping.comp(progression, figure: figure,
                                           seed: UInt64(bitPattern: Int64(index &* 7919 &+ 13)),
                                           leading: current.voiceLeading)
            guard !notes.isEmpty else { continue }
            commit(reloadKernel: index == CompingFigure.all.count - 1) {
                $0.add(GenerationRecord(
                    progressionText: progression.text,
                    temperature: current.temperature,
                    briefName: "\(figure.name) · \(figure.style.label)",
                    density: current.expression.density,
                    durationPalette: current.durationPalette,
                    source: .comping,
                    analysis: MelodyAnalyser.analyse(notes, over: progression),
                    lengthBeats: progression.totalBeats,
                    notes: notes))
            }
            added += 1
        }
        statusMessage = "\(added) comps, one per figure — they're in the history, judge them there."
    }

    /// Lays voicings under the progression and plays them.
    ///
    /// No model involved, and none wanted: comping is a voicing policy and a
    /// rhythm, both of which are decisions rather than guesses.
    /// - Parameter commitNow: `false` returns the comp instead of loading it, so
    ///   the auto loop can hold it for a loop boundary — the same shape
    ///   `composeLine` and `adaptStoredLine` use.
    @discardableResult
    private func compChanges(commitNow: Bool = true) -> GenerationRecord? {
        let current = liveState
        guard let progression = try? ChordProgression.parse(current.progressionText) else {
            statusMessage = "That progression doesn't parse."
            return nil
        }
        let template = current.nextTemplate
        let figure = template.figure ?? CompingFigure.charleston
        let notes = MelodyComping.comp(progression,
                                       figure: figure,
                                       seed: UInt64(bitPattern: Int64(current.briefCursor &* 2_246_822_519)),
                                       leading: current.voiceLeading)
        guard !notes.isEmpty else {
            statusMessage = "Nothing to comp — check the progression."
            return nil
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
        // The cursor advances either way: it's what moves the rotation on to the
        // next figure, so a held comp still leaves the next one different.
        if commitNow {
            commit {
                $0.add(record)
                $0.briefCursor += 1
            }
            statusMessage = "\(figure.name): \(notes.count) notes, up to "
                + "\(MelodyComping.maximumPolyphony(of: notes)) voices. \(figure.summary)."
        } else {
            commit(reloadKernel: false) { $0.briefCursor += 1 }
        }
        return record
    }

    private var nextTakeEnabled: Bool {
        guard !state.progressionText.isEmpty, !isGenerating else { return false }
        // Comping needs no model, so it's available whatever the model is doing.
        return state.mode == .comping || generateEnabled || modelIsDown
    }

    /// What the main button does right now, which is not always what it's called.
    ///
    /// With the framework down, "Generate" would be a button that waits three
    /// seconds and then composes — so it says what it will actually do. A control
    /// that names an action it can't perform is worse than one that isn't there.
    private var nextTakeLabel: String {
        if isGenerating { return "Working" }
        if state.mode == .comping { return modelIsDown ? "Comp" : "Comp" }
        return modelIsDown ? "Compose" : "Generate"
    }

    /// Asking the model for a way of playing, rather than for a line.
    ///
    /// The one request whose economics work: a take costs about 1.8 seconds a
    /// note every time it's asked for, and a template costs one request once,
    /// after which the deterministic path composes from it instantly for as long
    /// as it's kept. And the answer is checked — a template that composes to
    /// something the rotation already has is refused and says which one it
    /// duplicates, so this can't quietly fill the list with renames.
    @ViewBuilder
    private var authorRow: some View {
        if state.mode == .line {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: MelGenMetrics.space2) {
                    Button {
                        authorTemplate()
                    } label: {
                        findLabel(isAuthoring ? "Writing…" : "Write a new template",
                                  systemImage: "square.and.pencil",
                                  detail: modelIsDown ? "needs the model" : "one request, kept forever")
                    }
                    .buttonStyle(.plain)
                    .disabled(isAuthoring || modelIsDown)

                    if let authored, authoredVerdict?.accepted == false {
                        Button {
                            self.authored = nil
                            authoredVerdict = nil
                        } label: {
                            findLabel("Discard", systemImage: "trash")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Discard \(authored.name)")
                    }
                }

                refusedTemplateList

                if let authored, let verdict = authoredVerdict {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: verdict.accepted ? "checkmark.circle" : "xmark.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(verdict.accepted ? theme.accent : theme.warning)
                            Text(authored.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.text)
                        }
                        Text(authored.brief)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(String(format: "%.0f notes a bar · %.0f%% air · %.0f%% offbeat · "
                                    + "notes of about %.0f eighths",
                                    authored.notesPerBar, authored.airiness * 100,
                                    authored.offbeatness * 100, authored.noteLength))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.textMuted)
                        Text(verdict.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(verdict.accepted ? theme.textSecondary : theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
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

    /// The templates the gate turned down, and what they were too close to.
    ///
    /// Visible because the pattern in them is the finding: refusals all naming
    /// the same existing template say something about the gate rather than about
    /// the proposals. And each one can be taken into the rotation anyway — the
    /// gate stops the list filling with renames on its own, which is not the same
    /// as forbidding one.
    @ViewBuilder
    private var refusedTemplateList: some View {
        let refused = TemplateStore.refused
        if !refused.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    showRefusedTemplates.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showRefusedTemplates ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("Refused: \(refused.count) · " + refusalPattern)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(theme.textSecondary)
                    .frame(height: MelGenMetrics.smallControlHeight)
                }
                .buttonStyle(.plain)

                if showRefusedTemplates {
                    ForEach(refused.reversed()) { proposal in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(proposal.character.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.text)
                            Text(proposal.relationship)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(proposal.character.brief)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: MelGenMetrics.space2) {
                                Button {
                                    TemplateStore.promote(named: proposal.character.name)
                                    libraryRevision += 1
                                    useTemplate(proposal.character.name)
                                    statusMessage = "\(proposal.character.name) is in the rotation — "
                                        + "tweak the patterns it composes to make it its own."
                                } label: {
                                    Text("Use it anyway")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(theme.accent)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    TemplateStore.dropRefused(named: proposal.character.name)
                                    libraryRevision += 1
                                } label: {
                                    Text("Forget it")
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.textMuted)
                                }
                                .buttonStyle(.plain)
                                Spacer(minLength: 0)
                            }
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
            .id(libraryRevision)
        }
    }

    /// Whether the refusals are all blaming the same template — which would be a
    /// property of the gate, not of what was proposed.
    private var refusalPattern: String {
        let counts = state.refusalsByNearest
        guard let top = counts.first else { return "nothing in common" }
        let refusals = counts.reduce(0) { $0 + $1.count }
        guard refusals > 1 else { return "nearest: \(top.name)" }
        let share = Double(top.count) / Double(refusals)
        return share >= 0.5
            ? String(format: "%.0f%% of them blame %@", share * 100, top.name as NSString)
            : "spread across \(counts.count) templates"
    }

    private func authorTemplate() {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        isAuthoring = true
        authored = nil
        authoredVerdict = nil
        let existing = MelGenTemplates.all(for: .line)

        Task {
            do {
                let character = try await MelodyGenerator.writeTemplate(avoiding: existing)
                let verdict = TemplateGate.judge(character, against: existing)
                authored = character
                authoredVerdict = verdict

                // Logged either way, and the log goes out with the history: a
                // refusal costs a model request, and a run of them is the only
                // evidence there is about whether the gate is calibrated or the
                // model is repeating itself.
                let proposal = TemplateProposal(character: character, verdict: verdict)
                commit(reloadKernel: false) { $0.record(proposal) }

                if verdict.accepted {
                    TemplateStore.add(character)
                    libraryRevision += 1
                    // Straight into the rotation and selected, because a template
                    // you just asked for is one you want to hear.
                    useTemplate(character.name)
                    statusMessage = "\(character.name) — \(verdict.summary)"
                } else {
                    // Kept rather than discarded. A refusal says "this composes to
                    // nearly what X does", not "this is worthless", and the tweaks
                    // that make a template distinctive get applied by hand anyway.
                    TemplateStore.addRefused(proposal)
                    libraryRevision += 1
                    statusMessage = "\(character.name): \(proposal.relationship)."
                }
            } catch {
                let failure = MelodyGenerator.describe(error)
                if failure.isSystemwide { modelIsDown = true }
                statusMessage = failure.message
            }
            isAuthoring = false
        }
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
        guard !modelIsDown else {
            // Known down: go straight to the source that answers, rather than
            // spending three seconds finding out again.
            if liveState.mode == .comping { compChanges() } else { composeLine() }
            return
        }
        if liveState.mode == .comping {
            generateComp()
        } else {
            generate()
        }
    }

    /// Asks the model for a comping part, and falls back to the deterministic one.
    ///
    /// The model chooses when the chords land and which tones are in them; the
    /// voicing layer does register, spacing and voice leading. If it can't
    /// answer, `compChanges` produces a comp anyway — the same arrangement as the
    /// melodic path, where the model failing costs quality rather than music.
    private func generateComp() {
        let current = liveState
        guard let progression = try? ChordProgression.parse(current.progressionText) else {
            statusMessage = "That progression doesn't parse."
            return
        }

        guard #available(iOS 26.0, macOS 26.0, *),
              case .available = MelodyGenerator.availability else {
            compChanges()
            return
        }

        let template = current.nextTemplate
        let figure = template.figure ?? CompingFigure.charleston
        let temperature = current.temperature
        statusMessage = "Asking for a \(figure.name.lowercased()) comp over \(progression.text)…"
        isGenerating = true

        Task {
            let startedAt = Date()
            do {
                let notes = try await MelodyGenerator.comp(for: progression,
                                                           temperature: temperature,
                                                           figure: figure,
                                                           angle: current.briefCursor)
                guard !notes.isEmpty else {
                    compChanges()
                    isGenerating = false
                    return
                }
                let record = GenerationRecord(
                    progressionText: progression.text,
                    temperature: temperature,
                    briefName: "\(figure.name) · model",
                    density: current.expression.density,
                    durationPalette: current.durationPalette,
                    generationSeconds: Date().timeIntervalSince(startedAt),
                    requestCount: MelodyChunker.chunks(for: progression).count,
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
                    + "\(MelodyComping.maximumPolyphony(of: notes)) voices"
                    + timingNote(for: record)
            } catch {
                let failure = MelodyGenerator.describe(error)
                if failure.isSystemwide { modelIsDown = true }
                compChanges()
                statusMessage = failure.message + " Comped it here instead."
            }
            isGenerating = false
        }
    }

    // MARK: - Instant sources

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

    /// Direction, as a radio group of three.
    private var directionGroup: some View {
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
        // Capped: a small arrow centred in a 400pt button looks broken in a wide
        // plug-in window.
        .frame(maxWidth: 200)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback direction")
    }

    /// How often anything changes: when Auto swaps a take in, and when the drift
    /// re-rolls.
    ///
    /// Shown when either is on, because it now governs both. Behind Auto alone it
    /// was invisible in exactly the case that needed it — a drifting loop with no
    /// auto-regeneration changed every pass with no way to say otherwise.
    @ViewBuilder
    private var autoRow: some View {
        if state.autoRegenerate || state.liveMutation.isActive {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MelGenMetrics.space2) {
                    Text(state.autoRegenerate ? "New take every" : "Re-roll the drift every")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text)
                    ChipPicker(
                        options: [(1, "lap"), (2, "2 laps"), (4, "4 laps"), (8, "8 laps")],
                        selection: binding(\.regenerateEveryPasses, reloadKernel: false),
                        theme: theme
                    )
                    .frame(maxWidth: 320)
                    Spacer(minLength: 0)
                }
                if state.regenerateEveryPasses > 1 {
                    Text(state.autoRegenerate && state.liveMutation.isActive
                         ? "The take and the drift change together, so each performance is heard "
                           + "\(state.regenerateEveryPasses) times — long enough to judge one."
                         : "Heard \(state.regenerateEveryPasses) times before anything changes.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Feel (applies to the take already loaded)

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

                Text("Re-rolled every \(state.regenerateEveryPasses == 1 ? "lap" : "\(state.regenerateEveryPasses) laps"), and seeded by which roll "
                     + "it is — so a roll that sounded good can be got back rather than "
                     + "being gone. Roll \(state.mutationPass).")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: MelGenMetrics.space2) {
                    Button {
                        commit { $0.mutationPass -= 1 }
                    } label: {
                        findLabel("Previous roll", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.plain)
                    .disabled(!state.liveMutation.isActive)

                    Button {
                        keepThisPass()
                    } label: {
                        findLabel("Keep this roll", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.plain)
                    .disabled(!state.liveMutation.isActive)
                }
            }
        }
    }

    /// Re-rolls the drift, on the same cadence the take changes on.
    ///
    /// A quarter of a second is far shorter than any loop and costs nothing; the
    /// alternative is a callback from the render thread, which would mean the
    /// audio thread waiting on the interface.
    ///
    /// The cadence is `regenerateEveryPasses`, not every loop, and that's the
    /// whole point of the setting. "New take every two loops" was asked for so
    /// there would be time to judge something before it was gone — and it bought
    /// none, because the drift re-rolled every loop regardless. Two passes of the
    /// same take were two different performances of it, so there was still
    /// nothing stable to answer. Re-rolling with the take means the interval
    /// governs *how often anything changes*, which is what it was set for.
    ///
    /// It applies whether or not auto-regeneration is on: at the default of 1 the
    /// behaviour is exactly what it was, and at 2 you hear the same performance
    /// twice either way.
    private func runDrift() async {
        guard state.liveMutation.isActive else { return }
        var lastRolledPass = audioUnit?.currentPass ?? 0
        while !Task.isCancelled, liveState.liveMutation.isActive {
            try? await Task.sleep(for: .milliseconds(250))
            guard let pass = audioUnit?.currentPass else { continue }
            guard liveState.isDue(pass: pass, since: lastRolledPass) else { continue }
            lastRolledPass = pass
            commit { $0.mutationPass += 1 }
        }
    }

    /// Freezes the drifted loop as a take of its own, without interrupting it.
    ///
    /// The drift is a performance and doesn't touch the take, which is right
    /// until the moment a pass comes out better than what it was performing.
    ///
    /// Filed rather than loaded, and `reloadKernel: false`, because the pass is
    /// still playing and keeping it is a statement about the record. Loading it
    /// made a rating look like a skip: the panel jumped to the new take, the
    /// kernel got a new take id and restarted the loop from the top, and the
    /// drift began compounding on notes it had already drifted.
    /// - Returns: the take that was filed, so a caller can mark it.
    @discardableResult
    private func keepThisPass() -> GenerationRecord? {
        let current = liveState
        guard let take = current.currentTake else { return nil }
        let notes = current.renderedMelody
        guard !notes.isEmpty else { return nil }

        let record = GenerationRecord(
            progressionText: take.progressionText,
            temperature: take.temperature,
            briefName: "\(take.briefName) · roll \(current.mutationPass)",
            density: take.density,
            durationPalette: take.durationPalette,
            source: take.source,
            analysis: (try? ChordProgression.parse(take.progressionText))
                .map { MelodyAnalyser.analyse(notes, over: $0) },
            parentTakeID: take.id,
            derivation: "drift, roll \(current.mutationPass)",
            lengthBeats: take.lengthBeats,
            notes: notes
        )
        commit(reloadKernel: false) { $0.file(record) }
        statusMessage = "Roll \(current.mutationPass) kept as a take of its own."
        return record
    }

    // MARK: - Current take

    /// The take: what you hear, and what it looks like.
    ///
    /// The transport used to live here, on the roll's edge, so that what you hear
    /// and what you see never scrolled apart. It moved out because the section is
    /// gated on there *being* a take, which hid Host sync and Auto until one
    /// existed. The status message stays as the take's caption rather than
    /// floating above everything, and announces politely, so a new take is spoken
    /// rather than silently replacing the old one.
    private var currentTakeSection: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            if let changes = try? ChordProgression.parse(state.progressionText) {
                PianoRoll(notes: state.renderedMelody,
                          progression: changes,
                          lengthBeats: state.currentTake?.lengthBeats ?? 0,
                          theme: theme,
                          playheadBeat: playheadBeat)
                    // The sweep, as a gesture: right Yes, left No, up Maybe,
                    // each one rating and advancing by the aim shown in words
                    // under the strip. Long press reaches the seven.
                    .rateOnSwipe(onSwipe: { rating in
                        guard let take = state.currentTake else { return }
                        rate(rating, of: take, mark: take.mark(onPass: state.curationPass))
                    }, onMore: { showAllDispositions = true })
                    .accessibilityHint("Swipe right to keep, left to skip, up to set aside")
            }

            rollKey
            takeCaption

            if let take = state.currentTake {
                DisclosureGroup(isExpanded: $showNoteTable) {
                    noteTable(for: take)
                } label: {
                    Text("Read the take as text")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                        .frame(minHeight: MelGenMetrics.smallControlHeight)
                }
                .accessibilityHint("A table of every note with its chord and its role")

                curationControls(for: take)
            }
        }
    }

    /// Transport, on the roll's edge.
    private var transportStrip: some View {
        HStack(spacing: MelGenMetrics.space2) {
            playButton
            directionGroup
            Spacer(minLength: 0)
            ToggleChip(title: "Host sync", systemImage: "metronome",
                       isOn: hostSyncBinding, theme: theme)
            ToggleChip(title: "Auto", systemImage: "arrow.trianglehead.2.clockwise",
                       isOn: binding(\.autoRegenerate, reloadKernel: false), theme: theme)
        }
    }

    /// What the colours in the roll mean.
    ///
    /// Role is also carried by the note's outline — solid, hatched, dashed — so
    /// it survives without colour, which is the point of having a key at all.
    private var rollKey: some View {
        HStack(spacing: MelGenMetrics.space3) {
            ForEach(rollKeyEntries, id: \.label) { entry in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(entry.colour)
                        .frame(width: 14, height: 9)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(theme.text.opacity(0.55),
                                              style: StrokeStyle(lineWidth: 1, dash: entry.dash))
                        )
                    Text(entry.label)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Colour key: "
                            + rollKeyEntries.map(\.label).joined(separator: ", "))
    }

    private var rollKeyEntries: [(label: String, colour: Color, dash: [CGFloat])] {
        [("chord tone", theme.accent, []),
         ("colour note", theme.accent.opacity(0.62), []),
         ("to review", theme.warning, [2, 2]),
         ("off scale", theme.text.opacity(0.55), [4, 3])]
    }

    /// The take's own caption, which announces.
    private var takeCaption: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let take = state.currentTake {
                HStack(spacing: 6) {
                    Text(take.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(captionDetail(for: take))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                }
                Text(takeSummary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.textMuted)
                if let analysis = take.analysis {
                    Text(analysis.summary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MelGenMetrics.space2)
        .background(
            RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                .fill(theme.raised)
        )
        // Polite, so a new take is spoken rather than silently swapped in.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func captionDetail(for take: GenerationRecord) -> String {
        var parts = ["from the \(take.source.label)"]
        if take.generationSeconds > 0 {
            parts.append("took \(take.generationSeconds.formatted(.number.precision(.fractionLength(1))))s")
        }
        return parts.joined(separator: " · ")
    }

    /// The roll, as a table.
    ///
    /// Not a fallback — the roll is a picture and a picture of sixteen notes is
    /// not readable by everyone, nor copyable into a note. Same information,
    /// same order, role included.
    private func noteTable(for take: GenerationRecord) -> some View {
        let progression = try? ChordProgression.parse(take.progressionText)
        let notes = state.renderedMelody.sorted { $0.startBeat < $1.startBeat }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: MelGenMetrics.space2) {
                Text("Beat").frame(width: 44, alignment: .leading)
                Text("Note").frame(width: 44, alignment: .leading)
                Text("Length").frame(width: 52, alignment: .leading)
                Text("Chord").frame(width: 60, alignment: .leading)
                Text("Role")
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(theme.textSecondary)

            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                let chord = progression?.chord(at: note.startBeat)
                let role = progression.map { MelodyAnalyser.role(of: note, in: $0) }
                HStack(spacing: MelGenMetrics.space2) {
                    Text(note.startBeat.formatted(.number.precision(.fractionLength(1))))
                        .frame(width: 44, alignment: .leading)
                    Text(ChordProgression.noteName(forMIDINote: Int(note.note)))
                        .frame(width: 44, alignment: .leading)
                    Text(note.durationBeats.formatted(.number.precision(.fractionLength(1))))
                        .frame(width: 52, alignment: .leading)
                    Text(chord?.symbol.text ?? "—")
                        .frame(width: 60, alignment: .leading)
                    Text(roleName(role))
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func roleName(_ role: HarmonicRole?) -> String {
        switch role {
        case .chordTone: return "chord tone"
        case .colour: return "colour"
        case .avoid: return "to review"
        case .offScale: return "off scale"
        case nil: return "—"
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

            // Where this take came from, and what was said about that. The
            // sentence being written is "the parent was Tweak; this variation is
            // tweaked in the right direction, so it's Keep" — so both halves
            // have to be on screen at the moment of judging.
            lineage(of: take)

            // While drift is running these answer for the *pass*, so they show
            // what was said about this pass rather than about the take. Without
            // that it read as unjudged the instant after a tap, which looks like
            // the tap was lost.
            RateAndAdvanceStrip(
                current: judgingDrift ? markForThisPass : mark?.disposition,
                aim: state.advanceMode,
                theme: theme,
                subtitle: { TakeAdvance.subtitle(mode: $0, state: state, source: source) },
                onRate: { rate($0, of: take, mark: mark) },
                onAdvance: { advance(aiming: $0) },
                onMore: { showAllDispositions = true },
                onBack: ratedTakeID.flatMap { id in
                    id == take.id ? nil : { reselect(id) }
                })

            // The seven, as the "more" destination rather than the default. The
            // model didn't change — a rating writes one of these — so this bar
            // is unchanged from what it always was.
            if showAllDispositions {
                DispositionBar(current: judgingDrift ? markForThisPass : mark?.disposition,
                               theme: theme,
                               onSelect: { disposition in
                    judge(disposition, of: take, mark: mark)
                }, startExpanded: true)
            }

            if judgingDrift {
                Text("Drift is running, so this judges the roll you're hearing — "
                     + "kept as a take of its own with \(take.displayName) as its parent, "
                     + "which keeps playing and keeps its own mark."
                     + (markForThisPass == nil ? "" : " Roll \(state.mutationPass) answered."))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
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

    /// Whether what's sounding is a performance of the take rather than the take.
    ///
    /// Drift re-rolls on every loop and deliberately doesn't create takes, which
    /// meant judging while it ran marked the *parent* — so a pass that had
    /// changed a great deal still showed the mark of the thing it drifted from,
    /// and stayed on "pass 1" while doing it.
    private var judgingDrift: Bool {
        state.liveMutation.isActive && state.mutationPass > 0
    }

    /// What was said about the pass currently sounding, if anything.
    ///
    /// Keyed on the take *and* the pass, so it clears itself both when the drift
    /// re-rolls and when a different take is loaded. Keyed on the pass alone, a
    /// new take arrived showing the mark given to the previous take's pass —
    /// which read as a rating that had followed the wrong material, and is the
    /// exact confusion the pass/take/loop distinction exists to prevent.
    private var markForThisPass: TakeDisposition? {
        guard let answered = driftPassMark,
              answered.pass == state.mutationPass,
              answered.takeID == state.currentTake?.id else { return nil }
        return answered.disposition
    }

    /// Records a judgement about whatever is actually sounding.
    ///
    /// When that's the take, it marks the take. When it's a drifted pass, the
    /// pass is frozen as a variation first and the mark lands on that — which is
    /// what makes "rate each variation" true rather than approximately true.
    // MARK: - Rate, then advance

    /// One coarse answer, and the next take.
    ///
    /// The mark belongs to the take you were listening to, not to the one that
    /// replaced it — so it is written *before* anything advances, from the take
    /// that was passed in rather than from whatever `currentTake` becomes.
    private func rate(_ rating: TakeRating,
                      of take: GenerationRecord,
                      mark: CurationMark?) {
        if judgingDrift {
            judge(rating.disposition, of: take, mark: mark)
            return
        }
        commit(reloadKernel: false) { $0.rate(take.id, rating) }
        ratedTakeID = take.id
        statusMessage = "\(rating.label) — \(rating.disposition.label.lowercased()), "
            + "pass \(liveState.curationPass)."
        advance(aiming: state.advanceMode, quietly: true)
    }

    /// Makes the next take the way the listener aimed it, and makes that aim the
    /// swipe's mode — so the words under the strip stay true.
    private func advance(aiming mode: AdvanceMode, quietly: Bool = false) {
        if liveState.advanceMode != mode {
            commit(reloadKernel: false) { $0.advanceMode = mode }
        }

        let record = buffered[mode] ?? candidate(for: mode)
        buffered[mode] = nil
        guard let record else {
            if !quietly { statusMessage = "Nothing to aim at yet." }
            return
        }

        // The model is never what an advance waits on: if one is wanted it runs
        // alongside and swaps in on a lap boundary through the same path
        // auto-regeneration uses.
        if TakeAdvance.backgroundRequest(mode: mode, state: liveState, source: source) != nil {
            generate(auto: true, holdForLoopPoint: true)
        }

        deliver(record, aimed: mode, quietly: quietly)
        refillAdvances()
    }

    /// Puts a take in front of the listener without cutting a bar in half.
    ///
    /// Running: it waits for the next lap boundary, on the path that already
    /// exists for it. Stopped: there is no boundary to wait for, so it lands now.
    private func deliver(_ record: GenerationRecord, aimed mode: AdvanceMode, quietly: Bool) {
        if playParameter.boolValue, let pass = audioUnit?.currentPass {
            pendingTake = record
            pendingReadyPass = pass
            pendingAim = mode
            if !quietly {
                statusMessage = "\(mode.label): \(record.briefName) on the next lap."
            }
            return
        }
        commit {
            $0.add(record)
            if mode == .somethingElse { $0.briefCursor += 1 }
        }
        if !quietly {
            statusMessage = "\(mode.label): \(record.briefName), \(record.noteCount) notes."
        }
    }

    /// Refills both branches. Idempotent and cheap — both are deterministic.
    /// Everything a held candidate depends on, so a stale one is impossible
    /// rather than merely unlikely.
    private var advanceRefillKey: String {
        [state.currentTakeID?.uuidString ?? "-",
         source.rawValue,
         String(state.briefCursor),
         state.mode.rawValue,
         state.progressionText].joined(separator: "·")
    }

    private func refillAdvances() {
        for mode in AdvanceMode.allCases { buffered[mode] = candidate(for: mode) }
    }

    private func candidate(for mode: AdvanceMode) -> GenerationRecord? {
        guard let changes = try? ChordProgression.parse(liveState.progressionText) else { return nil }
        return TakeAdvance.candidate(mode: mode, state: liveState,
                                     source: source, progression: changes)
    }

    /// Puts back the take a swipe moved off. Not an undo of the mark — re-rating
    /// on the same pass already replaces — but of the *advance*.
    private func reselect(_ takeID: UUID) {
        guard liveState.history.contains(where: { $0.id == takeID }) else { return }
        commit { $0.currentTakeID = takeID }
        ratedTakeID = nil
        refillAdvances()
        statusMessage = "Back to \(liveState.currentTake?.displayName ?? "that take")."
    }

    private func judge(_ disposition: TakeDisposition?,
                       of take: GenerationRecord,
                       mark: CurationMark?) {
        guard let disposition else {
            commit(reloadKernel: false) { $0.unmark(take.id) }
            statusMessage = nil
            return
        }

        if judgingDrift {
            // The filed record is named directly rather than read back through
            // `currentTake`, which is still — correctly — the take being
            // performed. Asking "what's current" after filing was what made this
            // mark the wrong thing once the transport stopped being disturbed.
            guard let variation = keepThisPass() else { return }
            commit(reloadKernel: false) { $0.mark(variation.id, as: disposition) }
            driftPassMark = (takeID: take.id, pass: liveState.mutationPass, disposition: disposition)
            let parentMark = take.latestMark?.disposition.label ?? "unjudged"
            statusMessage = "\(disposition.label) — \(variation.derivationLabel), "
                + "from a take you called \(parentMark.lowercased()). Still playing."
            return
        }

        commit(reloadKernel: false) { state in
            state.judge(take.id, as: disposition, aspects: mark?.aspects ?? [])
        }
        refillAdvances()
        if let parent = liveState.parentMark(of: take) {
            statusMessage = "\(disposition.label) — \(take.derivationLabel) of a take "
                + "you called \(parent.disposition.label.lowercased())."
        } else {
            statusMessage = "\(disposition.label) — pass \(state.curationPass)."
        }
    }

    /// What this take was made from, and what was decided about that.
    @ViewBuilder
    private func lineage(of take: GenerationRecord) -> some View {
        if let parent = state.parent(of: take) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.up.right")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(take.derivationLabel) of \(parent.displayName)")
                    .lineLimit(1)
                if let parentMark = parent.latestMark {
                    Text("· parent: \(parentMark.disposition.label)")
                        .fontWeight(.semibold)
                } else {
                    Text("· parent unjudged")
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .foregroundStyle(theme.textMuted)
        } else {
            let derived = state.variations(of: take.id)
            if !derived.isEmpty {
                // A take that records this one as its parent, whether it came
                // from a variant, a morph or a kept drift roll. "Variation" was
                // a fourth word for the same thing.
                Text("\(derived.count) take\(derived.count == 1 ? "" : "s") came from this one.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }
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
                            VariantRow(
                                variant: variant,
                                theme: theme,
                                onAudition: { play(variant) },
                                onMorphTarget: {
                                    // Only a line has a degree-relative form to
                                    // morph through; a comp's variants are the
                                    // morph.
                                    if let pattern = variant.material.patternIfLine {
                                        morphTarget = pattern
                                        morphRhythm = 0.5
                                        morphPitch = 0.5
                                    }
                                },
                                onJudge: { judge(variant, as: $0) },
                                disposition: variantMarks[variant.id]
                            )
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
                    PianoRoll(notes: MelodyPatterns.realize(morphed, over: changes,
                                                            leading: liveState.voiceLeading),
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
                                                parent: take.notes,
                                                seed: take.id.uuidStableSeed,
                                                leading: liveState.voiceLeading)
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
    /// Judges a variant, which first has to make it a take.
    ///
    /// A disposition is recorded against a take, and until it's judged a variant
    /// is only a candidate — so answering one commits it (the same commit
    /// auditioning does) and marks that. Keeping a transform that improved a
    /// pattern is how the improvement reaches the library instead of being lost
    /// when the variant list is regenerated.
    private func judge(_ variant: MelodyVariant, as disposition: TakeDisposition?) {
        guard let disposition else {
            variantMarks[variant.id] = nil
            if let existing = liveState.currentTake?.id {
                commit(reloadKernel: false) { $0.unmark(existing) }
            }
            return
        }

        // The parent's mark is the context: judging a variant is judging the
        // step away from something already judged, and saying both makes the
        // comparison legible instead of implied.
        let parentMark = liveState.currentTake?.latestMark?.disposition
        play(variant)
        variantMarks[variant.id] = disposition
        guard let take = liveState.currentTake else { return }
        commit(reloadKernel: false) { $0.mark(take.id, as: disposition, aspects: []) }
        if let parentMark, parentMark != disposition {
            statusMessage = "\(variant.transform): \(disposition.label.lowercased())"
                + " — from a take you called \(parentMark.label.lowercased())."
        } else {
            statusMessage = "\(variant.transform): \(disposition.label.lowercased())"
                + " — kept as a take, so it counts toward what's learned."
        }
    }

    private func play(_ variant: MelodyVariant) {
        // The take being varied, captured before committing anything: `add`
        // moves `currentTake` on, so asking afterwards names the variant itself.
        let parent = liveState.currentTake
        switch variant.material {
        case .line(let pattern):
            play(pattern, describedAs: variant.transform, derivedFrom: parent)
        case .voiced(let notes, let summary):
            playVoiced(notes, named: variant.name, describedAs: summary, derivedFrom: parent)
        }
    }

    /// Commits already-realized polyphonic notes as a take.
    /// - Parameter derivedFrom: the take this was varied from, so the new take
    ///   carries the relationship and can be judged against its parent's mark.
    private func playVoiced(_ notes: [SequencedNote],
                            named name: String,
                            describedAs detail: String,
                            derivedFrom parent: GenerationRecord? = nil) {
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
            parentTakeID: parent?.id,
            derivation: parent == nil ? "" : name,
            lengthBeats: progression.totalBeats,
            notes: notes
        )
        commit { $0.add(record) }
        statusMessage = "\(name) — \(detail)."
    }

    /// Commits a pattern as a take so it can be heard and judged like any other.
    /// - Parameter derivedFrom: the take this was varied from. A variant, a
    ///   mutation and a morph are all steps away from something already judged,
    ///   and the judgement made about them is about the step.
    private func play(_ pattern: MelodyPattern,
                      describedAs description: String,
                      source: TakeSource = .mutated,
                      derivedFrom parent: GenerationRecord? = nil) {
        let current = liveState
        guard let progression = try? ChordProgression.parse(current.progressionText) else { return }
        let notes = realize(pattern, over: progression)
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
            parentTakeID: parent?.id,
            derivation: parent == nil ? "" : description,
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
                    // the long context to mean anything. Low is not a bug — and
                    // "order-2 usable: 34%" is a fact about the implementation
                    // rather than about the music, so it says what it means.
                    Text(chainConfidence(chain.trustedShare))
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
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
                HStack(spacing: MelGenMetrics.space2) {
                    exportButton
                    importButton
                }
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

    /// Reads a history file back in.
    ///
    /// The counterpart to exporting, and the reason exporting is worth doing: a
    /// library that can only leave is a log. Merging is by take id, so importing
    /// the same file twice changes nothing and two overlapping sessions join up
    /// instead of doubling.
    private var importButton: some View {
        Button {
            isImporting = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                Text("Import history")
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
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: true) { result in
            importHistoryFiles(result)
        }
    }

    /// Merges every chosen file, reporting what happened across all of them.
    ///
    /// The plug-in isn't the document's owner, so each URL has to be opened
    /// inside a security scope — without it the read fails with a permission
    /// error that looks like a corrupt file.
    private func importHistoryFiles(_ result: Result<[URL], any Error>) {
        switch result {
        case .failure(let error):
            statusMessage = "Import failed: \(error.localizedDescription)"
        case .success(let urls):
            var total = MelGenState.ImportSummary(added: 0, alreadyHere: 0, reunited: 0)
            var failures: [String] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let export = try MelGenState.importHistory(from: data)
                    var summary = MelGenState.ImportSummary(added: 0, alreadyHere: 0, reunited: 0)
                    commit(reloadKernel: false) { summary = $0.importHistory(export) }
                    total.added += summary.added
                    total.alreadyHere += summary.alreadyHere
                    total.reunited += summary.reunited
                } catch {
                    failures.append(url.lastPathComponent)
                }
            }
            statusMessage = failures.isEmpty
                ? total.sentence
                : total.sentence + " Couldn't read \(failures.joined(separator: ", "))."
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
    /// Realizes a pattern the way the current mode wants it heard.
    ///
    /// Every deterministic source produces a `MelodyPattern`, and a pattern is
    /// monophonic by construction — so each of them played a mono line in chord
    /// mode, which is a mode switch that only some of the buttons honoured. This
    /// is the one place that decides, so a seventh source can't reintroduce it:
    /// in chord mode the pattern's rhythm is kept and voicings are laid under it,
    /// voice-led, exactly as re-voicing a comp does.
    ///
    /// Qualified on purpose. An unqualified `realize(pattern, over:)` here is a
    /// call to *this* function, which recurses until the stack runs out — and it
    /// compiles, because the signature matches.
    private func realize(_ pattern: MelodyPattern,
                         over progression: ChordProgression) -> [SequencedNote] {
        let notes = MelodyPatterns.realize(pattern, over: progression,
                                           leading: liveState.voiceLeading)
        guard liveState.mode == .comping, !notes.isEmpty else { return notes }
        let voiced = MelodyComping.revoice(notes,
                                           over: progression,
                                           as: .rootlessA,
                                           voices: 3,
                                           leading: liveState.voiceLeading)
        return voiced.isEmpty ? notes : voiced
    }

    /// What a take made this way should be labelled as, so the history doesn't
    /// call a voiced draw a line.
    private func source(_ line: TakeSource) -> TakeSource {
        liveState.mode == .comping ? .comping : line
    }

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
        let notes = realize(pattern, over: progression)
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
                                            contours: template.gestureContours,
                                            density: template.density,
                                            restiness: template.restiness,
                                            architecture: template.architecture,
                                            palette: current.durationPalette)

        let notes = realize(pattern, over: progression)
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

        let notes = realize(pattern, over: progression)
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
            source: source(current.learnedDraw == .slots ? .sampled : .chained),
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
    /// Swaps a held take in on the next lap when auto-regeneration isn't running.
    ///
    /// Auto owns the boundary while it's on, and two writers to `pendingTake`
    /// would race — so this is deliberately the *same* rule for the times auto is
    /// off, rather than a second path that also runs when it's on.
    private func runPendingSwap() async {
        guard pendingTake != nil, !liveState.autoRegenerate else { return }
        while !Task.isCancelled, let ready = pendingTake {
            try? await Task.sleep(for: .milliseconds(120))
            guard !liveState.autoRegenerate else { return }
            guard let pass = audioUnit?.currentPass else { return }
            guard pass > pendingReadyPass else { continue }
            let aim = pendingAim
            pendingTake = nil
            pendingAim = nil
            commit {
                $0.add(ready)
                if aim == .somethingElse { $0.briefCursor += 1 }
            }
            refillAdvances()
            return
        }
    }

    private func runAutoRegeneration() async {
        guard state.autoRegenerate else { return }

        // Nothing to loop yet: put music under the changes within a beat, rather
        // than half a minute of silence while the model thinks. Which *kind* of
        // music depends on the mode — this loop used to compose a line whatever
        // the mode said, so an unattended session in chord mode played melodies
        // and never touched a comping figure.
        if liveState.currentTake == nil {
            if liveState.mode == .comping { compChanges() } else { composeLine() }
        }
        var lastStartedPass = audioUnit?.currentPass ?? 0
        var lastFilledPass = audioUnit?.currentPass ?? 0

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            let current = liveState
            guard current.autoRegenerate else { return }
            guard let pass = audioUnit?.currentPass else { continue }

            let due = current.isDue(pass: pass, since: lastStartedPass)

            // A model take finished during the last loop: it wins, so swap it in
            // now the loop has come round.
            if let ready = pendingTake, pass > pendingReadyPass {
                let aim = pendingAim
                pendingTake = nil
                pendingAim = nil
                commit {
                    $0.add(ready)
                    // An aimed advance only moves the rotation when that is what
                    // it promised; a model take that nobody aimed still does.
                    if aim == nil || aim == .somethingElse { $0.briefCursor += 1 }
                }
                statusMessage = "\(ready.briefName): \(ready.noteCount) notes"
                    + timingNote(for: ready)
                lastFilledPass = pass
            } else if due, pass > lastFilledPass {
                // Nothing from the model yet. Rather than repeat the same take
                // until it arrives, put something new under the changes —
                // instant, and it keeps them moving while the model works.
                //
                // In chord mode that's the next comping figure, which is how
                // chord mode cycles its templates at all: comping needs no model,
                // so this path is the one that runs, and each pass through it
                // advances the rotation. In line mode, alternating between a
                // fresh phrase and a stored one is what stops an unattended
                // session settling into either the same six lines or the same one
                // grammar.
                let filler: GenerationRecord?
                if liveState.mode == .comping {
                    filler = compChanges(commitNow: false)
                } else {
                    filler = liveState.patternCursor.isMultiple(of: 2)
                        ? composeLine(commitNow: false)
                        : adaptStoredLine(commitNow: false)
                }
                if let filler {
                    commit { $0.add(filler) }
                    statusMessage = "\(filler.briefName) (\(filler.source.label)) — model still working…"
                }
                lastFilledPass = pass
            }

            if due, !isGenerating, pendingTake == nil {
                lastStartedPass = pass
                // Comping is instant and needs no model, so the filler above has
                // already produced this loop's comp. Asking the model for one as
                // well would queue a take that lands a loop later and silently
                // overwrite a figure the rotation had already moved past.
                if liveState.mode != .comping {
                    generate(auto: true, holdForLoopPoint: true)
                }
            }
        }
    }

    /// Moves the playhead while the transport runs, and clears it when it stops.
    ///
    /// Twenty times a second is enough to read as continuous at any tempo the
    /// plug-in is useful at, and the task only exists while playing — a stopped
    /// transport costs nothing. The position comes from the render thread rather
    /// than being counted here, so it can't drift away from what's sounding.
    private func followPlayhead() async {
        guard playParameter.boolValue else {
            playheadBeat = nil
            return
        }
        while !Task.isCancelled {
            playheadBeat = audioUnit?.loopPhaseBeats
            try? await Task.sleep(for: .milliseconds(50))
        }
        playheadBeat = nil
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
                if failure.isSystemwide { modelIsDown = true }

                if failure.isTransient, !failure.isSystemwide, !auto {
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
