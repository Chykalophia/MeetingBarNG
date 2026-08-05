//
//  DebugHarness.swift
//  MeetingBarNG
//
//  DEBUG-only development aid: a control panel that feeds the running app
//  synthetic meetings, so any state the menu bar and dropdown can be in is one
//  click away instead of something you wait for a real calendar to produce.
//
//  Why this exists. Most of what this app draws is a function of the next
//  meeting and the current time — the Join chip appears two minutes before a
//  start, the title boldens when a meeting is imminent, the progress indicator
//  fills while one runs. Exercising any of that for real means owning a calendar
//  event that starts in ninety seconds, which is a slow and destructive way to
//  test (it writes to the developer's actual calendar). Every one of those states
//  is a scenario here.
//
//  Why it cannot ship. The whole file is inside `#if DEBUG`, and DEBUG is defined
//  by `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in the Debug configuration ONLY — the
//  Release configuration does not define it, so none of this reaches a build a
//  user runs. The same reasoning as `DropdownInspectorWindow`, and the same three
//  rules it follows:
//
//    • the whole file is guarded, not just its body — no half-compiled types;
//    • it is reached by a deep link matched AHEAD of the router, so no DEBUG-only
//      case is added to `AppRoute` and no DEBUG-only closure to `AppEnvironment`;
//    • it holds no state the app reads back. The override lives on the status bar
//      controller behind a DEBUG-only method, and clearing it restores the real
//      calendar. A development hook should leave no shape behind in shipping
//      types.
//
//  Reached by `open "meetingbar://debug-harness"`, or from the status item's
//  right-click menu, whose last item exists only in this configuration.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

#if DEBUG
import AppKit

/// One canned situation to put the app in.
///
/// `build` takes the moment the scenario is applied rather than capturing one, so
/// re-applying a scenario re-bases it on now. That matters because scenarios AGE:
/// pick "starts in 90 seconds", leave it, and ninety seconds later the app is
/// genuinely in the "meeting starting now" state — which is exactly the
/// transition worth watching, and the reason nothing here freezes the clock.
struct DebugScenario: Identifiable, Sendable {
    let id: String
    let name: String
    /// One line on what this is for — shown under the button.
    let detail: String
    /// `nil` means "stop overriding and go back to the real calendar".
    /// `@Sendable` so the catalogue can be a `static let` under the module's
    /// complete-concurrency checking; every builder is pure, so it costs nothing.
    let build: (@Sendable (Date) -> [MBEvent])?

    static let all: [DebugScenario] = [
        DebugScenario(
            id: "real",
            name: "Real calendar",
            detail: "Drop the override and go back to actual events.",
            build: nil
        ),
        DebugScenario(
            id: "empty",
            name: "Nothing upcoming",
            detail: "Empty list — the done-for-today icon.",
            build: { _ in [] }
        ),
        DebugScenario(
            id: "far",
            name: "In 45 minutes",
            detail: "Ordinary upcoming meeting. No chip, no emphasis.",
            build: { now in [Self.meeting(now: now, startsIn: 45 * 60)] }
        ),
        DebugScenario(
            id: "evening",
            name: "In 3h 40m",
            detail: "Far out: with a countdown lead set, the name shows but the countdown does not.",
            build: { now in
                [Self.meeting(
                    now: now,
                    startsIn: 3 * 3600 + 40 * 60,
                    lasts: 45 * 60,
                    title: "Journalling",
                    hasLink: false
                )]
            }
        ),
        DebugScenario(
            id: "soon",
            name: "In 5 minutes",
            detail: "Close, but outside the default 2-minute chip window.",
            build: { now in [Self.meeting(now: now, startsIn: 5 * 60)] }
        ),
        DebugScenario(
            id: "chip",
            name: "In 90 seconds",
            detail: "Inside the chip window: Join appears, title boldens.",
            build: { now in [Self.meeting(now: now, startsIn: 90)] }
        ),
        DebugScenario(
            id: "seconds",
            name: "In 20 seconds",
            detail: "Watch it roll over into a running meeting.",
            build: { now in [Self.meeting(now: now, startsIn: 20)] }
        ),
        DebugScenario(
            id: "running",
            name: "Running now",
            detail: "Started 10 minutes ago, 20 to go. Chip stays up.",
            build: { now in [Self.meeting(now: now, startsIn: -10 * 60, lasts: 30 * 60)] }
        ),
        DebugScenario(
            id: "ending",
            name: "Ending in 90 seconds",
            detail: "Late in a meeting — progress indicator nearly full.",
            build: { now in [Self.meeting(now: now, startsIn: -28 * 60 - 30, lasts: 30 * 60)] }
        ),
        DebugScenario(
            id: "nolink",
            name: "In 90 seconds, no link",
            detail: "Chip must NOT appear — there is nowhere to join.",
            build: { now in [Self.meeting(now: now, startsIn: 90, hasLink: false)] }
        ),
        DebugScenario(
            id: "declined",
            name: "In 90 seconds, declined",
            detail: "Dimmed or struck per Filters; never boldened.",
            build: { now in [Self.meeting(now: now, startsIn: 90, participation: .declined)] }
        ),
        DebugScenario(
            id: "pending",
            name: "In 90 seconds, not answered",
            detail: "Pending appearance, and no bold emphasis.",
            build: { now in [Self.meeting(now: now, startsIn: 90, participation: .pending)] }
        ),
        DebugScenario(
            id: "tentative",
            name: "In 90 seconds, tentative",
            detail: "Tentative appearance from the Filters pane.",
            build: { now in [Self.meeting(now: now, startsIn: 90, participation: .tentative)] }
        ),
        DebugScenario(
            id: "long",
            name: "In 90 seconds, very long title",
            detail: "Exercises truncation with the chip still on the end.",
            build: { now in
                [Self.meeting(
                    now: now,
                    startsIn: 90,
                    title: "Quarterly cross-functional planning and roadmap alignment review "
                        + "with the extended leadership group"
                )]
            }
        ),
        DebugScenario(
            id: "allday",
            name: "All-day event",
            detail: "All-day handling in the menu bar and agenda.",
            build: { now in [Self.allDay(now: now)] }
        ),
        DebugScenario(
            id: "busy",
            name: "A busy day",
            detail: "Eight meetings across today — agenda density, +N more row.",
            build: { now in Self.busyDay(now: now) }
        )
    ]

