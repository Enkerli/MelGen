//
//  MelGenExtensionAudioUnit.swift
//  MelGenExtension
//
//  MelGen's half of the audio unit: the session, and what the kernel should be
//  playing out of it.
//
//  `PluginAudioUnit` is the shell — kernel, parameter tree, transport readings,
//  capture ring — and knows nothing about melody. Everything MelGen-specific in
//  the class before the two were separated is here, which is PORTING.md's
//  `MelGenExtensionAudioUnit → MelGenState` and `→ SetupStore` seams: a plug-in's
//  session type is the plug-in's, and the shell was naming MelGen's. A sibling
//  plug-in writes a file this shape and inherits the other ~900 lines.
//
//  Nothing here changed when it moved. `fullState` still round-trips the same
//  JSON under the same key, so a session saved by a build before the split
//  reopens in one after it.
//

import AVFoundation

public final class MelGenExtensionAudioUnit: PluginAudioUnit, @unchecked Sendable {

    // MARK: - Session state
    //
    // The progression, generation settings and take history live here rather
    // than in the SwiftUI view, so they survive the view being torn down and can
    // be written into the audio unit's full state. Access is locked because the
    // host may ask for full state from a different thread than the UI.

    /// Which take the kernel is currently playing, so a re-render can be told
    /// apart from a change of material.
    private var lastLoadedTakeID: UUID?

    private let stateLock = NSLock()

    /// A fresh instance starts from the default setup, when one is marked.
    ///
    /// Here rather than in the view, and only for a *new* audio unit: a host
    /// restoring `fullState` assigns over this, so reopening a project keeps the
    /// settings that project was saved with. "The way I usually work" applies to
    /// the instance you just added, not to one you're getting back.
    private var _state: MelGenState = {
        var state = MelGenState()
        if let setup = SetupStore.defaultSetup { state.apply(setup) }
        return state
    }()

    var state: MelGenState {
        get { stateLock.withLock { _state } }
        set { update(state: newValue) }
    }

    /// - Parameter reloadKernel: pass `false` for edits that can't change the
    ///   notes (typing in the progression field), so the render thread isn't
    ///   handed a new sequence on every keystroke.
    func update(state newState: MelGenState, reloadKernel: Bool = true) {
        stateLock.withLock { _state = newState }
        if reloadKernel {
            loadCurrentTakeIntoKernel(newState)
        }
    }

    /// Renders the current take with its expression settings and hands it to the
    /// kernel. A take with no notes leaves the kernel's sequence alone.
    private func loadCurrentTakeIntoKernel(_ state: MelGenState) {
        guard let take = state.currentTake else { return }
        // A different take starts from its own beginning; the same take being
        // re-rendered — which is what every expression slider does — carries on
        // from where the loop already is, so touching a control doesn't jump the
        // playhead back to the top.
        let isNewTake = take.id != lastLoadedTakeID
        lastLoadedTakeID = take.id
        setMelody(state.renderedMelody, lengthBeats: take.lengthBeats, restartFromTop: isNewTake)
    }

    private static let stateKey = "MelGen.sessionState"

    public override var fullState: [String: Any]? {
        get {
            var dictionary = super.fullState ?? [:]
            if let data = try? JSONEncoder().encode(state) {
                dictionary[Self.stateKey] = data
            }
            return dictionary
        }
        set {
            super.fullState = newValue
            guard let data = newValue?[Self.stateKey] as? Data,
                  let restored = try? JSONDecoder().decode(MelGenState.self, from: data) else {
                return
            }
            // Assigning through `state` also reloads the kernel's sequence, so a
            // reopened session plays without the UI having to be shown.
            state = restored
        }
    }

    /// Hosts save session documents through this rather than `fullState`; for
    /// MelGen the two are the same thing.
    public override var fullStateForDocument: [String: Any]? {
        get { fullState }
        set { fullState = newValue }
    }
}
