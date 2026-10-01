//
//  RemindersSync.swift
//  MeetingBarNG
//
//  @MainActor store of the reminders shown in the menu (Dot parity). Mirrors
//  `CalendarSync` but much simpler: publishes `[MBReminder]` and refreshes on
//  `.EKEventStoreChanged`, a periodic timer, and a manual subject. Only fetches
//  when the feature is enabled AND reminders access has been granted, so a
//  disabled or unauthorized install never touches EventKit here.
//
//  Created for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Combine
import Defaults
import EventKit
import Foundation

@MainActor
final class RemindersSync: ObservableObject {
    @Published private(set) var reminders: [MBReminder] = []

    private let store: RemindersStore
    private let refreshInterval: TimeInterval
    let refreshSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?

    init(store: RemindersStore, refreshInterval: TimeInterval = 180) {
        self.store = store
        self.refreshInterval = refreshInterval
        setupPublishers()
    }

    private func setupPublishers() {
        // A) External Reminders edits (Reminders.app, other devices via iCloud).
        let storeChangedPub = NotificationCenter.default
            .publisher(for: .EKEventStoreChanged)
            .map { _ in () }
            .eraseToAnyPublisher()

        // B) Feature toggles that change what is shown.
        let defaultsPub = Defaults.publisher(
            keys: .showRemindersInMenu, .remindersIncludeOverdue, options: []
        )
        .map { _ in () }
        .eraseToAnyPublisher()

        // C) Periodic timer.
        let timerPub: AnyPublisher<Void, Never>
        if refreshInterval > 0 {
            timerPub = Timer
                .publish(every: refreshInterval, on: .main, in: .common)
                .autoconnect()
                .map { _ in () }
                .eraseToAnyPublisher()
        } else {
            timerPub = Empty().eraseToAnyPublisher()
        }

        // D) Manual trigger (startup, after a write).
        let manualPub = refreshSubject.eraseToAnyPublisher()

        Publishers.Merge4(storeChangedPub, defaultsPub, timerPub, manualPub)
            .throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: false)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
    }

    /// Refreshes the published reminders. Self-gates on the setting and access,
    /// clearing the list when either is off so a toggled-off feature shows nothing.
    func refresh() {
        guard Defaults[.showRemindersInMenu], store.isAccessGranted else {
            if !reminders.isEmpty { reminders = [] }
            return
        }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let fetched = await self.store.fetchDueToday()
            guard !Task.isCancelled else { return }
            self.reminders = fetched
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        cancellables.removeAll()
    }
}
