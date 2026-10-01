//
//  SoftwareUpdater.swift
//  Punctual
//
//  Sparkle-based "check for updates and install". The feed (SUFeedURL), the
//  EdDSA public key that every update must be signed with (SUPublicEDKey) and
//  the sandbox installer service are configured in Info.plist; this class owns
//  the updater's lifetime and exposes what the UI needs.
//
//  An update is only installed if its EdDSA signature verifies against the key
//  built into this app AND it is signed with the same Developer ID. Sparkle
//  enforces both; nothing here relaxes either.
//
//  Original work for Punctual by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit
import Combine
import Sparkle

@MainActor
final class SoftwareUpdater: NSObject, ObservableObject {
    static let shared = SoftwareUpdater()

    /// False while a check is already running, so "Check for Updates…" can be
    /// disabled instead of queueing a second one.
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?

    private var controller: SPUStandardUpdaterController?
    private var cancellables: Set<AnyCancellable> = []

    private var updater: SPUUpdater? { controller?.updater }

    /// Starts the updater once per launch. Never during tests: a test host must
    /// not reach the network or show Sparkle's permission prompt.
    func start() {
        guard controller == nil, !AppMessageCenter.shouldSuppressSystemUI() else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        self.controller = controller
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.lastUpdateCheckDate = $0 }
            .store(in: &cancellables)
    }

    /// User-initiated check. Punctual is a menu-bar (accessory) app, so it is
    /// activated first; otherwise Sparkle's window opens behind other apps.
    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            updater?.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set {
            objectWillChange.send()
            updater?.automaticallyDownloadsUpdates = newValue
        }
    }

    /// Whether the updater is running at all (false in tests and before launch
    /// finishes), so the UI can hide controls that would do nothing.
    var isAvailable: Bool { controller != nil }
}

extension SoftwareUpdater: SPUUpdaterDelegate {}

extension SoftwareUpdater: SPUStandardUserDriverDelegate {
    /// A scheduled check that finds an update shows Sparkle's window. Bring the
    /// app forward so that window is actually seen: an accessory app's windows
    /// otherwise open behind whatever the user is working in. Happens at most
    /// once per check interval (a day by default).
    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
