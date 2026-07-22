//
//  MonthGridLayout.swift
//  MeetingBarNG
//
//  Pure, hostless month-grid math for the calendar window (Dot parity). Given a
//  date, it produces whole weeks (respecting `Calendar.firstWeekday`) covering
//  that date's month, padded with the leading/trailing days of the adjacent
//  months so every week has exactly seven cells. It also folds down to a SINGLE
//  week (`week(containing:)` + its first/last-day helpers) for the calendar
//  window's week mode. No DateFormatter / locale
//  strings live here — only the grid geometry — so it is trivially testable and
//  compiles into the hostless MeetingBarLogic target.
//

import Foundation

/// A single cell in the month grid.
///
/// `isInMonth` is `false` for the leading/trailing padding days that belong to
/// the previous or next month. `isToday` is set when the cell falls on the same
/// day as the `now` passed to `MonthGridLayout.weeks(...)`.
public struct MonthGridDay: Equatable, Sendable {
    public let date: Date
    public let isInMonth: Bool
    public let isToday: Bool

    public init(date: Date, isInMonth: Bool, isToday: Bool) {
        self.date = date
        self.isInMonth = isInMonth
        self.isToday = isToday
    }
}

public enum MonthGridLayout {
    /// The first moment of the month containing `date` (its day-1 midnight).
    public static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    /// The top-left cell of the grid: the first day of `date`'s month stepped
    /// back to the calendar's `firstWeekday`. This is also the lower bound the
    /// app uses when fetching the month's events.
    public static func firstVisibleDay(forMonthContaining date: Date, calendar: Calendar) -> Date {
        let monthStart = startOfMonth(for: date, calendar: calendar)
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -leading, to: monthStart) ?? monthStart
    }

    /// The bottom-right cell of the grid: the last day of `date`'s month stepped
    /// forward to the end of its week. This is the (inclusive) upper day the app
    /// uses when fetching the month's events.
    public static func lastVisibleDay(forMonthContaining date: Date, calendar: Calendar) -> Date {
        let monthStart = startOfMonth(for: date, calendar: calendar)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let lastDay = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? monthStart
        let weekday = calendar.component(.weekday, from: lastDay)
        let trailing = (calendar.firstWeekday + 6 - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: trailing, to: lastDay) ?? lastDay
    }

    /// The first cell of a SINGLE-week grid: `date`'s own day stepped back to the
    /// calendar's `firstWeekday`. This is the lower bound the app uses when
    /// fetching events in week mode.
    public static func firstVisibleDayOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -leading, to: day) ?? day
    }

    /// The last cell of a SINGLE-week grid: six days after
    /// `firstVisibleDayOfWeek`. This is the (inclusive) upper day the app uses
    /// when fetching events in week mode.
    public static func lastVisibleDayOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let first = firstVisibleDayOfWeek(containing: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: 6, to: first) ?? first
    }

    /// The single seven-day week containing `date` (the week-mode fold).
    ///
    /// Always exactly seven cells, starting on the calendar's `firstWeekday`.
    /// `isInMonth` is computed relative to `date`'s OWN month, so a week that
    /// straddles a month boundary flags each half correctly; `isToday` matches
    /// the day of `now`.
    public static func week(containing date: Date, calendar: Calendar, now: Date) -> [MonthGridDay] {
        let monthComponents = calendar.dateComponents([.year, .month], from: date)
        let first = firstVisibleDayOfWeek(containing: date, calendar: calendar)
        return (0..<7).compactMap { offset in
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: first) else {
                return nil
            }
            let components = calendar.dateComponents([.year, .month], from: dayDate)
            return MonthGridDay(
                date: calendar.startOfDay(for: dayDate),
                isInMonth: components.year == monthComponents.year
                    && components.month == monthComponents.month,
                isToday: calendar.isDate(dayDate, inSameDayAs: now)
            )
        }
    }

    /// Whole weeks (each exactly seven days) covering the month of `date`.
    ///
    /// Leading/trailing padding days from the adjacent months are flagged
    /// `isInMonth == false`; the cell falling on `now` is flagged `isToday`.
    /// Returns 5 or 6 rows depending on how the month lands on the week grid.
    public static func weeks(
        forMonthContaining date: Date,
        calendar: Calendar,
        now: Date
    ) -> [[MonthGridDay]] {
        let monthComponents = calendar.dateComponents(
            [.year, .month], from: startOfMonth(for: date, calendar: calendar)
        )
        let first = firstVisibleDay(forMonthContaining: date, calendar: calendar)
        let last = lastVisibleDay(forMonthContaining: date, calendar: calendar)
        let totalDays = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1

        var weeks: [[MonthGridDay]] = []
        var week: [MonthGridDay] = []
        for offset in 0..<max(totalDays, 0) {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            let components = calendar.dateComponents([.year, .month], from: dayDate)
            let isInMonth = components.year == monthComponents.year
                && components.month == monthComponents.month
            week.append(
                MonthGridDay(
                    date: calendar.startOfDay(for: dayDate),
                    isInMonth: isInMonth,
                    isToday: calendar.isDate(dayDate, inSameDayAs: now)
                )
            )
            if week.count == 7 {
                weeks.append(week)
                week = []
            }
        }
        if !week.isEmpty {
            weeks.append(week)
        }
        return weeks
    }
}
