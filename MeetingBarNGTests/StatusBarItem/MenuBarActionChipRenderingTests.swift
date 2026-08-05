//
//  MenuBarActionChipRenderingTests.swift
//  MeetingBarNGTests
//
//  The half of the Join chip the hostless tests cannot reach.
//
//  `MenuBarActionChipGeometry` is pure arithmetic over widths a test hands it;
//  what it cannot check is that the widths the RENDERER measures off a real
//  `NSStatusBarButton` are the right ones. That is where this feature can fail
//  silently: a chip drawn from a mis-measured trailing run still draws, it just
//  draws in the wrong place, over a click target that no longer matches it.
//

import Cocoa
import XCTest

@testable import MeetingBarNG

@MainActor
final class MenuBarActionChipRenderingTests: BaseTestCase {
    private func makeController() -> StatusBarItemController {
        StatusBarItemController()
    }

    private func presentation(
        title: String,
        actionLabel: String,
        layout: StatusBarTitleLayout = .inline(showTime: false),
        time: String = "",
        icon: StatusBarIcon = .asset(MenuStyleConstants.appIconName)
    ) -> StatusBarPresentation {
        StatusBarPresentation(
            mode: .nextEvent,
            title: title,
            time: time,
            tooltip: nil,
            icon: icon,
            layout: layout,
            titleStyle: .normal,
            actionLabel: actionLabel,
            removeDeliveredNotifications: false
        )
    }

    /// The chip's own overlay, found by type so the view stays private.
    private func chipOverlay(_ controller: StatusBarItemController) -> MenuBarActionChipOverlayView? {
        controller.statusItem.button?.subviews
            .compactMap { $0 as? MenuBarActionChipOverlayView }
            .first
    }

    func testRenderingAChipProducesMatchingCapsuleAndClickTarget() {
        let controller = makeController()
        defer { controller.removeFromStatusBar() }

        controller.renderStatusBar(presentation(title: "Standup  in 2m  Join", actionLabel: "Join"))

        guard let button = controller.statusItem.button else {
            return XCTFail("status item has no button")
        }
        guard let hitRect = controller.actionChipHitRect else {
            return XCTFail("a chip was requested but no click target was produced")
        }
        guard let chip = chipOverlay(controller)?.chipRect else {
            return XCTFail("a chip was requested but nothing was drawn")
        }

        XCTAssertEqual(chip.minX, hitRect.minX, accuracy: 0.01, "drawn and clickable must agree")
        XCTAssertEqual(chip.width, hitRect.width, accuracy: 0.01)
        XCTAssertTrue(
            button.bounds.contains(chip),
            "chip \(chip) escaped the item \(button.bounds)"
        )
        XCTAssertGreaterThan(chip.width, 0)
        // "Join" is a short word; the capsule around it must not swallow the
        // whole item, which is what a mis-measured run would produce.
        XCTAssertLessThan(
            chip.width,
            button.bounds.width,
            "the chip measured wider than the item — the trailing run is wrong"
        )
    }

    func testChipSitsAtTheTrailingEndOfTheItem() {
        let controller = makeController()
        defer { controller.removeFromStatusBar() }

        controller.renderStatusBar(presentation(title: "Standup  in 2m  Join", actionLabel: "Join"))

        guard let button = controller.statusItem.button,
              let chip = chipOverlay(controller)?.chipRect
        else { return XCTFail("no chip drawn") }

        XCTAssertGreaterThan(
            chip.midX,
            button.bounds.midX,
            "the chip is appended last, so it belongs in the item's trailing half"
        )
    }

    func testNoChipWhenThePresentationHasNoAction() {
        let controller = makeController()
        defer { controller.removeFromStatusBar() }

        controller.renderStatusBar(presentation(title: "Standup  in 2m", actionLabel: ""))

        XCTAssertNil(controller.actionChipHitRect)
        XCTAssertNil(chipOverlay(controller)?.chipRect)
    }

    /// The click target has to be torn down with the chip, or a stale rect keeps
    /// swallowing clicks that should open the dropdown long after the meeting.
    func testChipIsClearedOnTheNextRenderWithoutOne() {
        let controller = makeController()
        defer { controller.removeFromStatusBar() }

        controller.renderStatusBar(presentation(title: "Standup  in 2m  Join", actionLabel: "Join"))
        XCTAssertNotNil(controller.actionChipHitRect)

        controller.renderStatusBar(presentation(title: "Standup  in 42m", actionLabel: ""))
        XCTAssertNil(controller.actionChipHitRect, "a stale target would hijack clicks")
        XCTAssertNil(chipOverlay(controller)?.chipRect)
    }

    /// Defensive: the renderer only draws a chip when the string really does end
    /// with the label. A presentation whose title lost it must not put a live
    /// click target over whatever happens to be at the end instead.
    func testNoChipWhenTheLabelIsNotTheTrailingRun() {
        let controller = makeController()
        defer { controller.removeFromStatusBar() }

        controller.renderStatusBar(presentation(title: "Standup  in 2m", actionLabel: "Join"))

        XCTAssertNil(controller.actionChipHitRect)
        XCTAssertNil(chipOverlay(controller)?.chipRect)
    }

    func testStackedLayoutPutsTheChipOnTheLowerLine() {
        let controller = makeController()
        defer { controller.removeFromStatusBar() }

        controller.renderStatusBar(
            presentation(
                title: "A rather long meeting name",
                actionLabel: "Join",
                layout: .stacked,
                time: "in 2m  Join"
            )
        )

        guard let button = controller.statusItem.button,
              let chip = chipOverlay(controller)?.chipRect
        else { return XCTFail("no chip drawn") }

        XCTAssertLessThan(
            chip.midY,
            button.bounds.midY,
            "y-up: the detail line the chip rides is the lower one"
        )
        XCTAssertTrue(button.bounds.contains(chip), "chip \(chip) escaped \(button.bounds)")
    }
}
