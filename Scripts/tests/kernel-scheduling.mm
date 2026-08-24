// Standalone harness for MelGenExtensionDSPKernel's melody scheduling.
// Drives the kernel with a fake host and prints the note-ons it emits.

#import <Foundation/Foundation.h>
#include "MelGenExtensionDSPKernel.hpp"
#include <cstdio>
#include <string>
#include <vector>

static std::vector<std::string> gEvents;
static int gFailures = 0;

static void expect(const char *label, bool ok, const char *detail) {
    printf("  %s  %s%s%s\n", ok ? "PASS" : "FAIL", label,
           detail && *detail ? " — " : "", detail ? detail : "");
    if (!ok) { gFailures += 1; }
}

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

// The UI reads tempo and loop length to work out how long a loop lasts, which
// is how it reports whether generation fits inside one.
static void testTimingPublication() {
    MelGenExtensionDSPKernel kernel;
    kernel.initialize(48000);
    wire(kernel);
    loadSequence(kernel);   // 4-beat loop
    kernel.setMusicalContextBlock(^BOOL(double *tempo, double *num, NSInteger *den,
                                        double *beat, NSInteger *offset, double *downbeat) {
        if (tempo) { *tempo = 96.0; }
        return YES;
    });
    kernel.setParameter(MelGenExtensionParameterAddress::playMelody, 1);
    run(kernel, 4.05);

    const double t = kernel.currentTempo();
    const double beats = kernel.currentLoopBeats();
    printf("%-10s tempo=%.1f loopBeats=%.1f → loop %.2fs  (expect 96.0, 4.0, 2.50)\n",
           "timing", t, beats, t > 0 ? beats / t * 60.0 : 0.0);
}

// A take committed part-way through a loop must be heard from its own first
// beat. Before commitSequence took restartFromTop, the new sequence inherited
// the running loop's phase: a take handed over at beat 3 of a 4-beat loop
// started at beat 3, so its first three beats were silent until the loop came
// round. With auto-regeneration handing over a take per pass, that was heard as
// every take missing its opening notes.
static void testRestartFromTop() {
    MelGenExtensionDSPKernel kernel;
    kernel.initialize(48000);
    wire(kernel);
    loadSequence(kernel);       // 4-beat loop: 60 62 64 65 on each beat
    kernel.setParameter(MelGenExtensionParameterAddress::playMelody, 1);
    run(kernel, 3.0);           // land three beats into the loop

    // Hand over a take whose only note is on its first beat.
    gEvents.clear();
    kernel.beginSequenceUpdate();
    kernel.appendSequenceNote(0, 1, 72, 100);
    kernel.commitSequence(4, /*restartFromTop=*/true);
    run(kernel, 0.5);

    expect("a take committed mid-loop sounds its first beat at once",
           noteOnsOnly().find("72") != std::string::npos,
           noteOnsOnly().c_str());

    // And the playhead agrees: the loop is near its start, not near beat 3.
    const double phase = kernel.currentPhaseBeats();
    char detail[64];
    snprintf(detail, sizeof(detail), "phase=%.2f", phase);
    expect("the playhead follows the restart", phase >= 0 && phase < 1.0, detail);

    // Re-rendering the same take — what every expression slider does — must not
    // move the loop, or touching a control would restart the phrase.
    run(kernel, 2.0);
    const double before = kernel.currentPhaseBeats();
    kernel.beginSequenceUpdate();
    kernel.appendSequenceNote(0, 1, 72, 60);
    kernel.commitSequence(4, /*restartFromTop=*/false);
    run(kernel, 0.25);
    const double after = kernel.currentPhaseBeats();
    snprintf(detail, sizeof(detail), "%.2f → %.2f", before, after);
    expect("a re-render leaves the loop where it is", after > before, detail);
}

int main() {
    testDirection("forward", MelGenPlaybackDirectionForward);
    testDirection("backward", MelGenPlaybackDirectionBackward);
    testDirection("pingpong", MelGenPlaybackDirectionPingPong);
    testHostSync();
    testPassCounter();
    testTimingPublication();
    printf("%-10s\n", "restart");
    testRestartFromTop();
    printf("\nkernel: %s\n", gFailures ? "FAILURES" : "OK");
    return gFailures ? 1 : 0;
}
