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
    /// Whether the menu bar emphasises the next meeting once it is close enough
    /// to act on. ON by default.
    var highlightImminentEvent: Bool = true
    /// Minutes before the start at which "close enough" begins. Shared with the
    /// dropdown's action buttons (`eventActionHighlightMinutes`) on purpose: one
    /// notion of "now-ish" across the whole app, not two that can disagree.
    var imminentLeadMinutes: Int = 2
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
    /// Whether the renderer should draw the title in a heavier weight because the
    /// meeting is close enough to act on.
    ///
    /// Separate from `titleStyle` rather than another case of it, because the two
    /// answer different questions — style says what KIND of event this is
    /// (declined, pending, past), emphasis says WHEN it is. The presenter only
    /// ever sets this alongside `.normal`, so a declined meeting stays dimmed
    /// instead of being shouted about a minute before a meeting you are not
    /// attending.
    let emphasizeTitle: Bool
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
        emphasizeTitle: Bool = false,
        removeDeliveredNotifications: Bool
    ) {
        self.emphasizeTitle = emphasizeTitle
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

        let resolvedStyle = titleStyle(
            participation: nextEvent.participation,
            layout: titleLayout(timeDisplay: settings.timeDisplay, titleFormat: settings.title.titleFormat),
            pendingDisplay: settings.pendingDisplay,
            tentativeDisplay: settings.tentativeDisplay
        )
        // Emphasis rides on top of a NORMAL title only. A declined or pending
        // meeting is dimmed/underlined precisely because you are not treating it
        // as yours; bolding it a minute beforehand would argue with that.
        let emphasize =
            settings.presentation.highlightImminentEvent
            && resolvedStyle == .normal
            && EventActionProminence.isImminent(
                start: nextEvent.startDate,
                end: nextEvent.endDate,
                now: now,
                leadMinutes: settings.presentation.imminentLeadMinutes
            )

        return StatusBarPresentation(
            mode: mode,
            title: text.title,
            time: text.time,
            tooltip: nextEvent.title,
            icon: icon,
            layout: titleLayout(timeDisplay: settings.timeDisplay, titleFormat: settings.title.titleFormat),
            titleStyle: resolvedStyle,
            emphasizeTitle: emphasize,
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
    /// A day/year progress bar drawn as a fixed-width Unicode-block string,
    /// styled per `MenuBarProgressStyle`. Event-independent.
    case progress
    /// The ISO-8601 week number, e.g. `W29`. Event-independent.
    case weekNumber
    /// The current time in a chosen time zone with an optional short label,
    /// e.g. `SF 9:41`. Event-independent.
    case worldClock
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

/// Progress-token rendering styles.
enum MenuBarProgressStyle: String, CaseIterable, Codable, Hashable {
    /// Fraction of the current day elapsed (midnight → midnight).
    case day
    /// Fraction of the current year elapsed (Jan 1 → Jan 1).
    case year
}

/// An ordered list of tokens. Considered "enabled" only when non-empty; the
/// adapter returns `nil` for an empty composition so the classic path runs.
struct MenuBarComposition: Equatable {
    var tokens: [MenuBarTokenKind]

    /// Sensible default when a user first opts in without deriving from their
    /// existing settings: icon, then title, then a countdown.
    static let standard = MenuBarComposition(tokens: [.icon, .title, .countdown])
}

/// One-click starting points for the composable menu bar (Dot parity). Each
/// named case maps to a fixed, ordered token list the existing composition
/// pipeline already understands — presets never introduce new behavior, they
/// just WRITE token lists. `.custom` is a sentinel meaning "user-defined
/// order"; its `tokens` is empty and must never be applied.
enum MenuBarPreset: String, CaseIterable, Codable {
    case classic
    case minimal
    case agenda
    case info
    case custom

    /// The ordered tokens each preset writes. `.custom` returns `[]` (sentinel).
    var tokens: [MenuBarTokenKind] {
        switch self {
        case .classic: return [.icon, .title, .countdown]
        case .minimal: return [.icon, .title]
        case .agenda: return [.title, .countdown]
        case .info: return [.icon, .date, .clock]
        case .custom: return []
        }
    }

    /// The named preset whose `tokens` exactly equals the given ordered list,
    /// else `.custom`. An empty/unset list detects as `.classic`: the derived
    /// legacy default ≈ icon+title+countdown, so an unconfigured menu bar reads
    /// as the classic preset rather than an empty custom one.
    static func detect(tokens: [MenuBarTokenKind]) -> MenuBarPreset {
        if tokens.isEmpty { return .classic }
        return allCases.first { $0 != .custom && $0.tokens == tokens } ?? .custom
    }
}

// MARK: - The block list (Menu Bar pane)

/// One row of the Menu Bar pane's block list: a kind, and whether the menu bar
/// currently shows it.
struct MenuBarBlock: Equatable {
    let kind: MenuBarTokenKind
    let isOn: Bool
}

/// The Menu Bar pane's list model, kept hostless so it is unit-tested without a
/// window: the stored token array in, the complete inventory of blocks out.
///
/// The pane always shows every kind the menu bar can hold. A block that is off
/// stays on screen, dimmed, one click from returning — which is what makes the
/// switch non-destructive. Before this, "off" meant *removed from the list*,
/// and the whole builder had an enable toggle whose off state wrote an empty
/// token array: the user's arrangement was destroyed with no undo, and turning
/// it back on reseeded from the legacy settings rather than from what they had.
enum MenuBarBlockList {
    /// Showing blocks first, in their stored left-to-right order, then the
    /// hidden ones in canonical order. Unknown and duplicate stored values are
    /// dropped, so a downgrade or a hand-edited plist degrades gracefully.
    static func blocks(stored: [String]) -> [MenuBarBlock] {
        let showing = kinds(stored: stored)
        let hidden = MenuBarTokenKind.allCases.filter { !showing.contains($0) }
        return showing.map { MenuBarBlock(kind: $0, isOn: true) }
            + hidden.map { MenuBarBlock(kind: $0, isOn: false) }
    }

    /// The showing kinds, parsed and de-duplicated, in stored order.
    static func kinds(stored: [String]) -> [MenuBarTokenKind] {
        var seen = Set<MenuBarTokenKind>()
        return stored
            .compactMap(MenuBarTokenKind.init(rawValue:))
            .filter { seen.insert($0).inserted }
    }

    /// Moves a showing block `offset` places. A hidden block, or a move past
    /// either end, returns the stored order unchanged.
    static func moved(stored: [String], kind: MenuBarTokenKind, by offset: Int) -> [String] {
        var showing = kinds(stored: stored)
        guard let index = showing.firstIndex(of: kind) else { return rawValues(showing) }
        let target = index + offset
        guard showing.indices.contains(target) else { return rawValues(showing) }
        showing.swapAt(index, target)
        return rawValues(showing)
    }

    /// Turns a block on (appended last, where the user can see it arrive) or off
    /// (removed from the showing order; every other block keeps its place).
    static func setting(stored: [String], kind: MenuBarTokenKind, isOn: Bool) -> [String] {
        var showing = kinds(stored: stored)
        if isOn {
            guard !showing.contains(kind) else { return rawValues(showing) }
            showing.append(kind)
        } else {
            showing.removeAll { $0 == kind }
        }
        return rawValues(showing)
    }

    private static func rawValues(_ kinds: [MenuBarTokenKind]) -> [String] {
        kinds.map(\.rawValue)
    }
}

// MARK: - Retiring the "Time next to the title" control

/// What the one-time `eventTimeFormat` migration should write. `nil` means
/// "leave that stored value exactly as it is".
struct MenuBarTimeFormatMigrationPlan: Equatable {
    let tokens: [String]?
    let twoLines: Bool?

    static let noChange = MenuBarTimeFormatMigrationPlan(tokens: nil, twoLines: nil)
}

/// The pure decision behind retiring `eventTimeFormat` as a control.
///
/// The picker offered show / show-under-title / hide, was read only by the
/// classic status-bar path, and sat directly above a composer that ignored it.
/// Its two capabilities survive in clearer places — a Countdown block, and
/// "One line / Two lines" — so the migration exists to carry the user's answer
/// across rather than silently dropping it.
///
/// Anyone who had already composed their menu bar is left untouched: for them
/// the picker was already inert, so honouring it now would change a menu bar
/// they never saw it affect.
enum MenuBarTimeFormatMigration {
    static func plan(
        storedTokens: [String],
        legacyTokens: [String],
        timeUnderTitle: Bool
    ) -> MenuBarTimeFormatMigrationPlan {
        guard MenuBarBlockList.kinds(stored: storedTokens).isEmpty else { return .noChange }
        return MenuBarTimeFormatMigrationPlan(tokens: legacyTokens, twoLines: timeUnderTitle)
    }
}

/// Everything the composed presenter needs beyond the classic title/mode
/// snapshots. Built in the `+MeetingBar` adapter from `Defaults`.
struct MenuBarComposedSettings: Equatable {
    let presentation: StatusBarPresentationSettings
    let title: StatusBarTitleSettings
    let countdownStyle: CountdownStyle
    let dateStyle: MenuBarDateStyle
    let progressStyle: MenuBarProgressStyle
    let use24HourClock: Bool
    /// Time zone for the `.worldClock` token (defaults to the current zone).
    let worldClockTimeZone: TimeZone
    /// Optional short label prepended to the `.worldClock` token (e.g. `SF`).
    let worldClockLabel: String
    /// Localized prefix for the `.weekNumber` token (e.g. `W`, `KW`, `S`).
    let weekNumberPrefix: String
    let iconFormat: StatusBarIconFormat
    let iconFormatAssetName: String
    let iconAssets: StatusBarIconAssets
    /// Separator inserted between adjacent text tokens (icon excluded).
    let tokenSeparator: String
    let pendingDisplay: StatusBarParticipationDisplay
    let tentativeDisplay: StatusBarParticipationDisplay
    /// "Two lines" on the Menu Bar pane: the meeting title takes the first line
    /// and every other block sits under it in smaller type. Defaults to off (one
    /// line), which is also what keeps the memberwise init source-compatible.
    ///
    /// This is the capability the deleted `eventTimeFormat` control carried as
    /// `.show_under_title`. That value was read only by the classic status-bar
    /// path, so it silently did nothing for anyone who composed their menu bar;
    /// implementing it here is what makes the deletion lossless.
    var twoLines: Bool = false
}

/// Pure formatters for the new tokens. Hostless and fully unit-tested.
enum MenuBarCompositionPolicy {
    /// Cell count for the `.progress` token's Unicode-block bar. Fixed (not a
    /// user setting yet) so the composer stays simple; ~1/8-cell resolution is
    /// plenty for a menu-bar day/year indicator.
    static let progressBarWidth = 8

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

    /// The current time in `timeZone`, formatted like `clockText`, prefixed with
    /// a trimmed non-empty `label` (e.g. `SF 9:41`). Empty label yields the time
    /// alone. Differs from `clockText` only in pinning the chosen time zone.
    static func worldClockText(
        now: Date,
        timeZone: TimeZone,
        label: String,
        use24Hour: Bool,
        calendar: Calendar
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? Locale.current
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(use24Hour ? "Hmm" : "hmma")
        let time = formatter.string(from: now)
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLabel.isEmpty ? time : "\(trimmedLabel) \(time)"
    }

    /// ISO-8601 week number (e.g. `W29`) with a caller-supplied prefix.
    /// Computed on a dedicated ISO-8601 calendar (Monday-start, 4-day first
    /// week) — copying only the passed calendar's time zone and locale — so the
    /// result is correct near year boundaries regardless of the passed
    /// calendar's `firstWeekday`/`minimumDaysInFirstWeek`.
    static func weekNumberText(now: Date, calendar: Calendar, prefix: String) -> String {
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = calendar.timeZone
        isoCalendar.locale = calendar.locale ?? Locale.current
        let week = isoCalendar.component(.weekOfYear, from: now)
        return "\(prefix)\(week)"
    }

    /// Fraction (0...1) of the current calendar day elapsed at `now`. Uses the
    /// calendar's own day boundaries (not a hardcoded 86 400s) so DST-short and
    /// DST-long days stay correct.
    static func dayFraction(now: Date, calendar: Calendar) -> Double {
        let startOfDay = calendar.startOfDay(for: now)
        guard let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return 0 }
        let dayLength = startOfNextDay.timeIntervalSince(startOfDay)
        guard dayLength > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(startOfDay) / dayLength))
    }

    /// Fraction (0...1) of the current calendar year elapsed at `now`. Measures
    /// the actual year span (Jan 1 → next Jan 1), so leap years are automatic.
    static func yearFraction(now: Date, calendar: Calendar) -> Double {
        let year = calendar.component(.year, from: now)
        guard
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
            let startOfNextYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
        else { return 0 }
        let yearLength = startOfNextYear.timeIntervalSince(startOfYear)
        guard yearLength > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(startOfYear) / yearLength))
    }

    /// Fraction (0...1) for the chosen progress style.
    static func progressFraction(now: Date, style: MenuBarProgressStyle, calendar: Calendar) -> Double {
        switch style {
        case .day:
            return dayFraction(now: now, calendar: calendar)
        case .year:
            return yearFraction(now: now, calendar: calendar)
        }
    }

    /// Renders `fraction` (clamped to 0...1) as a fixed-width bar of `width`
    /// cells: full `█` cells, one partial eighth-block glyph for the fractional
    /// cell, and `░` for the remainder — e.g. `███▍░░░░`.
    static func progressBarText(fraction: Double, width: Int) -> String {
        guard width > 0 else { return "" }
        let clamped = min(1, max(0, fraction))
        let totalEighths = Int((clamped * Double(width) * 8).rounded(.down))
        let fullCells = min(totalEighths / 8, width)
        let remainder = totalEighths % 8
        let partials = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]

        var bar = String(repeating: "█", count: fullCells)
        var cellsUsed = fullCells
        if cellsUsed < width && remainder > 0 {
            bar += partials[remainder]
            cellsUsed += 1
        }
        if cellsUsed < width {
            bar += String(repeating: "░", count: width - cellsUsed)
        }
        return bar
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
        var segments: [(kind: MenuBarTokenKind, text: String)] = []

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
                if !text.isEmpty { segments.append((token, text)) }
            }
        }

        let lines = composedLines(segments: segments, settings: settings)
        let layout: StatusBarTitleLayout
        if lines.second != nil {
            layout = .stacked
        } else {
            layout = lines.first.isEmpty ? .none : .inline(showTime: false)
        }

        return StatusBarPresentation(
            mode: mode,
            title: lines.first,
            time: lines.second ?? "",
            tooltip: nextEvent.title,
            icon: icon,
            iconPosition: iconPosition,
            layout: layout,
            titleStyle: titleStyle(
                participation: nextEvent.participation,
                layout: layout,
                pendingDisplay: settings.pendingDisplay,
                tentativeDisplay: settings.tentativeDisplay
            ),
            removeDeliveredNotifications: false
        )
    }

    /// Splits the composed segments into the one or two lines the renderer draws.
    ///
    /// "Two lines" means the meeting title is the headline and everything else
    /// sits under it, wherever the user put the Title block — a stack whose top
    /// line was a countdown would not be a title with detail beneath it. When
    /// there is no title, or nothing to put under it, the request cannot mean
    /// anything, so the strip stays on one line rather than rendering an empty
    /// second row.
    private static func composedLines(
        segments: [(kind: MenuBarTokenKind, text: String)],
        settings: MenuBarComposedSettings
    ) -> (first: String, second: String?) {
        let joined = segments.map(\.text).joined(separator: settings.tokenSeparator)
        guard settings.twoLines,
              let titleIndex = segments.firstIndex(where: { $0.kind == .title })
        else { return (joined, nil) }

        let rest = segments.enumerated()
            .filter { $0.offset != titleIndex }
            .map(\.element.text)
            .joined(separator: settings.tokenSeparator)
        guard !rest.isEmpty else { return (joined, nil) }
        return (segments[titleIndex].text, rest)
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
        case .progress:
            return MenuBarCompositionPolicy.progressBarText(
                fraction: MenuBarCompositionPolicy.progressFraction(
                    now: now, style: settings.progressStyle, calendar: calendar
                ),
                width: MenuBarCompositionPolicy.progressBarWidth
            )
        case .weekNumber:
            return MenuBarCompositionPolicy.weekNumberText(
                now: now, calendar: calendar, prefix: settings.weekNumberPrefix
            )
        case .worldClock:
            return MenuBarCompositionPolicy.worldClockText(
                now: now,
                timeZone: settings.worldClockTimeZone,
                label: settings.worldClockLabel,
                use24Hour: settings.use24HourClock,
                calendar: calendar
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
            case .progress:
                let text = MenuBarCompositionPolicy.progressBarText(
                    fraction: MenuBarCompositionPolicy.progressFraction(
                        now: now, style: settings.progressStyle, calendar: calendar
                    ),
                    width: MenuBarCompositionPolicy.progressBarWidth
                )
                if !text.isEmpty { segments.append(text) }
            case .weekNumber:
                let text = MenuBarCompositionPolicy.weekNumberText(
                    now: now, calendar: calendar, prefix: settings.weekNumberPrefix
                )
                if !text.isEmpty { segments.append(text) }
            case .worldClock:
                let text = MenuBarCompositionPolicy.worldClockText(
                    now: now,
                    timeZone: settings.worldClockTimeZone,
                    label: settings.worldClockLabel,
                    use24Hour: settings.use24HourClock,
                    calendar: calendar
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
