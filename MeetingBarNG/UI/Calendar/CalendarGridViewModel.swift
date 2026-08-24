//
//  CalendarGridViewModel.swift
//  MeetingBarNG
//
//  App-target view model for the calendar window. Owns the visible range (a
//  month or a single week, per `CalendarGridMode`), the rendered week grid (via
//  the hostless MonthGridLayout), and the events for that range bucketed by
//  start-of-day. It loads its OWN window of events on demand through an injected
//  fetch closure (resolved by AppDelegate from the calendar repository) — it
//  never touches the main today/tomorrow sync. The SwiftUI view stays
//  presentation-only.
//

import Defaults
import Foundation

/// How the calendar window folds its grid: a full month or a single week.
/// Persisted as a raw string in `Defaults[.calendarGridMode]`.
enum CalendarGridMode: String, CaseIterable, Sendable {
    case month
    case week
}

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
    @Published private(set) var mode: CalendarGridMode
    @Published private(set) var visibleMonth: Date
    /// First day of the visible week (week mode only), already on `firstWeekday`.
    @Published private(set) var visibleWeekStart: Date
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
        now: Date = Date(),
        mode: CalendarGridMode = CalendarGridMode(rawValue: Defaults[.calendarGridMode]) ?? .month
    ) {
        self.handlers = handlers
        self.calendar = calendar
        self.now = now
        self.mode = mode
        self.visibleMonth = MonthGridLayout.startOfMonth(for: now, calendar: calendar)
        self.visibleWeekStart = MonthGridLayout.firstVisibleDayOfWeek(
            containing: now, calendar: calendar
        )
        self.selectedDay = calendar.startOfDay(for: now)
        reload()
    }

    /// A locale-aware calendar so the grid honors the user's chosen language
    /// (which drives `firstWeekday` and the localized weekday/month symbols).
    /// Applies the user's first-weekday override when set (0 = follow locale).
    static func defaultCalendar() -> Calendar {
        var calendar = Calendar.current
        calendar.locale = I18N.instance.locale
        let override = Defaults[.calendarFirstWeekday]
        if override > 0 {
            calendar.firstWeekday = override
        }
        return calendar
    }

    // MARK: - Mode

    /// Switches the fold and persists the choice. The selected day is never lost:
    /// it stays selected and it anchors the newly visible range, so the user
    /// lands on the week (or month) that contains it.
    func setMode(_ newMode: CalendarGridMode) {
        guard newMode != mode else { return }
        mode = newMode
        Defaults[.calendarGridMode] = newMode.rawValue

        let anchor = selectedDay ?? now
        switch newMode {
        case .week:
            visibleWeekStart = MonthGridLayout.firstVisibleDayOfWeek(
                containing: anchor, calendar: calendar
            )
        case .month:
            visibleMonth = MonthGridLayout.startOfMonth(for: anchor, calendar: calendar)
        }
        reload()
    }

    // MARK: - Navigation

    /// Steps back one month in month mode, one week in week mode.
    func goToPrevious() {
        step(-1)
    }

    /// Steps forward one month in month mode, one week in week mode.
    func goToNext() {
        step(1)
    }

    private func step(_ direction: Int) {
        switch mode {
        case .month:
            guard let stepped = calendar.date(
                byAdding: .month, value: direction, to: visibleMonth
            ) else { return }
            visibleMonth = MonthGridLayout.startOfMonth(for: stepped, calendar: calendar)
        case .week:
            guard let stepped = calendar.date(
                byAdding: .day, value: direction * 7, to: visibleWeekStart
            ) else { return }
            visibleWeekStart = MonthGridLayout.firstVisibleDayOfWeek(
                containing: stepped, calendar: calendar
            )
        }
        reload()
    }

    func goToToday() {
        goTo(now)
    }

    /// Jumps the grid to `date` and selects that day.
    ///
    /// Both anchors are moved, not just the one the current mode reads: switching
    /// month/week after a jump should land where the user jumped TO, not back
    /// where the other mode was left. `goToToday()` is this with `now`, kept as
    /// its own entry point because the Today button is a distinct affordance.
    func goTo(_ date: Date) {
        visibleMonth = MonthGridLayout.startOfMonth(for: date, calendar: calendar)
        visibleWeekStart = MonthGridLayout.firstVisibleDayOfWeek(
            containing: date, calendar: calendar
        )
        selectedDay = calendar.startOfDay(for: date)
        reload()
    }

    // MARK: - Selection

    func select(_ day: MonthGridDay) {
        selectedDay = calendar.startOfDay(for: day.date)
    }

    /// The first and last day currently drawn, padding cells included.
    ///
    /// Read off `weeks` rather than recomputed, so it cannot disagree with what
    /// is actually on screen.
    var visibleRange: (start: Date, end: Date)? {
        guard let first = weeks.first?.first?.date,
              let last = weeks.last?.last?.date else { return nil }
        return (first, last)
    }

    /// Moves the keyboard selection, paging the grid when it walks off the edge.
    ///
    /// With nothing selected yet, the first arrow press starts from the anchor of
    /// whatever is on screen rather than from an arbitrary date — pressing Down
    /// on a freshly-opened window should land somewhere the user can see.
    func moveSelection(byDays days: Int) {
        guard let visibleRange else { return }
        let anchor = selectedDay ?? (mode == .month ? visibleMonth : visibleWeekStart)
        let result = CalendarGridNavigation.move(
            from: anchor,
            byDays: days,
            visibleRange: visibleRange,
            calendar: calendar
        )
        if result.requiresPaging {
            // goTo re-anchors BOTH modes and reloads, which is exactly what
            // stepping past the edge needs.
            goTo(result.selectedDay)
        } else {
            selectedDay = result.selectedDay
        }
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

    /// Rebuilds the grid for the visible range and (re)loads its events: the
    /// whole month grid (leading/trailing padding days included) in month mode,
    /// the single visible week in week mode.
    private func reload() {
        let first: Date
        let lastVisible: Date
        switch mode {
        case .month:
            weeks = MonthGridLayout.weeks(
                forMonthContaining: visibleMonth, calendar: calendar, now: now
            )
            first = MonthGridLayout.firstVisibleDay(
                forMonthContaining: visibleMonth, calendar: calendar
            )
            lastVisible = MonthGridLayout.lastVisibleDay(
                forMonthContaining: visibleMonth, calendar: calendar
            )
        case .week:
            weeks = [
                MonthGridLayout.week(containing: visibleWeekStart, calendar: calendar, now: now)
            ]
            first = MonthGridLayout.firstVisibleDayOfWeek(
                containing: visibleWeekStart, calendar: calendar
            )
            lastVisible = MonthGridLayout.lastVisibleDayOfWeek(
                containing: visibleWeekStart, calendar: calendar
            )
        }
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
