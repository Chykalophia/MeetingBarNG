//
//  SettingsIndex.swift
//  MeetingBarNG
//
//  Hostless model of the Preferences window: the eight panes, and one entry per
//  user-facing setting. Two jobs, one source of truth:
//
//    1. Settings search. `search(_:localized:)` ranks entries against the
//       localized label, help text, pane name and hand-authored synonyms, using
//       the same tier ladder as the Command Bar (`CommandBarSearch.matchTier`).
//    2. Per-pane reset. `defaultsKeys(in:)` is the exact set of `Defaults` key
//       names a pane owns, so "Reset this section" can never drift from what the
//       pane actually shows.
//
//  Deliberately hostless: no Defaults, no AppKit, no SwiftUI. Key NAMES are
//  plain strings so this file compiles into MeetingBarLogic and is unit-tested
//  without a host app (`MeetingBarLogicTests/SettingsIndexTests.swift`).
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026
//  (Preferences UX overhaul, Phase 2 — the IA restructure).
//

import Foundation

/// The panes of the Preferences window, in sidebar order.
///
/// The routing rule, applied with zero exceptions: *which meetings exist* →
/// `filters`; *how one surface draws them* → that surface's pane; *what happens
/// when you act* → `joining` / `alerts`; *the app itself* → `general`.
///
/// "About & Support" is deliberately NOT a case here: it is a pinned sidebar
/// footer item, not a settings pane, so it can never become a leftovers bin.
enum PreferencesTab: String, CaseIterable, Hashable, Sendable, Identifiable {
    case calendars
    case filters
    case menuBar
    case dropdown
    case calendarWindow
    case joining
    case alerts
    case general

    var id: String { rawValue }

    /// Opening Preferences lands on the first pane, never on credits.
    static let defaultSelection: PreferencesTab = .calendars

    /// Sidebar label. Single source of truth for the pane's name.
    var titleKey: String {
        switch self {
        case .calendars: "preferences_tab_calendars"
        case .filters: "preferences_tab_filters"
        case .menuBar: "preferences_tab_menu_bar"
        case .dropdown: "preferences_tab_dropdown"
        case .calendarWindow: "preferences_tab_calendar_window"
        case .joining: "preferences_tab_joining"
        case .alerts: "preferences_tab_alerts"
        case .general: "preferences_tab_general"
        }
    }

    /// One line under the pane header saying what the pane is for. Eight panes
    /// are only holdable if each one states its own purpose.
    var purposeKey: String {
        switch self {
        case .calendars: "preferences_purpose_calendars"
        case .filters: "preferences_purpose_filters"
        case .menuBar: "preferences_purpose_menu_bar"
        case .dropdown: "preferences_purpose_dropdown"
        case .calendarWindow: "preferences_purpose_calendar_window"
        case .joining: "preferences_purpose_joining"
        case .alerts: "preferences_purpose_alerts"
        case .general: "preferences_purpose_general"
        }
    }

    var systemImage: String {
        switch self {
        case .calendars: "calendar"
        case .filters: "line.3.horizontal.decrease.circle"
        case .menuBar: "menubar.rectangle"
        case .dropdown: "rectangle.grid.1x2"
        case .calendarWindow: "rectangle.on.rectangle"
        case .joining: "video"
        case .alerts: "bell"
        case .general: "gearshape"
        }
    }
}

/// One searchable, resettable setting.
struct SettingsIndexEntry: Hashable, Sendable, Identifiable {
    /// Stable identity, unique across the index (also used by search results).
    let id: String
    /// The pane the control lives on.
    let tab: PreferencesTab
    /// Localization key of the control's label.
    let labelKey: String
    /// Localization key of the control's help line, when it has one.
    let helpKey: String?
    /// `Defaults` key names the control writes. Drives per-pane reset.
    let defaultsKeys: [String]
    /// Words a user might search for that the label never says.
    let synonyms: [String]

    init(
        id: String,
        tab: PreferencesTab,
        labelKey: String,
        helpKey: String? = nil,
        defaultsKeys: [String] = [],
        synonyms: [String] = []
    ) {
        self.id = id
        self.tab = tab
        self.labelKey = labelKey
        self.helpKey = helpKey
        self.defaultsKeys = defaultsKeys
        self.synonyms = synonyms
    }
}

enum SettingsIndex {
    // MARK: - The index

