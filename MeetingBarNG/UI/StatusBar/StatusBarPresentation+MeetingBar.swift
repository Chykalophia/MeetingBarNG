//
//  StatusBarPresentation+MeetingBar.swift
//  MeetingBar
//

import Defaults
import Foundation

extension StatusBarPresentationSettings {
    /// Snapshot of the relevant `Defaults` keys the policy reads. The
    /// renderer (`StatusBarItemController.updateTitle`) builds this on every
    /// title update and passes it to `StatusBarPresentation.mode`.
    static var current: StatusBarPresentationSettings {
        StatusBarPresentationSettings(
            hasSelectedCalendars: !Defaults[.selectedCalendarIDs].isEmpty,
            showEventMaxTimeUntilEventEnabled: Defaults[.showEventMaxTimeUntilEventEnabled],
            showEventMaxTimeUntilEventThreshold: Defaults[.showEventMaxTimeUntilEventThreshold],
            highlightImminentEvent: Defaults[.menuBarHighlightImminentEvent],
            // Same key the dropdown's action buttons read, so "close enough to
            // act on" means one thing everywhere rather than drifting apart.
            imminentLeadMinutes: Defaults[.eventActionHighlightMinutes]
        )
    }
}

extension StatusBarTimeDisplay {
    init(_ format: EventTimeFormat) {
        switch format {
        case .show:
            self = .show
        case .show_under_title:
            self = .showUnderTitle
        case .hide:
            self = .hide
        }
    }
}

extension StatusBarEventParticipation {
    init(_ status: MBEventAttendeeStatus) {
        switch status {
        case .pending:
            self = .pending
        case .tentative:
            self = .tentative
        default:
            self = .normal
        }
    }
}

extension StatusBarParticipationDisplay {
    init(_ pendingAppearance: PendingEventsAppereance) {
        switch pendingAppearance {
        case .show_inactive:
            self = .inactive
        case .show_underlined:
            self = .underlined
        case .show, .hide:
            self = .normal
        }
    }

    init(_ tentativeAppearance: TentativeEventsAppereance) {
        switch tentativeAppearance {
        case .show_inactive:
            self = .inactive
        case .show_underlined:
            self = .underlined
        case .show, .hide:
            self = .normal
        }
    }
}

extension StatusBarEventPresentationInput {
    init(_ event: MBEvent) {
        self.init(
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            meetingService: event.meetingLink?.service,
            participation: StatusBarEventParticipation(event.participationStatus)
        )
    }
}

extension StatusBarPresenterSettings {
    static var current: StatusBarPresenterSettings {
        StatusBarPresenterSettings(
            presentation: .current,
            title: .current,
            timeDisplay: StatusBarTimeDisplay(Defaults[.eventTimeFormat]),
            iconFormat: StatusBarIconFormat(Defaults[.eventTitleIconFormat]),
            iconFormatAssetName: Defaults[.eventTitleIconFormat].rawValue,
            iconAssets: .production,
            pendingDisplay: StatusBarParticipationDisplay(Defaults[.showPendingEvents]),
            tentativeDisplay: StatusBarParticipationDisplay(Defaults[.showTentativeEvents])
        )
    }
}

// MARK: - Title policy adapters

extension StatusBarEventTitleFormat {
    init(_ format: EventTitleFormat) {
        switch format {
        case .show: self = .show
        case .generic: self = .generic
        case .dot: self = .dot
        case .none: self = .none
        }
    }
}

extension StatusBarTitleLabels {
    static var current: StatusBarTitleLabels {
        StatusBarTitleLabels(
            genericMeetingTitle: "general_meeting".loco(),
            noTitle: "status_bar_no_title".loco(),
            activeEventTimeFormat: "status_bar_event_status_now".loco(),
            upcomingEventTimeFormat: "status_bar_event_status_in".loco()
        )
    }
}

extension StatusBarTitleSettings {
    static var current: StatusBarTitleSettings {
        StatusBarTitleSettings(
            titleFormat: StatusBarEventTitleFormat(Defaults[.eventTitleFormat]),
            titleLength: Defaults[.statusbarEventTitleLength],
            labels: .current
        )
    }
}

// MARK: - Icon policy adapters

