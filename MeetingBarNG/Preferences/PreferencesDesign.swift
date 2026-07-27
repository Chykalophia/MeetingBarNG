//
//  PreferencesDesign.swift
//  MeetingBar
//
//  Copyright © 2026 Peter Krzyzek / Chykalophia. All rights reserved.
//
//  Rebuilt from scratch to follow the Ice 2 (teddychan/ice-2) visual
//  language: annotation-style help text under controls, a group box with
//  quinary fill (no hairline border), a simpler callout, and a cleaner
//  disclosure label. The old PreferencesCard used a windowBackgroundColor
//  fill + separatorColor hairline that fought the grouped form style;
//  the old PreferenceCallout had a heavy tinted background. Both are
//  replaced with the Ice 2 equivalents.
//

import Defaults
import SwiftUI

// MARK: - Annotation (help text under a control)

/// Places a help line beneath a control, matching Ice 2's `.annotation()`
/// pattern. In a grouped form this renders as muted caption text directly
/// under the toggle/picker it describes, rather than as a separate row.
///
/// Usage:
///   Toggle("Show reminders", isOn: $show)
///     .annotation("Reminders appear alongside calendar events.")
///
extension View {
    func annotation(_ key: String) -> some View {
        annotation(Text(key.loco()))
    }

    func annotation(_ text: Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            self
            text
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A standalone help-text row for use inside a `Section` when the help text
/// is not attached to a specific control (e.g. a section-level explanation).
/// Matches the `.annotation()` visual: caption, secondary, wrapping.
struct PreferencesHelpText: View {
    let key: String

    var body: some View {
        Text(key.loco())
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Disclosure (state survives window close)

/// A disclosure whose open/closed state survives closing the window.
/// Rebuilt with a simpler label: just the title in `.subheadline.weight(.medium)`,
/// no custom VStack. An optional subtitle line appears below in caption/secondary.
struct PreferencesDisclosure<Content: View>: View {
    let id: String
    let titleKey: String
    var subtitleKey: String?
    var opensAutomatically = false
    @ViewBuilder var content: Content

    @Default(.preferencesExpandedDisclosures) private var expandedIDs

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedIDs.contains(id) },
            set: { isOpen in
                if isOpen {
                    if !expandedIDs.contains(id) { expandedIDs.append(id) }
                } else {
                    expandedIDs.removeAll { $0 == id }
                }
            }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey.loco())
                    .font(.subheadline.weight(.medium))
                if let subtitleKey {
                    Text(subtitleKey.loco())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            if opensAutomatically, !expandedIDs.contains(id) {
                expandedIDs.append(id)
            }
        }
    }
}

// MARK: - Layout constants

enum PreferencesLayout {
    static let nestedIndent: CGFloat = 16
}

extension View {
    func preferenceIndent() -> some View {
        padding(.leading, PreferencesLayout.nestedIndent)
    }
}

// MARK: - Group box (for non-form content like the About card)

/// A titled content group matching Ice 2's `IceGroupBox`: a VStack with
/// an optional header, content in a rounded rectangle with `Color.primary
/// .quinary` fill (no hairline border), and an optional footer. Uses
/// `.focusSection()` for keyboard focus traversal.
///
/// Use this for content that sits OUTSIDE a grouped form (e.g. the About
/// card). Inside a form, use `Section { }` directly — the form provides
/// its own grouping.
struct PreferencesCard<Content: View>: View {
    private let title: String?
    private let subtitle: String?
    @ViewBuilder private let content: Content

    init(
        _ title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding([.top, .leading], 8)
                .padding(.bottom, 2)
            }
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.regularMaterial)
                )
                .containerShape(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
        }
        .focusSection()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Callout (advisory message)

/// An SF Symbol plus a short advisory message on a muted background.
/// Rebuilt to match Ice 2's `CalloutBox`: simpler, with a quinary fill
/// and no heavy tint.
struct PreferenceCallout: View {
    let systemImage: String
    let message: String
    var tint: Color = .orange

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .font(.title3)
            Text(message)
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        PreferencesCard("Card title", subtitle: "A supporting subtitle line.") {
            Text("Card body content")
        }
        PreferenceCallout(
            systemImage: "exclamationmark.triangle.fill",
            message: "These settings are intended for advanced users."
        )
    }
    .padding()
    .frame(width: 420)
}
