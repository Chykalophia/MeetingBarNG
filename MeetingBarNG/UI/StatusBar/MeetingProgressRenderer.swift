//
//  MeetingProgressRenderer.swift
//  MeetingBarNG
//
//  Draws menu-bar meeting progress. The WHAT (how full, what phase) is decided by
//  the hostless `MeetingProgressPolicy`; this file only turns that into pixels.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit

/// Colours and dimensions for the menu-bar indicator.
///
/// Phase colours follow the app's one shared vocabulary for urgency, so the
/// menu bar and the dropdown's Join buttons can never disagree about whether a
/// meeting is "close": secondary while it is merely approaching, the accent
/// colour once it is inside the imminence threshold, red while it runs.
enum MeetingProgressStyleMetrics {
    static func color(for phase: MeetingProgressPresentation.Phase) -> NSColor {
        switch phase {
        case .upcoming: .secondaryLabelColor
        case .imminent: .controlAccentColor
        case .running: .systemRed
        }
    }

    /// The unfilled part of the track. Faint enough to read as "space left"
    /// rather than as a second bar — but not so faint it vanishes against a
    /// tinted menu bar, which is where 0.22 was failing.
    static let trackAlpha: CGFloat = 0.35

    static let underlineHeight: CGFloat = 2
    /// Lifts the underline off the very bottom of the item. Drawn flush it sits
    /// on the menu bar's own edge and reads as clipped rather than as a rule.
    static let underlineBottomInset: CGFloat = 2
    static let ringLineWidth: CGFloat = 1.75
    static let capsuleLineWidth: CGFloat = 1
    /// The filled part of the capsule's border, drawn heavier than the track so
    /// the boundary between done and remaining is unmistakable.
    static let capsuleProgressLineWidth: CGFloat = 2
    /// A whisper of interior tint so the capsule reads as a container. Stays low
    /// because this overlay sits ON TOP of the title.
    static let capsuleInteriorAlpha: CGFloat = 0.10
    /// Width of the standalone bar, in the status item's image slot.
    static let barSize = NSSize(width: 22, height: 5)
    /// Inset the ring keeps from the icon box so it never touches the glyph.
    static let ringPadding: CGFloat = 1.5
    /// Diameter of the ring when it has to stand on its own (no icon to
    /// encircle). Matches the menu bar's icon size so it reads as one.
    static let standaloneRingSide: CGFloat = 14
}

/// A transparent overlay on the status-item button that draws the indicator on
/// top of AppKit's own rendering.
///
/// An overlay rather than a redraw of the whole item ON PURPOSE. The status item
/// renders its text as an `NSAttributedString`, and AppKit owns everything that
/// makes that text look native — light/dark adaptation, the inversion while the
/// menu is open, accessibility. Rendering the item ourselves to composite a
/// progress bar underneath would mean reimplementing all of it. Drawing over the
/// top costs nothing and cannot regress the classic path.
///
/// The consequence is that the styles which fill a REGION (underline, capsule)
/// are drawn around the text rather than behind it, and are kept translucent so
/// the text stays first.
final class MeetingProgressOverlayView: NSView {
    var style: MeetingProgressStyle = .none {
        didSet { if style != oldValue { needsDisplay = true } }
    }

    var presentation: MeetingProgressPresentation? {
        didSet { if presentation != oldValue { needsDisplay = true } }
    }

    /// Width of the leading icon, so the ring knows what to encircle. The status
    /// item does not expose the icon's frame, so this is supplied by the caller
    /// from the image it just set.
    var iconWidth: CGFloat = 0

    /// Clicks belong to the status item underneath — an overlay that swallowed
    /// them would make the menu bar item stop opening the panel.
    override func hitTest(_: NSPoint) -> NSView? { nil }

    override var isFlipped: Bool { false }

    override func draw(_: NSRect) {
        guard let presentation, style.drawsSomething, !bounds.isEmpty else { return }
        let color = MeetingProgressStyleMetrics.color(for: presentation.phase)

        switch style {
        case .none, .bar:
            // `.bar` is drawn into the image slot, not here — see
            // `MeetingProgressRenderer.barImage`.
            break
        case .underline:
            drawUnderline(fraction: presentation.fraction, color: color)
        case .ring:
            drawRing(fraction: presentation.fraction, color: color)
        case .capsule:
            drawCapsule(fraction: presentation.fraction, color: color)
        }
    }

    private func drawUnderline(fraction: Double, color: NSColor) {
        let height = MeetingProgressStyleMetrics.underlineHeight
        let baseline = MeetingProgressStyleMetrics.underlineBottomInset
        let track = NSRect(x: 0, y: baseline, width: bounds.width, height: height)
        color.withAlphaComponent(MeetingProgressStyleMetrics.trackAlpha).setFill()
        NSBezierPath(roundedRect: track, xRadius: height / 2, yRadius: height / 2).fill()

        guard fraction > 0 else { return }
        let filled = NSRect(x: 0, y: baseline, width: bounds.width * fraction, height: height)
        color.setFill()
        NSBezierPath(roundedRect: filled, xRadius: height / 2, yRadius: height / 2).fill()
    }

