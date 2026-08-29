//
//  DiatonicHarmony.swift
//  MelGenExtension
//
//  A key, where the rest of the plug-in expects changes.
//
//  MelGen has always started from a progression, because that is what a
//  leadsheet is and because degree-relative material only means anything against
//  a chord. Plenty of music doesn't work that way. A modal vamp, a bass line
//  over a one-chord groove, most of what a step sequencer is for — these have a
//  key and a colour and no changes at all, and asking someone to type a chord
//  symbol to get one is asking them to answer a question they weren't posing.
//
//  So: a key and a *minorness* become a progression of exactly one chord that
//  lasts the whole form. Nothing downstream changes. The pattern format still
//  describes degrees, the histograms still read against a `DegreeContext`, the
//  kernel still loops a take. What's different is only that the harmony has one
//  member and the interface asks for it in two dials rather than in text.
//
//  ## The ladder
//
//  Minorness is a position on the modal brightness ladder, not a switch between
//  major and minor. The seven modes of the major scale sort into exactly one
//  order by how many notes they flatten, and each step down flattens exactly one
//  degree:
//
//      Lydian ──♯4→4── Ionian ──7→♭7── Mixolydian ──3→♭3── Dorian
//             ──6→♭6── Aeolian ──2→♭2── Phrygian ──5→♭5── Locrian
//
//  That is a continuum, it is the one every modal instrument's "brightness" knob
//  is secretly implementing, and it is the honest way to make "how minor is
//  this" a single control. At 0 the line is as bright as diatonic material gets;
//  at 1 it is as dark. Halfway is Dorian, which is where most of the music that
//  needs this dial actually lives.
//
//  A scale can't be fractional — the harmony has to commit — so the *chord* uses
//  the nearest rung while the *degree histogram* blends its two neighbours. That
//  is a real difference and it is audible: between Mixolydian and Dorian both
//  thirds carry weight, and the one the scale doesn't contain arrives as an
//  altered degree with its role recorded, which is exactly what the pattern
//  format was built to carry.
//
//  Deliberately free of any FoundationModels dependency.
//

import Foundation

enum DiatonicHarmony {

    /// The modes of the major scale, brightest first.
    ///
    /// One order, derived rather than chosen: each is a fifth's worth darker
    /// than the last, and each differs from its neighbour by exactly one
    /// flattened degree.
    static let ladder: [Scale] = [
        .lydian, .ionian, .mixolydian, .dorian, .aeolian, .phrygian, .locrian
    ]

    /// Where on the ladder a minorness sits, as a fractional index.
    static func rung(forMinorness minorness: Double) -> Double {
        max(0, min(1, minorness)) * Double(ladder.count - 1)
    }

    /// The mode a minorness commits to. The harmony's answer, as against the
    /// histogram's — see the file comment.
    static func mode(forMinorness minorness: Double) -> Scale {
        ladder[Int(rung(forMinorness: minorness).rounded())]
    }

    /// The two rungs a minorness sits between, and how far down it is.
    ///
    /// `t` runs toward the darker of the two, so landing exactly on a rung gives
    /// `t == 0` and the brighter entry is the whole answer. At the dark end of
    /// the ladder there is nothing below, so both entries are Locrian. Either
    /// way a caller can blend unconditionally and never special-case a rung.
    static func neighbours(forMinorness minorness: Double) -> (brighter: Scale, darker: Scale, t: Double) {
        let position = rung(forMinorness: minorness)
        let above = Int(position.rounded(.down))
        let below = min(ladder.count - 1, above + 1)
        return (ladder[above], ladder[below], position - Double(above))
    }

    /// What to call a minorness, in words.
    ///
    /// The number is meaningless on its own and the mode name is the thing
    /// anyone actually wants to know, so the control says the name.
    static func label(forMinorness minorness: Double) -> String {
        let (brighter, darker, t) = neighbours(forMinorness: minorness)
        if brighter == darker || t < 0.15 { return brighter.displayName }
        if t > 0.85 { return darker.displayName }
        return "\(brighter.displayName)–\(darker.displayName)"
    }

    // MARK: - The chord over a key

    /// The tonic seventh chord of a mode, as semitones above the root.
    ///
    /// Degrees 1, 3, 5 and 7 of the scale, which is what "the chord this mode
    /// is" means and what a modal chart writes on the staff. Dorian gives a
    /// minor seventh, Mixolydian a dominant, Locrian a half-diminished, and so
    /// on — every one of them falls out rather than being tabulated.
    static func tonicSeventh(of scale: Scale) -> [Int] {
        let intervals = scale.intervals
        return [0, 2, 4, 6].compactMap { step in
            intervals.indices.contains(step) ? intervals[step] : nil
        }
    }

