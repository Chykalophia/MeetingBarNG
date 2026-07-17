//
//  StatusBarPresentationPolicy.swift
//  MeetingBar
//

import Foundation

/// Per-event-list settings the status bar presentation policy needs.
///
/// Constructed at the call site from `Defaults` so the policy itself stays
/// pure and testable.
struct StatusBarPresentationSettings: Equatable {
    let hasSelectedCalendars: Bool
    let showEventMaxTimeUntilEventEnabled: Bool
    /// Threshold in minutes — events starting more than this far in the future
    /// are rendered as "afterThreshold" when the toggle is on.
    let showEventMaxTimeUntilEventThreshold: Int
}

/// Coarse classification of what the status bar should show. Used to drive
/// the title text, icon and tooltip in `StatusBarItemController.updateTitle`.
enum StatusBarTitleMode: Equatable {
    /// User has not selected any calendars yet — render the app icon.
    case idle
    /// Calendars are selected, but no upcoming event matches the current
    /// filters — render the "done for today" icon.
    case noUpcoming
    /// An upcoming event exists and should be rendered with its title.
    case nextEvent
    /// An upcoming event exists but starts beyond the configured threshold.
    /// Render an "alarm clock" hint instead of the event title.
    case afterThreshold
}

enum StatusBarTimeDisplay: Equatable {
    case show
    case showUnderTitle
    case hide
}

enum StatusBarEventParticipation: Equatable {
    case normal
    case pending
    case tentative
}

enum StatusBarParticipationDisplay: Equatable {
    case normal
    case inactive
    case underlined
}

enum StatusBarTitleLayout: Equatable {
    case none
    case inline(showTime: Bool)
    case stacked
}

enum StatusBarTitleStyle: Equatable {
    case normal
    case inactive
    case underlined
}

struct StatusBarEventPresentationInput: Equatable {
    let title: String?
    let startDate: Date
    let endDate: Date
    let meetingService: MeetingServices?
    let participation: StatusBarEventParticipation
}

struct StatusBarPresenterSettings: Equatable {
    let presentation: StatusBarPresentationSettings
    let title: StatusBarTitleSettings
    let timeDisplay: StatusBarTimeDisplay
    let iconFormat: StatusBarIconFormat
    let iconFormatAssetName: String
    let iconAssets: StatusBarIconAssets
    let pendingDisplay: StatusBarParticipationDisplay
    let tentativeDisplay: StatusBarParticipationDisplay
}

/// Which side of the title the icon renders on. The classic path is always
/// `.leading`; the composable path derives it from where the user placed the
/// icon token relative to the text tokens (leading if nothing precedes it,
/// otherwise trailing — `NSStatusBarButton` only supports left/right).
enum StatusBarIconPosition: Equatable {
    case leading
    case trailing
}

struct StatusBarPresentation: Equatable {
    let mode: StatusBarTitleMode
    let title: String
    let time: String
    let tooltip: String?
    let icon: StatusBarIcon
    let iconPosition: StatusBarIconPosition
    let layout: StatusBarTitleLayout
    let titleStyle: StatusBarTitleStyle
    let removeDeliveredNotifications: Bool

    init(
        mode: StatusBarTitleMode,
        title: String,
        time: String,
        tooltip: String?,
        icon: StatusBarIcon,
        iconPosition: StatusBarIconPosition = .leading,
        layout: StatusBarTitleLayout,
        titleStyle: StatusBarTitleStyle,
        removeDeliveredNotifications: Bool
    ) {
        self.mode = mode
        self.title = title
        self.time = time
        self.tooltip = tooltip
        self.icon = icon
        self.iconPosition = iconPosition
        self.layout = layout
        self.titleStyle = titleStyle
        self.removeDeliveredNotifications = removeDeliveredNotifications
    }
}

