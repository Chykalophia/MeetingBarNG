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
    let onStep: (Int) -> Void
    let onSelect: (Date) -> Void

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
            Text(monthTitle)
                .font(.system(size: metrics.rowFontSize, weight: .semibold))
            Spacer(minLength: 0)
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
        CompactMonthDayCell(
            day: day,
            dots: markers[calendar.startOfDay(for: day.date)] ?? [],
            calendar: calendar,
            metrics: metrics,
            onSelect: onSelect
        )
    }

    // MARK: - Derived

    private var weeks: [[MonthGridDay]] {
        MonthGridLayout.weeks(forMonthContaining: month, calendar: calendar, now: now)
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
                    weight: day.isToday ? .bold : .regular
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
    }

    private var fill: Color {
        if day.isToday {
            return isHovered ? Color.accentColor.opacity(0.85) : Color.accentColor
        }
        return isHovered ? Color.primary.opacity(0.12) : .clear
    }

    private func dayColor(_ day: MonthGridDay) -> Color {
        if day.isToday { return .white }
        return day.isInMonth ? .primary : .secondary.opacity(0.5)
    }

    private func dayNumber(_ date: Date) -> String {
        String(calendar.component(.day, from: date))
    }
}
