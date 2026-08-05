//
//  MenuBarJoinAction.swift
//  MeetingBarNG
//
//  The menu bar's own call to action: a "Join" chip that appears on the status
//  item shortly before a meeting starts and joins it when clicked.
//
//  Two decisions live here, both pure so they are testable without a menu bar:
//  WHETHER the chip shows (`MenuBarJoinActionPolicy`) and WHERE it sits
//  (`MenuBarActionChipGeometry`). The second matters more than it looks: the
//  status item is a single `NSStatusBarButton` whose click normally opens the
//  dropdown, so the chip is not a real control — it is a drawn capsule plus a
//  rectangle the click handler tests against. Draw it in one place and hit-test
//  it in another and they drift, which means a chip you can see but not press.
//  One function returns the rect, and both callers use it.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

/// The user's answers on the Menu Bar pane, snapshotted for the policy.
struct MenuBarJoinActionSettings: Equatable {
    /// "Show a Join button in the menu bar". ON by default — the whole point of
    /// a meeting app's menu bar item is that the meeting is one click away.
    var isEnabled: Bool
    /// How long before the start the chip appears. `0` means "only once the
    /// meeting is actually running".
    var leadMinutes: Int
    /// The chip's text, localized by the caller (`"Join"`).
    var label: String

    /// The "no chip at all" snapshot, so callers that predate the feature — and
    /// the memberwise default on `MenuBarComposedSettings` — stay source-compatible.
    static let disabled = MenuBarJoinActionSettings(isEnabled: false, leadMinutes: 0, label: "")
}

enum MenuBarJoinActionPolicy {
    /// The chip's text, or `""` when the menu bar should not show one.
    ///
    /// Three things have to hold at once: the user asked for it, the meeting is
    /// close enough (or running), and there is somewhere to actually go. That
    /// last one is why `hasMeetingLink` exists rather than the policy assuming
    /// every event is joinable — a lunch block with no conferencing link would
    /// otherwise get a Join chip that opens nothing. It is the same condition the
    /// dropdown's row affordance uses, so the two surfaces offer Join on exactly
    /// the same set of meetings.
    static func label(
        event: StatusBarEventPresentationInput,
        settings: MenuBarJoinActionSettings,
        now: Date
    ) -> String {
        guard settings.isEnabled, event.hasMeetingLink else { return "" }

        let trimmed = settings.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Shares `EventActionProminence` with the menu bar's bold emphasis and
        // the dropdown's Join pill: "close enough to act on" is one rule in this
        // app, evaluated here with the chip's own lead time. A meeting that has
        // already ended is not imminent, so the chip clears itself.
        guard EventActionProminence.isImminent(
            start: event.startDate,
            end: event.endDate,
            now: now,
            leadMinutes: settings.leadMinutes
        ) else { return "" }

        return trimmed
    }

    /// The instant the chip becomes due for `eventStart`, for the redraw clock.
    ///
    /// The status bar already re-renders on every minute boundary, which would
    /// show the chip within 60 seconds of its time by itself. This exists for the
    /// meetings that do not start on a whole minute: a 10:00:30 start with a
    /// two-minute lead is due at 09:58:30, and rounding that up to 09:59:00 would
    /// quietly shorten the lead the user asked for.
    ///
    /// Returns `nil` when the feature is off, so a disabled chip never adds a
    /// wake-up to the timer.
    static func appearanceDate(
        eventStart: Date,
        settings: MenuBarJoinActionSettings
    ) -> Date? {
        guard settings.isEnabled else { return nil }
        return eventStart.addingTimeInterval(-Double(max(0, settings.leadMinutes)) * 60)
    }
}

/// Everything the chip's geometry depends on, measured off the button by the
/// renderer. Grouped into one value so the pure function's signature stays
/// readable and so a test can state a whole layout in one literal.
struct MenuBarActionChipMetrics: Equatable {
    /// The status item's bounds, in its own (non-flipped, y-up) coordinates.
    var buttonBounds: CGRect
    /// Width of the status icon, or `0` when the item has no image.
    var imageWidth: CGFloat
    /// Whether that icon draws after the text (the user put the icon block last).
    var imageIsTrailing: Bool
    /// The widest rendered line — what the item was actually sized to.
    var titleWidth: CGFloat
    /// Width of the line the chip sits on. Equal to `titleWidth` on one line;
    /// on two it is the detail line, which is usually the narrower of the pair.
    var lineWidth: CGFloat
    /// Rendered width of the chip's own text.
    var labelWidth: CGFloat
    /// The two-line layout, where the chip rides the lower line.
    var isStacked: Bool
}

