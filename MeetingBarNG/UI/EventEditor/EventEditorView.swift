//
//  EventEditorView.swift
//  MeetingBarNG
//
//  Structured (non-AI) form for creating and editing a calendar event in-app
//  (Dot parity). Presentation only: title, all-day toggle, start/end date
//  pickers (time hidden when all-day), a writable-calendar picker with color
//  swatches, location, notes, and URL. Save is disabled until the draft
//  validates (first issue shown inline); Delete (edit mode) confirms via NSAlert
//  in the view model before removing. All state lives in EventEditorViewModel.
//
//  Created for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import SwiftUI

enum EventEditorWindowPresentationPolicy {
    static let contentRect = CGSize(width: 440, height: 560)
    static let minimumSize = NSSize(width: 400, height: 500)
}

struct EventEditorView: View {
    @ObservedObject var viewModel: EventEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(
                viewModel.isEditing
                    ? "event_editor_edit_title".loco()
                    : "event_editor_new_title".loco()
            )
            .font(.headline)
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 8)

            Form {
                titleField
                allDayToggle
                datePickers
                calendarPicker
                locationField
                urlField
                notesField
            }

            footer
        }
        .frame(
            minWidth: EventEditorWindowPresentationPolicy.minimumSize.width,
            minHeight: EventEditorWindowPresentationPolicy.minimumSize.height
        )
    }

    // MARK: - Fields

    private var titleField: some View {
        TextField(
            "event_editor_title_label".loco(),
            text: $viewModel.title,
            prompt: Text("event_editor_title_placeholder".loco())
        )
    }

    private var allDayToggle: some View {
        Toggle("event_editor_all_day".loco(), isOn: $viewModel.isAllDay)
    }

    private var datePickers: some View {
        Group {
            DatePicker(
                "event_editor_starts".loco(),
                selection: $viewModel.startDate,
                displayedComponents: dateComponents
            )
            DatePicker(
                "event_editor_ends".loco(),
                selection: $viewModel.endDate,
                displayedComponents: dateComponents
            )
        }
    }

    private var dateComponents: DatePickerComponents {
        viewModel.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    private var calendarPicker: some View {
        Picker("event_editor_calendar".loco(), selection: $viewModel.selectedCalendarID) {
            ForEach(viewModel.writableCalendars, id: \.id) { calendar in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(nsColor: calendar.color))
                        .frame(width: 10, height: 10)
                    Text(calendar.title)
                }
                .tag(Optional(calendar.id))
            }
        }
        .disabled(viewModel.writableCalendars.isEmpty)
    }

    private var locationField: some View {
        TextField("event_editor_location".loco(), text: $viewModel.location)
    }

    private var urlField: some View {
        TextField("event_editor_url".loco(), text: $viewModel.url)
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("event_editor_notes".loco())
                .foregroundStyle(.secondary)
            TextEditor(text: $viewModel.notes)
                .frame(minHeight: 72)
                .font(.body)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = inlineMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if viewModel.isEditing {
                    Button("event_editor_delete".loco(), role: .destructive) {
                        viewModel.confirmAndDelete()
                    }
                    .disabled(viewModel.isSaving)
                }

                Spacer()

                Button("event_editor_cancel".loco()) {
                    viewModel.cancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("event_editor_save".loco()) {
                    viewModel.save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canSave)
            }
        }
        .padding(20)
    }

    /// Write failures win over validation hints (the user just tried to save).
    private var inlineMessage: String? {
        viewModel.errorMessage ?? viewModel.firstValidationMessage
    }
}
