// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PunctualLogic",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "PunctualLogic", targets: ["PunctualLogic"])
    ],
    targets: [
        .target(
            name: "PunctualLogic",
            path: "Punctual",
            exclude: [
                // Exclude app-layer files that depend on AppKit/Defaults/EventKit.
                // SPM scans the whole Punctual/ tree for resources; these paths
                // prevent it from picking up .lproj bundles and asset catalogues.
                "Resources ",
                "Assets.xcassets",
                "Base.lproj",
                "Preview Content"
            ],
            sources: [
                // Utilities/Diagnostics
                "Utilities/Diagnostics/DiagnosticsReport.swift",
                // Notifications
                "Notifications/EventActionPolicy.swift",
                "Notifications/NotificationPlanner.swift",
                // Calendar
                "Calendar/CalendarGridNavigation.swift",
                "Calendar/CalendarSourceSelection.swift",
                "Calendar/DateMarkers.swift",
                "Calendar/EventDeduplication.swift",
                "Calendar/EventFiltering.swift",
                "Calendar/MonthGridLayout.swift",
                "Calendar/EventSearch.swift",
                "Calendar/EventSelection.swift",
                "Calendar/ReminderSelection.swift",
                "Calendar/EventDraftValidation.swift",
                "Calendar/Providers/Google/GoogleCalendarPolicy.swift",
                "Calendar/Providers/Google/GoogleEventColors.swift",
                "Calendar/Providers/Google/GoogleIDToken.swift",
                "Calendar/Providers/Google/GoogleOAuthClient.swift",
                // Meetings
                "Meetings/LocationAutocompletePolicy.swift",
                "Meetings/MeetingIdentifier.swift",
                "Meetings/MeetingLinkDetector.swift",
                "Meetings/MeetingPrepLinks.swift",
                "Meetings/MeetingProvider.swift",
                "Meetings/MicLevel.swift",
                // UI/StatusBar
                "UI/StatusBar/AgendaSectionVisibility.swift",
                "UI/StatusBar/PanelTheme.swift",
                "UI/StatusBar/StatusBarPresentation.swift",
                "UI/StatusBar/WorldClockPanel.swift",
                "UI/StatusBar/DaySummaryGreeting.swift",
                "UI/StatusBar/DropdownComposition.swift",
                "UI/StatusBar/DropdownMetrics.swift",
                "UI/StatusBar/DropdownPanelNavigation.swift",
                "UI/StatusBar/DropdownPanelPlacement.swift",
                "UI/StatusBar/EventActionProminence.swift",
                "UI/StatusBar/MenuBarJoinAction.swift",
                "UI/StatusBar/MeetingProgress.swift",
                "UI/StatusBar/TimelineSpan.swift",
                "UI/StatusBar/StatusBarTickPolicy.swift",
                // Preferences (hostless core only; the tab Views are app-target)
                "Preferences/AlertsPresentation.swift",
                "Preferences/SettingsIndex.swift",
                "Preferences/FilterPresets.swift",
                "Preferences/CalendarListPresentation.swift",
                // UI/CommandBar (hostless core only; View/Window/ViewModel are app-target)
                "UI/CommandBar/CommandBarModels.swift",
                "UI/CommandBar/CommandBarSearch.swift",
                "UI/CommandBar/CommandBarAgenda.swift"
            ],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
        .testTarget(
            name: "PunctualLogicTests",
            dependencies: ["PunctualLogic"],
            path: "PunctualLogicTests",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        )
    ]
)
