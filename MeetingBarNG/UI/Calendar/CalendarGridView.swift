//
//  CalendarGridView.swift
//  MeetingBarNG
//
//  Calendar surface for the calendar window (Dot parity). Presentation only: a
//  header with ‹ ›, Today and a Month/Week fold picker, a localized weekday row,
//  a 7-column grid of day cells (each showing a day number plus up to three
//  calendar-color event dots, with weekends optionally dimmed), and a list of
//  the selected day's events with a Join affordance. All state and event loading
//  live in CalendarGridViewModel.
//

import Defaults
import SwiftUI

enum CalendarWindowPresentationPolicy {
    static let contentRect = CGSize(width: 520, height: 560)
    static let minimumSize = NSSize(width: 460, height: 480)
}

struct CalendarGridView: View {
    @ObservedObject var viewModel: CalendarGridViewModel
    @Default(.dimWeekendsInCalendar) private var dimWeekends

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4), count: 7
    )

    var body: some View {
        VStack(spacing: 0) {
            header
            weekdayHeader
            monthGrid
            Divider()
            selectedDaySection
        }
        .frame(
            minWidth: CalendarWindowPresentationPolicy.minimumSize.width,
            minHeight: CalendarWindowPresentationPolicy.minimumSize.height
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(rangeTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            modePicker

            Button {
                viewModel.goToToday()
            } label: {
                Text("calendar_grid_today".loco())
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            navButton(
                systemName: "chevron.left",
                accessibility: previousAccessibilityLabel,
                action: viewModel.goToPrevious
            )
            navButton(
                systemName: "chevron.right",
                accessibility: nextAccessibilityLabel,
                action: viewModel.goToNext
            )

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Month ⇄ week fold. `.segmented` is available on the macOS 12 floor.
    private var modePicker: some View {
        Picker("calendar_grid_mode_label".loco(), selection: modeBinding) {
            Text("calendar_grid_mode_month".loco()).tag(CalendarGridMode.month)
            Text("calendar_grid_mode_week".loco()).tag(CalendarGridMode.week)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 132)
        .accessibilityLabel("calendar_grid_mode_label".loco())
    }

    private var modeBinding: Binding<CalendarGridMode> {
        Binding(
            get: { viewModel.mode },
            set: { viewModel.setMode($0) }
        )
    }

    private func navButton(
        systemName: String,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibility)
    }

    // MARK: - Weekday header

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Month grid

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(viewModel.weeks.enumerated()), id: \.offset) { _, week in
                ForEach(week, id: \.date) { day in
                    DayCell(
                        day: day,
                        dayNumber: dayNumber(for: day.date),
                        events: viewModel.events(on: day),
                        isSelected: isSelected(day),
                        isDimmedWeekend: isDimmedWeekend(day)
                    )
                    .onTapGesture { viewModel.select(day) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Selected day

    @ViewBuilder
    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedDay = viewModel.selectedDay {
                Text(selectedDayTitle(selectedDay))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
            }

            let events = viewModel.selectedDayEvents
            if events.isEmpty {
                Text("calendar_grid_no_events".loco())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(events) { event in
                            CalendarEventRow(
                                event: event,
                                timeText: timeText(for: event),
                                onJoin: event.meetingLink != nil
                                    ? { viewModel.join(event) }
                                    : nil
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Helpers

    private func isSelected(_ day: MonthGridDay) -> Bool {
        guard let selectedDay = viewModel.selectedDay else { return false }
        return viewModel.calendar.isDate(day.date, inSameDayAs: selectedDay)
    }

    /// Weekend days are drawn in a lighter foreground when the preference is on.
    /// `Calendar.isDateInWeekend` follows the locale (not always Sat/Sun).
    private func isDimmedWeekend(_ day: MonthGridDay) -> Bool {
        dimWeekends && viewModel.calendar.isDateInWeekend(day.date)
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = viewModel.calendar.shortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let firstIndex = viewModel.calendar.firstWeekday - 1
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    /// "February 2026" in month mode; the visible week's date span in week mode
    /// (e.g. "Jul 12 – 18, 2026"), collapsed and ordered by the user's locale.
    private var rangeTitle: String {
        switch viewModel.mode {
        case .month:
            let formatter = DateFormatter()
            formatter.calendar = viewModel.calendar
            formatter.locale = I18N.instance.locale
            formatter.setLocalizedDateFormatFromTemplate("yMMMM")
            return formatter.string(from: viewModel.visibleMonth)
        case .week:
            // DateIntervalFormatter localizes the whole span (and collapses the
            // repeated month/year itself), so no hand-rolled range string.
            // https://developer.apple.com/documentation/foundation/dateintervalformatter
            let formatter = DateIntervalFormatter()
            formatter.calendar = viewModel.calendar
            formatter.locale = I18N.instance.locale
            formatter.timeZone = viewModel.calendar.timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            let start = viewModel.visibleWeekStart
            let end = MonthGridLayout.lastVisibleDayOfWeek(
                containing: start, calendar: viewModel.calendar
            )
            return formatter.string(from: start, to: end)
        }
    }

    private var previousAccessibilityLabel: String {
        viewModel.mode == .week
            ? "calendar_grid_previous_week".loco()
            : "calendar_grid_previous_month".loco()
    }

    private var nextAccessibilityLabel: String {
        viewModel.mode == .week
            ? "calendar_grid_next_week".loco()
            : "calendar_grid_next_month".loco()
    }

    private func dayNumber(for date: Date) -> String {
        String(viewModel.calendar.component(.day, from: date))
    }

    private func selectedDayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = viewModel.calendar
        formatter.locale = I18N.instance.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return formatter.string(from: date)
    }

    private func timeText(for event: MBEvent) -> String {
        guard !event.isAllDay else { return "calendar_grid_all_day".loco() }
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        formatter.setLocalizedDateFormatFromTemplate(
            Defaults[.timeFormat] == .military ? "Hmm" : "hmma"
        )
        return "\(formatter.string(from: event.startDate)) – \(formatter.string(from: event.endDate))"
    }
}

// MARK: - Day cell

private struct DayCell: View {
    let day: MonthGridDay
    let dayNumber: String
    let events: [MBEvent]
    let isSelected: Bool
    /// Weekend day with the dim-weekends preference on. Only the day number is
    /// muted — the today ring and the selection fill stay at full strength.
    let isDimmedWeekend: Bool

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle().fill(Color.accentColor)
                } else if day.isToday {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
                Text(dayNumber)
                    .font(.system(size: 13, weight: day.isToday ? .semibold : .regular))
                    .foregroundStyle(numberColor)
            }
            .frame(width: 26, height: 26)

            dots
                .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .opacity(day.isInMonth ? 1 : 0.35)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if day.isToday { return .accentColor }
        return isDimmedWeekend ? .secondary : .primary
    }

    @ViewBuilder
    private var dots: some View {
        let shown = Array(events.prefix(3))
        HStack(spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, event in
                Circle()
                    .fill(Color(nsColor: event.calendar.color))
                    .frame(width: 5, height: 5)
            }
            if events.count > 3 {
                Text("+\(events.count - 3)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Event row

private struct CalendarEventRow: View {
    let event: MBEvent
    let timeText: String
    var onJoin: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(nsColor: event.calendar.color))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let onJoin {
                Text("notifications_meetingbar_join_event_action".loco())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor))
                    .onTapGesture { onJoin() }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        // Double-click the row to join (single click is reserved for selection).
        .onTapGesture(count: 2) { onJoin?() }
    }
}
