//
//  StandardMIDIFile.swift
//  MelGenExtension
//
//  Reading and writing `.mid` — the in-app half of ROADMAP S2, and X1/X4.
//
//  Until now nothing left this plug-in except live MIDI, and nothing came in
//  except live MIDI. `Scripts/training/midi_to_events.py` reads a collection on
//  a desktop, but Python isn't on the iPad, so a file you were handed could not
//  become material. This is the codec that closes that; `MIDIFileImport` is
//  what decides what the notes *mean*.
//
//  Scope, chosen so this stays a file format reader and not a sequencer:
//
//  - Format 0 and 1. Format 2 is independent sequences rather than one piece,
//    and reading it as one would silently overlay unrelated material.
//  - Metrical division only. SMPTE-divided files exist and are rare outside
//    film work; they're refused by name rather than mis-timed.
//  - Note on/off (velocity-0 note-on is a note-off — that convention is why
//    running status is worth supporting at all), tempo, time signature, track
//    name, marker and text meta. Everything else is skipped by length, which is
//    the part that has to be right: a controller event misread by one byte
//    turns the rest of the track into noise.
//
//  Positions come out in **beats**, not ticks, because every other part of this
//  app thinks in beats and the tick grid is a property of the file rather than
//  of the music.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

// MARK: - What a file holds

/// One sounded note, positioned in quarter-note beats.
struct MIDIFileNote: Hashable, Sendable {
    var pitch: Int
    var startBeat: Double
    var durationBeats: Double
    var velocity: Int
    var channel: Int
}

/// A positioned text event — a marker (0x06) or a text meta (0x01).
struct MIDIFileText: Hashable, Sendable {
    var beat: Double
    var text: String
    /// 0x01 text, 0x06 marker, 0x03 track name.
    var metaType: Int
}

/// One track's worth of notes, with whatever it called itself.
struct MIDIFileTrack: Hashable, Sendable {
    var name: String
    var notes: [MIDIFileNote]
    /// The channels this track wrote on, so a drum track can be recognised.
    var channels: Set<Int>

    var isDrums: Bool { !channels.isEmpty && channels.allSatisfy { $0 == 9 } }
}

struct StandardMIDIFile: Sendable {
    var format: Int
    var ticksPerBeat: Int
    var tracks: [MIDIFileTrack]
    /// Markers and text, from every track, in time order.
    var texts: [MIDIFileText]
    var beatsPerBar: Double
    var beatsPerMinute: Double

    /// Every note in the file, whichever track it came from.
    var allNotes: [MIDIFileNote] {
        tracks.flatMap(\.notes).sorted { ($0.startBeat, $0.pitch) < ($1.startBeat, $1.pitch) }
    }

    var endBeat: Double {
        allNotes.map { $0.startBeat + $0.durationBeats }.max() ?? 0
    }
}

enum MIDIFileError: LocalizedError {
    case notAMIDIFile
    case unsupportedFormat(Int)
    case smpteDivision
    case truncated

    var errorDescription: String? {
        switch self {
        case .notAMIDIFile:
            return "That isn't a MIDI file — it doesn't start with a MThd header."
        case .unsupportedFormat(let format):
            return "MIDI format \(format) holds independent sequences rather than one piece, "
                + "so reading it as one would overlay unrelated material."
        case .smpteDivision:
            return "This file is timed in SMPTE frames rather than beats, which MelGen can't "
                + "place against a progression."
        case .truncated:
            return "The file ends in the middle of an event."
        }
    }
}

// MARK: - Reading

extension StandardMIDIFile {

    static func read(_ data: Data) throws -> StandardMIDIFile {
        var reader = ByteReader(data)
        guard reader.readASCII(4) == "MThd", reader.readUInt32() == 6 else {
            throw MIDIFileError.notAMIDIFile
        }
        let format = Int(reader.readUInt16())
        let trackCount = Int(reader.readUInt16())
        let division = Int(reader.readUInt16())

        guard format == 0 || format == 1 else { throw MIDIFileError.unsupportedFormat(format) }
        guard division & 0x8000 == 0 else { throw MIDIFileError.smpteDivision }
        let ticksPerBeat = max(1, division)

        var tracks: [MIDIFileTrack] = []
        var texts: [MIDIFileText] = []
        var beatsPerBar = 4.0
        var bpm = 120.0
        var sawTimeSignature = false
        var sawTempo = false

        for _ in 0..<trackCount {
            guard reader.remaining >= 8 else { break }
            guard reader.readASCII(4) == "MTrk" else { break }
            let length = Int(reader.readUInt32())
            guard let chunk = reader.readData(length) else { throw MIDIFileError.truncated }

            let parsed = try readTrack(chunk, ticksPerBeat: ticksPerBeat)
            tracks.append(MIDIFileTrack(name: parsed.name,
                                        notes: parsed.notes,
                                        channels: parsed.channels))
            texts.append(contentsOf: parsed.texts)
            // First one wins: a tempo map is a thing this reader deliberately
            // doesn't model, and taking the last value would silently pick
            // whichever change happened to be latest in the file.
            if let signature = parsed.beatsPerBar, !sawTimeSignature {
                beatsPerBar = signature
                sawTimeSignature = true
            }
            if let tempo = parsed.beatsPerMinute, !sawTempo {
                bpm = tempo
                sawTempo = true
            }
        }

        return StandardMIDIFile(format: format,
                                ticksPerBeat: ticksPerBeat,
                                tracks: tracks,
                                texts: texts.sorted { $0.beat < $1.beat },
                                beatsPerBar: beatsPerBar,
                                beatsPerMinute: bpm)
    }

