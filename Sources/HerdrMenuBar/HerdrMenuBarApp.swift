import SwiftUI

@main
struct HerdrMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
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

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(monitor)
                .environmentObject(settings)
        } label: {
            Image(nsImage: StatusIcon.image(for: monitor.summaryStatus,
                                            connected: monitor.isConnected))
        }
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
