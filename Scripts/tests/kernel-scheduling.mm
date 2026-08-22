// Standalone harness for MelGenExtensionDSPKernel's melody scheduling.
// Drives the kernel with a fake host and prints the note-ons it emits.

#import <Foundation/Foundation.h>
#include "MelGenExtensionDSPKernel.hpp"
#include <cstdio>
#include <string>
#include <vector>

static std::vector<std::string> gEvents;

static void wire(MelGenExtensionDSPKernel &kernel) {
    kernel.setLegacyMIDIOutputEventBlock(^OSStatus(AUEventSampleTime t, uint8_t cable, NSInteger len, const uint8_t *bytes) {
        char buf[64];
        const bool on = (bytes[0] & 0xF0) == 0x90;
        snprintf(buf, sizeof(buf), "%s%d", on ? "on" : "off", bytes[1]);
        gEvents.push_back(buf);
        return noErr;
    });
}

static void loadSequence(MelGenExtensionDSPKernel &kernel) {
    kernel.beginSequenceUpdate();
    kernel.appendSequenceNote(0, 1, 60, 100);
    kernel.appendSequenceNote(1, 1, 62, 100);
    kernel.appendSequenceNote(2, 1, 64, 100);
    kernel.appendSequenceNote(3, 1, 65, 100);
    kernel.commitSequence(4);
}

static std::string noteOnsOnly() {
    std::string out;
    for (auto &e : gEvents) {
        if (e.rfind("on", 0) == 0) { out += e.substr(2) + " "; }
    }
    return out;
}

// Runs `beats` worth of buffers at 120bpm / 48kHz.
static void run(MelGenExtensionDSPKernel &kernel, double beats) {
    const AUAudioFrameCount frames = 512;
    const double beatsPerBuffer = 120.0 / 60.0 * double(frames) / 48000.0;
    const int buffers = int(beats / beatsPerBuffer);
    for (int i = 0; i < buffers; ++i) {
        kernel.process(AUEventSampleTime(i) * frames, frames);
    }
}

static void testDirection(const char *label, MelGenPlaybackDirection dir) {
    MelGenExtensionDSPKernel kernel;
    kernel.initialize(48000);
    wire(kernel);
    loadSequence(kernel);
    gEvents.clear();
    kernel.setParameter(MelGenExtensionParameterAddress::playbackDirection, (AUValue)dir);
    kernel.setParameter(MelGenExtensionParameterAddress::playMelody, 1);
    run(kernel, 12.0);
    printf("%-10s %s\n", label, noteOnsOnly().c_str());
}

static void testHostSync() {
    MelGenExtensionDSPKernel kernel;
    kernel.initialize(48000);
    wire(kernel);
    loadSequence(kernel);

    // Fake host playhead, starting mid-bar to prove we follow it rather than
    // starting the loop from zero.
    static double hostBeat = 2.0;
    static bool rolling = true;
    kernel.setMusicalContextBlock(^BOOL(double *tempo, double *num, NSInteger *den,
                                       double *beat, NSInteger *offset, double *downbeat) {
        if (tempo) { *tempo = 120.0; }
        if (beat) { *beat = hostBeat; }
        return YES;
    });

    gEvents.clear();
    kernel.setParameter(MelGenExtensionParameterAddress::hostSync, 1);
    kernel.setParameter(MelGenExtensionParameterAddress::playMelody, 1);

    const AUAudioFrameCount frames = 512;
    const double beatsPerBuffer = 120.0 / 60.0 * double(frames) / 48000.0;
    for (int i = 0; i < 400; ++i) {
        // Host stops advancing part-way through.
        if (i == 200) { rolling = false; }
        kernel.process(AUEventSampleTime(i) * frames, frames);
        if (rolling) { hostBeat += beatsPerBuffer; }
    }
    printf("%-10s %s\n", "hostsync", noteOnsOnly().c_str());

    // Everything must be released once the host stops.
    int on = 0, off = 0;
    for (auto &e : gEvents) { (e.rfind("on", 0) == 0 ? on : off) += 1; }
    printf("           note-ons=%d note-offs=%d (must be equal)\n", on, off);
}

// The UI polls currentPass() to know when a take has looped, which is what
// drives auto-regeneration.
static void testPassCounter() {
    MelGenExtensionDSPKernel kernel;
    kernel.initialize(48000);
    wire(kernel);
    loadSequence(kernel);   // 4-beat loop
    gEvents.clear();
    kernel.setParameter(MelGenExtensionParameterAddress::playMelody, 1);

    printf("%-10s start=%lld", "passes", (long long)kernel.currentPass());
    for (int loop = 1; loop <= 3; ++loop) {
        // Slightly past each loop point, since run() rounds buffers down.
        run(kernel, loop == 1 ? 4.05 : 4.0);
        printf(" after%dloops=%lld", loop, (long long)kernel.currentPass());
    }
    printf("  (expect 0 1 2 3)\n");
}

int main() {
    testDirection("forward", MelGenPlaybackDirectionForward);
    testDirection("backward", MelGenPlaybackDirectionBackward);
    testDirection("pingpong", MelGenPlaybackDirectionPingPong);
    testHostSync();
    testPassCounter();
    return 0;
}
