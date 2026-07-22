//
//  DefaultsKeys.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  add persistence keys for the composable menu bar, the composable menu
//  dropdown (dropdownModuleOrder + per-module enabled bools), and Apple
//  Reminders in the menu; add the calendar-window keys (calendarGridMode,
//  dimWeekendsInCalendar); add the SwiftUI dropdown-panel flag
//  (useSwiftUIDropdown, now defaulting ON — the panel is the shipping dropdown
//  and the key is the escape hatch back to the classic NSMenu);
//  remove the StoreKit patronage keys (patronageDuration,
//  processedPatronageTransactionIDs, isInstalledFromAppStore) along with the
//  removed patronage feature.
//
@preconcurrency import Defaults
import Foundation

extension Defaults.Keys {
    // General
    static let appVersion = Key<String>("appVersion", default: "0.1.0")
    // Floor below the first MeetingBarNG release so its What's New surfaces on a
    // fresh install; ChangelogResetMigration resets inherited upstream 4.x/5.x
    // values on existing installs so the strictly-greater gate can fire again.
    static let lastRevisedVersionInChangelog = Key<String>(
        "lastRevisedVersionInChangelog", default: "0.0.0")
    static let changelogResetMigrated = Key<Bool>("changelogResetMigrated", default: false)

    static let selectedCalendarIDs = Key<[String]>("selectedCalendarIDs", default: [])
    static let selectedCalendarIDsByProvider = Key<[String: [String]]>(
        "selectedCalendarIDsByProvider",
        default: [:]
    )
    static let selectedCalendarIDsByProviderMigrated = Key<Bool>(
        "selectedCalendarIDsByProviderMigrated",
        default: false
    )
    static let timeFormatDefaultMigrated = Key<Bool>(
        "timeFormatDefaultMigrated",
        default: false
    )
    static let eventStoreProvider = Key<EventStoreProvider>(
        "eventStoreProvider", default: .macOSEventKit)

    static let onboardingCompleted = Key<Bool>("onboardingCompleted", default: false)

    static let showEventsForPeriod = Key<ShowEventsForPeriod>(
        "showEventsForPeriod", default: .today)
    static let joinEventNotification = Key<Bool>("joinEventNotification", default: true)
    static let joinEventNotificationTime = Key<TimeBeforeEvent>(
        "joinEventNotificationTime", default: .atStart)

    static let endOfEventNotification = Key<Bool>("endOfEventNotification", default: true)
    static let endOfEventNotificationTime = Key<TimeBeforeEventEnd>(
        "endOfEventNotificationTime", default: .atEnd)

    static let fullscreenNotification = Key<Bool>("fullscreenNotification", default: false)
    static let fullscreenNotificationTime = Key<TimeBeforeEvent>(
        "fullscreenNotificationTime", default: .atStart)
    static let fullscreenNotificationsForEventsWithoutMeetingLink = Key<Bool>(
        "fullscreenNotificationsForEventsWithoutMeetingLink",
        default: false
    )
    static let processedEventsForFullscreenNotification = Key<[ProcessedEvent]>(
        "processedEventsForFullscreenNotification", default: [])

    static let preferredLanguage = Key<AppLanguage>("preferredLanguage", default: .system)

    // Status Bar Appearance
    static let eventTitleFormat = Key<EventTitleFormat>("eventTitleFormat", default: .show)
    static let eventTimeFormat = Key<EventTimeFormat>("eventTimeFormat", default: .show)

    static let eventTitleIconFormat = Key<EventTitleIconFormat>(
        "eventTitleIconFormat", default: .none)
    static let statusbarEventTitleLength = Key<Int>(
        "statusbarEventTitleLength", default: statusbarEventTitleLengthLimits.max)

    static let hideMeetingTitle = Key<Bool>("hideMeetingTitle", default: false)
    static let dismissedEvents = Key<[ProcessedEvent]>("dismissedEvents", default: [])

    static let ongoingEventVisibility = Key<OngoingEventVisibility>(
        "ongoingEventVisibility", default: .showTenMinBeforeNext)

