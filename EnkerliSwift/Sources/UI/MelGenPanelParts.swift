//
//  MelGenPanelParts.swift
//  MelGenExtension
//
//  The pieces the redesign added: the two-loop tab bar, the source list, and the
//  disclosure rows that replaced four full-width sections.
//
//  These are separate from the main view because the main view is already long,
//  and because each of them exists to enforce one of the redesign's four rules —
//  which is easier to keep true when the rule and the code are the same file.
//
//  1. Two loops, two tabs. Playing and judging were interleaved down one column
//     of sixteen sections; they are two different activities and the only thing
//     that crosses between them is the strip under the roll.
//  2. Cost is the axis. Every source says whose vocabulary it is and whether it
//     answers now or in about 1.8 seconds a note.
//  3. Filled means it happens now. An action is filled accent; a setting is a
//     quiet outline or a segmented row. No control is both.
//  4. Mode changes the sources, not one button.
//

import SwiftUI
import Carrier

/// Which loop the panel is showing.
public enum PanelTab: String, CaseIterable, Sendable {
    case play, decide

    public var label: String { self == .play ? "Play" : "Decide" }
}

/// The one line that says what to do now.
///
/// Drawn as a quiet row rather than as a banner: it is advice, and advice that
/// looks like an alert gets dismissed rather than read. It shows the action, the
/// fact that makes it the action, and where it lives — because "Setups" means
/// nothing until you are told it is at the top of Decide.
///
/// Takes the two strings rather than the `NextStep` that produced them, because
/// the row draws advice and advice is text. That keeps the ladder of rungs out
/// of the UI kit, which has no business knowing one exists.
public struct NextStepRow: View {
    public let title: String
    public let reason: String
    public let placeName: String
    public let theme: MelGenTheme
    public let action: () -> Void

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: MelGenMetrics.space2) {
                Image(systemName: "arrow.forward.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(placeName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MelGenMetrics.space3)
            .frame(minHeight: MelGenMetrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(theme.raised))
            .overlay(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .strokeBorder(theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue("\(reason) In \(placeName).")
        .accessibilityHint("Opens it")
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(title: String,
                reason: String,
                placeName: String,
                theme: MelGenTheme,
                action: @escaping () -> Void) {
        self.title = title
        self.reason = reason
        self.placeName = placeName
        self.theme = theme
        self.action = action
    }
}

/// The two-loop tab bar.
///
/// A real tablist rather than two buttons that happen to look like one: it
/// announces which is selected, and the count on Decide is a queue length rather
/// than a badge for its own sake.
public struct PanelTabBar: View {
    @Binding public var tab: PanelTab
    public let waiting: Int
    public let theme: MelGenTheme

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(PanelTab.allCases, id: \.self) { candidate in
                let isSelected = tab == candidate
                Button {
                    tab = candidate
                } label: {
                    HStack(spacing: 6) {
                        Text(candidate.label)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                        if candidate == .decide, waiting > 0 {
                            Text("\(waiting)")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(isSelected
                                                   ? theme.accentText.opacity(0.25)
                                                   : theme.sunken)
                                )
                        }
                    }
                    .padding(.horizontal, MelGenMetrics.space3)
                    .frame(height: MelGenMetrics.controlHeight)
                    .foregroundStyle(isSelected ? theme.accentText : theme.text)
                    .background(
                        RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .fill(isSelected ? theme.accent : theme.raised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .strokeBorder(isSelected ? theme.accent : theme.border, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate == .decide && waiting > 0
                                    ? "\(candidate.label), \(waiting) takes waiting"
                                    : candidate.label)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(tab: Binding<PanelTab>,
                waiting: Int,
                theme: MelGenTheme) {
        self._tab = tab
        self.waiting = waiting
        self.theme = theme
    }
}

/// One row of the source list.
///
/// Three columns because there are three things to know and they are not the
/// same kind of thing: what it is, whose vocabulary, and what it costs. The cost
/// is right-aligned and monospaced so the column reads as a column — "instant"
/// against "~1.8s a note" is the comparison being offered.
public struct SourceRow: View {
    public let source: MaterialSource
    public let isSelected: Bool
    public let isAvailable: Bool
    public let theme: MelGenTheme
    public let onSelect: () -> Void

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: MelGenMetrics.space2) {
                Image(systemName: source.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.accent : theme.textMuted)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(source.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isAvailable ? theme.text : theme.textDisabled)
                    Text(source.provenance)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                }

                Spacer(minLength: MelGenMetrics.space2)

                Text(source.cost)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(source.isInstant ? theme.textMuted : theme.warning)
            }
            .padding(.horizontal, MelGenMetrics.space2)
            .frame(minHeight: MelGenMetrics.controlHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(isSelected ? theme.sunken : theme.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .strokeBorder(isSelected ? theme.accent : theme.border,
                                  lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel(source.name)
        .accessibilityValue("\(source.provenance), \(source.cost)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(source: MaterialSource,
                isSelected: Bool,
                isAvailable: Bool,
                theme: MelGenTheme,
                onSelect: @escaping () -> Void) {
        self.source = source
        self.isSelected = isSelected
        self.isAvailable = isAvailable
        self.theme = theme
        self.onSelect = onSelect
    }
}

/// The one filled action. Rule three: filled means it happens now.
public struct PrimaryAction: View {
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let isWorking: Bool
    public let isEnabled: Bool
    public let theme: MelGenTheme
    public let action: () -> Void

    public var body: some View {
        Button(action: action) {
            HStack(spacing: MelGenMetrics.space2) {
                if isWorking {
                    ProgressView().controlSize(.small).tint(theme.accentText)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(isWorking ? "Working" : title)
                        .font(.system(size: 15, weight: .semibold))
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            // A fixed tint rather than opacity: opacity on the
                            // accent measured 4.0:1 and this has to stay above
                            // 4.5:1 like everything else.
                            .foregroundStyle(theme.accentText)
                            .opacity(0.86)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MelGenMetrics.space3)
            .frame(minHeight: MelGenMetrics.controlHeight + 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isEnabled ? theme.accentText : theme.textDisabled)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(isEnabled ? theme.accent : theme.sunken)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isWorking)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(title: String,
                subtitle: String,
                systemImage: String,
                isWorking: Bool,
                isEnabled: Bool,
                theme: MelGenTheme,
                action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isWorking = isWorking
        self.isEnabled = isEnabled
        self.theme = theme
        self.action = action
    }
}

/// A one-line disclosure that used to be a full-width section heading.
///
/// Four of these replaced four sections that were competing with the transport
/// for attention while being touched about once a session.
public struct MoreRow: View {
    public let summary: String
    @Binding public var isExpanded: Bool
    public let theme: MelGenTheme

    public var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                Text(summary)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, MelGenMetrics.space2)
            .frame(minHeight: MelGenMetrics.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(summary: String,
                isExpanded: Binding<Bool>,
                theme: MelGenTheme) {
        self.summary = summary
        self._isExpanded = isExpanded
        self.theme = theme
    }
}

/// A group of controls under a label saying *when* they take effect.
///
/// Shape and Feel were two sections whose only real difference was that one
/// waits for the next take and the other re-renders what is playing. That is a
/// sentence, not a section boundary.
public struct WhenGroup<Content: View>: View {
    public let legend: String
    public let theme: MelGenTheme
    @ViewBuilder public let content: () -> Content

    public var body: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            Text(legend.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(theme.textMuted)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MelGenMetrics.space2)
        .background(
            RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                .fill(theme.sunken.opacity(0.6))
        )
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(legend: String,
                theme: MelGenTheme,
                @ViewBuilder content: @escaping () -> Content) {
        self.legend = legend
        self.theme = theme
        self.content = content
    }
}
