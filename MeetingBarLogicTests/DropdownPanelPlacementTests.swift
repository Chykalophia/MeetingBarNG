//
//  DropdownPanelPlacementTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the SwiftUI dropdown panel's placement math (MeetingBarNG).
//

import CoreGraphics
import XCTest

@testable import MeetingBarLogic

final class DropdownPanelPlacementTests: XCTestCase {
    /// A 1440×900 screen whose menu bar occupies the top 25pt, so the visible
    /// frame is y ∈ [0, 875] in AppKit's bottom-left origin coordinates.
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let panelSize = CGSize(width: 330, height: 400)

    /// Status-item button rect in screen coordinates: sits on the menu bar, so
    /// its bottom edge (`minY`) is the top of the visible frame.
    private func statusItem(midX: CGFloat) -> CGRect {
        CGRect(x: midX - 20, y: 875, width: 40, height: 25)
    }

    func testPanelHangsBelowTheStatusItem() {
        let frame = DropdownPanelPlacement.frame(
            for: statusItem(midX: 720),
            panelSize: panelSize,
            screen: screen
        )
        XCTAssertEqual(
            frame.maxY,
            875 - DropdownPanelPlacement.statusItemGap,
            accuracy: 0.001
        )
        XCTAssertEqual(frame.height, panelSize.height, accuracy: 0.001)
    }

    func testPanelIsCenteredUnderTheStatusItem() {
        let frame = DropdownPanelPlacement.frame(
            for: statusItem(midX: 720),
            panelSize: panelSize,
            screen: screen
        )
        XCTAssertEqual(frame.midX, 720, accuracy: 0.001)
        XCTAssertEqual(frame.width, panelSize.width, accuracy: 0.001)
    }

    func testPanelClampsToTheRightScreenEdge() {
        // Status item hard against the right edge (the usual case for a
        // menu-bar app): centering would push the panel offscreen.
        let frame = DropdownPanelPlacement.frame(
            for: statusItem(midX: 1430),
            panelSize: panelSize,
            screen: screen
        )
        XCTAssertEqual(
            frame.maxX,
            screen.maxX - DropdownPanelPlacement.screenEdgeInset,
            accuracy: 0.001
        )
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX)
    }

    func testPanelClampsToTheLeftScreenEdge() {
        let frame = DropdownPanelPlacement.frame(
            for: statusItem(midX: 10),
            panelSize: panelSize,
            screen: screen
        )
        XCTAssertEqual(
            frame.minX,
            screen.minX + DropdownPanelPlacement.screenEdgeInset,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX)
    }

    func testPanelHonorsANonZeroScreenOrigin() {
        // Secondary display to the right of the main one.
        let secondary = CGRect(x: 1440, y: 0, width: 1280, height: 800)
        let frame = DropdownPanelPlacement.frame(
            for: CGRect(x: 2700, y: 800, width: 40, height: 25),
            panelSize: panelSize,
            screen: secondary
        )
        XCTAssertEqual(
            frame.maxX,
            secondary.maxX - DropdownPanelPlacement.screenEdgeInset,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(frame.minY, secondary.minY)
    }

    func testTallPanelIsTrimmedToTheSpaceAboveTheScreenBottom() {
        // A day long enough to overflow: the panel scrolls instead of running
        // off the bottom of the screen.
        let tall = CGSize(width: 330, height: 2000)
        let frame = DropdownPanelPlacement.frame(
            for: statusItem(midX: 720),
            panelSize: tall,
            screen: screen
        )
        XCTAssertEqual(
            frame.minY,
            screen.minY + DropdownPanelPlacement.screenEdgeInset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            frame.maxY,
            875 - DropdownPanelPlacement.statusItemGap,
            accuracy: 0.001
        )
        XCTAssertLessThan(frame.height, tall.height)
    }

    func testPanelKeepsAUsableHeightWhenThereIsAlmostNoRoom() {
        // Pathological: a status item near the bottom of a tiny visible frame.
        let tiny = CGRect(x: 0, y: 0, width: 800, height: 200)
        let frame = DropdownPanelPlacement.frame(
            for: CGRect(x: 700, y: 60, width: 40, height: 25),
            panelSize: panelSize,
            screen: tiny
        )
        XCTAssertEqual(frame.height, DropdownPanelPlacement.minimumHeight, accuracy: 0.001)
        XCTAssertEqual(frame.minY, tiny.minY + DropdownPanelPlacement.screenEdgeInset, accuracy: 0.001)
    }

    func testShortPanelIsNotStretched() {
        let short = CGSize(width: 330, height: 90)
        let frame = DropdownPanelPlacement.frame(
            for: statusItem(midX: 720),
            panelSize: short,
            screen: screen
        )
        XCTAssertEqual(frame.height, short.height, accuracy: 0.001)
    }
}