/// Picks the status bar mode for the current next-event candidate.
///
/// Pure: takes the next event's `startDate` (not the full `MBEvent`) plus a
/// settings snapshot. The renderer already has the `MBEvent`, so the policy
/// does not need to thread it through.
enum StatusBarPresentationPolicy {
    static func mode(
        nextEventStartDate: Date?,
        settings: StatusBarPresentationSettings,
        now: Date
    ) -> StatusBarTitleMode {
        guard settings.hasSelectedCalendars else { return .idle }
        guard let startDate = nextEventStartDate else { return .noUpcoming }
        guard settings.showEventMaxTimeUntilEventEnabled else { return .nextEvent }
        let timeUntilStart = startDate.timeIntervalSince(now)
        let thresholdInSeconds = TimeInterval(settings.showEventMaxTimeUntilEventThreshold * 60)
        return timeUntilStart < thresholdInSeconds ? .nextEvent : .afterThreshold
    }
}

enum StatusBarPresenter {
    static func presentation(
        nextEvent: StatusBarEventPresentationInput?,
        settings: StatusBarPresenterSettings,
        now: Date,
        calendar: Calendar
    ) -> StatusBarPresentation {
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: nextEvent?.startDate,
            settings: settings.presentation,
            now: now
        )

        guard mode == .nextEvent, let nextEvent else {
            return StatusBarPresentation(
                mode: mode,
                title: "",
                time: "",
                tooltip: nil,
                icon: nonEventIcon(mode: mode, settings: settings),
                layout: .none,
                titleStyle: .normal,
                removeDeliveredNotifications: mode == .noUpcoming
            )
        }

        let text = StatusBarTitlePolicy.text(
            eventTitle: nextEvent.title,
            startDate: nextEvent.startDate,
            endDate: nextEvent.endDate,
            settings: settings.title,
            now: now,
            calendar: calendar
        )

        let icon = StatusBarIconPolicy.icon(
            mode: mode,
            format: settings.iconFormat,
            formatAssetName: settings.iconFormatAssetName,
            meetingService: nextEvent.meetingService,
            assets: settings.iconAssets
        )

        return StatusBarPresentation(
            mode: mode,
            title: text.title,
            time: text.time,
            tooltip: nextEvent.title,
            icon: icon,
            layout: titleLayout(timeDisplay: settings.timeDisplay, titleFormat: settings.title.titleFormat),
            titleStyle: titleStyle(
                participation: nextEvent.participation,
                layout: titleLayout(timeDisplay: settings.timeDisplay, titleFormat: settings.title.titleFormat),
                pendingDisplay: settings.pendingDisplay,
                tentativeDisplay: settings.tentativeDisplay
            ),
            removeDeliveredNotifications: false
        )
    }

    private static func nonEventIcon(
        mode: StatusBarTitleMode,
        settings: StatusBarPresenterSettings
    ) -> StatusBarIcon {
        StatusBarIconPolicy.icon(
            mode: mode,
            format: settings.iconFormat,
            formatAssetName: settings.iconFormatAssetName,
            meetingService: nil,
            assets: settings.iconAssets
        )
    }

    private static func titleLayout(
        timeDisplay: StatusBarTimeDisplay,
        titleFormat: StatusBarEventTitleFormat
    ) -> StatusBarTitleLayout {
        guard titleFormat != .none else {
            return timeDisplay == .showUnderTitle ? .inline(showTime: false) : .inline(showTime: timeDisplay == .show)
        }
        switch timeDisplay {
        case .show:
            return .inline(showTime: true)
        case .showUnderTitle:
            return .stacked
        case .hide:
            return .inline(showTime: false)
        }
    }

    private static func titleStyle(
        participation: StatusBarEventParticipation,
        layout: StatusBarTitleLayout,
        pendingDisplay: StatusBarParticipationDisplay,
        tentativeDisplay: StatusBarParticipationDisplay
    ) -> StatusBarTitleStyle {
        let display: StatusBarParticipationDisplay
        switch participation {
        case .normal:
            display = .normal
        case .pending:
            display = pendingDisplay
        case .tentative:
            display = tentativeDisplay
        }

        switch display {
        case .normal:
            return .normal
        case .inactive:
            return layout == .stacked ? .inactive : .normal
        case .underlined:
            return .underlined
        }
    }
}

