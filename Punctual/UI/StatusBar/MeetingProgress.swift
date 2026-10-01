//
//  MeetingProgress.swift
//  MeetingBarNG
//
//  Hostless model for menu-bar meeting progress: how full the indicator is, what
//  it should read as, and whether it should be drawn at all. Pure value types and
//  time arithmetic — no AppKit — so "the bar is exactly full when the meeting
//  starts" is a unit test rather than something you squint at in the menu bar.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

/// How the menu bar DRAWS progress toward the next meeting.
///
/// Not to be confused with `MenuBarProgressStyle`, which says what the
/// event-independent `.progress` token MEASURES (day or year). This one is about
/// a meeting and is about rendering; that one is about the calendar and is about
/// data. The names are close because both are honestly "progress"; they are kept
/// distinct because merging them would put "year" and "ring" in one enum.
public enum MeetingProgressStyle: String, CaseIterable, Codable, Hashable, Sendable {
    /// Draw nothing. The default — the menu bar is shared with every other app,
    /// so an indicator has to be asked for.
    case none
    /// A thin rule under the whole item, filling left to right.
    case underline
    /// A ring around the icon.
    case ring
    /// A capsule around the whole item, filling left to right behind the text.
    case capsule
    /// A standalone mini-bar in the icon slot. The only style that costs menu-bar
    /// width, which is the scarcest resource in the app.
    case bar

    /// Whether this style draws anything at all. Lets callers skip the whole
    /// render path without matching on a specific case.
    public var drawsSomething: Bool { self != .none }

    /// Whether the style is drawn in the status item's IMAGE slot (and so
    /// replaces the icon and costs width) rather than as an overlay.
    public var occupiesImageSlot: Bool { self == .bar }
}

/// One frame of meeting progress, resolved and ready to draw.
public struct MeetingProgressPresentation: Equatable, Sendable {
    /// What the indicator should read as. Colour is the renderer's business; the
    /// phase is the shared vocabulary both the menu bar and the panel use.
    public enum Phase: Equatable, Sendable {
        /// Approaching, but not yet worth reacting to.
        case upcoming
        /// Inside the shared "close enough to act on" threshold.
        case imminent
        /// The meeting is happening now; the indicator counts through it.
        case running
    }

    /// How full to draw, `0...1`. Clamped on construction — a renderer should
    /// never have to defend itself against a negative width.
    public let fraction: Double
    public let phase: Phase

    public init(fraction: Double, phase: Phase) {
        self.fraction = min(max(fraction, 0), 1)
        self.phase = phase
    }
}

public enum MeetingProgressPolicy {
    /// How long before a meeting the indicator starts filling.
    ///
    /// An hour: short enough that a full bar means something is imminent rather
    /// than "some time today", long enough to be a warning rather than a
    /// surprise. Deliberately NOT tied to `eventActionHighlightMinutes` — that
    /// threshold answers "should the Join button shout", and at its two-minute
    /// default a bar would snap from empty to full with no useful middle.
    public static let leadWindow: TimeInterval = 3600

    /// The indicator for one meeting, or `nil` when nothing should be drawn.
    ///
    /// `nil` rather than a zero-fraction frame, so an idle menu bar carries no
    /// decoration at all: an empty ring sitting there all morning is visual noise
    /// that says only "a meeting exists eventually".
    ///
    /// - Parameters:
    ///   - leadMinutes: the shared imminence threshold (`eventActionHighlightMinutes`).
    ///   - window: how long before the start the fill begins. Injected for tests.
    public static func presentation(
        start: Date,
        end: Date,
        now: Date,
        leadMinutes: Int,
        window: TimeInterval = leadWindow
    ) -> MeetingProgressPresentation? {
        // Running: count THROUGH the meeting, so a full indicator means "this is
        // ending", not "this is starting". The two are never confusable because
        // the phase changes colour at the same instant.
        if now >= start, now < end {
            let duration = end.timeIntervalSince(start)
            // A zero-length meeting is a real thing calendars produce. Treat it as
            // instantly complete rather than dividing by zero.
            guard duration > 0 else {
                return MeetingProgressPresentation(fraction: 1, phase: .running)
            }
            return MeetingProgressPresentation(
                fraction: now.timeIntervalSince(start) / duration,
                phase: .running
            )
        }

        guard now < start else { return nil }

        let untilStart = start.timeIntervalSince(now)
        guard untilStart <= window, window > 0 else { return nil }

        // Exactly 1.0 at the start instant, which is the property that makes the
        // indicator legible at a glance: full means now.
        let fraction = (window - untilStart) / window
        let phase: MeetingProgressPresentation.Phase =
            untilStart <= TimeInterval(leadMinutes) * 60 ? .imminent : .upcoming
        return MeetingProgressPresentation(fraction: fraction, phase: phase)
    }
}
