//
//  DropdownDensityTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the three dropdown densities. The values in each preset are
//  tuned as a SET — row padding, type size and the time column have to move
//  together or the leading grid stops lining up — so these pin the relationships
//  between the presets rather than any single number.
//

import XCTest

@testable import MeetingBarLogic

final class DropdownDensityTests: XCTestCase {
    private let all = DropdownDensity.allCases

    // MARK: - The shipping look must not move

    /// `.standard` IS the shipping panel. A failure here means every user's
    /// dropdown just changed shape — sometimes intended, sometimes a density
    /// preset edited by accident. Either way it should be a decision, not a
    /// surprise, which is why the values are spelled out.
    ///
    /// Changed deliberately twice: widened from the inherited NSMenu 330pt on
    /// 2026-07-28, then aligned to the approved mockup's own CSS in the polish
    /// pass — row `padding: 6px 10px`, `gap: 9px`, time column `54px` at a
    /// smaller type size, title `12.5px`. The time column sits at 58 rather than
    /// the mockup's 54 because "12:00 PM" has to fit at this font.
    func test_standardMatchesTheShippingPanel() {
        let grid = DropdownDensity.standard.metrics
        XCTAssertEqual(grid.panelWidth, 360)
        XCTAssertEqual(grid.rowOuterPadding, 8)
        XCTAssertEqual(grid.rowInnerPadding, 10)
        XCTAssertEqual(grid.rowVerticalPadding, 6)
        XCTAssertEqual(grid.columnSpacing, 9)
        XCTAssertEqual(grid.timeColumnWidth, 58)
        XCTAssertEqual(grid.rowFontSize, 12.5)
    }

    // MARK: - Invariants across all three

    /// Density changes vertical rhythm and type size ONLY. If width varied, the
    /// hosting window would have to resize when the setting changed.
    func test_panelWidthIsIdenticalAcrossDensities() {
        XCTAssertEqual(Set(all.map { $0.metrics.panelWidth }).count, 1)
    }

    /// The horizontal insets define where the content box starts; section headers
    /// share that number. Letting it drift per density would misalign headers
    /// against rows in one density only — the hardest kind of bug to spot.
    func test_rowOuterPaddingIsIdenticalAcrossDensities() {
        XCTAssertEqual(Set(all.map { $0.metrics.rowOuterPadding }).count, 1)
    }

    func test_everyDensityProducesAUsableContentWidth() {
        for density in all {
            let grid = density.metrics
            let content = grid.panelWidth - 2 * (grid.rowOuterPadding + grid.rowInnerPadding)
            XCTAssertGreaterThan(content, 240, "\(density) leaves too little room for a title")
        }
    }

    // MARK: - Ordering

    func test_densitiesAreOrderedByRowHeight() {
        XCTAssertLessThan(
            DropdownDensity.compact.metrics.rowVerticalPadding,
            DropdownDensity.standard.metrics.rowVerticalPadding
        )
        XCTAssertLessThan(
            DropdownDensity.standard.metrics.rowVerticalPadding,
            DropdownDensity.roomy.metrics.rowVerticalPadding
        )
    }

    func test_densitiesAreOrderedByTypeSize() {
        XCTAssertLessThan(
            DropdownDensity.compact.metrics.rowFontSize,
            DropdownDensity.standard.metrics.rowFontSize
        )
        XCTAssertLessThan(
            DropdownDensity.standard.metrics.rowFontSize,
            DropdownDensity.roomy.metrics.rowFontSize
        )
    }

    /// Cards are bounded surfaces, so their padding is what makes them read tight
    /// or airy. Leaving it fixed meant Small and Large moved every row but left
    /// every card identical, which reads as a bug rather than a density.
    func test_cardPaddingTracksDensity() {
        let byRow = all.sorted { $0.metrics.rowVerticalPadding < $1.metrics.rowVerticalPadding }
        XCTAssertEqual(
            byRow.map(\.metrics.cardVerticalPadding),
            byRow.map(\.metrics.cardVerticalPadding).sorted(),
            "card padding must grow with row padding"
        )
        XCTAssertEqual(
            byRow.map(\.metrics.cardHorizontalPadding),
            byRow.map(\.metrics.cardHorizontalPadding).sorted()
        )
    }

    /// A large inset inside a tight radius looks like a mistake — the corner's
    /// optical weight only stays constant if the two move together.
    func test_cardCornerRadiusTracksCardPadding() {
        let byPadding = all.sorted {
            $0.metrics.cardHorizontalPadding < $1.metrics.cardHorizontalPadding
        }
        let radii = byPadding.map(\.metrics.cardCornerRadius)
        XCTAssertEqual(radii, radii.sorted())
    }

    /// A card still has to leave room for content at every density.
    func test_cardsLeaveUsableContentWidthAtEveryDensity() {
        for density in all {
            let metrics = density.metrics
            let inner = metrics.rowContentWidth - metrics.cardHorizontalPadding * 2
            XCTAssertGreaterThan(inner, 200, "\(density)")
        }
    }

    /// The time column is sized to fit "12:00 PM" at the row's own type size, so
    /// it has to track the font. A wider font in a narrower column truncates; a
    /// narrower font in a wide column leaves dead space on every single row.
    func test_timeColumnTracksTypeSize() {
        let byFont = all.sorted { $0.metrics.rowFontSize < $1.metrics.rowFontSize }
        let widths = byFont.map { $0.metrics.timeColumnWidth }
        XCTAssertEqual(widths, widths.sorted(), "time column must grow with the font")
    }

    func test_secondaryTypeIsAlwaysSmallerThanPrimary() {
        for density in all {
            XCTAssertLessThan(
                density.metrics.secondaryFontSize,
                density.metrics.rowFontSize,
                "\(density) would render supporting text at or above title size"
            )
        }
    }

    // MARK: - The row solver still works at every density

    /// The agenda grid is solved from the metrics, so a density that broke the
    /// solver would produce overlapping columns. Runs the full combination matrix
    /// against all three presets rather than only `.standard`.
    func test_everyDensitySolvesToANonOverlappingRow() {
        for density in all {
            let grid = density.metrics
            for marker in AgendaMarker.allCases {
                for position in AgendaMarkerPosition.allCases {
                    for timeColumn in AgendaTimeColumn.allCases {
                        for icon in [true, false] {
                            let layout = AgendaRowLayout.resolve(
                                metrics: grid,
                                marker: marker,
                                position: position,
                                timeColumn: timeColumn,
                                showsServiceIcon: icon
                            )
                            XCTAssertGreaterThan(
                                layout.titleWidth, 0,
                                "\(density)/\(marker)/\(position)/\(timeColumn)/icon:\(icon) left no title room"
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Persistence shape

    /// Stored as a raw string in Defaults, so the case names are a wire format —
    /// renaming one silently resets that user to the default.
    func test_rawValuesAreStable() {
        XCTAssertEqual(DropdownDensity.compact.rawValue, "compact")
        XCTAssertEqual(DropdownDensity.standard.rawValue, "standard")
        XCTAssertEqual(DropdownDensity.roomy.rawValue, "roomy")
        XCTAssertEqual(DropdownDensity(rawValue: "standard"), .standard)
        XCTAssertNil(DropdownDensity(rawValue: "medium"))
    }
}
