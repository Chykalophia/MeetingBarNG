//
//  DropdownMetrics.swift
//  MeetingBarNG
//
//  The dropdown panel's ONE layout grid, and the pure agenda-row solver built on
//  it. Hostless (MeetingBarLogic): no AppKit, no SwiftUI, no Defaults — just
//  numbers, so every combination can be unit-tested.
//
//  Why this exists: the 330pt panel used to carry four unrelated left grids —
//  a 66pt time column on event rows, an 18pt symbol column on action rows, a
//  32pt indent on the detail disclosure and a 16pt indent on section headers —
//  each written as a literal at its own call site. Nothing tied them together,
//  so "move the calendar marker all the way to the left" had no grid to be left
//  OF, and any change to one column silently misaligned the other three.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import CoreGraphics
import Foundation

// MARK: - Agenda row vocabulary

/// The calendar-colour marker on an agenda row.
///
/// `.none` is the off state of `showEventCalendarColor`; the panel used to draw
/// the dot unconditionally, so that preference did nothing.
public enum AgendaMarker: String, Codable, CaseIterable, Sendable {
    case none
    case dot
    case leftBorderBar
}

public enum AgendaMarkerPosition: String, Codable, CaseIterable, Sendable {
    /// Outside the row's padding, flush with the panel edge.
    case farLeft
    /// The shipping position: in the gutter between the time and the title.
    case betweenTimeAndTitle
}

/// What the leading time column shows. `showEventEndTime` selects between
/// `.startOnly` and `.startAndEnd`.
public enum AgendaTimeColumn: String, Codable, CaseIterable, Sendable {
    case hidden
    case startOnly
    case startAndEnd
}

// MARK: - Metrics

/// Every fixed dimension in the dropdown panel, in one place.
///
/// `.standard` reproduces the shipping panel exactly — this type is a
/// consolidation of existing literals, not a restyle.
public struct DropdownMetrics: Equatable, Sendable {
    /// The panel's fixed width (`MeetingSummaryView.preferredWidth`).
    public var panelWidth: CGFloat
    /// Gap between the panel edge and a row's highlight capsule.
    public var rowOuterPadding: CGFloat
    /// Gap between the highlight capsule and the row's content.
    public var rowInnerPadding: CGFloat
    public var rowVerticalPadding: CGFloat
    /// The single gutter between adjacent columns in a row.
    public var columnSpacing: CGFloat
    /// Width of the leading time column when it is shown.
    public var timeColumnWidth: CGFloat
    public var markerDotDiameter: CGFloat
    public var markerBarWidth: CGFloat
    public var markerBarHeight: CGFloat
    /// Slot reserved for a meeting-service icon on an agenda row.
    public var serviceIconWidth: CGFloat
    /// Slot reserved for the leading SF Symbol on an action row.
    public var actionSymbolWidth: CGFloat
    /// Slot reserved for the hover-revealed Join affordance.
    public var trailingAffordanceWidth: CGFloat
    /// Slot reserved for the detail disclosure chevron.
    public var disclosureWidth: CGFloat

    public init(
        panelWidth: CGFloat,
        rowOuterPadding: CGFloat,
        rowInnerPadding: CGFloat,
        rowVerticalPadding: CGFloat,
        columnSpacing: CGFloat,
        timeColumnWidth: CGFloat,
        markerDotDiameter: CGFloat,
        markerBarWidth: CGFloat,
        markerBarHeight: CGFloat,
        serviceIconWidth: CGFloat,
        actionSymbolWidth: CGFloat,
        trailingAffordanceWidth: CGFloat,
        disclosureWidth: CGFloat
    ) {
        self.panelWidth = panelWidth
        self.rowOuterPadding = rowOuterPadding
        self.rowInnerPadding = rowInnerPadding
        self.rowVerticalPadding = rowVerticalPadding
        self.columnSpacing = columnSpacing
        self.timeColumnWidth = timeColumnWidth
        self.markerDotDiameter = markerDotDiameter
        self.markerBarWidth = markerBarWidth
        self.markerBarHeight = markerBarHeight
        self.serviceIconWidth = serviceIconWidth
        self.actionSymbolWidth = actionSymbolWidth
        self.trailingAffordanceWidth = trailingAffordanceWidth
        self.disclosureWidth = disclosureWidth
    }

    public static let standard = DropdownMetrics(
        panelWidth: 330,
        rowOuterPadding: 6,
        rowInnerPadding: 10,
        rowVerticalPadding: 5,
        columnSpacing: 8,
        timeColumnWidth: 66,
        markerDotDiameter: 7,
        markerBarWidth: 3,
        markerBarHeight: 16,
        serviceIconWidth: 14,
        actionSymbolWidth: 18,
        trailingAffordanceWidth: 48,
        disclosureWidth: 14
    )

    /// Distance from the panel's leading edge to a row's content box. Section
    /// headers use the same number, which is what makes headers and rows line up.
    public var rowLeadingInset: CGFloat { rowOuterPadding + rowInnerPadding }

