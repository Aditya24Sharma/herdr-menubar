import AppKit

/// The menu bar image: a robot head, with a small state dot at its top right.
///
/// SF Symbols has no robot glyph, so the head is drawn by hand. The head is
/// tinted with `labelColor` rather than a status colour, so it reads as a
/// normal menu bar item; only the dot carries state.
///
/// The dot encodes state twice over, in shape as well as colour, so the states
/// stay distinguishable without relying on colour vision:
///
/// - filled dot — an agent is working, finished, or waiting on you
/// - hollow ring — connected, everything idle
/// - no dot, dimmed head — Herdr is unreachable
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

    /// How the dot should look for a given state.
    private struct Indicator {
        let color: NSColor
        let radius: CGFloat
        let filled: Bool

        /// Outermost drawn radius, including a ring's stroke.
        var outerRadius: CGFloat { filled ? radius : radius + strokeWidth / 2 }
        var strokeWidth: CGFloat { 1.0 }
    }

    static func image(for status: AgentStatus, connected: Bool) -> NSImage {
        let indicator = indicator(for: status, connected: connected)

        let image = NSImage(size: size, flipped: false) { _ in
            drawHead(dimmed: !connected)
            if let indicator { draw(indicator) }
            return true
        }
        // Redraw on every paint so `labelColor` re-resolves when the menu bar
        // switches between light and dark.
        image.cacheMode = .never
        image.isTemplate = false
        return image
    }

    private static func indicator(for status: AgentStatus, connected: Bool) -> Indicator? {
        // Unreachable reads as a dimmed head with no dot, so a quiet session and
        // a dead app never look alike.
        guard connected else { return nil }

        switch status {
        case .blocked:
            // Slightly larger, because this is the only state that wants action.
            return Indicator(color: .systemRed, radius: 2.95, filled: true)
        case .done:
            return Indicator(color: .systemGreen, radius: 2.6, filled: true)
        case .working:
            return Indicator(color: .controlAccentColor, radius: 2.6, filled: true)
        case .idle, .unknown:
            // Quietest state, so the ring is small and faint — it should never
            // pull the eye harder than an agent that is actually doing something.
            return Indicator(color: .tertiaryLabelColor, radius: 2.0, filled: false)
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

    private static func draw(_ indicator: Indicator) {
        // Punch a small gap so the dot reads as separate from the head beneath it.
        let gap = indicator.outerRadius + 0.5
        NSGraphicsContext.current?.compositingOperation = .clear
        circle(radius: gap).fill()

        NSGraphicsContext.current?.compositingOperation = .sourceOver
        let path = circle(radius: indicator.radius)
        if indicator.filled {
            indicator.color.setFill()
            path.fill()
        } else {
            indicator.color.setStroke()
            path.lineWidth = indicator.strokeWidth
            path.stroke()
        }
    }

    private static func circle(radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(
            x: dotCentre.x - radius, y: dotCentre.y - radius,
            width: radius * 2, height: radius * 2))
    }
}