// MARK: - Title policy

enum StatusBarEventTitleFormat: Equatable {
    case show
    case generic
    case dot
    case none
}

struct StatusBarTitleLabels: Equatable {
    let genericMeetingTitle: String
    let noTitle: String
    let activeEventTimeFormat: String
    let upcomingEventTimeFormat: String
}

struct StatusBarTitleSettings: Equatable {
    let titleFormat: StatusBarEventTitleFormat
    let titleLength: Int
    let labels: StatusBarTitleLabels
}

struct StatusBarTitleText: Equatable {
    let title: String
    let time: String
    let isActiveEvent: Bool
}

enum StatusBarTitlePolicy {
    // swiftlint:disable:next function_parameter_count
    static func text(
        eventTitle rawTitle: String?,
        startDate: Date,
        endDate: Date,
        settings: StatusBarTitleSettings,
        now: Date,
        calendar: Calendar
    ) -> StatusBarTitleText {
        let title = formattedTitle(rawTitle, settings: settings)
        let isActiveEvent = startDate <= now && endDate > now
        let eventDate = isActiveEvent ? endDate : startDate
        let timeLeft = formattedTimeLeft(from: now.addingTimeInterval(-60), to: eventDate, calendar: calendar)
        let timeFormat = isActiveEvent ? settings.labels.activeEventTimeFormat : settings.labels.upcomingEventTimeFormat
        let time = String(format: timeFormat, timeLeft)
        return StatusBarTitleText(title: title, time: time, isActiveEvent: isActiveEvent)
    }

    static func shortenTitle(_ rawTitle: String?, limit: Int, noTitle: String) -> String {
        var eventTitle = String(rawTitle ?? noTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0 else { return "..." }
        if eventTitle.count > limit {
            let index = eventTitle.index(eventTitle.startIndex, offsetBy: limit - 1)
            eventTitle = String(eventTitle[...index]).trimmingCharacters(in: .whitespacesAndNewlines)
            eventTitle += "..."
        }
        return eventTitle
    }

    private static func formattedTitle(_ rawTitle: String?, settings: StatusBarTitleSettings) -> String {
        switch settings.titleFormat {
        case .show:
            return shortenTitle(
                rawTitle,
                limit: settings.titleLength,
                noTitle: settings.labels.noTitle
            )
            .replacingOccurrences(of: "\n", with: " ")
        case .generic:
            return settings.labels.genericMeetingTitle
        case .dot:
            return "•"
        case .none:
            return ""
        }
    }

    static func formattedTimeLeft(from start: Date, to end: Date, calendar: Calendar) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.minute, .hour, .day]
        formatter.calendar = calendar
        return formatter.string(from: start, to: end) ?? ""
    }
}

// MARK: - Icon policy

/// Shadow of `EventTitleIconFormat` so the policy stays hostless. The
/// `+MeetingBar.swift` adapter converts from the production Defaults enum.
enum StatusBarIconFormat: Equatable {
    case calendar
    case appicon
    case eventtype
    case none
}

/// What the status bar should render as its icon.
///
/// `asset(name)` is loaded via `NSImage(named:)` by the renderer; the renderer
/// is expected to fall back to a safe placeholder when the asset is missing
/// (see `MenuStyleConstants.iconNamed(_:)`).
enum StatusBarIcon: Equatable {
    case asset(String)
    case meetingService(MeetingServices?)
    case none
}

/// Asset names the renderer needs. Passed in by the caller so the policy is
/// fully decoupled from `MenuStyleConstants` and easy to test.
struct StatusBarIconAssets: Equatable {
    let appIcon: String
    let calendarCheckmark: String
    let calendar: String
}

