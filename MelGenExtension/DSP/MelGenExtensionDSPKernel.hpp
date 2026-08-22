//
//  MelGenExtensionDSPKernel.hpp
//  MelGenExtension
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

#pragma once

#import <AudioToolbox/AudioToolbox.h>
#import <CoreMIDI/MIDIMessages.h>

#import <algorithm>
#import <atomic>
#import <cmath>
#import <vector>

#import "MelGenExtensionParameterAddresses.h"

/*
 MelGenExtensionDSPKernel
 As a non-ObjC class, this is safe to use from render thread.
 */
class MelGenExtensionDSPKernel {
public:
    void initialize(double inSampleRate) {
        mSampleRate = inSampleRate;
    }
    
    void deInitialize() {
        // Drop the host-supplied blocks so a stale one can never be called
        // after the host has torn down its render resources.
        mMIDIOutBlock = nullptr;
        mLegacyMIDIOutBlock = nullptr;
        mMusicalContextBlock = nullptr;
    }
    
    // MARK: - Bypass
    bool isBypassed() {
        return mBypassed;
    }
    
    void setBypass(bool shouldBypass) {
        mBypassed = shouldBypass;
    }
    
    // MARK: - Parameter Getter / Setter
    // Add a case for each parameter in MelGenExtensionParameterAddresses.h
    void setParameter(AUParameterAddress address, AUValue value) {
        switch (address) {
            case MelGenExtensionParameterAddress::playMelody:
                mPlayMelody = (bool)value;
                break;
            case MelGenExtensionParameterAddress::playbackDirection:
                mDirection = (MelGenPlaybackDirection)(int)std::round(value);
                break;
            case MelGenExtensionParameterAddress::hostSync:
                mHostSync = (bool)value;
                break;
        }
    }

    AUValue getParameter(AUParameterAddress address) {
        // Return the goal. It is not thread safe to return the ramping value.

        switch (address) {
            case MelGenExtensionParameterAddress::playMelody:
                return (AUValue)mPlayMelody;

            case MelGenExtensionParameterAddress::playbackDirection:
                return (AUValue)mDirection;

            case MelGenExtensionParameterAddress::hostSync:
                return (AUValue)mHostSync;

            default: return 0.f;
        }
    }
    
    // MARK: - Maximum Frames To Render
    AUAudioFrameCount maximumFramesToRender() const {
        return mMaxFramesToRender;
    }
    
    void setMaximumFramesToRender(const AUAudioFrameCount &maxFrames) {
        mMaxFramesToRender = maxFrames;
    }
    
    // MARK: - Musical Context
    void setMusicalContextBlock(AUHostMusicalContextBlock contextBlock) {
        mMusicalContextBlock = contextBlock;
    }
    
    // MARK: - MIDI Output
    //
    // A host supplies whichever of these two blocks it supports: the UMP-based
    // event list block (MIDI 2.0 capable hosts) or the byte-based legacy block.
    // Both may be nil until the host has connected our MIDI output, in which
    // case the kernel emits nothing.
    void setMIDIOutputEventBlock(AUMIDIEventListBlock midiOutBlock) {
        mMIDIOutBlock = midiOutBlock;
    }

    void setLegacyMIDIOutputEventBlock(AUMIDIOutputEventBlock midiOutBlock) {
        mLegacyMIDIOutBlock = midiOutBlock;
    }

    bool hasMIDIOutput() const {
        return mMIDIOutBlock != nullptr || mLegacyMIDIOutBlock != nullptr;
    }

    // MARK: - MIDI Protocol
    MIDIProtocolID AudioUnitMIDIProtocol() const {
        return kMIDIProtocol_2_0;
    }
    
    // MARK: - Melody Sequence (UI-thread setters, render-thread reader)
    //
    // The sequence is double-buffered: the UI thread writes into the inactive
    // buffer, then commitSequence() atomically flips which buffer the render
    // thread reads. Buffers are fixed-size, so there is never an allocation
    // or dangling pointer visible to the render thread.
    
    static constexpr uint32_t kMaxSequenceNotes = 512;
    static constexpr uint32_t kMaxActiveNotes = 64;
    
    struct SequenceNote {
        double startBeat = 0;
        double endBeat = 0;
        uint8_t note = 0;
        uint8_t velocity = 0; // 0-127
    };
    
    void beginSequenceUpdate() {
        mStagingIndex = 1 - mShared.activeIndex.load(std::memory_order_acquire);
        mSequenceCounts[mStagingIndex] = 0;
    }
    
    void appendSequenceNote(double startBeat, double durationBeats, uint8_t note, uint8_t velocity) {
        uint32_t &count = mSequenceCounts[mStagingIndex];
        if (count >= kMaxSequenceNotes) { return; }
        mSequences[mStagingIndex][count] = { startBeat, startBeat + durationBeats, note, velocity };
        count += 1;
    }
    
