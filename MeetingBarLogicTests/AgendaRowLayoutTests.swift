//
//  AgendaRowLayoutTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the dropdown panel's single agenda grid (MeetingBarNG,
//  Preferences UX overhaul Phase 1).
//
//  Before `DropdownMetrics` the 330pt panel carried four unrelated left grids —
//  a 66pt time column, an 18pt action-symbol column, a 32pt detail indent and a
//  16pt section-header indent — none of which knew about each other. These tests
//  pin the grid down so "put the marker all the way left" has something to be
//  left OF.
//

import CoreGraphics
import XCTest

@testable import MeetingBarLogic

final class AgendaRowLayoutTests: XCTestCase {
    private let metrics = DropdownMetrics.standard

    /// One point in the marker × position × time-column × service-icon matrix.
    private struct Combination: CustomStringConvertible {
        let marker: AgendaMarker
        let position: AgendaMarkerPosition
        let timeColumn: AgendaTimeColumn
        let serviceIcon: Bool

        var description: String {
            "\(marker)/\(position)/\(timeColumn)/icon:\(serviceIcon)"
        }
    }

    private var allCombinations: [Combination] {
        AgendaMarker.allCases.flatMap { marker in
            AgendaMarkerPosition.allCases.flatMap { position in
                AgendaTimeColumn.allCases.flatMap { timeColumn in
                    [false, true].map {
                        Combination(
                            marker: marker,
                            position: position,
                            timeColumn: timeColumn,
                            serviceIcon: $0
                        )
                    }
                }
            }
        }
    }

    private func layout(_ combination: Combination) -> AgendaRowLayout {
        layout(
            combination.marker,
            combination.position,
            combination.timeColumn,
            serviceIcon: combination.serviceIcon
        )
    }

    private func layout(
        _ marker: AgendaMarker,
        _ position: AgendaMarkerPosition,
        _ timeColumn: AgendaTimeColumn,
        serviceIcon: Bool = false
    ) -> AgendaRowLayout {
        AgendaRowLayout.resolve(
            metrics: metrics,
            marker: marker,
            position: position,
            timeColumn: timeColumn,
            showsServiceIcon: serviceIcon
        )
    }

    // MARK: - The grid itself

    /// The four grids the plan measured are now one. A section header's indent
    /// and a row's content origin have to be the same number or headers and rows
    /// visibly disagree.
    func testTheRowContentBoxAndTheSectionHeaderShareOneIndent() {
        XCTAssertEqual(metrics.rowLeadingInset, metrics.rowOuterPadding + metrics.rowInnerPadding)
        XCTAssertEqual(metrics.sectionHeaderInset, metrics.rowLeadingInset)
    }

    /// The detail disclosure is indented from the same grid rather than from a
    /// literal, and it sits inside the row's content box, not outside it.
    func testDetailIndentIsDerivedFromTheGrid() {
        XCTAssertEqual(metrics.detailIndent, metrics.rowLeadingInset + metrics.columnSpacing * 2)
        XCTAssertGreaterThan(metrics.detailIndent, metrics.rowLeadingInset)
    }

    func testContentWidthIsThePanelMinusBothRowInsets() {
        XCTAssertEqual(metrics.rowContentWidth, metrics.panelWidth - metrics.rowLeadingInset * 2)
    }

    // MARK: - Time column

    func testHiddenTimeColumnTakesNoWidth() {
        XCTAssertEqual(metrics.timeColumnWidth(for: .hidden), 0)
    }

    /// Start-and-end stacks the two times instead of widening the column: a
    /// single-line "10:00 AM – 10:30 AM" needs ~125pt of a 298pt content box and
    /// would leave the title unreadable.
    func testStartAndEndKeepsTheSameColumnWidthAsStartOnly() {
        XCTAssertEqual(
            metrics.timeColumnWidth(for: .startAndEnd),
            metrics.timeColumnWidth(for: .startOnly)
        )
        XCTAssertEqual(metrics.timeColumnWidth(for: .startOnly), metrics.timeColumnWidth)
    }