    private struct ParsedTrack {
        var name = ""
        var notes: [MIDIFileNote] = []
        var texts: [MIDIFileText] = []
        var channels: Set<Int> = []
        var beatsPerBar: Double?
        var beatsPerMinute: Double?
    }

    private static func readTrack(_ data: Data, ticksPerBeat: Int) throws -> ParsedTrack {
        var reader = ByteReader(data)
        var track = ParsedTrack()
        var ticks = 0
        var runningStatus: UInt8 = 0
        /// Sounding notes, keyed by channel and pitch, so overlapping voices
        /// pair correctly instead of the first note-off ending all of them.
        var open: [Int: [(startTicks: Int, velocity: Int)]] = [:]

        func beat(_ value: Int) -> Double { Double(value) / Double(ticksPerBeat) }

        while reader.remaining > 0 {
            ticks += Int(reader.readVarInt())
            guard let first = reader.peekByte() else { break }

            var status = runningStatus
            if first >= 0x80 {
                status = first
                _ = reader.readByte()
                // Running status carries over channel messages only.
                if first < 0xF0 { runningStatus = first }
            }
            guard status != 0 else { break }

            if status == 0xFF {
                guard let type = reader.readByte() else { break }
                let length = Int(reader.readVarInt())
                guard let payload = reader.readData(length) else { throw MIDIFileError.truncated }
                switch type {
                case 0x01, 0x06:
                    if let text = String(data: payload, encoding: .utf8)
                        ?? String(data: payload, encoding: .isoLatin1) {
                        track.texts.append(MIDIFileText(beat: beat(ticks),
                                                        text: text,
                                                        metaType: Int(type)))
                    }
                case 0x03:
                    if track.name.isEmpty {
                        track.name = String(data: payload, encoding: .utf8)
                            ?? String(data: payload, encoding: .isoLatin1) ?? ""
                    }
                case 0x51:
                    if payload.count == 3 {
                        let microseconds = payload.reduce(0) { $0 << 8 | Int($1) }
                        if microseconds > 0 {
                            track.beatsPerMinute = 60_000_000 / Double(microseconds)
                        }
                    }
                case 0x58:
                    if payload.count >= 2 {
                        let numerator = Double(payload[payload.startIndex])
                        let denominator = pow(2.0, Double(payload[payload.startIndex + 1]))
                        if denominator > 0 { track.beatsPerBar = numerator * 4 / denominator }
                    }
                case 0x2F:
                    reader.skipToEnd()
                default:
                    break
                }
                continue
            }

            if status == 0xF0 || status == 0xF7 {
                let length = Int(reader.readVarInt())
                _ = reader.readData(length)
                continue
            }

            let kind = status & 0xF0
            let channel = Int(status & 0x0F)
            // The part that has to be right: one wrong length and the rest of
            // the track decodes as garbage.
            let dataBytes = (kind == 0xC0 || kind == 0xD0) ? 1 : 2
            guard let first = reader.readByte() else { break }
            let second = dataBytes == 2 ? reader.readByte() : nil
            guard dataBytes == 1 || second != nil else { break }

            let pitch = Int(first)
            let velocity = Int(second ?? 0)
            let key = channel << 8 | pitch

            if kind == 0x90 && velocity > 0 {
                track.channels.insert(channel)
                open[key, default: []].append((ticks, velocity))
            } else if kind == 0x80 || (kind == 0x90 && velocity == 0) {
                guard var stack = open[key], !stack.isEmpty else { continue }
                let started = stack.removeFirst()
                open[key] = stack.isEmpty ? nil : stack
                let duration = max(1, ticks - started.startTicks)
                track.notes.append(MIDIFileNote(pitch: pitch,
                                                startBeat: beat(started.startTicks),
                                                durationBeats: beat(duration),
                                                velocity: started.velocity,
                                                channel: channel))
            }
        }

        // A note left hanging at the end of the track is common in files people
        // actually have. Give it the shortest length the grid can express
        // rather than dropping it.
        for (key, stack) in open {
            for started in stack {
                track.notes.append(MIDIFileNote(pitch: key & 0xFF,
                                                startBeat: beat(started.startTicks),
                                                durationBeats: max(beat(1), 0.25),
                                                velocity: started.velocity,
                                                channel: key >> 8))
            }
        }
        track.notes.sort { ($0.startBeat, $0.pitch) < ($1.startBeat, $1.pitch) }
        return track
    }
}

