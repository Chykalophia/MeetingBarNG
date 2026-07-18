//
//  AppearanceTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  add the composable menu-bar composer section; adopt the shared
//  `.preferenceIndent()` modifier for dependent-row indents.
//

import Defaults
import SwiftUI

struct AppearanceTab: View {
    var body: some View {
        PreferencesGroupedForm {
            EventsSection()
            StatusBarSection()
            MenuBarComposerSection()
            MenuSection()
        }
    }
}

// MARK: - Events

struct EventsSection: View {
    @Default(.declinedEventsAppereance) var declinedEventsAppereance
    @Default(.personalEventsAppereance) var personalEventsAppereance
    @Default(.pastEventsAppereance) var pastEventsAppereance
    @Default(.allDayEvents) var allDayEvents
    @Default(.nonAllDayEvents) var nonAllDayEvents
    @Default(.showPendingEvents) var showPendingEvents
    @Default(.showTentativeEvents) var showTentativeEvents
    @Default(.showEventsForPeriod) var showEventsForPeriod

    var body: some View {
        Section(header: Text("preferences_appearance_events_title".loco())) {
            Picker(
                preferenceLabel("preferences_appearance_events_show_events_for_title"),
                selection: $showEventsForPeriod
            ) {
                Text("preferences_appearance_events_show_events_for_today_value".loco())
                    .tag(ShowEventsForPeriod.today)
                Text("preferences_appearance_events_show_events_for_today_tomorrow_value".loco())
                    .tag(ShowEventsForPeriod.today_n_tomorrow)
            }
        }

        Section {
            Picker(
                preferenceLabel("preferences_appearance_events_all_day_title"),
                selection: $allDayEvents
            ) {
                Text("preferences_appearance_events_value_show".loco())
                    .tag(AlldayEventsAppereance.show)
                Text("preferences_appearance_events_value_only_with_link".loco())
                    .tag(AlldayEventsAppereance.show_with_meeting_link_only)
                Text("preferences_appearance_events_value_hide".loco())
                    .tag(AlldayEventsAppereance.hide)
            }

            Picker(
                preferenceLabel("preferences_appearance_events_no_meeting_link_title"),
                selection: $nonAllDayEvents
            ) {
                Text("preferences_appearance_events_value_show".loco())
                    .tag(NonAlldayEventsAppereance.show)
                Text("preferences_appearance_events_value_as_inactive".loco())
                    .tag(NonAlldayEventsAppereance.show_inactive_without_meeting_link)
                Text("preferences_appearance_events_value_hide".loco())
                    .tag(NonAlldayEventsAppereance.hide_without_meeting_link)
            }

            Picker(
                preferenceLabel("preferences_appearance_events_without_guest_title"),
                selection: $personalEventsAppereance
            ) {
                Text("preferences_appearance_events_value_show".loco())
                    .tag(PastEventsAppereance.show_active)
                Text("preferences_appearance_events_value_as_inactive".loco())
                    .tag(PastEventsAppereance.show_inactive)
                Text("preferences_appearance_events_value_hide".loco())
                    .tag(PastEventsAppereance.hide)
            }
        }

        Section {
            Picker(
                preferenceLabel("preferences_appearance_events_pending_title"),
                selection: $showPendingEvents
            ) {
                Text("preferences_appearance_events_value_show".loco())
                    .tag(PendingEventsAppereance.show)
                Text("preferences_appearance_events_value_as_underlined".loco())
                    .tag(PendingEventsAppereance.show_underlined)
                Text("preferences_appearance_events_value_as_inactive".loco())
                    .tag(PendingEventsAppereance.show_inactive)
                Text("preferences_appearance_events_value_hide".loco())
                    .tag(PendingEventsAppereance.hide)
            }

            Picker(
                preferenceLabel("preferences_appearance_events_tentative_title"),
                selection: $showTentativeEvents
            ) {
                Text("preferences_appearance_events_value_show".loco())
                    .tag(TentativeEventsAppereance.show)
                Text("preferences_appearance_events_value_as_underlined".loco())
                    .tag(TentativeEventsAppereance.show_underlined)
                Text("preferences_appearance_events_value_as_inactive".loco())
                    .tag(TentativeEventsAppereance.show_inactive)
                Text("preferences_appearance_events_value_hide".loco())
                    .tag(TentativeEventsAppereance.hide)
            }

            Picker(
                preferenceLabel("preferences_appearance_events_declined_title"),
                selection: $declinedEventsAppereance
            ) {
                Text("preferences_appearance_events_value_with_strikethrough".loco())
                    .tag(DeclinedEventsAppereance.strikethrough)
                Text("preferences_appearance_events_value_as_inactive".loco())
                    .tag(DeclinedEventsAppereance.show_inactive)
                Text("preferences_appearance_events_value_hide".loco())
                    .tag(DeclinedEventsAppereance.hide)
            }

            Picker(
                preferenceLabel("preferences_appearance_events_past_title"),
                selection: $pastEventsAppereance
            ) {
                Text("preferences_appearance_events_value_show".loco())
                    .tag(PastEventsAppereance.show_active)
                Text("preferences_appearance_events_value_as_inactive".loco())
                    .tag(PastEventsAppereance.show_inactive)
                Text("preferences_appearance_events_value_hide".loco())
                    .tag(PastEventsAppereance.hide)
            }
        }
    }
}