    func testLayoutReportsTheTimeColumnWidthForItsMode() {
        for combination in allCombinations {
            XCTAssertEqual(
                layout(combination).timeColumnWidth,
                metrics.timeColumnWidth(for: combination.timeColumn),
                combination.description
            )
        }
    }

    // MARK: - Service icon slot

    /// `showMeetingServiceIcon` was drawn nowhere on agenda rows. Turning it on
    /// has to cost the title exactly one icon slot plus one gutter — no more, and
    /// never zero (which is what "the setting does nothing" looks like).
    func testServiceIconShiftsTheTitleByExactlyOneSlot() {
        for combination in allCombinations {
            let without = layout(
                combination.marker,
                combination.position,
                combination.timeColumn,
                serviceIcon: false
            )
            let with = layout(
                combination.marker,
                combination.position,
                combination.timeColumn,
                serviceIcon: true
            )
            XCTAssertEqual(
                with.titleOrigin - without.titleOrigin,
                metrics.serviceIconWidth + metrics.columnSpacing,
                accuracy: 0.001,
                combination.description
            )
        }
    }

    // MARK: - Marker resolution

    /// A "left border bar" that is not at the left edge is not a border. The
    /// position control is therefore resolved, not merely stored.
    func testLeftBorderBarAlwaysResolvesToFarLeft() {
        for position in AgendaMarkerPosition.allCases {
            for timeColumn in AgendaTimeColumn.allCases {
                XCTAssertEqual(
                    layout(.leftBorderBar, position, timeColumn).resolvedPosition,
                    .farLeft,
                    "\(position)/\(timeColumn)"
                )
            }
        }
    }

    func testDotHonoursTheRequestedPosition() {
        for position in AgendaMarkerPosition.allCases {
            XCTAssertEqual(layout(.dot, position, .startOnly).resolvedPosition, position)
        }
    }

    func testNoMarkerDrawsNothingAndDoesNotEscapeThePadding() {
        for position in AgendaMarkerPosition.allCases {
            for timeColumn in AgendaTimeColumn.allCases {
                let result = layout(.none, position, timeColumn)
                XCTAssertNil(result.markerFrame, "\(position)/\(timeColumn)")
                XCTAssertEqual(result.leadingInset, 0, "\(position)/\(timeColumn)")
            }
        }
    }

    // MARK: - Far left genuinely escapes the row padding

    /// The owner's literal ask: a marker "all the way to the left". Inside
    /// `PanelRow` that means a NEGATIVE offset — anything ≥ 0 stops at the
    /// padding and only looks flush.
    func testFarLeftMarkerEscapesPanelRowPadding() {
        for marker in [AgendaMarker.dot, .leftBorderBar] {
            for timeColumn in AgendaTimeColumn.allCases {
                let result = layout(marker, .farLeft, timeColumn)
                XCTAssertLessThan(result.leadingInset, 0, "\(marker)/\(timeColumn)")
                XCTAssertEqual(result.leadingInset, -metrics.rowLeadingInset)
                let frame = try? XCTUnwrap(result.markerFrame)
                XCTAssertEqual(frame?.x, -metrics.rowLeadingInset)
                // Reaches the true panel edge, not the content box edge.
                XCTAssertEqual(
                    (frame?.x ?? 0) + metrics.rowLeadingInset,
                    0,
                    accuracy: 0.001
                )
            }
        }
    }

    func testBetweenTimeAndTitleMarkerStaysInsideTheContentBox() {
        for timeColumn in AgendaTimeColumn.allCases {
            let result = layout(.dot, .betweenTimeAndTitle, timeColumn)
            XCTAssertEqual(result.leadingInset, 0, "\(timeColumn)")
            let frame = result.markerFrame
            XCTAssertNotNil(frame, "\(timeColumn)")
            XCTAssertGreaterThanOrEqual(frame?.x ?? -1, result.timeColumnWidth, "\(timeColumn)")
        }
    }

    /// A left border bar is a bar: taller than it is wide, unlike the dot.
    func testLeftBorderBarIsTallerThanItIsWide() {
        let frame = layout(.leftBorderBar, .farLeft, .startOnly).markerFrame
        XCTAssertNotNil(frame)
        XCTAssertGreaterThan(frame?.height ?? 0, frame?.width ?? 0)
    }

