//
//  AppSettings.swift
//  MeetingBar
//
//  Value-type snapshot of all user-configurable settings.
//  `AppSettings.current` is the single boundary that reads `Defaults`.
//  Feature logic should consume an `AppSettings` (or sub-struct) by value.
//

import Defaults
import Foundation

// MARK: - Sub-structs

struct CalendarSettings: Equatable {
    var selectedCalendarIDs: [String]
    var eventStoreProvider: EventStoreProvider
}

struct EventDisplaySettings: Equatable {
    var showEventsForPeriod: ShowEventsForPeriod
    var allDayEvents: AlldayEventsAppereance
    var nonAllDayEvents: NonAlldayEventsAppereance
    var declinedEventsAppearance: DeclinedEventsAppereance
    var pastEventsAppearance: PastEventsAppereance
    var personalEventsAppearance: PastEventsAppereance
    var showPendingEvents: PendingEventsAppereance
    var showTentativeEvents: TentativeEventsAppereance
    var filterEventRegexes: [String]
    var dismissedEvents: [ProcessedEvent]
    var ongoingEventVisibility: OngoingEventVisibility
    var showEventMaxTimeUntilEventEnabled: Bool
    var showEventMaxTimeUntilEventThreshold: Int
}

struct StatusBarSettings: Equatable {
    var eventTitleFormat: EventTitleFormat
    var eventTimeFormat: EventTimeFormat
    var eventTitleIconFormat: EventTitleIconFormat
    var statusbarEventTitleLength: Int
    var hideMeetingTitle: Bool
    var showEventEndTime: Bool
}

struct MenuSettings: Equatable {
    var showTimelineInMenu: Bool
    var shortenEventTitle: Bool
    var menuEventTitleLength: Int
    var showEventDetails: Bool
    var showMeetingServiceIcon: Bool
    var showEventCalendarColor: Bool
    /// When true, reference links found in an event's invite (Figma, Notion,
    /// GitHub, Google Docs/Sheets/Slides, generic URLs) are surfaced as clickable
    /// rows in the event detail submenu. ON by default.
    var showMeetingPrepLinks: Bool
    /// When true, the menu's day list starts at "now" — meetings that ended more
    /// than the grace period ago are hidden. When false, the full day is shown.
    var hideFinishedEventsInMenu: Bool
    /// Minutes before a meeting starts at which its action control becomes a
    /// full-strength call to action. Lives here rather than being read from
    /// `Defaults` inside `MenuBuilder`, which reads every display setting off
    /// this snapshot, so the classic menu's meeting card and the panel's agree.
    var eventActionHighlightMinutes: Int
    /// When true, Apple Reminders due today are shown in the menu's Today section.
    /// OFF by default (see `Defaults[.showRemindersInMenu]`).
    var showRemindersInMenu: Bool
    /// When true, overdue reminders are included alongside those due today.
    var remindersIncludeOverdue: Bool
    // Composable menu dropdown module toggles (MeetingBarNG). greeting/timeline
    // reuse showGreetingInMenu / showTimelineInMenu; these cover the rest.
    /// When true, the next/current meeting control card is shown.
    var showMeetingControlInMenu: Bool
    /// When true, the today/tomorrow agenda (dates + reminders) is shown.
    var showAgendaInMenu: Bool
    /// When true, the join / create / quick-actions section is shown.
    var showJoinSectionInMenu: Bool
    /// When true, the saved bookmarks section is shown.
    var showBookmarksInMenu: Bool
    /// Compact month grid in the dropdown. OFF by default.
    var showCalendarInMenu: Bool
}

struct NotificationSettings: Equatable {
    var joinEventNotification: Bool
    var joinEventNotificationTime: TimeBeforeEvent
    var endOfEventNotification: Bool
    var endOfEventNotificationTime: TimeBeforeEventEnd
    var fullscreenNotification: Bool
    var fullscreenNotificationTime: TimeBeforeEvent
    var fullscreenNotificationsForEventsWithoutMeetingLink: Bool
}

struct MeetingSettings: Equatable {
    var createMeetingService: CreateMeetingServices
    var createMeetingServiceUrl: String
    var bookmarks: [Bookmark]
    var browsers: [Browser]
    var defaultBrowser: Browser
    var browserForCreateMeeting: Browser
    /// Unified per-provider browser preferences (keyed by provider ID).
    /// Replaces the individual meetBrowser/zoomBrowser/… fields.
    var providerBrowsers: [String: Browser]
    var providerOpeningModes: [String: String]
}

