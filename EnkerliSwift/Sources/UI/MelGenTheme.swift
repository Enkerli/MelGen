//
//  MelGenTheme.swift
//  MelGenExtension
//
//  MelGen's slice of the suite's "paper & ink" design system, ported from
//  music-suite/packages/ui/tokens/tokens.css. Warm cream paper and warm ink in
//  light, a warm-dark counterpart in dark, with contrast ratios already audited
//  to WCAG 2.1 AA on both themes (Scripts/verify.sh contrast re-checks them).
//
//  A plug-in UI has to paint its own surface. Left transparent, the host's
//  backdrop shows through and text contrast becomes whatever AUM happens to be
//  using that day — which is exactly how this view ended up unreadable in dark
//  mode. Every screen here sits on `theme.background` or `theme.raised`.
//

import SwiftUI

public struct MelGenTheme: Equatable {
    /// Paper: the window surface.
    public let background: Color
    /// Panel: a raised group sitting on the paper.
    public let raised: Color
    /// Field or well: a sunken input area.
    public let sunken: Color

    /// Ink: primary text.
    public let text: Color
    /// Secondary text, still ≥4.5:1 on every surface.
    public let textSecondary: Color
    /// Muted text — labels and captions. Audited ≥4.5:1 on all three surfaces.
    public let textMuted: Color
    /// Disabled ink only. WCAG-exempt, never for live text.
    public let textDisabled: Color

    /// Decorative separation only.
    public let border: Color
    /// ≥3:1 — boundaries that identify a control.
    public let borderStrong: Color

    public let accent: Color
    public let accentText: Color
    /// For the one thing the interface needs to mark as "look at this" without
    /// saying it's wrong: a note landing on a tone the chord says not to land
    /// on. Distinct from the accent in hue rather than only in lightness, since
    /// the piano roll uses both as fills and a colour-blind reader needs the
    /// difference to survive.
    public let warning: Color

    public static let light = MelGenTheme(
        background: Color(hex: 0xf5f2eb),
        raised: Color(hex: 0xfcfbf7),
        sunken: Color(hex: 0xefebe2),
        text: Color(hex: 0x2d2b27),
        textSecondary: Color(hex: 0x4b463e),
        textMuted: Color(hex: 0x6b665b),
        textDisabled: Color(hex: 0xb3ac9e),
        border: Color(hex: 0xddd6ca),
        borderStrong: Color(hex: 0x9d8967),
        accent: Color(hex: 0x2f66a5),
        accentText: Color(hex: 0xffffff),
        warning: Color(hex: 0xa8541f)
    )

    public static let dark = MelGenTheme(
        background: Color(hex: 0x1a1814),
        raised: Color(hex: 0x221f1a),
        sunken: Color(hex: 0x14130f),
        text: Color(hex: 0xe8e1d2),
        textSecondary: Color(hex: 0xcfc7b5),
        textMuted: Color(hex: 0x908672),
        textDisabled: Color(hex: 0x5f584a),
        border: Color(hex: 0x38332b),
        borderStrong: Color(hex: 0x736958),
        accent: Color(hex: 0x6da3df),
        accentText: Color(hex: 0x14130f),
        warning: Color(hex: 0xdb8f52)
    )

    public static func resolved(for scheme: ColorScheme) -> MelGenTheme {
        scheme == .dark ? .dark : .light
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(background: Color,
                raised: Color,
                sunken: Color,
                text: Color,
                textSecondary: Color,
                textMuted: Color,
                textDisabled: Color,
                border: Color,
                borderStrong: Color,
                accent: Color,
                accentText: Color,
                warning: Color) {
        self.background = background
        self.raised = raised
        self.sunken = sunken
        self.text = text
        self.textSecondary = textSecondary
        self.textMuted = textMuted
        self.textDisabled = textDisabled
        self.border = border
        self.borderStrong = borderStrong
        self.accent = accent
        self.accentText = accentText
        self.warning = warning
    }
}

/// Sizing, from the same token set. Controls are touch-sized: a plug-in window
/// on an iPad is a touch target, never a pointer one.
public enum MelGenMetrics {
    /// Minimum touch target per WCAG 2.5.5 / the suite's coarse-pointer token.
    ///
    /// Every *interactive* thing uses this. `smallControlHeight` is for rows
    /// that aren't targets — a disclosure label's own height, a spacer — and
    /// reaching for it on a control is how chips ended up at 34pt in a design
    /// whose own token said 44.
    public static let controlHeight: CGFloat = 44
    public static let smallControlHeight: CGFloat = 34

