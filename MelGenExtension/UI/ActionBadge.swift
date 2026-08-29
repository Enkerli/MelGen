//
//  ActionBadge.swift
//  MelGenExtension
//
//  Three words, on group headers, saying what pressing anything inside will do.
//
//  One badge per group and two on the verbs — five on screen at rest. A badge
//  per control was the obvious first draft and is noise: it makes the rule look
//  like decoration, and a rule that looks decorative is one nobody reads. The
//  exception is the single case where two tenses genuinely sit side by side,
//  where the badge is the entire reason the split exists.
//
//  No new tokens. The three pairings are ones the audit already covers —
//  `accentText` on `accent`, `text` on `raised` inside a `borderStrong` edge,
//  `textMuted` on `sunken` — and if one of them ever fails
//  `Scripts/verify.sh contrast`, the badge changes rather than the theme.
//

import SwiftUI

/// What happens when you press anything in this group.
struct ActionBadge: View {
    let tense: ActionTense
    let theme: MelGenTheme

    var body: some View {
        Text(tense.label.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5).fill(background))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(border, lineWidth: tense == .take ? 1.5 : 0))
            // One element, not three: assistive technology gets the word and
            // the sentence, and never the punctuation of a pill.
            .accessibilityElement()
            .accessibilityLabel(tense.label)
            .accessibilityValue(tense.explanation)
    }

    private var foreground: Color {
        switch tense {
        case .now: return theme.accentText
        case .take: return theme.text
        case .aims: return theme.textMuted
        }
    }

    private var background: Color {
        switch tense {
        case .now: return theme.accent
        case .take: return theme.raised
        case .aims: return theme.sunken
        }
    }

    private var border: Color {
        tense == .take ? theme.borderStrong : .clear
    }
}

/// A group header that says its tense before it says its name.
///
/// The order matters and is the whole point: the badge is read first, so the
/// controls underneath are already classified by the time the heading is.
struct TenseHeader<Trailing: View>: View {
    let tense: ActionTense
    let title: String
    let theme: MelGenTheme
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: MelGenMetrics.space2) {
            ActionBadge(tense: tense, theme: theme)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            trailing()
        }
        .frame(minHeight: MelGenMetrics.smallControlHeight)
    }
}

extension TenseHeader where Trailing == EmptyView {
    init(tense: ActionTense, title: String, theme: MelGenTheme) {
        self.init(tense: tense, title: title, theme: theme) { EmptyView() }
    }
}
