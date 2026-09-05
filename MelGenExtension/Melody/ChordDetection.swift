//
//  ChordDetection.swift
//  MelGenExtension
//
//  Naming a chord from the notes that are sounding — ROADMAP I6, ported from
//  MIDIcurator by way of music-suite's `chordDetect.ts`.
//
//  MelGen has always been able to go from a *name* to pitches. This is the
//  other direction, and it is what an imported MIDI file needs: a chord track
//  is real harmony written as pitches, and without this the file can only teach
//  rhythm and contour. A degree with no chord under it is a pitch with a story
//  attached.
//
//  The algorithm is the suite's, unchanged, because the whole value of a port
//  is that both sides answer the same question the same way:
//
//    1. Reduce to unique pitch classes.
//    2. For each of the twelve possible roots, rotate so that root is 0.
//    3. Read the rotated set as a 12-bit fingerprint and look it up.
//    4. Prefer an exact match; failing that, allow the input to carry extra
//       notes and match the largest quality that explains the most of them.
//    5. Break ties by fewer extra notes, then simpler quality, then lower root.
//
//  Two deliberate differences from the TypeScript, both about staying
//  consistent with the rest of *this* app rather than with the suite's display:
//
//  **Symbols are spelled the way `ChordParser` writes them** — flat names and
//  `ChordDictionary.displaySuffix` — so a detected chord can be handed straight
//  back to `ChordProgression.parse`. Agreeing with the suite's symbol strings
//  would mean disagreeing with every other chord name MelGen shows. Root and
//  quality agree exactly, and that is what the cross-language vectors check.
//
//  **Ties are broken by dictionary order rather than by a stable sort.**
//  JavaScript's `Array.sort` is stable and Swift's is not, so the insertion
//  index is carried and compared last. Same answer, on purpose, rather than by
//  luck — this is the same class of bug as the non-total comparator that once
//  made `MelodyVariants.explore` return a different order on different runs.
//
//  Deliberately free of any FoundationModels dependency: it is arithmetic.
//

import Foundation

/// A chord read off a set of notes.
struct DetectedChord: Hashable, Sendable {
    let rootPitchClass: Int
    let quality: ChordQuality
    /// Spelled the way `ChordParser` spells things, so it re-parses.
    let symbol: String
    /// The pitch classes that were actually sounding.
    let observedPitchClasses: [Int]
    /// What the quality says should be there.
    let templatePitchClasses: [Int]
    /// Sounding but not in the quality — passing tones, added colour.
    let extras: [Int]
    /// In the quality but not sounding — an omitted fifth, most often.
    let missing: [Int]
    /// Set when the lowest note is a chord tone other than the root.
    let bassPitchClass: Int?

    /// How well the name fits what was played. 1 is exact.
    var confidence: Double {
        let explained = Double(templatePitchClasses.count - missing.count)
        let total = Double(templatePitchClasses.count + extras.count)
        return total > 0 ? max(0, explained / total) : 0
    }
}

/// A note, as reading harmony off one needs it: when it starts, how long it
/// sounds, and which pitch it is.
///
/// Three fields, deliberately. `SequencedNote` has velocity and a channel and
/// belongs to the carrier layer above this one; detection has no use for either,
/// and taking the whole thing was the only reason theory named a carrier type.
struct SoundingNote: Hashable, Sendable {
    var startBeat: Double
    var durationBeats: Double
    /// MIDI note number. Detection only ever reduces it mod 12.
    var pitch: Int

    init(startBeat: Double, durationBeats: Double, pitch: Int) {
        self.startBeat = startBeat
        self.durationBeats = durationBeats
        self.pitch = pitch
    }
}

enum ChordDetection {

    // MARK: - Entry points

    /// Names the chord in a set of MIDI note numbers.
    ///
    /// Register matters here only for the slash bass: the lowest note being a
    /// chord tone other than the root is what makes "Dm7/A" rather than "Dm7".
    static func detect(pitches: [Int]) -> DetectedChord? {
        guard !pitches.isEmpty else { return nil }
        let unique = uniquePitchClasses(pitches)
        guard unique.count >= 2 else { return nil }
        return match(unique, lowest: pitches.min())
    }

    /// Names the chord in a set of pitch classes, with no register to read.
    ///
    /// Never produces a slash chord, because nothing here says which note was
    /// underneath.
    static func detect(pitchClasses: [Int]) -> DetectedChord? {
        let unique = uniquePitchClasses(pitchClasses)
        guard unique.count >= 2 else { return nil }
        return match(unique, lowest: nil)
    }