/// Where the Join chip sits inside the status item, in the button's own
/// (non-flipped, y-up) coordinates.
///
/// The chip is always the LAST run of the last line, which is what makes this
/// tractable — but "last" is not the same as "hard against the item's right
/// edge". The status item centres its title, and on the two-line layout each
/// line is centred independently, so a short detail line under a long meeting
/// name ends well short of the item's edge. The chip therefore anchors to the
/// end of ITS OWN line, which collapses to the item's trailing content edge on
/// one line without needing a special case.
enum MenuBarActionChipGeometry {
    /// Breathing room drawn around the label run, per side.
    static let horizontalPadding: CGFloat = 4
    /// Keeps the capsule off the very top and bottom of the menu bar, where it
    /// would read as clipped rather than as a control.
    static let verticalInset: CGFloat = 2
    /// Fraction of the item's height the capsule takes on the two-line layout.
    static let stackedHeightFraction: CGFloat = 0.46
    /// The gap `NSButton` leaves between its image and its title. AppKit does
    /// not publish it; a point or two of error here moves the chip by half that,
    /// which is why nothing downstream depends on it being exact.
    static let imageTitleSpacing: CGFloat = 2
    /// Used when the derived inset comes out implausible — see `edgeInset`.
    static let fallbackEdgeInset: CGFloat = 4
    /// Widest inset `edgeInset` will believe.
    static let maximumEdgeInset: CGFloat = 12

    /// The padding `NSStatusBarButton` puts either side of its content.
    ///
    /// Derived rather than hardcoded: the item is `variableLength`, so it is its
    /// content plus a symmetric inset AppKit owns and does not publish. Halving
    /// the difference recovers it, and keeps working if AppKit ever changes it.
    /// A nonsense answer — negative, or wider than any plausible inset, which is
    /// what a mis-measured content width produces — falls back to a fixed value,
    /// so the chip lands a couple of points off rather than off the item.
    static func edgeInset(buttonWidth: CGFloat, contentWidth: CGFloat) -> CGFloat {
        let derived = (buttonWidth - contentWidth) / 2
        guard derived >= 0, derived <= maximumEdgeInset else { return fallbackEdgeInset }
        return derived
    }

    /// The capsule to draw, or `nil` when there is nothing to draw or no room.
    static func rect(_ metrics: MenuBarActionChipMetrics) -> CGRect? {
        let bounds = metrics.buttonBounds
        guard metrics.labelWidth > 0, bounds.width > 0, bounds.height > 0 else { return nil }

        let imageSlot = metrics.imageWidth > 0 ? metrics.imageWidth + imageTitleSpacing : 0
        let inset = edgeInset(
            buttonWidth: bounds.width,
            contentWidth: metrics.titleWidth + imageSlot
        )

        // The box the title is centred in: the item minus its edge insets, minus
        // whichever side the icon took.
        let titleMinX = bounds.minX + inset + (metrics.imageIsTrailing ? 0 : imageSlot)
        let titleMaxX = bounds.maxX - inset - (metrics.imageIsTrailing ? imageSlot : 0)
        guard titleMaxX > titleMinX else { return nil }

        // Where this line ends, and so where its trailing run ends.
        let lineMaxX = (titleMinX + titleMaxX) / 2 + metrics.lineWidth / 2
        let maxX = min(lineMaxX + horizontalPadding, bounds.maxX)
        let minX = lineMaxX - metrics.labelWidth - horizontalPadding
        guard minX >= bounds.minX, maxX > minX else { return nil }

        let height = metrics.isStacked
            ? bounds.height * stackedHeightFraction
            : bounds.height - verticalInset * 2
        guard height > 0 else { return nil }
        // y-up, so the stack's lower line sits at the bottom of the item.
        let minY = metrics.isStacked
            ? bounds.minY + verticalInset / 2
            : bounds.minY + verticalInset

        return CGRect(x: minX, y: minY, width: maxX - minX, height: height)
    }

    /// The click target for a drawn chip.
    ///
    /// Horizontally identical — what you see is what you press — but full-height,
    /// because on the two-line layout the drawn capsule is only about six points
    /// tall, and nothing else in that column wants a different click.
    static func hitRect(chip: CGRect, buttonBounds: CGRect) -> CGRect {
        CGRect(x: chip.minX, y: buttonBounds.minY, width: chip.width, height: buttonBounds.height)
    }
}
