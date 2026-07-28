//
//  TimelineLogicTests.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 23.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import XCTest
@testable import MeetingBarNG
import SwiftUI

final class TimelineLogicTests: XCTestCase {

    // MARK: - Row packing -----------------------------------------------------

    func seg(_ start: Int, _ end: Int, color: Color = .red) -> DaySegment {
        let startDate = Calendar.current.date(byAdding: .minute, value: start, to: Date())!
        let endDate = Calendar.current.date(byAdding: .minute, value: end, to: Date())!
        return DaySegment(start: startDate, end: endDate, color: color)
    }

    func testRowPacking_withoutOverlap_putsAllInOneRow() {
        let calc  = DayTimelineLayoutCalculator()
        let rows  = calc.rows(for: [seg(0, 10), seg(20, 30)])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].count, 2)
    }

    func testRowPacking_withOverlap_spreadsAcrossRows() {
        // 0‒50 overlaps 30‒60  → should allocate two rows
        let calc = DayTimelineLayoutCalculator()
        let rows = calc.rows(for: [seg(0, 50), seg(30, 60), seg(70, 90)])
        XCTAssertEqual(rows.count, 2)          // two visual lanes
        XCTAssertEqual(rows[0].count, 2)       // first two overlap -> same row
        XCTAssertEqual(rows[1].count, 1)
    }

    // MARK: - X position ------------------------------------------------------

    func testXPosition_midRange_isExactlyHalfWidth() {
        let calc  = DayTimelineLayoutCalculator()

        let interval = calc.visibleRange.upperBound.timeIntervalSince(calc.visibleRange.lowerBound)
        let mid = calc.visibleRange.lowerBound.addingTimeInterval(interval / 2)

        let width: CGFloat = 200
        let x = calc.xPosition(of: mid, width: width)
        XCTAssertEqual(x, 100, accuracy: 0.001)
    }

    func testXPosition_beforeLower_clampsToZero() {
        let calc  = DayTimelineLayoutCalculator()
        let point = calc.visibleRange.lowerBound.addingTimeInterval(-10)
        let width: CGFloat = 100
        let x = calc.xPosition(of: point, width: width)
        XCTAssertEqual(x, 0)
    }

    func testXPosition_afterUpper_clampsToWidth() {
        let calc  = DayTimelineLayoutCalculator()
        let point = calc.visibleRange.upperBound.addingTimeInterval(10)
        let width: CGFloat = 123
        let x = calc.xPosition(of: point, width: width)
        XCTAssertEqual(x, width)
    }

    // MARK: - Hour ticks ------------------------------------------------------

    func testHourTicks_areHourly_andCoverVisibleRange() {
        let calc  = DayTimelineLayoutCalculator()
        let ticks = calc.hourTicks()

        // first tick >= lowerBound and last <= upperBound
        XCTAssertGreaterThanOrEqual(ticks.first!, calc.visibleRange.lowerBound)
        XCTAssertLessThanOrEqual(ticks.last!, calc.visibleRange.upperBound)

        // step is 1 hour exactly
        let diffs = zip(ticks, ticks.dropFirst()).map { $1.timeIntervalSince($0) }
        for diff in diffs { XCTAssertEqual(diff, 3600, accuracy: 1) }
    }

    // MARK: - Hour labels -----------------------------------------------------

    /// The panel width where the bug showed: nine hours at ~37pt apart with
    /// "12 PM" ~34pt wide, so labels overlapped ("4 PM5 PM").
    private static let panelTrackWidth: CGFloat = 336

    func testHourLabels_neverOverlapAtPanelWidth() {
        for format in [TimeFormat.am_pm, .military] {
            let calc = DayTimelineLayoutCalculator()
            let width = Self.panelTrackWidth
            let halfWidth = DayTimelineLayout.hourLabelHalfWidth(for: format)
            let positions = calc.labelledTicks(width: width, timeFormat: format).map {
                calc.clampedLabelX(
                    calc.xPosition(of: $0, width: width),
                    width: width,
                    halfWidth: halfWidth
                )
            }

            for (left, right) in zip(positions, positions.dropFirst()) {
                XCTAssertGreaterThanOrEqual(
                    right - left,
                    DayTimelineLayout.minimumLabelSpacing(for: format),
                    "\(format) labels at \(left) and \(right) collide"
                )
            }
        }
    }

    /// Thinning must not empty the axis: a reader needs at least the ends.
    func testHourLabels_keepSomeLabelsAtPanelWidth() {
        for format in [TimeFormat.am_pm, .military] {
            let calc = DayTimelineLayoutCalculator()
            let kept = calc.labelledTicks(width: Self.panelTrackWidth, timeFormat: format)
            XCTAssertGreaterThanOrEqual(kept.count, 3, "\(format)")
        }
    }

    /// Narrow labels are cheaper, so a 24-hour axis keeps at least as many as a
    /// 12-hour one — the thinning is driven by measured width, not a fixed step.
    func testHourLabels_militaryKeepsAtLeastAsManyAs12Hour() {
        let calc = DayTimelineLayoutCalculator()
        let military = calc.labelledTicks(width: Self.panelTrackWidth, timeFormat: .military)
        let amPm = calc.labelledTicks(width: Self.panelTrackWidth, timeFormat: .am_pm)
        XCTAssertGreaterThanOrEqual(military.count, amPm.count)
    }

    /// Every label stays inside the view, including the clamped edge ones — the
    /// original "4 P" clipping this logic grew out of.
    func testHourLabels_stayInsideTheView() {
        let calc = DayTimelineLayoutCalculator()
        let width = Self.panelTrackWidth
        let halfWidth = DayTimelineLayout.hourLabelHalfWidth(for: .am_pm)

        for tick in calc.labelledTicks(width: width, timeFormat: .am_pm) {
            let x = calc.clampedLabelX(
                calc.xPosition(of: tick, width: width),
                width: width,
                halfWidth: halfWidth
            )
            XCTAssertGreaterThanOrEqual(x - halfWidth, 0)
            XCTAssertLessThanOrEqual(x + halfWidth, width)
        }
    }

    /// A width too small for even one label must not divide by a negative range.
    func testHourLabels_degenerateWidthDoesNotEscapeTheView() {
        let calc = DayTimelineLayoutCalculator()
        let width: CGFloat = 10
        let halfWidth = DayTimelineLayout.hourLabelHalfWidth(for: .am_pm)
        let x = calc.clampedLabelX(5, width: width, halfWidth: halfWidth)
        XCTAssertEqual(x, width / 2)
    }

    // MARK: - Preferred height ------------------------------------------------

    @MainActor func testPreferredHeight_matchesRowCount() {
        let view  = DayRelativeTimelineView(
            segments: [seg(0, 10), seg(20, 30), seg(40, 50)], // 1 row
            currentDate: Calendar.current.date(byAdding: .minute, value: 25, to: Date())!,
            timeFormat: .military
        )
        // Base track + top labels + vertical padding = 22 + 26
        XCTAssertEqual(view.preferredHeight, 48)
    }
}