    private static func match(_ unique: [Int], lowest: Int?) -> DetectedChord? {
        if let exact = exactMatch(unique, lowest: lowest) { return exact }
        return subsetMatch(unique, lowest: lowest)
    }

    // MARK: - Matching

    private struct Scored {
        let root: Int
        let quality: ChordQuality
        let extraNotes: Int
        /// Where this candidate was found, so ties resolve the way a stable
        /// sort would resolve them.
        let order: Int
    }

    /// Every pitch class accounted for, nothing left over.
    private static func exactMatch(_ unique: [Int], lowest: Int?) -> DetectedChord? {
        var candidates: [Scored] = []
        for root in 0..<12 {
            let rotated = rotate(unique, to: root)
            guard let quality = quality(forFingerprint: fingerprint(rotated)) else { continue }
            if normalized(quality).count == unique.count {
                candidates.append(Scored(root: root, quality: quality,
                                         extraNotes: 0, order: candidates.count))
            }
        }
        guard let best = candidates.min(by: exactOrder) else { return nil }
        return build(root: best.root, quality: best.quality, observed: unique, lowest: lowest)
    }

    /// Simpler is more fundamental, and a lower root is the convention.
    private static func exactOrder(_ a: Scored, _ b: Scored) -> Bool {
        if a.quality.pitchClasses.count != b.quality.pitchClasses.count {
            return a.quality.pitchClasses.count < b.quality.pitchClasses.count
        }
        if a.root != b.root { return a.root < b.root }
        return a.order < b.order
    }

    /// The input carries notes the quality doesn't name — a passing tone, a
    /// doubling, an added colour. Drop one at a time and see what fits.
    private static func subsetMatch(_ unique: [Int], lowest: Int?) -> DetectedChord? {
        guard unique.count >= 3 else { return nil }
        var candidates: [Scored] = []
        for root in 0..<12 {
            let rotated = rotate(unique, to: root)
            for skip in rotated.indices {
                var subset = rotated
                subset.remove(at: skip)
                guard subset.count >= 2, subset.contains(0) else { continue }
                guard let quality = quality(forFingerprint: fingerprint(subset)) else { continue }
                let extra = max(0, rotated.count - normalized(quality).count)
                candidates.append(Scored(root: root, quality: quality,
                                         extraNotes: extra, order: candidates.count))
            }
        }
        guard let best = candidates.min(by: subsetOrder) else { return nil }
        return build(root: best.root, quality: best.quality, observed: unique, lowest: lowest)
    }

    /// Fewest notes left unexplained first — then, unlike the exact path, the
    /// *larger* quality, because it accounts for more of what was played.
    private static func subsetOrder(_ a: Scored, _ b: Scored) -> Bool {
        if a.extraNotes != b.extraNotes { return a.extraNotes < b.extraNotes }
        if a.quality.pitchClasses.count != b.quality.pitchClasses.count {
            return a.quality.pitchClasses.count > b.quality.pitchClasses.count
        }
        if a.root != b.root { return a.root < b.root }
        return a.order < b.order
    }

    private static func build(root: Int,
                              quality: ChordQuality,
                              observed: [Int],
                              lowest: Int?) -> DetectedChord {
        let template = Set(quality.pitchClasses.map { ((root + $0) % 12 + 12) % 12 })
        let observedSet = Set(observed)

        var bass: Int?
        if let lowest {
            let lowestPitchClass = ((lowest % 12) + 12) % 12
            if lowestPitchClass != root, template.contains(lowestPitchClass) {
                bass = lowestPitchClass
            }
        }

        var symbol = ChordProgression.flatNoteNames[root]
            + ChordDictionary.displaySuffix(forKey: quality.key)
        if let bass { symbol += "/" + ChordProgression.flatNoteNames[bass] }

        return DetectedChord(
            rootPitchClass: root,
            quality: quality,
            symbol: symbol,
            observedPitchClasses: observed.sorted(),
            templatePitchClasses: template.sorted(),
            extras: observed.filter { !template.contains($0) }.sorted(),
            missing: template.subtracting(observedSet).sorted(),
            bassPitchClass: bass
        )
    }

    // MARK: - A run of notes as changes

    /// What one bar of a chord track, or of somebody's playing, is doing.
    struct ReadChanges: Sendable {
        /// Leadsheet text `ChordProgression.parse` accepts.
        let text: String
        /// How many bars could be named, out of how many there were. An empty
        /// bar holds the chord before it, which is what the parser does with it.
        let namedBars: Int
        let totalBars: Int
        /// Whether the material moves rather than blocks — an arpeggio read one
        /// chord a bar is a guess, and the caller should say so.
        let looksArpeggiated: Bool

        var isConfident: Bool { namedBars > 0 && !looksArpeggiated }
    }

