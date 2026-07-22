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
/// colour dot, prep links, and title shortening. Split out of the former
/// `MenuSection` (AppearanceTab.swift) so it can live on the Dropdown pane.
/// `showEventDetails` was deleted per the UX plan — the panel's inline chevron
/// is always available and costs nothing collapsed.
struct EventDetailSection: View {
    @Default(.shortenEventTitle) var shortenEventTitle
    @Default(.menuEventTitleLength) var menuEventTitleLength
    @Default(.showEventEndTime) var showEventEndTime
    @Default(.showMeetingServiceIcon) var showMeetingServiceIcon
    @Default(.showEventCalendarColor) var showEventCalendarColor
    @Default(.showMeetingPrepLinks) var showMeetingPrepLinks

    var body: some View {
        Section(header: Text(preferenceLabel("preferences_dropdown_rows_title"))) {
            Toggle(
                preferenceLabel("preferences_dropdown_rows_end_time_toggle"),
                isOn: $showEventEndTime
            )
            Toggle(
                preferenceLabel("preferences_dropdown_rows_service_icon_toggle"),
                isOn: $showMeetingServiceIcon
            )
            Toggle(
                preferenceLabel("preferences_dropdown_rows_calendar_color_toggle"),
                isOn: $showEventCalendarColor
            )
            Toggle(
                preferenceLabel("preferences_dropdown_rows_prep_links_toggle"),
                isOn: $showMeetingPrepLinks
            )
        }

        Section {
            Toggle(
                preferenceLabel("preferences_dropdown_rows_shorten_toggle"),
                isOn: $shortenEventTitle
            )

            PresetNumberPicker(
                presets: [20, 30, 50, 80],
                presetLabel: { "\($0)" },
                customLabel: "preferences_preset_custom".loco(),
                value: $menuEventTitleLength,
                range: 20 ... 100,
                step: 5,
                stepperLabel: { "preferences_dropdown_rows_shorten_stepper".loco($0) },
                example: "preferences_dropdown_rows_shorten_example".loco(),
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