    /// Every setting the Preferences window exposes, in pane order.
    ///
    /// Adding a control means adding a row here. `SettingsIndexTests` fails if a
    /// label key does not resolve, so the index cannot silently drift out of
    /// date as settings move between panes.
    static let all: [SettingsIndexEntry] = calendars + filters + menuBar
        + dropdown + calendarWindow + joining + alerts + general

    private static let calendars: [SettingsIndexEntry] = [
        SettingsIndexEntry(
            id: "calendars.selection",
            tab: .calendars,
            labelKey: "preferences_calendars_list_title",
            helpKey: "preferences_calendars_list_help",
            // Deliberately NO `defaultsKeys`. Which calendars you picked is your
            // DATA, not a setting — and both reset dialogs promise in so many
            // words that "your calendars … are untouched". Indexing
            // `selectedCalendarIDs` here made "Reset all settings…" clear the
            // selection while saying it would not. Searchable, never resettable.
            synonyms: ["calendar", "account", "icloud", "google", "exchange", "work", "personal"]
        ),
        SettingsIndexEntry(
            id: "calendars.reminders_access",
            tab: .calendars,
            labelKey: "preferences_calendars_reminders_toggle",
            helpKey: "preferences_calendars_reminders_help",
            synonyms: ["reminders", "permission", "access", "todo", "tasks", "privacy"]
        ),
        SettingsIndexEntry(
            id: "calendars.refresh",
            tab: .calendars,
            labelKey: "preferences_calendars_refresh_now",
            synonyms: ["sync", "force sync", "refresh", "stale", "not updating"]
        ),
        SettingsIndexEntry(
            id: "calendars.troubleshooting",
            tab: .calendars,
            labelKey: "preferences_calendars_troubleshoot_title",
            helpKey: "preferences_calendars_troubleshoot_notice",
            synonyms: ["sync", "stale", "permission", "internet accounts", "reauthenticate", "error"]
        )
    ]

    private static let filters: [SettingsIndexEntry] = [
        SettingsIndexEntry(
            id: "filters.look_ahead",
            tab: .filters,
            labelKey: "preferences_filters_look_ahead_title",
            helpKey: "preferences_filters_look_ahead_help",
            defaultsKeys: ["showEventsForPeriod"],
            synonyms: ["today", "tomorrow", "period", "range", "how far ahead"]
        ),
        SettingsIndexEntry(
            id: "filters.deduplicate",
            tab: .filters,
            labelKey: "preferences_filters_dedup_toggle",
            helpKey: "preferences_filters_dedup_help",
            defaultsKeys: ["deduplicateEvents"],
            synonyms: ["duplicate", "twice", "double", "merge", "same meeting"]
        ),
        SettingsIndexEntry(
            id: "filters.all_day",
            tab: .filters,
            labelKey: "preferences_filters_all_day_title",
            defaultsKeys: ["allDayEvents"],
            synonyms: ["all day", "birthday", "ooo", "out of office", "holiday"]
        ),
        SettingsIndexEntry(
            id: "filters.no_link",
            tab: .filters,
            labelKey: "preferences_filters_no_link_title",
            defaultsKeys: ["nonAllDayEvents"],
            synonyms: ["no link", "without link", "block", "hold", "dim"]
        ),
        SettingsIndexEntry(
            id: "filters.solo",
            tab: .filters,
            labelKey: "preferences_filters_solo_title",
            defaultsKeys: ["personalEventsAppereance"],
            synonyms: ["focus time", "lunch", "no guests", "personal", "myself", "dim"]
        ),
        SettingsIndexEntry(
            id: "filters.pending",
            tab: .filters,
            labelKey: "preferences_filters_pending_title",
            defaultsKeys: ["showPendingEvents"],
            synonyms: ["pending", "unanswered", "not accepted", "invite", "rsvp", "dim"]
        ),
        SettingsIndexEntry(
            id: "filters.tentative",
            tab: .filters,
            labelKey: "preferences_filters_tentative_title",
            defaultsKeys: ["showTentativeEvents"],
            synonyms: ["tentative", "maybe", "rsvp", "dim"]
        ),
        SettingsIndexEntry(
            id: "filters.declined",
            tab: .filters,
            labelKey: "preferences_filters_declined_title",
            defaultsKeys: ["declinedEventsAppereance"],
            synonyms: ["declined", "rejected", "no", "strikethrough", "crossed out", "dim"]
        ),
        SettingsIndexEntry(
            id: "filters.ended",
            tab: .filters,
            labelKey: "preferences_filters_ended_title",
            helpKey: "preferences_filters_ended_help",
            defaultsKeys: ["pastEventsAppereance", "hideFinishedEventsInMenu"],
            synonyms: ["past", "finished", "ended", "over", "done", "dim"]
        ),
        SettingsIndexEntry(
            id: "filters.ongoing",
            tab: .filters,
            labelKey: "preferences_filters_ongoing_title",
            helpKey: "preferences_filters_ongoing_help",
            defaultsKeys: ["ongoingEventVisibility"],
            synonyms: ["current", "happening now", "running", "in progress", "next"]
        ),
        SettingsIndexEntry(
            id: "filters.title_patterns",
            tab: .filters,
            labelKey: "preferences_filters_title_pattern_title",
            helpKey: "preferences_filters_title_pattern_help",
            defaultsKeys: ["filterEventRegexes"],
            synonyms: ["regex", "text pattern", "hide by name", "exclude", "keyword", "block title"]
        )
    ]