extension StatusBarIconFormat {
    /// Maps the production `EventTitleIconFormat` (defined in
    /// `Utilities/Constants.swift`, used as a Defaults type) to the hostless
    /// shadow enum the policy operates on.
    init(_ format: EventTitleIconFormat) {
        switch format {
        case .calendar: self = .calendar
        case .appicon: self = .appicon
        case .eventtype: self = .eventtype
        case .none: self = .none
        }
    }
}

extension StatusBarIconAssets {
    /// Asset names taken from `MenuStyleConstants` so production code stays
    /// the single source of truth.
    static var production: StatusBarIconAssets {
        StatusBarIconAssets(
            appIcon: MenuStyleConstants.appIconName,
            calendarCheckmark: MenuStyleConstants.calendarCheckmarkIconName,
            calendar: MenuStyleConstants.calendarIconName
        )
    }
}

// MARK: - Composable menu bar adapters (MeetingBarNG)

extension MenuBarComposition {
    /// The user's saved composition, or `nil` when the classic
    /// `StatusBarPresenter` path should draw the menu bar instead.
    ///
    /// An empty token list means two different things either side of
    /// `MenuBarTimeFormatDefaultsMigration`, and conflating them is what made
    /// the old "Customize menu bar layout" toggle destructive:
    ///
    ///   • before it has run — the user never composed anything, so the classic
    ///     path owns the menu bar and existing installs are unchanged;
    ///   • after it has run — every install has been seeded, so an empty list is
    ///     a deliberate "every block is switched off". That composes to nothing,
    ///     and `ensureStatusBarButtonIsVisible` keeps the app icon clickable.
    static var currentIfEnabled: MenuBarComposition? {
        let tokens = MenuBarBlockList.kinds(stored: Defaults[.menuBarTokens])
        if tokens.isEmpty {
            return Defaults[.menuBarTimeFormatMigrated] ? MenuBarComposition(tokens: []) : nil
        }
        return MenuBarComposition(tokens: tokens)
    }

    /// A composition mirroring the user's classic status-bar settings. Used to
    /// seed the composer when they first opt in, so the starting point matches
    /// their current menu bar.
    static var derivedFromLegacy: MenuBarComposition {
        var tokens: [MenuBarTokenKind] = []
        if Defaults[.eventTitleIconFormat] != .none { tokens.append(.icon) }
        if Defaults[.eventTitleFormat] != .none { tokens.append(.title) }
        if Defaults[.eventTimeFormat] != .hide { tokens.append(.countdown) }
        return tokens.isEmpty ? .standard : MenuBarComposition(tokens: tokens)
    }
}

extension MenuBarComposedSettings {
    /// Snapshot of the `Defaults` the composed presenter needs. Reuses the
    /// existing classic adapters (`StatusBarPresentationSettings.current`,
    /// `StatusBarTitleSettings.current`, `StatusBarIconAssets.production`).
    static var current: MenuBarComposedSettings {
        MenuBarComposedSettings(
            presentation: .current,
            title: .current,
            countdownStyle: CountdownStyle(rawValue: Defaults[.menuBarCountdownStyle]) ?? .full,
            dateStyle: MenuBarDateStyle(rawValue: Defaults[.menuBarDateStyle]) ?? .medium,
            progressStyle: MenuBarProgressStyle(rawValue: Defaults[.menuBarProgressStyle]) ?? .day,
            use24HourClock: Defaults[.timeFormat] == .military,
            worldClockTimeZone: TimeZone(identifier: Defaults[.menuBarWorldClockTimeZone]) ?? .current,
            worldClockLabel: Defaults[.menuBarWorldClockLabel],
            weekNumberPrefix: "menu_bar_week_number_prefix".loco(),
            iconFormat: StatusBarIconFormat(Defaults[.eventTitleIconFormat]),
            iconFormatAssetName: Defaults[.eventTitleIconFormat].rawValue,
            iconAssets: .production,
            tokenSeparator: "  ",
            pendingDisplay: StatusBarParticipationDisplay(Defaults[.showPendingEvents]),
            tentativeDisplay: StatusBarParticipationDisplay(Defaults[.showTentativeEvents]),
            twoLines: Defaults[.menuBarTwoLineLayout]
        )
    }
}
