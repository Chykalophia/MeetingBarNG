//
//  Shared.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  adopt the shared `.preferenceIndent()` modifier for dependent-row indents;
//  Preferences UX overhaul Phase 0 replaces the synchronous, main-thread-blocking
//  `checkNotificationSettings()` with the cached async `NotificationSettingsMonitor`.
//

import AppKit
import Defaults
import Foundation
import LaunchAtLogin
import Observation
import SwiftUI
import UserNotifications

/// The macOS notification settings the Alerts pane's delivery row depends on,
/// read **asynchronously** and cached.
///
/// This replaced a synchronous helper that did `DispatchGroup.wait()` on the main
/// thread from a computed property SwiftUI re-evaluates on every body render —
/// which blocked the render pass and made the captions flicker. The values are
/// stable between app activations, so one cached copy refreshed on
/// `didBecomeActive` is both correct and free.
///
/// The four notification picker views that used to live here moved onto the
/// Alerts pane (`Preferences/AlertsTab.swift`) in Phase 2, where their timing
/// pickers finally got labels and their two dead-end captions became one row
/// with a button. Only this monitor is genuinely shared machinery.
@MainActor
@Observable
final class NotificationSettingsMonitor {
    static let shared = NotificationSettingsMonitor()

    /// What actually reaches the user. The mapping itself is hostless and
    /// tested (`Preferences/AlertsPresentation.swift`); the only thing that has
    /// to happen here is reading macOS.
    private(set) var delivery: NotificationDelivery = .persistent

    private init() {}

    func refresh() async {
        // https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/notificationsettings()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        delivery = NotificationDeliveryPolicy.resolve(
            authorization: NotificationAuthorization(settings.authorizationStatus),
            staysOnscreen: settings.alertStyle == .alert
        )
    }
}

extension NotificationAuthorization {
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        default:
            // .authorized, .provisional, .ephemeral — macOS will deliver.
            self = .allowed
        }
    }
}

// `LaunchAtLoginANDPreferredLanguagePicker` was deleted here by the Preferences
// UX overhaul (Phase 2). Its name literally contained "AND" because it was two
// unrelated controls in one view: General now renders the launch-at-login toggle
// itself, and the LANGUAGE PICKER is gone — 16 languages against one maintained
// catalog, `ukrainian` mapping to "ua" while the shipped bundle is `uk.lproj`,
// and seven shipped bundles with no entry at all. See the header of
// `GeneralTab.swift` for the full reasoning and for what restoring it takes.
// `Defaults[.preferredLanguage]` is RETAINED and still applied at launch, so
// this deletes a control, not a capability.