    private static let menuBar: [SettingsIndexEntry] = [
        SettingsIndexEntry(
            id: "menubar.preset",
            tab: .menuBar,
            labelKey: "preferences_menubar_preset_title",
            helpKey: "preferences_menubar_preset_help",
            defaultsKeys: ["menuBarTokens"],
            synonyms: ["layout", "preset", "classic", "minimal", "agenda", "info", "arrangement"]
        ),
        SettingsIndexEntry(
            id: "menubar.blocks",
            tab: .menuBar,
            labelKey: "preferences_menubar_blocks_title",
            helpKey: "preferences_menubar_blocks_help",
            // The seeding flag rides with the arrangement it seeded. Without it,
            // "Reset this section" would empty the block list and leave it
            // empty — a menu bar showing nothing but the app icon, which is not
            // the shipped default. Reset instead returns the pane to the state a
            // fresh install is in, and the seed re-derives.
            defaultsKeys: ["menuBarTokens", "menuBarTimeFormatMigrated"],
            synonyms: ["block", "token", "order", "reorder", "clock", "date", "week number"]
        ),
        SettingsIndexEntry(
            id: "menubar.icon",
            tab: .menuBar,
            labelKey: "preferences_menubar_icon_title",
            defaultsKeys: ["eventTitleIconFormat"],
            synonyms: ["icon", "symbol", "logo", "zoom", "teams", "meet", "no icon"]
        ),
        SettingsIndexEntry(
            id: "menubar.title",
            tab: .menuBar,
            labelKey: "preferences_menubar_title_title",
            defaultsKeys: ["eventTitleFormat"],
            synonyms: ["title", "name", "dot", "text", "privacy", "hide title"]
        ),
        SettingsIndexEntry(
            id: "menubar.title_length",
            tab: .menuBar,
            labelKey: "preferences_menubar_title_shorten_title",
            helpKey: "preferences_menubar_title_shorten_example",
            defaultsKeys: ["statusbarEventTitleLength"],
            synonyms: ["shorten", "truncate", "length", "characters", "too long"]
        ),
        SettingsIndexEntry(
            id: "menubar.lines",
            tab: .menuBar,
            labelKey: "preferences_menubar_lines_title",
            // `eventTimeFormat` is no longer a control: showing the time is the
            // presence of the Countdown block, and show-under-title is this row.
            // Searchable by the old vocabulary too — someone looking for "time
            // under title" is looking for this, whatever it is now called.
            defaultsKeys: ["menuBarTwoLineLayout"],
            synonyms: ["time", "clock", "under title", "two lines", "one line", "start time", "stacked"]
        ),
        SettingsIndexEntry(
            id: "menubar.quiet",
            tab: .menuBar,
            labelKey: "preferences_menubar_quiet_toggle",
            helpKey: "preferences_menubar_quiet_example",
            defaultsKeys: ["showEventMaxTimeUntilEventEnabled", "showEventMaxTimeUntilEventThreshold"],
            synonyms: ["quiet", "distraction", "only when close", "threshold", "minutes before"]
        ),
        SettingsIndexEntry(
            id: "menubar.countdown_style",
            tab: .menuBar,
            labelKey: "preferences_menubar_countdown_style_title",
            defaultsKeys: ["menuBarCountdownStyle"],
            synonyms: ["countdown", "timer", "2h 30m", "digital", "time left"]
        ),
        SettingsIndexEntry(
            id: "menubar.date_style",
            tab: .menuBar,
            labelKey: "preferences_menubar_date_style_title",
            defaultsKeys: ["menuBarDateStyle"],
            synonyms: ["date", "weekday", "day", "mon", "format"]
        ),
        SettingsIndexEntry(
            id: "menubar.progress_style",
            tab: .menuBar,
            labelKey: "preferences_menubar_progress_style_title",
            defaultsKeys: ["menuBarProgressStyle"],
            synonyms: ["progress", "bar", "year", "day", "how much left"]
        ),
        SettingsIndexEntry(
            id: "menubar.world_clock",
            tab: .menuBar,
            labelKey: "preferences_menubar_world_clock_timezone_title",
            defaultsKeys: ["menuBarWorldClockTimeZone", "menuBarWorldClockLabel"],
            synonyms: ["world clock", "time zone", "timezone", "utc", "london", "sf"]
        )
    ]

