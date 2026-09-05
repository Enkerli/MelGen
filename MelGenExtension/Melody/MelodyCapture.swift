//
//  MelodyCapture.swift
//  MelGenExtension
//
//  Turning what was played in into material that can be learned from.
//
//  The style model and the chain were both written so that adding a take is
//  `add(pattern)` and nothing else — counts and sums, no recomputation. That was
//  not incidental. It means the difference between "learn from the takes you
//  kept" and "learn from what you just played" is only this file: get the notes
//  off the wire, segment them into phrases, read them back as degrees against the
//  harmony that was sounding, and hand them to the same two `add` methods.
//
//  Three things have to be got right, and none of them is the MIDI parsing.
//
//  *Pairing.* A note is a note-on and its matching note-off, and a keyboard
//  player overlaps them constantly. Pairing by pitch with a stack per pitch
//  handles retriggers; anything still held when capture ends is closed at the
//  end rather than dropped, because the last note of a phrase is usually the one
//  being held while you decide you liked it.
//
//  *Segmenting.* A stream of notes isn't a phrase. Splitting on silence is the
//  only segmentation that needs no model and matches what a player hears
//  themselves doing — you stop, therefore that was a phrase.
//
//  *Quantizing, but only just.* Captured onsets land wherever fingers put them.
//  The pattern format is an eighth grid, so they have to be rounded; but the
//  deviation is worth keeping, because a slot model's micro-timing field exists
//  precisely to record where a player leans, and throwing it away at the door
//  would make the whole capture path teach the machine to play like a sequencer.
//
//  Deliberately free of any FoundationModels dependency, and of the kernel: this
//  takes plain events, so it can be tested without an audio unit.
//

import Foundation
import Carrier
import Theory

/// A phrase someone played, with what it cost to write it down.
struct CapturedPhrase: Sendable, Identifiable {
    var id = UUID()
    var notes: [SequencedNote]
    /// Where it started on the timeline, before it was rebased to zero.
    var startBeat: Double
    /// Mean absolute distance from the eighth grid, in eighths. Near zero means
    /// it was played to a grid; large means it wasn't, and that's information
    /// rather than error.
    var meanDeviation: Double

    var lengthBeats: Double {
        (notes.map { $0.startBeat + $0.durationBeats }.max() ?? 0)
    }

    var summary: String {
        "\(notes.count) notes, \(String(format: "%.1f", lengthBeats)) beats"
            + (meanDeviation > 0.12 ? ", played loosely" : ", close to the grid")
    }
}

enum MelodyCapture {

    /// The gap that ends a phrase. Two beats — half a bar — because shorter
    /// reads as phrasing inside one phrase and longer misses the breath between
    /// two.
    static let phraseGapBeats: Double = 2

    /// Pairs note-ons with their note-offs.
    ///
    /// - Parameter endBeat: where capture stopped, used to close anything still
    ///   held. Notes still down at the end are kept, not dropped: the held note
    ///   at the end of a phrase is usually the one that made you stop.
    static func notes(from events: [CapturedMIDIEvent], endingAt endBeat: Double? = nil) -> [SequencedNote] {
        let ordered = events.sorted { ($0.beat, $0.isOn ? 1 : 0) < ($1.beat, $1.isOn ? 1 : 0) }
        var held: [UInt8: [(beat: Double, velocity: UInt8)]] = [:]
        var result: [SequencedNote] = []

        for event in ordered {
            if event.isOn {
                held[event.note, default: []].append((event.beat, event.velocity))
            } else if var stack = held[event.note], let start = stack.popLast() {
                held[event.note] = stack.isEmpty ? nil : stack
                let duration = max(0.05, event.beat - start.beat)
                result.append(SequencedNote(note: event.note,
                                            velocity: start.velocity,
                                            startBeat: start.beat,
                                            durationBeats: duration))
            }
        }

        let last = endBeat ?? (ordered.last?.beat ?? 0)
        for (note, stack) in held {
            for start in stack {
                let duration = max(0.25, last - start.beat)
                result.append(SequencedNote(note: note,
                                            velocity: start.velocity,
                                            startBeat: start.beat,
                                            durationBeats: duration))
            }
        }
        return result.sorted { $0.startBeat < $1.startBeat }
    }

