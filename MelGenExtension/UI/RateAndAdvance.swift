//
//  RateAndAdvance.swift
//  MelGenExtension
//
//  The sweep surface: three coarse answers and an advance the listener aims.
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

/// One of the two aims, with the subtitle that makes it a promise.
struct AdvanceControl: View {
    let mode: AdvanceMode
    let subtitle: String?
    let isAimed: Bool
    let theme: MelGenTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                // If the subtitle can't be computed the button is disabled, so
                // this only ever shows something true.
                Text(subtitle ?? "nothing to aim at")
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MelGenMetrics.space3)
            .frame(height: MelGenMetrics.controlHeight)
            .foregroundStyle(isAimed ? theme.accentText : theme.text)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(isAimed ? theme.accent : theme.raised))
            .overlay(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .strokeBorder(isAimed ? theme.accent : theme.borderStrong, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        #if os(macOS) || targetEnvironment(macCatalyst)
        // Down for the near one, right for the far one. Space is deliberately
        // unbound — hosts own it for transport.
        .keyboardShortcut(mode == .anotherLikeThis ? .downArrow : .rightArrow, modifiers: [])
        #endif
        .disabled(subtitle == nil)
        .opacity(subtitle == nil ? 0.5 : 1)
        .accessibilityLabel(mode.label)
        .accessibilityValue(subtitle ?? "not available yet")
        .accessibilityHint("Makes the next take and aims the swipe this way")
        .accessibilityAddTraits(isAimed ? [.isButton, .isSelected] : .isButton)
    }
}

/// The whole sweep surface: rate, aim, advance, and the sentence that says what
/// a swipe will do.
struct RateAndAdvanceStrip: View {
    let current: TakeDisposition?
    let aim: AdvanceMode
    let theme: MelGenTheme
    /// Nil disables that branch — see `TakeAdvance.subtitle`.
    let subtitle: (AdvanceMode) -> String?
    let onRate: (TakeRating) -> Void
    let onAdvance: (AdvanceMode) -> Void
    let onMore: () -> Void
    /// Present only when there is something to go back to.
    let onBack: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            RatingBar(current: current, theme: theme, onRate: onRate, onMore: onMore)

            HStack(spacing: MelGenMetrics.space1) {
                ForEach(AdvanceMode.allCases, id: \.self) { mode in
                    AdvanceControl(mode: mode,
                                   subtitle: subtitle(mode),
                                   isAimed: aim == mode,
                                   theme: theme) { onAdvance(mode) }
                }
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
