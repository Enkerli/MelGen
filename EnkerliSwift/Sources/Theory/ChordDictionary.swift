//
//  ChordDictionary.swift
//  MelGenExtension
//
//  Chord quality lookup, backed by the Music Suite / MIDIsplainer chord
//  dictionary. The 172-entry table itself lives in the generated companion
//  file; this is the lookup logic ported from music-suite's chordSymbol.ts.
//

import Foundation

public struct ChordQuality: Hashable, Sendable {
    /// Dictionary key, e.g. "maj7", "min", "7b9".
    public let key: String
    /// Descriptive name, e.g. "major seventh".
    public let fullName: String
    /// Compact display symbol, e.g. "∆", "-7", "ø".
    public let displaySymbol: String
    /// Pitch classes rooted at C.
    public let pitchClasses: [Int]
    public let aliases: [String]

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(key: String,
                fullName: String,
                displaySymbol: String,
                pitchClasses: [Int],
                aliases: [String]) {
        self.key = key
        self.fullName = fullName
        self.displaySymbol = displaySymbol
        self.pitchClasses = pitchClasses
        self.aliases = aliases
    }
}

public enum ChordDictionary {

    public static func quality(forKey key: String) -> ChordQuality? {
        keyIndex[key]
    }

    /// Resolves a written quality suffix ("m7", "∆9", "7alt", "") to a quality.
    ///
    /// Tries the suffix as written and then progressively normalized: ASCII
    /// accidentals, lowercased, and the long minor prefixes folded ("min7" → "m7").
    public static func quality(forSuffix suffix: String) -> ChordQuality? {
        for variant in suffixVariants(suffix) {
            if let key = suffixIndex[variant], let quality = keyIndex[key] {
                return quality
            }
        }
        return nil
    }

    /// Canonical compact suffix for a quality, for display.
    public static func displaySuffix(forKey key: String) -> String {
        displaySuffixes[key] ?? key
    }

    // MARK: - Indexes

    private static let keyIndex: [String: ChordQuality] = {
        Dictionary(allQualities.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }()

    /// Alias → key, in ascending precedence: lowercased aliases, exact aliases,
    /// exact keys, then the manual shorthand map. Matches chordSymbol.ts.
    private static let suffixIndex: [String: String] = {
        var index: [String: String] = [:]
        for quality in allQualities {
            for alias in quality.aliases { index[alias.lowercased()] = quality.key }
        }
        for quality in allQualities {
            for alias in quality.aliases { index[alias] = quality.key }
        }
        for quality in allQualities { index[quality.key] = quality.key }
        for (suffix, key) in manualSuffixKeys { index[suffix] = key }
        return index
    }()

    private static func suffixVariants(_ suffix: String) -> [String] {
        var variants: [String] = []
        func add(_ value: String) {
            if !variants.contains(value) { variants.append(value) }
        }

        add(suffix)
        add(suffix.lowercased())

        let ascii = suffix
            .replacingOccurrences(of: "𝄪", with: "##")
            .replacingOccurrences(of: "𝄫", with: "bb")
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "Δ", with: "∆")   // Greek delta → the maj7 glyph
            .replacingOccurrences(of: "△", with: "∆")
        add(ascii)
        add(ascii.lowercased())

        // Fold a leading "min"/"mi" to "m" so dictionary keys like "m7" match,
        // without ever touching "maj".
        for base in variants {
            if base.hasPrefix("min"), !base.hasPrefix("minMaj"), !base.hasPrefix("minmaj") {
                let rest = String(base.dropFirst(3))
                if rest.first?.isLetter != true || rest.hasPrefix("Maj") {
                    add("m" + rest)
                }
            } else if base.hasPrefix("mi"), base.count > 2 {
                let rest = String(base.dropFirst(2))
                if let first = rest.first, "0123456789#♯b♭MΔ∆".contains(first) {
                    add("m" + rest)
                }
            }
        }
        return variants
    }
}
