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
    /// Which connected SOURCE this calendar came from.
    ///
    /// Account name alone stopped being enough once both sources could be
    /// connected: macOS Calendar reports a Google account as a source literally
    /// named "Google", and the direct provider reports the same account by its
    /// address, so the list showed two groups with no way to tell which was
    /// which — or that they were the same calendars twice.
    public let provider: CalendarSourceKind

    public init(
        id: String,
        title: String,
        source: String,
        email: String?,
        provider: CalendarSourceKind = .macOSEventKit
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.email = email
        self.provider = provider
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
    /// Provider and source together — the account name alone is not unique
    /// across sources.
    public let id: String
    /// The raw account/source string this group was keyed on, without the
    /// provider prefix that makes `id` unique. Exposed so callers (and tests)
    /// never have to parse `id` apart.
    public let account: String
    /// The account name to display. Empty when `titleKey` supplies it instead.
    public let title: String
    /// A localization key to use in place of `title`. Non-nil only for the
    /// unnamed source, which renders as "Other" rather than the raw "unknown".
    public let titleKey: String?
    /// Which source these calendars came from. Rendered beside the account name
    /// so "iCloud" and "peter@example.com" are visibly answers to the same
    /// question, and so an EventKit source named "Google" cannot be mistaken for
    /// the direct Google connection.
    public let provider: CalendarSourceKind
    /// Localization key naming `provider` on screen.
    public let providerTitleKey: String
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

        // Grouped by SOURCE and account, not account alone: with both sources
        // connected the same account name can arrive from each, and collapsing
        // them into one group would list a calendar under an account it does not
        // belong to.
        let byAccount = Dictionary(grouping: matching) {
            AccountKey(provider: $0.provider, source: $0.source)
        }

        return byAccount.keys
            .sorted(by: accountsInDisplayOrder)
            .map { key in
                let rows = (byAccount[key] ?? [])
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
                let isUnnamed = key.source == unknownSource
                return CalendarAccountGroup(
                    id: "\(key.provider.rawValue)|\(key.source)",
                    account: key.source,
                    title: isUnnamed ? "" : key.source,
                    titleKey: isUnnamed ? otherSourceTitleKey : nil,
                    provider: key.provider,
                    providerTitleKey: key.provider.titleKey,
                    rows: rows
                )
            }
    }

    /// One account within one source. The pair is the real identity: "Google"
    /// as an EventKit source and a Google address from the direct provider are
    /// different accounts that can hold calendars of the same name.
    private struct AccountKey: Hashable {
        let provider: CalendarSourceKind
        let source: String
    }

    /// Every calendar id currently on screen, in reading order. This is what
    /// "All" selects and "None" clears — the buttons act on what you can see.
    public static func visibleIDs(in groups: [CalendarAccountGroup]) -> [String] {
        groups.flatMap { $0.rows.map(\.id) }
    }

    // MARK: - Ordering and matching

    /// Sources in their canonical order first, then accounts within each.
    /// Keeping each source's accounts contiguous is what makes the list
    /// scannable: "everything my Mac syncs" then "everything Google sends".
    private static func accountsInDisplayOrder(_ lhs: AccountKey, _ rhs: AccountKey) -> Bool {
        guard lhs.provider == rhs.provider else {
            let order = CalendarSourceKind.displayOrder
            return (order.firstIndex(of: lhs.provider) ?? 0)
                < (order.firstIndex(of: rhs.provider) ?? 0)
        }
        return sourcesInDisplayOrder(lhs.source, rhs.source)
    }

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
