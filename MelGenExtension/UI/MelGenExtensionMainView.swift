//
//  MelGenExtensionMainView.swift
//  MelGenExtension
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

import SwiftUI

// No #Preview here: Xcode can't host previews inside a
// "com.apple.AudioUnit-UI" app extension, so the layout is checked in a host.

struct MelGenExtensionMainView: View {
    var parameterTree: ObservableAUParameterGroup
    weak var audioUnit: MelGenExtensionAudioUnit?

    /// Mirror of the audio unit's session state. The audio unit owns the master
    /// copy so it survives this view and lands in the host's saved session.
    @State private var state = MelGenState()
    @State private var statusMessage: String?
    @State private var isGenerating = false
    @State private var savedExampleIDs: Set<UUID> = []

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

                transportSection
                shapeSection
                feelSection

                if state.currentTake != nil {
                    currentTakeSection
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

    private var progressionSection: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            Eyebrow(text: "Progression", theme: theme)

            HStack(spacing: MelGenMetrics.space2) {
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
                    .onSubmit { generate() }
                    .accessibilityLabel("Chord progression")

                Button {
                    generate()
                } label: {
                    HStack(spacing: 6) {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(theme.accentText)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(isGenerating ? "Working" : "Generate")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, MelGenMetrics.space3)
                    .frame(height: MelGenMetrics.controlHeight)
                    .foregroundStyle(generateEnabled ? theme.accentText : theme.textDisabled)
                    .background(
                        RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .fill(generateEnabled ? theme.accent : theme.sunken)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!generateEnabled)
            }
        }
    }

    private var generateEnabled: Bool {
        !isGenerating && !state.progressionText.isEmpty
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
                               format: { "\(MelodyGenerator.notesPerBar(forDensity: $0))/bar" })

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
        "\(MelodyGenerator.notesPerBar(forDensity: state.expression.density))/bar · "
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
                LabelledSlider(title: "Gate length", lowLabel: "staccato", highLabel: "legato",
                               value: binding(\.expression.noteLength), theme: theme)

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

    // MARK: - Current take

    private var currentTakeSection: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            Eyebrow(text: "Current take", theme: theme)

            Text(melodySummary)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MelGenMetrics.space2)
                .background(
                    RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .fill(theme.raised)
                )

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
                    ForEach(state.history) { take in
                        historyRow(take)
                    }
                }
            }
        }
    }

    private func historyRow(_ take: GenerationRecord) -> some View {
        let isCurrent = take.id == state.currentTake?.id
        return Button {
            commit { $0.currentTakeID = take.id }
        } label: {
            HStack(spacing: MelGenMetrics.space2) {
                Image(systemName: isCurrent ? "speaker.wave.2.fill" : "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCurrent ? theme.accent : theme.textMuted)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(take.progressionText) · \(take.briefName)")
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text("\(take.date.formatted(date: .omitted, time: .shortened)) · \(take.noteCount) notes · temp \(take.temperature.formatted(.number.precision(.fractionLength(2))))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
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

    private var melodySummary: String {
        let melody = state.renderedMelody
        guard !melody.isEmpty else { return "No notes yet." }
        return melody.map { note in
            "\(ChordProgression.noteName(forMIDINote: Int(note.note)))@\(note.startBeat.formatted(.number.precision(.fractionLength(0...1))))"
        }
        .joined(separator: " ")
    }

    // MARK: - Generation

    /// Polls the kernel's loop counter and queues a new take every few passes.
    /// The counter only advances while the melody is playing, so this idles when
    /// the transport is stopped.
    private func runAutoRegeneration() async {
        guard state.autoRegenerate else { return }

        // Nothing to loop yet: make the first take straight away.
        if liveState.currentTake == nil {
            generate(auto: true)
        }
        var lastPass = audioUnit?.currentPass ?? 0

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            let current = liveState
            guard current.autoRegenerate else { return }
            guard let pass = audioUnit?.currentPass else { continue }
            let due = pass >= lastPass + Int64(max(1, current.regenerateEveryPasses))
            if due, !isGenerating {
                lastPass = pass
                generate(auto: true)
            }
        }
    }

    private func generate(auto: Bool = false) {
        guard !isGenerating else { return }
        let current = liveState

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

        let brief = StyleBriefs.brief(at: current.briefCursor)
        let temperature = current.temperature
        let density = current.expression.density
        let durationPalette = current.durationPalette
        let progressionText = current.progressionText

        statusMessage = "Generating \(brief.name.lowercased()) take over \(progressionText)…"
        isGenerating = true

        Task {
            do {
                let notes = try await MelodyGenerator.generate(
                    for: progression,
                    temperature: temperature,
                    brief: brief,
                    density: density,
                    durationPalette: durationPalette
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
                        lengthBeats: progression.totalBeats,
                        notes: notes
                    )
                    commit {
                        $0.add(record)
                        $0.briefCursor += 1
                    }
                    statusMessage = "\(brief.name): \(notes.count) notes over \(progressionText)."
                }
            } catch {
                statusMessage = "Generation failed: \(error.localizedDescription)"
            }
            isGenerating = false
        }
    }
}
