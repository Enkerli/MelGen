//
//  FigurePad.swift
//  MelGenExtension
//
//  The two-axis control at the middle of Bass.
//
//  Two sliders would fit the same information into less space and would be
//  wrong, because the settings worth having are the ones *between* the ends and
//  a pair of sliders never shows you that you're between them. A pad does: where
//  the puck sits is what you are getting, and it is legible at a glance in a way
//  "−0.4 / 0.6" is not.
//
//  Left to right is the balance between the two layers — on the beat at the
//  west, off it at the east, both at full in the middle — and up and down is
//  which pair of figures is in play, sparsest at the bottom and busiest at the
//  top. `BasslinePad` has the reasoning for both, including why the region is a
//  square: the two axes mean two independent things, so a shape that trades one
//  against the other takes settings away rather than describing anything.
//
//  Assistive technology gets it as two adjustable values rather than as a
//  gesture, since a drag target with no keyboard equivalent is a control only
//  some people have.
//

import SwiftUI
import UI

struct FigurePad: View {
    @Binding var pad: BasslinePad
    let theme: MelGenTheme
    /// Called after a drag settles, so the caller can redraw rather than
    /// regenerating on every frame of a gesture.
    var onSettle: () -> Void = {}

    /// One nudge, for the accessibility actions.
    private static let step = 0.1

    var body: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space1) {
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let centre = CGPoint(x: size / 2, y: size / 2)
                let radius = size / 2 - 16

                ZStack {
                    padShape(centre: centre, radius: radius)
                        .fill(theme.sunken)
                    padShape(centre: centre, radius: radius)
                        .stroke(theme.borderStrong, lineWidth: 1)

                    // The axes, faint: without them the centre is guesswork, and
                    // the centre — both layers at full, mid-bank — is the one
                    // position anyone wants to be able to return to.
                    Path { path in
                        path.move(to: CGPoint(x: centre.x - radius, y: centre.y))
                        path.addLine(to: CGPoint(x: centre.x + radius, y: centre.y))
                        path.move(to: CGPoint(x: centre.x, y: centre.y - radius))
                        path.addLine(to: CGPoint(x: centre.x, y: centre.y + radius))
                    }
                    .stroke(theme.border, lineWidth: 1)

                    end(.busiest, at: CGPoint(x: centre.x, y: centre.y - radius - 8))
                    end(.sparsest, at: CGPoint(x: centre.x, y: centre.y + radius + 8))
                    end(.offBeat, at: CGPoint(x: centre.x + radius + 2, y: centre.y),
                        rotated: true)
                    end(.onBeat, at: CGPoint(x: centre.x - radius - 2, y: centre.y),
                        rotated: true)

                    Circle()
                        .fill(theme.accent)
                        .frame(width: 18, height: 18)
                        .position(x: centre.x + CGFloat(pad.x) * radius,
                                  y: centre.y - CGFloat(pad.y) * radius)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            pad.setPoint(
                                x: Double((value.location.x - centre.x) / radius),
                                y: Double((centre.y - value.location.y) / radius))
                        }
                        .onEnded { _ in onSettle() }
                )
            }
            .frame(height: 176)
            .accessibilityElement()
            .accessibilityLabel("Figure pad")
            .accessibilityValue(spokenValue)
            .accessibilityHint("Left and right balance the on-beat and off-beat layers; "
                               + "up and down choose which figures play")
            .accessibilityAdjustableAction { direction in
                nudge(y: direction == .increment ? Self.step : -Self.step)
            }
            .accessibilityAction(named: "More off the beat") { nudge(x: Self.step) }
            .accessibilityAction(named: "More on the beat") { nudge(x: -Self.step) }
            .accessibilityAction(named: "Centre") {
                pad.setPoint(x: 0, y: 0)
                onSettle()
            }

            Text(pad.readout)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.textMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the puck's position means, said rather than shown — the pad's own
    /// caption is the two figure names, and this adds the axis it sits on.
    private var spokenValue: String {
        let sideways: String
        switch pad.balance {
        case ..<(-0.66): sideways = "on the beat"
        case ..<(-0.2): sideways = "mostly on the beat"
        case ..<0.2: sideways = "both layers"
        case ..<0.66: sideways = "mostly off the beat"
        default: sideways = "off the beat"
        }
        return "\(sideways), \(pad.readout)"
    }

    private func nudge(x: Double = 0, y: Double = 0) {
        pad.setPoint(x: pad.x + x, y: pad.y + y)
        onSettle()
    }

    /// The axis ends, sitting outside the pad so the puck never hides one. The
    /// two horizontal ones are turned on their side, because a pad wide enough
    /// to hold "On the beat" beside it is a pad that has stopped being square.
    private func end(_ end: BasslineAxisEnd, at point: CGPoint,
                     rotated: Bool = false) -> some View {
        Text(end.label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme.textMuted)
            .lineLimit(1)
            .fixedSize()
            .rotationEffect(.degrees(rotated ? -90 : 0))
            .position(point)
    }

    private func padShape(centre: CGPoint, radius: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: centre.x - radius, y: centre.y - radius,
                                 width: radius * 2, height: radius * 2),
             cornerRadius: MelGenMetrics.radiusSmall)
    }
}
