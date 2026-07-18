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

struct DaySummaryHeaderView: View {
    let greeting: String
    let summary: String
    /// SF Symbol reflecting the time of day (chosen by MenuBuilder).
    let symbolName: String

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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: Self.preferredWidth, alignment: .leading)
    }
}

#Preview {
    DaySummaryHeaderView(
        greeting: "Good morning, Peter",
        summary: "3 meetings today · 4h 30m free",
        symbolName: "sunrise.fill"
    )
}
