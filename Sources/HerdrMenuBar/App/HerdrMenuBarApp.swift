import SwiftUI

@main
struct HerdrMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var iconAnimator = IconAnimator()
    @StateObject private var settings: Settings
    @StateObject private var notifier: Notifier
    @StateObject private var monitor: HerdrMonitor

    init() {
        let settings = Settings()
        let notifier = Notifier()
        let monitor = HerdrMonitor(settings: settings, notifier: notifier)
        _settings = StateObject(wrappedValue: settings)
        _notifier = StateObject(wrappedValue: notifier)
        _monitor = StateObject(wrappedValue: monitor)

        // MenuBarExtra builds its content only when the panel opens, so launch
        // work goes through the delegate instead.
        AppDelegate.onLaunch = {
            notifier.requestAuthorization()
            monitor.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(monitor)
                .environmentObject(settings)
        } label: {
            Image(nsImage: StatusIcon.image(for: monitor.summaryStatus,
                                            connected: monitor.isConnected,
                                            phase: iconAnimator.phase))
        }
        .onChange(of: monitor.summaryStatus, initial: true) { _, _ in updateIconAnimation() }
        .onChange(of: monitor.isConnected, initial: true) { _, _ in updateIconAnimation() }
        .menuBarExtraStyle(.window)
    }

    private func updateIconAnimation() {
        let status = monitor.summaryStatus
        iconAnimator.running = (status == .working || status == .blocked)
            && monitor.isConnected
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var onLaunch: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated { AppDelegate.onLaunch?() }
    }
}