    /// Alias that names the intent at header call sites.
    public var sectionHeaderInset: CGFloat { rowLeadingInset }

    /// Indent of the inline detail disclosure, derived from the grid rather than
    /// written as a literal.
    public var detailIndent: CGFloat { rowLeadingInset + columnSpacing * 2 }

    /// Width available to a row's content, between the two row insets.
    public var rowContentWidth: CGFloat { panelWidth - rowLeadingInset * 2 }

    /// Width of the time column in a given mode.
    ///
    /// `.startAndEnd` deliberately keeps the SAME width and stacks the two times
    /// instead of widening: on a 298pt content box a single-line
    /// "10:00 AM – 10:30 AM" costs ~125pt and leaves the title unreadable.
    public func timeColumnWidth(for column: AgendaTimeColumn) -> CGFloat {
        switch column {
        case .hidden: 0
        case .startOnly, .startAndEnd: timeColumnWidth
        }
    }
}

// MARK: - Agenda row layout

/// The solved geometry of one agenda row, in coordinates measured from the row's
/// **content box** leading edge (i.e. inside `PanelRow`'s padding). A negative
/// value therefore means "outside the padding", which is the only way a marker
/// can genuinely reach the panel edge.
public struct AgendaRowLayout: Equatable, Sendable {
    public struct MarkerFrame: Equatable, Sendable {
        public var x: CGFloat
        public var width: CGFloat
        public var height: CGFloat

        public var maxX: CGFloat { x + width }
    }

    public let marker: AgendaMarker
    /// The position actually used, which can differ from the one requested
    /// (a left border bar is only a border at the left edge).
    public let resolvedPosition: AgendaMarkerPosition
    public let timeColumn: AgendaTimeColumn
    /// Leading offset the row's content needs so the marker can escape the row
    /// padding. `0` unless a marker is drawn at the far left.
    public let leadingInset: CGFloat
    public let timeColumnWidth: CGFloat
    /// `nil` when no marker is drawn.
    public let markerFrame: MarkerFrame?
    /// `nil` when `showMeetingServiceIcon` is off — the slot is not reserved,
    /// so turning the setting off gives the width back to the title.
    public let serviceIconOrigin: CGFloat?
    public let titleOrigin: CGFloat
    public let titleWidth: CGFloat

    public static func resolve(
        metrics: DropdownMetrics = .standard,
        marker: AgendaMarker,
        position: AgendaMarkerPosition,
        timeColumn: AgendaTimeColumn,
        showsServiceIcon: Bool = false
    ) -> AgendaRowLayout {
        let resolvedPosition: AgendaMarkerPosition = marker == .leftBorderBar ? .farLeft : position
        let timeWidth = metrics.timeColumnWidth(for: timeColumn)
        // The gutter only exists when there is something to its left.
        let afterTime = timeWidth > 0 ? timeWidth + metrics.columnSpacing : 0

        var markerFrame: MarkerFrame?
        var leadingInset: CGFloat = 0
        var titleOrigin = afterTime

        switch marker {
        case .none:
            break
        case .dot, .leftBorderBar:
            let size = markerSize(marker, metrics: metrics)
            switch resolvedPosition {
            case .farLeft:
                leadingInset = -metrics.rowLeadingInset
                markerFrame = MarkerFrame(
                    x: leadingInset,
                    width: size.width,
                    height: size.height
                )
            case .betweenTimeAndTitle:
                markerFrame = MarkerFrame(
                    x: afterTime,
                    width: size.width,
                    height: size.height
                )
                titleOrigin = afterTime + size.width + metrics.columnSpacing
            }
        }

        // The service icon takes the slot immediately before the title, so the
        // title gives up exactly one icon width plus one gutter — and gets both
        // back when the setting is off.
        var serviceIconOrigin: CGFloat?
        if showsServiceIcon {
            serviceIconOrigin = titleOrigin
            titleOrigin += metrics.serviceIconWidth + metrics.columnSpacing
        }

        let trailing = metrics.trailingAffordanceWidth
            + metrics.columnSpacing
            + metrics.disclosureWidth
            + metrics.columnSpacing
        let titleWidth = metrics.rowContentWidth - titleOrigin - trailing

        return AgendaRowLayout(
            marker: marker,
            resolvedPosition: resolvedPosition,
            timeColumn: timeColumn,
            leadingInset: leadingInset,
            timeColumnWidth: timeWidth,
            markerFrame: markerFrame,
            serviceIconOrigin: serviceIconOrigin,
            titleOrigin: titleOrigin,
            titleWidth: titleWidth
        )
    }

    private static func markerSize(
        _ marker: AgendaMarker,
        metrics: DropdownMetrics
    ) -> CGSize {
        switch marker {
        case .none:
            CGSize(width: 0, height: 0)
        case .dot:
            CGSize(width: metrics.markerDotDiameter, height: metrics.markerDotDiameter)
        case .leftBorderBar:
            CGSize(width: metrics.markerBarWidth, height: metrics.markerBarHeight)
        }
    }
}
