//
//  PreferencesDesign.swift
//  MeetingBar
//
//  Copyright © 2026 Peter Krzyzek / Chykalophia. All rights reserved.
//
//  Shared visual language for the Preferences window, matching the app's own
//  Onboarding chrome (12pt continuous rounded corners, a separatorColor
//  hairline, .headline titles, .secondary subtitles). Purely additive and
//  behavior-free: tabs opt in for styling only. macOS 12-safe.
//

import Defaults
import SwiftUI

/// A disclosure whose open/closed state survives closing the window.
///
/// Phase 2 rule: a disclosure the user opened is never auto-collapsed, and one
/// that must open itself (the Calendars troubleshooting section when macOS
/// reports an error) opens by writing the same stored state, so the user can
/// still close it afterwards.
struct PreferencesDisclosure<Content: View>: View {
    let id: String
    let titleKey: String
    var subtitleKey: String?
    /// Opens the disclosure on appearance — used when the app knows the user
    /// needs what is inside (an error state), not merely that it is uncommon.
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

/// Layout constants shared across the preferences tabs so nesting depth is
/// defined in one place instead of scattered magic numbers.
enum PreferencesLayout {
    /// Indent for a dependent row (a picker/stepper/tip that belongs to the
    /// toggle above it).
    static let nestedIndent: CGFloat = 16
}

extension View {
    /// Indents a dependent row under its parent control by the shared amount.
    /// Replaces the ad-hoc `.padding(.leading, 16)` used throughout the tabs.
    func preferenceIndent() -> some View {
        padding(.leading, PreferencesLayout.nestedIndent)
    }
}

/// A titled rounded card matching the Onboarding chrome. Available for tabs
/// that want the app's card language around a cluster of content.
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
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

/// An inset callout — an SF Symbol plus a tinted, hairline-bordered background —
/// for a short advisory message. Replaces the flat `listRowBackground` banner.
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
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
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
