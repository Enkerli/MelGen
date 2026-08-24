//
//  MelGenExtensionDSPKernel.hpp
//  MelGenExtension
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

#pragma once

#import <AudioToolbox/AudioToolbox.h>
#import <CoreMIDI/MIDIMessages.h>
#import <CoreMIDI/MIDIServices.h>

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
    
    /// - Parameter restartFromTop: play the new sequence from its first beat
    ///   rather than from wherever the loop happens to be.
    ///
    ///   Without this, a take committed at beat 17 of a 32-beat loop began
    ///   sounding at beat 17: everything before that was skipped until the loop
    ///   came round, which is heard as the take's first notes never arriving.
    ///   Auditioning several takes in a row made it every take.
    ///
    ///   Asked for when the *take* changes, not when the render does — otherwise
    ///   moving an expression slider, which re-pushes the same take, would jump
    ///   the loop back to the start on every touch.
    void commitSequence(double lengthBeats, bool restartFromTop = false) {
        mSequenceLengths[mStagingIndex] = std::max(lengthBeats, 0.25);
        mShared.activeIndex.store(mStagingIndex, std::memory_order_release);
        if (restartFromTop) {
            mShared.restartRequested.store(true, std::memory_order_release);
        }
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
            mLoopOrigin = 0;
            mHostBeatInitialized = false;
            mMelodyPlaying = true;
            // Pressing play is itself a restart, so an outstanding request from a
            // take committed while stopped doesn't fire a second one later.
            mShared.restartRequested.store(false, std::memory_order_relaxed);
        } else if (!mPlayMelody && mMelodyPlaying) {
            releaseAllNotes(bufferStartTime);
            mMelodyPlaying = false;
            // Publish the stop here: the early return below means
            // publishPassIndex never runs again, so a playhead left to the last
            // value would sit frozen mid-loop instead of disappearing.
            mShared.phaseBeats.store(-1.0, std::memory_order_relaxed);
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
                // The loop starts here, so we come in on the pattern's downbeat
                // rather than at whatever beat the host happens to sit on.
                mHostBeatInitialized = true;
                mTimelineBeats = mHostBeat;
                mLoopOrigin = mHostBeat;
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
                // A locate is a fresh start: re-anchor the loop, both so the
                // pattern is heard from its top and so loop time can't go
                // negative when the host jumps backwards.
                mLoopOrigin = windowEnd;
                return;
            }
        } else {
            mHostBeatInitialized = false;
        }

        // A newly committed take asked to be heard from its beginning: move the
        // loop's origin to here. Whatever is sounding belongs to the take being
        // replaced, so it is released rather than left to expire against beat
        // numbers that no longer mean the same thing.
        if (mShared.restartRequested.exchange(false, std::memory_order_acq_rel)) {
            releaseAllNotes(bufferStartTime);
            mLoopOrigin = windowStart;
        }

        // Everything below works in loop time — beats from the loop's own start —
        // rather than in timeline time, so a restart is just a change of origin.
        const double loopStart = windowStart - mLoopOrigin;
        const double loopEnd = windowEnd - mLoopOrigin;

        // Note-offs first, so a note re-triggered at the loop point is released
        // before its next note-on.
        for (uint32_t i = 0; i < mActiveCount;) {
            if (mActiveNotes[i].offBeat < loopEnd) {
                const double offset = std::max(0.0, mActiveNotes[i].offBeat - loopStart) / beatsPerFrame;
                sendNoteOff(bufferStartTime + AUEventSampleTime(offset), mActiveNotes[i].note, 0);
                mActiveNotes[i] = mActiveNotes[mActiveCount - 1];
                mActiveCount -= 1;
            } else {
                i += 1;
            }
        }

        scheduleNotes(bufferStartTime, loopStart, loopEnd, beatsPerFrame);
        mTimelineBeats = windowEnd;
        publishPassIndex(loopEnd);
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
        // Where in the loop the last buffer ended. The pass counter says which
        // time round we are; this says where, which is what a playhead needs.
        double phase = std::fmod(timelineBeats, loopLength);
        if (phase < 0) { phase += loopLength; }
        mShared.phaseBeats.store(mMelodyPlaying ? phase : -1.0, std::memory_order_relaxed);
    }

    /// Position within the loop in beats, or a negative value when nothing is
    /// playing — so the interface can tell "at beat zero" from "stopped".
    double currentPhaseBeats() const {
        return mShared.phaseBeats.load(std::memory_order_relaxed);
    }

    // MARK: - Capture

    /// Whether incoming MIDI is collected for learning. Off by default: capture
    /// is a thing you turn on, not something that happens to you.
    void setCaptureEnabled(bool enabled) {
        mCaptureEnabled = enabled;
    }

    bool isCaptureEnabled() const { return mCaptureEnabled; }

    /// How many events have ever been captured. The UI keeps its own cursor and
    /// reads forward from it, which is what makes the ring single-writer,
    /// single-reader and lock-free.
    uint64_t capturedEventCount() const {
        return mShared.captureWrite.load(std::memory_order_acquire);
    }

    /// The oldest event still in the ring. Anything before this was overwritten.
    uint64_t oldestCapturedEvent() const {
        const uint64_t written = capturedEventCount();
        return written > kCaptureCapacity ? written - kCaptureCapacity : 0;
    }

    double capturedBeat(uint64_t index) const { return mCapture[index % kCaptureCapacity].beat; }
    uint8_t capturedNote(uint64_t index) const { return mCapture[index % kCaptureCapacity].note; }
    uint8_t capturedVelocity(uint64_t index) const { return mCapture[index % kCaptureCapacity].velocity; }
    bool capturedIsOn(uint64_t index) const { return mCapture[index % kCaptureCapacity].isOn != 0; }

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
        // Capture before forwarding. The capture is a fixed ring written by this
        // thread and read by the UI, so nothing here allocates, locks or blocks —
        // the whole point of learning from playing is that it costs the render
        // thread nothing.
        if (mCaptureEnabled) {
            captureEventList(&midiEvent->eventList);
        }

        // Pass incoming MIDI through unchanged.
        if (mMIDIOutBlock)
        {
            mMIDIOutBlock(now, 0, &midiEvent->eventList);
        }
    }

    /// Pulls note-ons and note-offs out of a UMP event list into the capture ring.
    ///
    /// Both encodings are handled because both turn up: a host that negotiated
    /// MIDI 1.0 sends message type 2, one that negotiated MIDI 2.0 sends type 4
    /// with 16-bit velocity. Everything else — control change, pitch bend, clock —
    /// is passed through untouched and not captured; this is learning *melody*
    /// from playing, and a mod wheel isn't one.
    void captureEventList(const MIDIEventList *list) {
        if (list == nullptr) { return; }
        const MIDIEventPacket *packet = &list->packet[0];
        for (uint32_t index = 0; index < list->numPackets; ++index) {
            for (uint32_t word = 0; word < packet->wordCount; ++word) {
                const uint32_t first = packet->words[word];
                const uint8_t messageType = (uint8_t)((first >> 28) & 0xF);

                if (messageType == 0x2) {
                    // MIDI 1.0 in a UMP: status, note, velocity in one word.
                    const uint8_t status = (uint8_t)((first >> 20) & 0xF);
                    const uint8_t note = (uint8_t)((first >> 8) & 0x7F);
                    const uint8_t velocity = (uint8_t)(first & 0x7F);
                    if (status == 0x9 && velocity > 0) {
                        pushCapture(note, velocity, true);
                    } else if (status == 0x8 || (status == 0x9 && velocity == 0)) {
                        pushCapture(note, 0, false);
                    }
                } else if (messageType == 0x4 && word + 1 < packet->wordCount) {
                    // MIDI 2.0: velocity is 16-bit in the second word.
                    const uint8_t status = (uint8_t)((first >> 20) & 0xF);
                    const uint8_t note = (uint8_t)((first >> 8) & 0x7F);
                    const uint16_t wide = (uint16_t)((packet->words[word + 1] >> 16) & 0xFFFF);
                    const uint8_t velocity = (uint8_t)(wide >> 9);
                    if (status == 0x9 && wide > 0) {
                        pushCapture(note, velocity > 0 ? velocity : 1, true);
                    } else if (status == 0x8 || (status == 0x9 && wide == 0)) {
                        pushCapture(note, 0, false);
                    }
                    ++word;
                }

                // A UMP's word count tells us how far to step; unknown message
                // types are skipped by the loop rather than mis-parsed.
                const uint8_t words = umpWordCount(messageType);
                if (words > 1) { word += (words - 1); }
            }
            packet = MIDIEventPacketNext(packet);
        }
    }

    static uint8_t umpWordCount(uint8_t messageType) {
        switch (messageType) {
            case 0x0: case 0x1: case 0x2: return 1;
            case 0x3: case 0x4: return 2;
            case 0x5: return 4;
            default: return 1;
        }
    }

    /// One entry into the ring. Never blocks: if the UI hasn't drained it in
    /// time the oldest entries are simply lost, which is the right trade for a
    /// render thread — a dropped phrase is a nuisance, a glitch is a bug.
    void pushCapture(uint8_t note, uint8_t velocity, bool isOn) {
        const uint64_t sequence = mShared.captureWrite.load(std::memory_order_relaxed);
        CapturedEvent &slot = mCapture[sequence % kCaptureCapacity];
        slot.beat = mTimelineBeats;
        slot.note = note;
        slot.velocity = velocity;
        slot.isOn = isOn ? 1 : 0;
        mShared.captureWrite.store(sequence + 1, std::memory_order_release);
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

    /// One captured note-on or note-off, in timeline beats.
    struct CapturedEvent {
        double beat = 0;
        uint8_t note = 0;
        uint8_t velocity = 0;
        uint8_t isOn = 0;
    };
    static constexpr uint32_t kCaptureCapacity = 1024;

    bool mCaptureEnabled = false;
    CapturedEvent mCapture[kCaptureCapacity];

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
    /// The timeline value that counts as beat zero of the loop.
    ///
    /// Zero until something restarts the loop. Keeping it separate from
    /// `mTimelineBeats` is what lets a restart work identically whether the
    /// timeline is ours or the host's: the host's playhead keeps its own meaning,
    /// and the loop just decides where its own start is on that ruler.
    double mLoopOrigin = 0;
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
        /// Position within the current pass, or negative when stopped.
        std::atomic<double> phaseBeats{-1.0};
        /// Set by the UI thread when a newly committed take should be heard from
        /// its beginning; cleared by the render thread once it has been.
        std::atomic<bool> restartRequested{false};
        /// How many MIDI events have been captured, ever. The render thread
        /// writes; the UI reads forward from its own cursor.
        std::atomic<uint64_t> captureWrite{0};

        SharedFields() = default;
        SharedFields(const SharedFields &other)
        : activeIndex{other.activeIndex.load(std::memory_order_acquire)},
          passIndex{other.passIndex.load(std::memory_order_acquire)},
          tempo{other.tempo.load(std::memory_order_relaxed)},
          loopBeats{other.loopBeats.load(std::memory_order_relaxed)},
          phaseBeats{other.phaseBeats.load(std::memory_order_relaxed)},
          restartRequested{other.restartRequested.load(std::memory_order_relaxed)},
          captureWrite{other.captureWrite.load(std::memory_order_acquire)} {}
        SharedFields &operator=(const SharedFields &other) {
            activeIndex.store(other.activeIndex.load(std::memory_order_acquire), std::memory_order_release);
            passIndex.store(other.passIndex.load(std::memory_order_acquire), std::memory_order_release);
            tempo.store(other.tempo.load(std::memory_order_relaxed), std::memory_order_relaxed);
            loopBeats.store(other.loopBeats.load(std::memory_order_relaxed), std::memory_order_relaxed);
            phaseBeats.store(other.phaseBeats.load(std::memory_order_relaxed), std::memory_order_relaxed);
            restartRequested.store(other.restartRequested.load(std::memory_order_relaxed), std::memory_order_relaxed);
            captureWrite.store(other.captureWrite.load(std::memory_order_acquire), std::memory_order_release);
            return *this;
        }
    };

    SharedFields mShared;
};
