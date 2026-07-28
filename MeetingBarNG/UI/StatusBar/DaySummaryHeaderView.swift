//
//  DaySummaryHeaderView.swift
//  MeetingBarNG
//
//  Non-clickable greeting header rendered at the top of the dropdown (Dot
//  parity). Copies the NSHostingView-backed, fixed-width pattern of
//  MeetingSummaryView. All strings are pre-localized by MenuBuilder; this view
//  is presentation-only.
//

import SwiftUI

/// A trailing icon button in the day header.
///
/// Modelled as data rather than a `@ViewBuilder` so the header stays renderable
/// from `MenuBuilder`'s `NSHostingView` too, where there is no SwiftUI action
/// context to hand down.
struct DaySummaryHeaderAction: Identifiable {
    let id: String
    let symbol: String
    let help: String
    let run: @MainActor () -> Void
}

struct DaySummaryHeaderView: View {
    let greeting: String
    let summary: String
    /// SF Symbol reflecting the time of day (chosen by MenuBuilder).
    let symbolName: String
    /// Trailing quick actions. Empty by default so the classic `NSMenu`'s hosted
    /// copy — which has no way to run SwiftUI closures — renders exactly as before.
    var actions: [DaySummaryHeaderAction] = []

    static let preferredWidth: CGFloat = MeetingSummaryView.preferredWidth
    static let preferredHeight: CGFloat = 54

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 6)

            if !actions.isEmpty {
                HStack(spacing: 1) {
                    ForEach(actions) { action in
                        DaySummaryHeaderButton(action: action)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: Self.preferredWidth, alignment: .leading)
    }
}

/// One header icon button. Its own view so hover state is per-button — a single
/// shared `@State` in the header would light every icon at once.
private struct DaySummaryHeaderButton: View {
    let action: DaySummaryHeaderAction

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: action.symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.10) : .clear)
            )
            .contentShape(Rectangle())
            .pointerStyle(.link)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
            .onTapGesture { action.run() }
            .help(action.help)
    }
}

#Preview {
    DaySummaryHeaderView(
        greeting: "Good morning, Peter",
        summary: "3 meetings today · 4h 30m free",
        symbolName: "sunrise.fill"
    )
}
