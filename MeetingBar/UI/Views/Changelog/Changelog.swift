//
//  Changelog.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 22.03.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  bold, modern redesign of the "What's New" surface — a hero header, per-version
//  cards driven by the ReleaseNotes model, an "Earlier releases" disclosure, an
//  empty "all caught up" state, and an Onboarding-style prominent footer button.
//  Replaces the hardcoded SidebarListStyle List and the in-content Close button.
//

import AppKit
import Defaults
import SwiftUI

struct ChangelogView: View {
    @Default(.lastRevisedVersionInChangelog) private var lastRevisedVersionInChangelog
    @Default(.appVersion) private var appVersion

    /// Releases unseen since the last acknowledgement — the headline content.
    private var newReleases: [ReleaseNote] {
        ReleaseNotes.releases(newerThan: lastRevisedVersionInChangelog)
    }

    /// Already-seen releases, collapsed under a disclosure when present.
    private var earlierReleases: [ReleaseNote] {
        ReleaseNotes.releases(upToAndIncluding: lastRevisedVersionInChangelog)
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            Divider()
            content
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The window itself is clear (WindowStylePolicy); the content paints an
        // opaque rounded background and a hairline border so the borderless
        // window reads as a distinct surface and AppKit can derive its shadow —
        // matching the Onboarding chrome.
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(spacing: 14) {
            appIcon
            VStack(alignment: .leading, spacing: 3) {
                Text("changelog_hero_title".loco())
                    .font(.title2)
                    .bold()
                Text("changelog_hero_version".loco(appVersion))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var appIcon: some View {
        let image = NSImage(named: "AppIcon")
            ?? NSImage(named: NSImage.applicationIconName)
            ?? NSImage()
        return Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if newReleases.isEmpty {
                    emptyState
                } else {
                    ForEach(newReleases) { release in
                        ReleaseCard(release: release)
                    }
                }

                if !earlierReleases.isEmpty {
                    DisclosureGroup("changelog_earlier_releases".loco()) {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(earlierReleases) { release in
                                ReleaseCard(release: release)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .font(.headline)
                    .tint(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(.green)
            Text("changelog_empty_title".loco())
                .font(.title3)
                .bold()
            Text("changelog_empty_message".loco(appVersion))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let releasesURL = URL(string: "https://github.com/Chykalophia/MeetingBarNG/releases") {
                Link("changelog_view_all".loco(), destination: releasesURL)
                    .font(.callout)
            }
            Spacer()
            Button("changelog_continue".loco(), action: close)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// Closing the window is what acknowledges the changelog: AppDelegate's
    /// window-close handler matches on WindowTitles.changelog and records the
    /// current app version as last-seen.
    private func close() {
        NSApplication.shared.keyWindow?.close()
    }
}

// MARK: - Release card

private struct ReleaseCard: View {
    let release: ReleaseNote

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(release.highlights.enumerated()), id: \.offset) { _, entry in
                        ChangeRow(entry: entry)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var cardHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(release.version)
                .font(.headline)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                .foregroundStyle(Color.accentColor)
            if let date = release.date {
                Text(date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Change row

private struct ChangeRow: View {
    let entry: ChangeEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.kind.symbolName)
                .font(.body)
                .foregroundStyle(entry.kind.accentColor)
                .frame(width: 20)
                .accessibilityLabel(Text(entry.kind.accessibilityLabelKey.loco()))
            Text(entry.text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