    /// The dictionary quality that spells a mode's tonic seventh, so a modal
    /// chord still has a real quality and still displays as a chord symbol.
    ///
    /// Falls back to a synthesized quality rather than failing: an eight-note
    /// scale's tonic seventh may not be in the dictionary, and refusing to build
    /// a chord because its name isn't catalogued would be the tail wagging the dog.
    static func quality(forTonicOf scale: Scale) -> ChordQuality {
        let tones = tonicSeventh(of: scale)
        let match = ChordDictionary.allQualities.first {
            Set($0.pitchClasses.map { ChordScales.pitchClass($0) }) == Set(tones)
        }
        return match ?? ChordQuality(key: scale.rawValue,
                                     fullName: "\(scale.displayName) tonic",
                                     displaySymbol: "",
                                     pitchClasses: tones,
                                     aliases: [])
    }

    /// The chord for a key in a mode, with its scale stated rather than inferred.
    static func symbol(root: Int, scale: Scale) -> ChordSymbol {
        ChordSymbol(rootPitchClass: ChordScales.pitchClass(root),
                    quality: quality(forTonicOf: scale),
                    scale: scale,
                    text: text(root: root, scale: scale))
    }

    /// How a modal chord is written, and therefore how it parses back.
    ///
    /// Parentheses because a bar splits on whitespace, so "C lydian" is two
    /// tokens and cannot be one chord. The mode has to travel with the root or
    /// a take reloaded from history comes back in a different scale.
    static func text(root: Int, scale: Scale) -> String {
        "\(ChordProgression.flatNoteNames[ChordScales.pitchClass(root)])(\(scale.rawValue))"
    }

    /// Reads a modal suffix, or returns nil so the dictionary gets its turn.
    ///
    /// The parentheses are required, and that is not a stylistic preference: the
    /// chord dictionary already spells two triads "major" and "minor", so a bare
    /// `Cminor` is a chord somebody meant and reading it as a scale would take a
    /// working symbol away. Inside parentheses nothing is shadowed, because no
    /// chord alias is written with them around the whole suffix.
    ///
    /// Accepts "(dorian)", "(Dorian)", "(melodic minor)" and "(melodicMinor)",
    /// plus the two names people reach for that aren't mode names — "(major)"
    /// and "(minor)" — because refusing those would be pedantry with a parse
    /// error attached.
    static func symbol(root: Int, suffix: String) -> ChordSymbol? {
        let name = suffix.trimmingCharacters(in: .whitespaces)
        guard name.hasPrefix("("), name.hasSuffix(")"), name.count > 2 else { return nil }
        let key = name.dropFirst().dropLast().lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard !key.isEmpty else { return nil }

        if let alias = friendlyNames[key] { return symbol(root: root, scale: alias) }
        guard let scale = Scale.allCases.first(where: { $0.rawValue.lowercased() == key }) else {
            return nil
        }
        return symbol(root: root, scale: scale)
    }

    private static let friendlyNames: [String: Scale] = [
        "major": .ionian,
        "minor": .aeolian,
        "naturalminor": .aeolian,
        "wholetone": .wholeTone,
        "lydiandominant": .lydianDominant,
        "lydianaugmented": .lydianAugmented,
        "melodicminor": .melodicMinor,
        "diminished": .diminishedWholeHalf
    ]

    // MARK: - A progression that is only a key

    /// A modal vamp as leadsheet text: one chord, held for `bars`.
    ///
    /// Empty bars after the first, because `parse` reads an empty bar as "hold
    /// the previous chord" — so four bars of D Dorian is `D(dorian)|||` rather
    /// than the same token four times. Shorter to read, and it is what somebody
    /// would write by hand.
    ///
    /// This is what "a key" *is* now: there is no separate harmony source and no
    /// switch, because a key with a mode is a progression with one chord in it,
    /// and every generator already reads a progression.
    static func vamp(key: Int, scale: Scale, bars: Int) -> String {
        text(root: key, scale: scale) + String(repeating: "|", count: max(0, bars - 1))
    }

    /// One chord, for the whole form.
    ///
    /// The form is still measured in bars because everything downstream is —
    /// the kernel loops beats, the pattern format counts eighths, and a key with
    /// no length is not something that can be played.
    static func progression(key: Int,
                            minorness: Double,
                            bars: Int,
                            beatsPerBar: Double = 4) -> ChordProgression {
        let scale = mode(forMinorness: minorness)
        let symbol = symbol(root: key, scale: scale)
        let beats = Double(max(1, bars)) * beatsPerBar
        return ChordProgression(
            text: symbol.text,
            chords: [PlacedChord(symbol: symbol, startBeat: 0, durationBeats: beats)],
            totalBeats: beats
        )
    }

}

// The bridge to the histograms lives in DegreeHistogram.swift rather than here,
// deliberately. This file is about harmony and depends on nothing but the chord
// dictionary and the scales — which is what lets `verify.sh chords` compile the
// theory layer on its own, at -O, without dragging in the whole Melody set.
// `ChordParser` calls into it to read a modal token, so anything this file
// imports, the parser imports too.