    private static let dropdown: [SettingsIndexEntry] = [
        SettingsIndexEntry(
            id: "dropdown.blocks",
            tab: .dropdown,
            labelKey: "preferences_dropdown_blocks_title",
            helpKey: "preferences_dropdown_blocks_help",
            defaultsKeys: [
                "dropdownModuleOrder",
                "showGreetingInMenu",
                "showTimelineInMenu",
                "showMeetingControlInMenu",
                "showAgendaInMenu",
                "showJoinSectionInMenu",
                "showBookmarksInMenu"
            ],
            synonyms: ["block", "section", "module", "order", "greeting", "timeline", "agenda"]
        ),
        SettingsIndexEntry(
            id: "dropdown.greeting_name",
            tab: .dropdown,
            labelKey: "preferences_dropdown_greeting_name_title",
            helpKey: "preferences_dropdown_greeting_name_help",
            defaultsKeys: ["greetingName"],
            synonyms: ["greeting", "good morning", "hello", "your name"]
        ),
        SettingsIndexEntry(
            id: "dropdown.reminders",
            tab: .dropdown,
            labelKey: "preferences_dropdown_reminders_toggle",
            helpKey: "preferences_dropdown_reminders_help",
            defaultsKeys: ["showRemindersInMenu", "remindersIncludeOverdue"],
            synonyms: ["reminders", "todo", "tasks", "overdue"]
        ),
        SettingsIndexEntry(
            id: "dropdown.row_end_time",
            tab: .dropdown,
            labelKey: "preferences_dropdown_rows_end_time_toggle",
            defaultsKeys: ["showEventEndTime"],
            synonyms: ["end time", "finish", "duration", "time column"]
        ),
        SettingsIndexEntry(
            id: "dropdown.row_service_icon",
            tab: .dropdown,
            labelKey: "preferences_dropdown_rows_service_icon_toggle",
            defaultsKeys: ["showMeetingServiceIcon"],
            synonyms: ["zoom", "teams", "meet", "logo", "icon", "service"]
        ),
        SettingsIndexEntry(
            id: "dropdown.row_calendar_colour",
            tab: .dropdown,
            labelKey: "preferences_dropdown_rows_calendar_color_toggle",
            defaultsKeys: ["showEventCalendarColor"],
            synonyms: ["dot", "bullet", "colour", "color", "marker", "calendar colour"]
        ),
        SettingsIndexEntry(
            id: "dropdown.row_prep_links",
            tab: .dropdown,
            labelKey: "preferences_dropdown_rows_prep_links_toggle",
            defaultsKeys: ["showMeetingPrepLinks"],
            synonyms: ["figma", "docs", "github", "notion", "prep", "links", "attachments"]
        ),
        SettingsIndexEntry(
            id: "dropdown.row_title_length",
            tab: .dropdown,
            labelKey: "preferences_dropdown_rows_shorten_toggle",
            helpKey: "preferences_dropdown_rows_shorten_example",
            defaultsKeys: ["shortenEventTitle", "menuEventTitleLength"],
            synonyms: ["long titles", "shorten", "truncate", "characters", "wrap"]
        )
    ]

