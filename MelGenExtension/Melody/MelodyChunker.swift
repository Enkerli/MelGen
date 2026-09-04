//
//  MelodyChunker.swift
//  MelGenExtension
//
//  Splits a progression into request-sized pieces.
//
//  The on-device model's context window is 4,096 tokens covering the
//  instructions, the prompt *and* the response together, and guided generation
//  emits one structured object per note — so the budget is bounded by note
//  count, not by bars. A whole 16-bar form asks for roughly 3,300 tokens and
//  fails; four bars at the densest setting is around 1,600, which leaves
//  comfortable headroom.
//
//  Generating a phrase at a time is also Apple's own guidance for data that
//  won't fit in one window, and the model writes better over four bars than over
//  sixteen. Deliberately free of any FoundationModels dependency so it can be
//  tested without the framework — see Scripts/verify.sh.
//

import Foundation

/// One request's worth of a progression.
struct MelodyChunk: Equatable {
    /// Where this chunk starts in the whole progression, in quarter-note beats.
    let startBeat: Double
    let beats: Double
    /// The chords sounding in this range, rebased so the chunk starts at beat 0.
    let progression: ChordProgression

    /// Offset to add to the model's eighth-note indices to place them on the
    /// whole progression's grid.
    var startEighth: Int { Int((startBeat * 2).rounded()) }

    /// 1-based bar range, for progress reporting.
    var bars: ClosedRange<Int> {
        let first = Int(startBeat / MelodyChunker.beatsPerBar) + 1
        let last = Int((startBeat + beats - 0.001) / MelodyChunker.beatsPerBar) + 1
        return first...max(first, last)
    }

    static func == (lhs: MelodyChunk, rhs: MelodyChunk) -> Bool {
        lhs.startBeat == rhs.startBeat
            && lhs.beats == rhs.beats
            && lhs.progression.chords == rhs.progression.chords
    }
}

enum MelodyChunker {
    static let beatsPerBar: Double = 4
    /// Bars asked for in one request.
    static let defaultBarsPerRequest = 4

    /// Splits at bar lines. A chord straddling a boundary appears in both
    /// chunks, clipped to each, so every chunk has harmony for its whole span.
    static func chunks(for progression: ChordProgression,
                       barsPerRequest: Int = defaultBarsPerRequest) -> [MelodyChunk] {
        let chunkBeats = Double(max(1, barsPerRequest)) * beatsPerBar
        guard progression.totalBeats > chunkBeats + 0.001 else {
            return [MelodyChunk(startBeat: 0,
                                beats: progression.totalBeats,
                                progression: progression)]
        }

        var chunks: [MelodyChunk] = []
        var start = 0.0
        while start < progression.totalBeats - 0.001 {
            let beats = min(chunkBeats, progression.totalBeats - start)
            let end = start + beats

            chunks.append(MelodyChunk(
                startBeat: start,
                beats: beats,
                progression: progression.slice(from: start, to: end)
            ))
            start = end
        }
        return chunks
    }
}