    // Composable menu bar (MeetingBarNG)
    // Ordered `MenuBarTokenKind` raw values. Empty ⇒ classic status-bar path,
    // so existing installs are unchanged until the user opts in. Stored as
    // strings so unknown/renamed tokens degrade gracefully.
    static let menuBarTokens = Key<[String]>("menuBarTokens", default: [])
    static let menuBarCountdownStyle = Key<String>(
        "menuBarCountdownStyle", default: CountdownStyle.full.rawValue)
    static let menuBarDateStyle = Key<String>(
        "menuBarDateStyle", default: MenuBarDateStyle.medium.rawValue)
    static let menuBarProgressStyle = Key<String>(
        "menuBarProgressStyle", default: MenuBarProgressStyle.day.rawValue)
    // World-clock token: time zone stored as its identifier (TimeZone isn't
    // trivially Defaults.Serializable) and reconstructed with a `.current` fallback.
    static let menuBarWorldClockTimeZone = Key<String>(
        "menuBarWorldClockTimeZone", default: TimeZone.current.identifier)
    static let menuBarWorldClockLabel = Key<String>("menuBarWorldClockLabel", default: "")
    // "One line / Two lines" on the Menu Bar pane — the capability the retired
    // `eventTimeFormat` control carried as `.show_under_title`. On two lines the
    // meeting title is the headline and every other block sits under it.
    static let menuBarTwoLineLayout = Key<Bool>("menuBarTwoLineLayout", default: false)
    // Bookkeeping for `MenuBarTimeFormatDefaultsMigration` (AppSettings.swift):
    // seeds the block list from the classic settings once, and carries
    // `eventTimeFormat` over to the Countdown block / two-line layout.
    static let menuBarTimeFormatMigrated = Key<Bool>(
        "menuBarTimeFormatMigrated",
        default: false
    )

    // World-clock panel (MeetingBarNG): the multi-zone panel window's chosen
    // zones, stored as time-zone identifiers (labels are derived at the host
    // boundary via `WorldClockPanelPolicy.cityLabel`). Defaults to the local
    // zone so a fresh panel shows something useful.
    static let worldClockPanelZones = Key<[String]>(
        "worldClockPanelZones", default: [TimeZone.current.identifier])

    // Day-summary greeting header (top of the dropdown). Name is optional —
    // empty falls back to NSFullUserName() at the host boundary, then to a
    // name-less greeting.
    static let showGreetingInMenu = Key<Bool>("showGreetingInMenu", default: true)
    static let greetingName = Key<String>("greetingName", default: "")

    // Composable menu dropdown (MeetingBarNG)
    // Ordered `DropdownModule` raw values driving the dropdown's section order.
    // Empty ⇒ standard order (`DropdownCompositionPolicy` reappends any missing
    // modules), so existing installs render exactly as before. Stored as strings
    // so unknown/renamed modules degrade gracefully.
    static let dropdownModuleOrder = Key<[String]>(
        "dropdownModuleOrder", default: DropdownComposition.standard.modules.map(\.rawValue))
    // Per-module enabled state. greeting/timeline reuse the existing keys above
    // (showGreetingInMenu / showTimelineInMenu); these cover the rest. All
    // default true so the dropdown looks unchanged until the user customizes it.
    // The custom SwiftUI dropdown panel (MeetingBarNG) is now the default
    // dropdown: it reached functional parity with the NSMenu and goes past it
    // (hover affordances, inline detail expansion, keyboard navigation) in ways
    // an NSMenu structurally cannot. The classic NSMenu remains behind this
    // switch as a fallback for anyone who hits a problem with the panel.
    static let useSwiftUIDropdown = Key<Bool>("useSwiftUIDropdown", default: true)

    static let showMeetingControlInMenu = Key<Bool>("showMeetingControlInMenu", default: true)
    static let showAgendaInMenu = Key<Bool>("showAgendaInMenu", default: true)
    static let showJoinSectionInMenu = Key<Bool>("showJoinSectionInMenu", default: true)
    static let showBookmarksInMenu = Key<Bool>("showBookmarksInMenu", default: true)

