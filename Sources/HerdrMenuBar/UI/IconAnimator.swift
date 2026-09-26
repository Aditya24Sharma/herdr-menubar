import Foundation

@MainActor
final class IconAnimator: ObservableObject {
    @Published private(set) var phase: Double = 0

    private static let framesPerSecond: Double = 12
    private static let phaseWrap: Double = 1_000
    private var timer: Timer?

    var running = false {
        didSet {
            guard running != (timer != nil) else { return }
            running ? start() : stop()
        }
    }

    private func start() {
        let frame = 1 / Self.framesPerSecond
        timer = Timer.scheduledTimer(withTimeInterval: frame, repeats: true) { _ in
            Task { @MainActor in self.advance(by: frame) }
        }
    }

    private func advance(by seconds: Double) {
        phase += seconds
        if phase > Self.phaseWrap { phase -= Self.phaseWrap }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        phase = 0
    }
}
