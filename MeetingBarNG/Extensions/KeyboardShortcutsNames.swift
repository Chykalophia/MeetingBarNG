//
//  KeyboardShortcutsNames.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  register the camera/mic pre-call preview ("mirror check") shortcut name.
//

import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let createMeetingShortcut = Self("createMeetingShortcut")
    static let openMenuShortcut = Self("openMenuShortcut")
    static let joinEventShortcut = Self("joinEventShortcut")
    static let openClipboardShortcut = Self("openClipboardShortcut")
    static let toggleMeetingTitleVisibilityShortcut = Self("toggleMeetingTitleVisibilityShortcut")
    static let commandBarShortcut = Self("commandBarShortcut")
    static let calendarShortcut = Self("calendarShortcut")
    static let newEventShortcut = Self("newEventShortcut")
    static let cameraPreviewShortcut = Self("cameraPreviewShortcut")
}
