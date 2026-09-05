//
//  PluginAudioUnit.swift
//  MelGenExtension
//
//  The AU half of a plug-in: the kernel, the parameter tree, the transport
//  readings and the capture ring. No session state, no melody, no MelGen.
//
//  It was `MelGenExtensionAudioUnit` and it held both halves, which is
//  PORTING.md's `MelGenExtensionAudioUnit → MelGenState` and `→ SetupStore`
//  seams: the shell may not reach up into the app, and it was reaching for the
//  app's entire session type. What is left here is the ~900 lines PORTING.md §2
//  measures against enkerli-juce's 921, and a sibling plug-in subclasses it the
//  way MelGen now does — see MelGenExtensionAudioUnit.swift.
//

import AVFoundation
import Carrier

public class PluginAudioUnit: AUAudioUnit, @unchecked Sendable
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