    /// A ring that fills clockwise from 12 o'clock, like a countdown timer.
    private func drawRing(fraction: Double, color: NSColor) {
        let side = min(iconWidth > 0 ? iconWidth : bounds.height, bounds.height)
            - MeetingProgressStyleMetrics.ringPadding
        guard side > 4 else { return }

        let center = NSPoint(x: side / 2 + MeetingProgressStyleMetrics.ringPadding, y: bounds.midY)
        let radius = side / 2

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = MeetingProgressStyleMetrics.ringLineWidth
        color.withAlphaComponent(MeetingProgressStyleMetrics.trackAlpha).setStroke()
        track.stroke()

        guard fraction > 0 else { return }
        // AppKit angles run counter-clockwise from 3 o'clock; a countdown reads
        // clockwise from 12, hence the negative sweep off a 90° start.
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - 360 * fraction,
            clockwise: true
        )
        arc.lineWidth = MeetingProgressStyleMetrics.ringLineWidth
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    /// A capsule whose BORDER fills left to right.
    ///
    /// The progress used to be a translucent wash across the capsule's interior,
    /// and it was caught between two requirements: this overlay draws ON TOP of
    /// the title (see the type's note — AppKit owns the text, so we cannot get
    /// behind it), so a fill heavy enough to see also greyed the meeting name.
    /// At the alpha that kept the text clean it was invisible.
    ///
    /// Filling the border instead removes the conflict entirely. Nothing is
    /// drawn over the text, so the progress can be full strength, and a capsule
    /// that fills round its own edge reads as progress at a glance. The interior
    /// keeps a whisper of tint so the pill still reads as a container.
    private func drawCapsule(fraction: Double, color: NSColor) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        guard rect.width > 4, rect.height > 4 else { return }
        let radius = rect.height / 2
        let outline = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        // Interior hint — low enough that the title is untouched.
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        color.withAlphaComponent(MeetingProgressStyleMetrics.capsuleInteriorAlpha).setFill()
        rect.fill()
        NSGraphicsContext.restoreGraphicsState()

        // The unfilled part of the border.
        outline.lineWidth = MeetingProgressStyleMetrics.capsuleLineWidth
        color.withAlphaComponent(MeetingProgressStyleMetrics.trackAlpha).setStroke()
        outline.stroke()

        guard fraction > 0 else { return }
        // The filled part: the same path at full strength, clipped to how far
        // along we are. Top and bottom edges advance together, which reads as one
        // boundary sweeping right rather than as two separate lines growing.
        NSGraphicsContext.saveGraphicsState()
        NSRect(
            x: rect.minX - MeetingProgressStyleMetrics.capsuleLineWidth,
            y: bounds.minY,
            width: rect.width * fraction + MeetingProgressStyleMetrics.capsuleLineWidth,
            height: bounds.height
        ).clip()
        let progress = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        progress.lineWidth = MeetingProgressStyleMetrics.capsuleProgressLineWidth
        color.setStroke()
        progress.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

enum MeetingProgressRenderer {
    /// The ring drawn as a standalone image, for when the menu bar has no icon
    /// for it to encircle.
    ///
    /// A ring needs something to sit around. With `eventTitleIconFormat` set to
    /// none — or any composition without an `.icon` block — there is no image in
    /// the status item, and an overlay ring lands on the first letter of the
    /// title instead. Taking the image slot costs a little width, which is the
    /// honest price of asking for a ring when nothing else is there to wear it.
    @MainActor
    static func ringImage(for presentation: MeetingProgressPresentation) -> NSImage {
        let side = MeetingProgressStyleMetrics.standaloneRingSide
        let color = MeetingProgressStyleMetrics.color(for: presentation.phase)
        let lineWidth = MeetingProgressStyleMetrics.ringLineWidth

        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = side / 2 - lineWidth / 2

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            color.withAlphaComponent(MeetingProgressStyleMetrics.trackAlpha).setStroke()
            track.stroke()

            guard presentation.fraction > 0 else { return true }
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - 360 * presentation.fraction,
                clockwise: true
            )
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// The standalone mini-bar, drawn as an image for the status item's image
    /// slot. The one style that costs menu-bar width.
    ///
    /// Not a template image: the whole point is the phase colour, and a template
    /// image would be flattened to the menu bar's own tint.
    @MainActor
    static func barImage(for presentation: MeetingProgressPresentation) -> NSImage {
        let size = MeetingProgressStyleMetrics.barSize
        let color = MeetingProgressStyleMetrics.color(for: presentation.phase)
        let image = NSImage(size: size, flipped: false) { rect in
            let radius = rect.height / 2
            color.withAlphaComponent(MeetingProgressStyleMetrics.trackAlpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

            guard presentation.fraction > 0 else { return true }
            let filled = NSRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width * presentation.fraction,
                height: rect.height
            )
            color.setFill()
            NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
