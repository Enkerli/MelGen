//
//  PatternStore.swift
//  MelGenExtension
//
//  The library that outlives a session.
//
//  The take history lives in the host's saved state, which means it belongs to
//  one project in one host — reasonable for a log, wrong for a library. A line
//  you lifted from a take you liked should be there in the next session, in the
//  next host, over the next set of changes. So the derived patterns live here,
//  in the extension's own defaults, rather than in the document.
//
//  That's the cheap version of the split. The real one is an App Group container
//  shared with the host app and eventually with the siblings (ROADMAP I5/L4);
//  this at least puts the library on the right side of the line, so moving it
//  later is a change of storage rather than a change of meaning.
//

import Foundation

enum PatternStore {
    private static let defaultsKey = "MelGen.userPatterns"

    /// Lines lifted from takes, newest first.
    static var userPatterns: [MelodyPattern] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let patterns = try? JSONDecoder().decode([MelodyPattern].self, from: data) else {
            return []
        }
        return patterns
    }

    /// What the rotation draws from: the hand-written seeds, the interval cells,
    /// then yours.
    ///
    /// The seeds stay, deliberately. They're generic on purpose — the property
    /// that makes them fit anything is the same one that makes them plain — and a
    /// library with nothing in it yet still has to play something. The interval
    /// cells (Hanon's exercises and Samchillian-style streams) are there because
    /// they're a different *kind* of generic: shapes defined by their moves
    /// rather than their positions, which sequence themselves.
    static var library: [MelodyPattern] {
        MelodyPatterns.seeds + MelodyStepPatterns.library() + userPatterns
    }

    static var isEmpty: Bool { userPatterns.isEmpty }

    @discardableResult
    static func add(_ pattern: MelodyPattern) -> MelodyPattern {
        var patterns = userPatterns
        var stored = pattern
        stored.name = uniqueName(from: pattern.name)
        patterns.insert(stored, at: 0)
        write(patterns)
        return stored
    }

    static func remove(named name: String) {
        write(userPatterns.filter { $0.name != name })
    }

    static func removeAll() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// Names are the identity here, so two lines can't share one.
    static func uniqueName(from base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? "Line" : trimmed
        let taken = Set(library.map(\.name))
        guard taken.contains(candidate) else { return candidate }
        var index = 2
        while taken.contains("\(candidate) \(index)") { index += 1 }
        return "\(candidate) \(index)"
    }

    private static func write(_ patterns: [MelodyPattern]) {
        guard let data = try? JSONEncoder().encode(patterns) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
