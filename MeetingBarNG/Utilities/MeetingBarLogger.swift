//
//  MeetingBarLogger.swift
//  MeetingBar
//

import Foundation
import OSLog

enum MeetingBarLogger {
    private static let subsystem =
        Bundle.main.bundleIdentifier ?? "com.chykalophia.MeetingBarNG"

    static let calendar = Logger(subsystem: subsystem, category: "calendar-provider")
    static let meetingOpening = Logger(subsystem: subsystem, category: "meeting-opening")
    static let notifications = Logger(subsystem: subsystem, category: "notifications-snooze")
    static let onboarding = Logger(subsystem: subsystem, category: "onboarding")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle-tasks")
    static let camera = Logger(subsystem: subsystem, category: "camera-preview")
    static let preferences = Logger(subsystem: subsystem, category: "preferences")
}
