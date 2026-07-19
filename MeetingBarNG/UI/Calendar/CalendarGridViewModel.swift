//
//  CalendarGridViewModel.swift
//  MeetingBarNG
//
//  App-target view model for the month calendar window. Owns the visible month,
//  the rendered week grid (via the hostless MonthGridLayout), and the events for
//  the visible range bucketed by start-of-day. It loads its OWN month window of
//  events on demand through an injected fetch closure (resolved by AppDelegate
//  from the calendar repository) — it never touches the main today/tomorrow
//  sync. The SwiftUI view stays presentation-only.
//

import Foundation

/// Closures the calendar window needs from the app, injected by AppDelegate so
/// the view model stays decoupled from AppModel / CalendarSync / the coordinator.
struct CalendarWindowHandlers {
    /// Fetches events for `[from, to)` across the user's selected calendars.
    var fetchEvents: @MainActor (_ from: Date, _ to: Date) async throws -> [MBEvent]
    /// Joins the meeting for the given event id (forwards to `.joinMeeting`).
    var join: @MainActor (_ eventID: String) -> Void
}

@MainActor
final class CalendarGridViewModel: ObservableObject {
    @Published private(set) var visibleMonth: Date
    @Published private(set) var weeks: [[MonthGridDay]] = []
    @Published private(set) var eventsByDay: [Date: [MBEvent]] = [:]
    @Published var selectedDay: Date?
    @Published private(set) var isLoading = false

    let calendar: Calendar
    private let now: Date
    private let handlers: CalendarWindowHandlers
    private var loadTask: Task<Void, Never>?

    init(
        handlers: CalendarWindowHandlers,
        calendar: Calendar = CalendarGridViewModel.defaultCalendar(),
        now: Date = Date()
    ) {
        self.handlers = handlers
        self.calendar = calendar
        self.now = now
        self.visibleMonth = MonthGridLayout.startOfMonth(for: now, calendar: calendar)
        self.selectedDay = calendar.startOfDay(for: now)
        reload()
    }

    /// A locale-aware calendar so the grid honors the user's chosen language
    /// (which drives `firstWeekday` and the localized weekday/month symbols).
    static func defaultCalendar() -> Calendar {
        var calendar = Calendar.current
        calendar.locale = I18N.instance.locale
        return calendar
    }

    // MARK: - Navigation

    func goToPreviousMonth() {
        guard let previous = calendar.date(byAdding: .month, value: -1, to: visibleMonth) else { return }
        visibleMonth = MonthGridLayout.startOfMonth(for: previous, calendar: calendar)
        reload()
    }

    func goToNextMonth() {
        guard let next = calendar.date(byAdding: .month, value: 1, to: visibleMonth) else { return }
        visibleMonth = MonthGridLayout.startOfMonth(for: next, calendar: calendar)
        reload()
    }

    func goToToday() {
        visibleMonth = MonthGridLayout.startOfMonth(for: now, calendar: calendar)
        selectedDay = calendar.startOfDay(for: now)
        reload()
    }

    // MARK: - Selection

    func select(_ day: MonthGridDay) {
        selectedDay = calendar.startOfDay(for: day.date)
    }

    var selectedDayEvents: [MBEvent] {
        guard let selectedDay else { return [] }
        return eventsByDay[calendar.startOfDay(for: selectedDay)] ?? []
    }

    func events(on day: MonthGridDay) -> [MBEvent] {
        eventsByDay[calendar.startOfDay(for: day.date)] ?? []
    }

    // MARK: - Join

    func join(_ event: MBEvent) {
        guard event.meetingLink != nil else { return }
        handlers.join(event.id)
    }

    // MARK: - Loading

    /// Rebuilds the grid for `visibleMonth` and (re)loads that month's events for
    /// the full visible range (leading/trailing padding days included).
    private func reload() {
        weeks = MonthGridLayout.weeks(
            forMonthContaining: visibleMonth, calendar: calendar, now: now
        )

        let first = MonthGridLayout.firstVisibleDay(
            forMonthContaining: visibleMonth, calendar: calendar
        )
        let lastVisible = MonthGridLayout.lastVisibleDay(
            forMonthContaining: visibleMonth, calendar: calendar
        )
        // Fetch is a half-open range, so extend to the start of the day *after*
        // the last visible day to include all-day and late events on that day.
        let upperBound = calendar.date(byAdding: .day, value: 1, to: lastVisible) ?? lastVisible

        loadTask?.cancel()
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let events = try await self.handlers.fetchEvents(first, upperBound)
                guard !Task.isCancelled else { return }
                self.eventsByDay = self.bucket(events)
            } catch {
                guard !Task.isCancelled else { return }
                MeetingBarLogger.calendar.error(
                    "Calendar window month fetch failed: \(String(describing: error), privacy: .private)"
                )
                self.eventsByDay = [:]
            }
            self.isLoading = false
        }
    }

    /// Buckets events by the start-of-day of their `startDate` (v1: a multi-day
    /// event lands only on its start day). Each bucket is sorted all-day-first,
    /// then by start time.
    private func bucket(_ events: [MBEvent]) -> [Date: [MBEvent]] {
        var result: [Date: [MBEvent]] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.startDate)
            result[day, default: []].append(event)
        }
        for key in result.keys {
            result[key]?.sort { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
        }
        return result
    }
}
