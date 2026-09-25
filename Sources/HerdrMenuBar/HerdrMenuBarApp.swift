import SwiftUI

@main
struct HerdrMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var hop = IconAnimator()
    @StateObject private var settings: Settings
    @StateObject private var notifier: Notifier
    @StateObject private var monitor: HerdrMonitor

    init() {
        let settings = Settings()
        let notifier = Notifier()
        _settings = StateObject(wrappedValue: settings)
        _notifier = StateObject(wrappedValue: notifier)
        let monitor = HerdrMonitor(settings: settings, notifier: notifier)
        _monitor = StateObject(wrappedValue: monitor)

        // MenuBarExtra content is only built when the panel opens, so start the
        // connection and ask for notification rights from the delegate instead.
        AppDelegate.onLaunch = {
            notifier.requestAuthorization()
            monitor.start()
        }
    }

    private var shownStatus: AgentStatus { monitor.summaryStatus }
    private var shownConnected: Bool { monitor.isConnected }

    /// The icon moves only while an agent is working or waiting on you, and
    /// never when the system asks for reduced motion.
    private func syncHop() {
        hop.running = (shownStatus == .working || shownStatus == .blocked)
            && shownConnected
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(monitor)
                .environmentObject(settings)
        } label: {
            Image(nsImage: StatusIcon.image(for: shownStatus, connected: shownConnected,
                                            phase: hop.phase))
        }
        .onChange(of: shownStatus, initial: true) { _, _ in syncHop() }
        .onChange(of: shownConnected, initial: true) { _, _ in syncHop() }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var onLaunch: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated { AppDelegate.onLaunch?() }
    }
}

/// Advances a phase so the menu bar icon can animate. Runs only while it is
/// wanted; the timer is torn down in every other state so the icon costs
/// nothing at rest.
@MainActor
final class IconAnimator: ObservableObject {
    @Published private(set) var phase: Double = 0

    /// 20fps keeps a one-second hop smooth without the cost of full frame rate.
    private static let fps: Double = 12
    private var timer: Timer?

    var running = false {
        didSet {
            guard running != (timer != nil) else { return }
            running ? start() : stop()
        }
    }

    private func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1 / Self.fps, repeats: true) { _ in
            Task { @MainActor in
                self.phase += 1 / Self.fps
                if self.phase > 1_000 { self.phase -= 1_000 }
            }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        phase = 0
    }
}
