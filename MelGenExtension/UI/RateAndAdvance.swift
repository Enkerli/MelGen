//
//  RateAndAdvance.swift
//  MelGenExtension
//
//  The verb bar: the three things done per minute, in a strip that never scrolls.
//
//  Kept in its own file for the same reason `MelGenPanelParts.swift` is: these
//  views exist to keep one rule true — *the coarse layer never reaches storage*
//  — and a rule is easier to keep when the code that implements it is somewhere
//  you can read in one sitting. Nothing here writes a mark itself; everything
//  goes through `MelGenState.rate` and lands as one of the seven.
//
//  Two decisions worth stating because they look like mistakes:
//
//  *Yes is wider than No and Maybe.* It is not the good one and they are not the
//  bad ones — weight and colour stay equal across all three. Only width differs,
//  because Yes is the answer whose consequence is durable, and target size is
//  how an interface says which tap you cannot afford to fat-finger. Wider by a
//  *minimum width*, though: the whole argument is about targets, so the two that
//  are not Yes still have to clear 44pt at every window size.
//
//  *The advance buttons are filled by which one the swipe will use*, not by
//  which is better. Tapping either both advances and makes it the swipe's mode,
//  so the words under the strip are always true.
//
//  *The aim is a switch, not a third button.* There were two aims and two
//  buttons; there are three aims now and no room for three in a pinned bar. So
//  `Next take` is one verb whose subtitle says which aim is loaded and what it
//  will produce, and `AimSwitch` beside it cycles the three. Two shipped buttons
//  becoming one verb with an aim is what makes room for the third — and the
//  subtitle is what stops a switch being a mystery, because the button always
//  reads as a sentence about what is about to happen.
//

import SwiftUI

/// Three coarse answers, equal in weight and colour.
struct RatingBar: View {
    let current: TakeDisposition?
    let theme: MelGenTheme
    let onRate: (TakeRating) -> Void
    /// The four that aren't ratings, behind a disclosure.
    let onMore: () -> Void

    /// Which rating reads as set. A mark from one of the other four shows as
    /// none of these rather than being bucketed into the nearest one.
    private var selected: TakeRating? { current.flatMap(TakeRating.of) }