// MARK: - Status bar

struct StatusBarSection: View {
    @Default(.eventTitleIconFormat) var eventTitleIconFormat
    @Default(.eventTitleFormat) var eventTitleFormat
    @Default(.eventTimeFormat) var eventTimeFormat
    @Default(.statusbarEventTitleLength) var statusbarEventTitleLength
    @Default(.showEventMaxTimeUntilEventThreshold) var showEventMaxTimeUntilEventThreshold
    @Default(.showEventMaxTimeUntilEventEnabled) var showEventMaxTimeUntilEventEnabled
    @Default(.ongoingEventVisibility) var ongoingEventVisibility

    var body: some View {
        Section(header: Text("preferences_appearance_status_bar_title".loco())) {
            Picker(
                preferenceLabel("preferences_appearance_status_bar_icon_title"),
                selection: $eventTitleIconFormat
            ) {
                HStack {
                    Image(nsImage: getImage(iconName: EventTitleIconFormat.calendar.rawValue))
                        .resizable()
                        .frame(width: 16.0, height: 16.0)
                    Text("preferences_appearance_status_bar_icon_calendar_icon_value".loco())
                }.tag(EventTitleIconFormat.calendar)

                HStack {
                    Image(nsImage: getImage(iconName: EventTitleIconFormat.appicon.rawValue))
                        .resizable()
                        .frame(width: 16.0, height: 16.0)
                    Text("preferences_appearance_status_bar_icon_app_icon_value".loco())
                }.tag(EventTitleIconFormat.appicon)

                HStack {
                    Image(nsImage: getImage(iconName: EventTitleIconFormat.eventtype.rawValue))
                        .resizable()
                        .frame(width: 16.0, height: 16.0)
                    Text("preferences_appearance_status_bar_icon_specific_icon_value".loco())
                }.tag(EventTitleIconFormat.eventtype)

                HStack {
                    Image(nsImage: getImage(iconName: EventTitleIconFormat.none.rawValue))
                        .resizable()
                        .frame(width: 16.0, height: 16.0)
                    Text("preferences_appearance_status_bar_icon_no_icon_value".loco())
                }.tag(EventTitleIconFormat.none)
            }

            Picker(
                preferenceLabel("preferences_appearance_status_bar_title_title"),
                selection: $eventTitleFormat
            ) {
                Text("preferences_appearance_status_bar_title_event_title_value".loco())
                    .tag(EventTitleFormat.show)
                Text("preferences_appearance_status_bar_title_generic_value".loco())
                    .tag(EventTitleFormat.generic)
                Text("preferences_appearance_status_bar_title_dot_value".loco())
                    .tag(EventTitleFormat.dot)
                Text("preferences_appearance_status_bar_title_hide_value".loco())
                    .tag(EventTitleFormat.none)
            }

            HStack {
                Spacer()
                Stepper(
                    value: $statusbarEventTitleLength,
                    in: statusbarEventTitleLengthLimits.min ... statusbarEventTitleLengthLimits.max,
                    step: 5
                ) {
                    Text(
                        "preferences_appearance_status_bar_title_shorten_stepper".loco(
                            statusbarEventTitleLength)
                    )
                    .monospacedDigit()
                }
                .fixedSize()
            }
            .preferenceIndent()
            .disabled(eventTitleFormat != .show)

            Picker(
                preferenceLabel("preferences_appearance_status_bar_time_title"),
                selection: $eventTimeFormat
            ) {
                ForEach(PreferencesStatusBarTimeOption.allCases, id: \.format) { option in
                    Text(option.titleKey.loco()).tag(option.format)
                }
            }
        }

        Section {
            Toggle(
                preferenceLabel("preferences_appearance_status_bar_next_event_toggle"),
                isOn: $showEventMaxTimeUntilEventEnabled
            )

            HStack {
                Spacer()
                Stepper(
                    value: $showEventMaxTimeUntilEventThreshold,
                    in: 5 ... 720,
                    step: 5
                ) {
                    Text(
                        "preferences_appearance_status_bar_next_event_stepper".loco(
                            showEventMaxTimeUntilEventThreshold)
                    )
                    .monospacedDigit()
                }
                .fixedSize()
            }
            .preferenceIndent()
            .disabled(!showEventMaxTimeUntilEventEnabled)

            Picker(
                preferenceLabel("preferences_appearance_status_bar_ongoing_title"),
                selection: $ongoingEventVisibility
            ) {
                Text("preferences_appearance_status_bar_ongoing_time_immediate_value".loco())
                    .tag(OngoingEventVisibility.hideImmediateAfter)
                Text("preferences_appearance_status_bar_ongoing_time_ten_after_value".loco())
                    .tag(OngoingEventVisibility.showTenMinAfter)
                Text("preferences_appearance_status_bar_ongoing_time_ten_before_next_value".loco())
                    .tag(OngoingEventVisibility.showTenMinBeforeNext)
            }
        }
    }

