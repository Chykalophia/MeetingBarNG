//
//  DefaultsKeys.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  add persistence keys for the composable menu bar (including its Join chip),
//  the composable menu
//  dropdown (dropdownModuleOrder + per-module enabled bools), and Apple
//  Reminders in the menu; add the calendar-window keys (calendarGridMode,
//  dimWeekendsInCalendar);
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
    // How early the Countdown block starts counting. `0` means no limit, which is
    // what the block has always done — so the default cannot change any existing
    // menu bar. Distinct from `showEventMaxTimeUntilEventThreshold`, which hides
    // the whole event (title included) behind the status icon; this hides only the
    // countdown, so the meeting still has a name on screen all day.
    static let menuBarCountdownLeadMinutes = Key<Int>("menuBarCountdownLeadMinutes", default: 0)
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
    // The menu bar's Join chip. Deliberately NOT a `MenuBarTokenKind`: a block
    // would be off for everyone who already has a stored arrangement, and
    // switching it on for them would mean a second migration rewriting their
    // block order. This is a plain toggle whose chip always renders last, so it
    // ships on without touching anyone's layout.
    static let menuBarShowJoinAction = Key<Bool>("menuBarShowJoinAction", default: true)
    // Minutes before the start at which the chip appears; 0 ⇒ only while the
    // meeting runs. Its own key rather than `eventActionHighlightMinutes`
    // (also 2): that one decides how things are STYLED once they are near, and
    // reusing it would mean you could not have the bolding without the chip.
    static let menuBarJoinActionLeadMinutes = Key<Int>("menuBarJoinActionLeadMinutes", default: 2)

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
    // Defaults to the standard order already materialized, so a fresh install
    // renders exactly as before without consulting the policy. An empty or
    // partial array — after a reset, or from a build that knew fewer modules —
    // is handled too: `DropdownCompositionPolicy` reappends whatever is missing
    // in standard order. Stored as strings so unknown/renamed modules degrade
    // gracefully.
    static let dropdownModuleOrder = Key<[String]>(
        "dropdownModuleOrder", default: DropdownComposition.standard.modules.map(\.rawValue))
    // Per-module enabled state. greeting/timeline reuse the existing keys above
    // (showGreetingInMenu / showTimelineInMenu); these cover the rest. All
    // default true so the dropdown looks unchanged until the user customizes it.
    //
    // `useSwiftUIDropdown` used to live here, switching between the SwiftUI panel
    // and a classic NSMenu. The NSMenu was retired, so the switch has nothing to
    // switch to. The stored value is simply ignored — deliberately not migrated
    // or deleted, since a stale bool in a plist costs nothing and reading one to
    // throw it away costs a launch-time migration.
    static let showMeetingControlInMenu = Key<Bool>("showMeetingControlInMenu", default: true)
    static let showAgendaInMenu = Key<Bool>("showAgendaInMenu", default: true)
    static let showJoinSectionInMenu = Key<Bool>("showJoinSectionInMenu", default: true)
    static let showBookmarksInMenu = Key<Bool>("showBookmarksInMenu", default: true)
    /// The compact month grid in the dropdown. OFF by default, unlike every other
    /// module: it is the tallest block available (~200pt), so switching it on is a
    /// deliberate choice to make the dropdown a day dashboard rather than a
    /// what's-next glance.
    static let showCalendarInMenu = Key<Bool>("showCalendarInMenu", default: false)
    /// The "Next · <meeting> — in 24m" progress card. ON: it is one row tall
    /// and answers the question the app exists to answer.
    static let showUpNextInMenu = Key<Bool>("showUpNextInMenu", default: true)

    // Calendar window (MeetingBarNG). The month ⇄ week fold, stored as a
    // `CalendarGridMode` raw value so an unknown/renamed value degrades to the
    // month grid. Weekend dimming is on by default so the work week stands out.
    static let calendarGridMode = Key<String>(
        "calendarGridMode", default: CalendarGridMode.month.rawValue)
    static let dimWeekendsInCalendar = Key<Bool>("dimWeekendsInCalendar", default: true)
    // 0 = follow the locale's first weekday; 1 = Sunday; 2 = Monday.
    static let calendarFirstWeekday = Key<Int>("calendarFirstWeekday", default: 0)
    static let showWeekNumbersInCalendar = Key<Bool>("showWeekNumbersInCalendar", default: false)
    static let maxEventsPerCalendarDay = Key<Int>("maxEventsPerCalendarDay", default: 3)

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

    /// Minutes before a meeting starts at which its row action (Join today, and
    /// whatever else earns a row button later) becomes a full-strength call to
    /// action. Further out than this the button renders muted, so a bright button
    /// always means "now" rather than "sometime today". Not named for Join
    /// specifically — the styling is the row-action slot's, not one action's.
    static let eventActionHighlightMinutes = Key<Int>(
        "eventActionHighlightMinutes", default: 2)

    /// How many meeting rows ONE agenda section draws before the remainder go
    /// behind a "+N more" row. `0` disables the cap entirely.
    ///
    /// Sized so an ordinary day never reaches it — the row exists for the
    /// conference day where forty sessions bury the one meeting that matters, not
    /// as something most people should ever see.
    static let dropdownMaxEventRows = Key<Int>("dropdownMaxEventRows", default: 10)

    /// Whether the menu bar draws the next meeting in a heavier weight once it is
    /// within `eventActionHighlightMinutes`. ON by default: the emphasis is rare,
    /// so it carries real signal, and it costs nothing the rest of the day
    /// because the resting appearance is unchanged.
    static let menuBarHighlightImminentEvent = Key<Bool>(
        "menuBarHighlightImminentEvent", default: true)

    /// How tightly the dropdown packs its rows. `.standard` reproduces the
    /// shipping panel exactly, so an existing install sees no change.
    ///
    /// Stored as a raw string, matching `menuBarCountdownStyle` above: the enum
    /// lives in the hostless module, which cannot import Defaults. An unknown
    /// value (older build, hand-edited plist) falls back to `.standard` at the
    /// read site rather than failing to decode.
    static let dropdownDensity = Key<String>(
        "dropdownDensity", default: DropdownDensity.standard.rawValue)

    /// Whether the dropdown's month calendar is folded down to the current week.
    ///
    /// A `Bool` rather than a second `CalendarGridMode`: the calendar WINDOW
    /// already owns that enum for the same idea, and two enums naming one concept
    /// across two layers is how they drift. Separate from the window's setting on
    /// purpose — the panel is a glance surface where a single row often beats six,
    /// and the window is where you go to browse.
    ///
    /// OFF by default, so the shipping panel is unchanged.
    static let dropdownCalendarWeekFold = Key<Bool>("dropdownCalendarWeekFold", default: false)

    /// User-marked important days — birthdays, anniversaries, deadlines — drawn
    /// on the month grids.
    ///
    /// One compact string per marker (`YYYY-MM-DD|label`, `----` for a repeating
    /// year), for the same reason `dropdownDensity` stores a raw string: the
    /// hostless module owns the model and cannot import Defaults, and a plist a
    /// human can read beats a nested archive when something goes wrong. Encoding
    /// and parsing live in `DateMarkerCodec`; an entry that does not parse costs
    /// that one marker, not the list.
    static let dateMarkers = Key<[String]>("dateMarkers", default: [])

    /// Whether an empty look-ahead day is dropped from the agenda entirely,
    /// rather than drawing a heading over a "nothing tomorrow" line.
    ///
    /// OFF by default, so an upgrade never silently loses a section. Today is
    /// never hidden regardless — see `AgendaSectionVisibilityPolicy`, which owns
    /// the rule and the reasoning.
    static let dropdownHidesEmptyDays = Key<Bool>("dropdownHidesEmptyDays", default: false)

    /// Whether the greeting's second line leads with today's date.
    ///
    /// When it does, the agenda's section head drops the parenthetical date and
    /// becomes a plain "TODAY" label. Two places naming the same day is the
    /// duplication this removes — so this key decides WHICH place, not whether
    /// the date appears at all.
    static let greetingShowsDate = Key<Bool>("greetingShowsDate", default: true)

    /// What the meeting card shows, field by field — see `MeetingCardFields`.
    ///
    /// Separate switches rather than named presets: the useful combinations are
    /// not the ones a preset list would guess. "Everything except the times" and
    /// "just the title and the bar" are both reasonable, and so is anything in
    /// between. All default on, so the card is unchanged until someone trims it.
    static let meetingCardShowsSectionLine = Key<Bool>(
        "meetingCardShowsSectionLine", default: true)
    static let meetingCardShowsTimes = Key<Bool>("meetingCardShowsTimes", default: true)
    static let meetingCardShowsProvider = Key<Bool>("meetingCardShowsProvider", default: true)
    static let meetingCardShowsSource = Key<Bool>("meetingCardShowsSource", default: true)

    /// Whether the dropdown's meeting card carries a countdown bar.
    ///
    /// Replaces the separate `upNext` MODULE, which drew a second card for the
    /// same meeting. Migrated from `showUpNextInMenu` once, so anyone who had
    /// that module on keeps their bar.
    static let meetingCardShowsProgress = Key<Bool>(
        "meetingCardShowsProgress", default: true)

    /// Set once `dropdownModuleMergeMigrated` has folded `showUpNextInMenu` and
    /// `showTimelineInMenu` into their replacements. A flag rather than a value
    /// check, because "off" is a legitimate destination and would otherwise be
    /// re-migrated on every launch.
    static let dropdownModuleMergeMigrated = Key<Bool>(
        "dropdownModuleMergeMigrated", default: false)

    /// How the timeline is DRAWN — track, bar, or minimal. Orthogonal to the
    /// span below: a compact bar can show the whole day, a detailed track can
    /// show just what's near.
    static let timelineAppearance = Key<String>(
        "timelineAppearance", default: TimelineAppearance.track.rawValue)

    /// What stretch of time the timeline covers — a window around now, or the
    /// whole working day. `off` hides it; there is no separate toggle.
    ///
    /// The stored key is still "timelineStyle" although the type is now
    /// `TimelineSpan`: it shipped in v0.2.0, and renaming the key would need a
    /// migration to buy nothing a comment cannot.
    ///
    /// No `none`: the timeline already has an on/off (`showTimelineInMenu`, plus
    /// the composer can drop the module), and a second way to hide one thing is
    /// how two switches end up disagreeing.
    static let timelineStyle = Key<String>(
        "timelineStyle", default: TimelineSpan.relative.rawValue)

    /// How the menu bar draws progress toward the next meeting.
    ///
    /// `.none` by default, and deliberately so: the menu bar is shared with every
    /// other app on the machine, so decorating it is something a user opts into
    /// rather than something an upgrade does to them.
    ///
    /// Stored as a raw string for the same reason as `dropdownDensity` — the enum
    /// is hostless and cannot import Defaults.
    static let meetingProgressStyle = Key<String>(
        "meetingProgressStyle", default: MeetingProgressStyle.none.rawValue)

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