    /// Reads a progression off notes that were played rather than named.
    ///
    /// It takes `SoundingNote` rather than the carrier's `SequencedNote`, which
    /// is PORTING.md's last listed seam: detection needs a pitch, a start and a
    /// length, and nothing else a note carries. Taking the smaller thing is what
    /// makes this usable from a plug-in whose notes are a different struct — and
    /// the conversion is one `map` at the two call sites that have real notes.
    ///
    /// One chord a bar, from everything *sounding during* the bar rather than
    /// merely starting in it — a whole note tied across is still the harmony of
    /// the bar it covers. This is the shared implementation behind an imported
    /// chord track and behind "what did I just play"; two of them would drift.
    static func changes(in notes: [SoundingNote],
                        beatsPerBar: Double = 4,
                        endBeat: Double? = nil) -> ReadChanges? {
        guard !notes.isEmpty else { return nil }
        let bar = max(1, beatsPerBar)
        let last = endBeat ?? (notes.map { $0.startBeat + $0.durationBeats }.max() ?? bar)
        let barCount = max(1, Int(ceil(max(last, bar) / bar)))

        var bars: [String] = []
        var named = 0
        for index in 0..<barCount {
            let start = Double(index) * bar
            let end = start + bar
            let sounding = notes.filter {
                $0.startBeat < end - 0.001 && $0.startBeat + $0.durationBeats > start + 0.001
            }
            guard let chord = detect(pitches: sounding.map(\.pitch)) else {
                bars.append("")
                continue
            }
            named += 1
            bars.append(chord.symbol)
        }
        while bars.last?.isEmpty == true { bars.removeLast() }
        guard named > 0, !bars.isEmpty else { return nil }

        let text = bars.joined(separator: "|")
        guard (try? ChordProgression.parse(text, beatsPerBar: bar)) != nil else { return nil }
        return ReadChanges(text: text,
                           namedBars: named,
                           totalBars: bars.count,
                           looksArpeggiated: isArpeggiated(notes, beatsPerBar: bar))
    }

    /// Whether the harmony is being *inferred from succession* rather than read
    /// off notes that sound together.
    ///
    /// The threshold is deliberately strict: if almost nothing is simultaneous,
    /// one chord a bar is a guess however plausible the name looks — and a
    /// monophonic line will always spell *something*, because four notes in a
    /// bar are four pitch classes and the dictionary has 172 entries. Naming
    /// them without saying it was inferred is how a melody becomes a
    /// progression nobody played.
    static func isArpeggiated(_ notes: [SoundingNote], beatsPerBar: Double) -> Bool {
        guard notes.count >= 3 else { return false }
        let onsets = Set(notes.map { ($0.startBeat * 48).rounded() })
        let polyphony = Double(notes.count) / Double(max(1, onsets.count))
        let span = (notes.map { $0.startBeat }.max() ?? 0) + beatsPerBar
        let onsetsPerBar = Double(onsets.count) / max(1, span / beatsPerBar)
        return polyphony < 1.5 && onsetsPerBar > 1.0
    }

    // MARK: - Fingerprints

    /// Pitch class `i` contributes 2^i — the suite's convention, leftmost-LSB.
    static func fingerprint(_ pitchClasses: [Int]) -> Int {
        pitchClasses.reduce(0) { $0 | (1 << (((($1 % 12) + 12) % 12))) }
    }

    /// Rotate so `root` becomes 0, deduplicated and sorted.
    static func rotate(_ pitchClasses: [Int], to root: Int) -> [Int] {
        uniquePitchClasses(pitchClasses.map { $0 - root })
    }

    private static func uniquePitchClasses(_ values: [Int]) -> [Int] {
        Array(Set(values.map { (($0 % 12) + 12) % 12 })).sorted()
    }

    private static func normalized(_ quality: ChordQuality) -> Set<Int> {
        Set(quality.pitchClasses.map { (($0 % 12) + 12) % 12 })
    }

    private static func quality(forFingerprint value: Int) -> ChordQuality? {
        fingerprintIndex[value]
    }

    /// First entry wins, exactly as the suite's index does: two qualities that
    /// share a pitch class set (`sus2` and `add9no3`) both parse by name, and
    /// detection reports whichever the dictionary lists first — so the answer
    /// doesn't depend on which one you happened to ask about.
    private static let fingerprintIndex: [Int: ChordQuality] = {
        var index: [Int: ChordQuality] = [:]
        for quality in ChordDictionary.allQualities {
            let key = fingerprint(quality.pitchClasses)
            if index[key] == nil { index[key] = quality }
        }
        return index
    }()
}