    void commitSequence(double lengthBeats) {
        mSequenceLengths[mStagingIndex] = std::max(lengthBeats, 0.25);
        mShared.activeIndex.store(mStagingIndex, std::memory_order_release);
    }
    
    /**
     MARK: - Internal Process
     
     This function does the core MIDI processing:
     it plays back the committed melody sequence, looped, following the host tempo.
     */
    void process(AUEventSampleTime bufferStartTime, AUAudioFrameCount frameCount) {

        if (mBypassed) { return; }

        // Ask the host for tempo and playhead position; fall back to the last
        // known tempo, and note whether the beat position is usable at all.
        mHostBeatValid = false;
        if (mMusicalContextBlock) {
            double tempo = 0;
            double beatPosition = 0;
            if (mMusicalContextBlock(&tempo,
                                     nullptr /* timeSignatureNumerator */,
                                     nullptr /* timeSignatureDenominator */,
                                     &beatPosition,
                                     nullptr /* sampleOffsetToNextBeat */,
                                     nullptr /* currentMeasureDownbeatPosition */)) {
                if (tempo > 0) { mTempo = tempo; }
                mHostBeat = beatPosition;
                mHostBeatValid = true;
            }
        }

        processMelody(bufferStartTime, frameCount);
    }

    void processMelody(AUEventSampleTime bufferStartTime, AUAudioFrameCount frameCount) {
        if (!hasMIDIOutput()) { return; }

        // Handle transport transitions of the playMelody parameter.
        if (mPlayMelody && !mMelodyPlaying) {
            mTimelineBeats = 0;
            mHostBeatInitialized = false;
            mMelodyPlaying = true;
        } else if (!mPlayMelody && mMelodyPlaying) {
            releaseAllNotes(bufferStartTime);
            mMelodyPlaying = false;
        }

        if (!mMelodyPlaying) { return; }

        const double beatsPerFrame = mTempo / 60.0 / mSampleRate;
        if (beatsPerFrame <= 0) { return; }
        const double bufferBeats = double(frameCount) * beatsPerFrame;

        // Work out the window of timeline beats this buffer covers. When synced,
        // the window comes from the host's playhead so we follow its transport,
        // tempo map and locates; otherwise we advance our own playhead.
        double windowStart = mTimelineBeats;
        double windowEnd = mTimelineBeats + bufferBeats;

        if (mHostSync && mHostBeatValid) {
            if (!mHostBeatInitialized) {
                // First synced buffer: latch the host position, emit nothing.
                mHostBeatInitialized = true;
                mTimelineBeats = mHostBeat;
                return;
            }
            windowStart = mTimelineBeats;
            windowEnd = mHostBeat;

            // A stopped host repeats the same position, and a locate jumps it.
            // Either way, release what is sounding and resync without emitting.
            const bool stalled = windowEnd <= windowStart;
            const bool jumped = (windowEnd - windowStart) > bufferBeats * 4.0 + 1e-9;
            if (stalled || jumped) {
                releaseAllNotes(bufferStartTime);
                mTimelineBeats = windowEnd;
                return;
            }
        } else {
            mHostBeatInitialized = false;
        }

        // Note-offs first, so a note re-triggered at the loop point is released
        // before its next note-on.
        for (uint32_t i = 0; i < mActiveCount;) {
            if (mActiveNotes[i].offBeat < windowEnd) {
                const double offset = std::max(0.0, mActiveNotes[i].offBeat - windowStart) / beatsPerFrame;
                sendNoteOff(bufferStartTime + AUEventSampleTime(offset), mActiveNotes[i].note, 0);
                mActiveNotes[i] = mActiveNotes[mActiveCount - 1];
                mActiveCount -= 1;
            } else {
                i += 1;
            }
        }

        scheduleNotes(bufferStartTime, windowStart, windowEnd, beatsPerFrame);
        mTimelineBeats = windowEnd;
        publishPassIndex(windowEnd);
    }

    /// How many complete loop passes have played. The UI polls this to know when
    /// a take has finished, so it can queue up the next one.
    int64_t currentPass() const {
        return mShared.passIndex.load(std::memory_order_relaxed);
    }

    void publishPassIndex(double timelineBeats) {
        mShared.tempo.store(mTempo, std::memory_order_relaxed);
        const uint32_t seq = mShared.activeIndex.load(std::memory_order_acquire);
        const double loopLength = mSequenceLengths[seq];
        if (loopLength <= 0) { return; }
        mShared.loopBeats.store(loopLength, std::memory_order_relaxed);
        mShared.passIndex.store((int64_t)std::floor(timelineBeats / loopLength),
                                std::memory_order_relaxed);
    }

