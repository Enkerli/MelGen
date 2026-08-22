//
//  MelodyGenerator.swift
//  MelGenExtension
//
//  Generates melodic lines from a parsed chord progression using the on-device
//  Foundation Models framework. Pattern examples from PatternLibrary are
//  embedded in the instructions as few-shot material, and generated notes are
//  snapped to each chord's recommended scale.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
enum MelodyGenerator {

    enum Availability {
        case available
        case unavailable(String)
    }

    static var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            // Availability says nothing about locale, so a device set to an
            // unsupported language reports .available and then fails at
            // generation time. Name the problem instead.
            guard SystemLanguageModel.default.supportsLocale(.current) else {
                return .unavailable("The on-device model doesn’t support this device’s language (\(Locale.current.identifier)). Switch the system language to a supported one, such as English (United States).")
            }
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("This device doesn’t support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in System Settings to generate melodies.")
        case .unavailable(.modelNotReady):
            // The Simulator reports .modelNotReady too, but nothing is
            // downloading and it never will be — saying "try again shortly"
            // there sends people back to a button that can't work.
            #if targetEnvironment(simulator)
            return .unavailable("Foundation Models isn't available in the Simulator. "
                                + "Run on a device to generate — the rest of the plug-in works here.")
            #else
            return .unavailable("The on-device model is still downloading. Try again shortly.")
            #endif
        case .unavailable:
            return .unavailable("The on-device model is unavailable.")
        }
    }

    /// - Parameters:
    ///   - temperature: 0 gives the model's safest line, 1 its most adventurous.
    ///     Clamped to the range the framework accepts.
    ///   - brief: The rhythmic/contour brief for this take. Rotating it is what
    ///     makes successive takes differ from one another.
    ///   - progress: Called on each request with the chunk index and total, so a
    ///     long progression can report where it's up to instead of hanging.
    static func generate(for progression: ChordProgression,
                         temperature: Double = 0.6,
                         brief: StyleBrief,
                         density: Double = 0.5,
                         durationPalette: DurationPalette = .mixed,
                         progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [SequencedNote] {
        let chunks = MelodyChunker.chunks(for: progression)
        let options = GenerationOptions(
            samplingMode: nil,
            temperature: min(max(temperature, 0), 1)
        )

        var collected: [MelodyIdeaNote] = []
        for (index, chunk) in chunks.enumerated() {
            progress?(index, chunks.count)

            // A fresh session per chunk, so each one gets a clean context window
            // rather than accumulating the previous chunks' transcripts.
            let session = LanguageModelSession(
                instructions: instructions(examples: PatternLibrary.allExamples)
            )
            let response = try await session.respond(
                to: prompt(for: chunk.progression,
                           brief: brief,
                           density: density,
                           durationPalette: durationPalette,
                           continuingFrom: collected.last?.midiNote),
                generating: MelodyIdea.self,
                options: options
            )

            // Rebase onto the whole progression's grid.
            for note in response.content.notes {
                var shifted = note
                shifted.startEighth += chunk.startEighth
                collected.append(shifted)
            }
        }

        // Post-process across the seams, not per chunk: `fold` and `snap` work
        // from the previous note, so running them over the assembled line is what
        // keeps voice leading continuous where two requests meet.
        return sequence(from: collected, progression: progression)
    }

    // MARK: - Prompt construction

    static func instructions(examples: [PatternExample]) -> String {
        var text = """
        You are MelGen, a composer of monophonic melodic lines for a MIDI plug-in.
        You receive a chord progression in leadsheet notation with a harmonic plan, and reply \
        with melody notes on an eighth-note grid (2 eighths per beat, 8 eighths per 4/4 bar).

        Harmony:
        - Put chord tones on strong beats (eighths 0, 2, 4, 6 of each bar); connect them with \
        scale tones and occasional chromatic approach notes.
        - Stay inside the scale given for each chord.
        - Colour notes are good on strong beats too — they are what makes the line sound like \
        music rather than an exercise. Notes listed as "avoid landing on" may be passed through \
        quickly but never held or landed on.

        Voice leading — this matters more than anything else:
        - Move mostly by step (1 or 2 semitones). Keep consecutive notes close together; \
        an interval wider than an octave is always wrong.
        - When you do leap, resolve it by step in the opposite direction.
        - At a chord change, move to the nearest tone of the new chord rather than jumping to \
        its root: approach it by a semitone or whole tone, from above or below.
        - Keep the whole line inside about a twelfth, so it reads as one voice.

        Rests are required, not optional. A line with no silence in it is wrong:
        - Every two bars must contain at least one rest of two eighths or more. Set \
        restAfterEighths on the note that ends each phrase; leave it 0 elsewhere.
        - Phrases are two to four bars long. End one, breathe, start the next.
        - A rest before a strong beat is worth more than a note on it.

        Rhythm — never write an unbroken run of equal note lengths:
        - Mix durations freely: 1, 2, 3, 4 and 6 eighths, and let notes tie across beats.
        - Syncopate: start some phrases on an odd eighth (an offbeat) rather than on the beat.
        - Let a phrase end on a long note.

        - Notes must not overlap: each note starts at or after the previous note ends.

        """
        if !examples.isEmpty {
            text += "\nExample patterns (progression → melody as midiNote@startEighth:lengthEighths):\n"
            for example in examples {
                text += "- \(example.progression) → \(example.pattern)\n"
            }
        }
        return text
    }

    /// - Parameter continuingFrom: the MIDI note the previous chunk ended on, so
    ///   the line doesn't restart in an unrelated register at every seam.
    static func prompt(for progression: ChordProgression,
                       brief: StyleBrief,
                       density: Double = 0.5,
                       durationPalette: DurationPalette = .mixed,
                       continuingFrom previousNote: Int? = nil) -> String {
        var lines = ["Compose a melody for this progression: \(progression.text)", "", "Harmonic plan:"]
        for placed in progression.chords {
            let startEighth = Int((placed.startBeat * 2).rounded())
            let endEighth = Int(((placed.startBeat + placed.durationBeats) * 2).rounded())
            let names = { (pitchClasses: [Int]) in
                pitchClasses.map { ChordProgression.flatNoteNames[$0] }.joined(separator: " ")
            }
            var line = "- \(placed.symbol.text)"
            line += ": eighths \(startEighth)–\(endEighth)"
            line += ", \(placed.symbol.scaleName) scale \(names(placed.symbol.scalePitchClasses))"
            line += ", chord tones \(names(placed.symbol.tonePitchClasses))"
            if !placed.symbol.tensionPitchClasses.isEmpty {
                line += ", colour notes \(names(placed.symbol.tensionPitchClasses))"
            }
            if !placed.symbol.avoidPitchClasses.isEmpty {
                line += ", avoid landing on \(names(placed.symbol.avoidPitchClasses))"
            }
            lines.append(line)
        }
        let totalEighths = Int((progression.totalBeats * 2).rounded())
        lines.append("")
        lines.append(brief.text)
        lines.append("")
        lines.append("Density: aim for about \(MelodyExpression.notesPerBar(forDensity: density)) notes per bar, "
                     + "counting rests as part of the phrasing rather than padding with notes.")
        lines.append("")
        lines.append(durationPalette.promptText)
        if let previousNote {
            lines.append("")
            lines.append("This continues a line already in progress: the previous phrase ended on "
                         + "\(ChordProgression.noteName(forMIDINote: previousNote)) (MIDI \(previousNote)). "
                         + "Start within a few steps of it, in the same register.")
        }
        lines.append("")
        lines.append("Total length: \(totalEighths) eighths. All notes must start before eighth \(totalEighths).")
        return lines.joined(separator: "\n")
    }

    // MARK: - Post-processing

    /// Converts the model's output into a clean, monophonic, scale-correct sequence
    /// with the leaps smoothed out.
    ///
    /// Takes a plain note array rather than a `MelodyIdea` because a long
    /// progression is assembled from several requests, and the smoothing has to
    /// run over the whole line for the seams to disappear.
    static func sequence(from ideaNotes: [MelodyIdeaNote], progression: ChordProgression) -> [SequencedNote] {
        let totalEighths = Int((progression.totalBeats * 2).rounded())
        let notes = ideaNotes
            .filter { $0.startEighth >= 0 && $0.startEighth < totalEighths }
            .sorted { $0.startEighth < $1.startEighth }

        var result: [SequencedNote] = []
        var previousPitch: Int?
        for (index, note) in notes.enumerated() {
            var lengthEighths = min(note.lengthEighths, totalEighths - note.startEighth)
            // Monophonic: truncate at the next note's start.
            if index + 1 < notes.count {
                let slot = notes[index + 1].startEighth - note.startEighth
                lengthEighths = min(lengthEighths, slot)

                // Honour the rest the model asked for, but never at the cost of
                // more than half the note: a model that asks for four eighths of
                // silence after a one-eighth note means "end the phrase here",
                // not "delete the note".
                let requested = max(0, min(note.restAfterEighths, slot))
                if requested > 0 {
                    lengthEighths = min(lengthEighths, max(slot - requested, (slot + 1) / 2))
                }
            }
            guard lengthEighths > 0 else { continue }

            let startBeat = Double(note.startEighth) / 2
            let folded = fold(pitch: note.midiNote, near: previousPitch)
            let pitch = snap(
                pitch: folded,
                toScaleAt: startBeat,
                in: progression,
                near: previousPitch,
                onStrongBeat: note.startEighth.isMultiple(of: 2)
            )
            previousPitch = pitch
            result.append(SequencedNote(
                note: UInt8(clamping: pitch),
                velocity: UInt8(clamping: note.velocity),
                startBeat: startBeat,
                durationBeats: Double(lengthEighths) / 2
            ))
        }
        // Open a rest where there is none, then cap any that are so long the line
        // reads as having stopped rather than breathed.
        let breathing = MelodyExpression.ensureBreathing(result, totalBeats: progression.totalBeats)
        return MelodyExpression.capDeadAir(breathing, totalBeats: progression.totalBeats)
    }

    /// Transposes a pitch by octaves until it sits within an octave of its
    /// predecessor. The model likes to jump register mid-phrase; this keeps the
    /// result readable as a single line without altering its pitch classes.
    static func fold(pitch: Int, near previous: Int?) -> Int {
        guard let previous else { return pitch }
        // Shared with the pattern path so a generated line and an adapted one are
        // folded into register by exactly the same rule.
        return MelodyGeneratorSupport.fold(pitch: pitch, near: previous)
    }

    /// Keeps a pitch that already fits the chord's scale, and otherwise moves it
    /// to the nearest tone that does — preferring chord tones on strong beats, and
    /// breaking ties toward the smaller step from the previous note.
    static func snap(pitch: Int,
                     toScaleAt beat: Double,
                     in progression: ChordProgression,
                     near previous: Int?,
                     onStrongBeat strongBeat: Bool) -> Int {
        guard let placed = progression.chord(at: beat) else { return pitch }
        let scale = Set(placed.symbol.scalePitchClasses)
        if scale.contains(pitchClass(pitch)) { return pitch }

        let preferred = strongBeat ? Set(placed.symbol.tonePitchClasses) : scale
        let candidates = (-3...3)
            .map { pitch + $0 }
            .filter { (0...127).contains($0) }
        var pool = candidates.filter { preferred.contains(pitchClass($0)) }
        if pool.isEmpty {
            pool = candidates.filter { scale.contains(pitchClass($0)) }
        }
        guard !pool.isEmpty else { return pitch }

        return pool.min { a, b in
            (abs(a - pitch), abs(a - (previous ?? a))) < (abs(b - pitch), abs(b - (previous ?? b)))
        } ?? pitch
    }

    static func pitchClass(_ pitch: Int) -> Int {
        ((pitch % 12) + 12) % 12
    }
}
#endif // canImport(FoundationModels)
