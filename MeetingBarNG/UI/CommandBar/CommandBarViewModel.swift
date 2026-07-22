//
//  CommandBarViewModel.swift
//  MeetingBarNG
//
//  App-target view model for the Command Bar. Maps [MBEvent] into the hostless
//  CommandBarEventInput projection, builds localized action descriptors, calls
//  the pure CommandBarSearch on every query change, and dispatches the chosen
//  row to existing entry points (join / create / preferences / copy agenda /
//  refresh). The SwiftUI view stays presentation-only.
//

import AppKit
import Defaults
import Foundation

/// Closures the Command Bar needs from the app, injected by AppDelegate so the
/// view model stays decoupled from AppModel/WindowCoordinator.
struct CommandBarHandlers {
    var events: @MainActor () -> [MBEvent]
    var send: @MainActor (AppAction) -> Void
    var openPreferences: @MainActor () -> Void
    var createMeeting: @MainActor () -> Void
}

@MainActor
final class CommandBarViewModel: ObservableObject {
    @Published var query: String = "" {
        didSet { recompute() }
    }
    @Published private(set) var rows: [CommandBarResultRow] = []
    @Published var selectionIndex: Int = 0

    private let handlers: CommandBarHandlers
    /// Closes the Command Bar window (owned by WindowCoordinator).
    let dismiss: () -> Void

    init(handlers: CommandBarHandlers, dismiss: @escaping () -> Void) {
        self.handlers = handlers
        self.dismiss = dismiss
        recompute()
    }

    // MARK: - Selection

    func moveSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selectionIndex = min(max(0, selectionIndex + delta), rows.count - 1)
    }

    func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        selectionIndex = index
    }

    func runSelected() {
        guard rows.indices.contains(selectionIndex) else { return }
        run(rows[selectionIndex])
    }

    // MARK: - Execution

    private func run(_ row: CommandBarResultRow) {
        dismiss()
        switch row.result {
        case let .action(action):
            runAction(action)
        case let .event(id):
            handlers.send(.joinMeeting(eventID: id))
        }
    }

    private func runAction(_ action: CommandBarAction) {
        switch action {
        case .joinNext:
            if let next = handlers.events().nextEvent(now: Date()) {
                handlers.send(.joinMeeting(eventID: next.id))
            }
        case .createMeeting:
            handlers.createMeeting()
        case .openPreferences:
            handlers.openPreferences()
        case .copyAgenda:
            copyAgenda()
        case .refreshCalendars:
            handlers.send(.refreshCalendars)
        }
    }

    private func copyAgenda() {
        let now = Date()
        let calendar = Calendar.current
        let entries = todayEvents(now: now, calendar: calendar).map {
            CommandBarAgendaEntry(
                title: $0.title,
                timeRange: $0.isAllDay ? "" : timeRange($0),
                isAllDay: $0.isAllDay
            )
        }
        let header = "command_bar_agenda_header".loco(dateText(now, calendar: calendar))
        let text = CommandBarAgenda.text(
            for: entries,
            header: header,
            emptyPlaceholder: "command_bar_agenda_empty".loco()
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Query → rows

    private func recompute() {
        let now = Date()
        let calendar = Calendar.current
        let inputs = handlers.events().enumerated().map { index, event in
            commandBarInput(event: event, sourceIndex: index)
        }
        rows = CommandBarSearch.results(
            query: query,
            events: inputs,
            actions: actionDescriptors(),
            now: now,
            calendar: calendar
        )
        selectionIndex = 0
    }

    private func commandBarInput(event: MBEvent, sourceIndex: Int) -> CommandBarEventInput {
        let people = event.attendees.flatMap { [$0.name, $0.email].compactMap { $0 } }
            + [event.organizer?.name, event.organizer?.email].compactMap { $0 }
        return CommandBarEventInput(
            sourceIndex: sourceIndex,
            id: event.id,
            title: event.title,
            subtitle: subtitle(for: event),
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            hasMeetingLink: event.meetingLink != nil,
            location: event.location,
            notes: event.notes,
            attendees: people
        )
    }

    private func actionDescriptors() -> [CommandBarActionDescriptor] {
        [
            CommandBarActionDescriptor(
                action: .joinNext,
                title: "command_bar_action_join_next".loco(),
                subtitle: nil,
                searchableText: synonyms("command_bar_action_join_next_keywords"),
                isPriority: true
            ),
            CommandBarActionDescriptor(
                action: .createMeeting,
                title: "command_bar_action_create_meeting".loco(),
                subtitle: nil,
                searchableText: synonyms("command_bar_action_create_meeting_keywords"),
                isPriority: true
            ),
            CommandBarActionDescriptor(
                action: .copyAgenda,
                title: "command_bar_action_copy_agenda".loco(),
                subtitle: nil,
                searchableText: synonyms("command_bar_action_copy_agenda_keywords"),
                isPriority: false
            ),
            CommandBarActionDescriptor(
                action: .refreshCalendars,
                title: "command_bar_action_refresh".loco(),
                subtitle: nil,
                searchableText: synonyms("command_bar_action_refresh_keywords"),
                isPriority: false
            ),
            CommandBarActionDescriptor(
                action: .openPreferences,
                title: "command_bar_action_open_preferences".loco(),
                subtitle: nil,
                searchableText: synonyms("command_bar_action_open_preferences_keywords"),
                isPriority: false
            )
        ]
    }

    // MARK: - Formatting helpers

    private func todayEvents(now: Date, calendar: Calendar) -> [MBEvent] {
        handlers.events()
            .filter { calendar.isDate($0.startDate, inSameDayAs: now) }
            .sorted { $0.startDate < $1.startDate }
    }

    private func subtitle(for event: MBEvent) -> String {
        var parts: [String] = [event.isAllDay ? "command_bar_all_day".loco() : timeRange(event)]
        if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            parts.append(location)
        }
        return parts.joined(separator: "  ·  ")
    }

    private func timeRange(_ event: MBEvent) -> String {
        "\(clock(event.startDate)) – \(clock(event.endDate))"
    }

    private func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        formatter.setLocalizedDateFormatFromTemplate(Defaults[.timeFormat] == .military ? "Hmm" : "hmma")
        return formatter.string(from: date)
    }

    private func dateText(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = I18N.instance.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: date)
    }

    /// Splits a localized space-separated keyword string into match synonyms.
    private func synonyms(_ key: String) -> [String] {
        key.loco().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}
