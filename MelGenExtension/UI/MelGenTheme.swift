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

struct MelGenTheme: Equatable {
    /// Paper: the window surface.
    let background: Color
    /// Panel: a raised group sitting on the paper.
    let raised: Color
    /// Field or well: a sunken input area.
    let sunken: Color

    /// Ink: primary text.
    let text: Color
    /// Secondary text, still ≥4.5:1 on every surface.
    let textSecondary: Color
    /// Muted text — labels and captions. Audited ≥4.5:1 on all three surfaces.
    let textMuted: Color
    /// Disabled ink only. WCAG-exempt, never for live text.
    let textDisabled: Color

    /// Decorative separation only.
    let border: Color
    /// ≥3:1 — boundaries that identify a control.
    let borderStrong: Color

    let accent: Color
    let accentText: Color

    static let light = MelGenTheme(
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
        accentText: Color(hex: 0xffffff)
    )

    static let dark = MelGenTheme(
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
        accentText: Color(hex: 0x14130f)
    )

    static func resolved(for scheme: ColorScheme) -> MelGenTheme {
        scheme == .dark ? .dark : .light
    }
}

/// Sizing, from the same token set. Controls are touch-sized: a plug-in window
/// on an iPad is a touch target, never a pointer one.
enum MelGenMetrics {
    /// Minimum touch target per WCAG 2.5.5 / the suite's coarse-pointer token.
    static let controlHeight: CGFloat = 44
    static let smallControlHeight: CGFloat = 34

    static let radiusSmall: CGFloat = 10
    static let radiusMedium: CGFloat = 14

    static let gap: CGFloat = 12
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
}

extension Color {
    init(hex: UInt32) {
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
struct Eyebrow: View {
    let text: String
    let theme: MelGenTheme

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(theme.textMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A labelled slider with a mono, tabular read-out.
///
/// The end labels flank the track rather than sitting under it: below the
/// slider they read as belonging to whatever control comes next, since they end
/// up directly above the next row's name and value.
struct LabelledSlider: View {
    let title: String
    let lowLabel: String
    let highLabel: String
    @Binding var value: Double
    let theme: MelGenTheme
    /// Formats the value for display; defaults to two decimals.
    var format: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(2))) }

    var body: some View {
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
                Text(lowLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize()

                Slider(value: $value, in: 0...1)
                    .tint(theme.accent)

                Text(highLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize()
            }
            .frame(height: MelGenMetrics.controlHeight)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(format(value))
    }
}

/// A group that can be folded away, with the suite's eyebrow as its header.
/// The header is a full-height target and carries the expanded state for
/// assistive technology.
struct CollapsibleSection<Content: View>: View {
    let title: String
    /// Shown next to the title when collapsed, e.g. "7/bar · legato".
    var summary: String?
    @Binding var isExpanded: Bool
    let theme: MelGenTheme
    @ViewBuilder let content: () -> Content

    var body: some View {
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
}

/// A row of mutually exclusive chips — for settings whose values really are
/// discrete, where a slider would imply a continuum that isn't there.
struct ChipPicker<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    let theme: MelGenTheme

    var body: some View {
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
                        .frame(height: MelGenMetrics.smallControlHeight)
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
}

/// A toggle drawn as a full-size labelled button: icon *and* text, filled when
/// on, outlined when off, so state never depends on colour alone.
struct ToggleChip: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    let theme: MelGenTheme

    var body: some View {
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
}
