//
//  DaySummaryHeaderView.swift
//  MeetingBarNG
//
//  Non-clickable greeting header rendered at the top of the dropdown (Dot
//  parity). Copies the NSHostingView-backed, fixed-width pattern of
//  MeetingSummaryView. All strings are pre-localized by DropdownPanelView, its
//  only caller; this view is presentation-only.
//

import SwiftUI

/// A trailing icon button in the day header.
///
/// Modelled as data rather than a `@ViewBuilder`. This dates from when the header
/// also had to render inside the classic `NSMenu`'s `NSHostingView`, which had no
/// SwiftUI action context; that renderer is gone, but data-shaped actions keep the
/// header usable from a hosting view, so the shape is retained.
struct DaySummaryHeaderAction: Identifiable {
    let id: String
    let symbol: String
    let help: String
    let run: @MainActor () -> Void
}

struct DaySummaryHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme

    let greeting: String
    let summary: String
    /// SF Symbol reflecting the time of day (chosen by the caller).
    let symbolName: String
    /// Trailing quick actions. Defaults to empty so a host that cannot run SwiftUI
    /// closures still renders a plain header.
    var actions: [DaySummaryHeaderAction] = []

    static let preferredWidth: CGFloat = MeetingSummaryView.preferredWidth
    /// 26pt tile + the vertical padding below. Must track those two: a hosting view
    /// that sizes its item from this number rather than measuring the view will clip
    /// if they drift.
    static let preferredHeight: CGFloat = 48

    var body: some View {
        HStack(spacing: 10) {
            // The time-of-day glyph sits in its own rounded tile — decorative
            // identity, not an action, so it is a flat inset tile rather than a
            // raised one. The trailing ACTIONS are raised instead (see
            // `DaySummaryHeaderButton`); the two treatments are what distinguish
            // "this is what the panel is about" from "this does something".
            // 26pt, from the mockup's `.dayhead .glyph`. It shipped at 32 and
            // was the heaviest thing in the header, which put the emphasis on
            // decoration rather than on the greeting beside it.
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(PanelChrome.rim(colorScheme, top: 0.12, bottom: 0.04))
                )

            VStack(alignment: .leading, spacing: 2) {
                // 13.5/semibold from the mockup's `.dayhead .who b`. At 15 it
                // competed with the meeting title below it, which is the line
                // that should carry the most weight in the panel.
                Text(greeting)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.primary)
                Text(summary)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    // One line, always. This carries up to three segments once
                    // the date is included, and letting it wrap grew the header
                    // and unbalanced the tile beside it. Shrinking a little is
                    // the lesser cost; the date and count survive either way.
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 6)

            if !actions.isEmpty {
                // Spaced, not touching: once the buttons carry their own fill and
                // rim, a 1pt gutter merged them into one segmented control.
                HStack(spacing: 4) {
                    ForEach(actions) { action in
                        DaySummaryHeaderButton(action: action)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: Self.preferredWidth, alignment: .leading)
    }
}

/// One header icon button. Its own view so hover state is per-button — a single
/// shared `@State` in the header would light every icon at once.
///
/// Raised rather than bare. A flat glyph on glass has no edge to catch light, so
/// it read as a label rather than a control; giving it a fill, a lit top edge and
/// a soft shadow is what makes it look pressable. The three cues have to travel
/// together — a fill alone is just a swatch, and a border alone is the "boxed
/// icon" look the panel avoids everywhere else.
private struct DaySummaryHeaderButton: View {
    let action: DaySummaryHeaderAction

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: action.symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            // Smaller than the 26pt identity tile. They were equal, which made
            // three controls carry the same weight as the thing the header is
            // about; the tile should lead and the actions should follow.
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.13 : 0.07))
            )
            .overlay(
                // Light from above: bright along the top edge, gone by the
                // bottom. A uniform border would flatten the button back out.
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        PanelChrome.rim(
                            colorScheme,
                            top: isHovered ? 0.30 : 0.20,
                            bottom: 0.05
                        ),
                        lineWidth: 0.8
                    )
            )
            // Sits ON the surface rather than in it. Kept tight and low-opacity:
            // a wider shadow would smear across the glass behind it.
            .shadow(color: .black.opacity(isHovered ? 0.28 : 0.18), radius: 1.5, y: 1)
            .contentShape(Rectangle())
            .pointerStyle(.link)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
            .onTapGesture { action.run() }
            .help(action.help)
            .accessibilityLabel(action.help)
            .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    DaySummaryHeaderView(
        greeting: "Good morning, Peter",
        summary: "3 meetings today · 4h 30m free",
        symbolName: "sunrise.fill"
    )
}