    var body: some View {
        HStack(spacing: MelGenMetrics.space1) {
            ForEach(TakeRating.allCases, id: \.self) { rating in
                let isSelected = selected == rating
                Button { onRate(rating) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: rating.symbolName)
                            .font(.system(size: 15, weight: .semibold))
                        Text(rating.label)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    // Yes is wider by a floor, not by a priority. Giving it a
                    // higher layout priority against three `maxWidth: .infinity`
                    // siblings hands it *all* the slack, which collapsed No and
                    // Maybe to icon slivers well under the 44pt target — the
                    // opposite of what a target-size argument was for.
                    .frame(minWidth: rating == .yes ? 132 : 64, maxWidth: .infinity)
                    .frame(height: MelGenMetrics.controlHeight)
                    .foregroundStyle(isSelected ? theme.accentText : theme.text)
                    .background(
                        RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .fill(isSelected ? theme.accent : theme.raised))
                    .overlay(
                        RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .strokeBorder(isSelected ? theme.accent : theme.borderStrong,
                                          lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                #if os(macOS) || targetEnvironment(macCatalyst)
                .keyboardShortcut(KeyEquivalent(rating.shortcut), modifiers: [])
                #endif
                .accessibilityLabel(rating.label)
                .accessibilityValue("\(rating.label), \(rating.consequence)")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }

            Button(action: onMore) {
                VStack(spacing: 2) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                    Text("more")
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .frame(width: 52)
                .frame(height: MelGenMetrics.controlHeight)
                .foregroundStyle(theme.textMuted)
                .background(
                    RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .fill(theme.raised))
                .overlay(
                    RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .strokeBorder(theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More ways to answer")
            .accessibilityHint("Shows tweak, again, elsewhere and partly — these record without advancing")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rate this take")
    }
}

/// A verb: what it is called, what it costs, and what it will produce.
///
/// One shape for both, because they are the same kind of thing and looked like
/// different kinds — `Roll again` filled because `now` actions are filled,
/// `Next take` outlined because it costs something and arrives later. The badge
/// under each is the grammar's own word, so the button teaches the rule every
/// time it is read.
struct VerbButton: View {
    let verb: Verb
    /// The aim, for `nextTake`. Nil on a verb that has none.
    let aim: AdvanceMode?
    /// What it will produce. Nil disables the button — see `TakeAdvance.subtitle`.
    let subtitle: String?
    /// Why it can't be pressed, when it can't. Beats a greyed control with no
    /// reason, which is a control that reads as broken.
    let unavailable: String?
    let theme: MelGenTheme
    let action: () -> Void

    private var isEnabled: Bool { unavailable == nil && subtitle != nil }
    private var isFilled: Bool { verb.tense.isFilled }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: verb.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                    Text(verb.label)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let aim {
                        Text("· \(aim.label.lowercased())")
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .opacity(0.8)
                    }
                }
                // The tense, then what will happen. If neither can be said the
                // button is disabled, so this only ever shows something true.
                Text(caption)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .opacity(0.88)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MelGenMetrics.space3)
            .frame(minHeight: 56)
            .foregroundStyle(isFilled ? theme.accentText : theme.text)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(isFilled ? theme.accent : theme.raised))
            .overlay(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .strokeBorder(isFilled ? theme.accent : theme.borderStrong, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        #if os(macOS) || targetEnvironment(macCatalyst)
        // Down makes a take, left re-rolls. Space is deliberately unbound —
        // hosts own it for transport.
        .keyboardShortcut(verb == .nextTake ? .downArrow : .leftArrow, modifiers: [])
        #endif
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(aim == nil ? verb.label : "\(verb.label), \(aim!.label)")
        .accessibilityValue(unavailable ?? subtitle ?? "not available yet")
        .accessibilityHint(verb.explanation)
    }

    /// The line under the name: the tense, the cost, and what it will produce —
    /// or the reason it can't be pressed, which displaces all three.
    private var caption: String {
        if let unavailable { return unavailable.uppercased() }
        var parts = [verb.tense.label.uppercased()]
        if let subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        return parts.joined(separator: " · ")
    }
}

/// The three aims, as one 44pt control that cycles them.
///
/// A switch rather than three buttons because a pinned bar has room for one
/// verb and one modifier, and because the aims are ordered — narrowest to
/// widest — so cycling is the gesture the order already implies.
struct AimSwitch: View {
    @Binding var aim: AdvanceMode
    let theme: MelGenTheme
    /// Fired after the aim changes, so the verb's subtitle can be recomputed.
    var onChange: () -> Void = {}

    var body: some View {
        Button {
            let all = AdvanceMode.allCases
            let next = all[(all.firstIndex(of: aim).map { $0 + 1 } ?? 0) % all.count]
            aim = next
            onChange()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: aim.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                Text("aim")
                    .font(.system(size: 9))
            }
            .frame(width: MelGenMetrics.controlHeight)
            .frame(minHeight: 56)
            .foregroundStyle(theme.textMuted)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall).fill(theme.raised))
            .overlay(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .strokeBorder(theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aim")
        .accessibilityValue(aim.label)
        .accessibilityHint("Cycles what the next take will be: same changed, another like this, something else")
    }
}

/// Rate, roll, advance — the three things done per minute, in a bar that never
/// scrolls.
///
/// It is a `safeAreaInset` rather than the last thing in the stack, because the
/// whole argument for it is that a half-height window in AUM should never put a
/// verb behind a scroll. What it costs is about 110pt of piano roll, and the
/// roll is what pays.
struct VerbBar: View {
    let current: TakeDisposition?
    @Binding var aim: AdvanceMode
    let theme: MelGenTheme
    /// Nil disables the verb — see `TakeAdvance.subtitle`.
    let subtitle: (AdvanceMode) -> String?
    /// Why `Roll again` can't be pressed, or nil when it can.
    let rollUnavailable: String?
    let onRate: (TakeRating) -> Void
    let onRoll: () -> Void
    let onAdvance: (AdvanceMode) -> Void
    let onMore: () -> Void
    /// Present only when there is something to go back to.
    let onBack: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            RatingBar(current: current, theme: theme, onRate: onRate, onMore: onMore)

            HStack(spacing: MelGenMetrics.space2) {
                VerbButton(verb: .rollAgain,
                           aim: nil,
                           subtitle: "free",
                           unavailable: rollUnavailable,
                           theme: theme,
                           action: onRoll)
                    .frame(maxWidth: 132)

                VerbButton(verb: .nextTake,
                           aim: aim,
                           subtitle: subtitle(aim),
                           unavailable: nil,
                           theme: theme) { onAdvance(aim) }

                AimSwitch(aim: $aim, theme: theme)
            }

            HStack(spacing: MelGenMetrics.space2) {
                Text("Swipe the roll to rate and advance · then: \(aim.label.lowercased())")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let onBack {
                    Button("Back", action: onBack)
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accent)
                        .accessibilityHint("Reselects the take you just rated")
                }
            }
        }
    }
}

/// The swipe, as a gesture the piano roll can wear.
///
/// Right is Yes, left is No, up is Maybe — and every one of them advances using
/// the current aim, which is why the aim is spelled out in words underneath.
/// Rating the same take again on the same pass replaces, so a mistaken swipe is
/// already undoable; what it isn't is *reversible*, because the take has moved
/// on. That is what Back is for.
struct RateSwipe: ViewModifier {
    let onSwipe: (TakeRating) -> Void
    /// Long press reaches the seven.
    let onMore: () -> Void

    private static let threshold: CGFloat = 44

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: Self.threshold)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        if abs(dx) > abs(dy) {
                            onSwipe(dx > 0 ? .yes : .no)
                        } else if dy < 0 {
                            onSwipe(.maybe)
                        }
                    }
            )
            .onLongPressGesture(minimumDuration: 0.5, perform: onMore)
    }
}

extension View {
    func rateOnSwipe(onSwipe: @escaping (TakeRating) -> Void,
                     onMore: @escaping () -> Void) -> some View {
        modifier(RateSwipe(onSwipe: onSwipe, onMore: onMore))
    }
}
