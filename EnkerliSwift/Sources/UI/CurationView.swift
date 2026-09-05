//
//  CurationView.swift
//  MelGenExtension
//
//  The curation surface: one tap (or one key) per take, and a sweep you can run
//  more than once.
//
//  Everything here follows from the model in MelodyCuration.swift — the marks
//  are dispositions rather than scores, so the control is a row of equals rather
//  than a scale; judgement is provisional, so the section is headed by which
//  pass you're on rather than by how many takes are "good"; and the two
//  vocabularies are drawn differently on purpose, facets as read-only chips you
//  can't edit and tags as a field you can type anything into.
//

import SwiftUI
import Carrier

/// The row of dispositions. Seven equals, not a scale.
///
/// Deliberately all one size and one weight: the moment one of them is drawn as
/// the good one, the row becomes a rating again.
///
/// Compact by default. Seven buttons is the honest model but a costly default —
/// it turns an ordinary keep/tweak/skip decision into a scan of seven labels,
/// and a sweep over a long history is exactly where that cost lands. So three
/// show, the rest are a tap away, and a disposition already set is always
/// visible even when it's one of the four that are folded away.
public struct DispositionBar: View {
    public let current: TakeDisposition?
    public let theme: MelGenTheme
    /// Tapping the disposition already set clears it — un-judging is normal.
    public let onSelect: (TakeDisposition?) -> Void
    /// Start expanded where there's room, such as a single take's own panel.
    public var startExpanded = false

    @State private var isExpanded = false

    /// What's on show: the three primaries, plus whatever is already set, plus
    /// everything once expanded.
    private var visible: [TakeDisposition] {
        if isExpanded || startExpanded { return TakeDisposition.allCases }
        return TakeDisposition.allCases.filter { $0.isPrimary || $0 == current }
    }

    private var showsDisclosure: Bool {
        !startExpanded && visible.count < TakeDisposition.allCases.count
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(visible, id: \.self) { disposition in
                let isSelected = current == disposition
                Button {
                    onSelect(isSelected ? nil : disposition)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: disposition.symbolName)
                            .font(.system(size: 14, weight: .semibold))
                        Text(disposition.chipLabel)
                            .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
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
                #if os(macOS) || targetEnvironment(macCatalyst)
                .keyboardShortcut(KeyEquivalent(disposition.shortcut), modifiers: [])
                #endif
                .accessibilityLabel(disposition.label)
                .accessibilityHint("Marks this take on pass in progress")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }

            if showsDisclosure {
                Button {
                    isExpanded = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                        Text("more")
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: MelGenMetrics.controlHeight)
                    .foregroundStyle(theme.textMuted)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.raised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More ways to answer")
                .accessibilityHint("Shows context, partly, later and again")
            }
        }
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(current: TakeDisposition?,
                theme: MelGenTheme,
                onSelect: @escaping (TakeDisposition?) -> Void,
                startExpanded: Bool = false) {
        self.current = current
        self.theme = theme
        self.onSelect = onSelect
        self.startExpanded = startExpanded
    }
}

