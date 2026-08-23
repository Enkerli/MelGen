//
//  PianoRoll.swift
//  MelGenExtension
//
//  Seeing the take instead of reading about it.
//
//  The text grid (`MelodyNotation`) made rests and note lengths *readable*, which
//  was a real improvement over a run of note names, and it has a hard ceiling:
//  one column is one eighth, so everything smaller than an eighth is invisible.
//  That covers gate length, which is the control most likely to be doing
//  something you can't account for, and micro-timing, and — since comping — it
//  covers polyphony too, because a column can only hold one name.
//
//  Two things this draws that a piano roll usually doesn't, both because they're
//  the things worth seeing *here*:
//
//  **The chord regions are behind the notes**, with the scale of each chord
//  shaded. A wrong note is only legible against the harmony it's wrong for, and
//  MelGen always knows the harmony — so the row a note sits in tells you whether
//  it belongs before you've worked out what note it is.
//
//  **Notes are coloured by their harmonic role**, from the same
//  `MelodyAnalyser.role` that scores takes. Chord tone, colour note, avoid note,
//  off-scale. The measurement and the picture agree by construction rather than
//  by being kept in step.
//

import SwiftUI

struct PianoRoll: View {
    let notes: [SequencedNote]
    let progression: ChordProgression?
    let lengthBeats: Double
    let theme: MelGenTheme
    /// Points per beat. Wide enough that an eighth is a comfortable target and
    /// a gate difference of a sixteenth is visible.
    var beatWidth: CGFloat = 34
    var height: CGFloat = 170

    /// The pitches on show, padded so a one-note take doesn't fill the view with
    /// a single enormous bar and a busy one still has air above and below.
    private var pitchRange: ClosedRange<Int> {
        let pitches = notes.map { Int($0.note) }
        guard let low = pitches.min(), let high = pitches.max() else { return 60...72 }
        let padded = max(11, high - low + 4)
        let centre = (low + high) / 2
        return (centre - padded / 2)...(centre + padded / 2)
    }

    private var rowCount: Int { pitchRange.upperBound - pitchRange.lowerBound + 1 }

    var body: some View {
        let beats = max(1, lengthBeats)
        let width = CGFloat(beats) * beatWidth

        ScrollView(.horizontal, showsIndicators: true) {
            Canvas { context, size in
                let rowHeight = size.height / CGFloat(rowCount)
                draw(chords: context, size: size, rowHeight: rowHeight)
                draw(grid: context, size: size, rowHeight: rowHeight)
                draw(notes: context, size: size, rowHeight: rowHeight)
            }
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(theme.sunken)
            )
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Piano roll")
        .accessibilityValue(accessibleDescription)
    }

    // MARK: - Layers

    /// The harmony, behind everything. Each chord's own scale is shaded, so a
    /// note outside it reads as outside without any colour being needed.
    private func draw(chords context: GraphicsContext, size: CGSize, rowHeight: CGFloat) {
        guard let progression else { return }

        for (index, placed) in progression.chords.enumerated() {
            let x = CGFloat(placed.startBeat) * beatWidth
            let chordWidth = CGFloat(placed.durationBeats) * beatWidth
            let region = CGRect(x: x, y: 0, width: chordWidth, height: size.height)

            context.fill(Path(region),
                         with: .color(index.isMultiple(of: 2) ? theme.sunken : theme.raised))

            let scale = Set(placed.symbol.scalePitchClasses)
            let tones = Set(placed.symbol.tonePitchClasses)
            for row in 0..<rowCount {
                let pitch = pitchRange.upperBound - row
                let pitchClass = ((pitch % 12) + 12) % 12
                guard scale.contains(pitchClass) else { continue }
                let rect = CGRect(x: x, y: CGFloat(row) * rowHeight,
                                  width: chordWidth, height: rowHeight)
                // Chord tones sit a shade stronger than the rest of the scale:
                // the difference between "fits" and "is the chord".
                context.fill(Path(rect),
                             with: .color(theme.accent.opacity(tones.contains(pitchClass) ? 0.16 : 0.07)))
            }

            context.draw(Text(placed.symbol.text)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(theme.textMuted),
                         at: CGPoint(x: x + 4, y: 8),
                         anchor: .topLeading)
        }
    }

    /// Bar lines heavy, beats light. Enough to place a note in time and no more.
    private func draw(grid context: GraphicsContext, size: CGSize, rowHeight: CGFloat) {
        var beat = 0.0
        while beat <= lengthBeats + 0.001 {
            let x = CGFloat(beat) * beatWidth
            let isBar = beat.truncatingRemainder(dividingBy: 4) < 0.001
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(line,
                           with: .color(isBar ? theme.borderStrong : theme.border),
                           lineWidth: isBar ? 1.2 : 0.5)
            beat += 1
        }
    }

    private func draw(notes context: GraphicsContext, size: CGSize, rowHeight: CGFloat) {
        for note in notes {
            let pitch = Int(note.note)
            guard pitchRange.contains(pitch) else { continue }
            let row = pitchRange.upperBound - pitch
            let x = CGFloat(note.startBeat) * beatWidth
            // Full height minus a hair, so two voices a semitone apart in a
            // voicing are still two bars rather than one block.
            let rect = CGRect(x: x + 0.5,
                              y: CGFloat(row) * rowHeight + 0.5,
                              width: max(2, CGFloat(note.durationBeats) * beatWidth - 1),
                              height: max(2, rowHeight - 1))

            let shape = Path(roundedRect: rect, cornerRadius: min(3, rowHeight / 3))
            context.fill(shape, with: .color(colour(for: note)))
            context.stroke(shape, with: .color(theme.background.opacity(0.5)), lineWidth: 0.5)

            // Velocity as opacity would fight the role colours, so it's a cap on
            // the bar instead: a quiet note is a thinner bar, which reads at a
            // glance and doesn't lie about what the note is.
            let velocityHeight = max(1, rowHeight * CGFloat(note.velocity) / 127 * 0.35)
            let cap = CGRect(x: rect.minX, y: rect.maxY - velocityHeight,
                             width: rect.width, height: velocityHeight)
            context.fill(Path(cap), with: .color(theme.text.opacity(0.25)))
        }
    }

    /// The role colours, from the same classification that scores a take.
    private func colour(for note: SequencedNote) -> Color {
        guard let progression else { return theme.accent }
        switch MelodyAnalyser.role(of: note, in: progression) {
        case .chordTone: return theme.accent
        case .colour: return theme.accent.opacity(0.62)
        case .avoid: return theme.warning
        case .offScale: return theme.text.opacity(0.55)
        }
    }

    private var accessibleDescription: String {
        guard !notes.isEmpty else { return "Nothing loaded" }
        let low = notes.map { Int($0.note) }.min() ?? 60
        let high = notes.map { Int($0.note) }.max() ?? 72
        var description = "\(notes.count) notes, "
            + "\(ChordProgression.noteName(forMIDINote: low)) to "
            + "\(ChordProgression.noteName(forMIDINote: high))"
        if let progression {
            let analysis = MelodyAnalyser.analyse(notes, over: progression)
            description += ", \(analysis.summary)"
        }
        return description
    }
}
