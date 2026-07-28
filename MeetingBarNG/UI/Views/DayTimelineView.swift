//
//  DayTimelineView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 22.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import SwiftUI

struct DaySegment: Identifiable {
    let id: String
    let start: Date
    let end: Date
    let color: Color
    let isHighlighted: Bool
    let title: String?

    init(
        id: String = UUID().uuidString,
        start: Date,
        end: Date,
        color: Color,
        isHighlighted: Bool = false,
        title: String? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.color = color
        self.isHighlighted = isHighlighted
        self.title = title
    }
}

enum DayTimelineLayout {
    /// How many hours are visible to the left / right of “now”
    static let hoursBefore: TimeInterval = 3 * 3600   // 3 h
    static let hoursAfter: TimeInterval = 6 * 3600   // 6 h

    static let baseTrackHeight: CGFloat = 22
    static let segmentHeight: CGFloat = 10
    static let rowSpacing: CGFloat = 4

    static var rowHeight: CGFloat { segmentHeight + rowSpacing }

    /// Half the width of the widest hour label at `.caption2`, by format.
    ///
    /// An estimate on purpose: measuring the rendered string would need a layout
    /// pass per tick to decide which labels survive. Over-estimating is the safe
    /// direction — it thins one label too many rather than letting two collide.
    static func hourLabelHalfWidth(for format: TimeFormat) -> CGFloat {
        switch format {
        case .am_pm: 17    // "12 PM"
        case .military: 7  // "09"
        }
    }

    /// Minimum clear distance between two label CENTRES before both are drawn.
    /// Two half-widths would leave them exactly touching, so add a readable gap.
    static func minimumLabelSpacing(for format: TimeFormat) -> CGFloat {
        hourLabelHalfWidth(for: format) * 2 + 6
    }
}

struct DayTimelineLayoutCalculator {
    // MARK: Cached range information
    let now: Date
    let visibleRange: ClosedRange<Date>
    private let totalSeconds: TimeInterval

    /// The range comes from `DayTimelineRange` so the two styles — and the
    /// left-fill behaviour of `.relative` — are decided by tested arithmetic
    /// rather than by this view.
    init(now: Date = Date(), range: ClosedRange<Date>) {
        self.now = now
        self.visibleRange = range
        self.totalSeconds = range.upperBound.timeIntervalSince(range.lowerBound)
    }

    init(now: Date = Date()) {
        self.now = now
        let lower = now.addingTimeInterval(-DayTimelineLayout.hoursBefore)
        let upper = now.addingTimeInterval( DayTimelineLayout.hoursAfter)
        self.visibleRange = lower...upper
        self.totalSeconds = upper.timeIntervalSince(lower)
    }

    // MARK: X-position helpers
    func xPosition(of date: Date, width: CGFloat) -> CGFloat {
        let clamped = min(max(date, visibleRange.lowerBound), visibleRange.upperBound)
        let seconds = clamped.timeIntervalSince(visibleRange.lowerBound)
        return width * CGFloat(seconds / totalSeconds)
    }

    // MARK: Hour ticks
    func hourTicks() -> [Date] {
        var out: [Date] = []
        var current = Calendar.current.nextDate(
            after: visibleRange.lowerBound.addingTimeInterval(-1),
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .strict
        )!
        while current <= visibleRange.upperBound {
            out.append(current)
            current = Calendar.current.date(byAdding: .hour, value: 1, to: current)!
        }
        return out
    }

    // MARK: Hour labels

    /// Keeps an hour label inside the view, leaving interior labels untouched.
    ///
    /// `.position` CENTRES on x, so a tick at either edge put half its label
    /// outside the view. At the panel's old full width nothing clipped it, so it
    /// went unnoticed; inside a card the overflow is visibly cut ("4 P").
    func clampedLabelX(_ x: CGFloat, width: CGFloat, halfWidth: CGFloat) -> CGFloat {
        guard width > halfWidth * 2 else { return width / 2 }
        return min(max(x, halfWidth), width - halfWidth)
    }