    func getImage(iconName: String) -> NSImage {
        let icon = NSImage(named: iconName)
        icon!.size = NSSize(width: 16, height: 16)
        return icon!
    }
}

// MARK: - Composable menu bar (MeetingBarNG)

/// Lets the user compose the menu-bar title from ordered tokens. When no tokens
/// are set, the classic `StatusBarSection` settings drive the menu bar, so
/// existing installs are unaffected until the user opts in here.
struct MenuBarComposerSection: View {
    @Default(.menuBarTokens) var menuBarTokens
    @Default(.menuBarCountdownStyle) var menuBarCountdownStyle
    @Default(.menuBarDateStyle) var menuBarDateStyle

    private var tokens: [MenuBarTokenKind] {
        var seen = Set<MenuBarTokenKind>()
        return menuBarTokens
            .compactMap(MenuBarTokenKind.init(rawValue:))
            .filter { seen.insert($0).inserted }
    }

    private var isEnabled: Bool { !tokens.isEmpty }

    private var availableTokens: [MenuBarTokenKind] {
        MenuBarTokenKind.allCases.filter { !tokens.contains($0) }
    }

    var body: some View {
        Section(header: Text("preferences_appearance_menu_bar_composer_title".loco())) {
            Toggle(
                preferenceLabel("preferences_appearance_menu_bar_composer_enable_toggle"),
                isOn: enabledBinding
            )
            Text("preferences_appearance_menu_bar_composer_hint".loco())
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if isEnabled {
            Section {
                ForEach(Array(tokens.enumerated()), id: \.element) { pair in
                    tokenRow(token: pair.element, index: pair.offset)
                }
                if !availableTokens.isEmpty {
                    Menu {
                        ForEach(availableTokens, id: \.self) { token in
                            Button(tokenName(token)) { add(token) }
                        }
                    } label: {
                        Label(
                            "preferences_appearance_menu_bar_composer_add".loco(),
                            systemImage: "plus"
                        )
                    }
                }
            }

            if tokens.contains(.countdown) {
                Section {
                    Picker(
                        preferenceLabel("preferences_appearance_menu_bar_countdown_style_title"),
                        selection: countdownStyleBinding
                    ) {
                        Text("preferences_appearance_menu_bar_countdown_style_compact_value".loco())
                            .tag(CountdownStyle.compact)
                        Text("preferences_appearance_menu_bar_countdown_style_full_value".loco())
                            .tag(CountdownStyle.full)
                        Text("preferences_appearance_menu_bar_countdown_style_digital_value".loco())
                            .tag(CountdownStyle.digital)
                    }
                }
            }

            if tokens.contains(.date) {
                Section {
                    Picker(
                        preferenceLabel("preferences_appearance_menu_bar_date_style_title"),
                        selection: dateStyleBinding
                    ) {
                        Text("preferences_appearance_menu_bar_date_style_weekday_value".loco())
                            .tag(MenuBarDateStyle.weekday)
                        Text("preferences_appearance_menu_bar_date_style_medium_value".loco())
                            .tag(MenuBarDateStyle.medium)
                        Text("preferences_appearance_menu_bar_date_style_short_value".loco())
                            .tag(MenuBarDateStyle.short)
                    }
                }
            }

            Section(header: Text("preferences_appearance_menu_bar_composer_preview_label".loco())) {
                previewChip
            }
        }
    }

    // MARK: Rows

    private func tokenRow(token: MenuBarTokenKind, index: Int) -> some View {
        HStack {
            Text(tokenName(token))
            Spacer()
            Button { move(from: index, by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("preferences_appearance_menu_bar_composer_move_up".loco())

            Button { move(from: index, by: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == tokens.count - 1)
            .help("preferences_appearance_menu_bar_composer_move_down".loco())

            Button { remove(token) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("preferences_appearance_menu_bar_composer_remove".loco())
        }
    }

    @ViewBuilder
    private var previewChip: some View {
        let presentation = previewPresentation
        HStack(spacing: 4) {
            if presentation.iconPosition == .leading {
                previewIcon(presentation.icon)
            }
            if !presentation.title.isEmpty {
                Text(presentation.title)
                    .font(.system(size: MenuStyleConstants.defaultFontSize))
            }
            if presentation.iconPosition == .trailing {
                previewIcon(presentation.icon)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.08))
        )
    }

    @ViewBuilder
    private func previewIcon(_ icon: StatusBarIcon) -> some View {
        switch icon {
        case .asset(let name):
            Image(nsImage: MenuStyleConstants.iconNamed(name))
                .resizable()
                .frame(width: 16, height: 16)
        case .meetingService(let service):
            Image(nsImage: getIconForMeetingService(service))
                .resizable()
                .frame(width: 16, height: 16)
        case .none:
            EmptyView()
        }
    }

    // MARK: Data

    private func tokenName(_ token: MenuBarTokenKind) -> String {
        switch token {
        case .icon: return "preferences_appearance_menu_bar_token_icon".loco()
        case .title: return "preferences_appearance_menu_bar_token_title".loco()
        case .countdown: return "preferences_appearance_menu_bar_token_countdown".loco()
        case .date: return "preferences_appearance_menu_bar_token_date".loco()
        case .clock: return "preferences_appearance_menu_bar_token_clock".loco()
        }
    }

    private var previewPresentation: StatusBarPresentation {
        let now = Date()
        var calendar = Calendar.current
        calendar.locale = I18N.instance.locale
        let sample = StatusBarEventPresentationInput(
            title: "preferences_appearance_menu_bar_preview_sample_event".loco(),
            startDate: now.addingTimeInterval(25 * 60),
            endDate: now.addingTimeInterval(55 * 60),
            // A representative service so the "event type" icon format previews a
            // real glyph rather than the no-session fallback.
            meetingService: .zoom,
            participation: .normal
        )
        return StatusBarPresenter.composedPresentation(
            nextEvent: sample,
            composition: MenuBarComposition(tokens: tokens),
            settings: .current,
            now: now,
            calendar: calendar
        )
    }

    // MARK: Mutation

    private func write(_ newTokens: [MenuBarTokenKind]) {
        menuBarTokens = newTokens.map(\.rawValue)
    }

    private func move(from index: Int, by offset: Int) {
        var updated = tokens
        let target = index + offset
        guard updated.indices.contains(index), updated.indices.contains(target) else { return }
        updated.swapAt(index, target)
        write(updated)
    }

    private func remove(_ token: MenuBarTokenKind) {
        write(tokens.filter { $0 != token })
    }

    private func add(_ token: MenuBarTokenKind) {
        guard !tokens.contains(token) else { return }
        write(tokens + [token])
    }

    // MARK: Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { isOn in
                if isOn {
                    if tokens.isEmpty { write(MenuBarComposition.derivedFromLegacy.tokens) }
                } else {
                    menuBarTokens = []
                }
            }
        )
    }

    private var countdownStyleBinding: Binding<CountdownStyle> {
        Binding(
            get: { CountdownStyle(rawValue: menuBarCountdownStyle) ?? .full },
            set: { menuBarCountdownStyle = $0.rawValue }
        )
    }

    private var dateStyleBinding: Binding<MenuBarDateStyle> {
        Binding(
            get: { MenuBarDateStyle(rawValue: menuBarDateStyle) ?? .medium },
            set: { menuBarDateStyle = $0.rawValue }
        )
    }
}

// MARK: - Menu

struct MenuSection: View {
    @Default(.shortenEventTitle) var shortenEventTitle
    @Default(.menuEventTitleLength) var menuEventTitleLength
    @Default(.showEventEndTime) var showEventEndTime
    @Default(.showEventDetails) var showEventDetails
    @Default(.showMeetingServiceIcon) var showMeetingServiceIcon
    @Default(.showEventCalendarColor) var showEventCalendarColor
    @Default(.showTimelineInMenu) var showTimelineInMenu
    @Default(.hideFinishedEventsInMenu) var hideFinishedEventsInMenu

