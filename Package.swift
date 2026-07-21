// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MeetingBarLogic",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "MeetingBarLogic", targets: ["MeetingBarLogic"])
    ],
    targets: [
        .target(
            name: "MeetingBarLogic",
            path: "MeetingBarNG",
            exclude: [
                // Exclude app-layer files that depend on AppKit/Defaults/EventKit.
                // SPM scans the whole MeetingBar/ tree for resources; these paths
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
                "Calendar/EventDeduplication.swift",
                "Calendar/EventFiltering.swift",
                "Calendar/MonthGridLayout.swift",
                "Calendar/EventSearch.swift",
                "Calendar/EventSelection.swift",
                "Calendar/ReminderSelection.swift",
                "Calendar/EventDraftValidation.swift",
                "Calendar/Providers/Google/GoogleCalendarPolicy.swift",
                // Meetings
                "Meetings/MeetingLinkDetector.swift",
                "Meetings/MeetingPrepLinks.swift",
                "Meetings/MeetingProvider.swift",
                "Meetings/MicLevel.swift",
                // UI/StatusBar
                "UI/StatusBar/StatusBarPresentation.swift",
                "UI/StatusBar/WorldClockPanel.swift",
                "UI/StatusBar/DaySummaryGreeting.swift",
                "UI/StatusBar/DropdownComposition.swift",
                "UI/StatusBar/DropdownMetrics.swift",
                "UI/StatusBar/DropdownPanelNavigation.swift",
                "UI/StatusBar/DropdownPanelPlacement.swift",
                "UI/StatusBar/StatusBarTickPolicy.swift",
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
            name: "MeetingBarLogicTests",
            dependencies: ["MeetingBarLogic"],
            path: "MeetingBarLogicTests",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        )
    ]
)