// MARK: - Writing

extension StandardMIDIFile {

    /// Writes a format-0 file: one track, the notes, per-chord markers, and any
    /// text events the caller wants carried.
    ///
    /// Format 0 rather than 1 because a take is one part. The chord information
    /// rides as markers plus a text payload rather than as a second track, so a
    /// DAW shows the changes without gaining a track of block chords nobody
    /// asked to hear.
    static func write(notes: [SequencedNote],
                      markers: [MIDIFileText] = [],
                      textEvents: [String] = [],
                      trackName: String = "",
                      beatsPerMinute: Double = 120,
                      beatsPerBar: Double = 4,
                      ticksPerBeat: Int = 480) -> Data {
        var events: [(ticks: Int, order: Int, bytes: [UInt8])] = []
        func tick(_ beat: Double) -> Int { max(0, Int((beat * Double(ticksPerBeat)).rounded())) }

        if !trackName.isEmpty {
            events.append((0, 0, meta(0x03, Array(trackName.utf8))))
        }
        for text in textEvents {
            events.append((0, 0, meta(0x01, Array(text.utf8))))
        }
        let microseconds = Int(60_000_000 / max(1, beatsPerMinute))
        events.append((0, 0, meta(0x51, [UInt8(microseconds >> 16 & 0xFF),
                                         UInt8(microseconds >> 8 & 0xFF),
                                         UInt8(microseconds & 0xFF)])))
        // Denominator as a power of two, which is what the file format stores.
        let numerator = max(1, Int(beatsPerBar.rounded()))
        events.append((0, 0, meta(0x58, [UInt8(numerator), 2, 24, 8])))

        for marker in markers {
            events.append((tick(marker.beat), 0, meta(0x06, Array(marker.text.utf8))))
        }

        for note in notes {
            let pitch = UInt8(clamping: note.note)
            let velocity = UInt8(clamping: max(1, note.velocity))
            let start = tick(note.startBeat)
            let end = max(start + 1, tick(note.startBeat + note.durationBeats))
            // Note-offs sort before note-ons at the same tick, so a repeated
            // pitch retriggers instead of the off killing the new note.
            events.append((start, 2, [0x90, pitch, velocity]))
            events.append((end, 1, [0x80, pitch, 0]))
        }

        events.sort { ($0.ticks, $0.order) < ($1.ticks, $1.order) }

        var track: [UInt8] = []
        var previous = 0
        for event in events {
            track.append(contentsOf: varInt(event.ticks - previous))
            track.append(contentsOf: event.bytes)
            previous = event.ticks
        }
        track.append(contentsOf: varInt(0))
        track.append(contentsOf: meta(0x2F, []))

        var file: [UInt8] = Array("MThd".utf8)
        file.append(contentsOf: uint32(6))
        file.append(contentsOf: uint16(0))
        file.append(contentsOf: uint16(1))
        file.append(contentsOf: uint16(ticksPerBeat))
        file.append(contentsOf: Array("MTrk".utf8))
        file.append(contentsOf: uint32(track.count))
        file.append(contentsOf: track)
        return Data(file)
    }

    private static func meta(_ type: UInt8, _ payload: [UInt8]) -> [UInt8] {
        [0xFF, type] + varInt(payload.count) + payload
    }

    private static func varInt(_ value: Int) -> [UInt8] {
        var value = max(0, value)
        var bytes = [UInt8(value & 0x7F)]
        value >>= 7
        while value > 0 {
            bytes.insert(UInt8(value & 0x7F | 0x80), at: 0)
            value >>= 7
        }
        return bytes
    }

    private static func uint16(_ value: Int) -> [UInt8] {
        [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private static func uint32(_ value: Int) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
         UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }
}

// MARK: - Bytes

private struct ByteReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) { bytes = Array(data) }

    var remaining: Int { max(0, bytes.count - index) }

    mutating func readByte() -> UInt8? {
        guard index < bytes.count else { return nil }
        defer { index += 1 }
        return bytes[index]
    }

    func peekByte() -> UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    mutating func readASCII(_ count: Int) -> String {
        guard let data = readData(count) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    mutating func readUInt16() -> Int {
        Int(readByte() ?? 0) << 8 | Int(readByte() ?? 0)
    }

    mutating func readUInt32() -> Int {
        var value = 0
        for _ in 0..<4 { value = value << 8 | Int(readByte() ?? 0) }
        return value
    }

    mutating func readData(_ count: Int) -> Data? {
        guard count >= 0, index + count <= bytes.count else { return nil }
        defer { index += count }
        return Data(bytes[index..<(index + count)])
    }

    /// Variable-length quantity: seven bits a byte, high bit means "more".
    mutating func readVarInt() -> Int {
        var value = 0
        for _ in 0..<4 {
            guard let byte = readByte() else { break }
            value = value << 7 | Int(byte & 0x7F)
            if byte & 0x80 == 0 { break }
        }
        return value
    }

    mutating func skipToEnd() { index = bytes.count }
}