    var body: some View {
        Section(header: Text("preferences_appearance_menu_title".loco())) {
            Toggle(
                preferenceLabel("preferences_appearance_menu_show_timeline_toggle"),
                isOn: $showTimelineInMenu
            )
            Toggle(
                preferenceLabel("preferences_appearance_menu_hide_finished_toggle"),
                isOn: $hideFinishedEventsInMenu
            )
        }

        Section(header: Text(preferenceLabel("preferences_appearance_menu_show_event_title"))) {
            Toggle(
                preferenceLabel("preferences_appearance_menu_show_event_end_time_value"),
                isOn: $showEventEndTime
            )
            Toggle(
                preferenceLabel("preferences_appearance_menu_show_event_icon_value"),
                isOn: $showMeetingServiceIcon
            )
            Toggle(
                preferenceLabel("preferences_appearance_menu_show_event_calendar_color_value"),
                isOn: $showEventCalendarColor
            )
            Toggle(
                preferenceLabel("preferences_appearance_menu_show_event_details_value"),
                isOn: $showEventDetails
            )
        }

        Section {
            Toggle(
                preferenceLabel("preferences_appearance_menu_shorten_event_title_toggle"),
                isOn: $shortenEventTitle
            )

            HStack {
                Spacer()
                Stepper(
                    value: $menuEventTitleLength,
                    in: 20 ... 100,
                    step: 5
                ) {
                    Text(
                        "preferences_appearance_menu_shorten_event_title_stepper".loco(
                            menuEventTitleLength)
                    )
                    .monospacedDigit()
                }
                .fixedSize()
            }
            .preferenceIndent()
            .disabled(!shortenEventTitle)
        }
    }
}

#Preview {
    AppearanceTab().frame(width: 700, height: 620)
}