    public static let radiusSmall: CGFloat = 10
    public static let radiusMedium: CGFloat = 14

    /// Width reserved for a slider's low/high captions, so tracks line up in a
    /// column. Fits the longest caption in use ("surprising") at 11pt.
    public static let sliderCaptionWidth: CGFloat = 66

    public static let gap: CGFloat = 12
    public static let space1: CGFloat = 4
    public static let space2: CGFloat = 8
    public static let space3: CGFloat = 12
    public static let space4: CGFloat = 16
}

extension Color {
    public init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

// MARK: - Shared building blocks

/// A small-caps section label. The suite calls these "eyebrows"; they replace
/// the disclosure-triangle-only grouping this view used to rely on.
public struct Eyebrow: View {
    public let text: String
    public let theme: MelGenTheme

    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(theme.textMuted)
            .accessibilityAddTraits(.isHeader)
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(text: String,
                theme: MelGenTheme) {
        self.text = text
        self.theme = theme
    }
}

/// A labelled slider with a mono, tabular read-out.
///
/// The end labels flank the track rather than sitting under it: below the
/// slider they read as belonging to whatever control comes next, since they end
/// up directly above the next row's name and value.
public struct LabelledSlider: View {
    public let title: String
    public let lowLabel: String
    public let highLabel: String
    @Binding public var value: Double
    public let theme: MelGenTheme
    /// Formats the value for display; defaults to two decimals.
    public var format: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(2))) }
    /// Called when a drag ends, not while it moves.
    ///
    /// The distinction is the whole reason this exists: a control that redraws
    /// on every frame of a gesture makes a hundred of whatever it makes, and one
    /// that redraws on release makes one you can hear against the last one. See
    /// `MelGenExtensionMainView.redrawBass()`.
    public var onCommit: () -> Void = {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: MelGenMetrics.space2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text)
                Spacer(minLength: 0)
                Text(format(value))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
            }

            HStack(spacing: MelGenMetrics.space2) {
                // Fixed caption widths, so every slider's track starts and ends at
                // the same x. Sized to the label rather than the text, the tracks
                // end up different lengths and equal values sit at visibly
                // different positions down the column.
                Text(lowLabel)
                    .frame(width: MelGenMetrics.sliderCaptionWidth, alignment: .trailing)

                Slider(value: $value, in: 0...1, onEditingChanged: { editing in
                    if !editing { onCommit() }
                })
                    .tint(theme.accent)

                Text(highLabel)
                    .frame(width: MelGenMetrics.sliderCaptionWidth, alignment: .leading)
            }
            .font(.system(size: 11))
            .foregroundStyle(theme.textMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(height: MelGenMetrics.controlHeight)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(format(value))
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(title: String,
                lowLabel: String,
                highLabel: String,
                value: Binding<Double>,
                theme: MelGenTheme,
                format: @escaping (Double) -> String = { $0.formatted(.number.precision(.fractionLength(2))) },
                onCommit: @escaping () -> Void = {}) {
        self.title = title
        self.lowLabel = lowLabel
        self.highLabel = highLabel
        self._value = value
        self.theme = theme
        self.format = format
        self.onCommit = onCommit
    }
}

/// A group that can be folded away, with the suite's eyebrow as its header.
/// The header is a full-height target and carries the expanded state for
/// assistive technology.
public struct CollapsibleSection<Content: View>: View {
    public let title: String
    /// Shown next to the title when collapsed, e.g. "7/bar · legato".
    public var summary: String?
    @Binding public var isExpanded: Bool
    public let theme: MelGenTheme
    @ViewBuilder public let content: () -> Content

