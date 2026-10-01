//
//  SoftwareUpdater.swift
//  Punctual
//
//  Sparkle-based "check for updates and install". The feed (SUFeedURL), the
//  EdDSA public key (SUPublicEDKey), a signed feed (SURequireSignedFeed),
//  verification before extraction, and the sandbox installer service are
//  configured in Info.plist; this class owns the updater's lifetime and
//  exposes what the UI needs.
//
//  What Sparkle accepts (read in its source, SUUpdateValidator.m): an update
//  installs if its EdDSA signature verifies against the key built into this
//  app, OR its Developer ID signature matches this app's team. The "or" is
//  Sparkle's design, for key rotation. Every Punctual release is signed both
//  ways, and the feed itself must carry a valid EdDSA signature.
//
//  Original work for Punctual by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit
import Combine
import Defaults
import Sparkle
import UserNotifications

@MainActor
final class SoftwareUpdater: NSObject, ObservableObject {
    static let shared = SoftwareUpdater()

    /// Identifier of the "update available" notification, so a tap on it can
    /// be routed here rather than to the meeting-notification handlers.
    nonisolated static let updateNotificationIdentifier = "punctual.software-update-available"

    /// False while a check is already running, so "Check for Updates…" can be
    /// disabled instead of queueing a second one.
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false

    private var controller: SPUStandardUpdaterController?
    private var cancellables: Set<AnyCancellable> = []

    /// Debug builds run from Xcode/DerivedData would otherwise check the
    /// public feed and could replace a development build with the release.
    /// They opt in explicitly with PUNCTUAL_ENABLE_UPDATER=1.
    static var isEnabledInThisBuild: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["PUNCTUAL_ENABLE_UPDATER"] == "1"
        #else
        return true
        #endif
    }

    /// Starts the updater once per launch. Never in a test host: it must not
    /// reach the network or show Sparkle's permission prompt.
    func start() {
        guard controller == nil,
              Self.isEnabledInThisBuild,
              !AppMessageCenter.shouldSuppressSystemUI() else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        self.controller = controller
        let updater = controller.updater
        bind(updater.publisher(for: \.canCheckForUpdates), to: \.canCheckForUpdates)
        bind(updater.publisher(for: \.automaticallyChecksForUpdates), to: \.automaticallyChecksForUpdates)
        bind(updater.publisher(for: \.automaticallyDownloadsUpdates), to: \.automaticallyDownloadsUpdates)
        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.lastUpdateCheckDate = $0 }
            .store(in: &cancellables)
    }

    private func bind(
        _ publisher: some Publisher<Bool, Never>,
        to keyPath: ReferenceWritableKeyPath<SoftwareUpdater, Bool>
    ) {
        publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?[keyPath: keyPath] = $0 }
            .store(in: &cancellables)
    }

    /// User-initiated check (menu, Preferences, or tapping the "update
    /// available" notification). Punctual is a menu-bar (accessory) app, so it
    /// is activated first; otherwise Sparkle's window opens behind other apps.
    /// Activation is only ever on a direct user action, never on a schedule.
    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ value: Bool) {
        controller?.updater.automaticallyChecksForUpdates = value
    }

    func setAutomaticallyDownloadsUpdates(_ value: Bool) {
        controller?.updater.automaticallyDownloadsUpdates = value
    }

    /// Whether the updater is running at all (false in tests, in Debug builds
    /// that did not opt in, and before launch finishes).
    var isAvailable: Bool { controller != nil }

    /// Tap on the "update available" notification: bring the update forward.
    func handleUpdateNotificationTapped() {
        checkForUpdates()
    }

    private func postUpdateAvailableNotification(version: String) {
        let content = UNMutableNotificationContent()
        content.title = "software_update_available_title".loco()
        content.body = "software_update_available_body".loco(version)
        let request = UNNotificationRequest(
            identifier: Self.updateNotificationIdentifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func clearUpdateAvailableNotification() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.updateNotificationIdentifier])
        center.removePendingNotificationRequests(withIdentifiers: [Self.updateNotificationIdentifier])
    }
}

extension SoftwareUpdater: SPUUpdaterDelegate {
    /// Sparkle asks "Check for updates automatically?" on the second launch.
    /// Never during first-run setup: wait until setup is finished (it asks on
    /// a later launch instead).
    nonisolated func updaterShouldPromptForPermissionToCheck(forUpdates _: SPUUpdater) -> Bool {
        MainActor.assumeIsolated { Defaults[.onboardingCompleted] }
    }
}

extension SoftwareUpdater: SPUStandardUserDriverDelegate {
    /// Gentle reminders: a scheduled check never pulls Punctual in front of
    /// what the user is doing, which for a meeting app may be a call or a
    /// screen share.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Let Sparkle show its window for a scheduled update only when that is
    /// already in focus (just launched, or Punctual is active). Otherwise a
    /// notification says an update is available, and tapping it opens it.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate, !state.userInitiated else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            postUpdateAvailableNotification(version: version)
        }
    }

    /// The user has seen the update (window shown or acted on): the reminder
    /// notification is no longer needed.
    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
        MainActor.assumeIsolated { clearUpdateAvailableNotification() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { clearUpdateAvailableNotification() }
    }
}
