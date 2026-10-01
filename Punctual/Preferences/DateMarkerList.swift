//
//  DateMarkerList.swift
//  MeetingBarNG
//
//  The editor for user-marked important days — birthdays, anniversaries,
//  deadlines — shown on both month grids.
//
//  Shaped after `TextPatternList`: an inline list with add and delete, and a
//  sheet for entry. No edit action, unlike patterns — a marker is a date and a
//  short label, so correcting one is faster to delete and re-add than to open a
//  second sheet for.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import SwiftUI

/// A list of stored date markers with add / delete.
struct DateMarkerList: View {
    /// The raw stored strings. Encoding stays at this boundary so the view above
    /// never has to know the storage format.
    @Binding var rawMarkers: [String]

    @State private var isAdding = false

    private var markers: [DateMarker] { DateMarkerCodec.decodeAll(rawMarkers) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if markers.isEmpty {
                Text("preferences_date_markers_empty".loco())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // Indexed so two markers with the same label and date stay separately
            // deletable rather than collapsing to one row.
            ForEach(Array(markers.enumerated()), id: \.offset) { index, marker in
                HStack(spacing: 8) {
                    Text(displayDate(marker))
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 96, alignment: .leading)
                    Text(marker.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if marker.repeatsAnnually {
                        Image(systemName: "repeat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("preferences_date_markers_repeats_help".loco())
                    }
                    Spacer()
                    Button {
                        remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("general_delete".loco())
                }
            }
            Button("preferences_date_markers_add_button".loco()) {
                isAdding = true
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $isAdding) {
            DateMarkerEditor { marker in
                rawMarkers.append(DateMarkerCodec.encode(marker))
            }
        }
    }

    /// Deletes by position in the DECODED list, mapped back through the encoding.
    /// Deleting by raw index would be wrong the moment an unparseable entry sits
    /// earlier in the stored list — the decoded list has dropped it, so the
    /// indices no longer line up.
    private func remove(at index: Int) {
        let decoded = markers
        guard decoded.indices.contains(index) else { return }
        let target = DateMarkerCodec.encode(decoded[index])
        if let rawIndex = rawMarkers.firstIndex(of: target) {
            rawMarkers.remove(at: rawIndex)
        }
    }

    private func displayDate(_ marker: DateMarker) -> String {
        var components = DateComponents()
        components.month = marker.month
        components.day = marker.day
        components.year = marker.year ?? 2024  // A leap year, so 29 Feb formats.

        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else {
            return "\(marker.month)/\(marker.day)"
        }
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        // A repeating marker has no year to show, and printing the placeholder
        // one would be a lie.
        formatter.setLocalizedDateFormatFromTemplate(marker.repeatsAnnually ? "MMMd" : "yMMMd")
        return formatter.string(from: date)
    }
}

/// The add sheet: a date, a label, and whether it comes round every year.
struct DateMarkerEditor: View {
    @Environment(\.presentationMode) private var presentationMode
    let onSave: (DateMarker) -> Void

    @State private var date = Date()
    @State private var label = ""
    @State private var repeatsAnnually = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("preferences_date_markers_new_title".loco())
                .font(.headline)

            DatePicker(
                "preferences_date_markers_date_label".loco(),
                selection: $date,
                displayedComponents: .date
            )
            .datePickerStyle(.field)

            TextField(
                "preferences_date_markers_label_label".loco(),
                text: $label,
                prompt: Text("preferences_date_markers_label_placeholder".loco())
            )

            // Defaulted ON: birthdays and anniversaries are the common case, and
            // a one-off deadline is the deliberate exception.
            Toggle("preferences_date_markers_repeats_toggle".loco(), isOn: $repeatsAnnually)

            HStack {
                Spacer()
                Button("general_cancel".loco()) {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("general_save".loco()) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedLabel.isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedLabel.isEmpty else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let month = components.month, let day = components.day else { return }
        onSave(DateMarker(
            month: month,
            day: day,
            year: repeatsAnnually ? nil : components.year,
            label: trimmedLabel
        ))
        presentationMode.wrappedValue.dismiss()
    }
}
