//
//  DiamondPad.swift
//  MelGenExtension
//
//  The two-axis control that mixes four bass figures.
//
//  Two sliders would fit the same information into less space and would be
//  wrong, because the settings worth having are the ones *between* corners and a
//  pair of sliders never shows you that you're between them. A pad does: the
//  puck's distance from each corner is how much of that corner you're getting,
//  and it is legible at a glance in a way "0.4 / −0.6" is not.
//
//  A diamond rather than a square because the weights have to be a partition —
//  see `BasslineDiamond.setPoint(x:y:)`. The shape is the constraint, drawn.
//
//  Assistive technology gets it as two adjustable values rather than as a
//  gesture, since a drag target with no keyboard equivalent is a control only
//  some people have.
//

import SwiftUI

struct DiamondPad: View {
    @Binding var diamond: BasslineDiamond
    let theme: MelGenTheme
    /// Called after a drag settles, so the caller can redraw rather than
    /// regenerating on every frame of a gesture.
    var onSettle: () -> Void = {}

    /// One nudge, for the accessibility actions and the arrow-key equivalents.
    private static let step = 0.1

    var body: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space1) {
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let centre = CGPoint(x: size / 2, y: size / 2)
                let radius = size / 2 - 14

                ZStack {
                    diamondShape(centre: centre, radius: radius)
                        .fill(theme.sunken)
                    diamondShape(centre: centre, radius: radius)
                        .stroke(theme.borderStrong, lineWidth: 1)

                    // The axes, faint: without them the centre is guesswork, and
                    // the centre is the one position anyone wants to return to.
                    Path { path in
                        path.move(to: CGPoint(x: centre.x - radius, y: centre.y))
                        path.addLine(to: CGPoint(x: centre.x + radius, y: centre.y))
                        path.move(to: CGPoint(x: centre.x, y: centre.y - radius))
                        path.addLine(to: CGPoint(x: centre.x, y: centre.y + radius))
                    }
                    .stroke(theme.border, lineWidth: 1)

                    corner(.onBeat, at: CGPoint(x: centre.x, y: centre.y - radius - 7))
                    corner(.offBeat, at: CGPoint(x: centre.x, y: centre.y + radius + 7))
                    corner(.running, at: CGPoint(x: centre.x + radius - 2, y: centre.y))
                    corner(.anchored, at: CGPoint(x: centre.x - radius + 2, y: centre.y))

                    Circle()
                        .fill(theme.accent)
                        .frame(width: 18, height: 18)
                        .position(x: centre.x + CGFloat(diamond.x) * radius,
                                  y: centre.y - CGFloat(diamond.y) * radius)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            diamond.setPoint(
                                x: Double((value.location.x - centre.x) / radius),
                                y: Double((centre.y - value.location.y) / radius))
                        }
                        .onEnded { _ in onSettle() }
                )
            }
            .frame(height: 168)
            .accessibilityElement()
            .accessibilityLabel("Figure mix")
            .accessibilityValue(readout)
            .accessibilityHint("Mixes the four bass figures")
            .accessibilityAdjustableAction { direction in
                nudge(y: direction == .increment ? Self.step : -Self.step)
            }
            .accessibilityAction(named: "More running") { nudge(x: Self.step) }
            .accessibilityAction(named: "More anchored") { nudge(x: -Self.step) }
            .accessibilityAction(named: "Centre") {
                diamond.setPoint(x: 0, y: 0)
                onSettle()
            }

            Text(readout)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.textMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the puck's position adds up to, in words rather than in numbers.
    private var readout: String {
        let weights = diamond.weights
        return BasslineCorner.allCases
            .compactMap { corner -> (String, Int)? in
                let percent = Int(((weights[corner] ?? 0) * 100).rounded())
                guard percent >= 5 else { return nil }
                return (diamond.figure(at: corner).name, percent)
            }
            .sorted { $0.1 > $1.1 }
            .map { "\($0.0) \($0.1)%" }
            .joined(separator: " · ")
    }

    private func nudge(x: Double = 0, y: Double = 0) {
        diamond.setPoint(x: diamond.x + x, y: diamond.y + y)
        onSettle()
    }

    private func corner(_ corner: BasslineCorner, at point: CGPoint) -> some View {
        Text(diamond.figure(at: corner).name)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme.textMuted)
            .lineLimit(1)
            .fixedSize()
            .position(point)
    }

    private func diamondShape(centre: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: centre.x, y: centre.y - radius))
        path.addLine(to: CGPoint(x: centre.x + radius, y: centre.y))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y + radius))
        path.addLine(to: CGPoint(x: centre.x - radius, y: centre.y))
        path.closeSubpath()
        return path
    }
}