    private static let calendarWindow: [SettingsIndexEntry] = [
        SettingsIndexEntry(
            id: "calendarwindow.dim_weekends",
            tab: .calendarWindow,
            labelKey: "preferences_calendarwindow_dim_weekends_toggle",
            helpKey: "preferences_calendarwindow_dim_weekends_help",
            defaultsKeys: ["dimWeekendsInCalendar"],
            synonyms: ["weekend", "saturday", "sunday", "grey", "gray", "dim"]
        ),
        SettingsIndexEntry(
            id: "calendarwindow.open_in",
            tab: .calendarWindow,
            labelKey: "preferences_calendarwindow_open_in_title",
            helpKey: "preferences_calendarwindow_open_in_help",
            defaultsKeys: ["calendarGridMode"],
            synonyms: ["month", "week", "grid", "view", "calendar window"]
        )
    ]

    private static let joining: [SettingsIndexEntry] = [
        SettingsIndexEntry(
            id: "joining.default_browser",
            tab: .joining,
            labelKey: "preferences_joining_default_browser_title",
            helpKey: "preferences_joining_default_browser_help",
            defaultsKeys: ["defaultBrowser"],
            synonyms: ["browser", "chrome", "safari", "firefox", "open links"]
        ),
        SettingsIndexEntry(
            id: "joining.per_service",
            tab: .joining,
            labelKey: "preferences_joining_overrides_title",
            helpKey: "preferences_joining_overrides_help",
            defaultsKeys: ["providerBrowsers", "providerOpeningModes"],
            synonyms: ["zoom app", "teams app", "pwa", "per service", "override", "native app"]
        ),
        SettingsIndexEntry(
            id: "joining.create_service",
            tab: .joining,
            labelKey: "preferences_joining_create_service_title",
            defaultsKeys: ["createMeetingService", "createMeetingServiceUrl"],
            synonyms: ["new meeting", "create", "instant meeting", "zoom", "meet", "custom url"]
        ),
        SettingsIndexEntry(
            id: "joining.create_browser",
            tab: .joining,
            labelKey: "preferences_joining_create_browser_title",
            defaultsKeys: ["browserForCreateMeeting"],
            synonyms: ["browser", "new meeting", "create meeting", "chrome"]
        ),
        SettingsIndexEntry(
            id: "joining.saved_links",
            tab: .joining,
            labelKey: "preferences_joining_links_title",
            helpKey: "preferences_joining_links_help",
            synonyms: ["bookmark", "saved link", "phone", "standing meeting", "shortcut link"]
        ),
        SettingsIndexEntry(
            id: "joining.link_patterns",
            tab: .joining,
            labelKey: "preferences_joining_link_patterns_title",
            helpKey: "preferences_joining_link_patterns_help",
            defaultsKeys: ["customRegexes"],
            synonyms: ["regex", "text pattern", "custom link", "detect link", "not detected"]
        )
    ]

    private static let alerts: [SettingsIndexEntry] = [
        SettingsIndexEntry(
            id: "alerts.notify_start",
            tab: .alerts,
            labelKey: "preferences_alerts_notify_start_toggle",
            defaultsKeys: ["joinEventNotification", "joinEventNotificationTime"],
            synonyms: ["notification", "banner", "alert", "before start", "remind me"]
        ),
        SettingsIndexEntry(
            id: "alerts.fullscreen",
            tab: .alerts,
            labelKey: "preferences_alerts_fullscreen_toggle",
            helpKey: "preferences_alerts_fullscreen_without_link_help",
            defaultsKeys: [
                "fullscreenNotification",
                "fullscreenNotificationTime",
                "fullscreenNotificationsForEventsWithoutMeetingLink"
            ],
            synonyms: ["fullscreen", "full screen", "takeover", "big alert", "cannot miss"]
        ),
        SettingsIndexEntry(
            id: "alerts.notify_end",
            tab: .alerts,
            labelKey: "preferences_alerts_notify_end_toggle",
            defaultsKeys: ["endOfEventNotification", "endOfEventNotificationTime"],
            synonyms: ["end", "over", "wrap up", "finish", "notification"]
        ),
        SettingsIndexEntry(
            id: "alerts.auto_join",
            tab: .alerts,
            labelKey: "preferences_alerts_auto_join_toggle",
            helpKey: "preferences_alerts_auto_join_help",
            defaultsKeys: ["automaticEventJoin", "automaticEventJoinTime"],
            synonyms: ["auto join", "automatic", "open for me", "hands free"]
        ),
        SettingsIndexEntry(
            id: "alerts.scripts",
            tab: .alerts,
            labelKey: "preferences_alerts_scripts_title",
            helpKey: "preferences_alerts_script_link_only_help",
            defaultsKeys: [
                "runEventStartScript",
                "eventStartScriptTime",
                "runAppleScriptWhenJoiningEvent"
            ],
            synonyms: ["applescript", "script", "automation", "shortcut", "do not disturb"]
        )
    ]

