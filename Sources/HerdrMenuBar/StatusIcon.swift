import AppKit

/// The menu bar image: a robot head, with a small urgency dot at its top right.
///
/// SF Symbols has no robot glyph, so the head is drawn by hand. The head is
/// tinted with `labelColor` rather than a status colour, so it reads as a
/// normal menu bar item; only the dot carries state.
enum StatusIcon {
    private static let size = NSSize(width: 20, height: 16)

    /// Builds the icon for the most urgent status present, or no dot at all
    /// when nothing wants attention.
    static func image(for status: AgentStatus, connected: Bool) -> NSImage {
        let dot = dotColor(for: status, connected: connected)

        let image = NSImage(size: size, flipped: false) { _ in
            drawHead(dimmed: !connected)
            if let dot { drawDot(dot) }
            return true
        }
        // Redraw on every paint so `labelColor` re-resolves when the menu bar
        // switches between light and dark.
        image.cacheMode = .never
        image.isTemplate = false
        return image
    }

    private static func dotColor(for status: AgentStatus, connected: Bool) -> NSColor? {
        guard connected else { return nil }
        switch status {
        case .blocked: return .systemOrange
        case .done: return .systemGreen
        case .working: return .controlAccentColor
        case .idle, .unknown: return nil  // nothing urgent, so stay quiet
        }
    }

    // MARK: - Drawing

    private static func drawHead(dimmed: Bool) {
        let body = NSBezierPath()

        // Antenna: a stem with a bulb, centred over the head.
        body.append(NSBezierPath(rect: NSRect(x: 7.6, y: 12.1, width: 0.8, height: 1.6)))
        body.append(NSBezierPath(ovalIn: NSRect(x: 6.7, y: 13.3, width: 2.6, height: 2.6)))

        // Head.
        body.append(NSBezierPath(
            roundedRect: NSRect(x: 1.2, y: 2.4, width: 13.6, height: 10),
            xRadius: 3.2, yRadius: 3.2))

        // Eyes, knocked out of the head by the even-odd rule.
        body.append(NSBezierPath(ovalIn: NSRect(x: 4.5, y: 6.4, width: 2.7, height: 2.7)))
        body.append(NSBezierPath(ovalIn: NSRect(x: 8.8, y: 6.4, width: 2.7, height: 2.7)))

        // Mouth, also knocked out.
        body.append(NSBezierPath(
            roundedRect: NSRect(x: 5.2, y: 4.2, width: 5.6, height: 1.2),
            xRadius: 0.6, yRadius: 0.6))

        body.windingRule = .evenOdd
        (dimmed ? NSColor.tertiaryLabelColor : NSColor.labelColor).setFill()
        body.fill()
    }

    private static func drawDot(_ color: NSColor) {
        let centre = NSPoint(x: 16.4, y: 12.6)
        let radius: CGFloat = 2.6

        // Punch a gap first so the dot reads separately from the head it overlaps.
        let gap = NSBezierPath(ovalIn: NSRect(
            x: centre.x - radius - 0.85, y: centre.y - radius - 0.85,
            width: (radius + 0.85) * 2, height: (radius + 0.85) * 2))
        NSGraphicsContext.current?.compositingOperation = .clear
        gap.fill()

        NSGraphicsContext.current?.compositingOperation = .sourceOver
        color.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: centre.x - radius, y: centre.y - radius,
            width: radius * 2, height: radius * 2)).fill()
    }
}
