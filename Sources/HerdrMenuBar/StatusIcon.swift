import AppKit

/// The menu bar image: a robot head, with a small state dot at its top right.
///
/// SF Symbols has no robot glyph, so the head is drawn by hand. The head is
/// tinted with `labelColor` rather than a status colour, so it reads as a
/// normal menu bar item; only the dot carries state.
///
/// Drawing is kept coarse on purpose. At a drawn height of 16pt anything
/// thinner than roughly 1.5pt does not survive rasterisation, so the head has
/// no mouth and the antenna stem is deliberately chunky.
enum StatusIcon {
    private static let size = NSSize(width: 17, height: 16)

    /// Head geometry. The rounded corners matter: they curve away from the top
    /// right, which lets the dot sit in that corner while barely overlapping
    /// anything actually drawn.
    private static let head = NSRect(x: 1.0, y: 2.2, width: 12.0, height: 9.4)
    private static let headCorner: CGFloat = 3.0
    private static let dotCentre = NSPoint(x: 13.9, y: 12.6)

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

        // Antenna: a stem wide enough to survive rasterisation, plus a bulb,
        // with clearance kept above the bulb so it cannot clip.
        body.append(NSBezierPath(rect: NSRect(x: 6.3, y: 11.4, width: 1.4, height: 1.6)))
        body.append(NSBezierPath(ovalIn: NSRect(x: 5.75, y: 12.75, width: 2.5, height: 2.5)))

        body.append(NSBezierPath(
            roundedRect: head, xRadius: headCorner, yRadius: headCorner))

        // Eyes, knocked out of the head by the even-odd rule.
        body.append(NSBezierPath(ovalIn: NSRect(x: 3.55, y: 6.05, width: 2.7, height: 2.7)))
        body.append(NSBezierPath(ovalIn: NSRect(x: 7.75, y: 6.05, width: 2.7, height: 2.7)))

        body.windingRule = .evenOdd
        (dimmed ? NSColor.tertiaryLabelColor : NSColor.labelColor).setFill()
        body.fill()
    }

    private static func drawDot(_ color: NSColor) {
        // Punch a small gap so the dot reads as separate from the head beneath it.
        NSGraphicsContext.current?.compositingOperation = .clear
        circle(radius: 2.6 + 0.5).fill()

        NSGraphicsContext.current?.compositingOperation = .sourceOver
        color.setFill()
        circle(radius: 2.6).fill()
    }

    private static func circle(radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(
            x: dotCentre.x - radius, y: dotCentre.y - radius,
            width: radius * 2, height: radius * 2))
    }
}
