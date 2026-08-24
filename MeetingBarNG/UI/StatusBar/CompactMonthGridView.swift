//
//  CompactMonthGridView.swift
//  MeetingBarNG
//
//  A month grid sized for the dropdown panel.
//
//  Why not reuse `CalendarGridView`: that view is floored at
//  `CalendarWindowPresentationPolicy.minimumSize.width` (460pt) and carries a
//  window's worth of chrome — a mode switcher, a selected-day detail list, week
//  numbers. The panel is 330pt. Bending the window's view down to fit would mean
//  surgery on a shipping surface for the benefit of a different one, and every
//  future change to either would have to satisfy both.
//
//  Instead this shares the POLICY and not the view: `MonthGridLayout` (hostless)
//  computes the weeks, the today flag and the visible range, exactly as it does
//  for the window. The two views disagree about chrome and agree about dates,
//  which is the right split — the same reasoning as `EventActionProminence`.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import SwiftUI

struct CompactMonthGridView: View {
    /// Month to render, any date within it.
    let month: Date
    let now: Date
    let calendar: Calendar
    /// Day-start -> calendar colours of that day's events, in order. Drives the
    /// dots; empty means a day with nothing on it.
    let markers: [Date: [Color]]
    /// User-marked important days. Rendered by tinting the day NUMBER rather than
    /// adding a fourth dot: the dot row already means "how busy", and overloading
    /// it would make a marked free day look like a meeting.
    var dateMarkers: [DateMarker] = []
    /// Folded to a single week. The step buttons follow suit — see
    /// `MonthGridLayout.anchor`, which the panel uses to move the anchor.
    var isWeekFold = false
    let onStep: (Int) -> Void
    let onSelect: (Date) -> Void
    /// Toggles the fold. Optional so previews and the Preferences live preview
    /// can render the grid without owning the setting.
    var onToggleFold: (() -> Void)?
    /// Returns the grid to the current period. Shown only when the user has
    /// stepped away — until now the only way back was stepping the same number
    /// of times in the other direction.
    var onReturnToToday: (() -> Void)?
    /// Whether the grid is currently showing something other than the period
    /// containing `now`. Owned by the panel, which holds the offset.
    var isSteppedAway = false

    @Environment(\.dropdownMetrics) private var metrics

    /// Dots per day. A packed conference day would otherwise draw a dozen and
    /// turn the cell into a smear; the overflow is silently dropped because the
    /// exact count is not the point — "this day is busy" is.
    static let maxMarkers = 3

    var body: some View {
        VStack(spacing: 5) {
            header
            weekdayRow
            grid
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: metrics.rowFontSize, weight: .semibold))
            Spacer(minLength: 0)
            if isSteppedAway, let onReturnToToday {
                Text("dropdown_calendar_today".loco())
                    .font(.system(size: metrics.secondaryFontSize - 2, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .pointerStyle(.link)
                    .onTapGesture { onReturnToToday() }
                    .help("dropdown_calendar_today_help".loco())
            }
            if let onToggleFold {
                Image(systemName: isWeekFold
                    ? "rectangle.expand.vertical"
                    : "rectangle.compress.vertical")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
                    .pointerStyle(.link)
                    .onTapGesture { onToggleFold() }
                    .help(isWeekFold
                        ? "dropdown_calendar_show_month".loco()
                        : "dropdown_calendar_show_week".loco())
                    .accessibilityLabel(isWeekFold
                        ? "dropdown_calendar_show_month".loco()
                        : "dropdown_calendar_show_week".loco())
            }
            stepButton(symbol: "chevron.left", step: -1)
            stepButton(symbol: "chevron.right", step: 1)
        }
    }

