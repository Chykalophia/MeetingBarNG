//
//  CommandBarAgenda.swift
//  MeetingBarNG
//
//  Hostless plain-text agenda builder for the Command Bar's "Copy today's
//  agenda" action. Deterministic assembly from preformatted entries (the app
//  passes locale-formatted time strings), mirroring DiagnosticsReport.text.
//

import Foundation

/// One agenda line. `timeRange` is preformatted app-side (e.g. "9:00 – 9:30").
struct CommandBarAgendaEntry: Equatable {
    let title: String
    let timeRange: String
    let isAllDay: Bool
}

enum CommandBarAgenda {
    /// Builds the copyable agenda: a header line, then one bullet per entry.
    /// All-day entries omit the time. `emptyPlaceholder` renders when there are
    /// no entries (both header and placeholder are already localized).
    static func text(
        for entries: [CommandBarAgendaEntry],
        header: String,
        emptyPlaceholder: String
    ) -> String {
        guard !entries.isEmpty else {
            return "\(header)\n\(emptyPlaceholder)"
        }
        var lines = [header]
        for entry in entries {
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if entry.isAllDay || entry.timeRange.isEmpty {
                lines.append("• \(title)")
            } else {
                lines.append("• \(entry.timeRange)  \(title)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