/// Picks the status bar icon based on the current title mode, the user's
/// chosen icon format, and (for `.eventtype` format on a real event) the
/// next event's meeting service.
///
/// Decision matrix:
///
/// | mode             | format                      | icon                |
/// | ---------------- | --------------------------- | ------------------- |
/// | idle             | (any)                       | app icon            |
/// | noUpcoming       | appicon                     | app icon            |
/// | noUpcoming       | calendar / eventtype / none | calendar-checkmark  |
/// | afterThreshold   | appicon                     | app icon            |
/// | afterThreshold   | calendar / eventtype / none | calendar            |
/// | nextEvent        | none                        | no icon             |
/// | nextEvent        | eventtype                   | meetingService(...) |
/// | nextEvent        | appicon / calendar          | named asset         |
enum StatusBarIconPolicy {
    static func icon(
        mode: StatusBarTitleMode,
        format: StatusBarIconFormat,
        formatAssetName: String,
        meetingService: MeetingServices?,
        assets: StatusBarIconAssets
    ) -> StatusBarIcon {
        switch mode {
        case .idle:
            return .asset(assets.appIcon)
        case .noUpcoming:
            return format == .appicon
                ? .asset(assets.appIcon)
                : .asset(assets.calendarCheckmark)
        case .afterThreshold:
            return format == .appicon
                ? .asset(assets.appIcon)
                : .asset(assets.calendar)
        case .nextEvent:
            switch format {
            case .none:
                return .none
            case .eventtype:
                return .meetingService(meetingService)
            case .appicon, .calendar:
                return .asset(formatAssetName)
            }
        }
    }
}

// MARK: - Composable menu bar (MeetingBarNG)

/// A single token the user can place, in any order, into the composable
/// menu-bar title. New in MeetingBarNG. The classic status-bar path
/// (`StatusBarPresenter.presentation`) is untouched and used whenever the user
/// has not opted into a custom composition, so existing installs are unchanged.
enum MenuBarTokenKind: String, CaseIterable, Codable, Hashable {
    /// The status/meeting icon (rendered leading, per `StatusBarIconPolicy`).
    case icon
    /// The next event's title (respects the classic title format + length).
    case title
    /// A bare countdown to the event (start, or end when the event is active),
    /// formatted per `CountdownStyle`.
    case countdown
    /// Today's date, formatted per `MenuBarDateStyle`.
    case date
    /// The current wall-clock time (respects the 12h/24h preference).
    case clock
}

/// Countdown rendering styles. Mirrors the ROADMAP "Countdown styles" item.
enum CountdownStyle: String, CaseIterable, Codable, Hashable {
    /// Largest unit only, e.g. `2h`.
    case compact
    /// Abbreviated multi-unit, e.g. `2h 30m`.
    case full
    /// Positional / digital, e.g. `2:30`.
    case digital
}

/// Date-token rendering styles.
enum MenuBarDateStyle: String, CaseIterable, Codable, Hashable {
    /// Abbreviated weekday, e.g. `Mon`.
    case weekday
    /// Weekday + month + day, e.g. `Mon, Jul 17`.
    case medium
    /// Locale short date, e.g. `7/17/26`.
    case short
}

/// An ordered list of tokens. Considered "enabled" only when non-empty; the
/// adapter returns `nil` for an empty composition so the classic path runs.
struct MenuBarComposition: Equatable {
    var tokens: [MenuBarTokenKind]

    /// Sensible default when a user first opts in without deriving from their
    /// existing settings: icon, then title, then a countdown.
    static let standard = MenuBarComposition(tokens: [.icon, .title, .countdown])
}

