//
//  WorldClockPanelView.swift
//  MeetingBarNG
//
//  Multi-zone world-clock panel window (Dot parity). A small titled window that
//  lists the user's chosen time zones with their current local time and a
//  Tomorrow/Yesterday tag when a zone's calendar day differs from the local
//  (reference) zone. Presentation only: all time/day formatting lives in the
//  hostless `WorldClockPanelPolicy`; the rows are rebuilt each minute by a
//  `TimelineView(.periodic)` anchored to the top of the current minute. An
//  "Edit" mode reveals a per-row remove button and an "Add time zone" picker,
//  both writing `Defaults[.worldClockPanelZones]`.
//

import Defaults
import SwiftUI

enum WorldClockPanelPresentationPolicy {
    static let contentRect = CGSize(width: 300, height: 360)
    static let minimumSize = NSSize(width: 260, height: 300)
}

struct WorldClockPanelView: View {
    @Default(.worldClockPanelZones) private var zoneIdentifiers
    @Default(.timeFormat) private var timeFormat

    @State private var isEditing = false
    @State private var pendingAddIdentifier = ""
    // Anchor the periodic refresh to the top of the current minute so ticks land
    // on hh:mm:00 (like the status-bar redraw loop) rather than 60 s after open.
    @State private var minuteAnchor = WorldClockPanelView.startOfCurrentMinute()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TimelineView(.periodic(from: minuteAnchor, by: 60)) { context in
                rows(now: context.date)
            }
        }
        .frame(
            minWidth: WorldClockPanelPresentationPolicy.minimumSize.width,
            minHeight: WorldClockPanelPresentationPolicy.minimumSize.height
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("world_clock_panel_title".loco())
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button {
                isEditing.toggle()
            } label: {
                Text(isEditing
                    ? "world_clock_panel_done".loco()
                    : "world_clock_panel_edit".loco())
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Rows

    private func rows(now: Date) -> some View {
        let entries = WorldClockPanelPolicy.entries(
            zones: zones,
            now: now,
            use24Hour: timeFormat == .military,
            referenceZone: TimeZone.current,
            locale: I18N.instance.locale
        )

        return ScrollView {
            LazyVStack(spacing: 2) {
                if entries.isEmpty {
                    Text("world_clock_panel_empty".loco())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        WorldClockRow(
                            entry: entry,
                            isEditing: isEditing,
                            onRemove: { remove(at: index) }
                        )
                    }
                }

                if isEditing {
                    addZonePicker
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var addZonePicker: some View {
        Picker(selection: $pendingAddIdentifier) {
            Text("world_clock_panel_add".loco()).tag("")
            ForEach(availableIdentifiers, id: \.self) { identifier in
                Text(WorldClockPanelPolicy.cityLabel(fromIdentifier: identifier)).tag(identifier)
            }
        } label: {
            Label("world_clock_panel_add".loco(), systemImage: "plus")
        }
        .labelsHidden()
        .onChange(of: pendingAddIdentifier) { newValue in
            guard !newValue.isEmpty else { return }
            add(newValue)
            pendingAddIdentifier = ""
        }
    }

    // MARK: - Data

    private var zones: [WorldClockZone] {
        zoneIdentifiers.map {
            WorldClockZone(identifier: $0, label: WorldClockPanelPolicy.cityLabel(fromIdentifier: $0))
        }
    }

    private var availableIdentifiers: [String] {
        let existing = Set(zoneIdentifiers)
        return TimeZone.knownTimeZoneIdentifiers.sorted().filter { !existing.contains($0) }
    }

    // MARK: - Mutation

    private func add(_ identifier: String) {
        guard !zoneIdentifiers.contains(identifier) else { return }
        zoneIdentifiers.append(identifier)
    }

    private func remove(at index: Int) {
        guard zoneIdentifiers.indices.contains(index) else { return }
        zoneIdentifiers.remove(at: index)
    }

    private static func startOfCurrentMinute() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: Date()
        )
        return calendar.date(from: components) ?? Date()
    }
}

// MARK: - Row

private struct WorldClockRow: View {
    let entry: WorldClockEntry
    let isEditing: Bool
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isEditing {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("world_clock_panel_remove".loco())
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let dayTag {
                    Text(dayTag)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }

            Spacer(minLength: 8)

            Text(entry.time)
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// A "Tomorrow"/"Yesterday" tag when the zone's day differs from the local
    /// reference day; `nil` for same-day zones (no tag).
    private var dayTag: String? {
        switch entry.dayOffset {
        case let offset where offset >= 1:
            return "world_clock_panel_tomorrow".loco()
        case let offset where offset <= -1:
            return "world_clock_panel_yesterday".loco()
        default:
            return nil
        }
    }
}

#Preview {
    WorldClockPanelView()
        .frame(
            width: WorldClockPanelPresentationPolicy.contentRect.width,
            height: WorldClockPanelPresentationPolicy.contentRect.height
        )
}