struct AdvancedSettings: Equatable {
    var automaticEventJoin: Bool
    var automaticEventJoinTime: TimeBeforeEvent
    var runJoinEventScript: Bool
    var joinEventScriptLocation: URL?
    var joinEventScript: String
    var runEventStartScript: Bool
    var eventStartScriptLocation: URL?
    var eventStartScriptTime: TimeBeforeEvent
    var eventStartScript: String
    var customRegexes: [String]
}

// MARK: - Root

struct AppSettings: Equatable {
    var calendar: CalendarSettings
    var events: EventDisplaySettings
    var statusBar: StatusBarSettings
    var menu: MenuSettings
    var notifications: NotificationSettings
    var meetings: MeetingSettings
    var advanced: AdvancedSettings
}

enum StatusBarTitleFormatMigration {
    @MainActor
    static func migrateDefaultsIfNeeded() {
        guard Defaults[.hideMeetingTitle] else { return }

        if Defaults[.eventTitleFormat] == .show {
            Defaults[.eventTitleFormat] = .generic
        }
        Defaults[.hideMeetingTitle] = false
    }
}

/// MeetingBarNG changed the time-format default from 24-hour to 12-hour. To
/// avoid silently flipping people who were already running the app on the old
/// default, this pins any EXISTING install (already past onboarding) that never
/// explicitly chose a format back to 24-hour. New installs — and anyone who
/// picked a value — are left alone, so only fresh installs get the 12-hour default.
enum TimeFormatDefaultMigration {
    /// Pure decision: only an existing install (already past onboarding) that
    /// never explicitly chose a time format is pinned to the previous 24-hour
    /// default. New installs — and anyone who picked a value — keep theirs (so
    /// new installs get the 12-hour key default).
    static func shouldPinToMilitary(onboardingCompleted: Bool, hasStoredTimeFormat: Bool) -> Bool {
        onboardingCompleted && !hasStoredTimeFormat
    }

    @MainActor
    static func migrateDefaultsIfNeeded() {
        guard !Defaults[.timeFormatDefaultMigrated] else { return }
        Defaults[.timeFormatDefaultMigrated] = true

        // A nil raw value means the user never changed the picker.
        let hasStored = UserDefaults.standard.object(forKey: "timeFormat") != nil
        if shouldPinToMilitary(
            onboardingCompleted: Defaults[.onboardingCompleted],
            hasStoredTimeFormat: hasStored
        ) {
            Defaults[.timeFormat] = .military
        }
    }
}

/// MeetingBarNG reset the app version to a sub-1.0 scheme. Because the "What's
/// new" gate is a strictly-greater version compare, an install carrying an
/// inherited upstream value (4.x/5.x) would never see the changelog again. This
/// one-time migration resets such values so the 0.1.0 notes can surface, while
/// leaving genuine sub-1.0 (MeetingBarNG) values alone.
enum ChangelogResetMigration {
    /// Pure decision: reset only when the stored value is a >= 1.0 (inherited)
    /// version. nil / sub-1.0 / unparseable values are left as-is.
    static func shouldReset(storedLastRevised: String?) -> Bool {
        guard let stored = storedLastRevised,
              let majorText = stored.split(separator: ".").first,
              let major = Int(majorText)
        else { return false }
        return major >= 1
    }

    @MainActor
    static func migrateDefaultsIfNeeded() {
        guard !Defaults[.changelogResetMigrated] else { return }
        Defaults[.changelogResetMigrated] = true

        let stored = UserDefaults.standard.string(forKey: "lastRevisedVersionInChangelog")
        if shouldReset(storedLastRevised: stored) {
            Defaults[.lastRevisedVersionInChangelog] = "0.0.0"
        }
    }
}

