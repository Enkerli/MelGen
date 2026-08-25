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

// The pass counter is what the interface uses to ask "has a loop gone by since I
// last acted", so it must only ever climb. Deriving it from loop time made it
// reset on every take handover — the origin moves, loop time goes back to zero —
// and the interface's own anchor was left stranded above it, so "a new take every
// two loops" stretched to four, then six, compounding all session.
static void testPassCounterSurvivesRestart() {
    MelGenExtensionDSPKernel kernel;
    kernel.initialize(48000);
    wire(kernel);
    loadSequence(kernel);       // 4-beat loop
    kernel.setParameter(MelGenExtensionParameterAddress::playMelody, 1);
    run(kernel, 8.1);           // two passes

    const int64_t before = kernel.currentPass();
    char detail[96];
    snprintf(detail, sizeof(detail), "%lld after two loops", (long long)before);
    expect("the counter climbs while playing", before >= 2, detail);

    // Hand over a take, the way auto-regeneration does.
    kernel.beginSequenceUpdate();
    kernel.appendSequenceNote(0, 1, 72, 100);
    kernel.commitSequence(4, /*restartFromTop=*/true);
    run(kernel, 0.5);

    const int64_t after = kernel.currentPass();
    snprintf(detail, sizeof(detail), "%lld → %lld", (long long)before, (long long)after);
    expect("a take handover doesn't reset it", after >= before, detail);

    // And it keeps counting from there rather than starting again.
    run(kernel, 4.1);
    const int64_t later = kernel.currentPass();
    snprintf(detail, sizeof(detail), "%lld → %lld after one more loop",
             (long long)after, (long long)later);
    expect("it keeps climbing after the handover", later > after, detail);

    // Several handovers in a row — what an auto session actually does — must not
    // walk the counter backwards even once, and must advance once per loop that
    // actually completes.
    bool monotonic = true;
    int64_t previous = later;
    for (int take = 0; take < 6; ++take) {
        kernel.beginSequenceUpdate();
        kernel.appendSequenceNote(0, 1, uint8_t(60 + take), 100);
        kernel.commitSequence(4, /*restartFromTop=*/true);
        run(kernel, 4.1);
        const int64_t now = kernel.currentPass();
        if (now < previous) { monotonic = false; }
        previous = now;
    }
    snprintf(detail, sizeof(detail), "%lld → %lld over six handovers",
             (long long)later, (long long)previous);
    expect("six handovers in a row keep it monotonic", monotonic, detail);
    expect("and each completed loop still counts", previous >= later + 6, detail);

    // A handover *before* the loop completes correctly counts nothing: no pass
    // was played. Worth pinning, because it's the one case where a stalled
    // counter is right rather than the bug above.
    const int64_t beforeShort = kernel.currentPass();
    kernel.beginSequenceUpdate();
    kernel.appendSequenceNote(0, 1, 79, 100);
    kernel.commitSequence(4, /*restartFromTop=*/true);
    run(kernel, 1.0);
    snprintf(detail, sizeof(detail), "%lld → %lld", (long long)beforeShort,
             (long long)kernel.currentPass());
    expect("a handover a quarter of the way through counts no pass",
           kernel.currentPass() == beforeShort, detail);

    // The playhead is still loop-relative: that's what it's for.
    const double phase = kernel.currentPhaseBeats();
    snprintf(detail, sizeof(detail), "phase=%.2f of 4", phase);
    expect("the phase stays inside the loop", phase >= 0 && phase < 4.0, detail);
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
    printf("%-10s\n", "passes across handovers");
    testPassCounterSurvivesRestart();
    printf("\nkernel: %s\n", gFailures ? "FAILURES" : "OK");
    return gFailures ? 1 : 0;
}