/// Which parts of a take work, for the "cool rhythm, rest is so-so" case.
///
/// Multi-select, because more than one part can be the good part, and a small
/// fixed vocabulary rather than free text, because these are the aspects the
/// code can act on later.
public struct AspectPicker: View {
    public let selected: [TakeAspect]
    public let theme: MelGenTheme
    public let onToggle: (TakeAspect) -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Which part?")
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
            HStack(spacing: 4) {
                ForEach(TakeAspect.allCases, id: \.self) { aspect in
                    let isSelected = selected.contains(aspect)
                    Button {
                        onToggle(aspect)
                    } label: {
                        Text(aspect.label)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 6)
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
                    .accessibilityLabel(aspect.label)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(selected: [TakeAspect],
                theme: MelGenTheme,
                onToggle: @escaping (TakeAspect) -> Void) {
        self.selected = selected
        self.theme = theme
        self.onToggle = onToggle
    }
}

/// The derived half of the vocabulary. Read-only on purpose: these are measured,
/// not asserted, and a chip you can edit is a chip that can lie.
public struct FacetChips: View {
    public let facets: TakeFacets
    public let theme: MelGenTheme

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(facets.chips, id: \.self) { chip in
                Text(chip)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .foregroundStyle(theme.textSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(theme.sunken)
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(facets.chips.joined(separator: ", "))
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(facets: TakeFacets,
                theme: MelGenTheme) {
        self.facets = facets
        self.theme = theme
    }
}

/// The emergent half. A field you can type anything into, plus whatever you've
/// typed before — which is how a vocabulary you didn't plan shows up.
public struct TagField: View {
    public let tags: [String]
    public let suggestions: [String]
    public let theme: MelGenTheme
    public let onCommit: ([String]) -> Void

    @State private var draft: String = ""

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: MelGenMetrics.space2) {
                TextField("Tags", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, MelGenMetrics.space2)
                    .frame(height: MelGenMetrics.smallControlHeight)
                    .background(
                        RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .fill(theme.sunken)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )
                    .onSubmit { commitDraft() }
                    .accessibilityLabel("Tags, comma separated")
            }

            // Everything already in play, tap to add or remove. Ordered by how
            // often it's been used, so the vocabulary you actually have is the
            // one in front of you.
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(suggestions.prefix(12), id: \.self) { tag in
                            let isOn = tags.contains(tag)
                            Button {
                                onCommit(isOn ? tags.filter { $0 != tag } : tags + [tag])
                            } label: {
                                Text(tag)
                                    .font(.system(size: 10, weight: isOn ? .semibold : .regular))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .foregroundStyle(isOn ? theme.accentText : theme.textSecondary)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(isOn ? theme.accent : theme.raised)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .strokeBorder(isOn ? theme.accent : theme.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tag)
                            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }
            }
        }
        .onAppear { draft = tags.joined(separator: ", ") }
        .onChange(of: tags) { _, newTags in draft = newTags.joined(separator: ", ") }
    }

    private func commitDraft() {
        onCommit(draft.split(separator: ",").map(String.init))
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(tags: [String],
                suggestions: [String],
                theme: MelGenTheme,
                onCommit: @escaping ([String]) -> Void) {
        self.tags = tags
        self.suggestions = suggestions
        self.theme = theme
        self.onCommit = onCommit
    }
}

/// One row of the review queue: what it is, what was last said about it, and
/// when that was said.
///
/// It takes the four things it draws rather than the take they came off, which
/// is PORTING.md's `CurationView → GenerationRecord` seam: a row that only reads
/// a name, its facets, its tags and its latest mark does not need to know that a
/// take record exists, and a sibling plug-in reviewing something other than a
/// melody has all four without having MelGen's record. The call site does the
/// unwrapping the row used to do; nothing else changed.
public struct ReviewRow: View {
    public let name: String
    public let facets: TakeFacets
    public let tags: [String]
    public let latestMark: CurationMark?
    public let isCurrent: Bool
    public let currentPass: Int
    public let theme: MelGenTheme
    public let onLoad: () -> Void

    public var body: some View {
        Button(action: onLoad) {
            HStack(spacing: MelGenMetrics.space2) {
                Image(systemName: isCurrent ? "speaker.wave.2.fill" : "play.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCurrent ? theme.accent : theme.textMuted)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    FacetChips(facets: facets, theme: theme)
                    if !tags.isEmpty {
                        Text(tags.joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if let mark = latestMark {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: mark.disposition.symbolName)
                                .font(.system(size: 10, weight: .semibold))
                            Text(mark.disposition.chipLabel)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(mark.pass == currentPass ? theme.accent : theme.textMuted)
                        Text(mark.pass == currentPass ? "this pass" : "pass \(mark.pass)")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.textMuted)
                    }
                }
            }
            .padding(.horizontal, MelGenMetrics.space2)
            .padding(.vertical, MelGenMetrics.space1)
            .frame(minHeight: MelGenMetrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(isCurrent ? theme.sunken : theme.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .strokeBorder(isCurrent ? theme.accent : theme.border, lineWidth: isCurrent ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        // Says which pass. A screen-reader user hearing "keep, pass 2" has the
        // same problem the vocabulary exists to fix — there are two counters in
        // this app and only one of them is a judgement.
        .accessibilityValue(latestMark.map { "\($0.disposition.label), judged on pass \($0.pass)" }
                            ?? "Not yet judged")
        .accessibilityHint("Loads this take so you can hear it")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(name: String,
                facets: TakeFacets,
                tags: [String],
                latestMark: CurationMark?,
                isCurrent: Bool,
                currentPass: Int,
                theme: MelGenTheme,
                onLoad: @escaping () -> Void) {
        self.name = name
        self.facets = facets
        self.tags = tags
        self.latestMark = latestMark
        self.isCurrent = isCurrent
        self.currentPass = currentPass
        self.theme = theme
        self.onLoad = onLoad
    }
}

/// One mutation, offered for audition.
///
/// The three numbers are shown side by side and not added together: collapsing
/// them into one score would decide in advance what "good" means, and that
/// decision belongs to whoever is listening. The order they're offered in is a
/// default, not a verdict.
/// A variant, with a way to judge it.
///
/// Variants were auditionable but not answerable, which left the best material
/// the system produces outside the loop that decides what's good: a transform
/// that improves a pattern *is* the tweak the disposition vocabulary already has
/// a word for, and there was no way to say so. Keeping one records it as its own
/// take, so it joins the library and conditions what comes next, exactly as a
/// generated line does.
/// Takes the four things it draws rather than the `MelodyVariant` they came
/// from. The row is a name and three scores; naming the type here would put the
/// whole transform vocabulary in the UI kit to render a label and a chip.
public struct VariantRow: View {
    public let transform: String
    public let summary: String
    public let novelty: Double
    public let variety: Double
    public let styleDistance: Double
    public let theme: MelGenTheme
    public let onAudition: () -> Void
    public let onMorphTarget: () -> Void
    /// Records a judgement about this variant. Nil disposition clears it.
    public var onJudge: ((TakeDisposition?) -> Void)?
    /// What's already been said about it, if anything.
    public var disposition: TakeDisposition?

    public var body: some View {
        HStack(spacing: MelGenMetrics.space2) {
            Button(action: onAudition) {
                HStack(spacing: MelGenMetrics.space2) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(transform)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            scoreChip("new", novelty)
                            scoreChip("varied", variety)
                            if styleDistance > 0 {
                                scoreChip("from you", styleDistance)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(transform)
            .accessibilityValue(summary)
            .accessibilityHint("Plays this variant")

            Button(action: onMorphTarget) {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                    .frame(width: 28, height: MelGenMetrics.smallControlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Morph toward \(transform)")
        }
        .padding(.horizontal, MelGenMetrics.space2)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.raised)
        )
        .overlay(alignment: .topTrailing) {
            if disposition != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.accent)
                    .padding(3)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 2) {
            if let onJudge {
                DispositionBar(current: disposition, theme: theme, onSelect: onJudge)
            }
        }
    }

    private func scoreChip(_ label: String, _ value: Double) -> some View {
        Text("\(Int(value * 100))% \(label)")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(theme.textMuted)
    }

    /// The memberwise initializer, written out because a public struct's
    /// synthesized one is internal and the app is a different module now.
    public init(transform: String,
                summary: String,
                novelty: Double,
                variety: Double,
                styleDistance: Double,
                theme: MelGenTheme,
                onAudition: @escaping () -> Void,
                onMorphTarget: @escaping () -> Void,
                onJudge: ((TakeDisposition?) -> Void)? = nil,
                disposition: TakeDisposition? = nil) {
        self.transform = transform
        self.summary = summary
        self.novelty = novelty
        self.variety = variety
        self.styleDistance = styleDistance
        self.theme = theme
        self.onAudition = onAudition
        self.onMorphTarget = onMorphTarget
        self.onJudge = onJudge
        self.disposition = disposition
    }
}
