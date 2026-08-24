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

import Defaults
import SwiftUI

enum EventEditorWindowPresentationPolicy {
    static let contentRect = CGSize(width: 440, height: 560)
    static let minimumSize = NSSize(width: 400, height: 500)
}

struct EventEditorView: View {
    @ObservedObject var viewModel: EventEditorViewModel

    @Default(.locationAutocompleteEnabled) private var locationAutocompleteEnabled
    @StateObject private var locationSuggestions = LocationSuggestionsModel()

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
                if viewModel.isRecurring {
                    recurringSpanPicker
                }
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

    /// Scope picker shown only for recurring events: apply the edit/delete to
    /// this occurrence, or this and all future occurrences.
    private var recurringSpanPicker: some View {
        Picker("event_editor_span_label".loco(), selection: $viewModel.editSpan) {
            Text("event_editor_span_this_event".loco()).tag(EventEditSpan.thisEvent)
            Text("event_editor_span_this_and_future".loco()).tag(EventEditSpan.thisAndFuture)
        }
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
        VStack(alignment: .leading, spacing: 4) {
            TextField("event_editor_location".loco(), text: $viewModel.location)
                .onChange(of: viewModel.location) { _, text in
                    locationSuggestions.update(for: text, isEnabled: locationAutocompleteEnabled)
                }
            if LocationAutocompletePolicy.shouldPresentResults(
                for: viewModel.location,
                isEnabled: locationAutocompleteEnabled,
                resultCount: locationSuggestions.suggestions.count
            ) {
                suggestionList
            }
        }
        .onDisappear { locationSuggestions.clear() }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(locationSuggestions.suggestions) { suggestion in
                Button {
                    viewModel.location = suggestion.fieldValue
                    // Clear rather than re-query: the field now holds the chosen
                    // address, and suggesting alternatives to a decision the user
                    // just made is noise.
                    locationSuggestions.clear()
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.title)
                            .font(.system(size: 12))
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
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
