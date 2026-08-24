//
//  MelGenExtensionAudioUnit.swift
//  MelGenExtension
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

import AVFoundation

public class MelGenExtensionAudioUnit: AUAudioUnit, @unchecked Sendable
{
	// C++ Objects
	var kernel = MelGenExtensionDSPKernel()
    var processHelper: AUProcessHelper?

	private var outputBus: AUAudioUnitBus?
	private var _outputBusses: AUAudioUnitBusArray!

	private var format:AVAudioFormat

	@objc override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions) throws {
		self.format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
		try super.init(componentDescription: componentDescription, options: options)
		outputBus = try AUAudioUnitBus(format: self.format)
        outputBus?.maximumChannelCount = 2
		_outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: AUAudioUnitBusType.output, busses: [outputBus!])
        kernel.initialize(outputBus!.format.sampleRate)
        processHelper = AUProcessHelper(&kernel)
	}

	public override var outputBusses: AUAudioUnitBusArray {
		return _outputBusses
	}
    
    public override var  maximumFramesToRender: AUAudioFrameCount {
        get {
            return kernel.maximumFramesToRender()
        }

        set {
            kernel.setMaximumFramesToRender(newValue)
        }
    }

    public override var  shouldBypassEffect: Bool {
        get {
            return kernel.isBypassed()
        }

        set {
            kernel.setBypass(newValue)
        }
    }

    // MARK: - MIDI
    public override var audioUnitMIDIProtocol: MIDIProtocolID {
        return kernel.AudioUnitMIDIProtocol()
    }

    /// Advertises a MIDI output port. Hosts only expose a MIDI output for the
    /// plug-in — and only connect `midiOutputEventListBlock` /
    /// `midiOutputEventBlock` — when this array is non-empty, so without it the
    /// kernel has nowhere to send the melody it generates.
    public override var midiOutputNames: [String] {
        return ["MelGen Out"]
    }

    // MARK: - Melody
    /// Hands a generated melody to the DSP kernel. The kernel loops it for
    /// `lengthBeats` quarter-note beats while the playMelody parameter is on.
    /// Safe to call from the main thread while rendering.
    /// - Parameter restartFromTop: begin the new sequence at its first beat.
    ///   Asked for when the take changes, not when the same take is re-rendered.
    func setMelody(_ notes: [SequencedNote], lengthBeats: Double, restartFromTop: Bool = false) {
        kernel.beginSequenceUpdate()
        for note in notes {
            kernel.appendSequenceNote(note.startBeat, note.durationBeats, note.note, note.velocity)
        }
        kernel.commitSequence(lengthBeats, restartFromTop)
    }

    /// How many complete loop passes have played. The UI polls this to decide
    /// when to generate the next take.
    // MARK: - Capture

    /// How far the UI has read into the kernel's capture ring.
    private var captureCursor: UInt64 = 0

    /// Whether incoming MIDI is being collected for learning.
    var isCapturing: Bool {
        get { kernel.isCaptureEnabled() }
        set {
            if newValue { captureCursor = kernel.capturedEventCount() }
            kernel.setCaptureEnabled(newValue)
        }
    }

    /// Everything captured since the last drain.
    ///
    /// The ring is single-writer, single-reader and lock-free: the render thread
    /// only ever appends, and this only ever reads forward from its own cursor.
    /// If playing outran the UI the oldest events are simply gone — a dropped
    /// phrase is a nuisance, a glitch on the audio thread is a bug.
    func drainCapturedEvents() -> [CapturedMIDIEvent] {
        let written = kernel.capturedEventCount()
        guard written > captureCursor else { return [] }
        let oldest = kernel.oldestCapturedEvent()
        var index = max(captureCursor, oldest)
        var events: [CapturedMIDIEvent] = []
        events.reserveCapacity(Int(written - index))
        while index < written {
            events.append(CapturedMIDIEvent(beat: kernel.capturedBeat(index),
                                            note: kernel.capturedNote(index),
                                            velocity: kernel.capturedVelocity(index),
                                            isOn: kernel.capturedIsOn(index)))
            index += 1
        }
        captureCursor = written
        return events
    }

    var currentPass: Int64 {
        kernel.currentPass()
    }

    /// Where the loop is now, in beats from its start, or nil when nothing is
    /// playing. What the piano roll's playhead follows.
    var loopPhaseBeats: Double? {
        let phase = kernel.currentPhaseBeats()
        return phase < 0 ? nil : phase
    }

    /// How long one pass through the loop lasts, in seconds, at the tempo the
    /// render thread is actually using — so the UI can say whether generating a
    /// take fits inside a loop. Nil until something has played.
    var loopDuration: TimeInterval? {
        let tempo = kernel.currentTempo()
        let beats = kernel.currentLoopBeats()
        guard tempo > 0, beats > 0 else { return nil }
        return beats / tempo * 60
    }

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

    // MARK: - Rendering
    public override var internalRenderBlock: AUInternalRenderBlock {
        return processHelper!.internalRenderBlock()
    }

    // Allocate resources required to render.
    // Subclassers should call the superclass implementation.
    public override func allocateRenderResources() throws {		
        kernel.setMusicalContextBlock(self.musicalContextBlock)
        kernel.setMIDIOutputEventBlock(self.midiOutputEventListBlock)
        kernel.setLegacyMIDIOutputEventBlock(self.midiOutputEventBlock)
        kernel.initialize(outputBus!.format.sampleRate)
		try super.allocateRenderResources()
	}

    // Deallocate resources allocated in allocateRenderResourcesAndReturnError:
    // Subclassers should call the superclass implementation.
    public override func deallocateRenderResources() {
        
        // Deallocate your resources.
        kernel.deInitialize()
        
        super.deallocateRenderResources()
    }

	public func setupParameterTree(_ parameterTree: AUParameterTree) {
		self.parameterTree = parameterTree

		// Set the Parameter default values before setting up the parameter callbacks
		for param in parameterTree.allParameters {
            kernel.setParameter(param.address, param.value)
		}

		setupParameterCallbacks()
	}

	private func setupParameterCallbacks() {
		// implementorValueObserver is called when a parameter changes value.
		parameterTree?.implementorValueObserver = { [weak self] param, value -> Void in
            self?.kernel.setParameter(param.address, value)
		}

		// implementorValueProvider is called when the value needs to be refreshed.
		parameterTree?.implementorValueProvider = { [weak self] param in
            return self!.kernel.getParameter(param.address)
		}

		// A function to provide string representations of parameter values.
		parameterTree?.implementorStringFromValueCallback = { param, valuePtr in
			guard let value = valuePtr?.pointee else {
				return "-"
			}
			return NSString.localizedStringWithFormat("%.f", value) as String
		}
	}
}