    /// The hour ticks that still get a LABEL at this width — every tick keeps its
    /// grid line, but a label is dropped when it would overlap the last one kept.
    ///
    /// Needed because clamping alone only stopped labels escaping the view; it
    /// left them free to collide with each other. At a 360pt panel in 12-hour
    /// format the nine visible hours sit ~37pt apart while "12 PM" is ~34pt wide,
    /// so the edge labels overlapped their neighbours ("4 PM5 PM").
    ///
    /// Greedy from the left, which means a colliding LAST label is the one
    /// dropped. That is the right end to lose: the earlier label is already
    /// placed, and dropping an interior one would leave a visible hole.
    func labelledTicks(width: CGFloat, timeFormat: TimeFormat) -> [Date] {
        let halfWidth = DayTimelineLayout.hourLabelHalfWidth(for: timeFormat)
        let minimumSpacing = DayTimelineLayout.minimumLabelSpacing(for: timeFormat)
        var kept: [Date] = []
        var lastX: CGFloat?

        for tick in hourTicks() {
            let x = clampedLabelX(
                xPosition(of: tick, width: width),
                width: width,
                halfWidth: halfWidth
            )
            if let lastX, x - lastX < minimumSpacing { continue }
            kept.append(tick)
            lastX = x
        }
        return kept
    }

    // MARK: Row packing
    func rows(for segments: [DaySegment]) -> [[DaySegment]] {
        var rows: [[DaySegment]] = []
        for seg in segments where seg.end > visibleRange.lowerBound && seg.start < visibleRange.upperBound {
            if let idx = rows.firstIndex(where: { row in
                !row.contains(where: { $0.start < seg.end && $0.end > seg.start })
            }) {
                rows[idx].append(seg)
            } else {
                rows.append([seg])
            }
        }
        return rows
    }
}

struct DayRelativeTimelineView: View {
    let segments: [DaySegment]
    let currentDate: Date
    let timeFormat: TimeFormat

    // Cached / pre-computed values
    private let layout: DayTimelineLayoutCalculator
    private let eventRows: [[DaySegment]]
    private let contentHeight: CGFloat

    /// Height the parent can rely on for sizing
    var preferredHeight: CGFloat { contentHeight + 26 }   // top labels + vertical padding

    // MARK: Init
    init(
        segments: [DaySegment],
        currentDate: Date,
        timeFormat: TimeFormat,
        style: TimelineStyle = .relative
    ) {
        // The bar is framed around the events it is actually drawing, so the
        // relative style opens on content instead of on empty past.
        let bounds = segments.isEmpty
            ? nil
            : (
                first: segments.map(\.start).min() ?? currentDate,
                last: segments.map(\.end).max() ?? currentDate
            )
        let layout = DayTimelineLayoutCalculator(
            now: currentDate,
            range: DayTimelineRange.range(style: style, now: currentDate, bounds: bounds)
        )
        self.segments     = segments
        self.currentDate  = currentDate
        self.timeFormat   = timeFormat
        self.layout       = layout
        self.eventRows    = layout.rows(for: segments)
        self.contentHeight = DayTimelineLayout.baseTrackHeight +
            DayTimelineLayout.rowHeight * CGFloat(max(eventRows.count - 1, 0))
    }

    /// Ticks that get a label at this width, in the view's current time format.
    private func labelledTicks(width: CGFloat) -> [Date] {
        layout.labelledTicks(width: width, timeFormat: timeFormat)
    }