    public var body: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.textMuted)
                    Eyebrow(text: title, theme: theme)
                    if let summary, !isExpanded {
                        Text(summary)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.textMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: MelGenMetrics.smallControlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapses this group" : "Expands this group")

            if isExpanded {
                content()
            }
        }
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(title: String,
                summary: String? = nil,
                isExpanded: Binding<Bool>,
                theme: MelGenTheme,
                @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.summary = summary
        self._isExpanded = isExpanded
        self.theme = theme
        self.content = content
    }
}

/// A row of mutually exclusive chips — for settings whose values really are
/// discrete, where a slider would imply a continuum that isn't there.
public struct ChipPicker<Value: Hashable>: View {
    public let options: [(value: Value, label: String)]
    @Binding public var selection: Value
    public let theme: MelGenTheme

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let isSelected = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, MelGenMetrics.space2)
                        .frame(maxWidth: .infinity)
                        // The theme's own touch-target token, not a smaller one.
                        // Segmented rows were at 34pt, which is under WCAG
                        // 2.5.5's floor and under the size the rest of this
                        // interface already meets.
                        .frame(height: MelGenMetrics.controlHeight)
                        .foregroundStyle(isSelected ? theme.accentText : theme.text)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? theme.accent : theme.raised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(isSelected ? theme.accent : theme.borderStrong, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(options: [(value: Value, label: String)],
                selection: Binding<Value>,
                theme: MelGenTheme) {
        self.options = options
        self._selection = selection
        self.theme = theme
    }
}

/// A toggle drawn as a full-size labelled button: icon *and* text, filled when
/// on, outlined when off, so state never depends on colour alone.
public struct ToggleChip: View {
    public let title: String
    public let systemImage: String
    @Binding public var isOn: Bool
    public let theme: MelGenTheme

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, MelGenMetrics.space3)
            .frame(height: MelGenMetrics.controlHeight)
            .foregroundStyle(isOn ? theme.accentText : theme.text)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(isOn ? theme.accent : theme.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .strokeBorder(isOn ? theme.accent : theme.borderStrong, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(title: String,
                systemImage: String,
                isOn: Binding<Bool>,
                theme: MelGenTheme) {
        self.title = title
        self.systemImage = systemImage
        self._isOn = isOn
        self.theme = theme
    }
}

/// A wrapping row of chips, for a multi-select over a set too long for one line.
///
/// Written as a `Layout` rather than a horizontal scroller because the whole
/// point of the control is seeing the *set* — what's in the rotation and what
/// isn't — and half of it hidden off the right edge doesn't show that.
public struct FlowChips: View {
    public let items: [String]
    public let isSelected: (String) -> Bool
    public var isPinned: (String) -> Bool = { _ in false }
    public let theme: MelGenTheme
    public let onTap: (String) -> Void

    public var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let selected = isSelected(item)
                let pinned = isPinned(item)
                Button {
                    onTap(item)
                } label: {
                    HStack(spacing: 3) {
                        if pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        Text(item)
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    }
                    .lineLimit(1)
                    .padding(.horizontal, MelGenMetrics.space2)
                    .frame(height: MelGenMetrics.controlHeight)
                    .foregroundStyle(selected ? theme.accentText : theme.textSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? theme.accent : theme.raised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(pinned ? theme.text : (selected ? theme.accent : theme.border),
                                          lineWidth: pinned ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(items: [String],
                isSelected: @escaping (String) -> Bool,
                isPinned: @escaping (String) -> Bool = { _ in false },
                theme: MelGenTheme,
                onTap: @escaping (String) -> Void) {
        self.items = items
        self.isSelected = isSelected
        self.isPinned = isPinned
        self.theme = theme
        self.onTap = onTap
    }
}

/// Left-to-right, wrapping when the row runs out. The smallest thing that does
/// the job; no alignment guides, no priorities.
public struct FlowLayout: Layout {
    public var spacing: CGFloat = 4

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, in: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, max(widest, 0)), height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, in: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, next > width {
                rows.append(row)
                row = Row()
                row.indices = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.indices.append(index)
                row.width = next
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(spacing: CGFloat = 4) {
        self.spacing = spacing
    }
}
