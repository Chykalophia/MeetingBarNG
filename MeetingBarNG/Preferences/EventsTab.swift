//
//  EventsTab.swift
//  MeetingBarNG
//
//  What is left of the deleted "Events" tab: the per-event-row detail toggles.
//
//  "Events" is gone as a pane — events are content, not a place. Its filters
//  (which meetings exist at all) moved to `FiltersTab.swift`, and `EventsSection`
//  was deleted with them rather than left behind as a second implementation.
//  What remains here is `EventDetailSection`, which is about how the DROPDOWN
//  draws a row and is composed by the Dropdown pane; it becomes the Agenda block
//  gear in Phase 5. Until then it is a plain, fully reachable section, so nothing
//  is ever unreachable.
//
//  The event-row detail controls were split out of AppearanceTab.swift's
//  `MenuSection`, originally:
//    Created by Andrii Leitsius on 13.01.2021.
//    Copyright © 2021 Andrii Leitsius. All rights reserved.
//  Licensed under the Apache License, Version 2.0. Modified for MeetingBarNG by
//  Peter Krzyzek / Chykalophia, 2026: relocated into the Events tab; Phase 3
//  legibility pass — plain-language labels and a `PresetNumberPicker` for the
//  dropdown title-length setting; Phase 2 of the Preferences UX overhaul deleted
//  the `EventsTab` container and `EventsSection` (re-homed onto Filters).
//

import Defaults
import SwiftUI

// MARK: - How each event looks

/// The per-event-row detail toggles: end time, meeting-service icon, calendar
/// color, event details, and title shortening. Split out of the former
/// `MenuSection` (AppearanceTab.swift) so it can live on the Events tab.
struct EventDetailSection: View {
    @Default(.shortenEventTitle) var shortenEventTitle
    @Default(.menuEventTitleLength) var menuEventTitleLength
    @Default(.showEventEndTime) var showEventEndTime
    @Default(.showEventDetails) var showEventDetails
    @Default(.showMeetingServiceIcon) var showMeetingServiceIcon
    @Default(.showEventCalendarColor) var showEventCalendarColor
    @Default(.showMeetingPrepLinks) var showMeetingPrepLinks

    var body: some View {
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
            Toggle(
                preferenceLabel("preferences_appearance_menu_show_prep_links_value"),
                isOn: $showMeetingPrepLinks
            )
        }

        Section {
            Toggle(
                preferenceLabel("preferences_appearance_menu_shorten_event_title_toggle"),
                isOn: $shortenEventTitle
            )

            PresetNumberPicker(
                presets: [20, 30, 50, 80],
                presetLabel: { "\($0)" },
                customLabel: "preferences_preset_custom".loco(),
                value: $menuEventTitleLength,
                range: 20 ... 100,
                step: 5,
                stepperLabel: { "preferences_appearance_menu_shorten_event_title_stepper".loco($0) },
                example: "preferences_appearance_menu_shorten_event_title_example".loco(),
                isEnabled: shortenEventTitle
            )
        }
    }
}

#Preview {
    PreferencesGroupedForm {
        EventDetailSection()
    }
    .frame(width: 700, height: 420)
}
