//
//  CalendarListPresentation.swift
//  MeetingBarNG
//
//  Hostless shaping for the Calendars pane's "Calendars to show" list
//  (Preferences UX overhaul, Phase 2).
//
//  The shipping list was `Dictionary(grouping: calendars, by: \.source)` rendered
//  straight into sections, which is why the app could list "Family" twice with no
//  way to tell the two apart: the account was a section header the user had to
//  correlate by position, and two calendars sharing a name inside — or across —
//  accounts were indistinguishable. Three rules fix it, and all three are pure
//  functions of the calendar list, so they are tested without a host app:
//
//    1. Group by account, named accounts first, the unnamed ("unknown") source
//       last under a localized "Other".
//    2. Show the account email UNDER a calendar name that occurs more than once
//       anywhere in the list — and nowhere else, so unambiguous rows stay clean.
//    3. Filter by name, account or address, keeping the disambiguator visible:
//       duplicates are detected against the FULL list, never the filtered one,
//       because searching is exactly what a user does when two names collide.
//
//  Values are plain strings rather than the app's `MBCalendar` (which carries an
//  `NSColor`), so this file compiles into MeetingBarLogic.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

/// One calendar, reduced to what the picker needs to group, disambiguate and
/// search it. The app maps `MBCalendar` onto this; colour stays in the view.
public struct CalendarPickerItem: Hashable, Sendable {
    public let id: String
    public let title: String
    /// The account the calendar belongs to (`MBCalendar.source`).
    public let source: String
    /// The account address, when macOS exposes one.
    public let email: String?

    public init(id: String, title: String, source: String, email: String?) {
        self.id = id
        self.title = title
        self.source = source
        self.email = email
    }
}

/// One checkbox row.
public struct CalendarPickerRow: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// The account address, present ONLY when this calendar's name is shared
    /// with another calendar in the list. `nil` for unambiguous names, and for
    /// ambiguous ones whose account has no address — nothing is invented.
    public let subtitle: String?
}

/// One account's worth of rows.
public struct CalendarAccountGroup: Hashable, Sendable, Identifiable {
    /// The raw source string, which is also the group's stable identity.
    public let id: String
    /// The account name to display. Empty when `titleKey` supplies it instead.
    public let title: String
    /// A localization key to use in place of `title`. Non-nil only for the
    /// unnamed source, which renders as "Other" rather than the raw "unknown".
    public let titleKey: String?
    public let rows: [CalendarPickerRow]
}

public enum CalendarListPresentation {
    /// `MBCalendar` substitutes this when EventKit hands over no source name.
    public static let unknownSource = "unknown"
    /// What the unnamed source is called on screen.
    public static let otherSourceTitleKey = "preferences_calendars_source_other"

    /// The grouped, disambiguated, filtered list, in display order.
    ///
    /// - Parameter query: free text matched against calendar name, account name
    ///   and account address. Blank shows everything.
    public static func groups(
        for items: [CalendarPickerItem],
        query: String = ""
    ) -> [CalendarAccountGroup] {
        // Ambiguity is a property of the WHOLE list, not of what survives the
        // filter — otherwise searching "family" would hide the very address that
        // tells the two Familys apart.
        var titleCounts: [String: Int] = [:]
        for item in items {
            titleCounts[TextNormalization.fold(item.title), default: 0] += 1
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = trimmedQuery.isEmpty
            ? items
            : items.filter { matches($0, foldedQuery: TextNormalization.fold(trimmedQuery)) }

        let bySource = Dictionary(grouping: matching, by: \.source)

        return bySource.keys
            .sorted(by: sourcesInDisplayOrder)
            .map { source in
                let rows = (bySource[source] ?? [])
                    .sorted(by: itemsInDisplayOrder)
                    .map { item in
                        CalendarPickerRow(
                            id: item.id,
                            title: item.title,
                            subtitle: (titleCounts[TextNormalization.fold(item.title)] ?? 0) > 1
                                ? item.email
                                : nil
                        )
                    }
                let isUnnamed = source == unknownSource
                return CalendarAccountGroup(
                    id: source,
                    title: isUnnamed ? "" : source,
                    titleKey: isUnnamed ? otherSourceTitleKey : nil,
                    rows: rows
                )
            }
    }

    /// Every calendar id currently on screen, in reading order. This is what
    /// "All" selects and "None" clears — the buttons act on what you can see.
    public static func visibleIDs(in groups: [CalendarAccountGroup]) -> [String] {
        groups.flatMap { $0.rows.map(\.id) }
    }

    // MARK: - Ordering and matching

    /// Named accounts alphabetically, the unnamed source always last: "Other" is
    /// a leftovers bucket, and a leftovers bucket that sorts into the middle
    /// reads like a real account.
    private static func sourcesInDisplayOrder(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == unknownSource || rhs == unknownSource {
            return rhs == unknownSource && lhs != unknownSource
        }
        let folded = TextNormalization.fold(lhs).compare(TextNormalization.fold(rhs))
        return folded == .orderedSame ? lhs < rhs : folded == .orderedAscending
    }

    /// Calendars by name, then by id so the order never shuffles between renders.
    private static func itemsInDisplayOrder(
        _ lhs: CalendarPickerItem,
        _ rhs: CalendarPickerItem
    ) -> Bool {
        let folded = TextNormalization.fold(lhs.title).compare(TextNormalization.fold(rhs.title))
        return folded == .orderedSame ? lhs.id < rhs.id : folded == .orderedAscending
    }

    private static func matches(_ item: CalendarPickerItem, foldedQuery: String) -> Bool {
        let haystack = [item.title, item.source, item.email ?? ""]
        return haystack.contains { TextNormalization.fold($0).contains(foldedQuery) }
    }
}
