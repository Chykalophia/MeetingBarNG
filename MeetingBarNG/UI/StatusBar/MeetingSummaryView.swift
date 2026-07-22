//
//  MeetingSummaryView.swift
//  MeetingBar
//

import AppKit
import SwiftUI

struct MeetingSummaryPresentation: Equatable {
    let sectionTitle: String
    let eventTitle: String
    let metadata: [String]
    /// `var` so a renderer can clear it: the SwiftUI panel honours
    /// `showMeetingServiceIcon` on the card, the classic NSMenu does not.
    var meetingService: MeetingServices?
    /// Relative time until the meeting starts (e.g. "in 25m"); nil for
    /// running meetings, where the section title already says enough.
    var countdown: String?

    var metadataText: String {
        metadata.joined(separator: " • ")
    }

    var sectionTitleText: String {
        guard let countdown, !countdown.isEmpty else { return sectionTitle }
        return "\(sectionTitle) • \(countdown)"
    }
}

struct MeetingSummaryView: View {
    let presentation: MeetingSummaryPresentation
    var onJoin: (() -> Void)?

    @State private var isHovered = false

    /// Derived rather than passed in: every call site computed exactly this, and
    /// letting them differ was how the card ended up indenting a title behind an
    /// invisible icon. `nil` when the event has no online meeting — the icon is
    /// then omitted entirely and the title sits flush, instead of reserving a
    /// gutter for the blank "no_online_session" placeholder.
    private var providerIcon: NSImage? {
        presentation.meetingService.map { getIconForMeetingService($0) }
    }

    // Narrower, modern menu-bar-dropdown width. DaySummaryHeaderView and the
    // timeline's NSHostingView both size off this constant, so the greeting,
    // timeline, summary card, and event rows all share one ~330 width — which is
    // itself the panel width in the hostless `DropdownMetrics` grid.
    static let preferredWidth: CGFloat = DropdownMetrics.standard.panelWidth
    static let preferredHeight: CGFloat = 66

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.sectionTitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 7) {
                    if let providerIcon {
                        Image(nsImage: providerIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }

                    Text(presentation.eventTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(presentation.metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if onJoin != nil {
                Spacer(minLength: 8)
                Text("notifications_meetingbar_join_event_action".loco())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor))
                    .opacity(isHovered ? 1.0 : 0.9)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(
            maxWidth: .infinity,
            minHeight: Self.preferredHeight,
            alignment: .leading
        )
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered && onJoin != nil ? Color.primary.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        // Scoped pointer style (macOS 15+, at the deployment floor). The previous
        // NSCursor.push/pop pair is the pattern `PanelRow` documents as able to
        // strand a pointing-hand cursor when the panel closes mid-hover.
        // https://developer.apple.com/documentation/swiftui/view/pointerstyle(_:)
        .pointerStyle(onJoin == nil ? nil : .link)
        .onHover { hovering in isHovered = hovering }
        .onTapGesture { onJoin?() }
    }
}

#Preview {
    MeetingSummaryView(
        presentation: MeetingSummaryPresentation(
            sectionTitle: "Next meeting",
            eventTitle: "Weekly product sync",
            metadata: ["10:00 – 10:30", "Zoom", "Work"],
            meetingService: .zoom,
            countdown: "in 25m"
        ),
        onJoin: {}
    )
}
