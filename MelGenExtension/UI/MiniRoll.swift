//
//  MiniRoll.swift
//  MelGenExtension
//
//  The take, in 44 points, in the bar that never scrolls.
//
//  The action grammar pinned rate, roll and advance — and then the thing they
//  act on scrolled away, so the bar was a set of buttons with no object. This is
//  the object. Once it is there the bar stops being a toolbar and becomes the
//  instrument, which is the permission the layout pass needed to take anything
//  away at all.
//
//  **Not a small piano roll.** A different drawing with a different job, and the
//  distinction is the whole design: `PianoRoll` answers *which note is that, and
//  does it belong* — it needs rows, scale shading, roles, a legend. This answers
//  *where am I, what is the shape, is it dense or sparse*, and nothing it draws
//  needs explaining. Shrinking the full roll to 44pt would have produced a
//  thing that looked like it could be read and couldn't.
//
//  So: register becomes height rather than a row, notes become marks rather than
//  bars, the scale shading goes entirely, and the only colour that survives is
//  the one that means *look at this* — a note the analyser flagged for review.
//  Chord names stay, because "where am I" is mostly a harmonic question.
//
//  It is also the swipe target, which the full roll used to be. That follows
//  from it being the thing on screen: you rate what you can see.
//

import SwiftUI

/// A glance at the take: where the playhead is, what shape the line has, and
/// whether anything wants looking at.
struct MiniRoll: View {
    let notes: [SequencedNote]
    let progression: ChordProgression?
    let lengthBeats: Double
    let theme: MelGenTheme
    /// Where the loop is now, in beats, or nil when nothing is playing.
    var playheadBeat: Double?

    /// 44pt: the touch target, so the swipe has something honest to land on and
    /// the bar gains one row rather than a panel.
    static let height: CGFloat = MelGenMetrics.controlHeight

    /// Air above and below the marks, so the highest and lowest notes are inside
    /// the drawing rather than on its edge.
    private static let verticalPadding: CGFloat = 7
    /// How thick a note reads. Three points is the smallest mark that still has
    /// a length you can see, which is what makes density legible.
    private static let markHeight: CGFloat = 3

    private var pitchSpan: (low: Int, high: Int) {
        let pitches = notes.map { Int($0.note) }
        guard let low = pitches.min(), let high = pitches.max() else { return (60, 72) }
        // One extra semitone either side, and a floor, so a one-note take is a
        // mark in the middle rather than a mark against the top edge.
        return (low - 1, max(high + 1, low + 3))
    }

    var body: some View {
        Canvas { context, size in
            let beats = max(1, lengthBeats)
            let beatWidth = size.width / CGFloat(beats)

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.sunken))
            draw(chordTicks: context, size: size, beatWidth: beatWidth)
            draw(marks: context, size: size, beatWidth: beatWidth)
            draw(playhead: context, size: size, beatWidth: beatWidth)
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall))
        .accessibilityElement()
        .accessibilityLabel("What is sounding")
        .accessibilityValue(spokenSummary)
        .accessibilityHint("Opens the full roll. Swipe to rate and advance.")
    }

    /// A tick where each chord starts, weighted by whether it is also a bar line.
    ///
    /// Only at chord starts, not on every beat: a beat grid at this size is a
    /// hatch pattern, and the question this drawing answers is harmonic.
    private func draw(chordTicks context: GraphicsContext, size: CGSize, beatWidth: CGFloat) {
        guard let progression else { return }
        for placed in progression.chords {
            let x = CGFloat(placed.startBeat) * beatWidth
            let isBar = placed.startBeat.truncatingRemainder(dividingBy: 4) < 0.001
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(line,
                           with: .color(isBar ? theme.borderStrong : theme.border),
                           lineWidth: isBar ? 1 : 0.5)

            context.draw(Text(placed.symbol.text)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(theme.textMuted),
                         at: CGPoint(x: x + 3, y: 3),
                         anchor: .topLeading)
        }
    }

    /// Notes as marks, register as height.
    ///
    /// The one thing that keeps its colour is a note the analyser flagged —
    /// avoid or off-scale — because *is anything wrong* is the one question
    /// worth answering at a glance, and answering it is what stops the mini roll
    /// being decorative.
    private func draw(marks context: GraphicsContext, size: CGSize, beatWidth: CGFloat) {
        let span = pitchSpan
        let band = size.height - Self.verticalPadding * 2
        let range = CGFloat(max(1, span.high - span.low))

        for note in notes {
            let pitch = CGFloat(Int(note.note) - span.low)
            let y = Self.verticalPadding + band * (1 - pitch / range)
            let x = CGFloat(note.startBeat) * beatWidth
            let width = max(2.5, CGFloat(note.durationBeats) * beatWidth - 1.5)
            let rect = CGRect(x: x, y: y - Self.markHeight / 2,
                              width: width, height: Self.markHeight)
            context.fill(Path(roundedRect: rect, cornerRadius: Self.markHeight / 2),
                         with: .color(colour(of: note)))
        }
    }

    private func colour(of note: SequencedNote) -> Color {
        guard let progression else { return theme.accent }
        switch MelodyAnalyser.role(of: note, in: progression) {
        case .chordTone: return theme.accent
        case .colour: return theme.accent.opacity(0.6)
        case .avoid: return theme.warning
        case .offScale: return theme.text.opacity(0.5)
        }
    }

    private func draw(playhead context: GraphicsContext, size: CGSize, beatWidth: CGFloat) {
        guard let playheadBeat, lengthBeats > 0 else { return }
        let x = CGFloat(min(max(playheadBeat, 0), lengthBeats)) * beatWidth
        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(line, with: .color(theme.accent), lineWidth: 1.5)
    }

    /// What the drawing says, for anyone who can't see it.
    ///
    /// The same three facts the picture carries — how much, how wide, and
    /// whether anything wants looking at — rather than a note-by-note reading,
    /// which is what the full roll's notation summary is for.
    private var spokenSummary: String {
        guard !notes.isEmpty else { return "nothing yet" }
        let pitches = notes.map { Int($0.note) }
        let low = pitches.min() ?? 60
        let high = pitches.max() ?? 72
        var parts = ["\(notes.count) notes",
                     "\(ChordProgression.noteName(forMIDINote: low)) to \(ChordProgression.noteName(forMIDINote: high))"]
        if let progression {
            let flagged = notes.filter {
                let role = MelodyAnalyser.role(of: $0, in: progression)
                return role == .avoid || role == .offScale
            }.count
            if flagged > 0 { parts.append("\(flagged) to review") }
        }
        return parts.joined(separator: ", ")
    }
}