    // Calendar window (MeetingBarNG). The month ⇄ week fold, stored as a
    // `CalendarGridMode` raw value so an unknown/renamed value degrades to the
    // month grid. Weekend dimming is on by default so the work week stands out.
    static let calendarGridMode = Key<String>(
        "calendarGridMode", default: CalendarGridMode.month.rawValue)
    static let dimWeekendsInCalendar = Key<Bool>("dimWeekendsInCalendar", default: true)

    // Preferences window UI state (MeetingBarNG, Phase 2 IA restructure).
    // IDs of `PreferencesDisclosure` sections the user has opened. Persisted
    // rather than reset per launch: re-collapsing a disclosure someone
    // deliberately opened is the app deciding it knows better, and the whole
    // point of putting depth behind disclosures is that reaching it once is
    // enough. Stored as IDs so an unknown/renamed section degrades to closed.
    static let preferencesExpandedDisclosures = Key<[String]>(
        "preferencesExpandedDisclosures", default: [])

    // Menu Appearance
    static let showTimelineInMenu = Key<Bool>("showTimelineInMenu", default: true)
    // When on, the menu's day list starts at "now" (hides finished events).
    static let hideFinishedEventsInMenu = Key<Bool>("hideFinishedEventsInMenu", default: true)
    // if the event title in the menu should be shortened or not -> the length will be stored in field menuEventTitleLength
    static let shortenEventTitle = Key<Bool>("shortenEventTitle", default: true)
    static let menuEventTitleLength = Key<Int>("menuEventTitleLength", default: 50)

    static let showEventDetails = Key<Bool>("showEventDetails", default: false)
    static let showMeetingServiceIcon = Key<Bool>("showMeetingServiceIcon", default: true)
    static let showEventCalendarColor = Key<Bool>("showEventCalendarColor", default: true)

    // Meeting-prep links (Dot parity, MeetingBarNG). Surfaces the useful links
    // buried in an invite (Figma, Notion, GitHub, Google Docs/Sheets/Slides,
    // generic URLs) as clickable rows in the event detail submenu, excluding the
    // meeting-join link. ON by default so the links appear without opt-in.
    static let showMeetingPrepLinks = Key<Bool>("showMeetingPrepLinks", default: true)

    // Apple Reminders in the menu (MeetingBarNG). OFF by default so existing
    // installs never see a surprise permission prompt — the Reminders access
    // request only fires when the user turns this on in Preferences.
    static let showRemindersInMenu = Key<Bool>("showRemindersInMenu", default: false)
    static let remindersIncludeOverdue = Key<Bool>("remindersIncludeOverdue", default: true)

    // Collapse the same underlying event when it appears on more than one
    // selected calendar/account (or as duplicate EventKit copies). On by
    // default so the dropdown stops showing visible duplicates; opt out to see
    // every calendar's copy.
    static let deduplicateEvents = Key<Bool>("deduplicateEvents", default: true)

    static let declinedEventsAppereance = Key<DeclinedEventsAppereance>(
        "declinedEventsAppereance", default: .strikethrough)
    static let pastEventsAppereance = Key<PastEventsAppereance>(
        "pastEventsAppereance", default: .show_inactive)
    static let personalEventsAppereance = Key<PastEventsAppereance>(
        "personalEventsAppereance", default: .show_active)

    static let showEventMaxTimeUntilEventThreshold = Key<Int>(
        "showEventMaxTimeUntilEventThreshold", default: 60)
    static let showEventMaxTimeUntilEventEnabled = Key<Bool>(
        "showEventMaxTimeUntilEventEnabled", default: false)

    // appearance of pending events should be shown in the statusbar and menu
    static let showPendingEvents = Key<PendingEventsAppereance>(
        "showPendingEvents", default: PendingEventsAppereance.show)

    // appearance of tentative events
    static let showTentativeEvents = Key<TentativeEventsAppereance>(
        "showTentativeEvents", default: TentativeEventsAppereance.show)

    // MeetingBarNG defaults new installs to 12-hour; the launch migration
    // TimeFormatDefaultMigration (guarded by timeFormatDefaultMigrated) pins
    // existing installs to their prior 24h so upgraders are never silently flipped.
    static let timeFormat = Key<TimeFormat>("timeFormat", default: .am_pm)

