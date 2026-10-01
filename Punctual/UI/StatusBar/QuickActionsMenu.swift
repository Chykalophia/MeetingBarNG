//
//  QuickActionsMenu.swift
//  MeetingBarNG
//
//  The compact menu shown when the status item is RIGHT-clicked: power-user
//  actions without opening the agenda.
//
//  Extracted from `MenuBuilder` when the classic NSMenu dropdown was retired.
//  This menu is not part of that path — it shows on a right-click regardless of
//  which dropdown is in use, and the panel's "More actions" flyout mirrors it
//  rather than replacing it.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit

enum QuickActionsMenu {
    /// Items target `target`'s existing @objc handlers, the same ones the panel's
    /// flyout runs through `DropdownPanelHandlers`.
    @MainActor
    static func build(target: AnyObject, state: StatusBarMenuState) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let join = item(
            "status_bar_quick_action_join_next",
            #selector(StatusBarItemController.joinNextMeeting),
            target: target
        )
        join.isEnabled = state.nextEvent?.meetingLink != nil
        menu.addItem(join)

        menu.addItem(item(
            "status_bar_quick_action_create_meeting",
            #selector(StatusBarItemController.createMeetingAction),
            target: target
        ))
        // In-app event creation (EventKit only). Google-backed calendars are
        // written through the macOS Calendar app's sync, so the write path is
        // EventKit-only; hide the entry for the Google provider.
        if state.activeProvider == .macOSEventKit {
            menu.addItem(item(
                "status_bar_quick_action_new_event",
                #selector(StatusBarItemController.newEventAction),
                target: target
            ))
        }
        menu.addItem(item(
            "status_bar_quick_action_copy_agenda",
            #selector(StatusBarItemController.copyTodayAgendaAction),
            target: target
        ))

        menu.addItem(.separator())

        menu.addItem(item(
            "status_bar_quick_action_open_calendar",
            #selector(StatusBarItemController.openCalendarAction),
            target: target
        ))
        menu.addItem(item(
            "status_bar_quick_action_world_clock",
            #selector(StatusBarItemController.openWorldClockAction),
            target: target
        ))
        menu.addItem(item(
            "status_bar_quick_action_camera_check",
            #selector(StatusBarItemController.openCameraPreviewAction),
            target: target
        ))
        menu.addItem(item(
            "status_bar_quick_action_refresh",
            #selector(StatusBarItemController.handleManualRefresh),
            target: target
        ))
        menu.addItem(item(
            "status_bar_quick_action_preferences",
            #selector(StatusBarItemController.openPreferencesAction),
            target: target
        ))

        menu.addItem(.separator())

        menu.addItem(item(
            "status_bar_quick_action_quit",
            #selector(StatusBarItemController.quitAction),
            target: target
        ))

        return menu
    }

    @MainActor
    private static func item(
        _ titleKey: String,
        _ action: Selector,
        target: AnyObject
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: titleKey.loco(), action: action, keyEquivalent: "")
        menuItem.target = target
        return menuItem
    }
}
