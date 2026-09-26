import AppKit

// Geometry is authored in a 16x16 SVG space (origin top-left, y down), hence
// the `viewBox - y` flips into AppKit's y-up space.
enum StatusIcon {
    private static let viewBox: CGFloat = 16
    private static let scale: CGFloat = 1.2
    private static var canvas: NSSize {
        NSSize(width: ceil(viewBox * scale), height: ceil(viewBox * scale))
    }

    private static let head = NSRect(x: 3, y: 3, width: 10, height: 10)
    private static let headRadius: CGFloat = 2.2
    private static let outlineWidth: CGFloat = 1.4
    private static let outlineRadius: CGFloat = 1.7
    private static let eyeCentres = [NSPoint(x: 5.75, y: viewBox - 8.1),
                                     NSPoint(x: 10.25, y: viewBox - 8.1)]
    private static let eyeRadius: CGFloat = 1.2
    private static let stillEars = [
        NSRect(x: 0.7, y: viewBox - 5.3 - 5.4, width: 1.6, height: 5.4),
        NSRect(x: 13.7, y: viewBox - 5.3 - 5.4, width: 1.6, height: 5.4),
    ]
    private static let earRadius: CGFloat = 0.7
    private static let checkPoints = [NSPoint(x: 5.4, y: viewBox - 8.2),
                                      NSPoint(x: 7.2, y: viewBox - 10),
                                      NSPoint(x: 10.7, y: viewBox - 6.3)]
    private static let checkWidth: CGFloat = 1.5

    private static let trackHalf: CGFloat = 6.5
    private static let trackRadius: CGFloat = 3.7
    private static let trackWidth: CGFloat = 1.6
    private static let earDashFraction: CGFloat = 0.083
    private static let lapSeconds: Double = 1.6

    private static let jumpSeconds: Double = 2.0
    private static let jumpKeyframes: [(time: Double, lift: CGFloat)] =
        [(0, 0), (0.08, 2.5), (0.16, 0), (0.24, 1.3), (0.32, 0)]

    static func image(for status: AgentStatus, connected: Bool, phase: Double) -> NSImage {
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

        let lift = status == .blocked && connected ? jumpOffset(seconds) : 0
        applyCanvasTransform(lift: lift)
        NSColor.labelColor.setFill()
        NSColor.labelColor.setStroke()

        if status == .working && connected {
            drawSnakeEars(seconds: seconds)
        } else {
            drawStillEars()
        }

        // Unreachable deliberately looks like idle; the dropdown is what reports it.
        if status.isResting || !connected {
            drawOutlineHead()
        } else if status == .done {
            drawCheckedHead()
        } else {
            drawSolidHead()
        }
    }

    private static func applyCanvasTransform(lift: CGFloat) {
        let transform = NSAffineTransform()
        transform.translateX(by: canvas.width / 2, yBy: canvas.height / 2)
        transform.scale(by: scale)
        transform.translateX(by: -viewBox / 2, yBy: -viewBox / 2 + lift)
        transform.concat()
    }

    private static func drawStillEars() {
        for ear in stillEars {
            NSBezierPath(roundedRect: ear, xRadius: earRadius, yRadius: earRadius).fill()
        }
    }

    private static func drawOutlineHead() {
        let inset = outlineWidth / 2
        let outline = NSBezierPath(roundedRect: head.insetBy(dx: inset, dy: inset),
                                   xRadius: outlineRadius, yRadius: outlineRadius)
        outline.lineWidth = outlineWidth
        outline.stroke()
        for centre in eyeCentres { eyePath(centre).fill() }
    }

    private static func drawCheckedHead() {
        NSBezierPath(roundedRect: head, xRadius: headRadius, yRadius: headRadius).fill()
        NSGraphicsContext.current?.compositingOperation = .clear
        checkPath().stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    private static func drawSolidHead() {
        let path = NSBezierPath(roundedRect: head, xRadius: headRadius, yRadius: headRadius)
        for centre in eyeCentres { path.append(eyePath(centre)) }
        path.windingRule = .evenOdd
        path.fill()
    }

    private static func eyePath(_ centre: NSPoint) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: centre.x - eyeRadius, y: centre.y - eyeRadius,
                                    width: eyeRadius * 2, height: eyeRadius * 2))
    }

    private static func checkPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: checkPoints[0])
        for point in checkPoints.dropFirst() { path.line(to: point) }
        path.lineWidth = checkWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }

    /// Starts at the left edge and runs clockwise on screen, so a dash centred
    /// on the start sits exactly where a still ear does.
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

    private static func drawSnakeEars(seconds: Double) {
        let length = trackLength
        let dash = length * earDashFraction
        let gap = length / 2 - dash
        let travelled = CGFloat((seconds / lapSeconds).truncatingRemainder(dividingBy: 1)) * length

        let path = trackPath()
        path.lineWidth = trackWidth
        path.lineCapStyle = .round
        path.setLineDash([dash, gap], count: 2, phase: dash / 2 - travelled)
        path.stroke()
    }

    private static func jumpOffset(_ seconds: Double) -> CGFloat {
        let t = (seconds / jumpSeconds).truncatingRemainder(dividingBy: 1)
        for (start, end) in zip(jumpKeyframes, jumpKeyframes.dropFirst())
        where t >= start.time && t <= end.time {
            let progress = easeInOut((t - start.time) / (end.time - start.time))
            return start.lift + (end.lift - start.lift) * CGFloat(progress)
        }
        return 0
    }

    private static func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }
}