    // MARK: Body
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .topLeading) {

                // Hour grid — every tick draws its line at the TRUE position.
                ForEach(layout.hourTicks(), id: \.self) { tick in
                    let x = layout.xPosition(of: tick, width: width)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: contentHeight))
                    }
                    .stroke(Color.primary.opacity(0.25), lineWidth: 1)
                }

                // Hour labels — only the ticks that can be labelled without
                // colliding, each clamped to stay inside the view.
                ForEach(labelledTicks(width: width), id: \.self) { tick in
                    Text(hourFormatter.string(from: tick))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize()
                        .position(
                            x: layout.clampedLabelX(
                                layout.xPosition(of: tick, width: width),
                                width: width,
                                halfWidth: DayTimelineLayout.hourLabelHalfWidth(for: timeFormat)
                            ),
                            y: -8
                        )
                }

                // Event rows
                ForEach(eventRows.indices, id: \.self) { row in
                    ForEach(eventRows[row]) { seg in
                        let startX  = layout.xPosition(of: max(seg.start, layout.visibleRange.lowerBound), width: width)
                        let endX    = layout.xPosition(of: min(seg.end, layout.visibleRange.upperBound), width: width)
                        let widthPx = max(endX - startX, DayTimelineLayout.segmentHeight / 2)

                        // Raised from 0.55/0.25. Behind-window vibrancy lightens
                        // with the DESKTOP, so over a pale wallpaper a quarter-
                        // opacity capsule all but vanished against the surface.
                        Capsule()
                            .fill(seg.color.opacity(seg.isHighlighted ? 0.70 : 0.42))
                            .overlay(
                                Capsule().stroke(
                                    seg.color,
                                    lineWidth: seg.isHighlighted ? 2 : 1
                                )
                            )
                            .frame(width: widthPx, height: DayTimelineLayout.segmentHeight)
                            .offset(
                                x: startX,
                                y: (DayTimelineLayout.baseTrackHeight - DayTimelineLayout.segmentHeight) / 2 +
                                   CGFloat(row) * DayTimelineLayout.rowHeight
                            )
                            .help(seg.title ?? "")
                    }
                }

                // Current time indicator
                if layout.visibleRange.contains(currentDate) {
                    let x = layout.xPosition(of: currentDate, width: width)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: contentHeight + 4)
                        .offset(x: x - 1, y: -2)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: x - 3, y: -5)
                }
            }
            .frame(height: contentHeight)
        }
        // OUTSIDE the GeometryReader on purpose. Inset within it, the proxy still
        // measured the FULL width while the content drew into a box 24pt
        // narrower, so every x position was computed against the wrong width and
        // the right-hand labels ran past the card's edge ("10 PM" clipped).
        .padding(.top, 10)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("timeline_accessibility_label".loco(segments.count))
    }

    private var hourFormatter: DateFormatter {
        let format = DateFormatter()
        format.locale = I18N.instance.locale
        switch timeFormat {
        case .am_pm:    format.dateFormat = "h a"
        case .military: format.dateFormat = "HH"
        }
        return format
    }
}

// MARK: — Preview

#Preview {
    let cal = Calendar.current
    let now = Date()
    let sampleSegments = [
        DaySegment(
            start: cal.date(byAdding: .hour, value: -2, to: now)!,
            end: cal.date(byAdding: .hour, value: -1, to: now)!,
            color: .blue
        ),
        DaySegment(
            start: cal.date(byAdding: .minute, value: -90, to: now)!,
            end: cal.date(byAdding: .minute, value: -30, to: now)!,
            color: .blue
        ),
        DaySegment(
            start: cal.date(byAdding: .minute, value: -90, to: now)!,
            end: cal.date(byAdding: .minute, value: 30, to: now)!,
            color: .blue
        ),
        DaySegment(
            start: cal.date(byAdding: .minute, value: -30, to: now)!,
            end: cal.date(byAdding: .minute, value: 30, to: now)!,
            color: .blue
        ),
        DaySegment(
            start: cal.date(byAdding: .hour, value: 1, to: now)!,
            end: cal.date(byAdding: .hour, value: 2, to: now)!,
            color: .green
        ),
        DaySegment(
            start: cal.date(byAdding: .hour, value: 4, to: now)!,
            end: cal.date(byAdding: .hour, value: 5, to: now)!,
            color: .orange
        )
    ]

    DayRelativeTimelineView(
        segments: sampleSegments,
        currentDate: now,
        timeFormat: .military
    )
    .padding()
}