    // MARK: - Builders

    /// A meeting link that is real enough for `MeetingLinkDetector` to classify
    /// (so the app takes the Google Meet path) and fake enough to be harmless:
    /// joining opens a browser on an invalid meeting code, which is all the
    /// confirmation a click test needs.
    static let meetingURL = URL(string: "https://meet.google.com/dbg-test-000")!

    private static let calendar = MBCalendar(
        title: "Debug harness",
        id: "debug-harness",
        source: "Debug",
        email: "debug@example.com",
        color: .systemPurple
    )

    static func meeting(
        now: Date,
        startsIn: TimeInterval,
        lasts: TimeInterval = 30 * 60,
        title: String = "Debug meeting",
        hasLink: Bool = true,
        participation: MBEventAttendeeStatus = .accepted,
        id: String = "debug-event"
    ) -> MBEvent {
        var event = MBEvent(
            id: id,
            lastModifiedDate: now,
            title: title,
            status: .confirmed,
            notes: nil,
            location: nil,
            url: hasLink ? meetingURL : nil,
            organizer: MBEventOrganizer(email: "debug@example.com", name: "Debug harness"),
            startDate: now.addingTimeInterval(startsIn),
            endDate: now.addingTimeInterval(startsIn + lasts),
            isAllDay: false,
            recurrent: false,
            calendar: calendar
        )
        // Set after init: `MBEvent` derives participation from the attendee list,
        // and a harness that had to synthesise a plausible attendee just to say
        // "declined" would be testing the attendee parser, not the appearance.
        event.participationStatus = participation
        return event
    }

    static func allDay(now: Date) -> MBEvent {
        let startOfDay = Calendar.current.startOfDay(for: now)
        return MBEvent(
            id: "debug-all-day",
            lastModifiedDate: now,
            title: "Debug all-day event",
            status: .confirmed,
            notes: nil,
            location: nil,
            url: nil,
            organizer: nil,
            startDate: startOfDay,
            endDate: startOfDay.addingTimeInterval(24 * 60 * 60),
            isAllDay: true,
            recurrent: false,
            calendar: calendar
        )
    }

    static func busyDay(now: Date) -> [MBEvent] {
        // One imminent (so the chip is up while the agenda is long) and seven
        // spread through the rest of the day.
        let offsets: [TimeInterval] = [90, 40 * 60, 75 * 60, 110 * 60, 150 * 60, 200 * 60, 260 * 60, 320 * 60]
        return offsets.enumerated().map { index, offset in
            meeting(
                now: now,
                startsIn: offset,
                lasts: 25 * 60,
                title: "Debug meeting \(index + 1)",
                id: "debug-busy-\(index)"
            )
        }
    }
}

/// What the menu bar is drawing right now, for the harness's readout.
///
/// A readout rather than "look at your menu bar" because the two things this
/// feature can get wrong are invisible at a glance: whether the click target
/// exists at all, and whether it agrees with the capsule that was drawn.
struct DebugRenderSummary {
    var firstLine: String
    var secondLine: String
    var actionLabel: String
    var chipRect: CGRect?
    var buttonWidth: CGFloat
    var eventCount: Int
    var isOverridden: Bool
    /// Whether any calendar is selected.
    ///
    /// Surfaced because it is the one way injected events can look broken through
    /// no fault of the injection: `StatusBarPresentationPolicy.mode` returns
    /// `.idle` when no calendar is chosen, so the item draws the app icon and
    /// nothing else no matter what the event list holds. Worth saying out loud
    /// rather than leaving someone to conclude the harness does not work.
    var hasSelectedCalendars: Bool
}

/// Closures the harness drives the app through. Passed in, like every other
/// window's dependencies, so the view holds no reference to the controller.
struct DebugHarnessHandlers {
    var apply: (DebugScenario) -> Void = { _ in }
    var summary: () -> DebugRenderSummary = {
        DebugRenderSummary(
            firstLine: "", secondLine: "", actionLabel: "",
            chipRect: nil, buttonWidth: 0, eventCount: 0,
            isOverridden: false, hasSelectedCalendars: true
        )
    }
}

/// The harness's window.
///
/// Titled, unlike `DropdownInspectorWindow` — that one is deliberately chromeless
/// because the thing being judged IS the panel's own surface. This is a control
/// panel, so it wants a titlebar and a close button like any other utility window.
final class DebugHarnessWindow: NSWindow {
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func close() {
        let handler = onClose
        onClose = nil
        handler?()
        super.close()
    }

    /// Whether `url` is the harness's deep link (`meetingbar://debug-harness`).
    /// Matched outside `URLHandler` for the reason given in the file header.
    static func matches(_ url: URL) -> Bool {
        url.scheme == "meetingbar" && url.host == "debug-harness"
    }
}
#endif