/// Retires the "Time next to the title" picker (`eventTimeFormat`) without
/// dropping anybody's answer to it.
///
/// The picker offered show / show-under-title / hide, was read only by the
/// classic status-bar path, and sat directly above a composer that ignored it.
/// Both of its capabilities now live in clearer places on the Menu Bar pane:
/// showing the time is the presence of the **Countdown** block, and
/// show-under-title is **Two lines**. So this runs once per install and:
///
///   • seeds the block list from the classic settings (`derivedFromLegacy`,
///     which appends a Countdown block for anyone who was NOT on `.hide`), and
///   • turns Two lines on for anyone who was on `.show_under_title`.
///
/// Someone who had already composed a menu bar is left completely alone: the
/// picker was already inert for them, so honouring it now would change a menu
/// bar they never saw it affect. The decision itself is hostless and tested
/// (`MenuBarTimeFormatMigration`); this is only the Defaults plumbing.
enum MenuBarTimeFormatDefaultsMigration {
    @MainActor
    static func migrateDefaultsIfNeeded() {
        guard !Defaults[.menuBarTimeFormatMigrated] else { return }
        Defaults[.menuBarTimeFormatMigrated] = true

        let plan = MenuBarTimeFormatMigration.plan(
            storedTokens: Defaults[.menuBarTokens],
            legacyTokens: MenuBarComposition.derivedFromLegacy.tokens.map(\.rawValue),
            timeUnderTitle: Defaults[.eventTimeFormat] == .show_under_title
        )
        if let tokens = plan.tokens {
            Defaults[.menuBarTokens] = tokens
        }
        if let twoLines = plan.twoLines {
            Defaults[.menuBarTwoLineLayout] = twoLines
        }
        MeetingBarLogger.preferences.info(
            "Migrated eventTimeFormat: seeded \(plan.tokens?.count ?? 0, privacy: .public) blocks"
        )
    }
}

// MARK: - Defaults factory

extension AppSettings {
    /// The single boundary that reads `Defaults` for app-level feature logic.
    /// Other code should receive `AppSettings` (or sub-structs) by value.
    @MainActor
    static var current: AppSettings {
        let eventTitleFormat = Defaults[.eventTitleFormat]

        return AppSettings(
            calendar: CalendarSettings(
                selectedCalendarIDs: Defaults[.selectedCalendarIDs],
                eventStoreProvider: Defaults[.eventStoreProvider]
            ),
            events: EventDisplaySettings(
                showEventsForPeriod: Defaults[.showEventsForPeriod],
                allDayEvents: Defaults[.allDayEvents],
                nonAllDayEvents: Defaults[.nonAllDayEvents],
                declinedEventsAppearance: Defaults[.declinedEventsAppereance],
                pastEventsAppearance: Defaults[.pastEventsAppereance],
                personalEventsAppearance: Defaults[.personalEventsAppereance],
                showPendingEvents: Defaults[.showPendingEvents],
                showTentativeEvents: Defaults[.showTentativeEvents],
                filterEventRegexes: Defaults[.filterEventRegexes],
                dismissedEvents: Defaults[.dismissedEvents],
                ongoingEventVisibility: Defaults[.ongoingEventVisibility],
                showEventMaxTimeUntilEventEnabled: Defaults[.showEventMaxTimeUntilEventEnabled],
                showEventMaxTimeUntilEventThreshold: Defaults[.showEventMaxTimeUntilEventThreshold]
            ),
            statusBar: StatusBarSettings(
                eventTitleFormat: eventTitleFormat,
                eventTimeFormat: Defaults[.eventTimeFormat],
                eventTitleIconFormat: Defaults[.eventTitleIconFormat],
                statusbarEventTitleLength: Defaults[.statusbarEventTitleLength],
                hideMeetingTitle: eventTitleFormat == .generic,
                showEventEndTime: Defaults[.showEventEndTime]
            ),
            menu: MenuSettings(
                showTimelineInMenu: Defaults[.showTimelineInMenu],
                shortenEventTitle: Defaults[.shortenEventTitle],
                menuEventTitleLength: Defaults[.menuEventTitleLength],
                showEventDetails: Defaults[.showEventDetails],
                showMeetingServiceIcon: Defaults[.showMeetingServiceIcon],
                showEventCalendarColor: Defaults[.showEventCalendarColor],
                showMeetingPrepLinks: Defaults[.showMeetingPrepLinks],
                hideFinishedEventsInMenu: Defaults[.hideFinishedEventsInMenu],
                eventActionHighlightMinutes: Defaults[.eventActionHighlightMinutes],
                showRemindersInMenu: Defaults[.showRemindersInMenu],
                remindersIncludeOverdue: Defaults[.remindersIncludeOverdue],
                showMeetingControlInMenu: Defaults[.showMeetingControlInMenu],
                showAgendaInMenu: Defaults[.showAgendaInMenu],
                showJoinSectionInMenu: Defaults[.showJoinSectionInMenu],
                showBookmarksInMenu: Defaults[.showBookmarksInMenu],
                showCalendarInMenu: Defaults[.showCalendarInMenu]
            ),
            notifications: NotificationSettings(
                joinEventNotification: Defaults[.joinEventNotification],
                joinEventNotificationTime: Defaults[.joinEventNotificationTime],
                endOfEventNotification: Defaults[.endOfEventNotification],
                endOfEventNotificationTime: Defaults[.endOfEventNotificationTime],
                fullscreenNotification: Defaults[.fullscreenNotification],
                fullscreenNotificationTime: Defaults[.fullscreenNotificationTime],
                fullscreenNotificationsForEventsWithoutMeetingLink:
                    Defaults[.fullscreenNotificationsForEventsWithoutMeetingLink]
            ),
            meetings: MeetingSettings(
                createMeetingService: Defaults[.createMeetingService],
                createMeetingServiceUrl: Defaults[.createMeetingServiceUrl],
                bookmarks: Defaults[.bookmarks],
                browsers: Defaults[.browsers],
                defaultBrowser: Defaults[.defaultBrowser],
                browserForCreateMeeting: Defaults[.browserForCreateMeeting],
                providerBrowsers: Defaults[.providerBrowsers],
                providerOpeningModes: Defaults[.providerOpeningModes]
            ),
            advanced: AdvancedSettings(
                automaticEventJoin: Defaults[.automaticEventJoin],
                automaticEventJoinTime: Defaults[.automaticEventJoinTime],
                runJoinEventScript: Defaults[.runJoinEventScript],
                joinEventScriptLocation: Defaults[.joinEventScriptLocation],
                joinEventScript: Defaults[.joinEventScript],
                runEventStartScript: Defaults[.runEventStartScript],
                eventStartScriptLocation: Defaults[.eventStartScriptLocation],
                eventStartScriptTime: Defaults[.eventStartScriptTime],
                eventStartScript: Defaults[.eventStartScript],
                customRegexes: Defaults[.customRegexes]
            )
        )
    }