/// Everything the composed presenter needs beyond the classic title/mode
/// snapshots. Built in the `+MeetingBar` adapter from `Defaults`.
struct MenuBarComposedSettings: Equatable {
    let presentation: StatusBarPresentationSettings
    let title: StatusBarTitleSettings
    let countdownStyle: CountdownStyle
    let dateStyle: MenuBarDateStyle
    let use24HourClock: Bool
    let iconFormat: StatusBarIconFormat
    let iconFormatAssetName: String
    let iconAssets: StatusBarIconAssets
    /// Separator inserted between adjacent text tokens (icon excluded).
    let tokenSeparator: String
    let pendingDisplay: StatusBarParticipationDisplay
    let tentativeDisplay: StatusBarParticipationDisplay
}

/// Pure formatters for the new tokens. Hostless and fully unit-tested.
enum MenuBarCompositionPolicy {
    /// Bare countdown between two dates. Returns an empty string for a
    /// non-positive interval so a stale/negative countdown never renders.
    static func countdownText(
        from start: Date,
        to end: Date,
        style: CountdownStyle,
        calendar: Calendar
    ) -> String {
        guard end > start else { return "" }

        // Digital is built by hand to guarantee a stable `H:MM` shape
        // (e.g. "2:30", "0:16"); DateComponentsFormatter's positional style
        // pads the leading unit to "02:30", which reads poorly in a menu bar.
        // Intervals of a day or more get a `Nd ` prefix so the hours field
        // never overflows into a clock-like "50:00".
        if style == .digital {
            let totalMinutes = Int((end.timeIntervalSince(start) / 60).rounded(.down))
            let days = totalMinutes / (24 * 60)
            let hours = (totalMinutes % (24 * 60)) / 60
            let minutes = totalMinutes % 60
            let hoursMinutes = "\(hours):" + String(format: "%02d", minutes)
            return days > 0 ? "\(days)d \(hoursMinutes)" : hoursMinutes
        }

        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        if style == .compact {
            // Largest non-zero unit only (localized), e.g. "2h" / "45m".
            formatter.maximumUnitCount = 1
        }
        return formatter.string(from: start, to: end) ?? ""
    }

    static func dateText(now: Date, style: MenuBarDateStyle, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? Locale.current
        // DateFormatter renders in its own time zone (system by default); pin it
        // to the calendar's so the function honors the calendar it's handed.
        formatter.timeZone = calendar.timeZone
        switch style {
        case .weekday:
            formatter.setLocalizedDateFormatFromTemplate("EEE")
        case .medium:
            formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        case .short:
            formatter.dateStyle = .short
            formatter.timeStyle = .none
        }
        return formatter.string(from: now)
    }

    static func clockText(now: Date, use24Hour: Bool, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? Locale.current
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(use24Hour ? "Hmm" : "hmma")
        return formatter.string(from: now)
    }
}

extension StatusBarPresenter {
    /// Builds the status-bar presentation from a user-defined token composition.
    /// Non-event modes (idle / noUpcoming / afterThreshold) render the status
    /// icon plus any event-independent tokens (clock/date) the user chose;
    /// title/countdown need an event, so they drop out there. The status icon
    /// always shows in those modes, so menu-bar visibility stays a reliability
    /// guarantee regardless of which tokens the user picked.
    static func composedPresentation(
        nextEvent: StatusBarEventPresentationInput?,
        composition: MenuBarComposition,
        settings: MenuBarComposedSettings,
        now: Date,
        calendar: Calendar
    ) -> StatusBarPresentation {
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: nextEvent?.startDate,
            settings: settings.presentation,
            now: now
        )

        guard mode == .nextEvent, let nextEvent else {
            return composedNonEventPresentation(
                mode: mode, composition: composition, settings: settings, now: now, calendar: calendar
            )
        }

        var icon: StatusBarIcon = .none
        var iconPosition: StatusBarIconPosition = .leading
        var segments: [String] = []

        for token in composition.tokens {
            if case .icon = token {
                iconPosition = segments.isEmpty ? .leading : .trailing
                icon = StatusBarIconPolicy.icon(
                    mode: mode,
                    format: settings.iconFormat,
                    formatAssetName: settings.iconFormatAssetName,
                    meetingService: nextEvent.meetingService,
                    assets: settings.iconAssets
                )
            } else {
                let text = eventTokenText(
                    token, nextEvent: nextEvent, settings: settings, now: now, calendar: calendar
                )
                if !text.isEmpty { segments.append(text) }
            }
        }