    /// Tempo and loop length as the render thread sees them, so the UI can say
    /// how long a loop lasts in seconds.
    double currentTempo() const {
        return mShared.tempo.load(std::memory_order_relaxed);
    }

    double currentLoopBeats() const {
        return mShared.loopBeats.load(std::memory_order_relaxed);
    }

    /**
     Emits note-ons for every occurrence of a sequence note in the timeline
     window [windowStart, windowEnd).

     The sequence loops, and each pass through the loop plays either forwards or
     reversed depending on the direction parameter. A reversed pass is a true
     time-reversal: a note occupying [s, e) of a loop of length L plays at
     [L - e, L - s). The window can straddle a loop boundary, so it is walked one
     pass at a time.
     */
    void scheduleNotes(AUEventSampleTime bufferStartTime, double windowStart, double windowEnd, double beatsPerFrame) {
        const uint32_t seq = mShared.activeIndex.load(std::memory_order_acquire);
        const double loopLength = mSequenceLengths[seq];
        const uint32_t noteCount = mSequenceCounts[seq];
        if (noteCount == 0 || loopLength <= 0) { return; }

        double cursor = windowStart;
        while (cursor < windowEnd) {
            const double passIndex = std::floor(cursor / loopLength);
            const double passStart = passIndex * loopLength;
            const double segmentEnd = std::min(windowEnd, passStart + loopLength);
            const bool reversed = isReversedPass((int64_t)passIndex);
            const double phaseStart = cursor - passStart;
            const double phaseEnd = segmentEnd - passStart;

            for (uint32_t i = 0; i < noteCount; ++i) {
                const SequenceNote &event = mSequences[seq][i];
                const double duration = event.endBeat - event.startBeat;
                const double phase = reversed ? (loopLength - event.endBeat) : event.startBeat;
                if (duration <= 0 || phase < 0 || phase >= loopLength) { continue; }
                if (phase < phaseStart || phase >= phaseEnd) { continue; }

                const double occurrence = passStart + phase;
                const AUEventSampleTime time =
                    bufferStartTime + AUEventSampleTime((occurrence - windowStart) / beatsPerFrame);
                startActiveNote(time, event.note, event.velocity, occurrence + duration);
            }

            cursor = segmentEnd;
        }
    }

    bool isReversedPass(int64_t passIndex) const {
        switch (mDirection) {
            case MelGenPlaybackDirectionBackward:
                return true;
            case MelGenPlaybackDirectionPingPong:
                // Alternate passes, so the loop turns around at both ends.
                return (passIndex % 2) != 0;
            default:
                return false;
        }
    }

    void releaseAllNotes(AUEventSampleTime time) {
        for (uint32_t i = 0; i < mActiveCount; ++i) {
            sendNoteOff(time, mActiveNotes[i].note, 0);
        }
        mActiveCount = 0;
    }

    void startActiveNote(AUEventSampleTime time, uint8_t note, uint8_t velocity, double offBeat) {
        // If this pitch is already sounding, release it to avoid a stuck note.
        for (uint32_t i = 0; i < mActiveCount; ++i) {
            if (mActiveNotes[i].note == note) {
                sendNoteOff(time, note, 0);
                sendNoteOn(time, note, uint16_t(velocity) * 516);
                mActiveNotes[i].offBeat = offBeat;
                return;
            }
        }
        if (mActiveCount >= kMaxActiveNotes) { return; }
        sendNoteOn(time, note, uint16_t(velocity) * 516);
        mActiveNotes[mActiveCount] = { offBeat, note };
        mActiveCount += 1;
    }
    
    void sendNoteOn(AUEventSampleTime sampleTime, uint8_t noteNum, uint16_t velocity) {
        if (mMIDIOutBlock) {
            auto message = MIDI2NoteOn(0, 0, noteNum, 0, 0, velocity);
            MIDIEventList eventList = {};
            MIDIEventPacket *packet = MIDIEventListInit(&eventList, kMIDIProtocol_2_0);
            packet = MIDIEventListAdd(&eventList, sizeof(MIDIEventList), packet, 0, 2, (UInt32 *)&message);
            mMIDIOutBlock(sampleTime, 0, &eventList);
        } else if (mLegacyMIDIOutBlock) {
            const uint8_t bytes[3] = { 0x90, noteNum, midi1Velocity(velocity) };
            mLegacyMIDIOutBlock(sampleTime, 0, sizeof(bytes), bytes);
        }
    }