    // Bookmarks
    static let bookmarks = Key<[Bookmark]>("bookmarks", default: [])

    // all browser configurations
    static let browsers = Key<[Browser]>("browsers", default: [])

    // default browser for meeting links
    static let defaultBrowser = Key<Browser>(
        "defaultBrowser",
        default: Browser(name: "Default Browser", path: "", arguments: "", deletable: false))

    // show all day events - by default true
    static let allDayEvents = Key<AlldayEventsAppereance>(
        "allDayEvents", default: AlldayEventsAppereance.show)

    // show all day events - by default show all, also events without any link
    static let nonAllDayEvents = Key<NonAlldayEventsAppereance>(
        "nonAllDayEvents", default: NonAlldayEventsAppereance.show)

    // show the end time of a meeting in the meetingbar for each event entry
    static let showEventEndTime = Key<Bool>("showEventEndTime", default: true)

    // Integrations
    static let createMeetingService = Key<CreateMeetingServices>(
        "createMeetingService", default: .zoom)

    // custom url to create meetings
    static let createMeetingServiceUrl = Key<String>("createMeetingServiceUrl", default: "")

    static let meetBrowser = Key<Browser>("meetBrowser", default: systemDefaultBrowser)
    static let zoomBrowser = Key<Browser>("zoomBrowser", default: systemDefaultBrowser)
    static let teamsBrowser = Key<Browser>("teamsBrowser", default: systemDefaultBrowser)
    static let jitsiBrowser = Key<Browser>("jitsiBrowser", default: systemDefaultBrowser)
    static let slackBrowser = Key<Browser>("slackBrowser", default: systemDefaultBrowser)
    static let riversideBrowser = Key<Browser>("riversideBrowser", default: systemDefaultBrowser)

    /// Unified per-provider browser preferences.
    /// Keyed by MeetingProvider.id (= MeetingServices.rawValue for built-in providers).
    /// Replaces the individual meetBrowser/zoomBrowser/… keys. See MeetingOpenPreferencesMigration.
    static let providerBrowsers = Key<[String: Browser]>("providerBrowsers", default: [:])

    /// Opt-in provider-specific app/web/PWA mode IDs.
    /// Unknown values are ignored and fall back to normal browser resolution.
    static let providerOpeningModes = Key<[String: String]>("providerOpeningModes", default: [:])

    /**
     * browser used for creating a new meeting
     */
    static let browserForCreateMeeting = Key<Browser>(
        "browserForCreateMeeting", default: systemDefaultBrowser)

    // Advanced
    static let automaticEventJoin = Key<Bool>("automaticEventJoin", default: false)
    static let automaticEventJoinTime = Key<TimeBeforeEvent>(
        "automaticEventJoinTime", default: .atStart)
    static let processedEventsForAutoJoin = Key<[ProcessedEvent]>(
        "processedEventsForAutoJoin", default: [])

    static let joinEventScriptLocation = Key<URL?>("joinEventScriptLocation", default: nil)
    static let runJoinEventScript = Key<Bool>("runAppleScriptWhenJoiningEvent", default: false)
    // Empty, NOT the localized placeholder: a `Key` declaration is evaluated at
    // static-init time — before the app's language is resolved — so calling
    // `.loco()` here baked one locale's placeholder into the *stored* default and
    // froze it there for the life of the install. `EditScriptModal` seeds the
    // localized placeholder at presentation time instead.
    static let joinEventScript = Key<String>("joinEventScript", default: "")

    static let eventStartScriptLocation = Key<URL?>("eventStartScriptLocation", default: nil)
    static let runEventStartScript = Key<Bool>("runEventStartScript", default: false)
    static let eventStartScriptTime = Key<TimeBeforeEvent>(
        "eventStartScriptTime", default: .atStart)
    static let eventStartScript = Key<String>(
        "eventStartScript", default: eventStartScriptPlaceholder)
    static let processedEventsForRunScriptOnEventStart = Key<[ProcessedEvent]>(
        "processedEventsForRunScriptOnEventStart", default: [])

    static let customRegexes = Key<[String]>("customRegexes", default: [])
    static let filterEventRegexes = Key<[String]>("filterEventRegexes", default: [])
}