    // MARK: - Every combination is a valid, non-overlapping layout

    func testEveryCombinationProducesANonOverlappingLayout() {
        for combination in allCombinations {
            let result = layout(combination)
            let label = combination.description

            // The title never sits on top of the time column.
            XCTAssertGreaterThanOrEqual(result.titleOrigin, result.timeColumnWidth, label)

            // The title always has room left for it.
            XCTAssertGreaterThan(result.titleWidth, 0, label)
            XCTAssertLessThanOrEqual(
                result.titleOrigin + result.titleWidth,
                metrics.rowContentWidth,
                label
            )

            guard let frame = result.markerFrame else { continue }
            XCTAssertGreaterThan(frame.width, 0, label)
            XCTAssertGreaterThan(frame.height, 0, label)
            // The marker never sits on top of the title …
            XCTAssertLessThanOrEqual(frame.maxX, result.titleOrigin, label)
            // … nor on top of the time column.
            switch result.resolvedPosition {
            case .farLeft:
                XCTAssertLessThanOrEqual(frame.maxX, 0, label)
            case .betweenTimeAndTitle:
                XCTAssertGreaterThanOrEqual(frame.x, result.timeColumnWidth, label)
            }
        }
    }

    /// Hiding the time column reclaims its width for the title rather than
    /// leaving a hole where it used to be.
    func testHidingTheTimeColumnMovesTheTitleLeft() {
        for marker in AgendaMarker.allCases {
            for position in AgendaMarkerPosition.allCases {
                let hidden = layout(marker, position, .hidden)
                let shown = layout(marker, position, .startOnly)
                XCTAssertLessThan(hidden.titleOrigin, shown.titleOrigin, "\(marker)/\(position)")
                XCTAssertGreaterThan(hidden.titleWidth, shown.titleWidth, "\(marker)/\(position)")
            }
        }
    }

    /// Today's shipping row — a dot between the time and the title with the
    /// start time showing — must keep the exact geometry it has, so Phase 1 is a
    /// refactor of the grid and not a silent restyle.
    func testTheShippingDefaultRowKeepsItsCurrentGeometry() {
        let result = layout(.dot, .betweenTimeAndTitle, .startOnly)
        XCTAssertEqual(result.timeColumnWidth, 66)
        XCTAssertEqual(result.markerFrame?.x, 66 + 8)
        XCTAssertEqual(result.markerFrame?.width, 7)
        XCTAssertEqual(result.titleOrigin, 66 + 8 + 7 + 8)
    }

    /// A row reserves space for the RESTING glyph, not for the Join pill that
    /// only exists on hover — the pill is drawn as an overlay. Asserted against
    /// the arithmetic rather than a literal so the intent survives a density
    /// retune, and pinned as a regression: reserving the pill width cost every
    /// linked event ~32pt of title for a control that was not on screen.
    func testRowReservesTheRestingGlyphNotTheHoverPill() {
        let result = layout(.dot, .betweenTimeAndTitle, .startOnly)
        let reserved = metrics.rowContentWidth - result.titleOrigin - result.titleWidth

        XCTAssertEqual(
            reserved,
            metrics.trailingGlyphWidth + metrics.columnSpacing
                + metrics.disclosureWidth + metrics.columnSpacing
        )
        XCTAssertLessThan(
            metrics.trailingGlyphWidth,
            metrics.trailingAffordanceWidth,
            "the glyph must be cheaper than the pill or the change bought nothing"
        )
    }

    /// The saving is real at every density, not just the default one.
    func testEveryDensityGivesTheTitleMoreRoomThanThePillWouldHave() {
        for density in DropdownDensity.allCases {
            let metrics = density.metrics
            let result = AgendaRowLayout.resolve(
                metrics: metrics,
                marker: .dot,
                position: .betweenTimeAndTitle,
                timeColumn: .startOnly
            )
            let withPill = metrics.rowContentWidth
                - result.titleOrigin
                - (metrics.trailingAffordanceWidth + metrics.columnSpacing
                    + metrics.disclosureWidth + metrics.columnSpacing)
            XCTAssertGreaterThan(result.titleWidth, withPill, "\(density)")
        }
    }
}