    /// Splits a stream into phrases at the silences.
    ///
    /// The only segmentation that needs no model, and the one that matches what
    /// a player hears themselves doing: you stopped, so that was a phrase.
    static func phrases(from notes: [SequencedNote],
                        gapBeats: Double = phraseGapBeats,
                        minimumNotes: Int = 3) -> [CapturedPhrase] {
        let ordered = notes.sorted { $0.startBeat < $1.startBeat }
        guard !ordered.isEmpty else { return [] }

        var groups: [[SequencedNote]] = []
        var current: [SequencedNote] = [ordered[0]]
        var cursor = ordered[0].startBeat + ordered[0].durationBeats

        for note in ordered.dropFirst() {
            if note.startBeat - cursor >= gapBeats {
                groups.append(current)
                current = []
            }
            current.append(note)
            cursor = max(cursor, note.startBeat + note.durationBeats)
        }
        if !current.isEmpty { groups.append(current) }

        return groups.compactMap { group in
            guard group.count >= minimumNotes, let start = group.first?.startBeat else { return nil }
            // Rebase to zero: a phrase is a shape, not a position on a timeline.
            let rebased = group.map { note -> SequencedNote in
                var copy = note
                copy.startBeat = note.startBeat - start
                return copy
            }
            let deviation = rebased
                .map { abs($0.startBeat * 2 - ($0.startBeat * 2).rounded()) }
                .reduce(0, +) / Double(rebased.count)
            return CapturedPhrase(notes: rebased, startBeat: start, meanDeviation: deviation)
        }
    }

    /// Snaps a phrase to the eighth grid the rest of the plug-in speaks.
    ///
    /// Rounding, not correcting: a note that arrived a third of an eighth late
    /// belongs on the nearest eighth, and how late it was is recorded separately
    /// by `CapturedPhrase.meanDeviation` rather than being silently absorbed.
    static func quantize(_ phrase: CapturedPhrase) -> [SequencedNote] {
        var snapped = phrase.notes.map { note -> SequencedNote in
            var copy = note
            copy.startBeat = ((note.startBeat * 2).rounded()) / 2
            copy.durationBeats = max(0.5, ((note.durationBeats * 2).rounded()) / 2)
            return copy
        }
        snapped.sort { $0.startBeat < $1.startBeat }

        // Two fingers landing on one eighth is a chord; this path is melodic, so
        // the higher note wins — which is what a listener hears anyway.
        var monophonic: [SequencedNote] = []
        for note in snapped {
            if let last = monophonic.last, abs(last.startBeat - note.startBeat) < 0.01 {
                if note.note > last.note { monophonic[monophonic.count - 1] = note }
                continue
            }
            monophonic.append(note)
        }
        for index in monophonic.indices.dropLast() {
            let slot = monophonic[index + 1].startBeat - monophonic[index].startBeat
            monophonic[index].durationBeats = max(0.25, min(monophonic[index].durationBeats, slot))
        }
        return monophonic
    }

    /// Reads a captured phrase back as a degree-relative pattern.
    ///
    /// The harmony matters and there's no guessing here: MelGen knows what
    /// progression was on screen while it was being played, so the phrase is
    /// read against it — which is what makes captured material reusable over
    /// other changes rather than being a recording.
    static func pattern(from phrase: CapturedPhrase,
                        over progression: ChordProgression,
                        name: String,
                        at startBeat: Double? = nil) -> MelodyPattern? {
        let notes = quantize(phrase)
        guard notes.count >= 2 else { return nil }

        // Where in the form it was played, so a phrase that began on beat three
        // of bar two is read against the chord that was actually sounding.
        let offset = (startBeat ?? phrase.startBeat).truncatingRemainder(dividingBy: max(1, progression.totalBeats))
        let placed = notes.map { note -> SequencedNote in
            var copy = note
            copy.startBeat = (note.startBeat + offset).truncatingRemainder(dividingBy: progression.totalBeats)
            return copy
        }.sorted { $0.startBeat < $1.startBeat }

        return MelodyPatterns.extract(from: placed,
                                      over: progression,
                                      name: name,
                                      lengthBeats: max(4, phrase.lengthBeats),
                                      origin: PatternOrigin(progressionText: progression.text,
                                                            briefName: "played in",
                                                            source: .captured))
    }

    /// Everything in one call: events to patterns, ready for `add`.
    static func learn(from events: [CapturedMIDIEvent],
                      over progression: ChordProgression,
                      endingAt endBeat: Double? = nil,
                      namePrefix: String = "Played") -> [MelodyPattern] {
        let sounded = notes(from: events, endingAt: endBeat)
        return phrases(from: sounded).enumerated().compactMap { index, phrase in
            pattern(from: phrase,
                    over: progression,
                    name: "\(namePrefix) \(index + 1)",
                    at: phrase.startBeat)
        }
    }
}
