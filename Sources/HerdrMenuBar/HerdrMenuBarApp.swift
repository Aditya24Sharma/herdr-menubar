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
            // An Image built from a status-tinted symbol, plus the count of
            // whatever is most urgent. Status items cannot carry a real badge,
            // so the count rides alongside as text.
            Image(nsImage: StatusIcon.image(for: monitor.summaryStatus))
            if monitor.badgeCount > 0 {
                Text("\(monitor.badgeCount)")
            }
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

/// Renders the menu bar symbol in the colour for a status.
///
/// The image is deliberately *not* a template image: macOS tints template
/// images to match the menu bar, which would throw away the colour.
enum StatusIcon {
    static func image(for status: AgentStatus) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            .applying(.init(paletteColors: [nsColor(for: status)]))
        let symbol = NSImage(systemSymbolName: "pawprint.fill",
                             accessibilityDescription: "Herdr agents")
        let image = symbol?.withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = false
        return image
    }

    private static func nsColor(for status: AgentStatus) -> NSColor {
        switch status {
        case .blocked: return .systemOrange
        case .done: return .systemGreen
        case .working: return .controlAccentColor
        case .idle, .unknown: return .secondaryLabelColor
        }
    }
}