    /// Zero-state `AppSettings` whose values mirror the hard-coded defaults in
    /// `Extensions/DefaultsKeys.swift`. Used by tests and value renderers that
    /// need clean-install behavior without reading `Defaults`.
    static var empty: AppSettings {
        AppSettings(
            calendar: CalendarSettings(
                selectedCalendarIDs: [], eventStoreProvider: .macOSEventKit),
            events: EventDisplaySettings(
                showEventsForPeriod: .today,
                allDayEvents: .show,
                nonAllDayEvents: .show,
                declinedEventsAppearance: .strikethrough,
                pastEventsAppearance: .show_inactive,
                personalEventsAppearance: .show_active,
                showPendingEvents: .show,
                showTentativeEvents: .show,
                filterEventRegexes: [],
                dismissedEvents: [],
                ongoingEventVisibility: .showTenMinBeforeNext,
                showEventMaxTimeUntilEventEnabled: false,
                showEventMaxTimeUntilEventThreshold: 60
            ),
            statusBar: StatusBarSettings(
                eventTitleFormat: .show,
                eventTimeFormat: .show,
                eventTitleIconFormat: .none,
                statusbarEventTitleLength: statusbarEventTitleLengthLimits.max,
                hideMeetingTitle: false,
                showEventEndTime: true
            ),
            menu: MenuSettings(
                showTimelineInMenu: true,
                shortenEventTitle: true,
                menuEventTitleLength: 50,
                showEventDetails: false,
                showMeetingServiceIcon: true,
                showEventCalendarColor: true,
                showMeetingPrepLinks: true,
                hideFinishedEventsInMenu: true,
                eventActionHighlightMinutes: 2,
                showRemindersInMenu: false,
                remindersIncludeOverdue: true,
                showMeetingControlInMenu: true,
                showAgendaInMenu: true,
                showJoinSectionInMenu: true,
                showBookmarksInMenu: true,
                showCalendarInMenu: false
            ),
            notifications: NotificationSettings(
                joinEventNotification: true,
                joinEventNotificationTime: .atStart,
                endOfEventNotification: true,
                endOfEventNotificationTime: .atEnd,
                fullscreenNotification: false,
                fullscreenNotificationTime: .atStart,
                fullscreenNotificationsForEventsWithoutMeetingLink: false
            ),
            meetings: MeetingSettings(
                createMeetingService: .zoom,
                createMeetingServiceUrl: "",
                bookmarks: [],
                browsers: [],
                defaultBrowser: Browser(
                    name: "Default Browser", path: "", arguments: "", deletable: false),
                browserForCreateMeeting: systemDefaultBrowser,
                providerBrowsers: [:],
                providerOpeningModes: [:]
            ),
            advanced: AdvancedSettings(
                automaticEventJoin: false,
                automaticEventJoinTime: .atStart,
                runJoinEventScript: false,
                joinEventScriptLocation: nil,
                joinEventScript: "",
                runEventStartScript: false,
                eventStartScriptLocation: nil,
                eventStartScriptTime: .atStart,
                eventStartScript: eventStartScriptPlaceholder,
                customRegexes: []
            )
        )
    }
}

