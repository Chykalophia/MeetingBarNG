//
//  AlertsPresentation.swift
//  MeetingBarNG
//
//  Hostless permission-state mapping for the Alerts pane (Preferences UX
//  overhaul, Phase 2).
//
//  The pane's job is to say what macOS *actually* does with MeetingBarNG's
//  notifications — and to say nothing at all when the answer is "they arrive
//  and they stay". The old tab shipped two advisory captions that were computed
//  in the view, phrased as instructions ("switch to Alerts in your macOS
//  notification settings"), and led nowhere. Here the state is one value, and
//  every state that is not calm carries a real button.
//
//  Deliberately hostless: no UserNotifications, no SwiftUI, no Defaults. The
//  app maps `UNAuthorizationStatus` / `UNAlertStyle` onto these cases at the
//  edge (`UI/Views/Shared.swift`), so the decision itself is unit-tested
//  without a host app (`MeetingBarLogicTests/AlertsPresentationTests.swift`).
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

/// Whether macOS has been asked, and what it said.
enum NotificationAuthorization: String, CaseIterable, Sendable {
    /// macOS has not been asked yet, so nothing is delivered.
    case notDetermined
    /// Switched off in System Settings.
    case denied
    /// Allowed to deliver.
    case allowed
}

/// What actually reaches the user — which is what the pane must state.
enum NotificationDelivery: String, CaseIterable, Sendable {
    /// Nothing arrives.
    case blocked
    /// Banners: they arrive, then vanish on their own.
    case disappearing
    /// Alerts: they stay onscreen until dismissed.
    case persistent

    /// Localization key of the advisory line, or `nil` when there is nothing to
    /// say. The silence is deliberate: the deleted Advanced tab proved that a
    /// warning stamped across a screen regardless of state becomes wallpaper
    /// and stops meaning anything.
    var messageKey: String? {
        switch self {
        case .blocked: "preferences_alerts_disabled_tip"
        case .disappearing: "preferences_alerts_banner_style_tip"
        case .persistent: nil
        }
    }

    /// Whether this reads as a failure (nothing gets through) rather than as
    /// advice (they get through, they just do not linger).
    var isProblem: Bool { self == .blocked }

    /// Whether the pane shows the "Open notification settings" button. Anything
    /// worth telling the user about is worth giving them a way to fix.
    var offersSettingsButton: Bool { messageKey != nil }

    /// The button that replaces "go and find it in System Settings yourself".
    static let settingsButtonKey = "preferences_alerts_open_notification_settings"
}

enum NotificationDeliveryPolicy {
    /// - Parameters:
    ///   - authorization: what macOS has been asked and answered.
    ///   - staysOnscreen: the Alerts style, rather than Banners.
    static func resolve(
        authorization: NotificationAuthorization,
        staysOnscreen: Bool
    ) -> NotificationDelivery {
        switch authorization {
        // Not-yet-asked is grouped with denied on purpose: in both states the
        // toggles below deliver nothing, and claiming otherwise is the lie the
        // old captions told.
        case .notDetermined, .denied:
            .blocked
        case .allowed:
            staysOnscreen ? .persistent : .disappearing
        }
    }
}
