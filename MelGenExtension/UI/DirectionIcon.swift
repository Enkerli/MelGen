//
//  DirectionIcon.swift
//  MelGenExtension
//
//  Playback-direction arrows drawn the way DrawnQurve draws them
//  (Source/UI/IconFactory.h: makeDirectionLeft / Right / PingPong): a plain
//  shaft with an arrowhead on the end that the playhead travels toward, and one
//  on each end for ping-pong.
//
//  SF Symbols don't have an equivalent — `backward.fill` reads as "rewind to the
//  previous track" and `arrow.left.arrow.right` as "swap", neither of which is
//  what the direction parameter does.
//

import SwiftUI

struct DirectionIcon: Shape {
    enum Direction {
        case backward, pingPong, forward
    }

    let direction: Direction

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let width = rect.width
        let height = rect.height

        // Proportions taken from DrawnQurve's icon factory.
        let shaft = width * 0.18
        let headBack = width * 0.10
        let headRise = height * 0.14

        func arrowhead(at tip: CGPoint, pointingLeft: Bool) {
            let inset = pointingLeft ? headBack : -headBack
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x + inset, y: centre.y - headRise))
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x + inset, y: centre.y + headRise))
        }

        let left = CGPoint(x: centre.x - shaft, y: centre.y)
        let right = CGPoint(x: centre.x + shaft, y: centre.y)

        path.move(to: left)
        path.addLine(to: right)

        switch direction {
        case .backward:
            arrowhead(at: left, pointingLeft: true)
        case .forward:
            arrowhead(at: right, pointingLeft: false)
        case .pingPong:
            arrowhead(at: left, pointingLeft: true)
            arrowhead(at: right, pointingLeft: false)
        }

        return path
    }
}

/// One segment of the direction control: a full-size button showing the arrow,
/// filled when selected. Selection is carried by fill *and* the accessibility
/// selected trait, never by colour alone.
struct DirectionButton: View {
    let direction: DirectionIcon.Direction
    let label: String
    let isSelected: Bool
    let theme: MelGenTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DirectionIcon(direction: direction)
                .stroke(
                    isSelected ? theme.accentText : theme.text,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 30, height: 20)
                .frame(maxWidth: .infinity)
                .frame(height: MelGenMetrics.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .fill(isSelected ? theme.accent : theme.raised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .strokeBorder(isSelected ? theme.accent : theme.borderStrong, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
