//
//  MenuBarBlockListTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the Menu Bar pane's block list (Preferences UX overhaul,
//  Phase 2). The list is the complete inventory of what the menu bar can hold —
//  showing blocks are ordered left to right, hidden ones sit below — so turning a
//  block off can never delete it from the user's view, and turning it back on is
//  one click rather than a re-discovery of a "+" menu.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import XCTest

@testable import MeetingBarLogic

final class MenuBarBlockListTests: XCTestCase {
    // MARK: - The inventory

    func testEveryKindAppearsExactlyOnce() {
        let blocks = MenuBarBlockList.blocks(stored: ["title", "countdown"])
        XCTAssertEqual(blocks.count, MenuBarTokenKind.allCases.count)
        XCTAssertEqual(Set(blocks.map(\.kind)).count, MenuBarTokenKind.allCases.count)
    }

    func testShowingBlocksComeFirstInStoredOrder() {
        let blocks = MenuBarBlockList.blocks(stored: ["countdown", "icon"])
        XCTAssertEqual(blocks[0].kind, .countdown)
        XCTAssertEqual(blocks[1].kind, .icon)
        XCTAssertTrue(blocks[0].isOn)
        XCTAssertTrue(blocks[1].isOn)
        XCTAssertFalse(blocks[2].isOn)
    }

    func testHiddenBlocksFollowInCanonicalOrder() {
        let hidden = MenuBarBlockList.blocks(stored: ["countdown"])
            .filter { !$0.isOn }
            .map(\.kind)
        XCTAssertEqual(hidden, MenuBarTokenKind.allCases.filter { $0 != .countdown })
    }

    func testUnknownAndDuplicateStoredValuesAreIgnored() {
        // A hand-edited plist or a downgrade must never break the list.
        let blocks = MenuBarBlockList.blocks(stored: ["title", "nonsense", "title"])
        XCTAssertEqual(blocks.filter(\.isOn).map(\.kind), [.title])
        XCTAssertEqual(blocks.count, MenuBarTokenKind.allCases.count)
    }

    func testEmptyStorageShowsNothingAndHidesEverything() {
        let blocks = MenuBarBlockList.blocks(stored: [])
        XCTAssertTrue(blocks.allSatisfy { !$0.isOn })
    }

    // MARK: - Moving

    func testMovingLater() {
        XCTAssertEqual(
            MenuBarBlockList.moved(stored: ["icon", "title", "countdown"], kind: .title, by: 1),
            ["icon", "countdown", "title"]
        )
    }

    func testMovingEarlier() {
        XCTAssertEqual(
            MenuBarBlockList.moved(stored: ["icon", "title", "countdown"], kind: .countdown, by: -1),
            ["icon", "countdown", "title"]
        )
    }

    func testMovingPastTheEndsIsANoOp() {
        let stored = ["icon", "title"]
        XCTAssertEqual(MenuBarBlockList.moved(stored: stored, kind: .icon, by: -1), stored)
        XCTAssertEqual(MenuBarBlockList.moved(stored: stored, kind: .title, by: 1), stored)
    }

    func testMovingAHiddenBlockIsANoOp() {
        let stored = ["icon", "title"]
        XCTAssertEqual(MenuBarBlockList.moved(stored: stored, kind: .clock, by: -1), stored)
    }

    // MARK: - Switching on and off

    func testTurningABlockOffKeepsTheOthersInOrder() {
        XCTAssertEqual(
            MenuBarBlockList.setting(stored: ["icon", "title", "countdown"], kind: .title, isOn: false),
            ["icon", "countdown"]
        )
    }

    func testTurningABlockOnAppendsItLast() {
        XCTAssertEqual(
            MenuBarBlockList.setting(stored: ["icon", "title"], kind: .clock, isOn: true),
            ["icon", "title", "clock"]
        )
    }

    func testTurningAnAlreadyShowingBlockOnChangesNothing() {
        let stored = ["icon", "title"]
        XCTAssertEqual(MenuBarBlockList.setting(stored: stored, kind: .icon, isOn: true), stored)
    }

    func testSwitchingOffThenOnLosesOnlyThePosition() {
        // Nothing is destroyed: the block returns with one click. Its
        // configuration (countdown style, world-clock zone…) lives in its own
        // keys and is untouched by the switch.
        let off = MenuBarBlockList.setting(stored: ["icon", "title", "clock"], kind: .title, isOn: false)
        XCTAssertEqual(MenuBarBlockList.setting(stored: off, kind: .title, isOn: true), ["icon", "clock", "title"])
    }
}