        let composedTitle = segments.joined(separator: settings.tokenSeparator)

        return StatusBarPresentation(
            mode: mode,
            title: composedTitle,
            time: "",
            tooltip: nextEvent.title,
            icon: icon,
            iconPosition: iconPosition,
            layout: composedTitle.isEmpty ? .none : .inline(showTime: false),
            titleStyle: titleStyle(
                participation: nextEvent.participation,
                layout: .inline(showTime: false),
                pendingDisplay: settings.pendingDisplay,
                tentativeDisplay: settings.tentativeDisplay
            ),
            removeDeliveredNotifications: false
        )
    }

    /// Rendered text for a single event-mode token. `.icon` sets the icon rather
    /// than a text segment, so it's handled by the caller and returns "" here.
    private static func eventTokenText(
        _ token: MenuBarTokenKind,
        nextEvent: StatusBarEventPresentationInput,
        settings: MenuBarComposedSettings,
        now: Date,
        calendar: Calendar
    ) -> String {
        switch token {
        case .icon:
            return ""
        case .title:
            return StatusBarTitlePolicy.text(
                eventTitle: nextEvent.title,
                startDate: nextEvent.startDate,
                endDate: nextEvent.endDate,
                settings: settings.title,
                now: now,
                calendar: calendar
            ).title
        case .countdown:
            let isActive = nextEvent.startDate <= now && nextEvent.endDate > now
            let target = isActive ? nextEvent.endDate : nextEvent.startDate
            return MenuBarCompositionPolicy.countdownText(
                from: now.addingTimeInterval(-60),
                to: target,
                style: settings.countdownStyle,
                calendar: calendar
            )
        case .date:
            return MenuBarCompositionPolicy.dateText(now: now, style: settings.dateStyle, calendar: calendar)
        case .clock:
            return MenuBarCompositionPolicy.clockText(
                now: now, use24Hour: settings.use24HourClock, calendar: calendar
            )
        }
    }

    /// Non-event composition: the status icon plus event-independent tokens
    /// (clock/date) only. Title/countdown are dropped (they need an event).
    private static func composedNonEventPresentation(
        mode: StatusBarTitleMode,
        composition: MenuBarComposition,
        settings: MenuBarComposedSettings,
        now: Date,
        calendar: Calendar
    ) -> StatusBarPresentation {
        var segments: [String] = []
        var iconPosition: StatusBarIconPosition = .leading

        for token in composition.tokens {
            switch token {
            case .icon:
                iconPosition = segments.isEmpty ? .leading : .trailing
            case .clock:
                let text = MenuBarCompositionPolicy.clockText(
                    now: now, use24Hour: settings.use24HourClock, calendar: calendar
                )
                if !text.isEmpty { segments.append(text) }
            case .date:
                let text = MenuBarCompositionPolicy.dateText(
                    now: now, style: settings.dateStyle, calendar: calendar
                )
                if !text.isEmpty { segments.append(text) }
            case .title, .countdown:
                break
            }
        }

        let composedTitle = segments.joined(separator: settings.tokenSeparator)
        return StatusBarPresentation(
            mode: mode,
            title: composedTitle,
            time: "",
            tooltip: nil,
            icon: StatusBarIconPolicy.icon(
                mode: mode,
                format: settings.iconFormat,
                formatAssetName: settings.iconFormatAssetName,
                meetingService: nil,
                assets: settings.iconAssets
            ),
            iconPosition: iconPosition,
            layout: composedTitle.isEmpty ? .none : .inline(showTime: false),
            titleStyle: .normal,
            removeDeliveredNotifications: mode == .noUpcoming
        )
    }
}
