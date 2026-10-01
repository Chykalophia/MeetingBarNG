//
//  TextPatternList.swift
//  MeetingBarNG
//
//  The shared editor for the two pattern lists — "Hide meetings whose title
//  matches a pattern" (Filters) and "Find meeting links in unusual formats"
//  (Joining). Both were on the deleted Advanced tab, where a blanket orange
//  "for advanced users" warning was stamped across ordinary wishes like *hide
//  meetings called Focus time*.
//
//  The word "regex" is banned from user-facing copy: it is a **text pattern**.
//  The lowercase "edit" button — the only lowercase button label in the app — is
//  now "Edit".
//
//  Extracted from AdvancedTab.swift, originally:
//    Created by Andrii Leitsius on 13.01.2021.
//    Copyright © 2021 Andrii Leitsius. All rights reserved.
//  Licensed under the Apache License, Version 2.0. Modified for MeetingBarNG by
//  Peter Krzyzek / Chykalophia, 2026: split out of the Advanced tab, plain-language
//  labels, and an example placeholder in the editor.
//

import SwiftUI

/// A list of stored text patterns with add / edit / delete.
struct TextPatternList: View {
    @Binding var patterns: [String]

    @State private var draft: RegexEditDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(patterns, id: \.self) { pattern in
                HStack {
                    Text(pattern)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("preferences_pattern_edit_button".loco()) {
                        draft = .editing(pattern)
                    }
                    Button {
                        patterns.removeAll { $0 == pattern }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("general_delete".loco())
                }
            }
            Button("preferences_pattern_add_button".loco()) {
                draft = .adding()
            }
        }
        .padding(.vertical, 4)
        .sheet(item: $draft) { draft in
            TextPatternEditor(pattern: draft.value, onSave: save)
        }
    }

    private func save(_ pattern: String) -> Bool {
        guard var draft else { return false }
        draft.value = pattern
        switch RegexListEditingPolicy.saving(draft, in: patterns) {
        case .saved(let updated):
            patterns = updated
            return true
        case .duplicate, .originalMissing:
            return false
        }
    }
}

/// The add/edit sheet. Validates the pattern before saving and reports the
/// system's own message rather than a generic failure.
struct TextPatternEditor: View {
    @Environment(\.presentationMode) var presentationMode
    let onSave: (_ pattern: String) -> Bool

    @State private var draftPattern: String
    @State private var showingAlert = false
    @State private var errorMessage = ""

    // Seeded in init rather than onAppear: `.sheet(item:)` gives the sheet a
    // fresh identity per presentation, so the initial value is applied before
    // the first render and the field never flashes empty.
    init(pattern: String, onSave: @escaping (_ pattern: String) -> Bool) {
        _draftPattern = State(initialValue: pattern)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("preferences_pattern_new_title".loco())
                .font(.headline)
            TextField(
                "preferences_pattern_new_placeholder".loco(),
                text: $draftPattern
            )
            .textFieldStyle(.roundedBorder)
            HStack {
                Button("general_cancel".loco()) {
                    presentationMode.wrappedValue.dismiss()
                }
                Spacer()
                Button("general_save".loco(), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draftPattern.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 150)
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("preferences_pattern_cant_save_title".loco()),
                message: Text(errorMessage),
                dismissButton: .default(Text("general_ok".loco()))
            )
        }
    }

    private func save() {
        do {
            _ = try NSRegularExpression(pattern: draftPattern)
            if onSave(draftPattern) {
                presentationMode.wrappedValue.dismiss()
            } else {
                errorMessage = "preferences_pattern_duplicate_error".loco()
                showingAlert = true
            }
        } catch let error as NSError {
            errorMessage = error.localizedDescription
            showingAlert = true
        }
    }
}