    private static let general: [SettingsIndexEntry] = [
        SettingsIndexEntry(
            id: "general.launch_at_login",
            tab: .general,
            labelKey: "preferences_general_login_toggle",
            synonyms: ["startup", "login", "boot", "start automatically", "launch"]
        ),
        SettingsIndexEntry(
            id: "general.time_format",
            tab: .general,
            labelKey: "preferences_general_time_format_title",
            helpKey: "preferences_general_time_format_help",
            defaultsKeys: ["timeFormat"],
            synonyms: ["24 hour", "12 hour", "am", "pm", "military", "clock"]
        ),
        SettingsIndexEntry(
            id: "general.shortcuts",
            tab: .general,
            labelKey: "preferences_general_shortcuts_title",
            synonyms: ["shortcut", "hotkey", "keyboard", "key", "command"]
        ),
        SettingsIndexEntry(
            id: "general.classic_menu",
            tab: .general,
            labelKey: "preferences_general_classic_menu_toggle",
            helpKey: "preferences_general_classic_menu_help",
            defaultsKeys: ["useSwiftUIDropdown"],
            synonyms: ["classic", "old menu", "fallback", "plain menu", "troubleshoot"]
        )
    ]

    // MARK: - Lookups

    static func entries(in tab: PreferencesTab) -> [SettingsIndexEntry] {
        all.filter { $0.tab == tab }
    }

    /// The `Defaults` key names a pane owns, de-duplicated, in index order.
    /// This is exactly what "Reset this section" restores.
    static func defaultsKeys(in tab: PreferencesTab) -> [String] {
        var seen = Set<String>()
        var keys: [String] = []
        for entry in entries(in: tab) {
            for key in entry.defaultsKeys where seen.insert(key).inserted {
                keys.append(key)
            }
        }
        return keys
    }

    /// Every `Defaults` key the window can reset, across all panes.
    static var allDefaultsKeys: [String] {
        var seen = Set<String>()
        var keys: [String] = []
        for tab in PreferencesTab.allCases {
            for key in defaultsKeys(in: tab) where seen.insert(key).inserted {
                keys.append(key)
            }
        }
        return keys
    }

    // MARK: - Search

    /// Ranked settings for `query`.
    ///
    /// - Parameter localized: resolves a localization key to display text. The
    ///   app passes `{ $0.loco() }`; tests pass a catalog reader, which is what
    ///   makes this hostless and deterministic.
    ///
    /// Scoring mirrors `CommandBarSearch`: every whitespace-separated term must
    /// match something (AND), each term contributing its best tier — exact 4,
    /// prefix 3, word-boundary prefix 2, substring 1. Ties keep index order, so
    /// results are stable.
    static func search(
        _ query: String,
        localized: (String) -> String
    ) -> [SettingsIndexEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let terms = TextNormalization.fold(trimmed)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !terms.isEmpty else { return [] }

        /// A match plus the tie-breaker that keeps ranking stable: equal scores
        /// resolve to index order, so search results never shuffle between
        /// keystrokes for no visible reason.
        struct ScoredEntry {
            let entry: SettingsIndexEntry
            let score: Double
            let order: Int
        }

        var scored: [ScoredEntry] = []
        for (order, entry) in all.enumerated() {
            var haystack = [localized(entry.labelKey), localized(entry.tab.titleKey)]
            if let helpKey = entry.helpKey {
                haystack.append(localized(helpKey))
            }
            haystack.append(contentsOf: entry.synonyms)
            let folded = haystack.map(TextNormalization.fold)

            var total = 0.0
            var matchedEveryTerm = true
            for term in terms {
                var best = 0.0
                for field in folded {
                    best = max(best, CommandBarSearch.matchTier(term: term, in: field))
                }
                guard best > 0 else {
                    matchedEveryTerm = false
                    break
                }
                total += best
            }
            if matchedEveryTerm {
                scored.append(ScoredEntry(entry: entry, score: total, order: order))
            }
        }

        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
            .map(\.entry)
    }
}
