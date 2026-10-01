//
//  SettingsSearchResults.swift
//  MeetingBarNG
//
//  The detail pane while the sidebar search field has text in it. Ranking lives
//  in the hostless `SettingsIndex`; this file only draws the hits and moves the
//  window to the pane that holds one.
//
//  Search ships in Phase 2 — three phases BEFORE the first gear popover exists —
//  because "nothing hidden is unfindable" has to be true before anything is
//  hidden, not afterwards.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import SwiftUI

struct SettingsSearchResults: View {
    let query: String
    let onSelect: (SettingsIndexEntry) -> Void

    private var results: [SettingsIndexEntry] {
        SettingsIndex.search(query) { $0.loco() }
    }

    var body: some View {
        if results.isEmpty {
            VStack(spacing: 6) {
                Text("preferences_search_no_results".loco(query))
                    .font(.headline)
                Text("preferences_search_no_results_help".loco())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(results) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    resultRow(entry)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }

    private func resultRow(_ entry: SettingsIndexEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: entry.tab.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.labelKey.loco())
                if let helpKey = entry.helpKey {
                    Text(helpKey.loco())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            Text(entry.tab.titleKey.loco())
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    SettingsSearchResults(query: "dot") { _ in }
        .frame(width: 600, height: 400)
}
