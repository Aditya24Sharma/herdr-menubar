import SwiftUI

struct StatusIndicator: View {
    let status: AgentStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let secondsPerTurn: TimeInterval = 0.9

    var body: some View {
        Group {
            if status == .working && !reduceMotion {
                spinner
            } else {
                dot
            }
        }
        .frame(width: 10, height: 10)
    }

    // Driven by TimelineView, not `withAnimation`: a repeating animation
    // transaction leaks into the panel and animates every list update.
    private var spinner: some View {
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.secondsPerTurn) / Self.secondsPerTurn
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(status.color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .frame(width: 9, height: 9)
                .rotationEffect(.degrees(turn * 360))
        }
    }

    private var dot: some View {
        let size: CGFloat = status == .blocked ? 9 : 7
        return Circle()
            .fill(status.color)
            .frame(width: size, height: size)
    }
}
