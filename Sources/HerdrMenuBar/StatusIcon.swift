import AppKit

/// The menu bar icon: a monochrome robot drawn entirely in `labelColor`, so it
/// follows a light or dark menu bar and sits quietly among the system icons.
///
/// State is carried by shape and motion rather than colour:
///
/// - idle, and Herdr unreachable — outline head, eyes painted, still
/// - working — filled head, eyes cut out, ears circling the face
/// - needs you — filled head, eyes cut out, the whole icon hopping
/// - done — filled head with a check punched through it
///
/// Working and "needs you" share the same still image; only motion separates
/// them, so they are indistinguishable while Reduce Motion is on.
///
/// Geometry is authored in a 16x16 SVG space (origin top-left, y down) and
/// flipped for AppKit. `scale` is the only size knob.
enum StatusIcon {
    static let scale: CGFloat = 1.2
    static var canvas: NSSize {
        NSSize(width: ceil(16 * scale), height: ceil(16 * scale))
    }

    private static let head = NSRect(x: 3, y: 3, width: 10, height: 10)
    private static let headRadius: CGFloat = 2.2
    private static let eyeCentres = [NSPoint(x: 5.75, y: 16 - 8.1),
                                     NSPoint(x: 10.25, y: 16 - 8.1)]
    private static let eyeRadius: CGFloat = 1.2
    private static let stillEars = [
        NSRect(x: 0.7, y: 16 - 5.3 - 5.4, width: 1.6, height: 5.4),
        NSRect(x: 13.7, y: 16 - 5.3 - 5.4, width: 1.6, height: 5.4),
    ]
    private static let earRadius: CGFloat = 0.7

    // Track the snake dashes ride: through the still ears' centre line.
    private static let trackHalf: CGFloat = 6.5
    private static let trackRadius: CGFloat = 3.7
    private static let trackWidth: CGFloat = 1.6
    private static let lapSeconds: Double = 1.6
    private static let jumpSeconds: Double = 2.0

    /// `phase` is elapsed seconds; each animation derives its own cycle from it.
    static func image(for status: AgentStatus, connected: Bool,
                      phase: Double = 0) -> NSImage {
        let image = NSImage(size: canvas, flipped: false) { _ in
            draw(status: status, connected: connected, seconds: phase)
            return true
        }
        // Redraw on every paint so `labelColor` re-resolves when the menu bar
        // switches between light and dark.
        image.cacheMode = .never
        image.isTemplate = false
        return image
    }

    private static func draw(status: AgentStatus, connected: Bool, seconds: Double) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let t = NSAffineTransform()
        t.translateX(by: canvas.width / 2, yBy: canvas.height / 2)
        t.scale(by: scale)
        // The jump lifts the whole icon, so it belongs in this transform.
        let lift = status == .blocked && connected ? jumpOffset(seconds) : 0
        t.translateX(by: -8, yBy: -8 + lift)
        t.concat()

        NSColor.labelColor.setFill()
        NSColor.labelColor.setStroke()

        // Unreachable looks exactly like idle. The dropdown says when Herdr is
        // out of reach; the icon does not need a fifth pose to say it too.
        let resting = status.isResting || !connected

        if status == .working && connected {
            drawSnakeEars(seconds: seconds)
        } else {
            for ear in stillEars {
                NSBezierPath(roundedRect: ear, xRadius: earRadius, yRadius: earRadius).fill()
            }
        }

        if resting {
            let outline = NSBezierPath(roundedRect: head.insetBy(dx: 0.7, dy: 0.7),
                                       xRadius: 1.7, yRadius: 1.7)
            outline.lineWidth = 1.4
            outline.stroke()
            for centre in eyeCentres { eyePath(centre).fill() }
            return
        }

        if status == .done {
            // A filled head with the check punched straight out of it.
            NSBezierPath(roundedRect: head, xRadius: headRadius, yRadius: headRadius).fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            checkPath().stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return
        }

        // Working and blocked: filled head with the eyes cut out.
        let body = NSBezierPath(roundedRect: head, xRadius: headRadius, yRadius: headRadius)
        for centre in eyeCentres { body.append(eyePath(centre)) }
        body.windingRule = .evenOdd
        body.fill()
    }

    private static func eyePath(_ centre: NSPoint) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: centre.x - eyeRadius, y: centre.y - eyeRadius,
                                    width: eyeRadius * 2, height: eyeRadius * 2))
    }

    private static func checkPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 5.4, y: 16 - 8.2))
        path.line(to: NSPoint(x: 7.2, y: 16 - 10))
        path.line(to: NSPoint(x: 10.7, y: 16 - 6.3))
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }

    /// The track, starting at the left edge and running clockwise on screen, so
    /// a dash centred at the start sits exactly where a still ear does.
    private static func trackPath() -> NSBezierPath {
        let cx = head.midX, cy = head.midY
        let straight = trackHalf - trackRadius
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cx - trackHalf, y: cy))
        path.appendArc(withCenter: NSPoint(x: cx - straight, y: cy + straight),
                       radius: trackRadius, startAngle: 180, endAngle: 90, clockwise: true)
        path.appendArc(withCenter: NSPoint(x: cx + straight, y: cy + straight),
                       radius: trackRadius, startAngle: 90, endAngle: 0, clockwise: true)
        path.appendArc(withCenter: NSPoint(x: cx + straight, y: cy - straight),
                       radius: trackRadius, startAngle: 0, endAngle: -90, clockwise: true)
        path.appendArc(withCenter: NSPoint(x: cx - straight, y: cy - straight),
                       radius: trackRadius, startAngle: -90, endAngle: -180, clockwise: true)
        path.close()
        return path
    }

    private static var trackLength: CGFloat {
        let straights = 4 * (trackHalf - trackRadius) * 2
        return straights + 2 * .pi * trackRadius
    }

    /// Two dashes half a lap apart, travelling one lap every 1.6s. Dash length
    /// is 8.3% of the track, which with round caps comes out as the still ear.
    private static func drawSnakeEars(seconds: Double) {
        let length = trackLength
        let dash = length * 0.083
        let gap = length / 2 - dash
        let travelled = CGFloat((seconds / lapSeconds).truncatingRemainder(dividingBy: 1)) * length

        let path = trackPath()
        path.lineWidth = trackWidth
        path.lineCapStyle = .round
        // Half a dash centres the first one on the start point; subtracting the
        // travel sends them forward along the path.
        path.setLineDash([dash, gap], count: 2, phase: dash / 2 - travelled)
        path.stroke()
    }

    /// Big hop, small hop, then a pause — a 2s cycle, eased between keyframes.
    private static func jumpOffset(_ seconds: Double) -> CGFloat {
        let t = (seconds / jumpSeconds).truncatingRemainder(dividingBy: 1)
        let keys: [(Double, CGFloat)] = [(0, 0), (0.08, 2.5), (0.16, 0), (0.24, 1.3), (0.32, 0)]
        guard t < 0.32 else { return 0 }
        for i in 0..<(keys.count - 1) {
            let (t0, v0) = keys[i], (t1, v1) = keys[i + 1]
            guard t >= t0, t <= t1 else { continue }
            let local = (t - t0) / (t1 - t0)
            let eased = local < 0.5 ? 2 * local * local : 1 - pow(-2 * local + 2, 2) / 2
            return v0 + (v1 - v0) * CGFloat(eased)
        }
        return 0
    }
}