    void sendNoteOff(AUEventSampleTime sampleTime, uint8_t noteNum, uint16_t velocity) {
        if (mMIDIOutBlock) {
            auto message = MIDI2NoteOff(0, 0, noteNum, 0, 0, velocity);
            MIDIEventList eventList = {};
            MIDIEventPacket *packet = MIDIEventListInit(&eventList, kMIDIProtocol_2_0);
            packet = MIDIEventListAdd(&eventList, sizeof(MIDIEventList), packet, 0, 2, (UInt32 *)&message);
            mMIDIOutBlock(sampleTime, 0, &eventList);
        } else if (mLegacyMIDIOutBlock) {
            const uint8_t bytes[3] = { 0x80, noteNum, midi1Velocity(velocity) };
            mLegacyMIDIOutBlock(sampleTime, 0, sizeof(bytes), bytes);
        }
    }

    // MIDI 2.0 velocities are 16-bit; MIDI 1.0 wants the top 7 bits.
    static uint8_t midi1Velocity(uint16_t velocity) {
        return uint8_t(velocity >> 9);
    }
    
    void handleOneEvent(AUEventSampleTime now, AURenderEvent const *event) {
        switch (event->head.eventType) {
            case AURenderEventParameter: {
                handleParameterEvent(now, event->parameter);
                break;
            }
                
            case AURenderEventMIDIEventList: {
                handleMIDIEventList(now, &event->MIDIEventsList);
                break;
            }
                
            default:
                break;
        }
    }

    void handleMIDIEventList(AUEventSampleTime now, AUMIDIEventList const* midiEvent) {
        // Pass incoming MIDI through unchanged.
        if (mMIDIOutBlock)
        {
            mMIDIOutBlock(now, 0, &midiEvent->eventList);
        }
    }
    
    void handleParameterEvent(AUEventSampleTime now, AUParameterEvent const& parameterEvent) {
        setParameter(parameterEvent.parameterAddress, parameterEvent.value);
    }
    
    // MARK: Member Variables
    AUHostMusicalContextBlock mMusicalContextBlock;
    
    double mSampleRate = 44100.0;
    double mTempo = 120.0;
    bool mBypassed = false;
    AUAudioFrameCount mMaxFramesToRender = 1024;
    
    AUMIDIEventListBlock mMIDIOutBlock;
    AUMIDIOutputEventBlock mLegacyMIDIOutBlock;

    // Melody playback state
    struct ActiveNote {
        double offBeat = 0; // timeline beat at which to release
        uint8_t note = 0;
    };

    // Transport parameters
    bool mPlayMelody = false;
    bool mHostSync = false;
    MelGenPlaybackDirection mDirection = MelGenPlaybackDirectionForward;

    bool mMelodyPlaying = false;   // render-thread playback state
    double mTimelineBeats = 0;     // position the last buffer ended at
    double mHostBeat = 0;          // host playhead, this buffer
    bool mHostBeatValid = false;   // did the host give us a position?
    bool mHostBeatInitialized = false;
    ActiveNote mActiveNotes[kMaxActiveNotes];
    uint32_t mActiveCount = 0;

    SequenceNote mSequences[2][kMaxSequenceNotes];
    uint32_t mSequenceCounts[2] = {0, 0};
    double mSequenceLengths[2] = {0, 0};
    uint32_t mStagingIndex = 1;

    // Fields shared across threads, gathered in one place because std::atomic is
    // neither copyable nor movable: a bare atomic member makes the whole kernel
    // un-importable by Swift's C++ interop (the type simply disappears from
    // Swift's view). This copyable holder keeps the kernel usable as a stored
    // property in MelGenExtensionAudioUnit.
    struct SharedFields {
        /// Which sequence buffer the render thread reads (UI thread writes).
        std::atomic<uint32_t> activeIndex{0};
        /// How many complete loop passes have played (render thread writes, the
        /// UI reads it to drive auto-regeneration).
        std::atomic<int64_t> passIndex{0};
        /// The tempo the render thread is working from, so the UI can work out
        /// how long a loop actually lasts and whether generation fits inside one.
        std::atomic<double> tempo{120.0};
        /// Loop length in beats, for the same reason.
        std::atomic<double> loopBeats{0};

        SharedFields() = default;
        SharedFields(const SharedFields &other)
        : activeIndex{other.activeIndex.load(std::memory_order_acquire)},
          passIndex{other.passIndex.load(std::memory_order_acquire)},
          tempo{other.tempo.load(std::memory_order_relaxed)},
          loopBeats{other.loopBeats.load(std::memory_order_relaxed)} {}
        SharedFields &operator=(const SharedFields &other) {
            activeIndex.store(other.activeIndex.load(std::memory_order_acquire), std::memory_order_release);
            passIndex.store(other.passIndex.load(std::memory_order_acquire), std::memory_order_release);
            tempo.store(other.tempo.load(std::memory_order_relaxed), std::memory_order_relaxed);
            loopBeats.store(other.loopBeats.load(std::memory_order_relaxed), std::memory_order_relaxed);
            return *this;
        }
    };

    SharedFields mShared;
};