// MARK: - Defaults write boundary

extension AppSettings {
    @MainActor
    static func setEventStoreProvider(_ provider: EventStoreProvider) {
        migrateSelectedCalendarsByProviderIfNeeded()
        Defaults[.eventStoreProvider] = provider
        Defaults[.selectedCalendarIDs] = selectedCalendarIDs(for: provider)
    }

    @MainActor
    static func clearSelectedCalendars() {
        migrateSelectedCalendarsByProviderIfNeeded()
        var selections = Defaults[.selectedCalendarIDsByProvider]
        selections[Defaults[.eventStoreProvider].rawValue] = []
        Defaults[.selectedCalendarIDsByProvider] = selections
        Defaults[.selectedCalendarIDs] = []
    }

    @MainActor
    static func toggleMeetingTitleVisibility() {
        Defaults[.eventTitleFormat] = Defaults[.eventTitleFormat] == .show ? .generic : .show
        Defaults[.hideMeetingTitle] = false
    }

    @MainActor
    static func setCalendarSelection(id: String, selected: Bool) {
        migrateSelectedCalendarsByProviderIfNeeded()
        let providerKey = Defaults[.eventStoreProvider].rawValue
        var selections = Defaults[.selectedCalendarIDsByProvider]
        var selectedIDs = selections[providerKey] ?? []

        if selected {
            if !selectedIDs.contains(id) {
                selectedIDs.append(id)
            }
        } else {
            selectedIDs.removeAll { $0 == id }
        }

        selections[providerKey] = selectedIDs
        Defaults[.selectedCalendarIDsByProvider] = selections
        Defaults[.selectedCalendarIDs] = selectedIDs
    }

    @MainActor
    static func selectedCalendarIDs(for provider: EventStoreProvider) -> [String] {
        migrateSelectedCalendarsByProviderIfNeeded()
        return Defaults[.selectedCalendarIDsByProvider][provider.rawValue] ?? []
    }

    @MainActor
    static func migrateSelectedCalendarsByProviderIfNeeded() {
        guard !Defaults[.selectedCalendarIDsByProviderMigrated] else { return }

        let providerKey = Defaults[.eventStoreProvider].rawValue
        var selections = Defaults[.selectedCalendarIDsByProvider]
        if selections[providerKey] == nil {
            selections[providerKey] = Defaults[.selectedCalendarIDs]
        }

        Defaults[.selectedCalendarIDsByProvider] = selections
        Defaults[.selectedCalendarIDsByProviderMigrated] = true
    }

    @MainActor
    static func completeOnboarding() {
        Defaults[.onboardingCompleted] = true
    }

    @MainActor
    static func acknowledgeCurrentChangelog() {
        Defaults[.lastRevisedVersionInChangelog] = Defaults[.appVersion]
    }

    @MainActor
    static func dismissEvent(_ event: MBEvent) {
        dismissEvent(
            ProcessedEvent(
                id: event.id,
                lastModifiedDate: event.lastModifiedDate,
                eventEndDate: event.endDate
            )
        )
    }

    @MainActor
    static func dismissEvent(_ event: ProcessedEvent) {
        Defaults[.dismissedEvents].append(event)
    }

    @MainActor
    static func undismissEvent(id: String) {
        Defaults[.dismissedEvents].removeAll { $0.id == id }
    }

    @MainActor
    static func clearDismissedEvents() {
        Defaults[.dismissedEvents] = []
    }

    @MainActor
    static func replaceDismissedEvents(_ events: [ProcessedEvent]) {
        Defaults[.dismissedEvents] = events
    }

    @MainActor
    static func refreshDismissedEvents(using currentEvents: [MBEvent]) {
        let dismissedEvents: [ProcessedEvent] = Defaults[.dismissedEvents].compactMap { dismissedEvent in
            guard
                let event = currentEvents.first(where: { $0.id == dismissedEvent.id }),
                event.endDate.timeIntervalSinceNow > 0
            else {
                return nil
            }

            // Preserve the lastModifiedDate captured at dismissal time. Refreshing
            // only prunes ended events and refreshes the end date; it must not
            // strip the modified-date metadata, otherwise a dismissed event could
            // never be re-surfaced when the underlying event changes.
            return ProcessedEvent(
                id: dismissedEvent.id,
                lastModifiedDate: dismissedEvent.lastModifiedDate,
                eventEndDate: event.endDate
            )
        }

        replaceDismissedEvents(dismissedEvents)
    }
}
