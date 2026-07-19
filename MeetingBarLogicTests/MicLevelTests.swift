//
//  MicLevelTests.swift
//  MeetingBarLogicTests
//
//  Covers the pure dBFS → 0…1 normalization that drives the pre-call preview's
//  mic-level meter: endpoints, the linear-in-dB midpoint, out-of-range clamping,
//  non-finite guards, and a custom floor.
//

import XCTest

@testable import MeetingBarLogic

final class MicLevelTests: XCTestCase {
    private let accuracy: Float = 0.0001

    func testFullScaleMapsToOne() {
        XCTAssertEqual(MicLevel.normalized(decibels: 0), 1, accuracy: accuracy)
    }

    func testFloorMapsToZero() {
        XCTAssertEqual(MicLevel.normalized(decibels: -60), 0, accuracy: accuracy)
    }

    func testMidpointIsLinearInDecibels() {
        // Halfway between the -60 dB floor and 0 dB is -30 dB → 0.5.
        XCTAssertEqual(MicLevel.normalized(decibels: -30), 0.5, accuracy: accuracy)
    }

    func testBelowFloorClampsToZero() {
        XCTAssertEqual(MicLevel.normalized(decibels: -120), 0, accuracy: accuracy)
    }

    func testAboveFullScaleClampsToOne() {
        XCTAssertEqual(MicLevel.normalized(decibels: 6), 1, accuracy: accuracy)
    }

    func testNonFiniteReadingsReturnZero() {
        XCTAssertEqual(MicLevel.normalized(decibels: .nan), 0, accuracy: accuracy)
        XCTAssertEqual(MicLevel.normalized(decibels: -.infinity), 0, accuracy: accuracy)
    }

    func testCustomFloorRescalesRange() {
        // With a -40 dB floor, -20 dB is the midpoint → 0.5.
        XCTAssertEqual(
            MicLevel.normalized(decibels: -20, floorDecibels: -40),
            0.5,
            accuracy: accuracy
        )
    }

    func testNonNegativeFloorIsClampedSafely() {
        // A degenerate floor must not divide by zero or exceed the 0…1 range.
        let value = MicLevel.normalized(decibels: -0.5, floorDecibels: 0)
        XCTAssertGreaterThanOrEqual(value, 0)
        XCTAssertLessThanOrEqual(value, 1)
    }
}