    private func stepButton(symbol: String, step: Int) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 18)
            .contentShape(Rectangle())
            .pointerStyle(.link)
            .onTapGesture { onStep(step) }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: metrics.secondaryFontSize - 3, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 1) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.date) { day in
                        cell(day)
                    }
                }
            }
        }
    }

    private func cell(_ day: MonthGridDay) -> some View {
        let marked = DateMarkerPolicy.markers(on: day.date, from: dateMarkers, calendar: calendar)
        return CompactMonthDayCell(
            day: day,
            dots: markers[calendar.startOfDay(for: day.date)] ?? [],
            markerLabels: marked.map(\.label),
            calendar: calendar,
            metrics: metrics,
            onSelect: onSelect
        )
    }

    // MARK: - Derived

    private var weeks: [[MonthGridDay]] {
        MonthGridLayout.rows(anchoredOn: month, isWeekFold: isWeekFold, calendar: calendar, now: now)
    }

    /// Narrow symbols ("M", "T") rotated to the locale's first weekday — the grid
    /// itself is built on `calendar.firstWeekday`, so the header has to match or
    /// every column is mislabelled.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        guard offset > 0, offset < symbols.count else { return symbols }
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var title: String {
        guard isWeekFold else { return monthTitle }
        // A folded week can straddle two months, so "August 2026" over a row
        // running 30 Aug – 5 Sep would be a lie. DateIntervalFormatter collapses
        // the shared parts per locale ("30 Aug – 5 Sep", "18–24 Aug").
        let range = MonthGridLayout.visibleRange(
            anchoredOn: month, isWeekFold: true, calendar: calendar
        )
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateTemplate = "MMMd"
        return formatter.string(from: range.start, to: range.end)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: month)
    }
}

/// One day in the grid. Its own view so the hover highlight is per-cell — a
/// single `@State` on the grid would light the whole month at once, which is the
/// same reason `PanelRow` is its own type.
private struct CompactMonthDayCell: View {
    let day: MonthGridDay
    let dots: [Color]
    /// Labels of any user markers on this day. Empty is the common case.
    let markerLabels: [String]
    let calendar: Calendar
    let metrics: DropdownMetrics
    let onSelect: (Date) -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxMarkers = CompactMonthGridView.maxMarkers

    var body: some View {
        VStack(spacing: 1) {
            Text(dayNumber(day.date))
                .font(.system(
                    size: metrics.secondaryFontSize - 1,
                    // A marked day gets weight as well as colour, so it is still
                    // distinguishable with a colour-vision deficiency and when
                    // Increase Contrast flattens the accent.
                    weight: day.isToday ? .bold : (isMarked ? .semibold : .regular)
                ))
                .foregroundStyle(dayColor(day))
            // The dot row is always present, even when empty, so a day with
            // events is not one pixel taller than one without.
            HStack(spacing: 2) {
                ForEach(Array(dots.prefix(Self.maxMarkers).enumerated()), id: \.offset) { _, colour in
                    Circle()
                        .fill(day.isToday ? Color.white.opacity(0.9) : colour)
                        .frame(width: 3, height: 3)
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                // Today keeps its accent fill; every OTHER day had no hover
                // state at all, so the grid was the one part of the panel that
                // gave no sign a cell could be clicked.
                .fill(fill)
        )
        .contentShape(Rectangle())
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.10)) {
                isHovered = hovering
            }
        }
        .onTapGesture { onSelect(day.date) }
        // The only place the marker's LABEL is readable — the grid cell is far
        // too small to draw it, so colour says "something is here" and the
        // tooltip says what.
        .help(markerLabels.joined(separator: " · "))
        .accessibilityLabel(accessibilityLabel)
    }

    /// VoiceOver gets the labels outright: a tooltip needs a pointer, and colour
    /// alone conveys nothing here.
    private var accessibilityLabel: String {
        let dayText = dayNumber(day.date)
        guard isMarked else { return dayText }
        return "\(dayText), \(markerLabels.joined(separator: ", "))"
    }

    private var fill: Color {
        if day.isToday {
            return isHovered ? Color.accentColor.opacity(0.85) : Color.accentColor
        }
        return isHovered ? Color.primary.opacity(0.12) : .clear
    }

    private var isMarked: Bool { !markerLabels.isEmpty }

    private func dayColor(_ day: MonthGridDay) -> Color {
        // Today's accent fill wins: white-on-accent is already the strongest cell
        // in the grid, and tinting the number there would reduce contrast to say
        // something the tooltip says better.
        if day.isToday { return .white }
        guard day.isInMonth else { return .secondary.opacity(0.5) }
        return isMarked ? .accentColor : .primary
    }

    private func dayNumber(_ date: Date) -> String {
        String(calendar.component(.day, from: date))
    }
}
